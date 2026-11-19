import Foundation
import Combine
import SQLite
typealias Expression = SQLite.Expression

final class ModelData: ObservableObject {
    @Published var persons: [Person] = []
    @Published var faces: [Face] = []
    @Published var errorOccurred = false
    @Published var errorMessage: String = ""

    let faceAttributes = getFaceAttributes()

    init() {
        if UserDefaults.standard.string(forKey: "PhotosLibraryPath") == nil {
            selectLibrary()
        }
        loadLibrary()
    }

    func loadLibrary() {
        let databasePath = "\(UserDefaults.standard.string(forKey: "PhotosLibraryPath")!)/database/Photos.sqlite"
        do {
            persons = try getPersons(path: databasePath)
            faces = try getFaces(path: databasePath)
        } catch {
            persons = []
            faces = []
            displayError(error: error)
        }
    }
    func sortByDate() { faces.sort { $0.captureDate < $1.captureDate } }
    func sortByName() { faces.sort { !$0.name.isEmpty && ($1.name.isEmpty || ($0.name < $1.name)) } }
    func sortBy(displayName: String) { faces.sort { $0.attributes[displayName]!.0 < $1.attributes[displayName]!.0 }
    }
    func displayError(error: Error) {
        errorMessage = errorToUserMessage(error: error)
        errorOccurred = true
    }
}

func load<T: Decodable>(_ filename: String) -> T {
    let data: Data

    guard let file = Bundle.main.url(forResource: filename, withExtension: nil)
        else {
            fatalError("Couldn't find \(filename) in main bundle.")
    }

    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error)")
    }
}

func errorToUserMessage(error: Error) -> String {
    let errorString = String(describing: error)
    var errorMessage = error.localizedDescription

    if let range = errorString.range(of: "\\((code: )(\\d+)\\)", options: .regularExpression),
        let errorCode = Int(errorString[range].dropFirst(7).dropLast(1)) {
        switch errorCode {
        case 23: // permissions error
            errorMessage = "Cannot open the Library due to a permissions error, please try selecting it again."
        default:
            errorMessage = error.localizedDescription
        }
    }
    return errorMessage
}

func getFaceAttributes() -> [FaceAttribute] {
    // TODO: Deal with non-Integer Attributes
    // Ideas: make it sortable and filterable via range slider l-u: 0-l---u-1
    let integerAttributes: [FaceAttribute] = load("Resources/FaceAttributeQueries.json")
    return integerAttributes
}

