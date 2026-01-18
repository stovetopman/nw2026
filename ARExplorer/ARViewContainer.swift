import SwiftUI
import RealityKit
import ARKit
import UIKit
import simd
import CoreVideo


struct ARViewContainer: UIViewRepresentable {

    final class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView?

        var currentSpaceFolder: URL?
        var photoIndex: Int = 0

        private var isScanning = false
        
        // Use the new LiDAR depth-based point cloud recorder
        private let recorder = PointCloudRecorder()
        
        // Live point cloud visualizer
        private var visualizer: PointCloudVisualizer?

        // MARK: - Setup
        
        func setupVisualizer() {
            guard let arView = arView else { return }
            
            // Initialize visualizer with the ARView
            visualizer = PointCloudVisualizer(arView: arView)
            
            // Connect the recorder to the visualizer
            recorder.onNewPoints = { [weak self] points in
                self?.visualizer?.update(newPoints: points)
            }
            
            print("✅ Point cloud visualizer initialized")
        }
        
        // MARK: - Crosshair Position for Notes
        
        /// Get the world position where the crosshair (screen center) is pointing
        func getCrosshairWorldPosition() -> SIMD3<Float>? {
            guard let arView = arView,
                  let frame = arView.session.currentFrame else { return nil }
            
            let camera = frame.camera
            let cameraTransform = camera.transform
            
            // Get camera position and forward direction
            let cameraPosition = SIMD3<Float>(
                cameraTransform.columns.3.x,
                cameraTransform.columns.3.y,
                cameraTransform.columns.3.z
            )
            
            // Camera forward is -Z in camera space
            let forward = SIMD3<Float>(
                -cameraTransform.columns.2.x,
                -cameraTransform.columns.2.y,
                -cameraTransform.columns.2.z
            )
            
            // Try to raycast against real-world surfaces first
            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            // Use ARKit raycast for real-world surfaces
            if let query = arView.makeRaycastQuery(from: screenCenter, allowing: .estimatedPlane, alignment: .any) {
                let results = arView.session.raycast(query)
                if let firstResult = results.first {
                    let position = firstResult.worldTransform.columns.3
                    return SIMD3<Float>(position.x, position.y, position.z)
                }
            }
            
            // Fallback: place at fixed distance in front of camera
            let defaultDistance: Float = 1.5
            return cameraPosition + forward * defaultDistance
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard isScanning else { return }
            
            // Process frame with LiDAR depth map recorder
            recorder.process(frame: frame)
        }

        // MARK: - Actions
        
        func clearMap(title: String = "New Memory") {
            guard let arView else { return }

            // Configure AR session with LiDAR depth
            let config = ARWorldTrackingConfiguration()
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
            // Enable scene depth for LiDAR point cloud capture
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            config.environmentTexturing = .automatic

            arView.session.run(
                config,
                options: [
                    .removeExistingAnchors,
                    .resetSceneReconstruction
                ]
            )

            // Start a fresh folder/session
            do {
                currentSpaceFolder = try ScanStorage.makeNewSpaceFolder(title: title)
                print("✅ Created space folder: \(currentSpaceFolder!.path)")
                
                // Notify ScanView of the folder URL
                NotificationCenter.default.post(name: .scanFolderCreated, object: currentSpaceFolder)
            } catch {
                print("❌ Failed to create space folder: \(error)")
            }
            photoIndex = 0
            isScanning = true
            recorder.reset()
            visualizer?.clear()  // Clear previous point cloud visualization

            print("✅ Started LiDAR scanning - move around to collect points")
        }


        func capturePhoto() {
            guard let arView,
                  let frame = arView.session.currentFrame,
                  let folder = currentSpaceFolder else { return }

            photoIndex += 1
            let name = String(format: "%03d", photoIndex)

            let photoURL = folder.appendingPathComponent("photos/\(name).jpg")
            let poseURL  = folder.appendingPathComponent("photos/\(name)_pose.json")

            do {
                try ScanStorage.saveJPEG(from: frame.capturedImage, to: photoURL)

                // Save camera transform (world space)
                let pose: [String: Any] = [
                    "timestamp": frame.timestamp,
                    "transform": ScanStorage.matrixToArray(frame.camera.transform)
                ]
                try ScanStorage.saveJSON(pose, to: poseURL)

                print("Saved photo \(name) to \(photoURL.lastPathComponent)")
            } catch {
                print("Failed saving photo:", error)
            }
        }

        func savePLY() {
            isScanning = false
            guard let folder = currentSpaceFolder else {
                print("ERROR: No space folder created. Did you start the scan?")
                return
            }

            print("Attempting to save PLY with \(recorder.pointCount) points")
            
            if recorder.pointCount == 0 {
                print("No point cloud data yet. Walk around for a few seconds and try again.")
                return
            }

            // Save using the LiDAR recorder
            recorder.savePLY { url in
                guard let url = url else {
                    print("❌ Failed to save PLY")
                    return
                }
                
                // Also save a copy to the space folder
                let plyURL = folder.appendingPathComponent("scene.ply")
                do {
                    if FileManager.default.fileExists(atPath: plyURL.path) {
                        try FileManager.default.removeItem(at: plyURL)
                    }
                    try FileManager.default.copyItem(at: url, to: plyURL)
                    print("✅ Copied PLY to space folder: \(plyURL.path)")
                    
                    NotificationCenter.default.post(name: .scanSaved, object: plyURL)
                } catch {
                    print("❌ Failed to copy PLY to space folder: \(error)")
                    // Still notify with the original URL
                    NotificationCenter.default.post(name: .scanSaved, object: url)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        // Initialize the point cloud visualizer
        context.coordinator.setupVisualizer()

        // AR config with LiDAR depth
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        // Enable scene depth for LiDAR point cloud capture
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.environmentTexturing = .automatic
        arView.session.run(config)

        NotificationCenter.default.addObserver(forName: .capturePhoto, object: nil, queue: .main) { _ in
            context.coordinator.capturePhoto()
        }
        NotificationCenter.default.addObserver(forName: .saveScan, object: nil, queue: .main) { _ in
            context.coordinator.savePLY()
        }
        NotificationCenter.default.addObserver(forName: .clearMap, object: nil, queue: .main) { _ in
            context.coordinator.clearMap()
        }
        NotificationCenter.default.addObserver(forName: .startScan, object: nil, queue: .main) { notification in
            let title = notification.object as? String ?? "New Memory"
            context.coordinator.clearMap(title: title)
            // Capture initial thumbnail photo after a brief delay to ensure AR is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                context.coordinator.capturePhoto()
            }
        }
        NotificationCenter.default.addObserver(forName: .requestCameraPosition, object: nil, queue: .main) { _ in
            if let position = context.coordinator.getCrosshairWorldPosition() {
                NotificationCenter.default.post(name: .cameraPositionResponse, object: position)
            }
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
