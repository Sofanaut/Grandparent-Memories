# CloudKit 6-Digit Code Sharing - Failure Analysis

**Date:** 2026-02-13
**Status:** BLOCKED - Share Metadata Fetch Consistently Fails
**Hours Spent:** ~8 hours

---

## 🎯 What We're Trying To Accomplish

### The Goal
Implement a 6-digit code system for CloudKit sharing that:
1. Avoids iMessage URL preview bubbles (the reason for using codes instead of direct URLs)
2. Allows grandchildren to accept shares on their own devices
3. Maintains time-locked security (some memories hidden until specific ages)
4. Uses zero-cost CloudKit infrastructure (no backend server)

### User Flow (Intended)
1. **Device 1 (Grandparent):** Creates grandchild → Adds memories → Shares → Gets 6-digit code (e.g., "ABC123")
2. **Device 2 (Grandchild):** Opens app → "I'm a Grandchild" → Enters code → Accepts share → Sees memories

---

## 🏗 Architecture Implemented

### Components Built

#### 1. Dual-Store Core Data + CloudKit Setup
**File:** `CoreData/CoreDataStack.swift`

**What It Does:**
- Creates two SQLite stores:
  - `private.sqlite` - Owner's data
  - `shared.sqlite` - Data shared with/from others
- Both configured with NSPersistentCloudKitContainer
- Automatic CloudKit sync for both stores

**Why It's Needed:**
Apple's CloudKit sharing architecture requires separate stores for private and shared data. Without this, participants have nowhere to receive shared data.

**Status:** ✅ Working correctly

---

#### 2. Share Code Manager
**File:** `Core/ShareCodeManager.swift`

**What It Does:**
- Generates random 6-digit codes (alphanumeric, excluding ambiguous characters)
- Stores code→URL mappings in CloudKit Public Database
- Looks up URLs when given a code

**Key Functions:**
```swift
generateShareCode(for: shareURL) async throws -> String
// Creates unique code, saves to CloudKit Public DB
// Returns: "ABC123"

lookupShareURL(for: code) async throws -> String
// Queries CloudKit Public DB for code
// Returns: "https://www.icloud.com/share/..."
```

**CloudKit Schema:**
- Record Type: `ShareCode`
- Fields:
  - `code` (String, QUERYABLE) - The 6-digit code
  - `shareURL` (String) - The CloudKit share URL

**Status:** ✅ Working correctly - codes are created and looked up successfully

---

#### 3. Share Generation View
**File:** `Views/SimpleShareView.swift`

**What It Does:**
1. Creates CloudKit CKShare using Core Data's `share()` method
2. Waits 90 seconds for CloudKit to propagate the share
3. Generates 6-digit code and stores in Public Database
4. Displays code to user

**Key Code Flow:**
```swift
// 1. Check for existing share, delete if found (prevents stale shares)
if let existingShare = await coreDataStack.fetchShare(for: objectToShare) {
    try await coreDataStack.persistentContainer.purgeObjectsAndRecordsInZone(...)
}

// 2. Create new share
let (share, _) = try await coreDataStack.share(objectToShare, title: shareTitle)

// 3. Wait for CloudKit sync
try await Task.sleep(for: .seconds(90))

// 4. Generate code
let code = try await ShareCodeManager.shared.generateShareCode(for: url)
```

**Current Settings:**
- `share.publicPermission = .readOnly` (anyone with link can view)
- 90-second wait before code generation
- Automatically deletes stale shares before creating new ones

**Status:** ✅ Share creation succeeds, code generation succeeds

---

#### 4. Share Acceptance View
**File:** `Views/AcceptShareView.swift`

**What It Does:**
1. Takes 6-digit code from user input
2. Looks up CloudKit share URL from Public Database
3. Fetches share metadata from CloudKit
4. Accepts share into shared.sqlite

**Key Code Flow (Current Implementation):**
```swift
// 1. Look up URL from code
let shareURL = try await ShareCodeManager.shared.lookupShareURL(for: code)

// 2. Parse URL
let url = URL(string: shareURL)

// 3. Fetch metadata using CKFetchShareMetadataOperation
let operation = CKFetchShareMetadataOperation(shareURLs: [url])
let metadata = try await /* ... wait for operation ... */

// 4. Accept share
try await coreDataStack.acceptShareInvitations(from: [metadata])
```

