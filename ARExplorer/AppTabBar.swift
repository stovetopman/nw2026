import SwiftUI

enum AppTab: Int {
    case home
    case directory
    case scan
    case settings
}

struct AppTabBar: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack(spacing: 16) {
            tabButton(tab: .home, systemImage: "house.fill")
            tabButton(tab: .directory, systemImage: "square.grid.2x2.fill")

            Button {
                selected = .scan
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        Circle()
                            .fill(AppTheme.accentBlue)
                            .overlay(
                                Circle().stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
                    .shadow(color: AppTheme.accentBlue.opacity(0.4), radius: 8, x: 0, y: 6)
            }

            tabButton(tab: .settings, systemImage: "gearshape.fill")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func tabButton(tab: AppTab, systemImage: String) -> some View {
        Button {
            selected = tab
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(selected == tab ? .white : AppTheme.ink)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(selected == tab ? AppTheme.accentBlue : Color.clear)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.ink, lineWidth: selected == tab ? 0 : 2)
                        )
                )
        }
    }
}
