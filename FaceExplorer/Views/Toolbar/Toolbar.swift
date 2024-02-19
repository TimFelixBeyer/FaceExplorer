//
//  ToolbarView.swift
//  FaceExplorer
//
//  Created by Tim Beyer on 14.02.24.
//  Copyright © 2024 Apple. All rights reserved.
//

import SwiftUI

extension FaceGrid {
    struct Toolbar: ToolbarContent {
        @EnvironmentObject var modelData: ModelData

        var filteredFaces: [Face]
        @Binding public var tagFilter: TagFilterCategory // special filter for named/unnamed faces
        @Binding public var attributeFilters: [String: Int]
        @Binding public var sortBy: String
        @Binding public var visibility: [String: Bool]

        @State private var albumName: String = ""
        @State private var makeAlbumInProgress: Bool = false
        @State private var isSheetPresented: Bool = false
        @State private var isReloadingLibrary: Bool = false

        var body: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                Button(action: modelData.selectLibrary) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                    Text("Change Library...")
                }
                .keyboardShortcut("o")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: modelData.loadLibrary) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload Faces")
                .keyboardShortcut("r")
            }
            // Make an album in Photos
            ToolbarItem(placement: .navigation) {
                Button {
                    isSheetPresented = true
                } label: {
                    Label("Create Album", systemImage: "rectangle.stack.badge.plus")
                }
                .disabled(isSheetPresented)
                .help("Create Album with Current Images")
                .popover(isPresented: $isSheetPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    HStack {
                        TextField("Enter Album Name", text: $albumName)
                            .onAppear { albumName = tagFilter.rawValue }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(albumName.isEmpty || makeAlbumInProgress)
                            .frame(width: 200)
                        Button(makeAlbumInProgress ? "Creating..." : "Create Album") {
                            Task {
                                makeAlbumInProgress = true
                                do {
                                    try await PhotosLibraryAPI().createAlbum(
                                        name: albumName,
                                        withLocalIdentifiers: filteredFaces.map(\.photoUUID.uuidString)
                                    )
                                } catch {
                                    modelData.displayError(error: error)
                                }
                                makeAlbumInProgress = false
                                isSheetPresented = false
                            }
                        }
                        .disabled(albumName.isEmpty || makeAlbumInProgress)
                        .keyboardShortcut(.defaultAction)
                        .frame(minWidth: 100)
                    }
                    .padding()
                }
                .keyboardShortcut("n")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Category", selection: $tagFilter) {
                        ForEach(TagFilterCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                    ForEach(modelData.faceAttributes, id: \.self) { (attr: FaceAttribute) in
                        Picker(attr.displayName, selection: $attributeFilters[attr.displayName]) {
                            ForEach(Array(attr.mapping.keys).sorted(), id: \.self) {
                                Text(attr.mapping[$0]!).tag($0 as Int?)
                            }
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.horizontal.3.decrease.circle")
                }
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 90)
                Menu {
                    Picker("Category", selection: $sortBy) {
                        Text("Date").tag("Date")
                        Text("Name").tag("Name")
                        ForEach(modelData.faceAttributes, id: \.self) { (attr: FaceAttribute) in
                            Text(attr.displayName).tag(attr.displayName)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 90)
                Menu {
                    ForEach(visibility.keys.sorted(), id: \.self) {key in
                        Toggle(key, isOn: Binding<Bool>(
                            get: { visibility[key] ?? false },
                            set: { visibility[key] = $0 }
                        ))
                    }
                }  label: {
                    Label("Visibility", systemImage: "eye")
                }
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 110)
            }
        }
    }
}