**Status:** ❌ FAILS at step 3 - metadata fetch returns "share not found"

---

## ❌ The Persistent Failure

### What Happens Every Single Time

**Device 1 Console (Success):**
```
📋 Share created:
   - Share URL: https://www.icloud.com/share/036XNwyU92NHcF_DxNcJbjlMQ#Jasmine_Smith's_Memories
   - Record ID: <CKRecordID: cloudkit.zoneshare>
   - Public permission: 2 (readOnly)
   - Participant count: 1
⏳ Waiting 90 seconds for CloudKit to sync the share...
✅ Share should be ready now
✅ Share code saved: 2F9LEU → https://www.icloud.com/share/...
✅ Generated share code: 2F9LEU
```

**Device 2 Console (Failure):**
```
🔍 Looking up share code: 2F9LEU
✅ Found URL for code: https://www.icloud.com/share/036XNwyU92NHcF_DxNcJbjlMQ#Jasmine_Smith's_Memories
✅ Parsed URL successfully
🔄 Fetching share metadata using operation...
❌ fetchShareMetadataOperation failed: share not found
   errorKey = ck1dhnm77
   serverError = { type = notFound }
```

### Error Details
- **CloudKit Error Type:** `notFound`
- **Error Message:** "share not found"
- **Timing:** Happens immediately when Device 2 tries to fetch metadata
- **Consistency:** Happens 100% of the time, every single test
- **What Works:** Code lookup ✅, URL parsing ✅
- **What Fails:** CloudKit metadata fetch ❌

---

## 🔧 Everything We've Tried

### Attempt 1: Increase Wait Time
**Hypothesis:** Share needs more time to sync to CloudKit
**Implementation:** Increased from 45s → 60s → 90s
**Result:** ❌ Still fails immediately on metadata fetch
**Conclusion:** Time alone doesn't solve it

---

### Attempt 2: Delete Stale Shares
**Hypothesis:** Old shares from previous tests were causing conflicts
**Implementation:**
```swift
if let existingShare = await coreDataStack.fetchShare(for: objectToShare) {
    try await coreDataStack.persistentContainer.purgeObjectsAndRecordsInZone(
        with: existingShare.recordID.zoneID,
        in: privateStore
    )
}
```
**Result:** ❌ Still fails with fresh shares
**Conclusion:** Stale shares weren't the issue

---

### Attempt 3: Change Share Permissions
**Hypothesis:** `.none` (participant-only) requires explicit participant invitation
**Implementation:** Changed `share.publicPermission` from `.none` → `.readOnly`
**Result:** ❌ Still fails
**Additional Issue Discovered:** `.readOnly` breaks time-lock security (grandchild can see ALL memories immediately)
**Conclusion:** Permission setting doesn't affect metadata fetch

---

### Attempt 4: Use fetchShareMetadata (Simple API)
**Implementation:**
```swift
let metadata = try await container.fetchShareMetadata(with: url)
```
**Result:** ❌ "share not found"
**Conclusion:** Simple API doesn't work

---

### Attempt 5: Use CKFetchShareMetadataOperation (Operation API)
**Hypothesis:** Operation-based API is more robust than simple API
**Implementation:**
```swift
let operation = CKFetchShareMetadataOperation(shareURLs: [url])
operation.perShareMetadataResultBlock = { shareURL, result in
    // ...
}
container.add(operation)
```
**Result:** ❌ Same "share not found" error
**Conclusion:** API choice doesn't matter - share simply doesn't exist in CloudKit yet

---

### Attempt 6: UIApplication.shared.open (System Handling)
**Hypothesis:** Let iOS handle share acceptance via Universal Links
**Implementation:**
```swift
UIApplication.shared.open(url) { success in
    // Expected: iOS routes to SceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)
}
```
**Result:** ❌ "process may not map database" - permission denied
**Conclusion:** Can't open CloudKit URLs from within the app itself

---

### Attempt 7: Fresh Device Installs
**Hypothesis:** Cached data on devices causing issues
**Implementation:**
- Deleted app from both devices
- Fresh Xcode builds to clean devices
- Different Apple IDs confirmed
- Both signed into iCloud with iCloud Drive enabled
**Result:** ❌ Same error with completely fresh installs
**Conclusion:** Not a caching issue

