import SwiftUI
import ARKit
import simd

/// View shown after scan completes, allowing user to add notes to the point cloud
struct PostScanNoteView: View {
    let plyURL: URL
    let folderURL: URL
    @ObservedObject var noteStore: NoteStore
    var onDone: () -> Void
    
    @State private var showingNoteInput = false
    @State private var noteText = ""
    @State private var crosshairPoint: SIMD3<Float>? = nil
    @State private var addedNotes: [SpatialNote] = []
    @State private var selectedNoteID: UUID? = nil
    @State private var editingNote: SpatialNote? = nil
    
    var body: some View {
        ZStack {
            // AR View for aiming at points
            PostScanARContainer(
                plyURL: plyURL,
                onCrosshairUpdate: { point in
                    crosshairPoint = point
                },
                notes: addedNotes,
                selectedNoteID: $selectedNoteID
            )
            .ignoresSafeArea()
            
            // Grid overlay
            GridOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // UI Overlay
            VStack(spacing: 0) {
                // Top bar
                topBar
                
                Spacer()
                
                // Crosshair
                crosshair
                
                // Hint text
                if !showingNoteInput && selectedNoteID == nil {
                    hintText
                        .padding(.top, 20)
                }
                
                // Selected note card
                if let noteID = selectedNoteID,
                   let note = addedNotes.first(where: { $0.id == noteID }) {
                    NoteCardView(
                        note: note,
                        onEdit: {
                            editingNote = note
                            noteText = note.text
                            showingNoteInput = true
                        },
                        onDelete: {
                            withAnimation {
                                addedNotes.removeAll { $0.id == noteID }
                                noteStore.delete(note)
                                selectedNoteID = nil
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                Spacer()
                
                // Bottom buttons
                bottomButtons
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            
            // Note input overlay
            if showingNoteInput {
                noteInputOverlay
            }
        }
        .onAppear {
            // Load existing notes
            addedNotes = noteStore.notes
        }
    }
    
    private var topBar: some View {
        HStack {
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
            }
            
            Spacer()
            
            // Mode indicator
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .bold))
                Text("EXPLORE MODE")
                    .font(AppTheme.titleFont(size: 12))
            }
            .foregroundColor(AppTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.ink, lineWidth: 2)
                    )
            )
            
            Spacer()
            
            // Filter button placeholder
            Button(action: {}) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var crosshair: some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 30)
            
            // Horizontal line
            Rectangle()
                .fill(Color.white)
                .frame(width: 30, height: 2)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
    
    private var hintText: some View {
        Text("Hover over dots to reveal memories")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.5))
            )
    }
    
    private var bottomButtons: some View {
        VStack(spacing: 16) {
            // Add Thought button
            Button(action: {
                if crosshairPoint != nil {
                    editingNote = nil
                    noteText = ""
                    showingNoteInput = true
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.bubble.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Add Thought")
                        .font(AppTheme.titleFont(size: 16))
                }
                .foregroundColor(AppTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )
                )
            }
            .padding(.horizontal, 40)
            .opacity(crosshairPoint != nil ? 1.0 : 0.5)
            .disabled(crosshairPoint == nil)
            
            // Save Memory button
            Button(action: onDone) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Save Memory")
                        .font(AppTheme.titleFont(size: 16))
                }
                .foregroundColor(AppTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppTheme.accentYellow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )
                )
            }
            .padding(.horizontal, 40)
        }
    }
    
    private var noteInputOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showingNoteInput = false
                    }
                }
            
            // Input card
            VStack(spacing: 20) {
                // Header
                HStack {
                    Text(editingNote != nil ? "Edit Thought" : "Add Thought")
                        .font(AppTheme.titleFont(size: 18))
                        .foregroundColor(AppTheme.ink)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            showingNoteInput = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.ink.opacity(0.6))
                    }
                }
                
                // Text input
                TextField("What's on your mind?", text: $noteText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.ink)
                    .padding()
                    .frame(minHeight: 100, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.ink.opacity(0.3), lineWidth: 1)
                            )
                    )
                
                // Save button
                Button(action: saveNote) {
                    Text("Save")
                        .font(AppTheme.titleFont(size: 16))
                        .foregroundColor(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppTheme.accentYellow)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.accentYellow.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(AppTheme.ink, lineWidth: 2)
                    )
            )
            .padding(.horizontal, 30)
        }
    }
    
    private func saveNote() {
        guard let position = crosshairPoint,
              !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        if let existingNote = editingNote {
            // Update existing note
            var updated = existingNote
            updated.text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let index = addedNotes.firstIndex(where: { $0.id == existingNote.id }) {
                addedNotes[index] = updated
            }
            noteStore.update(updated)
        } else {
            // Create new note
            let note = SpatialNote(
                text: noteText.trimmingCharacters(in: .whitespacesAndNewlines),
                author: "me",
                position: position
            )
            addedNotes.append(note)
            noteStore.add(note)
        }
        
        withAnimation {
            showingNoteInput = false
            noteText = ""
            editingNote = nil
        }
    }
}

