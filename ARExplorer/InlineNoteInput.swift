import SwiftUI
import SceneKit
import simd

/// Inline note input that appears after placing a pin
struct InlineNoteInput: View {
    @Binding var text: String
    var onSave: () -> Void
    var onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Arrow pointing up to the pin
            Triangle()
                .fill(AppTheme.accentYellow)
                .frame(width: 16, height: 8)
                .overlay(
                    Triangle()
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
            
            VStack(spacing: 12) {
                // Text field
                TextField("What's on your mind?", text: $text, axis: .vertical)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.ink)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppTheme.ink.opacity(0.3), lineWidth: 1)
                            )
                    )
                    .submitLabel(.done)
                    .onSubmit {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isFocused = false
                            onSave()
                        }
                    }
                
                // Action buttons - always visible
                HStack(spacing: 10) {
                    Button(action: {
                        isFocused = false
                        onCancel()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                                    )
                            )
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        isFocused = false
                        onSave()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Save")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(AppTheme.ink)
                        )
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.accentYellow)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.ink, lineWidth: 2)
                    )
            )
        }
        .frame(maxWidth: 280)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
}

/// Triangle shape for the arrow pointer
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A draggable pin for placing notes
struct DraggableNotePin: View {
    @Binding var position: CGPoint
    let isPlaced: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Pin head
            ZStack {
                Circle()
                    .fill(AppTheme.accentYellow)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "note.text")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.ink)
            }
            .overlay(
                Circle()
                    .stroke(AppTheme.ink, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            // Pin stem
            if isPlaced {
                Rectangle()
                    .fill(AppTheme.ink)
                    .frame(width: 3, height: 20)
                    .offset(y: -2)
            }
        }
        .scaleEffect(isPlaced ? 1.0 : 1.2)
        .animation(.spring(response: 0.3), value: isPlaced)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        
        VStack {
            DraggableNotePin(position: .constant(.zero), isPlaced: false)
            
            InlineNoteInput(
                text: .constant("I used to sleep here..."),
                onSave: {},
                onCancel: {}
            )
        }
    }
}
