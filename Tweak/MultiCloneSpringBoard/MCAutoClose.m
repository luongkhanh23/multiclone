#import "MCAutoClose.h"
#import "../../Source/MultiCloneCore/MCConstants.h"
#import "../../Source/MultiCloneCore/MCPrivateAPIBridge.h"
#import "../../Source/Logger/MCLogger.h"
#import <CoreFoundation/CoreFoundation.h>

// Keep v0.3 exported alias intact
NSString * const MCAutoClosePreferencesDomain = @"com.multiclone.manager";

static NSDictionary<NSString *, id> *MCReadDualLayerIPCPreferences(void) {
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];

    // Layer 1: Atomic IPC snapshot plist (immune to cross-process cfprefsd caching lag)
    NSDictionary *fileState = [NSDictionary dictionaryWithContentsOfFile:MCIPCStateFilePath()];
    if ([fileState isKindOfClass:[NSDictionary class]]) {
        [merged addEntriesFromDictionary:fileState];
    }

    // Layer 2: CFPreferences / NSUserDefaults suite (v0.3 compatible)
    CFPreferencesAppSynchronize((__bridge CFStringRef)MCAutoClosePreferencesDomain);
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MCAutoClosePreferencesDomain];
    [defaults synchronize];
    NSDictionary *defaultsRep = defaults.dictionaryRepresentation;
    if ([defaultsRep isKindOfClass:[NSDictionary class]]) {
        NSArray<NSString *> *keys = @[
            MCPrefKeyAutoCloseEnabled, MCPrefKeyAutoCloseOnlyManaged,
            MCPrefKeyManagedBundleIDs, MCPrefKeyPendingBundleID, MCPrefKeyLastManagedBundleID
        ];
        for (NSString *k in keys) {
            if (merged[k] == nil && defaultsRep[k] != nil) {
                merged[k] = defaultsRep[k];
            }
        }
    }
    return [merged copy];
}

static void MCWriteSpringBoardIPCUpdates(NSDictionary<NSString *, id> *updates, NSArray<NSString *> *keysToRemove) {
    @try {
        // Update atomic IPC plist
        NSMutableDictionary *fileState = [[NSDictionary dictionaryWithContentsOfFile:MCIPCStateFilePath()] mutableCopy]
            ?: [NSMutableDictionary dictionary];
        for (NSString *k in updates) {
            fileState[k] = updates[k];
        }
        for (NSString *k in keysToRemove) {
            [fileState removeObjectForKey:k];
        }
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:fileState
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                                      options:0
                                                                        error:nil];
        if (plistData) {
            [plistData writeToFile:MCIPCStateFilePath() options:NSDataWritingAtomic error:nil];
        }

        // Mirror to CFPreferences / NSUserDefaults
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:MCAutoClosePreferencesDomain];
        for (NSString *k in updates) {
            [defaults setObject:updates[k] forKey:k];
            CFPreferencesSetAppValue((__bridge CFStringRef)k,
                                     (__bridge CFPropertyListRef)updates[k],
                                     (__bridge CFStringRef)MCAutoClosePreferencesDomain);
        }
        for (NSString *k in keysToRemove) {
            [defaults removeObjectForKey:k];
            CFPreferencesSetAppValue((__bridge CFStringRef)k, NULL, (__bridge CFStringRef)MCAutoClosePreferencesDomain);
        }
        CFPreferencesAppSynchronize((__bridge CFStringRef)MCAutoClosePreferencesDomain);
        [defaults synchronize];
    } @catch (NSException *ex) {
        NSLog(@"[MultiClone] Failed writing SpringBoard IPC state: %@", ex.reason);
    }
}

static void MCPostResultAck(NSString *statusCode, NSString * _Nullable errorMessage, NSString * _Nullable newLastManaged) {
    NSMutableDictionary *updates = [@{
        MCPrefKeyLastActionStatus: statusCode ?: @"unknown",
        MCPrefKeyLastActionTimestamp: @([[NSDate date] timeIntervalSince1970])
    } mutableCopy];
    NSMutableArray *removals = [NSMutableArray arrayWithObject:MCPrefKeyPendingBundleID];

    if (errorMessage.length > 0) {
        updates[MCPrefKeyLastActionError] = errorMessage;
    } else {
        [removals addObject:MCPrefKeyLastActionError];
    }
    if (newLastManaged.length > 0) {
        updates[MCPrefKeyLastManagedBundleID] = newLastManaged;
    }

    MCWriteSpringBoardIPCUpdates(updates, removals);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)MCAutoCloseResultNotification,
                                         NULL, NULL, true);
}

