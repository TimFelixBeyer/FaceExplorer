import Foundation
import Combine
import SQLite

final class ModelData: ObservableObject {
    @Published var persons: [Person] = getPersons(path: UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/database/Photos.sqlite")
    @Published var faces: [Face] = getFaces(path: UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/database/Photos.sqlite")
//    @Published let faceAttributes = [FaceAttribute(queryName: "ZAGETYPE", displayName: "Age", dataType: AgeType)]
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

func getFaces(path: String) -> [Face] {
    print(path)
    var faces: [Face] = []
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
        // let deferredRebuildFaces = Table("ZDETECTEDFACE")
        let detectedFaces = Table("ZDETECTEDFACE")
        // let oneSevenClusterRejectedPersons = Table("Z_17CLUSTERREJECTEDPERSONS")
        // let oneSevenRejectedPersons = Table("Z_17REJECTEDPERSONS")
        // let oneSevenRejectedPersonsNeedingFaceCrops = Table("Z_17REJECTEDPERSONSNEEDINGFACECROPS")
        // let detectedFaceGroups = Table("ZDETECTEDFACEGROUP")
        // let detectedFacePrints = Table("ZDETECTEDFACEPRINT")
        // let faceCrops = Table("ZFACECROP")
        // let legacyFaces = Table("ZLEGACYFACE")
        let persons = Table("ZPERSON")
        // let fourFiveMergeCandidates = Table("Z_45MERGECANDIDATES")
        // let fourFiveInvalidMergeCandidates = Table("Z_45INVALIDMERGECANDIDATES")

        // Find all existing people
        // let favorites = Expression<Int>("ZTYPE")
        // let pk = Expression<Int>("Z_PK")
        // let fullName = Expression<String?>("ZFULLNAME")
        // let uuid = Expression<UUID>("ZPERSONUUID")
        // let faceCount = Expression<Int>("ZFACECOUNT")
        let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
        // let associatedFaceGroup = Expression<Int?>("ZASSOCIATEDFACEGROUP")

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
        // Optional attributes
        let skintoneType = Expression<Int>("ZSKINTONETYPE")
        let ageType = Expression<Int>("ZAGETYPE")
        let hasFaceMask = Expression<Int>("ZHASFACEMASK")
        let hasSmile = Expression<Int>("ZHASSMILE")
        let manual = Expression<Int>("ZMANUAL")
        let genderType = Expression<Int>("ZGENDERTYPE")
        let expressionType = Expression<Int>("ZFACEEXPRESSIONTYPE")

        // person-specfic queries
        let dateCreated = Expression<Double?>("ZDATECREATED")
        let dateCreatedi = Expression<Int?>("ZDATECREATED")
        let fullName = Expression<String?>("ZFULLNAME")
        print("{")
        for i in 0...6 {
            print(i, ":", try db.scalar(detectedFaces.select(skintoneType).filter(skintoneType == i).count), ",")
        }
        print("}")

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

            let skintoneType = SkintoneType(intValue: face[skintoneType])
            let ageType = AgeType(intValue: face[ageType])
            let genderType = GenderType(intValue: face[genderType])
            let expressionType = ExpressionType(intValue: face[expressionType])

            faces.append(Face(id: face[pk],
                              uuid: face[uuid],
                              photoPk: face[asset],
                              photoUUID: fullPic![uuid],
                              centerx: face[centerx],
                              centery: face[centery],
                              size: face[size],
                              name: name,
                              captureDate: captureDate,
                              skintoneType: skintoneType,
                              ageType: ageType,
                              genderType: genderType,
                              expressionType: expressionType))
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
