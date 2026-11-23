#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// SpringBoard-side Auto Close handler (backward compatible with v0.3 notification & domain names).
FOUNDATION_EXPORT NSString * const MCAutoCloseRequestNotification;
FOUNDATION_EXPORT NSString * const MCAutoClosePreferencesDomain;

/// Installs Darwin notification observers for managed app launch/auto-close and ping/pong health check.
void MCInstallAutoCloseObserver(void);

NS_ASSUME_NONNULL_END
