import SwiftUI
import SceneKit
import simd

// Extension to get world position from SCNNode
extension SCNNode {
    var worldPosition: SCNVector3 {
        return presentation.worldTransform.position
    }
}

extension SCNMatrix4 {
    var position: SCNVector3 {
        return SCNVector3(m41, m42, m43)
    }
}

/// Overlay that shows note markers projected from 3D to screen space
struct NoteMarkersOverlay: View {
    let notes: [SpatialNote]
    let scnView: SCNView?
    let pointCloudCenter: SIMD3<Float>
    @Binding var selectedNoteID: UUID?
    
    @State private var screenPositions: [UUID: CGPoint] = [:]
    @State private var updateTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Debug: show note count
                if !notes.isEmpty {
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(notes.count) note(s)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(4)
                        }
                        Spacer()
                    }
                }
                
                ForEach(notes) { note in
                    if let screenPos = screenPositions[note.id] {
                        NoteMarkerView(isSelected: selectedNoteID == note.id)
                            .position(screenPos)
                            .onTapGesture {
                                print("📝 Tapped note: \\(note.id.uuidString.prefix(8)) - \\(note.text.prefix(20))\")")
                                withAnimation(.spring(response: 0.3)) {
                                    if selectedNoteID == note.id {
                                        selectedNoteID = nil
                                    } else {
                                        selectedNoteID = note.id
                                    }
                                }
                            }
                    }
                }
            }
        }
        .onAppear {
            startUpdating()
        }
        .onDisappear {
            stopUpdating()
        }
        .onChange(of: notes.count) { _ in
            updatePositions()
        }
    }
    
    private func startUpdating() {
        updatePositions()
        // Update positions periodically to follow camera movement
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            updatePositions()
        }
    }
    
    private func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updatePositions() {
        guard let scnView = scnView else { 
            print("⚠️ No scnView available")
            return 
        }
        
        var newPositions: [UUID: CGPoint] = [:]
        let screenBounds = UIScreen.main.bounds
        
        for note in notes {
            // The note position is stored in world coordinates
            // Project directly without adjusting for center
            let scnPosition = SCNVector3(note.position.x, note.position.y, note.position.z)
            let projected = scnView.projectPoint(scnPosition)
            
            let screenPoint = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
            
            print("📍 Note \(note.id.uuidString.prefix(8)): 3D=\(note.position), screen=\(screenPoint), z=\(projected.z)")
            
            // Check if in front of camera (z between 0 and 1 in normalized depth)
            if projected.z > 0 && projected.z < 1 {
                // Clamp to screen bounds with padding
                let clampedX = max(30, min(screenBounds.width - 30, screenPoint.x))
                let clampedY = max(80, min(screenBounds.height - 120, screenPoint.y))
                newPositions[note.id] = CGPoint(x: clampedX, y: clampedY)
            }
        }
        
        screenPositions = newPositions
    }
}

/// A coordinator that bridges the SceneKit view to SwiftUI for note positioning
class NoteViewerCoordinator: ObservableObject {
    @Published var scnView: SCNView?
    @Published var pointCloudCenter: SIMD3<Float> = .zero
    @Published var isReady: Bool = false
}
