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

    static func exportPLY(from sourceURL: URL, spaceID: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Use a timestamp-based name for easier identification
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "PointCloud_\(timestamp).ply"
        
        let destinationURL = docs.appendingPathComponent(fileName)
        
        // Read source file data
        let sourceData = try Data(contentsOf: sourceURL)
        
        // Write directly to destination
        try sourceData.write(to: destinationURL, options: [.atomic])
        
        // Verify the file was created and log
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let size = (attrs?[.size] as? Int) ?? 0
            print("✅ PLY exported successfully:")
            print("   Path: \(destinationURL.path)")
            print("   Size: \(size) bytes")
            
            // List all files in Documents to verify
            let contents = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
            print("📂 Documents folder contents:")
            for file in contents ?? [] {
                print("   - \(file.lastPathComponent)")
            }
        }
        
        return destinationURL
    }

    static func saveJPEG(from pixelBuffer: CVPixelBuffer, to url: URL) throws {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw NSError(domain: "ScanStorage", code: 1)
        }
        // Apply correct orientation - ARKit camera feed is rotated 90° CW, so we correct with .right
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

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
