#import <Foundation/Foundation.h>
#import "MCModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Strictly isolated bridge for iOS private APIs (FBSSystemService, LSApplicationWorkspace,
/// LSApplicationProxy) and rootless CLI tools (ldid, uicache).
/// All calls validate runtime class/selector existence and method signatures inside @try/@catch
/// so missing or changed iOS 18.2 APIs degrade safely without crashing SpringBoard or Manager.
@interface MCPrivateAPIBridge : NSObject

/// Terminates an app bundle via FBSSystemService (prefers completion-handler variant on iOS 15-18.2).
+ (BOOL)terminateApplicationWithBundleID:(NSString *)bundleID
                                  reason:(NSString *)reasonDescription
                                   error:(NSError * _Nullable * _Nullable)error;

/// Opens an app bundle via LSApplicationWorkspace with FBSSystemService fallback.
+ (BOOL)openApplicationWithBundleID:(NSString *)bundleID
                              error:(NSError * _Nullable * _Nullable)error;

/// Enumerates installed applications via LSApplicationWorkspace.
+ (NSArray<MCInstalledAppInfo *> *)installedApplicationsWithManagedIDs:(NSSet<NSString *> *)managedIDs;

/// Looks up a single installed application proxy if present.
+ (nullable MCInstalledAppInfo *)installedApplicationForBundleID:(NSString *)bundleID;

/// Finds a rootless-compatible tool binary (e.g., "ldid", "uicache") in /var/jb/usr/bin or /usr/bin.
+ (nullable NSString *)pathForToolNamed:(NSString *)toolName;

/// Executes an external rootless helper tool via posix_spawn and captures exit code + output.
+ (int)runToolAtPath:(NSString *)toolPath
           arguments:(NSArray<NSString *> *)arguments
              output:(NSString * _Nullable * _Nullable)output
               error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
