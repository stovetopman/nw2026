import Foundation

/// Manages spatial notes for a memory folder
class NoteStore: ObservableObject {
    @Published private(set) var notes: [SpatialNote] = []
    
    private let folderURL: URL
    private var notesFileURL: URL {
        folderURL.appendingPathComponent("notes.json")
    }
    
    init(folderURL: URL) {
        self.folderURL = folderURL
        load()
    }
    
    // MARK: - CRUD Operations
    
    func add(_ note: SpatialNote) {
        notes.append(note)
        save()
    }
    
    func update(_ note: SpatialNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            save()
        }
    }
    
    func delete(_ note: SpatialNote) {
        notes.removeAll { $0.id == note.id }
        save()
    }
    
    func delete(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        save()
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: notesFileURL.path) else {
            notes = []
            return
        }
        
        do {
            let data = try Data(contentsOf: notesFileURL)
            let decoder = JSONDecoder()
            notes = try decoder.decode([SpatialNote].self, from: data)
            print("✅ Loaded \(notes.count) notes from \(notesFileURL.lastPathComponent)")
        } catch {
            print("❌ Failed to load notes: \(error)")
            notes = []
        }
    }
    
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(notes)
            try data.write(to: notesFileURL, options: .atomic)
            print("✅ Saved \(notes.count) notes to \(notesFileURL.lastPathComponent)")
        } catch {
            print("❌ Failed to save notes: \(error)")
        }
    }
}
