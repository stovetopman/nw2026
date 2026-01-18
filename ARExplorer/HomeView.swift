import SwiftUI
import Foundation

struct HomeView: View {
    @ObservedObject var store: MemoryStore
    var onStartScan: () -> Void
    var onOpenDirectory: () -> Void
    var onOpenMemory: (MemoryItem) -> Void

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    heroCard
                    recentSection
                    statsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accentBlue, AppTheme.accentPink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 24, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("WELCOME BACK!")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundColor(AppTheme.accentBlue)
                Text("Alex Chen")
                    .font(AppTheme.displayFont(size: 22))
                    .foregroundColor(AppTheme.ink)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LiDAR Ready")
                    .font(AppTheme.bodyFont(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(
                                Capsule()
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
                Spacer()
            }

            Text("Capture a\nNew Memory")
                .font(AppTheme.displayFont(size: 32))
                .foregroundColor(AppTheme.ink)

            Text("Create immersive spatial moments!\nScan your world in 3D and keep it forever.")
                .font(AppTheme.bodyFont(size: 14))
                .foregroundColor(AppTheme.softInk)

            Button(action: onStartScan) {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Start Scanning")
                        .font(AppTheme.titleFont(size: 16))
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.ink)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.98, blue: 1.0),
                            Color(red: 0.99, green: 0.95, blue: 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.accentBlue, AppTheme.accentPink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
        .shadow(color: AppTheme.accentPink.opacity(0.2), radius: 14, x: 0, y: 10)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Stuff")
                    .font(AppTheme.titleFont(size: 20))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Button(action: onOpenDirectory) {
                    Text("View All")
                        .font(AppTheme.titleFont(size: 12))
                        .foregroundColor(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.accentYellow)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if store.recentMemories.isEmpty {
                        emptyRecentCard
                    } else {
                        ForEach(store.recentMemories) { item in
                            Button {
                                onOpenMemory(item)
                            } label: {
                                MemoryCardView(item: item, isCompact: true)
                                    .frame(width: 200)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Storage")
                    .font(AppTheme.titleFont(size: 14))
                    .foregroundColor(AppTheme.accentBlue)

                Text(storageText)
                    .font(AppTheme.displayFont(size: 22))
                    .foregroundColor(AppTheme.ink)

                Text("used in Memories")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.softInk)

                Capsule()
                    .fill(AppTheme.accentBlue)
                    .frame(height: 6)
            }
            .padding(16)
            .appCard(cornerRadius: 22, stroke: AppTheme.accentBlue)

            VStack(alignment: .leading, spacing: 10) {
                Text("Scans")
                    .font(AppTheme.titleFont(size: 14))
                    .foregroundColor(AppTheme.accentPink)

                Text("\(store.memories.count)")
                    .font(AppTheme.displayFont(size: 22))
                    .foregroundColor(AppTheme.ink)

                Text("Spaces saved")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.softInk)

                HStack(spacing: -8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill([AppTheme.accentBlue, AppTheme.accentPink, AppTheme.accentYellow][index])
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
            .padding(16)
            .appCard(cornerRadius: 22, stroke: AppTheme.accentPink)
        }
    }

    private var emptyRecentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No scans yet")
                .font(AppTheme.titleFont(size: 16))
                .foregroundColor(AppTheme.ink)
            Text("Start scanning to save your first memory.")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.softInk)
        }
        .padding(16)
        .frame(width: 220)
        .appCard(cornerRadius: 22)
    }

    private var storageText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(store.totalBytes))
    }
}
