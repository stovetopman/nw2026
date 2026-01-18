//
//  CameraController.swift
//  ARExplorer - LiDAR Memory
//
//  Manages a virtual PerspectiveCamera for orbit, pan, and zoom navigation
//  with smooth inertia effects at 60fps.
//

import Foundation
import RealityKit
import simd
import Combine
import QuartzCore  // For CADisplayLink

/// Camera controller for orbit/pan/zoom gesture-based navigation
@MainActor
final class CameraController: ObservableObject {
    
    // MARK: - Published State
    
    /// Current camera transform (position + orientation)
    @Published private(set) var cameraTransform: simd_float4x4 = matrix_identity_float4x4
    
    // MARK: - Camera Parameters
    
    /// The pivot point the camera orbits around (center of model)
    private(set) var pivotPoint: SIMD3<Float> = .zero
    
    /// Distance from pivot point to camera
    private var distance: Float = 5.0
    
    /// Horizontal orbit angle (yaw) in radians
    private var azimuth: Float = 0
    
    /// Vertical orbit angle (pitch) in radians - clamped to avoid gimbal lock
    private var elevation: Float = Float.pi / 4  // Start at 45 degrees down
    
    // MARK: - Velocity State (for inertia)
    
    private var azimuthVelocity: Float = 0
    private var elevationVelocity: Float = 0
    private var panVelocity: SIMD2<Float> = .zero
    private var zoomVelocity: Float = 0
    
    // MARK: - Configuration
    
    /// Orbit sensitivity multiplier
    var orbitSensitivity: Float = 0.005
    
    /// Pan sensitivity multiplier
    var panSensitivity: Float = 0.003
    
    /// Zoom sensitivity multiplier
    var zoomSensitivity: Float = 1.0
    
    /// Inertia friction (0 = infinite glide, 1 = instant stop)
    var friction: Float = 0.92
    
    /// Minimum distance from pivot
    var minDistance: Float = 0.3
    
    /// Maximum distance from pivot
    var maxDistance: Float = 50.0
    
    /// Minimum elevation angle (radians) - prevents looking from below
    var minElevation: Float = 0.1
    
    /// Maximum elevation angle (radians) - prevents flipping over top
    var maxElevation: Float = Float.pi / 2 - 0.1
    
    /// Near clipping plane for tight corners
    var nearClipPlane: Float = 0.01
    
    // MARK: - Update Loop
    
