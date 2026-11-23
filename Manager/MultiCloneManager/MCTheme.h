#import <UIKit/UIKit.h>
#import "../../Source/Settings/MCSettingsManager.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const MCThemeDidChangeNotification;

@interface MCTheme : NSObject

+ (UIColor *)backgroundColor;
+ (UIColor *)surfaceColor;
+ (UIColor *)elevatedSurfaceColor;
+ (UIColor *)borderColor;
+ (UIColor *)primaryTextColor;
+ (UIColor *)secondaryTextColor;
+ (UIColor *)accentColor;
+ (UIColor *)successColor;
+ (UIColor *)warningColor;
+ (UIColor *)dangerColor;

+ (UIColor *)colorFromHex:(NSString *)hex fallback:(UIColor *)fallback;
+ (void)applyGlobalAppearance;
+ (void)styleCardView:(UIView *)view;
+ (UILabel *)makeBadgeLabelWithText:(NSString *)text color:(UIColor *)color;

@end

NS_ASSUME_NONNULL_END
