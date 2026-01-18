//
//  JoystickView.swift
//  ARExplorer - LiDAR Memory
//
//  DEPRECATED: This file is kept for reference only.
//  The app now uses gesture-based OrbitNavigationView instead of joysticks.
//  See: OrbitNavigationView.swift and CameraController.swift
//
//  Original: SwiftUI joystick components for fly-through navigation.
//

import SwiftUI
import simd

/// Joystick output values normalized from -1 to 1
struct JoystickOutput {
    var x: Float = 0  // Left-Right
    var y: Float = 0  // Up-Down (forward-backward for movement)
    
    var vector: SIMD2<Float> {
        SIMD2<Float>(x, y)
    }
    
    var isActive: Bool {
        abs(x) > 0.01 || abs(y) > 0.01
    }
}

/// A single joystick view with drag gesture
struct JoystickView: View {
    let size: CGFloat
    let label: String
    @Binding var output: JoystickOutput
    
    @State private var knobOffset: CGSize = .zero
    @State private var isDragging = false
    
    private var maxRadius: CGFloat { size / 2 - 25 }
    
    var body: some View {
        ZStack {
            // Base circle
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
            
            // Direction indicators
            VStack {
                Image(systemName: "chevron.up")
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.vertical, 12)
            .frame(height: size)
            
            HStack {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .frame(width: size)
            
            // Knob
            Circle()
                .fill(isDragging ? Color.white : Color.white.opacity(0.8))
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .offset(knobOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isDragging = true
                            
                            // Calculate offset clamped to circle
                            let translation = value.translation
                            let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
                            
                            if distance > maxRadius {
                                let scale = maxRadius / distance
                                knobOffset = CGSize(
                                    width: translation.width * scale,
                                    height: translation.height * scale
                                )
                            } else {
                                knobOffset = translation
                            }
                            
                            // Update output (normalized -1 to 1)
                            output.x = Float(knobOffset.width / maxRadius)
                            output.y = Float(-knobOffset.height / maxRadius)  // Invert Y for intuitive control
                        }
                        .onEnded { _ in
                            isDragging = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                knobOffset = .zero
                            }
                            output.x = 0
                            output.y = 0
                        }
                )
            
            // Label
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .offset(y: size / 2 + 12)
        }
        .frame(width: size, height: size)
    }
}

/// Container for both joysticks (movement + rotation)
struct DualJoystickOverlay: View {
    @Binding var movementOutput: JoystickOutput
    @Binding var rotationOutput: JoystickOutput
    
    let joystickSize: CGFloat = 120
    
    var body: some View {
        HStack {
            // Left joystick - Movement
            JoystickView(
                size: joystickSize,
                label: "MOVE",
                output: $movementOutput
            )
            .padding(.leading, 40)
            
            Spacer()
            
            // Right joystick - Rotation
            JoystickView(
                size: joystickSize,
                label: "LOOK",
                output: $rotationOutput
            )
            .padding(.trailing, 40)
        }
        .padding(.bottom, 60)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        DualJoystickOverlay(
            movementOutput: .constant(JoystickOutput()),
            rotationOutput: .constant(JoystickOutput())
        )
    }
}
