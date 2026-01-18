import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                Text("Settings")
                    .font(AppTheme.displayFont(size: 24))
                    .foregroundColor(AppTheme.ink)
                Text("Coming soon.")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundColor(AppTheme.softInk)
            }
        }
    }
}
