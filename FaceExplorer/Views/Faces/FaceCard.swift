import SwiftUI

struct FaceCard: View {
    var face: Face

    @EnvironmentObject var modelData: ModelData
    @State private var candidates: [String] = [""]
    @State private var textFieldInput: String = ""
    @State private var validInput: Bool = false
    @Binding public var visibility: [String: Bool]
    var focusedField: FocusState<UUID?>.Binding

    var names: Set<String> {
        Set(modelData.persons.compactMap({$0.name}))
    }

    var body: some View {
        VStack {
            face.image
                .resizable()
                .interpolation(.low)
                .cornerRadius(5)
                .frame(width: 150, height: 150)
            VStack(alignment: .leading) {
                if visibility["Date"]! {
                    Text("\(face.captureDate.formatted())")
                        .font(.body)
                        .frame(alignment: .leading)
                }
                ForEach(face.attributes.keys.filter({visibility[$0]!}).sorted(), id: \.self) { attr in
                    Text("\(attr): \(face.attributes[attr]!.1)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 150, alignment: .leading)
                if visibility["Name"]! {
                    TextField(face.name, text: $textFieldInput)
                        .focused(focusedField, equals: face.uuid)
                        .onChange(of: $textFieldInput.wrappedValue, perform: { newValue in
                            candidates = names.filter({ $0.starts(with: newValue) }).sorted()
                            validInput = names.contains(newValue)
                        })
                        .onSubmit {
                            updatePerson(personName: textFieldInput, face: face)
                        }
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, -5)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            overlay
                .alignmentGuide(.bottom) {$0[.top]}
                .opacity(focusedField.wrappedValue == face.uuid ? 1.0 : 0.0)
        }
        .padding(.vertical, 10)
        .fixedSize()
    }
    var overlay: some View {
        VStack {
            List(candidates, id: \.self) { candidate in
                Text(candidate).foregroundColor(validInput ? .blue : .red)
            }
        }
    }
}
