//
//  ShareWithGrandchildView.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-08.
//

import SwiftUI
import CoreData
import CloudKit

struct ShareWithGrandchildView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let grandchild: CDGrandchild
    
    @StateObject private var sharingManager = CoreDataSharingManager.shared
    @State private var showSuccess = false
    @State private var showError = false
    @State private var showSimpleShare = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.accent.opacity(0.1))
                                .frame(width: 120, height: 120)
                            
                            if let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(DesignSystem.Colors.accent)
                            }
                        }
                        
                        Text("Share with \(grandchild.name ?? "Grandchild")")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Text("Give them access to all the special memories you've created for them")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 24)
                    
                    // How it works
                    VStack(alignment: .leading, spacing: 20) {
                        Text("How it works")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        infoRow(
                            icon: "1.circle.fill",
                            title: "Share a 6-digit code",
                            description: "Send them a simple code via text, email, or in person"
                        )
                        
                        infoRow(
                            icon: "2.circle.fill",
                            title: "They Accept",
                            description: "They enter the code and accept your invitation"
                        )
                        
                        infoRow(
                            icon: "3.circle.fill",
                            title: "Memories Sync",
                            description: "All your gifts appear on their device automatically"
                        )
                        
                        infoRow(
                            icon: "checkmark.shield.fill",
                            title: "Private & Secure",
                            description: "Only people you invite can see the memories. Powered by iCloud."
                        )
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    
                    // CloudKit Share Info (if already shared)
                    if grandchild.shareCode != nil {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)
                            
                            Text("Already Shared")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text("Tap 'Share Memories' again to send the link to another device or person")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }
                    
                    // Share button
                    Button {
                        showSimpleShare = true
                    } label: {
                        HStack {
                            if sharingManager.isSharing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "number.circle.fill")
                                Text("Generate Share Code")
                            }
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(sharingManager.isSharing)
                    .padding(.horizontal)
                    
                    // Stop sharing button (if already shared)
                    if grandchild.shareCode != nil {
                        Button(role: .destructive) {
                            Task {
                                await stopSharing()
                            }
                        } label: {
                            Text("Stop Sharing")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Share Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }

            .alert("Share Created!", isPresented: $showSuccess) {
                Button("OK") {}
            } message: {
                Text("IMPORTANT: Tell them to wait at least 1 minute before tapping the link. iCloud needs time to sync the share across accounts.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(sharingManager.shareError ?? "Failed to share memories. Please try again.")
            }
            .sheet(isPresented: $showSimpleShare) {
                SimpleShareView(grandchild: grandchild, shareType: .grandchild)
            }
        }
    }
    
    // MARK: - Info Row
    
    @ViewBuilder
    private func infoRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text(description)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }
    
    // MARK: - Actions
    
    private func stopSharing() async {
        do {
            try await sharingManager.stopSharing(grandchild)
            try? viewContext.save()
        } catch {
            await MainActor.run {
                sharingManager.shareError = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    PreviewHelper()
}

private struct PreviewHelper: View {
    let container: NSPersistentContainer
    let grandchild: CDGrandchild
    
    init() {
        // Create in-memory Core Data stack for preview
        container = NSPersistentContainer(name: "GrandparentMemories")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load preview store: \(error)")
            }
        }
        
        let context = container.viewContext
        grandchild = CDGrandchild(context: context)
        grandchild.id = UUID()
        grandchild.name = "Emma"
        grandchild.birthDate = Date()
    }
    
    var body: some View {
        ShareWithGrandchildView(grandchild: grandchild)
            .environment(\.managedObjectContext, container.viewContext)
    }
}
