#!/bin/sh

/etc/init.d/network stop
/etc/init.d/firewall stop
wifi down 2>/dev/null || true
sleep 3

rm -f /etc/config/network /etc/config/wireless
ip link delete br-lan 2>/dev/null || true
ip link delete br-bridge 2>/dev/null || true

cat > /etc/config/network << 'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'auto'

config device
	option name 'br-bridge'
	option type 'bridge'
	list ports 'lan'
	list ports 'wan'
	list ports 'phy0-ap0'
	list ports 'phy1-ap0'

config interface 'bridge'
	option device 'br-bridge'
	option proto 'static'
	option ipaddr '192.168.1.1'
	option netmask '255.255.255.0'

config interface 'wan'
	option proto 'none'
EOF

cat > /etc/config/wireless << 'EOF'
config wifi-device 'radio0'
	option type 'mac80211'
	option path 'platform/soc@0/c000000.wifi'
	option band '2g'
	option channel '1'
	option htmode 'HE20'
	option disabled '0'

config wifi-iface 'local_ap'
	option device 'radio0'
	option network 'bridge'
	option mode 'ap'
	option ssid 'BelMax-Local'
	option encryption 'psk2'
	option key 'local_password'

config wifi-device 'radio1'
	option type 'mac80211'
	option path 'platform/soc@0/b00a040.wifi1'
	option band '5g'
	option channel '36'
	option htmode 'HE80'
	option disabled '0'

config wifi-iface 'ptp_ap'
	option device 'radio1'
	option network 'bridge'
	option mode 'ap'
	option ssid 'BelMax-PTP'
	option encryption 'psk2'
	option key 'ptp_password'
	option wds '1'  # WDS ВКЛЮЧЕН - пробрасывает DHCP!
EOF

uci commit
/etc/init.d/network restart
wifi reload
sleep 25

/etc/init.d/dnsmasq enable
/etc/init.d/dnsmasq restart
/etc/init.d/firewall disable

echo "=== Мастер готов ==="
echo "Статус:"
ip link show type bridge
ip addr show br-bridge
iwinfo radio1
echo "DHCP статус: $(pgrep -x dnsmasq && echo 'активен' || echo 'остановлен')"