//
//  AutoReleaseManager.swift
//  GrandparentMemories
//
//  Handles inactivity-based auto release of vault memories
//

import Foundation
import CoreData

final class AutoReleaseManager {
    static let shared = AutoReleaseManager()

    private init() {}

    func markActive() {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: "autoReleaseLastActiveTimestamp")
        // Reset grace if user is active again
        UserDefaults.standard.set(0.0, forKey: "autoReleaseGraceStartTimestamp")
        NotificationManager.shared.cancelAutoReleaseNotifications()
    }

    func runIfNeeded(viewContext: NSManagedObjectContext) {
        guard UserDefaults.standard.bool(forKey: "autoReleaseEnabled") else { return }

        let inactivityMonths = max(UserDefaults.standard.integer(forKey: "autoReleaseInactivityMonths"), 1)
        let graceWeeks = max(UserDefaults.standard.integer(forKey: "autoReleaseGraceWeeks"), 1)

        let now = Date().timeIntervalSince1970
        let lastActive = UserDefaults.standard.double(forKey: "autoReleaseLastActiveTimestamp")
        let inactivitySeconds = TimeInterval(inactivityMonths * 30 * 24 * 60 * 60)

        guard now - lastActive >= inactivitySeconds else { return }

        let graceStart = UserDefaults.standard.double(forKey: "autoReleaseGraceStartTimestamp")
        if graceStart <= 0 {
            UserDefaults.standard.set(now, forKey: "autoReleaseGraceStartTimestamp")
            Task {
                await NotificationManager.shared.checkAuthorizationStatus()
                if !NotificationManager.shared.isAuthorized {
                    await NotificationManager.shared.requestAuthorization()
                }
                await NotificationManager.shared.scheduleAutoReleaseGraceStart(graceWeeks: graceWeeks)
                await NotificationManager.shared.scheduleAutoReleaseStart(after: graceWeeks)
            }
            return
        }

        let graceSeconds = TimeInterval(graceWeeks * 7 * 24 * 60 * 60)
        guard now - graceStart >= graceSeconds else { return }

        let lastRelease = UserDefaults.standard.double(forKey: "autoReleaseWeeklyLastReleaseTimestamp")
        let sevenDays: TimeInterval = 7 * 24 * 60 * 60
        guard now - lastRelease >= sevenDays else { return }

        let didRelease = releaseNextVaultItem(viewContext: viewContext)
        if didRelease {
            UserDefaults.standard.set(now, forKey: "autoReleaseWeeklyLastReleaseTimestamp")
        }
    }

    private func releaseNextVaultItem(viewContext: NSManagedObjectContext) -> Bool {
        var didRelease = false
        viewContext.performAndWait {
            let request = NSFetchRequest<CDMemory>(entityName: "CDMemory")
            request.predicate = NSPredicate(format: "isReleased == NO OR isReleased == nil")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
            request.fetchLimit = 1

            if let memory = try? viewContext.fetch(request).first {
                memory.isReleased = true
                memory.wasWatched = false
                memory.watchedDate = nil
                do {
                    try viewContext.save()
                    didRelease = true
                } catch {
                    print("❌ Auto release failed: \(error.localizedDescription)")
                }
            }
        }

        return didRelease
    }
}
