//
//  PaywallView.swift
//  GrandparentMemories
//
//  Created by Claude on 07/02/2026.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""

    let source: PaywallSource
    let onDismiss: (() -> Void)?

    enum PaywallSource {
        case onboarding
        case memoryLimit
    }

    init(source: PaywallSource, onDismiss: (() -> Void)? = nil) {
        self.source = source
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            // Warm gradient background
            LinearGradient(
                colors: [
                    DesignSystem.Colors.backgroundPrimary,
                    DesignSystem.Colors.backgroundSecondary,
                    DesignSystem.Colors.backgroundTertiary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(DesignSystem.Colors.primaryGradient)

                        Text("Unlimited Memories")
                            .font(DesignSystem.Typography.largeTitle)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        if source == .memoryLimit {
                            VStack(spacing: 8) {
                                Text("You've reached your 10 free memories!")
                                    .font(DesignSystem.Typography.title3)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .multilineTextAlignment(.center)
                                
                                Text("Upgrade now to continue capturing precious moments with unlimited memories")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal)
                        } else {
                            Text("Start with 10 free memories, then upgrade to unlimited")
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 40)

                    // Features
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(
                            icon: "infinity",
                            title: "Unlimited Memories",
                            description: "Create as many memories as you want"
                        )

                        FeatureRow(
                            icon: "person.2.fill",
                            title: "Co-Grandparent Collaboration",
                            description: "Both grandparents contribute from their own devices - each with their own Apple ID"
                        )

                        FeatureRow(
                            icon: "paintpalette.fill",
                            title: "Color-Coded Contributions",
                            description: "See who added what - Grandpa in teal, Grandma in pink"
                        )

                        FeatureRow(
                            icon: "lock.shield.fill",
                            title: "Individual Child Privacy",
                            description: "Each grandchild gets unique access - they only see memories shared with them"
                        )

                        FeatureRow(
                            icon: "video.circle.fill",
                            title: "Welcome Videos",
                            description: "Record personal welcome messages that each grandchild sees first"
                        )

                        FeatureRow(
                            icon: "calendar.badge.clock",
                            title: "Memory Scheduling",
                            description: "Release memories on birthdays, milestones, or specific ages"
                        )

                        FeatureRow(
                            icon: "icloud.fill",
                            title: "Automatic iCloud Sync",
                            description: "All memories safely synced across all grandparent devices"
                        )
                    }
                    .padding(.horizontal, 24)

                    // Pricing Options
                    VStack(spacing: 20) {
                        Text("Choose Your Plan")
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        
                        // Annual Plan - Always show for development
                        PricingOption(
                            title: "Annual",
                            price: "£19.99/year",
                            description: "Renews yearly",
                            isRecommended: false,
                            isPurchasing: isPurchasing
                        ) {
                            if let annualProduct = storeManager.products.first(where: { $0.id.contains("annual") }) {
                                await purchaseProduct(annualProduct)
                            } else {
                                errorMessage = "Products are still loading. Please wait a moment and try again."
                                showError = true
                            }
                        }
                        
                        // Lifetime Plan
                        PricingOption(
                            title: "Lifetime",
                            price: "£99.99",
                            description: "Pay once, own forever",
                            isRecommended: true,
                            isPurchasing: isPurchasing
                        ) {
                            if let lifetimeProduct = storeManager.products.first(where: { $0.id.contains("lifetime") }) {
                                await purchaseProduct(lifetimeProduct)
                            } else {
                                errorMessage = "Products are still loading. Please wait a moment and try again."
                                showError = true
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Restore button
                    Button {
                        Task {
                            await storeManager.restorePurchases()
                            if storeManager.isPremium {
                                handleSuccess()
                            }
                        }
                    } label: {
                        Text("Restore Purchases")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }

                    // Skip/Maybe Later button
                    Button {
                        handleDismiss()
                    } label: {
                        Text(source == .memoryLimit ? "Maybe Later (Stay with 10 free memories)" : "Maybe Later")
                            .font(DesignSystem.Typography.callout)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 40)

                    // Terms
                    Text("Payment will be charged to your Apple Account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            print("🎯 PaywallView appeared - products count: \(storeManager.products.count)")
            Task {
                await storeManager.loadProducts()
                print("🎯 After load - products count: \(storeManager.products.count)")
                if !storeManager.products.isEmpty {
                    for product in storeManager.products {
                        print("🎯 Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
                    }
                }
            }
        }
    }

    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true

        do {
            let success = try await storeManager.purchase(product)
            if success {
                handleSuccess()
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
            showError = true
        }

        isPurchasing = false
    }

    private func handleSuccess() {
        if source == .onboarding {
            handleDismiss()
        } else {
            dismiss()
            onDismiss?()
        }
    }

    private func handleDismiss() {
        dismiss()
        onDismiss?()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text(description)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }
}

struct PricingOption: View {
    let title: String
    let price: String
    let description: String
    let isRecommended: Bool
    let isPurchasing: Bool
    let onPurchase: () async -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Left side - Plan info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(DesignSystem.Typography.title2)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    if isRecommended {
                        Text("BEST VALUE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DesignSystem.Colors.accent, in: Capsule())
                    }
                }
                
                Text(price)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.primary)
                
                Text(description)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            // Right side - Buy button
            Button {
                Task {
                    await onPurchase()
                }
            } label: {
                HStack(spacing: 6) {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("Buy")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(DesignSystem.Colors.tealGradient)
                .clipShape(Circle())
                .shadow(
                    color: DesignSystem.Colors.teal.opacity(0.3),
                    radius: 8,
                    y: 4
                )
            }
            .disabled(isPurchasing)
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(Color.white)
                .shadow(
                    color: DesignSystem.Shadows.medium.color,
                    radius: DesignSystem.Shadows.medium.radius,
                    y: DesignSystem.Shadows.medium.y
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(isRecommended ? DesignSystem.Colors.accent : Color.clear, lineWidth: 2)
        )
    }
}

#Preview("Onboarding") {
    PaywallView(source: .onboarding)
}

#Preview("Memory Limit") {
    PaywallView(source: .memoryLimit)
}
