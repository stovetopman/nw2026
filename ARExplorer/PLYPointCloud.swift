import Foundation
import simd

struct PLYPoint: Hashable {
    var position: SIMD3<Float>
    var color: SIMD3<UInt8>
}

enum PLYPointCloudError: Error {
    case invalidHeader
    case unsupportedFormat
    case missingVertexCount
    case malformedVertexLine
}

enum PLYPointCloud {
    static func write(points: [PLYPoint], to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let header = """
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

        handle.write(Data(header.utf8))

        let locale = Locale(identifier: "en_US_POSIX")
        for point in points {
            let line = String(
                format: "%.5f %.5f %.5f %d %d %d\n",
                locale: locale,
                point.position.x,
                point.position.y,
                point.position.z,
                Int(point.color.x),
                Int(point.color.y),
                Int(point.color.z)
            )
            handle.write(Data(line.utf8))
        }
    }

    static func read(from url: URL) throws -> [PLYPoint] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .ascii) else {
            throw PLYPointCloudError.invalidHeader
        }

        let lines = text.split(whereSeparator: \.isNewline)
        guard let first = lines.first, first == "ply" else {
            throw PLYPointCloudError.invalidHeader
        }

        var vertexCount: Int?
        var dataStartIndex: Int?

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("format ") {
                if !line.contains("ascii") {
                    throw PLYPointCloudError.unsupportedFormat
                }
            } else if line.hasPrefix("element vertex") {
                let parts = line.split(separator: " ")
                if let countString = parts.last, let count = Int(countString) {
                    vertexCount = count
                }
            } else if line == "end_header" {
                dataStartIndex = index + 1
                break
            }
        }

        guard let count = vertexCount else {
            throw PLYPointCloudError.missingVertexCount
        }
        guard let startIndex = dataStartIndex else {
            throw PLYPointCloudError.invalidHeader
        }

        var points: [PLYPoint] = []
        points.reserveCapacity(count)

        for i in 0..<count {
            let lineIndex = startIndex + i
            if lineIndex >= lines.count {
                break
            }

            let parts = lines[lineIndex].split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count < 6 {
                throw PLYPointCloudError.malformedVertexLine
            }

            guard let x = Float(String(parts[0])),
                  let y = Float(String(parts[1])),
                  let z = Float(String(parts[2])),
                  let r = UInt8(String(parts[3])),
                  let g = UInt8(String(parts[4])),
                  let b = UInt8(String(parts[5])) else {
                throw PLYPointCloudError.malformedVertexLine
            }

            points.append(PLYPoint(position: SIMD3<Float>(x, y, z), color: SIMD3<UInt8>(r, g, b)))
        }

        return points
    }
}
