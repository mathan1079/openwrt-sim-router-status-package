#!/bin/sh
. /usr/share/libubox/jshn.sh
. /lib/functions.sh
. /lib/functions/cellular.sh

count="$1"
[ "${count}" = "1" ] && count=""

monitor_id="${count:-default}"
instance_lock="/tmp/ping_cellular_${monitor_id}.lock"
if ! mkdir "$instance_lock" 2>/dev/null; then
	old_pid=$(cat "$instance_lock/pid" 2>/dev/null)
	if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
		logger -t simmanager-cellular-guard "Skipped duplicate cellular ping monitor ${monitor_id}; PID ${old_pid} is already running."
		exit 0
	fi
	rm -rf "$instance_lock"
	mkdir "$instance_lock" 2>/dev/null || exit 1
fi
echo "$$" > "$instance_lock/pid"

output="/tmp/ping_cellular${count}"
working="${output}.$$"
release_monitor() {
	lock_pid=$(cat "$instance_lock/pid" 2>/dev/null)
	[ "$lock_pid" = "$$" ] && rm -rf "$instance_lock"
	rm -f "$working"
}
stop_monitor() {
	release_monitor
	exit 0
}
trap release_monitor EXIT
trap stop_monitor HUP INT TERM

while true
do
	detect_host01=$(uci -q get host.led_host.detect_host01)
	detect_host02=$(uci -q get host.led_host.detect_host02)
	ifname=$(uci -q get network.cellular${count}.ifname)

	: > "$working"
	timeout 3 ping -W1 -c2 "$detect_host01" -I "$ifname" >> "$working" 2>/dev/null
	sleep 4
	timeout 3 ping -W1 -c2 "$detect_host02" -I "$ifname" >> "$working" 2>/dev/null
	sleep 4
	timeout 3 ping -W1 -c2 "$detect_host01" -I "$ifname" >> "$working" 2>/dev/null
	sleep 4
	timeout 3 ping -W1 -c2 "$detect_host02" -I "$ifname" >> "$working" 2>/dev/null
	mv -f "$working" "$output"
	sleep 10
done
