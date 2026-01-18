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
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let pointManager = pointManager else { return }
        guard let frame = session.currentFrame else { return }
        
        for anchor in anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            
            let points = extractPoints(from: meshAnchor, frame: frame)
            pointManager.addPoints(points)
        }
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let pointManager = pointManager else { return }
        guard let frame = session.currentFrame else { return }
        
        for anchor in anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            
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
        
        // Get display transform for correct UV mapping
        let displayTransform = frame.displayTransform(
            for: .portrait,
            viewportSize: CGSize(width: imageWidth, height: imageHeight)
        )
        
        let viewMatrix = frame.camera.viewMatrix(for: .portrait)
        let projectionMatrix = frame.camera.projectionMatrix(
            for: .portrait,
            viewportSize: CGSize(width: imageWidth, height: imageHeight),
            zNear: 0.001,
            zFar: 1000
        )
        
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
            
            // Sample color from camera image
            let color = sampleColor(
                worldPosition: worldPosition,
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                displayTransform: displayTransform,
                pixelBuffer: pixelBuffer,
                imageWidth: imageWidth,
                imageHeight: imageHeight
            )
            
            points.append(ColoredPoint(position: worldPosition, color: color))
        }
        
        return points
    }
    
    /// Sample color from camera image for a world position
    private func sampleColor(
        worldPosition: SIMD3<Float>,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        displayTransform: CGAffineTransform,
        pixelBuffer: CVPixelBuffer,
        imageWidth: Int,
        imageHeight: Int
    ) -> SIMD3<UInt8> {
        
        // Project world position to clip space
        let worldPos4 = SIMD4<Float>(worldPosition.x, worldPosition.y, worldPosition.z, 1.0)
        let viewPos = viewMatrix * worldPos4
        let clipPos = projectionMatrix * viewPos
        
        // Skip if behind camera
        guard clipPos.w > 0 else {
            return SIMD3<UInt8>(128, 128, 128)
        }
        
        // Normalized device coordinates (-1 to 1)
        let ndc = SIMD2<Float>(clipPos.x / clipPos.w, clipPos.y / clipPos.w)
        
        // Convert to 0-1 UV
        var uv = SIMD2<Float>((ndc.x + 1) * 0.5, (1 - ndc.y) * 0.5)
        
        // Apply display transform
        let transformedPoint = CGPoint(x: CGFloat(uv.x), y: CGFloat(uv.y))
            .applying(displayTransform)
        uv = SIMD2<Float>(Float(transformedPoint.x), Float(transformedPoint.y))
        
        // Clamp to valid range
        uv.x = max(0, min(1, uv.x))
        uv.y = max(0, min(1, uv.y))
        
        // Convert to pixel coordinates
        let pixelX = Int(uv.x * Float(imageWidth - 1))
        let pixelY = Int(uv.y * Float(imageHeight - 1))
        
        // Sample pixel (assuming BGRA or YCbCr format)
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
        
        // Convert YCbCr to RGB
        let yf = Float(yValue)
        let cbf = Float(cb) - 128
        let crf = Float(cr) - 128
        
        let r = UInt8(clamping: Int(yf + 1.402 * crf))
        let g = UInt8(clamping: Int(yf - 0.344 * cbf - 0.714 * crf))
        let b = UInt8(clamping: Int(yf + 1.772 * cbf))
        
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
