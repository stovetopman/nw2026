import SwiftUI

struct SettingsView: View {
    @AppStorage("autoStartScan") private var autoStartScan = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    settingsCard
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 80)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(AppTheme.ink)
            Text("Settings")
                .font(AppTheme.displayFont(size: 24))
                .foregroundColor(AppTheme.ink)
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preferences")
                .font(AppTheme.titleFont(size: 18))
                .foregroundColor(AppTheme.ink)

            Toggle(isOn: $autoStartScan) {
                Text("Auto-start Scan")
                    .font(AppTheme.bodyFont(size: 16))
                    .foregroundColor(AppTheme.ink)
            }
            .tint(AppTheme.accentBlue)

            Toggle(isOn: $hapticsEnabled) {
                Text("Haptics")
                    .font(AppTheme.bodyFont(size: 16))
                    .foregroundColor(AppTheme.ink)
            }
            .tint(AppTheme.accentBlue)
        }
        .padding(16)
        .appCard(cornerRadius: 22)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(AppTheme.titleFont(size: 18))
                .foregroundColor(AppTheme.ink)

            Text(versionText)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.softInk)
        }
        .padding(16)
        .appCard(cornerRadius: 22)
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
