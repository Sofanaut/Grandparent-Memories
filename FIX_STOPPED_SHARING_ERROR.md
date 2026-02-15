# Fix "Stopped Sharing" Error - Quick Guide

## 🎯 The Problem

You're seeing "stopped sharing" when the second phone tries to open the share link.

## 🔍 Root Cause

**CloudKit doesn't know about your data model yet.** The schema hasn't been initialized.

---

## ✅ Quick Fix (5 Minutes)

### Step 1: Initialize CloudKit Schema

1. Open `CoreDataStack.swift`
2. Find line ~113 (in the `persistentContainer` lazy var)
3. Look for this commented line:
   ```swift
   // try? container.initializeCloudKitSchema(options: [])
   ```

4. **Uncomment it:**
   ```swift
   try? container.initializeCloudKitSchema(options: [])
   ```

### Step 2: Run Once

1. Build and run on **your physical iPhone**
2. Let it launch completely
3. **Wait 2-3 minutes** (this creates CloudKit schema)
4. You'll see lots of activity in Console.app
5. Quit the app

### Step 3: Comment It Back Out

**IMPORTANT:** Go back to `CoreDataStack.swift` and comment it out again:

```swift
// try? container.initializeCloudKitSchema(options: [])
```

This should only run ONCE, not every time the app launches.

### Step 4: Verify Schema

1. Go to https://icloud.developer.apple.com/dashboard
2. Sign in with your Apple Developer account
3. Select: `iCloud.Sofanauts.GrandparentMemories`
4. Go to: Development → Schema → Record Types
5. **Check:** You should see record types like:
   - `CD_UserProfile`
   - `CD_Grandchild`
   - `CD_Memory`
   - etc.

If you see these, schema is initialized! ✅

---

## 📊 Use Diagnostic Tool

I've added a diagnostic view to help you:

### Add to Your App (Temporarily)

In your More/Settings view, add:

```swift
NavigationLink("CloudKit Diagnostics") {
    CloudKitDiagnosticView()
}
```

### What It Checks:
- ✅ iCloud account status
- ✅ CloudKit database access
- ✅ Schema initialization
- ✅ Core Data stores
- ✅ Local data

**Run this AFTER initializing schema** to verify everything is ready.

---

## 🧪 Test Sharing Again

After schema initialization:

### On Device 1 (Owner):
1. Create a test grandchild
2. **Save and wait 30 seconds** ← IMPORTANT
3. Run diagnostics to verify data is in CloudKit
4. Tap "Invite Co-Grandparent"
5. Send link via Messages

### On Device 2 (Participant):
1. Tap the link
2. Accept share
3. Wait 30-60 seconds
4. Data should appear!

---

## 🐛 If Still Not Working

### Check Console.app

The diagnostic logging I added will show exactly what's happening:

```
🔄 Attempting to share object: CDUserProfile
   Object ID: ...
✅ Object is in private store
🔄 No existing share found - creating new share...
⏳ Waiting 5 seconds for CloudKit sync...
🔄 Creating new CloudKit share via persistentContainer.share()...
```

Look for **❌ errors** - they'll tell you exactly what's wrong.

### Common Error Messages:

**"Schema not initialized"**
→ Run `initializeCloudKitSchema()` as described above

**"Record not found"**
→ Wait longer (60+ seconds) before sharing

**"No iCloud account"**
→ Sign in to iCloud on the device

**"Account restricted"**
→ Check iCloud settings, may need to enable iCloud Drive

---

## 📝 Checklist

Before testing sharing:

- [ ] CloudKit schema initialized (via `initializeCloudKitSchema()`)
- [ ] Schema visible in CloudKit Dashboard
- [ ] Both devices signed into iCloud
- [ ] iCloud Drive enabled on both
- [ ] Test data created and saved
- [ ] Waited 30+ seconds after creating data
- [ ] Ran diagnostics - all ✅ checks passed
- [ ] Internet connection on both devices

---

## 🎯 Expected Timeline

1. **Initialize schema:** 2-3 minutes (one-time)
2. **Create test data:** 1 minute
3. **Wait for sync:** 30-60 seconds
4. **Share:** Instant
5. **Participant sees data:** 30-60 seconds

**Total time:** ~5 minutes for first share

---

## 💡 Why This Happens

CloudKit is a **schema-based database**:
- Must define record types before storing data
- `initializeCloudKitSchema()` creates types from Core Data model
- Without schema → CloudKit rejects records
- Rejected records → can't share them

This is a **one-time setup step**, not a bug.

---

## 🚀 After This Works

Once schema is initialized and sharing works:

1. **Remove diagnostic view** (not needed for production)
2. **Keep the dual-store architecture** (this is permanent)
3. **Test with real data** to verify end-to-end
4. **Deploy schema to Production** before App Store launch

---

## TL;DR

1. Uncomment `initializeCloudKitSchema()` in CoreDataStack.swift
2. Run app once, wait 2-3 minutes
3. Comment it back out
4. Check CloudKit Dashboard - should see `CD_` record types
5. Create test data, wait 30 seconds
6. Try sharing again
7. Should work! ✅

**This is the fix for "stopped sharing" errors.**
