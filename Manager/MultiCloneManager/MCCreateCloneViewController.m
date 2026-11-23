#import "MCCreateCloneViewController.h"
#import "MCTheme.h"
#import "MCCloneDetailViewController.h"
#import "../../Source/MultiCloneCore/MCConstants.h"
#import "../../Source/MultiCloneCore/MCModels.h"
#import "../../Source/IPAInspector/MCIPAInspector.h"
#import "../../Source/IconManager/MCIconManager.h"
#import "../../Source/CloneEngine/MCCloneEngine.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MCCreateCloneViewController () <UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;

@property (nonatomic, strong) UIButton *pickIPAButton;
@property (nonatomic, strong) UILabel *selectedFileLabel;
@property (nonatomic, strong) UIActivityIndicatorView *inspectSpinner;

// Inspection summary card
@property (nonatomic, strong) UIView *summaryCard;
@property (nonatomic, strong) UIImageView *appIconView;
@property (nonatomic, strong) UILabel *appTitleLabel;
@property (nonatomic, strong) UILabel *appMetaLabel;
@property (nonatomic, strong) UILabel *compatibilityStatusLabel;
@property (nonatomic, strong) UILabel *compatibilityDetailLabel;

// Form card
@property (nonatomic, strong) UIView *formCard;
@property (nonatomic, strong) UITextField *nameField;
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
@property (nonatomic, copy, nullable) NSString *copiedTempIPAPath;
@end

@implementation MCCreateCloneViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tạo bản Clone";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [MCTheme backgroundColor];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mc_refreshTheme)
                                                 name:MCThemeDidChangeNotification
                                               object:nil];

    [self mc_buildUI];
    [self mc_updateUIForReport:nil];
}

- (void)mc_refreshTheme {
    self.view.backgroundColor = [MCTheme backgroundColor];
    [MCTheme styleCardView:self.summaryCard];
    [MCTheme styleCardView:self.formCard];
    self.pickIPAButton.backgroundColor = [MCTheme accentColor];
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

- (UIButton *)mc_makePrimaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    btn.backgroundColor = [MCTheme accentColor];
    btn.layer.cornerRadius = 12.0;
    [btn.heightAnchor constraintEqualToConstant:48].active = YES;
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
    self.stackView.spacing = 14;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stackView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:16],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-28],
        [self.stackView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32]
    ]];

    // Step 1: IPA Picker
    self.pickIPAButton = [self mc_makePrimaryButtonWithTitle:@"Chọn tệp IPA để phân tích" action:@selector(mc_pickIPA)];
    [self.stackView addArrangedSubview:self.pickIPAButton];

    self.selectedFileLabel = [[UILabel alloc] init];
    self.selectedFileLabel.font = [UIFont systemFontOfSize:13];
    self.selectedFileLabel.textColor = [MCTheme secondaryTextColor];
    self.selectedFileLabel.numberOfLines = 0;
    self.selectedFileLabel.text = @"Chưa chọn tệp IPA. MultiClone sẽ tự động kiểm tra Bundle ID, kiến trúc arm64/arm64e, FairPlay DRM, Frameworks, Extensions và Entitlements.";
    [self.stackView addArrangedSubview:self.selectedFileLabel];

    self.inspectSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.inspectSpinner.hidesWhenStopped = YES;
    self.inspectSpinner.color = [MCTheme accentColor];
    [self.stackView addArrangedSubview:self.inspectSpinner];

    // Step 2: Summary & Compatibility Card
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

    [self.stackView addArrangedSubview:self.summaryCard];

    // Step 3: Clone Configuration Form Card
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

    UILabel *nameTitle = [[UILabel alloc] init];
    nameTitle.text = @"Tên hiển thị bản Clone";
    nameTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    nameTitle.textColor = [MCTheme primaryTextColor];
    [formStack addArrangedSubview:nameTitle];

    self.nameField = [self mc_makeTextFieldWithPlaceholder:@"Ví dụ: App Clone - Công việc"];
    [formStack addArrangedSubview:self.nameField];

    UILabel *bidTitle = [[UILabel alloc] init];
    bidTitle.text = @"Bundle ID mới (độc lập, hợp lệ)";
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

    // Export IPA switch
    UIStackView *exportRow = [[UIStackView alloc] init];
    exportRow.axis = UILayoutConstraintAxisHorizontal;
    exportRow.alignment = UIStackViewAlignmentCenter;
    UILabel *exportLbl = [[UILabel alloc] init];
    exportLbl.text = @"Xuất tệp Clone .ipa vào thư mục Exports";
    exportLbl.font = [UIFont systemFontOfSize:14];
    exportLbl.textColor = [MCTheme primaryTextColor];
    exportLbl.numberOfLines = 0;
    self.exportIPASwitch = [[UISwitch alloc] init];
    self.exportIPASwitch.on = YES;
    self.exportIPASwitch.onTintColor = [MCTheme accentColor];
    [exportRow addArrangedSubview:exportLbl];
    [exportRow addArrangedSubview:self.exportIPASwitch];
    [formStack addArrangedSubview:exportRow];

    // Warning acknowledgement switch
    self.acknowledgeRow = [[UIStackView alloc] init];
    self.acknowledgeRow.axis = UILayoutConstraintAxisHorizontal;
    self.acknowledgeRow.alignment = UIStackViewAlignmentCenter;
    UILabel *ackLbl = [[UILabel alloc] init];
    ackLbl.text = @"Tôi hiểu các cảnh báo tương thích và có quyền chỉnh sửa IPA này";
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
    self.progressStageLabel.hidden = YES;
    [self.stackView addArrangedSubview:self.progressStageLabel];

    self.confirmButton = [self mc_makePrimaryButtonWithTitle:@"Xác nhận tạo bản Clone" action:@selector(mc_confirmCreateClone)];
    [self.stackView addArrangedSubview:self.confirmButton];
}

