//
//  NotificationManager.swift
//  GrandparentMemories
//
//  Created by Claude on 2026-02-08.
//

import Foundation
import UserNotifications
import CoreData

@MainActor
class NotificationManager {
    static let shared = NotificationManager()
    
    var isAuthorized = false
    
    private init() {}
    
    // MARK: - Authorization
    
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            
            if granted {
                print("🔔 Notification permission granted")
            } else {
                print("🔔 Notification permission denied")
            }
        } catch {
            print("🔔 Error requesting notification permission: \(error)")
        }
    }
    
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - Schedule Gift Release Notifications
    
    func scheduleGiftReleaseNotification(for memory: CDMemory, grandchildName: String) async {
        guard isAuthorized else {
            print("🔔 Cannot schedule notification - not authorized")
            return
        }
        
        guard let memoryID = memory.id else {
            print("🔔 Cannot schedule notification - no memory ID")
            return
        }
        
        // Determine when to send notification
        var triggerDate: Date?
        
        if let releaseDate = memory.releaseDate {
            triggerDate = releaseDate
        } else if memory.releaseAge > 0 {
            // Would need grandchild birthdate to calculate - skip for now
            print("🔔 Age-based notifications not yet implemented")
            return
        } else {
            // No schedule - immediate release (no notification needed)
            return
        }
        
        guard let notificationDate = triggerDate else { return }
        
        // Don't schedule if date is in the past
        guard notificationDate > Date() else {
            print("🔔 Release date is in the past - skipping notification")
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "🎁 A Gift Has Arrived!"
        content.body = "Your grandparents have a special memory waiting for you."
        content.sound = .default
        content.badge = 1
        content.userInfo = ["memoryID": memoryID.uuidString]
        
        // Create date components trigger
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Create request
        let identifier = "gift-release-\(memoryID.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🔔 Scheduled notification for \(notificationDate)")
        } catch {
            print("🔔 Error scheduling notification: \(error)")
        }
    }
    
    // MARK: - Cancel Notification
    
    func cancelGiftReleaseNotification(for memoryID: UUID) {
        let identifier = "gift-release-\(memoryID.uuidString)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("🔔 Cancelled notification for memory \(memoryID)")
    }
    
    // MARK: - Update All Notifications
    
    func updateAllGiftNotifications(memories: [CDMemory], grandchildName: String) async {
        // Remove all pending gift notifications
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await center.pendingNotificationRequests()
        let giftIdentifiers = pendingRequests.filter { $0.identifier.hasPrefix("gift-release-") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: giftIdentifiers)
        
        // Schedule new notifications for all scheduled gifts
        for memory in memories {
            guard let releaseDate = memory.releaseDate else { continue }
            guard releaseDate > Date() else { continue }
            guard memory.isReleased == false || memory.isReleased == nil else { continue }
            
            await scheduleGiftReleaseNotification(for: memory, grandchildName: grandchildName)
        }
        
        print("🔔 Updated all gift notifications")
    }
    
    // MARK: - Birthday Notifications (Age-based releases)
    
    func scheduleBirthdayCheck(for grandchild: String, birthDate: Date) async {
        guard isAuthorized else { return }
        
        // Schedule yearly notification to check for age-based releases
        let content = UNMutableNotificationContent()
        content.title = "🎂 Happy Birthday!"
        content.body = "Check for special gifts from your grandparents!"
        content.sound = .default
        content.badge = 1
        
        // Trigger on birthday at 9am
        var components = Calendar.current.dateComponents([.month, .day], from: birthDate)
        components.hour = 9
        components.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let identifier = "birthday-check-\(grandchild)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🔔 Scheduled birthday notification for \(grandchild)")
        } catch {
            print("🔔 Error scheduling birthday notification: \(error)")
        }
    }
    
    // MARK: - Clear Badge
    
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: - Auto Release Notifications

    func scheduleAutoReleaseGraceStart(graceWeeks: Int) async {
        guard isAuthorized else {
            print("🔔 Cannot schedule auto-release notification - not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Legacy Auto‑Release: Grace Period Started"
        content.body = "Open the app to pause auto‑release. Weekly releases begin after the grace period."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "auto-release-grace-start", content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🔔 Scheduled auto-release grace start notification")
        } catch {
            print("🔔 Error scheduling auto-release grace start: \(error)")
        }
    }

    func scheduleAutoReleaseStart(after graceWeeks: Int) async {
        guard isAuthorized else {
            print("🔔 Cannot schedule auto-release notification - not authorized")
            return
        }

        let graceSeconds = TimeInterval(max(graceWeeks, 1) * 7 * 24 * 60 * 60)
        let content = UNMutableNotificationContent()
        content.title = "Legacy Auto‑Release Will Begin"
        content.body = "Weekly memory releases start now. Open the app to pause."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: graceSeconds, repeats: false)
        let request = UNNotificationRequest(identifier: "auto-release-start", content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("🔔 Scheduled auto-release start notification")
        } catch {
            print("🔔 Error scheduling auto-release start: \(error)")
        }
    }

    func cancelAutoReleaseNotifications() {
        let identifiers = ["auto-release-grace-start", "auto-release-start"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        print("🔔 Cancelled auto-release notifications")
    }
}
