//
//  PointRenderView.swift
//  ARExplorer
//
//  RealityKit point cloud renderer using LowLevelMesh with .point topology.
//

import SwiftUI
import RealityKit
import Metal
import simd

// MARK: - Point Render View

/// Renders point cloud using RealityKit LowLevelMesh.
struct PointRenderView: View {
    
    @ObservedObject var pointManager: PointManager
    
    // Camera state
    @State private var cameraDistance: Float = 3.0
    @State private var cameraAzimuth: Float = 0.0      // Horizontal rotation
    @State private var cameraElevation: Float = 0.3   // Vertical rotation
    @State private var cameraTarget: SIMD3<Float> = .zero
    
    // Gesture state
    @State private var lastDragLocation: CGPoint?
    @State private var lastPanLocation: CGPoint?
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // RealityKit view
                PointCloudRealityView(
                    pointManager: pointManager,
                    cameraDistance: cameraDistance,
                    cameraAzimuth: cameraAzimuth,
                    cameraElevation: cameraElevation,
                    cameraTarget: cameraTarget
                )
                .gesture(orbitGesture)
                .gesture(zoomGesture)
                .gesture(panGesture)
                
                // Point count overlay
                VStack {
                    HStack {
                        Text("\(pointManager.uniqueCount) points")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.black.opacity(0.6))
                            .cornerRadius(6)
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
            }
        }
    }
    
    // MARK: - Gestures
    
    /// 1-finger drag: Orbit rotation
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if let last = lastDragLocation {
                    let dx = Float(value.location.x - last.x)
                    let dy = Float(value.location.y - last.y)
                    
                    cameraAzimuth -= dx * 0.01
                    cameraElevation += dy * 0.01
                    cameraElevation = max(-Float.pi/2 + 0.1, min(Float.pi/2 - 0.1, cameraElevation))
                }
                lastDragLocation = value.location
            }
            .onEnded { _ in
                lastDragLocation = nil
            }
    }
    
    /// Pinch: Zoom
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let scale = Float(value / lastScale)
                cameraDistance /= scale
                cameraDistance = max(0.5, min(50, cameraDistance))
                lastScale = value
            }
            .onEnded { _ in
                lastScale = 1.0
            }
    }
    
    /// 2-finger drag: Pan
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .simultaneously(with: DragGesture(minimumDistance: 1))
            .onChanged { value in
                guard let first = value.first?.location,
                      let second = value.second?.location else { return }
                
                let center = CGPoint(
                    x: (first.x + second.x) / 2,
                    y: (first.y + second.y) / 2
                )
                
                if let last = lastPanLocation {
                    let dx = Float(center.x - last.x) * 0.005 * cameraDistance
                    let dy = Float(center.y - last.y) * 0.005 * cameraDistance
                    
                    // Pan in view-aligned directions
                    let right = SIMD3<Float>(cos(cameraAzimuth), 0, -sin(cameraAzimuth))
                    let up = SIMD3<Float>(0, 1, 0)
                    
                    cameraTarget -= right * dx
                    cameraTarget += up * dy
                }
                lastPanLocation = center
            }
            .onEnded { _ in
                lastPanLocation = nil
            }
    }
}

// MARK: - RealityKit View

struct PointCloudRealityView: View {
    
    @ObservedObject var pointManager: PointManager
    
    let cameraDistance: Float
    let cameraAzimuth: Float
    let cameraElevation: Float
    let cameraTarget: SIMD3<Float>
    
    var body: some View {
        RealityView { content in
            // Create camera
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 60
            content.add(camera)
            
            // Create point cloud entity
            let pointEntity = Entity()
            pointEntity.name = "PointCloud"
            content.add(pointEntity)
            
        } update: { content in
            // Update camera position
            if let camera = content.entities.first(where: { $0 is PerspectiveCamera }) as? PerspectiveCamera {
                let x = cameraDistance * cos(cameraElevation) * sin(cameraAzimuth)
                let y = cameraDistance * sin(cameraElevation)
                let z = cameraDistance * cos(cameraElevation) * cos(cameraAzimuth)
                
                let cameraPos = cameraTarget + SIMD3<Float>(x, y, z)
                camera.position = cameraPos
                camera.look(at: cameraTarget, from: cameraPos, relativeTo: nil)
            }
            
            // Update point cloud mesh
            if let pointEntity = content.entities.first(where: { $0.name == "PointCloud" }) {
                updatePointCloudMesh(entity: pointEntity)
            }
        }
        .background(Color.black)
    }
    
    private func updatePointCloudMesh(entity: Entity) {
        let points = pointManager.points
        guard !points.isEmpty else { return }
        
        do {
            let mesh = try createPointMesh(from: points)
            
            // Create simple unlit material
            var material = UnlitMaterial()
            material.color = .init(tint: .white)
            
            let modelComponent = ModelComponent(mesh: mesh, materials: [material])
            entity.components.set(modelComponent)
            
        } catch {
            print("Failed to create point mesh: \(error)")
        }
    }
    
    private func createPointMesh(from points: [ColoredPoint]) throws -> MeshResource {
        // Create mesh descriptor with positions and colors
        var descriptor = MeshDescriptor(name: "PointCloud")
        
        // Positions
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(points.count)
        for point in points {
            positions.append(point.position)
        }
        descriptor.positions = MeshBuffer(positions)
        
        // Point primitives (each vertex is a point)
        var indices: [UInt32] = []
        indices.reserveCapacity(points.count)
        for i in 0..<points.count {
            indices.append(UInt32(i))
        }
        descriptor.primitives = .points(indices)
        
        return try MeshResource.generate(from: [descriptor])
    }
}

// MARK: - Preview

#Preview {
    let manager = PointManager()
    
    // Add some test points
    for i in 0..<1000 {
        let theta = Float(i) * 0.1
        let r = Float(i) * 0.001
        let point = ColoredPoint(
            position: SIMD3<Float>(r * cos(theta), Float(i) * 0.001, r * sin(theta)),
            color: SIMD3<UInt8>(UInt8(i % 256), UInt8((i * 2) % 256), UInt8((i * 3) % 256))
        )
        manager.addPoint(point)
    }
    
    return PointRenderView(pointManager: manager)
}
