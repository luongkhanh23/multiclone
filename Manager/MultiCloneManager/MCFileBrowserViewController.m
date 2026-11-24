#import "MCFileBrowserViewController.h"
#import "MCTheme.h"
#import "../../Source/MultiCloneCore/MCConstants.h"

@interface MCFileBrowserShortcut : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *path;
@end

@implementation MCFileBrowserShortcut
@end

@interface MCFileBrowserViewController ()
@property (nonatomic, copy, nullable) NSString *currentDirPath;
@property (nonatomic, copy) NSArray<MCFileBrowserShortcut *> *shortcuts;
@property (nonatomic, copy) NSArray<NSString *> *subdirectories;
@property (nonatomic, copy) NSArray<NSString *> *ipaFiles;
@end

@implementation MCFileBrowserViewController

- (instancetype)initWithDirectoryPath:(nullable NSString *)directoryPath title:(nullable NSString *)title {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _currentDirPath = [directoryPath copy];
        self.title = title ?: (directoryPath ? directoryPath.lastPathComponent : @"Chọn tệp IPA trên máy");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = [MCTheme backgroundColor];
    self.tableView.separatorColor = [MCTheme borderColor];

    if (!self.currentDirPath) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:@"Đóng" style:UIBarButtonItemStylePlain target:self action:@selector(mc_close)];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:@"Nhập đường dẫn" style:UIBarButtonItemStylePlain target:self action:@selector(mc_promptPath)];
    }

    [self mc_loadEntries];
}

- (void)mc_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)mc_promptPath {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nhập đường dẫn tệp .ipa"
                                                                   message:@"Dán đường dẫn đầy đủ tới tệp .ipa hoặc .tipa:"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"/var/mobile/Downloads/TikTok.ipa";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Chọn" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *p = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (p.length > 0) [self mc_finishWithIPAPath:p];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)mc_finishWithIPAPath:(NSString *)path {
    void (^cb)(NSString *) = self.onSelectIPAPath;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(path);
    }];
}

/// Discovers "On My iPhone" (Files app File Provider Storage) and Downloads automatically.
- (NSArray<MCFileBrowserShortcut *> *)mc_discoverShortcuts {
    NSMutableArray<MCFileBrowserShortcut *> *list = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    void (^addIfExists)(NSString *, NSString *, NSString *) = ^(NSString *title, NSString *subtitle, NSString *p) {
        BOOL isDir = NO;
        if (p.length > 0 && [fm fileExistsAtPath:p isDirectory:&isDir] && isDir) {
            for (MCFileBrowserShortcut *existing in list) {
                if ([existing.path isEqualToString:p]) return;
            }
            MCFileBrowserShortcut *s = [[MCFileBrowserShortcut alloc] init];
            s.title = title;
            s.subtitle = subtitle;
            s.path = p;
            [list addObject:s];
        }
    };

    // 1. Discover iOS Files.app "On My iPhone" (File Provider Storage) & Safari Downloads
    NSString *appGroupBase = @"/var/mobile/Containers/Shared/AppGroup";
    for (NSString *uuid in ([fm contentsOfDirectoryAtPath:appGroupBase error:nil] ?: @[])) {
        NSString *fpStorage = [[appGroupBase stringByAppendingPathComponent:uuid]
                               stringByAppendingPathComponent:@"File Provider Storage"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:fpStorage isDirectory:&isDir] && isDir) {
            NSString *downloads = [fpStorage stringByAppendingPathComponent:@"Downloads"];
            addIfExists(@"Tải về (Tệp / Safari Downloads)", @"Trên iPhone của tôi → Downloads", downloads);
            addIfExists(@"Trên iPhone của tôi (Ứng dụng Tệp)", fpStorage, fpStorage);
        }
    }

    // 2. iCloud Drive (Mobile Documents)
    addIfExists(@"iCloud Drive", @"Mobile Documents", @"/var/mobile/Library/Mobile Documents/com~apple~CloudDocs");

    // 3. Standard jailbreak & MultiClone locations
    addIfExists(@"MultiClone Exports", MCExportsDirectory(), MCExportsDirectory());
    addIfExists(@"/var/mobile/Downloads", @"Thư mục Downloads cục bộ", @"/var/mobile/Downloads");
    addIfExists(@"/var/mobile/Documents", @"Thư mục Documents cục bộ", @"/var/mobile/Documents");
    addIfExists(@"/var/mobile/Media/Downloads", @"Media Downloads", @"/var/mobile/Media/Downloads");
    addIfExists(@"/var/mobile", @"Thư mục gốc /var/mobile", @"/var/mobile");

    return [list copy];
}

