//
//  AppState.swift
//  ARExplorer - LiDAR Memory
//
//  Global app state management for the 3-state UI flow.
//

import Foundation
import SwiftUI

/// App states for the LiDAR Memory flow
enum AppState: Equatable {
    case scanning
    case saving(progress: Float)
    case exploring(usdzURL: URL)
    
    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
    
    var isSaving: Bool {
        if case .saving = self { return true }
        return false
    }
    
    var isExploring: Bool {
        if case .exploring = self { return true }
        return false
    }
}

/// Main view model for app state coordination
@MainActor
final class AppViewModel: ObservableObject {
    @Published var state: AppState = .scanning
    @Published var scanSession = ScanSession()
    @Published var showMemoryPicker = false
    @Published var savedMemories: [URL] = []
    
    let scanningEngine = ScanningEngine()
    let memoryManager = MemoryManager()
    
    init() {
        refreshSavedMemories()
    }
    
    func refreshSavedMemories() {
        savedMemories = MemoryManager.listSavedMemories()
    }
    
    func startScanning() {
        state = .scanning
    }
    
    func saveCurrentScan() {
        guard case .scanning = state else { return }
        
        let meshes = scanningEngine.allColoredMeshes
        
        guard !meshes.isEmpty else {
            print("⚠️ No mesh data to save")
            return
        }
        
        state = .saving(progress: 0)
        scanningEngine.stopScanning()
        
        memoryManager.exportToUSDZ(meshes: meshes) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    print("✅ Memory saved to: \(url)")
                    self?.refreshSavedMemories()
                    self?.state = .exploring(usdzURL: url)
                    
                case .failure(let error):
                    print("❌ Save failed: \(error)")
                    self?.state = .scanning
                }
            }
        }
    }
    
    func exploreMemory(at url: URL) {
        scanningEngine.stopScanning()
        state = .exploring(usdzURL: url)
    }
    
    func returnToScanning() {
        state = .scanning
    }
}
