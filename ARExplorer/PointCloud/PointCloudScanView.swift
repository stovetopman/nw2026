//
//  PointCloudScanView.swift
//  ARExplorer
//
//  AR view for scanning and capturing point cloud.
//

import SwiftUI
import ARKit
import RealityKit

// MARK: - Point Cloud Scan View

/// Main view for point cloud scanning.
struct PointCloudScanView: View {
    
    @StateObject private var pointManager = PointManager()
    @StateObject private var arProcessor = ARProcessor()
    
    @State private var showViewer = false
    
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
                // AR scanning view
                PointCloudARView(arProcessor: arProcessor, pointManager: pointManager)
                    .ignoresSafeArea()
                
                // Overlay controls
                VStack {
                    // Stats
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(pointManager.uniqueCount) points")
                                .font(.system(.headline, design: .monospaced))
                            Text(arProcessor.isRunning ? "Scanning..." : "Paused")
                                .font(.caption)
                                .foregroundColor(arProcessor.isRunning ? .green : .yellow)
                        }
                        .foregroundColor(.white)
                        .padding(12)
                        .background(.black.opacity(0.6))
                        .cornerRadius(10)
                        
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Bottom controls
                    HStack(spacing: 40) {
                        // Clear
                        Button(action: {
                            pointManager.clear()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.title2)
                                Text("Clear")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                        }
                        
                        // View
                        Button(action: {
                            arProcessor.stop()
                            showViewer = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "cube")
                                    .font(.title2)
                                Text("View")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                        }
                        .disabled(pointManager.uniqueCount == 0)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - AR View Container

struct PointCloudARView: UIViewRepresentable {
    
    let arProcessor: ARProcessor
    let pointManager: PointManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        arProcessor.start(session: arView.session, pointManager: pointManager)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No updates needed
    }
}

// MARK: - Preview

#Preview {
    PointCloudScanView()
}
