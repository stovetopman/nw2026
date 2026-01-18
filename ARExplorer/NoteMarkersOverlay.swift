import SwiftUI
import SceneKit
import simd

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
                ForEach(notes) { note in
                    if let screenPos = screenPositions[note.id],
                       isOnScreen(screenPos, in: geometry.size) {
                        NoteMarkerView(isSelected: selectedNoteID == note.id)
                            .position(screenPos)
                            .onTapGesture {
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
    
    private func isOnScreen(_ point: CGPoint, in size: CGSize) -> Bool {
        point.x >= 0 && point.x <= size.width &&
        point.y >= 0 && point.y <= size.height
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
        guard let scnView = scnView else { return }
        
        var newPositions: [UUID: CGPoint] = [:]
        
        for note in notes {
            // Adjust position relative to point cloud center (since we center the cloud)
            let adjustedPosition = note.position - pointCloudCenter
            let scnPosition = SCNVector3(adjustedPosition.x, adjustedPosition.y, adjustedPosition.z)
            let projected = scnView.projectPoint(scnPosition)
            
            // Only include if in front of camera (z < 1)
            if projected.z < 1 && projected.z > 0 {
                newPositions[note.id] = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
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
