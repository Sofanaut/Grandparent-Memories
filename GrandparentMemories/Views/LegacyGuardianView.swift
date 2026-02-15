//
//  LegacyGuardianView.swift
//  GrandparentMemories
//
//  Legacy & Guardian setup and access
//

import SwiftUI
import CoreData

struct LegacyGuardianView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @AppStorage("autoReleaseEnabled") private var autoReleaseEnabled = false
    @AppStorage("autoReleaseInactivityMonths") private var autoReleaseInactivityMonths = 6
    @AppStorage("autoReleaseGraceWeeks") private var autoReleaseGraceWeeks = 4
    @State private var statusMessage: String? = nil
    @State private var statusIsError = false
    @State private var statusText: String = "Not active"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    setupCard

                    statusCard

                    faqCard
                }
                .padding(24)
            }
            .background(DesignSystem.Colors.backgroundPrimary)
            .navigationTitle("Legacy & Guardian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            .task {
                updateStatus()
            }
            .onChange(of: autoReleaseEnabled) { _, _ in
                if autoReleaseEnabled {
                    if autoReleaseInactivityMonths <= 0 { autoReleaseInactivityMonths = 6 }
                    if autoReleaseGraceWeeks <= 0 { autoReleaseGraceWeeks = 4 }
                    AutoReleaseManager.shared.markActive()
                    Task {
                        await NotificationManager.shared.checkAuthorizationStatus()
                        if !NotificationManager.shared.isAuthorized {
                            await NotificationManager.shared.requestAuthorization()
                        }
                    }
                }
                updateStatus()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44))
                .foregroundStyle(DesignSystem.Colors.accent)

            Text("Protect memories if you can’t access the app")
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("If you stop using the app for 6 months, a grace period begins. After grace, one vault memory releases each week.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Auto-Release")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Toggle(isOn: $autoReleaseEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Auto-Release")
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("If you’re inactive, memories will release weekly.")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            HStack {
                Text("Inactivity window")
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("6 months")
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .font(DesignSystem.Typography.subheadline)

            HStack {
                Text("Grace period")
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("4 weeks")
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .font(DesignSystem.Typography.subheadline)
            
            Text("Notifications are used to remind you when grace starts and when releases begin.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(20)
        .background(DesignSystem.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Status")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(statusText)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            if let statusMessage = statusMessage {
                Text(statusMessage)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(statusIsError ? .red : DesignSystem.Colors.textSecondary)
            }
        }
        .padding(20)
        .background(DesignSystem.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var faqCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("• After 6 months of inactivity, a 4‑week grace period starts.")
            Text("• You’ll get a notification when grace starts and when releases begin.")
            Text("• Opening the app during grace pauses auto‑release.")
            Text("• After grace, one vault memory releases each week until the vault is empty.")
        }
        .font(DesignSystem.Typography.caption)
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .padding(20)
        .background(DesignSystem.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func updateStatus() {
        if !autoReleaseEnabled {
            statusText = "Auto-release is off."
            return
        }

        let now = Date().timeIntervalSince1970
        let lastActive = UserDefaults.standard.double(forKey: "autoReleaseLastActiveTimestamp")
        let graceStart = UserDefaults.standard.double(forKey: "autoReleaseGraceStartTimestamp")

        let inactivitySeconds = TimeInterval(autoReleaseInactivityMonths * 30 * 24 * 60 * 60)
        if now - lastActive < inactivitySeconds {
            statusText = "Waiting for inactivity window to pass."
            return
        }

        if graceStart <= 0 {
            statusText = "Grace period will start once inactivity is detected."
            return
        }

        let graceSeconds = TimeInterval(autoReleaseGraceWeeks * 7 * 24 * 60 * 60)
        let remaining = max(graceSeconds - (now - graceStart), 0)
        if remaining > 0 {
            let days = Int(remaining / (24 * 60 * 60))
            statusText = "Grace period active: \(days) days remaining."
            return
        }

        statusText = "Auto-release active: releasing 1 memory per week."
    }
}

#Preview {
    LegacyGuardianView()
        .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
}
