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

    /// An assignment waiting for the user to confirm writing to the library (asked once per session).
    var pendingAssignment: Assignment?
    private var isWritingConfirmed = false
    /// The library that was backed up before the first write of this session.
    private var backedUpLibrary: URL?
    /// Writes run one after another.
    private var writeTask: Task<Void, Never>?

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
        let face: Face
        let person: Person
    }

    /// Assigns a face to a person in the library database, after a one-time confirmation.
    func assign(_ face: Face, to person: Person) {
        let assignment = Assignment(face: face, person: person)
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

    private func perform(_ assignment: Assignment) {
        guard let libraryURL else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Photos").isEmpty else {
            errorMessage = "Please quit Photos before assigning names. Photos keeps the library in memory and would not see (or could overwrite) the change."
            return
        }
        let database = PhotosDatabase(libraryURL: libraryURL)
        let previousWrite = writeTask
        writeTask = Task {
            await previousWrite?.value
            do {
                if backedUpLibrary != libraryURL {
                    try await Task.detached { try database.backup() }.value
                    backedUpLibrary = libraryURL
                }
                let faceID = assignment.face.id, personID = assignment.person.id
                try await Task.detached { try database.assign(faceID: faceID, toPerson: personID) }.value
                // The library may have been reloaded meanwhile.
                if self.libraryURL == libraryURL, let index = faces.firstIndex(where: { $0.uuid == assignment.face.uuid }) {
                    faces[index].name = assignment.person.name
                }
            } catch {
                displayError(error)
            }
        }
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
        }
    }
}

enum SortOrder: Hashable {
    case date
    case name
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
