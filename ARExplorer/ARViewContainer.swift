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

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard isScanning else { return }
            
            // Process frame with LiDAR depth map recorder
            recorder.process(frame: frame)
        }

        // MARK: - Actions
        
        func clearMap() {
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
                currentSpaceFolder = try ScanStorage.makeNewSpaceFolder()
                print("✅ Created space folder: \(currentSpaceFolder!.path)")
            } catch {
                print("❌ Failed to create space folder: \(error)")
            }
            photoIndex = 0
            isScanning = true
            recorder.reset()

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

        // Show mesh overlay for visual feedback during scanning
        arView.debugOptions = [.showSceneUnderstanding]

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
        NotificationCenter.default.addObserver(forName: .startScan, object: nil, queue: .main) { _ in
            context.coordinator.clearMap()
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
