#import "MCCloneEngine.h"
#import "../MultiCloneCore/MCConstants.h"
#import "../MultiCloneCore/MCZipArchive.h"
#import "../MultiCloneCore/MCPrivateAPIBridge.h"
#import "../DataManager/MCDataManager.h"
#import "../IconManager/MCIconManager.h"
#import "../Settings/MCSettingsManager.h"
#import "../Logger/MCLogger.h"

@implementation MCCloneConfiguration

- (instancetype)init {
    self = [super init];
    if (self) {
        _exportClonedIPA = YES;
    }
    return self;
}

@end

@interface MCCloneEngine ()
@property (nonatomic, strong) dispatch_queue_t buildQueue;
@end

@implementation MCCloneEngine

+ (instancetype)sharedEngine {
    static MCCloneEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MCCloneEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _buildQueue = dispatch_queue_create("com.multiclone.cloneengine", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)suggestNextBundleIDForSource:(NSString *)sourceBundleID {
    NSString *base = MCIsValidBundleIdentifier(sourceBundleID) ? sourceBundleID : @"com.multiclone.app";
    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (MCCloneRecord *rec in [[MCDataManager sharedManager] allClones]) {
        if (rec.cloneBundleID.length > 0) [used addObject:rec.cloneBundleID.lowercaseString];
    }
    NSUInteger index = 1;
    while (YES) {
        NSString *candidate = [NSString stringWithFormat:@"%@.multiclone.%03lu", base, (unsigned long)index];
        if (![used containsObject:candidate.lowercaseString] &&
            ![MCPrivateAPIBridge installedApplicationForBundleID:candidate]) {
            return candidate;
        }
        index++;
    }
}

- (BOOL)validateTargetBundleID:(NSString *)targetBundleID
                sourceBundleID:(NSString *)sourceBundleID
                         error:(NSError **)error {
    if (!MCIsValidBundleIdentifier(targetBundleID)) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidBundleID,
            @"Bundle ID mới không hợp lệ (cần định dạng reverse-DNS, ví dụ: com.example.app.multiclone.001).");
        return NO;
    }
    if (MCIsProtectedBundleIdentifier(targetBundleID)) {
        if (error) *error = MCMakeError(MCErrorCodeProtectedBundle,
            @"Không được sử dụng Bundle ID thuộc phạm vi hệ thống Apple hoặc công cụ jailbreak.");
        return NO;
    }
    if (sourceBundleID.length > 0 && [targetBundleID caseInsensitiveCompare:sourceBundleID] == NSOrderedSame) {
        if (error) *error = MCMakeError(MCErrorCodeBundleIDCollision,
            @"Bundle ID mới phải khác với Bundle ID ứng dụng gốc để không ghi đè ứng dụng gốc.");
        return NO;
    }
    if ([[MCDataManager sharedManager] cloneWithBundleID:targetBundleID] != nil) {
        if (error) *error = MCMakeError(MCErrorCodeBundleIDCollision,
            @"Bundle ID này đã được sử dụng bởi một bản clone khác.");
        return NO;
    }
    if ([MCPrivateAPIBridge installedApplicationForBundleID:targetBundleID] != nil) {
        if (error) *error = MCMakeError(MCErrorCodeBundleIDCollision,
            @"Bundle ID này trùng với một ứng dụng đang cài đặt trên thiết bị.");
        return NO;
    }
    return YES;
}

