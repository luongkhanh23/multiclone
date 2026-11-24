#import "MCZipArchive.h"
#import "MCConstants.h"
#import <zlib.h>

static const uint32_t kZipLocalHeaderSig   = 0x04034b50;
static const uint32_t kZipCentralDirSig    = 0x02014b50;
static const uint32_t kZipEndOfCentralSig  = 0x06054b50;
static const uint16_t kZipMethodStore      = 0;
static const uint16_t kZipMethodDeflate    = 8;

static inline uint16_t MCReadLE16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static inline uint32_t MCReadLE32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static inline void MCAppendLE16(NSMutableData *buf, uint16_t v) {
    uint8_t b[2] = { (uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF) };
    [buf appendBytes:b length:2];
}

static inline void MCAppendLE32(NSMutableData *buf, uint32_t v) {
    uint8_t b[4] = {
        (uint8_t)(v & 0xFF),
        (uint8_t)((v >> 8) & 0xFF),
        (uint8_t)((v >> 16) & 0xFF),
        (uint8_t)((v >> 24) & 0xFF)
    };
    [buf appendBytes:b length:4];
}

static BOOL MCIsSafeRelativeZipPath(NSString *entryPath) {
    if (entryPath.length == 0) return NO;
    if ([entryPath hasPrefix:@"/"] || [entryPath hasPrefix:@"\\"]) return NO;
    if ([entryPath containsString:@"\0"]) return NO;
    NSArray<NSString *> *parts = [entryPath componentsSeparatedByString:@"/"];
    for (NSString *part in parts) {
        if ([part isEqualToString:@".."]) {
            return NO;
        }
    }
    return YES;
}

@implementation MCZipEntry
@end

@interface MCZipArchive ()
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSArray<MCZipEntry *> *entries;
@property (nonatomic, strong) NSDictionary<NSString *, MCZipEntry *> *entryMap;
@end

@implementation MCZipArchive

