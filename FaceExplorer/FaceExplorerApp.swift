import SwiftUI
import UniformTypeIdentifiers

@main
struct FaceExplorerApp: App {
    init() {
        if UserDefaults.standard.string(forKey: "PhotosLibraryPath") == nil {
            let openPanel = NSOpenPanel()
            openPanel.prompt = "Select your Photos Library"
            openPanel.canChooseFiles = true
            openPanel.canChooseDirectories = false
            openPanel.allowsMultipleSelection = false
            openPanel.allowedContentTypes = Array([UTType("com.apple.photos.library")!])
            if openPanel.runModal() == .OK {
                if let url = openPanel.url {
                    // Do something with the selected file URL
                    UserDefaults.standard.set(url, forKey: "PhotosLibraryPath")
                }
            }
        }
    }
    @StateObject private var modelData = ModelData()

    var body: some Scene {
        WindowGroup {
            FaceGrid()
            .frame(minWidth: 700, minHeight: 300)
            .environmentObject(modelData)
        }
        #if os(macOS)
        Settings {
            FaceSettings()
        }
        #endif
    }
}