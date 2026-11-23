#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MCLaunchBehavior) {
    MCLaunchBehaviorOpenOnly = 0,
    MCLaunchBehaviorAutoCloseThenOpen = 1,
    MCLaunchBehaviorAskEveryTime = 2
};

typedef NS_ENUM(NSInteger, MCThemeStyle) {
    MCThemeStyleMidnight = 0,
    MCThemeStylePureBlack = 1,
    MCThemeStyleSlate = 2
};

@interface MCSettingsManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) BOOL autoCloseEnabled;              // Default: NO
@property (nonatomic, assign) BOOL autoCloseOnlyManagedClones;    // Default: YES (always enforced for system apps)
@property (nonatomic, assign) BOOL confirmBeforeAutoClose;        // Default: YES
@property (nonatomic, assign) MCLaunchBehavior launchBehavior;    // Default: MCLaunchBehaviorAskEveryTime
@property (nonatomic, assign) MCThemeStyle themeStyle;            // Default: MCThemeStyleMidnight
@property (nonatomic, copy) NSString *accentColorHex;             // Default: @"#3B82F6"

@property (nonatomic, copy) NSArray<NSString *> *managedCloneBundleIDs;
@property (nonatomic, copy, nullable) NSString *lastManagedBundleID;

- (void)registerManagedBundleID:(NSString *)bundleID;
- (void)unregisterManagedBundleID:(NSString *)bundleID;
- (BOOL)isManagedBundleID:(NSString *)bundleID;

/// Writes synchronized snapshot to both CFPreferences and atomic IPC plist for SpringBoard.
- (BOOL)synchronizeIPCStateWithPendingBundleID:(nullable NSString *)pendingBundleID;
- (NSDictionary<NSString *, id> *)readSynchronizedIPCState;

/// Keychain-backed storage for sensitive strings (never persisted in plaintext plists).
- (BOOL)storeSecureValue:(NSString *)value forKey:(NSString *)key;
- (nullable NSString *)readSecureValueForKey:(NSString *)key;
- (BOOL)deleteSecureValueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
