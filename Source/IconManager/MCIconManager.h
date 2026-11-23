#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Manages app icon extraction, custom icon resizing/caching inside MultiClone's
/// managed Icons directory, and applying custom icons to cloned .app bundles.
@interface MCIconManager : NSObject

+ (instancetype)sharedManager;

/// Decodes raw PNG icon data (returns nil gracefully for unsupported CgBI images).
- (nullable UIImage *)imageFromPNGData:(nullable NSData *)pngData;

/// Saves and normalizes a custom icon image for a clone ID (180x180 PNG inside managed Icons dir).
- (nullable NSString *)saveCustomIconImage:(UIImage *)image
                                forCloneID:(NSString *)cloneID
                                     error:(NSError * _Nullable * _Nullable)error;

/// Loads the cached custom icon for a clone if present.
- (nullable UIImage *)loadIconForCloneID:(NSString *)cloneID;

/// Removes cached icon strictly inside MultiClone's managed Icons directory.
- (BOOL)deleteIconForCloneID:(NSString *)cloneID;

/// Applies a custom icon PNG into a staged/cloned .app bundle and updates Info.plist CFBundleIcons.
- (BOOL)applyCustomIcon:(UIImage *)image
            toAppBundle:(NSString *)appBundlePath
                  error:(NSError * _Nullable * _Nullable)error;

/// Loads icon of an installed app from its bundle directory if readable.
- (nullable UIImage *)loadIconFromAppBundlePath:(nullable NSString *)appBundlePath;

@end

NS_ASSUME_NONNULL_END
