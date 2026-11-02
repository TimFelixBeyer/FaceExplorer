import AppKit
import Observation

@Observable @MainActor
final class ModelData {
    /// Named persons, sorted by name.
    private(set) var persons: [Person] = []
    private(set) var faces: [Face] = []
    private(set) var isLoading = false
    /// The currently opened `.photoslibrary`, accessible to the sandbox.
    private(set) var libraryURL: URL?
    /// A user-facing error; the main window shows an alert while this is set.
    var errorMessage: String?

    var sortOrder: SortOrder = .date {
        didSet { sortFaces() }
    }

    /// The attributes available in the opened library.
    private(set) var faceAttributes = FaceAttribute.bundled
    private var loadTask: Task<Void, Never>?

    /// Contacts that aren't persons in the library yet, for creating persons; loaded on first use.
    private(set) var contacts: [ContactCard] = []
    private var contactsTask: Task<Void, Never>?

    /// An assignment waiting for the user to confirm writing to the library (asked once per session).
    var pendingAssignment: Assignment?
    private var isWritingConfirmed = false
    /// The library that was backed up before the first write of this session.
    private var backedUpLibrary: URL?
    /// Writes run one after another.
    private var writeTask: Task<Void, Never>?
    /// What a running write is doing; the main window is blocked while this is set.
    private(set) var writeActivity: WriteActivity?

    enum WriteActivity: Equatable {
        /// Backing up the database, with the approximate fraction done.
        case backingUp(Double)
        case saving
    }

    init() {
        libraryURL = LibraryLocation.restore()
        loadLibrary()
    }

    /// Opens a library the user picked; the open panel grants sandbox access for this session.
    func open(_ url: URL) {
        libraryURL?.stopAccessingSecurityScopedResource()
        libraryURL = url
        do {
            try LibraryLocation.save(url)
        } catch {
            displayError(error)
        }
        loadLibrary()
    }

    func loadLibrary() {
        guard let libraryURL else { return }
        let database = PhotosDatabase(libraryURL: libraryURL)
        let attributes = FaceAttribute.bundled
        loadTask?.cancel()
        isLoading = true

        loadTask = Task {
            let result = await Task.detached { Swift.Result { try database.load(attributes: attributes) } }.value
            guard !Task.isCancelled else { return }
            isLoading = false
            switch result {
            case .success(let contents):
                persons = contents.persons
                contactsTask = nil
                contacts = []
                faces = contents.faces
                faceAttributes = contents.attributes
                sortFaces()
            case .failure(let error):
                persons = []
                faces = []
                displayError(error)
            }
        }
    }

    struct Assignment {
        let faces: [Face]
        let target: AssignmentTarget
        let undoManager: UndoManager?
    }

    /// Assigns faces to a person (or a new person from a contact) in the library database,
    /// after a one-time confirmation. The change can be undone with `undoManager`.
    func assign(_ faces: [Face], to target: AssignmentTarget, undoManager: UndoManager?) {
        guard !faces.isEmpty else { return }
        let assignment = Assignment(faces: faces, target: target, undoManager: undoManager)
        if isWritingConfirmed {
            perform(assignment)
        } else {
            pendingAssignment = assignment
        }
    }

    func confirmPendingAssignment() {
        isWritingConfirmed = true
        if let pendingAssignment {
            self.pendingAssignment = nil
            perform(pendingAssignment)
        }
    }

    /// Filled in once the write of an undoable assignment has finished.
    private final class AssignmentRecord {
        var result: PhotosDatabase.AssignmentResult?
    }

    private func perform(_ assignment: Assignment) {
        guard let libraryURL, isPhotosQuit() else { return }
        let record = AssignmentRecord()
        // Registered right away (not after the asynchronous write), so undo and redo land on the right stacks.
        if let undoManager = assignment.undoManager {
            undoManager.registerUndo(withTarget: self) { model in
                model.undo(assignment, record: record, libraryURL: libraryURL)
            }
            let count = assignment.faces.count
            undoManager.setActionName(count == 1 ? "Assign Name" : "Assign \(count) Faces")
        }
        let faceIDs = assignment.faces.map(\.id)
        let target = assignment.target
        enqueueWrite(to: libraryURL) { database in
            let result = try await Task.detached { try database.assign(faceIDs: faceIDs, to: target) }.value
            record.result = result
            if result.createdPerson {
                self.persons.append(result.person)
                self.persons.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.contacts.removeAll { $0.id == result.person.contactIdentifier }
            }
            self.updateFaces(Dictionary(uniqueKeysWithValues: faceIDs.map { ($0, result.person.id) }))
        }
    }

