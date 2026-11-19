import Foundation
import CoreGraphics
import ImageIO

struct Face: Identifiable, Hashable, Sendable {
    /// `Z_PK` of the face in `ZDETECTEDFACE`.
    let id: Int
    let uuid: UUID
    let photoUUID: UUID
    /// Face position and size relative to the photo, origin at the bottom left.
    let centerX: Double
    let centerY: Double
    let size: Double
    /// The person (or unnamed cluster of similar faces) Photos assigned the face to, with merges resolved.
    var personID: Int?
    var name: String
    let captureDate: Date
    /// The time zone the photo was taken in.
    let captureTimeZone: TimeZone
    /// Predicted attributes, keyed by `FaceAttribute.displayName`.
    let attributes: [String: AttributeValue]

    struct AttributeValue: Hashable, Sendable {
        let raw: Int
        let label: String
    }

    var isNamed: Bool { !name.isEmpty }
}

/// Loads and caches cropped face thumbnails from the derivatives Photos keeps inside the library.
enum FaceThumbnailLoader {
    /// Side length of the thumbnails in pixels (150pt at 2x).
    static let pixelSize = 300
    /// How much of the surroundings to include around the detected face.
    private static let contextFactor = 2.5

    /// Keyed by face UUID, which is unique across libraries. NSCache is thread-safe.
    nonisolated(unsafe) private static let cache = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 2000
        return cache
    }()

    static func thumbnail(for face: Face, libraryURL: URL) async -> CGImage? {
        let key = face.uuid.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let task = Task.detached(priority: .userInitiated) {
            makeThumbnail(for: face, libraryURL: libraryURL)
        }
        let image = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    private static func makeThumbnail(for face: Face, libraryURL: URL) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let uuid = face.photoUUID.uuidString
        let prefix = uuid.prefix(1)
        let derivatives = libraryURL.appending(path: "resources/derivatives")
        let candidates = [
            derivatives.appending(path: "\(prefix)/\(uuid)_1_105_c.jpeg"),
            derivatives.appending(path: "\(prefix)/\(uuid)_1_101_o.jpeg"),
            derivatives.appending(path: "masters/\(prefix)/\(uuid)_4_5005_c.jpeg")
        ]
        // Decode only as large as needed for a full-resolution crop around the face.
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(Double(pixelSize) / max(face.size * contextFactor, 0.01))
        ] as CFDictionary

        for url in candidates {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                return crop(image, to: face)
            }
        }
        return nil
    }

    /// Crops a square around the face; areas outside the photo stay transparent.
    private static func crop(_ image: CGImage, to face: Face) -> CGImage? {
        let width = Double(image.width)
        let height = Double(image.height)
        let side = face.size * max(width, height) * contextFactor
        guard side > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let scale = Double(pixelSize) / side
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(
            x: -(face.centerX * width - side / 2) * scale,
            y: -(face.centerY * height - side / 2) * scale,
            width: width * scale,
            height: height * scale))
        return context.makeImage()
    }
}
