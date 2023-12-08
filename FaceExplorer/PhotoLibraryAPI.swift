//
//  PhotoLibraryAPI.swift
//  FaceExplorer
//
//  Created on 11/27/23.

import Foundation
import Photos

struct PhotoLibraryAPI {
    private var asdf : Int = 1 {
        willSet {}
    
    }
    private var filterNamed = FilterCategory.all {
        willSet {}
    
    }
    
    /// Create a new album in the Photo App with chosen photos
    /// - Parameters:
    ///   - name: the name of the new album
    ///   - localIdentifiers: List of localIdentiers for photos to be added to the album
    func createAlbum(name: String, withLocalIdentiers localIdentifiers: [String]) async {

        let assetsForLocalIdentifers = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: PHFetchOptions())

        // The user can sort by date or title in the app, but let's preserve the original order when adding to the album
        // PHAsset.fetchAssets does not preserve the order, so reorder the assets to match what was passed in
        var assetMap : Dictionary<String, PHAsset> = [:]
        
        // Make a dictionary of all the asset local identiers mapped to the asset
        assetsForLocalIdentifers.enumerateObjects { asset, count, stop in
            // local identiers can have a "/L00/001" suffix, so trim that out to just use the uuid
            let trimmedAssetLocalIdentifier = asset.localIdentifier.components(separatedBy:"/").first
            assetMap[trimmedAssetLocalIdentifier ?? asset.localIdentifier] = asset;
        }
        
        // Now use the uuid from the passed in localIdentifiers to look up the asset and add them in original order
        let orderedAssets : NSMutableArray = []
        localIdentifiers.forEach {
            if let assetForLocalIdentifier = assetMap[$0] {
                orderedAssets.add(assetForLocalIdentifier)
            }
            else {
                // Sometimes photos doesn't return the asked for identier in the PHAsset list (???)
                print("passed in localidentifier \($0) not returned as asset")
            }
        }
        
        // Make an ablum with the assets
        var newAlbumRequest: PHAssetCollectionChangeRequest? = nil;
        do {
            try await PHPhotoLibrary.shared().performChanges {
                 newAlbumRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            }
        } catch (let error) {
            print("Failed to create album: \(name) \(error.localizedDescription)")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if let albumLocalIdentifer = newAlbumRequest?.placeholderForCreatedAssetCollection.localIdentifier  {
                    let newlyCreatedAlbum = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumLocalIdentifer], options: nil).firstObject
                    let addToAlbumChangeRequest = PHAssetCollectionChangeRequest(for: newlyCreatedAlbum!)
                    addToAlbumChangeRequest!.addAssets(orderedAssets)
                }
                else {
                    print("Failed to create album: \(name)")
                }
            }
        } catch (let error) {
            print("Failed to add assets to album: \(error.localizedDescription)")
        }
    }
}
