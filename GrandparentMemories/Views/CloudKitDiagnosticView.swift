//
//  CloudKitDiagnosticView.swift
//  GrandparentMemories
//
//  Diagnostic tool to check CloudKit setup and schema
//  Add this to your More section temporarily for debugging
//

import SwiftUI
import CloudKit
import CoreData

struct CloudKitDiagnosticView: View {
    @State private var diagnosticResults: [String] = []
    @State private var isRunning = false
    
    var body: some View {
        List {
            Section("CloudKit Diagnostics") {
                Text("Use this to verify CloudKit is set up correctly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button("Run Diagnostics") {
                    runDiagnostics()
                }
                .disabled(isRunning)
            }
            
            if !diagnosticResults.isEmpty {
                Section("Results") {
                    ForEach(diagnosticResults, id: \.self) { result in
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("CloudKit Diagnostics")
    }
    
    private func runDiagnostics() {
        isRunning = true
        diagnosticResults = []
        
        Task {
            await performDiagnostics()
            await MainActor.run {
                isRunning = false
            }
        }
    }
    
    private func performDiagnostics() async {
        let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
        
        // Test 1: Account Status
        await addResult("=== Test 1: iCloud Account ===")
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                await addResult("✅ iCloud account available")
            case .noAccount:
                await addResult("❌ No iCloud account - sign in to Settings")
            case .restricted:
                await addResult("⚠️ iCloud account restricted")
            case .couldNotDetermine:
                await addResult("❌ Could not determine account status")
            case .temporarilyUnavailable:
                await addResult("⚠️ iCloud temporarily unavailable")
            @unknown default:
                await addResult("❌ Unknown account status")
            }
        } catch {
            await addResult("❌ Error checking account: \(error.localizedDescription)")
        }
        
        // Test 2: Private Database Access
        await addResult("\n=== Test 2: Private Database ===")
        do {
            let database = container.privateCloudDatabase
            let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
            
            let zone = try await database.recordZone(for: zoneID)
            await addResult("✅ Can access Core Data CloudKit zone")
            await addResult("   Zone: \(zone.zoneID.zoneName)")
        } catch {
            await addResult("⚠️ Core Data zone not found (normal on first launch)")
            await addResult("   Error: \(error.localizedDescription)")
        }
        
        // Test 3: Schema Check
        await addResult("\n=== Test 3: CloudKit Schema ===")
        let recordTypes = ["CD_UserProfile", "CD_Grandchild", "CD_Memory"]
        
        for recordType in recordTypes {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                
                let database = container.privateCloudDatabase
                let results = try await database.records(matching: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: 1)
                
                let count = results.matchResults.count
                await addResult("✅ \(recordType): \(count) record(s) found")
            } catch let error as CKError {
                if error.code == .unknownItem {
                    await addResult("⚠️ \(recordType): Schema not initialized")
                    await addResult("   → Run initializeCloudKitSchema() once")
                } else {
                    await addResult("❌ \(recordType): \(error.localizedDescription)")
                }
            } catch {
                await addResult("❌ \(recordType): \(error.localizedDescription)")
            }
        }
        
        // Test 4: Core Data Stores
        await addResult("\n=== Test 4: Core Data Stores ===")
        let stack = CoreDataStack.shared
        await addResult("✅ Private store exists: \(stack.privatePersistentStore != nil)")
        await addResult("✅ Shared store exists: \(stack.sharedPersistentStore != nil)")
        
        // Test 5: Test Data
        await addResult("\n=== Test 5: Local Data ===")
        let context = stack.viewContext
        await MainActor.run {
            let profileRequest: NSFetchRequest<CDUserProfile> = CDUserProfile.fetchRequest()
            let profiles = (try? context.fetch(profileRequest)) ?? []
            addResultSync("📊 Local profiles: \(profiles.count)")
            
            let grandchildRequest: NSFetchRequest<CDGrandchild> = CDGrandchild.fetchRequest()
            let grandchildren = (try? context.fetch(grandchildRequest)) ?? []
            addResultSync("📊 Local grandchildren: \(grandchildren.count)")
            
            if let profile = profiles.first {
                let store = profile.objectID.persistentStore
                if store == stack.privatePersistentStore {
                    addResultSync("✅ Profile in private store (correct)")
                } else if store == stack.sharedPersistentStore {
                    addResultSync("⚠️ Profile in shared store (unexpected)")
                } else {
                    addResultSync("❌ Profile in unknown store")
                }
            }
        }
        
        // Final summary
        await addResult("\n=== Summary ===")
        let hasErrors = diagnosticResults.contains(where: { $0.contains("❌") })
        let hasWarnings = diagnosticResults.contains(where: { $0.contains("⚠️") })
        
        if !hasErrors && !hasWarnings {
            await addResult("✅ All checks passed - ready to share!")
        } else if hasWarnings && !hasErrors {
            await addResult("⚠️ Some warnings - check schema initialization")
        } else {
            await addResult("❌ Errors found - see details above")
        }
        
        await addResult("\n💡 Next Steps:")
        if diagnosticResults.contains(where: { $0.contains("Schema not initialized") }) {
            await addResult("1. Uncomment initializeCloudKitSchema() in CoreDataStack.swift")
            await addResult("2. Run app once, wait 2-3 minutes")
            await addResult("3. Comment it back out")
            await addResult("4. Run diagnostics again")
        } else {
            await addResult("1. Create test grandchild if you haven't")
            await addResult("2. Wait 30 seconds")
            await addResult("3. Try sharing again")
        }
    }
    
    @MainActor
    private func addResult(_ result: String) {
        diagnosticResults.append(result)
    }
    
    private func addResultSync(_ result: String) {
        diagnosticResults.append(result)
    }
}

#Preview {
    NavigationStack {
        CloudKitDiagnosticView()
    }
}
