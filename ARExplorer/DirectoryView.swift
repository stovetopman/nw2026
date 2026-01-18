import SwiftUI

struct DirectoryView: View {
    @ObservedObject var store: MemoryStore
    var onOpenMemory: (MemoryItem) -> Void
    var onStartScan: () -> Void

    @State private var selectedFilter: DirectoryFilter = .all
    @State private var isSelectionMode: Bool = false
    @State private var selectedMemories: Set<UUID> = []

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
                if isSelectionMode {
                    Button(action: {
                        withAnimation {
                            selectedMemories.removeAll()
                            isSelectionMode = false
                        }
                    }) {
                        Text("Cancel")
                            .font(AppTheme.titleFont(size: 14))
                            .foregroundColor(AppTheme.ink)
                    }
                    Spacer()
                    Text("\(selectedMemories.count) selected")
                        .font(AppTheme.titleFont(size: 14))
                        .foregroundColor(AppTheme.ink)
                    Spacer()
                    Button(action: deleteSelectedMemories) {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedMemories.isEmpty ? Color.gray : Color.red)
                            )
                    }
                    .disabled(selectedMemories.isEmpty)
                } else {
                    Text("DIRECTORY")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundColor(AppTheme.softInk)
                    Spacer()
                    HStack(spacing: 10) {
                        Button(action: {
                            withAnimation {
                                isSelectionMode = true
                            }
                        }) {
                            Image(systemName: "checkmark.circle")
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
            }

            if !isSelectionMode {
                Text("MY\nMEMORIES")
                    .font(AppTheme.displayFont(size: 30))
                    .foregroundColor(AppTheme.ink)
            }
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
                    if isSelectionMode {
                        toggleSelection(item)
                    } else {
                        onOpenMemory(item)
                    }
                } label: {
                    MemoryCardView(
                        item: item,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedMemories.contains(item.id),
                        onGoToFile: { openInFilesApp(item: item) },
                        onDelete: { store.deleteMemory(item) }
                    )
                }
                .buttonStyle(.plain)
            }

            if !isSelectionMode {
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
    
    private func toggleSelection(_ item: MemoryItem) {
        if selectedMemories.contains(item.id) {
            selectedMemories.remove(item.id)
            if selectedMemories.isEmpty {
                withAnimation {
                    isSelectionMode = false
                }
            }
        } else {
            selectedMemories.insert(item.id)
        }
    }
    
    private func deleteSelectedMemories() {
        let itemsToDelete = store.memories.filter { selectedMemories.contains($0.id) }
        store.deleteMemories(itemsToDelete)
        withAnimation {
            selectedMemories.removeAll()
            isSelectionMode = false
        }
    }
    
    private func openInFilesApp(item: MemoryItem) {
        // Try to open the folder in Files app using shareddocuments scheme
        let folderURL = item.folderURL
        
        // Construct Files app URL for this document
        if let encodedPath = folderURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            let filesURLString = "shareddocuments://\(encodedPath)"
            if let filesURL = URL(string: filesURLString) {
                UIApplication.shared.open(filesURL, options: [:]) { success in
                    if !success {
                        // Fallback: show share sheet
                        showShareSheet(for: folderURL)
                    }
                }
                return
            }
        }
        
        // Fallback: show share sheet
        showShareSheet(for: folderURL)
    }
    
    private func showShareSheet(for url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        }
        
        rootVC.present(activityVC, animated: true)
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
