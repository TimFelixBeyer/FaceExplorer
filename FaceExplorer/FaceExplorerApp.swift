import SwiftUI

@main
struct FaceExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var modelData = ModelData()

    var body: some Scene {
        Window("FaceExplorer", id: "main") {
            FaceGrid()
                .frame(minWidth: 700, minHeight: 300)
                .environment(modelData)
        }
        Settings {
            FaceSettings()
                .environment(modelData)
        }
    }
}
