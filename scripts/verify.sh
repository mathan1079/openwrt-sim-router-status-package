#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
controller="$project_dir/luci-app-simmanager/luasrc/controller/simmanager.lua"
profiles="$project_dir/luci-app-simmanager/luasrc/model/cbi/simmanager/profiles.lua"

test -f "$controller"
test -f "$profiles"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/dashboard.htm"
test -f "$project_dir/luci-app-simmanager/root/etc/config/simmanager"

if grep -R -nE '(/etc/init\.d/cellular (reload|restart)|cellular_sw|uci (set|commit) cellular)' \
	"$project_dir/luci-app-simmanager/luasrc" "$project_dir/luci-app-simmanager/root"; then
	echo "Disruptive vendor operation found in package sources" >&2
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

echo "Read-only source checks passed"
