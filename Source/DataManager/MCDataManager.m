#import "MCDataManager.h"
#import "../MultiCloneCore/MCConstants.h"
#import "../IconManager/MCIconManager.h"
#import "../Settings/MCSettingsManager.h"
#import "../Logger/MCLogger.h"

@interface MCDataManager ()
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@end

@implementation MCDataManager

+ (instancetype)sharedManager {
    static MCDataManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MCDataManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ioQueue = dispatch_queue_create("com.multiclone.datamanager", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSMutableArray<MCCloneRecord *> *)mc_loadLocked {
    NSString *path = MCRegistryFilePath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return [NSMutableArray array];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return [NSMutableArray array];
    NSArray *items = obj[@"clones"];
    if (![items isKindOfClass:[NSArray class]]) return [NSMutableArray array];

    NSMutableArray<MCCloneRecord *> *records = [NSMutableArray arrayWithCapacity:items.count];
    for (id dict in items) {
        MCCloneRecord *rec = [MCCloneRecord fromDictionary:dict];
        if (rec) [records addObject:rec];
    }
    return records;
}

- (BOOL)mc_saveLocked:(NSArray<MCCloneRecord *> *)records error:(NSError **)error {
    NSMutableArray *serialized = [NSMutableArray arrayWithCapacity:records.count];
    NSMutableArray<NSString *> *managedIDs = [NSMutableArray arrayWithCapacity:records.count];
    for (MCCloneRecord *rec in records) {
        [serialized addObject:[rec toDictionary]];
        if (MCIsValidBundleIdentifier(rec.cloneBundleID) && !MCIsProtectedBundleIdentifier(rec.cloneBundleID)) {
            [managedIDs addObject:rec.cloneBundleID];
        }
    }

    NSDictionary *root = @{
        @"schema": @2,
        @"product": @"MultiClone",
        @"version": MCProductVersion,
        @"clones": serialized
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:error];
    if (!json) return NO;

    NSString *registryPath = MCRegistryFilePath();
    BOOL ok = [json writeToFile:registryPath options:NSDataWritingAtomic error:error];
    if (ok) {
        [[NSFileManager defaultManager] setAttributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                         ofItemAtPath:registryPath
                                                error:nil];
        [[MCSettingsManager sharedManager] setManagedCloneBundleIDs:managedIDs];
    }
    return ok;
}

- (NSArray<MCCloneRecord *> *)allClones {
    __block NSArray<MCCloneRecord *> *result = @[];
    dispatch_sync(self.ioQueue, ^{
        result = [[self mc_loadLocked] copy];
    });
    return result;
}

- (nullable MCCloneRecord *)cloneWithID:(NSString *)cloneID {
    if (cloneID.length == 0) return nil;
    for (MCCloneRecord *rec in [self allClones]) {
        if ([rec.cloneID isEqualToString:cloneID]) return rec;
    }
    return nil;
}

- (nullable MCCloneRecord *)cloneWithBundleID:(NSString *)cloneBundleID {
    if (cloneBundleID.length == 0) return nil;
    for (MCCloneRecord *rec in [self allClones]) {
        if ([rec.cloneBundleID isEqualToString:cloneBundleID]) return rec;
    }
    return nil;
}

- (BOOL)saveCloneRecord:(MCCloneRecord *)record error:(NSError **)error {
    if (!record || !MCIsValidBundleIdentifier(record.cloneBundleID)) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidBundleID, @"Bản ghi clone không hợp lệ.");
        return NO;
    }
    __block BOOL ok = NO;
    __block NSError *localErr = nil;
    dispatch_sync(self.ioQueue, ^{
        NSMutableArray<MCCloneRecord *> *all = [self mc_loadLocked];
        NSUInteger idx = [all indexOfObjectPassingTest:^BOOL(MCCloneRecord *obj, NSUInteger i, BOOL *stop) {
            (void)i; (void)stop;
            return [obj.cloneID isEqualToString:record.cloneID];
        }];
        record.updatedAt = [NSDate date];
        if (idx == NSNotFound) {
            [all addObject:record];
        } else {
            all[idx] = record;
        }
        ok = [self mc_saveLocked:all error:&localErr];
    });
    if (error && localErr) *error = localErr;
    return ok;
}

