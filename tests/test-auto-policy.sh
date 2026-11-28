#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/simmanager-auto-test.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

SIMMANAGER_AUTO_LIBRARY_ONLY=1
SIMMANAGER_AUTO_STATE_ROOT="$temp_dir/state"
SIMMANAGER_AUTO_STATUS_FILE="$temp_dir/status.json"
SIMMANAGER_AUTO_STATUS_NEW="$temp_dir/status.new"
SIMMANAGER_AUTO_DISCONNECT_FILE="$temp_dir/disconnects"
SIMMANAGER_AUTO_DISCONNECT_NEW="$temp_dir/disconnects.new"
export SIMMANAGER_AUTO_LIBRARY_ONLY SIMMANAGER_AUTO_STATE_ROOT
export SIMMANAGER_AUTO_STATUS_FILE SIMMANAGER_AUTO_STATUS_NEW
export SIMMANAGER_AUTO_DISCONNECT_FILE SIMMANAGER_AUTO_DISCONNECT_NEW
. "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-auto"

fail() { echo "Automatic policy test failed: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }
assert_delay() {
	actual="$1"; expected="$2"
	[ "$actual" -ge $((expected - 2)) ] && [ "$actual" -le $((expected + 2)) ] ||
		fail "expected delay near $expected, got $actual"
}

assert_eq "$(other_sim sim1)" sim2
assert_eq "$(other_sim sim2)" sim1
assert_eq "$(parse_sim_presence '+CPIN: READY')" present
assert_eq "$(parse_sim_presence '+CPIN: SIM PIN')" present
assert_eq "$(parse_sim_presence '+CME ERROR: 10')" absent
assert_eq "$(parse_sim_presence '+CME ERROR: SIM not inserted')" absent
assert_eq "$(parse_sim_presence 'ERROR')" unknown

mode=primary
retry_index=0
next_retry=0
last_switch=0
switch_day=$(date +%Y%m%d)
switch_count=0
secondary_since=0
failed_attempts=0
next_switch_attempt=0

before=$(date +%s)
set_secondary_schedule
assert_eq "$mode" secondary
assert_eq "$retry_index" 0
assert_delay $((next_retry - before)) 21600

before=$(date +%s)
schedule_next_primary_retry
assert_eq "$retry_index" 1
assert_eq "$((next_retry - secondary_since))" 43200

before=$(date +%s)
schedule_next_primary_retry
assert_eq "$retry_index" 2
assert_eq "$((next_retry - secondary_since))" 64800

before=$(date +%s)
schedule_next_primary_retry
assert_eq "$retry_index" 3
assert_eq "$((next_retry - secondary_since))" 86400

before=$(date +%s)
schedule_next_primary_retry
assert_eq "$retry_index" 4
assert_eq "$((next_retry - secondary_since))" 172800

mode=secondary
retry_index=2
next_retry=1234
last_switch=5678
switch_day=20261125
switch_count=3
secondary_since=1795590000
failed_attempts=2
next_switch_attempt=1795590060
save_state
mode=x; retry_index=0; next_retry=0; last_switch=0; switch_day=x; switch_count=0
secondary_since=0; failed_attempts=0; next_switch_attempt=0
load_state
assert_eq "$mode" secondary
assert_eq "$retry_index" 2
assert_eq "$next_retry" 1234
assert_eq "$last_switch" 5678
assert_eq "$switch_day" 20261125
assert_eq "$switch_count" 3
assert_eq "$secondary_since" 1795590000
assert_eq "$failed_attempts" 2
assert_eq "$next_switch_attempt" 1795590060

vendor_auto=1
ours_enabled=1
conflict_called=0
uci() {
	case "$*" in
		"-q get simmanager.automation.enabled") printf '%s\n' "$ours_enabled" ;;
		"-q get cellular.cellular.hw_asw") printf '%s\n' "$vendor_auto" ;;
		*) return 1 ;;
	esac
}
disable_for_vendor_conflict() { conflict_called=1; }
if guard_enabled; then fail "vendor auto-switch conflict was accepted"; fi
assert_eq "$conflict_called" 1
vendor_auto=0
guard_enabled || fail "non-conflicting enabled policy was rejected"

write_status() { :; }
save_state() { :; }
switch_day=$(date +%Y%m%d)
max_switches_per_day=4
cooldown_minutes=30
switch_count=4
last_switch=0
next_switch_attempt=0
if can_switch_now "$(date +%s)"; then fail "daily switch limit was ignored"; fi
switch_count=3
last_switch=$(date +%s)
set +e
can_switch_now "$(date +%s)" 0
deferred_rc=$?
set -e
assert_eq "$deferred_rc" 4
can_switch_now "$(date +%s)" 1 || fail "emergency failover was blocked by cooldown"
last_switch=0
can_switch_now "$(date +%s)" || fail "valid switch was blocked"

failed_attempts=0
next_switch_attempt=0
record_failed_attempt "$(date +%s)"
assert_eq "$failed_attempts" 1
assert_delay $((next_switch_attempt - $(date +%s))) 30
set +e
can_switch_now "$(date +%s)" 1
deferred_rc=$?
set -e
assert_eq "$deferred_rc" 4
clear_failed_attempts
assert_eq "$failed_attempts" 0
assert_eq "$next_switch_attempt" 0

network_device() { printf 'lan5\n'; }
probe_result=all
ping() {
	host=""
	for arg in "$@"; do host="$arg"; done
	sleep 1
	case "$probe_result:$host" in
		two:9.9.9.9|one:8.8.8.8|one:9.9.9.9) return 1 ;;
		*) return 0 ;;
	esac
}
started=$(date +%s)
health_check || fail "three successful probes were rejected"
elapsed=$(( $(date +%s) - started ))
[ "$elapsed" -le 2 ] || fail "health probes did not run in parallel"
probe_result=two
health_check || fail "two of three successful probes were rejected"
probe_result=one
if health_check; then fail "one of three successful probes was accepted"; fi

uci() {
	case "$*" in
		"-q get cellular.cellular.hw_sim") printf 'sim1\n' ;;
		"-q get simmanager.sim1.pdp_type") printf 'IPV6\n' ;;
		*) return 1 ;;
	esac
}
ping6() {
	case "$*" in
		*2606:4700:4700::1111*|*2001:4860:4860::8888*) return 0 ;;
		*) return 1 ;;
	esac
}
health_check || fail "IPv6-only profile did not use the IPv6 connectivity proof"

init_script="$project_dir/luci-app-simmanager/root/etc/init.d/simmanager-auto"
grep -q 'procd_set_param respawn' "$init_script" || fail "automatic controller has no crash respawn policy"
if grep -q 'procd_add_reload_trigger.*cellular' "$init_script"; then
	fail "cellular changes can still interrupt the automatic controller transaction"
fi

echo "Automatic policy tests passed"
