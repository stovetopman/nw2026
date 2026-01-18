import ARKit
import Foundation

class PointCloudRecorder {
    // We store points as simple strings for the PLY file (X Y Z R G B)
    private var points: [String] = []
    private var pointKeys: Set<PointKey> = []  // For deduplication
    private let queue = DispatchQueue(label: "com.lidar.recorder", qos: .userInitiated)
    
    // We don't want to save every single frame (too much data), so we skip some
    private var frameCounter = 0
    private let frameSkip = 5  // Process every 5th frame
    
    // Callback for live visualization - sends new points to visualizer
    var onNewPoints: (([ScannedPoint]) -> Void)?
    
    // Maximum distance from camera to capture points (in meters)
    private let maxDistance: Float = 1.0
    private let minDistance: Float = 0.1
    
    // Grid scale for deduplication (higher = finer detail, more points)
    // 500 means points within 2mm are considered duplicates
    private let gridScale: Float = 500.0
    
    private struct PointKey: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
    }
    
    var pointCount: Int {
        return points.count
    }
    
    func reset() {
        queue.async { [weak self] in
            self?.points.removeAll(keepingCapacity: true)
            self?.pointKeys.removeAll(keepingCapacity: true)
            self?.frameCounter = 0
        }
    }
    
    func process(frame: ARFrame) {
        // Run on background thread to avoid freezing UI
        queue.async { [weak self] in
            guard let self = self else { return }
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
            var newPointsBatch: [ScannedPoint] = []  // For live visualization
            
            // 4. Iterate through pixels
            // We skip pixels to balance quality and performance (step by 2 for higher density)
            for y in stride(from: 0, to: depthHeight, by: 2) {
                for x in stride(from: 0, to: depthWidth, by: 2) {
                    
                    // Read depth value (Float32)
                    let depthOffset = y * depthBytesPerRow + x * MemoryLayout<Float32>.size
                    let depthInMeters = depthBase.load(fromByteOffset: depthOffset, as: Float32.self)
                    
                    // Filter: Only capture points within our distance range
                    if depthInMeters < self.minDistance || depthInMeters > self.maxDistance { continue }
                    if depthInMeters.isNaN || depthInMeters.isInfinite { continue }
                    
                    // --- MATH: Un-project 2D pixel to 3D Local Point ---
                    // Using scaled intrinsics (fx, fy, cx, cy defined above)
                    let xRw = (Float(x) - cx) * depthInMeters / fx
                    let yRw = (Float(y) - cy) * depthInMeters / fy
                    let zRw = -depthInMeters  // Camera looks down -Z axis
                    
                    // --- MATH: Transform Local Point to World Space ---
                    let localPoint = SIMD4<Float>(xRw, -yRw, zRw, 1)  // Flip Y for world coords
                    let worldPoint = cameraTransform * localPoint
                    
                    // Deduplication check
                    let key = PointKey(
                        x: Int32((worldPoint.x * self.gridScale).rounded()),
                        y: Int32((worldPoint.y * self.gridScale).rounded()),
                        z: Int32((worldPoint.z * self.gridScale).rounded())
                    )
                    if self.pointKeys.contains(key) { continue }
                    self.pointKeys.insert(key)
                    
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
                    
                    // Save string line: "X Y Z R G B"
                    self.points.append(String(format: "%.5f %.5f %.5f %d %d %d",
                                              worldPoint.x, worldPoint.y, worldPoint.z,
                                              r, g, b))
                    
                    // Add to batch for live visualization
                    newPointsBatch.append(ScannedPoint(
                        position: SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z),
                        color: (r: r, g: g, b: b)
                    ))
                }
            }
            
            // Send batch to visualizer callback
            if !newPointsBatch.isEmpty {
                self.onNewPoints?(newPointsBatch)
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
            let fileName = "PointCloud_\(timestamp).ply"
            
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent(fileName)
            
            do {
                try fileContent.write(to: url, atomically: true, encoding: .ascii)
                print("✅ Saved PLY to: \(url.path)")
                print("✅ Total points: \(self.points.count)")
                
                // List documents folder
                let contents = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
                print("📂 Documents folder contents:")
                for file in contents ?? [] {
                    print("   - \(file.lastPathComponent)")
                }
                
                DispatchQueue.main.async { completion(url) }
            } catch {
                print("❌ Error saving PLY: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
