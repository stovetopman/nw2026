import RealityKit
import ARKit
import UIKit
import simd

/// Creates a panoramic background by placing dimmed camera snapshots as 3D planes in the scene
class PanoramaStitcher {
    private weak var arView: ARView?
    private var panoramaAnchor: AnchorEntity?
    
    // Track captured panels to avoid duplicates
    private var capturedDirections: Set<DirectionKey> = []
    
    // Last capture time to throttle
    private var lastCaptureTime: TimeInterval = 0
    private let captureInterval: TimeInterval = 0.5  // Capture every 0.5 seconds max
    
    // Distance to place the panorama planes from camera origin
    private let planeDistance: Float = 2.0
    
    // Size of each panorama panel
    private let panelWidth: Float = 1.5
    private let panelHeight: Float = 2.0
    
    // Grid resolution for direction tracking (lower = fewer panels, less overlap)
    private let gridResolution: Float = 30.0  // degrees
    
    // Core Image context for image processing
    private let ciContext = CIContext()
    
    struct DirectionKey: Hashable {
        let yawBucket: Int
        let pitchBucket: Int
    }
    
    init(arView: ARView) {
        self.arView = arView
        
        // Create anchor for panorama panels
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "PanoramaAnchor"
        arView.scene.addAnchor(anchor)
        self.panoramaAnchor = anchor
    }
    
    /// Call this on each frame to potentially capture a new panorama panel
    func update(frame: ARFrame) {
        let currentTime = frame.timestamp
        
        // Throttle captures
        guard currentTime - lastCaptureTime >= captureInterval else { return }
        
        // Get camera direction
        let cameraTransform = frame.camera.transform
        let forward = -simd_float3(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)
        
        // Calculate yaw and pitch
        let yaw = atan2(forward.x, forward.z) * 180 / .pi  // -180 to 180
        let pitch = asin(forward.y) * 180 / .pi  // -90 to 90
        
        // Bucket the direction
        let yawBucket = Int((yaw / gridResolution).rounded())
        let pitchBucket = Int((pitch / gridResolution).rounded())
        let directionKey = DirectionKey(yawBucket: yawBucket, pitchBucket: pitchBucket)
        
        // Check if we already have a panel for this direction
        guard !capturedDirections.contains(directionKey) else { return }
        
        // Capture and place a new panel
        capturePanel(frame: frame, yaw: yaw, pitch: pitch, directionKey: directionKey)
        lastCaptureTime = currentTime
    }
    
    private func capturePanel(frame: ARFrame, yaw: Float, pitch: Float, directionKey: DirectionKey) {
        guard let anchor = panoramaAnchor else { return }
        
        // Convert camera frame to dimmed UIImage
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Apply darkening filter
        guard let darkenFilter = CIFilter(name: "CIColorControls") else { return }
        darkenFilter.setValue(ciImage, forKey: kCIInputImageKey)
        darkenFilter.setValue(-0.35, forKey: kCIInputBrightnessKey)
        darkenFilter.setValue(1.05, forKey: kCIInputContrastKey)
        
        guard let outputImage = darkenFilter.outputImage,
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else { return }
        
        // Create texture from image (rotated for portrait)
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        // Create a smaller version for performance
        let targetSize = CGSize(width: 256, height: 341)  // Reduced resolution
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
        guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return
        }
        UIGraphicsEndImageContext()
        
        // Create texture
        guard let cgImageResized = resizedImage.cgImage,
              let texture = try? TextureResource.generate(from: cgImageResized, options: .init(semantic: .color)) else { return }
        
        // Calculate position for the panel (on a sphere around the camera)
        // Note: We place panels in the direction the camera was looking
        let yawRad = yaw * .pi / 180
        let pitchRad = pitch * .pi / 180
        
        // Position in front of where the camera was pointing
        let x = planeDistance * cos(pitchRad) * sin(yawRad)
        let y = planeDistance * sin(pitchRad)
        let z = -planeDistance * cos(pitchRad) * cos(yawRad)  // Negative Z is forward in ARKit
        
        // Create plane mesh (double-sided)
        let mesh = MeshResource.generatePlane(width: panelWidth, height: panelHeight)
        
        // Create material with the texture
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .none  // Double-sided
        
        // Create entity
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Panel_\(directionKey.yawBucket)_\(directionKey.pitchBucket)"
        
        // Position the panel
        entity.position = SIMD3<Float>(x, y, z)
        
        // Rotate plane to face the origin (where camera is)
        // First, make the plane vertical (it spawns horizontal by default)
        entity.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        
        // Then rotate to face the camera position
        let toCamera = normalize(SIMD3<Float>(0, 0, 0) - entity.position)
        let defaultForward = SIMD3<Float>(0, 0, 1)
        let rotationAxis = cross(defaultForward, toCamera)
        if length(rotationAxis) > 0.001 {
            let angle = acos(dot(defaultForward, toCamera))
            let lookRotation = simd_quatf(angle: angle, axis: normalize(rotationAxis))
            entity.orientation = lookRotation * entity.orientation
        }
        
        // Add to scene
        anchor.addChild(entity)
        
        // Mark this direction as captured
        capturedDirections.insert(directionKey)
        
        print("📷 Captured panorama panel at yaw: \(Int(yaw))° pitch: \(Int(pitch))° (total: \(capturedDirections.count))")
    }
    
    func clear() {
        panoramaAnchor?.children.removeAll()
        capturedDirections.removeAll()
        lastCaptureTime = 0
    }
    
    var panelCount: Int {
        return capturedDirections.count
    }
}
