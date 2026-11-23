THEOS ?= $(HOME)/theos
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak/MultiCloneSpringBoard Manager/MultiCloneManager

include $(THEOS_MAKE_PATH)/aggregate.mk

# Ensure clean rootless permissions for DEBIAN maintainer scripts during staging
internal-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/DEBIAN"
	@cp -f Packaging/DEBIAN/postinst "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	@cp -f Packaging/DEBIAN/prerm "$(THEOS_STAGING_DIR)/DEBIAN/prerm"
	@cp -f Packaging/DEBIAN/postrm "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	@chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/prerm" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	@mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/Application Support/MultiClone"
	@cp -f Resources/config/auto-close-defaults.plist "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/Application Support/MultiClone/auto-close-defaults.plist"
	@mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/MultiCloneManager.app"
	@cp -f Resources/Icons/AppIcon60x60@2x.png "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/MultiCloneManager.app/"
	@cp -f Resources/Icons/AppIcon60x60@3x.png "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/MultiCloneManager.app/"
