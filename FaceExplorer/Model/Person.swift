import Foundation

struct Person: Hashable, Codable, Identifiable {
    var id: Int
    var name: String?

    var type: Category
    enum Category: String, CaseIterable, Codable {
        case hidden = "Hidden"
        case standard = "Standard"
        case favorite = "Favorite"
    }

    public init(id: Int, name: String?, type: Int) throws {
        self.id = id
        if name == "" {
            self.name = nil
        } else {
            self.name = name
        }

        switch type {
        case -1: self.type = .hidden
        case 0: self.type = .standard
        case 1: self.type = .favorite
        default:
            enum TypeParsingError: Error {
                case invalidInput(Int)
            }
            throw TypeParsingError.invalidInput(type)
        }
    }
}
