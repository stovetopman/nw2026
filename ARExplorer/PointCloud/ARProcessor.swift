//
//  ARProcessor.swift
//  ARExplorer
//
//  Production-grade ARKit processor for LiDAR point cloud capture.
//  Uses temporal sync via didUpdate(frame:) for accurate color sampling.
//

import ARKit
import CoreVideo
import simd

// MARK: - AR Processor

/// Processes ARMeshAnchors with temporally-synchronized color sampling.
final class ARProcessor: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    @Published private(set) var isRunning = false
    
    /// The point manager to store extracted points
    weak var pointManager: PointManager?
    
    /// AR Session
    private var session: ARSession?
    
    /// Throttling: Process every 100ms to prevent thermal throttling
    private var lastProcessTime: TimeInterval = 0
    private let processInterval: TimeInterval = 0.1
    
    /// Version tracking: Skip unchanged meshes using buffer hash
    private var processedAnchorHashes: [UUID: Int] = [:]
    
    // MARK: - Public API
    
    /// Start AR session with mesh reconstruction
    func start(session: ARSession, pointManager: PointManager) {
        self.session = session
        self.pointManager = pointManager
        self.processedAnchorHashes.removeAll()
        session.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.frameSemantics = []
        
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
    
    /// Called every frame - provides temporally-synchronized color sampling
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let pointManager = pointManager, isRunning else { return }
        
        // Throttle to 10Hz processing
        let currentTime = frame.timestamp
        guard currentTime - lastProcessTime >= processInterval else { return }
        lastProcessTime = currentTime
        
        // Get display transform for accurate 3D→2D projection
        let pixelBuffer = frame.capturedImage
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        
        // displayTransform maps normalized image coords to display coords
        // We need the inverse to go from 3D projection to image sampling
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
        
        let displayTransform = frame.displayTransform(
            for: orientation,
            viewportSize: imageSize
        )
        
        // Collect anchors to process
        var anchorsToProcess: [(ARMeshAnchor, Int)] = []
        for anchor in frame.anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            
            let geometry = meshAnchor.geometry
            let bufferHash = computeBufferHash(geometry.vertices)
            let anchorID = meshAnchor.identifier
            
            if let lastHash = processedAnchorHashes[anchorID], lastHash == bufferHash {
                continue
            }
            processedAnchorHashes[anchorID] = bufferHash
            anchorsToProcess.append((meshAnchor, bufferHash))
        }
        
        guard !anchorsToProcess.isEmpty else { return }
        
        // Process on background queue to avoid blocking AR rendering
        let viewMatrix = frame.camera.viewMatrix(for: .portrait)
        let projectionMatrix = frame.camera.projectionMatrix(
            for: .portrait,
            viewportSize: imageSize,
            zNear: 0.001,
            zFar: 1000
        )
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var allPoints: [ColoredPoint] = []
            
            for (meshAnchor, _) in anchorsToProcess {
                let points = self.extractPoints(
                    from: meshAnchor,
                    pixelBuffer: pixelBuffer,
                    viewMatrix: viewMatrix,
                    projectionMatrix: projectionMatrix,
                    displayTransform: displayTransform,
                    imageSize: imageSize
                )
                allPoints.append(contentsOf: points)
            }
            
            DispatchQueue.main.async {
                pointManager.addPoints(allPoints)
            }
        }
    }
    
    /// Compute simple hash of vertex buffer for version tracking
    private func computeBufferHash(_ vertices: ARGeometrySource) -> Int {
        // Use vertex count + first/last vertex positions as quick hash
        let count = vertices.count
        guard count > 0 else { return 0 }
        
        let buffer = vertices.buffer.contents()
        let stride = vertices.stride
        
        // Sample first vertex
        let first = buffer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        
        // Sample last vertex
        let lastPtr = buffer.advanced(by: (count - 1) * stride)
        let last = lastPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
        
        // Combine into hash
        var hasher = Hasher()
        hasher.combine(count)
        hasher.combine(first.x)
        hasher.combine(first.y)
        hasher.combine(last.x)
        hasher.combine(last.y)
        return hasher.finalize()
    }
}

