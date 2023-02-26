import Foundation
import SwiftUI

struct Face: Hashable, Codable, Identifiable {
    var id: Int
    var uuid: UUID
    var photo_pk: Int?
    var photo_path: String?
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
    var skintoneType: ModelData.SkintoneType?
    var ageType: ModelData.AgeType?
    var genderType: ModelData.GenderType?
    var expressionType: ModelData.ExpressionType?
    
    public init(id: Int, uuid: UUID, photo_pk: Int?, photo_path: String?, centerx: Double, centery: Double, size: Double, name: String?, captureDate: Date, skintoneType: ModelData.SkintoneType?, ageType: ModelData.AgeType?, genderType: ModelData.GenderType?, expressionType: ModelData.ExpressionType?) {
        self.id = id
        self.uuid = uuid
        self.photo_pk = photo_pk
        self.photo_path = photo_path
        self.centerx = centerx
        self.centery = centery
        self.size = size
        self.name = name
        self.category = Category.untagged
        self.captureDate = captureDate
        self.skintoneType = skintoneType
        self.ageType = ageType
        self.genderType = genderType
        self.expressionType = expressionType

    }
    
    
    var image: Image {
        let image = NSImage(contentsOf: URL(fileURLWithPath: photo_path ?? "fail"))
        if (image == nil) {
            return Image(systemName: "questionmark.circle")
        }
        // crop into face
        let width = Double(image!.size.width)
        let height = Double(image!.size.height)
        
        let contextFactor = 2.5
        let radius = size * max(width, height) * contextFactor
        let boundsRect = CGRect(x: centerx * width - radius / 2, y: centery * height - radius / 2, width: radius, height: radius)
        let img = Image(nsImage: trim(image: image!, rect: boundsRect))
        return img
        
    }
}

func trim(image: NSImage, rect: CGRect) -> NSImage {
    let result = NSImage(size: rect.size)
    result.lockFocus()

    let destRect = CGRect(origin: .zero, size: result.size)
    image.draw(in: destRect, from: rect, operation: .copy, fraction: 1.0)

    result.unlockFocus()
    return result
}
