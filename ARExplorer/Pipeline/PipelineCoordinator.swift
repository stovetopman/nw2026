//
//  PipelineCoordinator.swift
//  ARExplorer - LiDAR Memory
//
//  Central coordinator managing data flow between pipeline modules.
//  Ensures 60fps scanning by offloading heavy processing to background queues.
//

import Foundation
import simd
import Combine
import ARKit
import QuartzCore

/// Central coordinator for the LiDAR data processing pipeline
@MainActor
public final class PipelineCoordinator: PipelineCoordinatorProtocol, ObservableObject {
    
    // MARK: - Modules
    
    public let spatialTracker: SpatialTrackerProtocol
    public let pointCloudProcessor: PointCloudProcessorProtocol
    public let featureExtractor: FeatureExtractorProtocol
    public let asyncExporter: AsyncExporterProtocol
    
    // MARK: - Published State
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var statistics: PipelineStatistics = PipelineStatistics()
    
    public var statisticsPublisher: AnyPublisher<PipelineStatistics, Never> {
        $statistics.eraseToAnyPublisher()
    }
    
    // MARK: - Performance Tracking
    
    private var frameCount: Int = 0
    private var lastStatisticsUpdate: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    private var frameTimeAccumulator: TimeInterval = 0
    private var pointsProcessedSinceLastUpdate: Int = 0
    
    // MARK: - Processing Queues
    
    /// High-priority queue for mesh extraction (must keep up with 60fps)
    private let meshExtractionQueue = DispatchQueue(
        label: "com.arexplorer.pipeline.meshextraction",
        qos: .userInteractive
    )
    
    /// Background queue for voxel processing
    private let processingQueue = DispatchQueue(
        label: "com.arexplorer.pipeline.processing",
        qos: .userInitiated,
        attributes: .concurrent
    )
    
    /// Serial queue for statistics updates
    private let statisticsQueue = DispatchQueue(
        label: "com.arexplorer.pipeline.statistics",
        qos: .utility
    )
    
    // MARK: - Subscriptions
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Frame Throttling
    
    /// Process mesh every N frames to reduce CPU load
    private let meshProcessingInterval: Int = 3
    
    /// Statistics update interval in seconds
    private let statisticsUpdateInterval: TimeInterval = 0.5
    
    // MARK: - Initialization
    
    public init(
        spatialTracker: SpatialTrackerProtocol? = nil,
        pointCloudProcessor: PointCloudProcessorProtocol? = nil,
        featureExtractor: FeatureExtractorProtocol? = nil,
        asyncExporter: AsyncExporterProtocol? = nil
    ) {
        self.spatialTracker = spatialTracker ?? SpatialTracker()
        self.pointCloudProcessor = pointCloudProcessor ?? PointCloudProcessor(voxelSize: 0.02)
        self.featureExtractor = featureExtractor ?? FeatureExtractor()
        self.asyncExporter = asyncExporter ?? AsyncExporter()
        
        setupSubscriptions()
    }
    
    // MARK: - PipelineCoordinatorProtocol
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        spatialTracker.startTracking()
        resetStatistics()
        
        print("🚀 Pipeline started")
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        
        spatialTracker.stopTracking()
        