// MARK: - Point Extraction

extension ARProcessor {
    
    /// Extract colored points using camera intrinsics for accurate projection
    private func extractPoints(
        from meshAnchor: ARMeshAnchor,
        pixelBuffer: CVPixelBuffer,
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4,
        displayTransform: CGAffineTransform,
        imageSize: CGSize
    ) -> [ColoredPoint] {
        let geometry = meshAnchor.geometry
        let vertices = geometry.vertices
        let modelMatrix = meshAnchor.transform
        
        let vertexCount = vertices.count
        let vertexBuffer = vertices.buffer.contents()
        let vertexStride = vertices.stride
        
        let imageWidth = Int(imageSize.width)
        let imageHeight = Int(imageSize.height)
        
        // Lock pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        var points: [ColoredPoint] = []
        points.reserveCapacity(vertexCount)
        
        // Batch autoreleasepool every 1000 vertices for efficiency
        let batchSize = 1000
        for batchStart in stride(from: 0, to: vertexCount, by: batchSize) {
            autoreleasepool {
                let batchEnd = min(batchStart + batchSize, vertexCount)
                for i in batchStart..<batchEnd {
                    let vertexPointer = vertexBuffer.advanced(by: i * vertexStride)
                    let localPosition = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                    
                    // Transform to world space
                    let localPos4 = SIMD4<Float>(localPosition.x, localPosition.y, localPosition.z, 1.0)
                    let worldPos4 = modelMatrix * localPos4
                    let worldPosition = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)
                    
                    // Transform to camera space
                    let cameraPos4 = viewMatrix * worldPos4
                    let cameraPos = SIMD3<Float>(cameraPos4.x, cameraPos4.y, cameraPos4.z)
                    
                    // Skip points behind camera (camera looks down -Z)
                    guard cameraPos.z < -0.001 else {
                        points.append(ColoredPoint(position: worldPosition, color: SIMD3<UInt8>(180, 170, 160)))
                        continue
                    }
                    
                    // Project using projection matrix
                    let clipPos = projectionMatrix * cameraPos4
                    
                    // Normalized device coordinates (-1 to 1)
                    let ndcX = clipPos.x / clipPos.w
                    let ndcY = clipPos.y / clipPos.w
                    
                    // Convert NDC to normalized image coords (0 to 1)
                    // Note: Camera image is in landscape-left orientation
                    // NDC Y is up, image Y is down
                    let normX = (ndcX + 1.0) * 0.5
                    let normY = (1.0 - ndcY) * 0.5
                    
                    // Apply displayTransform to go from normalized display to normalized image
                    // displayTransform maps image -> display, so we need inverse
                    let invTransform = displayTransform.inverted()
                    let displayPoint = CGPoint(x: CGFloat(normX), y: CGFloat(normY))
                    let imagePoint = displayPoint.applying(invTransform)
                    
                    // Convert to pixel coordinates in the raw camera image
                    let pixelX = Int(imagePoint.x * CGFloat(imageWidth))
                    let pixelY = Int(imagePoint.y * CGFloat(imageHeight))
                    
                    // Clamp and sample
                    let clampedX = max(0, min(imageWidth - 1, pixelX))
                    let clampedY = max(0, min(imageHeight - 1, pixelY))
                    
                    // Clamp and sample
                    let clampedX = max(0, min(imageWidth - 1, pixelX))
                    let clampedY = max(0, min(imageHeight - 1, pixelY))
                    
                    let color = samplePixel(pixelBuffer: pixelBuffer, x: clampedX, y: clampedY)
                    points.append(ColoredPoint(position: worldPosition, color: color))
                }
            }
        }
        
        return points
    }
    
    /// Read a pixel from the buffer
    private func samplePixel(pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> SIMD3<UInt8> {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
           pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            return sampleYCbCr(pixelBuffer: pixelBuffer, x: x, y: y)
        }
        
        if pixelFormat == kCVPixelFormatType_32BGRA {
            return sampleBGRA(pixelBuffer: pixelBuffer, x: x, y: y)
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
