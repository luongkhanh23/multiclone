#import "MCCreateCloneViewController.h"
#import "MCTheme.h"
#import "MCCloneDetailViewController.h"
#import "../../Source/MultiCloneCore/MCConstants.h"
#import "../../Source/MultiCloneCore/MCModels.h"
#import "../../Source/MultiCloneCore/MCPrivateAPIBridge.h"
#import "../../Source/IPAInspector/MCIPAInspector.h"
#import "../../Source/IconManager/MCIconManager.h"
#import "../../Source/CloneEngine/MCCloneEngine.h"
#import "../../Source/Settings/MCSettingsManager.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - Installed App Picker Modal

@interface MCInstalledAppPickerViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<MCInstalledAppInfo *> *allApps;
@property (nonatomic, copy) NSArray<MCInstalledAppInfo *> *filteredApps;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) void (^onSelectApp)(MCInstalledAppInfo *app);
@end

@implementation MCInstalledAppPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Chọn ứng dụng gốc";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = [MCTheme backgroundColor];
    self.tableView.separatorColor = [MCTheme borderColor];
    self.tableView.rowHeight = 62.0;

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Đóng" style:UIBarButtonItemStylePlain target:self action:@selector(mc_close)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Tìm TikTok, Zalo, Facebook...";
    self.navigationItem.searchController = self.searchController;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSSet *managed = [NSSet setWithArray:[MCSettingsManager sharedManager].managedCloneBundleIDs];
        NSArray<MCInstalledAppInfo *> *apps = [MCPrivateAPIBridge installedApplicationsWithManagedIDs:managed];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allApps = apps;
            self.filteredApps = apps;
            [self.tableView reloadData];
        });
    });
}

- (void)mc_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    if (q.length == 0) {
        self.filteredApps = self.allApps ?: @[];
    } else {
        self.filteredApps = [self.allApps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MCInstalledAppInfo *a, NSDictionary *b) {
            (void)b;
            return [a.displayName.lowercaseString containsString:q] || [a.bundleID.lowercaseString containsString:q];
        }]];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return MAX((NSInteger)1, (NSInteger)self.filteredApps.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PickAppCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"PickAppCell"];
    }
    cell.backgroundColor = [MCTheme surfaceColor];
    cell.textLabel.textColor = [MCTheme primaryTextColor];
    cell.detailTextLabel.textColor = [MCTheme secondaryTextColor];
    cell.imageView.layer.cornerRadius = 10.0;
    cell.imageView.clipsToBounds = YES;

    if (self.filteredApps.count == 0) {
        cell.textLabel.text = @"Không tìm thấy ứng dụng người dùng";
        cell.detailTextLabel.text = @"Hãy thử từ khóa khác";
        cell.imageView.image = [UIImage systemImageNamed:@"app.dashed"];
        return cell;
    }

    MCInstalledAppInfo *app = self.filteredApps[indexPath.row];
    cell.textLabel.text = app.displayName;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", app.bundleID,
        app.shortVersion.length ? [NSString stringWithFormat:@" • v%@", app.shortVersion] : @""];
    UIImage *icon = [[MCIconManager sharedManager] loadIconFromAppBundlePath:app.bundlePath];
    cell.imageView.image = icon ?: [UIImage systemImageNamed:@"app.fill"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.filteredApps.count == 0) return;
    MCInstalledAppInfo *picked = self.filteredApps[indexPath.row];
    void (^cb)(MCInstalledAppInfo *) = self.onSelectApp;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(picked);
    }];
}

@end

#pragma mark - MCCreateCloneViewController

@interface MCCreateCloneViewController () <UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;

// Source selection buttons
@property (nonatomic, strong) UIButton *pickInstalledAppButton;
@property (nonatomic, strong) UIButton *pickIPAButton;
@property (nonatomic, strong) UIButton *scanLocalIPAButton;
@property (nonatomic, strong) UILabel *selectedFileLabel;
@property (nonatomic, strong) UIActivityIndicatorView *inspectSpinner;

// Inspection summary card
@property (nonatomic, strong) UIView *summaryCard;
@property (nonatomic, strong) UIImageView *appIconView;
@property (nonatomic, strong) UILabel *appTitleLabel;
@property (nonatomic, strong) UILabel *appMetaLabel;
@property (nonatomic, strong) UILabel *compatibilityStatusLabel;
@property (nonatomic, strong) UILabel *compatibilityDetailLabel;
@property (nonatomic, strong) UIButton *extractOnlyIPAButton;

// Form card
@property (nonatomic, strong) UIView *formCard;
@property (nonatomic, strong) UITextField *baseNameField;
@property (nonatomic, strong) UISegmentedControl *countPresetControl;
@property (nonatomic, strong) UITextField *customCountField;
@property (nonatomic, strong) UILabel *namingPreviewLabel;
@property (nonatomic, strong) UITextField *bundleIDField;
@property (nonatomic, strong) UILabel *bundleValidationLabel;
@property (nonatomic, strong) UIButton *pickIconButton;
@property (nonatomic, strong) UISwitch *exportIPASwitch;
@property (nonatomic, strong) UISwitch *acknowledgeWarningsSwitch;
@property (nonatomic, strong) UIStackView *acknowledgeRow;

