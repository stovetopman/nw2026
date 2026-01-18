import SwiftUI

/// A yellow dot marker representing a note location
struct NoteMarkerView: View {
    let isSelected: Bool
    var size: CGFloat = 16
    
    var body: some View {
        ZStack {
            // Outer glow when selected
            if isSelected {
                Circle()
                    .fill(AppTheme.accentYellow.opacity(0.3))
                    .frame(width: size * 2, height: size * 2)
            }
            
            // Main dot
            Circle()
                .fill(AppTheme.accentYellow)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        VStack(spacing: 40) {
            NoteMarkerView(isSelected: false)
            NoteMarkerView(isSelected: true)
        }
    }
}
