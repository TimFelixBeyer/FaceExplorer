import SwiftUI

extension FaceGrid {
    struct Toolbar: ToolbarContent {
        @Environment(ModelData.self) private var modelData

        let filteredFaces: [Face]
        @Binding var tagFilter: TagFilterCategory
        /// Selected raw value per attribute; attributes without an entry aren't filtered.
        @Binding var attributeFilters: [String: Int]
        @Binding var visibility: [String: Bool]

        @State private var albumName = ""
        @State private var albumError: String?
        @State private var isCreatingAlbum = false
        @State private var isAlbumPopoverPresented = false

        var body: some ToolbarContent {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: modelData.selectLibrary) {
                    Label("Change Library…", systemImage: "arrow.left.arrow.right.circle")
                }
                .labelStyle(.titleAndIcon)
                .keyboardShortcut("o")

                Button(action: modelData.loadLibrary) {
                    Label("Reload Faces", systemImage: "arrow.clockwise")
                }
                .help("Reload Faces")
                .keyboardShortcut("r")
                .disabled(modelData.isLoading)

                Button {
                    albumName = tagFilter.rawValue
                    albumError = nil
                    isAlbumPopoverPresented = true
                } label: {
                    Label("Create Album", systemImage: "rectangle.stack.badge.plus")
                }
                .help("Create an Album in Photos with the Shown Faces")
                .keyboardShortcut("n")
                .popover(isPresented: $isAlbumPopoverPresented, arrowEdge: .bottom) {
                    createAlbumForm
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Group {
                    filterMenu
                    sortMenu
                    visibilityMenu
                }
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 100)
            }
        }

        private var createAlbumForm: some View {
            VStack(alignment: .leading) {
                HStack {
                    TextField("Album Name", text: $albumName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isCreatingAlbum)
                        .frame(width: 200)
                    Button(isCreatingAlbum ? "Creating…" : "Create Album", action: createAlbum)
                        .disabled(albumName.isEmpty || isCreatingAlbum)
                        .keyboardShortcut(.defaultAction)
                        .frame(minWidth: 100)
                }
                if let albumError {
                    Text(albumError)
                        .foregroundStyle(.red)
                        .frame(width: 300, alignment: .leading)
                }
            }
            .padding()
        }

        private func createAlbum() {
            Task {
                isCreatingAlbum = true
                defer { isCreatingAlbum = false }
                do {
                    try await PhotosLibraryAPI.createAlbum(name: albumName, photoUUIDs: filteredFaces.map(\.photoUUID))
                    isAlbumPopoverPresented = false
                } catch {
                    albumError = error.localizedDescription
                }
            }
        }

        private var filterMenu: some View {
            Menu {
                Picker("Category", selection: $tagFilter) {
                    ForEach(TagFilterCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.inline)
                ForEach(modelData.faceAttributes, id: \.self) { attribute in
                    Picker(attribute.displayName, selection: $attributeFilters[attribute.displayName]) {
                        Text("All").tag(Int?.none)
                        ForEach(attribute.mapping.keys.sorted(), id: \.self) { value in
                            Text(attribute.mapping[value] ?? "").tag(Int?.some(value))
                        }
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.horizontal.3.decrease.circle")
            }
        }

        private var sortMenu: some View {
            Menu {
                Picker("Sort By", selection: Bindable(modelData).sortOrder) {
                    Text("Date").tag(SortOrder.date)
                    Text("Name").tag(SortOrder.name)
                    ForEach(modelData.faceAttributes, id: \.self) { attribute in
                        Text(attribute.displayName).tag(SortOrder.attribute(attribute.displayName))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }

        private var visibilityMenu: some View {
            Menu {
                ForEach(["Date", "Name"] + modelData.faceAttributes.map(\.displayName), id: \.self) { key in
                    Toggle(key, isOn: Binding(
                        get: { visibility[key, default: false] },
                        set: { visibility[key] = $0 }
                    ))
                }
            } label: {
                Label("Visibility", systemImage: "eye")
            }
        }
    }
}
