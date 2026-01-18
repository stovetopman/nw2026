//
//  SpatialTracker.swift
//  ARExplorer - LiDAR Memory
//
//  MODULE 1: IMU-first spatial tracking with ARKit drift correction.
//  Provides high-frequency pose updates (100Hz) with low-latency IMU
//  and periodic drift correction from ARKit visual tracking.
//

import Foundation
import simd
import Combine
import CoreMotion
import ARKit

/// IMU-first spatial tracker with ARKit drift correction
public final class SpatialTracker: NSObject, SpatialTrackerProtocol, @unchecked Sendable {
    
    // MARK: - Published State
    
    public private(set) var currentPose: TrackedPose = TrackedPose(
        timestamp: 0,
        transform: matrix_identity_float4x4
    )
    
    // MARK: - Publishers
    
    private let poseSubject = PassthroughSubject<TrackedPose, Never>()
    private let correctedPoseSubject = PassthroughSubject<TrackedPose, Never>()
    
    public var posePublisher: AnyPublisher<TrackedPose, Never> {
        poseSubject.eraseToAnyPublisher()
    }
    
    public var correctedPosePublisher: AnyPublisher<TrackedPose, Never> {
        correctedPoseSubject.eraseToAnyPublisher()
    }
    
    // MARK: - IMU Components
    
    private let motionManager = CMMotionManager()
    private let imuQueue = OperationQueue()
    
    // MARK: - State
    
    private var isTracking = false
    private var lastIMUTimestamp: TimeInterval = 0
    private var lastARKitTimestamp: TimeInterval = 0
    
    // IMU integration state
    private var imuPosition: SIMD3<Float> = .zero
    private var imuVelocity: SIMD3<Float> = .zero
    private var imuOrientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    
    // ARKit correction state
    private var arKitTransform: simd_float4x4 = matrix_identity_float4x4
    private var driftOffset: SIMD3<Float> = .zero
    private var driftCorrectionFactor: Float = 0.1  // Smooth correction blend
    
    // Origin
    private var originTransform: simd_float4x4 = matrix_identity_float4x4
    
    // Thread safety
    private let stateLock = NSLock()
    
    // MARK: - Configuration
    
    /// IMU update rate in Hz
    public var imuUpdateRate: Double = 100.0
    
