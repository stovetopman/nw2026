//
//  SavingView.swift
//  ARExplorer - LiDAR Memory
//
//  Progress view shown during USDZ export.
//

import SwiftUI

/// View shown during memory export with progress indicator
struct SavingView: View {
    let progress: Float
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Icon
                Image(systemName: "cube.transparent")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, options: .repeating)
                
                // Title
                VStack(spacing: 8) {
                    Text("Saving Memory")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Converting your scan to a 3D model...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Progress bar
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(width: 250)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Stages indicator
                VStack(alignment: .leading, spacing: 8) {
                    StageRow(icon: "checkmark.circle.fill", text: "Mesh data collected", isComplete: progress > 0)
                    StageRow(icon: progress > 0.3 ? "checkmark.circle.fill" : "circle", text: "Applying vertex colors", isComplete: progress > 0.3)
                    StageRow(icon: progress > 0.7 ? "checkmark.circle.fill" : "circle", text: "Exporting USDZ", isComplete: progress > 0.7)
                    StageRow(icon: progress >= 1.0 ? "checkmark.circle.fill" : "circle", text: "Complete", isComplete: progress >= 1.0)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }
}

/// Single stage row indicator
struct StageRow: View {
    let icon: String
    let text: String
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isComplete ? .green : .white.opacity(0.3))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(isComplete ? .white : .white.opacity(0.5))
        }
    }
}

#Preview {
    SavingView(progress: 0.5)
}