// Progress & Confirm
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressStageLabel;
@property (nonatomic, strong) UIButton *confirmButton;

@property (nonatomic, strong, nullable) MCIPAInspectionReport *currentReport;
@property (nonatomic, strong, nullable) UIImage *selectedCustomIcon;
@property (nonatomic, assign) NSUInteger selectedCloneCount;
@property (nonatomic, strong, nullable) MCInstalledAppInfo *pendingAppToLoad;
@property (nonatomic, copy, nullable) NSString *pendingIPAToLoad;
@end

@implementation MCCreateCloneViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tạo bản Clone";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [MCTheme backgroundColor];
    self.selectedCloneCount = 1;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mc_refreshTheme)
                                                 name:MCThemeDidChangeNotification
                                               object:nil];

    [self mc_buildUI];
    [self mc_updateUIForReport:nil];

    if (self.pendingAppToLoad) {
        MCInstalledAppInfo *app = self.pendingAppToLoad;
        self.pendingAppToLoad = nil;
        [self loadInstalledAppInfo:app];
    } else if (self.pendingIPAToLoad.length > 0) {
        NSString *p = self.pendingIPAToLoad;
        self.pendingIPAToLoad = nil;
        [self loadIPAFileAtPath:p];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)mc_refreshTheme {
    self.view.backgroundColor = [MCTheme backgroundColor];
    [MCTheme styleCardView:self.summaryCard];
    [MCTheme styleCardView:self.formCard];
    self.pickInstalledAppButton.backgroundColor = [MCTheme accentColor];
    self.confirmButton.backgroundColor = [MCTheme accentColor];
}

- (UITextField *)mc_makeTextFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *tf = [[UITextField alloc] init];
    tf.backgroundColor = [MCTheme elevatedSurfaceColor];
    tf.textColor = [MCTheme primaryTextColor];
    tf.font = [UIFont systemFontOfSize:15];
    tf.layer.cornerRadius = 10.0;
    tf.layer.borderWidth = 1.0;
    tf.layer.borderColor = [MCTheme borderColor].CGColor;
    tf.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
                                                               attributes:@{NSForegroundColorAttributeName: [MCTheme secondaryTextColor]}];
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    tf.leftViewMode = UITextFieldViewModeAlways;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.delegate = self;
    [tf.heightAnchor constraintEqualToConstant:44].active = YES;
    return tf;
}