- (BOOL)updateDisplayName:(NSString *)newName forCloneID:(NSString *)cloneID error:(NSError **)error {
    NSString *trimmed = [newName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidArgument, @"Tên hiển thị không được để trống.");
        return NO;
    }
    MCCloneRecord *rec = [self cloneWithID:cloneID];
    if (!rec) {
        if (error) *error = MCMakeError(MCErrorCodeCloneNotFound, @"Không tìm thấy bản clone.");
        return NO;
    }

    // Also update staged/managed clone bundle Info.plist if inside MultiClone managed scope
    if (rec.bundlePath.length > 0 && MCIsPathStrictlyInsideDirectory(rec.bundlePath, MCManagedRootDirectory())) {
        NSString *infoPath = [rec.bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
        if (info) {
            info[@"CFBundleDisplayName"] = trimmed;
            info[@"CFBundleName"] = trimmed;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
            if (data) [data writeToFile:infoPath options:NSDataWritingAtomic error:nil];
        }
    }

    rec.displayName = trimmed;
    BOOL ok = [self saveCloneRecord:rec error:error];
    if (ok) {
        [[MCLogger sharedLogger] info:@"DataManager" format:@"Renamed clone %@ -> %@", rec.cloneBundleID, trimmed];
    }
    return ok;
}

- (BOOL)markCloneOpened:(NSString *)cloneBundleID {
    MCCloneRecord *rec = [self cloneWithBundleID:cloneBundleID];
    if (!rec) return NO;
    rec.lastOpenedAt = [NSDate date];
    return [self saveCloneRecord:rec error:nil];
}

- (unsigned long long)mc_directorySizeAtPath:(NSString *)dirPath {
    if (dirPath.length == 0) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dirPath isDirectory:&isDir]) return 0;
    if (!isDir) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:dirPath error:nil];
        return attrs ? [attrs fileSize] : 0;
    }

    unsigned long long total = 0;
    NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:dirPath]
                         includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey]
                                            options:0
                                       errorHandler:nil];
    for (NSURL *fileURL in en) {
        NSNumber *isRegular = nil;
        [fileURL getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        if (isRegular.boolValue) {
            NSNumber *size = nil;
            [fileURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            total += size.unsignedLongLongValue;
        }
    }
    return total;
}

- (MCStorageUsage *)storageUsageForClone:(MCCloneRecord *)record {
    MCStorageUsage *usage = [[MCStorageUsage alloc] init];
    if (!record) return usage;

    usage.bundleBytes = [self mc_directorySizeAtPath:record.bundlePath];
    if (record.exportedIPAPath.length > 0) {
        usage.bundleBytes += [self mc_directorySizeAtPath:record.exportedIPAPath];
    }

    NSString *cacheDir = [record.isolatedDataPath stringByAppendingPathComponent:@"Library/Caches"];
    usage.cacheBytes = [self mc_directorySizeAtPath:cacheDir];
    unsigned long long totalData = [self mc_directorySizeAtPath:record.isolatedDataPath];
    usage.dataBytes = (totalData >= usage.cacheBytes) ? (totalData - usage.cacheBytes) : 0;
    return usage;
}

- (BOOL)mc_safeRemovePath:(NSString *)targetPath error:(NSError **)error {
    if (targetPath.length == 0) return YES;
    if (!MCIsPathStrictlyInsideDirectory(targetPath, MCManagedRootDirectory())) {
        [[MCLogger sharedLogger] error:@"DataManager" format:@"BLOCKED deletion outside managed root: %@", targetPath];
        if (error) *error = MCMakeError(MCErrorCodePathOutsideManagedScope, @"Từ chối xóa đường dẫn nằm ngoài phạm vi quản lý MultiClone.");
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:targetPath]) return YES;
    return [fm removeItemAtPath:targetPath error:error];
}

