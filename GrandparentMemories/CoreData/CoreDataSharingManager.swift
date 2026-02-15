//
//  CoreDataSharingManager.swift
//  GrandparentMemories
//
//  Manages CloudKit sharing using UICloudSharingController with Core Data
//  This enables real cross-account collaboration
//  Created by Claude on 2026-02-09.
//

import UIKit
import CloudKit
import CoreData
import SwiftUI
import Combine

@MainActor
class CoreDataSharingManager: NSObject, ObservableObject {
    static let shared = CoreDataSharingManager()
    
    @Published var isSharing = false
    @Published var shareError: String?
    @Published var activeShareController: UICloudSharingController?
    
    private let coreDataStack = CoreDataStack.shared
    private let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
    
    private override init() {
        super.init()
    }
    
    // MARK: - Present Share Sheet for Co-Grandparent
    
    /// Present UICloudSharingController to share all family data with another grandparent
    func shareWithCoGrandparent(from viewController: UIViewController) async throws {
        isSharing = true
        defer { isSharing = false }
        
        // IMPORTANT: We share the first Grandchild object, which includes all memories, ancestors, and pets
        // This is better than sharing UserProfile because Grandchild has relationships to all the data
        let fetchRequest: NSFetchRequest<CDGrandchild> = CDGrandchild.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrandchild.name, ascending: true)]
        fetchRequest.fetchLimit = 1
        
        guard let grandchild = try? coreDataStack.viewContext.fetch(fetchRequest).first else {
            throw CoreDataSharingError.noGrandchildFound
        }
        
        guard let grandchildName = grandchild.name else {
            throw CoreDataSharingError.noGrandchildName
        }
        
        // IMPORTANT: Use the preparationHandler initializer for Core Data + CloudKit
        // This is the CORRECT way according to Apple's documentation
        let sharingController = UICloudSharingController { [weak self] controller, prepareCompletionHandler in
            guard let self = self else {
                prepareCompletionHandler(nil, nil, NSError(domain: "SharingError", code: -1))
                return
            }
            
            Task {
                do {
                    // Check if already shared
                    if let existingShare = await self.coreDataStack.fetchShare(for: grandchild) {
                        print("📤 Reusing existing share")
                        prepareCompletionHandler(existingShare, self.container, nil)
                        return
                    }
                    
                    print("📤 Creating new share")
                    let shareTitle = "\(grandchildName)'s Family Vault - Co-Grandparent Access"
                    let (share, container) = try await self.coreDataStack.share(grandchild, title: shareTitle, publicPermission: .readWrite)
                    
                    // CRITICAL: Must call completion handler with share
                    prepareCompletionHandler(share, container, nil)
                } catch {
                    print("❌ Share preparation failed: \(error)")
                    prepareCompletionHandler(nil, nil, error)
                }
            }
        }
        
        sharingController.availablePermissions = [.allowPrivate, .allowReadWrite]
        sharingController.delegate = self
        
        self.activeShareController = sharingController
        viewController.present(sharingController, animated: true)
    }
    
    // MARK: - Present Share Sheet for Grandchild
    
    /// Present UICloudSharingController to share filtered memories with a grandchild
    func shareWithGrandchild(_ grandchild: CDGrandchild, from viewController: UIViewController) async throws {
        isSharing = true
        defer { isSharing = false }
        
        guard let grandchildName = grandchild.name else {
            throw CoreDataSharingError.noGrandchildName
        }
        
        // Create or get existing share for this grandchild
        let shareTitle = "\(grandchildName)'s Memory Vault"
        let (share, container) = try await coreDataStack.share(grandchild, title: shareTitle, publicPermission: .readOnly)
        
        // Configure share as read-only
        share.publicPermission = .readOnly
        
        // Present UICloudSharingController
        let sharingController = UICloudSharingController { [weak self] controller, prepareCompletionHandler in
            guard let self = self else {
                prepareCompletionHandler(nil, nil, NSError(domain: "SharingError", code: -1))
                return
            }
            
            prepareCompletionHandler(share, container, nil)
        }
        
        // Grandchild gets read-only access
        sharingController.availablePermissions = [.allowPrivate, .allowReadOnly]
        sharingController.delegate = self
        
        self.activeShareController = sharingController
        
        viewController.present(sharingController, animated: true)
    }
    
    // MARK: - Stop Sharing
    
    /// Stop sharing with a specific person
    func stopSharing(_ object: NSManagedObject) async throws {
        isSharing = true
        defer { isSharing = false }
        
        try await coreDataStack.stopSharing(object)
    }
    
    // MARK: - Check Share Status
    
    /// Check if an object is currently shared
    func isShared(_ object: NSManagedObject) async -> Bool {
        return await coreDataStack.isShared(object)
    }
    
    /// Get the share for an object (to show participants, etc.)
    func getShare(for object: NSManagedObject) async -> CKShare? {
        return await coreDataStack.fetchShare(for: object)
    }
}

