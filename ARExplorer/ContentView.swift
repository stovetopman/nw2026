import SwiftUI

struct ContentView: View {
    @StateObject private var store = MemoryStore()
    @State private var selectedTab: AppTab = .home
    @State private var selectedMemory: MemoryItem?
    @State private var startScanOnAppear = false

    var body: some View {
        ZStack {
            Group {
                switch selectedTab {
                case .home:
                    HomeView(
                        store: store,
                        onStartScan: {
                            startScanOnAppear = true
                            selectedTab = .scan
                        },
                        onOpenDirectory: { selectedTab = .directory },
                        onOpenMemory: { selectedMemory = $0 }
                    )
                case .scan:
                    ScanView(
                        store: store,
                        startScanOnAppear: $startScanOnAppear,
                        onBack: { selectedTab = .home },
                        onOpenLatest: { selectedMemory = $0 }
                    )
                case .directory:
                    DirectoryView(
                        store: store,
                        onOpenMemory: { selectedMemory = $0 },
                        onStartScan: {
                            startScanOnAppear = true
                            selectedTab = .scan
                        }
                    )
                case .settings:
                    SettingsView()
                }
            }
        }
        .overlay(alignment: .bottom) {
            AppTabBar(selected: $selectedTab)
        }
        .fullScreenCover(item: $selectedMemory) { item in
            MemoryViewerView(item: item) {
                selectedMemory = nil
            }
        }
        .onAppear {
            store.refresh()
        }
    }
}