- (BOOL)clearCacheForClone:(MCCloneRecord *)record error:(NSError **)error {
    if (!record || record.isolatedDataPath.length == 0) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidArgument, @"Không có thư mục dữ liệu độc lập cho bản clone.");
        return NO;
    }
    NSString *cacheDir = [record.isolatedDataPath stringByAppendingPathComponent:@"Library/Caches"];
    NSString *tmpDir = [record.isolatedDataPath stringByAppendingPathComponent:@"tmp"];
    if (![self mc_safeRemovePath:cacheDir error:error]) return NO;
    if (![self mc_safeRemovePath:tmpDir error:error]) return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
    [[MCLogger sharedLogger] info:@"DataManager" format:@"Cleared isolated cache for %@", record.cloneBundleID];
    return YES;
}

- (BOOL)resetIsolatedDataForClone:(MCCloneRecord *)record error:(NSError **)error {
    if (!record || record.isolatedDataPath.length == 0) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidArgument, @"Không có thư mục dữ liệu độc lập.");
        return NO;
    }
    if (![self mc_safeRemovePath:record.isolatedDataPath error:error]) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *sub in @[@"Documents", @"Library/Preferences", @"Library/Caches", @"tmp"]) {
        NSString *p = [record.isolatedDataPath stringByAppendingPathComponent:sub];
        [fm createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [[MCLogger sharedLogger] info:@"DataManager" format:@"Reset isolated data for %@", record.cloneBundleID];
    return YES;
}

- (BOOL)deleteCloneWithID:(NSString *)cloneID error:(NSError **)error {
    MCCloneRecord *rec = [self cloneWithID:cloneID];
    if (!rec) {
        if (error) *error = MCMakeError(MCErrorCodeCloneNotFound, @"Không tìm thấy bản clone cần xóa.");
        return NO;
    }

    if (rec.cloneDirectoryPath.length > 0) {
        if (![self mc_safeRemovePath:rec.cloneDirectoryPath error:error]) {
            return NO;
        }
    }
    if (rec.exportedIPAPath.length > 0 && MCIsPathStrictlyInsideDirectory(rec.exportedIPAPath, MCExportsDirectory())) {
        [self mc_safeRemovePath:rec.exportedIPAPath error:nil];
    }
    [[MCIconManager sharedManager] deleteIconForCloneID:rec.cloneID];

    __block BOOL ok = NO;
    __block NSError *localErr = nil;
    dispatch_sync(self.ioQueue, ^{
        NSMutableArray<MCCloneRecord *> *all = [self mc_loadLocked];
        [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MCCloneRecord *obj, NSDictionary *bindings) {
            (void)bindings;
            return ![obj.cloneID isEqualToString:cloneID];
        }]];
        ok = [self mc_saveLocked:all error:&localErr];
    });
    if (error && localErr) *error = localErr;
    if (ok) {
        [[MCSettingsManager sharedManager] unregisterManagedBundleID:rec.cloneBundleID];
        [[MCLogger sharedLogger] info:@"DataManager" format:@"Deleted clone %@", rec.cloneBundleID];
    }
    return ok;
}

- (nullable NSString *)exportConfigurationForClone:(MCCloneRecord *)record error:(NSError **)error {
    if (!record) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidArgument, @"Bản ghi clone rỗng.");
        return nil;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:[record toDictionary]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:error];
    if (!json) return nil;
    NSString *fileName = [NSString stringWithFormat:@"%@_config.json", record.cloneBundleID];
    NSString *dest = [MCExportsDirectory() stringByAppendingPathComponent:fileName];
    if (![json writeToFile:dest options:NSDataWritingAtomic error:error]) return nil;
    return dest;
}

- (void)cleanupOrphanedStagingDirectories {
    NSString *staging = MCStagingDirectory();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:staging error:nil];
    for (NSString *name in items) {
        NSString *full = [staging stringByAppendingPathComponent:name];
        if (MCIsPathStrictlyInsideDirectory(full, staging)) {
            [fm removeItemAtPath:full error:nil];
        }
    }
}

@end
