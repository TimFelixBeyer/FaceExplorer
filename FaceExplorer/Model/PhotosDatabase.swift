import Foundation
import SQLite
import SQLite3

/// Access to the CoreData store of a `.photoslibrary` (`database/Photos.sqlite`); see `PhotosDatabaseWriter.swift` for writes.
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
        case unsupportedSchema

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
            case .unsupportedSchema:
                "This library's database has an unexpected structure, so FaceExplorer can't create persons in it."
            }
        }
    }

    func load(attributes: [FaceAttribute]) throws -> Contents {
        try mappingErrors {
            try load(attributes: attributes, from: Connection(url.path, readonly: true))
        }
    }

    func mappingErrors<T>(_ body: () throws -> T) throws -> T {
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
            let personID = (row[5] as? Int64).map { persons.resolveID(Int($0)) }
            let person = personID.flatMap(persons.person)

            faces.append(Face(
                id: Int(id),
                uuid: uuid,
                photoUUID: photoUUID,
                centerX: double(row[2]),
                centerY: double(row[3]),
                size: double(row[4]),
                personID: personID,
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
struct Schema {
    let faceColumns: Set<String>
    let personColumns: Set<String>
    let additionalAssetAttributeColumns: Set<String>
    let faceAsset: String
    let facePerson: String

    init(_ db: Connection) throws {
        func columns(_ table: String) throws -> Set<String> {
            Set(try db.schema.columnDefinitions(table: table).map(\.name))
        }
        faceColumns = try columns("ZDETECTEDFACE")
        personColumns = try columns("ZPERSON")
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
        let uri: String?
    }
    private var rows: [Int: Row] = [:]

    init(_ db: Connection) throws {
        for row in try db.prepare("SELECT Z_PK, ZFULLNAME, ZFACECOUNT, ZMERGETARGETPERSON, ZPERSONURI FROM ZPERSON") {
            guard let id = row[0] as? Int64 else { continue }
            rows[Int(id)] = Row(
                name: row[1] as? String,
                faceCount: (row[2] as? Int64).map(Int.init) ?? 0,
                mergeTarget: (row[3] as? Int64).map(Int.init),
                uri: row[4] as? String
            )
        }
    }

    /// Follows the merge chain of `id` to the surviving person (or unnamed cluster).
    func resolveID(_ id: Int) -> Int {
        var id = id
        var visited: Set<Int> = []
        while let target = rows[id]?.mergeTarget, rows[target] != nil, visited.insert(id).inserted {
            id = target
        }
        return id
    }

    /// The person with this (resolved) id, if it has a name.
    func person(_ id: Int) -> Person? {
        guard let row = rows[id], let name = row.name, !name.isEmpty else { return nil }
        return Person(id: id, name: name, contactIdentifier: row.uri.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Named persons that have at least one face, sorted by name.
    var namedPersons: [Person] {
        Set(rows.keys.map(resolveID).compactMap(person).filter { (rows[$0.id]?.faceCount ?? 0) > 0 })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
