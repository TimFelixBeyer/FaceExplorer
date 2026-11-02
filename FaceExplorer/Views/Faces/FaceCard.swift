import SwiftUI

struct FaceCard: View {
    let face: Face
    let visibility: [String: Bool]

    @Environment(ModelData.self) private var modelData
    @State private var candidates: [String] = []
    @State private var nameInput = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            FaceThumbnail(face: face, libraryURL: modelData.libraryURL)
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
                    TextField(face.name, text: $nameInput)
                        .focused($isFocused)
                        .onChange(of: nameInput) {
                            candidates = modelData.personNames.filter { $0.hasPrefix(nameInput) }
                        }
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, -5)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            if isFocused && !candidates.isEmpty {
                VStack(alignment: .leading) {
                    ForEach(candidates.prefix(8), id: \.self) { candidate in
                        Text(candidate).foregroundStyle(candidate == nameInput ? .blue : .red)
                    }
                }
                .alignmentGuide(.bottom) { $0[.top] }
            }
        }
        .padding(.vertical, 10)
        .fixedSize()
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
