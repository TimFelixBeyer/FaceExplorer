/// A named person in the Photos library.
struct Person: Hashable, Identifiable, Sendable {
    /// `Z_PK` of the person in `ZPERSON`.
    let id: Int
    let name: String
    /// The identifier of the linked contact (`ZPERSONURI`), if any.
    var contactIdentifier: String?
}
