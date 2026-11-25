#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
controller="$project_dir/luci-app-simmanager/luasrc/controller/simmanager.lua"
profiles="$project_dir/luci-app-simmanager/luasrc/model/cbi/simmanager/profiles.lua"

test -f "$controller"
test -f "$profiles"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/dashboard.htm"
test -f "$project_dir/luci-app-simmanager/root/etc/config/simmanager"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/activation.htm"
test -f "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-control"
test -f "$project_dir/luci-app-simmanager/root/www/luci-static/resources/view/status/include/19_simmanager.js"

if grep -R -nE '(/etc/init\.d/cellular (reload|restart)|cellular_sw|uci (set|commit) cellular)' \
	"$project_dir/luci-app-simmanager/luasrc" \
	"$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-status"; then
	echo "Disruptive operation found outside the approval-gated control helper" >&2
	exit 1
fi

if grep -R -nE '(^|[[:space:]/])(mtd|sysupgrade|fw_setenv|flash_erase|nandwrite)([[:space:]]|$)' \
	"$project_dir/luci-app-simmanager"; then
	echo "Firmware or flash modification command found" >&2
	exit 1
fi

if grep -nE 'AT\+(CFUN|CGDCONT=|COPS=|QCFG=.*,[0-9]|QICSGP=.*[,])' \
	"$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-status"; then
	echo "Modem-setting AT command found in query-only collector" >&2
	exit 1
fi

if command -v luac >/dev/null 2>&1; then
	luac -p "$controller" "$profiles"
fi

sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-status"
sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-control"

echo "Safety and syntax checks passed"
