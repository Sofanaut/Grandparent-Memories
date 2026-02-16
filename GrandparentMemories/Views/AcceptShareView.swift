//
//  AcceptShareView.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-08.
//

import Foundation
import SwiftUI
import CloudKit
import CoreData

struct AcceptShareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("isGrandchildMode") private var isGrandchildMode = false
    @AppStorage("isCoGrandparentDevice") private var isCoGrandparentDevice = false
    @AppStorage("isPrimaryDevice") private var isPrimaryDevice = false
    @AppStorage("selectedGrandchildID") private var selectedGrandchildID: String = ""
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    
    private let sharingManager = CloudKitSharingManager.shared
    private let coreDataStack = CoreDataStack.shared
    @State private var shareCode = ""
    @State private var isAccepting = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var isValidInput: Bool {
        let trimmed = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Accept either:
        // 1. 6-digit codes (letters/numbers only)
        // 2. CloudKit share URLs
        if trimmed.count == 6 {
            // 6-digit code
            return trimmed.allSatisfy { $0.isLetter || $0.isNumber }
        } else {
            // CloudKit URL
            return trimmed.contains("icloud.com/share") || trimmed.contains("cloudkit")
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.accent, DesignSystem.Colors.accentLight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text(isGrandchildMode ? "Connect with Your Grandparents" : "Join Family Vault")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text(isGrandchildMode ? "Enter the 6-digit code they sent you" : "Enter the 6-digit code your partner sent you")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // Enter Code or Link
                    VStack(spacing: 16) {
                        Text("Enter Share Code")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        TextField("ABC123", text: $shareCode)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled()
                            .textSelection(.enabled)
                        
                        VStack(spacing: 4) {
                            Text("Enter the 6-digit code they sent you")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    // Connect button
                    Button {
                        Task {
                            await acceptShare()
                        }
                    } label: {
                        HStack {
                            if isAccepting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "link")
                                Text("Connect")
                            }
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValidInput ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(!isValidInput || isAccepting)
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Accept Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Connected!", isPresented: $showSuccess) {
                Button("View Memories") {
                    dismiss()
                }
            } message: {
                Text("You can now access all the special memories your grandparents have shared with you!")
            }
            .alert("Connection Failed", isPresented: $showError) {
                Button("Try Again") {
                    Task {
                        await acceptShare()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Actions
    
    private func acceptShare() async {
        isAccepting = true
        defer { isAccepting = false }
        
        do {
            let trimmed = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
            var shareURL: String
            
            // Check if this is a 6-digit code or a full URL
            let normalizedCode = trimmed.filter { $0.isLetter || $0.isNumber }
            if normalizedCode.count == 6 {
                // Look up the code to get the CloudKit URL
                print("🔍 Looking up share code: \(normalizedCode)")
                shareURL = try await ShareCodeManager.shared.lookupShareURLWithRetry(for: normalizedCode)
                print("✅ Found URL for code: \(shareURL)")
            } else {
                // Use the URL directly
                shareURL = trimmed
            }
            
            // Parse the CloudKit URL
            guard let url = URL(string: shareURL) else {
                print("❌ Invalid URL string: \(shareURL)")
                throw SharingError.noShareURL
            }
            print("✅ Parsed URL successfully: \(url)")
            
            // CRITICAL FIX: Use CKFetchShareMetadataOperation with proper zone-wide share handling
            // Zone-wide shares have no root record, so we must set shouldFetchRootRecord = false
            print("🔄 Fetching share metadata for zone-wide share...")
            
            let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
            let metadata = try await fetchShareMetadata(for: url, in: container)
            
            if metadata.share.publicPermission == .none {
                await MainActor.run {
                    errorMessage = "This code points to a private share. Ask the sender to generate a new Co-Grandparent code."
                    showError = true
                }
                return
            }

            if let ownerID = metadata.ownerIdentity.userRecordID,
               let currentID = try? await container.userRecordID(),
               ownerID == currentID {
                await MainActor.run {
                    errorMessage = "This share was created by the same iCloud account. Please sign in with the other grandparent's iCloud account on this device."
                    showError = true
                }
                return
            }

            // Accept the share using CoreDataStack
            print("🔄 Accepting share invitation...")
            try await coreDataStack.acceptShareInvitations(from: [metadata])
            print("✅ Share accepted successfully!")

            // Trigger a shared-zone scan and wait for the shared grandchild to import
            await coreDataStack.checkForAcceptedShares()
            let importedGrandchild = await coreDataStack.waitForSharedGrandchildImport(timeoutSeconds: 120, pollInterval: 2)
            
            await MainActor.run {
                // Co-grandparent join should not force grandchild mode
                isGrandchildMode = false
                isCoGrandparentDevice = true
                isPrimaryDevice = false

                // Ensure onboarding is completed for this device
                if let profile = userProfiles.first {
                    profile.hasCompletedOnboarding = true
                } else {
                    let newProfile = CDUserProfile(context: viewContext)
                    newProfile.hasCompletedOnboarding = true
                    newProfile.isPremium = false
                    newProfile.freeMemoryCount = 0
                    newProfile.name = "Co-Grandparent"
                }
                viewContext.saveIfNeeded()

                if let importedGrandchild {
                    selectedGrandchildID = importedGrandchild.id?.uuidString ?? ""
                    sharingManager.currentGrandchildId = importedGrandchild.id
                    print("✅ Selected grandchild set to: \(importedGrandchild.name ?? "unknown")")
                } else {
                    print("⚠️ No shared grandchild imported within timeout")
                }

                showSuccess = true
            }
            
            // Re-detect user role now that flag is set
            await sharingManager.detectUserRole()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func fetchShareMetadata(for url: URL, in container: CKContainer) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
            let lock = NSLock()
            var didResume = false
            
            func resumeOnce(_ result: Result<CKShare.Metadata, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }
            
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = false
            operation.qualityOfService = .userInitiated
            
            operation.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let metadata):
                    print("✅ Share metadata fetched successfully")
                    print("   - Record Name: \(metadata.share.recordID.recordName)")
                    print("   - Zone Name: \(metadata.share.recordID.zoneID.zoneName)")
                    print("   - Public Permission: \(metadata.share.publicPermission.rawValue) (0=none, 1=readWrite, 2=readOnly)")
                    
                    if metadata.share.recordID.recordName == CKRecordNameZoneWideShare {
                        print("✅ Confirmed: This is a zone-wide share")
                    } else {
                        print("⚠️ Unexpected: Record name is \(metadata.share.recordID.recordName), expected \(CKRecordNameZoneWideShare)")
                    }
                    
                    if let hierarchicalRoot = metadata.hierarchicalRootRecordID {
                        print("⚠️ Note: Hierarchical root record found: \(hierarchicalRoot)")
                    } else {
                        print("✅ Confirmed: No hierarchical root (correct for zone-wide share)")
                    }
                    
                    resumeOnce(.success(metadata))
                case .failure(let error):
                    print("❌ fetchShareMetadataOperation failed: \(error.localizedDescription)")
                    if let ckError = error as? CKError {
                        print("   - CKError code: \(ckError.code.rawValue)")
                    }
                    resumeOnce(.failure(error))
                }
            }
            
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    resumeOnce(.failure(error))
                }
            }
            
            container.add(operation)
        }
    }
    
    
}

#Preview {
    AcceptShareView()
}
