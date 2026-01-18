import SwiftUI
import SceneKit
import simd

struct MemoryViewerView: View {
    let item: MemoryItem
    var onClose: () -> Void

    @State private var showShare = false
    @StateObject private var noteStore: NoteStore
    @StateObject private var viewerCoordinator = NoteViewerCoordinator()
    @State private var selectedNoteID: UUID?
    
    // Note placement state
    @State private var isPlacingNote = false
    @State private var pinPosition: CGPoint = .zero
    @State private var pinPlaced = false
    @State private var newNoteText = ""
    @State private var placedWorldPosition: SIMD3<Float> = .zero
    
    // Edit state
    @State private var editingNote: SpatialNote?
    @State private var editText = ""
    
    // Timer for crosshair focus tracking
    @State private var focusTimer: Timer?
    
    init(item: MemoryItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        self._noteStore = StateObject(wrappedValue: NoteStore(folderURL: item.folderURL))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Point cloud viewer
                ViewerView(plyURL: item.plyURL, viewerCoordinator: viewerCoordinator)
                    .ignoresSafeArea()
                
                // Note markers overlay (shows yellow dots for notes) - NOT in Immersive mode
                if viewerCoordinator.isReady && !isPlacingNote && viewerCoordinator.currentViewMode != .immersive {
                    NoteMarkersOverlay(
                        notes: noteStore.notes,
                        scnView: viewerCoordinator.scnView,
                        pointCloudCenter: viewerCoordinator.pointCloudCenter,
                        selectedNoteID: $selectedNoteID
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(!isPlacingNote && viewerCoordinator.currentViewMode != .birdview)
                }
                
                // Crosshair for birdview mode (NOT in Immersive mode)
                if viewerCoordinator.currentViewMode == .birdview && !isPlacingNote && editingNote == nil {
                    crosshairView
                }
                
                // Placement mode overlay (NOT in Immersive mode)
                if isPlacingNote && viewerCoordinator.currentViewMode != .immersive {
                    placementOverlay
                }
                
                // Show note card when crosshair focuses on a note (birdview mode only, NOT Immersive)
                if viewerCoordinator.currentViewMode == .birdview,
                   !isPlacingNote,
                   let focusedID = viewerCoordinator.crosshairFocusedNoteID,
                   let focusedNote = noteStore.notes.first(where: { $0.id == focusedID }) {
                    birdviewNoteCard(note: focusedNote)
                }
                
                // Selected note card (overview mode only, NOT Immersive or birdview)
                if viewerCoordinator.currentViewMode == .overview,
                   !isPlacingNote,
                   let selectedNote = noteStore.notes.first(where: { $0.id == selectedNoteID }) {
                    selectedNoteOverlay(note: selectedNote)
                }
                
                // Edit note overlay (NOT in Immersive mode)
                if let note = editingNote, viewerCoordinator.currentViewMode != .immersive {
                    editNoteOverlay(note: note)
                }

                // UI Controls
                if !isPlacingNote && editingNote == nil {
                    controlsOverlay
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [item.plyURL])
        }
        .onAppear {
            startFocusTimer()
        }
        .onDisappear {
            stopFocusTimer()
        }
    }
    
    // MARK: - Focus Timer
    
