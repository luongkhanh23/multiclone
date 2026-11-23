#import "MCCloneDetailViewController.h"
#import "MCTheme.h"
#import "../../Source/MultiCloneCore/MCModels.h"
#import "../../Source/DataManager/MCDataManager.h"
#import "../../Source/IconManager/MCIconManager.h"
#import "../../Source/AutoClose/MCAutoCloseClient.h"

@interface MCCloneDetailViewController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) NSString *cloneID;
@property (nonatomic, strong, nullable) MCCloneRecord *record;
@property (nonatomic, strong, nullable) MCStorageUsage *storageUsage;
@end

@implementation MCCloneDetailViewController

- (instancetype)initWithCloneID:(NSString *)cloneID {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _cloneID = [cloneID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = [MCTheme backgroundColor];
    self.tableView.separatorColor = [MCTheme borderColor];
    [self mc_reloadRecord];
}

- (void)mc_reloadRecord {
    self.record = [[MCDataManager sharedManager] cloneWithID:self.cloneID];
    self.title = self.record.displayName ?: @"Quản lý Clone";
    if (!self.record) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        MCStorageUsage *usage = [[MCDataManager sharedManager] storageUsageForClone:self.record];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.storageUsage = usage;
            [self.tableView reloadData];
        });
    });
}

#pragma mark - Actions

- (void)mc_openCloneApp {
    if (!self.record) return;
    NSString *targetID = self.record.cloneBundleID;
    NSString *previousID = nil;
    MCAutoCloseClient *client = [MCAutoCloseClient sharedClient];

    if ([client shouldPromptConfirmationForLaunchingBundleID:targetID previousBundleOut:&previousID]) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Xác nhận Auto Close"
                                                                         message:[NSString stringWithFormat:@"Đóng ứng dụng clone trước đó (%@) trước khi mở %@?", previousID, self.record.displayName]
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Đóng app trước rồi mở" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            (void)a;
            [self mc_executeLaunchBundleID:targetID allowAutoClose:YES];
        }]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Chỉ mở (giữ app trước)" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            (void)a;
            [self mc_executeLaunchBundleID:targetID allowAutoClose:NO];
        }]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:confirm animated:YES completion:nil];
    } else {
        [self mc_executeLaunchBundleID:targetID allowAutoClose:YES];
    }
}

- (void)mc_executeLaunchBundleID:(NSString *)bundleID allowAutoClose:(BOOL)allowAutoClose {
    [[MCAutoCloseClient sharedClient] openManagedBundleID:bundleID
                                      allowAutoClosePrev:allowAutoClose
                                              completion:^(MCAutoCloseActionResult *result) {
        if (!result.succeeded || result.errorMessage.length > 0) {
            NSString *title = result.succeeded ? @"Thông báo khởi chạy" : @"Không thể mở ứng dụng";
            NSString *msg = result.errorMessage.length > 0
                ? result.errorMessage
                : [NSString stringWithFormat:@"Mã trạng thái: %@. Hãy đảm bảo bản clone IPA đã được ký và cài đặt trên máy.", result.statusCode];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
        [self mc_reloadRecord];
    }];
}

- (void)mc_renameClone {
    if (!self.record) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Đổi tên bản Clone"
                                                                   message:@"Nhập tên hiển thị mới cho bản clone này:"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = self.record.displayName;
        tf.placeholder = @"Tên mới";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        NSString *newName = alert.textFields.firstObject.text ?: @"";
        NSError *err = nil;
        if (![[MCDataManager sharedManager] updateDisplayName:newName forCloneID:self.cloneID error:&err]) {
            [self mc_showSimpleAlert:@"Lỗi đổi tên" message:err.localizedDescription];
        } else {
            [self mc_reloadRecord];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)mc_changeIcon {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *img = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!img || !self.record) return;
        NSError *err = nil;
        NSString *savedPath = [[MCIconManager sharedManager] saveCustomIconImage:img forCloneID:self.record.cloneID error:&err];
        if (!savedPath) {
            [self mc_showSimpleAlert:@"Lỗi lưu Icon" message:err.localizedDescription];
            return;
        }
        if (self.record.bundlePath.length > 0) {
            [[MCIconManager sharedManager] applyCustomIcon:img toAppBundle:self.record.bundlePath error:nil];
        }
        self.record.customIconPath = savedPath;
        [[MCDataManager sharedManager] saveCloneRecord:self.record error:nil];
        [self mc_reloadRecord];
    }];
}

- (void)mc_shareExportedIPA {
    if (!self.record.exportedIPAPath || ![[NSFileManager defaultManager] fileExistsAtPath:self.record.exportedIPAPath]) {
        [self mc_showSimpleAlert:@"Không có IPA xuất" message:@"Bản clone này chưa có tệp .ipa xuất sẵn."];
        return;
    }
    NSURL *url = [NSURL fileURLWithPath:self.record.exportedIPAPath];
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)mc_clearCache {
    if (!self.record) return;
    NSError *err = nil;
    if ([[MCDataManager sharedManager] clearCacheForClone:self.record error:&err]) {
        [self mc_showSimpleAlert:@"Đã xóa bộ nhớ đệm" message:@"Bộ nhớ đệm độc lập của bản clone đã được dọn sạch."];
        [self mc_reloadRecord];
    } else {
        [self mc_showSimpleAlert:@"Lỗi" message:err.localizedDescription];
    }
}

