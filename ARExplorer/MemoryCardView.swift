import SwiftUI

struct MemoryCardView: View {
    let item: MemoryItem
    var isCompact: Bool = false
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onGoToFile: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if let previewURL = item.previewURL {
                    AsyncImage(url: previewURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .clipped()
                    } placeholder: {
                        placeholderImage
                    }
                } else {
                    placeholderImage
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppTheme.ink, lineWidth: 2)
            )

            Text(item.title)
                .font(AppTheme.titleFont(size: isCompact ? 16 : 18))
                .foregroundColor(AppTheme.ink)

            HStack(spacing: 12) {
                Label(item.dateText, systemImage: "calendar")
                Label(item.sizeText, systemImage: "externaldrive")
            }
            .font(AppTheme.bodyFont(size: 12))
            .foregroundColor(AppTheme.softInk)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(isSelected ? AppTheme.accentBlue : AppTheme.ink, lineWidth: isSelected ? 3 : 2)
        )
        .overlay(
            // Selection indicator
            Group {
                if isSelectionMode {
                    Circle()
                        .fill(isSelected ? AppTheme.accentBlue : Color.white)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isSelected ? .white : .clear)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(16)
                }
            }
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
        .if(!isSelectionMode) { view in
            view.contextMenu {
                if let onShare = onShare {
                    Button {
                        onShare()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                
                if let onGoToFile = onGoToFile {
                    Button {
                        onGoToFile()
                    } label: {
                        Label("Go to File", systemImage: "folder")
                    }
                }
                
                if let onDelete = onDelete {
                    Divider()
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Memory", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var placeholderImage: some View {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.95, blue: 1.0),
                Color(red: 0.99, green: 0.96, blue: 0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "cube")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(AppTheme.ink.opacity(0.5))
        )
    }
}

// MARK: - Conditional View Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
