//
//  VideoCache.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-08.
//

import Foundation
import CryptoKit

/// High-performance video URL cache to avoid recreating temp files on every render
class VideoCache {
    static let shared = VideoCache()
    
    private var urlCache: [String: URL] = [:]
    private let queue = DispatchQueue(label: "com.grandparentmemories.videocache")
    
    private init() {
        // Defer cleanup to avoid blocking app startup
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.cleanupOldTempFiles()
        }
    }
    
    /// Get a stable URL for video data, creating temp file only once
    func url(for data: Data) -> URL? {
        // Create a stable hash of the data to use as cache key
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        return queue.sync {
            // Return cached URL if exists and file still exists
            if let cachedURL = urlCache[hashString],
               FileManager.default.fileExists(atPath: cachedURL.path) {
                return cachedURL
            }
            
            // Create new temp file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("video_\(hashString).mov")
            
            do {
                // Only write if file doesn't exist
                if !FileManager.default.fileExists(atPath: tempURL.path) {
                    try data.write(to: tempURL)
                }
                urlCache[hashString] = tempURL
                return tempURL
            } catch {
                print("❌ Error caching video: \(error)")
                return nil
            }
        }
    }
    
    /// Clean up temp files older than 24 hours
    private func cleanupOldTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        
        DispatchQueue.global(qos: .utility).async {
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: tempDir,
                    includingPropertiesForKeys: [.creationDateKey],
                    options: .skipsHiddenFiles
                )
                
                let oldFiles = contents.filter { url in
                    guard url.lastPathComponent.hasPrefix("video_"),
                          url.pathExtension == "mov" else {
                        return false
                    }
                    
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let creationDate = attrs[.creationDate] as? Date {
                        return Date().timeIntervalSince(creationDate) > 86400 // 24 hours
                    }
                    return false
                }
                
                for file in oldFiles {
                    try? FileManager.default.removeItem(at: file)
                }
                
                print("🧹 Cleaned up \(oldFiles.count) old video temp files")
            } catch {
                print("⚠️ Error cleaning temp files: \(error)")
            }
        }
    }
    
    func clearCache() {
        queue.sync {
            // Remove all cached temp files
            for url in urlCache.values {
                try? FileManager.default.removeItem(at: url)
            }
            urlCache.removeAll()
        }
    }
}
