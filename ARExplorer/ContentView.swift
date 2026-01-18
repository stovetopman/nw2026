import SwiftUI

struct ContentView: View {
    @State private var showViewer = false
    @State private var latestUSDZ: URL?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ARViewContainer()
                    .ignoresSafeArea()

                HStack(spacing: 12) {
                    Button("Capture Photo") {
                        NotificationCenter.default.post(name: .capturePhoto, object: nil)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Save Scan") {
                        NotificationCenter.default.post(name: .saveScan, object: nil)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("View") {
                        latestUSDZ = SpaceFinder.latestUSDZ()
                        print("latestUSDZ:", latestUSDZ?.path ?? "nil")
                        showViewer = latestUSDZ != nil
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Clear Map") {
                        NotificationCenter.default.post(name: .clearMap, object: nil)
                    }
                    .buttonStyle(.bordered)

                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.bottom, 18)
            }
            .navigationDestination(isPresented: $showViewer) {
                if let url = latestUSDZ {
                    ViewerView(usdzURL: url)
                } else {
                    Text("No scan found.")
                }
            }
        }
    }
}

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
    static let saveScan = Notification.Name("saveScan")
    static let clearMap = Notification.Name("clearMap")
}
