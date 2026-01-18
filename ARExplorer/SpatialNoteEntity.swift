import RealityKit
import ARKit
import simd

/// A RealityKit entity that displays a spatial note with billboard behavior
final class SpatialNoteEntity: Entity, HasAnchoring {
    
    // MARK: - Properties
    
    /// The associated note data
    private(set) var note: SpatialNote
    
    /// Visual components
    private var markerEntity: ModelEntity?
    private var textEntity: ModelEntity?
    private var backgroundEntity: ModelEntity?
    
    /// Whether this is a "ghost" (not yet relocalized)
    var isGhost: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    
    // MARK: - Constants
    
    private static let markerRadius: Float = 0.015
    private static let markerColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // Yellow
    private static let ghostColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 0.4)
    
    // MARK: - Initialization
    
    required init() {
        self.note = SpatialNote(
            anchorID: UUID(),
            text: "",
            transform: matrix_identity_float4x4
        )
        super.init()
    }
    
    init(note: SpatialNote) {
        self.note = note
        super.init()
        
        setupVisuals()
        updateTransform()
    }
    
    // MARK: - Setup
    
    private func setupVisuals() {
        // Create marker sphere
        let markerMesh = MeshResource.generateSphere(radius: Self.markerRadius)
        var markerMaterial = SimpleMaterial()
        markerMaterial.color = .init(tint: Self.markerColor)
        markerMaterial.metallic = 0.0
        markerMaterial.roughness = 0.8
        
        markerEntity = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
        
        if let marker = markerEntity {
            addChild(marker)
        }
        
        // Create pulsing ring around marker
        let ringMesh = MeshResource.generateBox(
            width: Self.markerRadius * 3,
            height: 0.002,
            depth: Self.markerRadius * 3,
            cornerRadius: Self.markerRadius * 1.5
        )
        var ringMaterial = SimpleMaterial()
        ringMaterial.color = .init(tint: Self.markerColor.withAlphaComponent(0.5))
        
        let ringEntity = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
        addChild(ringEntity)
    }
    
    private func updateTransform() {
        // Position from note transform
        self.transform.matrix = note.transform
    }
    
    private func updateAppearance() {
        guard let marker = markerEntity else { return }
        
        var material = SimpleMaterial()
        material.color = .init(tint: isGhost ? Self.ghostColor : Self.markerColor)
        material.metallic = 0.0
        material.roughness = 0.8
        
        marker.model?.materials = [material]
    }
    
    // MARK: - Billboard Update
    
    /// Update orientation to face the camera
    func updateBillboard(cameraTransform: simd_float4x4) {
        let notePosition = self.position
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        // Calculate direction to camera (Y-axis billboard - only rotate around Y)
        let direction = cameraPosition - notePosition
        let flatDirection = SIMD3<Float>(direction.x, 0, direction.z)
        
        guard length(flatDirection) > 0.001 else { return }
        
        let normalizedDir = normalize(flatDirection)
        let angle = atan2(normalizedDir.x, normalizedDir.z)
        
        // Apply Y-rotation only
        self.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
    }
    
    // MARK: - Note Updates
    
    func update(with newNote: SpatialNote) {
        self.note = newNote
        updateTransform()
        isGhost = !newNote.isRelocalized
    }
    
    func updateTransform(_ newTransform: simd_float4x4) {
        self.transform.matrix = newTransform
    }
}

// MARK: - Note Entity Manager

/// Manages SpatialNoteEntity instances in the RealityKit scene
final class NoteEntityManager {
    
    private weak var arView: ARView?
    private var noteEntities: [UUID: SpatialNoteEntity] = [:]
    private var anchorEntities: [UUID: AnchorEntity] = [:]
    
    init(arView: ARView) {
        self.arView = arView
    }
    
    /// Add or update a note entity
    func addOrUpdate(note: SpatialNote) {
        guard let arView = arView else { return }
        
        if let existingEntity = noteEntities[note.id] {
            // Update existing
            existingEntity.update(with: note)
        } else {
            // Create new
            let noteEntity = SpatialNoteEntity(note: note)
            noteEntity.isGhost = !note.isRelocalized
            
            // Create anchor entity at note position
            let anchorEntity = AnchorEntity(world: note.position)
            anchorEntity.addChild(noteEntity)
            
            arView.scene.addAnchor(anchorEntity)
            
            noteEntities[note.id] = noteEntity
            anchorEntities[note.id] = anchorEntity
        }
    }
    
    /// Remove a note entity
    func remove(noteID: UUID) {
        if let anchorEntity = anchorEntities[noteID] {
            anchorEntity.removeFromParent()
        }
        noteEntities.removeValue(forKey: noteID)
        anchorEntities.removeValue(forKey: noteID)
    }
    
    /// Update all note entities with new positions
    func updatePositions(for notes: [SpatialNote]) {
        for note in notes {
            if let entity = noteEntities[note.id],
               let anchor = anchorEntities[note.id] {
                entity.update(with: note)
                anchor.transform.matrix = note.transform
            }
        }
    }
    
    /// Update billboard orientations to face camera
    func updateBillboards(cameraTransform: simd_float4x4) {
        for entity in noteEntities.values {
            entity.updateBillboard(cameraTransform: cameraTransform)
        }
    }
    
    /// Sync with notes array (add/remove as needed)
    func sync(with notes: [SpatialNote]) {
        let noteIDs = Set(notes.map { $0.id })
        
        // Remove entities for deleted notes
        let toRemove = noteEntities.keys.filter { !noteIDs.contains($0) }
        for id in toRemove {
            remove(noteID: id)
        }
        
        // Add/update all current notes
        for note in notes {
            addOrUpdate(note: note)
        }
    }
    
    /// Clear all entities
    func clear() {
        for anchor in anchorEntities.values {
            anchor.removeFromParent()
        }
        noteEntities.removeAll()
        anchorEntities.removeAll()
    }
}
