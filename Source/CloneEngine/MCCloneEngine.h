#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../MultiCloneCore/MCModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface MCCloneConfiguration : NSObject
@property (nonatomic, strong) MCIPAInspectionReport *inspectionReport;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *targetBundleID;
@property (nonatomic, strong, nullable) UIImage *customIcon;
@property (nonatomic, assign) BOOL acknowledgeWarnings;
@property (nonatomic, assign) BOOL exportClonedIPA;
@end

@interface MCBatchCloneConfiguration : NSObject
@property (nonatomic, strong) MCIPAInspectionReport *inspectionReport;
/// Base suffix name, e.g. "tiktok" -> generates "1_tiktok", "2_tiktok", "3_tiktok"...
@property (nonatomic, copy) NSString *baseDisplayName;
/// Optional custom Bundle ID for single clone (count == 1). For count > 1, sequential unique IDs are generated.
@property (nonatomic, copy, nullable) NSString *customSingleBundleID;
/// Number of clones to create in one batch (e.g. 1, 3, 5, 10, ...; no artificial limit).
@property (nonatomic, assign) NSUInteger cloneCount;
@property (nonatomic, strong, nullable) UIImage *customIcon;
@property (nonatomic, assign) BOOL acknowledgeWarnings;
@property (nonatomic, assign) BOOL exportClonedIPA;
@property (nonatomic, assign) BOOL alsoExportOriginalExtractedIPA;
@end

@interface MCBatchCloneResult : NSObject
@property (nonatomic, copy) NSArray<MCCloneRecord *> *createdRecords;
@property (nonatomic, copy) NSArray<NSString *> *failureMessages;
@property (nonatomic, copy, nullable) NSString *extractedSourceIPAPath;
@end

/// Transactional single & batch clone builder supporting BOTH .ipa files and direct
/// extraction from installed unencrypted .app bundles on-device.
/// Never modifies original app bundles or original app data containers.
/// Never bypasses FairPlay DRM, anti-cheat, or third-party server verification.
@interface MCCloneEngine : NSObject

+ (instancetype)sharedEngine;

/// Suggests the next sequential clone number for a source Bundle ID (1, 2, 3, ...).
- (NSUInteger)nextSequenceNumberForSource:(NSString *)sourceBundleID;

/// Formats numbered clone name like "1_tiktok", "2_tiktok", ...
- (NSString *)formattedNumberedNameWithBase:(NSString *)baseName sequenceNumber:(NSUInteger)seq;

/// Suggests a collision-free clone Bundle ID (no artificial upper limit).
- (NSString *)suggestNextBundleIDForSource:(NSString *)sourceBundleID;

/// Validates target Bundle ID against reverse-DNS syntax, system blocklist, installed apps, and existing clones.
- (BOOL)validateTargetBundleID:(NSString *)targetBundleID
                sourceBundleID:(NSString *)sourceBundleID
                         error:(NSError * _Nullable * _Nullable)error;

/// Extracts a standalone read-only .ipa directly from an installed unencrypted .app bundle.
- (void)extractIPAFromInstalledAppReport:(MCIPAInspectionReport *)report
                                progress:(void (^ _Nullable)(double fraction, NSString *stage))progressHandler
                              completion:(void (^)(NSString * _Nullable ipaPath, NSError * _Nullable error))completion;

/// Executes single transactional clone creation on a background queue.
- (void)createCloneWithConfiguration:(MCCloneConfiguration *)config
                            progress:(void (^ _Nullable)(double fraction, NSString *stageDescription))progressHandler
                          completion:(void (^)(MCCloneRecord * _Nullable record, NSError * _Nullable error))completion;

/// Executes batch creation of N clones (e.g. 5 or 10 at once) named "1_<base>", "2_<base>", ...
/// Extracts/copies source once into shared staging, then builds each clone transactionally with per-clone rollback.
- (void)createBatchClonesWithConfiguration:(MCBatchCloneConfiguration *)config
                                  progress:(void (^ _Nullable)(double fraction, NSString *stageDescription))progressHandler
                                completion:(void (^)(MCBatchCloneResult * _Nullable result, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
