import SwiftUI

/// A text field that suggests persons (and contacts to create persons from) by name.
///
/// ↑/↓ move through the suggestions, Return picks the highlighted one (or the only/exact match), Esc clears.
struct PersonPicker: View {
    let placeholder: String
    /// Where the suggestions appear relative to the field.
    var suggestionsEdge: VerticalEdge = .bottom
    var isFocused: FocusState<Bool>.Binding
    let onPick: (AssignmentTarget) -> Void

    @Environment(ModelData.self) private var modelData
    @State private var input = ""
    @State private var highlighted: Int?

    private static let maxSuggestions = 8

    private var suggestions: [AssignmentTarget] {
        guard !input.isEmpty else { return [] }
        func matches(_ name: String) -> Bool {
            name.range(of: input, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }
        let persons = modelData.persons.filter { matches($0.name) }.map(AssignmentTarget.person)
        let contacts = modelData.contacts.filter { matches($0.name) }.map(AssignmentTarget.contact)
        return Array((persons + contacts).prefix(Self.maxSuggestions))
    }

    var body: some View {
        let suggestions = isFocused.wrappedValue ? suggestions : []
        TextField(placeholder, text: $input)
            .focused(isFocused)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .onChange(of: input) {
                highlighted = nil
                modelData.loadContactsIfNeeded()
            }
            .onKeyPress(.downArrow) { moveHighlight(by: 1, in: suggestions) }
            .onKeyPress(.upArrow) { moveHighlight(by: -1, in: suggestions) }
            .onKeyPress(.escape) {
                guard !input.isEmpty else { return .ignored }
                input = ""
                return .handled
            }
            .onSubmit {
                if let highlighted, suggestions.indices.contains(highlighted) {
                    pick(suggestions[highlighted])
                } else {
                    // An exact match, or the only suggestion.
                    let exact = suggestions.filter { $0.name.localizedCaseInsensitiveCompare(input) == .orderedSame }
                    if let target = exact.count == 1 ? exact.first : (suggestions.count == 1 ? suggestions.first : nil) {
                        pick(target)
                    }
                }
            }
            .overlay(alignment: suggestionsEdge == .bottom ? .bottom : .top) {
                if !suggestions.isEmpty {
                    suggestionList(suggestions)
                        .alignmentGuide(suggestionsEdge == .bottom ? .bottom : .top) {
                            suggestionsEdge == .bottom ? $0[.top] - 4 : $0[.bottom] + 4
                        }
                }
            }
    }

    private func suggestionList(_ suggestions: [AssignmentTarget]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, target in
                Button {
                    pick(target)
                } label: {
                    HStack {
                        Text(target.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if case .contact = target {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .help("New person from Contacts")
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(index == highlighted ? Color.white : Color.primary)
                    .background(index == highlighted ? Color.accentColor : .clear, in: .rect(cornerRadius: 4))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 200)
        .background(.regularMaterial, in: .rect(cornerRadius: 6))
        .shadow(radius: 3)
    }

    private func moveHighlight(by offset: Int, in suggestions: [AssignmentTarget]) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        let start = highlighted ?? (offset > 0 ? -1 : suggestions.count)
        highlighted = min(max(start + offset, 0), suggestions.count - 1)
        return .handled
    }

    private func pick(_ target: AssignmentTarget) {
        onPick(target)
        input = ""
        isFocused.wrappedValue = false
    }
}
