#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Built-in Dark Mode local IPA file browser that directly reads iOS Files ("On My iPhone"
/// File Provider Storage, Safari Downloads), /var/mobile/Downloads, /var/mobile/Documents,
/// and MultiClone Exports without being blocked by UIDocumentPickerViewController sandbox bugs.
@interface MCFileBrowserViewController : UITableViewController

@property (nonatomic, copy, nullable) void (^onSelectIPAPath)(NSString *ipaPath);

- (instancetype)initWithDirectoryPath:(nullable NSString *)directoryPath title:(nullable NSString *)title;

@end

NS_ASSUME_NONNULL_END
