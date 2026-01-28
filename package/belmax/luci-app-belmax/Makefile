include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI BelMax setup
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

PKG_VERSION:=0.1
# PKG_RELEASE:=1
PKG_MAINTAINER:=vint

define Package/luci-app-belmax/postinst
[ -n "${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	/etc/init.d/uhttpd restart 2>/dev/null
	exit 0
}
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
