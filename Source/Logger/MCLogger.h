#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MCLogLevel) {
    MCLogLevelDebug = 0,
    MCLogLevelInfo = 1,
    MCLogLevelWarning = 2,
    MCLogLevelError = 3
};

@interface MCLogger : NSObject

+ (instancetype)sharedLogger;

- (void)logLevel:(MCLogLevel)level category:(NSString *)category message:(NSString *)message;
- (void)info:(NSString *)category format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
- (void)warn:(NSString *)category format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
- (void)error:(NSString *)category format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

/// Returns recent log text (safe redacted output, never contains raw sensitive tokens).
- (NSString *)readRecentLogsMaxBytes:(NSUInteger)maxBytes;
- (BOOL)clearLogs;
- (NSString *)logFilePath;

/// Redacts potentially sensitive key/value patterns before writing to persistent logs.
+ (NSString *)redactSensitiveText:(NSString *)input;

@end

NS_ASSUME_NONNULL_END