/// AR container for post-scan note adding
struct PostScanARContainer: UIViewRepresentable {
    let plyURL: URL
    var onCrosshairUpdate: (SIMD3<Float>?) -> Void
    let notes: [SpatialNote]
    @Binding var selectedNoteID: UUID?
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.session.delegate = context.coordinator
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true
        context.coordinator.arView = arView
        
        // Load point cloud
        loadPointCloud(into: arView.scene, coordinator: context.coordinator)
        
        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        arView.session.run(config)
        
        // Start crosshair detection
        context.coordinator.startCrosshairDetection()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.onCrosshairUpdate = onCrosshairUpdate
        context.coordinator.updateNoteMarkers(notes: notes, selectedID: selectedNoteID)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCrosshairUpdate: onCrosshairUpdate)
    }
    
    private func loadPointCloud(into scene: SCNScene, coordinator: Coordinator) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let points = try PLYPointCloud.read(from: plyURL)
                let node = createPointCloudNode(from: points)
                
                DispatchQueue.main.async {
                    scene.rootNode.addChildNode(node)
                    coordinator.pointCloudNode = node
                    coordinator.loadedPoints = points
                    coordinator.buildSpatialIndex()
                }
            } catch {
                print("❌ Failed to load PLY: \(error)")
            }
        }
    }
    
    private func createPointCloudNode(from points: [PLYPoint]) -> SCNNode {
        guard !points.isEmpty else { return SCNNode() }
        
        var positions: [Float] = []
        var colors: [Float] = []
        positions.reserveCapacity(points.count * 3)
        colors.reserveCapacity(points.count * 4)
        
        for point in points {
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
        geometry.materials = [material]
        
        return SCNNode(geometry: geometry)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARSCNView?
        var pointCloudNode: SCNNode?
        var loadedPoints: [PLYPoint] = []
        var onCrosshairUpdate: (SIMD3<Float>?) -> Void
        var noteMarkerNodes: [UUID: SCNNode] = [:]
        var displayLink: CADisplayLink?
        
        // Spatial index for efficient point lookup
        var pointSpatialIndex: [SIMD3<Int>: [Int]] = [:]
        let gridSize: Float = 0.1 // 10cm grid cells
        
        init(onCrosshairUpdate: @escaping (SIMD3<Float>?) -> Void) {
            self.onCrosshairUpdate = onCrosshairUpdate
            super.init()
        }
        
        deinit {
            displayLink?.invalidate()
        }
        
        func buildSpatialIndex() {
            pointSpatialIndex.removeAll()
            for (index, point) in loadedPoints.enumerated() {
                let key = SIMD3<Int>(
                    Int(floor(point.position.x / gridSize)),
                    Int(floor(point.position.y / gridSize)),
                    Int(floor(point.position.z / gridSize))
                )
                pointSpatialIndex[key, default: []].append(index)
            }
        }
        
        func startCrosshairDetection() {
            displayLink = CADisplayLink(target: self, selector: #selector(updateCrosshair))
            displayLink?.add(to: .main, forMode: .common)
        }
        
        @objc func updateCrosshair() {
            guard let arView = arView else { return }
            
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            // Use SceneKit hit test on the point cloud node
            if let hitPoint = performRaycast(from: center) {
                onCrosshairUpdate(hitPoint)
            } else {
                // Fallback: cast ray and place at fixed distance
                if let fallbackPoint = getRayPoint(from: center, distance: 1.5) {
                    onCrosshairUpdate(fallbackPoint)
                } else {
                    onCrosshairUpdate(nil)
                }
            }
        }
        
        /// Perform raycast to find closest point cloud point along the ray
        func performRaycast(from screenPoint: CGPoint) -> SIMD3<Float>? {
            guard let arView = arView,
                  let camera = arView.pointOfView,
                  !loadedPoints.isEmpty else { return nil }
            
            // Get ray from camera through screen point
            let nearPoint = arView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 0))
            let farPoint = arView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 1))
            
            let rayOrigin = SIMD3<Float>(nearPoint.x, nearPoint.y, nearPoint.z)
            let rayEnd = SIMD3<Float>(farPoint.x, farPoint.y, farPoint.z)
            let rayDir = simd_normalize(rayEnd - rayOrigin)
            
            // Find closest point to the ray
            var closestPoint: SIMD3<Float>? = nil
            var minDistToRay: Float = 0.15 // Max distance from ray (15cm)
            
            // Sample points along the ray and check nearby grid cells
            for t in stride(from: Float(0.3), through: Float(5.0), by: Float(0.1)) {
                let samplePoint = rayOrigin + rayDir * t
                let gridKey = SIMD3<Int>(
                    Int(floor(samplePoint.x / gridSize)),
                    Int(floor(samplePoint.y / gridSize)),
                    Int(floor(samplePoint.z / gridSize))
                )
                
                // Check this cell and neighbors
                for dx in -1...1 {
                    for dy in -1...1 {
                        for dz in -1...1 {
                            let neighborKey = gridKey &+ SIMD3<Int>(dx, dy, dz)
                            guard let indices = pointSpatialIndex[neighborKey] else { continue }
                            
                            for idx in indices {
                                let point = loadedPoints[idx].position
                                
                                // Calculate distance from point to ray
                                let toPoint = point - rayOrigin
                                let projLength = simd_dot(toPoint, rayDir)
                                
                                // Skip points behind camera
                                if projLength < 0.2 { continue }
                                
                                let projPoint = rayOrigin + rayDir * projLength
                                let distToRay = simd_length(point - projPoint)
                                
                                if distToRay < minDistToRay {
                                    minDistToRay = distToRay
                                    closestPoint = point
                                }
                            }
                        }
                    }
                }
                
                // If we found a close enough point, stop searching
                if closestPoint != nil && minDistToRay < 0.05 {
                    break
                }
            }
            
            return closestPoint
        }
        
        /// Get a point along the ray at a fixed distance (fallback)
        func getRayPoint(from screenPoint: CGPoint, distance: Float) -> SIMD3<Float>? {
            guard let arView = arView,
                  let camera = arView.pointOfView else { return nil }
            
            let nearPoint = arView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 0))
            let farPoint = arView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 1))
            
            let rayOrigin = SIMD3<Float>(nearPoint.x, nearPoint.y, nearPoint.z)
            let rayEnd = SIMD3<Float>(farPoint.x, farPoint.y, farPoint.z)
            let rayDir = simd_normalize(rayEnd - rayOrigin)
            
            return rayOrigin + rayDir * distance
        }
        
        func updateNoteMarkers(notes: [SpatialNote], selectedID: UUID?) {
            guard let arView = arView else { return }
            
            // Remove old markers not in notes
            let noteIDs = Set(notes.map { $0.id })
            for (id, node) in noteMarkerNodes where !noteIDs.contains(id) {
                node.removeFromParentNode()
                noteMarkerNodes.removeValue(forKey: id)
            }
            
            // Add/update markers
            for note in notes {
                if let existingNode = noteMarkerNodes[note.id] {
                    // Update position if needed
                    existingNode.simdPosition = note.position
                    // Update appearance based on selection
                    updateMarkerAppearance(existingNode, isSelected: note.id == selectedID)
                } else {
                    // Create new marker
                    let markerNode = createNoteMarker(isSelected: note.id == selectedID)
                    markerNode.simdPosition = note.position
                    arView.scene.rootNode.addChildNode(markerNode)
                    noteMarkerNodes[note.id] = markerNode
                }
            }
        }
        
        func createNoteMarker(isSelected: Bool) -> SCNNode {
            let sphere = SCNSphere(radius: 0.02)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(AppTheme.accentYellow)
            material.emission.contents = UIColor(AppTheme.accentYellow).withAlphaComponent(0.3)
            sphere.materials = [material]
            
            let node = SCNNode(geometry: sphere)
            
            if isSelected {
                // Add pulsing animation
                let pulse = CABasicAnimation(keyPath: "scale")
                pulse.fromValue = SCNVector3(1, 1, 1)
                pulse.toValue = SCNVector3(1.3, 1.3, 1.3)
                pulse.duration = 0.5
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                node.addAnimation(pulse, forKey: "pulse")
            }
            
            return node
        }
        
        func updateMarkerAppearance(_ node: SCNNode, isSelected: Bool) {
            if isSelected {
                node.removeAnimation(forKey: "pulse")
                let pulse = CABasicAnimation(keyPath: "scale")
                pulse.fromValue = SCNVector3(1, 1, 1)
                pulse.toValue = SCNVector3(1.3, 1.3, 1.3)
                pulse.duration = 0.5
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                node.addAnimation(pulse, forKey: "pulse")
            } else {
                node.removeAnimation(forKey: "pulse")
                node.scale = SCNVector3(1, 1, 1)
            }
        }
    }
}

// Simple grid overlay
private struct GridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let spacing: CGFloat = 28
                for x in stride(from: 0, through: proxy.size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
                for y in stride(from: 0, through: proxy.size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }
}
