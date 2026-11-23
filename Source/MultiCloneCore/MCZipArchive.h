#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCZipEntry : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) uint16_t compressionMethod;
@property (nonatomic, assign) uint32_t crc32;
@property (nonatomic, assign) uint64_t compressedSize;
@property (nonatomic, assign) uint64_t uncompressedSize;
@property (nonatomic, assign) uint64_t localHeaderOffset;
@property (nonatomic, assign) BOOL isDirectory;
@end

/// Lightweight, dependency-free ZIP reader/writer backed by system libz (<zlib.h>).
/// Enforces Zip Slip path traversal protection on extraction.
@interface MCZipArchive : NSObject

+ (nullable instancetype)archiveWithPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;

@property (nonatomic, readonly, copy) NSString *filePath;
@property (nonatomic, readonly, copy) NSArray<MCZipEntry *> *entries;

- (nullable MCZipEntry *)entryWithPath:(NSString *)entryPath;
- (nullable NSData *)dataForEntry:(MCZipEntry *)entry error:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)dataForPath:(NSString *)entryPath error:(NSError * _Nullable * _Nullable)error;

/// Extracts all entries safely inside destinationDirectory (rejects Zip Slip traversal).
- (BOOL)extractAllToDirectory:(NSString *)destinationDirectory
                     progress:(void (^ _Nullable)(double fraction))progressHandler
                        error:(NSError * _Nullable * _Nullable)error;

/// Packages a directory tree into a standard ZIP/IPA archive using DEFLATE compression.
+ (BOOL)createArchiveAtPath:(NSString *)archivePath
          fromRootDirectory:(NSString *)rootDirectory
                      error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
