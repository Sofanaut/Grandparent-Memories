//
//  CoreDataBridge.swift
//  GrandparentMemories
//
//  Provides SwiftUI-friendly wrappers for Core Data entities
//  Allows views to work with Core Data using familiar SwiftUI patterns
//  Created by Claude on 2026-02-09.
//

import Foundation
import SwiftUI
import CoreData

// MARK: - FetchRequest Type Aliases

/// Use these instead of @Query from SwiftData
typealias GrandchildrenFetchRequest = FetchRequest<CDGrandchild>
typealias MemoriesFetchRequest = FetchRequest<CDMemory>
typealias AncestorsFetchRequest = FetchRequest<CDAncestor>
typealias ContributorsFetchRequest = FetchRequest<CDContributor>
typealias FamilyPetsFetchRequest = FetchRequest<CDFamilyPet>

// MARK: - Enum Conversions

extension CDMemory {
    var memoryTypeEnum: MemoryType? {
        guard let typeString = memoryType else { return nil }
        return MemoryType(rawValue: typeString)
    }
    
    var privacyEnum: MemoryPrivacy? {
        guard let privacyString = privacy else { return nil }
        return MemoryPrivacy(rawValue: privacyString)
    }
}

extension CDContributor {
    var roleEnum: ContributorRole? {
        guard let roleString = role else { return nil }
        return ContributorRole(rawValue: roleString)
    }
}

extension CDAncestor {
    var lineageEnum: AncestorLineage? {
        guard let lineageString = lineage else { return nil }
        return AncestorLineage(rawValue: lineageString)
    }
    
    var genderEnum: Gender? {
        guard let genderString = gender else { return nil }
        return Gender(rawValue: genderString)
    }
    
    var familyRoleEnum: FamilyRole? {
        guard let roleString = familyRole else { return nil }
        return FamilyRole(rawValue: roleString)
    }
}

extension CDFamilyPet {
    var petTypeEnum: PetType? {
        guard let typeString = petType else { return nil }
        return PetType(rawValue: typeString)
    }
}

// MARK: - Array Conversion Helpers

