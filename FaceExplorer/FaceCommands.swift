import SwiftUI

struct FaceCommands: Commands {
    @FocusedBinding(\.selectedFace) var selectedFace

    var body: some Commands {
        SidebarCommands()

        CommandMenu("Face") {
            Button("\(selectedFace?.category == .untagged ? "Remove" : "Mark") as Favorite") {
                print("Clicked")
            }
            .keyboardShortcut("f", modifiers: [.shift, .option])
            .disabled(selectedFace == nil)
        }
    }
}

private struct SelectedFaceKey: FocusedValueKey {
    typealias Value = Binding<Face>
}

extension FocusedValues {
    var selectedFace: Binding<Face>? {
        get { self[SelectedFaceKey.self] }
        set { self[SelectedFaceKey.self] = newValue }
    }
}
