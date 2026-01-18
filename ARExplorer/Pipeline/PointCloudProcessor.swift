//
//  PointCloudProcessor.swift
//  ARExplorer - LiDAR Memory
//
//  MODULE 2: Streaming voxel grid filter for point cloud data reduction.
//  Implements spatial hashing for O(1) point insertion and elevation slicing.
//

import Foundation
import simd
import Combine

/// Voxel grid-based point cloud processor with streaming filter
public final class PointCloudProcessor: PointCloudProcessorProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    public var voxelSize: Float {
        didSet {
            if voxelSize != oldValue {
                recalculateVoxelGrid()
            }
        }
    }
    
    // MARK: - Published State
    
    public private(set) var voxelCount: Int = 0
    public private(set) var totalPointsProcessed: Int = 0
    
    // MARK: - Publishers
    
    private let filteredPointsSubject = PassthroughSubject<PointBatch, Never>()
    
    public var filteredPointsPublisher: AnyPublisher<PointBatch, Never> {
        filteredPointsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Voxel Grid Storage
    
    /// Voxel key for spatial hashing
    private struct VoxelKey: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
        
        init(position: SIMD3<Float>, voxelSize: Float) {
            x = Int32(floor(position.x / voxelSize))
            y = Int32(floor(position.y / voxelSize))
            z = Int32(floor(position.z / voxelSize))
        }
    }
    
    /// Voxel cell containing accumulated point data
    private struct VoxelCell {
        var point: LiDARPoint
        var sampleCount: Int
        var colorAccumulator: SIMD4<Float>
        var normalAccumulator: SIMD3<Float>
        
        init(point: LiDARPoint) {
            self.point = point
            self.sampleCount = 1
            self.colorAccumulator = point.color
            self.normalAccumulator = point.normal
        }
        
        mutating func accumulate(_ newPoint: LiDARPoint) {
            sampleCount += 1
            colorAccumulator += newPoint.color
            normalAccumulator += newPoint.normal
            
            // Update stored point with averaged values
            let avgColor = colorAccumulator / Float(sampleCount)
            let avgNormal = sampleCount > 1 ? normalize(normalAccumulator) : normalAccumulator
            
            point = LiDARPoint(
                position: point.position,  // Keep original position (first in voxel)
                normal: avgNormal,
                color: avgColor,
                intensity: (point.intensity + newPoint.intensity) / 2,
                timestamp: newPoint.timestamp,  // Use latest timestamp
                classification: newPoint.classification
            )
        }
    }
    
    /// Main voxel grid storage (spatial hash map)
    private var voxelGrid: [VoxelKey: VoxelCell] = [:]
    
    /// Elevation-sorted index for fast slice queries
    private var elevationIndex: [Int32: Set<VoxelKey>] = [:]
    
    /// Bounding box tracking
    private var boundsMin: SIMD3<Float> = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
    private var boundsMax: SIMD3<Float> = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)
    
    /// Thread safety
    private let gridLock = NSLock()
    
    // MARK: - Initialization
    
    /// Initialize with voxel size in meters
    /// - Parameter voxelSize: Size of each voxel cube (default 2cm = 0.02m)
    public init(voxelSize: Float = 0.02) {
        self.voxelSize = voxelSize
    }
    
    // MARK: - PointCloudProcessorProtocol
    
    public func processPoints(_ batch: PointBatch) {
        var newPoints: [LiDARPoint] = []
        newPoints.reserveCapacity(batch.points.count / 10)  // Estimate ~10% are new voxels
        
        gridLock.lock()
        
        for point in batch.points {
            totalPointsProcessed += 1
            
            let key = VoxelKey(position: point.position, voxelSize: voxelSize)
            
            if var existingCell = voxelGrid[key] {
                // Voxel exists - accumulate for averaging
                existingCell.accumulate(point)
                voxelGrid[key] = existingCell
            } else {
                // New voxel - store point
                voxelGrid[key] = VoxelCell(point: point)
                voxelCount += 1
                newPoints.append(point)
                
                // Update elevation index
                let elevationBucket = Int32(floor(point.position.y / voxelSize))
                if elevationIndex[elevationBucket] == nil {
                    elevationIndex[elevationBucket] = Set()
                }
                elevationIndex[elevationBucket]?.insert(key)
                
                // Update bounds
                boundsMin = min(boundsMin, point.position)
                boundsMax = max(boundsMax, point.position)
            }
        }
        
        gridLock.unlock()
        
        // Publish new filtered points
        if !newPoints.isEmpty {
            let filteredBatch = PointBatch(
                points: newPoints,
                frameTimestamp: batch.frameTimestamp,
                cameraTransform: batch.cameraTransform,
                anchorID: batch.anchorID
            )
            filteredPointsSubject.send(filteredBatch)
        }
    }
    
    public func getPointsInSlice(_ slice: ElevationSlice) -> [LiDARPoint] {
        gridLock.lock()
        defer { gridLock.unlock() }
        
        var result: [LiDARPoint] = []
        
        // Calculate bucket range
        let minBucket = Int32(floor(slice.minY / voxelSize))
        let maxBucket = Int32(floor(slice.maxY / voxelSize))
        
        // Iterate through elevation buckets
        for bucket in minBucket...maxBucket {
            guard let keys = elevationIndex[bucket] else { continue }
            
            for key in keys {
                if let cell = voxelGrid[key] {
                    let y = cell.point.position.y
                    if y >= slice.minY && y <= slice.maxY {
                        result.append(cell.point)
                    }
                }
            }
        }
        
        return result
    }
    
    public func getAllPoints() -> [LiDARPoint] {
        gridLock.lock()
        defer { gridLock.unlock() }
        
        return voxelGrid.values.map { $0.point }
    }
    
    public func clear() {
        gridLock.lock()
        defer { gridLock.unlock() }
        
        voxelGrid.removeAll()
        elevationIndex.removeAll()
        voxelCount = 0
        totalPointsProcessed = 0
        boundsMin = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        boundsMax = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)
        
        print("🗑️ PointCloudProcessor cleared")
    }
    
    public func getStatistics() -> VoxelStatistics {
        gridLock.lock()
        defer { gridLock.unlock() }
        
        let compressionRatio = totalPointsProcessed > 0 
            ? Float(voxelCount) / Float(totalPointsProcessed) 
            : 1.0
        
        return VoxelStatistics(
            voxelCount: voxelCount,
            pointsProcessed: totalPointsProcessed,
            pointsStored: voxelCount,
            compressionRatio: compressionRatio,
            boundsMin: boundsMin,
            boundsMax: boundsMax
        )
    }
    
    // MARK: - Private Methods
    
    private func recalculateVoxelGrid() {
        // When voxel size changes, we need to rebuild the grid
        // This is expensive, so it should be avoided during scanning
        gridLock.lock()
        let oldPoints = voxelGrid.values.map { $0.point }
        
        voxelGrid.removeAll()
        elevationIndex.removeAll()
        voxelCount = 0
        boundsMin = SIMD3<Float>(Float.infinity, Float.infinity, Float.infinity)
        boundsMax = SIMD3<Float>(-Float.infinity, -Float.infinity, -Float.infinity)
        
        gridLock.unlock()
        
        // Re-insert all points with new voxel size
        let batch = PointBatch(
            points: oldPoints,
            frameTimestamp: Date().timeIntervalSince1970,
            cameraTransform: matrix_identity_float4x4,
            anchorID: UUID()
        )
        processPoints(batch)
        
        print("📦 Voxel grid recalculated with size: \(voxelSize)m")
    }
}

