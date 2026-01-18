import SwiftUI
import SceneKit
import simd

/// Inline note input that appears ABOVE the keyboard
struct InlineNoteInput: View {
    @Binding var text: String
    var onSave: () -> Void
    var onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                // Input card positioned above keyboard
                VStack(spacing: 12) {
                    // Header
                    HStack {
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("ADD NOTE")
                            .font(AppTheme.titleFont(size: 12))
                        Spacer()
                    }
                    .foregroundColor(AppTheme.ink)
                    
                    // Text field
                    TextField("What's on your mind?", text: $text, axis: .vertical)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.ink)
                        .lineLimit(1...3)
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
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            isFocused = false
                            onCancel()
                        }) {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                                        )
                                )
                        }
                        
                        Button(action: {
                            isFocused = false
                            onSave()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Save Note")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.ink.opacity(0.4) : AppTheme.ink)
                            )
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppTheme.accentYellow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )
                )
                .padding(.horizontal, 16)
                .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: -4)
            }
            .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 8 : geometry.safeAreaInsets.bottom + 20)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
        }
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            keyboardHeight = 0
        }
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
