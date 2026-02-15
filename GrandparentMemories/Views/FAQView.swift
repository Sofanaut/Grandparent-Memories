//
//  FAQView.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-09.
//

import SwiftUI

struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expandedSections: Set<String> = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(DesignSystem.Colors.accent)
                        
                        Text("Frequently Asked Questions")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal)
                    
                    // FAQ Sections
                    ForEach(faqSections, id: \.title) { section in
                        FAQSection(section: section, expandedSections: $expandedSections)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Help & FAQ")
            .navigationBarTitleDisplayMode(.inline)
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

// MARK: - FAQ Section View

struct FAQSection: View {
    let section: FAQSectionData
    @Binding var expandedSections: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            Text(section.title)
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.top, 8)
            
            // Questions
            ForEach(section.items, id: \.question) { item in
                FAQItem(item: item, expandedSections: $expandedSections)
            }
        }
    }
}

// MARK: - FAQ Item View

struct FAQItem: View {
    let item: FAQItemData
    @Binding var expandedSections: Set<String>
    
    private var isExpanded: Bool {
        expandedSections.contains(item.question)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedSections.remove(item.question)
                    } else {
                        expandedSections.insert(item.question)
                    }
                }
            } label: {
                HStack {
                    Text(item.question)
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .font(.title3)
                }
                .padding()
                .background(DesignSystem.Colors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            
            // Answer
            if isExpanded {
                Text(item.answer)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignSystem.Colors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Data Models

struct FAQSectionData {
    let title: String
    let items: [FAQItemData]
}

struct FAQItemData {
    let question: String
    let answer: String
}

// MARK: - FAQ Content

private let faqSections: [FAQSectionData] = [
    FAQSectionData(
        title: "🚀 Getting Started",
        items: [
            FAQItemData(
                question: "What is Grandparent Memories?",
                answer: "Grandparent Memories helps you create photos, videos, voice notes, letters, and stories for your grandchildren. You decide when each memory is delivered."
            ),
            FAQItemData(
                question: "How do I create my first memory?",
                answer: "Tap the + button. Choose a memory type (photo, video, audio, story, recipe, letter, etc.), create it, and pick how it should be delivered."
            ),
            FAQItemData(
                question: "Who can see my memories?",
                answer: "Only you and other invited grandparents can see private items. Grandchildren only see memories you release or schedule for them."
            )
        ]
    ),
    
    FAQSectionData(
        title: "📸 Creating & Capturing",
        items: [
            FAQItemData(
                question: "Can I import photos and videos?",
                answer: "Yes. You can import from your photo library or capture new ones in the app."
            ),
            FAQItemData(
                question: "Can I set a title?",
                answer: "Yes. Titles help you find memories later. Heartbeats now show your title (or “Untitled” if you leave it blank)."
            ),
            FAQItemData(
                question: "Do I have to schedule right away?",
                answer: "No. You can save to Vault and decide later, or schedule immediately."
            )
        ]
    ),
    
    FAQSectionData(
        title: "💓 Heartbeats (Weekly Releases)",
        items: [
            FAQItemData(
                question: "What are Heartbeats?",
                answer: "Heartbeats are a weekly delivery queue. You can load it with many memories, then release one each week to a grandchild."
            ),
            FAQItemData(
                question: "When do they start?",
                answer: "You choose a start date and time. Releases follow that time each week."
            ),
            FAQItemData(
                question: "Where do Heartbeats live?",
                answer: "Heartbeats live only in the Heartbeats queue (not in Vault). After release, they remain in the Timeline."
            ),
            FAQItemData(
                question: "Can I edit or delete Heartbeats?",
                answer: "Yes. Each Heartbeat has an edit button for title/notes and a delete option."
            )
        ]
    ),
    
    FAQSectionData(
        title: "🗄️ Vault & Scheduling",
        items: [
            FAQItemData(
                question: "What is the Vault?",
                answer: "Vault is for unscheduled memories only. It’s where you store items until you decide when to release them."
            ),
            FAQItemData(
                question: "If a memory is scheduled, does it appear in Vault?",
                answer: "No. Once a memory is scheduled (date, age, or Heartbeats), it does not appear in Vault."
            ),
            FAQItemData(
                question: "Where do released memories show up?",
                answer: "Released memories appear in the Timeline for the grandchild and remain there."
            )
        ]
    ),
    
    FAQSectionData(
        title: "👨‍👩‍👧‍👦 Sharing & Collaboration",
        items: [
            FAQItemData(
                question: "How do I invite a co‑grandparent?",
                answer: "Go to More → Invite Co‑Grandparent and send the share link. They accept and join your family vault."
            ),
            FAQItemData(
                question: "Do we need different Apple IDs?",
                answer: "Yes. CloudKit sharing requires each person to have their own Apple ID."
            ),
            FAQItemData(
                question: "How do I share with grandchildren?",
                answer: "Select a grandchild and send them a share link. Their app opens with your shared memories."
            )
        ]
    ),
    
    FAQSectionData(
        title: "🛡️ Legacy Auto‑Release",
        items: [
            FAQItemData(
                question: "What is Legacy Auto‑Release?",
                answer: "It’s a safety feature that can release stored memories automatically if the app is inactive for a long time."
            ),
            FAQItemData(
                question: "How does the grace period work?",
                answer: "You choose a grace period. During that time you can cancel or change the plan before auto‑release begins."
            ),
            FAQItemData(
                question: "How often do memories release?",
                answer: "Once enabled, memories can release on a weekly cadence until the queue is empty."
            )
        ]
    ),
    
    FAQSectionData(
        title: "🔒 Data & Privacy",
        items: [
            FAQItemData(
                question: "Where is my data stored?",
                answer: "Your memories are stored in your iCloud account using Apple’s CloudKit. We don’t store your data on our servers."
            ),
            FAQItemData(
                question: "Is my data backed up?",
                answer: "Yes. iCloud backs everything up automatically across your devices."
            ),
            FAQItemData(
                question: "Who can see private memories?",
                answer: "Only you and invited co‑grandparents. Grandchildren only see released or scheduled items."
            )
        ]
    ),
    
    FAQSectionData(
        title: "📱 Devices & Syncing",
        items: [
            FAQItemData(
                question: "Can I use multiple devices?",
                answer: "Yes. Sign into the same Apple ID on each device and your data will sync."
            ),
            FAQItemData(
                question: "What happens if I get a new phone?",
                answer: "Install the app and sign into the same Apple ID. Your data will sync back automatically."
            ),
            FAQItemData(
                question: "Why aren’t my memories syncing?",
                answer: "Check iCloud sign‑in, iCloud Drive, storage space, and internet connection. Then reopen the app."
            )
        ]
    ),
    
    FAQSectionData(
        title: "⭐ Premium",
        items: [
            FAQItemData(
                question: "What’s included for free?",
                answer: "The free version includes up to 10 memories total and access to core features."
            ),
            FAQItemData(
                question: "What does Premium unlock?",
                answer: "Unlimited memories and all premium features with a one‑time purchase or subscription (as shown in the app)."
            )
        ]
    ),
    
    FAQSectionData(
        title: "🔧 Troubleshooting",
        items: [
            FAQItemData(
                question: "Videos won’t play",
                answer: "Check your connection and iCloud storage. Large videos may take a few seconds to load."
            ),
            FAQItemData(
                question: "App feels slow",
                answer: "Restart the app or device, and make sure there’s enough free storage."
            ),
            FAQItemData(
                question: "I deleted the app — are my memories gone?",
                answer: "No. Reinstall the app and sign into the same Apple ID to restore everything."
            )
        ]
    )
]

#Preview {
    FAQView()
}
