import SwiftUI

struct FaceGrid: View {
    @EnvironmentObject var modelData: ModelData
    @State private var filterTagged = FilterCategory.all
    @State private var filters: [String: Int] = {
        var x: [String: Int] = [:]
        for attr in getFaceAttributes() {
            x[attr.displayName] = -1
        }
        return x
    }()
    
    @State private var selectedFace: Face?
    @State private var visibility: [String: Bool] =
    {
        var viz: [String: Bool] = ["Date": true]
        for attr in getFaceAttributes() {
            viz[attr.displayName] = false
        }
        return viz
    }()

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case untagged = "Untagged"
        case tagged = "Tagged"
        var id: FilterCategory { self }
    }

    var filteredFaces: [Face] {
        modelData.faces.filter { face in
            (filterTagged == .all || filterTagged.rawValue == face.category.rawValue)
            && filters.allSatisfy({(key: String, value: Int) in
                (value == -1 || value == face.attributes[key]!.0)
            })
        }
    }

    var title: String {
        let title = filterTagged == .all ? "Faces" : filterTagged.rawValue
        return title
    }

    var index: Int? {
        modelData.faces.firstIndex(where: { $0.id == selectedFace?.id })
    }

    var layout = [GridItem(.adaptive(minimum: 170, maximum: 250))]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: layout, spacing: 10) {
                ForEach(filteredFaces, id: \.self) { face in
                    FaceCard(face: face, visibility: $visibility)
                }
            }
            .padding(20)
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        Picker("Category", selection: $filterTagged) {
                            ForEach(FilterCategory.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.inline)
                        ForEach(modelData.faceAttributes, id: \.self) { (attr: FaceAttribute) in
                            Picker(attr.displayName, selection: $filters[attr.displayName]) {
                                ForEach(Array(attr.mapping.keys).sorted(), id: \.self) {
                                    Text(attr.mapping[$0]!).tag($0 as Int?)
                                }
                            }.onSubmit {
                                
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "slider.horizontal.3")
                    }
                    Menu {
                        ForEach(visibility.keys.sorted(), id: \.self) {key in
                            Toggle(key, isOn: Binding<Bool>(
                                get: { visibility[key] ?? false },
                                set: { visibility[key] = $0 }
                            ))
                        }
                    }  label: {
                        Label("Select Visible Attributes", systemImage: "eye")
                    }
                }
            }
        }
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 100, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FaceGrid_Previews: PreviewProvider {
    static var previews: some View {
        FaceGrid()
            .environmentObject(ModelData())
    }
}
