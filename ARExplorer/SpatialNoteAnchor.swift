import ARKit
import simd

/// Custom ARAnchor subclass for spatial notes
/// This allows ARKit to track the note's position in world space
final class SpatialNoteAnchor: ARAnchor {
    
    /// The unique ID of the associated SpatialNote
    let noteID: UUID
    
    /// Initialize with a note ID and world transform
    init(noteID: UUID, transform: simd_float4x4) {
        self.noteID = noteID
        super.init(name: "SpatialNote-\(noteID.uuidString)", transform: transform)
    }
    
    /// Initialize from an existing ARAnchor (for relocalization)
    init(noteID: UUID, from anchor: ARAnchor) {
        self.noteID = noteID
        super.init(name: anchor.name ?? "SpatialNote-\(noteID.uuidString)", transform: anchor.transform)
    }
    
    // MARK: - Required Initializers
    
    required init(anchor: ARAnchor) {
        // Copy noteID from existing SpatialNoteAnchor if possible
        if let noteAnchor = anchor as? SpatialNoteAnchor {
            self.noteID = noteAnchor.noteID
        } else {
            // Fallback: try to parse from name
            if let name = anchor.name,
               name.hasPrefix("SpatialNote-"),
               let uuid = UUID(uuidString: String(name.dropFirst("SpatialNote-".count))) {
                self.noteID = uuid
            } else {
                self.noteID = UUID()
            }
        }
        super.init(anchor: anchor)
    }
    
    required init?(coder: NSCoder) {
        guard let noteIDString = coder.decodeObject(forKey: "noteID") as? String,
              let noteID = UUID(uuidString: noteIDString) else {
            return nil
        }
        self.noteID = noteID
        super.init(coder: coder)
    }
    
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(noteID.uuidString, forKey: "noteID")
    }
    
    override class var supportsSecureCoding: Bool {
        return true
    }
}

// MARK: - Anchor Creation Helpers

extension SpatialNoteAnchor {
    
    /// Create an anchor at a specific world position
    static func create(at position: SIMD3<Float>, noteID: UUID = UUID()) -> SpatialNoteAnchor {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        return SpatialNoteAnchor(noteID: noteID, transform: transform)
    }
    
    /// Position extracted from transform
    var position: SIMD3<Float> {
        SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}
