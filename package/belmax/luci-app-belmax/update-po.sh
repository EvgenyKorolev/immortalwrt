#!/bin/bash -x

../../../feeds/luci/build/i18n-scan.pl . > ./po/templates/belmax.pot
../../../feeds/luci/build/i18n-update.pl ./po
