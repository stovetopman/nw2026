import Foundation

struct MemoryItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let date: Date
    let sizeBytes: Int
    let usdzURL: URL
    let folderURL: URL
    let previewURL: URL?

    var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeBytes))
    }

    var dateText: String {
        Self.shortDateFormatter.string(from: date).uppercased()
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM dd"
        return f
    }()
}
