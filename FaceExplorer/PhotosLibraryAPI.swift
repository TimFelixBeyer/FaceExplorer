import Foundation
import Photos

/// Actions on the Photos library through PhotoKit.
///
/// PhotoKit always operates on the *system* Photos library,
/// while FaceExplorer can browse any `.photoslibrary`.
enum PhotosLibraryAPI {
    enum AlbumCreationError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            "FaceExplorer is not allowed to add photos to your library. You can change this in System Settings › Privacy & Security › Photos."
        }
    }

    /// Creates a new album in Photos containing the given photos.
    static func createAlbum(name: String, photoUUIDs: [UUID]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw AlbumCreationError.accessDenied
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: photoUUIDs.map { "\($0.uuidString)/L0/001" }, options: options)

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name).addAssets(assets)
        }
    }
}
