#import "MCConstants.h"

NSString * const MCProductVersion = @"1.0.0";
NSString * const MCPreferencesDomain = @"com.multiclone.manager";
NSString * const MCManagerBundleID = @"com.multiclone.manager";
NSString * const MCSpringBoardBundleID = @"com.apple.springboard";

NSString * const MCAutoCloseRequestNotification = @"com.multiclone.manager/open-managed-app";
NSString * const MCAutoCloseResultNotification = @"com.multiclone.manager/open-managed-app-result";
NSString * const MCSpringBoardPingNotification = @"com.multiclone.manager/ping";
NSString * const MCSpringBoardPongNotification = @"com.multiclone.manager/pong";

NSString * const MCPrefKeyAutoCloseEnabled = @"autoCloseEnabled";
NSString * const MCPrefKeyAutoCloseOnlyManaged = @"autoCloseOnlyManagedClones";
NSString * const MCPrefKeyConfirmBeforeAutoClose = @"confirmBeforeAutoClose";
NSString * const MCPrefKeyLaunchBehavior = @"launchBehavior";
NSString * const MCPrefKeyThemeStyle = @"themeStyle";
NSString * const MCPrefKeyAccentHex = @"accentColorHex";
NSString * const MCPrefKeyManagedBundleIDs = @"managedCloneBundleIDs";
NSString * const MCPrefKeyPendingBundleID = @"pendingBundleID";
NSString * const MCPrefKeyLastManagedBundleID = @"lastManagedBundleID";
NSString * const MCPrefKeyLastActionStatus = @"lastActionStatus";
NSString * const MCPrefKeyLastActionError = @"lastActionError";
NSString * const MCPrefKeyLastActionTimestamp = @"lastActionTimestamp";
NSString * const MCPrefKeySpringBoardHeartbeat = @"springBoardHeartbeat";

NSErrorDomain const MCErrorDomain = @"com.multiclone.error";

NSString *MCRootlessPrefix(void) {
    static NSString *cachedPrefix = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:@"/var/jb"]) {
            cachedPrefix = @"/var/jb";
        } else if ([fm fileExistsAtPath:@"/private/preboot"]) {
            // Check standard Dopamine jbroot symlink if /var/jb is absent
            cachedPrefix = @"/var/jb";
        } else {
            cachedPrefix = @"";
        }
    });
    return cachedPrefix;
}

NSString *MCRootPath(NSString *relativePath) {
    NSString *clean = relativePath ?: @"";
    if ([clean hasPrefix:@"/var/jb/"]) {
        return clean;
    }
    NSString *prefix = MCRootlessPrefix();
    if (prefix.length == 0) {
        return clean;
    }
    if (![clean hasPrefix:@"/"]) {
        clean = [@"/" stringByAppendingString:clean];
    }
    return [prefix stringByAppendingString:clean];
}

NSString *MCManagedRootDirectory(void) {
    static NSString *rootDir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *mobilePath = @"/var/mobile/Library/MultiClone";
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *err = nil;
        if ([fm createDirectoryAtPath:mobilePath withIntermediateDirectories:YES attributes:nil error:&err] &&
            [fm isWritableFileAtPath:mobilePath]) {
            rootDir = mobilePath;
        } else {
            NSString *docs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                ?: NSTemporaryDirectory();
            rootDir = [docs stringByAppendingPathComponent:@"MultiClone"];
            [fm createDirectoryAtPath:rootDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
    });
    return rootDir;
}

static NSString *MCEnsureSubdirectory(NSString *name) {
    NSString *path = [MCManagedRootDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                                    error:nil];
    return path;
}

NSString *MCClonesDirectory(void) {
    return MCEnsureSubdirectory(@"Clones");
}

NSString *MCStagingDirectory(void) {
    return MCEnsureSubdirectory(@"Staging");
}

NSString *MCIconsDirectory(void) {
    return MCEnsureSubdirectory(@"Icons");
}

NSString *MCExportsDirectory(void) {
    return MCEnsureSubdirectory(@"Exports");
}

NSString *MCLogsDirectory(void) {
    return MCEnsureSubdirectory(@"Logs");
}

NSString *MCRegistryFilePath(void) {
    return [MCManagedRootDirectory() stringByAppendingPathComponent:@"registry.json"];
}

NSString *MCIPCStateFilePath(void) {
    return [MCManagedRootDirectory() stringByAppendingPathComponent:@"ipc_state.plist"];
}

BOOL MCIsValidBundleIdentifier(NSString * _Nullable bundleID) {
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length < 3 || bundleID.length > 180) {
        return NO;
    }
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*)+$"
                                                          options:0
                                                            error:nil];
    });
    NSRange fullRange = NSMakeRange(0, bundleID.length);
    return [regex numberOfMatchesInString:bundleID options:0 range:fullRange] == 1;
}

BOOL MCIsProtectedBundleIdentifier(NSString * _Nullable bundleID) {
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
        return YES;
    }
    NSString *lower = bundleID.lowercaseString;
    // Protect ALL Apple system apps and daemons by default
    if ([lower hasPrefix:@"com.apple."]) {
        return YES;
    }
    static NSSet<NSString *> *protectedSet = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        protectedSet = [NSSet setWithArray:@[
            @"com.multiclone.manager",
            @"com.opa334.dopamine",
            @"com.opa334.dopamine-roothide",
            @"org.coolstar.sileostore",
            @"org.coolstar.sileonightly",
            @"xyz.willy.zebra",
            @"com.opa334.trollstore",
            @"com.tigisoftware.filza",
            @"ws.hbang.newterm3"
        ]];
    });
    return [protectedSet containsObject:lower];
}

BOOL MCIsPathStrictlyInsideDirectory(NSString *candidatePath, NSString *baseDirectory) {
    if (candidatePath.length == 0 || baseDirectory.length == 0) {
        return NO;
    }
    NSString *resolvedBase = [baseDirectory stringByStandardizingPath];
    resolvedBase = [resolvedBase stringByResolvingSymlinksInPath];
    if (![resolvedBase hasSuffix:@"/"]) {
        resolvedBase = [resolvedBase stringByAppendingString:@"/"];
    }

    NSString *resolvedCandidate = [candidatePath stringByStandardizingPath];
    resolvedCandidate = [resolvedCandidate stringByResolvingSymlinksInPath];

    if ([resolvedCandidate isEqualToString:[resolvedBase substringToIndex:resolvedBase.length - 1]]) {
        return NO; // Must be strictly INSIDE baseDirectory, never baseDirectory itself
    }
    return [resolvedCandidate hasPrefix:resolvedBase];
}

NSError *MCMakeError(MCErrorCode code, NSString *description) {
    return [NSError errorWithDomain:MCErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"Unknown MultiClone error"}];
}
