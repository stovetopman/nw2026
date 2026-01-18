import Foundation
import simd

/// A note anchored to a specific 3D coordinate in a memory
struct SpatialNote: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var author: String
    var date: Date
    var position: SIMD3<Float>
    
    init(id: UUID = UUID(), text: String, author: String = "me", date: Date = Date(), position: SIMD3<Float>) {
        self.id = id
        self.text = text
        self.author = author
        self.date = date
        self.position = position
    }
    
    // Custom Codable for SIMD3<Float>
    enum CodingKeys: String, CodingKey {
        case id, text, author, date, x, y, z
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        author = try container.decode(String.self, forKey: .author)
        date = try container.decode(Date.self, forKey: .date)
        let x = try container.decode(Float.self, forKey: .x)
        let y = try container.decode(Float.self, forKey: .y)
        let z = try container.decode(Float.self, forKey: .z)
        position = SIMD3<Float>(x, y, z)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(author, forKey: .author)
        try container.encode(date, forKey: .date)
        try container.encode(position.x, forKey: .x)
        try container.encode(position.y, forKey: .y)
        try container.encode(position.z, forKey: .z)
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
