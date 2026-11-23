#import "MCModels.h"

@implementation MCExtensionInfo

- (NSDictionary *)toDictionary {
    return @{
        @"relativePath": self.relativePath ?: @"",
        @"bundleID": self.bundleID ?: @"",
        @"displayName": self.displayName ?: @"",
        @"extensionPointIdentifier": self.extensionPointIdentifier ?: @""
    };
}

@end

@implementation MCCompatibilityIssue

+ (instancetype)issueWithSeverity:(MCCompatibilitySeverity)severity
                             code:(NSString *)code
                            title:(NSString *)title
                           detail:(NSString *)detail {
    MCCompatibilityIssue *issue = [[MCCompatibilityIssue alloc] init];
    issue.severity = severity;
    issue.code = code;
    issue.title = title;
    issue.detail = detail;
    return issue;
}

- (NSDictionary *)toDictionary {
    NSString *sev = @"info";
    if (self.severity == MCCompatibilitySeverityWarning) sev = @"warning";
    else if (self.severity == MCCompatibilitySeverityBlocker) sev = @"blocker";
    return @{
        @"severity": sev,
        @"code": self.code ?: @"",
        @"title": self.title ?: @"",
        @"detail": self.detail ?: @""
    };
}

@end

@implementation MCIPAInspectionReport

