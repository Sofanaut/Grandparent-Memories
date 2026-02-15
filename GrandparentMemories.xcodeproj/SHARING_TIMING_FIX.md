# CloudKit Sharing "Share Not Found" Error - COMPLETE FIX

## Problem
When creating a share on one device and immediately trying to accept it on another device, users were getting a "share not found" error. This error appears BEFORE the app even opens - it's iOS system showing a preview of the share. This happened because CloudKit shares take time to propagate across Apple's infrastructure.

## Root Cause
1. The share is created in the owner's private CloudKit database
2. A ShareReference record is created in the public database with the 6-digit code
3. The ShareReference appears quickly, but the actual share takes longer to become accessible from other iCloud accounts
4. **The error happens BEFORE your app opens**: When someone taps a CloudKit share URL, iOS tries to show a preview of the share first
5. If the share hasn't propagated yet, iOS shows "share not found" error in its own UI (not your app's UI)
6. This is why the error shows system text and appears before the app even launches

## Solution Implemented

### 1. Increased Initial Wait Time (CloudKitSharingManager.swift:282-306)
- Changed from 5 seconds to 8 seconds before verifying share availability
- Added an additional 3-second buffer after successful verification
- Exponential backoff: 2s, 4s, 6s, 8s, etc. (up to 15 retries)

### 2. Automatic Retry on Accept Share (CloudKitSharingManager.swift:166-186)
- Modified `acceptShare()` to use `fetchShareMetadataWithRetry()`
- Added `fetchShareMetadataWithRetry()` method that automatically retries when encountering "share not found" errors
- Detects CKError with code `.unknownItem` (the specific error for share not found)
- Retries up to 5 times with 3-second intervals (3s, 6s, 9s, 12s, 15s)
- Total potential wait time: up to 45 seconds

### 3. Automatic Retry on Code Entry (CloudKitSharingManager.swift:229-258)
- Added `acceptShareWithRetry()` method for code-based sharing
- Same retry logic as URL-based sharing

### 4. Updated Share Messages (CloudKitSharingManager.swift:438-468)
- Added warning in share sheet: "IMPORTANT: Wait at least 1 minute after receiving this before tapping the link"
- Sets proper expectations for recipients

### 5. Better Error Handling in App (GrandparentMemoriesApp.swift:40-92)
- Updated `handleIncomingURL()` to use CloudKitSharingManager's retry logic
- Added error alert when share link is clicked too early
- Shows user-friendly error message with proper context

### 6. Better User Experience in AcceptShareView (AcceptShareView.swift:147-161)
- Added "Try Again" button in error alert
- Clear error message: "The share was just created and needs a moment to sync. Please wait 30 seconds and try entering the code again."

## How to Use Sharing Now

### For Grandparents (Creating the Share)
1. Tap "Share with Co-Grandparent" or "Share with Grandchild"
2. The app will create the share and show a share sheet
3. Send the message via text, email, or any messaging app
4. **CRITICAL**: Tell the recipient to wait at least 1 minute before tapping the link
5. The message now includes this warning automatically

### For Recipients (Accepting the Share via Link)
1. Receive the share message
2. **Wait at least 1 minute** (this is critical - don't tap immediately!)
3. Tap the share link
4. iOS may show a preview - if it fails, close it and try again
5. The app will open and automatically accept the share with retry logic
6. If you still get an error, wait another minute and try again

### For Recipients (Accepting via Code)
1. Open the app and tap "Accept Invitation"
2. Enter the 6-digit code
3. Tap "Connect"
4. The app will automatically retry if the share isn't ready yet
5. If you get an error, tap "Try Again"

## Technical Details

### Code Changes

**CloudKitSharingManager.swift**:
- `waitForShareToSync()`: Increased delays and added buffer time
- `acceptShareWithRetry()`: New method with automatic retry logic
- `SharingError.shareNotFoundAfterRetries`: New error case with helpful message

**AcceptShareView.swift**:
- Added "Try Again" button in error alert for easy retry

### Why This Works
CloudKit sharing involves multiple steps:
1. Share record created in private database
2. Share metadata synced to CloudKit servers
3. Share URL becomes accessible
4. Share propagates to other data centers
5. Share becomes queryable from other iCloud accounts

This process typically takes 10-30 seconds but can take up to 60 seconds in some cases. By waiting longer and retrying automatically, we handle the normal propagation delay.

## Testing
To test the fix:
1. Create a share on Device A
2. Wait 30 seconds
3. Accept the share on Device B using the code
4. Should connect successfully

If it still fails, wait another 30 seconds and try again - CloudKit can be slower on some network conditions.

## Future Improvements
- Add a countdown timer showing "Share will be ready in X seconds"
- Show a progress indicator during retry attempts
- Implement push notification to alert recipient when share is ready
