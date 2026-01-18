import Foundation

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
    static let saveScan = Notification.Name("saveScan")
    static let clearMap = Notification.Name("clearMap")
    static let startScan = Notification.Name("startScan")
    static let scanSaved = Notification.Name("scanSaved")
    static let scanFolderCreated = Notification.Name("scanFolderCreated")
    static let viewerRecenter = Notification.Name("viewerRecenter")
    static let scanStatsUpdated = Notification.Name("scanStatsUpdated")
    static let updateScanDistance = Notification.Name("updateScanDistance")
    static let updateConfidenceThreshold = Notification.Name("updateConfidenceThreshold")
    static let requestCameraPosition = Notification.Name("requestCameraPosition")
    static let cameraPositionResponse = Notification.Name("cameraPositionResponse")
    static let addNoteAtCrosshair = Notification.Name("addNoteAtCrosshair")
    static let noteAddedAtPosition = Notification.Name("noteAddedAtPosition")
}

/// Stats payload for scan updates
struct ScanStats {
    let pointCount: Int
    let maxDistance: Float
}