- (BOOL)mc_patchExtensionBundlesInApp:(NSString *)appPath
                        sourceBundleID:(NSString *)sourceBundleID
                        targetBundleID:(NSString *)targetBundleID
                                 error:(NSError **)error {
    NSString *pluginsDir = [appPath stringByAppendingPathComponent:@"PlugIns"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:pluginsDir]) return YES;

    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:pluginsDir error:nil];
    for (NSString *name in items) {
        if (![name.lowercaseString hasSuffix:@".appex"]) continue;
        NSString *extInfoPath = [[pluginsDir stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"Info.plist"];
        NSMutableDictionary *extInfo = [NSMutableDictionary dictionaryWithContentsOfFile:extInfoPath];
        if (!extInfo) continue;

        NSString *oldID = extInfo[@"CFBundleIdentifier"];
        if ([oldID isKindOfClass:[NSString class]] && oldID.length > 0) {
            NSString *newExtID = nil;
            if ([oldID hasPrefix:sourceBundleID]) {
                NSString *suffix = [oldID substringFromIndex:sourceBundleID.length];
                newExtID = [targetBundleID stringByAppendingString:suffix];
            } else {
                NSString *cleanName = [[name stringByDeletingPathExtension]
                    stringByReplacingOccurrencesOfString:@" " withString:@""];
                newExtID = [NSString stringWithFormat:@"%@.%@", targetBundleID, cleanName];
            }
            extInfo[@"CFBundleIdentifier"] = newExtID;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:extInfo
                                                                      format:NSPropertyListXMLFormat_v1_0
                                                                     options:0
                                                                       error:error];
            if (!data || ![data writeToFile:extInfoPath options:NSDataWritingAtomic error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

- (void)mc_attemptSafeAdHocSigningAtBundle:(NSString *)appPath {
    // Only uses local ldid if installed in rootless jailbreak environment.
    // Never forges restricted Apple entitlements or bypasses DRM.
    NSString *ldidPath = [MCPrivateAPIBridge pathForToolNamed:@"ldid"];
    if (ldidPath.length == 0) {
        [[MCLogger sharedLogger] info:@"CloneEngine" format:@"ldid not found; clone prepared for external signing/export."];
        return;
    }

    NSString *out = nil;
    NSError *err = nil;
    int code = [MCPrivateAPIBridge runToolAtPath:ldidPath arguments:@[@"-S", appPath] output:&out error:&err];
    if (code == 0) {
        [[MCLogger sharedLogger] info:@"CloneEngine" format:@"Ad-hoc signed staged clone bundle with ldid."];
    } else {
        [[MCLogger sharedLogger] warn:@"CloneEngine" format:@"ldid returned code %d (%@); continuing with export.",
            code, err.localizedDescription ?: out ?: @""];
    }
}

- (void)mc_reportProgress:(void (^ _Nullable)(double, NSString *))handler fraction:(double)f stage:(NSString *)stage {
    if (!handler) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(f, stage);
    });
}

- (void)createCloneWithConfiguration:(MCCloneConfiguration *)config
                            progress:(void (^ _Nullable)(double fraction, NSString *stageDescription))progressHandler
                          completion:(void (^)(MCCloneRecord * _Nullable record, NSError * _Nullable error))completion {
    dispatch_async(self.buildQueue, ^{
        NSError *err = nil;
        NSFileManager *fm = [NSFileManager defaultManager];

        void (^finish)(MCCloneRecord *, NSError *) = ^(MCCloneRecord *rec, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(rec, e);
            });
        };

        MCIPAInspectionReport *report = config.inspectionReport;
        if (!report || report.ipaPath.length == 0) {
            finish(nil, MCMakeError(MCErrorCodeInvalidArgument, @"Chưa có báo cáo phân tích IPA hợp lệ."));
            return;
        }

        if (report.compatibilityStatus == MCCompatibilityStatusIncompatible) {
            MCErrorCode code = report.isFairPlayEncrypted ? MCErrorCodeIPADRMProtected : MCErrorCodeIPAIncompatibleArchitecture;
            finish(nil, MCMakeError(code, report.compatibilitySummary ?: @"IPA không tương thích để tạo bản clone."));
            return;
        }

        if (report.compatibilityStatus == MCCompatibilityStatusPartialWarning && !config.acknowledgeWarnings) {
            finish(nil, MCMakeError(MCErrorCodeInvalidArgument, @"Cần xác nhận đã đọc cảnh báo tương thích trước khi tiếp tục."));
            return;
        }

        NSString *displayName = [config.displayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (displayName.length == 0) {
            finish(nil, MCMakeError(MCErrorCodeInvalidArgument, @"Tên hiển thị cho bản clone không được để trống."));
            return;
        }

        if (![self validateTargetBundleID:config.targetBundleID sourceBundleID:report.bundleID error:&err]) {
            finish(nil, err);
            return;
        }

        NSString *cloneID = [NSUUID UUID].UUIDString;
        NSString *txStagingDir = [MCStagingDirectory() stringByAppendingPathComponent:cloneID];
        NSString *finalCloneDir = [MCClonesDirectory() stringByAppendingPathComponent:cloneID];
        NSString *exportedIPAPath = nil;

        void (^rollback)(void) = ^{
            if (MCIsPathStrictlyInsideDirectory(txStagingDir, MCStagingDirectory())) {
                [fm removeItemAtPath:txStagingDir error:nil];
            }
            if (MCIsPathStrictlyInsideDirectory(finalCloneDir, MCClonesDirectory())) {
                [fm removeItemAtPath:finalCloneDir error:nil];
            }
            if (exportedIPAPath.length > 0 && MCIsPathStrictlyInsideDirectory(exportedIPAPath, MCExportsDirectory())) {
                [fm removeItemAtPath:exportedIPAPath error:nil];
            }
            [[MCIconManager sharedManager] deleteIconForCloneID:cloneID];
            [[MCLogger sharedLogger] warn:@"CloneEngine" format:@"Rolled back failed transaction %@", cloneID];
        };

        [self mc_reportProgress:progressHandler fraction:0.10 stage:@"Khởi tạo không gian tạm cô lập (staging)..."];
        if (![fm createDirectoryAtPath:txStagingDir withIntermediateDirectories:YES attributes:nil error:&err]) {
            rollback();
            finish(nil, err);
            return;
        }

        [self mc_reportProgress:progressHandler fraction:0.20 stage:@"Giải nén IPA an toàn (chống Zip Slip)..."];
        MCZipArchive *archive = [MCZipArchive archiveWithPath:report.ipaPath error:&err];
        if (!archive) {
            rollback();
            finish(nil, err);
            return;
        }
        BOOL extracted = [archive extractAllToDirectory:txStagingDir progress:^(double f) {
            [self mc_reportProgress:progressHandler fraction:(0.20 + f * 0.35) stage:@"Đang giải nén nội dung IPA..."];
        } error:&err];
        if (!extracted) {
            rollback();
            finish(nil, err);
            return;
        }

        // Locate extracted .app inside Payload/
        NSString *payloadDir = [txStagingDir stringByAppendingPathComponent:@"Payload"];
        NSArray<NSString *> *payloadItems = [fm contentsOfDirectoryAtPath:payloadDir error:&err];
        NSString *appFolderName = nil;
        for (NSString *item in payloadItems) {
            if ([item.lowercaseString hasSuffix:@".app"]) {
                appFolderName = item;
                break;
            }
        }
        if (!appFolderName) {
            rollback();
            finish(nil, MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Không tìm thấy thư mục .app sau khi giải nén."));
            return;
        }

        NSString *stagedAppPath = [payloadDir stringByAppendingPathComponent:appFolderName];
        NSString *infoPlistPath = [stagedAppPath stringByAppendingPathComponent:@"Info.plist"];

        [self mc_reportProgress:progressHandler fraction:0.60 stage:@"Cập nhật Bundle ID và tên hiển thị độc lập..."];
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPlistPath];
        if (!info) {
            rollback();
            finish(nil, MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Không thể đọc Info.plist trong bản staging."));
            return;
        }

        info[@"CFBundleIdentifier"] = config.targetBundleID;
        info[@"CFBundleDisplayName"] = displayName;
        info[@"CFBundleName"] = displayName;
        info[@"MultiCloneSourceBundleID"] = report.bundleID ?: @"";
        info[@"MultiCloneInstanceID"] = cloneID;

        NSData *updatedPlist = [NSPropertyListSerialization dataWithPropertyList:info
                                                                          format:NSPropertyListXMLFormat_v1_0
                                                                         options:0
                                                                           error:&err];
        if (!updatedPlist || ![updatedPlist writeToFile:infoPlistPath options:NSDataWritingAtomic error:&err]) {
            rollback();
            finish(nil, err);
            return;
        }

        // Patch nested .appex bundle IDs proportionally
        if (![self mc_patchExtensionBundlesInApp:stagedAppPath
                                  sourceBundleID:report.bundleID
                                  targetBundleID:config.targetBundleID
                                           error:&err]) {
            rollback();
            finish(nil, err);
            return;
        }

        // Remove stale original _CodeSignature & embedded.mobileprovision from staged copy only
        NSString *oldSig = [stagedAppPath stringByAppendingPathComponent:@"_CodeSignature"];
        if (MCIsPathStrictlyInsideDirectory(oldSig, txStagingDir)) {
            [fm removeItemAtPath:oldSig error:nil];
        }
        NSString *oldProv = [stagedAppPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
        if (MCIsPathStrictlyInsideDirectory(oldProv, txStagingDir)) {
            [fm removeItemAtPath:oldProv error:nil];
        }

        // Apply custom icon if provided
        NSString *savedIconPath = nil;
        if (config.customIcon) {
            [self mc_reportProgress:progressHandler fraction:0.70 stage:@"Áp dụng biểu tượng tùy chỉnh..."];
            savedIconPath = [[MCIconManager sharedManager] saveCustomIconImage:config.customIcon forCloneID:cloneID error:&err];
            if (!savedIconPath || ![[MCIconManager sharedManager] applyCustomIcon:config.customIcon toAppBundle:stagedAppPath error:&err]) {
                rollback();
                finish(nil, err);
                return;
            }
        } else if (report.iconPNGData.length > 0) {
            UIImage *extractedImg = [[MCIconManager sharedManager] imageFromPNGData:report.iconPNGData];
            if (extractedImg) {
                savedIconPath = [[MCIconManager sharedManager] saveCustomIconImage:extractedImg forCloneID:cloneID error:nil];
            }
        }

        [self mc_reportProgress:progressHandler fraction:0.78 stage:@"Chuẩn bị chữ ký cục bộ (ad-hoc nếu có ldid)..."];
        [self mc_attemptSafeAdHocSigningAtBundle:stagedAppPath];

        // Export cloned IPA if requested
        if (config.exportClonedIPA) {
            [self mc_reportProgress:progressHandler fraction:0.85 stage:@"Đóng gói bản clone IPA vào thư mục Exports..."];
            NSString *ipaFileName = [NSString stringWithFormat:@"%@.ipa", config.targetBundleID];
            exportedIPAPath = [MCExportsDirectory() stringByAppendingPathComponent:ipaFileName];
            if (![MCZipArchive createArchiveAtPath:exportedIPAPath fromRootDirectory:txStagingDir error:&err]) {
                rollback();
                finish(nil, err);
                return;
            }
        }

        // Commit atomically into MCClonesDirectory()/<cloneID>/
        [self mc_reportProgress:progressHandler fraction:0.93 stage:@"Hoàn tất và đăng ký dữ liệu cô lập..."];
        if (![fm createDirectoryAtPath:finalCloneDir withIntermediateDirectories:YES attributes:nil error:&err]) {
            rollback();
            finish(nil, err);
            return;
        }
        NSString *finalAppPath = [finalCloneDir stringByAppendingPathComponent:appFolderName];
        if (![fm moveItemAtPath:stagedAppPath toPath:finalAppPath error:&err]) {
            rollback();
            finish(nil, err);
            return;
        }

        NSString *isolatedDataDir = [finalCloneDir stringByAppendingPathComponent:@"Data"];
        for (NSString *sub in @[@"Documents", @"Library/Preferences", @"Library/Caches", @"tmp"]) {
            NSString *p = [isolatedDataDir stringByAppendingPathComponent:sub];
            if (![fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:&err]) {
                rollback();
                finish(nil, err);
                return;
            }
        }

        // Clean staging dir after atomic move
        if (MCIsPathStrictlyInsideDirectory(txStagingDir, MCStagingDirectory())) {
            [fm removeItemAtPath:txStagingDir error:nil];
        }

        // Collect warning summaries
        NSMutableArray<NSString *> *warnTexts = [NSMutableArray array];
        for (MCCompatibilityIssue *issue in report.issues) {
            if (issue.severity == MCCompatibilitySeverityWarning) {
                [warnTexts addObject:[NSString stringWithFormat:@"%@: %@", issue.title, issue.detail]];
            }
        }

        MCCloneRecord *record = [[MCCloneRecord alloc] init];
        record.cloneID = cloneID;
        record.sourceBundleID = report.bundleID;
        record.cloneBundleID = config.targetBundleID;
        record.displayName = displayName;
        record.sourceVersion = report.shortVersion;
        record.sourceIPAPath = report.ipaPath;
        record.cloneDirectoryPath = finalCloneDir;
        record.bundlePath = finalAppPath;
        record.isolatedDataPath = isolatedDataDir;
        record.exportedIPAPath = exportedIPAPath;
        record.customIconPath = savedIconPath;
        record.status = exportedIPAPath ? MCCloneStatusExported : MCCloneStatusConfigured;
        record.compatibilityStatus = report.compatibilityStatus;
        record.compatibilityWarnings = [warnTexts copy];

        if (![[MCDataManager sharedManager] saveCloneRecord:record error:&err]) {
            rollback();
            finish(nil, err);
            return;
        }

        [[MCLogger sharedLogger] info:@"CloneEngine" format:@"Created clone %@ (%@) from %@",
            record.displayName, record.cloneBundleID, record.sourceBundleID];
        [self mc_reportProgress:progressHandler fraction:1.0 stage:@"Hoàn thành tạo cấu hình clone!"];
        finish(record, nil);
    });
}

@end
