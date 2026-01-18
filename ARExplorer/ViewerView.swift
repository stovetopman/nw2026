import SwiftUI
import SceneKit
import UIKit
import simd

struct ViewerView: View {
    let plyURL: URL
    @ObservedObject var viewerCoordinator: NoteViewerCoordinator
    @State private var isLoading = true
    @State private var loadingProgress: String = "Reading file..."

    var body: some View {
        ZStack {
            ViewerPointCloudContainer(plyURL: plyURL, isLoading: $isLoading, loadingProgress: $loadingProgress, viewerCoordinator: viewerCoordinator)
                .ignoresSafeArea()
            
            if isLoading {
                loadingOverlay
            }
        }
    }
    
    private var loadingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text(loadingProgress)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            
            Text("PREPARING MEMORY")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct ViewerPointCloudContainer: UIViewRepresentable {
    let plyURL: URL
    @Binding var isLoading: Bool
    @Binding var loadingProgress: String
    var viewerCoordinator: NoteViewerCoordinator

    final class Coordinator {
        weak var scnView: SCNView?
        var pointNode: SCNNode?
        var cameraNode: SCNNode?
        var pointCloudCenter: SIMD3<Float> = .zero
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        context.coordinator.scnView = scnView
        
        // Publish to coordinator for note overlay access
        DispatchQueue.main.async {
            self.viewerCoordinator.scnView = scnView
        }
        
        let scene = SCNScene()
        scnView.scene = scene
        scnView.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        scnView.autoenablesDefaultLighting = false
        
        // Enable user interaction for camera control
        scnView.allowsCameraControl = true
        scnView.defaultCameraController.interactionMode = .orbitTurntable
        scnView.defaultCameraController.inertiaEnabled = true
        
        // Add ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 1000
        ambientLight.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Add camera
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)
        context.coordinator.cameraNode = cameraNode
        scnView.pointOfView = cameraNode

        NotificationCenter.default.addObserver(forName: .viewerRecenter, object: nil, queue: .main) { _ in
            recenter(context: context)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                DispatchQueue.main.async {
                    self.loadingProgress = "Reading PLY file..."
                }
                
                let points = try PLYPointCloud.read(from: plyURL)
                
                DispatchQueue.main.async {
                    self.loadingProgress = "Processing \(formatPointCount(points.count)) points..."
                }
                
                let (node, center) = makePointCloudNode(from: points)
                
                DispatchQueue.main.async {
                    self.loadingProgress = "Rendering..."
                }
                
                DispatchQueue.main.async {
                    scene.rootNode.addChildNode(node)
                    context.coordinator.pointNode = node
                    context.coordinator.pointCloudCenter = center
                    
                    // Publish center to viewerCoordinator for note overlay
                    self.viewerCoordinator.pointCloudCenter = center
                    self.viewerCoordinator.isReady = true
                    
                    // Position camera based on point cloud bounds
                    if let boundingSphere = node.geometry?.boundingSphere {
                        let distance = Float(boundingSphere.radius) * 2.5
                        cameraNode.position = SCNVector3(0, 0, distance)
                    }
                    
                    // Hide loading indicator
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.isLoading = false
                    }
                }
            } catch {
                print("Failed to load PLY:", error)
                DispatchQueue.main.async {
                    self.loadingProgress = "Failed to load"
                    self.isLoading = false
                }
            }
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func makePointCloudNode(from points: [PLYPoint]) -> (node: SCNNode, center: SIMD3<Float>) {
        guard !points.isEmpty else {
            return (SCNNode(), .zero)
        }

        var minPoint = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for point in points {
            minPoint = simd_min(minPoint, point.position)
            maxPoint = simd_max(maxPoint, point.position)
        }

        let center = (minPoint + maxPoint) * 0.5

        var positions: [Float] = []
        var colors: [Float] = []
        positions.reserveCapacity(points.count * 3)
        colors.reserveCapacity(points.count * 4)

        for point in points {
            let centered = point.position - center
            positions.append(centered.x)
            positions.append(centered.y)
            positions.append(centered.z)

            colors.append(Float(point.color.x) / 255.0)
            colors.append(Float(point.color.y) / 255.0)
            colors.append(Float(point.color.z) / 255.0)
            colors.append(1.0)
        }

        let vertexData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: 0
        )
        element.pointSize = 4.0
        element.minimumPointScreenSpaceRadius = 2.0
        element.maximumPointScreenSpaceRadius = 6.0

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.diffuse.contents = UIColor.white
        geometry.materials = [material]

        return (SCNNode(geometry: geometry), center)
    }

    private func recenter(context: Context) {
        guard let cameraNode = context.coordinator.cameraNode,
              let pointNode = context.coordinator.pointNode else { return }
        
        // Reset point cloud position and camera
        pointNode.position = SCNVector3Zero
        pointNode.eulerAngles = SCNVector3Zero
        
        if let boundingSphere = pointNode.geometry?.boundingSphere {
            let distance = Float(boundingSphere.radius) * 2.5
            cameraNode.position = SCNVector3(0, 0, distance)
        } else {
            cameraNode.position = SCNVector3(0, 0, 3)
        }
        cameraNode.eulerAngles = SCNVector3Zero
    }
}

private func formatPointCount(_ count: Int) -> String {
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
        return String(format: "%.0fK", Double(count) / 1_000)
    } else {
        return "\(count)"
    }
}
