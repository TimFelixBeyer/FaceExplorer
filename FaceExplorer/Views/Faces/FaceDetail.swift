import SwiftUI

struct FaceDetail: View {
    @EnvironmentObject var modelData: ModelData
    var face: Face

    var faceIndex: Int {
        modelData.landmarks.firstIndex(where: { $0.id == face.id })!
    }
    var body: some View {
        ScrollView {
            
            CircleImage(image: face.image)
                .offset(y: -130)
                .padding(.bottom, -130)

            VStack(alignment: .leading) {
                HStack {
                    Text(face.uuid.uuidString)
                        .font(.title)
                }
                HStack {
                    Text(face.uuid.uuidString)
                    Spacer()
                    Text(face.uuid.uuidString)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                Divider()

                Text("About \(face.uuid.uuidString)")
                    .font(.title2)
                Text(face.uuid.uuidString)
            }
            .padding()
        }
        .navigationTitle(face.uuid.uuidString)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FaceDetail_Previews: PreviewProvider {
    static let modelData = ModelData()

    static var previews: some View {
        FaceDetail(face: modelData.faces[0])
            .environmentObject(modelData)
    }
}