+ (nullable instancetype)archiveWithPath:(NSString *)path error:(NSError **)error {
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, @"Không tìm thấy tệp IPA/ZIP.");
        return nil;
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể mở tệp IPA để đọc.");
        return nil;
    }

    @try {
        unsigned long long fileSize = [fh seekToEndOfFile];
        if (fileSize < 22) {
            [fh closeFile];
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, @"Tệp ZIP quá nhỏ hoặc bị hỏng.");
            return nil;
        }

        unsigned long long tailSize = MIN(fileSize, (unsigned long long)(22 + 65535));
        [fh seekToFileOffset:(fileSize - tailSize)];
        NSData *tail = [fh readDataOfLength:(NSUInteger)tailSize];
        const uint8_t *bytes = (const uint8_t *)tail.bytes;
        NSInteger eocdOffset = -1;
        for (NSInteger i = (NSInteger)tail.length - 22; i >= 0; i--) {
            if (MCReadLE32(bytes + i) == kZipEndOfCentralSig) {
                eocdOffset = i;
                break;
            }
        }
        if (eocdOffset < 0) {
            [fh closeFile];
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, @"Không tìm thấy chữ ký ZIP End of Central Directory.");
            return nil;
        }

        uint16_t entryCount = MCReadLE16(bytes + eocdOffset + 10);
        uint32_t cdSize = MCReadLE32(bytes + eocdOffset + 12);
        uint32_t cdOffset = MCReadLE32(bytes + eocdOffset + 16);

        if ((unsigned long long)cdOffset + (unsigned long long)cdSize > fileSize) {
            [fh closeFile];
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, @"Bảng mục lục ZIP (Central Directory) không hợp lệ.");
            return nil;
        }

        [fh seekToFileOffset:cdOffset];
        NSData *cdData = [fh readDataOfLength:cdSize];
        [fh closeFile];

        const uint8_t *cdBytes = (const uint8_t *)cdData.bytes;
        NSUInteger pos = 0;
        NSMutableArray<MCZipEntry *> *entries = [NSMutableArray arrayWithCapacity:entryCount];
        NSMutableDictionary<NSString *, MCZipEntry *> *entryMap = [NSMutableDictionary dictionaryWithCapacity:entryCount];

        while (pos + 46 <= cdData.length) {
            if (MCReadLE32(cdBytes + pos) != kZipCentralDirSig) {
                break;
            }
            uint16_t method = MCReadLE16(cdBytes + pos + 10);
            uint32_t crc = MCReadLE32(cdBytes + pos + 16);
            uint32_t compSize = MCReadLE32(cdBytes + pos + 20);
            uint32_t uncompSize = MCReadLE32(cdBytes + pos + 24);
            uint16_t nameLen = MCReadLE16(cdBytes + pos + 28);
            uint16_t extraLen = MCReadLE16(cdBytes + pos + 30);
            uint16_t commentLen = MCReadLE16(cdBytes + pos + 32);
            uint32_t localOffset = MCReadLE32(cdBytes + pos + 42);

            if (pos + 46 + nameLen + extraLen + commentLen > cdData.length) {
                break;
            }

            NSString *name = [[NSString alloc] initWithBytes:(cdBytes + pos + 46)
                                                      length:nameLen
                                                    encoding:NSUTF8StringEncoding];
            if (!name) {
                name = [[NSString alloc] initWithBytes:(cdBytes + pos + 46)
                                                length:nameLen
                                              encoding:NSISOLatin1StringEncoding];
            }
            if (name.length > 0) {
                MCZipEntry *entry = [[MCZipEntry alloc] init];
                entry.path = name;
                entry.compressionMethod = method;
                entry.crc32 = crc;
                entry.compressedSize = compSize;
                entry.uncompressedSize = uncompSize;
                entry.localHeaderOffset = localOffset;
                entry.isDirectory = [name hasSuffix:@"/"];
                [entries addObject:entry];
                entryMap[name] = entry;
            }
            pos += 46 + nameLen + extraLen + commentLen;
        }

        MCZipArchive *archive = [[MCZipArchive alloc] init];
        archive.filePath = path;
        archive.entries = [entries copy];
        archive.entryMap = [entryMap copy];
        return archive;
    } @catch (NSException *ex) {
        [fh closeFile];
        if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, [NSString stringWithFormat:@"Lỗi đọc tệp ZIP: %@", ex.reason]);
        return nil;
    }
}

- (nullable MCZipEntry *)entryWithPath:(NSString *)entryPath {
    return self.entryMap[entryPath];
}

- (nullable NSData *)dataForPath:(NSString *)entryPath error:(NSError **)error {
    MCZipEntry *entry = [self entryWithPath:entryPath];
    if (!entry) {
        if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, [NSString stringWithFormat:@"Không tìm thấy mục trong IPA: %@", entryPath]);
        return nil;
    }
    return [self dataForEntry:entry error:error];
}

