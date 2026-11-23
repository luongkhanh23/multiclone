#import <UIKit/UIKit.h>
#import "../../Source/MultiCloneCore/MCModels.h"

NS_ASSUME_NONNULL_BEGIN

/// Trang tạo clone:
/// - Trích xuất trực tiếp từ ứng dụng đã cài trên máy HOẶC chọn tệp IPA (Files / Quét nhanh Downloads)
/// - Phân tích IPA/Bundle tự động (Mach-O, FairPlay DRM, Entitlements, Extensions)
/// - Đánh số tự động theo định dạng 1_<ten>, 2_<ten>, ...
/// - Nhân bản hàng loạt nhiều bản cùng lúc (1, 3, 5, 10 hoặc tùy chỉnh N bản)
@interface MCCreateCloneViewController : UIViewController

/// Preloads and inspects an installed app bundle directly (e.g. tapped from Trang chủ).
- (void)loadInstalledAppInfo:(MCInstalledAppInfo *)appInfo;

/// Preloads and inspects an IPA file path directly (e.g. opened from Filza/Safari/Files).
- (void)loadIPAFileAtPath:(NSString *)ipaPath;

@end

NS_ASSUME_NONNULL_END
