//
//  ContentView.swift
//  ARExplorer - LiDAR Memory
//
//  Toggle between mesh scanning and point cloud modes.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage("usePointCloud") private var usePointCloud = true
    
    var body: some View {
        ZStack {
            if usePointCloud {
                PointCloudScanView()
            } else {
                // Original mesh-based scanning
                ZStack {
                    switch viewModel.state {
                    case .scanning:
                        ScanningView(viewModel: viewModel)
                    case .saving(let progress):
                        SavingView(progress: progress)
                    case .exploring(let usdzURL):
                        OrbitNavigationView(usdzURL: usdzURL)
                            .overlay(alignment: .topLeading) {
                                Button(action: { viewModel.returnToScanning() }) {
                                    Label("New Scan", systemImage: "arrow.left")
                                        .font(.subheadline.weight(.medium))
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
                .onReceive(viewModel.memoryManager.$exportProgress) { progress in
                    if case .saving = viewModel.state {
                        viewModel.state = .saving(progress: progress)
                    }
                }
            }
            
            // Mode toggle in top-right
            VStack {
                HStack {
                    Spacer()
                    Button(action: { usePointCloud.toggle() }) {
                        HStack(spacing: 6) {
                            Image(systemName: usePointCloud ? "circle.dotted" : "triangle")
                            Text(usePointCloud ? "Points" : "Mesh")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
}
