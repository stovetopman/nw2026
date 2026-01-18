import ARKit
import Foundation

/// Metadata saved alongside PLY file to help orient the viewer correctly
struct ScanMetadata: Codable {
    /// Position where the scan started (world coords, usually near 0,0,0)
    let recorderPosition: [Float]  // [x, y, z]
    
    /// The 3D point at the center of screen when recording started (crosshair target)
    /// This gives us the forward direction vector: crosshairPoint - recorderPosition
    let crosshairPoint: [Float]  // [x, y, z]
    
    /// The camera's up vector when recording started (typically close to world Y-up)
    let upVector: [Float]  // [x, y, z]
    
    /// The camera's forward vector when recording started
    let forwardVector: [Float]  // [x, y, z]
    
    /// The camera's right vector when recording started  
    let rightVector: [Float]  // [x, y, z]
    
    /// The full camera transform matrix when recording started (4x4 as flat array, column-major)
    let initialCameraTransform: [Float]
    
    // MARK: - Convenience accessors as SIMD3
    
    var recorderPositionSIMD: SIMD3<Float> {
        SIMD3<Float>(recorderPosition[0], recorderPosition[1], recorderPosition[2])
    }
    
    var crosshairPointSIMD: SIMD3<Float> {
        SIMD3<Float>(crosshairPoint[0], crosshairPoint[1], crosshairPoint[2])
    }
    
    var upVectorSIMD: SIMD3<Float> {
        SIMD3<Float>(upVector[0], upVector[1], upVector[2])
    }
    
    var forwardVectorSIMD: SIMD3<Float> {
        SIMD3<Float>(forwardVector[0], forwardVector[1], forwardVector[2])
    }
    
    var rightVectorSIMD: SIMD3<Float> {
        SIMD3<Float>(rightVector[0], rightVector[1], rightVector[2])
    }
    
    /// Computed: direction from recorder to crosshair (normalized)
    var lookDirection: SIMD3<Float> {
        let dir = crosshairPointSIMD - recorderPositionSIMD
        let length = simd_length(dir)
        return length > 0.001 ? dir / length : SIMD3<Float>(0, 0, -1)
    }
    
    // MARK: - Initializer from SIMD types
    
    init(recorderPosition: SIMD3<Float>, crosshairPoint: SIMD3<Float>, 
         upVector: SIMD3<Float>, forwardVector: SIMD3<Float>, 
         rightVector: SIMD3<Float>, initialCameraTransform: [Float]) {
        self.recorderPosition = [recorderPosition.x, recorderPosition.y, recorderPosition.z]
        self.crosshairPoint = [crosshairPoint.x, crosshairPoint.y, crosshairPoint.z]
        self.upVector = [upVector.x, upVector.y, upVector.z]
        self.forwardVector = [forwardVector.x, forwardVector.y, forwardVector.z]
        self.rightVector = [rightVector.x, rightVector.y, rightVector.z]
        self.initialCameraTransform = initialCameraTransform
    }
}

class PointCloudRecorder {
    // We store points as simple strings for the PLY file (X Y Z R G B)
    private var points: [String] = []
    private var pointKeys: Set<PointKey> = []  // For PLY deduplication
    private var vizPointKeys: Set<PointKey> = []  // For visualization deduplication (separate)
    private let queue = DispatchQueue(label: "com.lidar.recorder", qos: .userInitiated)
    
    // We don't want to save every single frame (too much data), so we skip some
    private var frameCounter = 0
    private let frameSkip = 5  // Process every 5th frame
    
    // Callback for live visualization - sends new points to visualizer
    var onNewPoints: (([ScannedPoint]) -> Void)?
    
    // Maximum distance from camera to capture points (in meters)
    // LiDAR typically works up to ~5m, but accuracy decreases with distance
    private var maxDistance: Float = 1.0
    private let minDistance: Float = 0.1
    
    // Grid scale for deduplication (higher = finer detail, more points)
    // 500 means points within 2mm are considered duplicates
    private let gridScale: Float = 500.0
    // Coarser grid for visualization (100 = ~1cm resolution)
    private let vizGridScale: Float = 25.0
    