func getFaces(path: String) throws -> [Face] {
    print(path)
    let db = try Connection(path, readonly: true)

    var faces: [Face] = []
    let faceAttributes = getFaceAttributes()
    // List available tables
    // for row in (try db.prepare("SELECT name FROM sqlite_schema WHERE type ='table' AND name NOT LIKE 'sqlite_%';")) {
    //     print("id: \(row[0]!)")
    // }
    // WARNING: For readability we add a trailing s to all database names in their swift object counterpart.
    let assets = Table("ZASSET")
    let detectedFaces = Table("ZDETECTEDFACE")
    // Generic Queries
    let pk = Expression<Int>("Z_PK")
    let uuid = Expression<UUID>("ZUUID")
    // detectedFace-ß queries
    let asset = Expression<Int?>("ZASSET")
    var assetForFace: Expression<Int?>
    if #available(macOS 14.0, *) {
        assetForFace = Expression<Int?>("ZASSETFORFACE")
    } else {
        assetForFace = Expression<Int?>("ZASSET")
    }
    let centerX = Expression<Double>("ZCENTERX")
    let centerY = Expression<Double>("ZCENTERY")
    let size = Expression<Double>("ZSIZE")
    let quality = Expression<Double>("ZQUALITY")
    let dateCreated = Expression<Double?>("ZDATECREATED")
    let dateCreatedi = Expression<Int?>("ZDATECREATED")

    // person queries
    let persons = Table("ZPERSON")
    let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
    let fullName = Expression<String?>("ZFULLNAME")

    // additionalAssetAttribute queries
    let additionalAttributes = Table("ZADDITIONALASSETATTRIBUTES")
    let timezoneOffset = Expression<Int?>("ZINFERREDTIMEZONEOFFSET")

    // Prefetch some data from the db for performance
    let assetsDict = Dictionary(uniqueKeysWithValues:
        try db.prepare(assets.select(pk, dateCreated, dateCreatedi, uuid)).map {
            ($0[pk], $0)
        }
    )
    let personsDict = Dictionary(uniqueKeysWithValues:
        try db.prepare(persons.select(pk, fullName, mergeTargetPerson)).map {
            ($0[pk], $0)
        }
    )
    let timezoneOffsetDict = Dictionary(uniqueKeysWithValues:
        try db.prepare(additionalAttributes.select(asset, timezoneOffset)).map {
            ($0[asset], $0)
        }
    )

    var count = 0
    for face in try db.prepare(detectedFaces.filter(quality > -1)) {
        if face[Expression<Int>("ZASSETVISIBLE")] == 0 {
            continue
        }
        let fullPic = assetsDict[face[assetForFace]!]!
        let name = getName(face: face, personsDict: personsDict)
        // Sometimes the capture date is in Int and sometimes in the Double format.
        // We need to be able to parse both.
        let interval = (fullPic[dateCreated] ?? Double(fullPic[dateCreatedi] ?? 0))
        // TODO: Look at timezones again, CEST has issues.
        var timezoneOffsetValue = 0.0
        if let timezone = timezoneOffsetDict[face[assetForFace]!],
           let offset = timezone[timezoneOffset] {
            timezoneOffsetValue = Double(offset)
        }
        let captureDate = Date(timeIntervalSince1970: 978303600 + interval + timezoneOffsetValue)

        var attributeList: [String: (Int, String)] = [:]
        for attribute in faceAttributes {
            let val = face[Expression<Int>(attribute.queryName)]
            attributeList[attribute.displayName] = (val, attribute.mapping[val] ?? "")
        }
        faces.append(Face(id: face[pk],
                          uuid: face[uuid],
                          photoPk: face[assetForFace],
                          photoUUID: fullPic[uuid],
                          centerX: face[centerX],
                          centerY: face[centerY],
                          size: face[size],
                          name: name,
                          captureDate: captureDate,
                          attributes: attributeList))
        count += 1
    }
    print(count)
    return faces.sorted { $0.captureDate < $1.captureDate }
}

func getName(face: Row, personsDict: [Int: Row]) -> String {
    var person: Expression<Int?>
    if #available(macOS 14.0, *) {
        person = Expression<Int?>("ZPERSONFORFACE")
    } else {
        person = Expression<Int?>("ZPERSON")
    }
    let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
    let fullName = Expression<String?>("ZFULLNAME")

    if var personID = face[person] {
        var personRow = personsDict[personID]

        while let newPersonID = personRow?[mergeTargetPerson], let newPersonRow = personsDict[newPersonID] {
            personID = newPersonID
            personRow = newPersonRow
        }
        return personRow?[fullName] ?? ""
    } else {
        return ""
    }
}

func getPersons(path: String) throws -> [Person] {
    var personsSet: Set<Person> = []

    let db = try Connection(path, readonly: true)
    let persons = Table("ZPERSON")
    let pk = Expression<Int>("Z_PK")
    let fullName = Expression<String?>("ZFULLNAME")
    let faceCount = Expression<Int>("ZFACECOUNT")
    let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
    let type = Expression<Int>("ZTYPE")

    // Create a dictionary of all persons, with `pk` as the key, yields dramatic speedup (1.2s -> 0.05s)!
    let personsDict = Dictionary(uniqueKeysWithValues:
        try db.prepare(persons.select(pk, fullName, faceCount, mergeTargetPerson, type)).map {
            ($0[pk], $0)
        }
    )
    for (_, currentPerson) in personsDict {
        var mergedPerson = currentPerson

        // We follow the merge chain to the end.
        while let mergeTarget = mergedPerson[mergeTargetPerson] {
            mergedPerson = personsDict[mergeTarget] ?? mergedPerson
        }
        // We add the person if they have photos with faces, some people have 0 faces registered.
        if let fullName = mergedPerson[fullName], mergedPerson[faceCount] > 0 {
            personsSet.insert(try Person(id: mergedPerson[pk], name: fullName, type: mergedPerson[type]))
        }
    }
    return Array(personsSet)
}