    private func undo(_ assignment: Assignment, record: AssignmentRecord, libraryURL: URL) {
        guard self.libraryURL == libraryURL, isPhotosQuit() else { return }
        assignment.undoManager?.registerUndo(withTarget: self) { model in
            model.perform(assignment)
        }
        enqueueWrite(to: libraryURL) { database in
            guard let result = record.result else { return }
            let removedPerson = try await Task.detached { try database.undo(result) }.value
            if removedPerson {
                self.persons.removeAll { $0.id == result.person.id }
                if case .contact(let contact) = assignment.target {
                    self.contacts.append(contact)
                    self.contacts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
            }
            self.updateFaces(Dictionary(uniqueKeysWithValues: result.snapshots.map { ($0.faceID, $0.personID) }))
        }
    }

    /// Updates loaded faces after a write, keyed by face id.
    private func updateFaces(_ personIDs: [Face.ID: Int?]) {
        let names = Dictionary(uniqueKeysWithValues: persons.map { ($0.id, $0.name) })
        for index in faces.indices {
            if let personID = personIDs[faces[index].id] {
                faces[index].personID = personID
                faces[index].name = personID.flatMap { names[$0] } ?? ""
            }
        }
    }

    /// Runs a write after the previous ones, backing up the library before its first write this session.
    private func enqueueWrite(to libraryURL: URL, _ write: @escaping (PhotosDatabase) async throws -> Void) {
        let database = PhotosDatabase(libraryURL: libraryURL)
        let previousWrite = writeTask
        writeTask = Task {
            await previousWrite?.value
            defer { writeActivity = nil }
            do {
                if backedUpLibrary != libraryURL {
                    writeActivity = .backingUp(0)
                    try await Task.detached {
                        try database.backup { fraction in
                            Task { @MainActor in
                                if case .backingUp = self.writeActivity {
                                    self.writeActivity = .backingUp(fraction)
                                }
                            }
                        }
                    }.value
                    backedUpLibrary = libraryURL
                }
                // Photos may have been opened while the backup was running; the library may have changed.
                guard self.libraryURL == libraryURL, isPhotosQuit() else { return }
                writeActivity = .saving
                try await write(database)
            } catch {
                displayError(error)
            }
        }
    }

    /// Loads the contacts that aren't persons yet, asking for access the first time.
    func loadContactsIfNeeded() {
        guard contactsTask == nil else { return }
        contactsTask = Task {
            do {
                let linked = Set(persons.compactMap(\.contactIdentifier))
                contacts = try await ContactCard.fetchAll().filter { !linked.contains($0.id) }
            } catch {
                displayError(error)
            }
        }
    }

    private func isPhotosQuit() -> Bool {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Photos").isEmpty else {
            errorMessage = "Please quit Photos before assigning names. Photos keeps the library in memory and would not see (or could overwrite) the change."
            return false
        }
        return true
    }

    func displayError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func sortFaces() {
        switch sortOrder {
        case .date:
            faces.sort { $0.captureDate < $1.captureDate }
        case .name:
            // Named faces first, alphabetically.
            faces.sort { $0.isNamed && (!$1.isNamed || $0.name.localizedStandardCompare($1.name) == .orderedAscending) }
        case .attribute(let name):
            faces.sort { ($0.attributes[name]?.raw ?? -1) < ($1.attributes[name]?.raw ?? -1) }
        case .person:
            // Faces of the same person or cluster next to each other, by date within.
            faces.sort { ($0.personID ?? .max, $0.captureDate) < ($1.personID ?? .max, $1.captureDate) }
        }
    }
}

enum SortOrder: Hashable {
    case date
    case name
    /// Grouped by person or cluster.
    case person
    case attribute(String)
}

enum TagFilterCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case unnamed = "Unnamed"
    case named = "Named"
    var id: Self { self }
}

/// A face attribute predicted by Photos (e.g. age or expression), see `Resources/FaceAttributeQueries.json`.
struct FaceAttribute: Hashable, Codable, Sendable {
    var displayName: String
    /// The `ZDETECTEDFACE` column holding the attribute.
    var queryName: String
    var mapping: [Int: String]

    static let bundled: [FaceAttribute] = {
        guard let url = Bundle.main.url(forResource: "FaceAttributeQueries", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let attributes = try? JSONDecoder().decode([FaceAttribute].self, from: data)
        else {
            fatalError("Couldn't load Resources/FaceAttributeQueries.json from the main bundle.")
        }
        return attributes
    }()
}
