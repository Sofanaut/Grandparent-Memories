//
//  StoreKitManager.swift
//  GrandparentMemories
//
//  Created by Claude on 07/02/2026.
//

import Foundation
import StoreKit
import Combine

@MainActor
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var subscriptionStatus: SubscriptionStatus = .notSubscribed

    // Product IDs - these must match your App Store Connect setup
    private let annualSubscriptionID = "com.sofanauts.grandparentmemories.annual"
    private let lifetimeProductID = "com.sofanauts.grandparentmemories.lifetime"
    
    // IMPORTANT: Set to false for App Store release!
    // Set to true only for local testing without App Store Connect products configured.
    private let useMockProducts = false

    enum SubscriptionStatus {
        case notSubscribed
        case annual
        case lifetime
    }

    private init() {
        // Defer product loading to not block app startup
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    var isPremium: Bool {
        subscriptionStatus != .notSubscribed
    }

    func loadProducts() async {
        if useMockProducts {
            // Mock products for development/testing
            print("🎭 Using mock products for development")
        } else {
            do {
                let productIDs = [annualSubscriptionID, lifetimeProductID]
                products = try await Product.products(for: productIDs)
                print("✅ Loaded \(products.count) products")
                
                if products.isEmpty {
                    print("⚠️ No products found. Make sure products are configured in App Store Connect:")
                    print("   - \(annualSubscriptionID)")
                    print("   - \(lifetimeProductID)")
                }
            } catch {
                print("❌ Failed to load products: \(error)")
            }
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await updateSubscriptionStatus()
            return true

        case .userCancelled:
            return false

        case .pending:
            return false

        @unknown default:
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
        } catch {
            print("❌ Failed to restore purchases: \(error)")
        }
    }

    private func updateSubscriptionStatus() async {
        // Check for lifetime purchase
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.productID == lifetimeProductID {
                    subscriptionStatus = .lifetime
                    purchasedProductIDs.insert(transaction.productID)
                    return
                }
            }
        }

        // Check for active subscription
        if let subscription = products.first(where: { $0.id == annualSubscriptionID }),
           let status = try? await subscription.subscription?.status.first {

            switch status.state {
            case .subscribed, .inGracePeriod:
                subscriptionStatus = .annual
                purchasedProductIDs.insert(annualSubscriptionID)
                return

            default:
                break
            }
        }

        // No active subscription
        subscriptionStatus = .notSubscribed
        purchasedProductIDs.removeAll()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
