import ARKit
import ModelIO
import Metal
import MetalKit

extension ARMeshAnchor {
    func toMDLMesh(device: MTLDevice) -> MDLMesh {
        let g = self.geometry
        let allocator = MTKMeshBufferAllocator(device: device)

        // ---- Vertices (positions) ----
        let vBuffer = g.vertices.buffer
        let vOffset = g.vertices.offset          // ✅ exists
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

        let fPtr = fBuffer.contents()            // ✅ no offset API, start at 0
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
}