- (UIButton *)mc_makeButtonWithTitle:(NSString *)title background:(UIColor *)bg action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    btn.titleLabel.numberOfLines = 1;
    btn.titleLabel.adjustsFontSizeToFitWidth = YES;
    btn.backgroundColor = bg;
    btn.layer.cornerRadius = 12.0;
    [btn.heightAnchor constraintEqualToConstant:46].active = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)mc_buildUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 12;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:14],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-28],
        [self.stackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32]
    ]];

    // Source 1: Direct extraction from installed app
    self.pickInstalledAppButton = [self mc_makeButtonWithTitle:@"Trích xuất trực tiếp từ App gốc đã cài"
                                                    background:[MCTheme accentColor]
                                                        action:@selector(mc_pickInstalledApp)];
    [self.stackView addArrangedSubview:self.pickInstalledAppButton];

    // Source 2 & 3: Files picker (fixed UTType) + Direct local Downloads/Documents scanner
    UIStackView *ipaBtnRow = [[UIStackView alloc] init];
    ipaBtnRow.axis = UILayoutConstraintAxisHorizontal;
    ipaBtnRow.spacing = 10;
    ipaBtnRow.distribution = UIStackViewDistributionFillEqually;

    self.pickIPAButton = [self mc_makeButtonWithTitle:@"Chọn tệp IPA (Tệp)"
                                           background:[MCTheme elevatedSurfaceColor]
                                               action:@selector(mc_pickIPAFromFiles)];
    self.pickIPAButton.layer.borderWidth = 1.0;
    self.pickIPAButton.layer.borderColor = [MCTheme borderColor].CGColor;

    self.scanLocalIPAButton = [self mc_makeButtonWithTitle:@"Quét IPA trên máy"
                                                background:[MCTheme elevatedSurfaceColor]
                                                    action:@selector(mc_scanLocalIPAs)];
    self.scanLocalIPAButton.layer.borderWidth = 1.0;
    self.scanLocalIPAButton.layer.borderColor = [MCTheme borderColor].CGColor;

    [ipaBtnRow addArrangedSubview:self.pickIPAButton];
    [ipaBtnRow addArrangedSubview:self.scanLocalIPAButton];
    [self.stackView addArrangedSubview:ipaBtnRow];

    self.selectedFileLabel = [[UILabel alloc] init];
    self.selectedFileLabel.font = [UIFont systemFontOfSize:13];
    self.selectedFileLabel.textColor = [MCTheme secondaryTextColor];
    self.selectedFileLabel.numberOfLines = 0;
    self.selectedFileLabel.text = @"Chọn trực tiếp ứng dụng đã cài để trích xuất IPA và nhân bản hàng loạt (1_app, 2_app...), hoặc chọn tệp .ipa có sẵn.";
    [self.stackView addArrangedSubview:self.selectedFileLabel];

    self.inspectSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.inspectSpinner.hidesWhenStopped = YES;
    self.inspectSpinner.color = [MCTheme accentColor];
    [self.stackView addArrangedSubview:self.inspectSpinner];

    // Summary & Compatibility Card
    self.summaryCard = [[UIView alloc] init];
    [MCTheme styleCardView:self.summaryCard];
    UIStackView *sumStack = [[UIStackView alloc] init];
    sumStack.axis = UILayoutConstraintAxisVertical;
    sumStack.spacing = 10;
    sumStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.summaryCard addSubview:sumStack];
    [NSLayoutConstraint activateConstraints:@[
        [sumStack.topAnchor constraintEqualToAnchor:self.summaryCard.topAnchor constant:14],
        [sumStack.leadingAnchor constraintEqualToAnchor:self.summaryCard.leadingAnchor constant:14],
        [sumStack.trailingAnchor constraintEqualToAnchor:self.summaryCard.trailingAnchor constant:-14],
        [sumStack.bottomAnchor constraintEqualToAnchor:self.summaryCard.bottomAnchor constant:-14]
    ]];

    UIStackView *headerRow = [[UIStackView alloc] init];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.spacing = 12;
    headerRow.alignment = UIStackViewAlignmentCenter;

    self.appIconView = [[UIImageView alloc] init];
    self.appIconView.layer.cornerRadius = 14.0;
    self.appIconView.clipsToBounds = YES;
    self.appIconView.contentMode = UIViewContentModeScaleAspectFill;
    self.appIconView.backgroundColor = [MCTheme elevatedSurfaceColor];
    [self.appIconView.widthAnchor constraintEqualToConstant:56].active = YES;
    [self.appIconView.heightAnchor constraintEqualToConstant:56].active = YES;

    UIStackView *titleCol = [[UIStackView alloc] init];
    titleCol.axis = UILayoutConstraintAxisVertical;
    titleCol.spacing = 4;

    self.appTitleLabel = [[UILabel alloc] init];
    self.appTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.appTitleLabel.textColor = [MCTheme primaryTextColor];

    self.appMetaLabel = [[UILabel alloc] init];
    self.appMetaLabel.font = [UIFont systemFontOfSize:12];
    self.appMetaLabel.textColor = [MCTheme secondaryTextColor];
    self.appMetaLabel.numberOfLines = 0;

    [titleCol addArrangedSubview:self.appTitleLabel];
    [titleCol addArrangedSubview:self.appMetaLabel];
    [headerRow addArrangedSubview:self.appIconView];
    [headerRow addArrangedSubview:titleCol];
    [sumStack addArrangedSubview:headerRow];

    self.compatibilityStatusLabel = [[UILabel alloc] init];
    self.compatibilityStatusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.compatibilityStatusLabel.numberOfLines = 0;
    [sumStack addArrangedSubview:self.compatibilityStatusLabel];

    self.compatibilityDetailLabel = [[UILabel alloc] init];
    self.compatibilityDetailLabel.font = [UIFont systemFontOfSize:12];
    self.compatibilityDetailLabel.textColor = [MCTheme secondaryTextColor];
    self.compatibilityDetailLabel.numberOfLines = 0;
    [sumStack addArrangedSubview:self.compatibilityDetailLabel];

    self.extractOnlyIPAButton = [self mc_makeButtonWithTitle:@"Chỉ trích xuất tệp IPA gốc vào Exports"
                                                  background:[MCTheme elevatedSurfaceColor]
                                                      action:@selector(mc_extractOriginalIPAOnly)];
    self.extractOnlyIPAButton.layer.borderWidth = 1.0;
    self.extractOnlyIPAButton.layer.borderColor = [MCTheme accentColor].CGColor;
    [self.extractOnlyIPAButton setTitleColor:[MCTheme accentColor] forState:UIControlStateNormal];
    [sumStack addArrangedSubview:self.extractOnlyIPAButton];

    [self.stackView addArrangedSubview:self.summaryCard];

    // Clone Configuration Form Card
    self.formCard = [[UIView alloc] init];
    [MCTheme styleCardView:self.formCard];
    UIStackView *formStack = [[UIStackView alloc] init];
    formStack.axis = UILayoutConstraintAxisVertical;
    formStack.spacing = 10;
    formStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.formCard addSubview:formStack];
    [NSLayoutConstraint activateConstraints:@[
        [formStack.topAnchor constraintEqualToAnchor:self.formCard.topAnchor constant:14],
        [formStack.leadingAnchor constraintEqualToAnchor:self.formCard.leadingAnchor constant:14],
        [formStack.trailingAnchor constraintEqualToAnchor:self.formCard.trailingAnchor constant:-14],
        [formStack.bottomAnchor constraintEqualToAnchor:self.formCard.bottomAnchor constant:-14]
    ]];

    UILabel *countTitle = [[UILabel alloc] init];
    countTitle.text = @"Số lượng bản sao cần tạo cùng lúc";
    countTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    countTitle.textColor = [MCTheme primaryTextColor];
    [formStack addArrangedSubview:countTitle];

    self.countPresetControl = [[UISegmentedControl alloc] initWithItems:@[@"1 bản", @"3 bản", @"5 bản", @"10 bản", @"Tùy chỉnh"]];
    self.countPresetControl.selectedSegmentIndex = 0;
    [self.countPresetControl addTarget:self action:@selector(mc_countPresetChanged) forControlEvents:UIControlEventValueChanged];
    [formStack addArrangedSubview:self.countPresetControl];

    self.customCountField = [self mc_makeTextFieldWithPlaceholder:@"Nhập số lượng bản clone (ví dụ: 5, 10, 20...)"];
    self.customCountField.keyboardType = UIKeyboardTypeNumberPad;
    self.customCountField.hidden = YES;
    [self.customCountField addTarget:self action:@selector(mc_customCountChanged) forControlEvents:UIControlEventEditingChanged];
    [formStack addArrangedSubview:self.customCountField];

    UILabel *nameTitle = [[UILabel alloc] init];
    nameTitle.text = @"Tên gốc đánh số (tự động tạo 1_<tên>, 2_<tên>...)";
    nameTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    nameTitle.textColor = [MCTheme primaryTextColor];
    [formStack addArrangedSubview:nameTitle];

    self.baseNameField = [self mc_makeTextFieldWithPlaceholder:@"Ví dụ: tiktok, zalo, facebook"];
    [self.baseNameField addTarget:self action:@selector(mc_updateNamingPreview) forControlEvents:UIControlEventEditingChanged];
    [formStack addArrangedSubview:self.baseNameField];

    self.namingPreviewLabel = [[UILabel alloc] init];
    self.namingPreviewLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    self.namingPreviewLabel.textColor = [MCTheme successColor];
    self.namingPreviewLabel.numberOfLines = 0;
    [formStack addArrangedSubview:self.namingPreviewLabel];

    UILabel *bidTitle = [[UILabel alloc] init];
    bidTitle.text = @"Bundle ID mới (tự sinh duy nhất khi tạo nhiều bản)";
    bidTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    bidTitle.textColor = [MCTheme primaryTextColor];
    [formStack addArrangedSubview:bidTitle];

    self.bundleIDField = [self mc_makeTextFieldWithPlaceholder:@"com.example.app.multiclone.001"];
    [self.bundleIDField addTarget:self action:@selector(mc_validateBundleIDLive) forControlEvents:UIControlEventEditingChanged];
    [formStack addArrangedSubview:self.bundleIDField];

    self.bundleValidationLabel = [[UILabel alloc] init];
    self.bundleValidationLabel.font = [UIFont systemFontOfSize:12];
    self.bundleValidationLabel.numberOfLines = 0;
    [formStack addArrangedSubview:self.bundleValidationLabel];

    self.pickIconButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pickIconButton setTitle:@"Chọn biểu tượng (Icon) tùy chỉnh từ Thư viện ảnh" forState:UIControlStateNormal];
    [self.pickIconButton setTitleColor:[MCTheme accentColor] forState:UIControlStateNormal];
    self.pickIconButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self.pickIconButton addTarget:self action:@selector(mc_pickCustomIcon) forControlEvents:UIControlEventTouchUpInside];
    [formStack addArrangedSubview:self.pickIconButton];

    UIStackView *exportRow = [[UIStackView alloc] init];
    exportRow.axis = UILayoutConstraintAxisHorizontal;
    exportRow.alignment = UIStackViewAlignmentCenter;
    UILabel *exportLbl = [[UILabel alloc] init];
    exportLbl.text = @"Xuất từng tệp Clone .ipa vào thư mục Exports";
    exportLbl.font = [UIFont systemFontOfSize:14];
    exportLbl.textColor = [MCTheme primaryTextColor];
    exportLbl.numberOfLines = 0;
    self.exportIPASwitch = [[UISwitch alloc] init];
    self.exportIPASwitch.on = YES;
    self.exportIPASwitch.onTintColor = [MCTheme accentColor];
    [exportRow addArrangedSubview:exportLbl];
    [exportRow addArrangedSubview:self.exportIPASwitch];
    [formStack addArrangedSubview:exportRow];

    self.acknowledgeRow = [[UIStackView alloc] init];
    self.acknowledgeRow.axis = UILayoutConstraintAxisHorizontal;
    self.acknowledgeRow.alignment = UIStackViewAlignmentCenter;
    UILabel *ackLbl = [[UILabel alloc] init];
    ackLbl.text = @"Tôi hiểu các cảnh báo tương thích và có quyền chỉnh sửa ứng dụng này";
    ackLbl.font = [UIFont systemFontOfSize:13];
    ackLbl.textColor = [MCTheme warningColor];
    ackLbl.numberOfLines = 0;
    self.acknowledgeWarningsSwitch = [[UISwitch alloc] init];
    self.acknowledgeWarningsSwitch.on = NO;
    self.acknowledgeWarningsSwitch.onTintColor = [MCTheme warningColor];
    [self.acknowledgeWarningsSwitch addTarget:self action:@selector(mc_updateConfirmState) forControlEvents:UIControlEventValueChanged];
    [self.acknowledgeRow addArrangedSubview:ackLbl];
    [self.acknowledgeRow addArrangedSubview:self.acknowledgeWarningsSwitch];
    [formStack addArrangedSubview:self.acknowledgeRow];

    [self.stackView addArrangedSubview:self.formCard];

    // Progress & Confirm
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [MCTheme accentColor];
    self.progressView.trackTintColor = [MCTheme elevatedSurfaceColor];
    self.progressView.hidden = YES;
    [self.stackView addArrangedSubview:self.progressView];

    self.progressStageLabel = [[UILabel alloc] init];
    self.progressStageLabel.font = [UIFont systemFontOfSize:12];
    self.progressStageLabel.textColor = [MCTheme secondaryTextColor];
    self.progressStageLabel.numberOfLines = 0;
    self.progressStageLabel.hidden = YES;
    [self.stackView addArrangedSubview:self.progressStageLabel];

    self.confirmButton = [self mc_makeButtonWithTitle:@"Xác nhận tạo bản Clone"
                                           background:[MCTheme accentColor]
                                               action:@selector(mc_confirmCreateClone)];
    [self.stackView addArrangedSubview:self.confirmButton];
}

