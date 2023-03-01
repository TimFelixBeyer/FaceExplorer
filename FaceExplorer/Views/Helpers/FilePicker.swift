//
//  FilePicker.swift
//  FaceExplorer
//
//  Created by Tim Beyer on 01.03.23.
//  Copyright © 2023 Apple. All rights reserved.
//
import SwiftUI
import UniformTypeIdentifiers

func FilePicker(modelData: ModelData) -> Void {
    let openPanel = NSOpenPanel()
    openPanel.prompt = "Select your Photos Library"
    openPanel.canChooseFiles = true
    openPanel.canChooseDirectories = false
    openPanel.allowsMultipleSelection = false
    openPanel.allowedContentTypes = Array([UTType("com.apple.photos.library")!])
    if openPanel.runModal() == .OK {
        if let url = openPanel.url {
            // Do something with the selected file URL
            UserDefaults.standard.set(url, forKey: "PhotosLibraryPath")
            modelData.persons = getPersons(path: "\(UserDefaults.standard.string(forKey: "PhotosLibraryPath")!)/database/Photos.sqlite")
            modelData.faces = getFaces(path: "\(UserDefaults.standard.string(forKey: "PhotosLibraryPath")!)/database/Photos.sqlite")
        }
    }
}
