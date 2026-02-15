//
//  PhotoStorageManager.swift
//  GrandparentMemories
//
//  Photo storage manager that saves photos to disk instead of Core Data
//  Fixes white screen issue by storing only filenames in database
//

import Foundation
import UIKit

class PhotoStorageManager {
    static let shared = PhotoStorageManager()
    
    private init() {
        createPhotosDirectoryIfNeeded()
    }
    
    // Directory where photos are stored
    private var photosDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Photos", isDirectory: true)
    }
    
    // Create photos directory if it doesn't exist
    private func createPhotosDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: photosDirectory.path) {
            try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            print("📸 Created photos directory at: \(photosDirectory.path)")
        }
    }
    
    // Save photo to disk and return filename (synchronous - use for Core Data sync)
    func savePhoto(_ data: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        do {
            // Use atomic write option for better performance
            try data.write(to: fileURL, options: .atomic)
            print("📸 ✅ Saved photo to: \(filename)")
            return filename
        } catch {
            print("📸 ❌ Failed to save photo: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Save photo to disk asynchronously and return filename
    func savePhotoAsync(_ data: Data) async -> String? {
        return await Task.detached(priority: .userInitiated) {
            let filename = "\(UUID().uuidString).jpg"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let photosDir = documentsPath.appendingPathComponent("Photos", isDirectory: true)
            let fileURL = photosDir.appendingPathComponent(filename)
            
            do {
                try data.write(to: fileURL)
                print("📸 ✅ Saved photo to: \(filename)")
                return filename
            } catch {
                print("📸 ❌ Failed to save photo: \(error.localizedDescription)")
                return nil
            }
        }.value
    }
    
    // Load photo from disk using filename
    func loadPhoto(filename: String) -> Data? {
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        do {
            let data = try Data(contentsOf: fileURL)
            print("📸 ✅ Loaded photo: \(filename) (\(data.count) bytes)")
            return data
        } catch {
            print("📸 ❌ Failed to load photo \(filename): \(error.localizedDescription)")
            return nil
        }
    }
    
    // Update existing photo file with new data
    func updatePhoto(_ data: Data, filename: String) {
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL, options: .atomic)
            print("📸 ✅ Updated photo: \(filename)")
        } catch {
            print("📸 ❌ Failed to update photo \(filename): \(error.localizedDescription)")
        }
    }
    
    // Delete photo from disk
    func deletePhoto(filename: String) {
        let fileURL = photosDirectory.appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("📸 ✅ Deleted photo: \(filename)")
        } catch {
            print("📸 ❌ Failed to delete photo \(filename): \(error.localizedDescription)")
        }
    }
    
    // Get UIImage directly from filename
    func loadImage(filename: String) -> UIImage? {
        guard let data = loadPhoto(filename: filename) else {
            return nil
        }
        return UIImage(data: data)
    }
}
