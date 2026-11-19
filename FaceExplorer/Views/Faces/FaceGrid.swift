import SwiftUI

struct FaceGrid: View {
    @EnvironmentObject var modelData: ModelData
    @State private var tagFilter = TagFilterCategory(
        rawValue: UserDefaults.standard.string(forKey: "FaceExplorer.TagFilter") ?? ""
    ) ?? .all
    @State private var attributeFilters = Self.loadAttributeFilters()
    @State private var sortBy: String = UserDefaults.standard.string(forKey: "FaceExplorer.SortBy") ?? "Date"
    @State private var selectedFace: Face?
    @FocusState private var focusedField: UUID?
    @State private var visibility = Self.loadVisibility()

    /// Restores saved filters while supplying defaults for newly introduced attributes.
    private static func loadAttributeFilters() -> [String: Int] {
        var filters = getFaceAttributes().reduce(into: [String: Int]()) { $0[$1.displayName] = -1 }
        let savedFilters = UserDefaults.standard.dictionary(
            forKey: "FaceExplorer.AttributeFilters"
        ) as? [String: Int] ?? [:]
        for key in filters.keys where savedFilters[key] != nil {
            filters[key] = savedFilters[key]
        }
        return filters
    }

    /// Restores saved attribute visibility and defaults for attributes added in future releases.
    private static func loadVisibility() -> [String: Bool] {
        var values = getFaceAttributes().reduce(into: [String: Bool]()) { $0[$1.displayName] = false }
        for key in ["Age", "Date", "Name"] {
            values[key] = true
        }
        let savedValues = UserDefaults.standard.dictionary(forKey: "FaceExplorer.Visibility") as? [String: Bool] ?? [:]
        for key in values.keys where savedValues[key] != nil {
            values[key] = savedValues[key]
        }
        return values
    }

    var filteredFaces: [Face] {
        modelData.faces.filter { face in
            (tagFilter == .all || tagFilter.rawValue == face.category.rawValue)
            && attributeFilters.allSatisfy({(key: String, value: Int) in
                (value == -1 || value == face.attributes[key]!.0)
            })
        }
    }

    private var title: String {
        let title = tagFilter == .all ? "Faces" : tagFilter.rawValue
        return title
    }

    private var index: Int? {
        modelData.faces.firstIndex(where: { $0.id == selectedFace?.id })
    }

    private var layout = [GridItem(.adaptive(minimum: 170, maximum: 250))]

    var body: some View {
        ScrollView {
            VStack {
                Text("Showing \(filteredFaces.count) faces")
                    .padding(.top, 20)
                    .foregroundColor(.secondary)
                LazyVGrid(columns: layout, spacing: 10) {
                    ForEach(filteredFaces, id: \.self) { face in
                        FaceCard(face: face, visibility: $visibility, focusedField: $focusedField)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .toolbar {
                Toolbar(
                    filteredFaces: filteredFaces,
                    tagFilter: $tagFilter,
                    attributeFilters: $attributeFilters,
                    sortBy: $sortBy,
                    visibility: $visibility
                )
            }
        }
        .onChange(of: sortBy, perform: { _ in
            UserDefaults.standard.set(sortBy, forKey: "FaceExplorer.SortBy")
            if sortBy == "Date" {
                modelData.sortByDate()
            } else if sortBy == "Name" {
                modelData.sortByName()
            } else {
                modelData.sortBy(displayName: sortBy)
            }
        })
        .onAppear {
            let isBuiltInSort = ["Date", "Name"].contains(sortBy)
            let isAttributeSort = modelData.faceAttributes.contains { $0.displayName == sortBy }
            if !isBuiltInSort && !isAttributeSort {
                sortBy = "Date"
            }
            applySort()
        }
        .onChange(of: tagFilter, perform: { _ in
            UserDefaults.standard.set(tagFilter.rawValue, forKey: "FaceExplorer.TagFilter")
        })
        .onChange(of: attributeFilters, perform: { _ in
            UserDefaults.standard.set(attributeFilters, forKey: "FaceExplorer.AttributeFilters")
        })
        .onChange(of: visibility, perform: { _ in
            UserDefaults.standard.set(visibility, forKey: "FaceExplorer.Visibility")
        })
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 100, maxHeight: .infinity, alignment: .topLeading)
        .alert(modelData.errorMessage, isPresented: $modelData.errorOccurred) {
            Button("Select Library...", action: modelData.selectLibrary)
            Button("Close", role: .cancel, action: {})
        }
    }

    /// Applies the selected sort after launch and whenever the sort preference changes.
    private func applySort() {
        if sortBy == "Date" {
            modelData.sortByDate()
        } else if sortBy == "Name" {
            modelData.sortByName()
        } else {
            modelData.sortBy(displayName: sortBy)
        }
    }
}

struct FaceGrid_Previews: PreviewProvider {
    static var previews: some View {
        FaceGrid()
            .environmentObject(ModelData())
    }
}
