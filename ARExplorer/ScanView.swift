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

                Spacer()

                scanFrame
                modePicker

                Spacer()

                bottomControls
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 90)
        }
        .onAppear {
            if startScanOnAppear {
                startScanOnAppear = false
                startScan()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .scanStatsUpdated)) { notification in
            if let stats = notification.object as? ScanStats {
                pointCount = stats.pointCount
                scanDistance = stats.maxDistance
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
            StatPill(icon: "ruler", text: String(format: "%.1fm DIST", scanDistance))
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
