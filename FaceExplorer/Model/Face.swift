import Foundation
import SwiftUI

struct Face: Identifiable, Hashable {
    static func == (lhs: Face, rhs: Face) -> Bool {
        return lhs.uuid == rhs.uuid
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
        hasher.combine(photoUUID)
    }

    var id: Int
    var uuid: UUID
    var photoPk: Int?
    var photoUUID: UUID

    private var centerx: Double
    private var centery: Double
    private var size: Double
    var name: String?

    var category: Category
    enum Category: String, CaseIterable, Codable {
        case unnamed = "Unnamed"
        case named = "Named"
    }
    var captureDate: Date
    var attributes: [String: (Int, String)] = [:]

    public init(id: Int,
                uuid: UUID,
                photoPk: Int?,
                photoUUID: UUID,
                centerx: Double,
                centery: Double,
                size: Double,
                name: String?,
                captureDate: Date,
                attributes: [String: (Int, String)]) {
        self.id = id
        self.uuid = uuid
        self.photoUUID = photoUUID
        self.photoPk = photoPk
        self.centerx = centerx
        self.centery = centery
        self.size = size
        self.name = name
        self.category = (name == "") ? Category.unnamed : Category.named
        self.captureDate = captureDate
        self.attributes = attributes
    }

    var image: Image {
        let photoLibraryPath = UserDefaults.standard.string(forKey: "PhotosLibraryPath")!
        let UUIDPrefix = photoUUID.uuidString.prefix(1)
        let picPath = "\(photoLibraryPath)/resources/derivatives/\(UUIDPrefix)/\(photoUUID.uuidString)_1_105_c.jpeg"
        let image = NSImage(contentsOf: URL(fileURLWithPath: picPath))

        if image == nil {
            return Image(systemName: "questionmark.circle")
        }
        // crop into face
        let width = Double(image!.size.width)
        let height = Double(image!.size.height)
        let contextFactor = 2.5
        let radius = size * max(width, height) * contextFactor
        let boundsRect = CGRect(x: centerx * width - radius / 2,
                                y: centery * height - radius / 2,
                                width: radius,
                                height: radius)
        let img = Image(trimFast(image: image!, rect: boundsRect), scale: 1.0, label: Text(""))
//        let img = Image(nsImage: trim(image: image!, rect: boundsRect))
        return img
    }
}
func trim(image: NSImage, rect: CGRect) -> NSImage {
    let result = NSImage(size: rect.size)
    result.lockFocus()
    let destRect = CGRect(origin: .zero, size: rect.size)
    image.draw(in: destRect, from: rect, operation: .copy, fraction: 1.0)
    result.unlockFocus()
    return result
}

func trimFast(image: NSImage, rect: CGRect) -> CGImage {
    // TODO: Fix crops that go over image bounds
    let cutRect = CGRect(
        x: rect.origin.x,
        y: image.size.height - rect.height - rect.origin.y,
        width: rect.width,
        height: rect.height
    )

    let cutImageRef = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
//    print(cutRect.origin.x, cutRect.origin.x + cutRect.width,
//          cutRect.origin.y, cutRect.origin.y + cutRect.height, image.size)
    let result = cutImageRef.cropping(to: cutRect)!
    return result
}
