//
//  ARExplorerApp.swift
//  ARExplorer
//
//  Created by Jasper Mao on 2026-01-17.
//

import SwiftUI

@main
struct ARExplorerApp: App {
    init() {
        // Ensure Documents directory is accessible and create a marker file
        // This helps the Files app recognize this app has shareable files
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let readmeURL = docs.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: readmeURL.path) {
            let content = "Memories App - Point Cloud Scans\n\nYour PLY scan files will appear in this folder."
            try? content.write(to: readmeURL, atomically: true, encoding: .utf8)
            print("📁 Created README at: \(docs.path)")
        }
        print("📁 Documents folder: \(docs.path)")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
