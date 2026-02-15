# CloudKit Environment Reset and Testing Steps

**Date:** 2026-02-10
**Status:** Ready to execute

---

## Step 1: Reset CloudKit Development Environment

1. Go to: https://icloud.developer.apple.com/dashboard
2. Sign in with your Apple Developer account
3. Select: `iCloud.Sofanauts.GrandparentMemories`
4. Click: **Development** environment
5. Click: **Reset Development Environment**
6. Confirm the reset

⚠️ **This will delete all development data!**

---

## Step 2: Initialize CloudKit Schema

The schema initialization code is now **UNCOMMENTED** in `CoreDataStack.swift` (lines 107-120).

### On Phone 1 (Your main testing device):

1. **Delete the app** if it's already installed
2. **Build and run** from Xcode
3. **Watch the Console** in Xcode - you should see:
   ```
   ✅ CloudKit schema initialization started
   ⏳ Wait 2-3 minutes for schema to upload to CloudKit
   ```
4. **Let the app run** for 2-3 minutes (don't close it)
5. Complete onboarding if needed
6. **Quit the app**

### Verify Schema Was Created:

1. Go back to: https://icloud.developer.apple.com/dashboard
2. Select: `iCloud.Sofanauts.GrandparentMemories`
3. Go to: **Development → Schema → Record Types**
4. **You should see:**
   - `CD_UserProfile`
   - `CD_Grandchild`
   - `CD_Memory`
   - `CD_ScheduledGift`
   - `CD_GiftDelivery`
   - etc.

✅ If you see these record types, schema is initialized!

---

## Step 3: Comment Out Schema Initialization

**CRITICAL:** Schema initialization should only run ONCE!

1. Open `CoreDataStack.swift`
2. Find lines 107-120
3. Comment out the `do-catch` block:
   ```swift
   #if DEBUG
   // do {
   //     try container.initializeCloudKitSchema(options: [])
   //     print("✅ CloudKit schema initialization started")
   //     print("⏳ Wait 2-3 minutes for schema to upload to CloudKit")
   //     print("📋 Then check CloudKit Dashboard for CD_ record types")
   // } catch {
   //     print("❌ Schema initialization failed: \(error)")
   // }
   #endif
   ```

4. **Save the file**

---

## Step 4: Create Test Data

### On Phone 1:

1. **Build and run** (with schema initialization commented out)
2. Complete onboarding
3. **Create a test grandchild:**
   - Name: "Emma"
   - Birthday: Any date
4. **Add a test memory:**
   - Take a quick photo OR record 3-second video
   - Add title: "Test Memory"
5. **IMPORTANT:** Wait 30-60 seconds for CloudKit sync
6. **Verify sync in Console.app:**
   - Look for CloudKit sync messages
   - Should see "Successfully exported" or similar

---

## Step 5: Share with Phone 2

### On Phone 1:

1. Go to **More** tab (or wherever your Share Management is)
2. Find the share button (probably in Settings or Vault)
3. Tap **"Invite Co-Grandparent"** (or similar)
4. **UICloudSharingController should appear**
5. ⚠️ **CRITICAL CHECK:**
   - Does it show **"Add People"** option?
   - Or just **"Copy Link"**?

### If it shows "Add People":
6. Tap **"Add People"**
7. Choose **"Share via Messages"**
8. Enter Phone 2's number/email
9. Send the invitation

### If it only shows "Copy Link":
- This means the participant-based sharing isn't working
- We'll need to debug why UICloudSharingController isn't showing participant options

---

## Step 6: Accept Share on Phone 2

### On Phone 2:

1. **Receive the Messages invitation**
2. **Tap the CloudKit share link**
3. **iOS should show CloudKit share acceptance UI**
4. **Tap "Open" or "Accept"**
5. **App should launch**
6. If prompted, complete onboarding
7. **Wait 30-60 seconds**
8. **Check if Emma and the test memory appear**

---

## Step 7: Verify Collaboration

### Test bidirectional sync:

1. **On Phone 2:** Add a new memory to Emma
2. **On Phone 1:** Wait 30-60 seconds → Verify new memory appears
3. **On Phone 1:** Edit Emma's birthday
4. **On Phone 2:** Wait 30-60 seconds → Verify changes appear

---

## Success Criteria

✅ CloudKit schema visible in Dashboard
✅ Test data created on Phone 1
✅ Share invitation shows "Add People" option
✅ Phone 2 receives and accepts share
✅ Phone 2 can see Emma and test memory
✅ Changes sync bidirectionally
✅ No "Item Unavailable" errors
✅ No "Stopped Sharing" errors

---

## If It Still Fails

### Check Console.app on both phones:

**On Phone 1 (Owner):**
- Look for share creation logs
- Check for CloudKit upload errors
- Verify share URL was generated

**On Phone 2 (Participant):**
- Look for share acceptance logs
- Check for "share not found" errors
- Verify shared store is being used

### Common Issues:

**"Share not found" on Phone 2:**
- Schema not initialized → Go back to Step 2
- Data not synced before sharing → Wait longer in Step 4
- Different iCloud accounts? → Verify both phones signed in

**"Stopped Sharing" error:**
- Usually means schema is missing
- Reset and repeat from Step 1

**UICloudSharingController shows only "Copy Link":**
- This is the issue we were debugging
- Means participant-based sharing isn't working
- Need to check share configuration in CoreDataStack

---

## Next Steps After Success

1. **Remove diagnostic logging** (all the print statements)
2. **Test with real family data**
3. **Deploy schema to Production** before App Store launch
4. **Beta test via TestFlight**
5. **Submit to App Review**

---

## Timeline

- **Step 1-3:** 5 minutes (reset + initialize + verify)
- **Step 4:** 2 minutes (create data + wait for sync)
- **Step 5-6:** 2 minutes (share + accept)
- **Step 7:** 2 minutes (verify collaboration)

**Total:** ~10-15 minutes for complete test

---

## Important Notes

- ✅ Both phones MUST use different iCloud accounts
- ✅ Both phones MUST be physical devices (not simulators)
- ✅ Both phones MUST have internet connection
- ✅ Both phones MUST have iCloud Drive enabled
- ✅ Wait times are REAL - CloudKit is not real-time

---

**Ready to start? Begin with Step 1: Reset the CloudKit Development environment.**
