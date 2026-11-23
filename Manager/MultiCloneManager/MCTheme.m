#import "MCTheme.h"

NSNotificationName const MCThemeDidChangeNotification = @"MCThemeDidChangeNotification";

@implementation MCTheme

+ (UIColor *)colorFromHex:(NSString *)hex fallback:(UIColor *)fallback {
    if (![hex isKindOfClass:[NSString class]] || hex.length != 7 || ![hex hasPrefix:@"#"]) {
        return fallback;
    }
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:1]];
    if (![scanner scanHexInt:&rgb]) return fallback;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

+ (UIColor *)backgroundColor {
    switch ([MCSettingsManager sharedManager].themeStyle) {
        case MCThemeStylePureBlack: return [UIColor colorWithRed:0.00 green:0.00 blue:0.00 alpha:1.0];
        case MCThemeStyleSlate:     return [UIColor colorWithRed:0.06 green:0.09 blue:0.16 alpha:1.0];
        case MCThemeStyleMidnight:
        default:                    return [UIColor colorWithRed:0.043 green:0.051 blue:0.071 alpha:1.0];
    }
}

+ (UIColor *)surfaceColor {
    switch ([MCSettingsManager sharedManager].themeStyle) {
        case MCThemeStylePureBlack: return [UIColor colorWithRed:0.07 green:0.07 blue:0.08 alpha:1.0];
        case MCThemeStyleSlate:     return [UIColor colorWithRed:0.10 green:0.14 blue:0.23 alpha:1.0];
        case MCThemeStyleMidnight:
        default:                    return [UIColor colorWithRed:0.082 green:0.098 blue:0.133 alpha:1.0];
    }
}

+ (UIColor *)elevatedSurfaceColor {
    switch ([MCSettingsManager sharedManager].themeStyle) {
        case MCThemeStylePureBlack: return [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        case MCThemeStyleSlate:     return [UIColor colorWithRed:0.14 green:0.19 blue:0.30 alpha:1.0];
        case MCThemeStyleMidnight:
        default:                    return [UIColor colorWithRed:0.118 green:0.141 blue:0.192 alpha:1.0];
    }
}

+ (UIColor *)borderColor {
    return [UIColor colorWithRed:0.18 green:0.22 blue:0.30 alpha:0.85];
}

+ (UIColor *)primaryTextColor {
    return [UIColor colorWithRed:0.95 green:0.96 blue:0.98 alpha:1.0];
}

+ (UIColor *)secondaryTextColor {
    return [UIColor colorWithRed:0.60 green:0.65 blue:0.74 alpha:1.0];
}

+ (UIColor *)accentColor {
    NSString *hex = [MCSettingsManager sharedManager].accentColorHex;
    return [self colorFromHex:hex fallback:[UIColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0]];
}

+ (UIColor *)successColor {
    return [UIColor colorWithRed:0.06 green:0.73 blue:0.51 alpha:1.0];
}

+ (UIColor *)warningColor {
    return [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1.0];
}

+ (UIColor *)dangerColor {
    return [UIColor colorWithRed:0.94 green:0.27 blue:0.27 alpha:1.0];
}

+ (void)applyGlobalAppearance {
    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithOpaqueBackground];
    nav.backgroundColor = [self backgroundColor];
    nav.shadowColor = [self borderColor];
    nav.titleTextAttributes = @{NSForegroundColorAttributeName: [self primaryTextColor]};
    nav.largeTitleTextAttributes = @{NSForegroundColorAttributeName: [self primaryTextColor]};

    UINavigationBar *navProxy = [UINavigationBar appearance];
    navProxy.standardAppearance = nav;
    navProxy.scrollEdgeAppearance = nav;
    navProxy.compactAppearance = nav;
    navProxy.tintColor = [self accentColor];

    UITabBarAppearance *tab = [[UITabBarAppearance alloc] init];
    [tab configureWithOpaqueBackground];
    tab.backgroundColor = [self surfaceColor];
    tab.shadowColor = [self borderColor];

    UITabBar *tabProxy = [UITabBar appearance];
    tabProxy.standardAppearance = tab;
    if (@available(iOS 15.0, *)) {
        tabProxy.scrollEdgeAppearance = tab;
    }
    tabProxy.tintColor = [self accentColor];
    tabProxy.unselectedItemTintColor = [self secondaryTextColor];
}

+ (void)styleCardView:(UIView *)view {
    view.backgroundColor = [self surfaceColor];
    view.layer.cornerRadius = 14.0;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = [self borderColor].CGColor;
    view.clipsToBounds = YES;
}

+ (UILabel *)makeBadgeLabelWithText:(NSString *)text color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"  %@  ", text ?: @""];
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    label.textColor = color;
    label.backgroundColor = [color colorWithAlphaComponent:0.16];
    label.layer.cornerRadius = 6.0;
    label.layer.masksToBounds = YES;
    return label;
}

@end
