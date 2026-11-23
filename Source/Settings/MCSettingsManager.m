#import "MCSettingsManager.h"
#import "../MultiCloneCore/MCConstants.h"
#import "../Logger/MCLogger.h"
#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>

@interface MCSettingsManager ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation MCSettingsManager

+ (instancetype)sharedManager {
    static MCSettingsManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MCSettingsManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [[NSUserDefaults alloc] initWithSuiteName:MCPreferencesDomain] ?: [NSUserDefaults standardUserDefaults];
        [_defaults registerDefaults:@{
            MCPrefKeyAutoCloseEnabled: @NO,
            MCPrefKeyAutoCloseOnlyManaged: @YES,
            MCPrefKeyConfirmBeforeAutoClose: @YES,
            MCPrefKeyLaunchBehavior: @(MCLaunchBehaviorAskEveryTime),
            MCPrefKeyThemeStyle: @(MCThemeStyleMidnight),
            MCPrefKeyAccentHex: @"#3B82F6",
            MCPrefKeyManagedBundleIDs: @[]
        }];
    }
    return self;
}

- (void)mc_setCFValue:(nullable id)value forKey:(NSString *)key {
    if (value) {
        [self.defaults setObject:value forKey:key];
    } else {
        [self.defaults removeObjectForKey:key];
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)MCPreferencesDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)MCPreferencesDomain);
    [self.defaults synchronize];
}

- (BOOL)autoCloseEnabled {
    return [self.defaults boolForKey:MCPrefKeyAutoCloseEnabled];
}

- (void)setAutoCloseEnabled:(BOOL)autoCloseEnabled {
    [self mc_setCFValue:@(autoCloseEnabled) forKey:MCPrefKeyAutoCloseEnabled];
    [self synchronizeIPCStateWithPendingBundleID:nil];
    [[MCLogger sharedLogger] info:@"Settings" format:@"autoCloseEnabled -> %@", autoCloseEnabled ? @"ON" : @"OFF"];
}

- (BOOL)autoCloseOnlyManagedClones {
    id val = [self.defaults objectForKey:MCPrefKeyAutoCloseOnlyManaged];
    return val ? [val boolValue] : YES;
}

- (void)setAutoCloseOnlyManagedClones:(BOOL)autoCloseOnlyManagedClones {
    // Safety policy: enforce managed-only mode so non-MultiClone and system apps are never targeted
    BOOL enforced = autoCloseOnlyManagedClones ? YES : YES;
    [self mc_setCFValue:@(enforced) forKey:MCPrefKeyAutoCloseOnlyManaged];
    [self synchronizeIPCStateWithPendingBundleID:nil];
}

- (BOOL)confirmBeforeAutoClose {
    id val = [self.defaults objectForKey:MCPrefKeyConfirmBeforeAutoClose];
    return val ? [val boolValue] : YES;
}

- (void)setConfirmBeforeAutoClose:(BOOL)confirmBeforeAutoClose {
    [self mc_setCFValue:@(confirmBeforeAutoClose) forKey:MCPrefKeyConfirmBeforeAutoClose];
}

- (MCLaunchBehavior)launchBehavior {
    return (MCLaunchBehavior)[self.defaults integerForKey:MCPrefKeyLaunchBehavior];
}

- (void)setLaunchBehavior:(MCLaunchBehavior)launchBehavior {
    [self mc_setCFValue:@(launchBehavior) forKey:MCPrefKeyLaunchBehavior];
}

- (MCThemeStyle)themeStyle {
    return (MCThemeStyle)[self.defaults integerForKey:MCPrefKeyThemeStyle];
}

- (void)setThemeStyle:(MCThemeStyle)themeStyle {
    [self mc_setCFValue:@(themeStyle) forKey:MCPrefKeyThemeStyle];
}

- (NSString *)accentColorHex {
    NSString *hex = [self.defaults stringForKey:MCPrefKeyAccentHex];
    return hex.length == 7 ? hex : @"#3B82F6";
}

- (void)setAccentColorHex:(NSString *)accentColorHex {
    if (accentColorHex.length == 7 && [accentColorHex hasPrefix:@"#"]) {
        [self mc_setCFValue:accentColorHex forKey:MCPrefKeyAccentHex];
    }
}

- (NSArray<NSString *> *)managedCloneBundleIDs {
    NSArray *raw = [self.defaults arrayForKey:MCPrefKeyManagedBundleIDs];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id item in raw) {
        if ([item isKindOfClass:[NSString class]] && MCIsValidBundleIdentifier(item) && !MCIsProtectedBundleIdentifier(item)) {
            if (![clean containsObject:item]) {
                [clean addObject:item];
            }
        }
    }
    return [clean copy];
}

- (void)setManagedCloneBundleIDs:(NSArray<NSString *> *)managedCloneBundleIDs {
    NSMutableArray<NSString *> *filtered = [NSMutableArray array];
    for (NSString *bid in managedCloneBundleIDs ?: @[]) {
        if (MCIsValidBundleIdentifier(bid) && !MCIsProtectedBundleIdentifier(bid) && ![filtered containsObject:bid]) {
            [filtered addObject:bid];
        }
    }
    [self mc_setCFValue:filtered forKey:MCPrefKeyManagedBundleIDs];
    [self synchronizeIPCStateWithPendingBundleID:nil];
}

