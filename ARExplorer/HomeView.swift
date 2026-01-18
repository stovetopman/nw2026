import SwiftUI
import Foundation

struct HomeView: View {
    @ObservedObject var store: MemoryStore
    var onStartScan: () -> Void
    var onOpenDirectory: () -> Void
    var onOpenMemory: (MemoryItem) -> Void
    
    @State private var isSearching = false
    @State private var searchText = ""
    
    // Profile
    @AppStorage("userName") private var userName: String = "Anonymous User"
    @State private var showProfileEdit = false
    @State private var editingName = ""
    
    private var searchResults: [MemoryItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return store.memories.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if isSearching {
                        searchSection
                    } else {
                        heroCard
                        recentSection
                        statsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
            .refreshable {
                store.refresh()
            }
            
            // Profile edit overlay
            if showProfileEdit {
                profileEditOverlay
            }
        }
    }
    
    private var profileEditOverlay: some View {
        ZStack {
            // Background dim
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showProfileEdit = false }
                }
            
            // Edit card
            VStack(spacing: 20) {
                HStack {
                    Text("EDIT PROFILE")
                        .font(AppTheme.titleFont(size: 18))
                        .foregroundColor(AppTheme.ink)
                    Spacer()
                    Button(action: { withAnimation { showProfileEdit = false } }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.ink)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.5))
                            )
                    }
                }
                
                // Profile icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentBlue, AppTheme.accentPink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 36, weight: .bold))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Name")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundColor(AppTheme.softInk)
                    
                    TextField("", text: $editingName, prompt: Text("Enter your name...").foregroundColor(.black.opacity(0.5)))
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .tint(.black)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                }
                
                Button(action: {
                    let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                    userName = trimmed.isEmpty ? "Anonymous User" : trimmed
                    withAnimation { showProfileEdit = false }
                }) {
                    Text("SAVE")
                        .font(AppTheme.titleFont(size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppTheme.accentBlue)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(AppTheme.ink, lineWidth: 2)
                    )
            )
            .padding(.horizontal, 30)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: {
                editingName = userName
                showProfileEdit = true
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentBlue, AppTheme.accentPink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 24, weight: .bold))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("WELCOME BACK!")
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundColor(AppTheme.accentBlue)
                Text(userName)
                    .font(AppTheme.displayFont(size: 22))
                    .foregroundColor(AppTheme.ink)
            }

            Spacer()

            Button(action: {
                withAnimation {
                    isSearching.toggle()
                    if !isSearching {
                        searchText = ""
                    }
                }
            }) {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSearching ? AppTheme.accentYellow : Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
            }
        }
    }
    
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.softInk)
                
                TextField("", text: $searchText, prompt: Text("Search memories...").foregroundColor(AppTheme.softInk))
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                    .tint(.black)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.softInk)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppTheme.ink, lineWidth: 2)
                    )
            )
            
            // Search results
            if searchText.isEmpty {
                Text("Type to search your memories")
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundColor(AppTheme.softInk)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else if searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.softInk)
                    Text("No memories found")
                        .font(AppTheme.titleFont(size: 16))
                        .foregroundColor(AppTheme.ink)
                    Text("Try a different search term")
                        .font(AppTheme.bodyFont(size: 14))
                        .foregroundColor(AppTheme.softInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.softInk)
                
                ForEach(searchResults) { item in
                    Button {
                        onOpenMemory(item)
                    } label: {
                        HStack(spacing: 14) {
                            if let previewURL = item.previewURL {
                                AsyncImage(url: previewURL) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Rectangle()
                                        .fill(AppTheme.accentBlue.opacity(0.2))
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppTheme.accentBlue.opacity(0.2))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: "cube")
                                            .foregroundColor(AppTheme.ink)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(AppTheme.ink, lineWidth: 2)
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(AppTheme.titleFont(size: 16))
                                    .foregroundColor(AppTheme.ink)
                                Text(item.dateText)
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundColor(AppTheme.softInk)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppTheme.softInk)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LiDAR Ready")
                    .font(AppTheme.bodyFont(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(
                                Capsule()
                                    .stroke(AppTheme.ink, lineWidth: 2)
                            )
                    )
                Spacer()
            }

            Text("Capture a\nNew Memory")
                .font(AppTheme.displayFont(size: 32))
                .foregroundColor(AppTheme.ink)

            Text("Create immersive spatial moments!\nScan your world in 3D and keep it forever.")
                .font(AppTheme.bodyFont(size: 14))
                .foregroundColor(AppTheme.softInk)

            Button(action: onStartScan) {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Start Scanning")
                        .font(AppTheme.titleFont(size: 16))
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppTheme.ink)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.98, blue: 1.0),
                            Color(red: 0.99, green: 0.95, blue: 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [AppTheme.accentBlue, AppTheme.accentPink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
        .shadow(color: AppTheme.accentPink.opacity(0.2), radius: 14, x: 0, y: 10)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Stuff")
                    .font(AppTheme.titleFont(size: 20))
                    .foregroundColor(AppTheme.ink)
                Spacer()
                Button(action: onOpenDirectory) {
                    Text("View All")
                        .font(AppTheme.titleFont(size: 12))
                        .foregroundColor(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.accentYellow)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.ink, lineWidth: 2)
                                )
                        )
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if store.recentMemories.isEmpty {
                        emptyRecentCard
                    } else {
                        ForEach(store.recentMemories) { item in
                            Button {
                                onOpenMemory(item)
                            } label: {
                                MemoryCardView(
                                    item: item,
                                    isCompact: true,
                                    onDelete: { store.deleteMemory(item) },
                                    onFavorite: { store.toggleFavorite(item) }
                                )
                                .frame(width: 200)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Storage")
                    .font(AppTheme.titleFont(size: 14))
                    .foregroundColor(AppTheme.accentBlue)

                Text(storageText)
                    .font(AppTheme.displayFont(size: 22))
                    .foregroundColor(AppTheme.ink)

                Text("used in Memories")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.softInk)

                Capsule()
                    .fill(AppTheme.accentBlue)
                    .frame(height: 6)
            }
            .padding(16)
            .appCard(cornerRadius: 22, stroke: AppTheme.accentBlue)

            VStack(alignment: .leading, spacing: 10) {
                Text("Scans")
                    .font(AppTheme.titleFont(size: 14))
                    .foregroundColor(AppTheme.accentPink)

                Text("\(store.memories.count)")
                    .font(AppTheme.displayFont(size: 22))
                    .foregroundColor(AppTheme.ink)

                Text("Spaces saved")
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundColor(AppTheme.softInk)

                HStack(spacing: -8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill([AppTheme.accentBlue, AppTheme.accentPink, AppTheme.accentYellow][index])
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
            .padding(16)
            .appCard(cornerRadius: 22, stroke: AppTheme.accentPink)
        }
    }

    private var emptyRecentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No scans yet")
                .font(AppTheme.titleFont(size: 16))
                .foregroundColor(AppTheme.ink)
            Text("Start scanning to save your first memory.")
                .font(AppTheme.bodyFont(size: 12))
                .foregroundColor(AppTheme.softInk)
        }
        .padding(16)
        .frame(width: 220)
        .appCard(cornerRadius: 22)
    }

    private var storageText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(store.totalBytes))
    }
}
