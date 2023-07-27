import SwiftUI

struct FaceGrid: View {
    @EnvironmentObject var modelData: ModelData
    @State private var filterNamed = FilterCategory.all
    @State private var filters = getFaceAttributes().reduce(into: [String: Int]()) { $0[$1.displayName] = -1 }
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

    private var filteredFaces: [Face] {
        modelData.faces.filter { face in
            (filterNamed == .all || filterNamed.rawValue == face.category.rawValue)
            && filters.allSatisfy({(key: String, value: Int) in
                (value == -1 || value == face.attributes[key]!.0)
            })
        }
    }

    private var title: String {
        let title = filterNamed == .all ? "Faces" : filterNamed.rawValue
        return title
    }

    private var index: Int? {
        modelData.faces.firstIndex(where: { $0.id == selectedFace?.id })
    }

    private var layout = [GridItem(.adaptive(minimum: 170, maximum: 250))]

    var body: some View {
        ScrollView {
            VStack() {
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
                ToolbarItem(placement: .navigation) {
                    Button(action: { modelData.selectLibrary() }) {
                        Image(systemName: "arrow.left.arrow.right.circle")
                        Text("Change Library...")
                    }
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: { modelData.loadLibrary() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload Faces")
                }
                
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Category", selection: $filterNamed) {
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
        .onChange(of: sortBy, perform: { _ in
            if sortBy == "Date" {
                modelData.sortByDate()
            } else if sortBy == "Name" {
                modelData.sortByName()
            } else {
                modelData.sortBy(attributeName: sortBy)
            }
        })
        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 100, maxHeight: .infinity, alignment: .topLeading)
        .alert(isPresented: $modelData.errorOccurred) {
            Alert(title: Text("Error"),
                  message: Text(modelData.errorMessage!),
                  primaryButton: .default(Text("Select Library..."), action: {
                    // Handle Select button tap
                modelData.selectLibrary()
                    }),
                  secondaryButton: .default(Text("Close")))
        }
    }
}

struct FaceGrid_Previews: PreviewProvider {
    static var previews: some View {
        FaceGrid()
            .environmentObject(ModelData())
    }
}
