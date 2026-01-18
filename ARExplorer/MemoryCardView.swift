import SwiftUI

struct MemoryCardView: View {
    let item: MemoryItem
    var isCompact: Bool = false

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
                .stroke(AppTheme.ink, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
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
