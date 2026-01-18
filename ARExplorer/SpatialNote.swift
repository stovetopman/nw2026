import Foundation
import simd

/// A note anchored to a specific 3D coordinate using ARKit anchors
struct SpatialNote: Identifiable, Codable, Equatable {
    let id: UUID                    // note_id
    let anchorID: UUID              // anchor_id - links to ARAnchor
    var text: String
    var author: String
    var date: Date
    var transform: simd_float4x4    // 4x4 world transform matrix
    
    /// Whether the anchor has been relocalized in the current AR session
    var isRelocalized: Bool = false
    
    init(
        id: UUID = UUID(),
        anchorID: UUID,
        text: String,
        author: String = "me",
        date: Date = Date(),
        transform: simd_float4x4
    ) {
        self.id = id
        self.anchorID = anchorID
        self.text = text
        self.author = author
        self.date = date
        self.transform = transform
        self.isRelocalized = false
    }
    
    /// Convenience: Get position from transform
    var position: SIMD3<Float> {
        SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
    
    // Custom Codable for simd_float4x4 as 16-element array
    enum CodingKeys: String, CodingKey {
        case note_id, anchor_id, content, transform, creation_date, author
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .note_id)
        anchorID = try container.decode(UUID.self, forKey: .anchor_id)
        text = try container.decode(String.self, forKey: .content)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "me"
        date = try container.decode(Date.self, forKey: .creation_date)
        
        // Decode 4x4 matrix as 16-element array (column-major)
        let transformArray = try container.decode([Float].self, forKey: .transform)
        guard transformArray.count == 16 else {
            throw DecodingError.dataCorruptedError(
                forKey: .transform,
                in: container,
                debugDescription: "Transform must have 16 elements"
            )
        }
        transform = simd_float4x4(
            SIMD4<Float>(transformArray[0], transformArray[1], transformArray[2], transformArray[3]),
            SIMD4<Float>(transformArray[4], transformArray[5], transformArray[6], transformArray[7]),
            SIMD4<Float>(transformArray[8], transformArray[9], transformArray[10], transformArray[11]),
            SIMD4<Float>(transformArray[12], transformArray[13], transformArray[14], transformArray[15])
        )
        isRelocalized = false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .note_id)
        try container.encode(anchorID, forKey: .anchor_id)
        try container.encode(text, forKey: .content)
        try container.encode(author, forKey: .author)
        try container.encode(date, forKey: .creation_date)
        
        // Encode 4x4 matrix as 16-element array (column-major)
        let t = transform
        let transformArray: [Float] = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w
        ]
        try container.encode(transformArray, forKey: .transform)
    }
    
    var dateText: String {
        Self.dateFormatter.string(from: date)
    }
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()
}

// MARK: - Transform Helpers

extension SpatialNote {
    /// Create a transform matrix from a position
    static func transformFromPosition(_ position: SIMD3<Float>) -> simd_float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1)
        return transform
    }
}
