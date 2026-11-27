#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
controller="$project_dir/luci-app-simmanager/luasrc/controller/simmanager.lua"
profiles="$project_dir/luci-app-simmanager/luasrc/model/cbi/simmanager/profiles.lua"
automation="$project_dir/luci-app-simmanager/luasrc/model/cbi/simmanager/automation.lua"

test -f "$controller"
test -f "$profiles"
test -f "$automation"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/dashboard.htm"
test -f "$project_dir/luci-app-simmanager/root/etc/config/simmanager"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/activation.htm"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/automation_style.htm"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/automation_history.htm"
test -f "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-control"
test -f "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-auto"
test -x "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-fast-switch"
test -x "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-jio-ensure"
test -f "$project_dir/luci-app-simmanager/root/etc/init.d/simmanager-auto"
test -f "$project_dir/luci-app-simmanager/root/etc/init.d/simmanager-sms"
test -f "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-sms"
test -f "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-sms-daemon"
test -f "$project_dir/luci-app-simmanager/root/usr/libexec/simmanager-sms"
test -f "$project_dir/luci-app-simmanager/root/usr/lib/lua/simmanager/sms.lua"
test -f "$project_dir/luci-app-simmanager/luasrc/view/simmanager/sms.htm"
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
	luac -p "$controller" "$profiles" "$automation"
fi

lua_compiler=""
if command -v luac5.1 >/dev/null 2>&1; then
	lua_compiler=luac5.1
elif command -v luac >/dev/null 2>&1 && luac -v 2>&1 | grep -q 'Lua 5\.1'; then
	lua_compiler=luac
fi
if [ -n "$lua_compiler" ]; then
	"$lua_compiler" -p "$project_dir/luci-app-simmanager/root/usr/libexec/simmanager-sms" \
		"$project_dir/luci-app-simmanager/root/usr/lib/lua/simmanager/sms.lua"
fi

sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-status"
sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-control"
sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-auto"
sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-fast-switch"
sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-jio-ensure"
sh -n "$project_dir/luci-app-simmanager/root/etc/init.d/simmanager-auto"
sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-sms"
sh -n "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-sms-daemon"
sh -n "$project_dir/luci-app-simmanager/root/etc/init.d/simmanager-sms"
sh -n "$project_dir/scripts/build-ipk.sh"
sh "$project_dir/tests/test-auto-policy.sh"
sh "$project_dir/tests/test-auto-switch-state-machine.sh"
sh "$project_dir/tests/test-backup-policy.sh"
sh "$project_dir/tests/test-fast-switch-policy.sh"
sh "$project_dir/tests/test-fast-gpio-switch.sh"
sh "$project_dir/tests/test-jio-state-policy.sh"
sh "$project_dir/tests/test-sms-codec.sh"
lua "$project_dir/tests/test-network-mode-ui.lua" "$profiles"

echo "Safety and syntax checks passed"