#pragma mark - Source Picking (Installed App / Fixed Document Picker / Local Scan)

- (void)loadInstalledAppInfo:(MCInstalledAppInfo *)appInfo {
    if (!self.isViewLoaded) {
        self.pendingAppToLoad = appInfo;
        return;
    }
    if (!appInfo || appInfo.bundlePath.length == 0) {
        self.selectedFileLabel.text = @"Không đọc được đường dẫn .app của ứng dụng đã chọn.";
        return;
    }
    self.selectedFileLabel.text = [NSString stringWithFormat:@"Đang phân tích trực tiếp ứng dụng gốc: %@...", appInfo.displayName];
    [self.inspectSpinner startAnimating];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        MCIPAInspectionReport *report = [MCIPAInspector inspectInstalledAppBundleAtPath:appInfo.bundlePath error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.inspectSpinner stopAnimating];
            if (!report) {
                self.selectedFileLabel.text = [NSString stringWithFormat:@"Lỗi đọc ứng dụng gốc: %@", err.localizedDescription];
                [self mc_updateUIForReport:nil];
                return;
            }
            [self mc_updateUIForReport:report];
        });
    });
}

- (void)loadIPAFileAtPath:(NSString *)ipaPath {
    if (!self.isViewLoaded) {
        self.pendingIPAToLoad = ipaPath;
        return;
    }
    if (ipaPath.length == 0) return;

    self.selectedFileLabel.text = [NSString stringWithFormat:@"Đang phân tích IPA: %@...", ipaPath.lastPathComponent];
    [self.inspectSpinner startAnimating];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        MCIPAInspectionReport *report = [MCIPAInspector inspectIPAAtPath:ipaPath error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.inspectSpinner stopAnimating];
            if (!report) {
                self.selectedFileLabel.text = [NSString stringWithFormat:@"Lỗi phân tích IPA: %@", err.localizedDescription];
                [self mc_updateUIForReport:nil];
                return;
            }
            [self mc_updateUIForReport:report];
        });
    });
}

