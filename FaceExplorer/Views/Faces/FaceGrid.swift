import SwiftUI

struct FaceGrid: View {
    @EnvironmentObject var modelData: ModelData
    @State private var photoAPI = PhotoLibraryAPI()
    @State private var filterNamed = FilterCategory.all
    @State private var filters = getFaceAttributes().reduce(into: [String: Int]()) { $0[$1.displayName] = -1 }
    @State private var sortBy: String = "Date"
    @State private var selectedFace: Face?
    @FocusState private var focusedField: UUID?
    @State private var makeAlbumInProgress = false;
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

    // this is being computed unneacesarily on each use which we may want to only do on change in the future, but
    // these machines chew through 10,000 items like it's nothing
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

    
    /// For the current filter set of Faces, return a list of all unique localIdentifiers for the images those faces are in
    /// - Returns: Array of photo localIdentifiers
    func localIdentifiers() -> [String] {

        var localIdentifiersUniqued: Dictionary<String, String> = [:]
        var localIdentifiers: Array<String> = []

        // Get a list of unique photo IDs for all the faces
        filteredFaces.forEach {
            if localIdentifiersUniqued[$0.photoUUID.uuidString] == nil {
                localIdentifiers.append($0.photoUUID.uuidString)
                localIdentifiersUniqued[$0.photoUUID.uuidString] = $0.photoUUID.uuidString
            }
        }
                
        return localIdentifiers
    }

    /// For the current filter set of Faces, return a list of all unique localIdentifiers for the images those faces are in ordered by least number of faces to most
    /// - Returns: Array of photo localIdentifiers
    func localIdentifiersOrderedByCountOfFaces() -> [String] {
        // Make a dict of all unique photoIds mapped to count of faces in each photo
        var allPicturesWithCountOfFaces : Dictionary<String, Int> = [:]
        modelData.faces.forEach {
            allPicturesWithCountOfFaces[($0.photoUUID).uuidString, default:0] += 1
        }

        // Copy the counts of the faces for only the photos in our current filter
        var localIdentifiersWithCountOfFaces: Dictionary<String, Int> = [:]
        filteredFaces.forEach {
            localIdentifiersWithCountOfFaces[$0.photoUUID.uuidString] = allPicturesWithCountOfFaces[$0.photoUUID.uuidString]
        }
                
        // Sort the pictures by the count of faces
        let sortedLocalIdentifersWithCountOfFaces =  localIdentifiersWithCountOfFaces.sorted(by:  { $0.value < $1.value })
        let sortedLocalIdentifers: [String] = sortedLocalIdentifersWithCountOfFaces.map({ $0.key })
        
        return sortedLocalIdentifers
    }

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
                ToolbarItem(placement: .navigation) {
                    Button(action: modelData.selectLibrary) {
                        Image(systemName: "arrow.left.arrow.right.circle")
                        Text("Change Library...")
                    }
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: modelData.loadLibrary) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload Faces")
                }
                // Button to make an album in Photos of the current view, changing the button image to indicate progress
                ToolbarItem(placement: .navigation) {
                    Button (action:{
                        makeAlbumInProgress = true;
                        
                        Task {
                            // Because the current order of the FaceGrid has limited value and given that you can sort
                            // by date/title in the Photos app, we will order them by the number of faces each image.
                            //
                            // Photos is horrible at allowing you to quickly tab through and name multiple unamed faces,
                            // (you have to tab 3 times, name a face, and then the selction resets and you have to tab
                            // 3 imes again and then tab through the faces to the next face you want to name)
                            // so i am hoping that in the case of unnamed faces being able to name a few indvidual
                            // faces quickly, and then allowing the image recognition to match those to unamed faces
                            // will lessen the ordeal of naming faces on images with lots of faces
                            //
                            // For proper UI, we should probably allow user to choose an album name, choose between the two sort orders,
                            // and show an indeterminate progress indicator.
                            //
                            // uncomment to preserve current sort order
                            // let sortedLocalIdentifers = self.localIdentifiers

                            // Sort the images to include in the album by the number of faces each one has
                            let sortedLocalIdentifers = localIdentifiersOrderedByCountOfFaces()
                            await photoAPI.createAlbum(name: "FaceExplorer " + self.filterNamed.rawValue, withLocalIdentiers: sortedLocalIdentifers)
                            
                            makeAlbumInProgress = false;
                        }
                    },
                    label: {
                        Label("Make Album", systemImage:makeAlbumInProgress ? "hammer.circle" : "rectangle.stack.badge.plus" )
                    })
                    .disabled(makeAlbumInProgress)
                    .help("Make \"" + self.filterNamed.rawValue + "\" Album in Photos")
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
                modelData.sortBy(displayName: sortBy)
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
