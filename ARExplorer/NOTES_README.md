# Spatial Notes System - Developer Documentation

> **Last Updated:** January 18, 2026  
> **Branch:** `maka_spatial_notes`  
> **Status:** 🟡 Partially Working

---

## Overview

The Spatial Notes system allows users to attach persistent notes to 3D positions within saved point cloud "memories". Notes are stored as JSON and should survive app restarts.

---

## Architecture

### Two Separate Contexts

The app has **two distinct viewing contexts** that handle notes differently:

| Context | Framework | View | Note System |
|---------|-----------|------|-------------|
| **Live AR Scanning** | RealityKit + ARKit | `ScanView` + `ARViewContainer` | `SpatialNoteManager` (NOT CONNECTED) |
| **Memory Viewer** | SceneKit | `MemoryViewerView` + `ViewerView` | `NoteStore` + `NoteMarkersOverlay` (WORKING) |

---

## Files & Their Status

### ✅ Working Files

| File | Purpose | Status |
|------|---------|--------|
| `SpatialNote.swift` | Data model with 4x4 transform, anchorID, Codable | ✅ Complete |
| `NoteStore.swift` | CRUD + JSON persistence per memory folder | ✅ Working |
| `NoteMarkerView.swift` | Yellow dot SwiftUI view with tap target | ✅ Working |
| `NoteCardView.swift` | Popup card showing note content, edit/delete | ✅ Working |
| `InlineNoteInput.swift` | Text input card that sits above keyboard | ✅ Working |
| `NoteMarkersOverlay.swift` | Projects 3D positions to screen space | ⚠️ Works but positioning may be off |

### 🟡 Partially Implemented / Not Connected

| File | Purpose | Status |
|------|---------|--------|
| `SpatialNoteManager.swift` | ARKit raycast, world map, anchor tracking | 🔴 **NOT CONNECTED** to UI |
| `SpatialNoteAnchor.swift` | ARAnchor subclass for notes | 🔴 **UNUSED** |
| `SpatialNoteEntity.swift` | RealityKit entity with billboard | 🔴 **UNUSED** |

---

## Data Model

### SpatialNote

```swift
struct SpatialNote: Identifiable, Codable, Equatable {
    let id: UUID                    // note_id
    let anchorID: UUID              // anchor_id - intended for ARAnchor linking
    var text: String
    var author: String
    var date: Date
    var transform: simd_float4x4    // 4x4 world transform matrix
    var isRelocalized: Bool         // For AR relocalization (unused)
    
    var position: SIMD3<Float>      // Computed from transform column 3
}
```

### JSON Schema

```json
{
  "note_id": "UUID",
  "anchor_id": "UUID",
  "content": "Note text",
  "author": "me",
  "creation_date": "2026-01-18T10:30:00Z",
  "transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, x,y,z,1]
}
```

### Storage Location

```
Documents/Spaces/<UUID>/
├── scene.ply
├── notes.json          ← Notes stored here
└── photos/
```

---

## What's Working (Memory Viewer)

### Flow

1. User opens a saved memory → `MemoryViewerView`
2. `ViewerView` loads PLY into SceneKit
3. `NoteStore` loads `notes.json` from memory folder
4. `NoteMarkersOverlay` projects note 3D positions to screen
5. Yellow dots appear, user can tap to select
6. `NoteCardView` shows note content with edit/delete

### Adding Notes in Memory Viewer

1. Tap yellow `+` button → enters placement mode
2. `DraggableNotePin` appears at screen center
3. User drags pin to desired position
4. Tap checkmark or release drag → pin is placed
5. `InlineNoteInput` appears above keyboard
6. User types note, taps Save
7. `saveNewNote()` creates `SpatialNote` with raycasted 3D position
8. Note saved to `notes.json`

---

## What's Broken / Not Working

### 1. 🔴 Note Position Accuracy

**Problem:** Notes don't appear at the exact 3D position where the user placed them.

**Root Cause:** The `placePin()` function in `MemoryViewerView` uses a simple ray cast:
```swift
// Current implementation places note 1.5 units from camera along ray
let distance: Float = 1.5
let notePos = cameraPos + normalizedDir * distance
```

This doesn't intersect with the actual point cloud geometry.

**Fix Needed:** Implement proper hit testing against the point cloud bounding box or create collision geometry.

---

### 2. 🔴 Live AR Notes Not Connected

**Problem:** `SpatialNoteManager`, `SpatialNoteAnchor`, and `SpatialNoteEntity` are fully implemented but **not connected to the UI**.

**Files Affected:**
- `ARViewContainer.swift` - Has `noteManager` property but UI doesn't trigger it
- `ScanView.swift` - Has crosshair and note input UI but uses notifications that aren't fully wired

**Fix Needed:** Connect `ScanView` note creation to `SpatialNoteManager.createNoteAtScreenCenter()`.

---