- (void)mc_pickInstalledApp {
    MCInstalledAppPickerViewController *picker = [[MCInstalledAppPickerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    __weak typeof(self) weakSelf = self;
    picker.onSelectApp = ^(MCInstalledAppInfo *app) {
        [weakSelf loadInstalledAppInfo:app];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)mc_pickIPAFromFiles {
    // Include UTTypeItem + explicit .ipa/.tipa extension UTTypes so .ipa files are ALWAYS selectable on iOS 15-18.2
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    UTType *ipaUT = [UTType typeWithFilenameExtension:@"ipa"];
    UTType *tipaUT = [UTType typeWithFilenameExtension:@"tipa"];
    if (ipaUT) [types addObject:ipaUT];
    if (tipaUT) [types addObject:tipaUT];
    [types addObject:UTTypeZIP];
    [types addObject:UTTypeArchive];
    [types addObject:UTTypeItem];
    [types addObject:UTTypeData];

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    picker.shouldShowFileExtensions = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;

    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSString *localCopy = [MCStagingDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"import_%@_%@", [[NSUUID UUID].UUIDString substringToIndex:8], url.lastPathComponent ?: @"app.ipa"]];
    NSError *copyErr = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:localCopy error:nil];
    BOOL copied = [fm copyItemAtPath:url.path toPath:localCopy error:&copyErr];
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (copied) {
        [self loadIPAFileAtPath:localCopy];
    } else {
        // Fallback: inspect original path directly if unsandboxed access works
        [self loadIPAFileAtPath:url.path];
    }
}

- (void)mc_scanLocalIPAs {
    NSArray<NSString *> *scanDirs = @[
        @"/var/mobile/Downloads",
        @"/var/mobile/Documents",
        @"/var/mobile/Media/Downloads",
        MCExportsDirectory()
    ];
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *dir in scanDirs) {
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *name in items) {
            NSString *low = name.lowercaseString;
            if ([low hasSuffix:@".ipa"] || [low hasSuffix:@".tipa"]) {
                [found addObject:[dir stringByAppendingPathComponent:name]];
            }
        }
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Tệp IPA trên máy"
                                                                   message:(found.count > 0 ? @"Chọn tệp .ipa muốn phân tích:" : @"Không thấy tệp .ipa trong Downloads/Documents. Bạn có thể nhập đường dẫn trực tiếp.")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *path in found) {
        [sheet addAction:[UIAlertAction actionWithTitle:path.lastPathComponent style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a;
            [self loadIPAFileAtPath:path];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Nhập đường dẫn tệp .ipa thủ công..." style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [self mc_promptManualIPAPath];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.scanLocalIPAButton;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)mc_promptManualIPAPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nhập đường dẫn tệp .ipa"
                                                                   message:@"Ví dụ: /var/mobile/Downloads/TikTok.ipa"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"/var/mobile/Downloads/app.ipa";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Phân tích" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *p = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (p.length > 0) [self loadIPAFileAtPath:p];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Inspection & Form State

- (void)mc_updateUIForReport:(nullable MCIPAInspectionReport *)report {
    self.currentReport = report;
    self.selectedCustomIcon = nil;

    BOOL hasReport = (report != nil);
    self.summaryCard.hidden = !hasReport;
    self.formCard.hidden = !hasReport;
    self.confirmButton.hidden = !hasReport;

    if (!report) return;

    self.selectedFileLabel.text = report.isFromInstalledAppBundle
        ? [NSString stringWithFormat:@"Nguồn: Ứng dụng đã cài (%@)", report.displayName]
        : [NSString stringWithFormat:@"Nguồn: Tệp IPA (%@)", report.ipaPath.lastPathComponent];

    self.appTitleLabel.text = report.displayName.length > 0 ? report.displayName : report.bundleID;

    NSString *archs = report.architectures.count > 0 ? [report.architectures componentsJoinedByString:@", "] : @"Không rõ";
    NSString *drmText = report.isFairPlayEncrypted ? @"CÓ MÃ HÓA FAIRPLAY DRM" : @"Không mã hóa (cryptid=0)";
    NSUInteger entCount = report.entitlements ? report.entitlements.count : 0;

    self.appMetaLabel.text = [NSString stringWithFormat:
        @"Bundle ID: %@\nPhiên bản: %@ (%@) • Min iOS: %@\nKiến trúc: %@ • DRM: %@\nFrameworks: %lu • Extensions: %lu • Entitlements: %lu",
        report.bundleID,
        report.shortVersion.length ? report.shortVersion : @"?",
        report.buildVersion.length ? report.buildVersion : @"?",
        report.minimumOSVersion ?: @"?",
        archs, drmText,
        (unsigned long)report.frameworks.count,
        (unsigned long)report.extensions.count,
        (unsigned long)entCount];

    UIImage *icon = [[MCIconManager sharedManager] imageFromPNGData:report.iconPNGData];
    self.appIconView.image = icon ?: [UIImage systemImageNamed:@"app.dashed"];

    if (report.compatibilityStatus == MCCompatibilityStatusIncompatible) {
        self.compatibilityStatusLabel.text = @"KHÔNG TƯƠNG THÍCH — ĐÃ CHẶN NHÂN BẢN";
        self.compatibilityStatusLabel.textColor = [MCTheme dangerColor];
    } else if (report.compatibilityStatus == MCCompatibilityStatusPartialWarning) {
        self.compatibilityStatusLabel.text = @"TƯƠNG THÍCH CÓ CẢNH BÁO";
        self.compatibilityStatusLabel.textColor = [MCTheme warningColor];
    } else {
        self.compatibilityStatusLabel.text = @"TƯƠNG THÍCH CƠ BẢN";
        self.compatibilityStatusLabel.textColor = [MCTheme successColor];
    }

    NSMutableString *details = [NSMutableString stringWithString:report.compatibilitySummary ?: @""];
    for (MCCompatibilityIssue *issue in report.issues) {
        NSString *prefix = (issue.severity == MCCompatibilitySeverityBlocker) ? @"[CHẶN]"
            : ((issue.severity == MCCompatibilitySeverityWarning) ? @"[CẢNH BÁO]" : @"[THÔNG TIN]");
        [details appendFormat:@"\n• %@ %@: %@", prefix, issue.title, issue.detail];
    }
    self.compatibilityDetailLabel.text = details;

    self.extractOnlyIPAButton.hidden = !(report.isFromInstalledAppBundle && !report.isFairPlayEncrypted);

    // Default clean lowercase base name for numbered clones: e.g. "tiktok" -> 1_tiktok, 2_tiktok...
    NSString *cleanBase = [[(report.displayName ?: @"app") lowercaseString]
        stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    self.baseNameField.text = cleanBase;
    self.bundleIDField.text = [[MCCloneEngine sharedEngine] suggestNextBundleIDForSource:report.bundleID];
    self.acknowledgeRow.hidden = (report.compatibilityStatus != MCCompatibilityStatusPartialWarning);
    self.acknowledgeWarningsSwitch.on = NO;

    [self mc_updateNamingPreview];
    [self mc_validateBundleIDLive];
}

- (void)mc_countPresetChanged {
    switch (self.countPresetControl.selectedSegmentIndex) {
        case 0: self.selectedCloneCount = 1;  self.customCountField.hidden = YES; break;
        case 1: self.selectedCloneCount = 3;  self.customCountField.hidden = YES; break;
        case 2: self.selectedCloneCount = 5;  self.customCountField.hidden = YES; break;
        case 3: self.selectedCloneCount = 10; self.customCountField.hidden = YES; break;
        default:
            self.customCountField.hidden = NO;
            [self mc_customCountChanged];
            break;
    }
    [self mc_updateNamingPreview];
    [self mc_validateBundleIDLive];
}

- (void)mc_customCountChanged {
    NSInteger val = [self.customCountField.text integerValue];
    self.selectedCloneCount = (val >= 1) ? (NSUInteger)val : 1;
    [self mc_updateNamingPreview];
    [self mc_validateBundleIDLive];
}

- (void)mc_updateNamingPreview {
    if (!self.currentReport) return;
    MCCloneEngine *engine = [MCCloneEngine sharedEngine];
    NSUInteger startSeq = [engine nextSequenceNumberForSource:self.currentReport.bundleID];
    NSString *base = self.baseNameField.text.length > 0 ? self.baseNameField.text : @"app";
    NSUInteger count = MAX((NSUInteger)1, self.selectedCloneCount);

    NSMutableArray<NSString *> *samples = [NSMutableArray array];
    NSUInteger previewMax = MIN(count, (NSUInteger)5);
    for (NSUInteger i = 0; i < previewMax; i++) {
        [samples addObject:[engine formattedNumberedNameWithBase:base sequenceNumber:(startSeq + i)]];
    }
    NSString *suffix = (count > previewMax)
        ? [NSString stringWithFormat:@" ... %lu_%@", (unsigned long)(startSeq + count - 1), base]
        : @"";
    self.namingPreviewLabel.text = [NSString stringWithFormat:@"Xem trước (%lu bản): %@%@",
        (unsigned long)count, [samples componentsJoinedByString:@", "], suffix];

    BOOL isBatch = (count > 1);
    self.bundleIDField.enabled = !isBatch;
    self.bundleIDField.alpha = isBatch ? 0.65 : 1.0;

    NSString *btnTitle = isBatch
        ? [NSString stringWithFormat:@"Tạo %lu bản Clone (%@ → ...)", (unsigned long)count, samples.firstObject ?: @""]
        : [NSString stringWithFormat:@"Tạo bản Clone (%@)", samples.firstObject ?: @""];
    [self.confirmButton setTitle:btnTitle forState:UIControlStateNormal];
}

- (void)mc_validateBundleIDLive {
    if (!self.currentReport) return;
    if (self.selectedCloneCount > 1) {
        self.bundleValidationLabel.text = [NSString stringWithFormat:
            @"Chế độ hàng loạt: tự động sinh %lu Bundle ID độc lập (%@.multiclone.xxx).",
            (unsigned long)self.selectedCloneCount, self.currentReport.bundleID];
        self.bundleValidationLabel.textColor = [MCTheme successColor];
        [self mc_updateConfirmState];
        return;
    }

    NSError *err = nil;
    BOOL valid = [[MCCloneEngine sharedEngine] validateTargetBundleID:self.bundleIDField.text
                                                       sourceBundleID:self.currentReport.bundleID
                                                                error:&err];
    if (valid) {
        self.bundleValidationLabel.text = @"Bundle ID hợp lệ và không trùng lặp.";
        self.bundleValidationLabel.textColor = [MCTheme successColor];
    } else {
        self.bundleValidationLabel.text = err.localizedDescription;
        self.bundleValidationLabel.textColor = [MCTheme dangerColor];
    }
    [self mc_updateConfirmState];
}

- (void)mc_updateConfirmState {
    if (!self.currentReport) {
        self.confirmButton.enabled = NO;
        self.confirmButton.alpha = 0.5;
        return;
    }
    BOOL blocked = (self.currentReport.compatibilityStatus == MCCompatibilityStatusIncompatible);
    BOOL needsAck = (self.currentReport.compatibilityStatus == MCCompatibilityStatusPartialWarning && !self.acknowledgeWarningsSwitch.isOn);
    BOOL validBID = (self.selectedCloneCount > 1) ||
        [[MCCloneEngine sharedEngine] validateTargetBundleID:self.bundleIDField.text
                                              sourceBundleID:self.currentReport.bundleID
                                                       error:nil];
    BOOL enabled = !blocked && !needsAck && validBID;
    self.confirmButton.enabled = enabled;
    self.confirmButton.alpha = enabled ? 1.0 : 0.45;
}

- (void)mc_pickCustomIcon {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    if (img) {
        self.selectedCustomIcon = img;
        self.appIconView.image = img;
        [self.pickIconButton setTitle:@"Đã chọn biểu tượng tùy chỉnh (nhấn để đổi lại)" forState:UIControlStateNormal];
    }
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)mc_extractOriginalIPAOnly {
    if (!self.currentReport) return;
    self.progressView.hidden = NO;
    self.progressStageLabel.hidden = NO;
    self.extractOnlyIPAButton.enabled = NO;

    [[MCCloneEngine sharedEngine] extractIPAFromInstalledAppReport:self.currentReport
                                                          progress:^(double fraction, NSString *stage) {
        self.progressView.progress = (float)fraction;
        self.progressStageLabel.text = stage;
    } completion:^(NSString * _Nullable ipaPath, NSError * _Nullable error) {
        self.extractOnlyIPAButton.enabled = YES;
        if (!ipaPath) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Trích xuất IPA thất bại"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"Đã trích xuất IPA thành công"
                                                                    message:[NSString stringWithFormat:@"Lưu tại:\n%@", ipaPath]
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"Chia sẻ tệp IPA" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a;
            UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:ipaPath]] applicationActivities:nil];
            [self presentViewController:vc animated:YES completion:nil];
        }]];
        [ok addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:ok animated:YES completion:nil];
    }];
}