extension CDGrandchild {
    var memoriesArray: [CDMemory] {
        let set = memories as? Set<CDMemory> ?? []
        return Array(set).sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    var ancestorsArray: [CDAncestor] {
        let set = ancestors as? Set<CDAncestor> ?? []
        return Array(set).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    
    var petsArray: [CDFamilyPet] {
        let set = pets as? Set<CDFamilyPet> ?? []
        return Array(set).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
}

extension CDMemory {
    var grandchildrenArray: [CDGrandchild] {
        let set = grandchildren as? Set<CDGrandchild> ?? []
        return Array(set).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
}

extension CDContributor {
    var memoriesArray: [CDMemory] {
        let set = memories as? Set<CDMemory> ?? []
        return Array(set).sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    var ancestorsArray: [CDAncestor] {
        let set = ancestors as? Set<CDAncestor> ?? []
        return Array(set).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    
    var petsArray: [CDFamilyPet] {
        let set = pets as? Set<CDFamilyPet> ?? []
        return Array(set).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
}

extension CDAncestor {
    var photosArray: [CDAncestorPhoto] {
        let set = photos as? Set<CDAncestorPhoto> ?? []
        return Array(set).sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }
    
    var petsArray: [CDFamilyPet] {
        let set = pets as? Set<CDFamilyPet> ?? []
        return Array(set).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
}

extension CDFamilyPet {
    var photosArray: [CDPetPhoto] {
        let set = photos as? Set<CDPetPhoto> ?? []
        return Array(set).sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }
}

// MARK: - SwiftUI Environment

extension EnvironmentValues {
    var coreDataStack: CoreDataStack {
        return CoreDataStack.shared
    }
}

// MARK: - Helper Functions for Creating Objects

extension NSManagedObjectContext {
    /// Creates a new grandchild
    func createGrandchild(name: String, birthDate: Date) -> CDGrandchild {
        let grandchild = CDGrandchild(context: self)
        grandchild.id = UUID()
        grandchild.name = name
        grandchild.birthDate = birthDate
        return grandchild
    }
    
    /// Creates a new memory
    func createMemory(type: MemoryType, privacy: MemoryPrivacy) -> CDMemory {
        let memory = CDMemory(context: self)
        memory.id = UUID()
        memory.date = Date()
        memory.memoryType = type.rawValue
        memory.privacy = privacy.rawValue
        return memory
    }
    
    /// Creates a new contributor
    func createContributor(name: String, role: ContributorRole, colorHex: String) -> CDContributor {
        let contributor = CDContributor(context: self)
        contributor.id = UUID()
        contributor.name = name
        contributor.role = role.rawValue
        contributor.colorHex = colorHex
        return contributor
    }
    
    /// Creates a new ancestor
    func createAncestor(name: String, relationship: String, generation: Int, lineage: AncestorLineage) -> CDAncestor {
        let ancestor = CDAncestor(context: self)
        ancestor.id = UUID()
        ancestor.name = name
        ancestor.relationship = relationship
        ancestor.generation = Int32(generation)
        ancestor.lineage = lineage.rawValue
        return ancestor
    }
    
    /// Creates a new family pet
    func createFamilyPet(name: String, petType: PetType) -> CDFamilyPet {
        let pet = CDFamilyPet(context: self)
        pet.id = UUID()
        pet.name = name
        pet.petType = petType.rawValue
        return pet
    }
    
    /// Save with error handling
    func saveIfNeeded() {
        guard hasChanges else { return }
        
        do {
            try save()
            print("✅ Context saved successfully")
        } catch {
            let nsError = error as NSError
            print("❌ Failed to save context: \(nsError), \(nsError.userInfo)")
        }
    }
}

// MARK: - FetchRequest Builders

struct FetchRequestBuilders {
    /// Fetch all grandchildren sorted by name
    /// This fetches from BOTH private and shared stores to include shared grandchildren
    static func allGrandchildren() -> NSFetchRequest<CDGrandchild> {
        let request = CDGrandchild.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrandchild.name, ascending: true)]
        
        // CRITICAL: Set affectedStores to nil to query ALL stores (private + shared)
        // By default, fetch requests only query the persistent store coordinator's default store
        // Setting this to nil makes it query all attached stores
        request.affectedStores = nil
        
        return request
    }
    
    /// Fetch all memories sorted by date (newest first)
    /// This fetches from BOTH private and shared stores to include shared memories
    static func allMemories() -> NSFetchRequest<CDMemory> {
        let request = CDMemory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDMemory.date, ascending: false)]
        request.affectedStores = nil  // Query all stores (private + shared)
        return request
    }
    
    /// Fetch memories for a specific grandchild
    static func memories(for grandchild: CDGrandchild) -> NSFetchRequest<CDMemory> {
        let request = CDMemory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDMemory.date, ascending: false)]
        request.predicate = NSPredicate(format: "%@ IN grandchildren", grandchild)
        request.affectedStores = nil  // Query all stores
        return request
    }
    
    /// Fetch released memories for a grandchild
    static func releasedMemories(for grandchild: CDGrandchild) -> NSFetchRequest<CDMemory> {
        let request = CDMemory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDMemory.date, ascending: false)]
        request.predicate = NSPredicate(format: "%@ IN grandchildren AND isReleased == YES", grandchild)
        request.affectedStores = nil  // Query all stores
        return request
    }
    
    /// Fetch all contributors sorted by name
    static func allContributors() -> NSFetchRequest<CDContributor> {
        let request = CDContributor.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDContributor.name, ascending: true)]
        request.affectedStores = nil  // Query all stores
        return request
    }
    
    /// Fetch all ancestors sorted by generation and name
    static func allAncestors() -> NSFetchRequest<CDAncestor> {
        let request = CDAncestor.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDAncestor.generation, ascending: true),
            NSSortDescriptor(keyPath: \CDAncestor.name, ascending: true)
        ]
        request.affectedStores = nil  // Query all stores
        return request
    }
    
    /// Fetch ancestors for a grandchild
    static func ancestors(for grandchild: CDGrandchild) -> NSFetchRequest<CDAncestor> {
        let request = CDAncestor.fetchRequest()
        request.affectedStores = nil  // Query all stores
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDAncestor.generation, ascending: true),
            NSSortDescriptor(keyPath: \CDAncestor.name, ascending: true)
        ]
        request.predicate = NSPredicate(format: "grandchild == %@", grandchild)
        return request
    }
    
    /// Fetch family pets for a grandchild
    static func pets(for grandchild: CDGrandchild) -> NSFetchRequest<CDFamilyPet> {
        let request = CDFamilyPet.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDFamilyPet.name, ascending: true)]
        request.predicate = NSPredicate(format: "grandchild == %@", grandchild)
        return request
    }
    
    /// Fetch the user profile (should be only one)
    static func userProfile() -> NSFetchRequest<CDUserProfile> {
        let request = CDUserProfile.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDUserProfile.name, ascending: true)]
        request.fetchLimit = 1
        request.affectedStores = nil
        return request
    }
    
    /// Fetch all user profiles sorted by name
    static func allUserProfiles() -> NSFetchRequest<CDUserProfile> {
        let request = CDUserProfile.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDUserProfile.name, ascending: true)]
        return request
    }
}