        print("🛑 Pipeline stopped")
        printFinalStatistics()
    }
    
    public func processFrame(_ frame: ARFrame, meshAnchors: [ARMeshAnchor]) {
        guard isRunning else { return }
        
        let frameTime = frame.timestamp
        let deltaTime = lastFrameTime == 0 ? 0.016 : frameTime - lastFrameTime
        lastFrameTime = frameTime
        frameTimeAccumulator += deltaTime
        frameCount += 1
        
        // Always update spatial tracker with ARKit data
        spatialTracker.processARFrame(frame)
        
        // Throttle mesh processing to every Nth frame
        guard frameCount % meshProcessingInterval == 0 else { return }
        
        // Extract points from mesh anchors on background queue
        meshExtractionQueue.async { [weak self] in
            guard let self = self else { return }
            
            for anchor in meshAnchors {
                let points = self.extractPoints(from: anchor, frame: frame)
                
                if !points.isEmpty {
                    let batch = PointBatch(
                        points: points,
                        frameTimestamp: frameTime,
                        cameraTransform: frame.camera.transform,
                        anchorID: anchor.identifier
                    )
                    
                    // Process through voxel filter
                    self.pointCloudProcessor.processPoints(batch)
                    
                    Task { @MainActor in
                        self.pointsProcessedSinceLastUpdate += points.count
                    }
                }
            }
        }
        
        // Update statistics periodically
        if frameTime - lastStatisticsUpdate >= statisticsUpdateInterval {
            updateStatistics(currentTime: frameTime)
            lastStatisticsUpdate = frameTime
        }
    }
    
    public func exportScan() async throws -> ExportResult {
        let points = pointCloudProcessor.getAllPoints()
        
        guard !points.isEmpty else {
            throw ExportError.emptyData
        }
        
        // Generate triangle indices from voxel grid
        // For now, use simple triangulation
        let indices = generateTriangleIndices(pointCount: points.count)
        
        return try await asyncExporter.exportToUSDZ(
            points: points,
            indices: indices,
            chunkSize: 10000
        )
    }
    
    // MARK: - Point Extraction
    
    private func extractPoints(from anchor: ARMeshAnchor, frame: ARFrame) -> [LiDARPoint] {
        let geometry = anchor.geometry
        let vertexCount = geometry.vertices.count
        let transform = anchor.transform
        
        // Early exit for small meshes
        guard vertexCount >= 3 else { return [] }
        
        var points: [LiDARPoint] = []
        points.reserveCapacity(vertexCount)
        
        // Get buffer pointers
        let vertexBuffer = geometry.vertices.buffer
        let vertexOffset = geometry.vertices.offset
        let vertexStride = geometry.vertices.stride
        let vertexPtr = vertexBuffer.contents().advanced(by: vertexOffset)
        
        let normalBuffer = geometry.normals.buffer
        let normalOffset = geometry.normals.offset
        let normalStride = geometry.normals.stride
        let normalPtr = normalBuffer.contents().advanced(by: normalOffset)
        
        // Get classification if available
        let classificationBuffer = geometry.classification.buffer
        let classificationOffset = geometry.classification.offset
        let classificationStride = geometry.classification.stride
        let classificationPtr = classificationBuffer.contents().advanced(by: classificationOffset)
        
        // Sample color from camera image (optimized: sample every Nth vertex)
        let colorSampleInterval = 4
        
        for i in 0..<vertexCount {
            // Read position
            let posPtr = vertexPtr.advanced(by: i * vertexStride)
            let localPos = posPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            
            // Transform to world space
            let worldPos4 = transform * SIMD4<Float>(localPos.x, localPos.y, localPos.z, 1.0)
            let worldPos = SIMD3<Float>(worldPos4.x, worldPos4.y, worldPos4.z)
            
            // Read normal
            let nrmPtr = normalPtr.advanced(by: i * normalStride)
            let localNormal = nrmPtr.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            
            // Transform normal to world space (rotation only)
            let normalTransform = simd_float3x3(
                SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
            )
            let worldNormal = normalize(normalTransform * localNormal)
            
            // Read classification
            let classPtr = classificationPtr.advanced(by: i * classificationStride)
            let classValue = classPtr.assumingMemoryBound(to: UInt8.self).pointee
            let classification = PointClassification(rawValue: Int(classValue)) ?? .unclassified
            
            // Sample color (throttled)
            let color: SIMD4<Float>
            if i % colorSampleInterval == 0 {
                color = sampleColor(worldPosition: worldPos, frame: frame)
            } else {
                color = SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
            }
            
            let point = LiDARPoint(
                position: worldPos,
                normal: worldNormal,
                color: color,
                intensity: 1.0,
                timestamp: frame.timestamp,
                classification: classification
            )
            
            points.append(point)
        }
        
        return points
    }
    
    // MARK: - Color Sampling
    
    private func sampleColor(worldPosition: SIMD3<Float>, frame: ARFrame) -> SIMD4<Float> {
        // Simplified color sampling - full implementation in ScanningEngine
        // Return neutral gray for now
        return SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
    }
    
    // MARK: - Triangle Generation
    
    private func generateTriangleIndices(pointCount: Int) -> [UInt32] {
        // Simple triangulation for voxel point cloud
        // Real implementation would use Delaunay or Ball Pivoting
        var indices: [UInt32] = []
        
        // Create triangles from consecutive triplets
        let triCount = pointCount / 3
        indices.reserveCapacity(triCount * 3)
        
        for i in 0..<triCount {
            indices.append(UInt32(i * 3))
            indices.append(UInt32(i * 3 + 1))
            indices.append(UInt32(i * 3 + 2))
        }
        
        return indices
    }
    
    // MARK: - Statistics
    
    private func resetStatistics() {
        frameCount = 0
        lastStatisticsUpdate = 0
        lastFrameTime = 0
        frameTimeAccumulator = 0
        pointsProcessedSinceLastUpdate = 0
        statistics = PipelineStatistics()
    }
    
    private func updateStatistics(currentTime: TimeInterval) {
        let voxelStats = pointCloudProcessor.getStatistics()
        let trackingQuality = spatialTracker.currentPose.trackingQuality
        
        // Calculate frame rate
        let elapsedTime = frameTimeAccumulator
        let fps = elapsedTime > 0 ? Float(frameCount) / Float(elapsedTime) : 0
        
        // Calculate processing latency (approximate)
        let avgFrameTime = elapsedTime / Double(max(1, frameCount))
        
        // Calculate points per second
        let pps = statisticsUpdateInterval > 0 
            ? Int(Double(pointsProcessedSinceLastUpdate) / statisticsUpdateInterval) 
            : 0
        
        // Estimate memory usage
        let pointMemory = Float(voxelStats.voxelCount * MemoryLayout<LiDARPoint>.stride) / (1024 * 1024)
        
        statistics = PipelineStatistics(
            frameRate: fps,
            processingLatency: avgFrameTime,
            pointsPerSecond: pps,
            voxelCount: voxelStats.voxelCount,
            memoryUsageMB: pointMemory,
            trackingQuality: trackingQuality
        )
        
        // Reset counters
        pointsProcessedSinceLastUpdate = 0
    }
    
    private func printFinalStatistics() {
        let stats = pointCloudProcessor.getStatistics()
        print("""
        📊 Pipeline Statistics:
           - Total points processed: \(stats.pointsProcessed)
           - Voxels stored: \(stats.voxelCount)
           - Compression ratio: \(String(format: "%.1f%%", stats.compressionRatio * 100))
           - Bounds: \(stats.boundsMin) to \(stats.boundsMax)
        """)
    }
    
    // MARK: - Subscriptions
    
    private func setupSubscriptions() {
        // Subscribe to filtered points for feature detection
        pointCloudProcessor.filteredPointsPublisher
            .receive(on: processingQueue)
            .sink { [weak self] batch in
                // Could trigger feature detection here
                // self?.triggerFeatureDetection(for: batch)
            }
            .store(in: &cancellables)
        
        // Subscribe to pose updates
        spatialTracker.posePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pose in
                // Could update UI with tracking quality
                _ = pose.trackingQuality
            }
            .store(in: &cancellables)
    }
}

