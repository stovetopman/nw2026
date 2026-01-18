//
//  PointCloudStorage.swift
//  ARExplorer
//
//  Save and load point clouds as PLY files.
//

import Foundation

/// Storage for point cloud files (PLY format)
enum PointCloudStorage {
    
    // MARK: - Directory
    
    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private static var pointCloudsDirectory: URL {
        let dir = documentsDirectory.appendingPathComponent("PointClouds")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    // MARK: - List
    
    static func listSavedPointClouds() -> [URL] {
        let dir = pointCloudsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "ply" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return date1 > date2
            }
    }
    
    // MARK: - Save
    
    static func save(points: [ColoredPoint]) async throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "scan_\(timestamp).ply"
        let url = pointCloudsDirectory.appendingPathComponent(filename)
        
        // Generate PLY content
        let plyData = generatePLY(points: points)
        try plyData.write(to: url, atomically: true, encoding: .utf8)
        
        return url
    }
    
    // MARK: - Load
    
    static func load(from url: URL) async throws -> [ColoredPoint] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parsePLY(content: content)
    }
    
    // MARK: - Delete
    
    static func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
    
    // MARK: - PLY Format
    
    private static func generatePLY(points: [ColoredPoint]) -> String {
        var ply = """
        ply
        format ascii 1.0
        element vertex \(points.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        
        """
        
        for point in points {
            ply += "\(point.position.x) \(point.position.y) \(point.position.z) "
            ply += "\(point.color.x) \(point.color.y) \(point.color.z)\n"
        }
        
        return ply
    }
    
    private static func parsePLY(content: String) -> [ColoredPoint] {
        var points: [ColoredPoint] = []
        var inHeader = true
        var vertexCount = 0
        
        let lines = content.split(separator: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if inHeader {
                if trimmed == "end_header" {
                    inHeader = false
                } else if trimmed.hasPrefix("element vertex") {
                    let parts = trimmed.split(separator: " ")
                    if parts.count >= 3, let count = Int(parts[2]) {
                        vertexCount = count
                        points.reserveCapacity(count)
                    }
                }
                continue
            }
            
            // Parse vertex line: x y z r g b
            let parts = trimmed.split(separator: " ")
            guard parts.count >= 6,
                  let x = Float(parts[0]),
                  let y = Float(parts[1]),
                  let z = Float(parts[2]),
                  let r = UInt8(parts[3]),
                  let g = UInt8(parts[4]),
                  let b = UInt8(parts[5]) else {
                continue
            }
            
            points.append(ColoredPoint(
                position: SIMD3<Float>(x, y, z),
                color: SIMD3<UInt8>(r, g, b)
            ))
        }
        
        return points
    }
}
