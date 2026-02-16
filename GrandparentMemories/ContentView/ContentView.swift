//
//  ContentView.swift
//  GrandparentMemories
//
//  Created by Tony Smith on 04/02/2026.
//

import SwiftUI
import CoreData
import PhotosUI
import Photos
import AVFoundation
import AVKit
import CoreLocation
import CloudKit
import UniformTypeIdentifiers

enum UserType {
    case grandparent
    case coGrandparent  // Second grandparent joining via share
    case grandchild
}

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

struct RootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var allMemories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var memories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("isGrandchildMode") private var isGrandchildMode = false
    @AppStorage("autoReleaseLastActiveTimestamp") private var autoReleaseLastActiveTimestamp: Double = 0
    @AppStorage("autoReleaseEnabled") private var autoReleaseEnabled = false
    @State private var hasCheckedForExistingData = false
    @State private var isCheckingForData = false
    @State private var helloQueueTimer: Timer?
    @State private var refreshTimer: Timer?
    @State private var sharePollTimer: Timer?
    
    var body: some View {
        Group {
            if isCheckingForData {
                // Show loading screen while checking for iCloud data
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(DesignSystem.Colors.primaryGradient)
                    
                    VStack(spacing: 8) {
                        Text("Grandparents Gift")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        
                        Text("Checking for your data...")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(.top, 8)
                    
                    // DEBUG: Force fresh install button
                    Button {
                        forceFreshInstall()
                    } label: {
                        Text("🧪 DEBUG: Force Fresh Install")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                    }
                    .padding(.top, 40)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.backgroundPrimary)
            } else if let profile = userProfiles.first, profile.hasCompletedOnboarding {
                // Show grandchild mode if enabled
                if isGrandchildMode {
                    GrandchildGiftView()
                } else {
                    MainAppView()
                }
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            if !isGrandchildMode {
                autoReleaseLastActiveTimestamp = Date().timeIntervalSince1970
                AutoReleaseManager.shared.markActive()
            }
            AutoReleaseManager.shared.runIfNeeded(viewContext: viewContext)
            Task { @MainActor in
                for grandchild in grandchildren {
                    if let id = grandchild.id {
                        HelloQueueManager.shared.runIfNeeded(viewContext: viewContext, grandchildID: id)
                    }
                }
            }
            startHelloQueueTimer()
            startRefreshTimer()
            startSharePollTimer()
            // Only check once per app launch
            guard !hasCheckedForExistingData else { return }
            hasCheckedForExistingData = true
            
            // If no user profile exists, wait briefly for iCloud to sync existing data
            if userProfiles.isEmpty {
                isCheckingForData = true
                
                Task {
                    // Give iCloud more time to sync existing data (especially important for new devices)
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    
                    await MainActor.run {
                        // Check if any data exists (from iCloud sync or CloudKit share)
                        let hasExistingData = !grandchildren.isEmpty || !memories.isEmpty || !contributors.isEmpty
                        
                        if hasExistingData {
                            print("✅ Found existing data - skipping onboarding")
                            // User has existing data - they reinstalled or got new phone
                            // Skip onboarding by marking as complete
                            if let existingProfile = userProfiles.first {
                                existingProfile.hasCompletedOnboarding = true
                            } else {
                                let profile = CDUserProfile(context: viewContext)
                                profile.hasCompletedOnboarding = true
                                profile.isPremium = false
                                profile.freeMemoryCount = 0
                                profile.name = contributors.first?.name ?? "Grandparent"
                            }
                            viewContext.saveIfNeeded()
                        } else {
                            if isGrandchildMode {
                                print("👶 Grandchild mode active - skipping onboarding fallback")
                                if let existingProfile = userProfiles.first {
                                    existingProfile.hasCompletedOnboarding = true
                                } else {
                                    let profile = CDUserProfile(context: viewContext)
                                    profile.hasCompletedOnboarding = true
                                    profile.isPremium = false
                                    profile.freeMemoryCount = 0
                                    profile.name = "Grandchild"
                                }
                                viewContext.saveIfNeeded()
                                isCheckingForData = false
                                return
                            }
                            print("ℹ️ No existing data found - showing onboarding")
                            // No existing data - this is a new user
                            // Create profile with onboarding required
                            if userProfiles.isEmpty {
                                let profile = CDUserProfile(context: viewContext)
                                profile.hasCompletedOnboarding = false
                                profile.isPremium = false
                                profile.freeMemoryCount = 0
                                viewContext.saveIfNeeded()
                            }
                        }
                        
                        // Stop showing loading screen
                        isCheckingForData = false
                    }
                }
            }
        }
        .onDisappear {
            helloQueueTimer?.invalidate()
            helloQueueTimer = nil
            refreshTimer?.invalidate()
            refreshTimer = nil
            sharePollTimer?.invalidate()
            sharePollTimer = nil
        }
    }

    private func startHelloQueueTimer() {
        helloQueueTimer?.invalidate()
        helloQueueTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            for grandchild in grandchildren {
                if let id = grandchild.id {
                    HelloQueueManager.shared.runIfNeeded(viewContext: viewContext, grandchildID: id)
                }
            }
        }
    }
    
    // DEBUG: Force fresh install for testing
    private func forceFreshInstall() {
        print("🧪 DEBUG: Force fresh install")
        
        // Delete all data
        for profile in userProfiles {
            viewContext.delete(profile)
        }
        for grandchild in grandchildren {
            viewContext.delete(grandchild)
        }
        for memory in memories {
            viewContext.delete(memory)
        }
        for contributor in contributors {
            viewContext.delete(contributor)
        }
        
        // Reset UserDefaults
        UserDefaults.standard.set(false, forKey: "isGrandchildMode")
        UserDefaults.standard.set("", forKey: "activeContributorID")
        
        // Save and stop checking
        try? viewContext.save()
        isCheckingForData = false
        hasCheckedForExistingData = false
        
        print("✅ Fresh install forced - restart app")
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            viewContext.refreshAllObjects()
        }
    }

    private func startSharePollTimer() {
        sharePollTimer?.invalidate()
        sharePollTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task {
                await CoreDataStack.shared.checkForAcceptedShares()
                await MainActor.run {
                    viewContext.refreshAllObjects()
                }
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var memories: FetchedResults<CDMemory>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("currentContributorRole") private var currentContributorRole: String = ""
    @AppStorage("primaryContributorRole") private var primaryContributorRole: String = ""
    @AppStorage("isCoGrandparentDevice") private var isCoGrandparentDevice: Bool = false
    @AppStorage("isPrimaryDevice") private var isPrimaryDevice: Bool = false
    @AppStorage("iCloudUserRecordName") private var iCloudUserRecordName: String = ""
    @AppStorage("selectedGrandchildID") private var selectedGrandchildID: String = ""
    @State private var currentPage = 0
    @State private var userType: UserType = .grandparent  // New: Track if grandparent or grandchild
    @State private var grandparentName = ""
    @State private var grandparentRole: ContributorRole = .grandpa
    @State private var hasInitialized = false
    @State private var grandchildName = ""
    @State private var grandchildBirthDate = Date()
    @State private var grandchildPhotoData: Data?
    @State private var grandchildPhotoPickerItem: PhotosPickerItem?
    @State private var showPhotoCropper = false
    @State private var showAcceptShare = false  // For grandchild to accept share
    @State private var grandchildShareCode = ""
    @State private var isAcceptingGrandchildShare = false
    @State private var grandchildShareError: String?
    
    // Co-grandparent share acceptance
    @State private var shareURL = ""
    @State private var isAcceptingShare = false
    @State private var shareAcceptanceError: String?
    
    // Welcome video
    @State private var welcomeVideoRecorder = VideoRecorder()
    @State private var showingCameraPermissionAlert = false
    @State private var cameraPreviewLayer: AVCaptureVideoPreviewLayer?
    @State private var welcomeVideoData: Data?
    
    var body: some View {
        TabView(selection: $currentPage) {
            // Page 0: Role Selection (Grandparent vs Grandchild)
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(DesignSystem.Colors.primaryGradient)
                
                VStack(spacing: 10) {
                    Text("Welcome")
                        .font(DesignSystem.Typography.largeTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Choose the right path to get started")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                
                VStack(spacing: 16) {
                    Button {
                        userType = .grandparent
                        withAnimation { currentPage = 1 }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(DesignSystem.Colors.primaryGradient)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("I'm a Grandparent")
                                    .font(DesignSystem.Typography.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text("Create memories and gifts")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                        }
                        .padding(20)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .clear, radius: 0)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        userType = .grandchild
                        withAnimation { currentPage = 12 }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "gift.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(DesignSystem.Colors.accentGradient)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("I'm a Grandchild")
                                    .font(DesignSystem.Typography.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text("Open gifts from grandparents")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                        }
                        .padding(20)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .clear, radius: 0)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.backgroundPrimary)
            .tag(0)
            
            // Page 1: A Simple Note for Grandparents
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)
                    
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(DesignSystem.Colors.primaryGradient)
                    
                    VStack(spacing: 8) {
                        Text("A note for grandparents")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text("Your voice and your world are the gift.")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        onboardingBullet(icon: "camera.fill", text: "Capture yourself, your home, your daily life")
                        onboardingBullet(icon: "mic.fill", text: "Talk to the camera — even a short hello matters")
                        onboardingBullet(icon: "house.fill", text: "Record places you love and routines you share")
                    }
                    .padding(20)
                    .background(DesignSystem.Colors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    
                    Text("These details are what they’ll treasure most.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button { withAnimation { currentPage = 2 } } label: {
                        Text("Continue").primaryButton()
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    
                    Spacer(minLength: 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.backgroundPrimary)
            .tag(1)
            
            // Page 2: Grandparent Setup Type - First Time or Joining Partner
            VStack(spacing: 32) {
                Spacer(minLength: 60)
                
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(DesignSystem.Colors.primaryGradient)
                
                VStack(spacing: 12) {
                    Text("Setting Up Your Vault")
                        .font(DesignSystem.Typography.largeTitle)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text("Are you the first, or joining your partner?")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                
                VStack(spacing: 16) {
                    // First Time - Create Vault Button
                    Button {
                        userType = .grandparent
                        withAnimation { currentPage = 3 }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 40))
                                .foregroundStyle(DesignSystem.Colors.primaryGradient)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("First Time - Create Vault")
                                    .font(DesignSystem.Typography.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text("Set up your family's memory vault")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.backgroundSecondary)
                        )
                        .shadow(color: .clear, radius: 0, x: 0, y: 0)
                    }
                    .buttonStyle(.plain)
                    
                    // Joining Partner Button
                    Button {
                        userType = .coGrandparent
                        withAnimation { currentPage = 11 }  // Jump to share acceptance page
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(DesignSystem.Colors.accentGradient)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Joining My Partner")
                                    .font(DesignSystem.Typography.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text("They've already created the vault")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.backgroundSecondary)
                        )
                        .shadow(color: .clear, radius: 0, x: 0, y: 0)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.backgroundPrimary)
            .tag(2)
            
            // Feature 1: Capture Memories
            OnboardingFeaturePage(
                icon: "camera.fill",
                gradient: DesignSystem.Colors.primaryGradient,
                title: "Capture Beautiful Memories",
                description: "Create a personalized archive of photos, videos, and voice recordings for each grandchild",
                features: [
                    "📸 Photo memories with stories",
                    "🎥 Personal video messages",
                    "🎤 Voice memos & recordings"
                ],
                currentPage: $currentPage,
                pageNumber: 3,
                nextPage: 4
            )
            .tag(3)
            
            // Feature 2: Welcome Videos
            OnboardingFeaturePage(
                icon: "video.circle.fill",
                gradient: DesignSystem.Colors.accentGradient,
                title: "Record Welcome Videos",
                description: "Create a special welcome message that each grandchild sees when they first open their vault",
                features: [
                    "🎬 Personal welcome for each child",
                    "💝 First thing they see in the app",
                    "🎥 Re-record anytime",
                    "❤️ Make them feel special"
                ],
                currentPage: $currentPage,
                pageNumber: 4,
                nextPage: 5
            )
            .tag(4)
            
            // Feature 3: Schedule & Share
            OnboardingFeaturePage(
                icon: "gift.fill",
                gradient: DesignSystem.Colors.warmGradient,
                title: "Schedule Gift Releases",
                description: "Release memories at special times - birthdays, milestones, or specific ages",
                features: [
                    "🎂 Release on birthdays",
                    "🎓 Unlock at certain ages",
                    "📅 Share immediately or later",
                    "🎁 Surprise them over time"
                ],
                currentPage: $currentPage,
                pageNumber: 5,
                nextPage: 6
            )
            .tag(5)
            
            // Feature 4: Collaborate
            OnboardingFeaturePage(
                icon: "person.2.fill",
                gradient: DesignSystem.Colors.tealGradient,
                title: "Grandma & Grandpa Together",
                description: "Both grandparents contribute from their own devices - each with their own Apple ID",
                features: [
                    "🟦 Grandpa's memories in teal",
                    "🟪 Grandma's memories in purple",
                    "☁️ Automatic iCloud sync",
                    "🔗 Easy invitation link"
                ],
                currentPage: $currentPage,
                pageNumber: 6,
                nextPage: 7  // Go to name entry page
            )
            .tag(6)
            
            // Co-Grandparent Share Acceptance Page
            if userType == .coGrandparent {
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 60)
                        
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(DesignSystem.Colors.primaryGradient)
                        
                        VStack(spacing: 8) {
                            Text("Join Your Partner's Vault")
                                .font(DesignSystem.Typography.largeTitle)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                            
                        Text("Your partner should have sent you a share link or a 6‑digit code")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("How to join:")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 12) {
                                    Text("1️⃣")
                                        .font(.title3)
                                    Text("Your partner will send you a share link or 6‑digit code")
                                        .font(DesignSystem.Typography.body)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                                
                                HStack(alignment: .top, spacing: 12) {
                                    Text("2️⃣")
                                        .font(.title3)
                                    Text("**Copy the link** or **type the code**")
                                        .font(DesignSystem.Typography.body)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                                
                                HStack(alignment: .top, spacing: 12) {
                                    Text("3️⃣")
                                        .font(.title3)
                                    Text("**Paste it below** and tap Accept")
                                        .font(DesignSystem.Typography.body)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                            }
                        }
                        .padding(24)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Enter Share Code or Link")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text("Copy the share link from your partner's message or enter the 6‑digit code:")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            
                            TextField("ABC123 or https://www.icloud.com/share/...", text: $shareURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.allCharacters)
                                .keyboardType(.URL)
                            
                            if let error = shareAcceptanceError {
                                Text("❌ \(error)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(.red)
                            }
                            
                            Button {
                                Task {
                                    await acceptShareFromURL()
                                }
                            } label: {
                                HStack {
                                    if isAcceptingShare {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Accepting Share...")
                                    } else {
                                        Text("Accept Share & Continue")
                                    }
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    shareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : DesignSystem.Colors.accent,
                                    in: RoundedRectangle(cornerRadius: 16)
                                )
                            }
                            .disabled(shareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAcceptingShare)
                        }
                        .padding(24)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.backgroundPrimary)
                .tag(11)
            }

            // Grandchild Share Acceptance Page
            if userType == .grandchild {
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 60)

                        Image(systemName: "gift.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(DesignSystem.Colors.accentGradient)

                        VStack(spacing: 8) {
                            Text("Open Your Grandparents' Vault")
                                .font(DesignSystem.Typography.largeTitle)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .multilineTextAlignment(.center)

                            Text("Enter the 6‑digit code or paste the share link they gave you")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Enter Share Code or Link")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)

                            TextField("ABC123 or https://www.icloud.com/share/...", text: $grandchildShareCode)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .autocapitalization(.allCharacters)
                                .keyboardType(.URL)

                            if let error = grandchildShareError {
                                Text("❌ \(error)")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(.red)
                            }

                            Button {
                                Task {
                                    await acceptGrandchildShareFromCode()
                                }
                            } label: {
                                HStack {
                                    if isAcceptingGrandchildShare {
                                        ProgressView()
                                            .tint(.white)
                                        Text("Connecting...")
                                    } else {
                                        Text("Accept Share & Continue")
                                    }
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    grandchildShareCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : DesignSystem.Colors.accent,
                                    in: RoundedRectangle(cornerRadius: 16)
                                )
                            }
                            .disabled(grandchildShareCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAcceptingGrandchildShare)
                        }
                        .padding(24)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)

                        Spacer(minLength: 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.backgroundPrimary)
                .tag(12)
            }

            // Co-Grandparent Name Page (after accepting share)
            if userType == .coGrandparent {
                VStack(spacing: 32) {
                    Text("What should we call you?")
                        .font(.title.bold())
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(.top, 60)

                    Text("Enter the name you want shown on memories (e.g., Gran, Nana, Grannie Smith)")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    TextField("Your name", text: $grandparentName)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .padding(.horizontal, 40)
                        .submitLabel(.done)
                        .onSubmit {
                            if !grandparentName.isEmpty {
                                Task { await completeCoGrandparentOnboarding() }
                            }
                        }

                    Spacer()

                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        Task { await completeCoGrandparentOnboarding() }
                    } label: {
                        Text("Finish")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(grandparentName.isEmpty ? AnyShapeStyle(Color.gray.gradient) : AnyShapeStyle(DesignSystem.Colors.primaryGradient), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .disabled(grandparentName.isEmpty)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignSystem.Colors.backgroundPrimary)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .tag(13)
            }
            
            // What do they call you?
            VStack(spacing: 32) {
                Text("What do they call you?")
                    .font(.title.bold())
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(.top, 60)
                
                Text(userType == .coGrandparent ?
                     "Enter your name (e.g., Gran, Nana, Peter)" :
                     "What the grandchildren call you")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                TextField(getNamePlaceholder(), text: $grandparentName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .padding(.horizontal, 40)
                    .submitLabel(.done)
                    .onSubmit {
                        if !grandparentName.isEmpty {
                            let nextPage = userType == .coGrandparent ? 11 : 8
                            withAnimation { currentPage = nextPage }
                        }
                    }
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    let nextPage = userType == .coGrandparent ? 11 : 8
                    withAnimation { currentPage = nextPage }
                } label: {
                    Text("Continue")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(grandparentName.isEmpty ? AnyShapeStyle(Color.gray.gradient) : AnyShapeStyle(DesignSystem.Colors.primaryGradient), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .disabled(grandparentName.isEmpty)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.backgroundPrimary)
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .tag(7)
            
            // Tell us about your grandchild
            VStack(spacing: 32) {
                Text("Tell us about your grandchild")
                    .font(.title.bold())
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(.top, 60)
                
                // Photo picker
                PhotosPicker(selection: $grandchildPhotoPickerItem, matching: .images) {
                    if let photoData = grandchildPhotoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(DesignSystem.Colors.primary, lineWidth: 3))
                    } else {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.backgroundTertiary)
                                .frame(width: 120, height: 120)
                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.fill.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(DesignSystem.Colors.primary)
                                Text("Add Photo")
                                    .font(.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .onChange(of: grandchildPhotoPickerItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            print("📸 Original photo loaded: \(data.count) bytes")
                            grandchildPhotoData = data
                            showPhotoCropper = true
                        }
                    }
                }
                .onChange(of: grandchildPhotoData) { oldValue, newValue in
                    if let data = newValue {
                        print("📝 Photo data updated: \(data.count) bytes")
                    }
                }
                .sheet(isPresented: $showPhotoCropper) {
                    if let photoData = grandchildPhotoData, let uiImage = UIImage(data: photoData) {
                        PhotoCropperView(
                            image: uiImage,
                            onSave: { croppedData in
                                print("💾 PhotoCropper onSave called with \(croppedData.count) bytes")
                                grandchildPhotoData = croppedData

                                showPhotoCropper = false
                            },
                            onCancel: {

                                showPhotoCropper = false
                            }
                        )
                    }
                }
                
                TextField("Name", text: $grandchildName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .padding(.horizontal, 40)
                    .submitLabel(.done)
                    .onSubmit {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                DatePicker("Birthday", selection: $grandchildBirthDate, displayedComponents: .date)
                    .padding(.horizontal, 40)
                Spacer()
                
                VStack(spacing: 16) {
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation { currentPage = 9 }
                    } label: {
                        Text("Continue")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(grandchildName.isEmpty ? AnyShapeStyle(Color.gray.gradient) : AnyShapeStyle(DesignSystem.Colors.primaryGradient), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .disabled(grandchildName.isEmpty)
                    
                    Button {
                        // Skip adding grandchild - useful when joining via share or setting up new device
                        completeOnboardingWithoutGrandchild()
                    } label: {
                        Text("Skip - Already joined via share")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .underline()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.backgroundPrimary)
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .tag(8)
            
            // Welcome Video Page
            ScrollView {
                VStack(spacing: 32) {
                    Text("Record a Welcome Message")
                        .font(.title.bold())
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 40)
                        .padding(.top, 60)
                    
                    Text("Say hello to \(grandchildName.isEmpty ? "your grandchild" : grandchildName)! This special video will be the first thing they see.")
                        .font(.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 40)
                    
                    // Camera preview or recorded video preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(DesignSystem.Colors.backgroundSecondary)
                            .frame(height: 400)
                        
                        if let videoURL = welcomeVideoRecorder.videoURL {
                            // Show recorded video preview
                            VideoPlayerView(url: videoURL)
                                .frame(height: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        } else if let previewLayer = cameraPreviewLayer {
                            // Show camera preview
                            CameraPreviewView(previewLayer: previewLayer)
                                .frame(height: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        Task { await welcomeVideoRecorder.switchCamera() }
                                    } label: {
                                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                            .padding(10)
                                            .background(Color.black.opacity(0.6), in: Circle())
                                    }
                                    .padding(12)
                                }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                Text("Camera preview will appear here")
                                    .font(.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    
                    // Recording controls
                    HStack(spacing: 20) {
                        if welcomeVideoRecorder.videoURL != nil {
                            // Show re-record button
                            Button {
                                welcomeVideoRecorder.deleteRecording()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Re-record")
                                }
                                .font(.headline)
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(DesignSystem.Colors.accent.opacity(0.1), in: Capsule())
                            }
                        } else {
                            // Show record button
                            Button {
                                if welcomeVideoRecorder.isRecording {
                                    welcomeVideoRecorder.stopRecording()
                                } else {
                                    welcomeVideoRecorder.startRecording()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(welcomeVideoRecorder.isRecording ? Color.red : DesignSystem.Colors.accent)
                                        .frame(width: 70, height: 70)
                                    
                                    if welcomeVideoRecorder.isRecording {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(.white)
                                            .frame(width: 28, height: 28)
                                    } else {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 60, height: 60)
                                    }
                                }
                            }
                            
                            if welcomeVideoRecorder.isRecording {
                                Text(welcomeVideoRecorder.formattedDuration)
                                    .font(.title2)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    
                    // Helper text
                    Text("You can record or update this later in More → Welcome Videos")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                    
                    // Continue buttons
                    VStack(spacing: 12) {
                        // Continue with video button
                        Button {
                            saveWelcomeVideo()
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation { currentPage = 10 }
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(welcomeVideoRecorder.videoURL != nil ? AnyShapeStyle(DesignSystem.Colors.primaryGradient) : AnyShapeStyle(Color.gray.gradient), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        }
                        .disabled(welcomeVideoRecorder.videoURL == nil)
                        
                        // Skip button
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation { currentPage = 10 }
                        } label: {
                            Text("Skip for now")
                                .font(.headline)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.backgroundPrimary)
            .tag(9)
            .task {
                // Setup camera when this page appears
                await setupWelcomeVideoCamera()
            }
            .onDisappear {
                Task {
                    await welcomeVideoRecorder.stopSession()
                }
            }
            
            // Paywall Page
            PaywallView(source: .onboarding) {
                // If grandchild info is filled in, complete full onboarding
                // Otherwise, complete without grandchild (e.g., if user skipped)
                if !grandchildName.isEmpty {
                    completeOnboarding()
                } else {
                    completeOnboardingWithoutGrandchild()
                }
            }
            .tag(10)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onAppear {
            // Disable swipe gestures on the TabView's underlying UIScrollView
            UIScrollView.appearance().isScrollEnabled = false
        }
        .onDisappear {
            // Re-enable scroll for other views
            UIScrollView.appearance().isScrollEnabled = true
        }
        .onChange(of: currentPage) { _, _ in
            // Dismiss keyboard when changing pages
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $showAcceptShare) {
            AcceptShareView()
                .interactiveDismissDisabled()
        }
    }
    

    
    private func completeOnboarding() {
        print("🚀 Starting completeOnboarding()")
        print("   Grandchild name: \(grandchildName)")
        print("   Grandchild birth date: \(grandchildBirthDate)")
        
        if let profile = userProfiles.first {
            profile.name = grandparentName
            profile.hasCompletedOnboarding = true
            print("   ✅ Updated existing profile")
        } else {
            let newProfile = CDUserProfile(context: viewContext)
            newProfile.name = grandparentName
            newProfile.hasCompletedOnboarding = true
            newProfile.isPremium = false
            newProfile.freeMemoryCount = 0
            print("   ✅ Created new profile")
        }
        
        // Delete any existing contributors to start fresh
        for contributor in contributors {
            viewContext.delete(contributor)
        }
        
        // Create contributors - use custom name for the selected role
        let primaryContributor: CDContributor
        let secondaryContributor: CDContributor
        
        if grandparentRole == .grandpa {
            primaryContributor = viewContext.createContributor(name: grandparentName, role: .grandpa, colorHex: ContributorRole.grandpa.defaultColor)
            secondaryContributor = viewContext.createContributor(name: "Grandma", role: .grandma, colorHex: ContributorRole.grandma.defaultColor)
        } else {
            primaryContributor = viewContext.createContributor(name: grandparentName, role: .grandma, colorHex: ContributorRole.grandma.defaultColor)
            secondaryContributor = viewContext.createContributor(name: "Grandpa", role: .grandpa, colorHex: ContributorRole.grandpa.defaultColor)
        }
        print("   ✅ Created contributors")
        
        // Set the primary contributor as active
        activeContributorID = primaryContributor.id?.uuidString ?? ""
        currentContributorRole = grandparentRole.rawValue
        primaryContributorRole = grandparentRole.rawValue
        isPrimaryDevice = true
        
        // Create grandchild
        let grandchild = viewContext.createGrandchild(name: grandchildName, birthDate: grandchildBirthDate)
        grandchild.photoData = grandchildPhotoData
        grandchild.familyId = ""
        grandchild.familyLink = nil
        
        print("   👶 Created grandchild:")
        print("      - Name: \(grandchild.name ?? "nil")")
        print("      - ID: \(grandchild.id?.uuidString ?? "nil")")
        print("      - Birth date: \(grandchild.birthDate?.description ?? "nil")")
        print("      - Photo data: \(grandchildPhotoData?.count ?? 0) bytes")
        print("      - Object ID: \(grandchild.objectID)")
        
        // Create welcome video memory if recorded
        if let welcomeVideoData = welcomeVideoData, let videoURL = welcomeVideoRecorder.videoURL {
            let welcomeMemory = viewContext.createMemory(type: .videoMessage, privacy: .maybeDecide)
            welcomeMemory.videoData = welcomeVideoData
            welcomeMemory.createdBy = grandparentName
            welcomeMemory.isWelcomeVideo = true
            welcomeMemory.isReleased = true  // Make it available immediately
            welcomeMemory.contributor = primaryContributor
            welcomeMemory.addToGrandchildren(grandchild)
            
            // Generate and set thumbnail
            if let thumbnailData = generateVideoThumbnail(from: videoURL) {
                welcomeMemory.videoThumbnailData = thumbnailData
            }
            
            print("   📹 Created welcome video memory")
        }
        
        // SAVE TO CORE DATA
        print("   💾 About to save context...")
        print("   Context has changes: \(viewContext.hasChanges)")
        
        do {
            try viewContext.save()
            print("   ✅ Context saved successfully!")
            
            // Verify the grandchild was saved by fetching
            let fetchRequest = CDGrandchild.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrandchild.name, ascending: true)]
            let savedGrandchildren = try viewContext.fetch(fetchRequest)
            print("   🔍 Verification: Fetched \(savedGrandchildren.count) grandchildren from database")
            for (index, child) in savedGrandchildren.enumerated() {
                print("      [\(index)] \(child.name ?? "unnamed") (ID: \(child.id?.uuidString ?? "none"))")
            }
        } catch {
            print("   ❌ FAILED TO SAVE: \(error)")
            let nsError = error as NSError
            print("   Error details: \(nsError.userInfo)")
        }
        
        // Set the primary contributor (the one who went through onboarding) as active
        activeContributorID = primaryContributor.id?.uuidString ?? ""
        currentContributorRole = grandparentRole.rawValue
        primaryContributorRole = grandparentRole.rawValue
        isPrimaryDevice = true


    }
    
    private func completeOnboardingWithoutGrandchild() {
        // For users joining via share or setting up a new device
        if let profile = userProfiles.first {
            profile.name = grandparentName.isEmpty ? "Grandparent" : grandparentName
            profile.hasCompletedOnboarding = true
        } else {
            let newProfile = CDUserProfile(context: viewContext)
            newProfile.name = grandparentName.isEmpty ? "Grandparent" : grandparentName
            newProfile.hasCompletedOnboarding = true
            newProfile.isPremium = false
            newProfile.freeMemoryCount = 0
        }
        
        // Create or update contributors
        if contributors.isEmpty {
            // Create default contributors
            let primaryContributor: CDContributor
            let secondaryContributor: CDContributor
            
            if grandparentRole == .grandpa {
                primaryContributor = viewContext.createContributor(
                    name: grandparentName.isEmpty ? "Grandpa" : grandparentName,
                    role: .grandpa,
                    colorHex: ContributorRole.grandpa.defaultColor
                )
                secondaryContributor = viewContext.createContributor(
                    name: "Grandma",
                    role: .grandma,
                    colorHex: ContributorRole.grandma.defaultColor
                )
            } else {
                primaryContributor = viewContext.createContributor(
                    name: grandparentName.isEmpty ? "Grandma" : grandparentName,
                    role: .grandma,
                    colorHex: ContributorRole.grandma.defaultColor
                )
                secondaryContributor = viewContext.createContributor(
                    name: "Grandpa",
                    role: .grandpa,
                    colorHex: ContributorRole.grandpa.defaultColor
                )
            }
            
            activeContributorID = primaryContributor.id?.uuidString ?? ""
        }
        if currentContributorRole.isEmpty {
            currentContributorRole = grandparentRole.rawValue
        }
        if primaryContributorRole.isEmpty {
            primaryContributorRole = grandparentRole.rawValue
        }
        isPrimaryDevice = true
        
        viewContext.saveIfNeeded()

        
        // Force multiple saves with delays to ensure Core Data propagates the change
        Task { @MainActor in
            for i in 1...3 {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
                if let profile = userProfiles.first {
                    profile.hasCompletedOnboarding = true
                    viewContext.saveIfNeeded()

                }
            }
        }
    }
    
    private func completeCoGrandparentOnboarding() async {
        // For co-grandparents joining via share link
        // They don't create a grandchild - they wait for the share to sync
        
        await MainActor.run {
            let coGrandparentName = grandparentName.isEmpty ? "Co-Grandparent" : grandparentName
            
            if let profile = userProfiles.first {
                profile.name = coGrandparentName
                profile.hasCompletedOnboarding = true
            } else {
                let newProfile = CDUserProfile(context: viewContext)
                newProfile.name = coGrandparentName
                newProfile.hasCompletedOnboarding = true
                newProfile.isPremium = false
                newProfile.freeMemoryCount = 0
            }
            
            // Ensure a grandma contributor exists and set it as active on this device
            if let grandmaContributor = contributors.first(where: { $0.role == ContributorRole.grandma.rawValue }) {
                grandmaContributor.name = coGrandparentName
                grandmaContributor.colorHex = ContributorRole.grandma.defaultColor
                activeContributorID = grandmaContributor.id?.uuidString ?? ""
            } else if let grandpaContributor = contributors.first(where: { $0.role == ContributorRole.grandpa.rawValue }) {
                // Create grandma if only grandpa exists
                let newGrandma = viewContext.createContributor(
                    name: coGrandparentName,
                    role: .grandma,
                    colorHex: ContributorRole.grandma.defaultColor
                )
                activeContributorID = newGrandma.id?.uuidString ?? ""
            } else if contributors.isEmpty {
                let contributor = viewContext.createContributor(
                    name: coGrandparentName,
                    role: .grandma,
                    colorHex: ContributorRole.grandma.defaultColor
                )
                activeContributorID = contributor.id?.uuidString ?? ""
            }
            currentContributorRole = ContributorRole.grandma.rawValue
            primaryContributorRole = ContributorRole.grandma.rawValue
            isCoGrandparentDevice = true
            isPrimaryDevice = false

            viewContext.saveIfNeeded()

        }
    }
    
    private func acceptShareFromURL() async {
        await MainActor.run {
            isAcceptingShare = true
            shareAcceptanceError = nil
        }
        
        defer {
            Task { @MainActor in
                isAcceptingShare = false
            }
        }
        
        let trimmed = shareURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = trimmed.filter { $0.isLetter || $0.isNumber }
        var shareLink: String
        
        do {
            if normalizedCode.count == 6 {
                shareLink = try await ShareCodeManager.shared.lookupShareURLWithRetry(for: normalizedCode)
            } else {
                shareLink = trimmed
            }
        } catch {
            await MainActor.run {
                shareAcceptanceError = error.localizedDescription
            }
            return
        }
        
        guard let url = URL(string: shareLink) else {
            await MainActor.run {
                shareAcceptanceError = "Invalid share link or code"
            }
            return
        }
        
        let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
        
        do {
            // Fetch share metadata (zone-wide share)
            let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
                let operation = CKFetchShareMetadataOperation(shareURLs: [url])
                operation.shouldFetchRootRecord = false
                operation.perShareMetadataResultBlock = { _, result in
                    switch result {
                    case .success(let metadata):
                        continuation.resume(returning: metadata)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                container.add(operation)
            }

            print("   Owner: \(metadata.ownerIdentity.userRecordID?.recordName ?? "unknown")")
            print("   Root record: \(metadata.rootRecordID.recordName)")
            print("   Public permission: \(metadata.share.publicPermission.rawValue) (0=none, 1=readWrite, 2=readOnly)")

            if metadata.share.publicPermission == .none {
                await MainActor.run {
                    shareAcceptanceError = "This code points to a private share. Ask the sender to generate a new Co-Grandparent code."
                }
                return
            }

            if let ownerID = metadata.ownerIdentity.userRecordID,
               let currentID = try? await container.userRecordID(),
               ownerID == currentID {
                await MainActor.run {
                    shareAcceptanceError = "This share was created by the same iCloud account. Please sign in with the other grandparent's iCloud account on this device."
                }
                return
            }
            
            // Accept the share
            let coreDataStack = CoreDataStack.shared
            try await coreDataStack.acceptShareInvitations(from: [metadata])

            // Wait for the shared grandchild to import (up to 2 minutes)
            let importedGrandchild = await coreDataStack.waitForSharedGrandchildImport(timeoutSeconds: 120, pollInterval: 2)

            // Ask for co-grandparent name after acceptance
            await MainActor.run {
                if let importedGrandchild {
                    selectedGrandchildID = importedGrandchild.id?.uuidString ?? ""
                    CloudKitSharingManager.shared.currentGrandchildId = importedGrandchild.id
                }
                isCoGrandparentDevice = true
                isPrimaryDevice = false
                withAnimation { currentPage = 13 }
            }
            


            
            // Wait for sync
            try await Task.sleep(for: .seconds(10))
            
            await MainActor.run {
                viewContext.refreshAllObjects()
            }
            
        } catch {

            await MainActor.run {
                shareAcceptanceError = error.localizedDescription
            }
        }
    }

    private func acceptGrandchildShareFromCode() async {
        await MainActor.run {
            isAcceptingGrandchildShare = true
            grandchildShareError = nil
        }

        defer {
            Task { @MainActor in
                isAcceptingGrandchildShare = false
            }
        }

        let trimmed = grandchildShareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCode = trimmed.filter { $0.isLetter || $0.isNumber }
        var shareLink: String

        do {
            if normalizedCode.count == 6 {
                shareLink = try await ShareCodeManager.shared.lookupShareURLWithRetry(for: normalizedCode)
            } else {
                shareLink = trimmed
            }
        } catch {
            await MainActor.run {
                grandchildShareError = error.localizedDescription
            }
            return
        }

        guard let url = URL(string: shareLink) else {
            await MainActor.run {
                grandchildShareError = "Invalid share link or code"
            }
            return
        }

        let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")

        do {
            let metadata = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Metadata, Error>) in
                let operation = CKFetchShareMetadataOperation(shareURLs: [url])
                operation.shouldFetchRootRecord = false
                operation.perShareMetadataResultBlock = { _, result in
                    switch result {
                    case .success(let metadata):
                        continuation.resume(returning: metadata)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                container.add(operation)
            }

            if metadata.share.publicPermission == .none {
                await MainActor.run {
                    grandchildShareError = "This code points to a private share. Ask the sender to generate a new grandchild code."
                }
                return
            }

            if let ownerID = metadata.ownerIdentity.userRecordID,
               let currentID = try? await container.userRecordID(),
               ownerID == currentID {
                await MainActor.run {
                    grandchildShareError = "This share was created by the same iCloud account. Please sign in with the other account."
                }
                return
            }

            let coreDataStack = CoreDataStack.shared
            try await coreDataStack.acceptShareInvitations(from: [metadata])

            await coreDataStack.checkForAcceptedShares()
            let importedGrandchild = await coreDataStack.waitForSharedGrandchildImport()

            await MainActor.run {
                completeOnboardingAsGrandchild()

                if let importedGrandchild {
                    selectedGrandchildID = importedGrandchild.id?.uuidString ?? ""
                    CloudKitSharingManager.shared.currentGrandchildId = importedGrandchild.id
                }
            }
        } catch {
            await MainActor.run {
                grandchildShareError = error.localizedDescription
            }
        }
    }
    
    private func completeOnboardingAsGrandchild() {
        // Grandchildren don't need to set up anything
        // They just need to mark onboarding as complete and enable grandchild mode
        
        if let profile = userProfiles.first {
            profile.hasCompletedOnboarding = true
        } else {
            let newProfile = CDUserProfile(context: viewContext)
            newProfile.hasCompletedOnboarding = true
            newProfile.isPremium = false
            newProfile.freeMemoryCount = 0
            newProfile.name = "Grandchild"
        }
        
        viewContext.saveIfNeeded()
        
        // Enable grandchild mode
        UserDefaults.standard.set(true, forKey: "isGrandchildMode")
    }
    
    private func setupWelcomeVideoCamera() async {
        await welcomeVideoRecorder.requestPermissions { granted in
            if granted {
                Task {
                    await MainActor.run {
                        welcomeVideoRecorder.setPreferredPosition(.front)
                    }
                    if let preview = await welcomeVideoRecorder.setupCaptureSession() {
                        await MainActor.run {
                            self.cameraPreviewLayer = preview
                        }
                        await self.welcomeVideoRecorder.startSession()
                    }
                }
            } else {
                Task { @MainActor in
                    self.showingCameraPermissionAlert = true
                }
            }
        }
    }
    
    private func saveWelcomeVideo() {
        guard let videoURL = welcomeVideoRecorder.videoURL else { return }
        
        // Convert video to Data
        if let videoData = try? Data(contentsOf: videoURL) {
            welcomeVideoData = videoData
            print("📹 Saved welcome video: \(videoData.count) bytes")
        }
    }
    
    private func getNamePlaceholder() -> String {
        if userType == .coGrandparent {
            return "e.g., Gran, Nana, Peter"
        } else if grandparentRole == .grandpa {
            return "e.g., Grandad, Gramps, Papa"
        } else {
            return "e.g., Nanna, Gran, Grandma"
        }
    }
    
    private func onboardingBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 24)
            Text(text)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }
    
    private func generateVideoThumbnail(from videoURL: URL) -> Data? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {

            return nil
        }
    }
}

struct MainAppView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var allMemories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("currentContributorRole") private var currentContributorRole: String = ""
    @AppStorage("primaryContributorRole") private var primaryContributorRole: String = ""
    @AppStorage("isCoGrandparentDevice") private var isCoGrandparentDevice: Bool = false
    @AppStorage("isPrimaryDevice") private var isPrimaryDevice: Bool = false
    @AppStorage("iCloudUserRecordName") private var iCloudUserRecordName: String = ""
    @State private var selectedTab = 0
    @State private var showingCapture = false
    @State private var selectedGrandchildForCapture: CDGrandchild?
    @State private var checkCount = 0
    
    // Get first grandchild for capture
    private var firstGrandchild: CDGrandchild? {
        return grandchildren.first
    }

    private func fetchiCloudUserRecordName() async -> String? {
        do {
            let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
            let recordID = try await container.userRecordID()
            return recordID.recordName
        } catch {
            print("⚠️ Failed to fetch iCloud user record ID: \(error)")
            return nil
        }
    }

    private func contributorForRecordName(_ recordName: String, roleFallback: String) -> CDContributor? {
        let request: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
        request.predicate = NSPredicate(format: "iCloudUserRecordName == %@", recordName)
        request.fetchLimit = 1
        request.affectedStores = nil
        if let match = try? viewContext.fetch(request).first {
            return match
        }

        let sharedStore = CoreDataStack.shared.sharedPersistentStore
        let sharedRequest: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
        sharedRequest.predicate = NSPredicate(format: "role == %@", roleFallback)
        sharedRequest.fetchLimit = 1
        sharedRequest.affectedStores = [sharedStore]
        if let sharedMatch = try? viewContext.fetch(sharedRequest).first {
            return sharedMatch
        }

        let roleRequest: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
        roleRequest.predicate = NSPredicate(format: "role == %@", roleFallback)
        roleRequest.fetchLimit = 1
        roleRequest.affectedStores = nil
        return try? viewContext.fetch(roleRequest).first
    }

    private func mapContributorToiCloudUser(_ recordName: String) {
        let roleFallback = isCoGrandparentDevice ? ContributorRole.grandma.rawValue : ContributorRole.grandpa.rawValue
        let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let contributor = contributorForRecordName(recordName, roleFallback: roleFallback) {
            if contributor.iCloudUserRecordName != recordName {
                contributor.iCloudUserRecordName = recordName
            }
            if let profileName, !profileName.isEmpty {
                contributor.name = profileName
            }
            activeContributorID = contributor.id?.uuidString ?? activeContributorID
            currentContributorRole = contributor.role ?? currentContributorRole
            if !isCoGrandparentDevice {
                primaryContributorRole = contributor.role ?? primaryContributorRole
            }
            viewContext.saveIfNeeded()
        }
        if let profileName, !profileName.isEmpty {
            let request: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
            request.predicate = NSPredicate(format: "iCloudUserRecordName == %@", recordName)
            request.affectedStores = nil
            if let matches = try? viewContext.fetch(request), !matches.isEmpty {
                for match in matches {
                    match.name = profileName
                }
                viewContext.saveIfNeeded()
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineTab(grandchild: firstGrandchild, onGrandchildFilterChanged: { grandchild in
                selectedGrandchildForCapture = grandchild
            }).tabItem { Label("Timeline", systemImage: "clock") }.tag(0)
            VaultTab().tabItem { Label("Vault", systemImage: "archivebox") }.tag(1)
            HelloQueueView().tabItem { Label("Heartbeats", systemImage: "heart.fill") }.tag(2)
            Text("Capture").tabItem { Label("Capture", systemImage: "plus.circle.fill") }.tag(3)
            SettingsTab().tabItem { Label("More", systemImage: "ellipsis.circle") }.tag(4)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 3 {
                showingCapture = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { selectedTab = oldValue }
            }
        }
        .fullScreenCover(isPresented: $showingCapture) {
            CaptureSheet(grandchild: selectedGrandchildForCapture)
        }
        .onAppear {
            Task {
                if let recordName = await fetchiCloudUserRecordName() {
                    await MainActor.run {
                        iCloudUserRecordName = recordName
                        mapContributorToiCloudUser(recordName)
                    }
                }
            }
            if !iCloudUserRecordName.isEmpty {
                mapContributorToiCloudUser(iCloudUserRecordName)
                return
            }
            // Ensure this device has an active contributor set (used for color + "Added by" badge)
            let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let inferredRoleFromName: String? = {
                guard let profileName, !profileName.isEmpty else { return nil }
                if profileName.contains("grandad") || profileName.contains("grandpa") || profileName.contains("granddad") || profileName.contains("papa") || profileName.contains("pop") {
                    return ContributorRole.grandpa.rawValue
                }
                if profileName.contains("grandma") || profileName.contains("gran") || profileName.contains("grannie") || profileName.contains("nana") {
                    return ContributorRole.grandma.rawValue
                }
                return nil
            }()

            if !isCoGrandparentDevice && !isPrimaryDevice {
                isPrimaryDevice = true
            }

            if !isCoGrandparentDevice && isPrimaryDevice,
               let grandpaContributor = contributors.first(where: { $0.role == ContributorRole.grandpa.rawValue }) {
                primaryContributorRole = grandpaContributor.role ?? primaryContributorRole
                currentContributorRole = grandpaContributor.role ?? currentContributorRole
                activeContributorID = grandpaContributor.id?.uuidString ?? activeContributorID
            }

            if !isCoGrandparentDevice && primaryContributorRole.isEmpty {
                if let inferredRoleFromName {
                    primaryContributorRole = inferredRoleFromName
                } else if let profileName,
                          let match = contributors.first(where: { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == profileName }) {
                    primaryContributorRole = match.role ?? primaryContributorRole
                }
            }

            if !isCoGrandparentDevice,
               !primaryContributorRole.isEmpty,
               let roleMatch = contributors.first(where: { $0.role == primaryContributorRole }) {
                currentContributorRole = roleMatch.role ?? ""
                activeContributorID = roleMatch.id?.uuidString ?? ""
            } else if !isCoGrandparentDevice,
                      !currentContributorRole.isEmpty,
                      let roleMatch = contributors.first(where: { $0.role == currentContributorRole }) {
                activeContributorID = roleMatch.id?.uuidString ?? ""
            } else if isCoGrandparentDevice,
                      let grandma = contributors.first(where: { $0.role == ContributorRole.grandma.rawValue }) {
                activeContributorID = grandma.id?.uuidString ?? ""
                currentContributorRole = grandma.role ?? ""
                if primaryContributorRole.isEmpty {
                    primaryContributorRole = grandma.role ?? ""
                }
            } else if !primaryContributorRole.isEmpty,
                      let roleMatch = contributors.first(where: { $0.role == primaryContributorRole }) {
                currentContributorRole = roleMatch.role ?? ""
                activeContributorID = roleMatch.id?.uuidString ?? ""
            } else if let profileName,
                      let match = contributors.first(where: { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == profileName }) {
                activeContributorID = match.id?.uuidString ?? ""
                currentContributorRole = match.role ?? ""
                if primaryContributorRole.isEmpty {
                    primaryContributorRole = match.role ?? ""
                }
            } else if activeContributorID.isEmpty || contributors.first(where: { $0.id?.uuidString == activeContributorID }) == nil {
                if let grandma = contributors.first(where: { $0.role == ContributorRole.grandma.rawValue }) {
                    activeContributorID = grandma.id?.uuidString ?? ""
                    currentContributorRole = grandma.role ?? ""
                } else if let grandpa = contributors.first(where: { $0.role == ContributorRole.grandpa.rawValue }) {
                    activeContributorID = grandpa.id?.uuidString ?? ""
                    currentContributorRole = grandpa.role ?? ""
                }
            }



            // Backfill contributor on this device for memories created by this user
            if !currentContributorRole.isEmpty,
               let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
               let roleContributor = contributors.first(where: { $0.role == currentContributorRole }) {
                var didUpdate = false
                for memory in allMemories where memory.createdBy == profileName {
                    if memory.contributor?.id != roleContributor.id {
                        memory.contributor = roleContributor
                        didUpdate = true
                    }
                }
                if didUpdate {
                    viewContext.saveIfNeeded()
                }
            }

            for (index, child) in grandchildren.enumerated() {
                print("   [\(index)] \(child.name ?? "unnamed") (ID: \(child.id?.uuidString ?? "none"))")
            }
            
            // DIAGNOSTIC: Check which stores viewContext has access to
            let coordinator = viewContext.persistentStoreCoordinator

            print("   Persistent stores count: \(coordinator?.persistentStores.count ?? 0)")
            coordinator?.persistentStores.forEach { store in
                print("   - \(store.url?.lastPathComponent ?? "unknown")")
            }
            
            // CRITICAL: Check for shares accepted through Mail/Messages
            // This is needed because iOS handles share acceptance at system level
            // and doesn't always call our URL handler
            Task {
                let coreDataStack = CoreDataStack.shared
                
                // First, check if there are any accepted shares we haven't imported
                await coreDataStack.checkForAcceptedShares()
                
                // Then continue with periodic checking
                // Check every 15 seconds for up to 10 minutes (CloudKit sync can be slow)
                for iteration in 0..<40 {
                    let bgContext = coreDataStack.newBackgroundContext()
                    
                    let request = CDGrandchild.fetchRequest()
                    request.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrandchild.name, ascending: true)]
                    request.affectedStores = nil  // Query ALL stores
                    
                    do {
                        let results = try bgContext.fetch(request)

                        print("   Found \(results.count) grandchildren")
                        for (index, child) in results.enumerated() {
                            let storeName = child.objectID.persistentStore?.url?.lastPathComponent ?? "unknown"
                            print("   [\(index)] \(child.name ?? "unnamed") in \(storeName)")
                        }
                        
                        // If we found data, stop checking
                        if results.count > 0 {

                            await MainActor.run {
                                viewContext.refreshAllObjects()
                            }
                            break
                        }
                    } catch {

                    }
                    
                    // Wait 15 seconds before next check
                    if iteration < 39 {
                        try? await Task.sleep(for: .seconds(15))
                    }
                }
            }
        }
    }
}

struct TimelineTab: View {
    let grandchild: CDGrandchild?
    let onGrandchildFilterChanged: ((CDGrandchild?) -> Void)?
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var allMemories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var allGrandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("isCoGrandparentDevice") private var isCoGrandparentDevice: Bool = false
    @AppStorage("currentContributorRole") private var currentContributorRole: String = ""
    @AppStorage("primaryContributorRole") private var primaryContributorRole: String = ""
    @AppStorage("isPrimaryDevice") private var isPrimaryDevice: Bool = false
    @AppStorage("iCloudUserRecordName") private var iCloudUserRecordName: String = ""
    @State private var showingCapture = false
    @State private var selectedMemory: CDMemory?
    @State private var selectedGrandchildFilter: CDGrandchild?
    @State private var showingDeleteNotAllowed = false
    
    var activeContributor: CDContributor? {
        contributors.first { $0.id?.uuidString == activeContributorID }
    }
    
    var activeContributorColor: Color {
        if let colorHex = activeContributor?.colorHex {
            return Color(hex: colorHex)
        }
        return DesignSystem.Colors.teal
    }
    
    init(grandchild: CDGrandchild?, onGrandchildFilterChanged: ((CDGrandchild?) -> Void)? = nil) {
        self.grandchild = grandchild
        self.onGrandchildFilterChanged = onGrandchildFilterChanged
    }
    
    var memories: [CDMemory] {
        if let filter = selectedGrandchildFilter {
            return allMemories.filter { memory in
                memory.grandchildrenArray.contains(where: { $0.id == filter.id })
            }
        } else {
            // Show all memories
            return Array(allMemories)
        }
    }
    

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Centered grandchild profile photo (cached)
                if let grandchild = selectedGrandchildFilter ?? allGrandchildren.first, let photoData = grandchild.photoData {
                    VStack(spacing: 8) {
                        CachedAsyncImage(data: photoData)
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())
                        
                        Text(grandchild.firstName)
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .background(DesignSystem.Colors.backgroundSecondary)
                }
                
                // Profile Switcher - only show if there are multiple grandchildren
                if allGrandchildren.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            // "All" button
                            ProfileFilterButton(
                                title: "All",
                                isSelected: selectedGrandchildFilter == nil
                            ) {
                                selectedGrandchildFilter = nil
                                onGrandchildFilterChanged?(nil)
                            }
                            
                            // Individual grandchild buttons
                            ForEach(allGrandchildren) { child in
                                ProfileFilterButton(
                                    title: child.name ?? "Grandchild",
                                    isSelected: selectedGrandchildFilter?.id == child.id,
                                    photoData: child.photoData
                                ) {
                                    selectedGrandchildFilter = child
                                    onGrandchildFilterChanged?(nil)  // Callback no longer needs CD model
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                    .background(DesignSystem.Colors.backgroundSecondary)
                }
                
                ZStack(alignment: .bottomTrailing) {
                    let _ = print("📋 Timeline - memories count: \(memories.count)")
                    if memories.isEmpty {
                        VStack(spacing: 24) {
                            Image(systemName: "photo").font(.system(size: 60)).foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text("No memories yet").font(.title2.bold()).foregroundStyle(DesignSystem.Colors.textPrimary)
                            Text("Tap + to capture your first moment").foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DesignSystem.Colors.backgroundPrimary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(memories) { memory in
                                    let _ = print("📋 Timeline showing memory: \(memory.title ?? "nil"), type: \(memory.memoryType ?? "nil"), filename: \(memory.photoFilename ?? "none")")
                                    MemoryCard(memory: memory)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            print("🖱️ TIMELINE TAPPED - Memory title: \(memory.title ?? "nil")")
                                            print("🖱️ TIMELINE TAPPED - Memory ID: \(memory.id?.uuidString ?? "nil")")
                                            print("🖱️ TIMELINE TAPPED - Setting selectedMemory...")
                                            selectedMemory = memory
                                            print("🖱️ TIMELINE TAPPED - selectedMemory is now: \(selectedMemory?.id?.uuidString ?? "nil")")
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                deleteMemory(memory)
                                            } label: {
                                                Label("Delete Memory", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding()
                            .padding(.bottom, 80)
                        }
                        .background(DesignSystem.Colors.backgroundPrimary)
                    }
                    
                    Button {
                        showingCapture = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            LinearGradient(
                                colors: [activeContributorColor, activeContributorColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .shadow(
                            color: DesignSystem.Shadows.medium.color,
                            radius: DesignSystem.Shadows.medium.radius,
                            x: DesignSystem.Shadows.medium.x,
                            y: DesignSystem.Shadows.medium.y
                        )
                }
                .padding(DesignSystem.Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showingCapture) {
                CaptureSheet(grandchild: nil)  // CaptureView handles nil and fetches from Core Data
            }
            .fullScreenCover(item: $selectedMemory) { memory in
                let _ = print("📱 SHEET PRESENTING - Memory title: \(memory.title ?? "nil")")
                let _ = print("📱 SHEET PRESENTING - Memory ID: \(memory.id?.uuidString ?? "nil")")
                return MemoryDetailView(memory: memory)
            }
            .alert("Can't Delete This Memory", isPresented: $showingDeleteNotAllowed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You can only delete memories you created.")
            }
            .onAppear {
                // Set initial filter to the first grandchild if not set
                if selectedGrandchildFilter == nil, let first = allGrandchildren.first {
                    selectedGrandchildFilter = first
                    onGrandchildFilterChanged?(nil)  // Callback no longer needs CD model
                }
            }
        }
    }
    
    private func deleteMemory(_ memory: CDMemory) {
        guard canDelete(memory) else {
            showingDeleteNotAllowed = true
            return
        }
        // Delete photo file from disk if it exists
        if let filename = memory.photoFilename {
            PhotoStorageManager.shared.deletePhoto(filename: filename)
        }
        
        // Delete from Core Data context - this will sync to iCloud/CloudKit
        // and remove from all shared devices including grandchild's device
        viewContext.delete(memory)
        
        // Save the context
        viewContext.saveIfNeeded()

    }

    private func canDelete(_ memory: CDMemory) -> Bool {
        if let contributorId = memory.contributor?.id?.uuidString, !activeContributorID.isEmpty {
            return contributorId == activeContributorID
        }
        if let recordName = memory.contributor?.iCloudUserRecordName, !recordName.isEmpty,
           !iCloudUserRecordName.isEmpty {
            return recordName == iCloudUserRecordName
        }
        if let createdBy = memory.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return createdBy == profileName
        }
        return false
    }
}

struct VaultTab: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var allMemories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("iCloudUserRecordName") private var iCloudUserRecordName: String = ""
    @State private var searchText = ""
    @State private var selectedMemory: CDMemory?
    @State private var memoryToSchedule: CDMemory?
    @State private var showingDeleteNotAllowed = false
    
    var vaultMemories: [CDMemory] {
        // Vault is for unreleased, unscheduled items (Heartbeats never appear here).
        allMemories.filter { memory in
            if memory.privacy == MemoryPrivacy.vaultOnly.rawValue { return true }
            // Fallback for older vault saves that didn't set privacy correctly
            let isUnreleased = (memory.isReleased == false || memory.isReleased == nil)
            let hasNoSchedule = (memory.releaseDate == nil && memory.releaseAge == 0)
            let isHelloQueue = (memory.privacy == MemoryPrivacy.helloQueue.rawValue)
            return isUnreleased && hasNoSchedule && !isHelloQueue
        }
    }
    
    var filteredMemories: [CDMemory] {
        if searchText.isEmpty {
            return vaultMemories
        }
        return vaultMemories.filter { memory in
            (memory.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (memory.note?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.backgroundPrimary.ignoresSafeArea()
                
                if filteredMemories.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredMemories) { memory in
                                VaultMemoryCard(
                                    memory: memory,
                                    onTap: {

                                        selectedMemory = memory
                                    },
                                    onSchedule: {
                                        memoryToSchedule = memory
                                    }
                                )
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteMemory(memory)
                                    } label: {
                                        Label("Delete Memory", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Vault")
            .searchable(text: $searchText, prompt: "Search memories")
            .fullScreenCover(item: $selectedMemory) { memory in
                let _ = print("📱 VAULT SHEET PRESENTING - Memory title: \(memory.title ?? "nil")")
                let _ = print("📱 VAULT SHEET PRESENTING - Memory ID: \(memory.id?.uuidString ?? "nil")")
                return MemoryDetailView(memory: memory)
            }
            .alert("Can't Delete This Memory", isPresented: $showingDeleteNotAllowed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You can only delete memories you created.")
            }
            .sheet(item: $memoryToSchedule) { memory in
                VaultScheduleSheet(memory: memory)
            }
            .onAppear {
                print("🗄️ Vault appeared - \(filteredMemories.count) memories")
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "archivebox")
                .font(.system(size: 80))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: 8) {
                Text("Your Vault is Empty")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text("Saved memories will appear here.\nYou can schedule when to release them to your grandchildren.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    private func deleteMemory(_ memory: CDMemory) {
        guard canDelete(memory) else {
            showingDeleteNotAllowed = true
            return
        }
        // Delete photo file from disk if it exists
        if let filename = memory.photoFilename {
            PhotoStorageManager.shared.deletePhoto(filename: filename)
        }
        
        viewContext.delete(memory)
        
        do {
            try viewContext.save()
            print("🗑️ Memory deleted from vault")
        } catch {
            print("❌ Failed to delete memory: \(error)")
        }
    }

    private func canDelete(_ memory: CDMemory) -> Bool {
        if let contributorId = memory.contributor?.id?.uuidString, !activeContributorID.isEmpty {
            return contributorId == activeContributorID
        }
        if let recordName = memory.contributor?.iCloudUserRecordName, !recordName.isEmpty,
           !iCloudUserRecordName.isEmpty {
            return recordName == iCloudUserRecordName
        }
        if let createdBy = memory.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return createdBy == profileName
        }
        return false
    }
}

struct VaultMemoryCard: View {
    let memory: CDMemory
    let onTap: () -> Void
    let onSchedule: () -> Void
    
    // Get icon and color for memory type
    private var memoryTypeInfo: (icon: String, gradient: LinearGradient, label: String) {
        guard let type = memory.memoryTypeEnum else {
            return ("note.text", DesignSystem.Colors.tealGradient, "Memory")
        }
        
        switch type {
        case .quickMoment:
            return ("photo", DesignSystem.Colors.tealGradient, "Photo")
        case .videoMessage:
            return ("video.fill", DesignSystem.Colors.primaryGradient, "Video")
        case .voiceMemory:
            return ("waveform", DesignSystem.Colors.pinkGradient, "Voice")
        case .audioPhoto:
            return ("photo.on.rectangle", DesignSystem.Colors.warmGradient, "Audio Photo")
        case .milestone:
            return ("star.fill", DesignSystem.Colors.pinkGradient, "Milestone")
        case .familyRecipe:
            return ("fork.knife", DesignSystem.Colors.accentGradient, "Recipe")
        case .letterToFuture:
            return ("envelope.open.fill", DesignSystem.Colors.tealGradient, "Letter")
        case .wisdomNote:
            return ("lightbulb.fill", DesignSystem.Colors.warmGradient, "Wisdom")
        case .storyTime:
            return ("book.fill", DesignSystem.Colors.primaryGradient, "Story")
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Memory preview
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    // Thumbnail with type badge overlay
                    ZStack(alignment: .topTrailing) {
                        // Main thumbnail
                        if let photoData = memory.displayPhotoData, let uiImage = UIImage(data: photoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        } else if memory.videoData != nil || memory.videoURL != nil {
                            ZStack {
                                Rectangle()
                                    .fill(memoryTypeInfo.gradient)
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white)
                            }
                        } else if memory.audioData != nil {
                            ZStack {
                                Rectangle()
                                    .fill(memoryTypeInfo.gradient)
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                
                                Image(systemName: "waveform")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white)
                            }
                        } else {
                            ZStack {
                                Rectangle()
                                    .fill(memoryTypeInfo.gradient)
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                
                                Image(systemName: memoryTypeInfo.icon)
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white)
                            }
                        }
                        
                        // Type badge
                        HStack(spacing: 4) {
                            Image(systemName: memoryTypeInfo.icon)
                                .font(.system(size: 10))
                            Text(memoryTypeInfo.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(memoryTypeInfo.gradient, in: Capsule())
                        .offset(x: 4, y: -4)
                    }
                    
                    // Memory info
                    VStack(alignment: .leading, spacing: 8) {
                        // Title
                        Text(memory.title ?? "Untitled Memory")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(2)
                        
                        // Date
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text((memory.date ?? Date()).formatted(date: .abbreviated, time: .omitted))
                                .font(DesignSystem.Typography.caption)
                        }
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        
                        // Grandchildren count
                        let grandchildren = memory.grandchildrenArray
                        if !grandchildren.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2")
                                    .font(.caption2)
                                Text("\(grandchildren.count) grandchild\(grandchildren.count == 1 ? "" : "ren")")
                                    .font(DesignSystem.Typography.caption)
                            }
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        
                        // Schedule status
                        if let releaseDate = memory.releaseDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                Text("Releases: \(releaseDate.formatted(date: .abbreviated, time: .omitted))")
                                    .font(DesignSystem.Typography.caption)
                            }
                            .foregroundStyle(DesignSystem.Colors.accent)
                        } else if memory.releaseAge > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "gift")
                                    .font(.caption2)
                                Text("At age \(memory.releaseAge)")
                                    .font(DesignSystem.Typography.caption)
                            }
                            .foregroundStyle(DesignSystem.Colors.accent)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                Text("Not scheduled")
                                    .font(DesignSystem.Typography.caption)
                            }
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            Divider()
            
            // Schedule button
            Button(action: onSchedule) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                    Text("Schedule Release")
                        .font(DesignSystem.Typography.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .foregroundStyle(DesignSystem.Colors.accent)
            }
        }
        .padding()
        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
    }
}

struct VaultScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    let memory: CDMemory
    
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @State private var selectedOption: GiftReleaseOption = .vault
    @State private var selectedDate = Date()
    @State private var selectedAge = 5
    @State private var selectedGrandchildIDs: Set<UUID> = []
    
enum GiftReleaseOption {
    case immediate
    case specificDate
    case specificAge
    case vault
    case helloQueue
}
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.backgroundPrimary.ignoresSafeArea()
                
                ScrollView {
                VStack(spacing: 24) {
                    // Release Options Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Release Options")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        VStack(spacing: 12) {
                            Button {
                                selectedOption = .immediate
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Share Now")
                                            .font(DesignSystem.Typography.headline)
                                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                                        Text("Release immediately")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                    Spacer()
                                    if selectedOption == .immediate {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(DesignSystem.Colors.accent)
                                    }
                                }
                                .padding()
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            }
                            .buttonStyle(.plain)
                    
                            Button {
                                selectedOption = .specificDate
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("On A Specific Date")
                                            .font(DesignSystem.Typography.headline)
                                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                                        Text("Choose a future date")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                    Spacer()
                                    if selectedOption == .specificDate {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(DesignSystem.Colors.accent)
                                    }
                                }
                                .padding()
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            }
                            .buttonStyle(.plain)
                            
                            if selectedOption == .specificDate {
                                DatePicker("Release Date", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                                    .padding()
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            }
                    
                            Button {
                                selectedOption = .specificAge
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("When They Turn")
                                            .font(DesignSystem.Typography.headline)
                                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                                        Text("Release at a specific age")
                                            .font(DesignSystem.Typography.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                    Spacer()
                                    if selectedOption == .specificAge {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(DesignSystem.Colors.accent)
                                    }
                                }
                                .padding()
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            }
                            .buttonStyle(.plain)
                            
                            if selectedOption == .specificAge {
                                Stepper("Age: \(selectedAge) years", value: $selectedAge, in: 1...100)
                                    .padding()
                                    .background(DesignSystem.Colors.backgroundSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            }
                        }
                    }
                
                    // Select Grandchildren Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select Grandchildren")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        VStack(spacing: 12) {
                            if grandchildren.isEmpty {
                                Text("No grandchildren added yet")
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .padding()
                            } else {
                                ForEach(grandchildren) { grandchild in
                                    Button {
                                        if let id = grandchild.id {
                                            if selectedGrandchildIDs.contains(id) {
                                                selectedGrandchildIDs.remove(id)
                                            } else {
                                                selectedGrandchildIDs.insert(id)
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            if let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 40, height: 40)
                                                    .clipShape(Circle())
                                            } else {
                                                Circle()
                                                    .fill(DesignSystem.Colors.accent.opacity(0.2))
                                                    .frame(width: 40, height: 40)
                                                    .overlay(
                                                        Text((grandchild.name ?? "?").prefix(1).uppercased())
                                                            .font(.headline)
                                                            .foregroundStyle(DesignSystem.Colors.accent)
                                                    )
                                            }
                                            
                                            Text(grandchild.name ?? "Unknown")
                                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                            
                                            Spacer()
                                            
                                            if let id = grandchild.id, selectedGrandchildIDs.contains(id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(DesignSystem.Colors.accent)
                                            } else {
                                                Image(systemName: "circle")
                                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                            }
                                        }
                                        .padding()
                                        .background(DesignSystem.Colors.backgroundSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Save Button
                    Button {
                        saveSchedule()
                    } label: {
                        Text("Save")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background {
                                if selectedGrandchildIDs.isEmpty {
                                    DesignSystem.Colors.textTertiary
                                } else {
                                    DesignSystem.Colors.accentGradient
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .disabled(selectedGrandchildIDs.isEmpty)
                    .buttonStyle(.plain)
                }
                .padding()
            }
            }
            .navigationTitle("Schedule Release")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
            print("📅 VaultScheduleSheet appeared for: \(memory.title ?? "nil")")
            print("   - Grandchildren count: \(grandchildren.count)")
            
            // Set initial selected grandchildren
            let memoryGrandchildren = memory.grandchildrenArray
            selectedGrandchildIDs = Set(memoryGrandchildren.compactMap { $0.id })
            print("   - Pre-selected \(selectedGrandchildIDs.count) grandchildren")
            
            // Set initial option based on memory state
            if memory.releaseDate != nil {
                selectedOption = .specificDate
                selectedDate = memory.releaseDate ?? Date()
                print("   - Has release date: \(selectedDate)")
            } else if memory.releaseAge > 0 {
                selectedOption = .specificAge
                selectedAge = Int(memory.releaseAge)
                print("   - Has release age: \(selectedAge)")
            } else if memory.isReleased {
                selectedOption = .immediate
                print("   - Already released")
            } else {
                print("   - No scheduling set (vault only)")
            }
        }
        }
    }
    
    private func saveSchedule() {
        // Update memory scheduling
        switch selectedOption {
        case .immediate:
            memory.releaseDate = nil
            memory.releaseAge = 0
            memory.isReleased = true
        case .specificDate:
            memory.releaseDate = selectedDate
            memory.releaseAge = 0
            memory.isReleased = false
        case .specificAge:
            memory.releaseDate = nil
            memory.releaseAge = Int32(selectedAge)
            memory.isReleased = false
        case .vault:
            memory.releaseDate = nil
            memory.releaseAge = 0
            memory.isReleased = false
        case .helloQueue:
            memory.releaseDate = nil
            memory.releaseAge = 0
            memory.isReleased = false
            memory.privacy = MemoryPrivacy.helloQueue.rawValue
        }
        
        // Update grandchildren - clear existing and add new ones
        let selectedGrandchildObjects = grandchildren.filter { selectedGrandchildIDs.contains($0.id ?? UUID()) }
        // Remove all existing grandchildren
        let existingGrandchildren = memory.grandchildrenArray
        for existingChild in existingGrandchildren {
            memory.removeFromGrandchildren(existingChild)
        }
        // Add selected grandchildren
        for grandchild in selectedGrandchildObjects {
            memory.addToGrandchildren(grandchild)
        }
        
        // Save
        viewContext.saveIfNeeded()
        
        // Schedule notification if needed
        // TODO: Convert VaultScheduleSheet to use Core Data
        // if let releaseDate = memory.releaseDate, releaseDate > Date() {
        //     Task {
        //         await NotificationManager.shared.scheduleGiftReleaseNotification(
        //             for: memory,
        //             grandchildName: selectedGrandchildren.first?.name ?? "your grandchild"
        //         )
        //     }
        // }
        
        Task { @MainActor in
            dismiss()
        }
    }
}

struct ProfileFilterButton: View {
    let title: String
    let isSelected: Bool
    let photoData: Data?
    let action: () -> Void
    
    init(title: String, isSelected: Bool, photoData: Data? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.photoData = photoData
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let photoData = photoData {
                    CachedAsyncImage(data: photoData)
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }
                
                Text(title)
                    .font(DesignSystem.Typography.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? AnyShapeStyle(DesignSystem.Colors.tealGradient) : AnyShapeStyle(DesignSystem.Colors.backgroundPrimary), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : DesignSystem.Colors.textTertiary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct MemoryCard: View {
    let memory: CDMemory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    
    // Full-screen video
    @State private var showFullScreenVideo = false
    @State private var fullScreenVideoURL: URL?
    
    // Full-screen photo
    @State private var showFullScreenPhoto = false
    @State private var fullScreenPhotoImage: UIImage?
    
    // Load photo once and cache it
    @State private var loadedImage: UIImage?

    private var mediaHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular ? 420 : 250
    }
    
    // Get gradient based on contributor
    private var contributorGradient: LinearGradient {
        guard let contributor = memory.contributor,
              let colorHex = contributor.colorHex else {
            // For imported memories without contributor, use active contributor's color
            if let activeContributor = contributors.first(where: { $0.id?.uuidString == activeContributorID }),
               let activeColorHex = activeContributor.colorHex {
                let baseColor = Color(hex: activeColorHex)
                let lightColor = baseColor.opacity(0.8)
                return LinearGradient(
                    colors: [baseColor, lightColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            return DesignSystem.Colors.tealGradient
        }
        
        let baseColor = Color(hex: colorHex)
        let lightColor = baseColor.opacity(0.8)
        return LinearGradient(
            colors: [baseColor, lightColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var isLocked: Bool {
        return (memory.isReleased ?? false) == false
    }

    private var isHelloQueue: Bool {
        return memory.privacy == MemoryPrivacy.helloQueue.rawValue
    }

    private var lockLabel: String {
        if isHelloQueue {
            return "Heartbeat queued"
        }
        if let releaseDate = memory.releaseDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return "Opens on \(formatter.string(from: releaseDate))"
        }
        if memory.releaseAge > 0 {
            return "Opens at age \(memory.releaseAge)"
        }
        return "Stored in Vault"
    }
    
    @ViewBuilder
    private var videoPlayerView: some View {
        if let videoData = memory.videoData,
           let cachedURL = VideoCache.shared.url(for: videoData) {
            VideoPlayerView(url: cachedURL)
                .frame(height: mediaHeight)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                .onTapGesture {
                    fullScreenVideoURL = cachedURL
                    showFullScreenVideo = true
                }
        } else if let videoPath = memory.videoURL {
            // Legacy: video stored as file path
            let videoURL = URL(fileURLWithPath: videoPath)
            VideoPlayerView(url: videoURL)
                .frame(height: mediaHeight)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                .onTapGesture {
                    fullScreenVideoURL = videoURL
                    showFullScreenVideo = true
                }
        }
    }
    
    var body: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: memory.memoryTypeEnum?.icon ?? "heart.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.backgroundPrimary)
                Text(memory.memoryTypeEnum?.rawValue ?? "Memory")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.backgroundPrimary)
                
                if memory.isImported == true {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    
                    if let contributor = memory.contributor {
                        Text("Imported by \(contributor.displayName)")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(contributorGradient, in: Capsule())
            
            // Show memory-type specific content
            switch memory.memoryTypeEnum {
            case .milestone:
                if let title = memory.milestoneTitle {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                if let age = memory.milestoneAge {
                    Text("Age: \(age)")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
            case .letterToFuture:
                if let title = memory.letterTitle {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                if memory.openWhenAge > 0 {
                    HStack {
                        Image(systemName: "envelope.badge.fill")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.teal)
                        Text("Open at age \(memory.openWhenAge)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                
            case .familyRecipe:
                if let title = memory.recipeTitle {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                
            case .voiceMemory:
                if memory.audioData != nil {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.teal)
                        Text("Voice recording")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DesignSystem.Colors.teal)
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundPrimary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                }
                
            case .audioPhoto:
                HStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.teal)
                    Text("Audio Photo story")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(DesignSystem.Colors.teal)
                }
                .padding()
                .background(DesignSystem.Colors.backgroundPrimary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                
            case .videoMessage:
                if memory.videoData != nil || memory.videoURL != nil {
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.teal)
                        Text("Video message")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DesignSystem.Colors.teal)
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundPrimary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                }
                
            default:
                EmptyView()
            }
            
            // Video (for videoMessage type)
            if memory.memoryTypeEnum == .videoMessage {
                videoPlayerView
            }
            
            // Photo (common for multiple types, except videoMessage) - cached
            if memory.memoryTypeEnum != .videoMessage {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: mediaHeight)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                        // Removed .onTapGesture to allow parent button to handle taps
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                        
                        if memory.memoryTypeEnum == .audioPhoto {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 36))
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                Text("Audio Photo")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    .onAppear {
                        // Load image asynchronously
                        Task {
                            if let photoData = memory.displayPhotoData,
                               let image = UIImage(data: photoData) {
                                await MainActor.run {
                                    self.loadedImage = image
                                    print("📸 MemoryCard loaded image: \(photoData.count) bytes")
                                }
                            } else {
                                print("📸 MemoryCard failed to load - filename: \(memory.photoFilename ?? "none"), photoData: \(memory.photoData?.count ?? 0)")
                            }
                        }
                    }
                }
            }
            
            if let title = memory.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            // Note preview (truncated)
            if let note = memory.note, !note.isEmpty {
                Text(note)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(3)
            }
            
            // Location (if available)
            if let locationName = memory.locationName {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(DesignSystem.Colors.primary)
                    Text(locationName)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text(memory.formattedDate)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                
                Spacer()
                
                // Show who added this memory
                if let contributor = memory.contributor {
                    ContributorBadge(contributor: contributor)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        .shadow(
            color: DesignSystem.Shadows.subtle.color,
            radius: DesignSystem.Shadows.subtle.radius,
            x: DesignSystem.Shadows.subtle.x,
            y: DesignSystem.Shadows.subtle.y
        )
        ZStack {
            content
                .blur(radius: isLocked ? 6 : 0)
            if isLocked {
                VStack(spacing: 8) {
                    Image(systemName: isHelloQueue ? "heart.fill" : "lock.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(lockLabel)
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(16)
                .background(DesignSystem.Colors.backgroundPrimary.opacity(0.85), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            }
        }
        .fullScreenCover(isPresented: $showFullScreenVideo) {
            if let videoURL = fullScreenVideoURL {
                FullScreenVideoPlayer(videoURL: videoURL, isPresented: $showFullScreenVideo)
            }
        }
        .fullScreenCover(isPresented: $showFullScreenPhoto) {
            if let image = fullScreenPhotoImage {
                FullScreenImageViewer(image: image, isPresented: $showFullScreenPhoto)
            }
        }
    }
}

struct CaptureSheet: View {
    let grandchild: CDGrandchild?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMemoryType: MemoryType?
    @State private var selectedVaultMemoryType: MemoryType?
    @State private var showingPhotoImport = false
    @State private var showingVaultCapturePicker = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Capture a Memory").font(DesignSystem.Typography.title2).foregroundStyle(DesignSystem.Colors.textPrimary).padding(.top, 32)
                    
                    // Capture to Vault button
                    Button(action: { showingVaultCapturePicker = true }) {
                        HStack(spacing: 16) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Capture to Vault")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text("Save photo or video to assign later")
                                    .font(DesignSystem.Typography.subheadline)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.vertical, 8)
                    
                    ForEach(MemoryType.allCases, id: \.self) { memoryType in
                        CaptureOptionButton(memoryType: memoryType) {
                            selectedMemoryType = memoryType
                        }
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    // Import from Photos button
                    Button(action: { showingPhotoImport = true }) {
                        HStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(DesignSystem.Colors.secondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Import from Photos")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text("Add past photos with original dates")
                                    .font(DesignSystem.Typography.subheadline)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.backgroundPrimary)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .fullScreenCover(item: $selectedMemoryType) { memoryType in
                CaptureView(grandchild: grandchild, memoryType: memoryType)
            }
            .fullScreenCover(item: $selectedVaultMemoryType) { memoryType in
                CaptureView(grandchild: nil, memoryType: memoryType, allowUnassigned: true, forceVaultOnly: true)
            }
            .fullScreenCover(isPresented: $showingPhotoImport) {
                PhotoImportView(grandchild: grandchild)
            }
            .confirmationDialog("Capture to Vault", isPresented: $showingVaultCapturePicker, titleVisibility: .visible) {
                Button("Photo") { selectedVaultMemoryType = .quickMoment }
                Button("Video") { selectedVaultMemoryType = .videoMessage }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

struct CaptureOptionButton: View {
    let memoryType: MemoryType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: memoryType.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(DesignSystem.Colors.tealGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(memoryType.rawValue)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(memoryType.description)
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding()
            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        }
        .buttonStyle(.plain)
    }
}

extension MemoryType: Identifiable {
    var id: String { rawValue }
}

struct CaptureView: View {
    let grandchild: CDGrandchild?
    let memoryType: MemoryType
    let allowUnassigned: Bool
    let forceVaultOnly: Bool
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var allMemories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var allGrandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("currentContributorRole") private var currentContributorRole: String = ""
    @AppStorage("isCoGrandparentDevice") private var isCoGrandparentDevice: Bool = false
    @AppStorage("primaryContributorRole") private var primaryContributorRole: String = ""
    @AppStorage("isPrimaryDevice") private var isPrimaryDevice: Bool = false
    @AppStorage("iCloudUserRecordName") private var iCloudUserRecordName: String = ""
    
    // Get the active contributor
    private var activeContributor: CDContributor? {
        if !iCloudUserRecordName.isEmpty,
           let userMatch = contributors.first(where: { $0.iCloudUserRecordName == iCloudUserRecordName }) {
            return userMatch
        }
        if !isCoGrandparentDevice,
           isPrimaryDevice,
           !primaryContributorRole.isEmpty,
           let roleMatch = contributors.first(where: { $0.role == primaryContributorRole }) {
            return roleMatch
        }
        if isCoGrandparentDevice || !currentContributorRole.isEmpty,
           let roleMatch = contributors.first(where: { $0.role == currentContributorRole || (isCoGrandparentDevice && $0.role == ContributorRole.grandma.rawValue) }) {
            return roleMatch
        }
        return contributors.first { $0.id?.uuidString == activeContributorID }
    }

    private var creatorName: String {
        let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profileName, !profileName.isEmpty {
            return profileName
        }
        let contributorName = activeContributor?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let contributorName, !contributorName.isEmpty {
            return contributorName
        }
        return "Grandparent"
    }

    private func memoryBelongsToCurrentUser(_ memory: CDMemory) -> Bool {
        if let contributorId = memory.contributor?.id?.uuidString, !activeContributorID.isEmpty {
            return contributorId == activeContributorID
        }
        if let recordName = memory.contributor?.iCloudUserRecordName, !recordName.isEmpty,
           !iCloudUserRecordName.isEmpty {
            return recordName == iCloudUserRecordName
        }
        if let createdBy = memory.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return createdBy == profileName
        }
        return false
    }

    private var currentUserMemoryCount: Int {
        allMemories.filter { memoryBelongsToCurrentUser($0) }.count
    }

    private func fetchiCloudUserRecordName() async -> String? {
        do {
            let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
            let recordID = try await container.userRecordID()
            return recordID.recordName
        } catch {
            print("⚠️ Failed to fetch iCloud user record ID (capture): \(error)")
            return nil
        }
    }

    private func contributorForRecordName(_ recordName: String, roleFallback: String) -> CDContributor? {
        let request: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
        request.predicate = NSPredicate(format: "iCloudUserRecordName == %@", recordName)
        request.fetchLimit = 1
        request.affectedStores = nil
        if let match = try? viewContext.fetch(request).first {
            return match
        }

        let sharedStore = CoreDataStack.shared.sharedPersistentStore
        let sharedRequest: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
        sharedRequest.predicate = NSPredicate(format: "role == %@", roleFallback)
        sharedRequest.fetchLimit = 1
        sharedRequest.affectedStores = [sharedStore]
        if let sharedMatch = try? viewContext.fetch(sharedRequest).first {
            return sharedMatch
        }

        let roleRequest: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
        roleRequest.predicate = NSPredicate(format: "role == %@", roleFallback)
        roleRequest.fetchLimit = 1
        roleRequest.affectedStores = nil
        return try? viewContext.fetch(roleRequest).first
    }
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showCamera = false
    @State private var memoryTitle = "" // General title for all memory types
    @State private var noteText = ""
    @State private var privacy: MemoryPrivacy = .maybeDecide
    @State private var selectedGrandchildren: Set<UUID> = []
    
    // Milestone fields
    @State private var milestoneTitle = ""
    @State private var milestoneAge = ""
    
    // Recipe fields
    @State private var recipeTitle = ""
    @State private var ingredients = ""
    @State private var instructions = ""
    
    // Letter fields
    @State private var letterTitle = ""
    @State private var openWhenAge = 18
    
    // Audio recording
    @State private var audioRecorder = AudioRecorder()
    @State private var showingPermissionAlert = false
    
    // Video recording
    @State private var videoRecorder = VideoRecorder()
    @State private var showingCameraPermissionAlert = false
    @State private var cameraPreviewLayer: AVCaptureVideoPreviewLayer?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var importedVideoURL: URL?
    @State private var showVideoImportAdvice = false
    @State private var pendingVideoItem: PhotosPickerItem?
    @State private var isLoadingVideo = false
    @State private var videoLoadProgress: Double = 0.0
    @State private var countdownRemaining: Int?
    @State private var countdownCancelled = false
    @FocusState private var focusedField: CaptureField?
    
    // Audio Photo (Voice Overlay)
    @State private var selectedAudioPhotos: [PhotosPickerItem] = []
    @State private var audioPhotoDataList: [Data] = []
    @State private var showAudioPhotoCamera = false
    @State private var showAudioPhotoIntro = true
    
    // Paywall
    @State private var showPaywall = false
    @State private var showMemoryReminder = false
    @StateObject private var storeManager = StoreKitManager.shared

    private var hasPremiumAccess: Bool {
        storeManager.isPremium || isCoGrandparentDevice
    }

    // Gift Scheduling
    @State private var showGiftScheduling = false
    @State private var giftReleaseOption: GiftReleaseOption = .vault
    @State private var giftReleaseDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var giftReleaseAge = 10
    @State private var isSavingMemory = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    
    private enum CaptureField {
        case title
    }

    init(grandchild: CDGrandchild?, memoryType: MemoryType, allowUnassigned: Bool = false, forceVaultOnly: Bool = false) {
        self.grandchild = grandchild
        self.memoryType = memoryType
        self.allowUnassigned = allowUnassigned
        self.forceVaultOnly = forceVaultOnly
    }
    
    var body: some View {
        modifiedNavigationContent
    }
    
    private var navigationContent: some View {
        NavigationStack {
            scrollContent
            .navigationTitle(memoryType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Save") { saveMemory() }
                .disabled(!canSave || isSavingMemory)
        }
    }
    
    private var modifiedNavigationContent: some View {
        withSheets
            .onAppear {
                if let grandchild = grandchild, let id = grandchild.id {
                    selectedGrandchildren.insert(id)
                } else if allGrandchildren.count == 1, let firstChild = allGrandchildren.first, let id = firstChild.id {
                    selectedGrandchildren.insert(id)
                }
            }
    }
    
    private var withChangeHandlers: some View {
        navigationContent
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            photoData = data
                            if memoryType == .quickMoment {
                                focusedField = .title
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedAudioPhotos) { _, newItems in
                Task {
                    for item in newItems {
                        if audioPhotoDataList.count >= 10 { break }
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            audioPhotoDataList.append(data)
                        }
                    }
                    await MainActor.run {
                        selectedAudioPhotos = []
                    }
                }
            }
            .onChange(of: selectedVideoItem) { _, newValue in
                if newValue != nil {
                    // Store the pending item and show advisory
                    pendingVideoItem = newValue
                    showVideoImportAdvice = true
                }
            }
    }
    
    private var withSheets: some View {
        withChangeHandlers
            .fullScreenCover(isPresented: $showCamera) {
                PhotoCameraView { image in
                    // Convert to JPEG data synchronously to ensure it's ready
                    if let imageData = image.jpegData(compressionQuality: 0.7) {
                        photoData = imageData
                        print("📸 ✅ Photo data set: \(imageData.count) bytes, canSave: \(photoData != nil)")
                        if memoryType == .quickMoment {
                            focusedField = .title
                        }
                    } else {
                        print("📸 ❌ Failed to convert image to JPEG data")
                    }
                }
            }
            .fullScreenCover(isPresented: $showAudioPhotoCamera) {
                PhotoCameraView { image in
                    if let imageData = image.jpegData(compressionQuality: 0.7) {
                        if audioPhotoDataList.count < 10 {
                            audioPhotoDataList.append(imageData)
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .memoryLimit) {
                    // Paywall dismissed - they may have purchased
                    // Try saving again if they're now premium
                    if storeManager.isPremium {
                        performSaveMemory()
                    }
                }
            }
            .alert("Only 2 Free Memories Left!", isPresented: $showMemoryReminder) {
                Button("Upgrade Now") {
                    showPaywall = true
                }
                Button("Continue", role: .cancel) {
                    showGiftScheduling = true
                }
            } message: {
                Text("You've used 8 of your 10 free memories. Upgrade to unlimited memories anytime!")
            }
            .alert("Video Import Notice", isPresented: $showVideoImportAdvice) {
                Button("Continue Import") {
                    // Start loading state
                    isLoadingVideo = true
                    videoLoadProgress = 0.0
                    
                    // Proceed with loading the video
                    Task {
                        // Simulate progress for user feedback
                        let progressTask = Task {
                            for i in 0...20 {
                                try? await Task.sleep(for: .milliseconds(200))
                                await MainActor.run {
                                    videoLoadProgress = Double(i) / 20.0 * 0.9 // Go up to 90%
                                }
                            }
                        }
                        
                        if let movie = try? await pendingVideoItem?.loadTransferable(type: VideoTransferable.self) {
                            progressTask.cancel()
                            await MainActor.run {
                                videoLoadProgress = 1.0 // Complete
                                importedVideoURL = movie.url
                                // Clear camera recording if switching to import
                                videoRecorder.deleteRecording()
                                cameraPreviewLayer = nil
                                
                                // Hide loading after brief delay
                                Task {
                                    try? await Task.sleep(for: .milliseconds(300))
                                    await MainActor.run {
                                        isLoadingVideo = false
                                    }
                                }
                            }
                        } else {
                            progressTask.cancel()
                            await MainActor.run {
                                isLoadingVideo = false
                                videoLoadProgress = 0.0
                            }
                        }
                        pendingVideoItem = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    // Reset selection
                    selectedVideoItem = nil
                    pendingVideoItem = nil
                }
            } message: {
                Text("Depending on the size of your video, it may take a few moments to load.\n\nFor the best experience:\n• Try to import smaller video files\n• Recording video directly in the app works best and loads instantly")
            }
            .alert("Couldn't Save Memory", isPresented: $showSaveError) {
                Button("OK") {}
            } message: {
                Text(saveErrorMessage)
            }
            .sheet(isPresented: $showGiftScheduling) {
                GiftSchedulingView(
                    selectedOption: $giftReleaseOption,
                    releaseDate: $giftReleaseDate,
                    releaseAge: $giftReleaseAge,
                    grandchildName: allGrandchildren.first?.name ?? "your grandchild",
                    onComplete: {
                        performSaveMemory()
                    }
                )
            }
            .overlay(savingOverlay)
    }
    
    private var scrollContent: some View {
        ScrollView {
            formContent.padding()
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }
    
    private var formContent: some View {
        VStack(spacing: 24) {
            // Content based on memory type
            Group {
                switch memoryType {
                case .quickMoment:
                    quickMomentFields
                case .voiceMemory:
                    voiceMemoryFields
                case .audioPhoto:
                    audioPhotoFields
                case .videoMessage:
                    videoMessageFields
                case .milestone:
                    milestoneFields
                case .letterToFuture:
                    letterToFutureFields
                case .wisdomNote:
                    wisdomNoteFields
                case .familyRecipe:
                    familyRecipeFields
                case .storyTime:
                    storyTimeFields
                }
            }
            
            // Grandchild selector (only show if multiple grandchildren exist)
            if !allowUnassigned {
                Group {
                    if allGrandchildren.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Who is this memory for?")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(allGrandchildren) { child in
                                    GrandchildToggleButton(
                                        name: child.name ?? "Grandchild",
                                        isSelected: selectedGrandchildren.contains(child.id ?? UUID())
                                    ) {
                                        if let id = child.id {
                                            if selectedGrandchildren.contains(id) {
                                                selectedGrandchildren.remove(id)
                                            } else {
                                                selectedGrandchildren.insert(id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Share timing is selected on the next screen
                    Text("You can decide when to share this on the next screen.")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            } else {
                Text("This will be saved to your vault so you can assign it later.")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }
    
    var canSave: Bool {
        let result: Bool
        switch memoryType {
        case .quickMoment:
            result = photoData != nil
            print("📸 canSave check - photoData: \(photoData?.count ?? 0) bytes, result: \(result)")
            return result
        case .voiceMemory:
            result = audioRecorder.audioData != nil
            return result
        case .audioPhoto:
            result = audioRecorder.audioData != nil && !audioPhotoDataList.isEmpty
            return result
        case .videoMessage:
            result = videoRecorder.videoURL != nil || importedVideoURL != nil
            return result
        case .milestone:
            result = !milestoneTitle.isEmpty
            return result
        case .letterToFuture:
            result = !letterTitle.isEmpty && !noteText.isEmpty
            return result
        case .wisdomNote:
            result = !noteText.isEmpty
            return result
        case .familyRecipe:
            result = !recipeTitle.isEmpty || !ingredients.isEmpty || !instructions.isEmpty || photoData != nil
            return result
        case .storyTime:
            result = !noteText.isEmpty
            return result
        }
    }
    
    // MARK: - View Components for Each Memory Type
    
    private var quickMomentFields: some View {
        VStack(spacing: 16) {
            photoPickerView
            
            // Title input
            TextField("Title (optional)", text: $memoryTitle)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            textFieldView(text: $noteText, placeholder: "What happened today?", lines: 5...10)
        }
    }

    private var audioPhotoFields: some View {
        VStack(spacing: 20) {
            if showAudioPhotoIntro {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(DesignSystem.Colors.accent)
                    Text("Audio Photo")
                        .font(DesignSystem.Typography.title2)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Add up to ten photos and record a voice story. This becomes a special Audio Photo in your grandchild's app -- they tap it to see the photos and hear your voice.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    Text("It appears as a gift they can open anytime, full-screen.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                    Button("Continue") {
                        showAudioPhotoIntro = false
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .padding()
                .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            }
            
            if !audioPhotoDataList.isEmpty {
                Text("\(audioPhotoDataList.count) photo(s) added")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(audioPhotoDataList.indices, id: \.self) { index in
                            if let uiImage = UIImage(data: audioPhotoDataList[index]) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 90, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    
                                    Button {
                                        audioPhotoDataList.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white)
                                            .background(Color.black.opacity(0.5), in: Circle())
                                    }
                                    .offset(x: 6, y: -6)
                                }
                            }
                        }
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button {
                    showAudioPhotoCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo")
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .buttonStyle(.plain)
                .disabled(audioPhotoDataList.count >= 10)
                
                PhotosPicker(selection: $selectedAudioPhotos, maxSelectionCount: 10, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Add Photos")
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .strokeBorder(DesignSystem.Colors.accent, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(audioPhotoDataList.count >= 10)
            }
            
            Text("Up to 10 photos")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            VStack(spacing: 16) {
                Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(audioRecorder.isRecording ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                    .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                
                if audioRecorder.isRecording {
                    Text(audioRecorder.formattedDuration)
                        .font(DesignSystem.Typography.title2)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .monospacedDigit()
                } else if audioRecorder.audioData != nil {
                    HStack(spacing: 16) {
                        Button {
                            if audioRecorder.isPlaying {
                                audioRecorder.stopPlaying()
                            } else if let data = audioRecorder.audioData {
                                audioRecorder.playAudio(from: data)
                            }
                        } label: {
                            Image(systemName: audioRecorder.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(DesignSystem.Colors.teal)
                        }
                        .buttonStyle(.plain)
                        
                        Text(audioRecorder.formattedDuration)
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Button {
                            audioRecorder.deleteRecording()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            
            if !audioRecorder.isRecording && audioRecorder.audioData == nil {
                Button {
                    Task {
                        await audioRecorder.requestPermission { granted in
                            if granted {
                                audioRecorder.startRecording()
                            } else {
                                showingPermissionAlert = true
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "mic.circle.fill")
                        Text("Record Story")
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .buttonStyle(.plain)
            } else if audioRecorder.isRecording {
                Button {
                    audioRecorder.stopRecording()
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("Stop Recording")
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .buttonStyle(.plain)
            }
            
            TextField("Title (optional)", text: $memoryTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            textFieldView(text: $noteText, placeholder: "Tell the story behind these photos...", lines: 4...8)
        }
    }

    private func makeAudioPhotoThumbnailData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1024
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
    
    private var voiceMemoryFields: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: audioRecorder.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(audioRecorder.isRecording ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                    .symbolEffect(.pulse, isActive: audioRecorder.isRecording)
                
                if audioRecorder.isRecording {
                    Text(audioRecorder.formattedDuration)
                        .font(DesignSystem.Typography.title2)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .monospacedDigit()
                } else if audioRecorder.audioData != nil {
                    HStack(spacing: 16) {
                        Button {
                            if audioRecorder.isPlaying {
                                audioRecorder.stopPlaying()
                            } else if let data = audioRecorder.audioData {
                                audioRecorder.playAudio(from: data)
                            }
                        } label: {
                            Image(systemName: audioRecorder.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(DesignSystem.Colors.teal)
                        }
                        .buttonStyle(.plain)
                        
                        Text(audioRecorder.formattedDuration)
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Button {
                            audioRecorder.deleteRecording()
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Use Recording") {
                            saveMemory()
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        
                        Button("Record Again") {
                            audioRecorder.deleteRecording()
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                .strokeBorder(DesignSystem.Colors.accent, lineWidth: 2)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(40)
            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            
            if !audioRecorder.isRecording && audioRecorder.audioData == nil {
                Button {
                    print("🎤 Button tapped")
                    Task {
                        print("🎤 Task started")
                        await audioRecorder.requestPermission { granted in
                            print("🎤 Permission result: \(granted)")
                            if granted {
                                print("🎤 Starting recording")
                                audioRecorder.startRecording()
                            } else {
                                print("🎤 Permission denied")
                                showingPermissionAlert = true
                            }
                        }
                        print("🎤 Task completed")
                    }
                } label: {
                    HStack {
                        Image(systemName: "mic.circle.fill")
                        Text("Start Recording")
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .buttonStyle(.plain)
            } else if audioRecorder.isRecording {
                Button {
                    audioRecorder.stopRecording()
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("Stop Recording")
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .buttonStyle(.plain)
            }
            
            // Title input
            TextField("Title (optional)", text: $memoryTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            textFieldView(text: $noteText, placeholder: "Add a note about this recording (optional)...", lines: 3...5)
        }
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("Please enable microphone access in Settings to record voice memories.")
        }
    }
    
    private var videoMessageFields: some View {
        VStack(spacing: 24) {
            // Camera preview or status
            if let previewLayer = cameraPreviewLayer {
                ZStack {
                    CameraPreviewView(previewLayer: previewLayer)
                        .frame(height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    
                    VStack {
                        HStack {
                            Button {
                                Task { await videoRecorder.switchCamera() }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(Color.black.opacity(0.6), in: Circle())
                            }
                            .disabled(videoRecorder.isRecording)
                            .accessibilityLabel("Switch camera")
                            
                            Spacer()
                        }
                        .padding(12)
                        Spacer()
                    }

                    // Recording indicator (only show when recording)
                    if videoRecorder.isRecording {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                            Text(videoRecorder.formattedDuration)
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .padding()
                    }
                    
                    // Pre-recording countdown and reminder
                    if let countdownRemaining {
                        VStack(spacing: 0) {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("Look at the camera")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("So they see your eyes")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .padding(.top, 16)
                            
                            Spacer()
                            
                            Text("\(countdownRemaining)")
                                .font(.system(size: 96, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Button("Dismiss") {
                                self.countdownRemaining = nil
                                countdownCancelled = true
                                if !videoRecorder.isRecording {
                                    videoRecorder.startRecording()
                                }
                            }
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .padding(.bottom, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.55))
                    }
                }
            } else if let videoURL = videoRecorder.videoURL ?? importedVideoURL {
                // Show recorded/imported video status
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(DesignSystem.Colors.primary)
                    
                    HStack(spacing: 16) {
                        Text(importedVideoURL != nil ? "Video imported" : "Video recorded: \(videoRecorder.formattedDuration)")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Button {
                            if importedVideoURL != nil {
                                importedVideoURL = nil
                                selectedVideoItem = nil
                            } else {
                                videoRecorder.deleteRecording()
                                cameraPreviewLayer = nil
                            }
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Video preview
                    VideoPlayerView(url: videoURL, autoPlay: false)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    HStack(spacing: 12) {
                        Button("Use Video") {
                            saveMemory()
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        
                        Button("Record Again") {
                            if importedVideoURL != nil {
                                importedVideoURL = nil
                                selectedVideoItem = nil
                            } else {
                                videoRecorder.deleteRecording()
                                cameraPreviewLayer = nil
                            }
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                .strokeBorder(DesignSystem.Colors.accent, lineWidth: 2)
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            } else if isLoadingVideo {
                // Show loading progress
                VStack(spacing: 24) {
                    Image(systemName: "video.badge.ellipsis")
                        .font(.system(size: 60))
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .symbolEffect(.pulse)
                    
                    VStack(spacing: 12) {
                        Text("Importing video...")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        ProgressView(value: videoLoadProgress)
                            .progressViewStyle(.linear)
                            .tint(DesignSystem.Colors.accent)
                            .frame(maxWidth: 200)
                        
                        Text("\(Int(videoLoadProgress * 100))%")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .monospacedDigit()
                    }
                    
                    Text("Please wait while we load your video")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            } else {
                // Placeholder when camera not set up yet
                VStack(spacing: 16) {
                    Image(systemName: "video")
                        .font(.system(size: 60))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("Ready to record")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            }
            
            if !videoRecorder.isRecording && videoRecorder.videoURL == nil && importedVideoURL == nil {
                if cameraPreviewLayer == nil {
                    VStack(spacing: 16) {
                        // Setup camera button
                        Button {
                            Task {
                                await videoRecorder.requestPermissions { granted in
                                    if granted {
                                        Task {
                                            if let preview = await videoRecorder.setupCaptureSession() {
                                                await MainActor.run {
                                                    cameraPreviewLayer = preview
                                                }
                                                await videoRecorder.startSession()
                                            }
                                        }
                                    } else {
                                        showingCameraPermissionAlert = true
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "video.circle.fill")
                                Text("Record Video")
                            }
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        }
                        .buttonStyle(.plain)
                        
                        // Import video button
                        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                            HStack {
                                Image(systemName: "photo.on.rectangle")
                                Text("Import Video")
                            }
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                    .strokeBorder(DesignSystem.Colors.accent, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Start recording button (camera is already open)
                    Button {
                        Task {
                            await startRecordingWithCountdown()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "record.circle")
                            Text("Start Recording")
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .buttonStyle(.plain)
                }
            } else if videoRecorder.isRecording {
                Button {
                    videoRecorder.stopRecording()
                    Task {
                        // Wait for video to be saved before stopping session
                        try? await Task.sleep(for: .seconds(1.0))
                        await videoRecorder.stopSession()
                    }
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                        Text("Stop Recording")
                    }
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .buttonStyle(.plain)
            }
            
            // Title input
            TextField("Title (optional)", text: $memoryTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            textFieldView(text: $noteText, placeholder: "Add a note about this video (optional)...", lines: 3...5)
        }
        .alert("Camera Permission Required", isPresented: $showingCameraPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("Please enable camera and microphone access in Settings to record video messages.")
        }
    }
    
    private var milestoneFields: some View {
        VStack(spacing: 16) {
            TextField("Milestone title (e.g., First Steps)", text: $milestoneTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            TextField("Age (e.g., 12 months)", text: $milestoneAge)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            photoPickerView
            textFieldView(text: $noteText, placeholder: "Describe this special moment...", lines: 5...10)
        }
    }
    
    private var letterToFutureFields: some View {
        VStack(spacing: 16) {
            TextField("Letter title", text: $letterTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Open when they turn:")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Picker("Age", selection: $openWhenAge) {
                    ForEach([13, 16, 18, 21, 25, 30], id: \.self) { age in
                        Text("\(age) years old").tag(age)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }
            
            textFieldView(text: $noteText, placeholder: "Dear future you...", lines: 10...20)
        }
    }
    
    private var wisdomNoteFields: some View {
        VStack(spacing: 16) {
            textFieldView(text: $noteText, placeholder: "Share your wisdom, advice, or life lessons...", lines: 10...15)
        }
    }
    
    private var familyRecipeFields: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipe Name")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                ZStack(alignment: .leading) {
                    if recipeTitle.isEmpty {
                        Text("Enter recipe name")
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .padding(.leading, 16)
                    }
                    TextField("", text: $recipeTitle)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.body)
                        .autocapitalization(.words)
                        .padding()
                }
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            }
            
            photoPickerView
            
            textFieldView(text: $ingredients, placeholder: "Ingredients...", lines: 5...8)
            textFieldView(text: $instructions, placeholder: "Instructions...", lines: 8...12)
            textFieldView(text: $noteText, placeholder: "Story behind this recipe (optional)...", lines: 3...5)
        }
    }
    
    private var storyTimeFields: some View {
        VStack(spacing: 16) {
            photoPickerView
            textFieldView(text: $noteText, placeholder: "Tell a family story, folk tale, or memory...", lines: 10...20)
        }
    }
    
    // MARK: - Reusable Components
    
    private var photoPickerView: some View {
        Group {
            if let photoData, let uiImage = UIImage(data: photoData) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    
                    Button { self.photoData = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    .padding(8)
                }
            } else {
                VStack(spacing: 12) {
                    // Take Photo button
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignSystem.Colors.accentGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            .foregroundStyle(.white)
                    }
                    
                    // Import Photo button
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Import Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
            }
        }
    }
    
    private func textFieldView(text: Binding<String>, placeholder: String, lines: ClosedRange<Int>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .padding()
            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .lineLimit(lines)
    }
    
    // MARK: - Save Function
    
    private func saveMemory() {
        if forceVaultOnly {
            privacy = .vaultOnly
            giftReleaseOption = .vault
            performSaveMemory()
            return
        }
        // Check memory limit for free users
        if let profile = userProfiles.first, !hasPremiumAccess {
            let currentCount = allMemories.count
            
            if currentCount >= 10 {
                // Hard limit reached - block and show paywall
                showPaywall = true
                return
            } else if currentCount == 8 {
                // Show reminder at 8 memories (2 left)
                showMemoryReminder = true
                return
            }
        }
        
        // Handle based on privacy selection
        switch privacy {
        case .shareNow:
            // Immediate release - show scheduling to select grandchildren
            giftReleaseOption = .immediate
            showGiftScheduling = true
        case .vaultOnly:
            // Vault only - show scheduling to select grandchildren
            giftReleaseOption = .vault
            showGiftScheduling = true
        case .helloQueue:
            giftReleaseOption = .helloQueue
            showGiftScheduling = true
        case .maybeDecide:
            // Show gift scheduling to let user choose everything
            showGiftScheduling = true
        }
    }
    
    private func performSaveMemory() {
        isSavingMemory = true
        Task {
            await performSaveMemoryAsync()
        }
    }
    
    private func performSaveMemoryAsync() async {
        defer {
            Task { @MainActor in
                isSavingMemory = false
            }
        }
        let roleFallback = isCoGrandparentDevice ? ContributorRole.grandma.rawValue : ContributorRole.grandpa.rawValue
        var resolvedRecordName = iCloudUserRecordName
        if resolvedRecordName.isEmpty {
            if let fetchedRecordName = await fetchiCloudUserRecordName() {
                resolvedRecordName = fetchedRecordName
                await MainActor.run {
                    iCloudUserRecordName = fetchedRecordName
                }
            }
        }
        var resolvedContributor: CDContributor? = {
            if !resolvedRecordName.isEmpty {
                return contributorForRecordName(resolvedRecordName, roleFallback: roleFallback)
            }
            return contributors.first(where: { $0.role == roleFallback }) ?? activeContributor
        }()
        if resolvedContributor == nil {
            let role = ContributorRole(rawValue: roleFallback) ?? .grandpa
            let created = viewContext.createContributor(
                name: creatorName,
                role: role,
                colorHex: role.defaultColor
            )
            if !resolvedRecordName.isEmpty {
                created.iCloudUserRecordName = resolvedRecordName
            }
            viewContext.assign(created, to: CoreDataStack.shared.privatePersistentStore)
            resolvedContributor = created
        }
        if let resolvedContributor {
            await MainActor.run {
                if let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !profileName.isEmpty {
                    resolvedContributor.name = profileName
                }
                activeContributorID = resolvedContributor.id?.uuidString ?? activeContributorID
                currentContributorRole = resolvedContributor.role ?? currentContributorRole
                if !resolvedRecordName.isEmpty, resolvedContributor.iCloudUserRecordName != resolvedRecordName {
                    resolvedContributor.iCloudUserRecordName = resolvedRecordName
                }
            }
        }
        if isCoGrandparentDevice {
            await CoreDataStack.shared.checkForAcceptedShares()
        }
        // Determine which Core Data grandchildren to assign by matching UUIDs
        let allGrandchildrenArray = Array(allGrandchildren)
        let sharedStore = CoreDataStack.shared.sharedPersistentStore
        let sharedGrandchildren = allGrandchildrenArray.filter { $0.objectID.persistentStore == sharedStore }
        let sharedGrandchildrenFromStore: [CDGrandchild]
        if sharedGrandchildren.isEmpty {
            let request: NSFetchRequest<CDGrandchild> = CDGrandchild.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDGrandchild.name, ascending: true)]
            request.affectedStores = [sharedStore]
            sharedGrandchildrenFromStore = (try? viewContext.fetch(request)) ?? []
        } else {
            sharedGrandchildrenFromStore = sharedGrandchildren
        }
        if isCoGrandparentDevice && sharedGrandchildrenFromStore.isEmpty {
            await MainActor.run {
                saveErrorMessage = "Shared family vault not available yet. Please re-open the app or accept the share again."
                showSaveError = true
            }
            return
        }
        if allGrandchildrenArray.isEmpty && sharedGrandchildrenFromStore.isEmpty {
            await MainActor.run {
                saveErrorMessage = "No family vault found on this device yet."
                showSaveError = true
            }
            return
        }
        // Always prefer shared-store grandchildren when available to avoid cross-store saves.
        let candidateGrandchildren = sharedGrandchildrenFromStore.isEmpty ? allGrandchildrenArray : sharedGrandchildrenFromStore
        let hasSharedCandidates = !sharedGrandchildrenFromStore.isEmpty
        let grandchildrenToAssign: [CDGrandchild]
        if allowUnassigned {
            grandchildrenToAssign = []
        } else if hasSharedCandidates {
            // On shared devices, never fall back to private selection.
            let sharedSelected = selectedGrandchildren.isEmpty
                ? []
                : sharedGrandchildrenFromStore.filter { selectedGrandchildren.contains($0.id ?? UUID()) }
            if !sharedSelected.isEmpty {
                grandchildrenToAssign = sharedSelected
                print("👶 Selected \(grandchildrenToAssign.count) shared grandchildren from selection")
            } else if let grandchild = grandchild, let grandchildID = grandchild.id,
                      let matched = sharedGrandchildrenFromStore.first(where: { $0.id == grandchildID }) {
                grandchildrenToAssign = [matched]
                print("👶 Matched shared grandchild by ID: \(grandchildID)")
            } else {
                grandchildrenToAssign = sharedGrandchildrenFromStore
                print("👶 Using all shared grandchildren (\(grandchildrenToAssign.count))")
            }
        } else if candidateGrandchildren.count > 1 {
            // Multiple grandchildren exist - use selection
            guard !selectedGrandchildren.isEmpty else {

                return
            }
            grandchildrenToAssign = candidateGrandchildren.filter { selectedGrandchildren.contains($0.id ?? UUID()) }
            print("👶 Selected \(grandchildrenToAssign.count) grandchildren from selection")
        } else {
            // Single grandchild - find matching CD grandchild by ID, or use first available
            if let grandchild = grandchild, let grandchildID = grandchild.id {
                let matched = candidateGrandchildren.filter { $0.id == grandchildID }
                if !matched.isEmpty {
                    grandchildrenToAssign = matched
                    print("👶 Matched grandchild by ID: \(grandchildID)")
                } else if let first = candidateGrandchildren.first {
                    grandchildrenToAssign = [first]
                    print("👶 No match found, using first grandchild: \(first.name ?? "unknown")")
                } else {

                    return
                }
            } else {
                // Fallback to first grandchild
                guard let first = candidateGrandchildren.first else {

                    return
                }
                grandchildrenToAssign = [first]
                print("👶 Using first available grandchild: \(first.name ?? "unknown")")
            }
        }
        
        let memory: CDMemory
        
        switch memoryType {
        case .quickMoment:
            guard let photoData else { return }
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.title = memoryTitle.isEmpty ? nil : memoryTitle
            memory.note = noteText.isEmpty ? nil : noteText
            // Save photo to disk for fast local access
            if let filename = PhotoStorageManager.shared.savePhoto(photoData) {
                memory.photoFilename = filename
            }
            // Also store in Core Data for CloudKit sync
            memory.photoData = photoData
            memory.createdBy = creatorName
            
        case .milestone:
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.note = noteText.isEmpty ? nil : noteText
            if let photoData {
                // Always store in Core Data for CloudKit sync
                memory.photoData = photoData
                // Save photo to disk for fast local access
                if let filename = PhotoStorageManager.shared.savePhoto(photoData) {
                    memory.photoFilename = filename
                }
            }
            memory.createdBy = creatorName
            memory.milestoneTitle = milestoneTitle
            memory.milestoneAge = milestoneAge.isEmpty ? nil : milestoneAge
            
        case .letterToFuture:
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.note = noteText
            memory.createdBy = creatorName
            memory.letterTitle = letterTitle
            memory.openWhenAge = Int32(openWhenAge)
            
        case .wisdomNote:
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.note = noteText
            memory.createdBy = creatorName
            
        case .familyRecipe:
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.note = noteText.isEmpty ? nil : noteText
            if let photoData {
                // Always store in Core Data for CloudKit sync
                memory.photoData = photoData
                // Save photo to disk for fast local access
                if let filename = PhotoStorageManager.shared.savePhoto(photoData) {
                    memory.photoFilename = filename
                }
            }
            memory.createdBy = creatorName
            memory.recipeTitle = recipeTitle
            memory.ingredients = ingredients
            memory.instructions = instructions
            
        case .storyTime:
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.note = noteText
            if let photoData {
                // Always store in Core Data for CloudKit sync
                memory.photoData = photoData
                // Save photo to disk for fast local access
                if let filename = PhotoStorageManager.shared.savePhoto(photoData) {
                    memory.photoFilename = filename
                }
            }
            memory.createdBy = creatorName
            
        case .voiceMemory:
            guard let audioData = audioRecorder.audioData else { return }
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.title = memoryTitle.isEmpty ? nil : memoryTitle
            memory.note = noteText.isEmpty ? nil : noteText
            memory.audioData = audioData
            memory.createdBy = creatorName
            
        case .audioPhoto:
            guard let audioData = audioRecorder.audioData else { return }
            guard !audioPhotoDataList.isEmpty else { return }
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.title = memoryTitle.isEmpty ? nil : memoryTitle
            memory.note = noteText.isEmpty ? nil : noteText
            memory.audioData = audioData
            let filenames = audioPhotoDataList.compactMap { PhotoStorageManager.shared.savePhoto($0) }
            let payloadImages = audioPhotoDataList.compactMap { makeAudioPhotoThumbnailData(from: $0) }
            print("🎧 AudioPhoto save - photos: \(audioPhotoDataList.count), filenames: \(filenames.count), payload images: \(payloadImages.count)")
            if let first = filenames.first {
                memory.photoFilename = first
            }
            if let payloadData = try? JSONEncoder().encode(AudioPhotoPayload(images: payloadImages, filenames: filenames)) {
                memory.photoData = payloadData
            } else if let firstPhoto = audioPhotoDataList.first {
                memory.photoData = firstPhoto
            }
            memory.createdBy = creatorName
            
        case .videoMessage:
            // Use imported video if available, otherwise use recorded video
            var tempVideoURL = importedVideoURL ?? videoRecorder.videoURL
            guard let videoURL = tempVideoURL else { return }
            
            // If this is an imported video, copy it to a permanent location first
            if importedVideoURL != nil {
                let permanentURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
                do {
                    try FileManager.default.copyItem(at: videoURL, to: permanentURL)
                    tempVideoURL = permanentURL
                } catch {
                    print("📹 Error copying imported video: \(error)")
                    return
                }
            }
            
            guard let finalVideoURL = tempVideoURL else { return }
            
            // Read video data to store in Core Data for iCloud sync
            guard let videoData = try? Data(contentsOf: finalVideoURL) else {
                print("📹 Error reading video data")
                return
            }
            
            print("📹 Video data size: \(videoData.count / 1024 / 1024) MB")
            
            // Generate video thumbnail
            let thumbnailData = generateVideoThumbnail(from: finalVideoURL)
            
            memory = viewContext.createMemory(type: memoryType, privacy: privacy)
            memory.title = memoryTitle.isEmpty ? nil : memoryTitle
            memory.note = noteText.isEmpty ? nil : noteText
            memory.videoData = videoData
            memory.createdBy = creatorName
            
            // Set the thumbnail if generated successfully
            if let thumbnailData = thumbnailData {
                memory.videoThumbnailData = thumbnailData
            }
            
            // Clean up temporary file (only for recorded videos, not imported ones that were just copied)
            if videoRecorder.videoURL != nil {
                try? FileManager.default.removeItem(at: finalVideoURL)
            }
        }
        
        // CRITICAL FIX: Assign memory to the target store BEFORE establishing relationships.
        let targetStore: NSPersistentStore? = sharedGrandchildrenFromStore.isEmpty ? CoreDataStack.shared.privatePersistentStore : CoreDataStack.shared.sharedPersistentStore
        if let store = targetStore {
            let storeType = store == CoreDataStack.shared.sharedPersistentStore ? "SHARED" : "PRIVATE"
            if let firstGrandchild = grandchildrenToAssign.first {
                print("🔍 Grandchild '\(firstGrandchild.name ?? "unknown")' is in \(storeType) store")
            }
            print("🔍 Memory before assignment is in: \(memory.objectID.persistentStore?.identifier ?? "unknown")")
            viewContext.assign(memory, to: store)
            print("✅ Memory assigned to \(storeType) store: \(store.identifier ?? "unknown")")
            print("🔍 Memory after assignment is in: \(memory.objectID.persistentStore?.identifier ?? "unknown")")
        } else if !grandchildrenToAssign.isEmpty {
            print("⚠️ Could not assign memory to target store - using default store")
            if let defaultStore = memory.objectID.persistentStore {
                print("⚠️ Memory will be in: \(defaultStore.identifier ?? "unknown")")
            }
        } else {
            print("ℹ️ Saving to vault without assigned grandchild")
        }
        
        // Assign grandchildren - Core Data uses NSSet
        if !grandchildrenToAssign.isEmpty {
            print("💾 Assigning \(grandchildrenToAssign.count) grandchildren to memory")
            for grandchild in grandchildrenToAssign {
                print("   - Adding grandchild: \(grandchild.name ?? "unknown") (ID: \(grandchild.id?.uuidString ?? "none"))")
                memory.addToGrandchildren(grandchild)
            }
        }
        
        // Assign the active contributor (must be in same store to avoid cross-store relationships)
        if let store = targetStore,
           store == CoreDataStack.shared.sharedPersistentStore {
            if let resolvedContributor {
                let request: NSFetchRequest<CDContributor> = CDContributor.fetchRequest()
                if !resolvedRecordName.isEmpty {
                    request.predicate = NSPredicate(format: "iCloudUserRecordName == %@", resolvedRecordName)
                } else {
                    request.predicate = NSPredicate(format: "role == %@", resolvedContributor.role ?? roleFallback)
                }
                request.fetchLimit = 1
                request.affectedStores = [CoreDataStack.shared.sharedPersistentStore]
                let sharedContributor = (try? viewContext.fetch(request).first) ?? {
                    let created = viewContext.createContributor(
                        name: creatorName,
                        role: ContributorRole(rawValue: resolvedContributor.role ?? roleFallback) ?? .grandma,
                        colorHex: resolvedContributor.colorHex ?? ContributorRole.grandma.defaultColor
                    )
                    if !resolvedRecordName.isEmpty {
                        created.iCloudUserRecordName = resolvedRecordName
                    }
                    viewContext.assign(created, to: CoreDataStack.shared.sharedPersistentStore)
                    return created
                }()
                // Keep shared contributor name/color in sync with active contributor
                sharedContributor.name = creatorName
                if let role = resolvedContributor.role {
                    sharedContributor.role = role
                }
                sharedContributor.colorHex = resolvedContributor.colorHex ?? sharedContributor.colorHex
                if !resolvedRecordName.isEmpty {
                    sharedContributor.iCloudUserRecordName = resolvedRecordName
                }
                memory.contributor = sharedContributor
                print("💾 Assigned shared contributor: \(sharedContributor.displayName)")
            }
        } else {
            memory.contributor = resolvedContributor
            print("💾 Assigned contributor: \(resolvedContributor?.displayName ?? "none")")
        }

        // Apply gift scheduling settings
        switch giftReleaseOption {
        case .immediate:
            memory.isReleased = true
            memory.releaseDate = nil
            memory.releaseAge = 0
        case .specificDate:
            memory.releaseDate = giftReleaseDate
            memory.releaseAge = 0
            memory.isReleased = false
        case .atAge:
            memory.releaseDate = nil
            memory.releaseAge = Int32(giftReleaseAge)
            memory.isReleased = false
        case .vault:
            memory.isReleased = false
            memory.releaseDate = nil
            memory.releaseAge = 0
        case .helloQueue:
            memory.isReleased = false
            memory.privacy = MemoryPrivacy.helloQueue.rawValue
            memory.releaseDate = nil
            memory.releaseAge = 0
        }

        if forceVaultOnly {
            memory.privacy = MemoryPrivacy.vaultOnly.rawValue
            memory.isReleased = false
            memory.releaseDate = nil
            memory.releaseAge = 0
        }
        
        // Memory is already inserted via createMemory, no need to insert again
        
        if let profile = userProfiles.first, !hasPremiumAccess {
            profile.freeMemoryCount = Int32(allMemories.count + 1)
        }
        
        print("💾 Saving memory to Core Data...")
        do {
            try viewContext.obtainPermanentIDs(for: [memory])
            try viewContext.saveAndSync()
            print("✅ Memory saved and sync triggered")
        } catch {
            print("❌ Failed to save memory: \(error)")
        }

        // Unblock UI as soon as the local save completes; share updates can run in the background.
        await MainActor.run { isSavingMemory = false }

        // If any selected grandchild is already shared, add this memory to that existing share.
        // This must happen after the memory has a permanent ID.
        Task {
            await addMemoryToExistingShareIfNeeded(memory, grandchildren: grandchildrenToAssign)
        }

        // Schedule notification for the gift release if it has a future date
        if let releaseDate = memory.releaseDate, releaseDate > Date() {
            Task {
                await NotificationManager.shared.scheduleGiftReleaseNotification(
                    for: memory,
                    grandchildName: grandchildrenToAssign.first?.name ?? "your grandchild"
                )
            }
        }
        
        dismiss()
    }

    private func startRecordingWithCountdown() async {
        guard countdownRemaining == nil else { return }
        await MainActor.run {
            countdownCancelled = false
            countdownRemaining = 5
        }
        while let current = countdownRemaining, current > 1 {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                if !countdownCancelled {
                    countdownRemaining = current - 1
                }
            }
        }
        try? await Task.sleep(for: .seconds(1))
        await MainActor.run {
            countdownRemaining = nil
            if !countdownCancelled {
                videoRecorder.startRecording()
            }
        }
    }

    private var savingOverlay: some View {
        Group {
            if isSavingMemory {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Saving...")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
    }

    private func addMemoryToExistingShareIfNeeded(_ memory: CDMemory, grandchildren: [CDGrandchild]) async {
        let coreDataStack = CoreDataStack.shared

        // Find the first grandchild that already has a share
        for grandchild in grandchildren {
            if let existingShare = await coreDataStack.fetchShare(for: grandchild) {
                do {
                    let (_, updatedShare, _) = try await coreDataStack.persistentContainer.share([memory], to: existingShare)
                    try await coreDataStack.persistUpdatedShare(updatedShare)
                    print("✅ Added memory to existing share for grandchild: \(grandchild.name ?? "unknown")")
                } catch {
                    print("❌ Failed to add memory to share: \(error)")
                }
                return
            }
        }
    }
    
    private func generateVideoThumbnail(from videoURL: URL) -> Data? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {

            return nil
        }
    }
}

struct GrandchildToggleButton: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? DesignSystem.Colors.teal : DesignSystem.Colors.textTertiary)
                Text(name)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? DesignSystem.Colors.teal.opacity(0.1) : DesignSystem.Colors.backgroundTertiary,
                in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(isSelected ? DesignSystem.Colors.teal : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

struct SettingsTab: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allUserProfiles())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var memories: FetchedResults<CDMemory>
    @State private var showingAddGrandchild = false
    @State private var selectedGrandchildForEdit: CDGrandchild?
    @State private var selectedGrandchildForShare: CDGrandchild?
    @State private var selectedGrandchildForWelcomeVideo: CDGrandchild?
    @State private var showPaywall = false
    @State private var showSimpleCoGrandparentShare = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    @State private var showProfilePhotoPicker = false
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var showProfilePhotoEditor = false
    @State private var profilePhotoToEdit: UIImage?
    @State private var showNameEditor = false
    @State private var editedName = ""
    @State private var showDeleteBlocked = false
    @State private var deleteBlockedMessage = ""
    @State private var showFAQ = false
    @State private var showLegacyGuardian = false
    @StateObject private var storeManager = StoreKitManager.shared
    @AppStorage("isGrandchildMode") private var isGrandchildMode = false
    @AppStorage("isCoGrandparentDevice") private var isCoGrandparentDevice: Bool = false
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("currentContributorRole") private var currentContributorRole: String = ""
    
    private var displayName: String {
        // First try the user profile name
        if let profileName = userProfiles.first?.name, !profileName.isEmpty {
            return profileName
        }
        
        // Fallback to active contributor name
        if let activeContributor = contributors.first(where: { $0.id?.uuidString == activeContributorID }) {
            return activeContributor.displayName
        }
        
        // Fallback to first contributor
        if let firstContributor = contributors.first {
            return firstContributor.displayName
        }
        
        // Final fallback
        return "Grandparent"
    }
    
    var body: some View {
        NavigationStack {
            List {
                listContent
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddGrandchild) {
                AddGrandchildView()
            }
            .sheet(item: $selectedGrandchildForEdit) { grandchild in
                EditGrandchildView(grandchild: grandchild)
            }
            .sheet(item: $selectedGrandchildForShare) { grandchild in
                SimpleShareView(grandchild: grandchild, shareType: .grandchild)
            }
            .sheet(item: $selectedGrandchildForWelcomeVideo) { grandchild in
                WelcomeVideoRecorderView(grandchild: grandchild)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .onboarding, onDismiss: nil)
            }
            .sheet(isPresented: $showFAQ) {
                FAQView()
            }
            .sheet(isPresented: $showLegacyGuardian) {
                LegacyGuardianView()
            }
            .sheet(isPresented: $showProfilePhotoPicker) {
                PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                    Text("Choose Profile Photo")
                }
            }
            .sheet(isPresented: $showProfilePhotoEditor) {
                if let profilePhotoToEdit = profilePhotoToEdit {
                    PhotoCropperView(
                        image: profilePhotoToEdit,
                        onSave: { croppedData in
                            if let profile = userProfiles.first {
                                profile.photoData = croppedData
                                try? viewContext.save()
                            }
                            showProfilePhotoEditor = false
                        },
                        onCancel: {
                            showProfilePhotoEditor = false
                        }
                    )
                }
            }
            .alert("Edit Name", isPresented: $showNameEditor) {
                TextField("Your Name", text: $editedName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    let oldProfileName = userProfiles.first?.name
                    if let profile = userProfiles.first {
                        profile.name = editedName
                    }
                    if let activeContributor = contributors.first(where: { $0.id?.uuidString == activeContributorID }) {
                        activeContributor.name = editedName
                    }
                    if isCoGrandparentDevice {
                        for contributor in contributors where contributor.role == ContributorRole.grandma.rawValue {
                            contributor.name = editedName
                        }
                        for contributor in contributors where contributor.name == "Co-Grandparent" {
                            contributor.name = editedName
                        }
                    } else if !contributors.isEmpty {
                        // Fallback: update first contributor so "From" labels reflect the new name.
                        contributors.first?.name = editedName
                    }
                    // Keep active contributor aligned to the edited name
                    if let match = contributors.first(where: { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(editedName) == .orderedSame }) {
                        activeContributorID = match.id?.uuidString ?? activeContributorID
                        currentContributorRole = match.role ?? currentContributorRole
                    } else if isCoGrandparentDevice,
                              let grandma = contributors.first(where: { $0.role == ContributorRole.grandma.rawValue }) {
                        activeContributorID = grandma.id?.uuidString ?? activeContributorID
                        currentContributorRole = grandma.role ?? currentContributorRole
                    }
                    try? viewContext.save()
                }
            } message: {
                Text("Enter your name as you'd like it to appear")
            }
            .alert("Can't Delete Grandchild", isPresented: $showDeleteBlocked) {
                Button("OK") {
                    deleteBlockedMessage = ""
                    showDeleteBlocked = false
                }
            } message: {
                Text(deleteBlockedMessage)
            }
            // Use simple share link view
            .sheet(isPresented: $showSimpleCoGrandparentShare) {
                SimpleShareView(grandchild: nil, shareType: .coGrandparent)
            }
            .alert("Sharing Error", isPresented: $showShareError) {
                Button("OK") {
                    shareErrorMessage = ""
                    showShareError = false
                }
            } message: {
                Text(shareErrorMessage)
            }
            .onChange(of: selectedProfilePhoto) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        profilePhotoToEdit = uiImage
                        showProfilePhotoPicker = false
                        showProfilePhotoEditor = true
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var listContent: some View {
        profileSection
        premiumSection
        quickActionsSection
        welcomeVideosSection
        grandchildrenSection
        iCloudSection
        usageSection
        debugSection
    }
    
    private var profileSection: some View {
        Section {
            Button {
                showProfilePhotoPicker = true
            } label: {
                profileHeaderView
            }
            .buttonStyle(.plain)
            
            // Edit Name button
            Button {
                editedName = displayName
                showNameEditor = true
            } label: {
                HStack {
                    Image(systemName: "pencil")
                        .foregroundStyle(DesignSystem.Colors.teal)
                    Text("Edit Name")
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                }
            }
        }
    }
    
    
    private var quickActionsSection: some View {
        Section("Quick Actions") {
            Button {
                showSimpleCoGrandparentShare = true
            } label: {
                settingsRow(
                    icon: "person.2.fill",
                    iconColor: DesignSystem.Colors.teal,
                    title: "Invite Co-Grandparent",
                    subtitle: "Add your partner to collaborate"
                )
            }
            .buttonStyle(.plain)
            
            DisclosureGroup("How sharing works") {
                Text("1. Tap 'Invite Co-Grandparent'\n2. Enter their email or phone number\n3. Choose Messages, Gmail, or copy the link\n4. Send the invitation\n5. They'll accept and join your family vault!")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.vertical, 4)
            }
            .font(.caption)
            
            Button {
                showLegacyGuardian = true
            } label: {
                settingsRow(
                    icon: "shield.lefthalf.filled",
                    iconColor: DesignSystem.Colors.accent,
                    title: "Legacy Auto-Release",
                    subtitle: "Plan for future deliveries"
                )
            }
            .buttonStyle(.plain)
            
            Button {
                showFAQ = true
            } label: {
                settingsRow(
                    icon: "questionmark.circle",
                    iconColor: DesignSystem.Colors.textSecondary,
                    title: "FAQ",
                    subtitle: "Common questions and support"
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var welcomeVideosSection: some View {
        Section {
            ForEach(grandchildren) { grandchild in
                Button {
                    selectedGrandchildForWelcomeVideo = grandchild
                } label: {
                    welcomeVideoRow(for: grandchild)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Welcome Videos")
        } footer: {
            Text("Record a personal welcome message for each grandchild. They'll see it when they first open the app.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
    
    private func welcomeVideoRow(for grandchild: CDGrandchild) -> some View {
        HStack(spacing: 12) {
            grandchildPhotoView(for: grandchild)
            welcomeVideoTextContent(for: grandchild)
            Spacer()
            Image(systemName: "video.fill")
                .foregroundStyle(DesignSystem.Colors.accent)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func grandchildPhotoView(for grandchild: CDGrandchild) -> some View {
        if let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
    
    private func welcomeVideoTextContent(for grandchild: CDGrandchild) -> some View {
        let hasVideo = checkHasWelcomeVideo(for: grandchild)
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(grandchild.name ?? "Grandchild")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            Text(hasVideo ? "Welcome video recorded" : "No welcome video")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(hasVideo ? DesignSystem.Colors.accent : DesignSystem.Colors.textTertiary)
        }
    }
    
    private func checkHasWelcomeVideo(for grandchild: CDGrandchild) -> Bool {
        return memories.contains { memory in
            guard memory.isWelcomeVideo == true else { return false }
            guard let grandchildren = memory.grandchildren as? Set<CDGrandchild> else { return false }
            guard grandchildren.count == 1 else { return false }
            return grandchildren.contains(where: { $0.id == grandchild.id })
        }
    }
    

    private var iCloudSection: some View {
        Section {
            settingsRow(
                icon: "icloud.fill",
                iconColor: DesignSystem.Colors.primary,
                title: "iCloud Sync",
                subtitle: "Enabled"
            )
        } footer: {
            Text("All data syncs automatically across devices signed in with the same Apple ID.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
    
    @ViewBuilder
    private var usageSection: some View {
        if let profile = userProfiles.first, profile.isPremium != true {
            Section("Usage") {
                VStack(alignment: .leading, spacing: 10) {
                    settingsRow(
                        icon: "chart.bar.fill",
                        iconColor: DesignSystem.Colors.accent,
                        title: "Free memories",
                        subtitle: "\(profile.freeMemoryCount) / 10 used"
                    )
                    ProgressView(value: Double(profile.freeMemoryCount), total: 10)
                        .tint(DesignSystem.Colors.primary)
                        .padding(.leading, 48)
                        .padding(.trailing, 8)
                }
            }
        }
    }
    
    
    private func settingsRow(icon: String, iconColor: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.vertical, 4)
    }
    
    private var debugSection: some View {
        Section {
            Toggle(isOn: $isGrandchildMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grandchild Mode")
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Show grandchild gift view with filtered memories")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            .onChange(of: isGrandchildMode) { oldValue, newValue in
                Task {
                    await CloudKitSharingManager.shared.detectUserRole()
                }
            }
            
            // Reset button for testing fresh install
            Button(role: .destructive) {
                resetToFreshInstall()
            } label: {
                settingsRow(
                    icon: "arrow.counterclockwise.circle.fill",
                    iconColor: .red,
                    title: "Reset to Fresh Install",
                    subtitle: "Clears local data and restarts onboarding"
                )
            }
        } header: {
            Text("Debug (Testing Only)")
        } footer: {
            Text("Enable Grandchild Mode to test the grandchild experience. Use Reset to clear all data and start fresh (useful for testing onboarding).")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }
    
    private func deleteGrandchildren(at offsets: IndexSet) {
        let targets = offsets.map { grandchildren[$0] }
        Task {
            if isCoGrandparentDevice {
                await MainActor.run {
                    deleteBlockedMessage = "Deleting a grandchild is disabled on a co-grandparent device to prevent removing it for everyone."
                    showDeleteBlocked = true
                }
                return
            }
            for grandchild in targets {
                if await CoreDataStack.shared.isShared(grandchild) {
                    await MainActor.run {
                        deleteBlockedMessage = "This grandchild is shared with another device. Deleting would remove it for everyone, so it's disabled."
                        showDeleteBlocked = true
                    }
                    return
                }
            }
            await MainActor.run {
                for grandchild in targets {
                    viewContext.delete(grandchild)
                }
                try? viewContext.save()
            }
        }
    }
    
    private func resetToFreshInstall() {
        print("🧪 DEBUG: Reset to fresh install")
        
        // Delete all data
        for profile in userProfiles {
            viewContext.delete(profile)
        }
        for grandchild in grandchildren {
            viewContext.delete(grandchild)
        }
        for memory in memories {
            viewContext.delete(memory)
        }
        for contributor in contributors {
            viewContext.delete(contributor)
        }
        
        // Reset UserDefaults
        UserDefaults.standard.set(false, forKey: "isGrandchildMode")
        UserDefaults.standard.set("", forKey: "activeContributorID")
        
        // Save changes
        try? viewContext.save()
        
        print("✅ Reset complete - close and reopen the app")
        
        // Exit the app so user can restart fresh
        exit(0)
    }
    

    

    
    @MainActor

    private func resetContributors() {
        // Delete all existing contributors
        for contributor in contributors {
            viewContext.delete(contributor)
        }
        
        // Create fresh Grandpa and Grandma
        let grandpa = CDContributor(context: viewContext)
        grandpa.id = UUID()
        grandpa.name = "Grandpa"
        grandpa.role = ContributorRole.grandpa.rawValue
        grandpa.colorHex = ContributorRole.grandpa.defaultColor
        
        let grandma = CDContributor(context: viewContext)
        grandma.id = UUID()
        grandma.name = "Grandma"
        grandma.role = ContributorRole.grandma.rawValue
        grandma.colorHex = ContributorRole.grandma.defaultColor
        
        try? viewContext.save()
        

    }
    
    private var profilePhotoView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let profile = userProfiles.first,
               let photoData = profile.photoData,
               let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DesignSystem.Colors.primaryGradient)
            }
            
            // Edit badge
            Image(systemName: "camera.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white, DesignSystem.Colors.accent)
                .background(Circle().fill(.white).frame(width: 18, height: 18))
        }
    }
    
    @ViewBuilder
    private var premiumSection: some View {
        if !storeManager.isPremium {
            Section {
                Button {
                    showPaywall = true
                } label: {
                    premiumUpgradeRow
                }
                .buttonStyle(.plain)
            } header: {
                Text("Subscription")
            } footer: {
                Text("£19.99/year or £99.99 lifetime • Unlock unlimited memories and access all premium features")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        } else {
            Section {
                premiumActiveRow
            } header: {
                Text("Subscription")
            }
        }
    }
    
    private var premiumUpgradeRow: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accentGradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "star.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Upgrade to Premium")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                if let profile = userProfiles.first {
                    let memoryCount = Int(profile.freeMemoryCount)
                    let remaining = max(0, 10 - memoryCount)
                    Text("\(remaining) free memories remaining")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private var premiumActiveRow: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accentGradient)
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Premium Active")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text(storeManager.subscriptionStatus == .lifetime ? "Lifetime Access" : "Annual Subscription")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var grandchildrenSection: some View {
        Section {
            ForEach(grandchildren) { grandchild in
                Button(action: { selectedGrandchildForEdit = grandchild }) {
                    grandchildRow(grandchild)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteGrandchildren)
            
            Button(action: { showingAddGrandchild = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.teal)
                    Text("Add Another Grandchild")
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
            }
        } header: {
            Text("Grandchildren")
        } footer: {
            Text("Swipe left on a name to delete")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
    
    private var profileHeaderView: some View {
        HStack {
            // Profile Photo
            profilePhotoView
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text("Tap to change photo")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                // Show subscription status: Free, Annual, or Lifetime
                if storeManager.isPremium {
                    Text(storeManager.subscriptionStatus == .lifetime ? "Lifetime" : "Annual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Show free memories countdown for free users
                if !storeManager.isPremium, let profile = userProfiles.first {
                    let memoryCount = Int(profile.freeMemoryCount)
                    let remaining = max(0, 10 - memoryCount)
                    Text("\(remaining) free memories left")
                        .font(.caption2)
                        .foregroundStyle(remaining <= 2 ? .red : DesignSystem.Colors.textTertiary)
                }
            }
        }
    }
    
    private func grandchildRow(_ grandchild: CDGrandchild) -> some View {
        HStack(spacing: 12) {
            if let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            
            VStack(alignment: .leading) {
                Text(grandchild.name ?? "Grandchild").font(.headline)
                Text(grandchild.ageDisplay).font(.caption).foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                selectedGrandchildForShare = grandchild
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .font(.caption)
                    Text("Share")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DesignSystem.Colors.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Welcome Video Recorder View

struct WelcomeVideoRecorderView: View {
    let grandchild: CDGrandchild
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allUserProfiles())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var memories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    
    @State private var videoRecorder = VideoRecorder()
    @State private var showingCameraPermissionAlert = false
    @State private var cameraPreviewLayer: AVCaptureVideoPreviewLayer?
    @State private var welcomeVideoData: Data?
    
    private var activeContributor: CDContributor? {
        contributors.first { $0.id?.uuidString == activeContributorID }
    }

    private var creatorName: String {
        let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profileName, !profileName.isEmpty {
            return profileName
        }
        let contributorName = activeContributor?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let contributorName, !contributorName.isEmpty {
            return contributorName
        }
        return "Grandparent"
    }
    
    private var existingWelcomeVideo: CDMemory? {
        memories.first { memory in
            guard memory.isWelcomeVideo == true else { return false }
            let grandchildrenSet = memory.grandchildren as? Set<CDGrandchild> ?? []
            return grandchildrenSet.count == 1 && grandchildrenSet.contains(where: { $0.id == grandchild.id })
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    if videoRecorder.isRecording || welcomeVideoData != nil {
                        // Recording UI
                        VStack(spacing: 24) {
                            Spacer()
                            
                            // Camera preview
                    if let previewLayer = cameraPreviewLayer {
                        CameraPreviewView(previewLayer: previewLayer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(DesignSystem.Colors.accent, lineWidth: 3)
                            )
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Task { await videoRecorder.switchCamera() }
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .padding(10)
                                        .background(Color.black.opacity(0.6), in: Circle())
                                }
                                .padding(12)
                            }
                    }
                            
                            if videoRecorder.isRecording {
                                // Recording indicator
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 12, height: 12)
                                    Text("Recording...")
                                        .font(DesignSystem.Typography.headline)
                                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                                }
                            }
                            
                            // Controls
                            if welcomeVideoData != nil {
                                VStack(spacing: 20) {
                                    VStack(spacing: 8) {
                                        Text("Perfect! 🎉")
                                            .font(DesignSystem.Typography.title2)
                                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                                        
                                        Text("Set this as \(grandchild.firstName)'s welcome video?")
                                            .font(DesignSystem.Typography.body)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    
                                    VStack(spacing: 12) {
                                        Button {
                                            saveWelcomeVideo()
                                        } label: {
                                            HStack {
                                                Image(systemName: "checkmark.circle.fill")
                                                Text("Set as Welcome Video for \(grandchild.firstName)")
                                            }
                                            .font(DesignSystem.Typography.headline)
                                            .foregroundStyle(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(DesignSystem.Colors.primaryGradient)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        
                                        Button {
                                            welcomeVideoData = nil
                                            videoRecorder.deleteRecording()
                                        } label: {
                                            Text("Re-record")
                                                .font(DesignSystem.Typography.body)
                                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                                .padding(.vertical, 12)
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            } else if videoRecorder.isRecording {
                                Button {
                                    stopRecording()
                                } label: {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 70, height: 70)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(.white)
                                                .frame(width: 24, height: 24)
                                        )
                                }
                            }
                            
                            Spacer()
                        }
                        .padding()
                    } else {
                        // Initial state
                        VStack(spacing: 32) {
                            Spacer()
                            
                            Image(systemName: "video.circle.fill")
                                .font(.system(size: 100))
                                .foregroundStyle(DesignSystem.Colors.primaryGradient)
                            
                            VStack(spacing: 12) {
                                Text(existingWelcomeVideo != nil ? "Re-record Welcome Video" : "Record Welcome Video")
                                    .font(DesignSystem.Typography.largeTitle)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                
                                Text("for \(grandchild.firstName)")
                                    .font(DesignSystem.Typography.title2)
                                    .foregroundStyle(DesignSystem.Colors.accent)
                                
                                Text("Record a special greeting that \(grandchild.firstName) will see when they first open the app")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            
                            Spacer()
                            
                            Button {
                                startRecording()
                            } label: {
                                HStack {
                                    Image(systemName: "video.fill")
                                    Text("Start Recording")
                                }
                                .primaryButton()
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle("Welcome Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
            .alert("Camera Permission Required", isPresented: $showingCameraPermissionAlert) {
                Button("Settings", action: openSettings)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Please enable camera access in Settings to record your welcome video")
            }
            .onAppear {

            }
        }
    }
    
    private func startRecording() {
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            
            if status == .authorized {
                // Only set up session if we haven't already
                if cameraPreviewLayer == nil {
                    await MainActor.run {
                        videoRecorder.setPreferredPosition(.front)
                    }
                    let previewLayer = await videoRecorder.setupCaptureSession()
                    await MainActor.run {
                        cameraPreviewLayer = previewLayer
                    }
                    
                    // Start session and wait for it to be ready
                    await videoRecorder.startSession()
                    
                    // Give the camera more time to warm up and show preview clearly
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    print("🎥 Camera warmed up, starting recording")
                } else {
                    // Session already exists, just ensure it's running
                    await videoRecorder.startSession()
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                
                // Now start recording
                await MainActor.run {
                    videoRecorder.startRecording()
                }
            } else if status == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    await MainActor.run {
                        videoRecorder.setPreferredPosition(.front)
                    }
                    let previewLayer = await videoRecorder.setupCaptureSession()
                    await MainActor.run {
                        cameraPreviewLayer = previewLayer
                    }
                    
                    // Start session and wait for it to be ready
                    await videoRecorder.startSession()
                    
                    // Give the camera more time to warm up and show preview clearly
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    print("🎥 Camera warmed up, starting recording")
                    
                    // Now start recording
                    await MainActor.run {
                        videoRecorder.startRecording()
                    }
                } else {
                    await MainActor.run {
                        showingCameraPermissionAlert = true
                    }
                }
            } else {
                await MainActor.run {
                    showingCameraPermissionAlert = true
                }
            }
        }
    }
    
    private func stopRecording() {
        videoRecorder.stopRecording()
        
        // Wait briefly for the video to be saved
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            
            await MainActor.run {
                if let videoURL = videoRecorder.videoURL {
                    do {
                        welcomeVideoData = try Data(contentsOf: videoURL)
                    } catch {

                    }
                }
                cameraPreviewLayer = nil
            }
            
            await videoRecorder.stopSession()
        }
    }
    
    private func saveWelcomeVideo() {
        guard let videoData = welcomeVideoData else { return }
        
        // Delete existing welcome video for this grandchild if it exists
        if let existingVideo = existingWelcomeVideo {
            viewContext.delete(existingVideo)
        }
        
        // Create new welcome video memory
        let memory = CDMemory(context: viewContext)
        memory.id = UUID()
        memory.date = Date()
        memory.memoryType = MemoryType.videoMessage.rawValue
        memory.privacy = MemoryPrivacy.shareNow.rawValue
        memory.title = "Welcome Video for \(grandchild.firstName)"
        memory.videoData = videoData
        memory.createdBy = creatorName
        memory.isWelcomeVideo = true
        memory.isReleased = true
        memory.wasWatched = false
        
        // Generate thumbnail from video data
        if let cachedURL = VideoCache.shared.url(for: videoData),
           let thumbnailData = generateVideoThumbnail(from: cachedURL) {
            memory.videoThumbnailData = thumbnailData
            print("📸 Generated video thumbnail (\(thumbnailData.count) bytes)")
        } else {

        }
        
        // Associate with only this specific grandchild
        memory.grandchildren = NSSet(array: [grandchild])
        
        do {
            try viewContext.save()

            print("   - Memory ID: \(memory.id?.uuidString ?? "none")")
            print("   - isWelcomeVideo: \(memory.isWelcomeVideo ?? false)")
            print("   - isReleased: \(memory.isReleased ?? false)")
            print("   - wasWatched: \(memory.wasWatched ?? false)")
            print("   - Grandchildren count: \(memory.grandchildren?.count ?? 0)")
            print("   - Video data size: \(videoData.count) bytes")
            dismiss()
        } catch {

        }
    }
    
    private func generateVideoThumbnail(from videoURL: URL) -> Data? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {

            return nil
        }
    }
    
    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

struct AddGrandchildView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var name = ""
    @State private var birthDate = Date()
    @State private var photoData: Data?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showPhotoCropper = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    DatePicker("Birthday", selection: $birthDate, displayedComponents: .date)
                }
                
                Section("Photo") {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        HStack {
                            if let photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 150, height: 150)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill.badge.plus")
                                    .font(.system(size: 80))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
            }
            .navigationTitle("Add Grandchild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addGrandchild()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        photoData = data
                        showPhotoCropper = true
                    }
                }
            }
            .sheet(isPresented: $showPhotoCropper) {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    PhotoCropperView(
                        image: uiImage,
                        onSave: { croppedData in
                            self.photoData = croppedData
                            showPhotoCropper = false
                        },
                        onCancel: {
                            showPhotoCropper = false
                        }
                    )
                }
            }
        }
    }
    
    private func addGrandchild() {
        let grandchild = CDGrandchild(context: viewContext)
        grandchild.id = UUID()
        grandchild.name = name
        grandchild.birthDate = birthDate
        grandchild.photoData = photoData
        try? viewContext.save()
        dismiss()
    }
}

struct EditGrandchildView: View {
    let grandchild: CDGrandchild
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var name: String
    @State private var birthDate: Date
    @State private var photoData: Data?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showPhotoCropper = false
    
    init(grandchild: CDGrandchild) {
        self.grandchild = grandchild
        _name = State(initialValue: grandchild.name ?? "")
        _birthDate = State(initialValue: grandchild.birthDate ?? Date())
        _photoData = State(initialValue: grandchild.photoData)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Photo picker
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            if let photoData = photoData, let uiImage = UIImage(data: photoData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 150, height: 150)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(DesignSystem.Colors.primary, lineWidth: 3))
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.Colors.backgroundTertiary)
                                        .frame(width: 120, height: 120)
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.crop.circle.fill.badge.plus")
                                            .font(.system(size: 40))
                                            .foregroundStyle(DesignSystem.Colors.primary)
                                        Text("Add Photo")
                                            .font(.caption)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onChange(of: photoPickerItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                photoData = data
                                showPhotoCropper = true
                            }
                        }
                    }
                }
                
                Section {
                    TextField("Name", text: $name)
                    DatePicker("Birthday", selection: $birthDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Edit Grandchild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showPhotoCropper) {
                if let photoData, let uiImage = UIImage(data: photoData) {
                    PhotoCropperView(
                        image: uiImage,
                        onSave: { croppedData in
                            self.photoData = croppedData
                            showPhotoCropper = false
                        },
                        onCancel: {
                            showPhotoCropper = false
                        }
                    )
                }
            }
        }
    }
    
    private func saveChanges() {
        grandchild.name = name
        grandchild.birthDate = birthDate
        grandchild.photoData = photoData
        try? viewContext.save()
        dismiss()
    }
}

struct MemoryDetailView: View {
    let memory: CDMemory
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: FetchRequestBuilders.userProfile())
    private var userProfiles: FetchedResults<CDUserProfile>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("iCloudUserRecordName") private var iCloudUserRecordName: String = ""
    @State private var isEditing = false
    @State private var noteText: String
    @State private var titleText: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteNotAllowed = false
    
    // Memory-type specific fields
    @State private var milestoneTitle: String
    @State private var milestoneAge: String
    @State private var recipeTitle: String
    @State private var ingredients: String
    @State private var instructions: String
    @State private var letterTitle: String
    @State private var openWhenAge: Int
    
    // Audio playback
    @State private var audioRecorder = AudioRecorder()
    @State private var audioPhotoIndex = 0
    @State private var audioPhotoTask: Task<Void, Never>?
    
    // Full-screen video
    @State private var showFullScreenVideo = false
    @State private var fullScreenVideoURL: URL?
    
    // Full-screen photo
    @State private var showFullScreenPhoto = false
    @State private var fullScreenPhotoImage: UIImage?
    @State private var showAudioPhotoFullScreen = false
    @State private var audioPhotoFullScreenPayload: AudioPhotoFullScreenPayload?
    
    // Photo editor
    @State private var showPhotoEditor = false
    
    // Release scheduling
    @State private var releaseDate: Date
    @State private var releaseAge: Int
    @State private var hasReleaseDate: Bool
    @State private var hasReleaseAge: Bool
    
    init(memory: CDMemory) {
        self.memory = memory
        self._titleText = State(initialValue: memory.title ?? "")
        self._noteText = State(initialValue: memory.note ?? "")
        self._photoData = State(initialValue: memory.photoData)
        self._milestoneTitle = State(initialValue: memory.milestoneTitle ?? "")
        self._milestoneAge = State(initialValue: memory.milestoneAge ?? "")
        self._recipeTitle = State(initialValue: memory.recipeTitle ?? "")
        self._ingredients = State(initialValue: memory.ingredients ?? "")
        self._instructions = State(initialValue: memory.instructions ?? "")
        self._letterTitle = State(initialValue: memory.letterTitle ?? "")
        self._openWhenAge = State(initialValue: Int(memory.openWhenAge))
        self._releaseDate = State(initialValue: memory.releaseDate ?? Date())
        self._releaseAge = State(initialValue: Int(memory.releaseAge))
        self._hasReleaseDate = State(initialValue: memory.releaseDate != nil)
        self._hasReleaseAge = State(initialValue: memory.releaseAge > 0)
    }
    
    // Get gradient based on contributor
    private var contributorGradient: LinearGradient {
        guard let contributor = memory.contributor,
              let colorHex = contributor.colorHex else {
            return DesignSystem.Colors.tealGradient
        }
        
        let baseColor = Color(hex: colorHex)
        let lightColor = baseColor.opacity(0.8)
        return LinearGradient(
            colors: [baseColor, lightColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    @ViewBuilder
    private var videoPlayerView: some View {
        if let videoData = memory.videoData,
           let cachedURL = VideoCache.shared.url(for: videoData) {
            VideoPlayerView(url: cachedURL)
                .frame(height: 400)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                .onTapGesture {
                    fullScreenVideoURL = cachedURL
                    showFullScreenVideo = true
                }
        } else if let videoPath = memory.videoURL {
            let videoURL = URL(fileURLWithPath: videoPath)
            VideoPlayerView(url: videoURL)
                .frame(height: 400)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                .onTapGesture {
                    fullScreenVideoURL = videoURL
                    showFullScreenVideo = true
                }
        }
    }
    
    @ViewBuilder
    private var editingPhotoSection: some View {
        if let photoData, let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                choosePhotoLabel
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Group {
                        Color.clear.frame(height: 0)
                    }
                    // Debug
                    Text("Memory: \(memory.title ?? "No title")")
                        .hidden()
                        .onAppear {
                            print("📝 MemoryDetailView appeared for: \(memory.title ?? "nil")")
                            print("📝 Photo filename: \(memory.photoFilename ?? "none")")
                        }
                    
                    if isEditing {
                        editingContent
                    } else {
                        viewingContent
                    }
                }
                .padding()
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .alert("Delete Memory?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    viewContext.delete(memory)
                    viewContext.saveIfNeeded()
                    dismiss()
                }
            } message: {
                Text("This memory will be permanently deleted from your account and your grandchild's account. This cannot be undone.")
            }
            .alert("Can't Delete This Memory", isPresented: $showingDeleteNotAllowed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You can only delete memories you created.")
            }
            .navigationTitle(isEditing ? "Edit Memory" : "Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if isEditing {
                            isEditing = false
                            titleText = memory.title ?? ""
                            noteText = memory.note ?? ""
                            photoData = memory.photoData
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button("Edit") {
                                isEditing = true
                            }
                            Button(role: .destructive) {
                                if canDelete(memory) {
                                    showingDeleteConfirmation = true
                                } else {
                                    showingDeleteNotAllowed = true
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullScreenVideo) {
                if let videoURL = fullScreenVideoURL {
                    FullScreenVideoPlayer(videoURL: videoURL, isPresented: $showFullScreenVideo)
                }
            }
            .fullScreenCover(isPresented: $showAudioPhotoFullScreen) {
                if let payload = audioPhotoFullScreenPayload {
                    FullScreenAudioPhotoPlayer(
                        images: payload.images,
                        audioData: payload.audioData,
                        isPresented: $showAudioPhotoFullScreen
                    )
                }
            }
            .overlay {
                if showFullScreenPhoto, let image = fullScreenPhotoImage {
                    FullScreenImageViewer(
                        image: image,
                        isPresented: $showFullScreenPhoto
                    )
                    .ignoresSafeArea()
                    .zIndex(999)
                }
            }
            .sheet(isPresented: $showPhotoEditor) {
                if let data = photoData, let uiImage = UIImage(data: data) {
                    PhotoEditorView(image: uiImage) { editedImage in
                        handlePhotoEdit(editedImage)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var memoryTypeSpecificFields: some View {
        switch memory.memoryTypeEnum {
        case .milestone:
            TextField("Milestone Title", text: $milestoneTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            TextField("Age (e.g., 2 years, 6 months)", text: $milestoneAge)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            TextField("Note (optional)", text: $noteText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .lineLimit(3...5)
        
        case .familyRecipe:
            TextField("Recipe Name", text: $recipeTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            TextField("Ingredients", text: $ingredients, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .lineLimit(5...8)
            
            TextField("Instructions", text: $instructions, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .lineLimit(8...12)
            
            TextField("Story behind this recipe (optional)", text: $noteText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .lineLimit(3...5)
        
        case .letterToFuture:
            TextField("Letter Title", text: $letterTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            Picker("Open When Age", selection: $openWhenAge) {
                ForEach([13, 16, 18, 21, 25, 30], id: \.self) { age in
                    Text("\(age) years old").tag(age)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            
            TextField("Letter Content", text: $noteText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .lineLimit(10...20)
        
        case .videoMessage, .voiceMemory:
            TextField("Add a note (optional)", text: $noteText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .lineLimit(3...5)
        
        default:
            TextField("What happened?", text: $noteText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                .lineLimit(5...10)
        }
    }
    
    private func saveChanges() {
        Task {
            await saveChangesAsync()
        }
    }
    
    private func saveChangesAsync() async {
        // Update common fields
        memory.title = titleText.isEmpty ? nil : titleText
        memory.note = noteText.isEmpty ? nil : noteText
        if let photoData {
            // Always store in Core Data for CloudKit sync
            memory.photoData = photoData
            // Save photo to disk for fast local access
            if let filename = PhotoStorageManager.shared.savePhoto(photoData) {
                memory.photoFilename = filename
            }
        }
        
        // Update memory-type specific fields
        switch memory.memoryTypeEnum {
        case .milestone:
            memory.milestoneTitle = milestoneTitle.isEmpty ? nil : milestoneTitle
            memory.milestoneAge = milestoneAge.isEmpty ? nil : milestoneAge
            
        case .familyRecipe:
            memory.recipeTitle = recipeTitle.isEmpty ? nil : recipeTitle
            memory.ingredients = ingredients.isEmpty ? nil : ingredients
            memory.instructions = instructions.isEmpty ? nil : instructions
            
        case .letterToFuture:
            memory.letterTitle = letterTitle.isEmpty ? nil : letterTitle
            memory.openWhenAge = Int32(openWhenAge)
            
        default:
            break
        }
        
        // Update release scheduling
        memory.releaseDate = hasReleaseDate ? releaseDate : nil
        memory.releaseAge = hasReleaseAge ? Int32(releaseAge) : 0
        
        // Update isReleased status based on scheduling
        if memory.releaseDate == nil && memory.releaseAge == 0 {
            // No scheduling, mark as released
            memory.isReleased = true
        } else {
            // Has scheduling, mark as not released yet
            memory.isReleased = false
        }
        
        viewContext.saveIfNeeded()
        
        // Schedule notification if there's a release date in the future
        // TODO: Convert this view to use Core Data
        // if let releaseDate = memory.releaseDate, releaseDate > Date() {
        //     Task {
        //         await NotificationManager.shared.scheduleGiftReleaseNotification(
        //             for: memory,
        //             grandchildName: memory.grandchildren?.first?.name ?? "your grandchild"
        //         )
        //     }
        // }
        
        isEditing = false
        dismiss()
    }
    
    @ViewBuilder
    private var editingContent: some View {
        Group {
            VStack(spacing: 16) {
                editingPhotoSection
                TextField("Title (optional)", text: $titleText)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                memoryTypeSpecificFields
            }
        }
    }
    
    @ViewBuilder
    private var viewingContent: some View {
        memoryTypeBadge
        titleSection
        if memory.memoryType == MemoryType.audioPhoto.rawValue {
            mediaContentSection
            audioPlayerSection
        } else {
            audioPlayerSection
            mediaContentSection
        }
        noteSection
        metadataSection
        contributorSection
        releaseInfoSection
        Divider().padding(.vertical, DesignSystem.Spacing.md)
        deleteButton
    }
    
    private var memoryTypeBadge: some View {
        HStack {
            Text(memory.memoryType ?? "Memory")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(contributorGradient, in: Capsule())
            Spacer()
        }
    }
    
    @ViewBuilder
    private var titleSection: some View {
        let trimmedTitle = memory.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text(trimmedTitle.isEmpty ? "No title" : trimmedTitle)
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(trimmedTitle.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
    }
    
    @ViewBuilder
    private var audioPlayerSection: some View {
        if memory.memoryType == MemoryType.voiceMemory.rawValue, let audioData = memory.audioData {
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    Button {
                        if audioRecorder.isPlaying {
                            audioRecorder.stopPlaying()
                        } else {
                            audioRecorder.playAudio(from: audioData)
                        }
                    } label: {
                        Image(systemName: audioRecorder.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(DesignSystem.Colors.primaryGradient)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(audioRecorder.isPlaying ? "Playing" : "Voice Memory")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text("Tap to " + (audioRecorder.isPlaying ? "pause" : "play"))
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "waveform")
                        .font(.title)
                        .foregroundStyle(DesignSystem.Colors.teal)
                        .symbolEffect(.variableColor, isActive: audioRecorder.isPlaying)
                }
                .padding()
                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            }
        } else if memory.memoryType == MemoryType.audioPhoto.rawValue {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var mediaContentSection: some View {
        if memory.memoryType == MemoryType.videoMessage.rawValue {
            videoPlayerView
        } else if memory.memoryType == MemoryType.audioPhoto.rawValue {
            let images = memory.audioPhotoImages
            if !images.isEmpty, let audioData = memory.audioData {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button {
                            if audioRecorder.isPlaying {
                                audioRecorder.stopPlaying()
                                stopAudioPhotoSlideshow()
                            } else {
                                audioRecorder.playAudio(from: audioData)
                                startAudioPhotoSlideshow(imageCount: images.count, duration: audioDuration(for: audioData))
                            }
                        } label: {
                            Image(systemName: audioRecorder.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(DesignSystem.Colors.primaryGradient)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audioRecorder.isPlaying ? "Playing" : "Audio Photo Story")
                                .font(DesignSystem.Typography.subheadline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            Text("Tap to " + (audioRecorder.isPlaying ? "pause" : "play"))
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.teal)
                            .symbolEffect(.variableColor, isActive: audioRecorder.isPlaying)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    
                    ZStack {
                        if let uiImage = UIImage(data: images[audioPhotoIndex]) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                                .id(audioPhotoIndex)
                                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                                .onTapGesture {
                                    audioPhotoFullScreenPayload = AudioPhotoFullScreenPayload(images: images, audioData: audioData)
                                    showAudioPhotoFullScreen = true
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 520)
                    .clipped()
                    .animation(.easeInOut, value: audioPhotoIndex)
                    
                    Text("\(audioPhotoIndex + 1) of \(images.count)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut) {
                                audioPhotoIndex = max(audioPhotoIndex - 1, 0)
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title2)
                        }
                        .disabled(audioPhotoIndex == 0)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(images.indices, id: \.self) { index in
                                    if let thumb = UIImage(data: images[index]) {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(index == audioPhotoIndex ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
                                            )
                                            .onTapGesture {
                                                withAnimation(.easeInOut) {
                                                    audioPhotoIndex = index
                                                }
                                            }
                                    }
                                }
                            }
                        }
                        
                        Button {
                            withAnimation(.easeInOut) {
                                audioPhotoIndex = min(audioPhotoIndex + 1, images.count - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title2)
                        }
                        .disabled(audioPhotoIndex >= images.count - 1)
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
                .onAppear {
                    audioPhotoIndex = 0
                    stopAudioPhotoSlideshow()
                }
                .onDisappear {
                    stopAudioPhotoSlideshow()
                }
                .onChange(of: audioRecorder.isPlaying) { _, isPlaying in
                    if isPlaying {
                        startAudioPhotoSlideshow(imageCount: images.count, duration: audioDuration(for: memory.audioData ?? Data()))
                    } else {
                        stopAudioPhotoSlideshow()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity, maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            }
        } else {
            // Load photo from disk using filename or fallback to photoData
            let photoData = memory.loadedPhotoData
            let _ = print("📷 Loading photo - filename: \(memory.photoFilename ?? "none"), photoData size: \(memory.photoData?.count ?? 0), loaded size: \(photoData?.count ?? 0)")
            if let data = photoData, let uiImage = UIImage(data: data) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        .onTapGesture {
                            print("📸 Photo tapped in detail view - setting image")
                            fullScreenPhotoImage = uiImage
                            showFullScreenPhoto = true
                            print("📸 showFullScreenPhoto set: \(showFullScreenPhoto)")
                            print("📸 fullScreenPhotoImage set: \(fullScreenPhotoImage != nil)")
                        }
                }
            } else {
                // Show placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 300)
                    .overlay {
                        VStack {
                            Text("No photo available")
                                .foregroundStyle(.secondary)
                            Text("Filename: \(memory.photoFilename ?? "none")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            }
        }
    }
    
    private func startAudioPhotoSlideshow(imageCount: Int, duration: TimeInterval) {
        stopAudioPhotoSlideshow()
        guard imageCount > 1 else { return }
        let safeDuration = max(duration, 1.0)
        let secondsPerImage = max(1.0, safeDuration / Double(imageCount))
        
        audioPhotoTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(secondsPerImage))
                if Task.isCancelled { break }
                withAnimation(.easeInOut) {
                    audioPhotoIndex = (audioPhotoIndex + 1) % imageCount
                }
            }
        }
    }
    
    private func stopAudioPhotoSlideshow() {
        audioPhotoTask?.cancel()
        audioPhotoTask = nil
    }
    
    private func audioDuration(for data: Data) -> TimeInterval {
        if let player = try? AVAudioPlayer(data: data) {
            return player.duration
        }
        return audioRecorder.recordingDuration
    }
    
    @ViewBuilder
    private var noteSection: some View {
        if !noteText.isEmpty {
            Text(noteText)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
    
    private var metadataSection: some View {
        HStack {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(memory.formattedDate)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
    
    @ViewBuilder
    private var contributorSection: some View {
        if let contributor = memory.contributor {
            ContributorBadge(contributor: contributor)
        }
    }
    
    @ViewBuilder
    private var releaseInfoSection: some View {
        if let releaseDate = memory.releaseDate {
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                Text("Scheduled for: \(releaseDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.accent.opacity(0.1), in: Capsule())
        }
        
        if memory.releaseAge > 0 {
            HStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
                Text("Release at age \(memory.releaseAge)")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.accent.opacity(0.1), in: Capsule())
        }
    }
    
    private var deleteButton: some View {
        Button(role: .destructive) {
            if canDelete(memory) {
                showingDeleteConfirmation = true
            } else {
                showingDeleteNotAllowed = true
            }
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Memory")
            }
            .font(DesignSystem.Typography.body)
            .frame(maxWidth: .infinity)
            .padding()
            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
        }
    }

    private func canDelete(_ memory: CDMemory) -> Bool {
        if let contributorId = memory.contributor?.id?.uuidString, !activeContributorID.isEmpty {
            return contributorId == activeContributorID
        }
        if let recordName = memory.contributor?.iCloudUserRecordName, !recordName.isEmpty,
           !iCloudUserRecordName.isEmpty {
            return recordName == iCloudUserRecordName
        }
        if let createdBy = memory.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return createdBy == profileName
        }
        return false
    }
    
    private func handlePhotoEdit(_ editedImage: UIImage) {
        print("📸 Photo edited - updating memory")
        // Convert edited image to data
        if let imageData = editedImage.jpegData(compressionQuality: 0.8) {
            photoData = imageData
            memory.photoData = imageData
            
            // Update file on disk if filename exists
            if let filename = memory.photoFilename {
                PhotoStorageManager.shared.updatePhoto(imageData, filename: filename)
            }
            
            viewContext.saveIfNeeded()
            print("📸 ✅ Photo updated successfully")
        }
    }
    
    private var choosePhotoLabel: some View {
        Label("Choose Photo", systemImage: "photo")
            .frame(maxWidth: .infinity)
            .padding()
            .background(DesignSystem.Colors.accentGradient, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            .foregroundStyle(.white)
    }
}

struct PhotoImportView: View {
    let grandchild: CDGrandchild?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allUserProfiles())
    private var userProfiles: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @AppStorage("isCoGrandparentDevice") private var isCoGrandparentDevice: Bool = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var importedPhotos: [ImportedPhoto] = []
    @State private var isProcessing = false
    @State private var showPaywall = false
    @State private var showMemoryReminder = false
    @StateObject private var storeManager = StoreKitManager.shared

    private var hasPremiumAccess: Bool {
        storeManager.isPremium || isCoGrandparentDevice
    }
    
    private var activeContributor: CDContributor? {
        contributors.first { $0.id?.uuidString == activeContributorID }
    }

    private var creatorName: String {
        let profileName = userProfiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profileName, !profileName.isEmpty {
            return profileName
        }
        let contributorName = activeContributor?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let contributorName, !contributorName.isEmpty {
            return contributorName
        }
        return "Grandparent"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if importedPhotos.isEmpty {
                    VStack(spacing: 24) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 60))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        
                        Text("Import Photos")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Text("Select photos from your camera roll.\nOriginal dates will be preserved.")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        PhotosPicker(selection: $selectedItems, maxSelectionCount: 20, matching: .images) {
                            Text("Select Photos")
                                .primaryButton()
                        }
                        .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DesignSystem.Colors.backgroundPrimary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach($importedPhotos) { $photo in
                                ImportedPhotoCard(photo: $photo) {
                                    importedPhotos.removeAll { $0.id == photo.id }
                                }
                            }
                        }
                        .padding()
                    }
                    .background(DesignSystem.Colors.backgroundPrimary)
                }
            }
            .navigationTitle("Import Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if !importedPhotos.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import \(importedPhotos.count)") {
                            saveImportedPhotos()
                        }
                        .bold()
                    }
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    await processSelectedPhotos(newItems)
                }
            }
            .overlay {
                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView("Processing photos...")
                            .padding()
                            .background(DesignSystem.Colors.backgroundPrimary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: .memoryLimit) {
                    // Paywall dismissed - they may have purchased
                    // Try saving again if they're now premium
                    if hasPremiumAccess {
                        performSaveImportedPhotos()
                    }
                }
            }
            .alert("Only 2 Free Memories Left!", isPresented: $showMemoryReminder) {
                Button("Upgrade Now") {
                    showPaywall = true
                }
                Button("Continue", role: .cancel) {
                    performSaveImportedPhotos()
                }
            } message: {
                Text("You've used 8 of your 10 free memories. Upgrade to unlimited memories anytime!")
            }
        }
    }
    
    private func processSelectedPhotos(_ items: [PhotosPickerItem]) async {
        await MainActor.run { isProcessing = true }
        var photos: [ImportedPhoto] = []
        
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               UIImage(data: data) != nil {
                
                // Extract creation date and location from photo metadata
                var creationDate = Date()
                var locationName: String?
                var latitude: Double?
                var longitude: Double?
                
                // Try to get the asset identifier and fetch from Photos library (most reliable)
                if let assetIdentifier = item.itemIdentifier {
                    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                    if let asset = fetchResult.firstObject {
                        if let assetDate = asset.creationDate {
                            creationDate = assetDate
                            print("📸 PHAsset date found: \(assetDate)")
                        }
                        
                        // Get location from PHAsset
                        if let location = asset.location {
                            latitude = location.coordinate.latitude
                            longitude = location.coordinate.longitude
                            print("📍 Location found: \(latitude!), \(longitude!)")
                            
                            // Reverse geocode to get readable location name
                            let geocoder = CLGeocoder()
                            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                                let components = [placemark.locality, placemark.administrativeArea, placemark.country]
                                    .compactMap { $0 }
                                locationName = components.joined(separator: ", ")
                                print("📍 Location name: \(locationName ?? "Unknown")")
                            }
                        }
                    }
                } else {
                    // Fallback: Extract from EXIF metadata
                    if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                       let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] {
                        
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                        
                        // Try EXIF DateTimeOriginal first (most accurate - when photo was taken)
                        if let exifData = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
                           let dateString = exifData[kCGImagePropertyExifDateTimeOriginal as String] as? String,
                           let date = formatter.date(from: dateString) {
                            creationDate = date
                            print("📸 EXIF date found: \(dateString)")
                        }
                        // Fall back to TIFF DateTime
                        else if let tiffData = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
                                let dateString = tiffData[kCGImagePropertyTIFFDateTime as String] as? String,
                                let date = formatter.date(from: dateString) {
                            creationDate = date
                            print("📸 TIFF date found: \(dateString)")
                        }
                        // Fall back to file creation date from Photos
                        else {

                        }
                        
                        // Extract GPS data from EXIF
                        if let gpsData = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                            if let lat = gpsData[kCGImagePropertyGPSLatitude as String] as? Double,
                               let latRef = gpsData[kCGImagePropertyGPSLatitudeRef as String] as? String,
                               let lon = gpsData[kCGImagePropertyGPSLongitude as String] as? Double,
                               let lonRef = gpsData[kCGImagePropertyGPSLongitudeRef as String] as? String {
                                
                                latitude = (latRef == "S") ? -lat : lat
                                longitude = (lonRef == "W") ? -lon : lon
                                print("📍 GPS found: \(latitude!), \(longitude!)")
                                
                                // Reverse geocode
                                let location = CLLocation(latitude: latitude!, longitude: longitude!)
                                let geocoder = CLGeocoder()
                                if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                                    let components = [placemark.locality, placemark.administrativeArea, placemark.country]
                                        .compactMap { $0 }
                                    locationName = components.joined(separator: ", ")
                                    print("📍 Location name: \(locationName ?? "Unknown")")
                                }
                            }
                        }
                    }
                }
                
                var photo = ImportedPhoto(imageData: data, date: creationDate)
                photo.locationName = locationName
                photo.latitude = latitude
                photo.longitude = longitude
                photos.append(photo)
            }
        }
        
        await MainActor.run {
            importedPhotos = photos.sorted { $0.date > $1.date }
            isProcessing = false
        }
    }
    
    private func saveImportedPhotos() {
        // Check if adding these photos would exceed the free limit
        if let profile = userProfiles.first, !hasPremiumAccess {
            let currentCount = Int(profile.freeMemoryCount)
            let newCount = currentCount + importedPhotos.count
            
            if currentCount >= 10 {
                // Hard limit reached
                showPaywall = true
                return
            } else if newCount > 10 {
                // Would exceed hard limit
                showPaywall = true
                return
            } else if currentCount == 8 || (currentCount < 8 && newCount >= 8) {
                // At or crossing the reminder threshold
                showMemoryReminder = true
                return
            }
        }
        
        performSaveImportedPhotos()
    }
    
    private func performSaveImportedPhotos() {
        Task {
            await performSaveImportedPhotosAsync()
        }
    }
    
    private func performSaveImportedPhotosAsync() async {
        for photo in importedPhotos {
            let memory = CDMemory(context: viewContext)
            memory.id = UUID()
            memory.date = photo.date
            memory.memoryType = MemoryType.quickMoment.rawValue
            memory.privacy = photo.privacy.rawValue
            memory.title = photo.title.isEmpty ? nil : photo.title
            memory.note = photo.note.isEmpty ? nil : photo.note
            // Save photo to disk for fast local access
            if let filename = PhotoStorageManager.shared.savePhoto(photo.imageData) {
                memory.photoFilename = filename
            }
            // Also store in Core Data for CloudKit sync
            memory.photoData = photo.imageData
            memory.createdBy = creatorName
            memory.locationName = photo.locationName
            memory.latitude = photo.latitude ?? 0.0
            memory.longitude = photo.longitude ?? 0.0
            memory.isImported = true
            
            // Set release status based on privacy
            memory.isReleased = (photo.privacy == .shareNow)
            
            if let grandchild = grandchild {
                memory.grandchildren = NSSet(array: [grandchild])
            }
            
            // Increment free memory count if not premium
            if let profile = userProfiles.first, !hasPremiumAccess {
                profile.freeMemoryCount = profile.freeMemoryCount + 1
            }
        }
        
        try? viewContext.save()
        dismiss()
    }
}

struct ImportedPhoto: Identifiable {
    let id = UUID()
    let imageData: Data
    let date: Date
    var title: String = ""
    var note: String = ""
    var privacy: MemoryPrivacy = .vaultOnly
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
}

struct ImportedPhotoCard: View {
    @Binding var photo: ImportedPhoto
    let onRemove: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let uiImage = UIImage(data: photo.imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        Text(photo.date.formatted(date: .abbreviated, time: .shortened))
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    
                    if let location = photo.locationName {
                        HStack {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.accent)
                            Text(location)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            
            // Title field
            TextField("Title (optional)", text: $photo.title)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.headline)
                .padding(12)
                .background(DesignSystem.Colors.backgroundPrimary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            // Note field
            TextField("Add a note (optional)", text: $photo.note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
                .lineLimit(2...4)
                .padding(12)
                .background(DesignSystem.Colors.backgroundPrimary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
            
            // Privacy picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Sharing")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                Picker("Privacy", selection: $photo.privacy) {
                    ForEach(MemoryPrivacy.allCases, id: \.self) { privacy in
                        Text(privacy.rawValue).tag(privacy)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
    }
}

struct FamilyTreeView: View {
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allAncestors())
    private var ancestors: FetchedResults<CDAncestor>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    @State private var selectedGrandchild: CDGrandchild?
    @State private var selectedAncestor: CDAncestor?
    @State private var showingAddAncestor = false
    @State private var selectedPet: CDFamilyPet?
    @State private var showingCopyFamilyTree = false
    
    var activeContributor: CDContributor? {
        contributors.first { $0.id?.uuidString == activeContributorID }
    }
    
    private var grandchildSelectorView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(grandchildren) { child in
                    ProfileFilterButton(
                        title: child.name ?? "Grandchild",
                        isSelected: selectedGrandchild?.id == child.id,
                        photoData: child.photoData
                    ) {
                        selectedGrandchild = child
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(DesignSystem.Colors.backgroundSecondary)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 60))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text("No grandchildren yet")
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundPrimary)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Centered grandchild profile photo
                if let grandchild = selectedGrandchild ?? grandchildren.first, let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
                    VStack(spacing: 8) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())
                        
                        Text("Family Tree")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .background(DesignSystem.Colors.backgroundSecondary)
                }
                
                if grandchildren.count > 1 {
                    grandchildSelectorView
                }
                
                if let grandchild = selectedGrandchild ?? grandchildren.first {
                    FamilyTreeContentView(
                        grandchild: grandchild,
                        ancestors: Array(ancestors),
                        activeContributorColor: Color(hex: activeContributor?.colorHex ?? ContributorRole.grandpa.defaultColor) ?? DesignSystem.Colors.teal,
                        selectedAncestor: $selectedAncestor,
                        showingAddAncestor: $showingAddAncestor,
                        selectedPet: $selectedPet
                    )
                } else {
                    emptyStateView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if grandchildren.count > 1, let currentGrandchild = selectedGrandchild ?? grandchildren.first {
                    let currentAncestors = ancestors.filter { $0.grandchild?.id == currentGrandchild.id }
                    if !currentAncestors.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingCopyFamilyTree = true
                            } label: {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundStyle(DesignSystem.Colors.teal)
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedAncestor) { ancestor in
                AncestorDetailView(ancestor: ancestor)
            }
            .sheet(isPresented: $showingAddAncestor) {
                if let grandchild = selectedGrandchild ?? grandchildren.first {
                    AddAncestorView(grandchild: grandchild)
                }
            }
            .sheet(item: $selectedPet) { pet in
                PetDetailView(pet: pet)
            }
            .sheet(isPresented: $showingCopyFamilyTree) {
                if let sourceGrandchild = selectedGrandchild ?? grandchildren.first {
                    CopyFamilyTreeView(
                        sourceGrandchild: sourceGrandchild,
                        ancestors: Array(ancestors),
                        grandchildren: Array(grandchildren),
                        viewContext: viewContext
                    )
                }
            }
            .onAppear {
                if selectedGrandchild == nil {
                    selectedGrandchild = grandchildren.first
                }
            }
        }
    }
    
    private func generationLabel(for generation: Int) -> String {
        switch generation {
        case 0: return "Parents"
        case 1: return "Grandparents"
        case 2: return "Great-Grandparents"
        case 3: return "Great-Great-Grandparents"
        default: return "Ancestors"
        }
    }
}

struct CopyFamilyTreeView: View {
    let sourceGrandchild: CDGrandchild
    let ancestors: [CDAncestor]
    let grandchildren: [CDGrandchild]
    let viewContext: NSManagedObjectContext
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTargetGrandchildren: Set<UUID> = []
    @State private var showingSuccess = false
    
    private var sourceAncestors: [CDAncestor] {
        ancestors.filter { $0.grandchild?.id == sourceGrandchild.id }
    }
    
    private var availableTargetGrandchildren: [CDGrandchild] {
        grandchildren.filter { $0.id != sourceGrandchild.id }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header explanation
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 50))
                        .foregroundStyle(DesignSystem.Colors.primaryGradient)
                    
                    Text("Copy Family Tree")
                        .font(DesignSystem.Typography.title2)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Text("Copy \(sourceGrandchild.name ?? "this")'s family tree to other blood-related grandchildren")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(DesignSystem.Colors.backgroundSecondary)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // What will be copied
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What will be copied:")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Label("\(sourceAncestors.count) ancestor(s)", systemImage: "person.3.fill")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                
                                let totalPets = sourceAncestors.reduce(0) { $0 + ($1.pets as? Set<CDFamilyPet> ?? []).count }
                                if totalPets > 0 {
                                    Label("\(totalPets) pet(s)", systemImage: "pawprint.fill")
                                        .font(DesignSystem.Typography.body)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                                
                                Label("All photos and stories", systemImage: "photo.fill")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        
                        // Select target grandchildren
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Copy to:")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            if availableTargetGrandchildren.isEmpty {
                                Text("No other grandchildren available")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .italic()
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(availableTargetGrandchildren) { grandchild in
                                        Button {
                                            if let id = grandchild.id {
                                                if selectedTargetGrandchildren.contains(id) {
                                                    selectedTargetGrandchildren.remove(id)
                                                } else {
                                                    selectedTargetGrandchildren.insert(id)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                // Photo
                                                if let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 50, height: 50)
                                                        .clipShape(Circle())
                                                } else {
                                                    Image(systemName: "person.circle.fill")
                                                        .font(.system(size: 50))
                                                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(grandchild.name ?? "Grandchild")
                                                        .font(DesignSystem.Typography.headline)
                                                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                                                    
                                                    Text(grandchild.ageDisplay)
                                                        .font(DesignSystem.Typography.caption)
                                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: selectedTargetGrandchildren.contains(grandchild.id ?? UUID()) ? "checkmark.circle.fill" : "circle")
                                                    .font(.title2)
                                                    .foregroundStyle(selectedTargetGrandchildren.contains(grandchild.id ?? UUID()) ? DesignSystem.Colors.teal : DesignSystem.Colors.textTertiary)
                                            }
                                            .padding()
                                            .background(
                                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                                    .fill(selectedTargetGrandchildren.contains(grandchild.id ?? UUID()) ? DesignSystem.Colors.teal.opacity(0.1) : DesignSystem.Colors.backgroundTertiary)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                                                    .stroke(selectedTargetGrandchildren.contains(grandchild.id ?? UUID()) ? DesignSystem.Colors.teal : Color.clear, lineWidth: 2)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .padding()
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        copyFamilyTree()
                    } label: {
                        Text("Copy Family Tree")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedTargetGrandchildren.isEmpty ? AnyShapeStyle(Color.gray.gradient) : AnyShapeStyle(DesignSystem.Colors.tealGradient), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .disabled(selectedTargetGrandchildren.isEmpty)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding()
                .background(DesignSystem.Colors.backgroundSecondary)
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Family Tree Copied!", isPresented: $showingSuccess) {
            Button("Done") {
                dismiss()
            }
        } message: {
            Text("Successfully copied family tree to \(selectedTargetGrandchildren.count) grandchild(ren)")
        }
    }
    
    private func copyFamilyTree() {
        let targetGrandchildren = grandchildren.filter {
            if let id = $0.id {
                return selectedTargetGrandchildren.contains(id)
            }
            return false
        }
        
        for targetGrandchild in targetGrandchildren {
            // Copy each ancestor
            for sourceAncestor in sourceAncestors {
                // Check if this ancestor already exists for the target grandchild
                let existingAncestor = ancestors.first { ancestor in
                    ancestor.grandchild?.id == targetGrandchild.id &&
                    ancestor.name == sourceAncestor.name &&
                    ancestor.generation == sourceAncestor.generation &&
                    ancestor.lineage == sourceAncestor.lineage
                }
                
                // Only copy if doesn't exist
                if existingAncestor == nil {
                    let newAncestor = CDAncestor(context: viewContext)
                    newAncestor.id = UUID()
                    newAncestor.name = sourceAncestor.name
                    newAncestor.relationship = sourceAncestor.relationship
                    newAncestor.generation = sourceAncestor.generation
                    newAncestor.lineage = sourceAncestor.lineage
                    newAncestor.birthYear = sourceAncestor.birthYear
                    newAncestor.deathYear = sourceAncestor.deathYear
                    newAncestor.photoData = sourceAncestor.photoData
                    newAncestor.story = sourceAncestor.story
                    newAncestor.grandchild = targetGrandchild
                    newAncestor.contributor = sourceAncestor.contributor
                    
                    // Copy photos
                    let sourcePhotos = sourceAncestor.photos as? Set<CDAncestorPhoto> ?? []
                    for sourcePhoto in sourcePhotos {
                        let newPhoto = CDAncestorPhoto(context: viewContext)
                        newPhoto.id = UUID()
                        newPhoto.photoData = sourcePhoto.photoData
                        newPhoto.caption = sourcePhoto.caption
                        newPhoto.year = sourcePhoto.year
                        newPhoto.ancestor = newAncestor
                        newPhoto.contributor = sourcePhoto.contributor
                    }
                    
                    // Copy pets
                    let sourcePets = sourceAncestor.pets as? Set<CDFamilyPet> ?? []
                    for sourcePet in sourcePets {
                        let newPet = CDFamilyPet(context: viewContext)
                        newPet.id = UUID()
                        newPet.name = sourcePet.name
                        newPet.petType = sourcePet.petType
                        newPet.birthYear = sourcePet.birthYear
                        newPet.passedYear = sourcePet.passedYear
                        newPet.story = sourcePet.story
                        newPet.ancestor = newAncestor
                        newPet.contributor = sourcePet.contributor
                        
                        // Copy pet photos
                        let petPhotos = sourcePet.photos as? Set<CDPetPhoto> ?? []
                        for petPhoto in petPhotos {
                            let newPetPhoto = CDPetPhoto(context: viewContext)
                            newPetPhoto.id = UUID()
                            newPetPhoto.photoData = petPhoto.photoData
                            newPetPhoto.caption = petPhoto.caption
                            newPetPhoto.year = petPhoto.year
                            newPetPhoto.pet = newPet
                            newPetPhoto.contributor = petPhoto.contributor
                        }
                    }
                }
            }
        }
        
        try? viewContext.save()
        showingSuccess = true
    }
}

struct FamilyTreeContentView: View {
    let grandchild: CDGrandchild
    let ancestors: [CDAncestor]
    let activeContributorColor: Color
    @Binding var selectedAncestor: CDAncestor?
    @Binding var showingAddAncestor: Bool
    @Binding var selectedPet: CDFamilyPet?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // FIXED HEADER - Grandchild (not zoomable/pannable)
                VStack(spacing: 12) {
                    HStack {
                        Spacer()
                        
                        // Small Add Ancestor button in header
                        Button(action: { showingAddAncestor = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Add Ancestor")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(activeContributorColor.gradient, in: Capsule())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    grandchildView
                    branchingConnector
                }
                .background(DesignSystem.Colors.backgroundPrimary)
                
                // SCROLLABLE/ZOOMABLE TREE CONTENT
                ZStack {
                    DesignSystem.Colors.backgroundPrimary
                    
                    VStack(spacing: 32) {
                        petsSection

                        let grandchildAncestors = ancestors.filter { $0.grandchild?.id == grandchild.id }

                        ForEach(0...3, id: \.self) { generation in
                            generationView(generation: generation, ancestors: grandchildAncestors)
                        }
                    }
                    .padding()
                    .scaleEffect(scale)
                    .offset(offset)
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, 0.5), 3.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffsetX = lastOffset.width + value.translation.width
                            let newOffsetY = lastOffset.height + value.translation.height
                            
                            // Limit horizontal panning
                            let maxOffsetX = geometry.size.width * 0.5
                            let constrainedX = min(max(newOffsetX, -maxOffsetX), maxOffsetX)
                            
                            // Prevent ANY upward panning - content can't cover header
                            // Allow only downward scrolling to see lower generations
                            let constrainedY = max(newOffsetY, 0)  // Can't go negative (upward)
                            
                            offset = CGSize(width: constrainedX, height: constrainedY)
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
        }
    }
    

    
    private var grandchildView: some View {
        VStack(spacing: 8) {
            if let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(activeContributorColor, lineWidth: 3))
            } else {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(activeContributorColor.gradient)
                    .frame(width: 120, height: 120)
            }
            
            Text(grandchild.firstName)
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
    
    private var branchingConnector: some View {
        VStack(spacing: 0) {
            // Vertical line down from grandchild
            Rectangle()
                .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                .frame(width: 2, height: 30)
            
            // Branching Y-shape
            ZStack {
                // Left branch to paternal side
                Rectangle()
                    .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                    .frame(width: 100, height: 2)
                    .offset(x: -50)
                
                // Right branch to maternal side
                Rectangle()
                    .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                    .frame(width: 100, height: 2)
                    .offset(x: 50)
                
                // Center point
                Circle()
                    .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .frame(height: 20)
        }
    }
    
    private var connectorLine: some View {
        Rectangle()
            .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
            .frame(width: 2, height: 30)
    }
    
    private var petsSection: some View {
        Group {
            let petsArray = grandchild.pets as? Set<CDFamilyPet> ?? []
            if !petsArray.isEmpty {
                VStack(spacing: 12) {
                    Text("Family Pets")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    HStack(spacing: 12) {
                        ForEach(Array(petsArray).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }), id: \.id) { pet in
                            FamilyTreePetCard(pet: pet, accentColor: activeContributorColor)
                                .onTapGesture {
                                    selectedPet = pet
                                }
                        }
                    }
                }
            }
        }
    }
    

    
    // Helper to group ancestors into couples and singles
    private func groupIntoCouples(ancestors: [CDAncestor]) -> [(primary: CDAncestor, spouse: CDAncestor?)] {
        var processed = Set<UUID>()
        var couples: [(primary: CDAncestor, spouse: CDAncestor?)] = []

        for ancestor in ancestors {
            guard let ancestorId = ancestor.id, !processed.contains(ancestorId) else { continue }
            processed.insert(ancestorId)

            // Try to find spouse
            if let spouseId = ancestor.spouseId,
               let spouse = ancestors.first(where: { $0.id == spouseId }),
               !processed.contains(spouseId) {
                processed.insert(spouseId)
                couples.append((primary: ancestor, spouse: spouse))
            } else {
                couples.append((primary: ancestor, spouse: nil))
            }
        }

        return couples
    }

    // Helper to render a single ancestor card with pets
    @ViewBuilder
    private func ancestorCardView(ancestor: CDAncestor) -> some View {
        VStack(spacing: 8) {
            FamilyTreePersonCard(
                name: ancestor.name ?? "Unknown",
                subtitle: ancestor.familyRoleEnum?.rawValue ?? ancestor.yearsDisplay,
                photoData: ancestor.primaryPhoto,
                generation: Int(ancestor.generation)
            )
            .onTapGesture {
                selectedAncestor = ancestor
            }

            // Show contributor badge
            if let contributor = ancestor.contributor {
                ContributorBadge(contributor: contributor)
            }
        }
    }

    @ViewBuilder
    private func couplePetsView(primary: CDAncestor, spouse: CDAncestor?) -> some View {
        let primaryPets = Array(primary.pets as? Set<CDFamilyPet> ?? [])
        let spousePets = Array(spouse?.pets as? Set<CDFamilyPet> ?? [])
        let allPets = primaryPets + spousePets
        
        if !allPets.isEmpty {
            VStack(spacing: 6) {
                Text("Family Pets")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                HStack(spacing: 12) {
                    // Primary's pets (left side)
                    ForEach(primaryPets.prefix(3), id: \.id) { pet in
                        petCardWithOwner(pet: pet, ownerName: primary.name ?? "")
                    }
                    
                    // Spouse's pets (right side)
                    if let spouse = spouse {
                        ForEach(spousePets.prefix(3), id: \.id) { pet in
                            petCardWithOwner(pet: pet, ownerName: spouse.name ?? "")
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func petCardWithOwner(pet: CDFamilyPet, ownerName: String) -> some View {
        VStack(spacing: 4) {
            if let photoData = pet.primaryPhoto, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DesignSystem.Colors.teal.opacity(0.5), lineWidth: 2))
            } else {
                Image(systemName: pet.petTypeEnum?.icon ?? "pawprint.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(DesignSystem.Colors.teal.opacity(0.7))
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(DesignSystem.Colors.backgroundTertiary))
            }
            
            Text(pet.name ?? "")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
            
            Text(ownerName)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 60)
        .onTapGesture {
            selectedPet = pet
        }
    }
    
    @ViewBuilder
    private func generationView(generation: Int, ancestors: [CDAncestor]) -> some View {
        let generationAncestors = ancestors
            .filter { $0.generation == Int32(generation) }

        if !generationAncestors.isEmpty {
            VStack(spacing: 16) {
                Text(generationLabel(for: generation))
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                // Split by lineage - paternal on left, maternal on right
                let paternalAncestors = generationAncestors.filter { $0.lineageEnum == .paternal }
                let maternalAncestors = generationAncestors.filter { $0.lineageEnum == .maternal }
                
                HStack(alignment: .top, spacing: 60) {
                    // PATERNAL SIDE (LEFT)
                    if !paternalAncestors.isEmpty {
                        VStack(spacing: 12) {
                            Text("Paternal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.accent.opacity(0.7))
                            
                            VStack(spacing: 20) {
                                ForEach(groupIntoCouples(ancestors: paternalAncestors), id: \.primary.id) { couple in
                                    familyGroupView(primary: couple.primary, spouse: couple.spouse)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // CENTER DIVIDER
                    if !paternalAncestors.isEmpty && !maternalAncestors.isEmpty {
                        Rectangle()
                            .fill(DesignSystem.Colors.textTertiary.opacity(0.2))
                            .frame(width: 1)
                    }
                    
                    // MATERNAL SIDE (RIGHT)
                    if !maternalAncestors.isEmpty {
                        VStack(spacing: 12) {
                            Text("Maternal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.accent.opacity(0.7))
                            
                            VStack(spacing: 20) {
                                ForEach(groupIntoCouples(ancestors: maternalAncestors), id: \.primary.id) { couple in
                                    familyGroupView(primary: couple.primary, spouse: couple.spouse)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if generation < 3 {
                connectorLine
            }
        }
    }
    
    @ViewBuilder
    private func familyGroupView(primary: CDAncestor, spouse: CDAncestor?) -> some View {
        VStack(spacing: 12) {
            // Couple or single person display
            if let spouse = spouse {
                // Married couple
                HStack(alignment: .top, spacing: 4) {
                    ancestorCardView(ancestor: primary)
                    
                    // Marriage connector line with heart
                    Rectangle()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 30, height: 3)
                        .overlay(
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                        )
                        .padding(.top, 55) // Align with center of person circle
                    
                    ancestorCardView(ancestor: spouse)
                }
            } else {
                // Single person
                ancestorCardView(ancestor: primary)
            }
            
            // Show pets for this couple/person
            couplePetsView(primary: primary, spouse: spouse)
        }
    }
    
    private func generationLabel(for generation: Int) -> String {
        switch generation {
        case 0: return "Parents"
        case 1: return "Grandparents"
        case 2: return "Great-Grandparents"
        case 3: return "Great-Great-Grandparents"
        default: return "Ancestors"
        }
    }
}

struct FamilyTreePersonCard: View {
    let name: String
    let subtitle: String
    let photoData: Data?
    let generation: Int
    var isGrandchild: Bool = false
    var accentColor: Color = DesignSystem.Colors.teal
    
    var body: some View {
        VStack(spacing: 8) {
            if let photoData = photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(accentColor, lineWidth: 3))
            } else {
                Image(systemName: isGrandchild ? "heart.circle.fill" : "person.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(isGrandchild ? AnyShapeStyle(accentColor.gradient) : AnyShapeStyle(DesignSystem.Colors.textTertiary))
                    .frame(width: 110, height: 110)
            }
            
            Text(name)
                .font(DesignSystem.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .frame(maxWidth: 120)
    }
}

struct FamilyTreePetCard: View {
    let pet: CDFamilyPet
    var accentColor: Color = DesignSystem.Colors.teal
    
    var body: some View {
        VStack(spacing: 8) {
            if let photoData = pet.primaryPhoto, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md).stroke(accentColor.opacity(0.3), lineWidth: 3))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .fill(DesignSystem.Colors.backgroundTertiary)
                        .frame(width: 140, height: 140)
                    Image(systemName: pet.petTypeEnum?.icon ?? "pawprint.circle.fill")
                        .font(.system(size: 65))
                        .foregroundStyle(accentColor)
                }
            }
            
            VStack(spacing: 2) {
                Text(pet.name ?? "Pet")
                    .font(DesignSystem.Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                if let petType = pet.petTypeEnum {
                    Text(petType.rawValue)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                if !pet.yearsDisplay.isEmpty {
                    Text(pet.yearsDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }
        }
        .frame(width: 160)
        .padding(.vertical, 8)
    }
}

struct AncestorDetailView: View {
    let ancestor: CDAncestor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedPhotoData: Data?
    @State private var showingAddPhoto = false
    @State private var showingAddPet = false
    @State private var selectedPet: CDFamilyPet?
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    
    // Edit state variables
    @State private var editName = ""
    @State private var editRelationship = ""
    @State private var editGeneration = 1
    @State private var editLineage: AncestorLineage = .maternal
    @State private var editBirthYear = ""
    @State private var editDeathYear = ""
    @State private var editStory = ""
    
    var allPhotos: [Data] {
        var photos: [Data] = []
        if let photoData = ancestor.photoData {
            photos.append(photoData)
        }
        let photosArray = ancestor.photos as? Set<CDAncestorPhoto> ?? []
        let additionalPhotos = photosArray.compactMap { $0.photoData }
        photos.append(contentsOf: additionalPhotos)
        return photos
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Photo Gallery
                    if !allPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Photos")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Spacer()
                                Button(action: { showingAddPhoto = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(DesignSystem.Colors.teal)
                                }
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(allPhotos.indices, id: \.self) { index in
                                        if let uiImage = UIImage(data: allPhotos[index]) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 150, height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                                .onTapGesture {
                                                    selectedPhotoData = allPhotos[index]
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Button(action: { showingAddPhoto = true }) {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                Text("Add Photos")
                                    .font(DesignSystem.Typography.subheadline)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        }
                    }
                    
                    // Basic Info
                    if isEditing {
                        VStack(spacing: 16) {
                            TextField("Name", text: $editName)
                                .font(DesignSystem.Typography.title3)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Relationship (e.g., Great-grandmother)", text: $editRelationship)
                                .textFieldStyle(.roundedBorder)
                            
                            VStack(spacing: 12) {
                                Picker("Generation", selection: $editGeneration) {
                                    Text("Grandparent").tag(1)
                                    Text("Great-Grandparent").tag(2)
                                    Text("Great-Great-Grandparent").tag(3)
                                }
                                .pickerStyle(.segmented)
                                
                                Picker("Side of Family", selection: $editLineage) {
                                    ForEach(AncestorLineage.allCases, id: \.self) { lineage in
                                        Text(lineage.rawValue).tag(lineage)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Birth Year")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    TextField("Year", text: $editBirthYear)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Death Year")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    TextField("Year", text: $editDeathYear)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    } else {
                        VStack(spacing: 8) {
                            Text(ancestor.name ?? "Unknown")
                                .font(DesignSystem.Typography.title1)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text(ancestor.relationship ?? "Ancestor")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.teal)
                            
                            if !ancestor.yearsDisplay.isEmpty {
                                Text(ancestor.yearsDisplay)
                                    .font(DesignSystem.Typography.subheadline)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                    
                    // Pets Section - Moved up to be more prominent
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Their Pets")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text("Pets that belonged to \(ancestor.name ?? "them")")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            Button(action: { showingAddPet = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Pet")
                                        .font(DesignSystem.Typography.caption)
                                }
                                .foregroundStyle(DesignSystem.Colors.teal)
                            }
                        }
                        
                        let petsArray = ancestor.pets as? Set<CDFamilyPet> ?? []
                        if !petsArray.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(petsArray).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }), id: \.id) { pet in
                                        FamilyTreePetCard(pet: pet)
                                            .onTapGesture {
                                                selectedPet = pet
                                            }
                                    }
                                }
                            }
                        } else {
                            Button(action: { showingAddPet = true }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "pawprint.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    Text("Add their dog, cat, or other beloved pet")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                            }
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    
                    // Story - Moved below pets
                    if isEditing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Their Story")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            TextField("Write about this ancestor...", text: $editStory, axis: .vertical)
                                .lineLimit(5...15)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    } else if let story = ancestor.story, !story.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Their Story")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text(story)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                }
                .padding()
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle(isEditing ? "Edit Ancestor" : "Ancestor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                            loadEditValues()
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                        }
                    } else {
                        Menu {
                            Button(action: {
                                loadEditValues()
                                isEditing = true
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: {
                                showingDeleteConfirmation = true
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .alert("Delete Ancestor?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    viewContext.delete(ancestor)
                    try? viewContext.save()
                    dismiss()
                }
            } message: {
                Text("This ancestor and all their photos will be permanently deleted. This cannot be undone.")
            }
            .fullScreenCover(item: Binding(
                get: { selectedPhotoData.map { PhotoWrapper(data: $0) } },
                set: { selectedPhotoData = $0?.data }
            )) { wrapper in
                if let uiImage = UIImage(data: wrapper.data) {
                    FullScreenPhotoView(image: uiImage)
                }
            }
            .sheet(isPresented: $showingAddPhoto) {
                AddAncestorPhotoView(ancestor: ancestor)
            }
            .sheet(isPresented: $showingAddPet) {
                AddPetView(ancestor: ancestor)
            }
            .sheet(item: $selectedPet) { pet in
                PetDetailView(pet: pet)
            }
        }
    }
    
    private func loadEditValues() {
        editName = ancestor.name ?? ""
        editRelationship = ancestor.relationship ?? ""
        editGeneration = Int(ancestor.generation)
        editLineage = ancestor.lineageEnum ?? .maternal
        editBirthYear = ancestor.birthYear > 0 ? String(ancestor.birthYear) : ""
        editDeathYear = ancestor.deathYear > 0 ? String(ancestor.deathYear) : ""
        editStory = ancestor.story ?? ""
    }
    
    private func saveChanges() {
        ancestor.name = editName.isEmpty ? nil : editName
        ancestor.relationship = editRelationship.isEmpty ? nil : editRelationship
        ancestor.generation = Int32(editGeneration)
        ancestor.lineage = editLineage.rawValue
        ancestor.birthYear = Int32(Int(editBirthYear) ?? 0)
        ancestor.deathYear = Int32(Int(editDeathYear) ?? 0)
        ancestor.story = editStory.isEmpty ? nil : editStory
        
        try? viewContext.save()
        isEditing = false
    }
}

struct PhotoWrapper: Identifiable {
    let id = UUID()
    let data: Data
}

struct FullScreenPhotoView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1 {
                                withAnimation {
                                    scale = 1
                                    lastScale = 1
                                }
                            } else if scale > 4 {
                                withAnimation {
                                    scale = 4
                                    lastScale = 4
                                }
                            }
                        }
                )
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}

struct AddAncestorView: View {
    let grandchild: CDGrandchild
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    
    @State private var name = ""
    @State private var relationship = ""
    @State private var generation = 0
    @State private var lineage: AncestorLineage = .maternal
    @State private var birthYear = ""
    @State private var deathYear = ""
    @State private var story = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var selectedContributor: CDContributor?
    
    // New fields for extended family
    @State private var gender: Gender = .male
    @State private var familyRole: FamilyRole = .grandpa
    @State private var selectedSpouse: CDAncestor?
    @State private var selectedSibling: CDAncestor?
    @FetchRequest(fetchRequest: FetchRequestBuilders.allAncestors())
    private var allAncestors: FetchedResults<CDAncestor>
    
    private var activeContributor: CDContributor? {
        contributors.first { $0.id?.uuidString == activeContributorID }
    }
    
    private var sameGenerationAncestors: [CDAncestor] {
        allAncestors.filter { ancestor in
            ancestor.generation == Int32(generation) &&
            ancestor.lineageEnum == lineage &&
            ancestor.grandchild?.id == grandchild.id
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ContributorPicker(selectedContributor: $selectedContributor)
                }
                
                Section("Basic Information") {
                    TextField("Name", text: $name)
                    
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Text(gender.rawValue).tag(gender)
                        }
                    }
                    
                    Picker("Family Role", selection: $familyRole) {
                        ForEach(FamilyRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    
                    Picker("Generation", selection: $generation) {
                        Text("Parent").tag(0)
                        Text("Grandparent").tag(1)
                        Text("Great-Grandparent").tag(2)
                        Text("Great-Great-Grandparent").tag(3)
                    }
                }
                
                Section {
                    Picker("Side of Family", selection: $lineage) {
                        ForEach(AncestorLineage.allCases, id: \.self) { lineage in
                            Text(lineage.rawValue).tag(lineage)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Family Side")
                } footer: {
                    Text("Paternal = Father's side, Maternal = Mother's side. This determines which side of the family tree this ancestor appears on.")
                        .font(.caption)
                }
                
                Section("Dates") {
                    TextField("Birth Year (optional)", text: $birthYear)
                        .keyboardType(.numberPad)
                    TextField("Death Year (optional)", text: $deathYear)
                        .keyboardType(.numberPad)
                }
                
                Section("Relationships") {
                    Picker("Link as Spouse", selection: $selectedSpouse) {
                        Text("None").tag(nil as CDAncestor?)
                        ForEach(sameGenerationAncestors, id: \.id) { ancestor in
                            Text(ancestor.name ?? "Unknown").tag(ancestor as CDAncestor?)
                        }
                    }
                    
                    Picker("Link as Sibling", selection: $selectedSibling) {
                        Text("None").tag(nil as CDAncestor?)
                        ForEach(sameGenerationAncestors, id: \.id) { ancestor in
                            Text(ancestor.name ?? "Unknown").tag(ancestor as CDAncestor?)
                        }
                    }
                }
                
                Section("Photo") {
                    if let photoData = photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    }
                    
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                }
                
                Section("Story") {
                    TextField("Write about this ancestor...", text: $story, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .navigationTitle("Add Ancestor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addAncestor()
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
            .task {
                // Auto-select the active contributor if none is selected
                if selectedContributor == nil {
                    selectedContributor = activeContributor
                }
            }
        }
    }
    
    private func addAncestor() {
        let ancestor = CDAncestor(context: viewContext)
        ancestor.id = UUID()
        ancestor.name = name
        ancestor.relationship = relationship
        ancestor.generation = Int32(generation)
        ancestor.lineage = lineage.rawValue
        ancestor.birthYear = Int32(Int(birthYear) ?? 0)
        ancestor.deathYear = Int32(Int(deathYear) ?? 0)
        ancestor.photoData = photoData
        ancestor.story = story.isEmpty ? nil : story
        
        // Set new fields
        ancestor.gender = gender.rawValue
        ancestor.familyRole = familyRole.rawValue
        
        // Link as spouse
        if let spouse = selectedSpouse {
            ancestor.spouseId = spouse.id
            spouse.spouseId = ancestor.id  // Bidirectional link
        }
        
        // Link as sibling (use sibling's group or create new one)
        if let sibling = selectedSibling {
            if let groupId = sibling.siblingGroupId {
                ancestor.siblingGroupId = groupId
            } else {
                let newGroupId = UUID()
                ancestor.siblingGroupId = newGroupId
                sibling.siblingGroupId = newGroupId
            }
        }
        
        ancestor.grandchild = grandchild
        ancestor.contributor = selectedContributor
        
        try? viewContext.save()
        dismiss()
    }
}

struct AddPetView: View {
    var grandchild: CDGrandchild?
    var ancestor: CDAncestor?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    
    @State private var name = ""
    @State private var petType: PetType = .dog
    @State private var birthYear = ""
    @State private var passedYear = ""
    @State private var story = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var selectedContributor: CDContributor?
    
    private var activeContributor: CDContributor? {
        contributors.first { $0.id?.uuidString == activeContributorID }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ContributorPicker(selectedContributor: $selectedContributor)
                }
                
                Section("Basic Information") {
                    TextField("Pet's Name", text: $name)
                    
                    Picker("Type", selection: $petType) {
                        ForEach(PetType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                            }.tag(type)
                        }
                    }
                }
                
                Section("Years") {
                    TextField("Birth Year (optional)", text: $birthYear)
                        .keyboardType(.numberPad)
                    TextField("Passed Year (optional)", text: $passedYear)
                        .keyboardType(.numberPad)
                }
                
                Section("Photo") {
                    if let photoData = photoData, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                    }
                    
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                }
                
                Section("Story") {
                    TextField("Share memories of this pet...", text: $story, axis: .vertical)
                        .lineLimit(5...10)
                }
            }
            .navigationTitle("Add Family Pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addPet()
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
            .task {
                // Auto-select the active contributor if none is selected
                if selectedContributor == nil {
                    selectedContributor = activeContributor
                }
            }
        }
    }
    
    private func addPet() {
        let pet = CDFamilyPet(context: viewContext)
        pet.id = UUID()
        pet.name = name
        pet.petType = petType.rawValue
        pet.birthYear = Int32(Int(birthYear) ?? 0)
        pet.passedYear = Int32(Int(passedYear) ?? 0)
        pet.story = story.isEmpty ? nil : story
        
        // Create photo if provided
        if let photoData = photoData {
            let petPhoto = CDPetPhoto(context: viewContext)
            petPhoto.id = UUID()
            petPhoto.photoData = photoData
            petPhoto.pet = pet
        }
        
        // Link to grandchild or ancestor
        if let grandchild = grandchild {
            pet.grandchild = grandchild
        } else if let ancestor = ancestor {
            pet.ancestor = ancestor
        }
        
        pet.contributor = selectedContributor
        
        try? viewContext.save()
        dismiss()
    }
}

struct AddAncestorPhotoView: View {
    let ancestor: CDAncestor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoDataList: [Data] = []
    @State private var caption = ""
    @State private var year = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                        Label("Choose Photos (up to 10)", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    if !photoDataList.isEmpty {
                        Text("\(photoDataList.count) photo(s) selected")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photoDataList.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: photoDataList[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section("Optional Details") {
                    TextField("Caption (optional)", text: $caption, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Year (optional)", text: $year)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Add Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addPhotos()
                    }
                    .disabled(photoDataList.isEmpty)
                }
            }
            .onChange(of: selectedPhotos) { _, newItems in
                Task {
                    photoDataList = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            photoDataList.append(data)
                        }
                    }
                }
            }
        }
    }
    
    private func addPhotos() {
        for photoData in photoDataList {
            let photo = CDAncestorPhoto(context: viewContext)
            photo.id = UUID()
            photo.photoData = photoData
            photo.caption = caption.isEmpty ? nil : caption
            if let yearInt = Int(year) {
                photo.year = Int32(yearInt)
            }
            photo.ancestor = ancestor
        }
        try? viewContext.save()
        dismiss()
    }
}

struct PetDetailView: View {
    let pet: CDFamilyPet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedPhotoData: Data?
    @State private var showingAddPhoto = false
    
    var yearsDisplay: String {
        if pet.birthYear > 0, pet.passedYear > 0 {
            return "\(pet.birthYear) - \(pet.passedYear)"
        } else if pet.birthYear > 0 {
            return "Born \(pet.birthYear)"
        } else if pet.passedYear > 0 {
            return "Passed \(pet.passedYear)"
        }
        return ""
    }
    
    var allPhotos: [Data] {
        let photosArray = pet.photos as? Set<CDPetPhoto> ?? []
        return photosArray.compactMap { $0.photoData }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Photo Gallery
                    if !allPhotos.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Photos")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Spacer()
                                Button(action: { showingAddPhoto = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(DesignSystem.Colors.teal)
                                }
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(allPhotos.indices, id: \.self) { index in
                                        if let uiImage = UIImage(data: allPhotos[index]) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 150, height: 150)
                                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md))
                                                .onTapGesture {
                                                    selectedPhotoData = allPhotos[index]
                                                }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Button(action: { showingAddPhoto = true }) {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                Text("Add Photos")
                                    .font(DesignSystem.Typography.subheadline)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                        }
                    }
                    
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: (pet.petType.flatMap { PetType(rawValue: $0) }?.icon) ?? "pawprint.circle.fill")
                                .font(.title2)
                                .foregroundStyle(DesignSystem.Colors.teal)
                            Text(pet.petType ?? "Pet")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Spacer()
                        }
                        
                        if !yearsDisplay.isEmpty {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                Text(yearsDisplay)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Spacer()
                            }
                        }
                        
                        if let story = pet.story, !story.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Story")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                Text(story)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                }
                .padding()
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle(pet.name ?? "Pet")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: Binding(
                get: { selectedPhotoData.map { PhotoWrapper(data: $0) } },
                set: { selectedPhotoData = $0?.data }
            )) { wrapper in
                if let uiImage = UIImage(data: wrapper.data) {
                    FullScreenPhotoView(image: uiImage)
                }
            }
            .sheet(isPresented: $showingAddPhoto) {
                AddPetPhotoView(pet: pet)
            }
        }
    }
}

struct AddPetPhotoView: View {
    let pet: CDFamilyPet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoDataList: [Data] = []
    @State private var caption = ""
    @State private var year = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                        Label("Choose Photos (up to 10)", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    if !photoDataList.isEmpty {
                        Text("\(photoDataList.count) photo(s) selected")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(photoDataList.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: photoDataList[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm))
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section("Optional Details") {
                    TextField("Caption (optional)", text: $caption, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Year (optional)", text: $year)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Add Pet Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        addPhotos()
                    }
                    .disabled(photoDataList.isEmpty)
                }
            }
            .onChange(of: selectedPhotos) { _, newItems in
                Task {
                    photoDataList = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            photoDataList.append(data)
                        }
                    }
                }
            }
        }
    }
    
    private func addPhotos() {
        for photoData in photoDataList {
            let photo = CDPetPhoto(context: viewContext)
            photo.id = UUID()
            photo.photoData = photoData
            photo.caption = caption.isEmpty ? nil : caption
            if let yearInt = Int(year) {
                photo.year = Int32(yearInt)
            }
            photo.pet = pet
        }
        try? viewContext.save()
        dismiss()
    }
}

// MARK: - Onboarding Feature Page

struct OnboardingFeaturePage: View {
    let icon: String
    let gradient: LinearGradient
    let title: String
    let description: String
    let features: [String]
    @Binding var currentPage: Int
    let pageNumber: Int
    let nextPage: Int
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                
                ZStack {
                    Circle()
                        .fill(gradient)
                        .frame(width: 84, height: 84)
                    Image(systemName: icon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(DesignSystem.Typography.title2)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Text(description)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .font(.body)
                            Text(feature)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                    }
                }
                .padding(20)
                .background(DesignSystem.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
                
                HStack(spacing: 10) {
                    ForEach(1...4, id: \.self) { page in
                        Circle()
                            .fill(page == pageNumber ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 8)
                
                Button { withAnimation { currentPage = nextPage } } label: {
                    Text("Continue").primaryButton()
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }
}

// MARK: - Contributor Components

struct ContributorBadge: View {
    let contributor: CDContributor?
    
    var body: some View {
        if let contributor = contributor {
            Text("Added by \(contributor.displayName)")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Color(hex: contributor.colorHex ?? ContributorRole.grandpa.defaultColor),
                    in: Capsule()
                )
        }
    }
}

struct ContributorPicker: View {
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @Binding var selectedContributor: CDContributor?
    
    var body: some View {
        if !contributors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Who's adding this?")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                HStack(spacing: 12) {
                    ForEach(contributors) { contributor in
                        let isSelected = selectedContributor?.id == contributor.id
                        let contributorColor = Color(hex: contributor.colorHex ?? "14B8A6")
                        
                        Button(action: {
                            selectedContributor = contributor
                        }) {
                            HStack(spacing: 8) {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                }
                                Text(contributor.displayName)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? .white : contributorColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                isSelected ? contributorColor : contributorColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(contributorColor, lineWidth: isSelected ? 2.5 : 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Active Contributor Switcher

struct ActiveContributorSwitcher: View {
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @AppStorage("activeContributorID") private var activeContributorID: String = ""
    
    var activeContributor: CDContributor? {
        contributors.first { $0.id?.uuidString == activeContributorID }
    }
    
    var body: some View {
        if contributors.count >= 2 {
            HStack(spacing: 12) {
                ForEach(contributors) { contributor in
                    Button(action: {
                        activeContributorID = contributor.id?.uuidString ?? ""
                    }) {
                        Text(contributor.displayName)
                            .font(DesignSystem.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(activeContributor?.id == contributor.id ? .white : DesignSystem.Colors.textSecondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .frame(minWidth: 120)
                        .background(
                            activeContributor?.id == contributor.id ?
                                Color(hex: contributor.colorHex ?? "14B8A6") :
                                DesignSystem.Colors.backgroundSecondary,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, 4)
        }
    }
}

// MARK: - Setup Step View

struct SetupStepView: View {
    let icon: String
    var iconColor: Color?
    var iconGradient: LinearGradient?
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let gradient = iconGradient {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(gradient)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(iconColor ?? DesignSystem.Colors.primary)
                }
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text(description)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CircularProfilePhoto: View {
    let photoData: Data?
    let size: CGFloat
    let fallbackIcon: String
    let fallbackColor: Color
    
    var body: some View {
        ZStack {
            if let photoData = photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: fallbackIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(fallbackColor.gradient)
                    .padding(8)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
    }
}

struct PhotoCropperView: View {
    let image: UIImage
    let onSave: (Data) -> Void
    let onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let cropSize: CGFloat = 300
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text("Position & Scale Photo")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 60)
                
                Text("Drag to reposition, pinch to zoom")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                
                Spacer()
                
                // Circular crop preview
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 300, height: 300)
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 300, height: 300)
                        .scaleEffect(scale)
                        .offset(offset)
                        .clipShape(Circle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, min(lastScale * value, 4.0))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                }
                
                Spacer()
                
                // Scale slider
                VStack(spacing: 8) {
                    Text("Zoom: \(Int(scale * 100))%")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    Slider(value: $scale, in: 1...4) { editing in
                        if !editing {
                            lastScale = scale
                        }
                    }
                    .tint(.white)
                    .padding(.horizontal, 40)
                }
                
                // Action buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                    
                    Button("Save") {
                        print("🖼️ Attempting to crop image with scale: \(scale), offset: \(offset)")
                        if let croppedData = cropImage() {

                            onSave(croppedData)
                        } else {

                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignSystem.Colors.primaryGradient, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func cropImage() -> Data? {
        let outputSize: CGFloat = 400
        
        // Calculate the visible portion of the image based on scale and offset
        let imageSize = image.size
        
        // Calculate the crop rect in image coordinates
        let minDimension = min(imageSize.width, imageSize.height)
        let cropRectSize = minDimension / scale
        
        // Convert offset from view coordinates to image coordinates
        let imageScale = minDimension / cropSize
        let offsetX = -offset.width * imageScale / scale
        let offsetY = -offset.height * imageScale / scale
        
        // Calculate crop rectangle centered on the image with offset
        let cropRect = CGRect(
            x: (imageSize.width - cropRectSize) / 2 + offsetX,
            y: (imageSize.height - cropRectSize) / 2 + offsetY,
            width: cropRectSize,
            height: cropRectSize
        )
        
        print("🎨 Cropping - Image size: \(imageSize), Scale: \(scale), Offset: \(offset)")
        print("📐 Crop rect: \(cropRect)")
        
        // Crop the image using CGImage
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {

            return nil
        }
        
        // Create UIImage from cropped CGImage
        let croppedUIImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        
        // Resize to output size and make circular
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize), format: format)
        
        let finalImage = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: outputSize, height: outputSize)
            
            // Create circular clipping path
            UIBezierPath(ovalIn: rect).addClip()
            
            // Draw the cropped image scaled to fit
            croppedUIImage.draw(in: rect)
        }
        

        return finalImage.jpegData(compressionQuality: 0.92)
    }
}

// MARK: - Co-Grandparent Share View

struct CoGrandparentShareView: View {
    let shareURL: URL
    let shareCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var showCopied = false
    
    private var familyCode: String {
        return shareCode
    }
    
    private var shareMessage: String {
        """
        Join our Grandparents Gift family vault!
        
        1. Download "Grandparents Gift" from the App Store
        2. Tap "Join Family Vault" in Settings
        3. Enter this family code: \(familyCode)
        
        We can both add memories for our grandchildren!
        """
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(DesignSystem.Colors.primaryGradient)
                        
                        Text("Invite Co-Grandparent")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Text("Share this code with another grandparent. They can install the app on their own device with their own Apple ID and enter this code to join your family vault.")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // Family Code Display
                    VStack(spacing: 16) {
                        Text("Family Code")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Text(familyCode)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .tracking(1)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        
                        Text("The other grandparent can enter this code in Settings → Join Family Vault")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        // Copy Button
                        Button {
                            UIPasteboard.general.string = familyCode
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showCopied = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: showCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                Text(showCopied ? "Copied Code!" : "Copy Code")
                            }
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(showCopied ? Color.green : DesignSystem.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                    
                    Divider()
                        .padding(.horizontal)
                    
                    // Share via System Sheet
                    ShareLink(item: shareMessage) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share via Messages, Email, etc.")
                        }
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instructions")
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            InstructionRow(number: "1", text: "Send this link to the other grandparent")
                            InstructionRow(number: "2", text: "They install Grandparents Gift on their device")
                            InstructionRow(number: "3", text: "They tap the link to join your family vault")
                            InstructionRow(number: "4", text: "Both can contribute with your own Apple IDs")
                        }
                    }
                    .padding()
                    .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Invite Co-Grandparent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(DesignSystem.Colors.accent)
                .clipShape(Circle())
            
            Text(text)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }
}

// MARK: - Custom Share Sheet

struct CustomShareSheet: View {
    let shareURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var showCopied = false
    
    private var shareMessage: String {
        guard let url = shareURL?.absoluteString else {
            return "Join our family vault in Grandparent Memories!"
        }
        return """
        Join our Grandparent Memories family vault!
        
        1. Download "Grandparent Memories" from the App Store
        2. Tap "Joining my partner" when setting up
        3. Paste this link when prompted:
        
        \(url)
        
        We can both add memories for our grandchildren!
        """
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)
                    
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(DesignSystem.Colors.primaryGradient)
                    
                    VStack(spacing: 16) {
                        Text("Share with Your Partner")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Text("Send this link to your partner via Messages, Email, or any app. They can copy and paste it when setting up the app.")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    if let url = shareURL {
                        VStack(spacing: 16) {
                            Text("Share Link")
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                            
                            Text(url.absoluteString)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(DesignSystem.Colors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                                .lineLimit(3)
                                .minimumScaleFactor(0.8)
                            
                            Button {
                                UIPasteboard.general.string = url.absoluteString
                                showCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCopied = false
                                }
                            } label: {
                                HStack {
                                    Image(systemName: showCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                    Text(showCopied ? "Copied!" : "Copy Link")
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(showCopied ? Color.green : DesignSystem.Colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        }
                        
                        Divider()
                            .padding(.horizontal)
                        
                        ShareLink(item: shareMessage) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share via Messages, Email, etc.")
                            }
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Invite Co-Grandparent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Profile Photo Editor View

struct ProfilePhotoEditorView: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                
                // Image with zoom and pan
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1.0), 5.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(DesignSystem.Colors.accent, lineWidth: 3)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 40)
                }
                .frame(height: UIScreen.main.bounds.width - 80)
                
                Spacer()
                
                // Instructions
                VStack(spacing: 8) {
                    Text("Pinch to zoom, drag to position")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    // Reset button
                    Button {
                        withAnimation {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    } label: {
                        Text("Reset")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundStyle(DesignSystem.Colors.accent)
                    }
                    .padding(.bottom, 20)
                }
                
                Spacer()
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Edit Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let croppedImage = cropImageToCircle()
                        onSave(croppedImage)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func cropImageToCircle() -> UIImage {
        let size = min(image.size.width, image.size.height) * scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
            
            // Create circular clipping path
            UIBezierPath(ovalIn: rect).addClip()
            
            // Calculate the drawing rect with scale and offset
            let scaledWidth = image.size.width * scale
            let scaledHeight = image.size.height * scale
            let x = (200 - scaledWidth) / 2 + (offset.width * scale)
            let y = (200 - scaledHeight) / 2 + (offset.height * scale)
            
            let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
            image.draw(in: drawRect)
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy video to app's documents directory for permanent storage
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "\(UUID().uuidString).mov"
            let destinationURL = documentsPath.appendingPathComponent(fileName)
            
            do {
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                // Copy the video file to permanent location
                try FileManager.default.copyItem(at: received.file, to: destinationURL)
                
                return Self(url: destinationURL)
            } catch {

                // Fall back to temporary file (will be deleted by system eventually)
                return Self(url: received.file)
            }
        }
    }
}

// MARK: - Co-Grandparent Share Options View

struct CoGrandparentShareOptionsView: View {
    @Binding var showSystemShare: Bool
    let onSystemShare: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isPreparingShare = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(DesignSystem.Colors.teal.gradient)
                    
                    Text("Invite Co-Grandparent")
                        .font(.title2.bold())
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    VStack(spacing: 8) {
                        Text("Share your family vault with your partner so you can both add memories together")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("You'll both keep your own Apple IDs and have full access")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 40)
                
                VStack(spacing: 16) {
                    // System Share (Recommended)
                    Button {
                        isPreparingShare = true
                        onSystemShare()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "message.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                                .background(DesignSystem.Colors.teal.gradient, in: Circle())
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Share via Messages")
                                        .font(DesignSystem.Typography.headline)
                                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    
                                    Text("Recommended")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(DesignSystem.Colors.accent.gradient, in: Capsule())
                                }
                                
                                Text("Send an iCloud link via Messages, Mail, or AirDrop")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding()
                        .background(DesignSystem.Colors.backgroundSecondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Share Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isPreparingShare)
                }
            }
            .overlay {
                if isPreparingShare {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            VStack(spacing: 8) {
                                Text("Preparing share link...")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                
                                Text("Hang tight - this can take up to a couple of minutes")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .padding(40)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }
    }
}

#Preview {
    // Create in-memory Core Data stack for preview
    let container = NSPersistentContainer(name: "GrandparentMemories")
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [description]
    
    container.loadPersistentStores { _, error in
        if let error = error {
            fatalError("Failed to load preview store: \(error)")
        }
    }
    
    return ContentView()
        .environment(\.managedObjectContext, container.viewContext)
}
