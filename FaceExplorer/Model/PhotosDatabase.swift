import Foundation
import SQLite
import SQLite3

/// Read access to the CoreData store of a `.photoslibrary` (`database/Photos.sqlite`).
///
/// Column names differ between Photos schema versions (e.g. `ZPERSON` vs. `ZPERSONFORFACE`),
/// so they are resolved from the schema of the opened database instead of the running macOS version.
struct PhotosDatabase: Sendable {
    let url: URL

    init(libraryURL: URL) {
        url = libraryURL.appending(path: "database/Photos.sqlite")
    }

    struct Contents: Sendable {
        var persons: [Person]
        var faces: [Face]
        /// The requested attributes that exist in this library's schema.
        var attributes: [FaceAttribute]
    }

    enum Error: LocalizedError {
        case accessDenied
        case busy
        case faceNotFound
        case personNotAssignable

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Cannot open the Library due to a permissions error, please try selecting it again."
            case .busy:
                "The Photos library is in use by another process. Please try again in a moment."
            case .faceNotFound:
                "The face no longer exists in the library. Please reload the faces."
            case .personNotAssignable:
                "The person no longer exists or was merged into another person. Please reload the faces."
            }
        }
    }

    func load(attributes: [FaceAttribute]) throws -> Contents {
        try mappingErrors {
            try load(attributes: attributes, from: Connection(url.path, readonly: true))
        }
    }

    /// Writes a consistent copy of the database into the library's `FaceExplorer Backups` folder.
    func backup() throws {
        try mappingErrors {
            let folder = url.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "FaceExplorer Backups")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let timestamp = Date.now.formatted(.iso8601.dateTimeSeparator(.space)).replacing(":", with: "-")
            let backup = folder.appending(path: "Photos \(timestamp).sqlite")
            try Connection(url.path, readonly: true).run("VACUUM INTO ?", backup.path)
        }
    }

    /// Assigns a face to a named person, like confirming a face in Photos does.
    ///
    /// Photos must not be running: it caches the store in memory and would not notice the change
    /// (or overwrite it). The change is not recorded in CoreData's persistent history, so it is
    /// not synced to iCloud Photos.
    func assign(faceID: Int, toPerson personID: Int) throws {
        try mappingErrors {
            let db = try Connection(url.path)
            db.busyTimeout = 5
            // Photos' CoreData triggers keep `ZPERSON.ZFACECOUNT` up to date, but they also call this
            // function to notify CoreData in-process. Only CoreData registers it, so writes outside
            // of Photos fail with "no such function" unless we provide a no-op.
            db.createFunction("NSCoreDataTriggerUpdateAffectedObjectValue", argumentCount: 5, deterministic: false) { _ in nil }
            let schema = try Schema(db)

            try db.transaction(.immediate) {
                let isAssignable = try db.scalar(
                    "SELECT count(*) FROM ZPERSON WHERE Z_PK = ? AND ZMERGETARGETPERSON IS NULL AND ZFULLNAME != ''",
                    personID) as? Int64 == 1
                guard isAssignable else { throw Error.personNotAssignable }
                guard let face = try db.prepare(
                    "SELECT \(schema.facePerson) FROM ZDETECTEDFACE WHERE Z_PK = ?", faceID).makeIterator().next()
                else { throw Error.faceNotFound }
                let previousPersonID = face[0] as? Int64
                guard previousPersonID != Int64(personID) else { return }

                // Mark the face as named by the user, as Photos does for faces confirmed by hand.
                var assignments = ["\(schema.facePerson) = ?", "Z_OPT = IFNULL(Z_OPT, 0) + 1"]
                assignments += ["ZNAMESOURCE", "ZCLOUDNAMESOURCE"].filter(schema.faceColumns.contains).map { "\($0) = 1" }
                if schema.faceColumns.contains("ZPERSONBEINGKEYFACE") {
                    // The face can't stay the representative face of its previous person.
                    assignments.append("ZPERSONBEINGKEYFACE = NULL")
                    try db.run("UPDATE ZPERSON SET ZKEYFACE = NULL WHERE ZKEYFACE = ?", faceID)
                }
                try db.run("UPDATE ZDETECTEDFACE SET \(assignments.joined(separator: ", ")) WHERE Z_PK = ?", personID, faceID)
                // Bump the CoreData version of both persons, whose face counts the triggers changed.
                try db.run("UPDATE ZPERSON SET Z_OPT = IFNULL(Z_OPT, 0) + 1 WHERE Z_PK IN (?, ?)", personID, previousPersonID)
            }
        }
    }

    private func mappingErrors<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as SQLite.Result {
            if case .error(_, let code) = error {
                switch code {
                case SQLITE_AUTH, SQLITE_CANTOPEN, SQLITE_PERM, SQLITE_READONLY: throw Error.accessDenied
                case SQLITE_BUSY, SQLITE_LOCKED: throw Error.busy
                default: break
                }
            }
            throw error
        }
    }

    private func load(attributes: [FaceAttribute], from db: Connection) throws -> Contents {
        let schema = try Schema(db)
        let persons = try PersonIndex(db)

        let attributes = attributes.filter { schema.faceColumns.contains($0.queryName) }
        let timezone = ["ZTIMEZONEOFFSET", "ZINFERREDTIMEZONEOFFSET"]
            .filter(schema.additionalAssetAttributeColumns.contains)
            .map { "aa.\($0)" }
        let timezoneSQL = "COALESCE(\((timezone + ["NULL", "NULL"]).joined(separator: ", ")))"
        let attributeSQL = attributes.map { ", f.\($0.queryName)" }.joined()

        let sql = """
            SELECT f.Z_PK, f.ZUUID, f.ZCENTERX, f.ZCENTERY, f.ZSIZE, f.\(schema.facePerson),
                   a.ZUUID, a.ZDATECREATED, \(timezoneSQL)\(attributeSQL)
            FROM ZDETECTEDFACE f
            JOIN ZASSET a ON a.Z_PK = f.\(schema.faceAsset)
            LEFT JOIN ZADDITIONALASSETATTRIBUTES aa ON aa.ZASSET = a.Z_PK
            WHERE f.ZQUALITY > -1 AND f.ZASSETVISIBLE != 0
            """

        var faces: [Face] = []
        var timeZones: [Int64: TimeZone] = [:]
        for row in try db.prepare(sql) {
            guard let id = row[0] as? Int64,
                  let uuid = (row[1] as? String).flatMap(UUID.init(uuidString:)),
                  let photoUUID = (row[6] as? String).flatMap(UUID.init(uuidString:))
            else { continue }

            var faceAttributes: [String: Face.AttributeValue] = [:]
            for (offset, attribute) in attributes.enumerated() {
                if let raw = (row[9 + offset] as? Int64).map(Int.init) {
                    faceAttributes[attribute.displayName] = .init(raw: raw, label: attribute.mapping[raw] ?? "")
                }
            }
            let person = (row[5] as? Int64).flatMap { persons.resolve(Int($0)) }

            faces.append(Face(
                id: Int(id),
                uuid: uuid,
                photoUUID: photoUUID,
                centerX: double(row[2]),
                centerY: double(row[3]),
                size: double(row[4]),
                name: person?.name ?? "",
                // ZDATECREATED is stored as seconds since 2001-01-01 UTC, sometimes as INTEGER, sometimes as REAL.
                captureDate: Date(timeIntervalSinceReferenceDate: double(row[7])),
                captureTimeZone: (row[8] as? Int64).flatMap { offset in
                    if let zone = timeZones[offset] { return zone }
                    let zone = TimeZone(secondsFromGMT: Int(offset))
                    timeZones[offset] = zone
                    return zone
                } ?? .current,
                attributes: faceAttributes
            ))
        }
        return Contents(persons: persons.namedPersons, faces: faces, attributes: attributes)
    }

    private func double(_ value: Binding?) -> Double {
        switch value {
        case let value as Double: value
        case let value as Int64: Double(value)
        default: 0
        }
    }
}

