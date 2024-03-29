import SwiftUI

struct FaceSettings: View {
    @EnvironmentObject var modelData: ModelData
    @AppStorage("PhotosLibraryPath") var photosLibraryPath: String?

    var body: some View {
        Form {
            HStack {
                Text("Photos Library Path: ")
                    .frame(width: 130)
                TextField("", text: Binding<String>(
                    get: { photosLibraryPath ?? "" },
                    set: { photosLibraryPath = $0 }
                ))
                .frame(width: 400)
                Button(action: modelData.selectLibrary) {
                    Text("Select...")
                }
            }
        }
        .padding(20)
        .frame(idealWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FaceSettings_Previews: PreviewProvider {
    static var previews: some View {
        FaceSettings()
    }
}
