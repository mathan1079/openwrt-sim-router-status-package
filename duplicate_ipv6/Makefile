# SDK builds retain the standard LuCI package rules.
ifneq ($(strip $(TOPDIR)),)
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ipv6-cleaner
PKG_VERSION:=1.0.0
PKG_RELEASE:=4
PKG_LICENSE:=MIT

LUCI_TITLE:=Automatic deprecated public IPv6 cleaner
LUCI_DEPENDS:=+luci-base +rpcd +ip-full +jshn +flock
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

else
PACKAGE := luci-app-ipv6-cleaner
VERSION ?= 1.0.0
RELEASE ?= 4
ROUTER ?= mathansims-local
SCP_FLAGS ?= -O
FORMAT ?= both
APK_TOOL ?= apk
FAKEROOT ?= fakeroot
APK_ALLOW_UNTRUSTED ?= 1
export VERSION RELEASE ROUTER SCP_FLAGS FORMAT APK_TOOL FAKEROOT APK_ALLOW_UNTRUSTED

.PHONY: build build-ipk build-apk verify install uninstall clean

build:
	./scripts/build.sh

build-ipk:
	$(MAKE) build FORMAT=ipk

build-apk:
	$(MAKE) build FORMAT=apk

verify:
	./scripts/verify.sh

install:
	python3 scripts/router-package.py install

uninstall:
	python3 scripts/router-package.py uninstall

clean:
	rm -rf dist

endif