- (void)mc_loadEntries {
    NSFileManager *fm = [NSFileManager defaultManager];

    if (!self.currentDirPath) {
        self.shortcuts = [self mc_discoverShortcuts];
        // Also scan all shortcut roots for immediate 1-tap .ipa files
        NSMutableArray<NSString *> *quickIPAs = [NSMutableArray array];
        for (MCFileBrowserShortcut *sc in self.shortcuts) {
            if ([sc.path isEqualToString:@"/var/mobile"]) continue;
            for (NSString *name in ([fm contentsOfDirectoryAtPath:sc.path error:nil] ?: @[])) {
                NSString *low = name.lowercaseString;
                if ([low hasSuffix:@".ipa"] || [low hasSuffix:@".tipa"] || [low hasSuffix:@".zip"]) {
                    NSString *full = [sc.path stringByAppendingPathComponent:name];
                    if (![quickIPAs containsObject:full]) [quickIPAs addObject:full];
                }
            }
        }
        [quickIPAs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent];
        }];
        self.ipaFiles = [quickIPAs copy];
        self.subdirectories = @[];
        [self.tableView reloadData];
        return;
    }

    NSMutableArray<NSString *> *dirs = [NSMutableArray array];
    NSMutableArray<NSString *> *ipas = [NSMutableArray array];
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:self.currentDirPath error:nil] ?: @[];

    for (NSString *name in items) {
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [self.currentDirPath stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir]) continue;
        if (isDir) {
            [dirs addObject:full];
        } else {
            NSString *low = name.lowercaseString;
            if ([low hasSuffix:@".ipa"] || [low hasSuffix:@".tipa"] || [low hasSuffix:@".zip"]) {
                [ipas addObject:full];
            }
        }
    }

    [dirs sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent];
    }];
    [ipas sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent];
    }];

    self.subdirectories = [dirs copy];
    self.ipaFiles = [ipas copy];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (!self.currentDirPath) {
        return (section == 0)
            ? [NSString stringWithFormat:@"Tệp IPA tìm thấy ngay (%lu)", (unsigned long)self.ipaFiles.count]
            : @"Thư mục trên iPhone (Chạm để duyệt)";
    }
    return (section == 0)
        ? [NSString stringWithFormat:@"Tệp IPA / ZIP (%lu)", (unsigned long)self.ipaFiles.count]
        : [NSString stringWithFormat:@"Thư mục con (%lu)", (unsigned long)self.subdirectories.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return MAX((NSInteger)1, (NSInteger)self.ipaFiles.count);
    return !self.currentDirPath ? (NSInteger)self.shortcuts.count : (NSInteger)self.subdirectories.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MCFileCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MCFileCell"];
    }
    cell.backgroundColor = [MCTheme surfaceColor];
    cell.textLabel.textColor = [MCTheme primaryTextColor];
    cell.detailTextLabel.textColor = [MCTheme secondaryTextColor];

    if (indexPath.section == 0) {
        if (self.ipaFiles.count == 0) {
            cell.textLabel.text = @"Không có tệp .ipa trong thư mục này";
            cell.detailTextLabel.text = @"Hãy duyệt vào thư mục Tải về (Downloads) bên dưới";
            cell.imageView.image = [UIImage systemImageNamed:@"doc.questionmark"];
            cell.imageView.tintColor = [MCTheme secondaryTextColor];
            cell.accessoryType = UITableViewCellAccessoryNone;
            return cell;
        }
        NSString *path = self.ipaFiles[indexPath.row];
        unsigned long long sz = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
        NSString *sizeStr = [NSByteCountFormatter stringFromByteCount:(long long)sz countStyle:NSByteCountFormatterCountStyleFile];
        cell.textLabel.text = path.lastPathComponent;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@", sizeStr, path.stringByDeletingLastPathComponent.lastPathComponent];
        cell.imageView.image = [UIImage systemImageNamed:@"doc.zipper"];
        cell.imageView.tintColor = [MCTheme accentColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (!self.currentDirPath) {
        MCFileBrowserShortcut *sc = self.shortcuts[indexPath.row];
        cell.textLabel.text = sc.title;
        cell.detailTextLabel.text = sc.subtitle;
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.imageView.tintColor = [MCTheme warningColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSString *dir = self.subdirectories[indexPath.row];
        cell.textLabel.text = dir.lastPathComponent;
        cell.detailTextLabel.text = @"Thư mục";
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.imageView.tintColor = [MCTheme warningColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (self.ipaFiles.count == 0) return;
        [self mc_finishWithIPAPath:self.ipaFiles[indexPath.row]];
        return;
    }

    NSString *nextDir = !self.currentDirPath ? self.shortcuts[indexPath.row].path : self.subdirectories[indexPath.row];
    NSString *nextTitle = !self.currentDirPath ? self.shortcuts[indexPath.row].title : nextDir.lastPathComponent;
    MCFileBrowserViewController *sub = [[MCFileBrowserViewController alloc] initWithDirectoryPath:nextDir title:nextTitle];
    sub.onSelectIPAPath = self.onSelectIPAPath;
    [self.navigationController pushViewController:sub animated:YES];
}

@end
