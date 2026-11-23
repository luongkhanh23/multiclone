#import "MCAppDelegate.h"
#import "MCTheme.h"
#import "MCHomeViewController.h"
#import "MCCreateCloneViewController.h"
#import "MCSettingsViewController.h"
#import "../../Source/DataManager/MCDataManager.h"
#import "../../Source/Logger/MCLogger.h"

@implementation MCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application; (void)launchOptions;

    // Clean any orphaned staging folders from interrupted sessions
    [[MCDataManager sharedManager] cleanupOrphanedStagingDirectories];
    [[MCLogger sharedLogger] info:@"Manager" format:@"MultiClone Manager launched."];

    [MCTheme applyGlobalAppearance];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.backgroundColor = [MCTheme backgroundColor];

    MCHomeViewController *homeVC = [[MCHomeViewController alloc] init];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:homeVC];
    homeNav.navigationBar.prefersLargeTitles = YES;
    homeNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Trang chủ"
                                                       image:[UIImage systemImageNamed:@"square.grid.2x2"]
                                               selectedImage:[UIImage systemImageNamed:@"square.grid.2x2.fill"]];

    MCCreateCloneViewController *createVC = [[MCCreateCloneViewController alloc] init];
    UINavigationController *createNav = [[UINavigationController alloc] initWithRootViewController:createVC];
    createNav.navigationBar.prefersLargeTitles = YES;
    createNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Tạo Clone"
                                                         image:[UIImage systemImageNamed:@"plus.square.on.square"]
                                                 selectedImage:[UIImage systemImageNamed:@"plus.square.fill.on.square.fill"]];

    MCSettingsViewController *settingsVC = [[MCSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    settingsNav.navigationBar.prefersLargeTitles = YES;
    settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Cài đặt"
                                                           image:[UIImage systemImageNamed:@"gearshape"]
                                                   selectedImage:[UIImage systemImageNamed:@"gearshape.fill"]];

    UITabBarController *tabBar = [[UITabBarController alloc] init];
    tabBar.viewControllers = @[homeNav, createNav, settingsNav];
    tabBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    (void)app; (void)options;
    if (!url.isFileURL) return NO;
    UITabBarController *tab = (UITabBarController *)self.window.rootViewController;
    if ([tab isKindOfClass:[UITabBarController class]] && tab.viewControllers.count > 1) {
        UINavigationController *nav = tab.viewControllers[1];
        if ([nav isKindOfClass:[UINavigationController class]] &&
            [nav.viewControllers.firstObject isKindOfClass:[MCCreateCloneViewController class]]) {
            tab.selectedIndex = 1;
            MCCreateCloneViewController *createVC = (MCCreateCloneViewController *)nav.viewControllers.firstObject;
            [createVC loadIPAFileAtPath:url.path];
            return YES;
        }
    }
    return NO;
}

@end