- (nullable NSData *)dataForEntry:(MCZipEntry *)entry error:(NSError **)error {
    if (!entry || entry.isDirectory) {
        return [NSData data];
    }

    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:self.filePath];
    if (!fh) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể mở tệp IPA.");
        return nil;
    }

    @try {
        [fh seekToFileOffset:entry.localHeaderOffset];
        NSData *lh = [fh readDataOfLength:30];
        if (lh.length < 30) {
            [fh closeFile];
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, @"Header cục bộ ZIP bị lỗi.");
            return nil;
        }
        const uint8_t *lhBytes = (const uint8_t *)lh.bytes;
        if (MCReadLE32(lhBytes) != kZipLocalHeaderSig) {
            [fh closeFile];
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, @"Chữ ký local header ZIP không khớp.");
            return nil;
        }
        uint16_t nameLen = MCReadLE16(lhBytes + 26);
        uint16_t extraLen = MCReadLE16(lhBytes + 28);
        [fh seekToFileOffset:(entry.localHeaderOffset + 30 + nameLen + extraLen)];
        NSData *compressed = [fh readDataOfLength:(NSUInteger)entry.compressedSize];
        [fh closeFile];

        if (entry.compressionMethod == kZipMethodStore) {
            return compressed;
        }
        if (entry.compressionMethod != kZipMethodDeflate) {
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted,
                [NSString stringWithFormat:@"Phương thức nén ZIP không được hỗ trợ (%u).", entry.compressionMethod]);
            return nil;
        }

        // Raw DEFLATE inflate via zlib (-MAX_WBITS)
        z_stream strm;
        memset(&strm, 0, sizeof(strm));
        strm.next_in = (Bytef *)compressed.bytes;
        strm.avail_in = (uInt)compressed.length;

        if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) {
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, @"Không thể khởi tạo zlib inflate.");
            return nil;
        }

        NSUInteger initialCap = (entry.uncompressedSize > 0 && entry.uncompressedSize < 128 * 1024 * 1024)
            ? (NSUInteger)entry.uncompressedSize : 65536;
        NSMutableData *outData = [NSMutableData dataWithCapacity:initialCap];
        uint8_t chunk[32768];
        int status = Z_OK;

        while (status == Z_OK) {
            strm.next_out = chunk;
            strm.avail_out = sizeof(chunk);
            status = inflate(&strm, Z_NO_FLUSH);
            NSUInteger produced = sizeof(chunk) - strm.avail_out;
            if (produced > 0) {
                [outData appendBytes:chunk length:produced];
            }
        }
        inflateEnd(&strm);

        if (status != Z_STREAM_END) {
            if (error) *error = MCMakeError(MCErrorCodeIPACorrupted,
                [NSString stringWithFormat:@"Giải nén DEFLATE thất bại cho %@.", entry.path]);
            return nil;
        }
        return outData;
    } @catch (NSException *ex) {
        [fh closeFile];
        if (error) *error = MCMakeError(MCErrorCodeIPACorrupted, ex.reason ?: @"Lỗi giải nén ZIP.");
        return nil;
    }
}

- (BOOL)extractAllToDirectory:(NSString *)destinationDirectory
                     progress:(void (^ _Nullable)(double fraction))progressHandler
                        error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:destinationDirectory withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSUInteger total = MAX((NSUInteger)1, self.entries.count);
    NSUInteger idx = 0;

    for (MCZipEntry *entry in self.entries) {
        @autoreleasepool {
            if (!MCIsSafeRelativeZipPath(entry.path)) {
                if (error) {
                    *error = MCMakeError(MCErrorCodePathTraversalBlocked,
                        [NSString stringWithFormat:@"Chặn đường dẫn không an toàn (Zip Slip): %@", entry.path]);
                }
                return NO;
            }

            NSString *destPath = [destinationDirectory stringByAppendingPathComponent:entry.path];
            if (!MCIsPathStrictlyInsideDirectory(destPath, destinationDirectory)) {
                if (error) {
                    *error = MCMakeError(MCErrorCodePathTraversalBlocked,
                        [NSString stringWithFormat:@"Đường dẫn đích thoát khỏi thư mục giải nén: %@", entry.path]);
                }
                return NO;
            }

            if (entry.isDirectory) {
                if (![fm createDirectoryAtPath:destPath withIntermediateDirectories:YES attributes:nil error:error]) {
                    return NO;
                }
            } else {
                NSString *parent = [destPath stringByDeletingLastPathComponent];
                if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:error]) {
                    return NO;
                }
                NSData *content = [self dataForEntry:entry error:error];
                if (!content) {
                    return NO;
                }
                if (![content writeToFile:destPath options:NSDataWritingAtomic error:error]) {
                    return NO;
                }
                // Preserve executable bit for Mach-O binaries (MH_MAGIC_64 / FAT_MAGIC)
                if (content.length >= 4) {
                    uint32_t magic = 0;
                    [content getBytes:&magic length:4];
                    if (magic == 0xfeedfacf || magic == 0xfeedface || magic == 0xbebafeca || magic == 0xcafebabe) {
                        [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:destPath error:nil];
                    }
                }
            }
            idx++;
            if (progressHandler && (idx % 16 == 0 || idx == total)) {
                progressHandler((double)idx / (double)total);
            }
        }
    }
    return YES;
}