---

### Attempt 8: Wait Longer Before Entering Code
**Hypothesis:** Maybe 90 seconds on Device 1 isn't enough before Device 2 tries
**Implementation:**
- Device 1: Generate code, wait 90 seconds
- Manual wait: Additional 1-5 minutes before testing Device 2
- Device 2: Enter code
**Result:** ❌ Still "share not found" even after 5+ minutes
**Conclusion:** Time between generation and acceptance doesn't help

---

## 🤔 Root Cause Analysis

### What We Know For Certain

1. **Share IS Created Locally**
   - Core Data has the share record
   - `share.url` is valid and non-nil
   - `share.recordID` exists
   - Console confirms creation

2. **Code System Works Perfectly**
   - Code generation: ✅
   - Code storage in Public DB: ✅
   - Code lookup: ✅
   - URL retrieval: ✅

3. **Share Does NOT Exist in CloudKit (from Device 2's perspective)**
   - CloudKit returns `notFound` error
   - This is a server-side error, not client-side
   - Error is consistent across different API methods

4. **Share May Never Propagate**
   - Even after 5+ minutes, metadata fetch fails
   - Suggests share isn't syncing to CloudKit servers at all
   - Or is syncing but not becoming publicly discoverable

### Possible Root Causes

#### Theory 1: NSPersistentCloudKitContainer Doesn't Support Public Shares
**Evidence:**
- Comments in original code said "Core Data + CloudKit ONLY supports participant-based sharing"
- Setting `publicPermission = .readOnly` may be ignored by NSPersistentCloudKitContainer
- Core Data might only create private shares that require explicit participant invitation

**If True, Would Mean:**
- 6-digit code approach fundamentally incompatible with Core Data sharing
- Must use UICloudSharingController to add participants by email/phone
- Would need different architecture entirely

**Counter-Evidence:**
- Share IS created with `publicPermission: 2` (readOnly) according to logs
- CloudKit should honor this setting

---

#### Theory 2: Share Exists But In Wrong Database Scope
**Evidence:**
- Share created in private database
- Metadata fetch might be looking in wrong place
- Public shares might need to be in shared database or public database

**If True, Would Mean:**
- Share is created but not discoverable via public URL
- Core Data's `.share()` method puts share in wrong location for public access

**Counter-Evidence:**
- Using standard Core Data sharing APIs
- Other apps (Notes, Reminders) work with same APIs

---

#### Theory 3: CloudKit Development vs Production Environment Mismatch
**Evidence:**
- Testing in development environment
- Shares might not propagate properly in dev
- Public database access might be restricted in dev

**If True, Would Mean:**
- Need to test in production CloudKit environment
- Might work once deployed to real users

**Counter-Evidence:**
- Code storage/retrieval in Public DB works (same environment)
- Development environment should work for testing

---

#### Theory 4: CloudKit Container Configuration Issue
**Evidence:**
- Container ID: `iCloud.Sofanauts.GrandparentMemories`
- Entitlements configured
- But might be missing some CloudKit Dashboard settings

**Possible Missing Configuration:**
- CloudKit sharing not enabled in Dashboard
- Record zones not properly configured
- Public database permissions not set
- Schema not deployed correctly

**If True, Would Mean:**
- Need to check CloudKit Dashboard settings
- May need to explicitly enable sharing features
- Schema deployment might be incomplete

---

#### Theory 5: Fragment Identifier in URL Causing Issues
**Evidence:**
- Share URLs include fragment: `#Jasmine_Smith's_Memories`
- Fragment identifiers might not be part of CloudKit's URL matching
- Metadata fetch might be stripping fragment before lookup

**Example:**
```
Full URL: https://www.icloud.com/share/036XNwyU92NHcF_DxNcJbjlMQ#Jasmine_Smith's_Memories
CloudKit lookups: https://www.icloud.com/share/036XNwyU92NHcF_DxNcJbjlMQ
```

**If True, Would Mean:**
- URL mismatch causing lookup failure
- Need to strip fragment before saving code
- Or ensure CloudKit preserves full URL

---

#### Theory 6: Metadata Simply Takes MUCH Longer Than 90 Seconds
**Evidence:**
- Expert said shares need time to "propagate to CloudKit servers"
- 90 seconds might be way too short
- Real-world timing could be 5-10 minutes or more

**If True, Would Mean:**
- Need MUCH longer wait times (5+ minutes)
- Should implement retry with very long delays
- Not practical for real user experience

**Counter-Evidence:**
- Tested with 5+ minute waits, still fails
- Would make feature unusable if true

---

## 🚨 Critical Blockers

### Blocker 1: Cannot Verify Share Exists in CloudKit
**Problem:** No way to confirm if share actually made it to CloudKit servers

**What We Need:**
- CloudKit Dashboard access to see if share records exist
- Ability to query shares programmatically
- Way to verify share is in correct database scope

---

### Blocker 2: Permission Settings May Be Ignored
**Problem:** `publicPermission = .readOnly` might not work with Core Data sharing

**What We Need:**
- Confirmation that NSPersistentCloudKitContainer supports public shares
- Documentation on correct way to create publicly accessible shares with Core Data
- Alternative approach if Core Data doesn't support this

---

### Blocker 3: No Error Recovery Possible
**Problem:** Once metadata fetch fails, no way to retry or recover

**What We Need:**
- Retry mechanism with exponential backoff
- User feedback showing share is "still propagating"
- Fallback mechanism if metadata never becomes available

---

### Blocker 4: Time-Lock vs. Public Access Conflict
**Problem:** Public shares (`.readOnly`) would break time-lock feature

**Context:**
- Grandparents want to lock memories until grandchild reaches certain age (18, 21, etc.)
- With public read access, grandchild can see ALL memories immediately
- Defeats core purpose of the app

**What We Need:**
- Filtered sharing (only share released memories)
- Separate entity for released vs. unreleased memories
- Or stick with participant-only sharing (but then codes won't work)

---

## 📊 Test Results Summary

### Total Tests Performed: ~15
### Success Rate: 0%
### Consistent Failure Point: CloudKit metadata fetch

| Test # | Share Creation | Code Generation | Code Lookup | Metadata Fetch | Result |
|--------|---------------|-----------------|-------------|----------------|---------|
| 1      | ✅             | ✅               | ✅           | ❌              | FAIL    |
| 2      | ✅             | ✅               | ✅           | ❌              | FAIL    |
| 3      | ✅             | ✅               | ✅           | ❌              | FAIL    |
| 4      | ✅             | ✅               | ✅           | ❌              | FAIL    |
| 5      | ✅             | ✅               | ✅           | ❌              | FAIL    |
| ...    | ✅             | ✅               | ✅           | ❌              | FAIL    |
| 15     | ✅             | ✅               | ✅           | ❌              | FAIL    |

**Pattern:** Everything works perfectly until the metadata fetch step, which fails 100% of the time.

---

## 💡 What External Expert Said

### Their Analysis
> "fetchShareMetadata is designed to work with the share URL recipient flow — specifically, it expects the URL to be opened/tapped by the recipient through the system (like via Universal Links or UICloudSharingController). When you just pass a URL string you stored in a public database, CloudKit doesn't treat Device 2 as a legitimate share recipient in the same way."

### Their Recommendation
**Option A: Use System Share Flow**
```swift
// On Device 2, when user enters code:
let shareURL = await ShareCodeManager.lookupShareURL(code: code)
await UIApplication.shared.open(shareURL)  // Let iOS handle it
```

**Problem:** We tried this, got "permission denied" error

**Option B: Filtered Entity Sharing**
- Create separate `CDReleasedMemory` entity
- Only share released memories
- Maintains time-lock security
- More complex implementation

### Their Key Insight
The 6-digit code approach is valid, but the way we're using it (manual metadata fetch) doesn't align with how CloudKit expects shares to be accessed. CloudKit wants shares to go through the system's Universal Link handling.

---

## 🎓 What We Learned

### Technical Insights

1. **NSPersistentCloudKitContainer Sharing Is Complex**
   - Requires dual-store architecture (private + shared)
   - Sync timing is unpredictable
   - May not support all CloudKit sharing features

2. **CloudKit Sharing Has Multiple Modes**
   - Participant-only (`.none`) - Requires explicit invitation
   - Public read (`.readOnly`) - Anyone with link can view
   - Public read-write (`.readWrite`) - Anyone can edit
   - Core Data might only support participant-only

3. **Public Database Works Reliably**
   - Code storage/retrieval is instant and reliable
   - No permission or propagation issues
   - The code system itself is solid

4. **Time Delays Don't Help**
   - Whether it's 45s, 90s, or 5+ minutes
   - If share isn't discoverable, waiting doesn't help
   - Suggests structural issue, not timing issue

### Architectural Insights

1. **6-Digit Codes Are Great UX**
   - Avoids iMessage bubble problem
   - Easy for users to communicate
   - Works perfectly for code generation/lookup

2. **But Incompatible With Current Approach**
   - CloudKit expects system-level share acceptance
   - Manual metadata fetch doesn't work
   - Mismatch between our pattern and CloudKit's expectations

3. **Time-Lock vs. Sharing Conflict**
   - Public shares break time-lock feature
   - Participant-only shares break code system
   - Fundamental architectural tension

---

## 🛠 Potential Solutions (Untested)

### Solution 1: Participant Invitation Via Code
**Approach:**
1. When grandchild enters code, also ask for their email/phone
2. Look up share URL from code
3. Programmatically add grandchild as participant using CKShare.addParticipant()
4. Then they can accept share

**Pros:**
- Maintains participant-only security
- Codes still work for identifying which share
- Time-lock feature preserved

**Cons:**
- Requires email/phone (not as simple as just code)
- Requires owner to be online when recipient enters code?
- More complex flow

**Unknowns:**
- Can participants be added programmatically?
- Does addParticipant() require owner's device to be online?
- Will this trigger proper metadata availability?

---

### Solution 2: Separate Released Memory Entity
**Approach:**
1. Create `CDReleasedMemory` entity
2. When releasing memory (date reached), copy to CDReleasedMemory
3. Share the CDReleasedMemory parent, not CDGrandchild
4. Use public read permission safely

**Pros:**
- Maintains time-lock security
- Public shares work (no participant invitation needed)
- Codes work as intended

**Cons:**
- Data duplication (memory exists in both entities)
- Complex sync logic for updates
- Migration headache if changing existing structure

**Implementation Effort:** High (2-3 days)

---

### Solution 3: Use UICloudSharingController + Codes
**Approach:**
1. Code identifies which share to accept
2. But use UICloudSharingController for actual acceptance
3. Show Apple's system UI

**Pros:**
- Uses supported Apple API
- Likely to work reliably
- Codes still avoid iMessage bubble

**Cons:**
- Less clean UX (shows Apple's UI)
- Might confuse elderly users
- Still requires participant invitation?

---

### Solution 4: CloudKit Public Database Only (No Core Data Sharing)
**Approach:**
1. Completely abandon Core Data sharing
2. Store ALL shared data in CloudKit Public Database
3. Implement own sharing logic
4. Core Data becomes local cache only

**Pros:**
- Full control over sharing logic
- Codes work perfectly (we already proved this)
- Can implement time-locks however we want
- No metadata fetch issues

**Cons:**
- Massive rewrite (1-2 weeks)
- Lose NSPersistentCloudKitContainer auto-sync
- More complex to maintain
- Public database has costs at scale?

---

### Solution 5: Wait for CloudKit (Much Longer)
**Approach:**
1. Tell user "Share is being created, this may take 5-10 minutes"
2. Implement retry logic with very long delays
3. Keep trying metadata fetch for 10+ minutes

**Pros:**
- Minimal code changes
- Might actually work if timing is the issue

**Cons:**
- Terrible UX (10 minute wait?)
- Still fails after 5+ minutes in our tests
- Not sustainable for production app

---

### Solution 6: Production Environment Testing
**Approach:**
1. Deploy CloudKit schema to production
2. Test with production container
3. Use TestFlight with real users

**Hypothesis:**
Maybe development environment has restrictions that production doesn't

**Pros:**
- Might just work in production
- Worth trying before major rewrites

**Cons:**
- Still fails after we've tried everything in dev
- Risky to assume production is different
- Can't easily debug in production

---

## 📞 Questions For Apple / CloudKit Experts

1. **Does NSPersistentCloudKitContainer support public share permissions?**
   - Or is it limited to participant-only sharing?
   - Documentation is unclear on this

2. **How long does CloudKit share propagation actually take?**
   - Is 90 seconds realistic?
   - What's the maximum time we should wait?

3. **Is there a way to verify a share exists in CloudKit?**
   - Dashboard query?
   - Programmatic check?
   - Debugging tools?

4. **Why does metadata fetch consistently fail immediately?**
   - Does the share exist in CloudKit at all?
   - Is it in the wrong database scope?
   - Is there a configuration issue?

5. **Can we programmatically add participants to a share?**
   - Using CKShare.addParticipant()?
   - Without requiring UICloudSharingController?
   - While recipient is offline?

6. **What's the proper way to do code-based sharing with CloudKit?**
   - Is our architecture fundamentally wrong?
   - What pattern should we use?
   - Examples from Apple apps?

---

## 🎯 Recommended Next Steps

### Immediate (To Unblock)

1. **Check CloudKit Dashboard**
   - Login to https://icloud.developer.apple.com/dashboard
   - Verify container exists and is configured
   - Look for any share records
   - Check if sharing is enabled
   - Verify schema deployment

2. **Test Without Core Data**
   - Create a pure CloudKit share (no Core Data)
   - See if metadata fetch works
   - Isolate whether Core Data is the issue

3. **Contact Apple Developer Support**
   - Submit Technical Support Incident (TSI)
   - Include: error logs, code samples, CloudKit container ID
   - Ask specifically about Core Data + public share permission

### Short Term (If Dashboard/Support Reveals Issue)

4. **Implement Based on Findings**
   - If configuration issue: fix it
   - If Core Data limitation: switch to Solution 1, 2, or 4
   - If timing issue: implement Solution 5 with very long retries

### Long Term (For Production)

5. **Redesign Architecture**
   - Based on what we learn from Apple
   - Choose solution that balances UX, security, and reliability
   - Implement time-lock security properly
   - Test thoroughly before launch

---

## 💰 Cost Analysis (If This Never Works)

### Time Invested
- Implementation: ~8 hours
- Testing: ~4 hours
- Debugging: ~6 hours
- **Total: ~18 hours**

### Alternative Approaches
If CloudKit sharing won't work:

**Option 1: Firebase Realtime Database**
- Cost: $25-200/month depending on usage
- 30-year cost: $9,000 - $72,000
- Implementation: 2-3 weeks

**Option 2: Custom Backend (AWS/Heroku)**
- Cost: $20-100/month
- 30-year cost: $7,200 - $36,000
- Implementation: 3-4 weeks
- Maintenance: Ongoing

**Option 3: No Sharing Feature**
- Cost: $0
- Impact: Major feature missing
- Alternative: Each grandparent creates their own separate vaults

---

## 🎓 Conclusion

We have successfully implemented:
- ✅ Dual-store Core Data + CloudKit architecture
- ✅ 6-digit code generation system
- ✅ Code storage in CloudKit Public Database
- ✅ Share creation with Core Data
- ✅ Clean UI for code entry

We have NOT successfully implemented:
- ❌ Share metadata fetch from CloudKit
- ❌ Grandchild receiving shared data
- ❌ End-to-end sharing flow

**The blocker is consistent and 100% reproducible:** CloudKit returns "share not found" when trying to fetch metadata, even though the share was just created and we waited 90+ seconds.

**This suggests one of the following:**
1. NSPersistentCloudKitContainer doesn't support public shares (architectural limitation)
2. Share isn't actually syncing to CloudKit servers (configuration issue)
3. We're using the wrong API pattern (implementation issue)
4. CloudKit development environment has restrictions (environment issue)

**Without Apple's guidance or more debugging tools, we cannot determine which is true.**

---

**Files Affected:**
- CoreData/CoreDataStack.swift
- Core/ShareCodeManager.swift
- Views/SimpleShareView.swift
- Views/AcceptShareView.swift
- SceneDelegate.swift
- GrandparentMemoriesApp.swift
- Info.plist
- GrandparentMemories.entitlements

**Test Devices:**
- Device 1: iPhone (00008110-000964410EE3A01E)
- Device 2: Tony's 17 ProMax (00008150-001805311E08401C)

**CloudKit Container:** `iCloud.Sofanauts.GrandparentMemories`

**Ready for escalation to Apple Developer Support.**