- (instancetype)init {
    self = [super init];
    if (self) {
        _supportedPlatforms = @[];
        _urlSchemes = @[];
        _architectures = @[];
        _frameworks = @[];
        _extensions = @[];
        _issues = @[];
        _compatibilityStatus = MCCompatibilityStatusPartialWarning;
        _compatibilitySummary = @"";
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableArray *extArr = [NSMutableArray array];
    for (MCExtensionInfo *ext in self.extensions) {
        [extArr addObject:[ext toDictionary]];
    }
    NSMutableArray *issueArr = [NSMutableArray array];
    for (MCCompatibilityIssue *issue in self.issues) {
        [issueArr addObject:[issue toDictionary]];
    }
    NSString *statusStr = @"warning";
    if (self.compatibilityStatus == MCCompatibilityStatusCompatible) statusStr = @"compatible";
    else if (self.compatibilityStatus == MCCompatibilityStatusIncompatible) statusStr = @"incompatible";

    return @{
        @"ipaPath": self.ipaPath ?: @"",
        @"bundleID": self.bundleID ?: @"",
        @"displayName": self.displayName ?: @"",
        @"shortVersion": self.shortVersion ?: @"",
        @"buildVersion": self.buildVersion ?: @"",
        @"executableName": self.executableName ?: @"",
        @"minimumOSVersion": self.minimumOSVersion ?: @"",
        @"supportedPlatforms": self.supportedPlatforms ?: @[],
        @"urlSchemes": self.urlSchemes ?: @[],
        @"architectures": self.architectures ?: @[],
        @"frameworks": self.frameworks ?: @[],
        @"extensions": extArr,
        @"hasEmbeddedProvisioningProfile": @(self.hasEmbeddedProvisioningProfile),
        @"isFairPlayEncrypted": @(self.isFairPlayEncrypted),
        @"encryptionCryptID": @(self.encryptionCryptID),
        @"entitlementKeys": self.entitlements ? self.entitlements.allKeys : @[],
        @"compatibilityStatus": statusStr,
        @"compatibilitySummary": self.compatibilitySummary ?: @"",
        @"issues": issueArr
    };
}

@end

@implementation MCInstalledAppInfo
@end

@implementation MCStorageUsage

- (unsigned long long)totalBytes {
    return self.bundleBytes + self.dataBytes + self.cacheBytes;
}

- (NSString *)formattedTotalSize {
    return [MCStorageUsage formatBytes:self.totalBytes];
}

+ (NSString *)formatBytes:(unsigned long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

@end

@implementation MCCloneRecord

- (instancetype)init {
    self = [super init];
    if (self) {
        _cloneID = [NSUUID UUID].UUIDString;
        _compatibilityWarnings = @[];
        _createdAt = [NSDate date];
        _updatedAt = _createdAt;
        _status = MCCloneStatusConfigured;
        _compatibilityStatus = MCCompatibilityStatusPartialWarning;
    }
    return self;
}

+ (nullable instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *cloneID = dict[@"cloneID"];
    NSString *cloneBundleID = dict[@"cloneBundleID"];
    if (![cloneID isKindOfClass:[NSString class]] || ![cloneBundleID isKindOfClass:[NSString class]]) {
        return nil;
    }
    MCCloneRecord *rec = [[MCCloneRecord alloc] init];
    rec.cloneID = cloneID;
    rec.sourceBundleID = [dict[@"sourceBundleID"] isKindOfClass:[NSString class]] ? dict[@"sourceBundleID"] : @"";
    rec.cloneBundleID = cloneBundleID;
    rec.displayName = [dict[@"displayName"] isKindOfClass:[NSString class]] ? dict[@"displayName"] : cloneBundleID;
    rec.sourceVersion = [dict[@"sourceVersion"] isKindOfClass:[NSString class]] ? dict[@"sourceVersion"] : nil;
    rec.sourceIPAPath = [dict[@"sourceIPAPath"] isKindOfClass:[NSString class]] ? dict[@"sourceIPAPath"] : nil;
    rec.cloneDirectoryPath = [dict[@"cloneDirectoryPath"] isKindOfClass:[NSString class]] ? dict[@"cloneDirectoryPath"] : @"";
    rec.bundlePath = [dict[@"bundlePath"] isKindOfClass:[NSString class]] ? dict[@"bundlePath"] : @"";
    rec.isolatedDataPath = [dict[@"isolatedDataPath"] isKindOfClass:[NSString class]] ? dict[@"isolatedDataPath"] : @"";
    rec.exportedIPAPath = [dict[@"exportedIPAPath"] isKindOfClass:[NSString class]] ? dict[@"exportedIPAPath"] : nil;
    rec.customIconPath = [dict[@"customIconPath"] isKindOfClass:[NSString class]] ? dict[@"customIconPath"] : nil;
    rec.status = [dict[@"status"] respondsToSelector:@selector(integerValue)] ? [dict[@"status"] integerValue] : MCCloneStatusConfigured;
    rec.compatibilityStatus = [dict[@"compatibilityStatus"] respondsToSelector:@selector(integerValue)]
        ? [dict[@"compatibilityStatus"] integerValue] : MCCompatibilityStatusPartialWarning;
    rec.compatibilityWarnings = [dict[@"compatibilityWarnings"] isKindOfClass:[NSArray class]] ? dict[@"compatibilityWarnings"] : @[];

    NSNumber *createdTs = dict[@"createdAt"];
    NSNumber *updatedTs = dict[@"updatedAt"];
    NSNumber *openedTs = dict[@"lastOpenedAt"];
    if ([createdTs isKindOfClass:[NSNumber class]]) rec.createdAt = [NSDate dateWithTimeIntervalSince1970:createdTs.doubleValue];
    if ([updatedTs isKindOfClass:[NSNumber class]]) rec.updatedAt = [NSDate dateWithTimeIntervalSince1970:updatedTs.doubleValue];
    if ([openedTs isKindOfClass:[NSNumber class]]) rec.lastOpenedAt = [NSDate dateWithTimeIntervalSince1970:openedTs.doubleValue];
    return rec;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *d = [@{
        @"cloneID": self.cloneID ?: @"",
        @"sourceBundleID": self.sourceBundleID ?: @"",
        @"cloneBundleID": self.cloneBundleID ?: @"",
        @"displayName": self.displayName ?: @"",
        @"cloneDirectoryPath": self.cloneDirectoryPath ?: @"",
        @"bundlePath": self.bundlePath ?: @"",
        @"isolatedDataPath": self.isolatedDataPath ?: @"",
        @"status": @(self.status),
        @"compatibilityStatus": @(self.compatibilityStatus),
        @"compatibilityWarnings": self.compatibilityWarnings ?: @[],
        @"createdAt": @(self.createdAt.timeIntervalSince1970),
        @"updatedAt": @(self.updatedAt.timeIntervalSince1970)
    } mutableCopy];
    if (self.sourceVersion) d[@"sourceVersion"] = self.sourceVersion;
    if (self.sourceIPAPath) d[@"sourceIPAPath"] = self.sourceIPAPath;
    if (self.exportedIPAPath) d[@"exportedIPAPath"] = self.exportedIPAPath;
    if (self.customIconPath) d[@"customIconPath"] = self.customIconPath;
    if (self.lastOpenedAt) d[@"lastOpenedAt"] = @(self.lastOpenedAt.timeIntervalSince1970);
    return [d copy];
}

- (NSString *)statusDisplayString {
    switch (self.status) {
        case MCCloneStatusInstalled: return @"Đã cài đặt";
        case MCCloneStatusExported:  return @"Đã xuất IPA";
        case MCCloneStatusError:     return @"Lỗi cấu hình";
        case MCCloneStatusConfigured:
        default:                     return @"Đã cấu hình";
    }
}

@end
