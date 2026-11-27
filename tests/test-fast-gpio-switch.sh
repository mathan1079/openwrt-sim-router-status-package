#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
helper="$repo_dir/luci-app-simmanager/root/usr/sbin/simmanager-fast-switch"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

grep -q 'SIM GPIO read-back did not match' "$helper" || {
	echo "FAIL: GPIO switching is not protected by read-back"
	exit 1
}
! grep -q 'SIM GPIO could not be changed' "$helper" || {
	echo "FAIL: GPIO write return code still bypasses authoritative read-back"
	exit 1
}

mockbin="$tmp/bin"
mockroot="$tmp/sys/class"
mkdir -p "$mockbin" "$mockroot/gpio/sim"
printf '0\n' > "$mockroot/gpio/sim/value"
printf 'sim2\n' > "$tmp/current-sim"
printf '1\n' > "$tmp/cfun"
: > "$tmp/events"

cat > "$tmp/cellular.sh" <<'EOF'
kill_process() { echo "kill:$*" >> "$MOCK_EVENTS"; }
watchsystem() { echo "watchsystem" >> "$MOCK_EVENTS"; }
cellular_sw() { echo "hard-fallback:$*" >> "$MOCK_EVENTS"; return 0; }
EOF

cat > "$mockbin/uci" <<'EOF'
#!/bin/sh
if [ "$1" = -q ] && [ "$2" = get ]; then
    key="$3"
    case "$key" in
        cellular.cellular.hw_sim) cat "$MOCK_CURRENT_SIM" ;;
        cellular.cellular.idevice_model) echo rm500u_ea ;;
        cellular.cellular.atdev) echo /dev/zero ;;
        cellular.cellular.script) echo '/usr/sbin/cellular/quectel_rm500u 1 /dev/ttyUSB2 lan5 usb0 1 0' ;;
        hw_info.cellular.s_cfun|hw_info.cellular.s2_cfun) echo gpio ;;
        hw_info.cellular.s_fs|hw_info.cellular.s2_fs) echo gpio/sim ;;
        hw_info.cellular.s_file|hw_info.cellular.s2_file) echo value ;;
        hw_info.cellular.s_val) echo 1 ;;
        hw_info.cellular.s2_val) echo 0 ;;
    esac
    exit 0
fi
if [ "$1" = set ]; then
    case "$2" in
        cellular.cellular.hw_sim=*) printf '%s\n' "${2#*=}" > "$MOCK_CURRENT_SIM" ;;
    esac
    exit 0
fi
[ "$1" = commit ] && exit 0
exit 0
EOF

cat > "$mockbin/at-cmd" <<'EOF'
#!/bin/sh
port="$1"
shift
command="$1"
echo "port:$port" >> "$MOCK_EVENTS"
echo "at:$command" >> "$MOCK_EVENTS"
case "$command" in
    AT+CCID)
        if [ "$(cat "$MOCK_GPIO")" = 1 ]; then
            echo '+CCID: 89918690400895597114'
        else
            echo '+CCID: 8991000923788177231F'
        fi
        echo OK
        ;;
    AT+CFUN=0)
        if [ "${MOCK_FAIL_CFUN0:-0}" = 1 ]; then
            echo ERROR
        else
            printf '0\n' > "$MOCK_CFUN"
        fi
        ;;
    AT+CFUN\?)
        echo "+CFUN: $(cat "$MOCK_CFUN")"
        echo OK
        ;;
    AT+CFUN=1)
        printf '1\n' > "$MOCK_CFUN"
        ;;
    AT+CPIN\?)
        [ "$(cat "$MOCK_CFUN")" = 1 ] && echo '+CPIN: READY'
        echo OK
        ;;
esac
EOF

cat > "$mockbin/timeout" <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF

cat > "$mockbin/flock" <<'EOF'
#!/bin/sh
echo "flock:$*" >> "$MOCK_EVENTS"
exit 0
EOF

cat > "$mockbin/logger" <<'EOF'
#!/bin/sh
echo "logger:$*" >> "$MOCK_EVENTS"
EOF

chmod +x "$mockbin"/*
export PATH="$mockbin:$PATH"
export SIMMANAGER_CELLULAR_LIB="$tmp/cellular.sh"
export SIMMANAGER_GPIO_ROOT="$mockroot"
export SIMMANAGER_AT_LOCK="$tmp/at.lock"
export SIMMANAGER_FAST_SWITCH_ATDEV=/dev/null
export SIMMANAGER_FAST_SWITCH_READY_TIMEOUT=3
export MOCK_CURRENT_SIM="$tmp/current-sim"
export MOCK_GPIO="$mockroot/gpio/sim/value"
export MOCK_CFUN="$tmp/cfun"
export MOCK_EVENTS="$tmp/events"

sh "$helper" sim1 1
[ "$(cat "$MOCK_GPIO")" = 1 ] || { echo "FAIL: GPIO did not select SIM1"; exit 1; }
[ "$(cat "$MOCK_CURRENT_SIM")" = sim1 ] || { echo "FAIL: UCI target was not updated"; exit 1; }
grep -q '^watchsystem$' "$MOCK_EVENTS" || { echo "FAIL: detector was not restarted"; exit 1; }
grep -q 'SIM 89918690400895597114 became ready' "$MOCK_EVENTS" || { echo "FAIL: padded source ICCID prevented target proof"; exit 1; }
grep -q '^port:/dev/null$' "$MOCK_EVENTS" || { echo "FAIL: dedicated control port was not used"; exit 1; }
grep -q '^flock:-u 9$' "$MOCK_EVENTS" || { echo "FAIL: AT lock was not released before detector restart"; exit 1; }
! grep -q '^hard-fallback:' "$MOCK_EVENTS" || { echo "FAIL: healthy fast path used hard fallback"; exit 1; }
! grep -q 'AT+CFUN=1,1' "$MOCK_EVENTS" || { echo "FAIL: healthy fast path reset the modem"; exit 1; }

printf '0\n' > "$MOCK_GPIO"
printf 'sim2\n' > "$MOCK_CURRENT_SIM"
printf '1\n' > "$MOCK_CFUN"
: > "$MOCK_EVENTS"
MOCK_FAIL_CFUN0=1 sh "$helper" sim1 1
grep -q '^hard-fallback:sim1 1$' "$MOCK_EVENTS" || { echo "FAIL: CFUN failure did not use vendor fallback"; exit 1; }
grep -q '^flock:-u 9$' "$MOCK_EVENTS" || { echo "FAIL: AT lock was not released before hard fallback"; exit 1; }

printf '1\n' > "$MOCK_GPIO"
printf 'sim2\n' > "$MOCK_CURRENT_SIM"
: > "$MOCK_EVENTS"
set +e
sh "$helper" sim1 1
status=$?
set -e
[ "$status" = 2 ] || { echo "FAIL: invalid GPIO precondition was not rejected"; exit 1; }
! grep -q '^at:' "$MOCK_EVENTS" || { echo "FAIL: invalid GPIO precondition sent AT commands"; exit 1; }

echo "PASS: safe fast GPIO switch policy"
