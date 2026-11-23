#import "MCAutoCloseClient.h"
#import "../MultiCloneCore/MCConstants.h"
#import "../MultiCloneCore/MCPrivateAPIBridge.h"
#import "../Settings/MCSettingsManager.h"
#import "../DataManager/MCDataManager.h"
#import "../Logger/MCLogger.h"
#import <CoreFoundation/CoreFoundation.h>

@implementation MCAutoCloseActionResult
@end

BOOL MCRequestOpenManagedBundle(NSString *bundleID) {
    if (!MCIsValidBundleIdentifier(bundleID) || MCIsProtectedBundleIdentifier(bundleID)) {
        return NO;
    }
    MCSettingsManager *settings = [MCSettingsManager sharedManager];
    if (![settings isManagedBundleID:bundleID]) {
        return NO;
    }
    if (![settings synchronizeIPCStateWithPendingBundleID:bundleID]) {
        return NO;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)MCAutoCloseRequestNotification,
                                         NULL, NULL, true);
    return YES;
}

@interface MCAutoCloseClient ()
@property (nonatomic, copy, nullable) void (^pendingOpenCompletion)(MCAutoCloseActionResult *result);
@property (nonatomic, copy, nullable) NSString *pendingTargetBundleID;
@property (nonatomic, copy, nullable) void (^pendingPingCompletion)(BOOL reachable, NSString *detail);
@property (nonatomic, assign) BOOL observersInstalled;
- (void)mc_handleSpringBoardResultNotification;
- (void)mc_handleSpringBoardPongNotification;
@end

static void MCClientResultCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)name; (void)object; (void)userInfo;
    MCAutoCloseClient *client = (__bridge MCAutoCloseClient *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [client mc_handleSpringBoardResultNotification];
    });
}

static void MCClientPongCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)name; (void)object; (void)userInfo;
    MCAutoCloseClient *client = (__bridge MCAutoCloseClient *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [client mc_handleSpringBoardPongNotification];
    });
}

@implementation MCAutoCloseClient

+ (instancetype)sharedClient {
    static MCAutoCloseClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MCAutoCloseClient alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self mc_installObservers];
    }
    return self;
}

- (void)mc_installObservers {
    if (self.observersInstalled) return;
    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwin, (__bridge const void *)self, MCClientResultCallback,
                                    (__bridge CFStringRef)MCAutoCloseResultNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwin, (__bridge const void *)self, MCClientPongCallback,
                                    (__bridge CFStringRef)MCSpringBoardPongNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    self.observersInstalled = YES;
}

- (BOOL)shouldPromptConfirmationForLaunchingBundleID:(NSString *)targetBundleID
                                  previousBundleOut:(NSString * _Nullable * _Nullable)previousBundleOut {
    MCSettingsManager *settings = [MCSettingsManager sharedManager];
    if (!settings.autoCloseEnabled) return NO;

    NSString *previous = settings.lastManagedBundleID;
    if (previous.length == 0 ||
        [previous isEqualToString:targetBundleID] ||
        MCIsProtectedBundleIdentifier(previous) ||
        ![settings isManagedBundleID:previous]) {
        return NO;
    }

    if (previousBundleOut) *previousBundleOut = previous;

    if (settings.launchBehavior == MCLaunchBehaviorOpenOnly) {
        return NO;
    }
    if (settings.launchBehavior == MCLaunchBehaviorAskEveryTime) {
        return YES;
    }
    return settings.confirmBeforeAutoClose;
}

