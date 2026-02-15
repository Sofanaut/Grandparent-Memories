//
//  SceneDelegate.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-11.
//

import UIKit
import CloudKit
import CoreData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    /// This is called when user taps a CloudKit share link
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            await acceptShare(metadata: cloudKitShareMetadata)
        }
    }
    
    private func acceptShare(metadata: CKShare.Metadata) async {
        do {
            try await CoreDataStack.shared.acceptShareInvitations(from: [metadata])

            await MainActor.run {
                // DO NOT set isGrandchildMode here!
                // Co-grandparents should stay in grandparent mode.
                // Grandchild mode is only enabled via:
                //   1. The "I'm a grandchild" button during onboarding
                //   2. The debug toggle in Settings
                
                // Notify app to refresh
                NotificationCenter.default.post(
                    name: NSNotification.Name("RefreshDataAfterShare"),
                    object: nil
                )
            }
        } catch {
            print("❌ Share acceptance failed: \(error.localizedDescription)")
        }
    }
}
