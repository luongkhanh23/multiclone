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

/// Transactional clone builder with atomic staging and automatic rollback on failure.
/// Never modifies original app bundles or original app data containers.
/// Never bypasses FairPlay DRM, anti-cheat, or third-party server verification.
@interface MCCloneEngine : NSObject

+ (instancetype)sharedEngine;

/// Suggests a collision-free clone Bundle ID (no artificial upper limit).
- (NSString *)suggestNextBundleIDForSource:(NSString *)sourceBundleID;

/// Validates target Bundle ID against reverse-DNS syntax, system blocklist, installed apps, and existing clones.
- (BOOL)validateTargetBundleID:(NSString *)targetBundleID
                sourceBundleID:(NSString *)sourceBundleID
                         error:(NSError * _Nullable * _Nullable)error;

/// Executes transactional clone creation on a background queue, reporting progress and status updates.
- (void)createCloneWithConfiguration:(MCCloneConfiguration *)config
                            progress:(void (^ _Nullable)(double fraction, NSString *stageDescription))progressHandler
                          completion:(void (^)(MCCloneRecord * _Nullable record, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