- (void)mc_pickIPA {
    NSArray<UTType *> *types = @[UTTypeArchive, UTTypeData];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;

    self.selectedFileLabel.text = [NSString stringWithFormat:@"Đang phân tích: %@", url.lastPathComponent];
    [self.inspectSpinner startAnimating];
    self.copiedTempIPAPath = url.path;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        MCIPAInspectionReport *report = [MCIPAInspector inspectIPAAtPath:url.path error:&err];
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

- (void)mc_updateUIForReport:(nullable MCIPAInspectionReport *)report {
    self.currentReport = report;
    self.selectedCustomIcon = nil;

    BOOL hasReport = (report != nil);
    self.summaryCard.hidden = !hasReport;
    self.formCard.hidden = !hasReport;
    self.confirmButton.hidden = !hasReport;

    if (!report) return;

    self.selectedFileLabel.text = [NSString stringWithFormat:@"Đã phân tích xong: %@", report.ipaPath.lastPathComponent];
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
        self.compatibilityStatusLabel.text = @"KHÔNG TƯƠNG THÍCH — ĐÃ CHẶN TẠO CLONE";
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

    // Prefill clone form
    self.nameField.text = [NSString stringWithFormat:@"%@ Clone", report.displayName ?: @"App"];
    self.bundleIDField.text = [[MCCloneEngine sharedEngine] suggestNextBundleIDForSource:report.bundleID];
    self.acknowledgeRow.hidden = (report.compatibilityStatus != MCCompatibilityStatusPartialWarning);
    self.acknowledgeWarningsSwitch.on = NO;

    [self mc_validateBundleIDLive];
}

- (void)mc_validateBundleIDLive {
    if (!self.currentReport) return;
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
    BOOL validBID = [[MCCloneEngine sharedEngine] validateTargetBundleID:self.bundleIDField.text
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

- (void)mc_confirmCreateClone {
    if (!self.currentReport) return;

    MCCloneConfiguration *cfg = [[MCCloneConfiguration alloc] init];
    cfg.inspectionReport = self.currentReport;
    cfg.displayName = self.nameField.text ?: @"";
    cfg.targetBundleID = self.bundleIDField.text ?: @"";
    cfg.customIcon = self.selectedCustomIcon;
    cfg.acknowledgeWarnings = self.acknowledgeWarningsSwitch.isOn;
    cfg.exportClonedIPA = self.exportIPASwitch.isOn;

    self.confirmButton.enabled = NO;
    self.progressView.hidden = NO;
    self.progressStageLabel.hidden = NO;
    self.progressView.progress = 0.05f;

    [[MCCloneEngine sharedEngine] createCloneWithConfiguration:cfg
                                                      progress:^(double fraction, NSString *stage) {
        self.progressView.progress = (float)fraction;
        self.progressStageLabel.text = stage;
    } completion:^(MCCloneRecord * _Nullable record, NSError * _Nullable error) {
        self.confirmButton.enabled = YES;
        if (!record) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Tạo Clone thất bại (Đã khôi phục)"
                                                                           message:error.localizedDescription ?: @"Đã xảy ra lỗi và hệ thống đã hoàn tác sạch sẽ."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }

        MCCloneDetailViewController *detail = [[MCCloneDetailViewController alloc] initWithCloneID:record.cloneID];
        [self.navigationController pushViewController:detail animated:YES];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
