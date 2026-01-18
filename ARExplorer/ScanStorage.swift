import Foundation
import UIKit
import simd


enum ScanStorage {
    static func makeNewSpaceFolder() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let spaceId = UUID().uuidString
        let folder = docs.appendingPathComponent("Spaces/\(spaceId)", isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("photos", isDirectory: true),
            withIntermediateDirectories: true
        )
        let metadata: [String: Any] = [
            "title": "New Memory",
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        _ = try? saveJSON(metadata, to: folder.appendingPathComponent("info.json"))
        return folder
    }

    static func saveJPEG(from pixelBuffer: CVPixelBuffer, to url: URL) throws {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw NSError(domain: "ScanStorage", code: 1)
        }
        let uiImage = UIImage(cgImage: cgImage)

        guard let data = uiImage.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "ScanStorage", code: 2)
        }
        try data.write(to: url, options: .atomic)
    }

    static func saveJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
    }

    static func matrixToArray(_ m: simd_float4x4) -> [[Float]] {
        [
            [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w],
            [m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w],
            [m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w],
            [m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w]
        ]
    }
}
