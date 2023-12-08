import Foundation
import Combine
import SQLite

final class ModelData: ObservableObject {
    @Published var persons: [Person] = []
    @Published var faces: [Face] = []
    @Published var errorOccurred = false
    @Published var errorMessage: String?

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
            errorOccurred = true
            errorMessage = errorToUserMessage(error: error)
        }
    }
    func sortByDate() { faces.sort { $0.captureDate < $1.captureDate } }
    func sortByName() { faces.sort { !$0.name!.isEmpty && ($1.name!.isEmpty || ($0.name! < $1.name!)) } }
    func sortBy(displayName: String) { faces.sort { $0.attributes[displayName]!.0 < $1.attributes[displayName]!.0 }
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
    // let additionalAssetAttributes = Table("ZADDITIONALASSETATTRIBUTES")
    let assets = Table("ZASSET")
    let detectedFaces = Table("ZDETECTEDFACE")
    // Generic Queries
    let pk = Expression<Int>("Z_PK")
    let uuid = Expression<UUID>("ZUUID")
    // detectedFace-ß queries
    var asset: Expression<Int?>
    if #available(macOS 14.0, *) {
        asset = Expression<Int?>("ZASSETFORFACE")
    } else {
        asset = Expression<Int?>("ZASSET")
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

    var count = 0
    for face in try db.prepare(detectedFaces.filter(quality > -1)) {
        let fullPic = assetsDict[face[asset]!]!
        let name = getName(face: face, personsDict: personsDict)
        // Sometimes the capture date is in Int and sometimes in the Double format.
        // We need to be able to parse both.
        let interval = (fullPic[dateCreated] ?? Double(fullPic[dateCreatedi] ?? 0))
        let captureDate = Date(timeIntervalSince1970: 978310800 + interval)

        var attributeList: [String: (Int, String)] = [:]
        for attribute in faceAttributes {
            let val = face[Expression<Int>(attribute.queryName)]
            let extractedExprOptional: String? = attribute.mapping[val]
            var extractedExpr = ""
            if extractedExprOptional == nil {
                print("Face \(String(describing: name)) count \(count) queryName \(attribute.queryName) val \(val) is nil, avoiding crash)")
            }
            else {
                extractedExpr = extractedExprOptional!
            }
            
            attributeList[attribute.displayName] = (val, extractedExpr)
        }
        faces.append(Face(id: face[pk],
                          uuid: face[uuid],
                          photoPk: face[asset],
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

func getName(face: Row, personsDict: [Int: Row]) -> String? {
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
        return personRow?[fullName]
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

func updatePerson(personName: String, face: Face) {
    print("Face \(face.uuid.uuidString) belongs to \(personName)")
}

struct FaceAttribute: Hashable, Codable {
    var displayName: String
    var queryName: String
    var type: String
    var mapping: [Int: String]
}

enum FilterCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case unnnamed = "Unnamed"
    case named = "Named"
    var id: FilterCategory { self }
}
