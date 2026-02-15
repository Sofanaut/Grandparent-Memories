//
//  GrandparentMemoriesApp.swift
//  GrandparentMemories
//
//  Created by Tony Smith on 04/02/2026.
//

import SwiftUI
import CoreData
import CloudKit

@main
struct GrandparentMemoriesApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    
    // Core Data stack
    private let coreDataStack = CoreDataStack.shared
    
    init() {
        // Perform migration if needed
        performMigrationIfNeeded()
        
        // Clean up any CloudKit corruption from previous sessions
        Task {
            do {
                try await CoreDataStack.shared.cleanupCloudKitCorruption()
            } catch {
                print("❌ Cleanup failed: \(error.localizedDescription)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, coreDataStack.viewContext)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    handleUserActivity(userActivity)
                }
                .alert("Share Not Ready", isPresented: $showShareError) {
                    Button("OK") {}
                } message: {
                    Text(shareErrorMessage)
                }
        }
    }
    
    // MARK: - Migration
    
    private func performMigrationIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "HasMigratedToCoreData"
        
        guard !defaults.bool(forKey: migrationKey) else {
            return
        }
        
        // Mark as migrated to prevent further checks
        defaults.set(true, forKey: migrationKey)
    }
    
    // MARK: - Handle Incoming Share URLs and User Activities
    
    private func handleUserActivity(_ userActivity: NSUserActivity) {
        if let webpageURL = userActivity.webpageURL,
           (webpageURL.absoluteString.contains("cloudkit") || webpageURL.absoluteString.contains("icloud")) {
            handleIncomingURL(webpageURL)
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Check if this is a CloudKit share URL
        guard url.absoluteString.contains("cloudkit") || url.absoluteString.contains("icloud") else {
            return
        }
        
        // SceneDelegate handles the primary share acceptance path via
        // windowScene(_:userDidAcceptCloudKitShareWith:). This onOpenURL handler
        // is a fallback for universal links that bypass SceneDelegate.
        Task {
            do {
                let ckContainer = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
                
                // Fetch share metadata using operation (compatible with iOS 15+)
                let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
                    let operation = CKFetchShareMetadataOperation(shareURLs: [url])
                    
                    operation.perShareMetadataResultBlock = { _, result in
                        switch result {
                        case .success(let metadata):
                            continuation.resume(returning: metadata)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    
                    ckContainer.add(operation)
                }
                
                try await coreDataStack.acceptShareInvitations(from: [metadata])
                
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RefreshDataAfterShare"),
                        object: nil
                    )
                }
            } catch {
                await MainActor.run {
                    shareErrorMessage = error.localizedDescription
                    showShareError = true
                }
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }
}
