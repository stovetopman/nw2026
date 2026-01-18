//
//  PointRenderView.swift
//  ARExplorer
//
//  Production RealityKit 4.0 point cloud renderer using LowLevelMesh.
//  Optimized vertex layout with .point topology and .uchar4Normalized colors.
//

import SwiftUI
import RealityKit
import Metal
import simd

// MARK: - Packed Vertex Structure (16 bytes, Metal-aligned)

/// GPU-optimized vertex layout: position (12 bytes) + color (4 bytes packed RGBA)
struct PackedVertex {
    var x: Float
    var y: Float  
    var z: Float
    var color: UInt32  // RGBA packed as uchar4
    
    init(position: SIMD3<Float>, color: SIMD3<UInt8>) {
        self.x = position.x
        self.y = position.y
        self.z = position.z
        // Pack RGBA into UInt32 (little-endian: ABGR in memory = RGBA when read as uchar4)
        self.color = UInt32(color.x) | (UInt32(color.y) << 8) | (UInt32(color.z) << 16) | (255 << 24)
    }
}

// MARK: - Point Render View

/// Renders point cloud using RealityKit LowLevelMesh with .point topology.
struct PointRenderView: View {
    
    @ObservedObject var pointManager: PointManager
    var onReset: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            // RealityKit point cloud view
            PointCloudRealityView(pointManager: pointManager)
                .ignoresSafeArea()
            
