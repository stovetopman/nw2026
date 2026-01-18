import SwiftUI
import SceneKit
import UIKit
import simd
import CoreMotion

// View mode enum
enum ViewerMode: String, CaseIterable {
    case immersive = "Immersive"
    case overview = "Overview"
    
    var icon: String {
        switch self {
        case .immersive: return "person.fill"
        case .overview: return "eye.fill"
        }
    }
}

struct ViewerView: View {
    let plyURL: URL
    @ObservedObject var viewerCoordinator: NoteViewerCoordinator
    @State private var isLoading = true
    @State private var loadingProgress: String = "Reading file..."
    @State private var viewMode: ViewerMode = .immersive

    var body: some View {
        ZStack {
            ViewerPointCloudContainer(
                plyURL: plyURL,
                isLoading: $isLoading,
                loadingProgress: $loadingProgress,
                viewerCoordinator: viewerCoordinator,
                viewMode: $viewMode
            )
            .ignoresSafeArea()
            
            if isLoading {
                loadingOverlay
            }
            
            // View mode toggle button (bottom right)
            if !isLoading {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        viewModeButton
                    }
                }
                .padding(.bottom, 40)
                .padding(.trailing, 20)
            }
        }
    }
    
    private var viewModeButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewMode = viewMode == .immersive ? .overview : .immersive
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: viewMode == .immersive ? "eye.fill" : "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(viewMode == .immersive ? "Overview" : "Immersive")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.8))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            )
        }
    }
    
    private var loadingOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text(loadingProgress)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
            
            Text("PREPARING MEMORY")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .tracking(2)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct ViewerPointCloudContainer: UIViewRepresentable {
    let plyURL: URL
    @Binding var isLoading: Bool
    @Binding var loadingProgress: String
    var viewerCoordinator: NoteViewerCoordinator
    @Binding var viewMode: ViewerMode

    final class Coordinator {
        weak var scnView: SCNView?
        var pointNode: SCNNode?
        var cameraNode: SCNNode?
        var pointCloudCenter: SIMD3<Float> = .zero
        var pointCloudBounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
        
        // Scan metadata for proper orientation
        var scanMetadata: ScanMetadata?
        
        // Motion manager for immersive mode
        var motionManager: CMMotionManager?
        var displayLink: CADisplayLink?
        var initialAttitude: CMAttitude?
        var currentViewMode: ViewerMode = .immersive
        
        // Base orientation from metadata (applied before device motion)
        var baseYaw: Float = 0
        var basePitch: Float = 0
        
        // Gesture recognizers for overview mode
        var panGesture: UIPanGestureRecognizer?
        var pinchGesture: UIPinchGestureRecognizer?
        var orbitAngleX: Float = 0
        var orbitAngleY: Float = 0.5  // Start looking slightly down
        var orbitDistance: Float = 3.0
        
        deinit {
            stopMotionUpdates()
        }
        
        func setupOverviewGestures(for view: SCNView) {
            // Remove existing gestures if any
            removeOverviewGestures(from: view)
            
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            view.addGestureRecognizer(pan)
            panGesture = pan
            
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            view.addGestureRecognizer(pinch)
            pinchGesture = pinch
        }
        
        func removeOverviewGestures(from view: SCNView) {
            if let pan = panGesture {
                view.removeGestureRecognizer(pan)
                panGesture = nil
            }
            if let pinch = pinchGesture {
                view.removeGestureRecognizer(pinch)
                pinchGesture = nil
            }
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard currentViewMode == .overview else { return }
            
            let translation = gesture.translation(in: gesture.view)
            
            // Rotate around the point cloud
            orbitAngleX += Float(translation.x) * 0.005
            orbitAngleY += Float(translation.y) * 0.005
            
            // Clamp vertical angle to avoid flipping
            orbitAngleY = max(-Float.pi * 0.4, min(Float.pi * 0.4, orbitAngleY))
            
            updateOverviewCamera()
            
            gesture.setTranslation(.zero, in: gesture.view)
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard currentViewMode == .overview else { return }
            
            if gesture.state == .changed {
                orbitDistance /= Float(gesture.scale)
                orbitDistance = max(0.5, min(20.0, orbitDistance))  // Clamp distance
                gesture.scale = 1.0
                
                updateOverviewCamera()
            }
        }
        
        func updateOverviewCamera() {
            guard let cameraNode = cameraNode else { return }
            
            let center = pointCloudCenter
            
            // Calculate camera position on a sphere around the center
            let x = center.x + orbitDistance * cos(orbitAngleY) * sin(orbitAngleX)
            let y = center.y + orbitDistance * sin(orbitAngleY)
            let z = center.z + orbitDistance * cos(orbitAngleY) * cos(orbitAngleX)
            
            cameraNode.position = SCNVector3(x, y, z)
            cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        }
        
        /// Calculate initial orientation from scan metadata, or fallback to point cloud center
        /// Returns the target point to look at (relative to origin)
        func calculateLookAtTarget() -> SCNVector3 {
            // If we have scan metadata, use the recorded forward direction
            if let metadata = scanMetadata {
                // Forward vector gives us the direction the camera was facing
                // We want to look in that direction from origin
                let forward = metadata.forwardVectorSIMD
                
                // Target is a point in the forward direction from origin
                let target = SCNVector3(forward.x, forward.y, forward.z)
                print("📷 Using metadata forward vector as target: \(forward)")
                return target
            }
            
            // Fallback: Look at point cloud center
            let center = pointCloudCenter
            
            // If center is basically at origin, look forward (-Z direction)
            guard simd_length(center) > 0.01 else {
                return SCNVector3(0, 0, -1)
            }
            
            print("📷 Fallback: looking at point cloud center: \(center)")
            return SCNVector3(center.x, center.y, center.z)
        }
        
        /// Apply initial orientation to camera using the recorded camera transform
        func applyInitialOrientation(to cameraNode: SCNNode) {
            // Position camera slightly back from origin for better view of points
            // The scan was made at origin, so we pull back a bit to see more context
            let pullBackDistance: Float = 0.7  // 0.5 meters back from origin
            
            // If we have metadata with the original camera transform, use it directly
            if let metadata = scanMetadata {
                let forward = metadata.forwardVectorSIMD
                let up = metadata.upVectorSIMD
                
                // Position camera pulled back along the opposite of forward direction
                let backDirection = -simd_normalize(forward)
                cameraNode.position = SCNVector3(
                    backDirection.x * pullBackDistance,
                    backDirection.y * pullBackDistance,
                    backDirection.z * pullBackDistance
                )
                
                // Calculate look-at target (in the forward direction from new position)
                let target = SCNVector3(forward.x, forward.y, forward.z)
                
                // Use the recorded up vector for proper orientation
                cameraNode.look(at: target, up: SCNVector3(up.x, up.y, up.z), localFront: SCNVector3(0, 0, -1))
                
                print("📷 Applied metadata orientation:")
                print("   Forward: \(forward)")
                print("   Up: \(up)")
                print("   Camera position: \(cameraNode.position)")
            } else {
                // Fallback: look at point cloud center, pull back from it
                let target = calculateLookAtTarget()
                let dir = simd_normalize(SIMD3<Float>(target.x, target.y, target.z))
                cameraNode.position = SCNVector3(
                    -dir.x * pullBackDistance,
                    -dir.y * pullBackDistance,
                    -dir.z * pullBackDistance
                )
                cameraNode.look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            }
            
            // Store the resulting euler angles as base orientation for motion tracking
            baseYaw = cameraNode.eulerAngles.y
            basePitch = cameraNode.eulerAngles.x
            
            print("📷 Camera euler angles - Pitch: \(basePitch * 180 / .pi)°, Yaw: \(baseYaw * 180 / .pi)°")
        }
        
        func startMotionUpdates() {
            guard motionManager == nil else { return }
            
            let manager = CMMotionManager()
            manager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 FPS
            
            if manager.isDeviceMotionAvailable {
                manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
                motionManager = manager
                
                // Use display link for smooth updates
                let link = CADisplayLink(target: self, selector: #selector(updateMotion))
                link.add(to: .main, forMode: .common)
                displayLink = link
                
                // Capture initial orientation after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.initialAttitude = self?.motionManager?.deviceMotion?.attitude
                }
            }
        }
        
        func stopMotionUpdates() {
            displayLink?.invalidate()
            displayLink = nil
            motionManager?.stopDeviceMotionUpdates()
            motionManager = nil
            initialAttitude = nil
        }
        
        @objc func updateMotion() {
            guard currentViewMode == .immersive,
                  let motion = motionManager?.deviceMotion,
                  let cameraNode = cameraNode else { return }
            
            // Get device orientation
            let attitude = motion.attitude
            
            // Get RELATIVE rotation by removing initial attitude
            // This gives us the delta rotation since motion tracking started
            if let initial = initialAttitude {
                attitude.multiply(byInverseOf: initial)
            }
            
            // Convert CMQuaternion to simd quaternion
            // This is now Identity (no rotation) at start, representing "change since start"
            let q = attitude.quaternion
            let deviceQuat = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
            
            // Base orientation from scan metadata (the correct starting orientation)
            // This was set by applyInitialOrientation using look(at:)
            let baseQuat = simd_quatf(angle: baseYaw, axis: SIMD3<Float>(0, 1, 0)) *
                           simd_quatf(angle: basePitch, axis: SIMD3<Float>(1, 0, 0))
            
            // Combine: base orientation * relative device rotation
            // Since deviceQuat is RELATIVE (delta from start), we don't need any
            // static axis-swapping transform like phoneToCamera
            let finalQuat = baseQuat * deviceQuat
            
            // Apply to camera
            cameraNode.simdOrientation = finalQuat
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    /// Load scan metadata from JSON file alongside the PLY
    private func loadMetadata(for plyURL: URL) -> ScanMetadata? {
        // Metadata file has same name as PLY but with .meta.json extension
        let metaFileName = plyURL.deletingPathExtension().lastPathComponent + ".meta.json"
        let metaURL = plyURL.deletingLastPathComponent().appendingPathComponent(metaFileName)
        
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            print("📄 No metadata file found at: \(metaURL.path)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: metaURL)
            let metadata = try JSONDecoder().decode(ScanMetadata.self, from: data)
            print("📄 Loaded scan metadata:")
            print("   Forward: \(metadata.forwardVectorSIMD)")
            print("   Up: \(metadata.upVectorSIMD)")
            return metadata
        } catch {
            print("❌ Failed to load metadata: \(error)")
            return nil
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        context.coordinator.scnView = scnView
        
        // Publish to coordinator for note overlay access
        DispatchQueue.main.async {
            self.viewerCoordinator.scnView = scnView
        }
        
        let scene = SCNScene()
        scnView.scene = scene
        scnView.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        scnView.autoenablesDefaultLighting = false
        
        // Start in immersive mode - no gesture control, device motion controls view
        scnView.allowsCameraControl = false
        context.coordinator.currentViewMode = .immersive
        
        // Add ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 1000
        ambientLight.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Add camera at origin (where the scanner was standing)
        let camera = SCNCamera()
        camera.zNear = 0.001  // 1mm - very close objects visible
        camera.zFar = 100.0   // 100m far plane
        camera.fieldOfView = 60  // Natural FOV
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 0)  // Start at origin where scanner stood
        scene.rootNode.addChildNode(cameraNode)
        context.coordinator.cameraNode = cameraNode
        scnView.pointOfView = cameraNode

        NotificationCenter.default.addObserver(forName: .viewerRecenter, object: nil, queue: .main) { _ in
            recenter(context: context)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                DispatchQueue.main.async {
                    self.loadingProgress = "Reading PLY file..."
                }
                
                // Load scan metadata if available
                let metadata = self.loadMetadata(for: self.plyURL)
                
                let points = try PLYPointCloud.read(from: self.plyURL)
                
                DispatchQueue.main.async {
                    self.loadingProgress = "Processing \(formatPointCount(points.count)) points..."
                }
                
                let (node, center, bounds) = self.makePointCloudNode(from: points)
                
                DispatchQueue.main.async {
                    self.loadingProgress = "Rendering..."
                }
                
                DispatchQueue.main.async {
                    scene.rootNode.addChildNode(node)
                    context.coordinator.pointNode = node
                    context.coordinator.pointCloudCenter = center
                    context.coordinator.pointCloudBounds = bounds
                    context.coordinator.scanMetadata = metadata
                    
                    // Publish center to viewerCoordinator for note overlay
                    self.viewerCoordinator.pointCloudCenter = center
                    self.viewerCoordinator.isReady = true
                    
                    // Apply initial orientation from metadata using look(at:)
                    context.coordinator.applyInitialOrientation(to: cameraNode)
                    
                    // Start motion tracking for immersive mode
                    context.coordinator.startMotionUpdates()
                    
                    // Hide loading indicator
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.isLoading = false
                    }
                }
            } catch {
                print("Failed to load PLY:", error)
                DispatchQueue.main.async {
                    self.loadingProgress = "Failed to load"
                    self.isLoading = false
                }
            }
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Handle view mode changes
        guard context.coordinator.currentViewMode != viewMode else { return }
        
        context.coordinator.currentViewMode = viewMode
        
        switch viewMode {
        case .immersive:
            // Immersive mode: camera at origin, device motion controls
            uiView.allowsCameraControl = false
            
            // Remove overview gestures
            context.coordinator.removeOverviewGestures(from: uiView)
            
            // Reset camera to origin, facing the recorded direction from metadata
            if let cameraNode = context.coordinator.cameraNode {
                // Re-apply orientation using the stored metadata
                context.coordinator.applyInitialOrientation(to: cameraNode)
            }
            
            // Reset point node position and rotation  
            if let pointNode = context.coordinator.pointNode {
                pointNode.position = SCNVector3Zero
                pointNode.eulerAngles = SCNVector3Zero
            }
            
            // Force the SCNView to use our camera node
            uiView.pointOfView = context.coordinator.cameraNode
            
            // Start motion tracking with fresh initial attitude
            context.coordinator.stopMotionUpdates()  // Stop first to reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                context.coordinator.startMotionUpdates()
            }
            
        case .overview:
            // Overview mode: camera orbits around point cloud with gesture controls
            uiView.allowsCameraControl = false  // We handle gestures ourselves
            
            // Stop motion tracking first
            context.coordinator.stopMotionUpdates()
            
            // Setup initial orbit parameters based on bounds
            if let bounds = context.coordinator.pointCloudBounds {
                let center = context.coordinator.pointCloudCenter
                let size = bounds.max - bounds.min
                let maxDimension = max(size.x, max(size.y, size.z))
                
                // Set initial orbit distance and angles
                context.coordinator.orbitDistance = maxDimension * 1.5 + 1.0
                context.coordinator.orbitAngleX = 0
                context.coordinator.orbitAngleY = 0.5  // Looking slightly down
                context.coordinator.pointCloudCenter = center
                
                // Update camera position
                context.coordinator.updateOverviewCamera()
            }
            
            // Ensure our camera is the point of view
            uiView.pointOfView = context.coordinator.cameraNode
            
            // Setup custom gesture recognizers
            context.coordinator.setupOverviewGestures(for: uiView)
        }
    }

    private func makePointCloudNode(from points: [PLYPoint]) -> (node: SCNNode, center: SIMD3<Float>, bounds: (min: SIMD3<Float>, max: SIMD3<Float>)) {
        guard !points.isEmpty else {
            return (SCNNode(), .zero, (min: .zero, max: .zero))
        }

        var minPoint = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

        for point in points {
            minPoint = simd_min(minPoint, point.position)
            maxPoint = simd_max(maxPoint, point.position)
        }

        let center = (minPoint + maxPoint) * 0.5

        var positions: [Float] = []
        var colors: [Float] = []
        positions.reserveCapacity(points.count * 3)
        colors.reserveCapacity(points.count * 4)

        for point in points {
            // Keep original world coordinates - don't center
            // This preserves the spatial relationship from the scan
            positions.append(point.position.x)
            positions.append(point.position.y)
            positions.append(point.position.z)

            colors.append(Float(point.color.x) / 255.0)
            colors.append(Float(point.color.y) / 255.0)
            colors.append(Float(point.color.z) / 255.0)
            colors.append(1.0)
        }

        let vertexData = positions.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: points.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: points.count,
            bytesPerIndex: 0
        )
        element.pointSize = 4.0
        element.minimumPointScreenSpaceRadius = 2.0
        element.maximumPointScreenSpaceRadius = 6.0

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.diffuse.contents = UIColor.white
        geometry.materials = [material]

        return (SCNNode(geometry: geometry), center, (min: minPoint, max: maxPoint))
    }

    private func recenter(context: Context) {
        guard let cameraNode = context.coordinator.cameraNode,
              let pointNode = context.coordinator.pointNode else { return }
        
        // Reset point cloud position
        pointNode.position = SCNVector3Zero
        pointNode.eulerAngles = SCNVector3Zero
        
        let currentMode = context.coordinator.currentViewMode
        
        if currentMode == .immersive {
            // In immersive mode, return camera to origin where the scanner stood
            cameraNode.position = SCNVector3(0, 0, 0)
            cameraNode.eulerAngles = SCNVector3Zero
            
            // Reset initial attitude for motion tracking
            context.coordinator.initialAttitude = context.coordinator.motionManager?.deviceMotion?.attitude
        } else {
            // In overview mode, reset to overview position
            if let bounds = context.coordinator.pointCloudBounds {
                let center = context.coordinator.pointCloudCenter
                let size = bounds.max - bounds.min
                let maxDimension = max(size.x, max(size.y, size.z))
                let distance = maxDimension * 1.5 + 1.0
                
                cameraNode.position = SCNVector3(
                    center.x,
                    center.y + distance * 0.6,
                    center.z + distance * 0.8
                )
                cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
            }
        }
    }
}

private func formatPointCount(_ count: Int) -> String {
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
        return String(format: "%.0fK", Double(count) / 1_000)
    } else {
        return "\(count)"
    }
}
