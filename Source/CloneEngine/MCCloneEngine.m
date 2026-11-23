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

@implementation MCBatchCloneConfiguration
- (instancetype)init {
    self = [super init];
    if (self) {
        _cloneCount = 1;
        _exportClonedIPA = YES;
        _alsoExportOriginalExtractedIPA = NO;
    }
    return self;
}
@end

@implementation MCBatchCloneResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _createdRecords = @[];
        _failureMessages = @[];
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

- (NSUInteger)nextSequenceNumberForSource:(NSString *)sourceBundleID {
    NSUInteger countForSource = 0;
    for (MCCloneRecord *rec in [[MCDataManager sharedManager] allClones]) {
        if ([rec.sourceBundleID caseInsensitiveCompare:sourceBundleID ?: @""] == NSOrderedSame) {
            countForSource++;
        }
    }
    return countForSource + 1;
}

- (NSString *)formattedNumberedNameWithBase:(NSString *)baseName sequenceNumber:(NSUInteger)seq {
    NSString *trimmed = [baseName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) trimmed = @"app";
    return [NSString stringWithFormat:@"%lu_%@", (unsigned long)MAX((NSUInteger)1, seq), trimmed];
}

- (NSString *)mc_suggestNextBundleIDForSource:(NSString *)sourceBundleID excluding:(NSSet<NSString *> *)extraUsed {
    NSString *base = MCIsValidBundleIdentifier(sourceBundleID) ? sourceBundleID : @"com.multiclone.app";
    NSMutableSet<NSString *> *used = [NSMutableSet setWithSet:extraUsed ?: [NSSet set]];
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

- (NSString *)suggestNextBundleIDForSource:(NSString *)sourceBundleID {
    return [self mc_suggestNextBundleIDForSource:sourceBundleID excluding:nil];
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
    NSString *ldidPath = [MCPrivateAPIBridge pathForToolNamed:@"ldid"];
    if (ldidPath.length == 0) return;

    NSString *out = nil;
    NSError *err = nil;
    int code = [MCPrivateAPIBridge runToolAtPath:ldidPath arguments:@[@"-S", appPath] output:&out error:&err];
    if (code == 0) {
        [[MCLogger sharedLogger] info:@"CloneEngine" format:@"Ad-hoc signed staged clone bundle with ldid."];
    } else {
        [[MCLogger sharedLogger] warn:@"CloneEngine" format:@"ldid returned code %d (%@); continuing.",
            code, err.localizedDescription ?: out ?: @""];
    }
}

- (void)mc_reportProgress:(void (^ _Nullable)(double, NSString *))handler fraction:(double)f stage:(NSString *)stage {
    if (!handler) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(MIN(1.0, MAX(0.0, f)), stage);
    });
}

/// Prepares a clean Payload/<App>.app directory inside baseStagingDir from either an .ipa or installed .app bundle.
- (nullable NSString *)mc_prepareSourceAppInStaging:(NSString *)baseStagingDir
                                             report:(MCIPAInspectionReport *)report
                                           progress:(void (^ _Nullable)(double, NSString *))progressHandler
                                       progressBase:(double)pBase
                                       progressSpan:(double)pSpan
                                              error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:baseStagingDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }

    if (report.isFromInstalledAppBundle && report.sourceAppBundlePath.length > 0) {
        [self mc_reportProgress:progressHandler fraction:pBase stage:@"Đang trích xuất trực tiếp từ thư mục .app gốc (chỉ đọc)..."];
        NSString *payloadDir = [baseStagingDir stringByAppendingPathComponent:@"Payload"];
        if (![fm createDirectoryAtPath:payloadDir withIntermediateDirectories:YES attributes:nil error:error]) {
            return nil;
        }
        NSString *destApp = [payloadDir stringByAppendingPathComponent:report.sourceAppBundlePath.lastPathComponent];
        if (![fm copyItemAtPath:report.sourceAppBundlePath toPath:destApp error:error]) {
            return nil;
        }
        [self mc_reportProgress:progressHandler fraction:(pBase + pSpan) stage:@"Đã trích xuất bản sao sạch từ ứng dụng gốc."];
        return destApp;
    }

    if (report.ipaPath.length == 0) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidArgument, @"Không có tệp IPA hoặc đường dẫn ứng dụng gốc.");
        return nil;
    }

    MCZipArchive *archive = [MCZipArchive archiveWithPath:report.ipaPath error:error];
    if (!archive) return nil;

    BOOL extracted = [archive extractAllToDirectory:baseStagingDir progress:^(double f) {
        [self mc_reportProgress:progressHandler fraction:(pBase + f * pSpan) stage:@"Đang giải nén tệp IPA (an toàn Zip Slip)..."];
    } error:error];
    if (!extracted) return nil;

    NSString *payloadDir = [baseStagingDir stringByAppendingPathComponent:@"Payload"];
    for (NSString *item in ([fm contentsOfDirectoryAtPath:payloadDir error:error] ?: @[])) {
        if ([item.lowercaseString hasSuffix:@".app"]) {
            return [payloadDir stringByAppendingPathComponent:item];
        }
    }
    if (error) *error = MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Không tìm thấy thư mục .app trong Payload/.");
    return nil;
}

