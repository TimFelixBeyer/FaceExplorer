import SwiftUI

struct FaceGrid: View {
    @EnvironmentObject var modelData: ModelData
    @State private var tagFilter = TagFilterCategory.all
    @State private var attributeFilters = getFaceAttributes().reduce(into: [String: Int]()) { $0[$1.displayName] = -1 }
    @State private var sortBy: String = "Date"
    @State private var selectedFace: Face?
    @FocusState private var focusedField: UUID?
    @State private var visibility: [String: Bool] =
    {
        var viz: [String: Bool] = [:]
        for attr in getFaceAttributes() {
            viz[attr.displayName] = false
        }
        // attributes that are visible by default
        for attr in ["Age", "Date", "Name"] {
            viz[attr] = true
        }
        return viz
    }()

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
            if sortBy == "Date" {
                modelData.sortByDate()
            } else if sortBy == "Name" {
                modelData.sortByName()
            } else {
                modelData.sortBy(displayName: sortBy)
            }
        })
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 100, maxHeight: .infinity, alignment: .topLeading)
        .alert(modelData.errorMessage!, isPresented: $modelData.errorOccurred) {
            Button("Select Library...", action: modelData.selectLibrary)
            Button("Close", role: .cancel, action: {})
        }
    }
}

struct FaceGrid_Previews: PreviewProvider {
    static var previews: some View {
        FaceGrid()
            .environmentObject(ModelData())
    }
}