// MARK: - Data Flow Diagram

/*
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │                         PIPELINE DATA FLOW                                   │
 │                                                                              │
 │  ┌──────────────┐                                                           │
 │  │   ARFrame    │ ─────────────────────────────────────────────────┐        │
 │  │  (60 fps)    │                                                  │        │
 │  └──────┬───────┘                                                  │        │
 │         │                                                          ▼        │
 │         │        ┌────────────────────┐                  ┌─────────────────┐│
 │         ├───────►│  SpatialTracker    │◄─────────────────│   IMU (100Hz)   ││
 │         │        │  (Drift Correct)   │                  └─────────────────┘│
 │         │        └────────┬───────────┘                                     │
 │         │                 │ TrackedPose                                     │
 │         │                 ▼                                                 │
 │  ┌──────┴───────┐  ┌─────────────────────┐                                 │
 │  │ ARMeshAnchor │  │PointCloudProcessor  │                                 │
 │  │  (per frame) │──│   (Voxel Filter)    │                                 │
 │  └──────────────┘  │   2cm grid          │                                 │
 │                    └──────────┬──────────┘                                 │
 │                               │ Filtered PointBatch                        │
 │                               ▼                                            │
 │                    ┌─────────────────────┐                                 │
 │                    │  FeatureExtractor   │                                 │
 │                    │  (L-M Fitting)      │                                 │
 │                    └──────────┬──────────┘                                 │
 │                               │ DetectedObjects                            │
 │                               ▼                                            │
 │                    ┌─────────────────────┐     ┌────────────────┐          │
 │                    │   AsyncExporter     │────►│   USDZ File    │          │
 │                    │   (Background)      │     └────────────────┘          │
 │                    └─────────────────────┘                                 │
 │                                                                             │
 │  THREADING:                                                                 │
 │  ─────────                                                                  │
 │  Main Thread:       ARFrame reception, UI updates                          │
 │  IMU Queue:         100Hz pose integration                                  │
 │  Mesh Queue:        Point extraction (QoS: userInteractive)                │
 │  Processing Queue:  Voxel filtering (QoS: userInitiated)                   │
 │  Export Queue:      USDZ generation (QoS: userInitiated)                   │
 │                                                                             │
 └─────────────────────────────────────────────────────────────────────────────┘
*/
