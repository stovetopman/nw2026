import SwiftUI

struct ScanView: View {
    @ObservedObject var store: MemoryStore
    @Binding var startScanOnAppear: Bool
    var onBack: () -> Void
    var onOpenLatest: (MemoryItem) -> Void

    @State private var isRecording = false
    @State private var scanMode: ScanMode = .point
    @State private var pointCount: Int = 0
    @State private var scanDistance: Float = 1.0
    @State private var showDistanceSlider = false
    @State private var userSetDistance: Float = 1.0
    @State private var isAddingNote = false
    @State private var noteText = ""

    var body: some View {
        ZStack {
            ARViewContainer()
                .ignoresSafeArea()

            GridOverlay()
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // Crosshair for note placement
            if isAddingNote {
                NotePlacementCrosshair()
                    .allowsHitTesting(false)
            }

            VStack(spacing: 16) {
                topBar
                statsRow
                
                if showDistanceSlider {
                    distanceSlider
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                scanFrame
                modePicker

                Spacer()
                
                // Note input when adding
                if isAddingNote {
                    noteInputCard
                        .transition(.scale.combined(with: .opacity))
                }

                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 90)
        }
        .animation(.spring(response: 0.3), value: isAddingNote)
        .onAppear {
            if startScanOnAppear {
                startScanOnAppear = false
                startScan()
            }
            // Set initial distance on recorder
            NotificationCenter.default.post(name: .updateScanDistance, object: userSetDistance)
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanStatsUpdated)) { notification in
            if let stats = notification.object as? ScanStats {
                pointCount = stats.pointCount
                // Don't overwrite user's distance setting
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
            Button(action: { withAnimation(.spring(response: 0.3)) { showDistanceSlider.toggle() } }) {
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
                    .onChange(of: userSetDistance) { newValue in
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
        HStack(spacing: 18) {
            // Add Note button
            Button(action: { isAddingNote.toggle() }) {
                Image(systemName: isAddingNote ? "xmark" : "note.text.badge.plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isAddingNote ? .white : AppTheme.ink)
                    .frame(width: 54, height: 54)
                    .background(
                        Circle()
                            .fill(isAddingNote ? AppTheme.accentYellow : Color.white.opacity(0.9))
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
        }
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
        NotificationCenter.default.post(name: .startScan, object: nil)
    }

    private func stopScan() {
        isRecording = false
        NotificationCenter.default.post(name: .saveScan, object: nil)
    }

    private func capturePhoto() {
        NotificationCenter.default.post(name: .capturePhoto, object: nil)
    }
    
    private var noteInputCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .bold))
                Text("Aim crosshair and add note")
                    .font(AppTheme.titleFont(size: 12))
            }
            .foregroundColor(AppTheme.ink.opacity(0.7))
            
            HStack(spacing: 10) {
                TextField("What's here?", text: $noteText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.ink)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.ink.opacity(0.3), lineWidth: 1)
                            )
                    )
                
                Button(action: createNote) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(noteText.isEmpty ? AppTheme.ink.opacity(0.3) : AppTheme.ink)
                        )
                }
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.accentYellow)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
    
    private func createNote() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Create note at screen center via notification
        let payload = CreateNotePayload(text: text)
        NotificationCenter.default.post(name: .createSpatialNote, object: payload)
        
        // Reset state
        noteText = ""
        isAddingNote = false
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

/// Crosshair overlay for targeting note placement
struct NotePlacementCrosshair: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Outer animated ring
            Circle()
                .stroke(AppTheme.accentYellow, lineWidth: 2)
                .frame(width: 60, height: 60)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0.3 : 0.8)
            
            // Middle ring
            Circle()
                .stroke(AppTheme.accentYellow, lineWidth: 2)
                .frame(width: 40, height: 40)
            
            // Center dot
            Circle()
                .fill(AppTheme.accentYellow)
                .frame(width: 8, height: 8)
            
            // Crosshair lines
            Path { path in
                // Horizontal lines
                path.move(to: CGPoint(x: -30, y: 0))
                path.addLine(to: CGPoint(x: -15, y: 0))
                path.move(to: CGPoint(x: 15, y: 0))
                path.addLine(to: CGPoint(x: 30, y: 0))
                
                // Vertical lines
                path.move(to: CGPoint(x: 0, y: -30))
                path.addLine(to: CGPoint(x: 0, y: -15))
                path.move(to: CGPoint(x: 0, y: 15))
                path.addLine(to: CGPoint(x: 0, y: 30))
            }
            .stroke(AppTheme.accentYellow, lineWidth: 2)
            .frame(width: 60, height: 60)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
