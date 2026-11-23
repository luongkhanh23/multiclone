#import "MCPrivateAPIBridge.h"
#import "MCConstants.h"
#import <objc/message.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

@implementation MCPrivateAPIBridge

+ (BOOL)terminateApplicationWithBundleID:(NSString *)bundleID
                                  reason:(NSString *)reasonDescription
                                   error:(NSError **)error {
    if (!MCIsValidBundleIdentifier(bundleID) || MCIsProtectedBundleIdentifier(bundleID)) {
        if (error) {
            *error = MCMakeError(MCErrorCodeProtectedBundle,
                [NSString stringWithFormat:@"Từ chối đóng ứng dụng được bảo vệ hoặc không hợp lệ: %@", bundleID ?: @"(nil)"]);
        }
        return NO;
    }

    @try {
        Class serviceClass = NSClassFromString(@"FBSSystemService");
        SEL sharedSEL = NSSelectorFromString(@"sharedService");
        if (!serviceClass || ![serviceClass respondsToSelector:sharedSEL]) {
            if (error) *error = MCMakeError(MCErrorCodePrivateAPIUnavailable, @"FBSSystemService không khả dụng trên tiến trình hiện tại.");
            return NO;
        }
        id service = ((id (*)(id, SEL))objc_msgSend)(serviceClass, sharedSEL);
        if (!service) {
            if (error) *error = MCMakeError(MCErrorCodePrivateAPIUnavailable, @"FBSSystemService sharedService trả về nil.");
            return NO;
        }

        NSString *desc = reasonDescription.length > 0 ? reasonDescription : @"MultiClone auto-close previous managed app";

        // Preferred on iOS 15 - 18.2: terminateApplication:forReason:andReport:withDescription:completion:
        SEL termWithCompletion = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:completion:");
        if ([service respondsToSelector:termWithCompletion]) {
            NSMethodSignature *sig = [service methodSignatureForSelector:termWithCompletion];
            if (sig && sig.numberOfArguments == 7) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = service;
                inv.selector = termWithCompletion;
                NSString *ident = bundleID;
                int64_t reasonVal = 1; // FBProcessTerminationReasonUserRequest
                BOOL reportVal = NO;
                void (^completion)(BOOL) = ^(BOOL success) {
                    (void)success;
                };
                [inv setArgument:&ident atIndex:2];
                // Validate integer argument width before passing reasonVal
                const char *arg3Type = [sig getArgumentTypeAtIndex:3];
                if (arg3Type && (arg3Type[0] == 'i' || arg3Type[0] == 'I')) {
                    int32_t reason32 = 1;
                    [inv setArgument:&reason32 atIndex:3];
                } else {
                    [inv setArgument:&reasonVal atIndex:3];
                }
                [inv setArgument:&reportVal atIndex:4];
                [inv setArgument:&desc atIndex:5];
                [inv setArgument:&completion atIndex:6];
                [inv invoke];
                return YES;
            }
        }

        // Fallback: terminateApplication:forReason:andReport:withDescription:
        SEL termLegacy = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
        if ([service respondsToSelector:termLegacy]) {
            NSMethodSignature *sig = [service methodSignatureForSelector:termLegacy];
            if (sig && sig.numberOfArguments == 6) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = service;
                inv.selector = termLegacy;
                NSString *ident = bundleID;
                int64_t reasonVal = 1;
                BOOL reportVal = NO;
                [inv setArgument:&ident atIndex:2];
                const char *arg3Type = [sig getArgumentTypeAtIndex:3];
                if (arg3Type && (arg3Type[0] == 'i' || arg3Type[0] == 'I')) {
                    int32_t reason32 = 1;
                    [inv setArgument:&reason32 atIndex:3];
                } else {
                    [inv setArgument:&reasonVal atIndex:3];
                }
                [inv setArgument:&reportVal atIndex:4];
                [inv setArgument:&desc atIndex:5];
                [inv invoke];
                return YES;
            }
        }

        if (error) *error = MCMakeError(MCErrorCodePrivateAPIUnavailable, @"Không tìm thấy selector đóng ứng dụng tương thích trên FBSSystemService.");
        return NO;
    } @catch (NSException *ex) {
        if (error) {
            *error = MCMakeError(MCErrorCodePrivateAPIUnavailable,
                [NSString stringWithFormat:@"Ngoại lệ khi gọi FBSSystemService: %@", ex.reason]);
        }
        return NO;
    }
}

