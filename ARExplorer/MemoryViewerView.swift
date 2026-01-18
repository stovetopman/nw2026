import SwiftUI
import Foundation

struct MemoryViewerView: View {
    let item: MemoryItem
    var onClose: () -> Void

    @State private var showShare = false

    var body: some View {
        ZStack {
            ViewerView(usdzURL: item.usdzURL)
                .ignoresSafeArea()

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
                                        .overlay(
                                            Circle().stroke(AppTheme.ink, lineWidth: 2)
                                        )
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("1.2M Points")
                                .font(AppTheme.titleFont(size: 12))
                                .foregroundColor(AppTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.9))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(AppTheme.ink, lineWidth: 2)
                                        )
                                )

                            Text("LiDAR Mesh")
                                .font(AppTheme.titleFont(size: 12))
                                .foregroundColor(AppTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 0.2, green: 0.8, blue: 0.65))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(AppTheme.ink, lineWidth: 2)
                                        )
                                )
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                    }
                }

                Spacer()

                HStack(spacing: 16) {
                    Button(action: {}) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .overlay(
                                        Circle().stroke(AppTheme.ink, lineWidth: 2)
                                    )
                            )
                    }

                    Button(action: recenter) {
                        HStack(spacing: 10) {
                            Image(systemName: "viewfinder")
                            Text("RECENTER")
                                .font(AppTheme.titleFont(size: 14))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(AppTheme.accentBlue)
                                .overlay(
                                    Capsule().stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                    }

                    Button(action: { showShare = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.9))
                                    .overlay(
                                        Circle().stroke(AppTheme.ink, lineWidth: 2)
                                    )
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 90)
            }
            .padding(.top, 16)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [item.usdzURL])
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
}
