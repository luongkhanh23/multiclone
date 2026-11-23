#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCMachOInspectionResult : NSObject
@property (nonatomic, assign) BOOL isValidMachO;
@property (nonatomic, copy) NSArray<NSString *> *architectures;
@property (nonatomic, assign) BOOL hasEncryptionCommand;
@property (nonatomic, assign) BOOL isEncrypted;
@property (nonatomic, assign) uint32_t cryptID;
@property (nonatomic, assign) BOOL hasCodeSignature;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *entitlements;
@end

/// Read-only Mach-O parser (thin 64-bit and FAT/Universal binaries).
/// Reads CPU architectures, LC_ENCRYPTION_INFO_64 (FairPlay DRM detection),
/// and embedded XML entitlements from LC_CODE_SIGNATURE SuperBlob without executing the binary.
@interface MCMachOInspector : NSObject

+ (MCMachOInspectionResult *)inspectMachOData:(NSData *)binaryData;

@end

NS_ASSUME_NONNULL_END
