//
//  ARProcessor.swift
//  ARExplorer
//
//  High-resolution LiDAR point cloud capture using depth buffer.
//  Samples per-pixel depth and color for dense point clouds.
//

import ARKit
import CoreVideo
import simd
import Accelerate

// MARK: - AR Processor

/// Processes depth buffer with aligned color sampling for dense point clouds.
final class ARProcessor: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var isRunning = false
    
    /// The point manager to store extracted points
    weak var pointManager: PointManager?
    
    /// AR Session
    private var session: ARSession?
    
    /// Throttling: Process every 50ms (20Hz) for higher density
    private var lastProcessTime: TimeInterval = 0
    private let processInterval: TimeInterval = 0.05
    
    /// Depth sampling stride (1 = every pixel, 2 = every other pixel, etc.)
    /// Lower = more points but slower. 2 gives good balance.
    private let depthStride: Int = 2
    
    // MARK: - Public API
    
    /// Start AR session with depth sensing
    func start(session: ARSession, pointManager: PointManager) {
        self.session = session
        self.pointManager = pointManager
        session.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh  // Keep mesh for scene understanding overlay
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]  // Enable depth
        
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
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
    
    /// Called every frame - extracts points from depth buffer with aligned color
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let pointManager = pointManager, isRunning else { return }
        
        // Throttle processing
        let currentTime = frame.timestamp
        guard currentTime - lastProcessTime >= processInterval else { return }
        lastProcessTime = currentTime
        
        // Get smoothed depth for better quality (falls back to sceneDepth)
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        
        let depthBuffer = depthData.depthMap
        let colorBuffer = frame.capturedImage
        let camera = frame.camera
        let cameraTransform = camera.transform
        
        // Get intrinsics for unprojection
        let intrinsics = camera.intrinsics
        
        // Depth buffer dimensions
        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        
        // Color buffer dimensions
        let colorWidth = CVPixelBufferGetWidth(colorBuffer)
        let colorHeight = CVPixelBufferGetHeight(colorBuffer)
        
        // Scale factors: depth is lower res than color
        let scaleX = Float(colorWidth) / Float(depthWidth)
        let scaleY = Float(colorHeight) / Float(depthHeight)
        
        // Process on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let points = self.extractPointsFromDepth(
                depthBuffer: depthBuffer,
                colorBuffer: colorBuffer,
                intrinsics: intrinsics,
                cameraTransform: cameraTransform,
                depthWidth: depthWidth,
                depthHeight: depthHeight,
                colorWidth: colorWidth,
                colorHeight: colorHeight,
                scaleX: scaleX,
                scaleY: scaleY
            )
            
            DispatchQueue.main.async {
                pointManager.addPoints(points)
            }
        }
    }
}

// MARK: - Depth-Based Point Extraction

extension ARProcessor {
    
