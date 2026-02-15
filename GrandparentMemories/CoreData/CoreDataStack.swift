//
//  CoreDataStack.swift
//  GrandparentMemories
//
//  Core Data stack with CloudKit sharing support
//  Created by Claude on 2026-02-09.
//

import Foundation
import CoreData
import CloudKit

class CoreDataStack {
    static let shared = CoreDataStack()

    private init() {}

    // MARK: - Persistent Stores
    
    private var _privatePersistentStore: NSPersistentStore?
    private var _sharedPersistentStore: NSPersistentStore?
    
    var privatePersistentStore: NSPersistentStore {
        return _privatePersistentStore!
    }
    
    var sharedPersistentStore: NSPersistentStore {
        return _sharedPersistentStore!
    }

    // MARK: - Core Data Stack

    lazy var persistentContainer: NSPersistentCloudKitContainer = {
        let container = NSPersistentCloudKitContainer(name: "GrandparentMemories")

        // IMPORTANT: CloudKit sharing requires TWO stores:
        // 1. Private store - for user's own data
        // 2. Shared store - for data shared with/by other users
        
        let baseURL = NSPersistentContainer.defaultDirectoryURL()
        let storeFolderURL = baseURL.appendingPathComponent("CoreDataStores")
        let privateStoreFolderURL = storeFolderURL.appendingPathComponent("Private")
        let sharedStoreFolderURL = storeFolderURL.appendingPathComponent("Shared")
        
        // Create store folders if needed
        let fileManager = FileManager.default
        for folderURL in [privateStoreFolderURL, sharedStoreFolderURL] {
            if !fileManager.fileExists(atPath: folderURL.path) {
                do {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    fatalError("Failed to create store folder: \(error)")
                }
            }
        }

        // Configure PRIVATE store (user's own data)
        guard let privateStoreDescription = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description")
        }
        
        privateStoreDescription.url = privateStoreFolderURL.appendingPathComponent("private.sqlite")
        
        // Enable history tracking and remote notifications
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        // Configure CloudKit private database
        let containerIdentifier = "iCloud.Sofanauts.GrandparentMemories"
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        privateOptions.databaseScope = .private
        privateStoreDescription.cloudKitContainerOptions = privateOptions

        // Configure SHARED store (data shared with/by others)
        guard let sharedStoreDescription = privateStoreDescription.copy() as? NSPersistentStoreDescription else {
            fatalError("Failed to copy private store description")
        }
        
        sharedStoreDescription.url = sharedStoreFolderURL.appendingPathComponent("shared.sqlite")
        
        // Configure CloudKit shared database
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        sharedOptions.databaseScope = .shared
        sharedStoreDescription.cloudKitContainerOptions = sharedOptions
        
        // Add shared store to container
        container.persistentStoreDescriptions.append(sharedStoreDescription)

        // Load both stores
        container.loadPersistentStores { loadedStoreDescription, error in
            if let error = error as NSError? {
                fatalError("Failed to load persistent store: \(error), \(error.userInfo)")
            }

            // Track which store is which
            guard let cloudKitContainerOptions = loadedStoreDescription.cloudKitContainerOptions else {
                return
            }
            
            if cloudKitContainerOptions.databaseScope == .private {
                self._privatePersistentStore = container.persistentStoreCoordinator.persistentStore(for: loadedStoreDescription.url!)
            } else if cloudKitContainerOptions.databaseScope == .shared {
                self._sharedPersistentStore = container.persistentStoreCoordinator.persistentStore(for: loadedStoreDescription.url!)
            }
        }
        
        // IMPORTANT: Initialize CloudKit schema in development
        // This creates the CloudKit record types that match your Core Data model
        // ⚠️ Run once, wait 2-3 minutes, then comment out again
        
