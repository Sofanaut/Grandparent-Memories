//
//  ImageCache.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-08.
//

import UIKit
import SwiftUI

/// High-performance image cache to avoid repeatedly decoding image data
class ImageCache {
    static let shared = ImageCache()
    
    private let cache = NSCache<NSData, UIImage>()
    
    private init() {
        // Configure cache limits
        cache.countLimit = 50 // Maximum 50 images
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }
    
    func image(for data: Data) -> UIImage? {
        let key = data as NSData
        
        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        // Decode and cache
        if let image = UIImage(data: data) {
            let cost = data.count
            cache.setObject(image, forKey: key, cost: cost)
            return image
        }
        
        return nil
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}

/// SwiftUI wrapper for cached images
struct CachedAsyncImage: View {
    let data: Data?
    
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .task(id: data) {
            guard let data = data else { return }
            // Load on background thread
            let loadedImage = await Task.detached(priority: .userInitiated) {
                ImageCache.shared.image(for: data)
            }.value
            self.image = loadedImage
        }
    }
}