    /// Extract dense point cloud from depth buffer with aligned color sampling
    private func extractPointsFromDepth(
        depthBuffer: CVPixelBuffer,
        colorBuffer: CVPixelBuffer,
        intrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        depthWidth: Int,
        depthHeight: Int,
        colorWidth: Int,
        colorHeight: Int,
        scaleX: Float,
        scaleY: Float
    ) -> [ColoredPoint] {
        
        // Lock both buffers
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(colorBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(colorBuffer, .readOnly)
        }
        
        guard let depthBase = CVPixelBufferGetBaseAddress(depthBuffer) else { return [] }
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        
        // Camera intrinsics (for depth buffer resolution)
        // Intrinsics are for full-res image, scale down for depth
        let fx = intrinsics[0][0] / scaleX
        let fy = intrinsics[1][1] / scaleY
        let cx = intrinsics[2][0] / scaleX
        let cy = intrinsics[2][1] / scaleY
        
        // Estimate point count for capacity
        let estimatedPoints = (depthWidth / depthStride) * (depthHeight / depthStride)
        var points: [ColoredPoint] = []
        points.reserveCapacity(estimatedPoints)
        
        // Process in batches for memory efficiency
        let batchSize = 2000
        var batchCount = 0
        
        for v in stride(from: 0, to: depthHeight, by: depthStride) {
            autoreleasepool {
                for u in stride(from: 0, to: depthWidth, by: depthStride) {
                    // Read depth value (Float32)
                    let depthPtr = depthBase.advanced(by: v * depthBytesPerRow + u * 4)
                    let depth = depthPtr.assumingMemoryBound(to: Float32.self).pointee
                    
                    // Skip invalid depth (0 or too far)
                    guard depth > 0.1 && depth < 5.0 else { continue }
                    
                    // Unproject to camera space
                    // Camera looks down -Z, so we negate depth
                    let xCam = (Float(u) - cx) * depth / fx
                    let yCam = (Float(v) - cy) * depth / fy
                    let zCam = -depth  // Negative because camera looks down -Z
                    
                    // Transform to world space
                    let camPoint = SIMD4<Float>(xCam, yCam, zCam, 1.0)
                    let worldPoint = cameraTransform * camPoint
                    let worldPos = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
                    
                    // Map depth pixel to color pixel
                    // Depth image is rotated 90° CCW relative to color in portrait
                    // Depth (u,v) -> Color (v * scaleY, (depthWidth - 1 - u) * scaleX)
                    let colorU = Int(Float(v) * scaleY)
                    let colorV = Int(Float(depthWidth - 1 - u) * scaleX)
                    
                    let clampedColorU = max(0, min(colorWidth - 1, colorU))
                    let clampedColorV = max(0, min(colorHeight - 1, colorV))
                    
                    // Sample color
                    let color = sampleColorBuffer(colorBuffer, x: clampedColorU, y: clampedColorV)
                    
                    points.append(ColoredPoint(position: worldPos, color: color))
                    batchCount += 1
                }
            }
        }
        
        return points
    }
    
    /// Sample color from the camera buffer
    private func sampleColorBuffer(_ buffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8> {
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            return sampleYCbCr(pixelBuffer: buffer, x: x, y: y)
        }
        
        if pixelFormat == kCVPixelFormatType_32BGRA {
            return sampleBGRA(pixelBuffer: buffer, x: x, y: y)
        }
        
        return SIMD3<UInt8>(128, 128, 128)
    }
    
    /// Sample from YCbCr format with BT.601 conversion
    private func sampleYCbCr(pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8> {
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let cbcrPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return SIMD3<UInt8>(128, 128, 128)
        }
        
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let cbcrStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        
        let yValue = yPlane.advanced(by: y * yStride + x).assumingMemoryBound(to: UInt8.self).pointee
        
        let cbcrX = (x / 2) * 2
        let cbcrY = y / 2
        let cbcrPtr = cbcrPlane.advanced(by: cbcrY * cbcrStride + cbcrX).assumingMemoryBound(to: UInt8.self)
        let cb = cbcrPtr.pointee
        let cr = cbcrPtr.advanced(by: 1).pointee
        
        // BT.601 conversion with saturation boost
        let yf = Float(yValue) - 16.0
        let cbf = Float(cb) - 128.0
        let crf = Float(cr) - 128.0
        
        var rf = 1.164 * yf + 1.596 * crf
        var gf = 1.164 * yf - 0.392 * cbf - 0.813 * crf
        var bf = 1.164 * yf + 2.017 * cbf
        
        // Saturation boost for vivid colors
        let gray = 0.299 * rf + 0.587 * gf + 0.114 * bf
        let boost: Float = 1.2
        rf = gray + (rf - gray) * boost
        gf = gray + (gf - gray) * boost
        bf = gray + (bf - gray) * boost
        
        return SIMD3<UInt8>(
            UInt8(clamping: Int(max(0, min(255, rf)))),
            UInt8(clamping: Int(max(0, min(255, gf)))),
            UInt8(clamping: Int(max(0, min(255, bf))))
        )
    }
    
    /// Sample from BGRA format
    private func sampleBGRA(pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8> {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return SIMD3<UInt8>(128, 128, 128)
        }
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = baseAddress.advanced(by: y * stride + x * 4).assumingMemoryBound(to: UInt8.self)
        return SIMD3<UInt8>(ptr.advanced(by: 2).pointee, ptr.advanced(by: 1).pointee, ptr.pointee)
    }
}
