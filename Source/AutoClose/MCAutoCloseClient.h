#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Backward-compatible C helper from v0.3: writes pendingBundleID and posts Darwin notification
/// to SpringBoard's MultiClone AutoClose handler.
FOUNDATION_EXPORT BOOL MCRequestOpenManagedBundle(NSString *bundleID);

@interface MCAutoCloseActionResult : NSObject
@property (nonatomic, assign) BOOL succeeded;
@property (nonatomic, assign) BOOL usedSpringBoardIPC;
@property (nonatomic, assign) BOOL previousAppClosed;
@property (nonatomic, copy, nullable) NSString *closedBundleID;
@property (nonatomic, copy) NSString *statusCode;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@end

/// Client-side coordinator for Auto Close Previous App and SpringBoard IPC health verification.
@interface MCAutoCloseClient : NSObject

+ (instancetype)sharedClient;

/// Returns YES if a confirmation alert should be presented before closing the previous managed app.
- (BOOL)shouldPromptConfirmationForLaunchingBundleID:(NSString *)targetBundleID
                                  previousBundleOut:(NSString * _Nullable * _Nullable)previousBundleOut;

/// Requests opening a managed clone. Respects autoCloseEnabled, managed-only policy, and
/// falls back safely to direct launch if SpringBoard tweak IPC does not respond.
- (void)openManagedBundleID:(NSString *)bundleID
        allowAutoClosePrev:(BOOL)allowAutoClosePrev
                 completion:(void (^ _Nullable)(MCAutoCloseActionResult *result))completion;

/// Sends a Darwin ping to MultiCloneSpringBoard and checks for a pong heartbeat.
- (void)pingSpringBoardTweakWithTimeout:(NSTimeInterval)timeout
                             completion:(void (^)(BOOL reachable, NSString *detail))completion;

@end

NS_ASSUME_NONNULL_END
