//
//  MemoryManager.swift
//  ARExplorer - LiDAR Memory
//
//  Handles conversion of colored mesh data to USDZ for persistence.
//

import Foundation
import ModelIO
import Metal
import MetalKit
import SceneKit
import simd

/// Manages export of colored 3D meshes to USDZ format
final class MemoryManager: ObservableObject {
    
    // MARK: - Published State
    @Published private(set) var isExporting = false
    @Published private(set) var exportProgress: Float = 0
    @Published private(set) var lastExportedURL: URL?
    @Published private(set) var exportError: String?
    
    // MARK: - Private Properties
    private let device: MTLDevice?
    private let allocator: MTKMeshBufferAllocator?
    
    init() {
        device = MTLCreateSystemDefaultDevice()
        if let device = device {
            allocator = MTKMeshBufferAllocator(device: device)
        } else {
            allocator = nil
            print("⚠️ No Metal device available for mesh export")
        }
    }
    
    // MARK: - Export Methods
    
    /// Export colored meshes to a USDZ file
    @MainActor
    func exportToUSDZ(meshes: [UUID: ColoredMesh], completion: @escaping (Result<URL, Error>) -> Void) {
        guard let allocator = allocator else {
            let error = NSError(domain: "MemoryManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
            completion(.failure(error))
            return
        }
        
        guard !meshes.isEmpty else {
            let error = NSError(domain: "MemoryManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No mesh data to export"])
            completion(.failure(error))
            return
        }
        
        isExporting = true
        exportProgress = 0
        exportError = nil
        
        Task.detached { [weak self] in
            do {
                let url = try await self?.performExport(meshes: meshes, allocator: allocator)
                await MainActor.run {
                    self?.isExporting = false
                    self?.exportProgress = 1.0
                    if let url = url {
                        self?.lastExportedURL = url
                        completion(.success(url))
                    }
                }
            } catch {
                await MainActor.run {
                    self?.isExporting = false
                    self?.exportError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Perform the actual export on a background thread
    private func performExport(meshes: [UUID: ColoredMesh], allocator: MTKMeshBufferAllocator) async throws -> URL {
        let meshArray = Array(meshes.values)
        let totalMeshes = Float(meshArray.count)
        
        // Create MDLAsset
        let asset = MDLAsset()
        
        for (index, coloredMesh) in meshArray.enumerated() {
            let mdlMesh = try createMDLMesh(from: coloredMesh, allocator: allocator)
            asset.add(mdlMesh)
            
            await MainActor.run {
                self.exportProgress = Float(index + 1) / totalMeshes * 0.7
            }
        }
        
        // Create output URL
        let outputURL = try createOutputURL()
        
        await MainActor.run {
            self.exportProgress = 0.8
        }
        
        // Export via SceneKit (more reliable USDZ export)
        let scnScene = SCNScene(mdlAsset: asset)
        
        // Write to USDZ
        try scnScene.write(to: outputURL, options: nil, delegate: nil, progressHandler: { progress, error, stop in
            Task { @MainActor in
                self.exportProgress = 0.8 + Float(progress) * 0.2
            }
        })
        
        // Verify file was created
        let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        
        print("✅ Exported USDZ to: \(outputURL.path)")
        print("   File size: \(fileSize) bytes")
        
        return outputURL
    }
    
    /// Create an MDLMesh from ColoredMesh with vertex colors
    private func createMDLMesh(from coloredMesh: ColoredMesh, allocator: MTKMeshBufferAllocator) throws -> MDLMesh {
        let vertices = coloredMesh.vertices
        let indices = coloredMesh.indices
        
        guard !vertices.isEmpty && !indices.isEmpty else {
            throw NSError(domain: "MemoryManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Empty mesh data"])
        }
        
        // Create interleaved vertex data: position (float3) + normal (float3) + color (float4)
        // Layout: [pos.x, pos.y, pos.z, norm.x, norm.y, norm.z, r, g, b, a] per vertex
        let floatsPerVertex = 10  // 3 + 3 + 4
        var vertexData = [Float]()
        vertexData.reserveCapacity(vertices.count * floatsPerVertex)
        
        for vertex in vertices {
            // Position
            vertexData.append(vertex.position.x)
            vertexData.append(vertex.position.y)
            vertexData.append(vertex.position.z)
            // Normal
            vertexData.append(vertex.normal.x)
            vertexData.append(vertex.normal.y)
            vertexData.append(vertex.normal.z)
            // Color (RGBA)
            vertexData.append(vertex.color.x)
            vertexData.append(vertex.color.y)
            vertexData.append(vertex.color.z)
            vertexData.append(vertex.color.w)
        }
        
        let vertexStride = floatsPerVertex * MemoryLayout<Float>.stride
        let vertexDataBytes = Data(bytes: vertexData, count: vertexData.count * MemoryLayout<Float>.stride)
        let vertexBuffer = allocator.newBuffer(with: vertexDataBytes, type: .vertex)
        
        // Create index buffer
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.stride)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)
        
        // Create vertex descriptor with position, normal, and color
        let vertexDescriptor = MDLVertexDescriptor()
        
        // Position attribute
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        
        // Normal attribute
        vertexDescriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: 3 * MemoryLayout<Float>.stride,
            bufferIndex: 0
        )
        
        // Color attribute
        vertexDescriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: .float4,
            offset: 6 * MemoryLayout<Float>.stride,
            bufferIndex: 0
        )
        
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: vertexStride)
        
        // Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: createDefaultMaterial()
        )
        
        // Create MDLMesh
        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )
        
        // Apply world transform
        mdlMesh.transform = MDLTransform(matrix: coloredMesh.transform)
        
        return mdlMesh
    }
    
    /// Create a default material for the mesh
    private func createDefaultMaterial() -> MDLMaterial {
        let material = MDLMaterial(name: "VertexColorMaterial", scatteringFunction: MDLScatteringFunction())
        
        // Set base color to white - vertex colors will modulate
        let baseColor = MDLMaterialProperty(name: "baseColor", semantic: .baseColor)
        baseColor.color = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        material.setProperty(baseColor)
        
        return material
    }
    
    /// Create a unique output URL in Documents/Spaces
    private func createOutputURL() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let spacesDir = docs.appendingPathComponent("Spaces", isDirectory: true)
        
        // Create spaces directory if needed
        try FileManager.default.createDirectory(at: spacesDir, withIntermediateDirectories: true)
        
        // Create unique folder for this export
        let sessionID = UUID().uuidString
        let sessionDir = spacesDir.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        return sessionDir.appendingPathComponent("scene.usdz")
    }
    
    // MARK: - Utility Methods
    
    /// List all saved memory files
    static func listSavedMemories() -> [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let spacesDir = docs.appendingPathComponent("Spaces", isDirectory: true)
        
        guard FileManager.default.fileExists(atPath: spacesDir.path) else { return [] }
        
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: spacesDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        // Find all USDZ files
        var usdzFiles: [URL] = []
        for folder in folders {
            let usdzPath = folder.appendingPathComponent("scene.usdz")
            if FileManager.default.fileExists(atPath: usdzPath.path) {
                usdzFiles.append(usdzPath)
            }
        }
        
        // Sort by modification date (newest first)
        return usdzFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return date1 > date2
        }
    }
    
    /// Get the most recently saved memory
    static func latestMemory() -> URL? {
        listSavedMemories().first
    }
    
    /// Delete a saved memory
    static func deleteMemory(at url: URL) throws {
        let folderURL = url.deletingLastPathComponent()
        try FileManager.default.removeItem(at: folderURL)
    }
}
