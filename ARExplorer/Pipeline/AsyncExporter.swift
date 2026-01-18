//
//  AsyncExporter.swift
//  ARExplorer - LiDAR Memory
//
//  MODULE 4: Asynchronous USDZ export with chunked MDLMesh building.
//  Decoupled from UI thread for non-blocking export operations.
//

import Foundation
import simd
import Combine
import ModelIO
import Metal
import MetalKit
import SceneKit

/// Asynchronous USDZ exporter with chunked processing
public final class AsyncExporter: AsyncExporterProtocol, @unchecked Sendable {
    
    // MARK: - Published State
    
    public private(set) var progress: Float = 0
    public private(set) var isExporting: Bool = false
    
    // MARK: - Publishers
    
    private let progressSubject = CurrentValueSubject<Float, Never>(0)
    
    public var progressPublisher: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    
    private let device: MTLDevice?
    private let allocator: MTKMeshBufferAllocator?
    private var exportTask: Task<ExportResult, Error>?
    private let exportQueue = DispatchQueue(label: "com.arexplorer.asyncexporter", qos: .userInitiated)
    
    // MARK: - Configuration
    
    /// Number of points to process per chunk
    public var defaultChunkSize: Int = 10000
    
    /// Whether to include vertex colors in export
    public var includeVertexColors: Bool = true
    
    /// Whether to include vertex normals in export
    public var includeVertexNormals: Bool = true
    
    // MARK: - Initialization
    
    public init() {
        device = MTLCreateSystemDefaultDevice()
        if let device = device {
            allocator = MTKMeshBufferAllocator(device: device)
        } else {
            allocator = nil
            print("⚠️ No Metal device available for mesh export")
        }
    }
    
    // MARK: - AsyncExporterProtocol
    
    public func exportToUSDZ(
        points: [LiDARPoint],
        indices: [UInt32],
        chunkSize: Int = 0
    ) async throws -> ExportResult {
        guard let allocator = allocator else {
            throw ExportError.noMetalDevice
        }
        
        guard !points.isEmpty else {
            throw ExportError.emptyData
        }
        
        let effectiveChunkSize = chunkSize > 0 ? chunkSize : defaultChunkSize
        
        // Cancel any existing export
        exportTask?.cancel()
        
        isExporting = true
        progress = 0
        progressSubject.send(0)
        
        let startTime = Date()
        
        // Create export task
        let task = Task { [weak self] () -> ExportResult in
            guard let self = self else { throw ExportError.cancelled }
            
            // Phase 1: Build vertex buffer in chunks (0% - 40%)
            let vertexData = try await self.buildVertexBufferInChunks(
                points: points,
                chunkSize: effectiveChunkSize,
                progressRange: (0.0, 0.4)
            )
            
            try Task.checkCancellation()
            
            // Phase 2: Build index buffer (40% - 50%)
            let indexData = self.buildIndexBuffer(indices: indices)
            await self.updateProgress(0.5)
            
            try Task.checkCancellation()
            
            // Phase 3: Create MDLMesh (50% - 70%)
            let mdlMesh = try self.createMDLMesh(
                vertexData: vertexData,
                indexData: indexData,
                vertexCount: points.count,
                indexCount: indices.count,
                allocator: allocator
            )
            await self.updateProgress(0.7)
            
            try Task.checkCancellation()
            
            // Phase 4: Export to USDZ (70% - 100%)
            let outputURL = try self.createOutputURL()
            try self.writeUSDZ(mesh: mdlMesh, to: outputURL, progressRange: (0.7, 1.0))
            
            await self.updateProgress(1.0)
            
            // Calculate result
            let duration = Date().timeIntervalSince(startTime)
            let fileSize = try self.getFileSize(at: outputURL)
            
            return ExportResult(
                url: outputURL,
                pointCount: points.count,
                faceCount: indices.count / 3,
                fileSize: fileSize,
                duration: duration
            )
        }
        
        exportTask = task
        
        do {
            let result = try await task.value
            isExporting = false
            print("✅ Export completed: \(result.url.lastPathComponent) (\(result.fileSize) bytes in \(String(format: "%.2f", result.duration))s)")
            return result
        } catch {
            isExporting = false
            progress = 0
            progressSubject.send(0)
            throw error
        }
    }
    