/// Assigns a detected face to a named person in the selected Photos library.
///
/// Existing people are reused by exact, case-sensitive name. If no matching
/// person exists, a standard person record is created. The face relationship
/// and each affected person's face count are updated in one transaction.
///
/// - Parameters:
///   - personName: The desired person's name. Leading and trailing whitespace
///     is ignored; an empty name is rejected.
///   - face: The detected face whose person relationship should change.
/// - Throws: An error if the library path is unavailable, the face or person
///   cannot be resolved, or the database transaction fails.
func updatePerson(personName: String, face: Face) throws {
    let normalizedName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
        throw PersonUpdateError.emptyName
    }
    guard let libraryPath = UserDefaults.standard.string(forKey: "PhotosLibraryPath") else {
        throw PersonUpdateError.libraryPathUnavailable
    }

    let databasePath = "\(libraryPath)/database/Photos.sqlite"
    let database = try Connection(databasePath)
    let persons = Table("ZPERSON")
    let detectedFaces = Table("ZDETECTEDFACE")
    let primaryKeys = Table("Z_PRIMARYKEY")
    let primaryKey = Expression<Int>("Z_PK")
    let faceUUID = Expression<UUID>("ZUUID")
    registerCoreDataTriggerCallback(on: database)
    let personColumnName: String
    if #available(macOS 14.0, *) {
        personColumnName = "ZPERSONFORFACE"
    } else {
        personColumnName = "ZPERSON"
    }
    let facePerson = Expression<Int?>(personColumnName)
    let context = PersonDatabaseContext(database: database, persons: persons,
                                        detectedFaces: detectedFaces, primaryKeys: primaryKeys,
                                        primaryKey: primaryKey, faceUUIDColumn: faceUUID,
                                        facePerson: facePerson)
    try assignPerson(named: normalizedName, faceUUID: face.uuid, context: context)
}

/// Registers the callback expected by Core Data triggers in Photos databases.
///
/// Photos' triggers call this function after maintaining derived database values.
/// FaceExplorer uses SQLite directly and has no Core Data context to notify, so
/// the callback is intentionally a no-op; the trigger's SQL still runs normally.
///
/// - Parameter database: The writable connection that will execute Photos triggers.
private func registerCoreDataTriggerCallback(on database: Connection) {
    database.createFunction("NSCoreDataTriggerUpdateAffectedObjectValue") { _ in nil }
}

/// Holds the Photos database handles and column expressions used for assignment.
private struct PersonDatabaseContext {
    let database: Connection
    let persons: Table
    let detectedFaces: Table
    let primaryKeys: Table
    let primaryKey: Expression<Int>
    let faceUUIDColumn: Expression<UUID>
    let facePerson: Expression<Int?>
}

