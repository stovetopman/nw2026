import SwiftUI
import RealityKit
import ARKit
import SceneKit
import ModelIO
import Metal
import SceneKit.ModelIO
import MetalKit


struct ARViewContainer: UIViewRepresentable {

    final class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView?

        var currentSpaceFolder: URL?
        var photoIndex: Int = 0

        // Collect LiDAR mesh anchors for export
        var meshAnchors: [UUID: ARMeshAnchor] = [:]

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for a in anchors {
                if let m = a as? ARMeshAnchor {
                    meshAnchors[m.identifier] = m
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for a in anchors {
                if let m = a as? ARMeshAnchor {
                    meshAnchors[m.identifier] = m
                }
            }
        }

        // MARK: - Actions

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

        func saveUSDZ() {
            guard let folder = currentSpaceFolder else { return }
            guard let device = MTLCreateSystemDefaultDevice() else {
                print("No Metal device available.")
                return
            }

            // Debug: how much mesh data we have
            print("meshAnchors:", meshAnchors.count)
            var totalVerts = 0
            var totalFaces = 0
            for (_, a) in meshAnchors {
                totalVerts += a.geometry.vertices.count
                totalFaces += a.geometry.faces.count
            }
            print("totalVerts:", totalVerts, "totalFaces:", totalFaces)

            if meshAnchors.isEmpty || totalVerts == 0 || totalFaces == 0 {
                print("No mesh data yet. Walk around for 5–10 seconds and try again.")
                return
            }

            let usdzURL = folder.appendingPathComponent("scene.usdz")

            let asset = MDLAsset()
            for (_, anchor) in meshAnchors {
                let mdlMesh = anchor.toMDLMesh(device: device)
                asset.add(mdlMesh)
            }

            let scnScene = SCNScene(mdlAsset: asset)

                scnScene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil)

                let attrs = try? FileManager.default.attributesOfItem(atPath: usdzURL.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1
                print("Saved USDZ to \(usdzURL)")
                print("USDZ bytes:", size)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        // Helpful while scanning
        arView.debugOptions = [.showSceneUnderstanding]

        // Create a new folder for this scan session
        context.coordinator.currentSpaceFolder = try? ScanStorage.makeNewSpaceFolder()

        // AR config (LiDAR mesh)
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .automatic
        arView.session.run(config)

        NotificationCenter.default.addObserver(forName: .capturePhoto, object: nil, queue: .main) { _ in
            context.coordinator.capturePhoto()
        }
        NotificationCenter.default.addObserver(forName: .saveScan, object: nil, queue: .main) { _ in
            context.coordinator.saveUSDZ()
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Robust ARMeshAnchor -> MDLMesh conversion (handles vertices.offset; rebuilds indices)

extension ARMeshAnchor {

    private func readTriangleIndices(faces: ARGeometryElement) -> (indicesU16: [UInt16]?, indicesU32: [UInt32]?) {
        let triCount = faces.count
        let bpi = faces.bytesPerIndex
        let ptr = faces.buffer.contents()

        if bpi == 2 {
            var out: [UInt16] = []
            out.reserveCapacity(triCount * 3)
            for i in 0..<(triCount * 3) {
                let v = ptr.load(fromByteOffset: i * 2, as: UInt16.self)
                out.append(v)
            }
            return (out, nil)
        } else {
            var out: [UInt32] = []
            out.reserveCapacity(triCount * 3)
            for i in 0..<(triCount * 3) {
                let v = ptr.load(fromByteOffset: i * 4, as: UInt32.self)
                out.append(v)
            }
            return (nil, out)
        }
    }
}
