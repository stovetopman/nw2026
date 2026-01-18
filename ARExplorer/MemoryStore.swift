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

    var totalBytes: Int {
        memories.reduce(0) { $0 + $1.sizeBytes }
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

            let id = UUID(uuidString: folder.lastPathComponent) ?? UUID()
            return MemoryItem(
                id: id,
                title: title,
                date: date,
                sizeBytes: size,
                plyURL: plyURL,
                folderURL: folder,
                previewURL: previewURL
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