/// Builds a single clone transactionally from an already-staged Payload/<App>.app template.
- (nullable MCCloneRecord *)mc_buildOneCloneFromTemplateApp:(NSString *)templateAppPath
                                                     report:(MCIPAInspectionReport *)report
                                                displayName:(NSString *)displayName
                                             targetBundleID:(NSString *)targetBundleID
                                                 customIcon:(nullable UIImage *)customIcon
                                            exportClonedIPA:(BOOL)exportClonedIPA
                                                      error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
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
    };

    NSString *payloadDir = [txStagingDir stringByAppendingPathComponent:@"Payload"];
    if (![fm createDirectoryAtPath:payloadDir withIntermediateDirectories:YES attributes:nil error:error]) {
        rollback();
        return nil;
    }

    NSString *appFolderName = templateAppPath.lastPathComponent;
    NSString *stagedAppPath = [payloadDir stringByAppendingPathComponent:appFolderName];
    if (![fm copyItemAtPath:templateAppPath toPath:stagedAppPath error:error]) {
        rollback();
        return nil;
    }

    NSString *infoPlistPath = [stagedAppPath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPlistPath];
    if (!info) {
        rollback();
        if (error) *error = MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Không thể đọc Info.plist trong bản staging.");
        return nil;
    }

    info[@"CFBundleIdentifier"] = targetBundleID;
    info[@"CFBundleDisplayName"] = displayName;
    info[@"CFBundleName"] = displayName;
    info[@"MultiCloneSourceBundleID"] = report.bundleID ?: @"";
    info[@"MultiCloneInstanceID"] = cloneID;

    NSData *updatedPlist = [NSPropertyListSerialization dataWithPropertyList:info
                                                                      format:NSPropertyListXMLFormat_v1_0
                                                                     options:0
                                                                       error:error];
    if (!updatedPlist || ![updatedPlist writeToFile:infoPlistPath options:NSDataWritingAtomic error:error]) {
        rollback();
        return nil;
    }

    if (![self mc_patchExtensionBundlesInApp:stagedAppPath
                              sourceBundleID:report.bundleID
                              targetBundleID:targetBundleID
                                       error:error]) {
        rollback();
        return nil;
    }

    // Remove stale signature & provisioning from staged clone copy ONLY (original untouched)
    for (NSString *stale in @[@"_CodeSignature", @"embedded.mobileprovision", @"SC_Info"]) {
        NSString *p = [stagedAppPath stringByAppendingPathComponent:stale];
        if (MCIsPathStrictlyInsideDirectory(p, txStagingDir) && [fm fileExistsAtPath:p]) {
            [fm removeItemAtPath:p error:nil];
        }
    }

    // Icon handling
    NSString *savedIconPath = nil;
    if (customIcon) {
        savedIconPath = [[MCIconManager sharedManager] saveCustomIconImage:customIcon forCloneID:cloneID error:error];
        if (!savedIconPath || ![[MCIconManager sharedManager] applyCustomIcon:customIcon toAppBundle:stagedAppPath error:error]) {
            rollback();
            return nil;
        }
    } else if (report.iconPNGData.length > 0) {
        UIImage *extractedImg = [[MCIconManager sharedManager] imageFromPNGData:report.iconPNGData];
        if (extractedImg) {
            savedIconPath = [[MCIconManager sharedManager] saveCustomIconImage:extractedImg forCloneID:cloneID error:nil];
        }
    }

    [self mc_attemptSafeAdHocSigningAtBundle:stagedAppPath];

    // Export clone IPA with readable name (e.g. 1_tiktok.ipa)
    if (exportClonedIPA) {
        NSString *safeName = [[displayName componentsSeparatedByCharactersInSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."] invertedSet]]
            componentsJoinedByString:@"_"];
        if (safeName.length == 0) safeName = targetBundleID;
        NSString *ipaFileName = [NSString stringWithFormat:@"%@.ipa", safeName];
        exportedIPAPath = [MCExportsDirectory() stringByAppendingPathComponent:ipaFileName];
        if ([fm fileExistsAtPath:exportedIPAPath]) {
            ipaFileName = [NSString stringWithFormat:@"%@_%@.ipa", safeName, [cloneID substringToIndex:6]];
            exportedIPAPath = [MCExportsDirectory() stringByAppendingPathComponent:ipaFileName];
        }
        if (![MCZipArchive createArchiveAtPath:exportedIPAPath fromRootDirectory:txStagingDir error:error]) {
            rollback();
            return nil;
        }
    }

    if (![fm createDirectoryAtPath:finalCloneDir withIntermediateDirectories:YES attributes:nil error:error]) {
        rollback();
        return nil;
    }
    NSString *finalAppPath = [finalCloneDir stringByAppendingPathComponent:appFolderName];
    if (![fm moveItemAtPath:stagedAppPath toPath:finalAppPath error:error]) {
        rollback();
        return nil;
    }

    NSString *isolatedDataDir = [finalCloneDir stringByAppendingPathComponent:@"Data"];
    for (NSString *sub in @[@"Documents", @"Library/Preferences", @"Library/Caches", @"tmp"]) {
        NSString *p = [isolatedDataDir stringByAppendingPathComponent:sub];
        if (![fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:error]) {
            rollback();
            return nil;
        }
    }

    if (MCIsPathStrictlyInsideDirectory(txStagingDir, MCStagingDirectory())) {
        [fm removeItemAtPath:txStagingDir error:nil];
    }

    NSMutableArray<NSString *> *warnTexts = [NSMutableArray array];
    for (MCCompatibilityIssue *issue in report.issues) {
        if (issue.severity == MCCompatibilitySeverityWarning) {
            [warnTexts addObject:[NSString stringWithFormat:@"%@: %@", issue.title, issue.detail]];
        }
    }

    MCCloneRecord *record = [[MCCloneRecord alloc] init];
    record.cloneID = cloneID;
    record.sourceBundleID = report.bundleID;
    record.cloneBundleID = targetBundleID;
    record.displayName = displayName;
    record.sourceVersion = report.shortVersion;
    record.sourceIPAPath = report.isFromInstalledAppBundle ? report.sourceAppBundlePath : report.ipaPath;
    record.cloneDirectoryPath = finalCloneDir;
    record.bundlePath = finalAppPath;
    record.isolatedDataPath = isolatedDataDir;
    record.exportedIPAPath = exportedIPAPath;
    record.customIconPath = savedIconPath;
    record.status = exportedIPAPath ? MCCloneStatusExported : MCCloneStatusConfigured;
    record.compatibilityStatus = report.compatibilityStatus;
    record.compatibilityWarnings = [warnTexts copy];

    if (![[MCDataManager sharedManager] saveCloneRecord:record error:error]) {
        rollback();
        return nil;
    }

    [[MCLogger sharedLogger] info:@"CloneEngine" format:@"Created clone %@ (%@) from %@",
        record.displayName, record.cloneBundleID, record.sourceBundleID];
    return record;
}

