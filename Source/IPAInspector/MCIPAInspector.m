#import "MCIPAInspector.h"
#import "../MultiCloneCore/MCConstants.h"
#import "../MultiCloneCore/MCZipArchive.h"
#import "../MultiCloneCore/MCMachOInspector.h"
#import "../Logger/MCLogger.h"

@implementation MCIPAInspector

+ (nullable NSDictionary<NSString *, id> *)mc_parseProvisioningProfileData:(NSData *)raw {
    if (raw.length == 0) return nil;
    NSData *startTag = [@"<plist" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *endTag = [@"</plist>" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange startRange = [raw rangeOfData:startTag options:0 range:NSMakeRange(0, raw.length)];
    if (startRange.location == NSNotFound) return nil;
    NSRange endRange = [raw rangeOfData:endTag
                                options:0
                                  range:NSMakeRange(startRange.location, raw.length - startRange.location)];
    if (endRange.location == NSNotFound) return nil;
    NSUInteger xmlLen = (endRange.location + endRange.length) - startRange.location;
    NSData *xmlData = [raw subdataWithRange:NSMakeRange(startRange.location, xmlLen)];
    id obj = [NSPropertyListSerialization propertyListWithData:xmlData options:NSPropertyListImmutable format:NULL error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

+ (BOOL)mc_isCgBIPNG:(NSData *)pngData {
    if (pngData.length < 16) return NO;
    const uint8_t *b = (const uint8_t *)pngData.bytes;
    // Standard PNG signature: 89 50 4E 47 0D 0A 1A 0A; Apple CgBI chunk appears immediately at bytes 12..15
    return (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 &&
            b[12] == 'C' && b[13] == 'g' && b[14] == 'B' && b[15] == 'I');
}

+ (nullable MCZipEntry *)mc_findBestIconEntryInArchive:(MCZipArchive *)archive
                                             appPrefix:(NSString *)appPrefix
                                             infoPlist:(NSDictionary *)info {
    NSMutableArray<NSString *> *preferredPrefixes = [NSMutableArray array];
    NSDictionary *icons = info[@"CFBundleIcons"];
    if ([icons isKindOfClass:[NSDictionary class]]) {
        NSDictionary *primary = icons[@"CFBundlePrimaryIcon"];
        if ([primary isKindOfClass:[NSDictionary class]]) {
            NSArray *files = primary[@"CFBundleIconFiles"];
            if ([files isKindOfClass:[NSArray class]]) {
                [preferredPrefixes addObjectsFromArray:files];
            }
            NSString *iconName = primary[@"CFBundleIconName"];
            if ([iconName isKindOfClass:[NSString class]]) {
                [preferredPrefixes addObject:iconName];
            }
        }
    }
    NSArray *legacyFiles = info[@"CFBundleIconFiles"];
    if ([legacyFiles isKindOfClass:[NSArray class]]) {
        [preferredPrefixes addObjectsFromArray:legacyFiles];
    }

    MCZipEntry *bestMatch = nil;
    uint64_t bestSize = 0;

    for (MCZipEntry *entry in archive.entries) {
        if (entry.isDirectory || ![entry.path hasPrefix:appPrefix]) continue;
        NSString *rel = [entry.path substringFromIndex:appPrefix.length];
        if ([rel containsString:@"/"]) continue; // top-level icon PNG in .app
        if (![rel.lowercaseString hasSuffix:@".png"]) continue;

        BOOL matchesHint = NO;
        for (NSString *prefix in preferredPrefixes) {
            if ([rel hasPrefix:prefix]) {
                matchesHint = YES;
                break;
            }
        }
        if (!matchesHint && ![rel.lowercaseString containsString:@"appicon"]) {
            continue;
        }
        if (entry.uncompressedSize > bestSize) {
            bestSize = entry.uncompressedSize;
            bestMatch = entry;
        }
    }
    return bestMatch;
}

+ (nullable MCIPAInspectionReport *)inspectIPAAtPath:(NSString *)ipaPath error:(NSError **)error {
    [[MCLogger sharedLogger] info:@"IPAInspector" format:@"Inspecting IPA: %@", ipaPath.lastPathComponent ?: @"(nil)"];
    MCZipArchive *archive = [MCZipArchive archiveWithPath:ipaPath error:error];
    if (!archive) {
        return nil;
    }

    MCZipEntry *infoEntry = nil;
    for (MCZipEntry *e in archive.entries) {
        if ([e.path hasPrefix:@"__MACOSX/"]) continue;
        NSString *low = e.path.lowercaseString;
        if ([low hasPrefix:@"payload/"] && [low hasSuffix:@".app/info.plist"]) {
            NSArray *parts = [e.path componentsSeparatedByString:@"/"];
            if (parts.count == 3) {
                infoEntry = e;
                break;
            }
        }
    }
    if (!infoEntry) {
        if (error) *error = MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Không tìm thấy Payload/*.app/Info.plist trong tệp IPA.");
        return nil;
    }

    NSData *plistData = [archive dataForEntry:infoEntry error:error];
    if (!plistData) return nil;

    id plistObj = [NSPropertyListSerialization propertyListWithData:plistData
                                                            options:NSPropertyListImmutable
                                                             format:NULL
                                                              error:error];
    if (![plistObj isKindOfClass:[NSDictionary class]]) {
        if (error) *error = MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Info.plist trong IPA không hợp lệ.");
        return nil;
    }
    NSDictionary *info = (NSDictionary *)plistObj;
    NSString *appPrefix = [infoEntry.path substringToIndex:(infoEntry.path.length - @"Info.plist".length)];

    MCIPAInspectionReport *report = [[MCIPAInspectionReport alloc] init];
    report.ipaPath = ipaPath;
    report.appFolderPathInZip = appPrefix;
    report.bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? info[@"CFBundleIdentifier"] : @"";
    report.displayName = [info[@"CFBundleDisplayName"] isKindOfClass:[NSString class]] ? info[@"CFBundleDisplayName"]
        : ([info[@"CFBundleName"] isKindOfClass:[NSString class]] ? info[@"CFBundleName"] : report.bundleID);
    report.shortVersion = [info[@"CFBundleShortVersionString"] isKindOfClass:[NSString class]] ? info[@"CFBundleShortVersionString"] : @"";
    report.buildVersion = [info[@"CFBundleVersion"] isKindOfClass:[NSString class]] ? info[@"CFBundleVersion"] : @"";
    report.executableName = [info[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? info[@"CFBundleExecutable"] : @"";
    report.minimumOSVersion = [info[@"MinimumOSVersion"] isKindOfClass:[NSString class]] ? info[@"MinimumOSVersion"] : nil;
    report.supportedPlatforms = [info[@"CFBundleSupportedPlatforms"] isKindOfClass:[NSArray class]] ? info[@"CFBundleSupportedPlatforms"] : @[];

    // URL Schemes
    NSMutableArray<NSString *> *schemes = [NSMutableArray array];
    NSArray *urlTypes = info[@"CFBundleURLTypes"];
    if ([urlTypes isKindOfClass:[NSArray class]]) {
        for (id item in urlTypes) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                NSArray *s = item[@"CFBundleURLSchemes"];
                if ([s isKindOfClass:[NSArray class]]) {
                    for (id sc in s) {
                        if ([sc isKindOfClass:[NSString class]] && ![schemes containsObject:sc]) {
                            [schemes addObject:sc];
                        }
                    }
                }
            }
        }
    }
    report.urlSchemes = [schemes copy];

    // Frameworks & Extensions & Provisioning Profile
    NSMutableArray<NSString *> *frameworks = [NSMutableArray array];
    NSMutableArray<MCExtensionInfo *> *extensions = [NSMutableArray array];
    NSString *frameworksPrefix = [appPrefix stringByAppendingString:@"Frameworks/"];
    NSString *provPath = [appPrefix stringByAppendingString:@"embedded.mobileprovision"];

    for (MCZipEntry *e in archive.entries) {
        if (![e.path hasPrefix:appPrefix]) continue;

        if ([e.path hasPrefix:frameworksPrefix] &&
            ([e.path hasSuffix:@".framework/Info.plist"] || [e.path hasSuffix:@".dylib"])) {
            NSString *rel = [e.path substringFromIndex:frameworksPrefix.length];
            NSString *fwName = [rel componentsSeparatedByString:@"/"].firstObject ?: rel;
            if (![frameworks containsObject:fwName]) {
                [frameworks addObject:fwName];
            }
        } else if ([e.path containsString:@".appex/Info.plist"]) {
            NSData *extData = [archive dataForEntry:e error:nil];
            NSDictionary *extPlist = extData ? [NSPropertyListSerialization propertyListWithData:extData options:0 format:NULL error:nil] : nil;
            if ([extPlist isKindOfClass:[NSDictionary class]]) {
                MCExtensionInfo *ext = [[MCExtensionInfo alloc] init];
                ext.relativePath = [e.path substringFromIndex:appPrefix.length];
                ext.bundleID = [extPlist[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? extPlist[@"CFBundleIdentifier"] : @"";
                ext.displayName = [extPlist[@"CFBundleDisplayName"] isKindOfClass:[NSString class]]
                    ? extPlist[@"CFBundleDisplayName"]
                    : ([extPlist[@"CFBundleName"] isKindOfClass:[NSString class]] ? extPlist[@"CFBundleName"] : ext.bundleID);
                NSDictionary *nsExt = extPlist[@"NSExtension"];
                if ([nsExt isKindOfClass:[NSDictionary class]] && [nsExt[@"NSExtensionPointIdentifier"] isKindOfClass:[NSString class]]) {
                    ext.extensionPointIdentifier = nsExt[@"NSExtensionPointIdentifier"];
                }
                [extensions addObject:ext];
            }
        } else if ([e.path isEqualToString:provPath]) {
            report.hasEmbeddedProvisioningProfile = YES;
            NSData *provData = [archive dataForEntry:e error:nil];
            report.provisioningProfile = [self mc_parseProvisioningProfileData:provData];
        }
    }
    report.frameworks = [frameworks copy];
    report.extensions = [extensions copy];

    // Executable Mach-O inspection (architectures, FairPlay DRM cryptid, embedded entitlements)
    if (report.executableName.length > 0) {
        @autoreleasepool {
            NSString *execZipPath = [appPrefix stringByAppendingString:report.executableName];
            NSData *execData = [archive dataForPath:execZipPath error:nil];
            if (execData.length > 0) {
                MCMachOInspectionResult *macho = [MCMachOInspector inspectMachOData:execData];
                report.architectures = macho.architectures;
                report.isFairPlayEncrypted = macho.isEncrypted;
                report.encryptionCryptID = macho.cryptID;
                if (macho.entitlements) {
                    report.entitlements = macho.entitlements;
                }
            }
        }
    }
    // Fallback to provisioning profile entitlements if binary signature blob absent
    if (!report.entitlements && [report.provisioningProfile[@"Entitlements"] isKindOfClass:[NSDictionary class]]) {
        report.entitlements = report.provisioningProfile[@"Entitlements"];
    }

    // Icon extraction
    MCZipEntry *iconEntry = [self mc_findBestIconEntryInArchive:archive appPrefix:appPrefix infoPlist:info];
    if (iconEntry) {
        NSData *iconData = [archive dataForEntry:iconEntry error:nil];
        if (iconData.length > 0) {
            report.iconEntryPath = iconEntry.path;
            report.iconPNGData = iconData;
            report.isIconCgBIEncoded = [self mc_isCgBIPNG:iconData];
        }
    }

    [self evaluateCompatibilityForReport:report];
    return report;
}

+ (nullable MCIPAInspectionReport *)inspectInstalledAppBundleAtPath:(NSString *)appBundlePath error:(NSError **)error {
    [[MCLogger sharedLogger] info:@"IPAInspector" format:@"Inspecting installed .app bundle: %@", appBundlePath.lastPathComponent ?: @"(nil)"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (appBundlePath.length == 0 || ![fm fileExistsAtPath:appBundlePath isDirectory:&isDir] || !isDir) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không tìm thấy thư mục .app của ứng dụng gốc.");
        return nil;
    }

    NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (![info isKindOfClass:[NSDictionary class]]) {
        if (error) *error = MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Không thể đọc Info.plist từ ứng dụng đã cài (kiểm tra quyền truy cập).");
        return nil;
    }

    MCIPAInspectionReport *report = [[MCIPAInspectionReport alloc] init];
    report.ipaPath = @"";
    report.sourceAppBundlePath = appBundlePath;
    report.isFromInstalledAppBundle = YES;
    report.appFolderPathInZip = [NSString stringWithFormat:@"Payload/%@/", appBundlePath.lastPathComponent];
    report.bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? info[@"CFBundleIdentifier"] : @"";
    report.displayName = [info[@"CFBundleDisplayName"] isKindOfClass:[NSString class]] ? info[@"CFBundleDisplayName"]
        : ([info[@"CFBundleName"] isKindOfClass:[NSString class]] ? info[@"CFBundleName"] : report.bundleID);
    report.shortVersion = [info[@"CFBundleShortVersionString"] isKindOfClass:[NSString class]] ? info[@"CFBundleShortVersionString"] : @"";
    report.buildVersion = [info[@"CFBundleVersion"] isKindOfClass:[NSString class]] ? info[@"CFBundleVersion"] : @"";
    report.executableName = [info[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ? info[@"CFBundleExecutable"] : @"";
    report.minimumOSVersion = [info[@"MinimumOSVersion"] isKindOfClass:[NSString class]] ? info[@"MinimumOSVersion"] : nil;
    report.supportedPlatforms = [info[@"CFBundleSupportedPlatforms"] isKindOfClass:[NSArray class]] ? info[@"CFBundleSupportedPlatforms"] : @[];

    // URL Schemes
    NSMutableArray<NSString *> *schemes = [NSMutableArray array];
    NSArray *urlTypes = info[@"CFBundleURLTypes"];
    if ([urlTypes isKindOfClass:[NSArray class]]) {
        for (id item in urlTypes) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                NSArray *s = item[@"CFBundleURLSchemes"];
                if ([s isKindOfClass:[NSArray class]]) {
                    for (id sc in s) {
                        if ([sc isKindOfClass:[NSString class]] && ![schemes containsObject:sc]) [schemes addObject:sc];
                    }
                }
            }
        }
    }
    report.urlSchemes = [schemes copy];

    // Embedded Frameworks
    NSMutableArray<NSString *> *frameworks = [NSMutableArray array];
    NSString *fwDir = [appBundlePath stringByAppendingPathComponent:@"Frameworks"];
    for (NSString *fw in ([fm contentsOfDirectoryAtPath:fwDir error:nil] ?: @[])) {
        if ([fw.lowercaseString hasSuffix:@".framework"] || [fw.lowercaseString hasSuffix:@".dylib"]) {
            [frameworks addObject:fw];
        }
    }
    report.frameworks = [frameworks copy];

    // Embedded Extensions (.appex)
    NSMutableArray<MCExtensionInfo *> *extensions = [NSMutableArray array];
    NSString *pluginsDir = [appBundlePath stringByAppendingPathComponent:@"PlugIns"];
    for (NSString *item in ([fm contentsOfDirectoryAtPath:pluginsDir error:nil] ?: @[])) {
        if (![item.lowercaseString hasSuffix:@".appex"]) continue;
        NSString *extPlistPath = [[pluginsDir stringByAppendingPathComponent:item] stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *extPlist = [NSDictionary dictionaryWithContentsOfFile:extPlistPath];
        if ([extPlist isKindOfClass:[NSDictionary class]]) {
            MCExtensionInfo *ext = [[MCExtensionInfo alloc] init];
            ext.relativePath = [@"PlugIns/" stringByAppendingPathComponent:[item stringByAppendingPathComponent:@"Info.plist"]];
            ext.bundleID = [extPlist[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? extPlist[@"CFBundleIdentifier"] : @"";
            ext.displayName = [extPlist[@"CFBundleDisplayName"] isKindOfClass:[NSString class]] ? extPlist[@"CFBundleDisplayName"]
                : ([extPlist[@"CFBundleName"] isKindOfClass:[NSString class]] ? extPlist[@"CFBundleName"] : ext.bundleID);
            NSDictionary *nsExt = extPlist[@"NSExtension"];
            if ([nsExt isKindOfClass:[NSDictionary class]] && [nsExt[@"NSExtensionPointIdentifier"] isKindOfClass:[NSString class]]) {
                ext.extensionPointIdentifier = nsExt[@"NSExtensionPointIdentifier"];
            }
            [extensions addObject:ext];
        }
    }
    report.extensions = [extensions copy];

    // Provisioning profile
    NSString *provPath = [appBundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    if ([fm fileExistsAtPath:provPath]) {
        report.hasEmbeddedProvisioningProfile = YES;
        NSData *provData = [NSData dataWithContentsOfFile:provPath];
        report.provisioningProfile = [self mc_parseProvisioningProfileData:provData];
    }

    // Mach-O Executable inspection (read-only)
    if (report.executableName.length > 0) {
        NSString *execPath = [appBundlePath stringByAppendingPathComponent:report.executableName];
        NSData *execData = [NSData dataWithContentsOfFile:execPath options:NSDataReadingMappedIfSafe error:nil];
        if (execData.length > 0) {
            MCMachOInspectionResult *macho = [MCMachOInspector inspectMachOData:execData];
            report.architectures = macho.architectures;
            report.isFairPlayEncrypted = macho.isEncrypted;
            report.encryptionCryptID = macho.cryptID;
            if (macho.entitlements) {
                report.entitlements = macho.entitlements;
            }
        }
    }
    if (!report.entitlements && [report.provisioningProfile[@"Entitlements"] isKindOfClass:[NSDictionary class]]) {
        report.entitlements = report.provisioningProfile[@"Entitlements"];
    }

    // Best icon PNG from installed bundle
    NSArray<NSString *> *topFiles = [fm contentsOfDirectoryAtPath:appBundlePath error:nil] ?: @[];
    NSString *bestIconPath = nil;
    unsigned long long bestSize = 0;
    for (NSString *file in topFiles) {
        if (![file.lowercaseString hasSuffix:@".png"]) continue;
        if (![file.lowercaseString containsString:@"appicon"] && ![file.lowercaseString containsString:@"icon"]) continue;
        NSString *full = [appBundlePath stringByAppendingPathComponent:file];
        unsigned long long sz = [[fm attributesOfItemAtPath:full error:nil] fileSize];
        if (sz > bestSize) {
            bestSize = sz;
            bestIconPath = full;
        }
    }
    if (bestIconPath) {
        NSData *iconData = [NSData dataWithContentsOfFile:bestIconPath];
        if (iconData.length > 0) {
            report.iconEntryPath = bestIconPath.lastPathComponent;
            report.iconPNGData = iconData;
            report.isIconCgBIEncoded = [self mc_isCgBIPNG:iconData];
        }
    }

    [self evaluateCompatibilityForReport:report];
    return report;
}

+ (void)evaluateCompatibilityForReport:(MCIPAInspectionReport *)report {
    NSMutableArray<MCCompatibilityIssue *> *issues = [NSMutableArray array];
    BOOL hasBlocker = NO;
    BOOL hasWarning = NO;

    if (!MCIsValidBundleIdentifier(report.bundleID)) {
        hasBlocker = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityBlocker
                                                             code:@"INVALID_BUNDLE_ID"
                                                            title:@"Bundle ID không hợp lệ"
                                                           detail:@"Info.plist không chứa CFBundleIdentifier hợp lệ."]];
    }

    if (MCIsProtectedBundleIdentifier(report.bundleID)) {
        hasBlocker = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityBlocker
                                                             code:@"PROTECTED_SYSTEM_APP"
                                                            title:@"Ứng dụng hệ thống được bảo vệ"
                                                           detail:@"MultiClone không cho phép nhân bản ứng dụng hệ thống Apple hoặc công cụ jailbreak cốt lõi."]];
    }

    if (report.executableName.length == 0) {
        hasBlocker = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityBlocker
                                                             code:@"MISSING_EXECUTABLE"
                                                            title:@"Thiếu tệp thực thi chính"
                                                           detail:@"Không tìm thấy CFBundleExecutable trong Info.plist."]];
    }

    if (report.isFairPlayEncrypted) {
        hasBlocker = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityBlocker
                                                             code:@"FAIRPLAY_DRM_ENCRYPTED"
                                                            title:@"IPA có mã hóa FairPlay DRM (cryptid != 0)"
                                                           detail:@"Tệp thực thi đang được mã hóa FairPlay DRM. MultiClone KHÔNG bypass DRM. Chỉ sử dụng IPA không mã hóa mà bạn có quyền hợp lệ."]];
    }

    BOOL hasArm64 = [report.architectures containsObject:@"arm64"] || [report.architectures containsObject:@"arm64e"];
    if (report.architectures.count > 0 && !hasArm64) {
        hasBlocker = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityBlocker
                                                             code:@"UNSUPPORTED_ARCH"
                                                            title:@"Không hỗ trợ kiến trúc iPhone 11 (arm64/arm64e)"
                                                           detail:[NSString stringWithFormat:@"Kiến trúc tìm thấy: %@.",
                                                                   [report.architectures componentsJoinedByString:@", "]]]];
    }

    // Entitlement checks (App Groups, Keychain, Push, Associated Domains)
    NSDictionary *ents = report.entitlements;
    if ([ents isKindOfClass:[NSDictionary class]]) {
        NSArray *appGroups = ents[@"com.apple.security.application-groups"];
        if ([appGroups isKindOfClass:[NSArray class]] && appGroups.count > 0) {
            hasWarning = YES;
            [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityWarning
                                                                 code:@"ENTITLEMENT_APP_GROUPS"
                                                                title:@"Sử dụng App Groups"
                                                               detail:[NSString stringWithFormat:@"Ứng dụng khai báo %lu App Group(s). Đổi Bundle ID có thể khiến dữ liệu chia sẻ giữa app và extension bị xung đột hoặc không cô lập hoàn toàn.", (unsigned long)appGroups.count]]];
        }

        NSArray *keychainGroups = ents[@"keychain-access-groups"];
        if ([keychainGroups isKindOfClass:[NSArray class]] && keychainGroups.count > 0) {
            hasWarning = YES;
            [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityWarning
                                                                 code:@"ENTITLEMENT_KEYCHAIN"
                                                                title:@"Sử dụng Keychain Access Groups"
                                                               detail:@"Keychain gắn với Team ID và entitlement. Bản clone có thể không lưu được phiên đăng nhập hoặc xung đột Keychain nếu ký lại không đúng quyền."]];
        }

        if (ents[@"aps-environment"] != nil) {
            hasWarning = YES;
            [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityWarning
                                                                 code:@"ENTITLEMENT_PUSH"
                                                                title:@"Push Notifications (APNs)"
                                                               detail:@"Thông báo đẩy gắn chặt với Bundle ID và chứng chỉ Apple gốc. Bản clone ký ad-hoc thường không nhận được Push Notifications."]];
        }

        NSArray *domains = ents[@"com.apple.developer.associated-domains"];
        if ([domains isKindOfClass:[NSArray class]] && domains.count > 0) {
            hasWarning = YES;
            [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityWarning
                                                                 code:@"ENTITLEMENT_ASSOC_DOMAINS"
                                                                title:@"Associated Domains / Universal Links"
                                                               detail:@"Universal Links và đăng nhập liên kết miền yêu cầu Apple Team ID hợp lệ."]];
        }
    } else {
        hasWarning = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityWarning
                                                             code:@"ENTITLEMENTS_UNDETECTED"
                                                            title:@"Không đọc được entitlement từ chữ ký"
                                                           detail:@"Binary không chứa blob entitlement nhúng hoặc chưa ký. Hãy kiểm tra lại quyền ứng dụng trước khi phân phối."]];
    }

    if (report.extensions.count > 0) {
        hasWarning = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityWarning
                                                             code:@"EMBEDDED_EXTENSIONS"
                                                            title:[NSString stringWithFormat:@"Có %lu App Extension (.appex)", (unsigned long)report.extensions.count]
                                                           detail:@"Extension phải có Bundle ID khớp tiền tố với ứng dụng chính và yêu cầu chữ ký/entitlement tương ứng."]];
    }

    // Known third-party server-verified platforms warning (honest disclosure, no bypass)
    NSString *lowerBID = report.bundleID.lowercaseString ?: @"";
    if ([lowerBID hasPrefix:@"com.facebook."] ||
        [lowerBID hasPrefix:@"vn.com.vng.zalo"] ||
        [lowerBID hasPrefix:@"com.zing.zalo"] ||
        [lowerBID hasPrefix:@"com.zhiliaoapp.musically"] ||
        [lowerBID hasPrefix:@"com.ss.iphone.ugc."]) {
        hasWarning = YES;
        [issues addObject:[MCCompatibilityIssue issueWithSeverity:MCCompatibilitySeverityWarning
                                                             code:@"THIRD_PARTY_SERVER_VERIFICATION"
                                                            title:@"Ứng dụng bên thứ ba có xác minh máy chủ / toàn vẹn"
                                                           detail:@"Ứng dụng này có thể kiểm tra chữ ký, Bundle ID, App Attest hoặc thiết bị phía máy chủ. MultiClone KHÔNG bypass cơ chế bảo vệ hoặc chống gian lận; bản clone có thể không đăng nhập hoặc hoạt động hạn chế."]];
    }

    if (hasBlocker) {
        report.compatibilityStatus = MCCompatibilityStatusIncompatible;
        report.compatibilitySummary = @"Không tương thích để clone (phát hiện yếu tố chặn như DRM hoặc kiến trúc/Bundle ID không hợp lệ).";
    } else if (hasWarning) {
        report.compatibilityStatus = MCCompatibilityStatusPartialWarning;
        report.compatibilitySummary = @"Có cảnh báo tương thích (Entitlements, Extension hoặc xác minh máy chủ). Chỉ tiếp tục với ứng dụng bạn có quyền chỉnh sửa.";
    } else {
        report.compatibilityStatus = MCCompatibilityStatusCompatible;
        report.compatibilitySummary = @"Tương thích cơ bản (không phát hiện FairPlay DRM hay entitlement hạn chế).";
    }
    report.issues = [issues copy];
}

@end
