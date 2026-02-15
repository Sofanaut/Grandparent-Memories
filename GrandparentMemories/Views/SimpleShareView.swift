//
//  SimpleShareView.swift
//  GrandparentMemories
//
//  Simple share link view - no confusing bubbles, just copy and paste
//

import SwiftUI
import CloudKit
import CoreData

struct SimpleShareView: View {
    let grandchild: CDGrandchild?
    let shareType: ShareType
    @Environment(\.dismiss) private var dismiss
    
    @State private var shareURL: String = ""
    @State private var shareCode: String = ""
    @State private var isGenerating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCodeCopied = false
    
    enum ShareType {
        case coGrandparent
        case grandchild
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)
                    
                    // Icon
                    Image(systemName: shareType == .coGrandparent ? "person.2.fill" : "gift.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(DesignSystem.Colors.primaryGradient)
                    
                    // Title
                    VStack(spacing: 8) {
                        Text(shareType == .coGrandparent ? "Share with Co-Grandparent" : "Share with \(grandchild?.name ?? "Grandchild")")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text("Send this code via Messages, Email, or tell them in person")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 40)
                    
                    // Share Link Box
                    if isGenerating {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Generating share code...")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text("This takes about 45 seconds while iCloud syncs. Please wait...")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    } else if !shareCode.isEmpty {
                        VStack(spacing: 16) {
                            Text("Your Share Code:")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text(shareCode)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .padding()
                                .background(DesignSystem.Colors.backgroundPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .textSelection(.enabled)
                            
                            Text("Send this code via Messages or tell them in person")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            // Copy Code Button
                            Button {
                                UIPasteboard.general.string = shareCode
                                showCodeCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCodeCopied = false
                                }
                            } label: {
                                HStack {
                                    Image(systemName: showCodeCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                    Text(showCodeCopied ? "Copied!" : "Copy Code")
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(showCodeCopied ? Color.green : DesignSystem.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            
                            // Share Code via Messages
                            ShareLink(item: shareCode) {
                                HStack {
                                    Image(systemName: "message.fill")
                                    Text("Send Code via Messages")
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(DesignSystem.Colors.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(24)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        
                        // Instructions
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Next Steps:")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("1.")
                                    Text("Send the code via Messages or tell them in person")
                                        .fontWeight(.semibold)
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("2.")
                                    Text("They tap 'Joining My Partner' in their app")
                                        .fontWeight(.semibold)
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("3.")
                                    Text("They enter the code and tap Accept")
                                        .fontWeight(.semibold)
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Text("📝")
                                    Text("Code expires in 30 days")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                                }
                            }
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .padding(20)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    }
                    else {
                        VStack(spacing: 16) {
                            Text("We couldn't generate a code yet")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text("Please try again in a minute. This page never shows share links.")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button {
                                Task { await generateShareLink() }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Try Again")
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(DesignSystem.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(24)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            await generateShareLink()
        }
    }
    
    private func generateShareLink() async {
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            let coreDataStack = CoreDataStack.shared
            let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
            
            // Get or create share
            let objectToShare: NSManagedObject
            if shareType == .coGrandparent {
                // Share the first grandchild (which includes all family data)
                let fetchRequest: NSFetchRequest<CDGrandchild> = CDGrandchild.fetchRequest()
                fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrandchild.name, ascending: true)]
                fetchRequest.fetchLimit = 1
                
                guard let firstGrandchild = try? coreDataStack.viewContext.fetch(fetchRequest).first else {
                    errorMessage = "Please add a grandchild first before sharing"
                    showError = true
                    return
                }
                objectToShare = firstGrandchild
            } else {
                guard let grandchild = grandchild else {
                    errorMessage = "Grandchild not found"
                    showError = true
                    return
                }
                objectToShare = grandchild
            }
            
            // Check for existing share first
            if let existingShare = await coreDataStack.fetchShare(for: objectToShare) {
                if shareType == .coGrandparent {
                    // For co-grandparent, always create a fresh read-write share
                    // to avoid stale permissions in an existing shared zone.
                    do {
                        try await coreDataStack.persistentContainer.purgeObjectsAndRecordsInZone(
                            with: existingShare.recordID.zoneID,
                            in: coreDataStack.privatePersistentStore
                        )
                        print("🧹 Purged existing co-grandparent share zone")
                    } catch {
                        print("⚠️ Failed to purge existing share zone: \(error.localizedDescription)")
                    }
                } else {
                    // Reuse existing share for grandchild to avoid wiping shared zones.
                    if let url = existingShare.url?.absoluteString {
                        await MainActor.run {
                            shareURL = url
                        }
                        // Still generate a code from the existing share URL.
                        do {
                            let code = try await ShareCodeManager.shared.generateShareCode(for: url)
                            _ = try await ShareCodeManager.shared.lookupShareURLWithRetry(for: code)
                            await MainActor.run {
                                shareCode = code
                            }
                        } catch {
                            await MainActor.run {
                                shareCode = ""
                            }
                        }
                        return
                    }
                }
            }
            
            // Create new share
            let shareTitle = shareType == .coGrandparent ? 
                "Family Vault - Co-Grandparent Access" : 
                "\(grandchild?.name ?? "Grandchild")'s Memories"
            
            let permission: CKShare.ParticipantPermission = (shareType == .coGrandparent) ? .readWrite : .readOnly
            let (share, _) = try await coreDataStack.share(objectToShare, title: shareTitle, publicPermission: permission)
            
            guard let url = share.url?.absoluteString else {
                errorMessage = "Could not generate share link. Please try again."
                showError = true
                return
            }
            
            print("📋 Share details:")
            print("   - URL: \(url)")
            print("   - Public permission: \(share.publicPermission.rawValue)")
            print("   - Can be accessed by anyone: \(share.publicPermission != .none)")
            
            // CRITICAL: Wait for CloudKit to sync the share
            // This prevents "share not found" errors when recipient tries to accept
            // Increased to 2 minutes to ensure full propagation
            print("⏳ Waiting 120 seconds for CloudKit to sync the share...")
            try await Task.sleep(for: .seconds(120))
            print("✅ Share should be ready now")
            
            // Generate a 6-digit code that maps to this URL
            // This avoids the Messages bubble problem!
            var code = ""
            do {
                code = try await ShareCodeManager.shared.generateShareCode(for: url)
                print("✅ Generated share code: \(code)")
                
                // Verify the code is visible in the public database before showing it
                _ = try await ShareCodeManager.shared.lookupShareURLWithRetry(for: code)
                print("✅ Share code verified in public database")
            } catch {
                print("⚠️ Code generation failed: \(error.localizedDescription)")
                print("⚠️ Falling back to URL sharing (will show bubble in Messages)")
                // Fall back to showing URL if code generation fails
                // This can happen if CloudKit public database isn't set up yet
            }
            
            await MainActor.run {
                shareURL = url
                shareCode = code
            }
            
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