    private var displayLink: CADisplayLink?
    private var lastUpdateTime: CFTimeInterval = 0
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        displayLink?.invalidate()
    }
    
    // MARK: - Setup
    
    /// Initialize camera position based on model bounds
    func initialize(modelCenter: SIMD3<Float>, modelExtents: SIMD3<Float>) {
        pivotPoint = modelCenter
        
        // Calculate initial distance to see the whole model
        let maxExtent = max(modelExtents.x, max(modelExtents.y, modelExtents.z))
        distance = maxExtent * 2.0
        
        // Start at 45-degree downward angle, looking at center
        elevation = Float.pi / 4
        azimuth = 0
        
        // Clear any residual velocity
        clearVelocity()
        
        // Update initial transform
        updateCameraTransform()
        
        print("📷 Camera initialized - pivot: \(pivotPoint), distance: \(distance)")
    }
    
    /// Start the 60fps update loop
    func startUpdateLoop() {
        guard displayLink == nil else { return }
        
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    /// Stop the update loop
    func stopUpdateLoop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    // MARK: - Gesture Input
    
    /// Handle orbit (single finger drag)
    /// - Parameters:
    ///   - delta: Translation delta in screen points
    ///   - isEnding: True if gesture is ending (for inertia)
    func handleOrbit(delta: CGSize, isEnding: Bool = false) {
        if isEnding {
            // Convert recent delta to velocity for inertia
            azimuthVelocity = Float(delta.width) * orbitSensitivity * 0.3
            elevationVelocity = Float(delta.height) * orbitSensitivity * 0.3
        } else {
            // Direct manipulation
            azimuth -= Float(delta.width) * orbitSensitivity
            elevation += Float(delta.height) * orbitSensitivity
            clampElevation()
        }
    }
    
    /// Handle pan (two-finger drag)
    /// - Parameters:
    ///   - delta: Translation delta in screen points
    ///   - isEnding: True if gesture is ending (for inertia)
    func handlePan(delta: CGSize, isEnding: Bool = false) {
        if isEnding {
            panVelocity = SIMD2<Float>(Float(delta.width), Float(delta.height)) * panSensitivity * 0.3
        } else {
            // Calculate pan vectors in world space
            let panDelta = calculatePanDelta(screenDelta: delta)
            pivotPoint += panDelta
        }
    }
    
    /// Handle zoom (pinch gesture)
    /// - Parameters:
    ///   - scale: Magnification scale (1.0 = no change)
    ///   - isEnding: True if gesture is ending (for inertia)
    func handleZoom(scale: CGFloat, velocity: CGFloat = 0, isEnding: Bool = false) {
        if isEnding {
            zoomVelocity = Float(velocity) * -0.001
        } else {
            // Zoom is inverse of scale (pinch out = zoom in = decrease distance)
            let zoomFactor = 1.0 / Float(scale)
            distance *= zoomFactor
            clampDistance()
        }
    }
    
    /// Clear all velocity (stop inertia)
    func clearVelocity() {
        azimuthVelocity = 0
        elevationVelocity = 0
        panVelocity = .zero
        zoomVelocity = 0
    }
    
    // MARK: - Frame Update
    
    @objc private func updateFrame(displayLink: CADisplayLink) {
        let currentTime = displayLink.timestamp
        let deltaTime = lastUpdateTime == 0 ? 0.016 : Float(currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        
        // Apply inertia for orbit
        if abs(azimuthVelocity) > 0.0001 || abs(elevationVelocity) > 0.0001 {
            azimuth -= azimuthVelocity
            elevation += elevationVelocity
            clampElevation()
            
            // Apply friction
            azimuthVelocity *= friction
            elevationVelocity *= friction
        }
        
        // Apply inertia for pan
        if length(panVelocity) > 0.0001 {
            let panDelta = calculatePanDelta(velocity: panVelocity)
            pivotPoint += panDelta
            
            panVelocity *= friction
        }
        
        // Apply inertia for zoom
        if abs(zoomVelocity) > 0.0001 {
            distance += zoomVelocity * distance
            clampDistance()
            
            zoomVelocity *= friction
        }
        
        // Update the camera transform
        updateCameraTransform()
    }
    
    // MARK: - Transform Calculation
    
    private func updateCameraTransform() {
        // Calculate camera position on a sphere around pivot point
        let x = pivotPoint.x + distance * cos(elevation) * sin(azimuth)
        let y = pivotPoint.y + distance * sin(elevation)
        let z = pivotPoint.z + distance * cos(elevation) * cos(azimuth)
        
        let cameraPosition = SIMD3<Float>(x, y, z)
        
        // Calculate look-at rotation
        let lookDirection = normalize(pivotPoint - cameraPosition)
        let worldUp = SIMD3<Float>(0, 1, 0)
        
        // Build rotation matrix
        let zAxis = -lookDirection  // Camera looks down -Z
        let xAxis = normalize(cross(worldUp, zAxis))
        let yAxis = cross(zAxis, xAxis)
        
        // Construct 4x4 transform matrix
        cameraTransform = simd_float4x4(
            SIMD4<Float>(xAxis.x, xAxis.y, xAxis.z, 0),
            SIMD4<Float>(yAxis.x, yAxis.y, yAxis.z, 0),
            SIMD4<Float>(zAxis.x, zAxis.y, zAxis.z, 0),
            SIMD4<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z, 1)
        )
    }
    
    // MARK: - Helpers
    
    private func clampElevation() {
        elevation = max(minElevation, min(maxElevation, elevation))
    }
    
    private func clampDistance() {
        distance = max(minDistance, min(maxDistance, distance))
    }
    
    /// Calculate pan delta in world space from screen delta
    private func calculatePanDelta(screenDelta: CGSize) -> SIMD3<Float> {
        // Get camera right and up vectors from current transform
        let right = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
        let up = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
        
        // Scale by distance for consistent feel at different zoom levels
        let scaleFactor = distance * panSensitivity
        
        // Pan moves pivot (and camera) opposite to drag direction
        let panX = -Float(screenDelta.width) * scaleFactor * right
        let panY = Float(screenDelta.height) * scaleFactor * up
        
        return panX + panY
    }
    
    /// Calculate pan delta from velocity for inertia
    private func calculatePanDelta(velocity: SIMD2<Float>) -> SIMD3<Float> {
        let right = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
        let up = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
        
        let scaleFactor = distance
        
        let panX = -velocity.x * scaleFactor * right
        let panY = velocity.y * scaleFactor * up
        
        return panX + panY
    }
}

// MARK: - Camera Position/Orientation Extraction

extension CameraController {
    /// Current camera position in world space
    var cameraPosition: SIMD3<Float> {
        SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
    }
    
    /// Current camera orientation as quaternion
    var cameraOrientation: simd_quatf {
        simd_quatf(cameraTransform)
    }
}