    // Scan metadata - captured when recording starts
    private var scanMetadata: ScanMetadata?
    private var hasRecordedInitialFrame = false
    
    private struct PointKey: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
    }
    
    init() {
        // Listen for distance updates from UI
        NotificationCenter.default.addObserver(
            forName: .updateScanDistance,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            if let distance = notification.object as? Float {
                self?.queue.async {
                    self?.maxDistance = distance
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    var currentMaxDistance: Float {
        return maxDistance
    }
    
    var pointCount: Int {
        return points.count
    }
    
    func reset() {
        queue.async { [weak self] in
            self?.points.removeAll(keepingCapacity: true)
            self?.pointKeys.removeAll(keepingCapacity: true)
            self?.vizPointKeys.removeAll(keepingCapacity: true)
            self?.frameCounter = 0
            self?.scanMetadata = nil
            self?.hasRecordedInitialFrame = false
        }
    }
    
    func process(frame: ARFrame) {
        // Run on background thread to avoid freezing UI
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Capture initial frame metadata (camera orientation when scan started)
            if !self.hasRecordedInitialFrame {
                self.captureInitialMetadata(from: frame)
                self.hasRecordedInitialFrame = true
            }
            
            self.frameCounter += 1
            if self.frameCounter % self.frameSkip != 0 { return }
            
            // 1. Get the data - need sceneDepth for LiDAR depth map
            guard let sceneDepth = frame.sceneDepth,
                  let colorImage = frame.capturedImage as CVPixelBuffer? else { return }
            
            let depthMap = sceneDepth.depthMap
            
            // 2. Prepare to read data
            let cameraTransform = frame.camera.transform
            
            // Use the depth map's own intrinsics (not the color camera intrinsics)
            // The depth map has different resolution than the color image
            let depthWidth = CVPixelBufferGetWidth(depthMap)
            let depthHeight = CVPixelBufferGetHeight(depthMap)
            
            // Scale intrinsics from color image resolution to depth map resolution
            let colorWidth = CVPixelBufferGetWidth(colorImage)
            let colorHeight = CVPixelBufferGetHeight(colorImage)
            
            // ARKit intrinsics are for the color image, we need to scale them for depth
            let scaleX = Float(depthWidth) / Float(colorWidth)
            let scaleY = Float(depthHeight) / Float(colorHeight)
            
            let intrinsics = frame.camera.intrinsics
            let fx = intrinsics.columns.0.x * scaleX  // focal length x (scaled)
            let fy = intrinsics.columns.1.y * scaleY  // focal length y (scaled)
            let cx = intrinsics.columns.2.x * scaleX  // principal point x (scaled)
            let cy = intrinsics.columns.2.y * scaleY  // principal point y (scaled)
            
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            CVPixelBufferLockBaseAddress(colorImage, .readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
                CVPixelBufferUnlockBaseAddress(colorImage, .readOnly)
            }
            
            let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let depthBase = CVPixelBufferGetBaseAddress(depthMap)!
            
            // For YCbCr color buffer (iPhone camera format)
            let yPlane = CVPixelBufferGetBaseAddressOfPlane(colorImage, 0)!
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(colorImage, 0)
            let cbcrPlane = CVPixelBufferGetBaseAddressOfPlane(colorImage, 1)!
            let cbcrBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(colorImage, 1)
            
            // 3. Scale factor for color mapping (Depth map is smaller than Color image)
            let colorScaleX = Float(colorWidth) / Float(depthWidth)
            let colorScaleY = Float(colorHeight) / Float(depthHeight)
            
            let beforeCount = self.points.count
            var newPointsBatch: [ScannedPoint] = []  // For live visualization (sparse)
            
            // Helper function to process a single pixel
            func processPixel(x: Int, y: Int, forVisualization: Bool) -> (worldPoint: SIMD4<Float>, r: UInt8, g: UInt8, b: UInt8)? {
                // Read depth value (Float32)
                let depthOffset = y * depthBytesPerRow + x * MemoryLayout<Float32>.size
                let depthInMeters = depthBase.load(fromByteOffset: depthOffset, as: Float32.self)
                
                // Filter: Only capture points within our distance range
                if depthInMeters < self.minDistance || depthInMeters > self.maxDistance { return nil }
                if depthInMeters.isNaN || depthInMeters.isInfinite { return nil }
                
                // --- MATH: Un-project 2D pixel to 3D Local Point ---
                let xRw = (Float(x) - cx) * depthInMeters / fx
                let yRw = (Float(y) - cy) * depthInMeters / fy
                let zRw = -depthInMeters  // Camera looks down -Z axis
                
                // --- MATH: Transform Local Point to World Space ---
                let localPoint = SIMD4<Float>(xRw, -yRw, zRw, 1)  // Flip Y for world coords
                let worldPoint = cameraTransform * localPoint
                
                // Deduplication check
                if forVisualization {
                    // Use coarser grid for visualization dedup (~1cm)
                    let key = PointKey(
                        x: Int32((worldPoint.x * self.vizGridScale).rounded()),
                        y: Int32((worldPoint.y * self.vizGridScale).rounded()),
                        z: Int32((worldPoint.z * self.vizGridScale).rounded())
                    )
                    if self.vizPointKeys.contains(key) { return nil }
                    self.vizPointKeys.insert(key)
                } else {
                    // Use fine grid for PLY dedup (~2mm)
                    let key = PointKey(
                        x: Int32((worldPoint.x * self.gridScale).rounded()),
                        y: Int32((worldPoint.y * self.gridScale).rounded()),
                        z: Int32((worldPoint.z * self.gridScale).rounded())
                    )
                    if self.pointKeys.contains(key) { return nil }
                    self.pointKeys.insert(key)
                }
                
                // --- COLOR: Map to RGB from YCbCr ---
                let colorX = min(Int(Float(x) * colorScaleX), colorWidth - 1)
                let colorY = min(Int(Float(y) * colorScaleY), colorHeight - 1)
                
                // Read Y (luminance)
                let yIndex = colorY * yBytesPerRow + colorX
                let yValue = Float(yPlane.load(fromByteOffset: yIndex, as: UInt8.self))
                
                // Read CbCr (chroma) - subsampled by 2
                let cbcrX = colorX / 2 * 2
                let cbcrY = colorY / 2
                let cbcrIndex = cbcrY * cbcrBytesPerRow + cbcrX
                let cb = Float(cbcrPlane.load(fromByteOffset: cbcrIndex, as: UInt8.self)) - 128.0
                let cr = Float(cbcrPlane.load(fromByteOffset: cbcrIndex + 1, as: UInt8.self)) - 128.0
                
                // YCbCr to RGB conversion
                let r = UInt8(clamping: Int(yValue + 1.402 * cr))
                let g = UInt8(clamping: Int(yValue - 0.344136 * cb - 0.714136 * cr))
                let b = UInt8(clamping: Int(yValue + 1.772 * cb))
                
                return (worldPoint, r, g, b)
            }
            
            // 4. SPARSE loop for visualization (every 16th pixel) - run first, no dedup
            for y in stride(from: 0, to: depthHeight, by: 16) {
                for x in stride(from: 0, to: depthWidth, by: 16) {
                    if let result = processPixel(x: x, y: y, forVisualization: true) {
                        newPointsBatch.append(ScannedPoint(
                            position: SIMD3<Float>(result.worldPoint.x, result.worldPoint.y, result.worldPoint.z),
                            color: (r: result.r, g: result.g, b: result.b)
                        ))
                    }
                }
            }
            
            // 5. HIGH-RESOLUTION loop for PLY file (every 2nd pixel) - with dedup
            for y in stride(from: 0, to: depthHeight, by: 2) {
                for x in stride(from: 0, to: depthWidth, by: 2) {
                    if let result = processPixel(x: x, y: y, forVisualization: false) {
                        // Save string line: "X Y Z R G B"
                        self.points.append(String(format: "%.5f %.5f %.5f %d %d %d",
                                                  result.worldPoint.x, result.worldPoint.y, result.worldPoint.z,
                                                  result.r, result.g, result.b))
                    }
                }
            }
            
            // Send batch to visualizer callback
            if !newPointsBatch.isEmpty {
                self.onNewPoints?(newPointsBatch)
            }
            
            // Broadcast stats update to UI
            let currentPointCount = self.points.count
            DispatchQueue.main.async {
                let stats = ScanStats(pointCount: currentPointCount, maxDistance: self.maxDistance)
                NotificationCenter.default.post(name: .scanStatsUpdated, object: stats)
            }
            
            // Log progress
            let newPoints = self.points.count - beforeCount
            if newPoints > 0 && self.points.count % 10000 < newPoints {
                print("📍 Total points: \(self.points.count)")
            }
        }
    }
    
    func savePLY(completion: @escaping (URL?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let header = """
            ply
            format ascii 1.0
            element vertex \(self.points.count)
            property float x
            property float y
            property float z
            property uchar red
            property uchar green
            property uchar blue
            end_header
            
            """
            
            let fileContent = header + self.points.joined(separator: "\n")
            
            // Save to Documents directory
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            let plyFileName = "PointCloud_\(timestamp).ply"
            let metaFileName = "PointCloud_\(timestamp).meta.json"
            
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let plyURL = docs.appendingPathComponent(plyFileName)
            let metaURL = docs.appendingPathComponent(metaFileName)
            
            do {
                // Save PLY file
                try fileContent.write(to: plyURL, atomically: true, encoding: .ascii)
                print("✅ Saved PLY to: \(plyURL.path)")
                print("✅ Total points: \(self.points.count)")
                
                // Save metadata JSON
                if let metadata = self.scanMetadata {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let metaData = try encoder.encode(metadata)
                    try metaData.write(to: metaURL)
                    print("✅ Saved metadata to: \(metaURL.path)")
                }
                
                // List documents folder
                let contents = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
                print("📂 Documents folder contents:")
                for file in contents ?? [] {
                    print("   - \(file.lastPathComponent)")
                }
                
                DispatchQueue.main.async { completion(plyURL) }
            } catch {
                print("❌ Error saving PLY: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    /// Capture the camera orientation and crosshair point when recording starts
    private func captureInitialMetadata(from frame: ARFrame) {
        let cameraTransform = frame.camera.transform
        
        // Extract camera position (translation component)
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        // Extract camera orientation vectors from the transform matrix
        // Column 0 = Right vector, Column 1 = Up vector, Column 2 = Forward (looking direction is -Z)
        let rightVector = SIMD3<Float>(
            cameraTransform.columns.0.x,
            cameraTransform.columns.0.y,
            cameraTransform.columns.0.z
        )
        let upVector = SIMD3<Float>(
            cameraTransform.columns.1.x,
            cameraTransform.columns.1.y,
            cameraTransform.columns.1.z
        )
        // Camera looks down -Z axis, so forward = negative of column 2
        let forwardVector = SIMD3<Float>(
            -cameraTransform.columns.2.x,
            -cameraTransform.columns.2.y,
            -cameraTransform.columns.2.z
        )
        
        // Calculate crosshair point: a point 1 meter in front of camera center
        // This represents where the user was looking when they started the scan
        let crosshairPoint = cameraPosition + forwardVector * 1.0
        
        // Flatten the 4x4 transform matrix for JSON storage
        let transformArray: [Float] = [
            cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z, cameraTransform.columns.0.w,
            cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z, cameraTransform.columns.1.w,
            cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z, cameraTransform.columns.2.w,
            cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z, cameraTransform.columns.3.w
        ]
        
        scanMetadata = ScanMetadata(
            recorderPosition: cameraPosition,
            crosshairPoint: crosshairPoint,
            upVector: upVector,
            forwardVector: forwardVector,
            rightVector: rightVector,
            initialCameraTransform: transformArray
        )
        
        print("📷 Captured initial scan metadata:")
        print("   Position: \(cameraPosition)")
        print("   Looking at: \(crosshairPoint)")
        print("   Forward: \(forwardVector)")
        print("   Up: \(upVector)")
    }
}
