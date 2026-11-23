THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MultiClone
MultiClone_FILES = \
	Tweak.xm \
	MCAutoClose.m \
	../../Source/MultiCloneCore/MCConstants.m \
	../../Source/MultiCloneCore/MCModels.m \
	../../Source/MultiCloneCore/MCPrivateAPIBridge.m \
	../../Source/Logger/MCLogger.m

MultiClone_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I../../Source
MultiClone_FRAMEWORKS = Foundation UIKit CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