    /// Gravity magnitude for accelerometer calibration
    private let gravity: Float = 9.81
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        imuQueue.name = "com.arexplorer.spatialtracker.imu"
        imuQueue.maxConcurrentOperationCount = 1
    }
    
    // MARK: - SpatialTrackerProtocol
    
    public func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        startIMUUpdates()
        
        print("📍 SpatialTracker started - IMU rate: \(imuUpdateRate)Hz")
    }
    
    public func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        
        motionManager.stopDeviceMotionUpdates()
        
        print("📍 SpatialTracker stopped")
    }
    
    public func resetOrigin() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        originTransform = arKitTransform
        imuPosition = .zero
        imuVelocity = .zero
        driftOffset = .zero
        
        print("📍 Origin reset")
    }
    
    public func processARFrame(_ frame: ARFrame) {
        let timestamp = frame.timestamp
        let camera = frame.camera
        
        stateLock.lock()
        
        // Store ARKit transform for drift correction
        arKitTransform = camera.transform
        lastARKitTimestamp = timestamp
        
        // Calculate drift between IMU prediction and ARKit ground truth
        let arKitPosition = SIMD3<Float>(
            arKitTransform.columns.3.x,
            arKitTransform.columns.3.y,
            arKitTransform.columns.3.z
        )
        
        // Relative to origin
        let originPosition = SIMD3<Float>(
            originTransform.columns.3.x,
            originTransform.columns.3.y,
            originTransform.columns.3.z
        )
        let arKitRelativePosition = arKitPosition - originPosition
        
        // Drift is difference between ARKit ground truth and IMU prediction
        let drift = arKitRelativePosition - imuPosition
        
        // Smooth drift correction (don't snap, blend)
        driftOffset = driftOffset + drift * driftCorrectionFactor
        
        // Determine tracking quality
        let quality: TrackedPose.TrackingQuality
        switch camera.trackingState {
        case .notAvailable:
            quality = .notAvailable
        case .limited:
            quality = .limited
        case .normal:
            quality = .normal
        }
        
        stateLock.unlock()
        
        // Publish corrected pose
        let correctedPose = createCorrectedPose(timestamp: timestamp, quality: quality)
        correctedPoseSubject.send(correctedPose)
        
        // Also update current pose
        currentPose = correctedPose
    }
    
    // MARK: - IMU Processing
    
    private func startIMUUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("⚠️ Device motion not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / imuUpdateRate
        
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: imuQueue
        ) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.processIMUData(motion)
        }
    }
    
    private func processIMUData(_ motion: CMDeviceMotion) {
        let timestamp = motion.timestamp
        
        stateLock.lock()
        
        let deltaTime = lastIMUTimestamp == 0 ? 0.01 : Float(timestamp - lastIMUTimestamp)
        lastIMUTimestamp = timestamp
        
        // Get user acceleration (gravity removed)
        let userAccel = SIMD3<Float>(
            Float(motion.userAcceleration.x) * gravity,
            Float(motion.userAcceleration.y) * gravity,
            Float(motion.userAcceleration.z) * gravity
        )
        
        // Get rotation rate for angular velocity
        let angularVelocity = SIMD3<Float>(
            Float(motion.rotationRate.x),
            Float(motion.rotationRate.y),
            Float(motion.rotationRate.z)
        )
        
        // Convert CMAttitude quaternion to simd
        let attitude = motion.attitude.quaternion
        imuOrientation = simd_quatf(
            ix: Float(attitude.x),
            iy: Float(attitude.y),
            iz: Float(attitude.z),
            r: Float(attitude.w)
        )
        
        // Transform acceleration to world frame using current orientation
        let worldAccel = imuOrientation.act(userAccel)
        
        // Dead reckoning integration (simple Euler)
        // Note: This drifts quickly, ARKit corrects it
        imuVelocity += worldAccel * deltaTime
        imuPosition += imuVelocity * deltaTime
        
        // Apply velocity damping (simulates friction, reduces drift)
        imuVelocity *= 0.98
        
        // Apply accumulated drift correction
        let correctedPosition = imuPosition + driftOffset
        
        stateLock.unlock()
        
        // Build transform matrix
        let rotationMatrix = simd_float3x3(imuOrientation)
        let transform = simd_float4x4(
            SIMD4<Float>(rotationMatrix.columns.0, 0),
            SIMD4<Float>(rotationMatrix.columns.1, 0),
            SIMD4<Float>(rotationMatrix.columns.2, 0),
            SIMD4<Float>(correctedPosition.x, correctedPosition.y, correctedPosition.z, 1)
        )
        
        // Create and publish pose
        let pose = TrackedPose(
            timestamp: timestamp,
            transform: transform,
            velocity: imuVelocity,
            angularVelocity: angularVelocity,
            trackingQuality: .normal,
            isIMUOnly: true
        )
        
        currentPose = pose
        poseSubject.send(pose)
    }
    
    private func createCorrectedPose(timestamp: TimeInterval, quality: TrackedPose.TrackingQuality) -> TrackedPose {
        stateLock.lock()
        let velocity = imuVelocity
        stateLock.unlock()
        
        // Use ARKit transform directly (most accurate)
        // Apply origin offset
        let originInverse = originTransform.inverse
        let relativeTransform = originInverse * arKitTransform
        
        return TrackedPose(
            timestamp: timestamp,
            transform: relativeTransform,
            velocity: velocity,
            angularVelocity: .zero,
            trackingQuality: quality,
            isIMUOnly: false
        )
    }
}

// MARK: - simd_quatf Extensions

extension simd_quatf {
    /// Apply quaternion rotation to a vector
    func act(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        let rotationMatrix = simd_float3x3(self)
        return rotationMatrix * vector
    }
}

extension simd_float3x3 {
    /// Initialize from quaternion
    init(_ q: simd_quatf) {
        let xx = q.imag.x * q.imag.x
        let xy = q.imag.x * q.imag.y
        let xz = q.imag.x * q.imag.z
        let xw = q.imag.x * q.real
        let yy = q.imag.y * q.imag.y
        let yz = q.imag.y * q.imag.z
        let yw = q.imag.y * q.real
        let zz = q.imag.z * q.imag.z
        let zw = q.imag.z * q.real
        
        self.init(
            SIMD3<Float>(1 - 2 * (yy + zz), 2 * (xy + zw), 2 * (xz - yw)),
            SIMD3<Float>(2 * (xy - zw), 1 - 2 * (xx + zz), 2 * (yz + xw)),
            SIMD3<Float>(2 * (xz + yw), 2 * (yz - xw), 1 - 2 * (xx + yy))
        )
    }
}
