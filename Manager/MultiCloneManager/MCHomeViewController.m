#import "MCHomeViewController.h"
#import "MCTheme.h"
#import "MCCloneDetailViewController.h"
#import "MCCreateCloneViewController.h"
#import "../../Source/MultiCloneCore/MCModels.h"
#import "../../Source/MultiCloneCore/MCPrivateAPIBridge.h"
#import "../../Source/DataManager/MCDataManager.h"
#import "../../Source/IconManager/MCIconManager.h"
#import "../../Source/Settings/MCSettingsManager.h"
#import "../../Source/AutoClose/MCAutoCloseClient.h"

@interface MCHomeViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, copy) NSArray<MCCloneRecord *> *allClones;
@property (nonatomic, copy) NSArray<MCInstalledAppInfo *> *installedApps;
@property (nonatomic, copy) NSArray<MCCloneRecord *> *filteredClones;
@property (nonatomic, copy) NSArray<MCInstalledAppInfo *> *filteredInstalled;
@end

@implementation MCHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MultiClone";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [MCTheme backgroundColor];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mc_applyTheme)
                                                 name:MCThemeDidChangeNotification
                                               object:nil];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(mc_openCreateClone)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Tìm kiếm ứng dụng hoặc Bundle ID...";
    self.searchController.searchBar.barStyle = UIBarStyleBlack;
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"Tất cả", @"Đã Clone", @"Đã cài"]];
    self.scopeControl.selectedSegmentIndex = 0;
    self.scopeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scopeControl addTarget:self action:@selector(mc_scopeChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.scopeControl];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [MCTheme backgroundColor];
    self.tableView.separatorColor = [MCTheme borderColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 68.0;

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(mc_reloadData) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = refresh;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scopeControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.scopeControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.scopeControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [self.tableView.topAnchor constraintEqualToAnchor:self.scopeControl.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self mc_applyTheme];
    [self mc_reloadData];
}

- (void)mc_applyTheme {
    self.view.backgroundColor = [MCTheme backgroundColor];
    self.tableView.backgroundColor = [MCTheme backgroundColor];
    self.tableView.separatorColor = [MCTheme borderColor];
    self.navigationController.navigationBar.tintColor = [MCTheme accentColor];
    [self.tableView reloadData];
}

- (void)mc_openCreateClone {
    if (self.tabBarController && self.tabBarController.viewControllers.count > 1) {
        self.tabBarController.selectedIndex = 1;
    } else {
        MCCreateCloneViewController *vc = [[MCCreateCloneViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (void)mc_scopeChanged {
    [self mc_applyFilter];
}

- (void)mc_reloadData {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<MCCloneRecord *> *clones = [[MCDataManager sharedManager] allClones];
        NSMutableSet<NSString *> *managed = [NSMutableSet setWithArray:[MCSettingsManager sharedManager].managedCloneBundleIDs];
        for (MCCloneRecord *c in clones) {
            if (c.cloneBundleID.length > 0) [managed addObject:c.cloneBundleID];
        }
        NSArray<MCInstalledAppInfo *> *installed = [MCPrivateAPIBridge installedApplicationsWithManagedIDs:managed];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allClones = clones;
            self.installedApps = installed;
            [self.tableView.refreshControl endRefreshing];
            [self mc_applyFilter];
        });
    });
}

- (void)mc_applyFilter {
    NSString *query = [self.searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (query.length == 0) {
        self.filteredClones = self.allClones ?: @[];
        self.filteredInstalled = self.installedApps ?: @[];
    } else {
        self.filteredClones = [self.allClones filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MCCloneRecord *c, NSDictionary *b) {
            (void)b;
            return [c.displayName.lowercaseString containsString:query] ||
                   [c.cloneBundleID.lowercaseString containsString:query] ||
                   [c.sourceBundleID.lowercaseString containsString:query];
        }]];
        self.filteredInstalled = [self.installedApps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MCInstalledAppInfo *a, NSDictionary *b) {
            (void)b;
            return [a.displayName.lowercaseString containsString:query] ||
                   [a.bundleID.lowercaseString containsString:query];
        }]];
    }
    [self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self mc_applyFilter];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    if (self.scopeControl.selectedSegmentIndex == 0) return 2;
    return 1;
}

