//
//  PipelineProtocols.swift
//  ARExplorer - LiDAR Memory
//
//  Protocol-oriented architecture for the modular LiDAR data pipeline.
//  Inspired by ForestScanner's efficient processing approach.
//

import Foundation
import simd
import Combine
import ARKit

// MARK: - Core Data Types

/// A single 3D point with position, normal, color, and metadata
public struct LiDARPoint: Hashable, Sendable {
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let color: SIMD4<Float>
    public let intensity: Float
    public let timestamp: TimeInterval
    public let classification: PointClassification
    
    public init(
        position: SIMD3<Float>,
        normal: SIMD3<Float> = .zero,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        intensity: Float = 1.0,
        timestamp: TimeInterval = 0,
        classification: PointClassification = .unclassified
    ) {
        self.position = position
        self.normal = normal
        self.color = color
        self.intensity = intensity
        self.timestamp = timestamp
        self.classification = classification
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(position.x)
        hasher.combine(position.y)
        hasher.combine(position.z)
    }
    
    public static func == (lhs: LiDARPoint, rhs: LiDARPoint) -> Bool {
        lhs.position == rhs.position
    }
}

/// Classification types for points
public enum PointClassification: Int, Sendable, CaseIterable {
    case unclassified = 0
    case ground = 1
    case wall = 2
    case ceiling = 3
    case furniture = 4
    case object = 5
}

/// A batch of points for efficient processing
public struct PointBatch: Sendable {
    public let points: [LiDARPoint]
    public let frameTimestamp: TimeInterval
    public let cameraTransform: simd_float4x4
    public let anchorID: UUID
    
    public init(points: [LiDARPoint], frameTimestamp: TimeInterval, cameraTransform: simd_float4x4, anchorID: UUID) {
        self.points = points
        self.frameTimestamp = frameTimestamp
        self.cameraTransform = cameraTransform
        self.anchorID = anchorID
    }
}

/// Detected geometric feature from point cloud analysis
public struct DetectedObject: Identifiable, Sendable {
    public let id: UUID
    public let type: ObjectType
    public let center: SIMD3<Float>
    public let dimensions: SIMD3<Float>
    public let orientation: simd_quatf
    public let confidence: Float
    public let pointIndices: [Int]
    public let metadata: [String: String]
    
    public enum ObjectType: String, Sendable {
        case circle
        case plane
        case cylinder
        case sphere
        case box
        case unknown
    }
    
    public init(
        id: UUID = UUID(),
        type: ObjectType,
        center: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        orientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        confidence: Float,
        pointIndices: [Int] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.center = center
        self.dimensions = dimensions
        self.orientation = orientation
        self.confidence = confidence
        self.pointIndices = pointIndices
        self.metadata = metadata
    }
}

/// Spatial tracking pose with IMU and visual tracking data
public struct TrackedPose: Sendable {
    public let timestamp: TimeInterval
    public let transform: simd_float4x4
    public let velocity: SIMD3<Float>
    public let angularVelocity: SIMD3<Float>
    public let trackingQuality: TrackingQuality
    public let isIMUOnly: Bool
    
    public enum TrackingQuality: Int, Sendable {
        case notAvailable = 0
        case limited = 1
        case normal = 2
        case high = 3
    }
    
    public init(
        timestamp: TimeInterval,
        transform: simd_float4x4,
        velocity: SIMD3<Float> = .zero,
        angularVelocity: SIMD3<Float> = .zero,
        trackingQuality: TrackingQuality = .normal,
        isIMUOnly: Bool = false
    ) {
        self.timestamp = timestamp
        self.transform = transform
        self.velocity = velocity
        self.angularVelocity = angularVelocity
        self.trackingQuality = trackingQuality
        self.isIMUOnly = isIMUOnly
    }
}

/// Elevation slice parameters for filtering
public struct ElevationSlice: Sendable {
    public let minY: Float
    public let maxY: Float
    
    public init(minY: Float, maxY: Float) {
        self.minY = minY
        self.maxY = maxY
    }
    
    public func contains(_ y: Float) -> Bool {
        y >= minY && y <= maxY
    }
}

/// Export result from async exporter
public struct ExportResult: Sendable {
    public let url: URL
    public let pointCount: Int
    public let faceCount: Int
    public let fileSize: Int64
    public let duration: TimeInterval
    
    public init(url: URL, pointCount: Int, faceCount: Int, fileSize: Int64, duration: TimeInterval) {
        self.url = url
        self.pointCount = pointCount
        self.faceCount = faceCount
        self.fileSize = fileSize
        self.duration = duration
    }
}

// MARK: - Module Protocols

/// MODULE 1: Spatial Tracker - IMU-first positioning with ARKit correction
public protocol SpatialTrackerProtocol: AnyObject, Sendable {
    /// Current tracking pose
    var currentPose: TrackedPose { get }
    
    /// Publisher for high-frequency pose updates (100Hz IMU)
    var posePublisher: AnyPublisher<TrackedPose, Never> { get }
    
    /// Publisher for drift-corrected poses (30Hz ARKit)
    var correctedPosePublisher: AnyPublisher<TrackedPose, Never> { get }
    
    /// Start tracking
    func startTracking()
    
    /// Stop tracking
    func stopTracking()
    
    /// Reset tracking origin
    func resetOrigin()
    
