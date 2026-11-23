#import "MCSettingsViewController.h"
#import "MCTheme.h"
#import "MCLogViewerViewController.h"
#import "../../Source/MultiCloneCore/MCConstants.h"
#import "../../Source/Settings/MCSettingsManager.h"
#import "../../Source/AutoClose/MCAutoCloseClient.h"

@implementation MCSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cài đặt";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = [MCTheme backgroundColor];
    self.tableView.separatorColor = [MCTheme borderColor];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - Switch Handlers

- (void)mc_autoCloseToggled:(UISwitch *)sender {
    [MCSettingsManager sharedManager].autoCloseEnabled = sender.isOn;
}

- (void)mc_confirmBeforeCloseToggled:(UISwitch *)sender {
    [MCSettingsManager sharedManager].confirmBeforeAutoClose = sender.isOn;
}

#pragma mark - Pickers

- (NSString *)mc_launchBehaviorLabel:(MCLaunchBehavior)behavior {
    switch (behavior) {
        case MCLaunchBehaviorAutoCloseThenOpen: return @"Đóng clone trước rồi mở";
        case MCLaunchBehaviorOpenOnly:          return @"Chỉ mở (không đóng app cũ)";
        case MCLaunchBehaviorAskEveryTime:
        default:                                return @"Hỏi mỗi lần mở";
    }
}

- (NSString *)mc_themeStyleLabel:(MCThemeStyle)style {
    switch (style) {
        case MCThemeStylePureBlack: return @"AMOLED Pure Black";
        case MCThemeStyleSlate:     return @"Slate Dark";
        case MCThemeStyleMidnight:
        default:                    return @"Midnight Dark";
    }
}

- (void)mc_pickLaunchBehavior {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Hành vi khi mở ứng dụng mới"
                                                                   message:@"Chọn cách MultiClone xử lý bản clone đang mở trước đó."
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *opts = @[@(MCLaunchBehaviorAskEveryTime), @(MCLaunchBehaviorAutoCloseThenOpen), @(MCLaunchBehaviorOpenOnly)];
    for (NSNumber *opt in opts) {
        MCLaunchBehavior b = (MCLaunchBehavior)opt.integerValue;
        [sheet addAction:[UIAlertAction actionWithTitle:[self mc_launchBehaviorLabel:b] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a;
            [MCSettingsManager sharedManager].launchBehavior = b;
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)mc_pickThemeStyle {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Giao diện Dark Mode"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *styles = @[@(MCThemeStyleMidnight), @(MCThemeStylePureBlack), @(MCThemeStyleSlate)];
    for (NSNumber *s in styles) {
        MCThemeStyle st = (MCThemeStyle)s.integerValue;
        [sheet addAction:[UIAlertAction actionWithTitle:[self mc_themeStyleLabel:st] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a;
            [MCSettingsManager sharedManager].themeStyle = st;
            [MCTheme applyGlobalAppearance];
            self.tableView.backgroundColor = [MCTheme backgroundColor];
            [[NSNotificationCenter defaultCenter] postNotificationName:MCThemeDidChangeNotification object:nil];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)mc_pickAccentColor {
    NSDictionary<NSString *, NSString *> *palette = @{
        @"Xanh dương (#3B82F6)": @"#3B82F6",
        @"Xanh ngọc (#10B981)": @"#10B981",
        @"Tím (#8B5CF6)": @"#8B5CF6",
        @"Cam (#F59E0B)": @"#F59E0B"
    };
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Màu nhấn (Accent)"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *label in palette) {
        NSString *hex = palette[label];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a;
            [MCSettingsManager sharedManager].accentColorHex = hex;
            [MCTheme applyGlobalAppearance];
            [[NSNotificationCenter defaultCenter] postNotificationName:MCThemeDidChangeNotification object:nil];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)mc_pingSpringBoard {
    [[MCAutoCloseClient sharedClient] pingSpringBoardTweakWithTimeout:1.5 completion:^(BOOL reachable, NSString *detail) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:(reachable ? @"SpringBoard Tweak: Hoạt động" : @"SpringBoard Tweak: Không phản hồi")
                                                                       message:detail
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return @"Auto Close Previous App";
        case 1: return @"Giao diện";
        case 2: return @"Hệ thống & Chẩn đoán";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) {
        return @"Chính sách an toàn: MultiClone chỉ đóng ứng dụng clone trước đó có trong danh sách quản lý. Ứng dụng hệ thống Apple và ứng dụng bên ngoài luôn được bảo vệ tuyệt đối.";
    }
    if (section == 2) {
        return @"MultiClone miễn phí hoàn toàn, không yêu cầu giấy phép trả phí. Mục tiêu: iPhone 11 • iOS 18.2 • Dopamine 3.0.7+ Rootless.";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return 4;
        case 1: return 2;
        case 2: return 3;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"MCSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    }
    cell.backgroundColor = [MCTheme surfaceColor];
    cell.textLabel.textColor = [MCTheme primaryTextColor];
    cell.detailTextLabel.textColor = [MCTheme secondaryTextColor];
    cell.detailTextLabel.text = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    MCSettingsManager *settings = [MCSettingsManager sharedManager];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Bật Auto Close Previous App";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = settings.autoCloseEnabled;
            sw.onTintColor = [MCTheme accentColor];
            [sw addTarget:self action:@selector(mc_autoCloseToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Chỉ đóng clone của MultiClone";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = YES;
            sw.enabled = NO; // Enforced safety lock
            sw.onTintColor = [MCTheme successColor];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Xác nhận trước khi đóng";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = settings.confirmBeforeAutoClose;
            sw.onTintColor = [MCTheme accentColor];
            [sw addTarget:self action:@selector(mc_confirmBeforeCloseToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            cell.textLabel.text = @"Hành vi khi mở ứng dụng mới";
            cell.detailTextLabel.text = [self mc_launchBehaviorLabel:settings.launchBehavior];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Chủ đề tối (Dark Mode)";
            cell.detailTextLabel.text = [self mc_themeStyleLabel:settings.themeStyle];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Màu nhấn (Accent)";
            cell.detailTextLabel.text = settings.accentColorHex;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Kiểm tra SpringBoard Tweak (IPC Ping)";
            cell.textLabel.textColor = [MCTheme accentColor];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Xem nhật ký lỗi & sự kiện";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Phiên bản";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@ (Rootless)", MCProductVersion];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 3) {
        [self mc_pickLaunchBehavior];
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) [self mc_pickThemeStyle];
        else [self mc_pickAccentColor];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            [self mc_pingSpringBoard];
        } else if (indexPath.row == 1) {
            MCLogViewerViewController *logs = [[MCLogViewerViewController alloc] init];
            [self.navigationController pushViewController:logs animated:YES];
        }
    }
}

@end
