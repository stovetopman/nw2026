//
//  FlyThroughView.swift
//  ARExplorer - LiDAR Memory
//
//  RealityKit-based fly-through viewer with joystick navigation.
//

import SwiftUI
import RealityKit
import simd
import Combine

/// Fly-through navigation view for exploring saved 3D memories
struct FlyThroughView: View {
    let usdzURL: URL
    @Environment(\.dismiss) private var dismiss
    
    @State private var movementOutput = JoystickOutput()
    @State private var rotationOutput = JoystickOutput()
    @State private var isLoading = true
    @State private var loadError: String?
    
    var body: some View {
        ZStack {
            // 3D View
            FlyThroughARViewContainer(
                usdzURL: usdzURL,
                movementInput: $movementOutput,
                rotationInput: $rotationOutput,
                isLoading: $isLoading,
                loadError: $loadError
            )
            .ignoresSafeArea()
            
            // UI Overlay
            VStack {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .padding()
                    
                    Spacer()
                    
                    if !isLoading {
                        Text("FLY-THROUGH MODE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 44, height: 44)
                        .padding()
                }
                
                Spacer()
                
                // Loading or error state
                if isLoading {
                    ProgressView("Loading memory...")
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .foregroundColor(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                if let error = loadError {
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
                
                Spacer()
                
                // Joysticks (only show when loaded)
                if !isLoading && loadError == nil {
                    DualJoystickOverlay(
                        movementOutput: $movementOutput,
                        rotationOutput: $rotationOutput
                    )
                }
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: true)
    }
}

/// UIViewRepresentable container for RealityKit fly-through
struct FlyThroughARViewContainer: UIViewRepresentable {
    let usdzURL: URL
    @Binding var movementInput: JoystickOutput
    @Binding var rotationInput: JoystickOutput
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .nonAR,
            automaticallyConfigureSession: false
        )
        
        // Disable AR session - we're in virtual fly-through mode
        arView.session.pause()
        
        // Set up environment
        arView.environment.background = .color(.black)
        arView.environment.lighting.intensityExponent = 1.0
        
        // Store reference
        context.coordinator.arView = arView
        
        // Load the USDZ model
        Task {
            await loadModel(context: context, arView: arView)
        }
        
        // Start the update loop
        context.coordinator.startUpdateLoop()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update camera based on joystick input
        context.coordinator.updateCamera(
            movement: movementInput,
            rotation: rotationInput
        )
    }
    
    @MainActor
    private func loadModel(context: Context, arView: ARView) async {
        isLoading = true
        loadError = nil
        
        do {
            print("📂 Loading USDZ from: \(usdzURL.path)")
            
            let entity = try await Entity.load(contentsOf: usdzURL)
            
            // Create anchor for the model
            let modelAnchor = AnchorEntity(world: .zero)
            modelAnchor.addChild(entity)
            arView.scene.addAnchor(modelAnchor)
            
            // Calculate bounds for initial camera positioning
            let bounds = entity.visualBounds(relativeTo: nil)
            let center = bounds.center
            let extents = bounds.extents
            let maxExtent = max(extents.x, max(extents.y, extents.z))
            
            print("📊 Model bounds - center: \(center), extents: \(extents)")
            
            // Create camera entity
            let cameraAnchor = AnchorEntity(world: .zero)
            let cameraEntity = Entity()
            
            // Position camera to see the whole model
            let cameraDistance = maxExtent * 1.5
            cameraEntity.position = SIMD3<Float>(
                center.x,
                center.y + extents.y * 0.5,
                center.z + cameraDistance
            )
            
            // Look at center
            cameraEntity.look(at: center, from: cameraEntity.position, relativeTo: nil)
            
            cameraAnchor.addChild(cameraEntity)
            arView.scene.addAnchor(cameraAnchor)
            
            // Store camera reference for navigation
            context.coordinator.cameraEntity = cameraEntity
            context.coordinator.modelCenter = center
            
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
        var cameraEntity: Entity?
        var modelCenter: SIMD3<Float> = .zero
        
        private var displayLink: CADisplayLink?
        private var lastUpdateTime: CFTimeInterval = 0
        
        // Camera state
        private var yaw: Float = 0      // Rotation around Y axis
        private var pitch: Float = 0    // Rotation around X axis
        
        // Movement/rotation speeds
        private let moveSpeed: Float = 2.0
        private let rotationSpeed: Float = 1.5
        
        // Current input
        private var currentMovement = JoystickOutput()
        private var currentRotation = JoystickOutput()
        
        deinit {
            displayLink?.invalidate()
        }
        
        func startUpdateLoop() {
            displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
            displayLink?.add(to: .main, forMode: .common)
        }
        
        func updateCamera(movement: JoystickOutput, rotation: JoystickOutput) {
            currentMovement = movement
            currentRotation = rotation
        }
        
        @objc private func updateFrame(displayLink: CADisplayLink) {
            let currentTime = displayLink.timestamp
            let deltaTime = lastUpdateTime == 0 ? 0.016 : Float(currentTime - lastUpdateTime)
            lastUpdateTime = currentTime
            
            guard let camera = cameraEntity else { return }
            
            // Update rotation from right joystick
            if currentRotation.isActive {
                yaw -= currentRotation.x * rotationSpeed * deltaTime
                pitch += currentRotation.y * rotationSpeed * deltaTime
                
                // Clamp pitch to prevent flipping
                pitch = max(-Float.pi / 2.5, min(Float.pi / 2.5, pitch))
            }
            
            // Calculate camera orientation
            let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let pitchRotation = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            camera.orientation = yawRotation * pitchRotation
            
            // Update position from left joystick
            if currentMovement.isActive {
                // Get camera's forward and right vectors
                let forward = camera.transform.matrix.forwardVector
                let right = camera.transform.matrix.rightVector
                
                // Calculate movement delta
                let moveX = currentMovement.x * moveSpeed * deltaTime
                let moveZ = currentMovement.y * moveSpeed * deltaTime
                
                // Apply movement relative to camera orientation
                camera.position += right * moveX
                camera.position += forward * moveZ
            }
        }
    }
}

// MARK: - Matrix Extensions for Camera Vectors

extension simd_float4x4 {
    /// Forward vector (negative Z in camera space)
    var forwardVector: SIMD3<Float> {
        let forward = SIMD3<Float>(-columns.2.x, -columns.2.y, -columns.2.z)
        return normalize(forward)
    }
    
    /// Right vector (positive X in camera space)
    var rightVector: SIMD3<Float> {
        let right = SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z)
        return normalize(right)
    }
    
    /// Up vector (positive Y in camera space)
    var upVector: SIMD3<Float> {
        let up = SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z)
        return normalize(up)
    }
}

// MARK: - Preview

#Preview {
    FlyThroughView(usdzURL: URL(fileURLWithPath: "/tmp/test.usdz"))
}
