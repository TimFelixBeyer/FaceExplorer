import SwiftUI

struct FaceCard: View {
    let face: Face
    let visibility: [String: Bool]

    @Environment(ModelData.self) private var modelData
    /// Persons whose name starts with the input, shown as suggestions.
    @State private var candidates: [Person] = []
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
                    TextField(face.isNamed ? face.name : "Assign Name", text: $nameInput)
                        .focused($isFocused)
                        .onChange(of: nameInput) {
                            candidates = nameInput.isEmpty ? [] : modelData.persons.filter {
                                $0.name.range(of: nameInput, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                            }
                        }
                        .onSubmit {
                            // Accept an exact match, or the only suggestion.
                            let exactMatches = candidates.filter { $0.name.localizedCaseInsensitiveCompare(nameInput) == .orderedSame }
                            if let person = exactMatches.count == 1 ? exactMatches.first : (candidates.count == 1 ? candidates.first : nil) {
                                assign(person)
                            }
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
                suggestions
                    .alignmentGuide(.bottom) { $0[.top] }
            }
        }
        .padding(.vertical, 10)
        .fixedSize()
        // Keep the suggestions above the cards in the next row.
        .zIndex(isFocused ? 1 : 0)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(candidates.prefix(8)) { person in
                Button(person.name) { assign(person) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            if candidates.count > 8 {
                Text("\(candidates.count - 8) more…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(width: 170)
        .background(.regularMaterial, in: .rect(cornerRadius: 6))
        .shadow(radius: 3)
    }

    private func assign(_ person: Person) {
        modelData.assign(face, to: person)
        nameInput = ""
        isFocused = false
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
