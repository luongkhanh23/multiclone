#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MCCompatibilityStatus) {
    MCCompatibilityStatusCompatible = 0,
    MCCompatibilityStatusPartialWarning = 1,
    MCCompatibilityStatusIncompatible = 2
};

typedef NS_ENUM(NSInteger, MCCompatibilitySeverity) {
    MCCompatibilitySeverityInfo = 0,
    MCCompatibilitySeverityWarning = 1,
    MCCompatibilitySeverityBlocker = 2
};

typedef NS_ENUM(NSInteger, MCCloneStatus) {
    MCCloneStatusConfigured = 0,
    MCCloneStatusExported = 1,
    MCCloneStatusInstalled = 2,
    MCCloneStatusError = 3
};

@interface MCExtensionInfo : NSObject
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *extensionPointIdentifier;
- (NSDictionary *)toDictionary;
@end

@interface MCCompatibilityIssue : NSObject
@property (nonatomic, assign) MCCompatibilitySeverity severity;
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
+ (instancetype)issueWithSeverity:(MCCompatibilitySeverity)severity
                             code:(NSString *)code
                            title:(NSString *)title
                           detail:(NSString *)detail;
- (NSDictionary *)toDictionary;
@end

@interface MCIPAInspectionReport : NSObject
@property (nonatomic, copy) NSString *ipaPath;
@property (nonatomic, copy) NSString *appFolderPathInZip;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *shortVersion;
@property (nonatomic, copy) NSString *buildVersion;
@property (nonatomic, copy) NSString *executableName;
@property (nonatomic, copy, nullable) NSString *minimumOSVersion;
@property (nonatomic, copy) NSArray<NSString *> *supportedPlatforms;
@property (nonatomic, copy) NSArray<NSString *> *urlSchemes;
@property (nonatomic, copy) NSArray<NSString *> *architectures;
@property (nonatomic, copy) NSArray<NSString *> *frameworks;
@property (nonatomic, copy) NSArray<MCExtensionInfo *> *extensions;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *entitlements;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *provisioningProfile;
@property (nonatomic, assign) BOOL hasEmbeddedProvisioningProfile;
@property (nonatomic, assign) BOOL isFairPlayEncrypted;
@property (nonatomic, assign) uint32_t encryptionCryptID;
@property (nonatomic, copy, nullable) NSData *iconPNGData;
@property (nonatomic, copy, nullable) NSString *iconEntryPath;
@property (nonatomic, assign) BOOL isIconCgBIEncoded;
@property (nonatomic, assign) MCCompatibilityStatus compatibilityStatus;
@property (nonatomic, copy) NSString *compatibilitySummary;
@property (nonatomic, copy) NSArray<MCCompatibilityIssue *> *issues;
- (NSDictionary *)toDictionary;
@end

@interface MCInstalledAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *shortVersion;
@property (nonatomic, copy, nullable) NSString *bundlePath;
@property (nonatomic, copy, nullable) NSString *dataContainerPath;
@property (nonatomic, assign) BOOL isSystemApp;
@property (nonatomic, assign) BOOL isManagedClone;
@end

@interface MCStorageUsage : NSObject
@property (nonatomic, assign) unsigned long long bundleBytes;
@property (nonatomic, assign) unsigned long long dataBytes;
@property (nonatomic, assign) unsigned long long cacheBytes;
@property (nonatomic, readonly) unsigned long long totalBytes;
- (NSString *)formattedTotalSize;
+ (NSString *)formatBytes:(unsigned long long)bytes;
@end

@interface MCCloneRecord : NSObject
@property (nonatomic, copy) NSString *cloneID;
@property (nonatomic, copy) NSString *sourceBundleID;
@property (nonatomic, copy) NSString *cloneBundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *sourceVersion;
@property (nonatomic, copy, nullable) NSString *sourceIPAPath;
@property (nonatomic, copy) NSString *cloneDirectoryPath;
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic, copy) NSString *isolatedDataPath;
@property (nonatomic, copy, nullable) NSString *exportedIPAPath;
@property (nonatomic, copy, nullable) NSString *customIconPath;
@property (nonatomic, assign) MCCloneStatus status;
@property (nonatomic, assign) MCCompatibilityStatus compatibilityStatus;
@property (nonatomic, copy) NSArray<NSString *> *compatibilityWarnings;
@property (nonatomic, copy) NSDate *createdAt;
@property (nonatomic, copy) NSDate *updatedAt;
@property (nonatomic, copy, nullable) NSDate *lastOpenedAt;

+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
- (NSString *)statusDisplayString;
@end

NS_ASSUME_NONNULL_END
