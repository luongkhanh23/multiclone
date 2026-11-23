#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const MCProductVersion;
FOUNDATION_EXPORT NSString * const MCPreferencesDomain;
FOUNDATION_EXPORT NSString * const MCManagerBundleID;
FOUNDATION_EXPORT NSString * const MCSpringBoardBundleID;

// Darwin Notification names (backward compatible with v0.3)
FOUNDATION_EXPORT NSString * const MCAutoCloseRequestNotification;
FOUNDATION_EXPORT NSString * const MCAutoCloseResultNotification;
FOUNDATION_EXPORT NSString * const MCSpringBoardPingNotification;
FOUNDATION_EXPORT NSString * const MCSpringBoardPongNotification;

// Preference & IPC Keys (backward compatible with v0.3)
FOUNDATION_EXPORT NSString * const MCPrefKeyAutoCloseEnabled;
FOUNDATION_EXPORT NSString * const MCPrefKeyAutoCloseOnlyManaged;
FOUNDATION_EXPORT NSString * const MCPrefKeyConfirmBeforeAutoClose;
FOUNDATION_EXPORT NSString * const MCPrefKeyLaunchBehavior;
FOUNDATION_EXPORT NSString * const MCPrefKeyThemeStyle;
FOUNDATION_EXPORT NSString * const MCPrefKeyAccentHex;
FOUNDATION_EXPORT NSString * const MCPrefKeyManagedBundleIDs;
FOUNDATION_EXPORT NSString * const MCPrefKeyPendingBundleID;
FOUNDATION_EXPORT NSString * const MCPrefKeyLastManagedBundleID;
FOUNDATION_EXPORT NSString * const MCPrefKeyLastActionStatus;
FOUNDATION_EXPORT NSString * const MCPrefKeyLastActionError;
FOUNDATION_EXPORT NSString * const MCPrefKeyLastActionTimestamp;
FOUNDATION_EXPORT NSString * const MCPrefKeySpringBoardHeartbeat;

// Error domain & codes
FOUNDATION_EXPORT NSErrorDomain const MCErrorDomain;

typedef NS_ENUM(NSInteger, MCErrorCode) {
    MCErrorCodeUnknown = 1000,
    MCErrorCodeInvalidArgument = 1001,
    MCErrorCodeInvalidBundleID = 1002,
    MCErrorCodePathTraversalBlocked = 1003,
    MCErrorCodePathOutsideManagedScope = 1004,
    MCErrorCodeIPACorrupted = 1005,
    MCErrorCodeIPAMissingInfoPlist = 1006,
    MCErrorCodeIPADRMProtected = 1007,
    MCErrorCodeIPAIncompatibleArchitecture = 1008,
    MCErrorCodeProtectedBundle = 1009,
    MCErrorCodeBundleIDCollision = 1010,
    MCErrorCodeStagingFailed = 1011,
    MCErrorCodeSigningToolUnavailable = 1012,
    MCErrorCodeSigningFailed = 1013,
    MCErrorCodeInstallationFailed = 1014,
    MCErrorCodeIPCUnavailable = 1015,
    MCErrorCodePrivateAPIUnavailable = 1016,
    MCErrorCodeCloneNotFound = 1017,
    MCErrorCodeIOFailure = 1018
};

// Rootless & Managed Storage Path Helpers
FOUNDATION_EXPORT NSString *MCRootlessPrefix(void);
FOUNDATION_EXPORT NSString *MCRootPath(NSString *relativePath);
FOUNDATION_EXPORT NSString *MCManagedRootDirectory(void);
FOUNDATION_EXPORT NSString *MCClonesDirectory(void);
FOUNDATION_EXPORT NSString *MCStagingDirectory(void);
FOUNDATION_EXPORT NSString *MCIconsDirectory(void);
FOUNDATION_EXPORT NSString *MCExportsDirectory(void);
FOUNDATION_EXPORT NSString *MCLogsDirectory(void);
FOUNDATION_EXPORT NSString *MCRegistryFilePath(void);
FOUNDATION_EXPORT NSString *MCIPCStateFilePath(void);

// Validation & Safety Guards
FOUNDATION_EXPORT BOOL MCIsValidBundleIdentifier(NSString * _Nullable bundleID);
FOUNDATION_EXPORT BOOL MCIsProtectedBundleIdentifier(NSString * _Nullable bundleID);
FOUNDATION_EXPORT BOOL MCIsPathStrictlyInsideDirectory(NSString *candidatePath, NSString *baseDirectory);
FOUNDATION_EXPORT NSError *MCMakeError(MCErrorCode code, NSString *description);

NS_ASSUME_NONNULL_END
