#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Trang quản lý clone: mở ứng dụng (có hỗ trợ Auto Close & xác nhận), đổi tên,
/// thay icon, xem thông tin, kiểm tra dung lượng dữ liệu, quản lý dữ liệu độc lập, xóa clone.
@interface MCCloneDetailViewController : UITableViewController

- (instancetype)initWithCloneID:(NSString *)cloneID;

@end

NS_ASSUME_NONNULL_END
