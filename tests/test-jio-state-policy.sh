#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
helper="$repo_dir/luci-app-simmanager/root/usr/sbin/simmanager-jio-ensure"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

mockbin="$tmp/bin"
state_dir="$tmp/state"
mkdir -p "$mockbin" "$state_dir"

cat > "$mockbin/flock" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$mockbin/uci" <<'EOF'
#!/bin/sh
case "$*" in
  *"cellular.cellular.hw_sim") echo "${MOCK_SIM:-sim1}" ;;
  *"cellular.cellular.m_netmode") echo "${MOCK_PROFILE_MODE:-NR5G:LTE}" ;;
  *"simmanager.sim1") echo profile ;;
  *"simmanager.sim2") echo profile ;;
  *"simmanager.sim1.network_mode") echo "${MOCK_PROFILE_MODE:-NR5G:LTE}" ;;
  *"simmanager.sim2.network_mode") echo "${MOCK_PROFILE_MODE:-NR5G:LTE}" ;;
esac
exit 0
EOF

cat > "$mockbin/at-cmd" <<'EOF'
#!/bin/sh
shift
command="$*"
printf '%s\n' "$command" >> "$MOCK_AT_LOG"
case "$command" in
  AT+CIMI)
    [ "${MOCK_CARRIER:-jio}" = jio ] && echo 405869188462733 || echo 404094123456789
    ;;
  AT+COPS\?)
    [ "${MOCK_CARRIER:-jio}" = jio ] && echo '+COPS: 0,0,"Jio",11' || echo '+COPS: 0,0,"airtel",7'
    ;;
  AT+CGPADDR=1)
    [ "${MOCK_CARRIER:-jio}" = jio ] && echo '+CGPADDR: 1,"2405:200:abcd::1"' || echo '+CGPADDR: 1,"10.10.10.10"'
    ;;
  'AT+QCFG="nat"') echo "+QCFG: \"nat\",${MOCK_NAT:-1}" ;;
  'AT+QCFG="clat"') echo "+QCFG: \"clat\",${MOCK_CLAT:-1}" ;;
  'AT+QNWPREFCFG="mode_pref"') echo "+QNWPREFCFG: \"mode_pref\",${MOCK_CURRENT_MODE:-AUTO}" ;;
esac
exit 0
EOF

cat > "$mockbin/logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LOGGER_LOG"
EOF

cat > "$mockbin/sync" <<'EOF'
#!/bin/sh
exit 0
EOF

chmod +x "$mockbin"/*
export PATH="$mockbin:$PATH"
export SIMMANAGER_STATE_DIR="$state_dir"
export SIMMANAGER_AT_LOCK="$tmp/at.lock"
export MOCK_AT_LOG="$tmp/at.log"
export MOCK_LOGGER_LOG="$tmp/logger.log"

jio_iccid=89918690400895597114
airtel_iccid=8991000923788177231
shared_marker="$state_dir/xlat-cellular.state"
per_jio_marker="$state_dir/xlat-cellular-${jio_iccid}.state"

printf 'v3|%s|405869188462733|jionet|IPV4V6|nat1|clat1\n' "$jio_iccid" > "$shared_marker"
printf '%s|100\n' "$jio_iccid" > "$state_dir/xlat-cellular.restart"

: > "$MOCK_AT_LOG"
MOCK_CARRIER=jio MOCK_NAT=1 MOCK_CLAT=1 sh "$helper" /dev/null cellular "$jio_iccid"
[ -f "$per_jio_marker" ] || { echo "FAIL: shared Jio state was not migrated per ICCID"; exit 1; }
grep -q "^v5|${jio_iccid}|.*|NR5G:LTE$" "$per_jio_marker" || { echo "FAIL: migrated marker was not upgraded with the selected network mode"; exit 1; }
grep -q 'AT+QNWPREFCFG="mode_pref",NR5G:LTE' "$MOCK_AT_LOG" || { echo "FAIL: Jio preparation did not apply the selected LTE/5G mode"; exit 1; }
! grep -q 'AT+QNWPREFCFG="mode_pref",AUTO' "$MOCK_AT_LOG" || { echo "FAIL: Jio preparation forced AUTO mode"; exit 1; }
! grep -q 'AT+CFUN=1,1' "$MOCK_AT_LOG" || { echo "FAIL: prepared Jio SIM was restarted during migration"; exit 1; }

: > "$MOCK_AT_LOG"
MOCK_CARRIER=airtel MOCK_SIM=sim2 sh "$helper" /dev/null cellular "$airtel_iccid"
[ -f "$per_jio_marker" ] || { echo "FAIL: Airtel activation deleted saved Jio state"; exit 1; }
! grep -q 'AT+CFUN=1,1' "$MOCK_AT_LOG" || { echo "FAIL: non-Jio SIM triggered modem restart"; exit 1; }

: > "$MOCK_AT_LOG"
MOCK_CARRIER=jio MOCK_SIM=sim1 MOCK_NAT=1 MOCK_CLAT=1 sh "$helper" /dev/null cellular "$jio_iccid"
! grep -q 'AT+CFUN=1,1' "$MOCK_AT_LOG" || { echo "FAIL: returning to prepared Jio SIM triggered modem restart"; exit 1; }

: > "$MOCK_AT_LOG"
rm -f "$state_dir/xlat-cellular-${jio_iccid}.restart"
MOCK_CARRIER=jio MOCK_SIM=sim1 MOCK_NAT=0 MOCK_CLAT=0 sh "$helper" /dev/null cellular "$jio_iccid" || rc=$?
[ "${rc:-0}" = 10 ] || { echo "FAIL: confirmed disabled CLAT/NAT did not request one restart"; exit 1; }
grep -q 'AT+CFUN=1,1' "$MOCK_AT_LOG" || { echo "FAIL: confirmed disabled CLAT/NAT did not restart modem"; exit 1; }

echo "PASS: Jio per-ICCID state policy"
