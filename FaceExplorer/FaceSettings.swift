import SwiftUI

struct FaceSettings: View {
    @Environment(ModelData.self) private var modelData

    var body: some View {
        Form {
            LabeledContent("Photos Library:") {
                HStack {
                    Text(modelData.libraryURL?.path ?? "None selected")
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(width: 400, alignment: .leading)
                    Button("Select…", action: modelData.selectLibrary)
                }
            }
        }
        .padding(20)
    }
}
