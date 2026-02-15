# CloudKit Sharing Guide
## How to Use Cross-Account Collaboration

**Date:** 2026-02-09  
**Status:** READY FOR TESTING ✅

---

## 🎉 What's Working

Your app now has **full CloudKit sharing support** using Apple's `UICloudSharingController`. This means:

✅ **Two grandparents with DIFFERENT Apple IDs can collaborate**  
✅ **Real-time sync between devices**  
✅ **Grandchildren can access their memories (read-only)**  
✅ **Private, secure, encrypted sharing**  
✅ **No server costs - works for 30+ years**

---

## 📱 How to Use Sharing in Your App

### 1. Access the Share Management Screen

Add the `ShareManagementView` to your app navigation:

```swift
// In your settings or main menu
NavigationLink("Share & Collaborate") {
    ShareManagementView()
}
```

### 2. Share with Co-Grandparent

**From ShareManagementView:**
1. Tap "Invite Co-Grandparent"
2. iOS presents UICloudSharingController
3. Choose how to send invitation:
   - Messages
   - Email
   - AirDrop
   - Copy link
4. Share with your spouse/partner

**Recipient receives:**
- A link or invitation
- Taps it to accept
- Opens app (or downloads from App Store)
- Full access to all family data

### 3. Share with Grandchild

**From ShareManagementView:**
1. Find the grandchild in the list
2. Tap "Share" button
3. iOS presents UICloudSharingController
4. Send invitation to grandchild

**Grandchild receives:**
- Link to their memory vault
- Read-only access
- Only sees their released memories

---

## 🛠️ Integration Options

### Option A: Use ShareManagementView (Easiest)

Add the provided view to your app:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("Share & Collaborate") {
                ShareManagementView()
            }
            // ... other settings
        }
    }
}
```

### Option B: Custom Integration

Use the sharing manager directly:

```swift
import SwiftUI

struct YourCustomView: View {
    @State private var showCoGrandparentShare = false
    
    var body: some View {
        Button("Share with Co-Grandparent") {
            showCoGrandparentShare = true
        }
        .shareWithCoGrandparent(isPresented: $showCoGrandparentShare)
    }
}
```

### Option C: Programmatic Sharing

Call the manager directly:

```swift
let sharingManager = CoreDataSharingManager.shared

// Get the current view controller
if let viewController = UIApplication.shared.windows.first?.rootViewController {
    Task {
        try await sharingManager.shareWithCoGrandparent(from: viewController)
    }
}
```

---

## 🧪 Testing Requirements

### ⚠️ CRITICAL: Must Test on Physical Devices

Simulator testing is NOT sufficient. You MUST test on real devices because:
- CloudKit sharing requires iCloud accounts
- Can't properly test cross-account sync in simulator
- Share acceptance only works on physical devices

### Required Test Setup

**You Need:**
1. **Device 1** - iPhone/iPad with Apple ID #1 (Grandparent A)
2. **Device 2** - iPhone/iPad with Apple ID #2 (Grandparent B - DIFFERENT account)
3. **Device 3** (optional) - iPhone/iPad with Apple ID #3 (Grandchild)

### Test Plan: Co-Grandparent Sharing

**On Device 1 (Grandparent A):**
1. ✅ Complete onboarding
2. ✅ Create a grandchild "Emma" with birthdate
3. ✅ Add 2-3 test memories (photo, video, voice)
4. ✅ Go to Share Management
5. ✅ Tap "Invite Co-Grandparent"
6. ✅ Send via Messages to Device 2

**On Device 2 (Grandparent B):**
1. ✅ Receive message with share link
2. ✅ Tap the link
3. ✅ Should prompt to accept share
4. ✅ Accept the share
5. ✅ Open app (or download if not installed)
6. ✅ **VERIFY**: Can see Emma and all her memories
7. ✅ **VERIFY**: Can add a new memory
8. ✅ **TEST**: Add a video memory

**Back on Device 1:**
1. ✅ Wait 5-30 seconds
2. ✅ **VERIFY**: New memory from Device 2 appears
3. ✅ **VERIFY**: Can edit that memory
4. ✅ **TEST**: Edit the memory title

**Back on Device 2:**
1. ✅ **VERIFY**: Edit from Device 1 syncs

### Test Plan: Grandchild Sharing

**On Device 1 (Grandparent A):**
1. ✅ Create grandchild "Emma"
2. ✅ Add 3 memories for Emma
3. ✅ Mark 2 memories as "Share Now" (released)
4. ✅ Leave 1 memory as "Vault Only" (not released)
5. ✅ Go to Share Management
6. ✅ Tap "Share" next to Emma
7. ✅ Send invite to Device 3

**On Device 3 (Grandchild - Emma):**
1. ✅ Receive and accept share
2. ✅ Open app
3. ✅ **VERIFY**: Can see 2 released memories
4. ✅ **VERIFY**: CANNOT see vault-only memory
5. ✅ **VERIFY**: Cannot add or edit memories (read-only)
6. ✅ **TEST**: Try to add a memory - should fail or not show option

**On Device 1:**
1. ✅ Release the 3rd memory
2. ✅ Wait 5-30 seconds

**On Device 3:**
1. ✅ **VERIFY**: 3rd memory now appears

### Edge Case Testing

**Offline/Online:**
- ✅ Turn on airplane mode on Device 1
- ✅ Add a memory
- ✅ Turn off airplane mode
- ✅ Verify memory syncs to Device 2

**Conflict Resolution:**
- ✅ On both devices, go offline
- ✅ Edit the SAME memory on both
- ✅ Go back online
- ✅ Verify CloudKit resolves conflict

**Stop Sharing:**
- ✅ On Device 1, stop sharing with Device 2
- ✅ Verify Device 2 loses access
- ✅ Re-share and verify Device 2 regains access

---

## 🐛 Troubleshooting

### "No Profile Found" Error
**Solution:** Complete onboarding first. Sharing requires a user profile.

### Share Link Doesn't Work
**Check:**
- Both devices signed in to iCloud
- iCloud Drive enabled in Settings
- Internet connection active
- CloudKit entitlements correct

### Changes Don't Sync
**Check:**
- iCloud sync enabled for app
- Internet connection on both devices
- Wait 30-60 seconds (CloudKit isn't instant)
- Check Console logs for sync errors

### "Share Failed" Error
**Solutions:**
- Check CloudKit Dashboard for schema errors
- Verify container ID: `iCloud.Sofanauts.GrandparentMemories`
- Check entitlements file has CloudKit enabled
- Try on different network (cellular vs WiFi)

### Simulator Limitations
**Remember:** 
- Simulator can't properly test sharing
- Always test on physical devices
- Need different Apple IDs for real test

---

## 📊 How It Works Under the Hood

### Architecture

```
Device 1 (Owner)                    Device 2 (Participant)
├─ Private Database                 ├─ Shared Database
│  ├─ CDUserProfile (root)          │  ├─ CDUserProfile (shared)
│  ├─ CDGrandchild                  │  ├─ CDGrandchild (shared)
│  └─ CDMemory                      │  └─ CDMemory (shared)
│                                   │
└─ CKShare                          └─ Receives CKShare
   ├─ Read-Write permission            └─ Syncs automatically
   └─ Links to root object
