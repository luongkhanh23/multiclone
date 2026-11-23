#import <Foundation/Foundation.h>
#import "../MultiCloneCore/MCModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Manages MultiClone's atomic JSON registry and isolated per-clone storage directories.
/// Enforces strict path containment inside MCManagedRootDirectory() so original apps and
/// system directories can never be modified or deleted.
@interface MCDataManager : NSObject

+ (instancetype)sharedManager;

- (NSArray<MCCloneRecord *> *)allClones;
- (nullable MCCloneRecord *)cloneWithID:(NSString *)cloneID;
- (nullable MCCloneRecord *)cloneWithBundleID:(NSString *)cloneBundleID;

- (BOOL)saveCloneRecord:(MCCloneRecord *)record error:(NSError * _Nullable * _Nullable)error;
- (BOOL)updateDisplayName:(NSString *)newName forCloneID:(NSString *)cloneID error:(NSError * _Nullable * _Nullable)error;
- (BOOL)markCloneOpened:(NSString *)cloneBundleID;

/// Computes exact disk usage (bundle, isolated data, cache) of a clone.
- (MCStorageUsage *)storageUsageForClone:(MCCloneRecord *)record;

/// Clears only the isolated cache directory of a clone (never touches original app).
- (BOOL)clearCacheForClone:(MCCloneRecord *)record error:(NSError * _Nullable * _Nullable)error;

/// Resets the isolated data container of a clone while preserving its bundle/config.
- (BOOL)resetIsolatedDataForClone:(MCCloneRecord *)record error:(NSError * _Nullable * _Nullable)error;

/// Safely deletes a clone's managed directory, cached icon, exported IPA, and registry entry.
- (BOOL)deleteCloneWithID:(NSString *)cloneID error:(NSError * _Nullable * _Nullable)error;

/// Exports clone configuration metadata JSON (without sensitive credentials) to Exports/.
- (nullable NSString *)exportConfigurationForClone:(MCCloneRecord *)record error:(NSError * _Nullable * _Nullable)error;

/// Removes all temporary staging folders left over from interrupted operations.
- (void)cleanupOrphanedStagingDirectories;

@end

NS_ASSUME_NONNULL_END
