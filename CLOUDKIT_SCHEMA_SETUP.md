# CloudKit Schema Initialization Guide

## 🚨 Critical First Step: Initialize CloudKit Schema

The "stopped sharing" error you're seeing is because **CloudKit doesn't know about your data model yet**.

---

## Why This Happens

When you create a Core Data object and try to share it:
1. Core Data tries to sync it to CloudKit ✅
2. CloudKit looks for the record type (e.g., "CDUserProfile") ❌
3. Record type doesn't exist yet → sync fails
4. Share creation fails → "stopped sharing" error

**Solution:** Tell CloudKit about your Core Data model ONCE.

---

## Option 1: Automatic Schema Initialization (Recommended)

### Step 1: Uncomment the initialization line

In `CoreDataStack.swift` around line 113, you'll see:

```swift
#if DEBUG
// Uncomment this line ONCE to initialize the schema, then comment it back out:
// try? container.initializeCloudKitSchema(options: [])
#endif
```

**Change it to:**

```swift
#if DEBUG
// Uncomment this line ONCE to initialize the schema, then comment it back out:
try? container.initializeCloudKitSchema(options: [])
#endif
```

### Step 2: Run the app ONCE

1. Build and run the app on a physical device
2. Wait for it to launch
3. Check Console.app - you should see CloudKit activity
4. **Wait 2-3 minutes** for schema creation
5. Quit the app

### Step 3: Comment it back out

**IMPORTANT:** Change the line back to:

```swift
#if DEBUG
// Uncomment this line ONCE to initialize the schema, then comment it back out:
// try? container.initializeCloudKitSchema(options: [])
#endif
```

### Step 4: Verify in CloudKit Dashboard

1. Go to https://icloud.developer.apple.com/dashboard
2. Select your container: `iCloud.Sofanauts.GrandparentMemories`
3. Go to Schema → Record Types
4. **Verify you see:**
   - `CD_UserProfile`
   - `CD_Grandchild`
   - `CD_Memory`
   - `CD_Contributor`
   - etc.

If you see these record types, the schema is initialized! ✅

---

## Option 2: Manual Schema Check (Debugging)

If automatic initialization doesn't work, let's debug:

### Check Current Schema

Add this temporary code to `CoreDataStack.swift`:

```swift
// Add this after stores are loaded (around line 120)
Task {
    let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")
    let database = container.privateCloudDatabase

    // Try to fetch any existing records
    let query = CKQuery(recordType: "CD_UserProfile", predicate: NSPredicate(value: true))
    do {
        let results = try await database.records(matching: query)
        print("✅ Found \(results.matchResults.count) CD_UserProfile records")
    } catch {
        print("❌ Schema check failed: \(error.localizedDescription)")
        print("   This usually means the schema isn't initialized yet")
    }
}
```

Run the app and check Console.app. If you see "Schema check failed", the schema isn't initialized.

---

## Option 3: Fresh Start (If Nothing Works)

### Delete All CloudKit Data

1. Go to CloudKit Dashboard
2. Development → Data
3. Delete all records
4. Development → Schema → Record Types
5. Delete all custom record types (keep system types)

### Reinitialize

1. Follow Option 1 above
2. The schema will be created from scratch

---

## Common Issues

### Issue: "Operation not permitted"

**Cause:** Not signed into iCloud on the device

**Fix:**
1. Settings → [Your Name]
2. Verify you're signed in
3. Settings → [Your Name] → iCloud
4. Enable iCloud Drive

### Issue: "Account unavailable"

**Cause:** iCloud container not properly configured

**Fix:**
1. Xcode → Select project
2. Select GrandparentMemories target
3. Signing & Capabilities
4. Verify iCloud capability is enabled
5. Verify CloudKit is checked
6. Verify container `iCloud.Sofanauts.GrandparentMemories` is selected

### Issue: Schema initialization hangs

**Cause:** Too much data to create fake records

**Fix:**
1. This is normal - can take 2-5 minutes
2. Don't quit the app
3. Check Console.app for progress
4. Wait patiently

---

## After Schema Is Initialized

### Test Sharing Again

1. **Device 1:** Create test grandchild
2. **Save and wait 30 seconds** ← IMPORTANT
3. Pull to refresh or restart app
4. Check Console.app - should see "✅ Remote change notification"
5. NOW try sharing
6. Send link to Device 2
7. Should work! ✅

### Why the Wait?

Even with schema initialized:
- Core Data → CloudKit sync is async
- Takes 10-30 seconds for new records to upload
- If you share before upload completes → "stopped sharing" error

**Best Practice:**
1. Create data
2. Save
3. Wait 30-60 seconds
4. Verify data exists in CloudKit Dashboard
5. Then share

---

## Verification Checklist

Before testing sharing, verify:

- [ ] iCloud account signed in on both devices
- [ ] iCloud Drive enabled
- [ ] App has iCloud capability in Xcode
- [ ] CloudKit schema initialized (check dashboard)
- [ ] Test data created and saved
- [ ] Waited 30+ seconds after creating data
- [ ] Can see data in CloudKit Dashboard → Data section
- [ ] Internet connection on both devices

---

## CloudKit Dashboard Navigation

1. **Go to:** https://icloud.developer.apple.com/dashboard
2. **Sign in** with your Apple Developer account
3. **Select container:** `iCloud.Sofanauts.GrandparentMemories`

### Check Schema:
- Schema → Record Types
- Look for `CD_` prefixed types
- Should see all your Core Data entities

### Check Data:
- Development → Data
- Select "Private Database"
- Select record type (e.g., "CD_UserProfile")
- Click "Query Records"
- Should see your test data

### Check Zones:
- Development → Data → Private Database
- Should see "com.apple.coredata.cloudkit.zone"
- After sharing, should see additional zones

---

## Quick Diagnostic Script

Add this to a button in your app for testing:

```swift
Button("Check CloudKit Status") {
    Task {
        let container = CKContainer(identifier: "iCloud.Sofanauts.GrandparentMemories")

        // Check account status
        let status = try? await container.accountStatus()
        print("📊 Account Status: \(status?.rawValue ?? -1)")
        // 0 = not determined, 1 = available, 2 = restricted, 3 = no account

        // Check if we can access private database
        let database = container.privateCloudDatabase
        let testZone = CKRecordZone(zoneName: "com.apple.coredata.cloudkit.zone")

        do {
            let _ = try await database.recordZone(for: testZone.zoneID)
            print("✅ Can access CloudKit zone")
        } catch {
            print("❌ Cannot access CloudKit: \(error.localizedDescription)")
        }
    }
}
```

Expected output:
```
📊 Account Status: 1
✅ Can access CloudKit zone
```

---

## TL;DR - Quick Fix

1. In `CoreDataStack.swift` line ~113: Uncomment `try? container.initializeCloudKitSchema(options: [])`
2. Run app ONCE on device
3. Wait 2-3 minutes
4. Comment it back out
5. Check CloudKit Dashboard - should see `CD_` record types
6. Create test data
7. **Wait 30 seconds**
8. Try sharing again

This should fix the "stopped sharing" error! 🎯

---

## Still Not Working?

If you still see errors after this:

1. **Check Console.app** for detailed error messages
2. **Check CloudKit Dashboard** → Development → Logs
3. **Verify both devices** are on same iCloud environment (Development vs Production)
4. **Try deleting the app** from both devices and reinstalling
5. **Check that you're testing in Development environment**, not Production

The schema initialization is the #1 cause of "stopped sharing" errors with new CloudKit apps.