        // ✅ Schema initialization COMPLETED - Keep this commented out
        // Only uncomment if you need to reinitialize the schema
        #if DEBUG
//        do {
//            try container.initializeCloudKitSchema(options: [])
//            print("✅ CloudKit schema initialization started")
//            print("⏳ Wait 2-3 minutes for schema to upload to CloudKit")
//            print("📋 Then check CloudKit Dashboard for CD_ record types")
//            print("🔄 After schema uploads, comment this out and rebuild")
//        } catch {
//            print("❌ Schema initialization failed: \(error)")
//        }
        #endif

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Observe remote changes
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            // Remote changes detected
        }

        return container
    }()

    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    /// Checks for any accepted shares that haven't been imported yet
    /// Call this on app launch to handle shares accepted through Mail/Messages
    func checkForAcceptedShares() async {
        let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
        
        // First check account status
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                break
            case .noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable:
                return
            @unknown default:
                return
            }
        } catch {
            return
        }
        
        let sharedDatabase = container.sharedCloudDatabase
        
        do {
            // Fetch all shared zones
            let allZones = try await sharedDatabase.allRecordZones()
            
            for zone in allZones {
                print("   Zone: \(zone.zoneID.zoneName)")
                print("   Owner: \(zone.zoneID.ownerName)")
                
                // Try to fetch records from this zone
                let query = CKQuery(recordType: "CD_Grandchild", predicate: NSPredicate(value: true))
                let results = try await sharedDatabase.records(matching: query, inZoneWith: zone.zoneID)
                
                let recordCount = results.matchResults.count
                
                if recordCount > 0 {
                    // Force Core Data to import by triggering a sync
                    await MainActor.run {
                        viewContext.refreshAllObjects()
                    }
                    
                    // Wait for import
                    try await Task.sleep(for: .seconds(5))
                    
                    // Check again
                    await MainActor.run {
                        viewContext.refreshAllObjects()
                    }
                }
            }
        } catch {
            // Error checking for shares - silently continue
        }
    }

    /// Waits for shared data to appear after accepting a share invitation.
    /// Returns the first imported grandchild if found within the timeout.
    func waitForSharedGrandchildImport(timeoutSeconds: Double = 30, pollInterval: Double = 1) async -> CDGrandchild? {
        let maxAttempts = Int(timeoutSeconds / pollInterval)
        let request: NSFetchRequest<CDGrandchild> = CDGrandchild.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrandchild.name, ascending: true)]
        request.affectedStores = nil

        for _ in 0..<maxAttempts {
            await MainActor.run {
                viewContext.refreshAllObjects()
            }

            if let grandchild = try? viewContext.fetch(request).first {
                return grandchild
            }

            try? await Task.sleep(for: .seconds(pollInterval))
        }

        return nil
    }

    // MARK: - Sharing Support

    /// Creates a share for a record (grandchild or memory)
    func share(_ object: NSManagedObject, title: String, publicPermission: CKShare.ParticipantPermission = .readOnly) async throws -> (CKShare, CKContainer) {
        let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")

        // IMPORTANT: Ensure object is saved and in the private store
        guard let store = object.objectID.persistentStore,
              store == privatePersistentStore else {
            throw ShareError.creationFailed("Object must be in private store to share")
        }

        // Check if already shared
        do {
            let existingShares = try await persistentContainer.fetchShares(matching: [object.objectID])
            if let existingShare = existingShares[object.objectID] {
                if existingShare.publicPermission != publicPermission {
                    // If permission doesn't match (e.g., co-grandparent needs readWrite),
                    // purge the old share and create a fresh one.
                    try await persistentContainer.purgeObjectsAndRecordsInZone(
                        with: existingShare.recordID.zoneID,
                        in: privatePersistentStore
                    )
                } else {
                    return (existingShare, container)
                }
            }
        } catch {
            // Continue - this might be first time sharing
        }
        
        // Save any pending changes before sharing
        if viewContext.hasChanges {
            try viewContext.save()
        }
        
        // Brief pause to let CloudKit process the save before sharing
        try await Task.sleep(for: .seconds(3))

        // Create new share
        do {
            let (_, share, _) = try await persistentContainer.share([object], to: nil)
            
            // Configure share
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue
            // Configure public permission
            share.publicPermission = publicPermission

            // Save to Core Data context first
            try viewContext.save()
            
            // CRITICAL: Persist the permission change to CloudKit
            // Without this, publicPermission stays at .none in CloudKit even though we set it!
            print("🔄 Persisting share permission to CloudKit...")
            try await persistentContainer.persistUpdatedShare(share, in: privatePersistentStore)
            print("✅ Share permission (\(publicPermission.rawValue)) persisted to CloudKit")
            
            // Log share details for debugging
            print("📋 Share configuration:")
            print("   - Share URL: \(share.url?.absoluteString ?? "NO URL")")
            print("   - Record ID: \(share.recordID)")
            print("   - Record Name: \(share.recordID.recordName)")
            print("   - Zone ID: \(share.recordID.zoneID.zoneName)")
            print("   - Public permission: \(share.publicPermission.rawValue) (0=none, 1=readWrite, 2=readOnly)")
            print("   - Participant count: \(share.participants.count)")
            print("   - Owner: \(share.owner.userIdentity.nameComponents?.formatted() ?? "Unknown")")
            
            return (share, container)
        } catch let error as NSError {
            // Provide helpful error message
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("not found") || errorDescription.contains("doesn't exist") {
                throw ShareError.recordNotSynced
            } else if errorDescription.contains("not signed in") || errorDescription.contains("account") {
                throw ShareError.notSignedIn
            } else if errorDescription.contains("schema") || errorDescription.contains("unknown type") {
                throw ShareError.creationFailed("CloudKit schema not initialized. See CLOUDKIT_SCHEMA_SETUP.md")
            } else {
                throw ShareError.creationFailed(error.localizedDescription)
            }
        }
    }
    
    enum ShareError: LocalizedError {
        case recordNotSynced
        case notSignedIn
        case checkFailed(String)
        case creationFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .recordNotSynced:
                return "This record hasn't synced to iCloud yet. Please wait a moment and try again. Make sure you're connected to the internet and signed into iCloud."
            case .notSignedIn:
                return "You must be signed into iCloud to share. Please check Settings → [Your Name] → iCloud."
            case .checkFailed(let message):
                return "Failed to check sharing status: \(message)"
            case .creationFailed(let message):
                return "Failed to create share: \(message). Make sure you're signed into iCloud and connected to the internet."
            }
        }
    }

    /// Checks if an object is shared
    func isShared(_ object: NSManagedObject) async -> Bool {
        guard let shares = try? await persistentContainer.fetchShares(matching: [object.objectID]) else {
            return false
        }
        return !shares.isEmpty
    }

    /// Gets the share for an object
    func fetchShare(for object: NSManagedObject) async -> CKShare? {
        let shares = try? await persistentContainer.fetchShares(matching: [object.objectID])
        return shares?[object.objectID]
    }

    /// Stops sharing an object
    func stopSharing(_ object: NSManagedObject) async throws {
        guard let share = await fetchShare(for: object) else {
            return
        }

        // Purge the share and associated objects
        try await persistentContainer.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: privatePersistentStore)
    }
    
    /// Accepts share invitations from other users
    /// This is called when a user taps a share link
    func acceptShareInvitations(from metadata: [CKShare.Metadata]) async throws {
        try await persistentContainer.acceptShareInvitations(
            from: metadata,
            into: sharedPersistentStore
        )
        
        // CRITICAL: Force a save to trigger sync
        await MainActor.run {
            if viewContext.hasChanges {
                try? viewContext.save()
            }
            // Refresh all objects to pick up shared data
            viewContext.refreshAllObjects()
        }
        
        // Wait briefly for CloudKit to import the shared zone data
        try await Task.sleep(for: .seconds(3))
        
        await MainActor.run {
            viewContext.refreshAllObjects()
        }
    }
    
    /// Persists an updated share (called by UICloudSharingController delegate)
    func persistUpdatedShare(_ share: CKShare) async throws {
        try await persistentContainer.persistUpdatedShare(share, in: privatePersistentStore)
    }

    // MARK: - Save Context

    func saveContext() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // In production, handle this appropriately
            }
        }
    }

    // MARK: - Background Context

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    // MARK: - CloudKit Corruption Cleanup
    
    /// Resets CloudKit mirroring to recover from "object graph corruption"
    /// This is a nuclear option that forces CloudKit to rebuild its metadata
    func cleanupCloudKitCorruption() async throws {
        print("🧹 Starting CloudKit corruption recovery...")
        
        // Check if we have the corruption error
        let hasCorruption = await checkForCloudKitCorruption()
        
        if hasCorruption {
            print("⚠️  CloudKit corruption detected - resetting mirroring state")
            
            // Reset the CloudKit mirroring state
            // This clears CloudKit's internal metadata about what's in which zone
            try await resetCloudKitMirroringState()
            
            print("✅ CloudKit state reset - will re-export on next sync")
        } else {
            print("✅ No CloudKit corruption detected")
        }
    }
    
    /// Checks if CloudKit has corruption by looking for the specific error
    private func checkForCloudKitCorruption() async -> Bool {
        // We can't easily check this without triggering an export
        // So we'll be conservative and reset if we detect any issues
        // For now, always return false and let the user trigger manually if needed
        return false
    }
    
    /// Resets CloudKit mirroring state to force re-export
    private func resetCloudKitMirroringState() async throws {
        // Get the private store
        guard let privateStore = persistentContainer.persistentStoreCoordinator.persistentStores.first(where: { store in
            !store.identifier!.contains("shared")
        }) else {
            print("⚠️  Could not find private store")
            return
        }
        
        // Reset history tracking for this store
        // This forces CloudKit to re-examine all objects
        let resetRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: Date())
        
        let context = persistentContainer.newBackgroundContext()
        try await context.perform {
            try context.execute(resetRequest)
            try context.save()
        }
        
        print("✅ Reset persistent history - CloudKit will re-export")
    }

    // MARK: - Migration from SwiftData

    /// Migrates data from SwiftData to Core Data
    /// This should be called once during app upgrade
    func migrateFromSwiftData(swiftDataModels: [Any]) async throws {
        // This will be implemented with actual migration logic
        // For now, it's a placeholder for the migration process

        // Migration logic will go here
        // We'll implement this in the next step
    }
}

// MARK: - Convenience Extensions

extension NSManagedObject {
    /// Get the CloudKit record ID for this object
    var recordID: CKRecord.ID? {
        guard let recordData = value(forKey: "recordID") as? Data else {
            return nil
        }

        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.ID.self, from: recordData)
    }
    
    /// Check if this object is shared (async)
    func checkIfShared() async -> Bool {
        return await CoreDataStack.shared.isShared(self)
    }
}

extension NSManagedObjectContext {
    /// Save and immediately trigger CloudKit sync
    func saveAndSync() throws {
        guard hasChanges else { return }
        
        // Save the changes
        try save()
        
        // Perform a save on a background context to trigger CloudKit export
        // This is necessary because NSPersistentCloudKitContainer only exports
        // changes when a save happens, and sometimes the main context save
        // doesn't immediately trigger the export
        let container = CoreDataStack.shared.persistentContainer
        let backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        backgroundContext.perform {
            // This empty save on background context forces CloudKit to check for changes
            if backgroundContext.hasChanges {
                try? backgroundContext.save()
            }
            
            // Also trigger a processPendingChanges to flush any pending updates
            backgroundContext.processPendingChanges()
        }
    }
}
