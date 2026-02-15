# Core Data Migration Status
## SwiftData → Core Data + CloudKit Sharing Migration

**Date:** 2026-02-09  
**Status:** Infrastructure Complete ✅ | Views Need Update 🔄

---

## ✅ Completed Infrastructure

### 1. Core Data Model Created
**File:** `GrandparentMemories/CoreData/GrandparentMemories.xcdatamodeld`

All 8 entities migrated from SwiftData:
- ✅ CDUserProfile
- ✅ CDContributor
- ✅ CDGrandchild
- ✅ CDMemory
- ✅ CDAncestor
- ✅ CDAncestorPhoto
- ✅ CDPetPhoto
- ✅ CDFamilyPet

**Key Changes:**
- All relationships are optional (CloudKit requirement)
- Enums stored as String values
- Binary data marked with `allowsExternalBinaryDataStorage`

### 2. Core Data Stack with CloudKit Sharing
**File:** `GrandparentMemories/CoreData/CoreDataStack.swift`

Features implemented:
- ✅ NSPersistentCloudKitContainer configuration
- ✅ CloudKit container: `iCloud.Sofanauts.GrandparentMemories`
- ✅ Automatic merge from parent
- ✅ Remote change notifications
- ✅ Sharing support methods:
  - `share(_ object:, title:)` - Creates CKShare for an object
  - `isShared(_ object:)` - Checks if object is shared
  - `fetchShare(for:)` - Gets CKShare for object
  - `stopSharing(_ object:)` - Removes sharing

### 3. Data Migration Utility
**File:** `GrandparentMemories/CoreData/SwiftDataMigration.swift`

Complete migration logic that:
- ✅ Reads all SwiftData entities
- ✅ Creates corresponding Core Data entities
- ✅ Preserves all relationships
- ✅ Maintains data integrity
- ✅ Handles enum conversions
- ✅ Runs in background context

Migration runs automatically on first launch after update.

### 4. SwiftUI Bridge Layer
**File:** `GrandparentMemories/CoreData/CoreDataBridge.swift`

Convenience features:
- ✅ Enum conversion extensions
- ✅ Array conversion helpers (NSSet → [Entity])
- ✅ FetchRequest builders for common queries
- ✅ NSManagedObjectContext creation helpers

### 5. Core Data Extensions
**File:** `GrandparentMemories/CoreData/CoreDataModels.swift`

Computed properties matching SwiftData interface:
- ✅ CDGrandchild: `age`, `ageDisplay`, `firstName`
- ✅ CDMemory: `formattedDate`, `displayTitle`
- ✅ CDAncestor: `yearsDisplay`, `primaryPhoto`
- ✅ CDFamilyPet: `yearsDisplay`, `primaryPhoto`
- ✅ CDContributor: `displayName`

### 6. App Initialization Updated
**File:** `GrandparentMemories/GrandparentMemoriesApp.swift`

Changes:
- ✅ Core Data stack initialization
- ✅ Automatic migration on first launch
- ✅ CloudKit share URL handling
- ✅ SwiftData container kept temporarily for migration
- ✅ Migration flag in UserDefaults

### 7. Build Configuration Fixed
- ✅ Info.plist conflict resolved
- ✅ Automatic Info.plist generation enabled
- ✅ Project builds successfully

---

## 🔄 Next Steps: View Layer Migration

The Core Data infrastructure is complete and building. Now we need to update the views to use Core Data instead of SwiftData.

### Views That Need Updating

#### High Priority (Core Functionality)
1. **ContentView** - Main hub, uses @Query
2. **TimelineView** - Displays memories
3. **VaultView** - Shows all memories
4. **GrandchildGiftView** - Grandchild's view of memories

#### Medium Priority (Features)
5. **ShareWithGrandchildView** - Sharing UI
6. **AcceptShareView** - Accept share UI
7. **GiftSchedulingView** - Schedule releases
8. **SettingsView** - User settings

#### Low Priority (Secondary Features)
9. **OnboardingFlow** - Setup wizard
10. **PaywallView** - Premium features
11. **FAQView** - Help content

### Migration Pattern for Each View

**Before (SwiftData):**
```swift
@Query private var grandchildren: [Grandchild]
@Environment(\.modelContext) private var modelContext

// Create new object
let grandchild = Grandchild(name: name, birthDate: date)
modelContext.insert(grandchild)
try? modelContext.save()
```

**After (Core Data):**
```swift
@FetchRequest(fetchRequest: FetchRequestBuilders.allGrandchildren())
private var grandchildren: FetchedResults<CDGrandchild>
@Environment(\.managedObjectContext) private var viewContext

// Create new object
let grandchild = viewContext.createGrandchild(name: name, birthDate: date)
viewContext.saveIfNeeded()
```

### Key Changes Needed

1. **Replace @Query with @FetchRequest**
   ```swift
   // Old
   @Query private var memories: [Memory]
   
   // New
   @FetchRequest(fetchRequest: FetchRequestBuilders.allMemories())
   private var memories: FetchedResults<CDMemory>
   ```

2. **Replace modelContext with managedObjectContext**
   ```swift
   // Old
   @Environment(\.modelContext) private var modelContext
   
   // New
   @Environment(\.managedObjectContext) private var viewContext
   ```

3. **Update Entity References**
   ```swift
   // Old
   Memory → CDMemory
   Grandchild → CDGrandchild
   Contributor → CDContributor
   etc.
   ```

