//
//  PointManager.swift
//  ARExplorer
//
//  Minimal point cloud storage with 1cm voxel filtering.
//

import Foundation
import simd

// MARK: - Point Structure

/// A single point: position (xyz) + color (rgb)
struct ColoredPoint {
    let position: SIMD3<Float>
    let color: SIMD3<UInt8>
}

// MARK: - Point Manager

/// Stores unique points using a 1cm voxel grid filter.
final class PointManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var points: [ColoredPoint] = []
    @Published private(set) var uniqueCount: Int = 0
    
    // MARK: - Voxel Filter
    
    /// Set of occupied voxel keys (1cm resolution)
    private var occupiedVoxels: Set<SIMD3<Int32>> = []
    
    /// Convert world position to voxel key (1cm = 0.01m, so multiply by 100)
    private func voxelKey(for position: SIMD3<Float>) -> SIMD3<Int32> {
        return SIMD3<Int32>(
            Int32(round(position.x * 100)),
            Int32(round(position.y * 100)),
            Int32(round(position.z * 100))
        )
    }
    
    // MARK: - Public API
    
    /// Add a point if its voxel is unoccupied.
    /// Returns true if the point was added.
    @discardableResult
    func addPoint(_ point: ColoredPoint) -> Bool {
        let key = voxelKey(for: point.position)
        
        if occupiedVoxels.contains(key) {
            return false
        }
        
        occupiedVoxels.insert(key)
        points.append(point)
        uniqueCount = points.count
        return true
    }
    
    /// Add multiple points, filtering duplicates.
    func addPoints(_ newPoints: [ColoredPoint]) {
        for point in newPoints {
            addPoint(point)
        }
    }
    
    /// Clear all points.
    func clear() {
        points.removeAll()
        occupiedVoxels.removeAll()
        uniqueCount = 0
    }
    
    /// Get raw position data for rendering (interleaved xyz)
    func getPositionData() -> [Float] {
        var data: [Float] = []
        data.reserveCapacity(points.count * 3)
        for point in points {
            data.append(point.position.x)
            data.append(point.position.y)
            data.append(point.position.z)
        }
        return data
    }
    
    /// Get raw color data for rendering (interleaved rgb as floats 0-1)
    func getColorData() -> [Float] {
        var data: [Float] = []
        data.reserveCapacity(points.count * 3)
        for point in points {
            data.append(Float(point.color.x) / 255.0)
            data.append(Float(point.color.y) / 255.0)
            data.append(Float(point.color.z) / 255.0)
        }
        return data
    }
}