- (void)extractIPAFromInstalledAppReport:(MCIPAInspectionReport *)report
                                progress:(void (^ _Nullable)(double fraction, NSString *stage))progressHandler
                              completion:(void (^)(NSString * _Nullable ipaPath, NSError * _Nullable error))completion {
    dispatch_async(self.buildQueue, ^{
        NSError *err = nil;
        void (^finish)(NSString *, NSError *) = ^(NSString *p, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(p, e); });
        };

        if (!report || !report.isFromInstalledAppBundle || report.sourceAppBundlePath.length == 0) {
            finish(nil, MCMakeError(MCErrorCodeInvalidArgument, @"Chưa chọn ứng dụng gốc đã cài để trích xuất IPA."));
            return;
        }
        if (report.isFairPlayEncrypted) {
            finish(nil, MCMakeError(MCErrorCodeIPADRMProtected,
                @"Ứng dụng này có mã hóa FairPlay DRM (cryptid != 0). MultiClone không bypass DRM."));
            return;
        }

        NSString *tmpStage = [MCStagingDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"extract_%@", [NSUUID UUID].UUIDString]];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *stagedApp = [self mc_prepareSourceAppInStaging:tmpStage report:report progress:progressHandler progressBase:0.1 progressSpan:0.4 error:&err];
        if (!stagedApp) {
            if (MCIsPathStrictlyInsideDirectory(tmpStage, MCStagingDirectory())) [fm removeItemAtPath:tmpStage error:nil];
            finish(nil, err);
            return;
        }

        [self mc_reportProgress:progressHandler fraction:0.65 stage:@"Đang đóng gói IPA trích xuất vào thư mục Exports..."];
        NSString *ipaName = [NSString stringWithFormat:@"%@_extracted.ipa", report.bundleID ?: @"app"];
        NSString *outPath = [MCExportsDirectory() stringByAppendingPathComponent:ipaName];
        BOOL ok = [MCZipArchive createArchiveAtPath:outPath fromRootDirectory:tmpStage error:&err];
        if (MCIsPathStrictlyInsideDirectory(tmpStage, MCStagingDirectory())) [fm removeItemAtPath:tmpStage error:nil];

        if (!ok) {
            finish(nil, err);
            return;
        }
        [self mc_reportProgress:progressHandler fraction:1.0 stage:@"Trích xuất IPA thành công!"];
        [[MCLogger sharedLogger] info:@"CloneEngine" format:@"Extracted IPA from installed app %@ -> %@", report.bundleID, outPath.lastPathComponent];
        finish(outPath, nil);
    });
}

