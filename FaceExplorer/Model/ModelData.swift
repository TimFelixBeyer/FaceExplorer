import Foundation
import Observation

@Observable @MainActor
final class ModelData {
    private(set) var persons: [Person] = [] {
        didSet { personNames = Array(Set(persons.map(\.name))).sorted(using: .localizedStandard) }
    }
    /// Unique person names, sorted, for name suggestions.
    private(set) var personNames: [String] = []
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