// MARK: - Advanced Queries

extension PointCloudProcessor {
    
    /// Get points within a spherical radius of a center point
    public func getPointsInSphere(center: SIMD3<Float>, radius: Float) -> [LiDARPoint] {
        gridLock.lock()
        defer { gridLock.unlock() }
        
        let radiusSquared = radius * radius
        var result: [LiDARPoint] = []
        
        // Calculate bounding box of sphere in voxel coordinates
        let minKey = VoxelKey(position: center - SIMD3<Float>(repeating: radius), voxelSize: voxelSize)
        let maxKey = VoxelKey(position: center + SIMD3<Float>(repeating: radius), voxelSize: voxelSize)
        
        // Iterate through voxels in bounding box
        for x in minKey.x...maxKey.x {
            for y in minKey.y...maxKey.y {
                for z in minKey.z...maxKey.z {
                    let key = VoxelKey(position: SIMD3<Float>(Float(x), Float(y), Float(z)) * voxelSize, voxelSize: voxelSize)
                    if let cell = voxelGrid[key] {
                        let distSquared = simd_length_squared(cell.point.position - center)
                        if distSquared <= radiusSquared {
                            result.append(cell.point)
                        }
                    }
                }
            }
        }
        
        return result
    }
    
    /// Get points within an axis-aligned bounding box
    public func getPointsInBox(min: SIMD3<Float>, max: SIMD3<Float>) -> [LiDARPoint] {
        gridLock.lock()
        defer { gridLock.unlock() }
        
        var result: [LiDARPoint] = []
        
        let minKey = VoxelKey(position: min, voxelSize: voxelSize)
        let maxKey = VoxelKey(position: max, voxelSize: voxelSize)
        
        for x in minKey.x...maxKey.x {
            for y in minKey.y...maxKey.y {
                for z in minKey.z...maxKey.z {
                    let key = VoxelKey(position: SIMD3<Float>(Float(x), Float(y), Float(z)) * voxelSize, voxelSize: voxelSize)
                    if let cell = voxelGrid[key] {
                        let p = cell.point.position
                        if p.x >= min.x && p.x <= max.x &&
                           p.y >= min.y && p.y <= max.y &&
                           p.z >= min.z && p.z <= max.z {
                            result.append(cell.point)
                        }
                    }
                }
            }
        }
        
        return result
    }
    
    /// Downsample to a coarser voxel grid for preview/LOD
    public func downsample(factor: Int) -> [LiDARPoint] {
        gridLock.lock()
        defer { gridLock.unlock() }
        
        let coarseSize = voxelSize * Float(factor)
        var coarseGrid: [VoxelKey: LiDARPoint] = [:]
        
        for cell in voxelGrid.values {
            let key = VoxelKey(position: cell.point.position, voxelSize: coarseSize)
            if coarseGrid[key] == nil {
                coarseGrid[key] = cell.point
            }
        }
        
        return Array(coarseGrid.values)
    }
}

// MARK: - SIMD Helpers

private func min(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(Swift.min(a.x, b.x), Swift.min(a.y, b.y), Swift.min(a.z, b.z))
}

private func max(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(Swift.max(a.x, b.x), Swift.max(a.y, b.y), Swift.max(a.z, b.z))
}
