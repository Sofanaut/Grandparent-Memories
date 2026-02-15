//
//  CloudKitSharingManager.swift
//  GrandparentMemories
//
//  Handles user role detection and memory filtering.
//  All actual sharing (creating/accepting shares) is done by CoreDataSharingManager
//  and CoreDataStack via UICloudSharingController + SceneDelegate.
//
//  Created by Claude on 2026-02-08.
//  Simplified 2026-02-11: removed duplicate sharing code.
//

import SwiftUI
import CoreData
import CloudKit
import Combine

/// User role in the app
enum AppUserRole: String, Codable {
    case grandparent  // Can see and edit everything
    case grandchild   // Can only see their released memories (read-only)
}

class CloudKitSharingManager: ObservableObject {
    static let shared = CloudKitSharingManager()
    
    @Published var isSharing = false
    @Published var shareError: String?
    @Published var currentUserRole: AppUserRole = .grandparent
    @Published var currentGrandchildId: UUID?  // Set if user is a grandchild
    
    private init() {
        Task { @MainActor in
            await detectUserRole()
        }
    }
    
    // MARK: - User Role Detection
    
    /// Detects if this user is a grandparent (owner/collaborator) or grandchild (recipient)
    @MainActor
    func detectUserRole() async {
        let isGrandchildMode = UserDefaults.standard.bool(forKey: "isGrandchildMode")
        currentUserRole = isGrandchildMode ? .grandchild : .grandparent
    }

    // MARK: - Data Access Control
    
    /// Determines if a memory should be visible to the current user
    func shouldShowMemory(_ memory: CDMemory, for grandchild: CDGrandchild?) -> Bool {
        switch currentUserRole {
        case .grandparent:
            // Grandparents see everything
            return true
            
        case .grandchild:
            // Grandchildren only see their own released memories
            guard let currentGrandchildId = currentGrandchildId,
                  let grandchildId = grandchild?.id else {
                // If no grandchild ID set, fall back to showing released memories
                return memory.isReleased
            }
            
            // Must be for this grandchild and must be released
            let grandchildrenSet = memory.grandchildren as? Set<CDGrandchild> ?? []
            let isForThisChild = grandchildrenSet.contains(where: { $0.id == currentGrandchildId })
            let isReleased = memory.isReleased
            
            return isForThisChild && isReleased
        }
    }
    
    /// Filters memories based on current user role
    func filterMemories(_ memories: [CDMemory], for grandchild: CDGrandchild?) -> [CDMemory] {
        return memories.filter { shouldShowMemory($0, for: grandchild) }
    }
}

// MARK: - Sharing Errors

enum SharingError: LocalizedError {
    case noPersistentIdentifier
    case noShareFound
    case noMetadata
    case noActiveShare
    case noUserRecordID
    case codeNotImplemented
    case codeNotFound
    case noShareURL
    case shareNotSynced
    case shareNotFoundAfterRetries
    
    var errorDescription: String? {
        switch self {
        case .noPersistentIdentifier:
            return "Could not get persistent identifier for data"
        case .noShareFound:
            return "No share found at this URL"
        case .noMetadata:
            return "Could not fetch share metadata"
        case .noActiveShare:
            return "No active share to stop"
        case .noUserRecordID:
            return "Could not find user record ID"
        case .codeNotImplemented:
            return "Code-based sharing is coming soon. Please use the share link for now."
        case .codeNotFound:
            return "No share found with this code. Please check the code and try again."
        case .noShareURL:
            return "Could not get share URL from CloudKit"
        case .shareNotSynced:
            return "The share is taking longer than expected to sync to iCloud. Please check your internet connection and try again in a moment."
        case .shareNotFoundAfterRetries:
            return "The share was just created and needs a moment to sync. Please wait 30 seconds and try entering the code again."
        }
    }
}