- (void)openManagedBundleID:(NSString *)bundleID
        allowAutoClosePrev:(BOOL)allowAutoClosePrev
                 completion:(void (^ _Nullable)(MCAutoCloseActionResult *result))completion {
    MCAutoCloseActionResult *quickResult = [[MCAutoCloseActionResult alloc] init];

    if (!MCIsValidBundleIdentifier(bundleID) || MCIsProtectedBundleIdentifier(bundleID)) {
        quickResult.succeeded = NO;
        quickResult.statusCode = @"rejected_protected";
        quickResult.errorMessage = @"Không thể mở Bundle ID không hợp lệ hoặc thuộc hệ thống.";
        if (completion) completion(quickResult);
        return;
    }

    MCSettingsManager *settings = [MCSettingsManager sharedManager];
    if (![settings isManagedBundleID:bundleID]) {
        quickResult.succeeded = NO;
        quickResult.statusCode = @"rejected_unmanaged";
        quickResult.errorMessage = @"Ứng dụng này chưa được đăng ký trong danh sách MultiClone.";
        if (completion) completion(quickResult);
        return;
    }

    // Temporarily reflect per-launch decision without permanently altering user setting
    BOOL originalAutoClose = settings.autoCloseEnabled;
    BOOL effectiveAutoClose = originalAutoClose && allowAutoClosePrev && (settings.launchBehavior != MCLaunchBehaviorOpenOnly);

    if (!effectiveAutoClose) {
        // Direct launch without closing previous app
        NSError *openErr = nil;
        BOOL opened = [MCPrivateAPIBridge openApplicationWithBundleID:bundleID error:&openErr];
        quickResult.succeeded = opened;
        quickResult.usedSpringBoardIPC = NO;
        quickResult.previousAppClosed = NO;
        quickResult.statusCode = opened ? @"opened_direct" : @"open_failed";
        quickResult.errorMessage = openErr.localizedDescription;
        if (opened) {
            settings.lastManagedBundleID = bundleID;
            [[MCDataManager sharedManager] markCloneOpened:bundleID];
        }
        [[MCLogger sharedLogger] info:@"AutoCloseClient" format:@"Direct open %@ -> %@", bundleID, quickResult.statusCode];
        if (completion) completion(quickResult);
        return;
    }

    // Dispatch via SpringBoard Darwin IPC with timeout + safe fallback
    self.pendingTargetBundleID = bundleID;
    self.pendingOpenCompletion = completion;

    BOOL sent = MCRequestOpenManagedBundle(bundleID);
    if (!sent) {
        self.pendingOpenCompletion = nil;
        self.pendingTargetBundleID = nil;
        NSError *openErr = nil;
        BOOL opened = [MCPrivateAPIBridge openApplicationWithBundleID:bundleID error:&openErr];
        quickResult.succeeded = opened;
        quickResult.usedSpringBoardIPC = NO;
        quickResult.statusCode = opened ? @"ipc_write_failed_fallback_opened" : @"ipc_write_failed";
        quickResult.errorMessage = openErr.localizedDescription ?: @"Không ghi được trạng thái IPC.";
        if (completion) completion(quickResult);
        return;
    }

    // Timeout guard: if SpringBoard tweak does not acknowledge within 1.5s, fallback safely
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.pendingOpenCompletion || ![strongSelf.pendingTargetBundleID isEqualToString:bundleID]) {
            return;
        }
        void (^cb)(MCAutoCloseActionResult *) = strongSelf.pendingOpenCompletion;
        strongSelf.pendingOpenCompletion = nil;
        strongSelf.pendingTargetBundleID = nil;

        NSError *fallbackErr = nil;
        BOOL opened = [MCPrivateAPIBridge openApplicationWithBundleID:bundleID error:&fallbackErr];
        MCAutoCloseActionResult *res = [[MCAutoCloseActionResult alloc] init];
        res.succeeded = opened;
        res.usedSpringBoardIPC = NO;
        res.previousAppClosed = NO;
        res.statusCode = opened ? @"ipc_timeout_fallback_opened" : @"ipc_timeout_open_failed";
        res.errorMessage = opened
            ? @"Tweak SpringBoard không phản hồi kịp; đã mở ứng dụng bằng chế độ dự phòng (không đóng app cũ)."
            : (fallbackErr.localizedDescription ?: @"Tweak SpringBoard không phản hồi và không thể mở ứng dụng.");
        if (opened) {
            [[MCDataManager sharedManager] markCloneOpened:bundleID];
        }
        [[MCLogger sharedLogger] warn:@"AutoCloseClient" format:@"IPC timeout for %@ -> %@", bundleID, res.statusCode];
        cb(res);
    });
}

- (void)mc_handleSpringBoardResultNotification {
    if (!self.pendingOpenCompletion) return;
    void (^cb)(MCAutoCloseActionResult *) = self.pendingOpenCompletion;
    NSString *target = self.pendingTargetBundleID;
    self.pendingOpenCompletion = nil;
    self.pendingTargetBundleID = nil;

    NSDictionary *state = [[MCSettingsManager sharedManager] readSynchronizedIPCState];
    NSString *status = [state[MCPrefKeyLastActionStatus] isKindOfClass:[NSString class]] ? state[MCPrefKeyLastActionStatus] : @"unknown";
    NSString *errMsg = [state[MCPrefKeyLastActionError] isKindOfClass:[NSString class]] ? state[MCPrefKeyLastActionError] : nil;

    MCAutoCloseActionResult *res = [[MCAutoCloseActionResult alloc] init];
    res.usedSpringBoardIPC = YES;
    res.statusCode = status;
    res.errorMessage = errMsg;
    res.previousAppClosed = [status isEqualToString:@"ok_closed_and_opened"];
    res.succeeded = [status hasPrefix:@"ok"] || [status isEqualToString:@"terminate_failed_opened_target"];
    if (res.succeeded && target.length > 0) {
        [[MCDataManager sharedManager] markCloneOpened:target];
    }
    [[MCLogger sharedLogger] info:@"AutoCloseClient" format:@"SpringBoard IPC ack for %@: %@", target ?: @"", status];
    cb(res);
}

- (void)pingSpringBoardTweakWithTimeout:(NSTimeInterval)timeout
                             completion:(void (^)(BOOL reachable, NSString *detail))completion {
    self.pendingPingCompletion = completion;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)MCSpringBoardPingNotification,
                                         NULL, NULL, true);

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0.5, timeout) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.pendingPingCompletion) return;
        void (^cb)(BOOL, NSString *) = strongSelf.pendingPingCompletion;
        strongSelf.pendingPingCompletion = nil;
        cb(NO, @"Không nhận được phản hồi từ MultiCloneSpringBoard. Hãy đảm bảo tweak đã cài và đã respring.");
    });
}

- (void)mc_handleSpringBoardPongNotification {
    if (!self.pendingPingCompletion) return;
    void (^cb)(BOOL, NSString *) = self.pendingPingCompletion;
    self.pendingPingCompletion = nil;
    NSDictionary *state = [[MCSettingsManager sharedManager] readSynchronizedIPCState];
    NSNumber *hb = [state[MCPrefKeySpringBoardHeartbeat] isKindOfClass:[NSNumber class]] ? state[MCPrefKeySpringBoardHeartbeat] : nil;
    NSString *detail = hb
        ? [NSString stringWithFormat:@"MultiCloneSpringBoard đang hoạt động bình thường (v%@, heartbeat=%.0f).", MCProductVersion, hb.doubleValue]
        : [NSString stringWithFormat:@"MultiCloneSpringBoard đã phản hồi pong (v%@).", MCProductVersion];
    cb(YES, detail);
}

@end
