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

    private var centerX: Double
    private var centerY: Double
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
                centerX: Double,
                centerY: Double,
                size: Double,
                name: String?,
                captureDate: Date,
                attributes: [String: (Int, String)]) {
        self.id = id
        self.uuid = uuid
        self.photoUUID = photoUUID
        self.photoPk = photoPk
        self.centerX = centerX
        self.centerY = centerY
        self.size = size
        self.name = name
        self.category = (name == "") ? Category.unnamed : Category.named
        self.captureDate = captureDate
        self.attributes = attributes
    }

    var image: Image {
        guard let photoLibraryPath = UserDefaults.standard.string(forKey: "PhotosLibraryPath") else {
            return Image(systemName: "questionmark.circle")
        }

        let UUIDPrefix = photoUUID.uuidString.prefix(1)
        let rootPath = "\(photoLibraryPath)/resources/derivatives/"
        let picPathCandidates = ["\(rootPath)\(UUIDPrefix)/\(photoUUID.uuidString)_1_105_c.jpeg",
                        "\(rootPath)\(UUIDPrefix)/\(photoUUID.uuidString)_1_101_o.jpeg",
                        "\(rootPath)masters/\(UUIDPrefix)/\(photoUUID.uuidString)_4_5005_c.jpeg"]
        guard let validImage = ImageLoader.loadImage(fromPaths: picPathCandidates) else {
            return Image(systemName: "questionmark.circle")
        }

        guard let croppedImage = ImageLoader.cropImage(validImage,
                                                       centerX: centerX,
                                                       centerY: centerY,
                                                       size: size)
        else {
            // Return the original image if cropping failed
            return Image(nsImage: validImage)
        }

        return Image(nsImage: croppedImage)
    }
}

class ImageLoader {
    static func loadImage(fromPaths paths: [String]) -> NSImage? {
        for path in paths {
            if let image = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                return image
            }
        }
        return nil
    }

    static func cropImage(_ image: NSImage, centerX: Double, centerY: Double, size: Double) -> NSImage? {
        let width = Double(image.size.width)
        let height = Double(image.size.height)
        let contextFactor = 2.5
        let radius = size * max(width, height) * contextFactor
        let boundsRect = CGRect(x: centerX * width - radius / 2,
                                y: centerY * height - radius / 2,
                                width: radius,
                                height: radius)

        let trimmedImage = trim(image: image, rect: boundsRect)
        return trimmedImage
    }
}

func trim(image: NSImage, rect: CGRect) -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return NSImage() // return an empty image or handle this error case appropriately.
    }

    let transformedRect = CGRect(
        x: rect.origin.x,
        y: CGFloat(cgImage.height) - rect.origin.y - rect.size.height,
        width: rect.width, height:
        rect.height
    )
    let xOutOfBounds = transformedRect.minX < 0 || transformedRect.maxX > CGFloat(cgImage.width)
    let yOutOfBounds = transformedRect.minY < 0 || transformedRect.maxY > CGFloat(cgImage.height)
    if xOutOfBounds || yOutOfBounds {
        return trimSlow(image: image, rect: rect)
    }
    guard let croppedImage = cgImage.cropping(to: transformedRect) else {
        return NSImage() // return an empty image or handle this error case appropriately.
    }

    // Convert back to NSImage
    let trimmedImage = NSImage(cgImage: croppedImage, size: .zero)
    return trimmedImage
}

func trimSlow(image: NSImage, rect: CGRect) -> NSImage {
    // we use this function for faces that go outside the bounds of the image
    // it is slower but returns correct results even for those cases.
    let result = NSImage(size: rect.size)
    result.lockFocus()
    let destRect = CGRect(origin: .zero, size: rect.size)
    image.draw(in: destRect, from: rect, operation: .copy, fraction: 1.0)
    result.unlockFocus()
    return result
}
