#import "MCMachOInspector.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>

#ifndef CPU_SUBTYPE_ARM64E
#define CPU_SUBTYPE_ARM64E ((cpu_subtype_t)2)
#endif

static const uint32_t kCSMagicEmbeddedSignature = 0xfade0cc0;
static const uint32_t kCSMagicEntitlements      = 0xfade7171;

static NSString *MCArchitectureName(cpu_type_t cputype, cpu_subtype_t cpusubtype) {
    cpu_subtype_t masked = cpusubtype & ~CPU_SUBTYPE_MASK;
    if (cputype == CPU_TYPE_ARM64) {
        if (masked == CPU_SUBTYPE_ARM64E) {
            return @"arm64e";
        }
        return @"arm64";
    }
    if (cputype == CPU_TYPE_ARM) {
        return @"armv7";
    }
    if (cputype == CPU_TYPE_X86_64) {
        return @"x86_64";
    }
    return [NSString stringWithFormat:@"cpu_%d_%d", (int)cputype, (int)masked];
}

static NSDictionary<NSString *, id> * _Nullable MCParseCodeSignatureEntitlements(const uint8_t *base,
                                                                                 NSUInteger sliceLen,
                                                                                 uint32_t sigOffset,
                                                                                 uint32_t sigSize) {
    if ((uint64_t)sigOffset + (uint64_t)sigSize > sliceLen || sigSize < 12) {
        return nil;
    }
    const uint8_t *cs = base + sigOffset;
    uint32_t magic = OSSwapBigToHostInt32(*(const uint32_t *)(cs));
    uint32_t count = OSSwapBigToHostInt32(*(const uint32_t *)(cs + 8));
    if (magic != kCSMagicEmbeddedSignature || count > 128) {
        return nil;
    }
    if (12 + (uint64_t)count * 8 > sigSize) {
        return nil;
    }

    for (uint32_t i = 0; i < count; i++) {
        uint32_t blobOffset = OSSwapBigToHostInt32(*(const uint32_t *)(cs + 12 + i * 8 + 4));
        if ((uint64_t)blobOffset + 8 > sigSize) continue;
        const uint8_t *blob = cs + blobOffset;
        uint32_t blobMagic = OSSwapBigToHostInt32(*(const uint32_t *)(blob));
        uint32_t blobLength = OSSwapBigToHostInt32(*(const uint32_t *)(blob + 4));
        if (blobMagic == kCSMagicEntitlements && blobLength > 8 && (uint64_t)blobOffset + blobLength <= sigSize) {
            NSData *xmlData = [NSData dataWithBytes:(blob + 8) length:(blobLength - 8)];
            NSError *plistErr = nil;
            id plist = [NSPropertyListSerialization propertyListWithData:xmlData
                                                                 options:NSPropertyListImmutable
                                                                  format:NULL
                                                                   error:&plistErr];
            if ([plist isKindOfClass:[NSDictionary class]]) {
                return plist;
            }
        }
    }
    return nil;
}

static void MCInspectMachOSlice(const uint8_t *slice,
                                NSUInteger sliceLen,
                                NSMutableArray<NSString *> *archs,
                                MCMachOInspectionResult *result) {
    if (sliceLen < sizeof(struct mach_header_64)) return;

    uint32_t magic = *(const uint32_t *)slice;
    if (magic != MH_MAGIC_64) {
        if (magic == MH_MAGIC) {
            const struct mach_header *hdr32 = (const struct mach_header *)slice;
            result.isValidMachO = YES;
            NSString *name = MCArchitectureName(hdr32->cputype, hdr32->cpusubtype);
            if (![archs containsObject:name]) [archs addObject:name];
        }
        return;
    }

    const struct mach_header_64 *hdr = (const struct mach_header_64 *)slice;
    result.isValidMachO = YES;
    NSString *archName = MCArchitectureName(hdr->cputype, hdr->cpusubtype);
    if (![archs containsObject:archName]) {
        [archs addObject:archName];
    }

    NSUInteger offset = sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < hdr->ncmds; i++) {
        if (offset + sizeof(struct load_command) > sliceLen) break;
        const struct load_command *lc = (const struct load_command *)(slice + offset);
        if (lc->cmdsize < sizeof(struct load_command) || offset + lc->cmdsize > sliceLen) break;

        if (lc->cmd == LC_ENCRYPTION_INFO_64 && lc->cmdsize >= sizeof(struct encryption_info_command_64)) {
            const struct encryption_info_command_64 *enc = (const struct encryption_info_command_64 *)(slice + offset);
            result.hasEncryptionCommand = YES;
            if (enc->cryptid != 0) {
                result.isEncrypted = YES;
                result.cryptID = enc->cryptid;
            }
        } else if (lc->cmd == LC_CODE_SIGNATURE && lc->cmdsize >= sizeof(struct linkedit_data_command)) {
            const struct linkedit_data_command *csCmd = (const struct linkedit_data_command *)(slice + offset);
            result.hasCodeSignature = YES;
            if (!result.entitlements) {
                NSDictionary *ents = MCParseCodeSignatureEntitlements(slice, sliceLen, csCmd->dataoff, csCmd->datasize);
                if (ents) {
                    result.entitlements = ents;
                }
            }
        }
        offset += lc->cmdsize;
    }
}

@implementation MCMachOInspectionResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _architectures = @[];
    }
    return self;
}

@end

@implementation MCMachOInspector

+ (MCMachOInspectionResult *)inspectMachOData:(NSData *)binaryData {
    MCMachOInspectionResult *result = [[MCMachOInspectionResult alloc] init];
    if (binaryData.length < 4) return result;

    const uint8_t *bytes = (const uint8_t *)binaryData.bytes;
    NSUInteger length = binaryData.length;
    uint32_t magic = *(const uint32_t *)bytes;
    NSMutableArray<NSString *> *archs = [NSMutableArray array];

    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        if (length >= sizeof(struct fat_header)) {
            BOOL swap = (magic == FAT_CIGAM);
            const struct fat_header *fh = (const struct fat_header *)bytes;
            uint32_t nfat = swap ? OSSwapInt32(fh->nfat_arch) : fh->nfat_arch;
            if (nfat <= 16) {
                NSUInteger archOffset = sizeof(struct fat_header);
                for (uint32_t i = 0; i < nfat; i++) {
                    if (archOffset + sizeof(struct fat_arch) > length) break;
                    const struct fat_arch *fa = (const struct fat_arch *)(bytes + archOffset);
                    uint32_t sliceOff = swap ? OSSwapInt32(fa->offset) : fa->offset;
                    uint32_t sliceSize = swap ? OSSwapInt32(fa->size) : fa->size;
                    if ((uint64_t)sliceOff + (uint64_t)sliceSize <= length) {
                        MCInspectMachOSlice(bytes + sliceOff, sliceSize, archs, result);
                    }
                    archOffset += sizeof(struct fat_arch);
                }
            }
        }
    } else {
        MCInspectMachOSlice(bytes, length, archs, result);
    }

    result.architectures = [archs copy];
    return result;
}

@end
