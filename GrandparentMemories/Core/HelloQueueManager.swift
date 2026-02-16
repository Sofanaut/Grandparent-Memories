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

    func runIfNeeded(viewContext: NSManagedObjectContext, grandchildID: UUID) {
        viewContext.performAndWait {
            let request = NSFetchRequest<CDGrandchild>(entityName: "CDGrandchild")
            request.predicate = NSPredicate(format: "id == %@", grandchildID as CVarArg)
            request.fetchLimit = 1

            guard let grandchild = try? viewContext.fetch(request).first else { return }
            guard grandchild.heartbeatsEnabled else { return }
            guard let startDate = grandchild.heartbeatsStartDate else { return }

            let now = Date()
            guard now >= startDate else { return }

            let lastReleaseDate = grandchild.heartbeatsLastReleaseDate
            let sevenDays: TimeInterval = 7 * 24 * 60 * 60
            if let lastReleaseDate, now.timeIntervalSince(lastReleaseDate) < sevenDays {
                return
            }

            let didRelease = releaseNextHelloItem(viewContext: viewContext, grandchildID: grandchildID)
            if didRelease {
                grandchild.heartbeatsLastReleaseDate = now
                do {
                    try viewContext.save()
                } catch {
                    print("❌ Hello queue release save failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func releaseNextHelloItem(viewContext: NSManagedObjectContext, grandchildID: UUID) -> Bool {
        var didRelease = false
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

        return didRelease
    }
}
