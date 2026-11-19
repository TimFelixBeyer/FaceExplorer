import SwiftUI

struct FaceCard: View {
    var face: Face

    @EnvironmentObject private var modelData: ModelData
    @State private var nameQuery = ""
    @Binding public var visibility: [String: Bool]
    var focusedField: FocusState<UUID?>.Binding

    /// Matching names with prefix matches sorted before other matches.
    private var matchingNames: [String] {
        let query = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = Set(modelData.persons.map(\.name))
        guard !query.isEmpty else { return names.sorted() }
        return names.filter { $0.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.localizedCaseInsensitiveHasPrefix(query)
                let rhsPrefix = rhs.localizedCaseInsensitiveHasPrefix(query)
                return lhsPrefix == rhsPrefix ? lhs.localizedStandardCompare(rhs) == .orderedAscending : lhsPrefix
            }
    }

    /// Whether the current query is a new, nonempty name.
    private var canUseTypedName: Bool {
        let query = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && !modelData.persons.contains {
            $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame
        }
    }

    var body: some View {
        VStack {
            face.image
                .interpolation(.low)
                .cornerRadius(5)
                .frame(width: 150, height: 150)
            VStack(alignment: .leading) {
                if visibility["Date"]! {
                    Text("\(face.captureDate.formatted())")
                        .font(.body)
                        .frame(alignment: .leading)
                }
                ForEach(face.attributes.keys.filter({ visibility[$0]! }).sorted(), id: \.self) { attr in
                    Text("\(attr): \(face.attributes[attr]!.1)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 150, alignment: .leading)
                if visibility["Name"]! {
                    TextField(face.name.isEmpty ? "Add a Name" : face.name, text: $nameQuery)
                        .focused(focusedField, equals: face.uuid)
                        .onChange(of: focusedField.wrappedValue) { newValue in
                            if newValue == face.uuid {
                                nameQuery = face.name
                            }
                        }
                        .onSubmit { assign(nameQuery) }
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Name this face")
                        .accessibilityHint("Search existing people or enter a new name")
                        .padding(.top, -5)
                        .overlay(alignment: .topLeading) {
                            if focusedField.wrappedValue == face.uuid {
                                namePicker
                                    .offset(y: 34)
                                    .zIndex(1)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .fixedSize()
        .zIndex(focusedField.wrappedValue == face.uuid ? 1 : 0)
    }

    /// Assigns a name and dismisses the picker.
    /// - Parameter name: Existing or newly entered person name to assign.
    private func assign(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        updatePerson(personName: trimmedName, face: face)
        focusedField.wrappedValue = nil
    }

    /// Renders searchable choices in the card without creating an AppKit window.
    private var namePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            if canUseTypedName {
                Button {
                    assign(nameQuery)
                } label: {
                    Label(
                        "Use ‘\(nameQuery.trimmingCharacters(in: .whitespacesAndNewlines))’",
                        systemImage: "person.badge.plus"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(10)
                Divider()
            }

            List(matchingNames, id: \.self) { name in
                Button {
                    assign(name)
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                        Text(name)
                        Spacer()
                        if name == face.name {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(name == face.name ? .isSelected : [])
            }
            .listStyle(.plain)
            .frame(width: 260, height: min(CGFloat(max(matchingNames.count, 1)) * 34, 240))
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
    }
}

private extension String {
    /// Checks a string prefix without regard to letter case or diacritics.
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}
