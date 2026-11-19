import SwiftUI

struct FaceCard: View {
    let face: Face
    let visibility: [String: Bool]
    let isSelected: Bool
    /// Number of shown faces in the same person or cluster.
    let clusterSize: Int
    /// Called when the thumbnail is clicked, with the modifier keys held.
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onSelectCluster: () -> Void

    @Environment(ModelData.self) private var modelData
    @Environment(\.undoManager) private var undoManager
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            FaceThumbnail(face: face, libraryURL: modelData.libraryURL)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 4 : 0)
                }
                .contentShape(.rect)
                .onTapGesture { onSelect(NSEvent.modifierFlags) }
                .contextMenu {
                    if face.personID != nil, clusterSize > 1 {
                        Button(face.isNamed ? "Select All \(clusterSize) Shown Faces of \(face.name)" : "Select All \(clusterSize) Shown Faces in This Cluster",
                               action: onSelectCluster)
                    }
                }
            VStack(alignment: .leading) {
                if visibility["Date", default: false] {
                    Text(face.captureDate.formatted(Date.FormatStyle(date: .numeric, time: .shortened, timeZone: face.captureTimeZone)))
                        .font(.body)
                }
                ForEach(modelData.faceAttributes.map(\.displayName).filter { visibility[$0, default: false] }, id: \.self) { name in
                    Text("\(name): \(face.attributes[name]?.label ?? "–")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 150, alignment: .leading)
                if visibility["Name", default: false] {
                    PersonPicker(placeholder: face.isNamed ? face.name : "Assign Name", isFocused: $isFocused) { target in
                        modelData.assign([face], to: target, undoManager: undoManager)
                    }
                    .padding(.top, -5)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .fixedSize()
        // Keep the suggestions above the cards in the next row.
        .zIndex(isFocused ? 1 : 0)
    }
}

struct FaceThumbnail: View {
    let face: Face
    let libraryURL: URL?

    private enum Phase {
        case loading
        case loaded(CGImage)
        case failed
    }
    @State private var phase = Phase.loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                Color.secondary.opacity(0.1)
            case .loaded(let image):
                Image(decorative: image, scale: 2)
            case .failed:
                Image(systemName: "questionmark.circle")
            }
        }
        .frame(width: 150, height: 150)
        .clipShape(.rect(cornerRadius: 5))
        .task(id: face.uuid) {
            guard let libraryURL else {
                phase = .failed
                return
            }
            phase = await FaceThumbnailLoader.thumbnail(for: face, libraryURL: libraryURL).map(Phase.loaded) ?? .failed
        }
    }
}
