import Foundation
import Combine
import SQLite

final class ModelData: ObservableObject {
    @Published var faceAttributes = getFaceAttributes()
    @Published var persons: [Person] = getPersons(path: "\(UserDefaults.standard.string(forKey: "PhotosLibraryPath")!)/database/Photos.sqlite")
    @Published var faces: [Face] = getFaces(path: "\(UserDefaults.standard.string(forKey: "PhotosLibraryPath")!)/database/Photos.sqlite")
    
    func sortByDate() { faces.sort { $0.captureDate < $1.captureDate } }
    func sortByName() { faces.sort { !$0.name!.isEmpty && ($1.name!.isEmpty || ($0.name! < $1.name!)) } }
    func sortBy(attributeName: String) { faces.sort { $0.attributes[attributeName]!.0 < $1.attributes[attributeName]!.0 }
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

func getFaceAttributes() -> [FaceAttribute] {
    // TODO: Deal with non-Integer Attributes
    // Ideas: make it sortable and filterable via range slider l-u: 0-l---u-1
    let integerAttributes: [FaceAttribute] = load("Resources/FaceAttributeQueries.json")
    return integerAttributes
}

func getFaces(path: String) -> [Face] {
    print(path)
    var faces: [Face] = []
    let faceAttributes = getFaceAttributes()
    do {
        let db = try Connection(path, readonly: true)
        print("Connected!")
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
        let asset = Expression<Int?>("ZASSET")
        let centerx = Expression<Double>("ZCENTERX")
        let centery = Expression<Double>("ZCENTERY")
        let size = Expression<Double>("ZSIZE")
        let quality = Expression<Double>("ZQUALITY")
        let dateCreated = Expression<Double?>("ZDATECREATED")
        let dateCreatedi = Expression<Int?>("ZDATECREATED")

        var count = 0
        for face in try db.prepare(detectedFaces.filter(quality > -1)) {
            let fullPic = try db.pluck(assets.filter(pk == face[asset]!).select(dateCreated, dateCreatedi, uuid))!
            let name = getName(db: db, face: face)
            // Sometimes the capture date is in Int and sometimes in the Double format.
            // We need to be able to parse both.
            let interval = (fullPic[dateCreated] ?? Double(fullPic[dateCreatedi] ?? 0))
            let captureDate = Date(timeIntervalSince1970: 978310800 + interval)
            
            var attributeList: [String: (Int, String)] = [:]
            for attribute in faceAttributes {
                let val = face[Expression<Int>(attribute.queryName)]
                attributeList[attribute.displayName] = (val, attribute.mapping[val]!)
            }
            faces.append(Face(id: face[pk],
                              uuid: face[uuid],
                              photoPk: face[asset],
                              photoUUID: fullPic[uuid],
                              centerx: face[centerx],
                              centery: face[centery],
                              size: face[size],
                              name: name,
                              captureDate: captureDate,
                              attributes: attributeList))
            count += 1
        }
        print(count)
    } catch {
        print(error)
    }
    return faces.sorted { $0.captureDate < $1.captureDate }
}

func getName(db: Connection, face: Row) -> String? {
    let persons = Table("ZPERSON")
    let person = Expression<Int?>("ZPERSON")
    let pk = Expression<Int>("Z_PK")
    let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
    let fullName = Expression<String?>("ZFULLNAME")

    var name: String?
    do {
        if var curIdx = face[person] {
            var peep = try db.pluck(persons.filter(pk == curIdx).select(fullName, mergeTargetPerson))!
            while peep[mergeTargetPerson] != nil {
                curIdx = peep[mergeTargetPerson]!
                peep = try db.pluck(persons.filter(pk == curIdx).select(fullName, mergeTargetPerson))!
            }
            name = peep[fullName]
        }
    } catch {
        print(error)
    }
    return name
}

func getPersons(path: String) -> [Person] {
    var personsSet: Set<Person> = []

    do {
        let db = try Connection(path, readonly: true)
        let persons = Table("ZPERSON")
        let pk = Expression<Int>("Z_PK")
        let fullName = Expression<String?>("ZFULLNAME")
        let faceCount = Expression<Int>("ZFACECOUNT")
        let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
        let type = Expression<Int>("ZTYPE")

        for person in try db.prepare(persons) {
            var person = try db.pluck(persons.filter(pk == person[pk]))!
            while person[mergeTargetPerson] != nil {
                person = try db.pluck(persons.filter(pk == person[mergeTargetPerson]!))!
            }
            if person[fullName] != nil && person[faceCount] > 0 {
                personsSet.insert(try Person(id: person[pk], name: person[fullName], type: person[type]))
            }
        }
    } catch {
        print(error)
    }
    return Array(personsSet)
}

func updatePerson(personName: String, face: Face) {
    print("Face \(face.uuid.uuidString) belongs to \(personName)")
}

struct FaceAttribute: Hashable, Codable {
    var displayName: String
    var queryName: String
    var mapping: [Int: String]
}
