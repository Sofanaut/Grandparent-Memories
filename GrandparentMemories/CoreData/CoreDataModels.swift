//
//  CoreDataModels.swift
//  GrandparentMemories
//
//  Core Data model extensions and computed properties
//  Bridges Core Data with SwiftData-style interface
//  Created by Claude on 2026-02-09.
//

import Foundation
import CoreData

struct AudioPhotoPayload: Codable {
    let images: [Data]?
    let filenames: [String]?
}

// MARK: - CDGrandchild Extensions

extension CDGrandchild {
    var age: Int {
        guard let birthDate = birthDate else { return 0 }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
        return ageComponents.year ?? 0
    }

    var ageDisplay: String {
        guard let birthDate = birthDate else { return "Unknown age" }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: birthDate, to: Date())

        let years = components.year ?? 0
        let months = components.month ?? 0

        if years == 0 {
            return months == 1 ? "1 month" : "\(months) months"
        } else if years == 1 {
            return "1 year"
        } else {
            return "\(years) years"
        }
    }

    var firstName: String {
        guard let fullName = name else { return "" }
        return fullName.components(separatedBy: " ").first ?? fullName
    }
}

// MARK: - CDMemory Extensions

extension CDMemory {
    var formattedDate: String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    /// Get photo data - tries filename first for fast local loading, falls back to photoData
    var loadedPhotoData: Data? {
        if memoryType == MemoryType.audioPhoto.rawValue {
            if let data = photoData,
               let payload = try? JSONDecoder().decode(AudioPhotoPayload.self, from: data) {
                if let images = payload.images, let first = images.first {
                    return first
                }
                if let filenames = payload.filenames, let first = filenames.first,
                   let firstData = PhotoStorageManager.shared.loadPhoto(filename: first) {
                    return firstData
                }
            }
        }
        // Try filename-based storage first (fast local file access)
        if let filename = photoFilename, let data = PhotoStorageManager.shared.loadPhoto(filename: filename) {
            return data
        }
        // Fall back to photoData (may be slow if Core Data hasn't loaded yet, or for CloudKit synced data)
        if let data = photoData {
            // If we have photoData but no file, save it locally for next time
            if photoFilename == nil, let filename = PhotoStorageManager.shared.savePhoto(data) {
                photoFilename = filename
            }
            return data
        }
        return nil
    }
    
    var audioPhotoImages: [Data] {
        guard memoryType == MemoryType.audioPhoto.rawValue else { return [] }
        if let data = photoData,
           let payload = try? JSONDecoder().decode(AudioPhotoPayload.self, from: data) {
            if let images = payload.images, !images.isEmpty {
                return images
            }
            if let filenames = payload.filenames, !filenames.isEmpty {
                let loaded = filenames.compactMap { PhotoStorageManager.shared.loadPhoto(filename: $0) }
                return loaded
            }
        }
        if let filename = photoFilename,
           let data = PhotoStorageManager.shared.loadPhoto(filename: filename) {
            return [data]
        }
        return []
    }

    var displayPhotoData: Data? {
        if memoryType == MemoryType.audioPhoto.rawValue {
            return audioPhotoImages.first ?? loadedPhotoData
        }
        return loadedPhotoData ?? photoData
    }

    var displayTitle: String {
        // If user provided a custom title, use it
        if let title = title, !title.isEmpty {
            return title
        }

        // Generate descriptive title based on memory type
        guard let memoryType = memoryType else {
            return "Memory"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let dateStr = date.map { formatter.string(from: $0) } ?? ""

        switch memoryType {
        case "quickMoment":
            return "Photo Moment - \(dateStr)"
        case "voiceMemory":
            if let creator = createdBy {
                return "\(creator)'s Voice Message"
            }
            return "Voice Message"
        case "audioPhoto":
            if let creator = createdBy {
                return "\(creator)'s Audio Photo"
            }
            return "Audio Photo"
        case "videoMessage":
            if let creator = createdBy {
                return "\(creator)'s Video"
            }
            return "Video Message"
        case "milestone":
            if let milestoneTitle = milestoneTitle, !milestoneTitle.isEmpty {
                return milestoneTitle
            }
            return "Milestone - \(dateStr)"
        case "letterToFuture":
            if let letterTitle = letterTitle, !letterTitle.isEmpty {
                return letterTitle
            }
            if openWhenAge > 0 {
                return "Letter for Age \(openWhenAge)"
            }
            return "Letter to Future"
        case "familyRecipe":
            if let recipeTitle = recipeTitle, !recipeTitle.isEmpty {
                return recipeTitle
            }
            return "Family Recipe"
        case "storyTime":
            if let creator = createdBy {
                return "\(creator)'s Story"
            }
            return "Story Time - \(dateStr)"
        case "wisdomNote":
            if let creator = createdBy {
                return "Wisdom from \(creator)"
            }
            return "Wisdom Note"
        default:
            return "Memory"
        }
    }
}

// MARK: - CDAncestor Extensions

extension CDAncestor {
    var yearsDisplay: String {
        if birthYear > 0, deathYear > 0 {
            return "\(birthYear) - \(deathYear)"
        } else if birthYear > 0 {
            return "b. \(birthYear)"
        }
        return ""
    }

    var primaryPhoto: Data? {
        if let photoData = photoData {
            return photoData
        }
        let photosArray = photos as? Set<CDAncestorPhoto> ?? []
        return photosArray.first?.photoData
    }
}

// MARK: - CDFamilyPet Extensions

extension CDFamilyPet {
    var yearsDisplay: String {
        if birthYear > 0, passedYear > 0 {
            return "\(birthYear) - \(passedYear)"
        } else if birthYear > 0 {
            return "b. \(birthYear)"
        }
        return ""
    }

    var primaryPhoto: Data? {
        let photosArray = photos as? Set<CDPetPhoto> ?? []
        return photosArray.first?.photoData
    }
}

// MARK: - CDContributor Extensions

extension CDContributor {
    var displayName: String {
        return name ?? role ?? "Unknown"
    }
}

// MARK: - Helper Functions for Creating Objects

extension CoreDataStack {
    /// Creates a new grandchild
    func createGrandchild(name: String, birthDate: Date) -> CDGrandchild {
        let grandchild = CDGrandchild(context: viewContext)
        grandchild.id = UUID()
        grandchild.name = name
        grandchild.birthDate = birthDate
        return grandchild
    }

    /// Creates a new memory
    func createMemory(type: String, privacy: String) -> CDMemory {
        let memory = CDMemory(context: viewContext)
        memory.id = UUID()
        memory.date = Date()
        memory.memoryType = type
        memory.privacy = privacy
        return memory
    }

    /// Creates a new contributor
    func createContributor(name: String, role: String, colorHex: String) -> CDContributor {
        let contributor = CDContributor(context: viewContext)
        contributor.id = UUID()
        contributor.name = name
        contributor.role = role
        contributor.colorHex = colorHex
        return contributor
    }

    /// Creates a new ancestor
    func createAncestor(name: String, relationship: String, generation: Int, lineage: String) -> CDAncestor {
        let ancestor = CDAncestor(context: viewContext)
        ancestor.id = UUID()
        ancestor.name = name
        ancestor.relationship = relationship
        ancestor.generation = Int32(generation)
        ancestor.lineage = lineage
        return ancestor
    }

    /// Creates a new family pet
    func createFamilyPet(name: String, petType: String) -> CDFamilyPet {
        let pet = CDFamilyPet(context: viewContext)
        pet.id = UUID()
        pet.name = name
        pet.petType = petType
        return pet
    }
}
