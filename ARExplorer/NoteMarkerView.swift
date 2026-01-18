import SwiftUI

/// A yellow dot marker representing a note location
struct NoteMarkerView: View {
    let isSelected: Bool
    var size: CGFloat = 20
    
    var body: some View {
        ZStack {
            // Invisible tap target (larger than visible dot)
            Circle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)
            
            // Outer glow when selected
            if isSelected {
                Circle()
                    .fill(AppTheme.accentYellow.opacity(0.3))
                    .frame(width: size * 2.5, height: size * 2.5)
            }
            
            // Pulse animation ring
            Circle()
                .stroke(AppTheme.accentYellow.opacity(0.5), lineWidth: 2)
                .frame(width: size * 1.5, height: size * 1.5)
            
            // Main dot
            Circle()
                .fill(AppTheme.accentYellow)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(AppTheme.ink, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
            
            // Note icon inside
            Image(systemName: "note.text")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(AppTheme.ink)
        }
        .contentShape(Circle().size(CGSize(width: 44, height: 44)))
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