// MARK: - UICloudSharingControllerDelegate

extension CoreDataSharingManager: UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        shareError = error.localizedDescription
        
        Task { @MainActor in
            csc.dismiss(animated: true)
            self.activeShareController = nil
        }
    }
    
    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "Family Memories"
    }
    
    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        // Optionally provide a thumbnail image
        // For now, return nil - could add app icon or family photo
        return nil
    }
    
    func itemType(for csc: UICloudSharingController) -> String? {
        return "com.sofanauts.grandparentmemories.family"
    }
    
    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        // Persist the updated share to Core Data
        if let share = csc.share {
            Task {
                do {
                    try await coreDataStack.persistUpdatedShare(share)
                } catch {
                    // Failed to persist share
                }
                
                await MainActor.run {
                    self.activeShareController = nil
                }
            }
        } else {
            Task { @MainActor in
                self.activeShareController = nil
            }
        }
    }
    
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        // The share has been deleted - Core Data will sync this automatically
        Task { @MainActor in
            self.activeShareController = nil
        }
    }
}

// MARK: - SwiftUI View Representable

struct CloudSharingView: UIViewControllerRepresentable {
    let sharingController: UICloudSharingController
    
    func makeUIViewController(context: Context) -> UICloudSharingController {
        return sharingController
    }
    
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No updates needed
    }
}

// MARK: - SwiftUI Helper Extension

extension View {
    /// Present the CloudKit sharing UI for co-grandparent collaboration
    func shareWithCoGrandparent(isPresented: Binding<Bool>) -> some View {
        self.modifier(CoGrandparentShareModifier(isPresented: isPresented))
    }
    
    /// Present the CloudKit sharing UI for a grandchild
    func shareWithGrandchild(_ grandchild: CDGrandchild?, isPresented: Binding<Bool>) -> some View {
        self.modifier(GrandchildShareModifier(grandchild: grandchild, isPresented: isPresented))
    }
}

// MARK: - View Modifiers

struct CoGrandparentShareModifier: ViewModifier {
    @Binding var isPresented: Bool
    @StateObject private var sharingManager = CoreDataSharingManager.shared
    
    func body(content: Content) -> some View {
        content
            .background(
                SharePresenter(isPresented: $isPresented) {
                    Task {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            
                            // Get the top-most view controller
                            var topController = rootViewController
                            while let presented = topController.presentedViewController {
                                topController = presented
                            }
                            
                            do {
                                try await sharingManager.shareWithCoGrandparent(from: topController)
                            } catch {
                                // Failed to share
                            }
                        }
                    }
                }
            )
    }
}

struct GrandchildShareModifier: ViewModifier {
    let grandchild: CDGrandchild?
    @Binding var isPresented: Bool
    @StateObject private var sharingManager = CoreDataSharingManager.shared
    
    func body(content: Content) -> some View {
        content
            .background(
                SharePresenter(isPresented: $isPresented) {
                    Task {
                        guard let grandchild = grandchild else { return }
                        
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            
                            // Get the top-most view controller
                            var topController = rootViewController
                            while let presented = topController.presentedViewController {
                                topController = presented
                            }
                            
                            do {
                                try await sharingManager.shareWithGrandchild(grandchild, from: topController)
                            } catch {
                                // Failed to share with grandchild
                            }
                        }
                    }
                }
            )
    }
}

struct SharePresenter: UIViewRepresentable {
    @Binding var isPresented: Bool
    let onPresent: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if isPresented {
            onPresent()
            DispatchQueue.main.async {
                isPresented = false
            }
        }
    }
}

// MARK: - Errors

enum CoreDataSharingError: LocalizedError {
    case noProfileFound
    case noGrandchildFound
    case noGrandchildName
    case noViewController
    
    var errorDescription: String? {
        switch self {
        case .noProfileFound:
            return "No user profile found. Please complete onboarding first."
        case .noGrandchildFound:
            return "No grandchild found. Please add a grandchild first before sharing."
        case .noGrandchildName:
            return "Grandchild must have a name to share."
        case .noViewController:
            return "Could not find view controller to present sharing UI."
        }
    }
}
