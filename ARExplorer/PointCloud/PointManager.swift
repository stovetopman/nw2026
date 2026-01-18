//
//  PointManager.swift
//  ARExplorer
//
//  Minimal point cloud storage with 2mm voxel filtering for high density.
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

/// Stores unique points using a 2mm voxel grid filter for high density scans.
final class PointManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var points: [ColoredPoint] = []
    @Published private(set) var uniqueCount: Int = 0
    
    // MARK: - Memory Management
    
    /// Maximum points to prevent memory exhaustion (2M × 16 bytes ≈ 32MB)
    private let maxPoints = 2_000_000
    
    // MARK: - Voxel Filter
    
    /// Set of occupied voxel keys (0.5mm resolution for high density)
    private var occupiedVoxels: Set<SIMD3<Int32>> = []
    
    /// Convert world position to voxel key (0.5mm = 0.0005m, so multiply by 2000)
    private func voxelKey(for position: SIMD3<Float>) -> SIMD3<Int32> {
        return SIMD3<Int32>(
            Int32(round(position.x * 2000)),
            Int32(round(position.y * 2000)),
            Int32(round(position.z * 2000))
        )
    }
    
    // MARK: - Public API
    
    /// Add a point if its voxel is unoccupied and under capacity.
    /// Returns true if the point was added.
    @discardableResult
    func addPoint(_ point: ColoredPoint) -> Bool {
        // Memory cap: stop accepting points at limit
        guard points.count < maxPoints else { return false }
        
        let key = voxelKey(for: point.position)
        
        if occupiedVoxels.contains(key) {
            return false
        }
        
        occupiedVoxels.insert(key)
        points.append(point)
        uniqueCount = points.count
        return true
    }
    
    /// Add multiple points, filtering duplicates efficiently.
    func addPoints(_ newPoints: [ColoredPoint]) {
        // Pre-reserve capacity if needed
        let remaining = maxPoints - points.count
        guard remaining > 0 else { return }
        
        // Reserve additional capacity for efficiency
        if points.capacity < points.count + min(newPoints.count, remaining) {
            points.reserveCapacity(points.count + min(newPoints.count, remaining))
        }
        
        for point in newPoints {
            guard points.count < maxPoints else { break }
            let key = voxelKey(for: point.position)
            if !occupiedVoxels.contains(key) {
                occupiedVoxels.insert(key)
                points.append(point)
            }
        }
        uniqueCount = points.count
    }
    
    /// Clear all points.
    func clear() {
        points.removeAll(keepingCapacity: true)  // Keep capacity for reuse
        occupiedVoxels.removeAll(keepingCapacity: true)
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