- (void)createCloneWithConfiguration:(MCCloneConfiguration *)config
                            progress:(void (^ _Nullable)(double fraction, NSString *stageDescription))progressHandler
                          completion:(void (^)(MCCloneRecord * _Nullable record, NSError * _Nullable error))completion {
    MCBatchCloneConfiguration *batch = [[MCBatchCloneConfiguration alloc] init];
    batch.inspectionReport = config.inspectionReport;
    batch.baseDisplayName = config.displayName;
    batch.customSingleBundleID = config.targetBundleID;
    batch.cloneCount = 1;
    batch.customIcon = config.customIcon;
    batch.acknowledgeWarnings = config.acknowledgeWarnings;
    batch.exportClonedIPA = config.exportClonedIPA;

    [self createBatchClonesWithConfiguration:batch progress:progressHandler completion:^(MCBatchCloneResult * _Nullable res, NSError * _Nullable err) {
        if (err || !res || res.createdRecords.count == 0) {
            NSString *msg = err.localizedDescription ?: res.failureMessages.firstObject ?: @"Tạo bản clone thất bại.";
            completion(nil, err ?: MCMakeError(MCErrorCodeStagingFailed, msg));
            return;
        }
        completion(res.createdRecords.firstObject, nil);
    }];
}

- (void)createBatchClonesWithConfiguration:(MCBatchCloneConfiguration *)config
                                  progress:(void (^ _Nullable)(double fraction, NSString *stageDescription))progressHandler
                                completion:(void (^)(MCBatchCloneResult * _Nullable result, NSError * _Nullable error))completion {
    dispatch_async(self.buildQueue, ^{
        NSError *err = nil;
        NSFileManager *fm = [NSFileManager defaultManager];

        void (^finish)(MCBatchCloneResult *, NSError *) = ^(MCBatchCloneResult *res, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(res, e); });
        };

        MCIPAInspectionReport *report = config.inspectionReport;
        if (!report || (!report.isFromInstalledAppBundle && report.ipaPath.length == 0)) {
            finish(nil, MCMakeError(MCErrorCodeInvalidArgument, @"Chưa có tệp IPA hoặc ứng dụng gốc hợp lệ."));
            return;
        }
        if (report.compatibilityStatus == MCCompatibilityStatusIncompatible) {
            MCErrorCode code = report.isFairPlayEncrypted ? MCErrorCodeIPADRMProtected : MCErrorCodeIPAIncompatibleArchitecture;
            finish(nil, MCMakeError(code, report.compatibilitySummary ?: @"Ứng dụng không tương thích để nhân bản."));
            return;
        }
        if (report.compatibilityStatus == MCCompatibilityStatusPartialWarning && !config.acknowledgeWarnings) {
            finish(nil, MCMakeError(MCErrorCodeInvalidArgument, @"Cần xác nhận đã đọc cảnh báo tương thích trước khi tiếp tục."));
            return;
        }

        NSUInteger count = MAX((NSUInteger)1, config.cloneCount);
        NSString *baseName = [config.baseDisplayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (baseName.length == 0) {
            finish(nil, MCMakeError(MCErrorCodeInvalidArgument, @"Tên bản clone không được để trống."));
            return;
        }

        if (count == 1 && config.customSingleBundleID.length > 0) {
            if (![self validateTargetBundleID:config.customSingleBundleID sourceBundleID:report.bundleID error:&err]) {
                finish(nil, err);
                return;
            }
        }

        // Extract/copy source ONCE into a shared base staging folder for fast batch cloning
        NSString *sharedStage = [MCStagingDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"batch_%@", [NSUUID UUID].UUIDString]];
        NSString *templateApp = [self mc_prepareSourceAppInStaging:sharedStage
                                                            report:report
                                                          progress:progressHandler
                                                      progressBase:0.05
                                                      progressSpan:0.25
                                                             error:&err];
        if (!templateApp) {
            if (MCIsPathStrictlyInsideDirectory(sharedStage, MCStagingDirectory())) [fm removeItemAtPath:sharedStage error:nil];
            finish(nil, err);
            return;
        }

        MCBatchCloneResult *batchResult = [[MCBatchCloneResult alloc] init];

        // Optionally export extracted source IPA if sourced from installed app
        if (report.isFromInstalledAppBundle && config.alsoExportOriginalExtractedIPA) {
            [self mc_reportProgress:progressHandler fraction:0.32 stage:@"Đang lưu tệp IPA trích xuất từ app gốc..."];
            NSString *origName = [NSString stringWithFormat:@"%@_original_extracted.ipa", report.bundleID ?: @"app"];
            NSString *origDest = [MCExportsDirectory() stringByAppendingPathComponent:origName];
            if ([MCZipArchive createArchiveAtPath:origDest fromRootDirectory:sharedStage error:nil]) {
                batchResult.extractedSourceIPAPath = origDest;
            }
        }

        NSMutableArray<MCCloneRecord *> *created = [NSMutableArray arrayWithCapacity:count];
        NSMutableArray<NSString *> *failures = [NSMutableArray array];
        NSMutableSet<NSString *> *reservedIDs = [NSMutableSet set];
        NSUInteger startSeq = [self nextSequenceNumberForSource:report.bundleID];

        for (NSUInteger i = 0; i < count; i++) {
            @autoreleasepool {
                NSUInteger seq = startSeq + i;
                // If user already typed "1_tiktok" for single clone, preserve; otherwise format as "<seq>_<baseName>"
                NSString *cloneName = nil;
                if (count == 1 && [baseName rangeOfString:@"^[0-9]+_" options:NSRegularExpressionSearch].location != NSNotFound) {
                    cloneName = baseName;
                } else {
                    cloneName = [self formattedNumberedNameWithBase:baseName sequenceNumber:seq];
                }

                NSString *targetBID = (count == 1 && config.customSingleBundleID.length > 0)
                    ? config.customSingleBundleID
                    : [self mc_suggestNextBundleIDForSource:report.bundleID excluding:reservedIDs];
                [reservedIDs addObject:targetBID.lowercaseString];

                double frac = 0.35 + (0.62 * ((double)i / (double)count));
                [self mc_reportProgress:progressHandler
                               fraction:frac
                                  stage:[NSString stringWithFormat:@"[%lu/%lu] Đang tạo %@ (%@)...",
                                         (unsigned long)(i + 1), (unsigned long)count, cloneName, targetBID]];

                NSError *oneErr = nil;
                MCCloneRecord *rec = [self mc_buildOneCloneFromTemplateApp:templateApp
                                                                    report:report
                                                               displayName:cloneName
                                                            targetBundleID:targetBID
                                                                customIcon:config.customIcon
                                                           exportClonedIPA:config.exportClonedIPA
                                                                     error:&oneErr];
                if (rec) {
                    [created addObject:rec];
                } else {
                    [failures addObject:[NSString stringWithFormat:@"%@: %@", cloneName, oneErr.localizedDescription ?: @"Lỗi không xác định"]];
                }
            }
        }

        if (MCIsPathStrictlyInsideDirectory(sharedStage, MCStagingDirectory())) {
            [fm removeItemAtPath:sharedStage error:nil];
        }

        batchResult.createdRecords = [created copy];
        batchResult.failureMessages = [failures copy];
        [self mc_reportProgress:progressHandler fraction:1.0
                          stage:[NSString stringWithFormat:@"Hoàn thành: %lu/%lu bản clone!",
                                 (unsigned long)created.count, (unsigned long)count]];
        finish(batchResult, nil);
    });
}

@end
