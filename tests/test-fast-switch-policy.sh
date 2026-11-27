#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/simmanager-fast-switch-test.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

SIMMANAGER_CONTROL_LIBRARY_ONLY=1
export SIMMANAGER_CONTROL_LIBRARY_ONLY
. "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-control"

fail() { echo "Fast switch policy test failed: $*" >&2; exit 1; }

cellular_device() { printf 'lan5\n'; }
ping() {
	case "$*" in
		*1.1.1.1*|*8.8.8.8*) return 0 ;;
		*) return 1 ;;
	esac
}
activation_health_check || fail "two successful probes were rejected"

ping() {
	case "$*" in *1.1.1.1*) return 0 ;; *) return 1 ;; esac
}
if activation_health_check; then
	fail "one successful probe was accepted"
fi

automation_allowed() { return 0; }
printf '0\n' > "$temp_dir/checks"
activation_health_check() {
	checks=$(cat "$temp_dir/checks")
	checks=$((checks + 1))
	printf '%s\n' "$checks" > "$temp_dir/checks"
	[ "$checks" -ge 2 ]
}
activation_monitor_interval=0
activation_required_successes=2
activation_max_checks=4
wait_for_stable_connectivity || fail "two consecutive healthy rounds were rejected"
[ "$(cat "$temp_dir/checks")" = 3 ] || fail "unexpected healthy-round count"

activation_health_check() { return 1; }
activation_max_checks=2
if wait_for_stable_connectivity; then
	fail "failed connectivity was accepted"
fi

# Once routed Internet is already proved, a busy AT port must not keep a
# completed SIM switch in the switching state.
activation_health_check() { return 0; }
locked_at() { fail "AT query ran despite proved Internet connectivity"; }
uci() { printf '/dev/null\n'; }
wait_for_sim_ready || fail "proved Internet did not satisfy SIM readiness"
wait_for_registration || fail "proved Internet did not satisfy registration"

echo "Fast switch policy tests passed"
