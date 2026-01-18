import SwiftUI

final class MemoryStore: ObservableObject {
    @Published private(set) var memories: [MemoryItem] = []

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: .scanSaved,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    var recentMemories: [MemoryItem] {
        Array(memories.prefix(2))
    }
    
    var favoriteMemories: [MemoryItem] {
        memories.filter { $0.isFavorite }
    }

    var totalBytes: Int {
        memories.reduce(0) { $0 + $1.sizeBytes }
    }

    func deleteMemory(_ item: MemoryItem) {
        do {
            try FileManager.default.removeItem(at: item.folderURL)
            refresh()
        } catch {
            print("❌ Failed to delete memory: \(error)")
        }
    }

    func deleteMemories(_ items: [MemoryItem]) {
        for item in items {
            do {
                try FileManager.default.removeItem(at: item.folderURL)
            } catch {
                print("❌ Failed to delete memory: \(error)")
            }
        }
        refresh()
    }
    
    func toggleFavorite(_ item: MemoryItem) {
        let infoURL = item.folderURL.appendingPathComponent("info.json")
        var json: [String: Any] = [:]
        
        // Load existing info.json
        if let data = try? Data(contentsOf: infoURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        
        // Toggle favorite status
        let newFavoriteStatus = !item.isFavorite
        json["isFavorite"] = newFavoriteStatus
        
        // Save back to info.json
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
            try data.write(to: infoURL, options: .atomic)
            refresh()
        } catch {
            print("❌ Failed to save favorite status: \(error)")
        }
    }

    func refresh() {
        let root = SpaceFinder.spacesRoot()
        if !FileManager.default.fileExists(atPath: root.path) {
            memories = []
            return
        }

        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let items: [MemoryItem] = folders.compactMap { folder in
            let plyURL = folder.appendingPathComponent("scene.ply")
            guard FileManager.default.fileExists(atPath: plyURL.path) else { return nil }

            let values = try? plyURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate ?? Date()
            let size = values?.fileSize ?? 0
            let title = loadTitle(in: folder, date: date)
            let previewURL = loadPreviewURL(in: folder)
            let isFavorite = loadFavoriteStatus(in: folder)

            let id = UUID(uuidString: folder.lastPathComponent) ?? UUID()
            return MemoryItem(
                id: id,
                title: title,
                date: date,
                sizeBytes: size,
                plyURL: plyURL,
                folderURL: folder,
                previewURL: previewURL,
                isFavorite: isFavorite
            )
        }

        memories = items.sorted { $0.date > $1.date }
    }

    private func loadTitle(in folder: URL, date: Date) -> String {
        let infoURL = folder.appendingPathComponent("info.json")
        if let data = try? Data(contentsOf: infoURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let title = json["title"] as? String,
           !title.isEmpty {
            return title
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Memory \(formatter.string(from: date))"
    }
    
    private func loadFavoriteStatus(in folder: URL) -> Bool {
        let infoURL = folder.appendingPathComponent("info.json")
        if let data = try? Data(contentsOf: infoURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let isFavorite = json["isFavorite"] as? Bool {
            return isFavorite
        }
        return false
    }

    private func loadPreviewURL(in folder: URL) -> URL? {
        let photosURL = folder.appendingPathComponent("photos", isDirectory: true)
        let candidate = photosURL.appendingPathComponent("001.jpg")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        let photos = (try? FileManager.default.contentsOfDirectory(
            at: photosURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return photos.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }
}
