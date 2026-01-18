//
//  ARProcessor.swift
//  ARExplorer
//
//  ARKit delegate for processing mesh anchors into point cloud.
//

import ARKit
import CoreVideo
import simd

// MARK: - AR Processor

/// Processes ARMeshAnchors and extracts colored points.
final class ARProcessor: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var isRunning = false
    
    /// The point manager to store extracted points
    weak var pointManager: PointManager?
    
    /// AR Session
    private var session: ARSession?
    
    /// Track last processed time for throttling
    private var lastProcessTime: TimeInterval = 0
    private let processInterval: TimeInterval = 0.1  // Process every 100ms
    
    /// Track processed anchor versions to avoid reprocessing unchanged meshes
    private var processedAnchorVersions: [UUID: Int] = [:]
    
    // MARK: - Public API
    
    /// Start AR session with mesh reconstruction
    func start(session: ARSession, pointManager: PointManager) {
        self.session = session
        self.pointManager = pointManager
        session.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.frameSemantics = []
        
        session.run(config)
        isRunning = true
    }
    
    /// Stop AR session
    func stop() {
        session?.pause()
        isRunning = false
    }
}

// MARK: - ARSessionDelegate

extension ARProcessor: ARSessionDelegate {
    
    // Called every frame - this gives us correct temporal sync
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let pointManager = pointManager else { return }
        
        // Throttle processing to avoid overwhelming the system
        let currentTime = frame.timestamp
        guard currentTime - lastProcessTime >= processInterval else { return }
        lastProcessTime = currentTime
        
        // Process mesh anchors with THIS frame's camera data
        // This ensures color sampling uses the exact camera position/image
        for anchor in frame.anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            
            // Check if this mesh version was already processed
            let anchorID = meshAnchor.identifier
            let geometry = meshAnchor.geometry
            let currentVersion = geometry.vertices.count  // Use vertex count as simple version proxy
            
            if let lastVersion = processedAnchorVersions[anchorID], lastVersion == currentVersion {
                continue  // Skip unchanged mesh
            }
            processedAnchorVersions[anchorID] = currentVersion
            
            let points = extractPoints(from: meshAnchor, frame: frame)
            pointManager.addPoints(points)
        }
    }
}

// MARK: - Point Extraction

extension ARProcessor {
    
    /// Extract colored points from a mesh anchor
    private func extractPoints(from meshAnchor: ARMeshAnchor, frame: ARFrame) -> [ColoredPoint] {
        let geometry = meshAnchor.geometry
        let vertices = geometry.vertices
        let modelMatrix = meshAnchor.transform
        
        // Get vertex data
        let vertexCount = vertices.count
        let vertexBuffer = vertices.buffer.contents()
        let vertexStride = vertices.stride
        
        // Prepare for color sampling
        let pixelBuffer = frame.capturedImage
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        // Get camera transform (world to camera)
        let cameraTransform = frame.camera.transform
        let cameraInverse = cameraTransform.inverse
        
        // Get camera intrinsics (focal length and principal point)
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        
        // Lock pixel buffer for reading
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        var points: [ColoredPoint] = []
        points.reserveCapacity(vertexCount)
        
        for i in 0..<vertexCount {
            // Read vertex position (local space)
            let vertexPointer = vertexBuffer.advanced(by: i * vertexStride)
            let localPosition = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            
            // Transform to world space
            let localPos4 = SIMD4<Float>(localPosition.x, localPosition.y, localPosition.z, 1.0)
            let worldPos4 = modelMatrix * localPos4
            let worldPosition = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)
            
            // Transform world position to camera space
            let cameraPos4 = cameraInverse * worldPos4
            let cameraPos = SIMD3<Float>(cameraPos4.x, cameraPos4.y, cameraPos4.z)
            
            // Sample color from camera image
            let color = sampleColorFromIntrinsics(
                cameraPosition: cameraPos,
                fx: fx, fy: fy, cx: cx, cy: cy,
                pixelBuffer: pixelBuffer,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
            
            points.append(ColoredPoint(position: worldPosition, color: color))
        }
        
        return points
    }
    
