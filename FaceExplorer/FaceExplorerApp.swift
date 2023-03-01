import SwiftUI
@main
struct FaceExplorerApp: App {
    init() {
        if UserDefaults.standard.string(forKey: "PhotosLibraryPath") == nil {
            FilePicker()
        }
    }
    @StateObject private var modelData = ModelData()

    var body: some Scene {
        WindowGroup {
            FaceGrid()
            .frame(minWidth: 700, minHeight: 300)
            .environmentObject(modelData)
        }
        Settings {
            FaceSettings()
        }
    }
}