### 3. 🟡 Note Markers May Appear Off-Screen or Wrong Position

**Problem:** `NoteMarkersOverlay.updatePositions()` projects 3D to screen but may not account for:
- Point cloud center offset
- Camera orientation changes properly

**Symptoms:**
- Notes appear but not where expected
- Notes may cluster or overlap incorrectly

---

### 4. 🟡 ARWorldMap Persistence Untested

**Problem:** `SpatialNoteManager` has world map save/load logic but:
- Never tested
- May not trigger correctly
- Relocalization UI doesn't exist

---

### 5. 🟡 Billboard Behavior Not Working

**Problem:** `SpatialNoteEntity` has `updateBillboard()` method but:
- Entity is never added to scene
- `NoteEntityManager` exists but unused
- Notes in memory viewer use 2D overlay, not 3D entities

---

## Key Functions to Understand

### MemoryViewerView.swift

```swift
// Places note at fixed distance from camera (BROKEN)
private func placePin() {
    let distance: Float = 1.5
    let notePos = cameraPos + normalizedDir * distance
    placedWorldPosition = notePos
}

// Creates note with transform (WORKING)
private func saveNewNote() {
    let transform = SpatialNote.transformFromPosition(placedWorldPosition)
    let note = SpatialNote(anchorID: UUID(), text: text, transform: transform)
    noteStore.add(note)
}
```

### NoteMarkersOverlay.swift

```swift
// Projects 3D position to screen (MAY BE INACCURATE)
private func updatePositions() {
    let scnPosition = SCNVector3(note.position.x, note.position.y, note.position.z)
    let projected = scnView.projectPoint(scnPosition)
    // Doesn't account for point cloud center offset
}
```

### SpatialNoteManager.swift (NOT USED)

```swift
// Proper ARKit raycast implementation (NOT CONNECTED)
func createNote(at screenPoint: CGPoint, ...) {
    let query = arView.makeRaycastQuery(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
    let results = arView.session.raycast(query)
    // Creates proper ARAnchor
}
```

---

## Immediate Fixes Needed

### Priority 1: Fix Note Positioning in Memory Viewer

Update `placePin()` to use proper hit testing:

```swift
// Option A: Use SceneKit hit test
let hitResults = scnView.hitTest(pinPosition, options: [.rootNode: pointCloudNode])
if let hit = hitResults.first {
    placedWorldPosition = SIMD3<Float>(hit.worldCoordinates)
}

// Option B: Generate collision geometry for point cloud
// Add invisible bounding box for hit testing
```

### Priority 2: Connect Live AR Notes

In `ScanView.swift`, connect the note creation flow:

```swift
private func createNote() {
    let payload = CreateNotePayload(text: noteText)
    NotificationCenter.default.post(name: .createSpatialNote, object: payload)
}
```

Ensure `ARViewContainer` observes and calls `noteManager.createNoteAtScreenCenter()`.

### Priority 3: Account for Point Cloud Center Offset

In `NoteMarkersOverlay`, the point cloud is centered when loaded:

```swift
let center = (minPoint + maxPoint) * 0.5
// Points are stored as: position - center
```

When projecting notes, may need to add center back:
```swift
let adjustedPosition = note.position + pointCloudCenter
let scnPosition = SCNVector3(adjustedPosition.x, adjustedPosition.y, adjustedPosition.z)
```

---

## Testing Checklist

- [ ] Create note in memory viewer - does it appear?
- [ ] Close and reopen memory - do notes persist?
- [ ] Rotate camera - do notes follow correctly?
- [ ] Tap note marker - does card appear?
- [ ] Edit note text - does it save?
- [ ] Delete note - does it disappear and stay deleted?
- [ ] Create multiple notes - do they all show?
- [ ] Create note during live scan - does it work?

---

## File Dependencies

```
MemoryViewerView
├── ViewerView (SceneKit point cloud)
│   └── NoteViewerCoordinator (bridges SCNView to SwiftUI)
├── NoteStore (persistence)
├── NoteMarkersOverlay (3D → 2D projection)
│   └── NoteMarkerView (yellow dot)
├── NoteCardView (selected note popup)
├── InlineNoteInput (text entry)
└── DraggableNotePin (placement UI)

ScanView (Live AR)
├── ARViewContainer
│   └── SpatialNoteManager (NOT CONNECTED)
│       ├── SpatialNoteAnchor (unused)
│       └── SpatialNoteEntity (unused)
└── NotePlacementCrosshair (UI only)
```

---

## Recommended Next Steps

1. **Fix memory viewer note placement** - Implement proper hit testing
2. **Remove unused AR code OR connect it** - SpatialNoteManager/Entity/Anchor are orphaned
3. **Add visual feedback** - Show where note will be placed before confirming
4. **Test persistence** - Verify notes survive app restart
5. **Add note count badge** - Show number of notes on memory thumbnail
