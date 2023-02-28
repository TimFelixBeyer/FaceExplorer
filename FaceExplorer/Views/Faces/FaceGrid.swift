import SwiftUI

struct FaceGrid: View {
    @EnvironmentObject var modelData: ModelData
    @State private var filterTagged = FilterCategory.all
    @State private var filterAge = AgeType.all
    @State private var filterEthnicity = EthnicityType.all
    @State private var filterExpression = ExpressionType.all
    @State private var filterEyeState = EyeStateType.all
    @State private var filterGender = GenderType.all
    @State private var filterFacialHair = FacialHairType.all
    @State private var filterSkintone = SkintoneType.all
    
    @State private var selectedFace: Face?
    @State private var visibility: [String: Bool] = [
        "Age": true,
        "Date": true,
        "Ethnicity": true,
        "Expression": true,
        "Eye State": true,
        "Gender": true,
        "Facial Hair": true,
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
            && (filterAge == .all || filterAge.rawValue == face.attributes["Age"]?.rawValue)
            && (filterEthnicity == .all || filterEthnicity.rawValue == face.attributes["Ethnicity"]?.rawValue)
            && (filterExpression == .all || filterExpression.rawValue == face.attributes["Expression"]?.rawValue)
            && (filterEyeState == .all || filterEyeState.rawValue == face.attributes["Eye State"]?.rawValue)
            && (filterGender == .all || filterGender.rawValue == face.attributes["Gender"]?.rawValue)
            && (filterFacialHair == .all || filterFacialHair.rawValue == face.attributes["Facial Hair"]?.rawValue)
            && (filterSkintone == .all || filterSkintone.rawValue == face.attributes["Skintone"]?.rawValue)
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
                        Picker("Age", selection: $filterAge) {
                            ForEach(AgeType.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        Picker("Ethnicity", selection: $filterEthnicity) {
                            ForEach(EthnicityType.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        Picker("Expression", selection: $filterExpression) {
                            ForEach(ExpressionType.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        Picker("Eye State", selection: $filterEyeState) {
                            ForEach(EyeStateType.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.inline)
                        Picker("Gender", selection: $filterGender) {
                            ForEach(GenderType.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        Picker("Facial Hair", selection: $filterFacialHair) {
                            ForEach(FacialHairType.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        Picker("Skintone", selection: $filterSkintone) {
                            ForEach(SkintoneType.allCases) { category in
                                Text(category.rawValue).tag(category)
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
