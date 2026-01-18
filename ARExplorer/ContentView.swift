//
//  ContentView.swift
//  ARExplorer - LiDAR Memory
//
//  Main entry point with 3-state UI: Scanning → Saving → Exploring
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    
    var body: some View {
        ZStack {
            switch viewModel.state {
            case .scanning:
                ScanningView(viewModel: viewModel)
                    .transition(.opacity)
                
            case .saving(let progress):
                SavingView(progress: progress)
                    .transition(.opacity)
                
            case .exploring(let usdzURL):
                OrbitNavigationView(usdzURL: usdzURL)
                    .transition(.opacity)
                    .overlay(alignment: .topLeading) {
                        Button(action: {
                            viewModel.returnToScanning()
                        }) {
                            HStack {
                                Image(systemName: "arrow.left")
                                Text("New Scan")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .padding()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.state)
        .onReceive(viewModel.memoryManager.$exportProgress) { progress in
            if case .saving = viewModel.state {
                viewModel.state = .saving(progress: progress)
            }
        }
    }
}

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
    static let saveScan = Notification.Name("saveScan")
}

#Preview {
    ContentView()
}
