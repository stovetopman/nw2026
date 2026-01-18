//
//  MetalLibLoader.swift
//  ARExplorer
//
//  Loads the Metal shader library for custom materials.
//

import Metal
import RealityKit

/// Provides access to the compiled Metal shader library
enum MetalLibLoader {
    
    /// The default Metal library containing custom shaders
    static let library: MTLLibrary = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default Metal library")
        }
        
        return library
    }()
}
