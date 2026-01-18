//
//  FeatureExtractor.swift
//  ARExplorer - LiDAR Memory
//
//  MODULE 3: Geometric feature extraction using Levenberg-Marquardt optimization.
//  Fits circles, planes, and cylinders to point cloud clusters.
//

import Foundation
import simd
import Combine
import Accelerate

/// Geometric feature extractor with Levenberg-Marquardt fitting
public final class FeatureExtractor: FeatureExtractorProtocol, @unchecked Sendable {
    
    // MARK: - Configuration
    
    private var maxIterations: Int = 50
    private var convergenceThreshold: Float = 1e-6
    private var minPointsForFit: Int = 10
    
    // MARK: - Publishers
    
    private let detectedObjectsSubject = PassthroughSubject<[DetectedObject], Never>()
    
    public var detectedObjectsPublisher: AnyPublisher<[DetectedObject], Never> {
        detectedObjectsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Configuration
    
    public func configure(maxIterations: Int, convergenceThreshold: Float, minPointsForFit: Int) {
        self.maxIterations = maxIterations
        self.convergenceThreshold = convergenceThreshold
        self.minPointsForFit = minPointsForFit
    }
    
    // MARK: - FeatureExtractorProtocol
    
    /// Fit a circle to points projected onto XZ plane (horizontal)
    public func fitCircle(to points: [SIMD3<Float>]) async -> DetectedObject? {
        guard points.count >= minPointsForFit else { return nil }
        
        // Project to XZ plane (use x and z coordinates)
        let points2D = points.map { SIMD2<Float>($0.x, $0.z) }
        
        // Initial estimate: centroid and average distance
        let centroid = points2D.reduce(.zero, +) / Float(points2D.count)
        let avgRadius = points2D.map { simd_length($0 - centroid) }.reduce(0, +) / Float(points2D.count)
        
        // Levenberg-Marquardt optimization
        var params = SIMD3<Float>(centroid.x, centroid.y, avgRadius)  // cx, cz, r
        var lambda: Float = 0.001
        var prevError = calculateCircleError(params: params, points: points2D)
        
        for _ in 0..<maxIterations {
            // Calculate Jacobian and residuals
            let (jacobian, residuals) = calculateCircleJacobian(params: params, points: points2D)
            
            // J^T * J
            let jtj = multiplyTranspose(jacobian)
            
            // Add damping: (J^T * J + λI)
            var damped = jtj
            damped[0][0] += lambda
            damped[1][1] += lambda
            damped[2][2] += lambda
            
            // J^T * r
            let jtr = multiplyTransposeVector(jacobian, residuals)
            
            // Solve (J^T * J + λI) * δ = J^T * r
            guard let delta = solve3x3(damped, jtr) else { break }
            
            // Try update
            let newParams = params - delta
            let newError = calculateCircleError(params: newParams, points: points2D)
            
            if newError < prevError {
                params = newParams
                lambda *= 0.1
                
                if abs(prevError - newError) < convergenceThreshold {
                    break
                }
                prevError = newError
            } else {
                lambda *= 10
            }
        }
        
        // Calculate confidence based on fit error
        let finalError = calculateCircleError(params: params, points: points2D)
        let rmse = sqrt(finalError / Float(points.count))
        let confidence = max(0, 1 - rmse / params.z)  // Relative to radius
        
        // Calculate average Y (elevation) of points
        let avgY = points.map { $0.y }.reduce(0, +) / Float(points.count)
        
        return DetectedObject(
            type: .circle,
            center: SIMD3<Float>(params.x, avgY, params.y),
            dimensions: SIMD3<Float>(params.z * 2, 0, params.z * 2),  // diameter
            confidence: confidence,
            metadata: [
                "radius": String(format: "%.3f", params.z),
                "rmse": String(format: "%.4f", rmse)
            ]
        )
    }
    
    /// Fit a plane to points using least squares
    public func fitPlane(to points: [SIMD3<Float>]) async -> DetectedObject? {
        guard points.count >= minPointsForFit else { return nil }
        
        // Compute centroid
        let centroid = points.reduce(.zero, +) / Float(points.count)
        
        // Build covariance matrix
        var cov = simd_float3x3(diagonal: .zero)
        for p in points {
            let d = p - centroid
            cov.columns.0 += SIMD3<Float>(d.x * d.x, d.x * d.y, d.x * d.z)
            cov.columns.1 += SIMD3<Float>(d.y * d.x, d.y * d.y, d.y * d.z)
            cov.columns.2 += SIMD3<Float>(d.z * d.x, d.z * d.y, d.z * d.z)
        }
        
        // Find eigenvector with smallest eigenvalue (plane normal)
        // Using power iteration for largest, then deflation
        let normal = findSmallestEigenvector(cov)
        
        // Calculate plane distance from origin
        let d = -simd_dot(normal, centroid)
        
        // Calculate fit error (average distance to plane)
        var totalError: Float = 0
        for p in points {
            let dist = abs(simd_dot(normal, p) + d)
            totalError += dist * dist
        }
        let rmse = sqrt(totalError / Float(points.count))
        
        // Calculate confidence
        let confidence = max(0, 1 - rmse / 0.1)  // 10cm threshold
        
        // Calculate bounding box on plane
        let (minBound, maxBound) = calculatePlaneBounds(points: points, normal: normal, centroid: centroid)
        let dimensions = maxBound - minBound
        
        // Create orientation quaternion from normal
        let up = SIMD3<Float>(0, 1, 0)
        let orientation = simd_quatf(from: up, to: normal)
        
        return DetectedObject(
            type: .plane,
            center: centroid,
            dimensions: dimensions,
            orientation: orientation,
            confidence: confidence,
            metadata: [
                "normal": "(\(normal.x), \(normal.y), \(normal.z))",
                "rmse": String(format: "%.4f", rmse)
            ]
        )
    }
    
    /// Fit a cylinder to points
    public func fitCylinder(to points: [SIMD3<Float>]) async -> DetectedObject? {
        guard points.count >= minPointsForFit else { return nil }
        
        // Initial estimate: find axis direction via PCA
        let centroid = points.reduce(.zero, +) / Float(points.count)
        
        // Build covariance matrix
        var cov = simd_float3x3(diagonal: .zero)
        for p in points {
            let d = p - centroid
            cov.columns.0 += SIMD3<Float>(d.x * d.x, d.x * d.y, d.x * d.z)
            cov.columns.1 += SIMD3<Float>(d.y * d.x, d.y * d.y, d.y * d.z)
            cov.columns.2 += SIMD3<Float>(d.z * d.x, d.z * d.y, d.z * d.z)
        }
        
        // Principal axis is eigenvector with largest eigenvalue
        let axis = findLargestEigenvector(cov)
        
        // Project points onto plane perpendicular to axis
        var projectedPoints: [SIMD2<Float>] = []
        for p in points {
            let d = p - centroid
            let alongAxis = simd_dot(d, axis)
            let perpendicular = d - axis * alongAxis
            
            // Create 2D coordinates in perpendicular plane
            let u = createPerpendicular(to: axis)
            let v = simd_cross(axis, u)
            projectedPoints.append(SIMD2<Float>(simd_dot(perpendicular, u), simd_dot(perpendicular, v)))
        }
        
        // Fit circle to projected points
        let circleCentroid = projectedPoints.reduce(.zero, +) / Float(projectedPoints.count)
        let radius = projectedPoints.map { simd_length($0 - circleCentroid) }.reduce(0, +) / Float(projectedPoints.count)
        
        // Calculate height from axis extent
        let axisProjections = points.map { simd_dot($0 - centroid, axis) }
        let height = (axisProjections.max() ?? 0) - (axisProjections.min() ?? 0)
        
        // Calculate fit error
        var totalError: Float = 0
        for p2d in projectedPoints {
            let dist = abs(simd_length(p2d - circleCentroid) - radius)
            totalError += dist * dist
        }
        let rmse = sqrt(totalError / Float(points.count))
        let confidence = max(0, 1 - rmse / radius)
        
        // Create orientation quaternion
        let up = SIMD3<Float>(0, 1, 0)
        let orientation = simd_quatf(from: up, to: axis)
        
        return DetectedObject(
            type: .cylinder,
            center: centroid,
            dimensions: SIMD3<Float>(radius * 2, height, radius * 2),
            orientation: orientation,
            confidence: confidence,
            metadata: [
                "radius": String(format: "%.3f", radius),
                "height": String(format: "%.3f", height),
                "rmse": String(format: "%.4f", rmse)
            ]
        )
    }
    
    /// Detect all features in point cloud
    public func detectFeatures(in points: [LiDARPoint]) async -> [DetectedObject] {
        // This would typically involve:
        // 1. Region growing / clustering
        // 2. RANSAC for robust fitting
        // 3. Classification of each cluster
        
        // For now, return empty - full implementation would be extensive
        // TODO: Implement RANSAC-based segmentation
        return []
    }
    
    // MARK: - Levenberg-Marquardt Helpers
    
    private func calculateCircleError(params: SIMD3<Float>, points: [SIMD2<Float>]) -> Float {
        let cx = params.x
        let cz = params.y
        let r = params.z
        
        var error: Float = 0
        for p in points {
            let dist = simd_length(p - SIMD2<Float>(cx, cz)) - r
            error += dist * dist
        }
        return error
    }
    
    private func calculateCircleJacobian(params: SIMD3<Float>, points: [SIMD2<Float>]) -> ([[Float]], [Float]) {
        let cx = params.x
        let cz = params.y
        let r = params.z
        let center = SIMD2<Float>(cx, cz)
        
        var jacobian: [[Float]] = []
        var residuals: [Float] = []
        
        for p in points {
            let diff = p - center
            let dist = simd_length(diff)
            
            if dist < 1e-6 { continue }
            
            let residual = dist - r
            residuals.append(residual)
            
            // Partial derivatives
            let dCx = -diff.x / dist
            let dCz = -diff.y / dist
            let dR: Float = -1.0
            
            jacobian.append([dCx, dCz, dR])
        }
        
        return (jacobian, residuals)
    }
    
    // MARK: - Linear Algebra Helpers
    
    private func multiplyTranspose(_ matrix: [[Float]]) -> [[Float]] {
        // J^T * J for 3-column matrix
        let n = matrix.count
        var result: [[Float]] = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
        
        for i in 0..<3 {
            for j in 0..<3 {
                for k in 0..<n {
                    result[i][j] += matrix[k][i] * matrix[k][j]
                }
            }
        }
        
        return result
    }
    
    private func multiplyTransposeVector(_ matrix: [[Float]], _ vector: [Float]) -> SIMD3<Float> {
        var result = SIMD3<Float>.zero
        for i in 0..<matrix.count {
            result.x += matrix[i][0] * vector[i]
            result.y += matrix[i][1] * vector[i]
            result.z += matrix[i][2] * vector[i]
        }
        return result
    }
    
    private func solve3x3(_ A: [[Float]], _ b: SIMD3<Float>) -> SIMD3<Float>? {
        // Simple 3x3 solver using Cramer's rule
        let a = simd_float3x3(
            SIMD3<Float>(A[0][0], A[1][0], A[2][0]),
            SIMD3<Float>(A[0][1], A[1][1], A[2][1]),
            SIMD3<Float>(A[0][2], A[1][2], A[2][2])
        )
        
        let det = simd_determinant(a)
        if abs(det) < 1e-10 { return nil }
        
        let aInv = a.inverse
        return aInv * b
    }
    
    // MARK: - Eigenvector Methods
    
    private func findLargestEigenvector(_ matrix: simd_float3x3) -> SIMD3<Float> {
        // Power iteration
        var v = SIMD3<Float>(1, 0, 0)
        
        for _ in 0..<20 {
            let mv = matrix * v
            let norm = simd_length(mv)
            if norm < 1e-10 { break }
            v = mv / norm
        }
        
        return v
    }
    
    private func findSmallestEigenvector(_ matrix: simd_float3x3) -> SIMD3<Float> {
        // Inverse power iteration (find smallest eigenvalue)
        // For numerical stability, shift matrix
        let trace = matrix.columns.0.x + matrix.columns.1.y + matrix.columns.2.z
        let shift = trace / 3.0
        
        var shifted = matrix
        shifted.columns.0.x -= shift
        shifted.columns.1.y -= shift
        shifted.columns.2.z -= shift
        
        // Use largest eigenvector of shifted inverse
        let inv = shifted.inverse
        return findLargestEigenvector(inv)
    }
    
    private func createPerpendicular(to v: SIMD3<Float>) -> SIMD3<Float> {
        // Create a vector perpendicular to v
        let absV = SIMD3<Float>(abs(v.x), abs(v.y), abs(v.z))
        
        var other: SIMD3<Float>
        if absV.x <= absV.y && absV.x <= absV.z {
            other = SIMD3<Float>(1, 0, 0)
        } else if absV.y <= absV.z {
            other = SIMD3<Float>(0, 1, 0)
        } else {
            other = SIMD3<Float>(0, 0, 1)
        }
        
        return normalize(simd_cross(v, other))
    }
    
    private func calculatePlaneBounds(points: [SIMD3<Float>], normal: SIMD3<Float>, centroid: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        // Create local coordinate system on plane
        let u = createPerpendicular(to: normal)
        let v = simd_cross(normal, u)
        
        var minU: Float = .infinity, maxU: Float = -.infinity
        var minV: Float = .infinity, maxV: Float = -.infinity
        var minN: Float = .infinity, maxN: Float = -.infinity
        
        for p in points {
            let d = p - centroid
            let pu = simd_dot(d, u)
            let pv = simd_dot(d, v)
            let pn = simd_dot(d, normal)
            
            minU = min(minU, pu); maxU = max(maxU, pu)
            minV = min(minV, pv); maxV = max(maxV, pv)
            minN = min(minN, pn); maxN = max(maxN, pn)
        }
        
        return (
            SIMD3<Float>(minU, minN, minV),
            SIMD3<Float>(maxU, maxN, maxV)
        )
    }
}