- (void)mc_resetIsolatedData {
    if (!self.record) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Đặt lại dữ liệu độc lập?"
                                                                   message:@"Chỉ dữ liệu trong thư mục cô lập của bản clone này bị xóa. Ứng dụng gốc hoàn toàn không bị ảnh hưởng."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đặt lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)a;
        NSError *err = nil;
        if ([[MCDataManager sharedManager] resetIsolatedDataForClone:self.record error:&err]) {
            [self mc_reloadRecord];
        } else {
            [self mc_showSimpleAlert:@"Lỗi" message:err.localizedDescription];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)mc_exportConfig {
    if (!self.record) return;
    NSError *err = nil;
    NSString *path = [[MCDataManager sharedManager] exportConfigurationForClone:self.record error:&err];
    if (!path) {
        [self mc_showSimpleAlert:@"Lỗi xuất cấu hình" message:err.localizedDescription];
        return;
    }
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)mc_deleteClone {
    if (!self.record) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa bản Clone?"
                                                                   message:[NSString stringWithFormat:@"Xóa bản clone \"%@\" (%@) khỏi MultiClone?\nỨng dụng gốc sẽ KHÔNG bị ảnh hưởng.", self.record.displayName, self.record.cloneBundleID]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Xóa bản Clone" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)a;
        NSError *err = nil;
        if ([[MCDataManager sharedManager] deleteCloneWithID:self.cloneID error:&err]) {
            [self.navigationController popViewControllerAnimated:YES];
        } else {
            [self mc_showSimpleAlert:@"Lỗi xóa bản clone" message:err.localizedDescription];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)mc_showSimpleAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return @"Thao tác nhanh";
        case 1: return @"Thông tin bản Clone";
        case 2: return @"Dung lượng & Dữ liệu độc lập";
        case 3: return @"Vùng nguy hiểm";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return 4; // Open, Rename, Change Icon, Share Exported IPA
        case 1: return 4; // Clone ID, Source ID, Status, Warnings
        case 2: return 5; // Total size, Bundle/Data/Cache detail, Clear Cache, Reset Data, Export Config
        case 3: return 1; // Delete Clone
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"MCDetailCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    }
    cell.backgroundColor = [MCTheme surfaceColor];
    cell.textLabel.textColor = [MCTheme primaryTextColor];
    cell.detailTextLabel.textColor = [MCTheme secondaryTextColor];
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Mở ứng dụng Clone";
            cell.textLabel.textColor = [MCTheme accentColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Đổi tên hiển thị";
            cell.detailTextLabel.text = self.record.displayName;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Thay đổi biểu tượng (Icon)";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Chia sẻ / Cài đặt tệp Clone .ipa";
            cell.detailTextLabel.text = self.record.exportedIPAPath ? @"Sẵn sàng" : @"Chưa xuất";
        }
    } else if (indexPath.section == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Bundle ID Clone";
            cell.detailTextLabel.text = self.record.cloneBundleID;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Bundle ID Gốc";
            cell.detailTextLabel.text = self.record.sourceBundleID;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Trạng thái";
            cell.detailTextLabel.text = [self.record statusDisplayString];
        } else {
            cell.textLabel.text = @"Cảnh báo tương thích";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu mục", (unsigned long)self.record.compatibilityWarnings.count];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Tổng dung lượng quản lý";
            cell.detailTextLabel.text = self.storageUsage ? [self.storageUsage formattedTotalSize] : @"Đang tính...";
        } else if (indexPath.row == 1) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.text = @"Chi tiết (Bundle / Data / Cache)";
            cell.detailTextLabel.text = self.storageUsage
                ? [NSString stringWithFormat:@"%@ / %@ / %@",
                   [MCStorageUsage formatBytes:self.storageUsage.bundleBytes],
                   [MCStorageUsage formatBytes:self.storageUsage.dataBytes],
                   [MCStorageUsage formatBytes:self.storageUsage.cacheBytes]]
                : @"...";
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Xóa bộ nhớ đệm (Cache) độc lập";
            cell.textLabel.textColor = [MCTheme accentColor];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Đặt lại toàn bộ dữ liệu độc lập";
            cell.textLabel.textColor = [MCTheme warningColor];
        } else {
            cell.textLabel.text = @"Xuất tệp cấu hình JSON";
        }
    } else {
        cell.textLabel.text = @"Xóa bản Clone này";
        cell.textLabel.textColor = [MCTheme dangerColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self mc_openCloneApp];
        else if (indexPath.row == 1) [self mc_renameClone];
        else if (indexPath.row == 2) [self mc_changeIcon];
        else if (indexPath.row == 3) [self mc_shareExportedIPA];
    } else if (indexPath.section == 1 && indexPath.row == 3) {
        NSString *msg = self.record.compatibilityWarnings.count > 0
            ? [self.record.compatibilityWarnings componentsJoinedByString:@"\n\n"]
            : @"Không ghi nhận cảnh báo tương thích nào.";
        [self mc_showSimpleAlert:@"Chi tiết tương thích" message:msg];
    } else if (indexPath.section == 2) {
        if (indexPath.row == 2) [self mc_clearCache];
        else if (indexPath.row == 3) [self mc_resetIsolatedData];
        else if (indexPath.row == 4) [self mc_exportConfig];
    } else if (indexPath.section == 3) {
        [self mc_deleteClone];
    }
}

@end
