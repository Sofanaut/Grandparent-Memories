//
//  GuardianReleaseManager.swift
//  GrandparentMemories
//
//  Handles legacy guardian code and weekly vault release
//

import Foundation
import CloudKit
import CoreData

final class GuardianReleaseManager {
    static let shared = GuardianReleaseManager()

    private let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
    private let publicDatabase: CKDatabase

    private init() {
        publicDatabase = container.publicCloudDatabase
    }

    // MARK: - Public API

    func generateGuardianCode(inactivityMonths: Int) async throws -> String {
        var code = ""
        var attempts = 0
        let maxAttempts = 10

        repeat {
            code = generateRandomCode()
            attempts += 1

            let exists = try await checkCodeExists(code)
            if !exists {
                break
            }

            if attempts >= maxAttempts {
                throw GuardianError.tooManyAttempts
            }
        } while attempts < maxAttempts

        try await saveGuardianRecord(code: code, inactivityMonths: inactivityMonths)
        return code
    }

    func fetchGuardianRecord(for code: String) async throws -> CKRecord {
        let normalizedCode = normalize(code)
        let predicate = NSPredicate(format: "code == %@", normalizedCode)
        let query = CKQuery(recordType: "GuardianRelease", predicate: predicate)

        let results = try await publicDatabase.records(matching: query)
        guard let firstMatch = results.matchResults.first else {
            throw GuardianError.codeNotFound
        }

        switch firstMatch.1 {
        case .success(let record):
            return record
        case .failure(let error):
            throw GuardianError.lookupFailed(error.localizedDescription)
        }
    }

    func updateLastActive(code: String, timestamp: TimeInterval) async throws {
        var record = try await fetchGuardianRecord(for: code)
        record["lastActiveTimestamp"] = timestamp as CKRecordValue
        _ = try await publicDatabase.save(record)
    }

    func isEligibleForGuardianRelease(code: String) async throws -> Bool {
        let record = try await fetchGuardianRecord(for: code)
        return isEligible(record: record)
    }

    func enableWeeklyRelease(code: String) async throws {
        var record = try await fetchGuardianRecord(for: code)
        record["weeklyReleaseEnabled"] = true as CKRecordValue
        if record["weeklyLastReleaseTimestamp"] == nil {
            record["weeklyLastReleaseTimestamp"] = 0 as CKRecordValue
        }
        _ = try await publicDatabase.save(record)
    }

    func runWeeklyReleaseIfNeeded(viewContext: NSManagedObjectContext, code: String) async {
        do {
            var record = try await fetchGuardianRecord(for: code)
            guard isEligible(record: record) else { return }
            let weeklyEnabled = record["weeklyReleaseEnabled"] as? Bool ?? false
            guard weeklyEnabled else { return }

            let lastRelease = record["weeklyLastReleaseTimestamp"] as? Double ?? 0
            let now = Date().timeIntervalSince1970
            let sevenDays: TimeInterval = 7 * 24 * 60 * 60
            guard now - lastRelease >= sevenDays else { return }

            let released = releaseNextVaultItem(viewContext: viewContext)
            guard released else { return }

            record["weeklyLastReleaseTimestamp"] = now as CKRecordValue
            _ = try await publicDatabase.save(record)
        } catch {
            print("❌ Guardian weekly release failed: \(error.localizedDescription)")
        }
    }

    func releaseNextVaultItem(viewContext: NSManagedObjectContext) -> Bool {
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
                    print("❌ Failed to release vault item: \(error.localizedDescription)")
                }
            }
        }

        return didRelease
    }

    // MARK: - Helpers

    private func saveGuardianRecord(code: String, inactivityMonths: Int) async throws {
        let normalizedCode = normalize(code)
        let recordID = CKRecord.ID(recordName: "GuardianRelease-\(normalizedCode)")
        let record = CKRecord(recordType: "GuardianRelease", recordID: recordID)

        record["code"] = normalizedCode as CKRecordValue
        record["enabled"] = true as CKRecordValue
        record["inactivityMonths"] = inactivityMonths as CKRecordValue
        record["lastActiveTimestamp"] = Date().timeIntervalSince1970 as CKRecordValue
        record["weeklyReleaseEnabled"] = false as CKRecordValue
        record["weeklyLastReleaseTimestamp"] = 0 as CKRecordValue

        _ = try await publicDatabase.save(record)
        print("✅ Guardian code saved: \(normalizedCode)")
    }

    private func checkCodeExists(_ code: String) async throws -> Bool {
        let normalizedCode = normalize(code)
        let predicate = NSPredicate(format: "code == %@", normalizedCode)
        let query = CKQuery(recordType: "GuardianRelease", predicate: predicate)
        let results = try await publicDatabase.records(matching: query)
        return !results.matchResults.isEmpty
    }

    private func isEligible(record: CKRecord) -> Bool {
        let enabled = record["enabled"] as? Bool ?? false
        guard enabled else { return false }

        let inactivityMonths = record["inactivityMonths"] as? Int ?? 6
        let lastActive = record["lastActiveTimestamp"] as? Double ?? 0
        let now = Date().timeIntervalSince1970
        let inactivitySeconds = TimeInterval(inactivityMonths * 30 * 24 * 60 * 60)
        return now - lastActive >= inactivitySeconds
    }

    private func generateRandomCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in characters.randomElement()! })
    }

    private func normalize(_ code: String) -> String {
        return code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum GuardianError: LocalizedError {
        case tooManyAttempts
        case codeNotFound
        case lookupFailed(String)

        var errorDescription: String? {
            switch self {
            case .tooManyAttempts:
                return "Failed to generate a unique guardian code. Please try again."
            case .codeNotFound:
                return "Guardian code not found. Please check the code and try again."
            case .lookupFailed(let message):
                return "Guardian lookup failed: \(message)"
            }
        }
    }
}
