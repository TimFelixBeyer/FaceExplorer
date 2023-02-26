import SwiftUI

struct FaceRow: View {
    @EnvironmentObject var modelData: ModelData

    var face: Face
    var names: Set<String> {
        Set(modelData.persons.compactMap( { $0.name }))
    }
    
    @FocusState private var emailFieldIsFocused: Bool
    @State private var candidates: [String] = [""]
    @State private var textFieldInput: String = ""
    @State private var validInput: Bool = false

    @Binding public var visibility: [String:Bool]
    
    var body: some View {
        VStack() {
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
                if visibility["Age"]! {
                    Text("Age group: \(face.ageType!.rawValue)")
                        .font(.callout).foregroundColor(.secondary)
                }
                if visibility["Expression"]! {
                    Text("Expression: \(face.expressionType!.rawValue)")
                        .font(.callout).foregroundColor(.secondary)
                }
                if visibility["Gender"]! {
                    Text("Gender: \(face.genderType!.rawValue)")
                        .font(.callout).foregroundColor(.secondary)
                }
                if visibility["Skintone"]! {
                    Text("Skintone: \(face.skintoneType!.rawValue)")
                        .font(.callout).foregroundColor(.secondary)
                }
                TextField("Max Mustermann", text: $textFieldInput)
                    .focused($emailFieldIsFocused)
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
    }
    
    var overlay: some View {
        VStack {
            List(candidates, id: \.self) { candidate in
                Text(candidate).foregroundColor(validInput ? .blue : .red)
            }
        }
    }
}
