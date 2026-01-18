import SceneKit
import RealityKit
import ARKit

/// A type alias for scanned point data with position and color
typealias ScannedPoint = (position: SIMD3<Float>, color: (r: UInt8, g: UInt8, b: UInt8))

/// Manages real-time visualization of point cloud data in RealityKit ARView
class PointCloudVisualizer {
    private weak var arView: ARView?
    private var pointAnchor: AnchorEntity?
    private let maxPoints = 50_000 // Limit points to prevent crashing
    
    // Buffers to hold data
    private var positions: [SIMD3<Float>] = []
    private var colors: [(r: UInt8, g: UInt8, b: UInt8)] = []
    
    // Update throttling - don't rebuild mesh every frame
    private var updateCounter = 0
    private let updateFrequency = 3  // Rebuild mesh every N batches
    
    init(arView: ARView) {
        self.arView = arView
        
        // Create anchor for point cloud
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "PointCloudAnchor"
        arView.scene.addAnchor(anchor)
        self.pointAnchor = anchor
        
        // Pre-allocate storage to avoid lag
        positions.reserveCapacity(maxPoints)
        colors.reserveCapacity(maxPoints)
    }
    
    func update(newPoints: [ScannedPoint]) {
        // Run UI updates on Main Thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. Add new data to our arrays (only every 16th point for visualization)
            for (index, point) in newPoints.enumerated() {
                if self.positions.count >= self.maxPoints { break }
                // Only visualize every 16th point (reduce by 15/16)
                if index % 16 != 0 { continue }
                self.positions.append(point.position)
                self.colors.append(point.color)
            }
            
            // 2. Throttle mesh rebuilds for performance
            self.updateCounter += 1
            if self.updateCounter % self.updateFrequency == 0 {
                self.rebuildPointCloudMesh()
            }
        }
    }
    
    private func rebuildPointCloudMesh() {
        guard let anchor = pointAnchor, !positions.isEmpty else { return }
        
        // Remove existing children
        anchor.children.removeAll()
        
        // Create point cloud as small spheres (RealityKit doesn't have native point primitives)
        // For performance, we'll create a single mesh with all points
        
        // Use a simpler approach: create sphere instances at each point location
        // But for large point counts, we batch them into groups
        let batchSize = 5000
        let pointsToRender = min(positions.count, maxPoints)
        
        for batchStart in stride(from: 0, to: pointsToRender, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, pointsToRender)
            createPointBatch(anchor: anchor, startIndex: batchStart, endIndex: batchEnd)
        }
    }
    
    private func createPointBatch(anchor: AnchorEntity, startIndex: Int, endIndex: Int) {
        // Create a mesh descriptor for points as tiny boxes
        var meshDescriptor = MeshDescriptor()
        
        var allPositions: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allIndices: [UInt32] = []
        
        let pointSize: Float = 0.003  // 3mm points
        
        for i in startIndex..<endIndex {
            let center = positions[i]
            let baseIndex = UInt32((i - startIndex) * 8)
            
            // Create a tiny cube (8 vertices, 12 triangles = 36 indices)
            let halfSize = pointSize / 2
            
            // 8 corners of the cube
            let corners: [SIMD3<Float>] = [
                center + SIMD3(-halfSize, -halfSize, -halfSize),
                center + SIMD3( halfSize, -halfSize, -halfSize),
                center + SIMD3( halfSize,  halfSize, -halfSize),
                center + SIMD3(-halfSize,  halfSize, -halfSize),
                center + SIMD3(-halfSize, -halfSize,  halfSize),
                center + SIMD3( halfSize, -halfSize,  halfSize),
                center + SIMD3( halfSize,  halfSize,  halfSize),
                center + SIMD3(-halfSize,  halfSize,  halfSize),
            ]
            
            allPositions.append(contentsOf: corners)
            
            // Simple normals (pointing outward from center)
            for corner in corners {
                let normal = normalize(corner - center)
                allNormals.append(normal)
            }
            
            // 12 triangles (2 per face, 6 faces)
            let cubeIndices: [UInt32] = [
                // Front
                0, 1, 2, 0, 2, 3,
                // Back  
                5, 4, 7, 5, 7, 6,
                // Top
                3, 2, 6, 3, 6, 7,
                // Bottom
                4, 5, 1, 4, 1, 0,
                // Right
                1, 5, 6, 1, 6, 2,
                // Left
                4, 0, 3, 4, 3, 7
            ]
            
            for idx in cubeIndices {
                allIndices.append(baseIndex + idx)
            }
        }
        
        meshDescriptor.positions = MeshBuffer(allPositions)
        meshDescriptor.normals = MeshBuffer(allNormals)
        meshDescriptor.primitives = .triangles(allIndices)
        
        do {
            let mesh = try MeshResource.generate(from: [meshDescriptor])
            
            // Create a simple unlit material
            var material = UnlitMaterial()
            material.color = .init(tint: .yellow.withAlphaComponent(0.9))
            
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "PointBatch_\(startIndex)"
            anchor.addChild(entity)
        } catch {
            print("❌ Failed to create point cloud mesh: \(error)")
        }
    }
    
    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.positions.removeAll(keepingCapacity: true)
            self?.colors.removeAll(keepingCapacity: true)
            self?.pointAnchor?.children.removeAll()
            self?.updateCounter = 0
        }
    }
    
    var currentPointCount: Int {
        return positions.count
    }
}

