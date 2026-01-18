import Foundation

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
    static let saveScan = Notification.Name("saveScan")
    static let clearMap = Notification.Name("clearMap")
    static let startScan = Notification.Name("startScan")
    static let scanSaved = Notification.Name("scanSaved")
    static let viewerRecenter = Notification.Name("viewerRecenter")
    static let scanStatsUpdated = Notification.Name("scanStatsUpdated")
    static let updateScanDistance = Notification.Name("updateScanDistance")
    
    // Spatial Notes
    static let createSpatialNote = Notification.Name("createSpatialNote")
    static let deleteSpatialNote = Notification.Name("deleteSpatialNote")
}

/// Stats payload for scan updates
struct ScanStats {
    let pointCount: Int
    let maxDistance: Float
}

/// Payload for creating a spatial note
struct CreateNotePayload {
    let text: String
    let screenPoint: CGPoint?  // nil = screen center
    let author: String
    
    init(text: String, screenPoint: CGPoint? = nil, author: String = "me") {
        self.text = text
        self.screenPoint = screenPoint
        self.author = author
    }
}