+ (BOOL)openApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error {
    if (!MCIsValidBundleIdentifier(bundleID)) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidBundleID, @"Bundle ID không hợp lệ để mở ứng dụng.");
        return NO;
    }

    @try {
        // Primary: LSApplicationWorkspace
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSEL = NSSelectorFromString(@"defaultWorkspace");
        SEL openSEL = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (wsClass && [wsClass respondsToSelector:defaultSEL]) {
            id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, defaultSEL);
            if (ws && [ws respondsToSelector:openSEL]) {
                BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, openSEL, bundleID);
                if (ok) return YES;
            }
        }

        // Secondary fallback: FBSSystemService openApplication:options:withResult:
        Class fbsClass = NSClassFromString(@"FBSSystemService");
        SEL sharedSEL = NSSelectorFromString(@"sharedService");
        SEL fbsOpenSEL = NSSelectorFromString(@"openApplication:options:withResult:");
        if (fbsClass && [fbsClass respondsToSelector:sharedSEL]) {
            id fbs = ((id (*)(id, SEL))objc_msgSend)(fbsClass, sharedSEL);
            if (fbs && [fbs respondsToSelector:fbsOpenSEL]) {
                void (^resultBlock)(NSError *) = ^(NSError *openErr) { (void)openErr; };
                ((void (*)(id, SEL, id, id, id))objc_msgSend)(fbs, fbsOpenSEL, bundleID, @{}, resultBlock);
                return YES;
            }
        }

        if (error) *error = MCMakeError(MCErrorCodePrivateAPIUnavailable,
            [NSString stringWithFormat:@"Không thể mở ứng dụng %@ (LSApplicationWorkspace/FBSSystemService không sẵn sàng).", bundleID]);
        return NO;
    } @catch (NSException *ex) {
        if (error) {
            *error = MCMakeError(MCErrorCodePrivateAPIUnavailable,
                [NSString stringWithFormat:@"Ngoại lệ khi mở ứng dụng %@: %@", bundleID, ex.reason]);
        }
        return NO;
    }
}

+ (nullable MCInstalledAppInfo *)mc_appInfoFromProxy:(id)proxy managedIDs:(NSSet<NSString *> *)managedIDs {
    if (!proxy) return nil;
    @try {
        SEL idSEL = NSSelectorFromString(@"applicationIdentifier");
        if (![proxy respondsToSelector:idSEL]) {
            idSEL = NSSelectorFromString(@"bundleIdentifier");
        }
        if (![proxy respondsToSelector:idSEL]) return nil;
        NSString *bid = ((id (*)(id, SEL))objc_msgSend)(proxy, idSEL);
        if (![bid isKindOfClass:[NSString class]] || bid.length == 0) return nil;

        MCInstalledAppInfo *info = [[MCInstalledAppInfo alloc] init];
        info.bundleID = bid;
        info.isManagedClone = [managedIDs containsObject:bid];

        SEL nameSEL = NSSelectorFromString(@"localizedName");
        NSString *name = [proxy respondsToSelector:nameSEL] ? ((id (*)(id, SEL))objc_msgSend)(proxy, nameSEL) : nil;
        info.displayName = ([name isKindOfClass:[NSString class]] && name.length > 0) ? name : bid;

        SEL verSEL = NSSelectorFromString(@"shortVersionString");
        if ([proxy respondsToSelector:verSEL]) {
            id v = ((id (*)(id, SEL))objc_msgSend)(proxy, verSEL);
            if ([v isKindOfClass:[NSString class]]) info.shortVersion = v;
        }

        SEL typeSEL = NSSelectorFromString(@"applicationType");
        if ([proxy respondsToSelector:typeSEL]) {
            id t = ((id (*)(id, SEL))objc_msgSend)(proxy, typeSEL);
            info.isSystemApp = [t isKindOfClass:[NSString class]] && [t isEqualToString:@"System"];
        } else {
            info.isSystemApp = [bid hasPrefix:@"com.apple."];
        }

        SEL urlSEL = NSSelectorFromString(@"bundleURL");
        if ([proxy respondsToSelector:urlSEL]) {
            NSURL *u = ((id (*)(id, SEL))objc_msgSend)(proxy, urlSEL);
            if ([u isKindOfClass:[NSURL class]]) info.bundlePath = u.path;
        }

        SEL dataSEL = NSSelectorFromString(@"dataContainerURL");
        if ([proxy respondsToSelector:dataSEL]) {
            NSURL *u = ((id (*)(id, SEL))objc_msgSend)(proxy, dataSEL);
            if ([u isKindOfClass:[NSURL class]]) info.dataContainerPath = u.path;
        }
        return info;
    } @catch (NSException *ex) {
        (void)ex;
        return nil;
    }
}

