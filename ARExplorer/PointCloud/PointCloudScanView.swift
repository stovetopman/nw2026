//
//  PointCloudScanView.swift
//  ARExplorer
//
//  AR view for scanning and capturing point cloud with real-time visualization.
//

import SwiftUI
import ARKit
import RealityKit

// MARK: - Point Cloud Scan View

/// Main view for point cloud scanning - matches mesh UI controls.
struct PointCloudScanView: View {
    
    @StateObject private var pointManager = PointManager()
    @StateObject private var arProcessor = ARProcessor()
    
    @State private var showViewer = false
    @State private var showMemoryPicker = false
    @State private var isSaving = false
    @State private var savedMemories: [URL] = []
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            if showViewer {
                // Point cloud viewer (non-AR) with footer bar
                PointRenderView(
                    pointManager: pointManager,
                    onReset: { pointManager.clear() },
                    onBack: { showViewer = false }
                )
            } else {
                // AR scanning view with point overlay
                PointCloudARView(arProcessor: arProcessor, pointManager: pointManager)
                    .ignoresSafeArea()
                
                // Overlay UI - matches mesh ScanningView
                VStack {
                    // Top stats bar with pulse indicator
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                // Pulsing dot to show scanning is active
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                                    .opacity(pulseAnimation ? 0.6 : 1.0)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
                                
                                Text("SCANNING")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                            
                            HStack(spacing: 16) {
                                Label(formatCount(pointManager.uniqueCount), systemImage: "circle.dotted")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onAppear { pulseAnimation = true }
                        
                        Spacer()
                        
                        // View 3D button
                        if pointManager.uniqueCount > 0 {
                            Button(action: {
                                arProcessor.stop()
                                showViewer = true
                            }) {
                                Image(systemName: "cube")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                        }
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
                    
                    // Bottom action bar - matches mesh controls
                    HStack(spacing: 16) {
                        // History
                        Button(action: {
                            showMemoryPicker = true
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
                        
                        // Save Memory (main action)
                        Button(action: savePointCloud) {
                            VStack(spacing: 4) {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "square.and.arrow.down.fill")
                                        .font(.title)
                                }
                                Text("Save Memory")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(width: 120, height: 70)
                            .background(pointManager.uniqueCount > 0 ? Color.blue : Color.gray)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(pointManager.uniqueCount == 0 || isSaving)
                        
                        // Clear
                        Button(action: {
                            pointManager.clear()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.title2)
                                Text("Clear")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .frame(width: 70, height: 60)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showMemoryPicker) {
            PointCloudMemoryPicker(memories: savedMemories, onSelect: loadMemory)
        }
        .onAppear {
            refreshMemories()
        }
    }
    
    // MARK: - Helpers
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM pts", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK pts", Double(count) / 1_000)
        }
        return "\(count) pts"
    }
    
    private func refreshMemories() {
        savedMemories = PointCloudStorage.listSavedPointClouds()
    }
    
    private func savePointCloud() {
        guard pointManager.uniqueCount > 0 else { return }
        
        isSaving = true
        arProcessor.stop()
        
        Task {
            do {
                let url = try await PointCloudStorage.save(points: pointManager.points)
                print("✅ Point cloud saved: \(url)")
                await MainActor.run {
                    isSaving = false
                    refreshMemories()
                    showViewer = true
                }
            } catch {
                print("❌ Save failed: \(error)")
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
    
    private func loadMemory(url: URL) {
        showMemoryPicker = false
        Task {
            if let points = try? await PointCloudStorage.load(from: url) {
                await MainActor.run {
                    pointManager.clear()
                    for point in points {
                        pointManager.addPoint(point)
                    }
                    showViewer = true
                }
            }
        }
    }
}

// MARK: - AR View Container with Mesh Wireframe Overlay

struct PointCloudARView: UIViewRepresentable {
    
    let arProcessor: ARProcessor
    let pointManager: PointManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        
        // Show mesh wireframe during scanning (same as mesh mode)
        // This is lightweight - built into ARKit, no custom rendering
        arView.debugOptions = [.showSceneUnderstanding]
        
        arProcessor.start(session: arView.session, pointManager: pointManager)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No updates needed
    }
}

// MARK: - Memory Picker

struct PointCloudMemoryPicker: View {
    let memories: [URL]
    let onSelect: (URL) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if memories.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "cube.transparent")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No saved point clouds")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(memories, id: \.absoluteString) { url in
                        Button(action: { onSelect(url) }) {
                            HStack {
                                Image(systemName: "cube.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(.headline)
                                    Text(formatDate(url))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func formatDate(_ url: URL) -> String {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.creationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return ""
    }
}

// MARK: - Preview

#Preview {
    PointCloudScanView()
}
