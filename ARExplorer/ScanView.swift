import SwiftUI
import ARKit
import simd

struct ScanView: View {
    @ObservedObject var store: MemoryStore
    @Binding var startScanOnAppear: Bool
    var onBack: () -> Void
    var onOpenLatest: (MemoryItem) -> Void

    @State private var isRecording = false
    @State private var scanMode: ScanMode = .point
    @State private var pointCount: Int = 0
    @State private var scanDistance: Float = 3.5
    @State private var showDistanceSlider = false
    @State private var userSetDistance: Float = 3.5
    @State private var confidenceThreshold: ConfidenceThreshold = .high
    @State private var showConfidencePicker = false
    
    // Live note adding during scan
    @State private var showNoteInput = false
    @State private var noteText = ""
    @State private var pendingNotes: [SpatialNote] = []
    @State private var currentFolderURL: URL? = nil
    @State private var lastCameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, -1.5)

    var body: some View {
        ZStack {
            ARViewContainer()
                .ignoresSafeArea()

            GridOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                topBar
                statsRow
                
                if showDistanceSlider {
                    distanceSlider
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                if showConfidencePicker {
                    confidencePicker
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Crosshair (only when recording)
                if isRecording {
                    crosshair
                }

                scanFrame

                Spacer()

                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 90)
            
            // Note input overlay
            if showNoteInput {
                noteInputOverlay
            }
        }
        .onAppear {
            if startScanOnAppear {
                startScanOnAppear = false
                startScan()
            }
            // Set initial distance on recorder
            NotificationCenter.default.post(name: .updateScanDistance, object: userSetDistance)
            // Set initial confidence threshold on recorder
            NotificationCenter.default.post(name: .updateConfidenceThreshold, object: confidenceThreshold)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanStatsUpdated)) { notification in
            if let stats = notification.object as? ScanStats {
                pointCount = stats.pointCount
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanFolderCreated)) { notification in
            // Capture the folder URL when scan starts
            if let url = notification.object as? URL {
                currentFolderURL = url
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanSaved)) { notification in
            // When scan is saved, save pending notes and refresh
            if let url = notification.object as? URL {
                let folderURL = url.deletingLastPathComponent()
                saveNotesToFolder(folderURL)
                store.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraPositionResponse)) { notification in
            // Update last camera position when received
            if let position = notification.object as? SIMD3<Float> {
                lastCameraPosition = position
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
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

            HStack(spacing: 10) {
                Circle()
                    .fill(isRecording ? AppTheme.accentBlue : AppTheme.accentPink)
                    .frame(width: 10, height: 10)
                Text(isRecording ? "LIDAR RECORDING" : "LIDAR READY")
                    .font(AppTheme.titleFont(size: 12))
                    .foregroundColor(AppTheme.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        Capsule()
                            .stroke(AppTheme.ink, lineWidth: 2)
                    )
            )

            Spacer()

            Button(action: {}) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .bold))
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
    }

    private var statsRow: some View {
        HStack {
            StatPill(icon: "cube", text: formattedPointCount)
            Spacer()
            Button(action: { 
                withAnimation(.spring(response: 0.3)) { 
                    showDistanceSlider.toggle()
                    if showDistanceSlider { showConfidencePicker = false }
                } 
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "ruler")
                        .font(.system(size: 12, weight: .bold))
                    Text(String(format: "%.1fm", userSetDistance))
                        .font(AppTheme.titleFont(size: 12))
                    Image(systemName: showDistanceSlider ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )
                )
            }
            
            Button(action: { 
                withAnimation(.spring(response: 0.3)) { 
                    showConfidencePicker.toggle()
                    if showConfidencePicker { showDistanceSlider = false }
                } 
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 12, weight: .bold))
                    Text(confidenceThreshold.title)
                        .font(AppTheme.titleFont(size: 12))
                    Image(systemName: showConfidencePicker ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )
                )
            }
        }
    }
    
    private var distanceSlider: some View {
        VStack(spacing: 8) {
            HStack {
                Text("SCAN RANGE")
                    .font(AppTheme.titleFont(size: 10))
                    .foregroundColor(AppTheme.ink.opacity(0.7))
                Spacer()
                Text(distanceLabel)
                    .font(AppTheme.titleFont(size: 10))
                    .foregroundColor(AppTheme.ink)
            }
            
            HStack(spacing: 12) {
                Text("0.5m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.ink.opacity(0.5))
                
                Slider(value: $userSetDistance, in: 0.5...5.0, step: 0.5)
                    .tint(AppTheme.accentBlue)
                    .onChange(of: userSetDistance) { oldValue, newValue in
                        NotificationCenter.default.post(name: .updateScanDistance, object: newValue)
                    }
                
                Text("5m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.ink.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
        )
    }
    
    private var distanceLabel: String {
        if userSetDistance <= 1.0 {
            return "CLOSE-UP"
        } else if userSetDistance <= 2.0 {
            return "NEAR"
        } else if userSetDistance <= 3.5 {
            return "MEDIUM"
        } else {
            return "FAR"
        }
    }
    
    private var confidencePicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("CONFIDENCE FILTER")
                    .font(AppTheme.titleFont(size: 10))
                    .foregroundColor(AppTheme.ink.opacity(0.7))
                Spacer()
            }
            
            HStack(spacing: 12) {
                ForEach(ConfidenceThreshold.allCases, id: \.self) { threshold in
                    Button(action: {
                        confidenceThreshold = threshold
                        NotificationCenter.default.post(name: .updateConfidenceThreshold, object: threshold)
                    }) {
                        Text(threshold.title)
                            .font(AppTheme.titleFont(size: 11))
                            .foregroundColor(confidenceThreshold == threshold ? .white : AppTheme.ink)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(confidenceThreshold == threshold ? AppTheme.ink : Color.white.opacity(0.7))
                                    .overlay(
                                        Capsule()
                                            .stroke(AppTheme.ink, lineWidth: confidenceThreshold == threshold ? 0 : 2)
                                    )
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
        )
    }
    
    private var formattedPointCount: String {
        if pointCount >= 1_000_000 {
            return String(format: "%.1fM PTS", Double(pointCount) / 1_000_000)
        } else if pointCount >= 1_000 {
            return String(format: "%.1fK PTS", Double(pointCount) / 1_000)
        } else {
            return "\(pointCount) PTS"
        }
    }

    private var scanFrame: some View {
        RoundedRectangle(cornerRadius: 22)
            .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [12, 10]))
            .frame(height: 240)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.8))
            )
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            ForEach(ScanMode.allCases, id: \.self) { mode in
                Button {
                    scanMode = mode
                } label: {
                    Text(mode.title)
                        .font(AppTheme.titleFont(size: 12))
                        .foregroundColor(scanMode == mode ? .white : AppTheme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(scanMode == mode ? AppTheme.ink : Color.white.opacity(0.85))
                                .overlay(
                                    Capsule()
                                        .stroke(AppTheme.ink, lineWidth: scanMode == mode ? 0 : 2)
                                )
                        )
                }
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.7))
                .overlay(
                    Capsule()
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
        )
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Add Thought button (only when recording)
            if isRecording {
                Button(action: { showNoteInput = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.bubble.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("ADD THOUGHT")
                            .font(AppTheme.titleFont(size: 14))
                    }
                    .foregroundColor(AppTheme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(AppTheme.accentYellow)
                            .overlay(
                                Capsule()
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            HStack(spacing: 18) {
                Button(action: capturePhoto) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.ink)
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.9))
                                .overlay(
                                    Circle()
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                }

                Button(action: toggleScan) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(isRecording ? Color.red : AppTheme.accentBlue)
                            .frame(width: 12, height: 12)
                        Text(isRecording ? "STOP SCAN" : "START SCAN")
                            .font(AppTheme.titleFont(size: 16))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(AppTheme.ink)
                    )
                }

                Button {
                    if let latest = store.memories.first {
                        onOpenLatest(latest)
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 54, height: 54)
                            .overlay(
                                Circle().stroke(AppTheme.ink, lineWidth: 2)
                            )
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.ink)
                            )

                    if store.memories.count > 0 {
                        Text("\(store.memories.count)")
                            .font(AppTheme.titleFont(size: 10))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(AppTheme.accentPink)
                                    .overlay(Circle().stroke(AppTheme.ink, lineWidth: 1))
                            )
                            .offset(x: 6, y: -6)
                    }
                }
            }
            } // HStack
        } // VStack
    }

    private func toggleScan() {
        if isRecording {
            stopScan()
        } else {
            startScan()
        }
    }

    private func startScan() {
        isRecording = true
        pendingNotes = []
        NotificationCenter.default.post(name: .startScan, object: nil)
    }

    private func stopScan() {
        isRecording = false
        NotificationCenter.default.post(name: .saveScan, object: nil)
    }

    private func capturePhoto() {
        NotificationCenter.default.post(name: .capturePhoto, object: nil)
    }
    
    // MARK: - Crosshair
    
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
            
            // Center dot
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
    
    // MARK: - Note Input Overlay
    
    private var noteInputOverlay: some View {
        ZStack {
            // Background dim
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showNoteInput = false }
                }
            
            // Note input card
            VStack(spacing: 20) {
                HStack {
                    Text("ADD THOUGHT")
                        .font(AppTheme.titleFont(size: 18))
                        .foregroundColor(AppTheme.ink)
                    Spacer()
                    Button(action: { withAnimation { showNoteInput = false } }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                            )
                    }
                }
                
                Text("Note will be placed where the crosshair is pointing")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.ink.opacity(0.7))
                
                TextField("What's on your mind?", text: $noteText, axis: .vertical)
                    .font(.system(size: 16))
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
                    .lineLimit(3...6)
                
                Button(action: addNote) {
                    Text("SAVE THOUGHT")
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
    
    // MARK: - Note Actions
    
    private func addNote() {
        guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Request the current camera position from ARViewContainer
        NotificationCenter.default.post(name: .requestCameraPosition, object: nil)
        
        // Small delay to allow the position response to arrive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let note = SpatialNote(
                text: noteText.trimmingCharacters(in: .whitespacesAndNewlines),
                author: "me",
                position: lastCameraPosition
            )
            pendingNotes.append(note)
            
            withAnimation {
                noteText = ""
                showNoteInput = false
            }
            
            print("✅ Added note at position: \(lastCameraPosition)")
        }
    }
    
    private func saveNotesToFolder(_ folderURL: URL) {
        guard !pendingNotes.isEmpty else { return }
        
        let noteStore = NoteStore(folderURL: folderURL)
        for note in pendingNotes {
            noteStore.add(note)
        }
        let count = pendingNotes.count
        pendingNotes = []
        print("✅ Saved \(count) notes to \(folderURL.lastPathComponent)")
    }
}

private enum ScanMode: CaseIterable {
    case point
    case mesh
    case texture

    var title: String {
        switch self {
        case .point: return "POINT"
        case .mesh: return "MESH"
        case .texture: return "TEXTURE"
        }
    }
}

private struct StatPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .font(AppTheme.titleFont(size: 12))
        }
        .foregroundColor(AppTheme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
        )
    }
}

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