+ (NSArray<MCInstalledAppInfo *> *)installedApplicationsWithManagedIDs:(NSSet<NSString *> *)managedIDs {
    NSMutableArray<MCInstalledAppInfo *> *result = [NSMutableArray array];
    @try {
        Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSEL = NSSelectorFromString(@"defaultWorkspace");
        SEL allSEL = NSSelectorFromString(@"allInstalledApplications");
        if (!wsClass || ![wsClass respondsToSelector:defaultSEL]) return @[];
        id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, defaultSEL);
        if (!ws || ![ws respondsToSelector:allSEL]) return @[];
        NSArray *proxies = ((id (*)(id, SEL))objc_msgSend)(ws, allSEL);
        if (![proxies isKindOfClass:[NSArray class]]) return @[];

        for (id proxy in proxies) {
            MCInstalledAppInfo *info = [self mc_appInfoFromProxy:proxy managedIDs:managedIDs ?: [NSSet set]];
            if (info && !info.isSystemApp) {
                [result addObject:info];
            }
        }
        [result sortUsingComparator:^NSComparisonResult(MCInstalledAppInfo *a, MCInstalledAppInfo *b) {
            return [a.displayName localizedCaseInsensitiveCompare:b.displayName];
        }];
    } @catch (NSException *ex) {
        (void)ex;
    }
    return [result copy];
}

+ (nullable MCInstalledAppInfo *)installedApplicationForBundleID:(NSString *)bundleID {
    if (!MCIsValidBundleIdentifier(bundleID)) return nil;
    @try {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL lookupSEL = NSSelectorFromString(@"applicationProxyForIdentifier:");
        if (!proxyClass || ![proxyClass respondsToSelector:lookupSEL]) return nil;
        id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, lookupSEL, bundleID);
        if (!proxy) return nil;
        SEL installedSEL = NSSelectorFromString(@"isInstalled");
        if ([proxy respondsToSelector:installedSEL]) {
            BOOL installed = ((BOOL (*)(id, SEL))objc_msgSend)(proxy, installedSEL);
            if (!installed) return nil;
        }
        return [self mc_appInfoFromProxy:proxy managedIDs:[NSSet set]];
    } @catch (NSException *ex) {
        (void)ex;
        return nil;
    }
}

+ (nullable NSString *)pathForToolNamed:(NSString *)toolName {
    if (toolName.length == 0 || [toolName containsString:@"/"]) return nil;
    NSArray<NSString *> *candidates = @[
        MCRootPath([@"/usr/bin/" stringByAppendingString:toolName]),
        MCRootPath([@"/usr/local/bin/" stringByAppendingString:toolName]),
        MCRootPath([@"/bin/" stringByAppendingString:toolName]),
        [@"/usr/bin/" stringByAppendingString:toolName]
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

+ (int)runToolAtPath:(NSString *)toolPath
           arguments:(NSArray<NSString *> *)arguments
              output:(NSString * _Nullable * _Nullable)output
               error:(NSError **)error {
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:toolPath]) {
        if (error) *error = MCMakeError(MCErrorCodeSigningToolUnavailable,
            [NSString stringWithFormat:@"Không tìm thấy công cụ thực thi tại: %@", toolPath ?: @"(nil)"]);
        return -1;
    }

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể tạo pipe tiến trình con.");
        return -1;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    NSUInteger argc = 1 + arguments.count;
    char **argv = calloc(argc + 1, sizeof(char *));
    argv[0] = strdup(toolPath.fileSystemRepresentation);
    for (NSUInteger i = 0; i < arguments.count; i++) {
        argv[i + 1] = strdup(arguments[i].UTF8String);
    }

    pid_t pid = 0;
    int spawnStatus = posix_spawn(&pid, toolPath.fileSystemRepresentation, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);

    for (NSUInteger i = 0; i < argc; i++) {
        free(argv[i]);
    }
    free(argv);

    if (spawnStatus != 0) {
        close(pipefd[0]);
        if (error) {
            *error = MCMakeError(MCErrorCodeIOFailure,
                [NSString stringWithFormat:@"posix_spawn thất bại cho %@ (errno=%d).", toolPath.lastPathComponent, spawnStatus]);
        }
        return -1;
    }

    NSMutableData *buf = [NSMutableData data];
    uint8_t chunk[4096];
    ssize_t n = 0;
    while ((n = read(pipefd[0], chunk, sizeof(chunk))) > 0) {
        [buf appendBytes:chunk length:(NSUInteger)n];
    }
    close(pipefd[0]);

    int waitStatus = 0;
    waitpid(pid, &waitStatus, 0);
    int exitCode = WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : -1;

    if (output) {
        *output = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding] ?: @"";
    }
    return exitCode;
}

@end
