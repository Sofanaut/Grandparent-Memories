//
//  GrandchildGiftView.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-08.
//

import SwiftUI
import CoreData
import AVKit
import AVFoundation

struct GrandchildGiftView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var memories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
    private var grandchildren: FetchedResults<CDGrandchild>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allUserProfiles())
    private var contributors: FetchedResults<CDUserProfile>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributorRecords: FetchedResults<CDContributor>
    @StateObject private var sharingManager = CloudKitSharingManager.shared
    
    @State private var currentGift: CDMemory?
    @State private var showArchive = false
    @State private var showFullScreenVideo = false
    @State private var fullScreenVideoURL: URL?
    @State private var fullScreenPhoto: PhotoDataWrapper?
    @State private var audioPhotoFullScreenPayload: AudioPhotoFullScreenPayload?
    @State private var dragOffset: CGFloat = 0
    @State private var showReactionPicker = false
    @State private var audioRecorder = AudioRecorder()
    @State private var audioPhotoIndex = 0
    @State private var audioPhotoTask: Task<Void, Never>?
    @State private var audioPhotoError: String?
    @AppStorage("isGrandchildMode") private var isGrandchildMode = false
    @AppStorage("selectedGrandchildID") private var selectedGrandchildID: String = ""

    
    // Get the current grandchild based on persisted selection
    private var currentGrandchild: CDGrandchild? {
        print("👶 Getting current grandchild...")
        print("   - selectedGrandchildID: \(selectedGrandchildID)")
        print("   - Total grandchildren: \(grandchildren.count)")
        for (index, child) in grandchildren.enumerated() {
            print("   - [\(index)] \(child.firstName) (ID: \(child.id?.uuidString ?? "none"))")
        }
        
        // Try to find the selected grandchild by ID
        if !selectedGrandchildID.isEmpty,
           let selected = grandchildren.first(where: { $0.id?.uuidString == selectedGrandchildID }) {
            print("✅ Found selected grandchild: \(selected.firstName)")
            return selected
        }
        
        // Fall back to first grandchild and persist the selection
        if let first = grandchildren.first {
            print("⚠️ No selection found, defaulting to first: \(first.firstName)")
            selectedGrandchildID = first.id?.uuidString ?? ""
            return first
        }
        
        print("❌ No grandchildren found")
        return nil
    }
    
    // Get the welcome video for the current grandchild if it hasn't been watched yet
    private var welcomeVideo: CDMemory? {
        guard let currentGrandchild = currentGrandchild else { return nil }
        
        // Filter memories based on user role (grandparent sees all, grandchild sees only released)
        let visibleMemories = sharingManager.filterMemories(Array(memories), for: currentGrandchild)
        
        let welcomeVideos = visibleMemories.filter { $0.isWelcomeVideo }
        print("🎬 Total welcome videos visible to user: \(welcomeVideos.count)")
        for video in welcomeVideos {
            print("   - ID: \(video.id?.uuidString ?? "none")")
            let grandchildrenSet = video.grandchildren as? Set<CDGrandchild> ?? []
            print("     Grandchildren: \(grandchildrenSet.map { $0.firstName }.joined(separator: ", "))")
            print("     Watched: \(video.wasWatched)")
        }
        
        let result = visibleMemories.first { memory in
            let grandchildrenSet = memory.grandchildren as? Set<CDGrandchild> ?? []
            return memory.isWelcomeVideo &&
            !memory.wasWatched &&
            grandchildrenSet.contains(where: { $0.id == currentGrandchild.id })
        }
        
        if result != nil {
            print("✅ Found unwatched welcome video for \(currentGrandchild.firstName)")
        } else {
            print("❌ No unwatched welcome video found for \(currentGrandchild.firstName)")
        }
        
        return result
    }
    
    // Get the next unreleased gift ready to show
    private var nextGift: CDMemory? {
        guard let currentGrandchild = currentGrandchild else { return nil }
        let _ = Date()  // Current date for potential future use
        
        // Filter memories based on user role (grandparent sees all, grandchild sees only released)
        let visibleMemories = sharingManager.filterMemories(Array(memories), for: currentGrandchild)
        
        // Filter memories that:
        // 1. Are for this specific grandchild
        // 2. Are released (either by date or no schedule)
        // 3. Haven't been watched yet
        // 4. Aren't the welcome video (that's shown separately)
        let availableGifts = visibleMemories.filter { memory in
            // Must be shared with this grandchild
            let grandchildrenSet = memory.grandchildren as? Set<CDGrandchild> ?? []
            let isForThisGrandchild = grandchildrenSet.contains(where: { $0.id == currentGrandchild.id })
            guard isForThisGrandchild else { return false }
            
            let isScheduled = memory.releaseDate != nil || memory.releaseAge > 0
            let isReleased = memory.isReleased
            let notWatched = !memory.wasWatched
            let notWelcome = !memory.isWelcomeVideo
            
            // If no schedule, it's available immediately
            if !isScheduled {
                return notWatched && notWelcome
            }
            
            // If scheduled, check if released
            return isReleased && notWatched && notWelcome
        }
        
        // Return the oldest gift first
        return availableGifts.sorted(by: { ($0.date ?? Date()) < ($1.date ?? Date()) }).first
    }
    
    // Count of watched gifts (for archive badge) - only for this grandchild
    private var watchedCount: Int {
        guard let currentGrandchild = currentGrandchild else { return 0 }
        return memories.filter { memory in
            let isWatched = memory.wasWatched
            let grandchildrenSet = memory.grandchildren as? Set<CDGrandchild> ?? []
            let isForThisGrandchild = grandchildrenSet.contains(where: { $0.id == currentGrandchild.id })
            return isWatched && isForThisGrandchild
        }.count
    }

    
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    DesignSystem.Colors.backgroundPrimary,
                    DesignSystem.Colors.backgroundPrimary.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header with archive button and exit
                    HStack {
                        // Exit grandchild mode button (for testing)
                        Button {
                            isGrandchildMode = false
                            Task {
                                await CloudKitSharingManager.shared.detectUserRole()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .font(.caption)
                                Text("Exit")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.8))
                            .clipShape(Capsule())
                        }
                        .padding()
                        
                        Spacer()

                        Button {
                            showArchive = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.title3)
                                Text("Memories")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if watchedCount > 0 {
                                    Text("\(watchedCount)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(DesignSystem.Colors.accent)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.8))
                            .clipShape(Capsule())
                        }
                        .padding()
                    }
                    
                    // Grandchild selector (tap to switch - for development/testing)
                    if let child = currentGrandchild, grandchildren.count > 1 {
                        HStack {
                            Spacer()
                            Menu {
                                ForEach(grandchildren) { grandchild in
                                    Button {
                                        selectedGrandchildID = grandchild.id?.uuidString ?? ""
                                        print("🔄 Switched to grandchild: \(grandchild.firstName)")
                                        print("   - New ID stored: \(selectedGrandchildID)")
                                    } label: {
                                        HStack {
                                            Text(grandchild.firstName)
                                            if grandchild.id?.uuidString == selectedGrandchildID {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.body)
                                    Text("\(child.firstName)'s Memories")
                                        .font(.headline)
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.caption)
                                }
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(DesignSystem.Colors.backgroundSecondary.opacity(0.9))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                    
                    Spacer()
                        .frame(height: 40)
                    
                    // Main gift display area
                    // Show welcome video first if unwatched, otherwise show next gift
                    if let welcomeGift = welcomeVideo {
                        welcomeVideoView(gift: welcomeGift)
                            .offset(y: dragOffset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Only allow downward drag
                                        if value.translation.height > 0 {
                                            dragOffset = value.translation.height
                                        }
                                    }
                                    .onEnded { value in
                                        if value.translation.height > 150 {
                                            // Mark as watched and archive
                                            markGiftAsWatched(welcomeGift)
                                            withAnimation(.spring()) {
                                                dragOffset = 1000  // Large enough offset to move off screen
                                            }
                                            // Reset after animation
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                dragOffset = 0
                                            }
                                        } else {
                                            // Snap back
                                            withAnimation(.spring()) {
                                                dragOffset = 0
                                            }
                                        }
                                    }
                            )
                    } else if let gift = nextGift {
                        giftPlayerView(gift: gift)
                            .offset(y: dragOffset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Only allow downward drag
                                        if value.translation.height > 0 {
                                            dragOffset = value.translation.height
                                        }
                                    }
                                    .onEnded { value in
                                        if value.translation.height > 150 {
                                            // Mark as watched and archive
                                            markGiftAsWatched(gift)
                                            withAnimation(.spring()) {
                                                dragOffset = 1000  // Large enough offset to move off screen
                                            }
                                            // Reset after animation
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                dragOffset = 0
                                            }
                                        } else {
                                            // Snap back
                                            withAnimation(.spring()) {
                                                dragOffset = 0
                                            }
                                        }
                                    }
                            )
                    } else {
                        emptyStateView
                    }
                    
                    Spacer()
                        .frame(height: 40)
                }
                .frame(maxHeight: .infinity)
            }
            .refreshable {
                await refreshMemories()
            }
        }
        .sheet(isPresented: $showArchive) {
            if let grandchild = currentGrandchild {
                GrandchildArchiveView(grandchild: grandchild)
            }
        }

            .fullScreenCover(isPresented: $showFullScreenVideo) {
                if let videoURL = fullScreenVideoURL {
                    FullScreenVideoPlayer(videoURL: videoURL, isPresented: $showFullScreenVideo)
                }
            }
            .fullScreenCover(item: $audioPhotoFullScreenPayload) { payload in
                FullScreenAudioPhotoPlayer(
                    images: payload.images,
                    audioData: payload.audioData,
                    isPresented: Binding(
                        get: { audioPhotoFullScreenPayload != nil },
                        set: { if !$0 { audioPhotoFullScreenPayload = nil } }
                    )
                )
            }
            .fullScreenCover(item: $fullScreenPhoto) { wrapper in
                FullScreenPhotoDataViewer(data: wrapper.data) {
                    fullScreenPhoto = nil
                }
            }
        .onAppear {
            print("🎁 GrandchildGiftView appeared")
            print("   - Current selectedGrandchildID: \(selectedGrandchildID)")
            if let current = currentGrandchild {
                print("   - Showing view for: \(current.firstName)")
            }
            
            checkForNewReleases()
            NotificationManager.shared.clearBadge()
            
            Task {
                await NotificationManager.shared.checkAuthorizationStatus()
                if !NotificationManager.shared.isAuthorized {
                    await NotificationManager.shared.requestAuthorization()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            // CloudKit synced new data - refresh the view
            viewContext.refreshAllObjects()
        }
    }
    
    // MARK: - Gift Player View
    
    @ViewBuilder
    private func giftPlayerView(gift: CDMemory) -> some View {
        VStack(spacing: 24) {
            // Gift card
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                VStack(spacing: 16) {
                    // Content preview
                    if gift.memoryType == MemoryType.videoMessage.rawValue {
                        // Video content
                        if let videoData = gift.videoData,
                           let cachedURL = VideoCache.shared.url(for: videoData) {
                            VideoPlayerView(url: cachedURL)
                                .frame(height: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .onTapGesture {
                                    fullScreenVideoURL = cachedURL
                                    showFullScreenVideo = true
                                }
                        } else if let videoPath = gift.videoURL {
                            // Legacy: video stored as file path
                            let videoURL = URL(fileURLWithPath: videoPath)
                            VideoPlayerView(url: videoURL)
                                .frame(height: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .onTapGesture {
                                    fullScreenVideoURL = videoURL
                                    showFullScreenVideo = true
                                }
                        } else {
                            // Fallback if no video data
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 60))
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                Text("Video not available")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            .frame(height: 400)
                        }
                    } else if gift.memoryType == MemoryType.voiceMemory.rawValue, let audioData = gift.audioData {
                        VStack(spacing: 24) {
                            // Animated waveform icon
                            Image(systemName: audioRecorder.isPlaying ? "waveform" : "waveform.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(
                                    (gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent
                                )
                                .symbolEffect(.pulse, isActive: audioRecorder.isPlaying)
                            
                            if let title = gift.title, !title.isEmpty {
                                Text(title)
                                    .font(DesignSystem.Typography.title2)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Voice Message")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                            }
                            
                            // Duration display
                            if audioRecorder.isPlaying || audioRecorder.audioData != nil {
                                Text(audioRecorder.formattedDuration)
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .monospacedDigit()
                            }
                            
                            // Play/Stop button
                            Button {
                                if audioRecorder.isPlaying {
                                    audioRecorder.stopPlaying()
                                } else {
                                    audioRecorder.playAudio(from: audioData)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: audioRecorder.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 44))
                                    Text(audioRecorder.isPlaying ? "Stop" : "Play")
                                        .font(DesignSystem.Typography.headline)
                                }
                                .foregroundStyle(
                                    (gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(height: 400)
                    } else if gift.memoryType == MemoryType.audioPhoto.rawValue, let audioData = gift.audioData {
                        let images = gift.audioPhotoImages
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Button {
                                    guard !audioData.isEmpty else {
                                        audioPhotoError = "Audio is still syncing. Please try again in a minute."
                                        return
                                    }
                                    audioRecorder.stopPlaying()
                                    stopAudioPhotoSlideshow()
                                    audioPhotoFullScreenPayload = AudioPhotoFullScreenPayload(images: images, audioData: audioData)
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(DesignSystem.Colors.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Audio Photo Story")
                                        .font(DesignSystem.Typography.subheadline)
                                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    Text("Tap to play")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "waveform")
                                    .font(.title3)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .symbolEffect(.variableColor, isActive: false)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.backgroundTertiary, in: RoundedRectangle(cornerRadius: 14))
                            
                            if !images.isEmpty {
                                ZStack {
                                    if let uiImage = UIImage(data: images[audioPhotoIndex]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 340)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            .id(audioPhotoIndex)
                                            .transition(.opacity)
                                            .onTapGesture {
                                                guard !audioData.isEmpty else {
                                                    audioPhotoError = "Audio is still syncing. Please try again in a minute."
                                                    return
                                                }
                                                audioRecorder.stopPlaying()
                                                stopAudioPhotoSlideshow()
                                                audioPhotoFullScreenPayload = AudioPhotoFullScreenPayload(images: images, audioData: audioData)
                                            }
                                    }
                                }
                                .frame(height: 360)
                                .clipped()
                                .animation(.easeInOut(duration: 0.9), value: audioPhotoIndex)
                                
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
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 44))
                                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    Text("Photos not available")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                }
                                .frame(height: 320)
                            }
                        }
                        .frame(height: 520)
                        .onAppear {
                            audioPhotoIndex = 0
                            stopAudioPhotoSlideshow()
                        }
                        .onDisappear {
                            stopAudioPhotoSlideshow()
                        }
                        .onChange(of: audioRecorder.isPlaying) { _, isPlaying in
                            if isPlaying {
                                startAudioPhotoSlideshow(imageCount: images.count, duration: audioDuration(for: audioData))
                            } else {
                                stopAudioPhotoSlideshow()
                            }
                        }
                    } else if let photoData = gift.displayPhotoData {
                        CachedAsyncImage(data: photoData)
                            .scaledToFit()
                            .frame(height: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture {
                                fullScreenPhoto = PhotoDataWrapper(data: photoData)
                            }
                    } else if let note = gift.note, !note.isEmpty {
                        ScrollView {
                            Text(note)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                                .padding()
                        }
                        .frame(height: 400)
                    }
                    
                    // Creator info with color coding (pill)
                    HStack {
                        if let contributor = gift.contributor {
                            Text("From \(contributor.displayName)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(contributorColor(for: contributor), in: Capsule())
                        } else if let createdBy = gift.createdBy {
                            Text("From \(createdBy)")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(contributorColorForCreatedBy(createdBy), in: Capsule())
                        }
                        
                        Spacer()
                        
                        if let date = gift.date {
                            Text(date, style: .date)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            
            // Swipe down hint
            VStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.5))
                
                Text("Swipe down when finished")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Welcome Video View
    
    @ViewBuilder
    private func welcomeVideoView(gift: CDMemory) -> some View {
        VStack(spacing: 24) {
            // Special welcome card
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                    .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                
                VStack(spacing: 20) {
                    // Welcome header
                    VStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(DesignSystem.Colors.accent)
                        
                        Text("Welcome!")
                            .font(DesignSystem.Typography.largeTitle)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        if let createdBy = gift.createdBy {
                            Text("\(createdBy) has a special message for you")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(contributorColorForCreatedBy(createdBy))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Video player
                    if let videoData = gift.videoData,
                       let cachedURL = VideoCache.shared.url(for: videoData) {
                        VideoPlayerView(url: cachedURL)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture {
                                fullScreenVideoURL = cachedURL
                                showFullScreenVideo = true
                            }
                    } else if let videoPath = gift.videoURL {
                        let videoURL = URL(fileURLWithPath: videoPath)
                        VideoPlayerView(url: videoURL)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture {
                                fullScreenVideoURL = videoURL
                                showFullScreenVideo = true
                            }
                    }
                    
                    // Welcome message
                    Text("This is your special Grandparents Gift vault - a treasure chest of memories made just for you! ✨")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
                .padding()
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            
            // Continue button
            Button {
                markGiftAsWatched(gift)
            } label: {
                HStack {
                    Text("Continue to Memories")
                    Image(systemName: "arrow.right")
                }
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(DesignSystem.Colors.primaryGradient)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg))
            }
            .padding(.horizontal, 40)
            
            // Swipe down hint
            VStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.5))
                
                Text("or swipe down")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: hasReceivedMemories ? "sparkles" : "gift.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(DesignSystem.Colors.accent)
            }
            
            VStack(spacing: 16) {
                Text(hasReceivedMemories ? "What Will Your Grandparents Share Next?" : "Connect to Your Grandparents")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                if hasReceivedMemories {
                    VStack(spacing: 12) {
                        Text("You're all caught up!")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        Text("Check back soon for new memories from your grandparents. In the meantime, tap the sparkles button at the top to revisit your treasured moments.")
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                } else {
                    Text("Ask your grandparents to send you a share link via Messages. Tap the link to connect and start receiving their special memories.")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
        .padding(.horizontal, 40)
    }
    
    private var hasReceivedMemories: Bool {
        // Check if the grandchild has any watched memories
        guard let grandchild = currentGrandchild else { return false }
        return memories.contains { memory in
            memory.wasWatched && (memory.grandchildren as? Set<CDGrandchild>)?.contains(where: { $0.id == grandchild.id }) == true
        }
    }
    
    // MARK: - Helper Functions
    
    private func markGiftAsWatched(_ gift: CDMemory) {
        gift.wasWatched = true
        gift.watchedDate = Date()
        
        // Update grandchild's last viewed date
        if let grandchild = currentGrandchild {
            grandchild.lastViewedDate = Date()
        }
        
        try? viewContext.save()
    }
    
    // Helper to get contributor color
    private func contributorColor(for contributor: CDContributor) -> Color {
        if let colorHex = contributor.colorHex {
            return Color(hex: colorHex)
        }
        // Fallback to role-based color
        if let roleString = contributor.role,
           let role = ContributorRole(rawValue: roleString) {
            switch role {
            case .grandpa:
                return DesignSystem.Colors.teal
            case .grandma:
                return DesignSystem.Colors.pink
            }
        }
        return DesignSystem.Colors.accent
    }

    private func contributorColorForCreatedBy(_ createdBy: String) -> Color {
        let trimmed = createdBy.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if let match = contributorRecords.first(where: { ($0.displayName).lowercased() == lowercased }) {
            return contributorColor(for: match)
        }

        if lowercased.contains("grandpa") || lowercased.contains("grandad") || lowercased.contains("granddad") {
            return DesignSystem.Colors.teal
        }
        if lowercased.contains("grandma") || lowercased.contains("grannie") || lowercased.contains("gran") || lowercased.contains("nana") {
            return DesignSystem.Colors.pink
        }

        return DesignSystem.Colors.accent
    }
    
    private func checkForNewReleases() {
        let now = Date()
        
        // Check all scheduled memories to see if they should be released
        for memory in memories {
            // Skip if already released or watched
            if memory.isReleased || memory.wasWatched {
                continue
            }
            
            // Check release date
            if let releaseDate = memory.releaseDate, releaseDate <= now {
                memory.isReleased = true
            }
            
            // Check release age
            if memory.releaseAge > 0,
               let grandchild = currentGrandchild,
               let birthDate = grandchild.birthDate {
                let calendar = Calendar.current
                let ageComponents = calendar.dateComponents([.year], from: birthDate, to: now)
                if let currentAge = ageComponents.year, currentAge >= memory.releaseAge {
                    memory.isReleased = true
                }
            }
        }
        
        try? viewContext.save()
    }
    
    private func refreshMemories() async {
        // Refresh all objects in the context to pull latest from CloudKit
        viewContext.refreshAllObjects()
        
        // Give CloudKit a moment to sync
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Check for any newly released memories
        checkForNewReleases()
    }
}

// MARK: - Memories View

struct GrandchildArchiveView: View {
    let grandchild: CDGrandchild
    
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
    private var memories: FetchedResults<CDMemory>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributorRecords: FetchedResults<CDContributor>
    @State private var selectedMemory: CDMemory?
    @State private var searchText = ""
    @State private var selectedMemoryType: MemoryType?
    @State private var selectedCreator: String?
    @State private var sortOrder: SortOrder = .newestFirst
    @State private var showFilters = false
    
    enum SortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case creator = "By Creator"
    }
    
    private var availableCreators: [String] {
        let creators = memories
            .compactMap { $0.createdBy }
            .reduce(into: Set<String>()) { $0.insert($1) }
        return Array(creators).sorted()
    }
    
    private var watchedGifts: [CDMemory] {
        // Filter memories based on user role (grandparent sees all, grandchild sees only released)
        let visibleMemories = CloudKitSharingManager.shared.filterMemories(Array(memories), for: grandchild)
        
        // Filter to only memories for this grandchild that have been watched
        let watched = visibleMemories.filter { memory in
            let isWatched = memory.wasWatched
            let grandchildrenSet = memory.grandchildren as? Set<CDGrandchild> ?? []
            let isForThisGrandchild = grandchildrenSet.contains(where: { $0.id == grandchild.id })
            return isWatched && isForThisGrandchild
        }
        
        // Apply memory type filter first (fastest)
        var filtered = watched
        if let selectedType = selectedMemoryType {
            filtered = filtered.filter { $0.memoryType == selectedType.rawValue }
        }
        
        // Apply creator filter
        if let creator = selectedCreator {
            filtered = filtered.filter { $0.createdBy == creator }
        }
        
        // Apply search filter last (most expensive)
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            filtered = filtered.filter { memory in
                // Search in title
                if let title = memory.title?.lowercased(), title.contains(lowercasedSearch) {
                    return true
                }
                // Search in creator name
                if let creator = memory.createdBy?.lowercased(), creator.contains(lowercasedSearch) {
                    return true
                }
                // Search in note
                if let note = memory.note?.lowercased(), note.contains(lowercasedSearch) {
                    return true
                }
                // Search in memory type
                if let type = memory.memoryType?.lowercased(), type.contains(lowercasedSearch) {
                    return true
                }
                return false
            }
        }
        
        // Apply sorting
        switch sortOrder {
        case .newestFirst:
            return filtered.sorted { ($0.watchedDate ?? Date.distantPast) > ($1.watchedDate ?? Date.distantPast) }
        case .oldestFirst:
            return filtered.sorted { ($0.watchedDate ?? Date.distantPast) < ($1.watchedDate ?? Date.distantPast) }
        case .creator:
            return filtered.sorted { ($0.createdBy ?? "") < ($1.createdBy ?? "") }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search and filter controls
                    searchAndFilterView
                    
                    if watchedGifts.isEmpty {
                        emptyMemoriesView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                ForEach(watchedGifts, id: \.id) { gift in
                                    memoryCard(gift: gift)
                                        .onTapGesture {
                                            selectedMemory = gift
                                        }
                                        .id(gift.id)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
        }
        .sheet(item: $selectedMemory) { memory in
            GrandchildMemoryDetailView(memory: memory)
        }
        .sheet(isPresented: $showFilters) {
            filterSheet
        }
    }
    
    // MARK: - Search and Filter Views
    
    private var searchAndFilterView: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                
                TextField("Search memories...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
            }
            .padding(12)
            .background(DesignSystem.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Active filters and controls
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Filter button
                    Button {
                        showFilters = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                            Text("Filters")
                            
                            // Badge showing active filter count
                            let activeFilterCount = (selectedMemoryType != nil ? 1 : 0) + (selectedCreator != nil ? 1 : 0)
                            if activeFilterCount > 0 {
                                Text("\(activeFilterCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignSystem.Colors.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(Circle())
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(Capsule())
                    }
                    
                    // Sort order picker
                    Menu {
                        Picker("Sort By", selection: $sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOrder.rawValue)
                        }
                        .font(.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.backgroundSecondary)
                        .clipShape(Capsule())
                    }
                    
                    // Active filter chips
                    if let memoryType = selectedMemoryType {
                        filterChip(title: memoryType.rawValue, color: memoryType.accentColor) {
                            selectedMemoryType = nil
                        }
                    }
                    
                    if let creator = selectedCreator {
                        filterChip(title: creator, color: DesignSystem.Colors.accent) {
                            selectedCreator = nil
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }
    
    private func filterChip(title: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color)
        .clipShape(Capsule())
    }
    
    private var filterSheet: some View {
        NavigationStack {
            List {
                // Memory Type Section
                Section {
                    Button {
                        selectedMemoryType = nil
                    } label: {
                        HStack {
                            Text("All Types")
                            Spacer()
                            if selectedMemoryType == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DesignSystem.Colors.accent)
                            }
                        }
                    }
                    
                    ForEach(MemoryType.allCases, id: \.self) { type in
                        Button {
                            selectedMemoryType = type
                        } label: {
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundStyle(type.accentColor)
                                Text(type.rawValue)
                                Spacer()
                                if selectedMemoryType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DesignSystem.Colors.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Memory Type")
                }
                
                // Creator Section
                Section {
                    Button {
                        selectedCreator = nil
                    } label: {
                        HStack {
                            Text("All Creators")
                            Spacer()
                            if selectedCreator == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DesignSystem.Colors.accent)
                            }
                        }
                    }
                    
                    ForEach(availableCreators, id: \.self) { creator in
                        Button {
                            selectedCreator = creator
                        } label: {
                            HStack {
                                Text(creator)
                                Spacer()
                                if selectedCreator == creator {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DesignSystem.Colors.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Creator")
                }
            }
            .navigationTitle("Filter Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        selectedMemoryType = nil
                        selectedCreator = nil
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showFilters = false
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
        }
    }
    
    private var emptyMemoriesView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(DesignSystem.Colors.accent)
            
            Text(searchText.isEmpty && selectedMemoryType == nil && selectedCreator == nil ? "No Memories Yet" : "No Results")
                .font(DesignSystem.Typography.title2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            Text(searchText.isEmpty && selectedMemoryType == nil && selectedCreator == nil ? "Open your gifts to start building\nyour collection of memories" : "Try adjusting your search or filters")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    @ViewBuilder
    // Helper to get contributor color
    private func contributorColor(for contributor: CDContributor) -> Color {
        if let colorHex = contributor.colorHex {
            return Color(hex: colorHex)
        }
        // Fallback to role-based color
        if let roleString = contributor.role,
           let role = ContributorRole(rawValue: roleString) {
            switch role {
            case .grandpa:
                return DesignSystem.Colors.teal
            case .grandma:
                return DesignSystem.Colors.pink
            }
        }
        return DesignSystem.Colors.accent
    }

    private func contributorColorForCreatedBy(_ createdBy: String) -> Color {
        let trimmed = createdBy.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if let match = contributorRecords.first(where: { ($0.displayName).lowercased() == lowercased }) {
            return contributorColor(for: match)
        }

        if lowercased.contains("grandpa") || lowercased.contains("grandad") || lowercased.contains("granddad") {
            return DesignSystem.Colors.teal
        }
        if lowercased.contains("grandma") || lowercased.contains("grannie") || lowercased.contains("gran") || lowercased.contains("nana") {
            return DesignSystem.Colors.pink
        }

        return DesignSystem.Colors.accent
    }
    
    private func memoryCard(gift: CDMemory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with overlay - enforced square aspect ratio
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.backgroundSecondary)
                
                // Border
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        (gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent,
                        lineWidth: 3
                    )
                
                // Show thumbnail (video thumbnail, photo, or beautiful gradient for other types)
                if let photoData = gift.displayPhotoData {
                    // Photo - show actual image (cached)
                    ZStack(alignment: .topTrailing) {
                        CachedAsyncImage(data: photoData)
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        if gift.memoryType == MemoryType.audioPhoto.rawValue {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.5), in: Circle())
                                .padding(8)
                        }
                    }
                } else if gift.memoryType == MemoryType.videoMessage.rawValue {
                    // Video: show thumbnail with play overlay
                    if let thumbnailData = gift.videoThumbnailData {
                        ZStack {
                            CachedAsyncImage(data: thumbnailData)
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                            // Play overlay
                            Circle()
                                .fill(.black.opacity(0.5))
                                .frame(width: 50, height: 50)
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    } else {
                        // Video without thumbnail - beautiful gradient
                        ZStack {
                            LinearGradient(
                                colors: [
                                    (gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent,
                                    ((gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent).opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            
                            VStack(spacing: 12) {
                                Image(systemName: (gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.icon) ?? "play.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.white)
                                
                                Circle()
                                    .fill(.black.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.title3)
                                            .foregroundStyle(.white)
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    // All other types - beautiful gradient with icon
                    ZStack {
                        LinearGradient(
                            colors: [
                                (gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent,
                                ((gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent).opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        Image(systemName: (gift.memoryType.flatMap { MemoryType(rawValue: $0) }?.icon) ?? "doc.text.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                // Type badge - only show on photos/videos with actual content
                // Don't show on gradient cards as they're already color-coded
                if let memoryTypeString = gift.memoryType,
                   let memoryType = MemoryType(rawValue: memoryTypeString),
                   (gift.displayPhotoData != nil || (gift.memoryType == MemoryType.videoMessage.rawValue && gift.videoThumbnailData != nil)) {
                    HStack(spacing: 4) {
                        Image(systemName: memoryType.icon)
                            .font(.caption2)
                        Text(memoryType.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(memoryType.accentColor)
                    .clipShape(Capsule())
                    .padding(8)
                }
                }
                .frame(width: geometry.size.width, height: geometry.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            .aspectRatio(1, contentMode: .fit)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Show custom title if available, otherwise show memory type
                if let title = gift.title, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)
                } else {
                    Text(gift.memoryType ?? "Memory")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                }
                
                // Metadata row - date and location
                HStack(spacing: 4) {
                    if let date = gift.date {
                        Text(date, style: .date)
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    
                    if let location = gift.locationName, !location.isEmpty {
                        if gift.date != nil {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        Text(location)
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                // Creator name with color coding (pill)
                if let contributor = gift.contributor {
                    Text("From \(contributor.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(contributorColor(for: contributor), in: Capsule())
                } else if let createdBy = gift.createdBy {
                    Text("From \(createdBy)")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(contributorColorForCreatedBy(createdBy), in: Capsule())
                }
            }
        }
    }
}

struct AudioPhotoFullScreenPayload: Identifiable {
    let id = UUID()
    let images: [Data]
    let audioData: Data
}

struct FullScreenAudioPhotoPlayer: View {
    let images: [Data]
    let audioData: Data
    @Binding var isPresented: Bool
    
    @State private var index = 0
    @State private var audioRecorder = AudioRecorder()
    @State private var slideshowTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 12) {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button {
                            if audioRecorder.isPlaying {
                                audioRecorder.stopPlaying()
                                stopSlideshow()
                            } else {
                                audioRecorder.playAudio(from: audioData)
                                startSlideshow(imageCount: images.count, duration: audioDuration(for: audioData))
                            }
                        } label: {
                            Image(systemName: audioRecorder.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white)
                        }
                        
                        Image(systemName: "waveform")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                            .symbolEffect(.variableColor, isActive: audioRecorder.isPlaying)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                ZStack {
                    if !images.isEmpty, let uiImage = UIImage(data: images[index]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .id(index)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.9), value: index)
                
                Text("\(index + 1) of \(max(images.count, 1))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            index = 0
            audioRecorder.playAudio(from: audioData)
            startSlideshow(imageCount: images.count, duration: audioDuration(for: audioData))
        }
        .onDisappear {
            audioRecorder.stopPlaying()
            stopSlideshow()
        }
        .onChange(of: audioRecorder.isPlaying) { _, isPlaying in
            if !isPlaying {
                stopSlideshow()
            }
        }
    }
    
    private func startSlideshow(imageCount: Int, duration: TimeInterval) {
        stopSlideshow()
        guard imageCount > 1 else { return }
        let safeDuration = max(duration, 1.0)
        let secondsPerImage = max(3.0, safeDuration / Double(imageCount))
        
        slideshowTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(secondsPerImage))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.9)) {
                    index = (index + 1) % imageCount
                }
            }
        }
    }
    
    private func stopSlideshow() {
        slideshowTask?.cancel()
        slideshowTask = nil
    }
    
    private func audioDuration(for data: Data) -> TimeInterval {
        if let player = try? AVAudioPlayer(data: data) {
            return player.duration
        }
        return audioRecorder.recordingDuration
    }
}

// MARK: - Grandchild Memory Detail View

struct GrandchildMemoryDetailView: View {
    let memory: CDMemory
    @Environment(\.dismiss) private var dismiss
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var audioRecorder = AudioRecorder()
    @State private var audioPhotoIndex = 0
    @State private var audioPhotoTask: Task<Void, Never>?
    @State private var audioPhotoError: String?
    @State private var showFullScreenVideo = false
    @State private var fullScreenVideoURL: URL?
    @State private var fullScreenPhoto: PhotoDataWrapper?
    @State private var audioPhotoFullScreenPayload: AudioPhotoFullScreenPayload?
    
    var body: some View {
        NavigationStack {
            ZStack {
                DesignSystem.Colors.backgroundPrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Title section (if custom title exists)
                        if let title = memory.title, !title.isEmpty {
                            VStack(spacing: 8) {
                                Text(title)
                                    .font(DesignSystem.Typography.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .multilineTextAlignment(.center)
                                
                                // Show memory type as subtitle
                                if let memoryTypeString = memory.memoryType,
                                   let memoryType = MemoryType(rawValue: memoryTypeString) {
                                    HStack(spacing: 6) {
                                        Image(systemName: memoryType.icon)
                                            .font(.caption)
                                        Text(memoryType.rawValue)
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(memoryType.accentColor)
                                }
                            }
                            .padding(.top, 8)
                        }
                        
                        // Main content
                        contentView
                        
                        // Metadata
                        metadataView
                        
                        // Note if exists
                        if let note = memory.note, !note.isEmpty {
                            noteView(note: note)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(memory.title ?? memory.memoryType ?? "Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .font(.title3)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showFullScreenVideo) {
            if let videoURL = fullScreenVideoURL {
                FullScreenVideoPlayer(videoURL: videoURL, isPresented: $showFullScreenVideo)
            }
        }
        .fullScreenCover(item: $fullScreenPhoto) { wrapper in
            FullScreenPhotoDataViewer(data: wrapper.data) {
                fullScreenPhoto = nil
            }
        }
        .fullScreenCover(item: $audioPhotoFullScreenPayload) { payload in
            FullScreenAudioPhotoPlayer(
                images: payload.images,
                audioData: payload.audioData,
                isPresented: Binding(
                    get: { audioPhotoFullScreenPayload != nil },
                    set: { if !$0 { audioPhotoFullScreenPayload = nil } }
                )
            )
        }
        .alert("Audio not ready", isPresented: Binding(
            get: { audioPhotoError != nil },
            set: { if !$0 { audioPhotoError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(audioPhotoError ?? "")
        }
        .onChange(of: audioPhotoFullScreenPayload != nil) { _, isPresented in
            if isPresented {
                audioRecorder.stopPlaying()
                stopAudioPhotoSlideshow()
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(DesignSystem.Colors.backgroundSecondary)
            
            if memory.memoryType == MemoryType.videoMessage.rawValue {
                // Video content (cached)
                if let videoData = memory.videoData,
                   let cachedURL = VideoCache.shared.url(for: videoData) {
                    VideoPlayerView(url: cachedURL)
                        .frame(height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture {
                            fullScreenVideoURL = cachedURL
                            showFullScreenVideo = true
                        }
                } else if let videoPath = memory.videoURL {
                    let videoURL = URL(fileURLWithPath: videoPath)
                    VideoPlayerView(url: videoURL)
                        .frame(height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture {
                            fullScreenVideoURL = videoURL
                            showFullScreenVideo = true
                        }
                }
            } else if memory.memoryType == MemoryType.voiceMemory.rawValue, let audioData = memory.audioData {
                // Voice memory with playback
                VStack(spacing: 24) {
                    // Animated waveform icon
                    Image(systemName: audioRecorder.isPlaying ? "waveform" : "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            (memory.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent
                        )
                        .symbolEffect(.pulse, isActive: audioRecorder.isPlaying)
                    
                    if let title = memory.title, !title.isEmpty {
                        Text(title)
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Voice Memory")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    
                    // Duration display
                    if audioRecorder.isPlaying || audioRecorder.audioData != nil {
                        Text(audioRecorder.formattedDuration)
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .monospacedDigit()
                    }
                    
                    // Play/Stop button
                    Button {
                        if audioRecorder.isPlaying {
                            audioRecorder.stopPlaying()
                        } else {
                            audioRecorder.playAudio(from: audioData)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: audioRecorder.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                            Text(audioRecorder.isPlaying ? "Stop" : "Play")
                                .font(DesignSystem.Typography.headline)
                        }
                        .foregroundStyle(
                            (memory.memoryType.flatMap { MemoryType(rawValue: $0) }?.accentColor) ?? DesignSystem.Colors.accent
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 400)
                .frame(maxWidth: .infinity)
            } else if memory.memoryType == MemoryType.audioPhoto.rawValue, let audioData = memory.audioData {
                let images = memory.audioPhotoImages
                VStack(spacing: 16) {
                    if !images.isEmpty {
                        ZStack {
                            if let uiImage = UIImage(data: images[audioPhotoIndex]) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 320)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .id(audioPhotoIndex)
                                    .transition(.opacity)
                                    .onTapGesture {
                                        guard !audioData.isEmpty else {
                                            audioPhotoError = "Audio is still syncing. Please try again in a minute."
                                            return
                                        }
                                        audioRecorder.stopPlaying()
                                        stopAudioPhotoSlideshow()
                                        audioPhotoFullScreenPayload = AudioPhotoFullScreenPayload(images: images, audioData: audioData)
                                    }
                            }
                        }
                        .frame(height: 340)
                        .clipped()
                        .animation(.easeInOut(duration: 0.9), value: audioPhotoIndex)
                        
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
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 44))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text("Photos not available")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        .frame(height: 320)
                    }
                    
                    VStack(spacing: 12) {
                        Image(systemName: audioRecorder.isPlaying ? "waveform" : "waveform.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .symbolEffect(.pulse, isActive: audioRecorder.isPlaying)
                        
                        Button {
                            if audioRecorder.isPlaying {
                                audioRecorder.stopPlaying()
                                stopAudioPhotoSlideshow()
                            } else {
                                audioRecorder.playAudio(from: audioData)
                                startAudioPhotoSlideshow(imageCount: images.count, duration: audioDuration(for: audioData))
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: audioRecorder.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 36))
                                Text(audioRecorder.isPlaying ? "Stop" : "Play Story")
                                    .font(DesignSystem.Typography.headline)
                            }
                            .foregroundStyle(DesignSystem.Colors.accent)
                        }
                        .buttonStyle(.plain)
                        
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .symbolEffect(.variableColor, isActive: audioRecorder.isPlaying)
                    }
                }
                .frame(maxWidth: .infinity)
                .onAppear {
                    audioPhotoIndex = 0
                    stopAudioPhotoSlideshow()
                }
                .onDisappear {
                    stopAudioPhotoSlideshow()
                }
                .onChange(of: audioRecorder.isPlaying) { _, isPlaying in
                    if isPlaying {
                        startAudioPhotoSlideshow(imageCount: images.count, duration: audioDuration(for: audioData))
                    } else {
                        stopAudioPhotoSlideshow()
                    }
                }
            } else if let photoData = memory.displayPhotoData {
                // Photo - with pinch to zoom (cached)
                CachedAsyncImage(data: photoData)
                    .scaledToFit()
                    .scaleEffect(imageScale)
                    .offset(imageOffset)
                    .onTapGesture {
                        fullScreenPhoto = PhotoDataWrapper(data: photoData)
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                imageScale = value
                            }
                            .onEnded { _ in
                                withAnimation(.spring()) {
                                    if imageScale < 1 {
                                        imageScale = 1
                                        imageOffset = .zero
                                    }
                                }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if imageScale > 1 {
                                    imageOffset = value.translation
                                }
                            }
                            .onEnded { _ in
                                if imageScale <= 1 {
                                    withAnimation(.spring()) {
                                        imageOffset = .zero
                                    }
                                }
                            }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    private var metadataView: some View {
        VStack(spacing: 12) {
            // Creator and Date Created
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    
                    if let createdBy = memory.createdBy {
                        Text(createdBy)
                            .font(.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Created")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    
                    if let date = memory.date {
                        Text(date, style: .date)
                            .font(.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
            }
            .padding()
            .background(DesignSystem.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Location (if available)
            if let location = memory.locationName, !location.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundStyle(DesignSystem.Colors.accent)
                            Text(location)
                                .font(.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(DesignSystem.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Memory Type and Opened Date
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    
                    if let memoryTypeString = memory.memoryType,
                       let memoryType = MemoryType(rawValue: memoryTypeString) {
                        HStack(spacing: 6) {
                            Image(systemName: memoryType.icon)
                                .font(.caption)
                                .foregroundStyle(memoryType.accentColor)
                            Text(memoryType.rawValue)
                                .font(.body)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Opened")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    
                    if let watchedDate = memory.watchedDate {
                        Text(watchedDate, style: .date)
                            .font(.body)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                }
            }
            .padding()
            .background(DesignSystem.Colors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func noteView(note: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Message")
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            Text(note)
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DesignSystem.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Audio Photo Slideshow Helpers

extension GrandchildGiftView {
    private func startAudioPhotoSlideshow(imageCount: Int, duration: TimeInterval) {
        stopAudioPhotoSlideshow()
        guard imageCount > 1 else { return }
        let safeDuration = max(duration, 1.0)
        let secondsPerImage = max(3.0, safeDuration / Double(imageCount))
        
        audioPhotoTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(secondsPerImage))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.9)) {
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
}

extension GrandchildMemoryDetailView {
    private func startAudioPhotoSlideshow(imageCount: Int, duration: TimeInterval) {
        stopAudioPhotoSlideshow()
        guard imageCount > 1 else { return }
        let safeDuration = max(duration, 1.0)
        let secondsPerImage = max(3.0, safeDuration / Double(imageCount))
        
        audioPhotoTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(secondsPerImage))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.9)) {
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
}

// MARK: - Video Thumbnail Helper

extension GrandchildMemoryDetailView {
    static func generateThumbnail(from videoData: Data) -> Data? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        
        do {
            try videoData.write(to: tempURL)
            let asset = AVAsset(url: tempURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {
            print("Error generating thumbnail: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }
    
    static func generateThumbnail(from videoURL: URL) -> Data? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let time = CMTime(seconds: 0, preferredTimescale: 1)
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.7)
        } catch {
            print("Error generating thumbnail: \(error)")
            return nil
        }
    }
}

// MARK: - Grandchild Family Tree View

struct GrandchildFamilyTreeView: View {
    let grandchild: CDGrandchild
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: FetchRequestBuilders.allAncestors())
    private var ancestors: FetchedResults<CDAncestor>
    @FetchRequest(fetchRequest: FetchRequestBuilders.allContributors())
    private var contributors: FetchedResults<CDContributor>
    @State private var selectedAncestor: CDAncestor?
    @State private var selectedPet: CDFamilyPet?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var grandchildAncestors: [CDAncestor] {
        ancestors.filter { $0.grandchild?.id == grandchild.id }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // FIXED HEADER - Grandchild (not zoomable/pannable)
                    if let photoData = grandchild.photoData, let uiImage = UIImage(data: photoData) {
                        VStack(spacing: 12) {
                            VStack(spacing: 8) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(DesignSystem.Colors.teal, lineWidth: 3))

                                Text(grandchild.name ?? "")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                            }
                            
                            // Branching connector
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                                    .frame(width: 2, height: 20)
                                
                                ZStack {
                                    Rectangle()
                                        .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                                        .frame(width: 100, height: 2)
                                        .offset(x: -50)
                                    
                                    Rectangle()
                                        .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                                        .frame(width: 100, height: 2)
                                        .offset(x: 50)
                                    
                                    Circle()
                                        .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                                .frame(height: 20)
                            }
                        }
                        .padding(.top, 20)
                        .padding(.horizontal)
                        .background(DesignSystem.Colors.backgroundPrimary)
                    }
                    
                    // SCROLLABLE/ZOOMABLE TREE CONTENT
                    ZStack {
                        DesignSystem.Colors.backgroundPrimary
                        
                        VStack(spacing: 32) {
                            ForEach(0...3, id: \.self) { generation in
                                generationView(generation: generation)
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
            .navigationTitle("Family Tree")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
        }
        .sheet(item: $selectedAncestor) { ancestor in
            // Show ancestor detail view (read-only for grandchild)
            GrandchildAncestorDetailView(ancestor: ancestor)
        }
    }

    @ViewBuilder
    private func generationView(generation: Int) -> some View {
        let generationAncestors = grandchildAncestors
            .filter { $0.generation == generation }

        if !generationAncestors.isEmpty {
            VStack(spacing: 16) {
                Text(generationLabel(for: generation))
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                // Split by lineage - paternal on left, maternal on right
                let paternalAncestors = generationAncestors.filter { $0.lineage == AncestorLineage.paternal.rawValue }
                let maternalAncestors = generationAncestors.filter { $0.lineage == AncestorLineage.maternal.rawValue }
                
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
            
            // Connector line between generations
            if generation < 3 {
                Rectangle()
                    .fill(DesignSystem.Colors.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 30)
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
        }
    }

    private func ancestorCardView(ancestor: CDAncestor) -> some View {
        VStack(spacing: 8) {
            if let photoData = ancestor.primaryPhoto, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DesignSystem.Colors.teal, lineWidth: 3))
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 110, height: 110)
            }

            Text(ancestor.name ?? "Unknown")
                .font(DesignSystem.Typography.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text(ancestor.familyRole ?? ancestor.yearsDisplay)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: 120)
        .onTapGesture {
            selectedAncestor = ancestor
        }
    }

    private func groupIntoCouples(ancestors: [CDAncestor]) -> [(primary: CDAncestor, spouse: CDAncestor?)] {
        var processed = Set<UUID>()
        var couples: [(primary: CDAncestor, spouse: CDAncestor?)] = []

        for ancestor in ancestors {
            guard let ancestorId = ancestor.id, !processed.contains(ancestorId) else { continue }
            processed.insert(ancestorId)

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

// MARK: - Grandchild Ancestor Detail View (Read-Only)

struct GrandchildAncestorDetailView: View {
    let ancestor: CDAncestor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let photoData = ancestor.primaryPhoto, let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        if let role = ancestor.familyRole {
                            Text(role)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(DesignSystem.Colors.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        if !ancestor.yearsDisplay.isEmpty {
                            Text(ancestor.yearsDisplay)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }

                        if let story = ancestor.story, !story.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Story")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                                Text(story)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                            .padding()
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(ancestor.name ?? "Ancestor")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(DesignSystem.Colors.accent)
                }
            }
        }
    }
}

// MARK: - Full-Screen Video Player

struct FullScreenVideoPlayer: View {
    let videoURL: URL
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            player = AVPlayer(url: videoURL)
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - Full-Screen Image Viewer

struct FullScreenImageViewer: View {
    let image: UIImage
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
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
                            // Reset to original if zoomed out below 1.0
                            if scale < 1.0 {
                                withAnimation(.spring()) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            if scale > 1.0 {
                                lastOffset = offset
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                            lastScale = 1.0
                        } else {
                            scale = 2.5
                        }
                    }
                }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Full-Screen Photo Viewer (Data-based)

struct FullScreenPhotoDataViewer: View {
    let data: Data
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    CachedAsyncImage(data: data)
                        .scaledToFill()
                    Text("Photo unavailable")
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .clipped()
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1.0 {
                            withAnimation(.spring()) {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        if scale > 1.0 {
                            lastOffset = offset
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                        lastScale = 1.0
                    } else {
                        scale = 2.5
                    }
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}

struct PhotoDataWrapper: Identifiable {
    let id = UUID()
    let data: Data
}

struct PhotoEditorView: UIViewControllerRepresentable {
    let image: UIImage
    let onSave: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let editor = PhotoEditViewController(image: image, onSave: onSave, onCancel: {
            dismiss()
        })
        let navController = UINavigationController(rootViewController: editor)
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

class PhotoEditViewController: UIViewController {
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void
    
    private var imageView: UIImageView!
    private var scrollView: UIScrollView!
    private var cropFrame: UIView!
    private var originalImage: UIImage
    
    init(image: UIImage, onSave: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.originalImage = image
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        title = "Edit Photo"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        
        setupScrollView()
        setupToolbar()
    }
    
    private func setupScrollView() {
        scrollView = UIScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.backgroundColor = .black
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        view.addSubview(scrollView)
        
        imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
    }
    
    private func setupToolbar() {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        let rotateLeft = UIBarButtonItem(image: UIImage(systemName: "rotate.left"), style: .plain, target: self, action: #selector(rotateLeft))
        let rotateRight = UIBarButtonItem(image: UIImage(systemName: "rotate.right"), style: .plain, target: self, action: #selector(rotateRight))
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolbar.items = [flexSpace, rotateLeft, flexSpace, rotateRight, flexSpace]
    }
    
    @objc private func rotateLeft() {
        if let rotated = rotateImage(image: imageView.image ?? image, degrees: -90) {
            imageView.image = rotated
        }
    }
    
    @objc private func rotateRight() {
        if let rotated = rotateImage(image: imageView.image ?? image, degrees: 90) {
            imageView.image = rotated
        }
    }
    
    private func rotateImage(image: UIImage, degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        var newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)
        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return rotatedImage
    }
    
    @objc private func cancelTapped() {
        onCancel()
    }
    
    @objc private func doneTapped() {
        if let editedImage = imageView.image {
            onSave(editedImage)
        }
    }
}

extension PhotoEditViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
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
    
    return GrandchildGiftView()
        .environment(\.managedObjectContext, container.viewContext)
}
