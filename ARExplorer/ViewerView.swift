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
        
        // Motion manager for immersive mode
        var motionManager: CMMotionManager?
        var displayLink: CADisplayLink?
        var initialAttitude: CMAttitude?
        var currentViewMode: ViewerMode = .immersive
        
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
            
            // Get device orientation and apply to camera
            let attitude = motion.attitude
            
            // If we have an initial attitude, use relative orientation
            if let initial = initialAttitude {
                attitude.multiply(byInverseOf: initial)
            }
            
            // Convert device rotation to camera orientation
            // Phone held vertically: pitch controls looking up/down, yaw controls left/right
            let pitch = Float(attitude.pitch)  // Looking up/down
            let yaw = Float(attitude.yaw)      // Looking left/right
            let roll = Float(attitude.roll)    // Head tilt
            
            // Apply rotation - adjust for how phone is typically held
            cameraNode.eulerAngles = SCNVector3(
                -pitch + .pi / 2,  // Compensate for phone being vertical
                yaw,
                -roll
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
                
                let points = try PLYPointCloud.read(from: plyURL)
                
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
                    
                    // Publish center to viewerCoordinator for note overlay
                    self.viewerCoordinator.pointCloudCenter = center
                    self.viewerCoordinator.isReady = true
                    
                    // Start in immersive mode at origin
                    cameraNode.position = SCNVector3(0, 0, 0)
                    cameraNode.eulerAngles = SCNVector3Zero
                    
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
            
            // Reset camera to origin with no rotation
            if let cameraNode = context.coordinator.cameraNode {
                cameraNode.position = SCNVector3(0, 0, 0)
                cameraNode.eulerAngles = SCNVector3Zero
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