            // Minimal footer
            VStack {
                Spacer()
                footerBar
            }
        }
    }
    
    // MARK: - Footer Bar
    
    private var footerBar: some View {
        HStack {
            if let onBack = onBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .padding(.trailing, 12)
            }
            
            Text("\(formatCount(pointManager.uniqueCount)) pts")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            if let onReset = onReset {
                Button(action: onReset) {
                    Text("Reset")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - RealityKit Point Cloud View

struct PointCloudRealityView: UIViewRepresentable {
    
    @ObservedObject var pointManager: PointManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.black)
        
        // Create anchor for point cloud
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "PointCloudAnchor"
        arView.scene.addAnchor(anchor)
        
        // Create point cloud entity
        let pointEntity = Entity()
        pointEntity.name = "PointCloud"
        anchor.addChild(pointEntity)
        
        // Setup camera
        setupCamera(in: arView)
        
        // Enable gestures
        context.coordinator.setupGestures(for: arView)
        context.coordinator.pointEntity = pointEntity
        context.coordinator.arView = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Rebuild mesh when points change
        context.coordinator.updatePointCloud(points: pointManager.points)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func setupCamera(in arView: ARView) {
        let cameraEntity = PerspectiveCamera()
        cameraEntity.camera.fieldOfViewInDegrees = 60
        cameraEntity.position = [0, 0, 3]
        cameraEntity.look(at: .zero, from: cameraEntity.position, relativeTo: nil)
        
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.name = "CameraAnchor"
        cameraAnchor.addChild(cameraEntity)
        arView.scene.addAnchor(cameraAnchor)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject {
        weak var pointEntity: Entity?
        weak var arView: ARView?
        
        private var cameraDistance: Float = 3.0
        private var cameraAzimuth: Float = 0.0
        private var cameraElevation: Float = 0.3
        private var lastPanLocation: CGPoint?
        
        private var lastPointCount = 0
        private var cachedMesh: MeshResource?
        
        // Throttle mesh rebuilds to 1Hz to reduce GPU memory pressure
        private var lastMeshBuildTime: Date = .distantPast
        private let meshRebuildInterval: TimeInterval = 1.0
        
        // Cached material to avoid expensive shader recompilation
        private var cachedMaterial: RealityKit.Material?
        
        func setupGestures(for view: ARView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
        }
        
        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            if gesture.state == .changed, let last = lastPanLocation {
                let dx = Float(location.x - last.x) * 0.01
                let dy = Float(location.y - last.y) * 0.01
                cameraAzimuth -= dx
                cameraElevation = max(-1.5, min(1.5, cameraElevation + dy))
                updateCameraPosition()
            }
            
            lastPanLocation = gesture.state == .ended ? nil : location
        }
        
        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .changed {
                cameraDistance = max(0.5, min(20, cameraDistance / Float(gesture.scale)))
                gesture.scale = 1.0
                updateCameraPosition()
            }
        }
        
        private func updateCameraPosition() {
            guard let arView = arView,
                  let cameraAnchor = arView.scene.findEntity(named: "CameraAnchor"),
                  let camera = cameraAnchor.children.first else { return }
            
            let x = cameraDistance * cos(cameraElevation) * sin(cameraAzimuth)
            let y = cameraDistance * sin(cameraElevation)
            let z = cameraDistance * cos(cameraElevation) * cos(cameraAzimuth)
            
            camera.position = [x, y, z]
            camera.look(at: .zero, from: camera.position, relativeTo: nil)
        }
        
        func updatePointCloud(points: [ColoredPoint]) {
            guard let entity = pointEntity else { return }
            
            // Skip if unchanged
            guard points.count != lastPointCount else { return }
            
            // Throttle mesh rebuilds to 1Hz to reduce memory pressure
            let now = Date()
            guard now.timeIntervalSince(lastMeshBuildTime) >= meshRebuildInterval else { return }
            lastMeshBuildTime = now
            lastPointCount = points.count
            
            guard !points.isEmpty else {
                entity.components.remove(ModelComponent.self)
                return
            }
            
            // Build mesh on main actor (LowLevelMesh requires it)
            Task { @MainActor in
                if let mesh = buildLowLevelMesh(from: points) {
                    // Use cached material or create once
                    if cachedMaterial == nil {
                        cachedMaterial = (try? await createVertexColorMaterial()) ?? UnlitMaterial()
                    }
                    entity.components.set(ModelComponent(mesh: mesh, materials: [cachedMaterial!]))
                }
            }
        }
        
        /// Create a CustomMaterial that reads vertex colors
        @MainActor
        private func createVertexColorMaterial() async throws -> CustomMaterial {
            let surfaceShader = CustomMaterial.SurfaceShader(
                named: "vertexColorSurface",
                in: MetalLibLoader.library
            )
            var material = try CustomMaterial(surfaceShader: surfaceShader, lightingModel: .unlit)
            material.faceCulling = CustomMaterial.FaceCulling.none
            return material
        }
        
        /// Build LowLevelMesh with .point topology and packed RGBA colors
        @MainActor
        private func buildLowLevelMesh(from points: [ColoredPoint]) -> MeshResource? {
            guard #available(iOS 18.0, *) else { return nil }
            
            let vertexCount = points.count
            guard vertexCount > 0 else { return nil }
            
            do {
                // Vertex attributes: position (float3) + color (uchar4Normalized)
                let attributes: [LowLevelMesh.Attribute] = [
                    LowLevelMesh.Attribute(
                        semantic: .position,
                        format: .float3,
                        offset: 0
                    ),
                    LowLevelMesh.Attribute(
                        semantic: .color,
                        format: .uchar4Normalized,
                        offset: MemoryLayout<Float>.stride * 3  // After xyz
                    )
                ]
                
                let layout = LowLevelMesh.Layout(
                    bufferIndex: 0,
                    bufferStride: MemoryLayout<PackedVertex>.stride  // 16 bytes
                )
                
                var descriptor = LowLevelMesh.Descriptor()
                descriptor.vertexAttributes = attributes
                descriptor.vertexLayouts = [layout]
                descriptor.vertexCapacity = vertexCount
                descriptor.indexCapacity = vertexCount  // Point topology needs indices
                descriptor.indexType = .uint32
                
                let mesh = try LowLevelMesh(descriptor: descriptor)
                
                // Fill vertex buffer with zero-copy write
                mesh.withUnsafeMutableBytes(bufferIndex: 0) { buffer in
                    let vertices = buffer.bindMemory(to: PackedVertex.self)
                    for i in 0..<vertexCount {
                        vertices[i] = PackedVertex(
                            position: points[i].position,
                            color: points[i].color
                        )
                    }
                }
                
                // Fill index buffer (sequential indices for point topology)
                mesh.withUnsafeMutableIndices { buffer in
                    let indices = buffer.bindMemory(to: UInt32.self)
                    for i in 0..<vertexCount {
                        indices[i] = UInt32(i)
                    }
                }
                
                // Compute bounds
                var minP = points[0].position
                var maxP = points[0].position
                for point in points {
                    minP = min(minP, point.position)
                    maxP = max(maxP, point.position)
                }
                
                // Create part with .point topology
                let part = LowLevelMesh.Part(
                    indexCount: vertexCount,
                    topology: .point,
                    bounds: BoundingBox(min: minP, max: maxP)
                )
                mesh.parts.replaceAll([part])
                
                return try MeshResource(from: mesh)
                
            } catch {
                print("❌ LowLevelMesh error: \(error)")
                return nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let manager = PointManager()
    
    for i in 0..<5000 {
        let theta = Float(i) * 0.05
        let r = Float(i) * 0.0005
        let point = ColoredPoint(
            position: SIMD3<Float>(r * cos(theta), Float(i) * 0.0002 - 0.5, r * sin(theta)),
            color: SIMD3<UInt8>(
                UInt8(128 + Int(127 * cos(theta))),
                UInt8(128 + Int(127 * sin(theta))),
                UInt8(i % 256)
            )
        )
        manager.addPoint(point)
    }
    
    return PointRenderView(
        pointManager: manager,
        onReset: { manager.clear() }
    )
}
