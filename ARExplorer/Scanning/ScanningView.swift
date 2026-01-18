//
//  ScanningView.swift
//  ARExplorer - LiDAR Memory
//
//  SwiftUI view for the scanning state with ARKit visualization.
//

import SwiftUI
import RealityKit
import ARKit

/// Main scanning view with AR camera and mesh visualization
struct ScanningView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        ZStack {
            // AR View
            ScanningARViewContainer(scanningEngine: viewModel.scanningEngine)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top stats bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SCANNING")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        HStack(spacing: 16) {
                            Label("\(viewModel.scanningEngine.scanSession.totalVertices)", systemImage: "dot.radiowaves.up.forward")
                            Label("\(viewModel.scanningEngine.scanSession.totalFaces)", systemImage: "triangle")
                        }
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Instructions
                Text("Move slowly around your space to capture the environment")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                
                // Bottom action bar
                HStack(spacing: 16) {
                    // View saved memories
                    Button(action: {
                        viewModel.showMemoryPicker = true
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                            Text("History")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .frame(width: 70, height: 60)
                    }
                    
                    // Save scan button (main action)
                    Button(action: {
                        viewModel.saveCurrentScan()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.title)
                            Text("Save Memory")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(width: 120, height: 70)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 70, height: 60)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $viewModel.showMemoryPicker) {
            MemoryPickerView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.refreshSavedMemories()
        }
    }
}

/// UIViewRepresentable for ARView during scanning
struct ScanningARViewContainer: UIViewRepresentable {
    let scanningEngine: ScanningEngine
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure and start scanning
        Task { @MainActor in
            scanningEngine.configure(arView: arView)
            scanningEngine.startScanning()
        }
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Sheet for selecting previously saved memories
struct MemoryPickerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.savedMemories.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Saved Memories")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Scan your environment and save it to create a memory.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.savedMemories, id: \.absoluteString) { url in
                            MemoryRow(url: url) {
                                viewModel.exploreMemory(at: url)
                                dismiss()
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let url = viewModel.savedMemories[index]
                                try? MemoryManager.deleteMemory(at: url)
                            }
                            viewModel.refreshSavedMemories()
                        }
                    }
                }
            }
            .navigationTitle("Saved Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// Row for a single saved memory
struct MemoryRow: View {
    let url: URL
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "cube.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(memoryName)
                        .font(.headline)
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var memoryName: String {
        let folderName = url.deletingLastPathComponent().lastPathComponent
        return String(folderName.prefix(8)) + "..."
    }
    
    private var formattedDate: String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values?.contentModificationDate else { return "Unknown date" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
