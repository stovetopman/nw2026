//
//  ARMeshAnchor+ModelIO.swift
//  ARExplorer - LiDAR Memory
//
//  Extension for converting ARMeshAnchor to MDLMesh with vertex color support.
//

import ARKit
import ModelIO
import Metal
import MetalKit
import simd

extension ARMeshAnchor {
    
    /// Convert ARMeshAnchor to MDLMesh (position only, no colors)
    func toMDLMesh(device: MTLDevice) -> MDLMesh {
        let g = self.geometry
        let allocator = MTKMeshBufferAllocator(device: device)

        // ---- Vertices (positions) ----
        let vBuffer = g.vertices.buffer
        let vOffset = g.vertices.offset
        let vStride = g.vertices.stride
        let vCount  = g.vertices.count
        let vLength = vCount * vStride

        let vPtr = vBuffer.contents().advanced(by: vOffset)
        let vData = Data(bytes: vPtr, count: vLength)
        let mdlVertexBuffer = allocator.newBuffer(with: vData, type: .vertex)

        // ---- Indices (faces) ----
        let fBuffer = g.faces.buffer
        let faceCount = g.faces.count
        let bpi = g.faces.bytesPerIndex

        // ARMesh faces are triangles → 3 indices per face
        let indexCount = faceCount * 3
        let fLength = indexCount * bpi

        let fPtr = fBuffer.contents()
        let fData = Data(bytes: fPtr, count: fLength)
        let mdlIndexBuffer = allocator.newBuffer(with: fData, type: .index)

        // ---- Vertex descriptor (position only) ----
        let vdesc = MDLVertexDescriptor()
        vdesc.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vdesc.layouts[0] = MDLVertexBufferLayout(stride: vStride)

        let submesh = MDLSubmesh(
            indexBuffer: mdlIndexBuffer,
            indexCount: indexCount,
            indexType: (bpi == 2) ? .uInt16 : .uInt32,
            geometryType: .triangles,
            material: nil
        )

        let mdlMesh = MDLMesh(
            vertexBuffer: mdlVertexBuffer,
            vertexCount: vCount,
            descriptor: vdesc,
            submeshes: [submesh]
        )

        // Put each chunk into world space
        mdlMesh.transform = MDLTransform(matrix: self.transform)
        return mdlMesh
    }
    
    /// Convert ARMeshAnchor to MDLMesh with vertex colors from ColoredMesh
    func toColoredMDLMesh(device: MTLDevice, coloredMesh: ColoredMesh) -> MDLMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let vertices = coloredMesh.vertices
        let indices = coloredMesh.indices
        
        // Create interleaved vertex data: position (float3) + normal (float3) + color (float4)
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
        
        // Create material that uses vertex colors
        let material = MDLMaterial(name: "VertexColorMaterial", scatteringFunction: MDLScatteringFunction())
        let baseColor = MDLMaterialProperty(name: "baseColor", semantic: .baseColor)
        baseColor.color = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        material.setProperty(baseColor)
        
        // Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: material
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
    
    /// Read triangle indices from geometry
    func readTriangleIndices() -> [UInt32] {
        let faces = geometry.faces
        let triCount = faces.count
        let bpi = faces.bytesPerIndex
        let ptr = faces.buffer.contents()
        
        var indices: [UInt32] = []
        indices.reserveCapacity(triCount * 3)
        
        for i in 0..<(triCount * 3) {
            if bpi == 2 {
                let v = ptr.load(fromByteOffset: i * 2, as: UInt16.self)
                indices.append(UInt32(v))
            } else {
                let v = ptr.load(fromByteOffset: i * 4, as: UInt32.self)
                indices.append(v)
            }
        }
        
        return indices
    }
    
    /// Read vertex positions from geometry
    func readVertexPositions() -> [SIMD3<Float>] {
        let vertices = geometry.vertices
        let vCount = vertices.count
        let vStride = vertices.stride
        let vOffset = vertices.offset
        let ptr = vertices.buffer.contents().advanced(by: vOffset)
        
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(vCount)
        
        for i in 0..<vCount {
            let posPtr = ptr.advanced(by: i * vStride)
            let position = posPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            positions.append(position)
        }
        
        return positions
    }
    
    /// Read vertex normals from geometry
    func readVertexNormals() -> [SIMD3<Float>] {
        let normals = geometry.normals
        let nCount = normals.count
        let nStride = normals.stride
        let nOffset = normals.offset
        let ptr = normals.buffer.contents().advanced(by: nOffset)
        
        var normalVectors: [SIMD3<Float>] = []
        normalVectors.reserveCapacity(nCount)
        
        for i in 0..<nCount {
            let nrmPtr = ptr.advanced(by: i * nStride)
            let normal = nrmPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            normalVectors.append(normal)
        }
        
        return normalVectors
    }
}
