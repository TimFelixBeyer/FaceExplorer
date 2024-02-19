//
//  PhotoLibraryAPI.swift
//  FaceExplorer
//
//  Created on 11/27/23.

import Foundation
import Photos

struct PhotosLibraryAPI {
    /// Create a new album in Photos.app with chosen photos
    /// using the native Photos API.
    /// This brings about some challenges, as the native API always operates on the system library,
    /// while FaceExplorer can use any .photoslibrary file.
    /// - Parameters:
    ///   - name: the name of the new album
    ///   - localIdentifiers: List of localIdentiers for photos to be added to the album
    func createAlbum(name: String, withLocalIdentifiers localIdentifiers: [String]) async throws {
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        allPhotosOptions.predicate = NSPredicate(format: "localIdentifier in %@", localIdentifiers)
        let phAssetsToAdd = PHAsset.fetchAssets(with: allPhotosOptions)

        // Make an album with the assets
        var newAlbumRequest: PHAssetCollectionChangeRequest?
        var albumLocalIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            newAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            albumLocalIdentifier = newAlbumRequest!.placeholderForCreatedAssetCollection.localIdentifier
        }
        if albumLocalIdentifier == nil {
            throw AlbumCreationError.runtimeError("Failed to create album: \(name)")
        }

        try await PHPhotoLibrary.shared().performChanges {
            let newlyCreatedAlbum = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumLocalIdentifier!], options: nil
            ).firstObject
            let addToAlbumChangeRequest = PHAssetCollectionChangeRequest(for: newlyCreatedAlbum!)
            addToAlbumChangeRequest!.addAssets(phAssetsToAdd)
        }
    }

    enum AlbumCreationError: Error {
        case runtimeError(String)
    }
}