    private func startFocusTimer() {
        focusTimer?.invalidate()
        focusTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            viewerCoordinator.updateCrosshairFocus(notes: noteStore.notes)
        }
    }
    
    private func stopFocusTimer() {
        focusTimer?.invalidate()
        focusTimer = nil
    }
    
    // MARK: - Placement Overlay
    
    private var placementOverlay: some View {
        ZStack {
            // Semi-transparent overlay - tapping cancels
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            
            // The draggable pin - starts in center, user drags to position
            DraggableNotePin(position: $pinPosition, isPlaced: pinPlaced)
                .position(pinPosition)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !pinPlaced else { return }
                            pinPosition = value.location
                        }
                        .onEnded { value in
                            guard !pinPlaced else { return }
                            pinPosition = value.location
                            placePin()
                        }
                )
            
            // Inline input appears after placing
            if pinPlaced {
                InlineNoteInput(
                    text: $newNoteText,
                    onSave: saveNewNote,
                    onCancel: cancelPlacement
                )
                .position(x: pinPosition.x, y: min(pinPosition.y + 100, UIScreen.main.bounds.height - 200))
            }
            
            // Top bar with cancel and confirm buttons
            VStack {
                HStack {
                    Button(action: cancelPlacement) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            )
                    }
                    
                    Spacer()
                    
                    if !pinPlaced {
                        Text("Drag pin to position")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    
                    Spacer()
                    
                    if !pinPlaced {
                        Button(action: placePin) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.ink)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(AppTheme.accentYellow)
                                        .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                Spacer()
            }
        }
        .onAppear {
            // Start pin in center of screen
            let screenCenter = CGPoint(
                x: UIScreen.main.bounds.width / 2,
                y: UIScreen.main.bounds.height / 2
            )
            pinPosition = screenCenter
        }
    }
    
    private func placePin() {
        if let scnView = viewerCoordinator.scnView {
            let hitPoint = scnView.unprojectPoint(SCNVector3(
                Float(pinPosition.x),
                Float(pinPosition.y),
                0.5
            ))
            placedWorldPosition = SIMD3<Float>(
                Float(hitPoint.x),
                Float(hitPoint.y),
                Float(hitPoint.z)
            ) + viewerCoordinator.pointCloudCenter
        }
        
        withAnimation(.spring(response: 0.3)) {
            pinPlaced = true
        }
    }
    
    // MARK: - Selected Note Overlay
    
    private func selectedNoteOverlay(note: SpatialNote) -> some View {
        VStack {
            Spacer()
            NoteCardView(
                note: note,
                onEdit: {
                    editingNote = note
                    editText = note.text
                    selectedNoteID = nil
                },
                onDelete: {
                    withAnimation {
                        noteStore.delete(note)
                        selectedNoteID = nil
                    }
                }
            )
            .frame(maxWidth: 320)
            .padding(.horizontal, 20)
            .padding(.bottom, 180)
            .transition(.scale.combined(with: .opacity))
            .onTapGesture { }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                selectedNoteID = nil
            }
        }
    }
    
    // MARK: - Edit Note Overlay
    
    private func editNoteOverlay(note: SpatialNote) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { editingNote = nil }
            
            VStack {
                Spacer()
                InlineNoteInput(
                    text: $editText,
                    onSave: {
                        var updated = note
                        updated.text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                        noteStore.update(updated)
                        editingNote = nil
                    },
                    onCancel: { editingNote = nil }
                )
                .padding(.horizontal, 20)
                Spacer().frame(height: 200)
            }
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                        )
                    }

                    if !noteStore.notes.isEmpty && viewerCoordinator.currentViewMode != .immersive {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(noteStore.notes.count) NOTES")
                                .font(AppTheme.titleFont(size: 12))
                        }
                        .foregroundColor(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.accentYellow)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.ink, lineWidth: 2))
                        )
                    }

                    viewModeIndicator
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                        Text("MEMORY")
                            .font(AppTheme.titleFont(size: 12))
                    }
                    Text("Captured\n\(relativeDateText)")
                        .font(AppTheme.displayFont(size: 18))
                }
                .foregroundColor(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.accentPink)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppTheme.ink, lineWidth: 2))
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()

            // Bottom controls - simplified
            HStack(spacing: 16) {
                Button(action: { showShare = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.95))
                                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                        )
                }
                
                Button(action: recenter) {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(AppTheme.accentBlue)
                            .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                    )
                }
                
                // Hide add note button in Immersive mode
                if viewerCoordinator.currentViewMode != .immersive {
                    Button(action: startPlacingNote) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(AppTheme.accentYellow)
                                    .overlay(Circle().stroke(AppTheme.ink, lineWidth: 2))
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 90)
        }
    }

    private var viewModeIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: viewerCoordinator.currentViewMode.icon)
                .font(.system(size: 10, weight: .bold))
            Text(viewerCoordinator.currentViewMode.rawValue.uppercased())
                .font(AppTheme.titleFont(size: 11))
        }
        .foregroundColor(AppTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.9))
                .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 2))
        )
    }
    
    // MARK: - Actions
    
    private func startPlacingNote() {
        withAnimation(.spring(response: 0.3)) {
            isPlacingNote = true
            pinPlaced = false
            pinPosition = .zero
            newNoteText = ""
            selectedNoteID = nil
        }
    }
    
    private func cancelPlacement() {
        withAnimation(.spring(response: 0.3)) {
            isPlacingNote = false
            pinPlaced = false
            pinPosition = .zero
            newNoteText = ""
        }
    }
    
    private func saveNewNote() {
        let trimmedText = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        let note = SpatialNote(
            text: trimmedText,
            author: "me",
            position: placedWorldPosition
        )
        noteStore.add(note)
        
        withAnimation(.spring(response: 0.3)) {
            isPlacingNote = false
            pinPlaced = false
            pinPosition = .zero
            newNoteText = ""
        }
    }

    private var relativeDateText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: item.date, relativeTo: Date())
    }

    private func recenter() {
        NotificationCenter.default.post(name: .viewerRecenter, object: nil)
    }
    
    // MARK: - Crosshair View (Immersive Mode)
    
    private var crosshairView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // Simple crosshair
                ZStack {
                    // Horizontal line
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 24, height: 2)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    // Vertical line
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 24)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    // Center dot
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4, height: 4)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
                Spacer()
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Birdview Note Card (when crosshair focuses on a note)
    
    private func birdviewNoteCard(note: SpatialNote) -> some View {
        VStack {
            Spacer()
            
            // Note card appears at bottom of screen
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(AppTheme.accentYellow)
                    Text(note.author)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                    Spacer()
                    Text(note.date, style: .relative)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.ink.opacity(0.6))
                }
                
                Text(note.text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: note.id)
        }
        .allowsHitTesting(false)
    }
}
