//
//  ColoredVertex.swift
//  ARExplorer - LiDAR Memory
//
//  Represents a 3D vertex with position, normal, and RGB color data.
//

import Foundation
import simd

/// A vertex structure containing position, normal, and color data
/// Uses SIMD types for efficient GPU-compatible memory layout
struct ColoredVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD4<Float>  // RGBA, normalized 0-1
    
    init(position: SIMD3<Float>, normal: SIMD3<Float> = .zero, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
        self.position = position
        self.normal = normal
        self.color = color
    }
    
    /// Memory stride for vertex buffer creation
    static var stride: Int {
        MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
    }
}

/// A complete colored mesh with vertices and triangle indices
struct ColoredMesh {
    var vertices: [ColoredVertex]
    var indices: [UInt32]
    var transform: simd_float4x4
    
    init(vertices: [ColoredVertex] = [], indices: [UInt32] = [], transform: simd_float4x4 = matrix_identity_float4x4) {
        self.vertices = vertices
        self.indices = indices
        self.transform = transform
    }
    
    /// Transform a local position to world space
    func worldPosition(for localPosition: SIMD3<Float>) -> SIMD3<Float> {
        let p4 = SIMD4<Float>(localPosition.x, localPosition.y, localPosition.z, 1.0)
        let world = transform * p4
        return SIMD3<Float>(world.x, world.y, world.z)
    }
}

/// Container for all mesh data collected during a scan session
final class ScanSession: ObservableObject {
    @Published var meshes: [UUID: ColoredMesh] = [:]
    @Published var scanProgress: Float = 0
    @Published var totalVertices: Int = 0
    @Published var totalFaces: Int = 0
    
    func updateMesh(id: UUID, mesh: ColoredMesh) {
        meshes[id] = mesh
        recalculateStats()
    }
    
    func removeMesh(id: UUID) {
        meshes.removeValue(forKey: id)
        recalculateStats()
    }
    
    func clear() {
        meshes.removeAll()
        totalVertices = 0
        totalFaces = 0
        scanProgress = 0
    }
    
    private func recalculateStats() {
        totalVertices = meshes.values.reduce(0) { $0 + $1.vertices.count }
        totalFaces = meshes.values.reduce(0) { $0 + $1.indices.count / 3 }
    }
}