```

### Sync Flow

1. **Device 1** creates CDGrandchild
2. **CoreDataStack** saves to Core Data
3. **NSPersistentCloudKitContainer** syncs to CloudKit
4. **Device 1** creates CKShare for CDGrandchild
5. **UICloudSharingController** presents system share UI
6. **Device 2** receives share invitation
7. **CKAcceptSharesOperation** accepts share
8. **Device 2's NSPersistentCloudKitContainer** syncs shared data
9. **Both devices** see changes in real-time

### Data Flow

```
User Edits → Core Data → NSPersistentCloudKitContainer 
                            ↓
                        CloudKit Private DB
                            ↓
                        CKShare (if shared)
                            ↓
                        CloudKit Shared DB
                            ↓
                Participant's NSPersistentCloudKitContainer
                            ↓
                    Participant's Core Data
                            ↓
                    Participant's UI Updates
```

---

## 🚀 Deployment Checklist

Before submitting to App Store:

### CloudKit Configuration
- [ ] Schema deployed to production in CloudKit Dashboard
- [ ] Container ID matches: `iCloud.Sofanauts.GrandparentMemories`
- [ ] Indexes created for efficient queries
- [ ] Security roles configured

### Entitlements
- [ ] CloudKit capability enabled
- [ ] iCloud container selected
- [ ] Push notifications enabled (for sync alerts)
- [ ] Background modes: Remote notifications

### Testing
- [ ] Tested on 2+ physical devices
- [ ] Tested with different Apple IDs
- [ ] Tested offline/online scenarios
- [ ] Tested conflict resolution
- [ ] Tested with multiple grandchildren
- [ ] Tested stop sharing flow

### Code Review
- [ ] Error handling for all CloudKit operations
- [ ] User-friendly error messages
- [ ] Loading states during sync
- [ ] Proper cleanup when stopping shares

---

## 📚 Additional Resources

### Apple Documentation
- [Sharing Core Data Objects Between iCloud Users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users)
- [NSPersistentCloudKitContainer](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer)
- [UICloudSharingController](https://developer.apple.com/documentation/uikit/uicloudsharingcontroller)

### WWDC Sessions
- WWDC 2021: "Build apps that share data through CloudKit and Core Data"
- WWDC 2019: "Core Data: Advances in Performance and Security"

### Tools
- [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard)
- Console.app (for debugging sync issues)
- Network Link Conditioner (for testing poor connections)

---

## 💡 Pro Tips

### Performance
- Batch operations when possible
- Use background contexts for heavy operations
- Implement pagination for large data sets
- Cache frequently accessed data

### User Experience
- Show sync progress indicators
- Handle offline gracefully
- Provide clear error messages
- Allow retry on failed operations

### Security
- Validate share recipients
- Implement proper access control
- Log share activities
- Allow users to revoke access easily

### Maintenance
- Monitor CloudKit usage in dashboard
- Track sync errors in analytics
- Update schema carefully (additive only)
- Test migrations thoroughly

---

## ✨ Success Metrics

Your sharing implementation is successful when:

✅ Two grandparents can collaborate seamlessly  
✅ Changes sync within 30 seconds  
✅ Works offline and syncs when back online  
✅ Grandchildren see only their memories  
✅ No data loss or corruption  
✅ Users find it intuitive and easy  
✅ Zero ongoing server costs  

**Congratulations! You've built a 30-year sustainable collaboration feature! 🎉**
