import SwiftUI

struct FaceList: View {
    @EnvironmentObject var modelData: ModelData
    @State private var filterTagged = FilterCategory.all
    @State private var filterGender = ModelData.GenderType.all
    @State private var filterExpression = ModelData.ExpressionType.all
    @State private var filterSkintone = ModelData.SkintoneType.all


    @State private var selectedFace: Face?
    @State private var visibility: [String: Bool] = [
        "Age": false,
        "Date": true,
        "Gender": true,
        "Expression": true,
        "Name": false,
        "Skintone": false,        
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
            && (filterGender == .all || filterGender.rawValue == face.genderType!.rawValue)
            && (filterExpression == .all || filterExpression.rawValue == face.expressionType!.rawValue)
            && (filterSkintone == .all || filterSkintone.rawValue == face.skintoneType!.rawValue)
        }
    }

    var title: String {
        let title = filterTagged == .all ? "Faces" : filterTagged.rawValue
        return title
    }

    var index: Int? {
        modelData.faces.firstIndex(where: { $0.id == selectedFace?.id })
    }

    var layout = [GridItem(.adaptive(minimum: 170, maximum: 250)),]
    var body: some View {
        HStack {
            ScrollView {
                LazyVGrid(columns: layout, spacing: 10) {
                    ForEach(filteredFaces) { face in
                        FaceRow(face: face,
                                visibility: $visibility
                        )
                    }
                }
                .padding(20)
                .frame(minWidth: 300)
                .toolbar {
                    ToolbarItemGroup {
                        Menu {
                            Picker("Category", selection: $filterTagged) {
                                ForEach(FilterCategory.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.inline)
                            Picker("Expression", selection: $filterExpression) {
                                ForEach(ModelData.ExpressionType.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.inline)
                            Picker("Gender", selection: $filterGender) {
                                ForEach(ModelData.GenderType.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.inline)
                            Picker("Skintone", selection: $filterSkintone) {
                                ForEach(ModelData.SkintoneType.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label("Filter", systemImage: "slider.horizontal.3")
                        }
                        
                        Menu {
                            ForEach(visibility.keys.sorted(), id: \.self) {key in
                                Toggle(key, isOn:  Binding<Bool>(
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
}

struct FaceList_Previews: PreviewProvider {
    static var previews: some View {
        FaceList()
            .environmentObject(ModelData())
    }
}
