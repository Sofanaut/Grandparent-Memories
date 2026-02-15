//
//  ShareCodeManager.swift
//  GrandparentMemories
//
//  Manages 6-digit share codes that map to CloudKit share URLs
//  Uses CloudKit Public Database (free, no backend needed)
//

import Foundation
import CloudKit

/// Manages share codes for CloudKit sharing without URL bubbles in Messages
class ShareCodeManager {
    static let shared = ShareCodeManager()
    
    private let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
    private let publicDatabase: CKDatabase
    
    private init() {
        publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - Share Code Generation
    
    /// Generates a unique 6-digit code and stores it in CloudKit Public Database
    /// - Parameter shareURL: The CloudKit share URL to map to this code
    /// - Returns: A 6-digit code (e.g., "ABC123")
    func generateShareCode(for shareURL: String) async throws -> String {
        // Generate random 6-character code (alphanumeric, easy to read)
        var code = ""
        var attempts = 0
        let maxAttempts = 10
        
        repeat {
            code = generateRandomCode()
            attempts += 1
            
            // Check if code already exists
            let exists = try await checkCodeExists(code)
            if !exists {
                break
            }
            
            if attempts >= maxAttempts {
                throw ShareCodeError.tooManyAttempts
            }
        } while attempts < maxAttempts
        
        // Store code → URL mapping in public database
        try await saveCodeMapping(code: code, shareURL: shareURL)
        
        return code
    }
    
    /// Looks up the CloudKit share URL for a given code
    /// - Parameter code: The 6-digit share code
    /// - Returns: The CloudKit share URL
    func lookupShareURL(for code: String) async throws -> String {
        let normalizedCode = code
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        
        // Query public database for this code
        let predicate = NSPredicate(format: "code == %@", normalizedCode)
        let query = CKQuery(recordType: "ShareCode", predicate: predicate)
        
        let results = try await publicDatabase.records(matching: query)
        
        guard let firstMatch = results.matchResults.first else {
            throw ShareCodeError.codeNotFound
        }
        
        let (recordID, result) = firstMatch
        
        switch result {
        case .success(let record):
            guard let shareURL = record["shareURL"] as? String else {
                throw ShareCodeError.invalidRecord
            }
            return shareURL
            
        case .failure(let error):
            throw ShareCodeError.lookupFailed(error.localizedDescription)
        }
    }

    /// Looks up a share URL with retries to handle CloudKit propagation delays
    func lookupShareURLWithRetry(for code: String, attempts: Int = 12, delaySeconds: Int = 10) async throws -> String {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await lookupShareURL(for: code)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .seconds(delaySeconds))
                }
            }
        }
        throw lastError ?? ShareCodeError.codeNotFound
    }
    
    // MARK: - Private Helpers
    
    /// Generates a random 6-character code (letters and numbers only, excluding ambiguous characters)
    private func generateRandomCode() -> String {
        // Exclude ambiguous characters: 0, O, I, 1
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in characters.randomElement()! })
    }
    
    /// Checks if a code already exists in the database
    private func checkCodeExists(_ code: String) async throws -> Bool {
        let predicate = NSPredicate(format: "code == %@", code)
        let query = CKQuery(recordType: "ShareCode", predicate: predicate)
        
        let results = try await publicDatabase.records(matching: query)
        return !results.matchResults.isEmpty
    }
    
    /// Saves a code → URL mapping to the public database
    private func saveCodeMapping(code: String, shareURL: String) async throws {
        let recordID = CKRecord.ID(recordName: "ShareCode-\(code)")
        let record = CKRecord(recordType: "ShareCode", recordID: recordID)

        record["code"] = code as CKRecordValue
        record["shareURL"] = shareURL as CKRecordValue

        // Note: createdAt and expiresAt fields removed due to CloudKit Dashboard issues
        // CloudKit automatically tracks createdTimestamp, so we can use that if needed

        _ = try await publicDatabase.save(record)

        print("✅ Share code saved: \(code) → \(shareURL)")
    }
    
    // MARK: - Error Types
    
    enum ShareCodeError: LocalizedError {
        case tooManyAttempts
        case codeNotFound
        case invalidRecord
        case lookupFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .tooManyAttempts:
                return "Failed to generate unique code. Please try again."
            case .codeNotFound:
                return "Your share is still syncing. Please wait 30–60 seconds and try again."
            case .invalidRecord:
                return "Invalid share code record. Please request a new code from the sender."
            case .lookupFailed(let message):
                return "Failed to look up share code: \(message)"
            }
        }
    }
}
