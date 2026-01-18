import SwiftUI

struct DirectoryView: View {
    @ObservedObject var store: MemoryStore
    var onOpenMemory: (MemoryItem) -> Void
    var onStartScan: () -> Void

    @State private var selectedFilter: DirectoryFilter = .all

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    filterChips
                    grid
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 90)
            }
        }
        .onAppear {
            store.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DIRECTORY")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.softInk)
                Spacer()
                HStack(spacing: 10) {
                    Button(action: {}) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(AppTheme.ink, lineWidth: 2)
                                    )
                            )
                    }
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentPink, AppTheme.accentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle().stroke(AppTheme.ink, lineWidth: 2)
                        )
                }
            }

            Text("MY\nMEMORIES")
                .font(AppTheme.displayFont(size: 30))
                .foregroundColor(AppTheme.ink)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DirectoryFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(AppTheme.titleFont(size: 12))
                            .foregroundColor(selectedFilter == filter ? .white : AppTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedFilter == filter ? AppTheme.ink : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(AppTheme.ink, lineWidth: selectedFilter == filter ? 0 : 2)
                                    )
                            )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(store.memories) { item in
                Button {
                    onOpenMemory(item)
                } label: {
                    MemoryCardView(item: item)
                }
                .buttonStyle(.plain)
            }

            Button(action: onStartScan) {
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(AppTheme.ink)
                        )
                        .overlay(
                            Circle()
                                .stroke(AppTheme.ink, lineWidth: 2)
                        )

                    Text("New Scan")
                        .font(AppTheme.titleFont(size: 14))
                        .foregroundColor(AppTheme.ink)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundColor(AppTheme.ink)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color.white)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private enum DirectoryFilter: CaseIterable {
    case all
    case favorites
    case recent
    case archived

    var title: String {
        switch self {
        case .all: return "All Scans"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .archived: return "Archive"
        }
    }
}
