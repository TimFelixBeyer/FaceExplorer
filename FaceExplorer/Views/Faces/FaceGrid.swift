import SwiftUI

struct FaceGrid: View {
    @Environment(ModelData.self) private var modelData
    @State private var tagFilter = TagFilterCategory.all
    /// Selected raw value per attribute; attributes without an entry aren't filtered.
    @State private var attributeFilters: [String: Int] = [:]
    @State private var visibility: [String: Bool] = ["Age": true, "Date": true, "Name": true]
    @State private var selection: Set<Face.ID> = []
    /// The face a Shift-click extends the selection from.
    @State private var selectionAnchor: Face.ID?
    @FocusState private var isBulkPickerFocused: Bool
    @Environment(\.undoManager) private var undoManager

    private let layout = [GridItem(.adaptive(minimum: 170, maximum: 250))]

    private func isShown(_ face: Face) -> Bool {
        let matchesTag = switch tagFilter {
        case .all: true
        case .named: face.isNamed
        case .unnamed: !face.isNamed
        }
        return matchesTag && attributeFilters.allSatisfy { name, value in face.attributes[name]?.raw == value }
    }

    /// Selects like Finder: click selects one face, ⌘-click toggles, ⇧-click extends.
    private func select(_ face: Face, modifiers: NSEvent.ModifierFlags, in faces: [Face]) {
        if modifiers.contains(.shift), let selectionAnchor,
           let from = faces.firstIndex(where: { $0.id == selectionAnchor }),
           let to = faces.firstIndex(where: { $0.id == face.id }) {
            selection.formUnion(faces[min(from, to)...max(from, to)].map(\.id))
            return
        }
        if modifiers.contains(.command) {
            if selection.remove(face.id) == nil {
                selection.insert(face.id)
            }
        } else {
            selection = selection == [face.id] ? [] : [face.id]
        }
        selectionAnchor = face.id
    }

    var body: some View {
        let faces = modelData.faces.filter(isShown)
        let clusterSizes = Dictionary(grouping: faces.compactMap(\.personID), by: { $0 }).mapValues(\.count)
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
                        FaceCard(
                            face: face,
                            visibility: visibility,
                            isSelected: selection.contains(face.id),
                            clusterSize: face.personID.flatMap { clusterSizes[$0] } ?? 1,
                            onSelect: { select(face, modifiers: $0, in: faces) },
                            onSelectCluster: {
                                selection = Set(faces.filter { $0.personID == face.personID }.map(\.id))
                                selectionAnchor = face.id
                            }
                        )
                    }
                }
                .padding([.horizontal, .bottom], 20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty {
                selectionBar(faces: faces)
            }
        }
        .onChange(of: modelData.faces.map(\.id)) {
            // Drop selected faces that no longer exist, e.g. after switching libraries.
            selection.formIntersection(modelData.faces.map(\.id))
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
        .alert(
            "Write to the Photos Library?",
            isPresented: Binding(
                get: { modelData.pendingAssignment != nil },
                set: { if !$0 { modelData.pendingAssignment = nil } }
            ),
            presenting: modelData.pendingAssignment
        ) { assignment in
            Button(assignment.faces.count == 1
                   ? "Assign to \(assignment.target.name)"
                   : "Assign \(assignment.faces.count) Faces to \(assignment.target.name)",
                   action: modelData.confirmPendingAssignment)
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("""
                Names are assigned by writing directly to the library's database, which Photos does not officially support. \
                Before the first change, a backup of the database is saved in the library's "FaceExplorer Backups" folder. \
                Changes are not synced to iCloud Photos.
                """)
        }
        .sheet(isPresented: Binding(get: { modelData.writeActivity != nil }, set: { _ in })) {
            WriteProgressView(activity: modelData.writeActivity)
        }
        .task {
            if modelData.libraryURL == nil {
                modelData.selectLibrary()
            }
        }
    }
}

extension FaceGrid {
    private func selectionBar(faces: [Face]) -> some View {
        let selected = faces.filter { selection.contains($0.id) }
        return HStack(spacing: 12) {
            Text(selected.count == selection.count
                 ? "\(selection.count) selected"
                 : "\(selected.count) of \(selection.count) selected faces shown")
                .monospacedDigit()
            PersonPicker(
                placeholder: "Assign \(selected.count) faces to…",
                suggestionsEdge: .top,
                isFocused: $isBulkPickerFocused
            ) { target in
                modelData.assign(selected, to: target, undoManager: undoManager)
                selection = []
            }
            .frame(width: 220)
            .disabled(selected.isEmpty)
            Spacer()
            Button("Select All Shown") {
                selection = Set(faces.map(\.id))
            }
            Button("Deselect") {
                selection = []
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Blocks the window while a backup or name assignment is being written.
private struct WriteProgressView: View {
    let activity: ModelData.WriteActivity?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .backingUp(let fraction) = activity {
                ProgressView(value: fraction) {
                    Text("Backing up the Photos library…")
                        .font(.headline)
                } currentValueLabel: {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                }
                Text("Before the first change of a session, FaceExplorer saves a copy of the library database. For large libraries on external drives this can take a few minutes. Please don't quit FaceExplorer or open Photos in the meantime.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView("Saving name…")
            }
        }
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled()
    }
}
