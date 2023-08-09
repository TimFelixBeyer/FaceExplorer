//
//  FilePicker.swift
//  FaceExplorer
//
//  Created by Tim Beyer on 01.03.23.
//  Copyright © 2023 Apple. All rights reserved.
//
import SwiftUI
import UniformTypeIdentifiers

extension ModelData {
    func selectLibrary() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Select your Photos Library"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [UTType("com.apple.photos.library")!]
        if openPanel.runModal() == .OK {
            if let url = openPanel.url {
                UserDefaults.standard.set(url, forKey: "PhotosLibraryPath")
                self.loadLibrary()
            }
        }
    }
}
