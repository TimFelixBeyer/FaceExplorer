import SwiftUI

struct FaceGrid: View {
    @Environment(ModelData.self) private var modelData
    @State private var tagFilter = TagFilterCategory.all
    /// Selected raw value per attribute; attributes without an entry aren't filtered.
    @State private var attributeFilters: [String: Int] = [:]
    @State private var visibility: [String: Bool] = ["Age": true, "Date": true, "Name": true]

    private let layout = [GridItem(.adaptive(minimum: 170, maximum: 250))]

    private func isShown(_ face: Face) -> Bool {
        let matchesTag = switch tagFilter {
        case .all: true
        case .named: face.isNamed
        case .unnamed: !face.isNamed
        }
        return matchesTag && attributeFilters.allSatisfy { name, value in face.attributes[name]?.raw == value }
    }

    var body: some View {
        let faces = modelData.faces.filter(isShown)
        ScrollView {
            VStack {
                Group {
                    if modelData.isLoading {
                        ProgressView("Loading faces…")
                    } else {
                        Text("Showing \(faces.count) faces")
                    }
                }
                .padding(.top, 20)
                .foregroundStyle(.secondary)
                LazyVGrid(columns: layout, spacing: 10) {
                    ForEach(faces) { face in
                        FaceCard(face: face, visibility: visibility)
                    }
                }
                .padding([.horizontal, .bottom], 20)
            }
        }
        .toolbar {
            Toolbar(
                filteredFaces: faces,
                tagFilter: $tagFilter,
                attributeFilters: $attributeFilters,
                visibility: $visibility
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            modelData.errorMessage ?? "",
            isPresented: Binding(
                get: { modelData.errorMessage != nil },
                set: { if !$0 { modelData.errorMessage = nil } }
            )
        ) {
            Button("Select Library…", action: modelData.selectLibrary)
            Button("Close", role: .cancel) {}
        }
        .task {
            if modelData.libraryURL == nil {
                modelData.selectLibrary()
            }
        }
    }
}