static void MCHandleOpenRequest(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MCHandleOpenRequest();
        });
        return;
    }

    @autoreleasepool {
        @try {
            NSDictionary *prefs = MCReadDualLayerIPCPreferences();
            NSString *target = [prefs[MCPrefKeyPendingBundleID] isKindOfClass:[NSString class]] ? prefs[MCPrefKeyPendingBundleID] : nil;
            NSArray *managedArray = [prefs[MCPrefKeyManagedBundleIDs] isKindOfClass:[NSArray class]] ? prefs[MCPrefKeyManagedBundleIDs] : @[];
            NSSet<NSString *> *managedIDs = [NSSet setWithArray:managedArray];

            if (!MCIsValidBundleIdentifier(target) || MCIsProtectedBundleIdentifier(target)) {
                MCPostResultAck(@"rejected_protected", @"Target Bundle ID không hợp lệ hoặc được bảo vệ.", nil);
                return;
            }
            if (![managedIDs containsObject:target]) {
                MCPostResultAck(@"rejected_unmanaged", @"Target Bundle ID không nằm trong danh sách MultiClone.", nil);
                return;
            }

            BOOL enabled = [prefs[MCPrefKeyAutoCloseEnabled] respondsToSelector:@selector(boolValue)]
                ? [prefs[MCPrefKeyAutoCloseEnabled] boolValue] : NO;
            // Strict policy: default YES; never terminate non-managed or system apps
            BOOL onlyManaged = [prefs[MCPrefKeyAutoCloseOnlyManaged] respondsToSelector:@selector(boolValue)]
                ? [prefs[MCPrefKeyAutoCloseOnlyManaged] boolValue] : YES;
            NSString *previous = [prefs[MCPrefKeyLastManagedBundleID] isKindOfClass:[NSString class]]
                ? prefs[MCPrefKeyLastManagedBundleID] : nil;

            BOOL closedPrevious = NO;
            NSError *termError = nil;

            if (enabled &&
                previous.length > 0 &&
                ![previous isEqualToString:target] &&
                !MCIsProtectedBundleIdentifier(previous) &&
                (!onlyManaged || [managedIDs containsObject:previous])) {
                // Double safety check: only terminate if explicitly managed by MultiClone
                if ([managedIDs containsObject:previous]) {
                    closedPrevious = [MCPrivateAPIBridge terminateApplicationWithBundleID:previous
                                                                                   reason:@"MultiClone auto-close previous managed app"
                                                                                    error:&termError];
                    if (!closedPrevious) {
                        [[MCLogger sharedLogger] warn:@"SpringBoard" format:@"Failed closing previous managed app %@: %@",
                            previous, termError.localizedDescription ?: @"unknown"];
                    } else {
                        [[MCLogger sharedLogger] info:@"SpringBoard" format:@"Auto-closed previous managed app %@", previous];
                    }
                }
            }

            NSError *openError = nil;
            BOOL opened = [MCPrivateAPIBridge openApplicationWithBundleID:target error:&openError];
            if (opened) {
                if (termError) {
                    MCPostResultAck(@"terminate_failed_opened_target",
                                    [NSString stringWithFormat:@"Đã mở %@ nhưng không thể đóng bản trước (%@): %@",
                                     target, previous ?: @"", termError.localizedDescription],
                                    target);
                } else {
                    MCPostResultAck(closedPrevious ? @"ok_closed_and_opened" : @"ok_opened_only", nil, target);
                }
            } else {
                [[MCLogger sharedLogger] error:@"SpringBoard" format:@"Failed opening target %@: %@",
                    target, openError.localizedDescription ?: @"unknown"];
                MCPostResultAck(@"open_failed", openError.localizedDescription ?: @"Không thể khởi chạy ứng dụng đích.", nil);
            }
        } @catch (NSException *ex) {
            NSLog(@"[MultiClone] Caught unexpected exception in MCHandleOpenRequest: %@", ex.reason);
            MCPostResultAck(@"exception_recovered", ex.reason ?: @"SpringBoard handler recovered from exception.", nil);
        }
    }
}

static void MCHandlePingRequest(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try {
                MCWriteSpringBoardIPCUpdates(@{
                    MCPrefKeySpringBoardHeartbeat: @([[NSDate date] timeIntervalSince1970])
                }, @[]);
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                     (__bridge CFStringRef)MCSpringBoardPongNotification,
                                                     NULL, NULL, true);
            } @catch (NSException *ex) {
                NSLog(@"[MultiClone] Ping handler exception: %@", ex.reason);
            }
        }
    });
}

static void MCDarwinOpenCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    MCHandleOpenRequest();
}

static void MCDarwinPingCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    MCHandlePingRequest();
}

void MCInstallAutoCloseObserver(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(darwin, NULL, MCDarwinOpenCallback,
                                        (__bridge CFStringRef)MCAutoCloseRequestNotification,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MCDarwinPingCallback,
                                        (__bridge CFStringRef)MCSpringBoardPingNotification,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}