    public func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
        progress = 0
        progressSubject.send(0)
        print("🛑 Export cancelled")
    }
    
    // MARK: - Chunked Vertex Buffer Building
    
    private func buildVertexBufferInChunks(
        points: [LiDARPoint],
        chunkSize: Int,
        progressRange: (Float, Float)
    ) async throws -> Data {
        let totalPoints = points.count
        let floatsPerVertex = 10  // position (3) + normal (3) + color (4)
        let bytesPerVertex = floatsPerVertex * MemoryLayout<Float>.stride
        
        var vertexData = Data(capacity: totalPoints * bytesPerVertex)
        
        let chunks = stride(from: 0, to: totalPoints, by: chunkSize)
        let totalChunks = (totalPoints + chunkSize - 1) / chunkSize
        var processedChunks = 0
        
        for chunkStart in chunks {
            try Task.checkCancellation()
            
            let chunkEnd = min(chunkStart + chunkSize, totalPoints)
            let chunk = Array(points[chunkStart..<chunkEnd])
            
            // Process chunk
            var chunkFloats: [Float] = []
            chunkFloats.reserveCapacity(chunk.count * floatsPerVertex)
            
            for point in chunk {
                // Position
                chunkFloats.append(point.position.x)
                chunkFloats.append(point.position.y)
                chunkFloats.append(point.position.z)
                
                // Normal
                chunkFloats.append(point.normal.x)
                chunkFloats.append(point.normal.y)
                chunkFloats.append(point.normal.z)
                
                // Color
                chunkFloats.append(point.color.x)
                chunkFloats.append(point.color.y)
                chunkFloats.append(point.color.z)
                chunkFloats.append(point.color.w)
            }
            
            // Append chunk data
            chunkFloats.withUnsafeBytes { buffer in
                vertexData.append(contentsOf: buffer)
            }
            
            processedChunks += 1
            let chunkProgress = Float(processedChunks) / Float(totalChunks)
            let overallProgress = progressRange.0 + (progressRange.1 - progressRange.0) * chunkProgress
            await updateProgress(overallProgress)
            
            // Yield to prevent blocking
            await Task.yield()
        }
        
        return vertexData
    }
    
    private func buildIndexBuffer(indices: [UInt32]) -> Data {
        var data = Data(capacity: indices.count * MemoryLayout<UInt32>.stride)
        indices.withUnsafeBytes { buffer in
            data.append(contentsOf: buffer)
        }
        return data
    }
    
    // MARK: - MDLMesh Creation
    
    private func createMDLMesh(
        vertexData: Data,
        indexData: Data,
        vertexCount: Int,
        indexCount: Int,
        allocator: MTKMeshBufferAllocator
    ) throws -> MDLMesh {
        let floatsPerVertex = 10
        let vertexStride = floatsPerVertex * MemoryLayout<Float>.stride
        
        // Create buffers
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)
        
        // Create vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()
        
        // Position
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        
        // Normal
        vertexDescriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: 3 * MemoryLayout<Float>.stride,
            bufferIndex: 0
        )
        
        // Color
        vertexDescriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: .float4,
            offset: 6 * MemoryLayout<Float>.stride,
            bufferIndex: 0
        )
        
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: vertexStride)
        
        // Create material
        let material = MDLMaterial(name: "PointCloudMaterial", scatteringFunction: MDLScatteringFunction())
        
        // Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indexCount,
            indexType: .uInt32,
            geometryType: .triangles,
            material: material
        )
        
        // Create mesh
        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )
        
        return mesh
    }
    
    // MARK: - USDZ Writing
    
    private func writeUSDZ(mesh: MDLMesh, to url: URL, progressRange: (Float, Float)) throws {
        // Create asset
        let asset = MDLAsset()
        asset.add(mesh)
        
        // Convert via SceneKit for reliable USDZ export
        let scene = SCNScene(mdlAsset: asset)
        
        // Write to USDZ
        try scene.write(to: url, options: nil, delegate: nil) { [weak self] progress, error, stop in
            guard let self = self else { return }
            let overallProgress = progressRange.0 + (progressRange.1 - progressRange.0) * Float(progress)
            Task { @MainActor in
                self.progress = overallProgress
                self.progressSubject.send(overallProgress)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func createOutputURL() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let spacesDir = docs.appendingPathComponent("Spaces", isDirectory: true)
        
        try FileManager.default.createDirectory(at: spacesDir, withIntermediateDirectories: true)
        
        let sessionID = UUID().uuidString
        let sessionDir = spacesDir.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        return sessionDir.appendingPathComponent("scene.usdz")
    }
    
    private func getFileSize(at url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
    
    @MainActor
    private func updateProgress(_ value: Float) {
        progress = value
        progressSubject.send(value)
    }
}

// MARK: - Export Errors

public enum ExportError: Error, LocalizedError {
    case noMetalDevice
    case emptyData
    case cancelled
    case writeFailed(underlying: Error)
    
    public var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "No Metal device available for mesh generation"
        case .emptyData:
            return "No point data to export"
        case .cancelled:
            return "Export was cancelled"
        case .writeFailed(let error):
            return "Failed to write USDZ: \(error.localizedDescription)"
        }
    }
}

// MARK: - Convenience Extensions

extension AsyncExporter {
    
    /// Export from LiDARPoints with automatic triangulation
    public func exportPointCloud(_ points: [LiDARPoint]) async throws -> ExportResult {
        // For point cloud without mesh, create simple triangle fan or point sprites
        // This is a simplified version - real implementation would do Delaunay triangulation
        
        guard points.count >= 3 else {
            throw ExportError.emptyData
        }
        
        // Create simple indices (every 3 consecutive points form a triangle)
        var indices: [UInt32] = []
        for i in stride(from: 0, to: points.count - 2, by: 3) {
            indices.append(UInt32(i))
            indices.append(UInt32(i + 1))
            indices.append(UInt32(i + 2))
        }
        
        return try await exportToUSDZ(points: points, indices: indices)
    }
}
