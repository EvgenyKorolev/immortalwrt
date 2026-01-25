#!/bin/sh
platform_check_image() {
    return 0
}

platform_do_upgrade() {
    echo "FORCE UPGRADE OK"
    sysupgrade -n -F /tmp/sysupgrade.bin
}
