import SwiftUI
import AppKit

@main
struct FaceExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var modelData = ModelData()

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
