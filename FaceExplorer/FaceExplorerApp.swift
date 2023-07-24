import SwiftUI
import AppKit

@main
struct FaceExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var modelData = ModelData()

    init() {
        if UserDefaults.standard.string(forKey: "PhotosLibraryPath") == nil {
            modelData.selectLibrary()
        }
    }

    var body: some Scene {
        WindowGroup {
            FaceGrid()
            .frame(minWidth: 700, minHeight: 300)
            .environmentObject(modelData)
        }
        Settings {
            FaceSettings()
                .environmentObject(modelData)
        }
    }
}
