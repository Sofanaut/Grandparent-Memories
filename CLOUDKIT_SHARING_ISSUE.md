# CloudKit Code-Based Sharing Issue

**Date:** 2026-02-13
**Status:** BLOCKED - Need Help

---

## 🎯 What We're Trying to Do

Implement a **6-digit code system** for CloudKit sharing to avoid the iMessage URL bubble problem.

**User Flow:**
1. Device 1 (Grandad): Create grandchild → Add memories → Share → Get 6-digit code (e.g., "ABC123")
2. Device 2 (Grandchild): Install app → "I'm a Grandchild" → Enter code → See memories

**Why Not Direct URL Sharing:**
- CloudKit share URLs in iMessage show large preview bubbles
- We want simple codes that can be texted or said verbally
- Better UX for elderly users

---

## 🏗 Current Architecture

### Share Code System
1. **ShareCodeManager** stores code→URL mappings in CloudKit Public Database
2. **SimpleShareView** creates CloudKit share and generates 6-digit code
3. **AcceptShareView** looks up code, gets URL, fetches share metadata, accepts share

### Code Flow:
```
Device 1: Create CKShare → Wait 90s → Generate code → Save to Public DB
Device 2: Enter code → Lookup URL → fetchShareMetadata → acceptShareInvitations
```

---

## ❌ The Problem

**Error:** `"share not found"` when calling `CKContainer.fetchShareMetadata(with: URL)`

**Full Error from Screenshot:**
```
CKDPResponseOperationResult: 0x703936a80> {
  code = failure;
  error = {
    errorDescription = "share not found";
    errorKey = ck1dhnm77;
    serverError = {
      type = notFound;
    };
  }
} when fetching short token metadata for https://www.icloud.com/share/...
```

**When it Happens:**
- Even after waiting 90 seconds for CloudKit sync
- With fresh shares (we delete old shares before creating new ones)
- On different Apple IDs
- With fresh device installs

---

## 🔧 What We've Tried

### Attempt 1: Increase Wait Time
- **Before:** 45 seconds
- **After:** 90 seconds
- **Result:** Still fails ❌

### Attempt 2: Delete Stale Shares
- Added code to purge existing shares before creating new ones
- Ensures fresh share each time
- **Result:** Still fails ❌

### Attempt 3: Change Share Permissions
- **Before:** `share.publicPermission = .none` (participant-only)
- **After:** `share.publicPermission = .readOnly` (anyone with link)
- **Reasoning:** Participant-only mode requires explicit participant invitation
- **Result:** NOT TESTED YET (realized security issue)

### Attempt 4: Enhanced Logging
Added detailed logging to track:
- Share creation success
- Share URL generation
- Public permission settings
- Record IDs and participant counts

---

## 🚨 Critical Discovery

### Permission Conflict:
- `.none` (participant-only) = Secure but requires UICloudSharingController to add participants
- `.readOnly` (public) = Would allow 6-digit codes BUT grandchild could see ALL memories immediately (breaks time-lock feature)

**The Dilemma:**
- Grandparents want to lock certain memories until grandchild turns 18, 21, etc.
- If share is public (.readOnly), grandchild can see everything right away
- If share is participant-only (.none), we can't use simple 6-digit codes

---

## 🤔 Questions We Need Answered

### 1. Share Metadata Fetch Timing
**Q:** How long does CloudKit actually need to propagate a share before `fetchShareMetadata` will succeed?
- We've tried 45s and 90s
- Is there a way to verify share is ready before generating code?
- Should we poll/retry instead of fixed wait?

### 2. Participant-Only Sharing with Codes
**Q:** Can we make participant-only sharing work with 6-digit codes?
- Could we add participant programmatically using their Apple ID/email?
- Does the recipient need to be added BEFORE they can fetch metadata?
- Is there a way to get their Apple ID from the code entry screen?

### 3. Filtered Sharing
**Q:** Can we share only a FILTERED subset of data (only released memories)?
- Create separate CDGrandchildReleasedMemories entity?
- Share that instead of full CDGrandchild?
- Would this maintain proper relationships?

### 4. Alternative Approaches
**Q:** Are we fundamentally going about this wrong?
- Should we use CloudKit Public Database differently?
- Should we store the share metadata itself in Public DB?
- Is there a different CloudKit sharing pattern we should use?

---

## 📁 Key Files

### ShareCodeManager.swift
- Lines 28-53: `generateShareCode()` - Creates code and saves to CloudKit Public DB
- Lines 58-83: `lookupShareURL()` - Retrieves URL for given code
- **Status:** Working correctly ✅

