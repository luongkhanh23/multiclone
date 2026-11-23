#import <Foundation/Foundation.h>
#import "../MultiCloneCore/MCModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Read-only IPA inspector that parses Bundle ID, Display Name, icons, Mach-O executable,
/// FairPlay DRM encryption flag, embedded entitlements, provisioning profile, frameworks,
/// and app extensions without modifying the source IPA.
@interface MCIPAInspector : NSObject

+ (nullable MCIPAInspectionReport *)inspectIPAAtPath:(NSString *)ipaPath
                                               error:(NSError * _Nullable * _Nullable)error;

/// Evaluates compatibility rules and populates report.compatibilityStatus, summary, and issues.
+ (void)evaluateCompatibilityForReport:(MCIPAInspectionReport *)report;

@end

NS_ASSUME_NONNULL_END
