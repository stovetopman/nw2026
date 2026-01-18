import Foundation

enum SpaceFinder {
    static func spacesRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spaces", isDirectory: true)
    }

    static func latestUSDZ() -> URL? {
        let root = spacesRoot()
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let sorted = folders.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return d1 > d2
        }

        for folder in sorted {
            let usdz = folder.appendingPathComponent("scene.usdz")
            if FileManager.default.fileExists(atPath: usdz.path) {
                return usdz
            }
        }
        return nil
    }
}
