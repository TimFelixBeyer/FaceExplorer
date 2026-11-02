import Contacts
import Foundation

/// A contact from the Contacts app that a new person can be created from.
struct ContactCard: Hashable, Identifiable, Sendable {
    /// `CNContact.identifier`, which Photos stores as the person's `ZPERSONURI`.
    let id: String
    let name: String
    let givenName: String
    let familyName: String
    let phoneNumbers: [String]
    let emailAddresses: [String]

    /// Reads all contacts with a name, after asking for access if needed.
    static func fetchAll() async throws -> [ContactCard] {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else {
            throw AccessError()
        }
        return try await Task.detached {
            let keys: [any CNKeyDescriptor] = [
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactGivenNameKey as NSString,
                CNContactFamilyNameKey as NSString,
                CNContactPhoneNumbersKey as NSString,
                CNContactEmailAddressesKey as NSString
            ]
            var cards: [ContactCard] = []
            try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                guard let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty else { return }
                cards.append(ContactCard(
                    id: contact.identifier,
                    name: name,
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
                    emailAddresses: contact.emailAddresses.map { $0.value as String }
                ))
            }
            return cards.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
    }

    struct AccessError: LocalizedError {
        var errorDescription: String? {
            "FaceExplorer is not allowed to read your contacts. You can change this in System Settings › Privacy & Security › Contacts."
        }
    }
}

/// Who to assign faces to.
enum AssignmentTarget: Hashable, Sendable {
    case person(Person)
    /// A contact that isn't a person in the library yet.
    case contact(ContactCard)

    var name: String {
        switch self {
        case .person(let person): person.name
        case .contact(let contact): contact.name
        }
    }
}