/// Column names that changed between Photos schema versions.
private struct Schema {
    let faceColumns: Set<String>
    let additionalAssetAttributeColumns: Set<String>
    let faceAsset: String
    let facePerson: String

    init(_ db: Connection) throws {
        func columns(_ table: String) throws -> Set<String> {
            Set(try db.schema.columnDefinitions(table: table).map(\.name))
        }
        faceColumns = try columns("ZDETECTEDFACE")
        additionalAssetAttributeColumns = try columns("ZADDITIONALASSETATTRIBUTES")
        // macOS 14 renamed these relationships.
        faceAsset = faceColumns.contains("ZASSETFORFACE") ? "ZASSETFORFACE" : "ZASSET"
        facePerson = faceColumns.contains("ZPERSONFORFACE") ? "ZPERSONFORFACE" : "ZPERSON"
    }
}

/// All rows of `ZPERSON`, with merge chains (`ZMERGETARGETPERSON`) resolved to the surviving person.
private struct PersonIndex {
    private struct Row {
        let name: String?
        let faceCount: Int
        let mergeTarget: Int?
    }
    private var rows: [Int: Row] = [:]

    init(_ db: Connection) throws {
        for row in try db.prepare("SELECT Z_PK, ZFULLNAME, ZFACECOUNT, ZMERGETARGETPERSON FROM ZPERSON") {
            guard let id = row[0] as? Int64 else { continue }
            rows[Int(id)] = Row(
                name: row[1] as? String,
                faceCount: (row[2] as? Int64).map(Int.init) ?? 0,
                mergeTarget: (row[3] as? Int64).map(Int.init)
            )
        }
    }

    /// Follows the merge chain of `id` and returns the final person, if it has a name.
    func resolve(_ id: Int) -> Person? {
        var id = id
        var visited: Set<Int> = []
        while let target = rows[id]?.mergeTarget, rows[target] != nil, visited.insert(id).inserted {
            id = target
        }
        guard let name = rows[id]?.name, !name.isEmpty else { return nil }
        return Person(id: id, name: name)
    }

    /// Named persons that have at least one face, sorted by name.
    var namedPersons: [Person] {
        Set(rows.keys.compactMap(resolve).filter { (rows[$0.id]?.faceCount ?? 0) > 0 })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
