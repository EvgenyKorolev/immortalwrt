include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI BelMax setup
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

PKG_VERSION:=0.1
# PKG_RELEASE:=1
PKG_MAINTAINER:=vint

define Package/luci-app-belmax/postinst
  rm -rf /tmp/luci-*
  /etc/init.d/rpcd restart
  /etc/init.d/uhttpd restart
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
