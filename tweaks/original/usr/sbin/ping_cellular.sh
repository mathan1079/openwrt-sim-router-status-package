#!/bin/sh
. /usr/share/libubox/jshn.sh
. /lib/functions.sh
. /lib/functions/cellular.sh

count="$1"
[ "${count}" == "1" ] && count=""

while true
do
	## Seriver user for ping
	detect_host01=`uci get host.led_host.detect_host01 2> /dev/null`
	detect_host02=`uci get host.led_host.detect_host02 2> /dev/null`
	ifname=`uci get network.cellular${count}.ifname 2> /dev/null`

	timeout 3 ping -W1 -c2 "${detect_host01}" -I "${ifname}" 2> /dev/null > /tmp/ping_cellular${count}
	sleep 4
	timeout 3 ping -W1 -c2 "${detect_host02}" -I "${ifname}" 2> /dev/null >> /tmp/ping_cellular${count}
	sleep 4
	timeout 3 ping -W1 -c2 "${detect_host01}" -I "${ifname}" 2> /dev/null >> /tmp/ping_cellular${count}
	sleep 4
	timeout 3 ping -W1 -c2 "${detect_host02}" -I "${ifname}" 2> /dev/null >> /tmp/ping_cellular${count}
	sync && sleep 10
done
