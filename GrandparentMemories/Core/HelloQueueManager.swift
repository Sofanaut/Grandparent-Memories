//
//  HelloQueueManager.swift
//  GrandparentMemories
//
//  Weekly release pipeline for Hello Queue
//

import Foundation
import CoreData

final class HelloQueueManager {
    static let shared = HelloQueueManager()

    private init() {}

    func isEnabled(for grandchildID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: enabledKey(for: grandchildID))
    }

    func setEnabled(_ enabled: Bool, for grandchildID: UUID) {
        UserDefaults.standard.set(enabled, forKey: enabledKey(for: grandchildID))
    }

    func startDate(for grandchildID: UUID) -> Date? {
        let ts = UserDefaults.standard.double(forKey: startKey(for: grandchildID))
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    func setStartDate(_ date: Date, for grandchildID: UUID) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: startKey(for: grandchildID))
    }

    func runIfNeeded(viewContext: NSManagedObjectContext, grandchildID: UUID) {
        guard isEnabled(for: grandchildID) else { return }
        guard let startDate = startDate(for: grandchildID) else { return }

        let now = Date()
        guard now >= startDate else { return }

        let lastRelease = UserDefaults.standard.double(forKey: lastReleaseKey(for: grandchildID))
        let sevenDays: TimeInterval = 7 * 24 * 60 * 60
        if lastRelease > 0, now.timeIntervalSince1970 - lastRelease < sevenDays {
            return
        }

        let didRelease = releaseNextHelloItem(viewContext: viewContext, grandchildID: grandchildID)
        if didRelease {
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastReleaseKey(for: grandchildID))
        }
    }

    private func releaseNextHelloItem(viewContext: NSManagedObjectContext, grandchildID: UUID) -> Bool {
        var didRelease = false
        viewContext.performAndWait {
            let request = NSFetchRequest<CDMemory>(entityName: "CDMemory")
            request.predicate = NSPredicate(format: "privacy == %@ AND (isReleased == NO OR isReleased == nil)", MemoryPrivacy.helloQueue.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

            if let memory = try? viewContext.fetch(request).first(where: { memory in
                let grandchildren = memory.grandchildren as? Set<CDGrandchild> ?? []
                return grandchildren.contains(where: { $0.id == grandchildID })
            }) {
                memory.isReleased = true
                memory.wasWatched = false
                memory.watchedDate = nil
                do {
                    try viewContext.save()
                    didRelease = true
                } catch {
                    print("❌ Hello queue release failed: \(error.localizedDescription)")
                }
            }
        }

        return didRelease
    }

    private func enabledKey(for id: UUID) -> String {
        "helloQueueEnabled_\(id.uuidString)"
    }

    private func startKey(for id: UUID) -> String {
        "helloQueueStartTimestamp_\(id.uuidString)"
    }

    private func lastReleaseKey(for id: UUID) -> String {
        "helloQueueLastReleaseTimestamp_\(id.uuidString)"
    }
}
