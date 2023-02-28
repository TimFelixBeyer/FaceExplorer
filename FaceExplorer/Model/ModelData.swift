import Foundation
import Combine
import SQLite

final class ModelData: ObservableObject {
    @Published var faceAttributes = getFaceAttributes()
    @Published var persons: [Person] = getPersons(path: UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/database/Photos.sqlite")
    @Published var faces: [Face] = getFaces(path: UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/database/Photos.sqlite")
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
    return [
        FaceAttribute(displayName: "Age", queryName: "ZAGETYPE", mapping: [-1: "All", 1: "Baby", 2: "Child", 3: "Young adult", 4: "Adult", 5: "Senior"]),
        FaceAttribute(displayName: "Ethnicity", queryName: "ZETHNICITYTYPE", mapping: [-1: "All", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5"]),
        FaceAttribute(displayName: "Expression", queryName: "ZFACEEXPRESSIONTYPE", mapping: [-1: "All", 1: "Serious", 2: "Frowning", 3: "Annoyed", 4: "Pleased", 5: "Smiling", 6: "Speaking"]),
        FaceAttribute(displayName: "Eye State", queryName: "ZEYESSTATE", mapping: [-1: "All", 1: "Open", 2: "Closed"]),
//        FaceAttribute(displayName: "Eye State (left)", queryName: "ZISLEFTEYECLOSED", mapping: [-1: "All", 0: "Open", 1: "Closed"]),
//        FaceAttribute(displayName: "Eye State (right)", queryName: "ZISRIGHTEYECLOSED", mapping: [-1: "All", 0: "Open", 1: "Closed"]),  redundant
        FaceAttribute(displayName: "Face Mask", queryName: "ZHASFACEMASK", mapping: [-1: "All", 0: "No Mask", 1: "Mask?"]),
        FaceAttribute(displayName: "Facial Hair", queryName: "ZFACIALHAIRTYPE", mapping: [-1: "All", 1: "None", 2: "Light Beard", 3: "Beard", 4: "Chevron", 5: "Stubble"]),
        FaceAttribute(displayName: "Gaze", queryName: "ZGAZETYPE", mapping: [-1: "All", 1: "Into Camera", 2: "Sideways?", 3: "Downwards", 4: "Diagonal?", 5: "Sunglasses"]),
        FaceAttribute(displayName: "Gender", queryName: "ZGENDERTYPE", mapping: [-1: "All", 1: "Male", 2: "Female"]),
        FaceAttribute(displayName: "Glasses", queryName: "ZGLASSESTYPE", mapping: [-1: "All", 1: "Glasses", 2: "Sunglasses", 3: "No Glasses"]),
        FaceAttribute(displayName: "Head Gear", queryName: "ZHEADGEARTYPE", mapping: [-1: "All", 1: "Cap", 2: "Beanie/Hoodie", 3: "Hoodie", 4: "Hood (Jacket)", 5: "None"]),
//        FaceAttribute(displayName: "Makeup (Eyes)", queryName: "ZEYESMAKEUPTYPE", mapping: [-1: "All", 0: "0", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5", 6: "6"]),
//        FaceAttribute(displayName: "Makeup (Lips)", queryName: "ZLIPSMAKEUPTYPE", mapping: [-1: "All", 0: "0", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5", 6: "6"]), // all 0s
        FaceAttribute(displayName: "Pose", queryName: "ZPOSETYPE", mapping: [-1: "All", 1: "Frontal", 2: "Left", 3: "Half-left", 4: "Right", 5: "Half-right"]),
        FaceAttribute(displayName: "Smiling", queryName: "ZHASSMILE", mapping: [-1: "All", 0: "No", 1: "Yes"]),
        FaceAttribute(displayName: "Smile Type", queryName: "ZSMILETYPE", mapping: [-1: "All", 1: "No Smile", 2: "Smiling"]),
        FaceAttribute(displayName: "Skintone", queryName: "ZSKINTONETYPE", mapping: [-1: "All", 1: "Light", 2: "Fair", 3: "Medium", 4: "Brown", 5: "Dark", 6: "Black"])
//        FaceAttribute(displayName: "Dummy", queryName: "Dummy", mapping: [-1: "All", 0: "0", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5", 6: "6"]),
    ]
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
        let persons = Table("ZPERSON")

        // Generic Queries
        let pk = Expression<Int>("Z_PK")
        let uuid = Expression<UUID>("ZUUID")
        // detectedFace-specific queries
        let person = Expression<Int?>("ZPERSON")
        let asset = Expression<Int?>("ZASSET")
        let centerx = Expression<Double>("ZCENTERX")
        let centery = Expression<Double>("ZCENTERY")
        let size = Expression<Double>("ZSIZE")
        let quality = Expression<Double>("ZQUALITY")
        // person-specfic queries
        let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
        let dateCreated = Expression<Double?>("ZDATECREATED")
        let dateCreatedi = Expression<Int?>("ZDATECREATED")
        let fullName = Expression<String?>("ZFULLNAME")

        var count = 0
        for face in try db.prepare(detectedFaces.filter(quality > -1)) {
            // Find the person belonging to this face.
            var name: String?
            if var curIdx = face[person] {
                var peep = try db.pluck(persons.filter(pk == curIdx).select(fullName, mergeTargetPerson))!
                while peep[mergeTargetPerson] != nil {
                    curIdx = peep[mergeTargetPerson]!
                    peep = try db.pluck(persons.filter(pk == curIdx).select(fullName, mergeTargetPerson))!
                }
                name = peep[fullName]
            }
            let fullPic = try db.pluck(assets.filter(pk == face[asset]!).select(dateCreated, dateCreatedi, uuid))
            // Sometimes the capture date is in Int and sometimes in the Double format.
            // We need to be able to parse both.
            let interval = (fullPic![dateCreated] ?? Double(fullPic![dateCreatedi] ?? 0))
            let captureDate = Date(timeIntervalSince1970: 978310800 + interval)
            
            var attributeList: [String: (Int, String)] = [:]
            for attribute in faceAttributes {
                let val = face[Expression<Int>(attribute.queryName)]
                attributeList[attribute.displayName] = (val, attribute.mapping[val]!)
            }
            faces.append(Face(id: face[pk],
                              uuid: face[uuid],
                              photoPk: face[asset],
                              photoUUID: fullPic![uuid],
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

struct FaceAttribute: Hashable {
    var displayName: String
    var queryName: String
    var mapping: [Int: String]
}
