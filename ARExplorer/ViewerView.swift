import SwiftUI
import RealityKit
import UIKit
import ARKit

struct ViewerView: View {
    let usdzURL: URL

    var body: some View {
        ViewerARViewContainer(usdzURL: usdzURL)
            .ignoresSafeArea()
    }
}

struct ViewerARViewContainer: UIViewRepresentable {
    let usdzURL: URL

    final class Coordinator {
        weak var arView: ARView?
        var anchor: AnchorEntity?
        var entity: Entity?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        context.coordinator.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)

        NotificationCenter.default.addObserver(forName: .viewerRecenter, object: nil, queue: .main) { _ in
            recenter(context: context)
        }

        Task { @MainActor in
            do {
                let entity = try await Entity.load(contentsOf: usdzURL)
                applyColorfulMaterial(to: entity)

                let bounds = entity.visualBounds(relativeTo: nil)
                entity.position -= bounds.center

                let modelAnchor = AnchorEntity(world: .zero)
                modelAnchor.addChild(entity)
                arView.scene.addAnchor(modelAnchor)

                context.coordinator.anchor = modelAnchor
                context.coordinator.entity = entity
            } catch {
                print("Failed to load USDZ:", error)
            }
        }

        return arView
    }

    private func applyColorfulMaterial(to entity: Entity) {
        // Walk the whole hierarchy and recolor anything renderable
        func walk(_ e: Entity) {
            if var model = e.components[ModelComponent.self] {
                // Option A: single pleasant color (cleanest)
                model.materials = [SimpleMaterial(color: .systemTeal, isMetallic: false)]
                e.components.set(model)
            }
            for c in e.children { walk(c) }
        }
        walk(entity)
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    private func recenter(context: Context) {
        guard let arView = context.coordinator.arView,
              let anchor = context.coordinator.anchor,
              let camera = arView.session.currentFrame?.camera else { return }

        let t = camera.transform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        anchor.position = position
    }
}