/// Applies the relationship and face-count changes in one database transaction.
///
/// - Parameters:
///   - name: The normalized name assigned to the face.
///   - faceUUID: The stable identifier of the detected face.
///   - context: The open database and the relevant table and column expressions.
/// - Throws: An error if rows cannot be resolved or the transaction fails.
private func assignPerson(named name: String,
                          faceUUID: UUID,
                          context: PersonDatabaseContext) throws {
    let database = context.database
    let persons = context.persons
    let detectedFaces = context.detectedFaces
    let primaryKey = context.primaryKey
    let faceUUIDColumn = context.faceUUIDColumn
    let facePerson = context.facePerson
    let fullName = Expression<String?>("ZFULLNAME")
    let faceCount = Expression<Int>("ZFACECOUNT")
    let mergeTarget = Expression<Int?>("ZMERGETARGETPERSON")
    let type = Expression<Int>("ZTYPE")

    try database.transaction {
        let faceRow = try database.pluck(detectedFaces.filter(faceUUIDColumn == faceUUID))
        guard let faceRow else { throw PersonUpdateError.faceNotFound }
        let personRows = try database.prepare(persons.select(primaryKey, fullName, faceCount, mergeTarget, type))
        let people = Dictionary(uniqueKeysWithValues: personRows.map { ($0[primaryKey], $0) })
        let oldPersonID = resolvedPersonID(faceRow[facePerson], people: people,
                                           mergeTarget: mergeTarget)
        let newPersonID = try personID(named: name, context: context)
        guard oldPersonID != newPersonID else { return }
        try database.run(detectedFaces.filter(primaryKey == faceRow[primaryKey])
            .update(facePerson <- newPersonID))
        if let oldPersonID {
            try database.run(persons.filter(primaryKey == oldPersonID && faceCount > 0)
                .update(faceCount <- faceCount - 1))
        }
        try database.run(persons.filter(primaryKey == newPersonID)
            .update(faceCount <- faceCount + 1))
    }
}

/// Resolves a face's person through any Photos merge chain.
private func resolvedPersonID(_ personID: Int?,
                              people: [Int: Row],
                              mergeTarget: Expression<Int?>) -> Int? {
    guard var currentID = personID, var row = people[currentID] else { return nil }
    var visited: Set<Int> = []
    while let nextID = row[mergeTarget], let nextRow = people[nextID], visited.insert(currentID).inserted {
        currentID = nextID
        row = nextRow
    }
    return currentID
}

/// Reuses a named person or inserts a standard person record.
private func personID(named name: String, context: PersonDatabaseContext) throws -> Int {
    let database = context.database
    let persons = context.persons
    let primaryKeys = context.primaryKeys
    let primaryKey = context.primaryKey
    let fullName = Expression<String?>("ZFULLNAME")
    let faceCount = Expression<Int>("ZFACECOUNT")
    let mergeTarget = Expression<Int?>("ZMERGETARGETPERSON")
    let entity = Expression<Int>("Z_ENT")
    let entityName = Expression<String>("Z_NAME")
    let type = Expression<Int>("ZTYPE")
    if let row = try database.pluck(persons
        .filter(fullName == name && mergeTarget == nil).select(primaryKey)) {
        return row[primaryKey]
    }
    guard let personEntityID = try database.pluck(primaryKeys.filter(entityName == "Person"))?[entity] else {
        throw PersonUpdateError.personEntityUnavailable
    }
    let insert = persons.insert(entity <- personEntityID,
                                Expression<Int>("Z_OPT") <- 1,
                                fullName <- name,
                                faceCount <- 0,
                                type <- 0)
    return Int(try database.run(insert))
}

/// Errors that can prevent assigning a detected face to a person.
enum PersonUpdateError: LocalizedError {
    case emptyName
    case libraryPathUnavailable
    case faceNotFound
    case personEntityUnavailable

    /// A user-facing description of the failed assignment.
    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a person's name before assigning this face."
        case .libraryPathUnavailable:
            return "Select a Photos library before assigning a person."
        case .faceNotFound:
            return "The selected face could not be found in the Photos library."
        case .personEntityUnavailable:
            return "The Photos library does not contain person records."
        }
    }
}

struct FaceAttribute: Hashable, Codable {
    var displayName: String
    var queryName: String
    var type: String
    var mapping: [Int: String]
}

enum TagFilterCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case unnnamed = "Unnamed"
    case named = "Named"
    var id: TagFilterCategory { self }
}
