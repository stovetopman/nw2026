//
//  ScanningEngine.swift
//  ARExplorer - LiDAR Memory
//
//  ARKit scanning engine that captures colored 3D meshes from LiDAR + camera.
//

import Foundation
import ARKit
import RealityKit
import Combine
import CoreVideo
import Accelerate

/// Scanning engine that captures colored 3D mesh data using LiDAR and camera
@MainActor
final class ScanningEngine: NSObject, ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var isScanning = false
    @Published private(set) var scanSession = ScanSession()
    @Published private(set) var currentFrame: ARFrame?
    
    // MARK: - Private Properties
    private var arView: ARView?
    private var frameCounter: Int = 0
    private let colorUpdateInterval = 10  // Only update colors every 10th frame
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    
    // Cache for pixel buffer processing
    private var cachedPixelData: [UInt8]?
    private var cachedImageWidth: Int = 0
    private var cachedImageHeight: Int = 0
    
    // MARK: - Configuration
    
    func configure(arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        
        // Show mesh wireframe during scanning
        arView.debugOptions = [.showSceneUnderstanding]
    }
    
    func startScanning() {
        guard let arView = arView else { return }
        
        let config = ARWorldTrackingConfiguration()
        
        // Enable LiDAR mesh with classification
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        } else {
            print("⚠️ Scene reconstruction not supported on this device")
        }
        
        config.environmentTexturing = .automatic
        config.frameSemantics = [.sceneDepth]
        
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        scanSession.clear()
        meshAnchors.removeAll()
        frameCounter = 0
        isScanning = true
        
        print("✅ Scanning started with LiDAR mesh + classification")
    }
    
    func stopScanning() {
        arView?.session.pause()
        isScanning = false
        print("⏹ Scanning stopped. Total meshes: \(meshAnchors.count)")
    }
    
    // MARK: - Mesh Coloring
    
    /// Project a 3D world point into the camera image and sample its color
    private func sampleColor(
        worldPosition: SIMD3<Float>,
        frame: ARFrame,
        pixelData: [UInt8],
        imageWidth: Int,
        imageHeight: Int
    ) -> SIMD4<Float> {
        
        let camera = frame.camera
        
        // Transform world position to camera space
        let viewMatrix = camera.viewMatrix(for: .landscapeRight)
        let projectionMatrix = camera.projectionMatrix(
            for: .landscapeRight,
            viewportSize: CGSize(width: imageWidth, height: imageHeight),
            zNear: 0.001,
            zFar: 100
        )
        
        let worldPos4 = SIMD4<Float>(worldPosition.x, worldPosition.y, worldPosition.z, 1.0)
        let cameraPos = viewMatrix * worldPos4
        
        // Skip points behind camera
        if cameraPos.z > 0 { return SIMD4<Float>(0.7, 0.7, 0.7, 1.0) }
        
        let clipPos = projectionMatrix * cameraPos
        
        // Perspective divide
        guard clipPos.w != 0 else { return SIMD4<Float>(0.7, 0.7, 0.7, 1.0) }
        let ndcPos = SIMD3<Float>(clipPos.x / clipPos.w, clipPos.y / clipPos.w, clipPos.z / clipPos.w)
        
        // NDC to pixel coordinates (NDC is -1 to 1)
        let u = (ndcPos.x + 1.0) * 0.5
        let v = (1.0 - ndcPos.y) * 0.5  // Flip Y
        
        let pixelX = Int(u * Float(imageWidth))
        let pixelY = Int(v * Float(imageHeight))
        
        // Bounds check
        guard pixelX >= 0 && pixelX < imageWidth && pixelY >= 0 && pixelY < imageHeight else {
            return SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
        }
        
        // Sample BGRA pixel (CVPixelBuffer is typically BGRA)
        let bytesPerPixel = 4
        let bytesPerRow = imageWidth * bytesPerPixel
        let offset = pixelY * bytesPerRow + pixelX * bytesPerPixel
        
        guard offset + 3 < pixelData.count else {
            return SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
        }
        
        let b = Float(pixelData[offset]) / 255.0
        let g = Float(pixelData[offset + 1]) / 255.0
        let r = Float(pixelData[offset + 2]) / 255.0
        
        return SIMD4<Float>(r, g, b, 1.0)
    }
    
    /// Extract pixel data from CVPixelBuffer
    private func extractPixelData(from pixelBuffer: CVPixelBuffer) -> (data: [UInt8], width: Int, height: Int)? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        
        // Convert YUV to RGB if needed, or copy directly if BGRA
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        if pixelFormat == kCVPixelFormatType_32BGRA {
            let data = [UInt8](UnsafeBufferPointer(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: bytesPerRow * height
            ))
            return (data, width, height)
        }
        
        // For YUV formats, we need conversion - simplified approach using CIImage
        return nil
    }
    
    /// Convert YUV pixel buffer to BGRA data
    private func convertToBGRA(pixelBuffer: CVPixelBuffer) -> (data: [UInt8], width: Int, height: Int)? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var bgraBuffer = [UInt8](repeating: 0, count: width * height * 4)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        context.render(
            ciImage,
            toBitmap: &bgraBuffer,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .BGRA8,
            colorSpace: colorSpace
        )
        
        return (bgraBuffer, width, height)
    }
    
    /// Process mesh anchor and apply vertex colors from camera
    private func processMeshAnchor(_ anchor: ARMeshAnchor, frame: ARFrame) -> ColoredMesh {
        let geometry = anchor.geometry
        let vertexCount = geometry.vertices.count
        let transform = anchor.transform
        
        // Read vertex positions
        var vertices: [ColoredVertex] = []
        vertices.reserveCapacity(vertexCount)
        
        let vertexBuffer = geometry.vertices.buffer
        let vertexOffset = geometry.vertices.offset
        let vertexStride = geometry.vertices.stride
        let vertexPtr = vertexBuffer.contents().advanced(by: vertexOffset)
        
        // Read normals if available
        let normalBuffer = geometry.normals.buffer
        let normalOffset = geometry.normals.offset
        let normalStride = geometry.normals.stride
        let normalPtr = normalBuffer.contents().advanced(by: normalOffset)
        
        // Get pixel data for color sampling (use cached or convert new)
        let pixelData: [UInt8]
        let imageWidth: Int
        let imageHeight: Int
        
        if let extracted = extractPixelData(from: frame.capturedImage) {
            pixelData = extracted.data
            imageWidth = extracted.width
            imageHeight = extracted.height
        } else if let converted = convertToBGRA(pixelBuffer: frame.capturedImage) {
            pixelData = converted.data
            imageWidth = converted.width
            imageHeight = converted.height
        } else {
            // Fallback: gray vertices
            pixelData = []
            imageWidth = 0
            imageHeight = 0
        }
        
        for i in 0..<vertexCount {
            // Read position
            let posPtr = vertexPtr.advanced(by: i * vertexStride)
            let position = posPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            
            // Read normal
            let nrmPtr = normalPtr.advanced(by: i * normalStride)
            let normal = nrmPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            
            // Transform to world space for color sampling
            let worldPos4 = transform * SIMD4<Float>(position.x, position.y, position.z, 1.0)
            let worldPosition = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)
            
            // Sample color from camera image
            let color: SIMD4<Float>
            if !pixelData.isEmpty {
                color = sampleColor(
                    worldPosition: worldPosition,
                    frame: frame,
                    pixelData: pixelData,
                    imageWidth: imageWidth,
                    imageHeight: imageHeight
                )
            } else {
                color = SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
            }
            
            vertices.append(ColoredVertex(position: position, normal: normal, color: color))
        }
        
        // Read indices
        let indices = readIndices(from: geometry.faces)
        
        return ColoredMesh(vertices: vertices, indices: indices, transform: transform)
    }
    
    /// Read triangle indices from ARGeometryElement
    private func readIndices(from faces: ARGeometryElement) -> [UInt32] {
        let faceCount = faces.count
        let bytesPerIndex = faces.bytesPerIndex
        let ptr = faces.buffer.contents()
        
        var indices: [UInt32] = []
        indices.reserveCapacity(faceCount * 3)
        
        for i in 0..<(faceCount * 3) {
            if bytesPerIndex == 2 {
                let value = ptr.load(fromByteOffset: i * 2, as: UInt16.self)
                indices.append(UInt32(value))
            } else {
                let value = ptr.load(fromByteOffset: i * 4, as: UInt32.self)
                indices.append(value)
            }
        }
        
        return indices
    }
}

// MARK: - ARSessionDelegate

extension ScanningEngine: ARSessionDelegate {
    
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    meshAnchors[meshAnchor.identifier] = meshAnchor
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    meshAnchors[meshAnchor.identifier] = meshAnchor
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    meshAnchors.removeValue(forKey: meshAnchor.identifier)
                    scanSession.removeMesh(id: meshAnchor.identifier)
                }
            }
        }
    }
    
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            currentFrame = frame
            frameCounter += 1
            
            // Only update vertex colors every Nth frame to save CPU
            guard frameCounter % colorUpdateInterval == 0 else { return }
            
            // Process all mesh anchors with current frame colors
            for (id, anchor) in meshAnchors {
                let coloredMesh = processMeshAnchor(anchor, frame: frame)
                scanSession.updateMesh(id: id, mesh: coloredMesh)
            }
        }
    }
}

// MARK: - Mesh Anchor Access

extension ScanningEngine {
    
    /// Get all current mesh anchors for export
    var allMeshAnchors: [UUID: ARMeshAnchor] {
        meshAnchors
    }
    
    /// Get all colored meshes
    var allColoredMeshes: [UUID: ColoredMesh] {
        scanSession.meshes
    }
}