4. **Update Enum Access**
   ```swift
   // Old
   memory.memoryType == .videoMessage
   
   // New  
   memory.memoryTypeEnum == .videoMessage
   ```

5. **Update Relationship Access**
   ```swift
   // Old
   grandchild.memories ?? []
   
   // New
   grandchild.memoriesArray  // Uses extension from CoreDataBridge
   ```

---

## 🎯 Critical: UICloudSharingController Implementation

After views are migrated, implement actual CloudKit sharing:

### For Co-Grandparent Sharing

```swift
import CloudKit
import UIKit

func shareWithCoGrandparent(grandchild: CDGrandchild) async throws {
    // Create share
    let (share, container) = try await CoreDataStack.shared.share(grandchild, title: "Family Memories")
    
    // Present UICloudSharingController
    let sharingController = UICloudSharingController { controller, preparationHandler in
        preparationHandler(share, container, nil)
    }
    
    // Present to user
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let viewController = scene.windows.first?.rootViewController {
        viewController.present(sharingController, animated: true)
    }
}
```

### For Grandchild Sharing

```swift
func shareWithGrandchild(_ grandchild: CDGrandchild) async throws {
    // Create filtered share (read-only, only released memories)
    let (share, container) = try await CoreDataStack.shared.share(grandchild, title: "\(grandchild.name ?? "Grandchild")'s Memories")
    
    // Configure as read-only
    share.publicPermission = .readOnly
    
    // Present sharing UI
    let sharingController = UICloudSharingController(share: share, container: container)
    // ... present
}
```

---

## 📋 Testing Checklist

Once views are migrated and UICloudSharingController is implemented:

### Two-Device Testing (CRITICAL)
- [ ] Device 1 (Grandparent A): Create grandchild and memories
- [ ] Device 1: Share with co-grandparent
- [ ] Device 2 (Grandparent B - DIFFERENT Apple ID): Accept share
- [ ] Device 2: Verify all data appears
- [ ] Device 2: Add a new memory
- [ ] Device 1: Verify new memory syncs
- [ ] Both devices: Verify edits sync both ways

### Grandchild Access Testing
- [ ] Create share for grandchild
- [ ] Device 3 (Grandchild - DIFFERENT Apple ID): Accept share
- [ ] Verify only released memories visible
- [ ] Verify read-only (can't edit)
- [ ] Release a new memory on Device 1
- [ ] Verify it appears on Device 3

### Edge Cases
- [ ] Offline mode (changes sync when back online)
- [ ] Conflict resolution (both edit same memory)
- [ ] Stop sharing (remove access)
- [ ] Multiple grandchildren
- [ ] Large videos (>100MB)

---

## 📊 Migration Progress

```
Infrastructure:  ████████████████████ 100% ✅
View Layer:      ░░░░░░░░░░░░░░░░░░░░   0% 🔄
Sharing UI:      ░░░░░░░░░░░░░░░░░░░░   0% 🔄
Testing:         ░░░░░░░░░░░░░░░░░░░░   0% ⏳
Overall:         █████░░░░░░░░░░░░░░░  25%
```

---

## 🚨 Important Notes

1. **Don't Delete SwiftData Models Yet**
   - Keep `Models.swift` until migration is verified
   - Users upgrading need to migrate their data
   - Can remove after confirming all users have updated

2. **CloudKit Schema is Additive Only**
   - Once deployed to production, you CAN'T remove fields
   - Test thoroughly in development environment first
   - Use CloudKit Dashboard to promote schema when ready

3. **Testing on Real Devices is MANDATORY**
   - Simulator doesn't accurately test CloudKit sharing
   - Need THREE actual devices with different Apple IDs:
     - Device 1: Grandparent A (owner)
     - Device 2: Grandparent B (collaborator) 
     - Device 3: Grandchild (read-only recipient)

4. **UserDefaults Migration Flag**
   - Key: `HasMigratedToCoreData`
   - Set to `true` after successful migration
   - Prevents re-running migration on every launch

---

## 🔗 Useful Resources

- **Apple Docs:** [Sharing Core Data Objects Between iCloud Users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users)
- **WWDC 2021:** [Build apps that share data through CloudKit and Core Data](https://developer.apple.com/videos/play/wwdc2021/10015/)
- **CloudKit Dashboard:** [icloud.developer.apple.com](https://icloud.developer.apple.com/dashboard)
- **Sample Code:** Search "CoreDataCloudKitShare" in Xcode

---

## 💡 Next Immediate Action

**Start with ContentView migration:**

1. Open `GrandparentMemories/ContentView/ContentView.swift`
2. Replace `@Query` with `@FetchRequest`
3. Replace `modelContext` with `managedObjectContext`
4. Update entity type references (Memory → CDMemory, etc.)
5. Test that the view still compiles and displays data
6. Repeat for other views

**Estimated time per view:** 15-30 minutes
**Total views to update:** ~10
**Total estimated time:** 3-5 hours

---

## ✨ What This Achieves

Once complete, this migration enables:

✅ **Co-grandparent collaboration** - Two grandparents with DIFFERENT iCloud accounts can share and edit the same family data  
✅ **Grandchild access** - Grandchildren can download the app and see only their released memories (read-only)  
✅ **30+ year reliability** - No server costs, fully Apple-supported  
✅ **Real-time sync** - Changes appear instantly on all devices  
✅ **Conflict resolution** - Automatic merge handling  
✅ **Offline support** - Works offline, syncs when connected  

**This is THE feature that makes the app unique and viable long-term.**
