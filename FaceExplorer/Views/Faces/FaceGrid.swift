import SwiftUI

struct FaceGrid: View {
    @EnvironmentObject var modelData: ModelData
    @State private var filterTagged = FilterCategory.all
    @State private var filterAttributes: [String: any Constructible] = {
        var x: [String: any Constructible] = [:]
        for attr in ModelData().faceAttributes {
            x[attr.displayName] = attr.dataType.init(intValue: -1)
        }
        return x
    }()
    @State private var selectedFace: Face?
    @State private var visibility: [String: Bool] = [
        "Age": true,
        "Date": true,
        "Name": false,
//        "Gender": true,
//        "Expression": true,
//        "Skintone": false
    ]

    enum FilterCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case untagged = "Untagged"
        case tagged = "Tagged"
        var id: FilterCategory { self }
    }

    var filteredFaces: [Face] {
        modelData.faces.filter { face in
            (filterTagged == .all || filterTagged.rawValue == face.category.rawValue)
            && filterAttributes.allSatisfy({(key: String, value: any Constructible) -> Bool in
                return (value.rawValue == "All") || value.rawValue == face.attributes[key]?.rawValue
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
    
    func binding<Value: Equatable>(_ key: String, _ value: Value.Type) -> Binding<Value> {
        Binding<Value>(
            get: { filterAttributes[key] as! Value },
            set: { filterAttributes[key] = $0 as? any Constructible }
            )
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
                        let x = print(type(of: modelData.faceAttributes[0].dataType))
                        let y = print(modelData.faceAttributes[0].dataType.allCases)
                        ForEach(modelData.faceAttributes, id: \.self) { attr in
                            Picker(attr.displayName, selection: $filterAttributes[attr.displayName]) {
                                Text("A")
                            }
                        }
                        
                        //                            ForEach(Array(filterAttributes["Age"]!.allCases), id:\.self) { (category: Constructible) in
                        //                                Text(category.rawValue).tag(category)
                        //                            }
                        //                        }
//                        ForEach(filterAttributes.keys.sorted(), id: \.self) {key in
//                            Picker(key, selection: binding(key, type(of: filterAttributes[key]))) {
//                                ForEach(filterAttributes[key]!.allCases) { (category: Constructible) in
//                                    Text(category.rawValue).tag(category)
//                                }
//                            }
//                            .pickerStyle(.inline)
//                        }
//                        Picker("Age", selection: binding(for: "Age")) {
//                            ForEach(Array(filterAttributes["Age"]!.allCases), id:\.self) { (category: Constructible) in
//                                Text(category.rawValue).tag(category)
//                            }
//                        }
//                        Picker("Expression", selection: $filterExpression) {
//                            ForEach(ExpressionType.allCases) { category in
//                                Text(category.rawValue).tag(category)
//                            }
//                        }
//                        .pickerStyle(.inline)
//                        Picker("Gender", selection: $filterGender) {
//                            ForEach(GenderType.allCases) { category in
//                                Text(category.rawValue).tag(category)
//                            }
//                        }
//                        .pickerStyle(.inline)
//                        Picker("Skintone", selection: $filterSkintone) {
//                            ForEach(SkintoneType.allCases) { category in
//                                Text(category.rawValue).tag(category)
//                            }
//                        }
//                        .pickerStyle(.inline)
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
