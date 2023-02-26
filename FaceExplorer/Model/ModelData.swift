import Foundation
import Combine
import SQLite

final class ModelData: ObservableObject {
    @Published var persons: [Person] = getPersons(path: UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/database/Photos.sqlite")
    @Published var faces: [Face] = getFaces(path: UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/database/Photos.sqlite")
        
    enum SkintoneType: String, CaseIterable, Codable, Identifiable {
        case all = "All"
        case light = "Light"
        case fair = "Fair"
        case medium = "Medium"
        case brown = "Brown"
        case dark = "Dark"
        case black = "Black"
        case unknown = "Unknown"
        var id: String { self.rawValue }

        init?(intValue: Int?) {
            switch intValue! {
                case 0: self = .unknown
                case 1: self = .light
                case 2: self = .fair
                case 3: self = .medium
                case 4: self = .brown
                case 5: self = .dark
                case 6: self = .black
                default: self = .unknown
            }
        }
    }
    enum AgeType: String, CaseIterable, Codable, Identifiable {
        case all = "All"
        case child = "Child"
        case youth = "Youth"
        case mediumYouth = "Teenager"
        case medium = "Young adult"
        case mediumOld = "Middle-aged"
        case old = "Senior"
        case unknown = "Unknown"
        var id: String { self.rawValue }

        init?(intValue: Int?) {
            switch intValue! {
                case 0: self = .child
                case 1: self = .youth
                case 2: self = .mediumYouth
                case 3: self = .medium
                case 4: self = .mediumOld
                case 5: self = .old
                default: self = .unknown
            }
        }
    }
    enum GenderType: String, CaseIterable, Codable, Identifiable {
        case all = "All"
        case male = "Male"
        case female = "Female"
        case unknown = "Unknown"
        var id: String { self.rawValue }

        init?(intValue: Int?) {
            switch intValue! {
                case 1: self = .male
                case 2: self = .female
                default: self = .unknown
            }
        }
    }
    enum ExpressionType: String, CaseIterable, Codable, Identifiable {
        case all = "All"
        case serious = "Serious"
        case frowning = "Frowning"
        case annoyed = "Annoyed"
        case pleased = "Pleased"
        case smiling = "Smiling"
        case speaking = "Speaking"
        case unknown = "Unknown"
        var id: String { self.rawValue }

        init?(intValue: Int?) {
            switch intValue! {
                case 0: self = .unknown
                case 1: self = .serious
                case 2: self = .frowning
                case 3: self = .annoyed
                case 4: self = .pleased
                case 5: self = .smiling
                case 6: self = .speaking
                default: self = .unknown
            }
        }
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




func getFaces(path: String) -> [Face] {
    print(path)
    var faces: [Face] = []
    var names: Set<String> = Set(getPersons(path: path).compactMap( { $0.name }))
                                

    do {
        let db = try Connection(path, readonly: true)
        print("Connected!")
        for row in (try db.prepare("SELECT name FROM sqlite_schema WHERE type ='table' AND name NOT LIKE 'sqlite_%';")) {
            print("id: \(row[0]!)")
            
        }
        // WARNING: For readability we add a trailing s to all database names in their swift object counterpart.
//            let additionalAssetAttributes = Table("ZADDITIONALASSETATTRIBUTES")
        let assets = Table("ZASSET")
//            let deferredRebuildFaces = Table("ZDETECTEDFACE")
        let detectedFaces = Table("ZDETECTEDFACE")
//            let oneSevenClusterRejectedPersons = Table("Z_17CLUSTERREJECTEDPERSONS")
//            let oneSevenRejectedPersons = Table("Z_17REJECTEDPERSONS")
//            let oneSevenRejectedPersonsNeedingFaceCrops = Table("Z_17REJECTEDPERSONSNEEDINGFACECROPS")
//            let detectedFaceGroups = Table("ZDETECTEDFACEGROUP")
//            let detectedFacePrints = Table("ZDETECTEDFACEPRINT")
//            let faceCrops = Table("ZFACECROP")
//            let legacyFaces = Table("ZLEGACYFACE")
        let persons = Table("ZPERSON")
//            let fourFiveMergeCandidates = Table("Z_45MERGECANDIDATES")
//            let fourFiveInvalidMergeCandidates = Table("Z_45INVALIDMERGECANDIDATES")

        
        // Find all existing people
//        let favorites = Expression<Int>("ZTYPE")
//        let pk = Expression<Int>("Z_PK")
//        let fullName = Expression<String?>("ZFULLNAME")
//        let uuid = Expression<UUID>("ZPERSONUUID")
//        let faceCount = Expression<Int>("ZFACECOUNT")
        let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
//        let associatedFaceGroup = Expression<Int?>("ZASSOCIATEDFACEGROUP")

        var faceGraph: [Int: [Int]] = [:]
        
        var sum_faces = 0
//        for person in try db.prepare(persons) {
//            //if (person[faceCount] == 0) { continue }
//            print("Person: ", person[fullName], "Face count:", person[faceCount], "UUID ", person[uuid], "tgt",  person[mergeTargetPerson])
//            sum_faces += person[faceCount]
//
//
//            if (person[mergeTargetPerson] != nil) {
//                print("Appending ", person[mergeTargetPerson], " to ", person[pk])
//                faceGraph[person[pk]] = [person[mergeTargetPerson]!]
//            } else {
//                faceGraph[person[pk]] = []
//            }
//        }
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
        for face in try db.prepare(detectedFaces) {
            if face[quality] > -1 {
//            if SkintoneType(rawValue: face[skintoneType]) == .light {
//            if AgeType(rawValue: face[ageType]) == .youth {
//            if face[manual] == 1 {
                let fullPic = try db.pluck(assets.filter(pk == face[asset]!))
                let picUUID = fullPic![uuid].uuidString
                let picPath = UserDefaults.standard.string(forKey: "PhotosLibraryPath")! + "/resources/derivatives/\(picUUID.prefix(1))/" + picUUID + "_1_105_c.jpeg"
                var name: String? = nil
                if face[person] != nil {
                    var curIdx = face[person]!
                    
                    
                    var peep = try db.pluck(persons.filter(pk == curIdx))!
                    while peep[mergeTargetPerson] != nil {
                        curIdx = peep[mergeTargetPerson]!
                        peep = try db.pluck(persons.filter(pk == curIdx))!
                    }
                    name = peep[fullName]
                }
                    
                if name != nil && names.contains(name!) {
                    continue
                }

                let dateCreated_ = fullPic![dateCreated]
                let dateCreatedi = fullPic![dateCreatedi]
                var captureDate: Date
                if dateCreated_ == nil && dateCreatedi == nil {
                    captureDate = Date(timeIntervalSince1970: 0)
                } else {
                    if dateCreated_ != nil {
                        captureDate = Date(timeIntervalSince1970: 978310800 + dateCreated_!)
                    } else {
                        captureDate = Date(timeIntervalSince1970: 978310800 + Double(dateCreatedi!))
                    }
                }
            
                let skintoneType_ = ModelData.SkintoneType(intValue: face[skintoneType])
                let ageType_ = ModelData.AgeType(intValue: face[ageType])
                let genderType_ = ModelData.GenderType(intValue: face[genderType])
                let expressionType_ = ModelData.ExpressionType(intValue: face[expressionType])


                faces.append(Face(id: face[pk],
                                  uuid: face[uuid],
                                  photo_pk: face[asset],
                                  photo_path: picPath,
                                  centerx: face[centerx],
                                  centery: face[centery],
                                  size: face[size],
                                  name: name,
                                  captureDate: captureDate,
                                  skintoneType: skintoneType_,
                                  ageType: ageType_,
                                  genderType: genderType_,
                                  expressionType: expressionType_))
                count += 1
            }
            if (count >= 1000) { break }
        }
        print(count)

    } catch {
        print(error)
    }
    return faces.sorted { $0.captureDate < $1.captureDate }
}


func getPersons(path: String) -> [Person] {
    var persons_: Set<Person> = []

    do {
        let db = try Connection(path, readonly: true)
        let persons = Table("ZPERSON")
        let pk = Expression<Int>("Z_PK")
        let fullName = Expression<String?>("ZFULLNAME")
        let faceCount = Expression<Int>("ZFACECOUNT")
        let mergeTargetPerson = Expression<Int?>("ZMERGETARGETPERSON")
        let type = Expression<Int>("ZTYPE")


        
        for person in try db.prepare(persons) {
            var curIdx = person[pk]
            
            var person = try db.pluck(persons.filter(pk == curIdx))!
            while person[mergeTargetPerson] != nil {
                curIdx = person[mergeTargetPerson]!
                person = try db.pluck(persons.filter(pk == curIdx))!
            }
            if person[fullName] != nil && person[faceCount] > 0 {
                persons_.insert(try Person(id: person[pk], name: person[fullName]!, type: person[type]))
            }
        }
    } catch {
        print(error)
    }
    return Array(persons_)
}

func updatePerson(personName: String, face: Face) {
    print("Face \(face.uuid.uuidString) belongs to \(personName)")
}
