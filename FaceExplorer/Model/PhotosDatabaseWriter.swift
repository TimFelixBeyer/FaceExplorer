import Foundation
import SQLite

/// Writing to the library database, as Photos would when confirming faces or adding people.
///
/// Photos must not be running: it caches the store in memory and would not notice the changes
/// (or overwrite them). Changes are not recorded in CoreData's persistent history, so they are
/// not synced to iCloud Photos.
extension PhotosDatabase {
    /// How a face was assigned before a change, to undo it.
    struct FaceSnapshot: Sendable {
        let faceID: Int
        let personID: Int?
        let nameSource: Int64?
        let cloudNameSource: Int64?
        /// The person whose representative (key) face this face was.
        let keyFaceOfPersonID: Int?
    }

    struct AssignmentResult: Sendable {
        /// The person the faces now belong to.
        let person: Person
        /// The previous state of the faces that changed.
        let snapshots: [FaceSnapshot]
        /// Whether the person was created from a contact by this assignment.
        let createdPerson: Bool
    }

    /// Writes a consistent copy of the database into the library's `FaceExplorer Backups` folder.
    ///
    /// - Parameter progress: Called periodically from a background queue with the approximate fraction done.
    func backup(progress: @escaping @Sendable (Double) -> Void) throws {
        try mappingErrors {
            let folder = url.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "FaceExplorer Backups")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let timestamp = Date.now.formatted(.iso8601.dateTimeSeparator(.space)).replacing(":", with: "-")
            let backup = folder.appending(path: "Photos \(timestamp).sqlite")

            // The copy grows to roughly the size of the database while VACUUM INTO writes it.
            let totalSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Double) ?? 0
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now(), repeating: .milliseconds(500))
            timer.setEventHandler {
                let size = (try? FileManager.default.attributesOfItem(atPath: backup.path)[.size] as? Double) ?? 0
                progress(totalSize > 0 ? min(size / totalSize, 1) : 0)
            }
            timer.resume()
            defer { timer.cancel() }

            do {
                try Connection(url.path, readonly: true).run("VACUUM INTO ?", backup.path)
            } catch {
                // Don't leave an incomplete backup behind.
                for file in [backup.path, backup.path + "-journal"] {
                    try? FileManager.default.removeItem(atPath: file)
                }
                throw error
            }
        }
    }

    /// Assigns faces to a person, creating the person first for a contact that isn't one yet.
    /// All faces change in one transaction.
    func assign(faceIDs: [Int], to target: AssignmentTarget) throws -> AssignmentResult {
        try writing { db, schema in
            let (person, createdPerson) = switch target {
            case .person(let person):
                (try assignablePerson(person, db), false)
            case .contact(let contact):
                try person(for: contact, db, schema)
            }

            var snapshots: [FaceSnapshot] = []
            for faceID in faceIDs {
                let snapshot = try snapshot(of: faceID, db, schema)
                guard snapshot.personID != person.id else { continue }
                snapshots.append(snapshot)

                // Mark the face as named by the user, as Photos does for faces confirmed by hand.
                var assignments = ["\(schema.facePerson) = ?", "Z_OPT = IFNULL(Z_OPT, 0) + 1"]
                assignments += ["ZNAMESOURCE", "ZCLOUDNAMESOURCE"].filter(schema.faceColumns.contains).map { "\($0) = 1" }
                if schema.faceColumns.contains("ZPERSONBEINGKEYFACE") {
                    // The face can't stay the representative face of its previous person.
                    assignments.append("ZPERSONBEINGKEYFACE = NULL")
                    try db.run("UPDATE ZPERSON SET ZKEYFACE = NULL, Z_OPT = IFNULL(Z_OPT, 0) + 1 WHERE ZKEYFACE = ?", faceID)
                }
                try db.run("UPDATE ZDETECTEDFACE SET \(assignments.joined(separator: ", ")) WHERE Z_PK = ?", person.id, faceID)
                // The triggers changed both persons' face counts.
                try bumpVersion(ofPersons: [person.id, snapshot.personID], db)
            }
            return AssignmentResult(person: person, snapshots: snapshots, createdPerson: createdPerson)
        }
    }

    /// Reverts an assignment: restores the faces and removes a person it created, if that person has no faces left.
    /// - Returns: Whether the created person was removed.
    @discardableResult
    func undo(_ result: AssignmentResult) throws -> Bool {
        try writing { db, schema in
            for snapshot in result.snapshots.reversed() {
                guard let current = try db.prepare(
                    "SELECT \(schema.facePerson) FROM ZDETECTEDFACE WHERE Z_PK = ?", snapshot.faceID).makeIterator().next()
                else { throw Error.faceNotFound }
                let currentPersonID = (current[0] as? Int64).map(Int.init)

                // The previous person may be gone, e.g. merged by Photos meanwhile.
                let personID = try snapshot.personID.flatMap { id in
                    try db.scalar("SELECT count(*) FROM ZPERSON WHERE Z_PK = ?", id) as? Int64 == 1 ? id : nil
                }
                var assignments = ["\(schema.facePerson) = ?", "Z_OPT = IFNULL(Z_OPT, 0) + 1"]
                var values: [Binding?] = [personID]
                for (column, value) in [("ZNAMESOURCE", snapshot.nameSource), ("ZCLOUDNAMESOURCE", snapshot.cloudNameSource)]
                where schema.faceColumns.contains(column) {
                    assignments.append("\(column) = ?")
                    values.append(value)
                }
                if schema.faceColumns.contains("ZPERSONBEINGKEYFACE"), let keyPerson = snapshot.keyFaceOfPersonID {
                    // Only if Photos hasn't picked another key face meanwhile.
                    try db.run(
                        "UPDATE ZPERSON SET ZKEYFACE = ?, Z_OPT = IFNULL(Z_OPT, 0) + 1 WHERE Z_PK = ? AND ZKEYFACE IS NULL",
                        snapshot.faceID, keyPerson)
                    if db.changes == 1 {
                        assignments.append("ZPERSONBEINGKEYFACE = ?")
                        values.append(keyPerson)
                    }
                }
                try db.run("UPDATE ZDETECTEDFACE SET \(assignments.joined(separator: ", ")) WHERE Z_PK = ?", values + [snapshot.faceID])
                try bumpVersion(ofPersons: [personID, currentPersonID], db)
            }

            guard result.createdPerson else { return false }
            try db.run(
                "DELETE FROM ZPERSON WHERE Z_PK = ? AND NOT EXISTS (SELECT 1 FROM ZDETECTEDFACE WHERE \(schema.facePerson) = ?)",
                result.person.id, result.person.id)
            return db.changes == 1
        }
    }

    /// Opens a write connection and runs `body` in an immediate transaction.
    private func writing<T>(_ body: (Connection, Schema) throws -> T) throws -> T {
        try mappingErrors {
            let db = try Connection(url.path)
            db.busyTimeout = 5
            // Photos' CoreData triggers keep `ZPERSON.ZFACECOUNT` up to date, but they also call this
            // function to notify CoreData in-process. Only CoreData registers it, so writes outside
            // of Photos fail with "no such function" unless we provide a no-op.
            db.createFunction("NSCoreDataTriggerUpdateAffectedObjectValue", argumentCount: 5, deterministic: false) { _ in nil }
            let schema = try Schema(db)
            var result: T?
            try db.transaction(.immediate) {
                result = try body(db, schema)
            }
            return result!
        }
    }

    private func assignablePerson(_ person: Person, _ db: Connection) throws -> Person {
        let isAssignable = try db.scalar(
            "SELECT count(*) FROM ZPERSON WHERE Z_PK = ? AND ZMERGETARGETPERSON IS NULL AND ZFULLNAME != ''",
            person.id) as? Int64 == 1
        guard isAssignable else { throw Error.personNotAssignable }
        return person
    }

    private func snapshot(of faceID: Int, _ db: Connection, _ schema: Schema) throws -> FaceSnapshot {
        func column(_ name: String) -> String { schema.faceColumns.contains(name) ? name : "NULL" }
        guard let row = try db.prepare(
            "SELECT \(schema.facePerson), \(column("ZNAMESOURCE")), \(column("ZCLOUDNAMESOURCE")) FROM ZDETECTEDFACE WHERE Z_PK = ?",
            faceID).makeIterator().next()
        else { throw Error.faceNotFound }
        let keyFaceOf = try db.scalar("SELECT Z_PK FROM ZPERSON WHERE ZKEYFACE = ? LIMIT 1", faceID) as? Int64
        return FaceSnapshot(
            faceID: faceID,
            personID: (row[0] as? Int64).map(Int.init),
            nameSource: row[1] as? Int64,
            cloudNameSource: row[2] as? Int64,
            keyFaceOfPersonID: keyFaceOf.map(Int.init))
    }

    private func bumpVersion(ofPersons ids: [Int?], _ db: Connection) throws {
        for id in Set(ids.compactMap { $0 }) {
            try db.run("UPDATE ZPERSON SET Z_OPT = IFNULL(Z_OPT, 0) + 1 WHERE Z_PK = ?", id)
        }
    }

    /// The person linked to the contact, created like Photos does when naming a face after a contact.
    private func person(for contact: ContactCard, _ db: Connection, _ schema: Schema) throws -> (Person, created: Bool) {
        if let id = try db.scalar("""
            SELECT Z_PK FROM ZPERSON
            WHERE ZPERSONURI = ? AND ZMERGETARGETPERSON IS NULL AND ZVERIFIEDTYPE = 1 AND ZFULLNAME != ''
            ORDER BY ZFACECOUNT DESC LIMIT 1
            """, contact.id) as? Int64 {
            return (Person(id: Int(id), name: try db.scalar("SELECT ZFULLNAME FROM ZPERSON WHERE Z_PK = ?", id) as? String ?? contact.name,
                           contactIdentifier: contact.id), false)
        }

        // Primary keys come from CoreData's per-entity counter.
        guard let key = try db.prepare("SELECT Z_ENT, Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = 'Person'").makeIterator().next(),
              let entity = key[0] as? Int64, let maxID = key[1] as? Int64,
              ["Z_PK", "Z_ENT", "Z_OPT", "ZFULLNAME", "ZPERSONUUID", "ZVERIFIEDTYPE"].allSatisfy(schema.personColumns.contains)
        else { throw Error.unsupportedSchema }
        let id = maxID + 1
        try db.run("UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_NAME = 'Person'", id)
        let manualOrder = (try db.scalar("SELECT MAX(ZMANUALORDER) FROM ZPERSON") as? Int64 ?? 0) + 1

        // Values as found on named persons Photos created from contacts.
        let values: [(String, Binding?)] = [
            ("Z_PK", id), ("Z_ENT", entity), ("Z_OPT", 1),
            ("ZFULLNAME", contact.name),
            ("ZDISPLAYNAME", contact.givenName.isEmpty ? contact.name : contact.givenName),
            ("ZPERSONUUID", UUID().uuidString),
            ("ZPERSONURI", contact.id),
            ("ZCONTACTMATCHINGDICTIONARY", try contactMatchingDictionary(for: contact).datatypeValue),
            ("ZVERIFIEDTYPE", 1), ("ZCLOUDVERIFIEDTYPE", 1), ("ZTYPE", 0), ("ZDETECTIONTYPE", 1),
            ("ZFACECOUNT", 0), ("ZMANUALORDER", manualOrder),
            ("ZAGETYPE", 0), ("ZGENDERTYPE", 0), ("ZASSETSORTORDER", 0), ("ZCLOUDDELETESTATE", 0),
            ("ZCLOUDDETECTIONTYPE", 0), ("ZCLOUDLOCALSTATE", 0), ("ZINPERSONNAMINGMODEL", 0),
            ("ZKEYFACEPICKSOURCE", 0), ("ZQUESTIONTYPE", 0), ("ZSUGGESTEDFORCLIENTTYPE", 0),
            ("ZISMECONFIDENCE", 0.0), ("ZMERGECANDIDATECONFIDENCE", 0.0)
        ].filter { schema.personColumns.contains($0.0) }
        try db.run(
            "INSERT INTO ZPERSON (\(values.map(\.0).joined(separator: ", "))) VALUES (\(values.map { _ in "?" }.joined(separator: ", ")))",
            values.map(\.1))
        return (Person(id: Int(id), name: contact.name, contactIdentifier: contact.id), true)
    }

    /// The archived dictionary Photos uses to re-identify the contact of a person.
    private func contactMatchingDictionary(for contact: ContactCard) throws -> Data {
        let dictionary = NSMutableDictionary(dictionary: [
            "version": 1,
            "contact-name": contact.name,
            "first-name": contact.givenName,
            "last-name": contact.familyName
        ])
        if !contact.phoneNumbers.isEmpty {
            dictionary["phone-numbers"] = NSMutableArray(array: contact.phoneNumbers)
        }
        if !contact.emailAddresses.isEmpty {
            dictionary["email-addresses"] = NSMutableArray(array: contact.emailAddresses)
        }
        return try NSKeyedArchiver.archivedData(withRootObject: dictionary, requiringSecureCoding: true)
    }
}