- (void)mc_confirmCreateClone {
    if (!self.currentReport) return;

    MCBatchCloneConfiguration *cfg = [[MCBatchCloneConfiguration alloc] init];
    cfg.inspectionReport = self.currentReport;
    cfg.baseDisplayName = self.baseNameField.text ?: @"app";
    cfg.cloneCount = MAX((NSUInteger)1, self.selectedCloneCount);
    cfg.customSingleBundleID = (cfg.cloneCount == 1) ? self.bundleIDField.text : nil;
    cfg.customIcon = self.selectedCustomIcon;
    cfg.acknowledgeWarnings = self.acknowledgeWarningsSwitch.isOn;
    cfg.exportClonedIPA = self.exportIPASwitch.isOn;
    cfg.alsoExportOriginalExtractedIPA = NO;

    self.confirmButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressStageLabel.hidden = NO;
    self.progressView.progress = 0.05f;

    [[MCCloneEngine sharedEngine] createBatchClonesWithConfiguration:cfg
                                                            progress:^(double fraction, NSString *stage) {
        self.progressView.progress = (float)fraction;
        self.progressStageLabel.text = stage;
    } completion:^(MCBatchCloneResult * _Nullable result, NSError * _Nullable error) {
        self.confirmButton.enabled = YES;
        if (error || !result || result.createdRecords.count == 0) {
            NSString *msg = error.localizedDescription ?: result.failureMessages.firstObject ?: @"Đã xảy ra lỗi và hệ thống đã hoàn tác sạch sẽ.";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tạo Clone thất bại (Đã khôi phục)"
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }

        [self mc_updateNamingPreview];
        if (result.createdRecords.count == 1) {
            MCCloneDetailViewController *detail = [[MCCloneDetailViewController alloc] initWithCloneID:result.createdRecords.firstObject.cloneID];
            [self.navigationController pushViewController:detail animated:YES];
        } else {
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            for (MCCloneRecord *r in result.createdRecords) {
                [names addObject:r.displayName];
            }
            NSString *summary = [NSString stringWithFormat:@"Đã tạo thành công %lu bản clone:\n%@\n\nCác tệp .ipa đã lưu tại:\n%@",
                (unsigned long)result.createdRecords.count,
                [names componentsJoinedByString:@", "],
                MCExportsDirectory()];
            if (result.failureMessages.count > 0) {
                summary = [summary stringByAppendingFormat:@"\n\nLỗi (%lu):\n%@",
                    (unsigned long)result.failureMessages.count,
                    [result.failureMessages componentsJoinedByString:@"\n"]];
            }
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Nhân bản hàng loạt hoàn tất"
                                                                          message:summary
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"Xem danh sách ở Trang chủ" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                (void)a;
                if (self.tabBarController) self.tabBarController.selectedIndex = 0;
            }]];
            [done addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:done animated:YES completion:nil];
        }
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