- (BOOL)mc_isCloneSection:(NSInteger)section {
    if (self.scopeControl.selectedSegmentIndex == 1) return YES;
    if (self.scopeControl.selectedSegmentIndex == 2) return NO;
    return section == 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ([self mc_isCloneSection:section]) {
        return [NSString stringWithFormat:@"Ứng dụng đã Clone (%lu)", (unsigned long)self.filteredClones.count];
    }
    return [NSString stringWithFormat:@"Ứng dụng đã cài trên máy (%lu)", (unsigned long)self.filteredInstalled.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if ([self mc_isCloneSection:section]) {
        return MAX((NSInteger)1, (NSInteger)self.filteredClones.count);
    }
    return MAX((NSInteger)1, (NSInteger)self.filteredInstalled.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"MCAppRowCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    }
    cell.backgroundColor = [MCTheme surfaceColor];
    cell.textLabel.textColor = [MCTheme primaryTextColor];
    cell.detailTextLabel.textColor = [MCTheme secondaryTextColor];
    cell.accessoryView = nil;
    cell.imageView.layer.cornerRadius = 10.0;
    cell.imageView.clipsToBounds = YES;

    if ([self mc_isCloneSection:indexPath.section]) {
        if (self.filteredClones.count == 0) {
            cell.textLabel.text = @"Chưa có bản clone nào";
            cell.detailTextLabel.text = @"Nhấn nút + ở góc trên phải để nhập IPA và tạo clone";
            cell.imageView.image = [UIImage systemImageNamed:@"plus.app"];
            cell.imageView.tintColor = [MCTheme accentColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }
        MCCloneRecord *clone = self.filteredClones[indexPath.row];
        NSString *lastID = [MCSettingsManager sharedManager].lastManagedBundleID;
        BOOL isLastActive = [lastID isEqualToString:clone.cloneBundleID];

        cell.textLabel.text = clone.displayName;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", clone.cloneBundleID, [clone statusDisplayString]];
        UIImage *icon = [[MCIconManager sharedManager] loadIconForCloneID:clone.cloneID];
        cell.imageView.image = icon ?: [UIImage systemImageNamed:@"app.badge.checkmark"];
        cell.imageView.tintColor = [MCTheme accentColor];

        UIColor *badgeColor = isLastActive ? [MCTheme successColor]
            : (clone.compatibilityStatus == MCCompatibilityStatusPartialWarning ? [MCTheme warningColor] : [MCTheme accentColor]);
        NSString *badgeText = isLastActive ? @"Gần nhất" : [clone statusDisplayString];
        UILabel *badge = [MCTheme makeBadgeLabelWithText:badgeText color:badgeColor];
        [badge sizeToFit];
        badge.frame = CGRectMake(0, 0, badge.bounds.size.width + 6, 22);
        cell.accessoryView = badge;
        return cell;
    } else {
        if (self.filteredInstalled.count == 0) {
            cell.textLabel.text = @"Không tìm thấy ứng dụng người dùng";
            cell.detailTextLabel.text = @"Kéo xuống để làm mới danh sách ứng dụng";
            cell.imageView.image = [UIImage systemImageNamed:@"iphone"];
            cell.imageView.tintColor = [MCTheme secondaryTextColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }
        MCInstalledAppInfo *app = self.filteredInstalled[indexPath.row];
        cell.textLabel.text = app.displayName;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", app.bundleID,
            app.shortVersion.length > 0 ? [NSString stringWithFormat:@" • v%@", app.shortVersion] : @""];
        UIImage *icon = [[MCIconManager sharedManager] loadIconFromAppBundlePath:app.bundlePath];
        cell.imageView.image = icon ?: [UIImage systemImageNamed:@"app.fill"];
        cell.imageView.tintColor = [MCTheme secondaryTextColor];
        UILabel *badge = [MCTheme makeBadgeLabelWithText:(app.isManagedClone ? @"Clone" : @"Gốc")
                                                   color:(app.isManagedClone ? [MCTheme successColor] : [MCTheme secondaryTextColor])];
        [badge sizeToFit];
        badge.frame = CGRectMake(0, 0, badge.bounds.size.width + 6, 22);
        cell.accessoryView = badge;
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self mc_isCloneSection:indexPath.section]) {
        if (self.filteredClones.count == 0) {
            [self mc_openCreateClone];
            return;
        }
        MCCloneRecord *clone = self.filteredClones[indexPath.row];
        MCCloneDetailViewController *detail = [[MCCloneDetailViewController alloc] initWithCloneID:clone.cloneID];
        [self.navigationController pushViewController:detail animated:YES];
    } else if (self.filteredInstalled.count > 0) {
        MCInstalledAppInfo *app = self.filteredInstalled[indexPath.row];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:app.displayName
                                                                       message:[NSString stringWithFormat:@"Bundle ID: %@\nPhiên bản: %@\n\nĐể tạo bản clone, hãy nhập tệp IPA hợp lệ của ứng dụng này tại tab Tạo Clone.", app.bundleID, app.shortVersion ?: @"N/A"]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Đi tới Tạo Clone" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a;
            [self mc_openCreateClone];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:sheet animated:YES completion:nil];
    }
}

@end