    /// Inject ARKit frame for drift correction
    func processARFrame(_ frame: ARFrame)
}

/// MODULE 2: Point Cloud Processor - Voxel filtering and elevation slicing
public protocol PointCloudProcessorProtocol: AnyObject, Sendable {
    /// Current voxel grid resolution in meters
    var voxelSize: Float { get set }
    
    /// Total number of stored voxels
    var voxelCount: Int { get }
    
    /// Total number of points processed
    var totalPointsProcessed: Int { get }
    
    /// Publisher for filtered point batches
    var filteredPointsPublisher: AnyPublisher<PointBatch, Never> { get }
    
    /// Process incoming point batch through voxel filter
    func processPoints(_ batch: PointBatch)
    
    /// Get all points within elevation slice
    func getPointsInSlice(_ slice: ElevationSlice) -> [LiDARPoint]
    
    /// Get all filtered points
    func getAllPoints() -> [LiDARPoint]
    
    /// Clear all stored data
    func clear()
    
    /// Export voxel grid statistics
    func getStatistics() -> VoxelStatistics
}

/// Statistics from voxel processor
public struct VoxelStatistics: Sendable {
    public let voxelCount: Int
    public let pointsProcessed: Int
    public let pointsStored: Int
    public let compressionRatio: Float
    public let boundsMin: SIMD3<Float>
    public let boundsMax: SIMD3<Float>
    
    public init(
        voxelCount: Int,
        pointsProcessed: Int,
        pointsStored: Int,
        compressionRatio: Float,
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>
    ) {
        self.voxelCount = voxelCount
        self.pointsProcessed = pointsProcessed
        self.pointsStored = pointsStored
        self.compressionRatio = compressionRatio
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
    }
}

/// MODULE 3: Feature Extractor - Geometric fitting
public protocol FeatureExtractorProtocol: AnyObject, Sendable {
    /// Publisher for detected objects
    var detectedObjectsPublisher: AnyPublisher<[DetectedObject], Never> { get }
    
    /// Fit a circle to a cluster of points (XZ plane)
    func fitCircle(to points: [SIMD3<Float>]) async -> DetectedObject?
    
    /// Fit a plane to a cluster of points
    func fitPlane(to points: [SIMD3<Float>]) async -> DetectedObject?
    
    /// Fit a cylinder to a cluster of points
    func fitCylinder(to points: [SIMD3<Float>]) async -> DetectedObject?
    
    /// Detect all features in point cloud
    func detectFeatures(in points: [LiDARPoint]) async -> [DetectedObject]
    
    /// Configure fitting parameters
    func configure(maxIterations: Int, convergenceThreshold: Float, minPointsForFit: Int)
}

/// MODULE 4: Async Exporter - Background USDZ generation
public protocol AsyncExporterProtocol: AnyObject, Sendable {
    /// Current export progress (0.0 - 1.0)
    var progress: Float { get }
    
    /// Whether an export is currently in progress
    var isExporting: Bool { get }
    
    /// Publisher for export progress updates
    var progressPublisher: AnyPublisher<Float, Never> { get }
    
    /// Export points to USDZ asynchronously
    func exportToUSDZ(
        points: [LiDARPoint],
        indices: [UInt32],
        chunkSize: Int
    ) async throws -> ExportResult
    
    /// Cancel current export
    func cancelExport()
}

/// Central Coordinator - Manages data flow between modules
public protocol PipelineCoordinatorProtocol: AnyObject {
    /// The spatial tracker module
    var spatialTracker: SpatialTrackerProtocol { get }
    
    /// The point cloud processor module
    var pointCloudProcessor: PointCloudProcessorProtocol { get }
    
    /// The feature extractor module
    var featureExtractor: FeatureExtractorProtocol { get }
    
    /// The async exporter module
    var asyncExporter: AsyncExporterProtocol { get }
    
    /// Whether the pipeline is currently running
    var isRunning: Bool { get }
    
    /// Current pipeline statistics
    var statistics: PipelineStatistics { get }
    
    /// Publisher for pipeline statistics
    var statisticsPublisher: AnyPublisher<PipelineStatistics, Never> { get }
    
    /// Start the processing pipeline
    func start()
    
    /// Stop the processing pipeline
    func stop()
    
    /// Process an AR frame through the pipeline
    func processFrame(_ frame: ARFrame, meshAnchors: [ARMeshAnchor])
    
    /// Export current scan
    func exportScan() async throws -> ExportResult
}

/// Pipeline performance statistics
public struct PipelineStatistics: Sendable {
    public let frameRate: Float
    public let processingLatency: TimeInterval
    public let pointsPerSecond: Int
    public let voxelCount: Int
    public let memoryUsageMB: Float
    public let trackingQuality: TrackedPose.TrackingQuality
    
    public init(
        frameRate: Float = 0,
        processingLatency: TimeInterval = 0,
        pointsPerSecond: Int = 0,
        voxelCount: Int = 0,
        memoryUsageMB: Float = 0,
        trackingQuality: TrackedPose.TrackingQuality = .normal
    ) {
        self.frameRate = frameRate
        self.processingLatency = processingLatency
        self.pointsPerSecond = pointsPerSecond
        self.voxelCount = voxelCount
        self.memoryUsageMB = memoryUsageMB
        self.trackingQuality = trackingQuality
    }
}