### SimpleShareView.swift
- Lines 250-338: `generateShareLink()` - Creates share, waits, generates code
- Lines 282-293: Deletes existing shares first
- Lines 300-318: Creates share and waits 90 seconds
- **Status:** Share creation succeeds, but subsequent fetch fails ❌

### AcceptShareView.swift
- Lines 127-180: `acceptShare()` - Looks up code and accepts share
- **Issue:** Fails at `fetchShareMetadata` with "share not found"

### CoreDataStack.swift
- Lines 204-263: `share()` - Creates CKShare using NSPersistentCloudKitContainer
- Line 238: `share.publicPermission = .readOnly` (current setting)
- **Note:** Can be changed to `.none` for security

---

## 🧪 Testing Setup

### Devices:
- Device 1 (Grandad): iPhone with Apple ID #1
- Device 2 (Grandchild): iPhone with Apple ID #2 (different)

### Test Steps:
1. **Device 1:**
   - Create account
   - Add grandchild "Jaz"
   - Add memory (photo)
   - Tap "Share with Grandchild"
   - Wait 90 seconds
   - Get code (e.g., "GT2BEY")

2. **Device 2:**
   - Fresh install
   - Tap "I'm a Grandchild"
   - Enter code "GT2BEY"
   - Tap "Accept Invitation"
   - **ERROR:** "share not found"

### Console Output (Device 1):
```
📋 Share created:
   - Share URL: https://www.icloud.com/share/0ccRu8SPOPu00G5u8aQmpM2wA#Jaz's_Memories
   - Record ID: ...
   - Public permission: 1 (readOnly)
   - Participant count: 1
⏳ Waiting 90 seconds for CloudKit to sync the share...
✅ Share should be ready now
✅ Share code saved: GT2BEY → https://www.icloud.com/share/...
```

### Console Output (Device 2):
```
🔍 Looking up share code: GT2BEY
✅ Found URL for code: https://www.icloud.com/share/...
🔄 Fetching share metadata from CloudKit...
❌ fetchShareMetadata failed: share not found
```

---

## 💡 Possible Solutions to Explore

### Option A: Participant Invitation via Code
- When grandchild enters code, also ask for their email/phone
- Programmatically add them as participant using `CKShare.addParticipant()`
- Then they can fetch metadata
- **Question:** Does this require owner to be online?

### Option B: Filtered Entity Sharing
- Create `CDReleasedMemory` entity
- Copy released memories to this entity when releasing
- Share the CDReleasedMemory parent instead of CDGrandchild
- Maintains time-lock security
- **Question:** How do updates sync?

### Option C: Use UICloudSharingController
- Accept the Apple UI for participant invitation
- Still use 6-digit codes to identify WHICH share
- But use system UI for actual share acceptance
- **Downside:** Not as clean UX

### Option D: Wait Much Longer
- Try 5 minutes instead of 90 seconds?
- Add retry logic with exponential backoff?
- Show progress to user while waiting?
- **Question:** Is there a max wait time?

### Option E: Store Metadata in Public DB
- Instead of just storing URL, store full share metadata
- Device 2 doesn't need to fetch from CloudKit
- Gets everything from Public DB
- **Question:** Is this secure? Allowed?

---

## 🎯 What We Need

**Immediate:** Help understanding why `fetchShareMetadata` fails even 90+ seconds after share creation

**Strategic:** Architecture advice on how to do code-based sharing with:
1. Time-locked content (some memories hidden until later)
2. Simple 6-digit codes (no email/phone required)
3. No backend server (CloudKit only)
4. Zero ongoing costs

---

## 📚 References

- [CloudKit Sharing Documentation](https://developer.apple.com/documentation/cloudkit/shared_records)
- [NSPersistentCloudKitContainer Sharing](https://developer.apple.com/documentation/coredata/sharing_core_data_objects_between_icloud_users)
- [WWDC 2021 - CloudKit Sharing](https://developer.apple.com/videos/play/wwdc2021/10015/)
- Our previous implementation: `DUAL_STORE_IMPLEMENTATION_COMPLETE.md`

---

## 🆘 Help Wanted

If you know:
- Why CloudKit share metadata fetch fails with "share not found"
- How to do participant-only sharing with simple codes
- Better patterns for filtered CloudKit sharing
- Whether we're fundamentally misunderstanding something

**Please help!** We've been stuck on this for hours and are running out of ideas.

---

**Test Project Available:** GrandparentMemories Xcode project
**CloudKit Container:** `iCloud.Sofanauts.GrandparentMemories`
**Environment:** iOS 18.3+, Xcode 16+
