#import <Foundation/Foundation.h>
#import "../MultiCloneCore/MCModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Read-only IPA & installed .app bundle inspector that parses Bundle ID, Display Name,
/// icons, Mach-O executable, FairPlay DRM encryption flag, embedded entitlements,
/// provisioning profile, frameworks, and app extensions without modifying the source app.
@interface MCIPAInspector : NSObject

+ (nullable MCIPAInspectionReport *)inspectIPAAtPath:(NSString *)ipaPath
                                               error:(NSError * _Nullable * _Nullable)error;

/// Inspects an installed .app bundle directory directly on-device (read-only).
+ (nullable MCIPAInspectionReport *)inspectInstalledAppBundleAtPath:(NSString *)appBundlePath
                                                              error:(NSError * _Nullable * _Nullable)error;

/// Evaluates compatibility rules and populates report.compatibilityStatus, summary, and issues.
+ (void)evaluateCompatibilityForReport:(MCIPAInspectionReport *)report;

@end

NS_ASSUME_NONNULL_END
