#import "MCLogViewerViewController.h"
#import "MCTheme.h"
#import "../../Source/Logger/MCLogger.h"

@interface MCLogViewerViewController ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation MCLogViewerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Nhật ký hệ thống";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [MCTheme backgroundColor];

    UIBarButtonItem *shareBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                              target:self
                                                                              action:@selector(mc_shareLogs)];
    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:@"Xóa"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(mc_clearLogs)];
    clearBtn.tintColor = [MCTheme dangerColor];
    self.navigationItem.rightBarButtonItems = @[clearBtn, shareBtn];

    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.backgroundColor = [MCTheme surfaceColor];
    self.textView.textColor = [MCTheme primaryTextColor];
    self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.textView.layer.cornerRadius = 12.0;
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.view addSubview:self.textView];

    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12]
    ]];

    [self mc_reloadLogs];
}

- (void)mc_reloadLogs {
    self.textView.text = [[MCLogger sharedLogger] readRecentLogsMaxBytes:128 * 1024];
}

- (void)mc_shareLogs {
    NSString *logs = self.textView.text ?: @"";
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[logs] applicationActivities:nil];
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)mc_clearLogs {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa nhật ký?"
                                                                   message:@"Thao tác này chỉ xóa tệp nhật ký lỗi của MultiClone."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)a;
        [[MCLogger sharedLogger] clearLogs];
        [self mc_reloadLogs];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
