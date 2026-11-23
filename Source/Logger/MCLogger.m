#import "MCLogger.h"
#import "../MultiCloneCore/MCConstants.h"

static const unsigned long long kMaxLogFileBytes = 512 * 1024; // 512 KB rotation cap

@interface MCLogger ()
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, strong) NSDateFormatter *timestampFormatter;
@property (nonatomic, copy) NSString *filePath;
@end

@implementation MCLogger

+ (instancetype)sharedLogger {
    static MCLogger *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MCLogger alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logQueue = dispatch_queue_create("com.multiclone.logger", DISPATCH_QUEUE_SERIAL);
        _timestampFormatter = [[NSDateFormatter alloc] init];
        _timestampFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _timestampFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        _filePath = [MCLogsDirectory() stringByAppendingPathComponent:@"multiclone.log"];
    }
    return self;
}

- (NSString *)logFilePath {
    return self.filePath;
}

+ (NSString *)redactSensitiveText:(NSString *)input {
    if (input.length == 0) return @"";
    static NSRegularExpression *tokenRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tokenRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)(token|password|passwd|secret|cookie|authorization|session[_-]?key)\\s*[:=]\\s*[^\\s,;\"'\\}]+"
                                                               options:0
                                                                 error:nil];
    });
    return [tokenRegex stringByReplacingMatchesInString:input
                                                options:0
                                                  range:NSMakeRange(0, input.length)
                                           withTemplate:@"$1=[REDACTED]"];
}

- (NSString *)mc_levelString:(MCLogLevel)level {
    switch (level) {
        case MCLogLevelDebug:   return @"DEBUG";
        case MCLogLevelInfo:    return @"INFO";
        case MCLogLevelWarning: return @"WARN";
        case MCLogLevelError:   return @"ERROR";
    }
}

- (void)logLevel:(MCLogLevel)level category:(NSString *)category message:(NSString *)message {
    NSString *safeMsg = [MCLogger redactSensitiveText:message ?: @""];
    NSString *safeCat = category.length > 0 ? category : @"Core";
    NSString *levelStr = [self mc_levelString:level];

    NSLog(@"[MultiClone][%@][%@] %@", levelStr, safeCat, safeMsg);

    dispatch_async(self.logQueue, ^{
        @autoreleasepool {
            NSString *ts = [self.timestampFormatter stringFromDate:[NSDate date]];
            NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\n", ts, levelStr, safeCat, safeMsg];
            NSFileManager *fm = [NSFileManager defaultManager];

            NSDictionary *attrs = [fm attributesOfItemAtPath:self.filePath error:nil];
            if (attrs && [attrs fileSize] > kMaxLogFileBytes) {
                NSString *backup = [self.filePath stringByAppendingString:@".1"];
                [fm removeItemAtPath:backup error:nil];
                [fm moveItemAtPath:self.filePath toPath:backup error:nil];
            }

            if (![fm fileExistsAtPath:self.filePath]) {
                [fm createFileAtPath:self.filePath
                            contents:[line dataUsingEncoding:NSUTF8StringEncoding]
                          attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}];
            } else {
                NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:self.filePath];
                if (fh) {
                    @try {
                        [fh seekToEndOfFile];
                        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                    } @catch (NSException *ex) {
                        (void)ex;
                    }
                    [fh closeFile];
                }
            }
        }
    });
}

- (void)info:(NSString *)category format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logLevel:MCLogLevelInfo category:category message:msg];
}

- (void)warn:(NSString *)category format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logLevel:MCLogLevelWarning category:category message:msg];
}

- (void)error:(NSString *)category format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logLevel:MCLogLevelError category:category message:msg];
}

- (NSString *)readRecentLogsMaxBytes:(NSUInteger)maxBytes {
    __block NSString *result = @"";
    dispatch_sync(self.logQueue, ^{
        NSData *data = [NSData dataWithContentsOfFile:self.filePath];
        if (!data || data.length == 0) {
            result = @"Chưa có nhật ký sự kiện nào.";
            return;
        }
        NSData *slice = data;
        if (maxBytes > 0 && data.length > maxBytes) {
            slice = [data subdataWithRange:NSMakeRange(data.length - maxBytes, maxBytes)];
        }
        result = [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding] ?: @"";
    });
    return result;
}

- (BOOL)clearLogs {
    __block BOOL ok = YES;
    dispatch_sync(self.logQueue, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:self.filePath]) {
            ok = [fm removeItemAtPath:self.filePath error:nil];
        }
        [fm removeItemAtPath:[self.filePath stringByAppendingString:@".1"] error:nil];
    });
    return ok;
}

@end
