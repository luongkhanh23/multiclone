#import <Foundation/Foundation.h>
#import "MCAutoClose.h"

// MultiCloneSpringBoard Tweak — Rootless iOS 18.2 / Dopamine 3.0.7+
// Loaded strictly in com.apple.springboard (enforced by MultiClone.plist + runtime check).
// Handles opt-in Auto Close Previous Managed App and IPC health checks safely.
%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if ([bundleID isEqualToString:@"com.apple.springboard"]) {
            MCInstallAutoCloseObserver();
            NSLog(@"[MultiClone] SpringBoard module v1.2.2 loaded (rootless); auto-close & health observers ready.");
        }
    }
}
