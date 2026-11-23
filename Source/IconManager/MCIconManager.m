#import "MCIconManager.h"
#import "../MultiCloneCore/MCConstants.h"
#import "../Logger/MCLogger.h"

@implementation MCIconManager

+ (instancetype)sharedManager {
    static MCIconManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MCIconManager alloc] init];
    });
    return instance;
}

- (nullable UIImage *)imageFromPNGData:(nullable NSData *)pngData {
    if (pngData.length < 8) return nil;
    return [UIImage imageWithData:pngData];
}

- (UIImage *)mc_resizeImage:(UIImage *)image toSquareSize:(CGFloat)pixels {
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.scale = 1.0;
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(pixels, pixels) format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        [image drawInRect:CGRectMake(0, 0, pixels, pixels)];
    }];
}

- (NSString *)mc_iconPathForCloneID:(NSString *)cloneID {
    NSString *safeID = [[cloneID componentsSeparatedByCharactersInSet:
        [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
    return [MCIconsDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", safeID]];
}

- (nullable NSString *)saveCustomIconImage:(UIImage *)image
                                forCloneID:(NSString *)cloneID
                                     error:(NSError **)error {
    if (!image || cloneID.length == 0) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidArgument, @"Hình ảnh hoặc Clone ID không hợp lệ.");
        return nil;
    }
    UIImage *normalized = [self mc_resizeImage:image toSquareSize:180.0];
    NSData *png = UIImagePNGRepresentation(normalized);
    if (!png) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể mã hóa icon sang định dạng PNG.");
        return nil;
    }
    NSString *dest = [self mc_iconPathForCloneID:cloneID];
    if (!MCIsPathStrictlyInsideDirectory(dest, MCIconsDirectory())) {
        if (error) *error = MCMakeError(MCErrorCodePathOutsideManagedScope, @"Đường dẫn icon nằm ngoài phạm vi quản lý.");
        return nil;
    }
    if (![png writeToFile:dest options:NSDataWritingAtomic error:error]) {
        return nil;
    }
    return dest;
}

- (nullable UIImage *)loadIconForCloneID:(NSString *)cloneID {
    if (cloneID.length == 0) return nil;
    NSString *path = [self mc_iconPathForCloneID:cloneID];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

- (BOOL)deleteIconForCloneID:(NSString *)cloneID {
    if (cloneID.length == 0) return YES;
    NSString *path = [self mc_iconPathForCloneID:cloneID];
    if (!MCIsPathStrictlyInsideDirectory(path, MCIconsDirectory())) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;
    return [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (BOOL)applyCustomIcon:(UIImage *)image
            toAppBundle:(NSString *)appBundlePath
                  error:(NSError **)error {
    if (!image || appBundlePath.length == 0) {
        if (error) *error = MCMakeError(MCErrorCodeInvalidArgument, @"Thiếu hình ảnh hoặc đường dẫn .app bundle.");
        return NO;
    }
    if (!MCIsPathStrictlyInsideDirectory(appBundlePath, MCManagedRootDirectory())) {
        if (error) *error = MCMakeError(MCErrorCodePathOutsideManagedScope, @"Từ chối sửa đổi icon ngoài phạm vi thư mục MultiClone.");
        return NO;
    }

    NSString *iconBase = @"MultiCloneIcon60x60";
    UIImage *img2x = [self mc_resizeImage:image toSquareSize:120.0];
    UIImage *img3x = [self mc_resizeImage:image toSquareSize:180.0];
    NSData *png2x = UIImagePNGRepresentation(img2x);
    NSData *png3x = UIImagePNGRepresentation(img3x);
    if (!png2x || !png3x) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể tạo ảnh PNG @2x/@3x cho icon.");
        return NO;
    }

    NSString *path2x = [appBundlePath stringByAppendingPathComponent:[iconBase stringByAppendingString:@"@2x.png"]];
    NSString *path3x = [appBundlePath stringByAppendingPathComponent:[iconBase stringByAppendingString:@"@3x.png"]];
    if (![png2x writeToFile:path2x options:NSDataWritingAtomic error:error] ||
        ![png3x writeToFile:path3x options:NSDataWritingAtomic error:error]) {
        return NO;
    }

    NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
    if (!info) {
        if (error) *error = MCMakeError(MCErrorCodeIPAMissingInfoPlist, @"Không thể đọc Info.plist của bản clone để cập nhật icon.");
        return NO;
    }

    NSDictionary *primaryIcon = @{
        @"CFBundleIconFiles": @[iconBase],
        @"UIPrerenderedIcon": @YES
    };
    info[@"CFBundleIcons"] = @{@"CFBundlePrimaryIcon": primaryIcon};
    info[@"CFBundleIcons~ipad"] = @{@"CFBundlePrimaryIcon": primaryIcon};
    info[@"CFBundleIconFiles"] = @[iconBase];

    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:info
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:error];
    if (!plistData) return NO;
    return [plistData writeToFile:infoPath options:NSDataWritingAtomic error:error];
}

- (nullable UIImage *)loadIconFromAppBundlePath:(nullable NSString *)appBundlePath {
    if (appBundlePath.length == 0) return nil;
    NSString *infoPath = [appBundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSDictionary *icons = info[@"CFBundleIcons"];
    if ([icons isKindOfClass:[NSDictionary class]]) {
        NSDictionary *primary = icons[@"CFBundlePrimaryIcon"];
        if ([primary isKindOfClass:[NSDictionary class]]) {
            NSArray *files = primary[@"CFBundleIconFiles"];
            if ([files isKindOfClass:[NSArray class]]) [candidates addObjectsFromArray:files];
            NSString *name = primary[@"CFBundleIconName"];
            if ([name isKindOfClass:[NSString class]]) [candidates addObject:name];
        }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:appBundlePath error:nil];
    for (NSString *suffix in @[@"@3x.png", @"@2x.png", @".png"]) {
        for (NSString *prefix in candidates) {
            NSString *full = [appBundlePath stringByAppendingPathComponent:[prefix stringByAppendingString:suffix]];
            if ([fm fileExistsAtPath:full]) {
                UIImage *img = [UIImage imageWithContentsOfFile:full];
                if (img) return img;
            }
        }
    }
    for (NSString *file in entries) {
        if ([file.lowercaseString containsString:@"appicon"] && [file.lowercaseString hasSuffix:@".png"]) {
            UIImage *img = [UIImage imageWithContentsOfFile:[appBundlePath stringByAppendingPathComponent:file]];
            if (img) return img;
        }
    }
    return nil;
}

@end
