THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MultiCloneManager
MultiCloneManager_FILES = \
	main.m \
	MCTheme.m \
	MCAppDelegate.m \
	MCHomeViewController.m \
	MCCreateCloneViewController.m \
	MCCloneDetailViewController.m \
	MCSettingsViewController.m \
	MCLogViewerViewController.m \
	../../Source/MultiCloneCore/MCConstants.m \
	../../Source/MultiCloneCore/MCModels.m \
	../../Source/MultiCloneCore/MCZipArchive.m \
	../../Source/MultiCloneCore/MCMachOInspector.m \
	../../Source/MultiCloneCore/MCPrivateAPIBridge.m \
	../../Source/Logger/MCLogger.m \
	../../Source/Settings/MCSettingsManager.m \
	../../Source/IPAInspector/MCIPAInspector.m \
	../../Source/IconManager/MCIconManager.m \
	../../Source/DataManager/MCDataManager.m \
	../../Source/CloneEngine/MCCloneEngine.m \
	../../Source/AutoClose/MCAutoCloseClient.m

MultiCloneManager_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I../../Source
MultiCloneManager_FRAMEWORKS = Foundation UIKit CoreFoundation Security UniformTypeIdentifiers
MultiCloneManager_LIBRARIES = z
MultiCloneManager_CODESIGN_FLAGS = -Sentitlements.plist
MultiCloneManager_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