+ (nullable NSData *)mc_deflateRaw:(NSData *)input {
    if (input.length == 0) return [NSData data];
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef *)input.bytes;
    strm.avail_in = (uInt)input.length;
    if (deflateInit2(&strm, Z_BEST_SPEED, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    NSMutableData *out = [NSMutableData dataWithCapacity:(input.length / 2 + 128)];
    uint8_t buf[32768];
    int status = Z_OK;
    while (status == Z_OK) {
        strm.next_out = buf;
        strm.avail_out = sizeof(buf);
        status = deflate(&strm, Z_FINISH);
        NSUInteger produced = sizeof(buf) - strm.avail_out;
        if (produced > 0) {
            [out appendBytes:buf length:produced];
        }
    }
    deflateEnd(&strm);
    return (status == Z_STREAM_END) ? out : nil;
}

+ (BOOL)createArchiveAtPath:(NSString *)archivePath
          fromRootDirectory:(NSString *)rootDirectory
                      error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:rootDirectory];
    if (!enumerator) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể duyệt thư mục để đóng gói IPA.");
        return NO;
    }

    NSString *tmpPath = [archivePath stringByAppendingString:@".tmp"];
    [fm removeItemAtPath:tmpPath error:nil];
    if (![fm createFileAtPath:tmpPath contents:nil attributes:nil]) {
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể tạo tệp IPA tạm trên bộ nhớ.");
        return NO;
    }

    NSFileHandle *outFH = [NSFileHandle fileHandleForWritingAtPath:tmpPath];
    if (!outFH) {
        [fm removeItemAtPath:tmpPath error:nil];
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, @"Không thể mở luồng ghi tệp IPA.");
        return NO;
    }

    NSMutableData *centralDir = [NSMutableData data];
    uint64_t currentOffset = 0;
    uint32_t entryCount = 0;

    @try {
        for (NSString *relPath in enumerator) {
            @autoreleasepool {
                NSString *fullPath = [rootDirectory stringByAppendingPathComponent:relPath];
                NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                NSString *fileType = attrs[NSFileType];
                if (![fileType isEqualToString:NSFileTypeRegular]) {
                    continue;
                }

                NSData *raw = [NSData dataWithContentsOfFile:fullPath options:NSDataReadingMappedIfSafe error:error];
                if (!raw) {
                    [outFH closeFile];
                    [fm removeItemAtPath:tmpPath error:nil];
                    return NO;
                }

                uint32_t crc = (uint32_t)crc32(0L, Z_NULL, 0);
                if (raw.length > 0) {
                    const uint8_t *ptr = (const uint8_t *)raw.bytes;
                    NSUInteger remaining = raw.length;
                    while (remaining > 0) {
                        uInt step = (uInt)MIN(remaining, (NSUInteger)(16 * 1024 * 1024));
                        crc = (uint32_t)crc32(crc, ptr, step);
                        ptr += step;
                        remaining -= step;
                    }
                }

                // Store large media/already-compressed files directly to keep memory low and speed fast
                NSString *ext = relPath.pathExtension.lowercaseString;
                BOOL alreadyCompressed = ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] ||
                                          [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"mp4"] ||
                                          [ext isEqualToString:@"zip"] || [ext isEqualToString:@"car"] ||
                                          raw.length > 24 * 1024 * 1024);

                NSData *payload = raw;
                uint16_t method = kZipMethodStore;
                if (!alreadyCompressed && raw.length > 128) {
                    NSData *compressed = [self mc_deflateRaw:raw];
                    if (compressed && compressed.length < raw.length) {
                        payload = compressed;
                        method = kZipMethodDeflate;
                    }
                }

                NSData *nameData = [relPath dataUsingEncoding:NSUTF8StringEncoding];
                uint32_t localOffset = (uint32_t)currentOffset;

                NSMutableData *lh = [NSMutableData dataWithCapacity:(30 + nameData.length)];
                MCAppendLE32(lh, kZipLocalHeaderSig);
                MCAppendLE16(lh, 20);
                MCAppendLE16(lh, 0);
                MCAppendLE16(lh, method);
                MCAppendLE16(lh, 0);
                MCAppendLE16(lh, 0);
                MCAppendLE32(lh, crc);
                MCAppendLE32(lh, (uint32_t)payload.length);
                MCAppendLE32(lh, (uint32_t)raw.length);
                MCAppendLE16(lh, (uint16_t)nameData.length);
                MCAppendLE16(lh, 0);
                [lh appendData:nameData];

                [outFH writeData:lh];
                if (payload.length > 0) {
                    // Stream payload in 4MB slices so peak RAM stays tiny
                    NSUInteger written = 0;
                    while (written < payload.length) {
                        NSUInteger chunkLen = MIN(payload.length - written, (NSUInteger)(4 * 1024 * 1024));
                        NSData *slice = [NSData dataWithBytesNoCopy:((uint8_t *)payload.bytes + written)
                                                             length:chunkLen
                                                       freeWhenDone:NO];
                        [outFH writeData:slice];
                        written += chunkLen;
                    }
                }
                currentOffset += lh.length + payload.length;

                MCAppendLE32(centralDir, kZipCentralDirSig);
                MCAppendLE16(centralDir, 20);
                MCAppendLE16(centralDir, 20);
                MCAppendLE16(centralDir, 0);
                MCAppendLE16(centralDir, method);
                MCAppendLE16(centralDir, 0);
                MCAppendLE16(centralDir, 0);
                MCAppendLE32(centralDir, crc);
                MCAppendLE32(centralDir, (uint32_t)payload.length);
                MCAppendLE32(centralDir, (uint32_t)raw.length);
                MCAppendLE16(centralDir, (uint16_t)nameData.length);
                MCAppendLE16(centralDir, 0);
                MCAppendLE16(centralDir, 0);
                MCAppendLE16(centralDir, 0);
                MCAppendLE16(centralDir, 0);
                MCAppendLE32(centralDir, 0);
                MCAppendLE32(centralDir, localOffset);
                [centralDir appendData:nameData];
                entryCount++;
            }
        }

        uint32_t cdOffset = (uint32_t)currentOffset;
        [outFH writeData:centralDir];

        uint16_t eocdCount = (uint16_t)MIN(entryCount, (uint32_t)0xFFFF);
        NSMutableData *eocd = [NSMutableData dataWithCapacity:22];
        MCAppendLE32(eocd, kZipEndOfCentralSig);
        MCAppendLE16(eocd, 0);
        MCAppendLE16(eocd, 0);
        MCAppendLE16(eocd, eocdCount);
        MCAppendLE16(eocd, eocdCount);
        MCAppendLE32(eocd, (uint32_t)centralDir.length);
        MCAppendLE32(eocd, cdOffset);
        MCAppendLE16(eocd, 0);
        [outFH writeData:eocd];
        [outFH closeFile];

        [fm removeItemAtPath:archivePath error:nil];
        return [fm moveItemAtPath:tmpPath toPath:archivePath error:error];
    } @catch (NSException *ex) {
        [outFH closeFile];
        [fm removeItemAtPath:tmpPath error:nil];
        if (error) *error = MCMakeError(MCErrorCodeIOFailure, ex.reason ?: @"Lỗi đóng gói IPA.");
        return NO;
    }
}

@end
