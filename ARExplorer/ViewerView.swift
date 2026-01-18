import SwiftUI
import RealityKit
import UIKit

struct ViewerView: View {
    let usdzURL: URL

    var body: some View {
        ViewerARViewContainer(usdzURL: usdzURL)
            .ignoresSafeArea()
    }
}

struct ViewerARViewContainer: UIViewRepresentable {
    let usdzURL: URL

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        arView.session.pause()
        arView.environment.background = .color(.black)

        print("Viewer started, loading:", usdzURL.path)

        Task {
            do {
                let entity = try await Entity.load(contentsOf: usdzURL)
                
                applyColorfulMaterial(to: entity)


                // Debug: count ModelComponents
                var modelCount = 0
                func walk(_ e: Entity) {
                    if e.components.has(ModelComponent.self) { modelCount += 1 }
                    for c in e.children { walk(c) }
                }
                walk(entity)
                print("Root children:", entity.children.count)
                print("ModelComponent count:", modelCount)

                let modelAnchor = AnchorEntity(world: .zero)
                modelAnchor.addChild(entity)
                arView.scene.addAnchor(modelAnchor)

                let bounds = entity.visualBounds(relativeTo: nil)
                print("BOUNDS center:", bounds.center)
                print("BOUNDS extents:", bounds.extents)

                // Force camera
                let camAnchor = AnchorEntity(world: .zero)
                let camEntity = Entity()
//                camEntity.components.set(PerspectiveCamera())
                camEntity.position = [0, 0.8, 2.0]
                camEntity.look(at: .zero, from: camEntity.position, relativeTo: nil)
                camAnchor.addChild(camEntity)
                arView.scene.addAnchor(camAnchor)
                print("DEBUG camera added")

            } catch {
                print("❌ Failed to load USDZ:", error)
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
}
