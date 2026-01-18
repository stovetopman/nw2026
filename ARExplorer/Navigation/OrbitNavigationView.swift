//
//  OrbitNavigationView.swift
//  ARExplorer - LiDAR Memory
//
//  Gesture-based orbit, pan, and zoom navigation for exploring 3D memories.
//  Uses RealityKit in non-AR mode with a virtual PerspectiveCamera.
//

import SwiftUI
import RealityKit
import simd
import Combine

/// Orbit & Pan navigation view for exploring saved 3D memories
struct OrbitNavigationView: View {
    let usdzURL: URL
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var cameraController = CameraController()
    @State private var isLoading = true
    @State private var loadError: String?
    
    // Gesture tracking state
    @State private var lastDragValue: CGSize = .zero
    @State private var lastPanValue: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1.0
    @State private var isDragging = false
    @State private var isPanning = false
    
    var body: some View {
        ZStack {
            // 3D RealityKit View with gestures
            OrbitRealityView(
                usdzURL: usdzURL,
                cameraController: cameraController,
                isLoading: $isLoading,
                loadError: $loadError
            )
            .ignoresSafeArea()
            .gesture(orbitGesture)
            .simultaneousGesture(magnificationGesture)
            .simultaneousGesture(panGesture)
            
            // UI Overlay
            VStack {
                // Top bar
                topBar
                
                Spacer()
                
                // Status overlays
                if isLoading {
                    loadingOverlay
                }
                
                if let error = loadError {
                    errorOverlay(error: error)
                }
                
                Spacer()
                
                // Instructions (fade out after a few seconds)
                if !isLoading && loadError == nil {
                    instructionsOverlay
                }
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
        .onAppear {
            cameraController.startUpdateLoop()
        }
        .onDisappear {
            cameraController.stopUpdateLoop()
        }
    }
    
    // MARK: - Gestures
    
    /// Single-finger drag for orbit (yaw/pitch around pivot)
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // Calculate delta from last position
                let delta = CGSize(
                    width: value.translation.width - lastDragValue.width,
                    height: value.translation.height - lastDragValue.height
                )
                lastDragValue = value.translation
                isDragging = true
                
                cameraController.handleOrbit(delta: delta)
            }
            .onEnded { value in
                // Calculate velocity for inertia
                let velocity = value.velocity
                let velocityDelta = CGSize(
                    width: velocity.width * 0.016,  // Approximate one frame
                    height: velocity.height * 0.016
                )
                cameraController.handleOrbit(delta: velocityDelta, isEnding: true)
                
                lastDragValue = .zero
                isDragging = false
            }
    }
    
    /// Pinch gesture for zoom
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Calculate relative scale change
                let scale = value / lastMagnification
                lastMagnification = value
                
