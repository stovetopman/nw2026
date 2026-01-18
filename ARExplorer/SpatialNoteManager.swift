import ARKit
import RealityKit
import Combine
import simd

/// Manages spatial notes with ARKit anchor tracking and persistence
final class SpatialNoteManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var notes: [SpatialNote] = []
    @Published private(set) var isRelocalizingNotes: Bool = false
    @Published private(set) var relocalizationProgress: Float = 0.0
    
    // MARK: - Private Properties
    
    private weak var arView: ARView?
    private var folderURL: URL?
    private var anchorSubscription: Cancellable?
    
    /// Maps anchor identifiers to note IDs for quick lookup
    private var anchorToNoteMap: [UUID: UUID] = [:]
    
    // MARK: - File URLs
    
    private var notesFileURL: URL? {
        folderURL?.appendingPathComponent("notes.json")
    }
    
    private var worldMapFileURL: URL? {
        folderURL?.appendingPathComponent("worldmap.arworldmap")
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    /// Configure the manager with an ARView and storage folder
    func configure(arView: ARView, folderURL: URL) {
        self.arView = arView
        self.folderURL = folderURL
        
        // Load existing notes
        loadNotes()
        
        // Try to load world map for relocalization
        loadWorldMap()
        
        print("✅ SpatialNoteManager configured for: \(folderURL.lastPathComponent)")
    }
    
    // MARK: - Note Creation (Raycast Method)
    
    /// Create a note at screen center using raycast
    /// - Parameters:
    ///   - text: The note content
    ///   - completion: Called with the created note, or nil if raycast failed
    func createNoteAtScreenCenter(text: String, author: String = "me", completion: @escaping (SpatialNote?) -> Void) {
        guard let arView = arView else {
            print("❌ ARView not configured")
            completion(nil)
            return
        }
        
        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        createNote(at: screenCenter, text: text, author: author, completion: completion)
    }
    
    /// Create a note at a specific screen position using raycast
    func createNote(at screenPoint: CGPoint, text: String, author: String = "me", completion: @escaping (SpatialNote?) -> Void) {
        guard let arView = arView,
              let query = arView.makeRaycastQuery(
                from: screenPoint,
                allowing: .estimatedPlane,
                alignment: .any
              ) else {
            print("❌ Failed to create raycast query")
            // Fallback: place note 1.5m in front of camera
            createNoteFallback(text: text, author: author, completion: completion)
            return
        }
        
        // Perform raycast
        let results = arView.session.raycast(query)
        
        if let firstResult = results.first {
            // Got a valid raycast hit
            let worldTransform = firstResult.worldTransform
            createNoteWithTransform(worldTransform, text: text, author: author, completion: completion)
        } else {
            print("⚠️ Raycast found no surfaces, using fallback placement")
            createNoteFallback(text: text, author: author, completion: completion)
        }
    }
    
    /// Fallback: place note in front of camera when raycast fails
    private func createNoteFallback(text: String, author: String, completion: @escaping (SpatialNote?) -> Void) {
        guard let arView = arView,
              let cameraTransform = arView.session.currentFrame?.camera.transform else {
            completion(nil)
            return
        }
        
        // Place 1.5 meters in front of camera
        let forward = SIMD3<Float>(-cameraTransform.columns.2.x,
                                    -cameraTransform.columns.2.y,
                                    -cameraTransform.columns.2.z)
        let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                          cameraTransform.columns.3.y,
                                          cameraTransform.columns.3.z)
        let notePosition = cameraPosition + forward * 1.5
        
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(notePosition.x, notePosition.y, notePosition.z, 1)
        
        createNoteWithTransform(transform, text: text, author: author, completion: completion)
    }
    
    /// Create note with a specific world transform
    private func createNoteWithTransform(_ transform: simd_float4x4, text: String, author: String, completion: @escaping (SpatialNote?) -> Void) {
        guard let arView = arView else {
            completion(nil)
            return
        }
        
        // Create ARAnchor
        let noteID = UUID()
        let anchor = SpatialNoteAnchor(noteID: noteID, transform: transform)
        
        // Add anchor to session
        arView.session.add(anchor: anchor)
        
        // Create note
        let note = SpatialNote(
            id: noteID,
            anchorID: anchor.identifier,
            text: text,
            author: author,
            transform: transform
        )
        
        // Track mapping
        anchorToNoteMap[anchor.identifier] = noteID
        
        // Add to collection
        notes.append(note)
        saveNotes()
        
        print("✅ Created spatial note at \(note.position)")
        completion(note)
    }
    
    // MARK: - Note Management
    
    func updateNote(_ note: SpatialNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            saveNotes()
        }
    }
    
    func deleteNote(_ note: SpatialNote) {
        // Remove anchor from session
        if let arView = arView {
            let anchors = arView.session.currentFrame?.anchors ?? []
            if let anchor = anchors.first(where: { $0.identifier == note.anchorID }) {
                arView.session.remove(anchor: anchor)
            }
        }
        
        // Remove from tracking
        anchorToNoteMap.removeValue(forKey: note.anchorID)
        
        // Remove from collection
        notes.removeAll { $0.id == note.id }
        saveNotes()
    }
    
    // MARK: - Anchor Updates (call from ARSessionDelegate)
    
    /// Update note transforms when anchors are updated by ARKit
    func updateAnchors(_ anchors: [ARAnchor]) {
        var didUpdate = false
        
        for anchor in anchors {
            guard let noteID = anchorToNoteMap[anchor.identifier],
                  let index = notes.firstIndex(where: { $0.id == noteID }) else {
                continue
            }
            
            // Update transform from anchor
            notes[index].transform = anchor.transform
            
            // Mark as relocalized if it was pending
            if !notes[index].isRelocalized {
                notes[index].isRelocalized = true
                didUpdate = true
            }
        }
        
        if didUpdate {
            updateRelocalizationStatus()
        }
    }
    
    /// Handle anchors being added (for relocalization)
    func handleAddedAnchors(_ anchors: [ARAnchor]) {
        for anchor in anchors {
            // Check if this matches any pending note anchor
            if let noteID = anchorToNoteMap[anchor.identifier],
               let index = notes.firstIndex(where: { $0.id == noteID }) {
                notes[index].transform = anchor.transform
                notes[index].isRelocalized = true
            }
        }
        updateRelocalizationStatus()
    }
    
    private func updateRelocalizationStatus() {
        let totalNotes = notes.count
        guard totalNotes > 0 else {
            isRelocalizingNotes = false
            relocalizationProgress = 1.0
            return
        }
        
        let relocalizedCount = notes.filter { $0.isRelocalized }.count
        relocalizationProgress = Float(relocalizedCount) / Float(totalNotes)
        isRelocalizingNotes = relocalizedCount < totalNotes
    }
    
    // MARK: - Persistence (JSON)
    
    private func loadNotes() {
        guard let url = notesFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            notes = []
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = try decoder.decode([SpatialNote].self, from: data)
            
            // Rebuild anchor map
            anchorToNoteMap.removeAll()
            for note in notes {
                anchorToNoteMap[note.anchorID] = note.id
            }
            
            print("✅ Loaded \(notes.count) spatial notes")
        } catch {
            print("❌ Failed to load notes: \(error)")
            notes = []
        }
    }
    
    private func saveNotes() {
        guard let url = notesFileURL else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: url, options: .atomic)
            print("✅ Saved \(notes.count) spatial notes")
        } catch {
            print("❌ Failed to save notes: \(error)")
        }
    }
    
    // MARK: - World Map Persistence
    
    /// Save current world map for future relocalization
    func saveWorldMap(completion: @escaping (Bool) -> Void) {
        guard let arView = arView,
              let url = worldMapFileURL else {
            completion(false)
            return
        }
        
        arView.session.getCurrentWorldMap { worldMap, error in
            guard let map = worldMap else {
                print("❌ Failed to get world map: \(error?.localizedDescription ?? "unknown")")
                completion(false)
                return
            }
            
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                try data.write(to: url, options: .atomic)
                print("✅ Saved world map with \(map.anchors.count) anchors")
                completion(true)
            } catch {
                print("❌ Failed to save world map: \(error)")
                completion(false)
            }
        }
    }
    
    /// Load world map for relocalization
    private func loadWorldMap() {
        guard let arView = arView,
              let url = worldMapFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                print("⚠️ Failed to unarchive world map")
                return
            }
            
            // Run session with world map for relocalization
            let config = ARWorldTrackingConfiguration()
            config.initialWorldMap = worldMap
            
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            
            arView.session.run(config, options: [])
            
            isRelocalizingNotes = true
            print("✅ Loaded world map, starting relocalization...")
            
        } catch {
            print("❌ Failed to load world map: \(error)")
        }
    }
    
    /// Re-add anchors from notes to current session
    func restoreAnchorsToSession() {
        guard let arView = arView else { return }
        
        for note in notes {
            let anchor = SpatialNoteAnchor(noteID: note.id, transform: note.transform)
            arView.session.add(anchor: anchor)
            anchorToNoteMap[anchor.identifier] = note.id
        }
        
        print("✅ Restored \(notes.count) note anchors to session")
    }
}

// MARK: - Billboard Transform Helper

extension SpatialNoteManager {
    
    /// Calculate billboard transform for a note to face the camera
    func billboardTransform(for note: SpatialNote) -> simd_float4x4? {
        guard let arView = arView,
              let cameraTransform = arView.session.currentFrame?.camera.transform else {
            return nil
        }
        
        let notePosition = note.position
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        // Calculate look-at rotation (Y-axis only for billboard)
        let direction = normalize(cameraPosition - notePosition)
        let right = normalize(cross(SIMD3<Float>(0, 1, 0), direction))
        let up = cross(direction, right)
        
        var billboard = matrix_identity_float4x4
        billboard.columns.0 = SIMD4<Float>(right.x, right.y, right.z, 0)
        billboard.columns.1 = SIMD4<Float>(up.x, up.y, up.z, 0)
        billboard.columns.2 = SIMD4<Float>(direction.x, direction.y, direction.z, 0)
        billboard.columns.3 = SIMD4<Float>(notePosition.x, notePosition.y, notePosition.z, 1)
        
        return billboard
    }
}