- (nullable NSString *)lastManagedBundleID {
    NSDictionary *ipc = [self readSynchronizedIPCState];
    NSString *fromIPC = [ipc[MCPrefKeyLastManagedBundleID] isKindOfClass:[NSString class]] ? ipc[MCPrefKeyLastManagedBundleID] : nil;
    if (fromIPC.length > 0) return fromIPC;
    return [self.defaults stringForKey:MCPrefKeyLastManagedBundleID];
}

- (void)setLastManagedBundleID:(nullable NSString *)lastManagedBundleID {
    [self mc_setCFValue:lastManagedBundleID forKey:MCPrefKeyLastManagedBundleID];
}

- (void)registerManagedBundleID:(NSString *)bundleID {
    if (!MCIsValidBundleIdentifier(bundleID) || MCIsProtectedBundleIdentifier(bundleID)) return;
    NSMutableArray<NSString *> *list = [self.managedCloneBundleIDs mutableCopy];
    if (![list containsObject:bundleID]) {
        [list addObject:bundleID];
        self.managedCloneBundleIDs = list;
    }
}

- (void)unregisterManagedBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return;
    NSMutableArray<NSString *> *list = [self.managedCloneBundleIDs mutableCopy];
    [list removeObject:bundleID];
    self.managedCloneBundleIDs = list;
    if ([self.lastManagedBundleID isEqualToString:bundleID]) {
        self.lastManagedBundleID = nil;
        [self synchronizeIPCStateWithPendingBundleID:nil];
    }
}

- (BOOL)isManagedBundleID:(NSString *)bundleID {
    return [self.managedCloneBundleIDs containsObject:bundleID ?: @""];
}

- (BOOL)synchronizeIPCStateWithPendingBundleID:(nullable NSString *)pendingBundleID {
    NSMutableDictionary *payload = [[self readSynchronizedIPCState] mutableCopy] ?: [NSMutableDictionary dictionary];
    payload[MCPrefKeyAutoCloseEnabled] = @(self.autoCloseEnabled);
    payload[MCPrefKeyAutoCloseOnlyManaged] = @(self.autoCloseOnlyManagedClones);
    payload[MCPrefKeyManagedBundleIDs] = self.managedCloneBundleIDs ?: @[];

    if (pendingBundleID.length > 0) {
        payload[MCPrefKeyPendingBundleID] = pendingBundleID;
        [self mc_setCFValue:pendingBundleID forKey:MCPrefKeyPendingBundleID];
    } else {
        [payload removeObjectForKey:MCPrefKeyPendingBundleID];
        [self mc_setCFValue:nil forKey:MCPrefKeyPendingBundleID];
    }

    NSString *ipcPath = MCIPCStateFilePath();
    NSError *err = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:payload
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                                  options:0
                                                                    error:&err];
    if (!plistData) {
        [[MCLogger sharedLogger] error:@"Settings" format:@"Failed to serialize IPC plist: %@", err.localizedDescription];
        return NO;
    }
    BOOL ok = [plistData writeToFile:ipcPath options:NSDataWritingAtomic error:&err];
    if (!ok) {
        [[MCLogger sharedLogger] warn:@"Settings" format:@"IPC fallback plist write skipped: %@", err.localizedDescription];
    }
    return ok || [self.defaults synchronize];
}

- (NSDictionary<NSString *, id> *)readSynchronizedIPCState {
    CFPreferencesAppSynchronize((__bridge CFStringRef)MCPreferencesDomain);
    [self.defaults synchronize];
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];

    NSDictionary *fromFile = [NSDictionary dictionaryWithContentsOfFile:MCIPCStateFilePath()];
    if ([fromFile isKindOfClass:[NSDictionary class]]) {
        [merged addEntriesFromDictionary:fromFile];
    }
    NSDictionary *fromDefaults = [self.defaults dictionaryRepresentation];
    if ([fromDefaults isKindOfClass:[NSDictionary class]]) {
        NSArray<NSString *> *keys = @[
            MCPrefKeyAutoCloseEnabled, MCPrefKeyAutoCloseOnlyManaged, MCPrefKeyManagedBundleIDs,
            MCPrefKeyPendingBundleID, MCPrefKeyLastManagedBundleID, MCPrefKeyLastActionStatus,
            MCPrefKeyLastActionError, MCPrefKeyLastActionTimestamp, MCPrefKeySpringBoardHeartbeat
        ];
        for (NSString *k in keys) {
            id val = fromDefaults[k];
            if (val != nil && merged[k] == nil) {
                merged[k] = val;
            }
        }
    }
    return [merged copy];
}

- (BOOL)storeSecureValue:(NSString *)value forKey:(NSString *)key {
    if (key.length == 0 || !value) return NO;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: MCPreferencesDomain,
        (__bridge id)kSecAttrAccount: key
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    NSMutableDictionary *item = [query mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    return status == errSecSuccess;
}

- (nullable NSString *)readSecureValueForKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: MCPreferencesDomain,
        (__bridge id)kSecAttrAccount: key,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (BOOL)deleteSecureValueForKey:(NSString *)key {
    if (key.length == 0) return NO;
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: MCPreferencesDomain,
        (__bridge id)kSecAttrAccount: key
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

@end
