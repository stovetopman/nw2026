import SwiftUI
import RealityKit
import ARKit
import UIKit
import simd
import CoreVideo
import Combine


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
        
        // Spatial notes
        let noteManager = SpatialNoteManager()
        private var noteEntityManager: NoteEntityManager?
        private var notesCancellable: AnyCancellable?

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
        
        func setupNotes() {
            guard let arView = arView, let folder = currentSpaceFolder else { return }
            
            // Configure note entity manager
            noteEntityManager = NoteEntityManager(arView: arView)
            
            // Configure note manager with folder
            noteManager.configure(arView: arView, folderURL: folder)
            
            // Observe note changes to sync entities
            notesCancellable = noteManager.$notes
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notes in
                    self?.noteEntityManager?.sync(with: notes)
                }
            
            print("✅ Spatial notes initialized for: \(folder.lastPathComponent)")
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard isScanning else { return }
            
            // Process frame with LiDAR depth map recorder
            recorder.process(frame: frame)
            
            // Update billboard orientations
            noteEntityManager?.updateBillboards(cameraTransform: frame.camera.transform)
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            // Handle anchor additions for relocalization
            noteManager.handleAddedAnchors(anchors)
        }
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            // Update note transforms when ARKit updates anchors
            noteManager.updateAnchors(anchors)
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
                
                // Initialize notes for this new folder
                setupNotes()
            } catch {
                print("❌ Failed to create space folder: \(error)")
            }
            photoIndex = 0
            isScanning = true
            recorder.reset()
            visualizer?.clear()  // Clear previous point cloud visualization
            noteEntityManager?.clear()  // Clear previous note entities

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
            
            // Save world map for note relocalization
            noteManager.saveWorldMap { success in
                if success {
                    print("✅ World map saved for note relocalization")
                }
            }

            // Save using the LiDAR recorder
            recorder.savePLY { [weak self] url in
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
        
        // MARK: - Note Actions
        
        func createNoteAtCenter(text: String, completion: @escaping (SpatialNote?) -> Void) {
            noteManager.createNoteAtScreenCenter(text: text, completion: completion)
        }
        
        func createNote(at screenPoint: CGPoint, text: String, completion: @escaping (SpatialNote?) -> Void) {
            noteManager.createNote(at: screenPoint, text: text, completion: completion)
        }
        
        func deleteNote(_ note: SpatialNote) {
            noteManager.deleteNote(note)
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
        NotificationCenter.default.addObserver(forName: .startScan, object: nil, queue: .main) { _ in
            context.coordinator.clearMap()
        }
        
        // Spatial Note notifications
        NotificationCenter.default.addObserver(forName: .createSpatialNote, object: nil, queue: .main) { notification in
            guard let payload = notification.object as? CreateNotePayload else { return }
            
            if let screenPoint = payload.screenPoint {
                context.coordinator.createNote(at: screenPoint, text: payload.text) { note in
                    if let note = note {
                        print("✅ Created note: \(note.text)")
                    }
                }
            } else {
                context.coordinator.createNoteAtCenter(text: payload.text) { note in
                    if let note = note {
                        print("✅ Created note at center: \(note.text)")
                    }
                }
            }
        }
        
        NotificationCenter.default.addObserver(forName: .deleteSpatialNote, object: nil, queue: .main) { notification in
            guard let note = notification.object as? SpatialNote else { return }
            context.coordinator.deleteNote(note)
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