    /// Sample color using camera intrinsics (pinhole model)
    private func sampleColorFromIntrinsics(
        cameraPosition: SIMD3<Float>,
        fx: Float, fy: Float, cx: Float, cy: Float,
        pixelBuffer: CVPixelBuffer,
        imageWidth: Int,
        imageHeight: Int
    ) -> SIMD3<UInt8> {
        
        // Point must be in front of camera (negative Z in camera space)
        // Use a very small threshold to accept more points
        guard cameraPosition.z < -0.001 else {
            return SIMD3<UInt8>(180, 170, 160) // Neutral beige for behind-camera points
        }
        
        // Project to image plane using pinhole camera model
        let z = -cameraPosition.z
        
        // Project to pixel coordinates
        let u = (fx * cameraPosition.x / z) + cx
        let v = (fy * cameraPosition.y / z) + cy
        
        // Clamp to image bounds instead of rejecting
        let pixelX = max(0, min(imageWidth - 1, Int(u)))
        let pixelY = max(0, min(imageHeight - 1, Int(v)))
        
        // Sample pixel
        return samplePixel(pixelBuffer: pixelBuffer, x: pixelX, y: pixelY)
    }
    
    /// Read a pixel from the buffer
    private func samplePixel(pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8> {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Handle YCbCr (420v/420f) format - common for camera
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            return sampleYCbCr(pixelBuffer: pixelBuffer, x: x, y: y)
        }
        
        // Handle BGRA format
        if pixelFormat == kCVPixelFormatType_32BGRA {
            return sampleBGRA(pixelBuffer: pixelBuffer, x: x, y: y)
        }
        
        // Fallback gray
        return SIMD3<UInt8>(128, 128, 128)
    }
    
    /// Sample from YCbCr format
    private func sampleYCbCr(pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8> {
        // Y plane
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return SIMD3<UInt8>(128, 128, 128)
        }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let yValue = yPlane.advanced(by: y * yStride + x).assumingMemoryBound(to: UInt8.self).pointee
        
        // CbCr plane (half resolution)
        guard let cbcrPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return SIMD3<UInt8>(yValue, yValue, yValue)
        }
        let cbcrStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let cbcrX = (x / 2) * 2
        let cbcrY = y / 2
        let cbcrPtr = cbcrPlane.advanced(by: cbcrY * cbcrStride + cbcrX).assumingMemoryBound(to: UInt8.self)
        let cb = cbcrPtr.pointee
        let cr = cbcrPtr.advanced(by: 1).pointee
        
        // Convert YCbCr to RGB (BT.601 full range for better color accuracy)
        let yf = Float(yValue) - 16.0
        let cbf = Float(cb) - 128.0
        let crf = Float(cr) - 128.0
        
        // BT.601 coefficients with slight saturation boost
        var rf = 1.164 * yf + 1.596 * crf
        var gf = 1.164 * yf - 0.392 * cbf - 0.813 * crf
        var bf = 1.164 * yf + 2.017 * cbf
        
        // Slight saturation boost for more vivid colors
        let gray = 0.299 * rf + 0.587 * gf + 0.114 * bf
        let saturationBoost: Float = 1.15
        rf = gray + (rf - gray) * saturationBoost
        gf = gray + (gf - gray) * saturationBoost
        bf = gray + (bf - gray) * saturationBoost
        
        let r = UInt8(clamping: Int(max(0, min(255, rf))))
        let g = UInt8(clamping: Int(max(0, min(255, gf))))
        let b = UInt8(clamping: Int(max(0, min(255, bf))))
        
        return SIMD3<UInt8>(r, g, b)
    }
    
    /// Sample from BGRA format
    private func sampleBGRA(pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8> {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return SIMD3<UInt8>(128, 128, 128)
        }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = baseAddress.advanced(by: y * stride + x * 4).assumingMemoryBound(to: UInt8.self)
        
        let b = ptr.pointee
        let g = ptr.advanced(by: 1).pointee
        let r = ptr.advanced(by: 2).pointee
        
        return SIMD3<UInt8>(r, g, b)
    }
}
