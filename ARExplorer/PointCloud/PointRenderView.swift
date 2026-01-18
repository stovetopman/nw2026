//
//  PointRenderView.swift
//  ARExplorer
//
//  SceneKit point cloud renderer with orbit/zoom gestures.
//  Uses SCNGeometryPrimitiveType.point for efficient point rendering.
//

import SwiftUI
import SceneKit
import simd

// MARK: - Point Render View

/// Renders point cloud using SceneKit with full RGB colors.
struct PointRenderView: View {
    
    @ObservedObject var pointManager: PointManager
    var onReset: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            // Full-screen point cloud view
            PointCloudSceneView(pointManager: pointManager)
                .ignoresSafeArea()
            
            // Minimal footer at bottom
            VStack {
                Spacer()
                footerBar
            }
        }
    }
    
    // MARK: - Footer Bar
    
    private var footerBar: some View {
        HStack {
            // Back button (if provided)
            if let onBack = onBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .padding(.trailing, 12)
            }
            
            // Point count
            Text("\(formatCount(pointManager.uniqueCount)) pts")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            // Reset button
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

// MARK: - SceneKit View

struct PointCloudSceneView: UIViewRepresentable {
    
    @ObservedObject var pointManager: PointManager
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true  // Built-in orbit, pan, zoom
        scnView.autoenablesDefaultLighting = false
        
        // Create scene
        let scene = SCNScene()
        scnView.scene = scene
        
        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 100
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)
        
        // Add point cloud node
        let pointCloudNode = SCNNode()
        pointCloudNode.name = "PointCloud"
        scene.rootNode.addChildNode(pointCloudNode)
        
        // Initial update
        updatePointCloud(node: pointCloudNode, points: pointManager.points)
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let scene = uiView.scene,
              let pointCloudNode = scene.rootNode.childNode(withName: "PointCloud", recursively: false) else {
            return
        }
        
        updatePointCloud(node: pointCloudNode, points: pointManager.points)
    }
    
    private func updatePointCloud(node: SCNNode, points: [ColoredPoint]) {
        // Remove existing geometry
        node.geometry = nil
        
        guard !points.isEmpty else { return }
        
        // Create geometry from points
        node.geometry = createPointGeometry(from: points)
    }
    
    private func createPointGeometry(from points: [ColoredPoint]) -> SCNGeometry {
        // Vertex positions
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(points.count)
        
        // Vertex colors
        var colors: [SCNVector3] = []
        colors.reserveCapacity(points.count)
        
        // Center calculation for better viewing
        var center = SIMD3<Float>.zero
        
        for point in points {
            vertices.append(SCNVector3(point.position.x, point.position.y, point.position.z))
            colors.append(SCNVector3(
                Float(point.color.x) / 255.0,
                Float(point.color.y) / 255.0,
                Float(point.color.z) / 255.0
            ))
            center += point.position
        }
        
        if !points.isEmpty {
            center /= Float(points.count)
        }
        
        // Create geometry sources
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let colorSource = SCNGeometrySource(
            data: Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector3>.stride),
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )
        
        // Create point element (no indices needed for points)
        let indices = Array(0..<Int32(points.count))
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        
        // Set point size - balance between detail and coverage
        element.pointSize = 3.0
        element.minimumPointScreenSpaceRadius = 2.0
        element.maximumPointScreenSpaceRadius = 6.0
        
        // Create geometry
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        // Use unlit material to show vertex colors directly
        let material = SCNMaterial()
        material.lightingModel = .constant  // Unlit - shows vertex colors as-is
        material.isDoubleSided = true
        geometry.materials = [material]
        
        return geometry
    }
}

// MARK: - Preview

#Preview {
    let manager = PointManager()
    
    // Add test points with colors
    for i in 0..<1000 {
        let theta = Float(i) * 0.1
        let r = Float(i) * 0.002
        let point = ColoredPoint(
            position: SIMD3<Float>(r * cos(theta), Float(i) * 0.001 - 0.5, r * sin(theta)),
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