                cameraController.handleZoom(scale: scale)
            }
            .onEnded { value in
                // Apply ending inertia
                cameraController.handleZoom(scale: 1.0, velocity: 0, isEnding: true)
                lastMagnification = 1.0
            }
    }
    
    /// Two-finger drag for pan (moves pivot point)
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .simultaneously(with: DragGesture(minimumDistance: 1))
            .onChanged { value in
                // This fires with simultaneous two-finger drag
                // Use the first gesture's values
                if let first = value.first?.translation {
                    // Only treat as pan if we detect this is a multi-touch
                    // (In practice, single vs two-finger is distinguished by gesture priority)
                    if isPanning {
                        let delta = CGSize(
                            width: first.width - lastPanValue.width,
                            height: first.height - lastPanValue.height
                        )
                        cameraController.handlePan(delta: delta)
                    }
                    lastPanValue = first
                    isPanning = true
                }
            }
            .onEnded { value in
                if let velocity = value.first?.velocity {
                    let velocityDelta = CGSize(
                        width: velocity.width * 0.016,
                        height: velocity.height * 0.016
                    )
                    cameraController.handlePan(delta: velocityDelta, isEnding: true)
                }
                lastPanValue = .zero
                isPanning = false
            }
    }
    
    // MARK: - UI Components
    
    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            .padding()
            
            Spacer()
            
            if !isLoading {
                Text("EXPLORE MODE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            // Reset view button
            if !isLoading && loadError == nil {
                Button(action: resetCamera) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                .padding()
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .padding()
            }
        }
    }
    
    private var loadingOverlay: some View {
        ProgressView("Loading memory...")
            .progressViewStyle(.circular)
            .tint(.white)
            .foregroundColor(.white)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func errorOverlay(error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("Failed to load")
                .font(.headline)
            Text(error)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(.white)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var instructionsOverlay: some View {
        VStack(spacing: 4) {
            HStack(spacing: 16) {
                Label("Orbit", systemImage: "hand.draw")
                Label("Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                Label("Pan", systemImage: "hand.point.up.braille")
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, 30)
        .transition(.opacity)
    }
    
    private func resetCamera() {
        // Clear any velocity and let camera controller reinitialize on next load
        cameraController.clearVelocity()
    }
}

// MARK: - RealityKit View Container

struct OrbitRealityView: UIViewRepresentable {
    let usdzURL: URL
    @ObservedObject var cameraController: CameraController
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(cameraController: cameraController)
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        
        // Disable AR session - we're in virtual explore mode
        arView.session.pause()
        
        // Set up environment
        arView.environment.background = .color(.darkGray)
        arView.environment.lighting.intensityExponent = 1.0
        
        // Store reference
        context.coordinator.arView = arView
        
        // Load the USDZ model
        Task {
            await loadModel(context: context, arView: arView)
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update camera transform from controller
        context.coordinator.updateCameraTransform(cameraController.cameraTransform)
    }
    
    @MainActor
    private func loadModel(context: Context, arView: ARView) async {
        isLoading = true
        loadError = nil
        
        do {
            print("📂 Loading USDZ from: \(usdzURL.path)")
            
            let entity = try await Entity.load(contentsOf: usdzURL)
            
            // Calculate bounds before centering
            let originalBounds = entity.visualBounds(relativeTo: nil)
            let originalCenter = originalBounds.center
            
            // Center the model at world origin (0,0,0)
            entity.position = -originalCenter
            
            // Create anchor for the model
            let modelAnchor = AnchorEntity(world: .zero)
            modelAnchor.addChild(entity)
            arView.scene.addAnchor(modelAnchor)
            
            // Get new bounds after centering
            let bounds = entity.visualBounds(relativeTo: nil)
            let center = bounds.center  // Should now be near (0,0,0)
            let extents = bounds.extents
            
            print("📊 Model centered - bounds center: \(center), extents: \(extents)")
            
            // Add lighting
            let lightAnchor = AnchorEntity(world: .zero)
            let light = PointLight()
            light.light.intensity = 10000
            light.position = SIMD3<Float>(0, extents.y * 2, 0)
            lightAnchor.addChild(light)
            arView.scene.addAnchor(lightAnchor)
            
            // Create perspective camera
            let cameraAnchor = AnchorEntity(world: .zero)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 60
            camera.camera.near = 0.01  // Small near clip for tight corners
            camera.camera.far = 1000
            cameraAnchor.addChild(camera)
            arView.scene.addAnchor(cameraAnchor)
            
            context.coordinator.cameraEntity = camera
            
            // Initialize camera controller with model bounds
            // Pivot at center of bounding box (which is now at origin)
            cameraController.initialize(
                modelCenter: SIMD3<Float>(0, extents.y * 0.3, 0),  // Slightly above center
                modelExtents: extents
            )
            
            print("✅ Model loaded successfully")
            isLoading = false
            
        } catch {
            print("❌ Failed to load USDZ: \(error)")
            loadError = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator {
        var arView: ARView?
        var cameraEntity: PerspectiveCamera?
        weak var cameraController: CameraController?
        
        init(cameraController: CameraController) {
            self.cameraController = cameraController
        }
        
        func updateCameraTransform(_ transform: simd_float4x4) {
            guard let camera = cameraEntity else { return }
            
            // Apply transform to camera entity
            camera.transform = Transform(matrix: transform)
        }
    }
}

// MARK: - Preview

#Preview {
    OrbitNavigationView(usdzURL: URL(fileURLWithPath: "/tmp/test.usdz"))
}
