import SwiftUI

/// Card displaying a spatial note's content with edit/delete actions
struct NoteCardView: View {
    let note: SpatialNote
    var onEdit: () -> Void
    var onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                // NOTE label
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 10, weight: .bold))
                    Text("NOTE")
                        .font(AppTheme.titleFont(size: 10))
                }
                .foregroundColor(AppTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.ink, lineWidth: 1.5)
                        )
                )
                
                Spacer()
                
                // Date
                Text(note.dateText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.ink.opacity(0.7))
            }
            
            // Note text
            Text("\"\(note.text)\"")
                .font(.system(size: 18, weight: .medium, design: .serif))
                .italic()
                .foregroundColor(AppTheme.ink)
                .lineLimit(4)
            
            // Footer row
            HStack {
                // Author
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.ink.opacity(0.2))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.ink.opacity(0.6))
                        )
                    
                    Text("@\(note.author)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.ink.opacity(0.7))
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppTheme.ink, lineWidth: 1.5)
                                    )
                            )
                    }
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppTheme.ink, lineWidth: 1.5)
                                    )
                            )
                    }
                }
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
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.5)
        NoteCardView(
            note: SpatialNote(
                anchorID: UUID(),
                text: "I used to sleep here...",
                author: "alex_m",
                transform: matrix_identity_float4x4
            ),
            onEdit: {},
            onDelete: {}
        )
        .padding(20)
    }
}
