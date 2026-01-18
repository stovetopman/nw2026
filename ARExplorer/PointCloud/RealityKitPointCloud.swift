//
//  RealityKitPointCloud.swift
//  ARExplorer
//
//  Reference implementation for RealityKit LowLevelMesh point cloud rendering.
//  This demonstrates the CORRECT way to create a point cloud with vertex colors.
//
//  Key requirements for LowLevelMesh with .point topology:
//  1. Use .uchar4Normalized for color (not .float3)
//  2. Set indexCount = 0 for point topology (or provide explicit index buffer)
//  3. Set indexType = .uint32 even though we don't use indices
//  4. Vertex buffer must be properly aligned
//

import RealityKit
import Metal
import simd

// MARK: - Vertex Layout (Packed for Metal alignment)

/// Vertex struct with proper Metal alignment for point clouds
struct PackedPointVertex {
    var position: SIMD3<Float>      // 12 bytes
    var padding: Float = 0          // 4 bytes (alignment)
    var color: SIMD4<UInt8>         // 4 bytes (RGBA as uchar4)
}

// MARK: - Point Cloud Mesh Builder

@available(iOS 18.0, *)
enum PointCloudMeshBuilder {
    
    /// Creates a RealityKit MeshResource from colored points
    /// - Returns: MeshResource or nil if creation fails
    static func buildMesh(from points: [ColoredPoint]) -> MeshResource? {
        guard !points.isEmpty else { return nil }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        
        let vertexCount = points.count
        
        do {
            // Define vertex attributes
            // CRITICAL: Use .uchar4Normalized for color, not .float3
            let attributes: [LowLevelMesh.Attribute] = [
                LowLevelMesh.Attribute(
                    semantic: .position,
                    format: .float3,
                    offset: 0
                ),
                LowLevelMesh.Attribute(
                    semantic: .color,
                    format: .uchar4Normalized,  // ✅ Correct format for vertex colors
                    offset: MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<Float>.stride
                )
            ]
            
            // Vertex layout
            let layout = LowLevelMesh.Layout(
                bufferIndex: 0,
                bufferStride: MemoryLayout<PackedPointVertex>.stride
            )
            
            // Create descriptor
            var descriptor = LowLevelMesh.Descriptor()
            descriptor.vertexAttributes = attributes
            descriptor.vertexLayouts = [layout]
            descriptor.vertexCapacity = vertexCount
            descriptor.indexCapacity = 0  // ✅ No index buffer for points
            
            // Create mesh
            let mesh = try LowLevelMesh(descriptor: descriptor)
            
            // Fill vertex buffer
            mesh.withUnsafeMutableBytes(bufferIndex: 0) { buffer in
                let vertices = buffer.bindMemory(to: PackedPointVertex.self)
                for i in 0..<vertexCount {
                    let point = points[i]
                    vertices[i] = PackedPointVertex(
                        position: point.position,
                        padding: 0,
                        color: SIMD4<UInt8>(point.color.x, point.color.y, point.color.z, 255)
                    )
                }
            }
            
            // Create part with point topology
            // CRITICAL: For .point topology, primitiveCount = vertex count
            let bounds = computeBounds(points: points)
            let part = LowLevelMesh.Part(
                indexCount: vertexCount,  // Number of points to draw
                topology: .point,
                bounds: bounds
            )
            mesh.parts.replaceAll([part])
            
            return try MeshResource(from: mesh)
            
        } catch {
            print("❌ LowLevelMesh creation failed: \(error)")
            return nil
        }
    }
    
    private static func computeBounds(points: [ColoredPoint]) -> BoundingBox {
        guard let first = points.first else {
            return BoundingBox(min: .zero, max: .zero)
        }
        
        var minP = first.position
        var maxP = first.position
        
        for point in points {
            minP = min(minP, point.position)
            maxP = max(maxP, point.position)
        }
        
        return BoundingBox(min: minP, max: maxP)
    }
}

// MARK: - Usage Example

/*
 Usage in a RealityView:
 
 RealityView { content in
     let anchor = AnchorEntity()
     content.add(anchor)
     
     if let mesh = PointCloudMeshBuilder.buildMesh(from: points) {
         var material = UnlitMaterial()
         material.color = .init(tint: .white)  // Tint multiplies with vertex color
         
         let entity = ModelEntity(mesh: mesh, materials: [material])
         anchor.addChild(entity)
     }
 }
 
 Notes:
 - UnlitMaterial with white tint preserves vertex colors
 - For larger point sizes, use a custom shader or splat rendering
 - RealityKit point size is fixed at 1 pixel by default
 - For variable point sizes, consider using small sphere meshes instead
*/
