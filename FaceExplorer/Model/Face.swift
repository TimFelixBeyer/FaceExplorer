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
        case untagged = "Untagged"
        case tagged = "Tagged"
    }
    var captureDate: Date
    var attributes: [String: any Constructible] = [:]

    public init(id: Int,
                uuid: UUID,
                photoPk: Int?,
                photoUUID: UUID,
                centerx: Double,
                centery: Double,
                size: Double,
                name: String?,
                captureDate: Date,
                attributes: [String: any Constructible]) {
        self.id = id
        self.uuid = uuid
        self.photoUUID = photoUUID
        self.photoPk = photoPk
        self.centerx = centerx
        self.centery = centery
        self.size = size
        self.name = name
        self.category = (name == "") ? Category.untagged : Category.tagged
        self.captureDate = captureDate
        self.attributes = attributes
    }

    var image: Image {
        let picPath = UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/resources/derivatives/\(photoUUID.uuidString.prefix(1))/" + photoUUID.uuidString + "_1_105_c.jpeg"
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
//        let img = Image(nsImage: trim(image: image!, rect: boundsRect), scale: 1.0, label: Text(""))
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
//    print(cutRect.origin.x, cutRect.origin.x + cutRect.width, cutRect.origin.y, cutRect.origin.y + cutRect.height, image.size)
    let result = cutImageRef.cropping(to: cutRect)!
    return result
}


protocol Constructible: Hashable, Identifiable, Equatable, CaseIterable, RawRepresentable where RawValue == String {
    init(intValue: Int?)
}

enum SkintoneType: String, CaseIterable, Codable, Identifiable, Constructible {
    case all = "All"
    case light = "Light"
    case fair = "Fair"
    case medium = "Medium"
    case brown = "Brown"
    case dark = "Dark"
    case black = "Black"
    case other = "Other"
    var id: String { self.rawValue }

    init(intValue: Int?) {
        switch intValue! {
        case -1: self = .all
        case 1...6: self = SkintoneType(rawValue: SkintoneType.allCases[intValue!].rawValue) ?? .other
        default: self = .other
        }
    }
}

enum AgeType: String, CaseIterable, Codable, Identifiable, Constructible {
    case all = "All"
    case baby = "Baby"
    case child = "Child"
    case youngAdult = "Young adult"
    case adult = "Adult"
    case senior = "Senior"
    case other = "Other"
    var id: String { self.rawValue }

    init(intValue: Int?) {
        switch intValue! {
        case -1: self = .all
        case 1: self = .baby
        case 2: self = .child
        case 3: self = .youngAdult
        case 4: self = .senior
        case 5: self = .adult
        default: self = .other
        }
    }
}

enum GenderType: String, CaseIterable, Codable, Identifiable, Constructible {
    case all = "All"
    case male = "Male"
    case female = "Female"
    case other = "Other"
    var id: String { self.rawValue }

    init(intValue: Int?) {
        switch intValue! {
        case -1: self = .all
        case 1: self = .male
        case 2: self = .female
        default: self = .other
        }
    }
}

enum ExpressionType: String, CaseIterable, Codable, Identifiable, Constructible {
    case all = "All"
    case serious = "Serious"
    case frowning = "Frowning"
    case annoyed = "Annoyed"
    case pleased = "Pleased"
    case smiling = "Smiling"
    case speaking = "Speaking"
    case other = "Other"
    var id: String { self.rawValue }

    init(intValue: Int?) {
        switch intValue! {
        case -1: self = .all
        case 1...6: self = ExpressionType(rawValue: ExpressionType.allCases[intValue!].rawValue) ?? .other
        default: self = .other
        }
    }
}
