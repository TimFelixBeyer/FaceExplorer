import SwiftUI

struct FaceCard: View {
    var face: Face

    @EnvironmentObject var modelData: ModelData
    @FocusState private var nameFieldIsFocused: Bool
    @State private var candidates: [String] = [""]
    @State private var textFieldInput: String = ""
    @State private var validInput: Bool = false
    @Binding public var visibility: [String: Bool]

    var names: Set<String> {
        Set(modelData.persons.compactMap({$0.name}))
    }

    var body: some View {
        VStack {
            face.image
                .resizable()
                .interpolation(.low)
                .frame(width: 150, height: 150)
                .cornerRadius(5)
            VStack(alignment: .leading) {
                if visibility["Date"]! {
                    Text("\(face.captureDate.formatted())")
                        .font(.body)
                }
                ForEach(Array(face.attributes.keys).sorted(), id: \.self) { attr in
                    if visibility[attr]! {
                        Text("\(attr): \(face.attributes[attr]!.1)")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
                TextField(face.name ?? "Max Mustermann", text: $textFieldInput)
                    .focused($nameFieldIsFocused)
                    .onChange(of: $textFieldInput.wrappedValue, perform: { newValue in
                        candidates = names.filter({ $0.starts(with: newValue)}).sorted()
                        validInput = names.contains(newValue)
                    })
                    .onSubmit {
                        updatePerson(personName: textFieldInput, face: face)
                    }
                    .disableAutocorrection(true)
                    .border(.secondary)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .overlay(alignment: .bottom) {
            overlay
                .alignmentGuide(.bottom) {$0[.top]}
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
