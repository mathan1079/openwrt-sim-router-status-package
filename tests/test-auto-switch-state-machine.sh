#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/simmanager-auto-machine-test.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

cat > "$temp_dir/control" <<'EOF'
#!/bin/sh
exit "${SIMMANAGER_TEST_CONTROL_RC:-0}"
EOF
chmod +x "$temp_dir/control"

cat > "$temp_dir/jshn.sh" <<'EOF'
json_init() { json_body=""; json_separator=""; }
json_add_string() {
	json_key="$1"
	json_value=$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')
	json_body="${json_body}${json_separator}\"${json_key}\":\"${json_value}\""
	json_separator=,
}
json_dump() { printf '{%s}\n' "$json_body"; }
json_cleanup() { :; }
EOF

cat > "$temp_dir/jsonfilter" <<'EOF'
#!/bin/sh
json=""
expression=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		-s) json="$2"; shift 2 ;;
		-e) expression="$2"; shift 2 ;;
		*) shift ;;
	esac
done
key=${expression#@.}
printf '%s\n' "$json" | sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p"
EOF
chmod +x "$temp_dir/jsonfilter"
PATH="$temp_dir:$PATH"

SIMMANAGER_AUTO_LIBRARY_ONLY=1
SIMMANAGER_AUTO_STATE_ROOT="$temp_dir/state"
SIMMANAGER_AUTO_STATUS_FILE="$temp_dir/status.json"
SIMMANAGER_AUTO_STATUS_NEW="$temp_dir/status.new"
SIMMANAGER_AUTO_DISCONNECT_FILE="$temp_dir/disconnects"
SIMMANAGER_AUTO_DISCONNECT_NEW="$temp_dir/disconnects.new"
SIMMANAGER_AUTO_HISTORY_ROOT="$temp_dir/history"
SIMMANAGER_JSHN_LIB="$temp_dir/jshn.sh"
SIMMANAGER_AUTO_CONTROL="$temp_dir/control"
SIMMANAGER_CONTROL_LOCK_DIR="$temp_dir/control.lock"
export SIMMANAGER_AUTO_LIBRARY_ONLY SIMMANAGER_AUTO_STATE_ROOT
export SIMMANAGER_AUTO_STATUS_FILE SIMMANAGER_AUTO_STATUS_NEW
export SIMMANAGER_AUTO_DISCONNECT_FILE SIMMANAGER_AUTO_DISCONNECT_NEW
export SIMMANAGER_AUTO_HISTORY_ROOT
export SIMMANAGER_JSHN_LIB PATH
export SIMMANAGER_AUTO_CONTROL SIMMANAGER_CONTROL_LOCK_DIR
. "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-auto"

fail() { echo "Automatic state-machine test failed: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }

ours_enabled=1
vendor_auto=0
active_sim=sim1
uci() {
	case "$*" in
		"-q get simmanager.automation.enabled") printf '%s\n' "$ours_enabled" ;;
		"-q get cellular.cellular.hw_asw") printf '%s\n' "$vendor_auto" ;;
		"-q get cellular.cellular.hw_sim") printf '%s\n' "$active_sim" ;;
		*) return 1 ;;
	esac
}

write_status() { last_status="$1"; }
verify_stable_health() { return 0; }
critical_disabled=0
disable_after_rollback_failure() { critical_disabled=1; }

default_sim=sim1
mode=primary
retry_index=0
next_retry=0
last_switch=0
switch_day=$(date +%Y%m%d)
switch_count=0
secondary_since=0
failed_attempts=0
next_switch_attempt=0
sim1_presence=unknown
sim2_presence=unknown
sim1_retry_after=0
sim2_retry_after=0
cooldown_minutes=30
max_switches_per_day=4
failure_seconds=20
disconnect_limit=3
disconnect_window_minutes=10
recover_before_failover=0

# A failed activation is a disruptive attempt, consumes budget and starts a
# short backoff. An immediate retry must not invoke the control helper again.
SIMMANAGER_TEST_CONTROL_RC=1
export SIMMANAGER_TEST_CONTROL_RC
if switch_and_verify sim2 sustained_outage; then fail "failed activation was accepted"; fi
assert_eq "$switch_count" 1
assert_eq "$failed_attempts" 1
[ "$next_switch_attempt" -gt "$(date +%s)" ] || fail "failed activation did not start backoff"
set +e
switch_and_verify sim2 sustained_outage
backoff_rc=$?
set -e
assert_eq "$backoff_rc" 4
assert_eq "$switch_count" 1

# An explicit target-slot absence is retained and receives the longest safety
# backoff so the monitor cannot hammer an empty SIM slot every five seconds.
next_switch_attempt=0
failed_attempts=0
switch_count=0
SIMMANAGER_TEST_CONTROL_RC=10
export SIMMANAGER_TEST_CONTROL_RC
set +e
switch_and_verify sim2 sim_removed
absent_rc=$?
set -e
assert_eq "$absent_rc" 1
assert_eq "$sim2_presence" absent
[ "$sim2_retry_after" -ge $(( $(date +%s) + 298 )) ] || fail "missing target did not receive five-minute retry backoff"

sim2_presence=unknown
sim2_retry_after=0
next_switch_attempt=0
failed_attempts=0

# Exit 3 means activation and rollback both failed. Automation must stop rather
# than retrying from an unknown physical/configuration state.
next_switch_attempt=0
failed_attempts=0
SIMMANAGER_TEST_CONTROL_RC=3
export SIMMANAGER_TEST_CONTROL_RC
set +e
switch_and_verify sim2 sustained_outage
critical_rc=$?
set -e
assert_eq "$critical_rc" 2
assert_eq "$critical_disabled" 1

# The optional active-profile recovery path must also stop on the same critical
# result instead of continuing into a second SIM switch.
critical_disabled=0
set +e
recover_active sim1 sustained_outage
recovery_rc=$?
set -e
assert_eq "$recovery_rc" 2
assert_eq "$critical_disabled" 1

# A successful guarded activation clears any previous failure backoff.
critical_disabled=0
next_switch_attempt=0
failed_attempts=2
switch_count=0
SIMMANAGER_TEST_CONTROL_RC=0
export SIMMANAGER_TEST_CONTROL_RC
switch_and_verify sim2 sustained_outage || fail "healthy target was rejected"
assert_eq "$switch_count" 1
assert_eq "$failed_attempts" 0
assert_eq "$next_switch_attempt" 0

history_count=$(find "$temp_dir/history" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "$history_count" 4
grep -R -q '"outcome":"activation_failed"' "$temp_dir/history" || fail "failed activation history was not completed"
grep -R -q '"outcome":"target_sim_absent"' "$temp_dir/history" || fail "missing target history was not completed"
grep -R -q '"outcome":"rollback_failed"' "$temp_dir/history" || fail "critical rollback history was not completed"
grep -R -q '"outcome":"switched"' "$temp_dir/history" || fail "successful switch history was not completed"

history_trigger_elapsed=20
history_trigger_events=3
history_begin sim2 reconnect_loop sim1 || fail "pending history record could not be created"
[ ! -f "$temp_dir/history/$history_id/end.json" ] || fail "new history record was completed too early"
history_reconcile_interrupted
grep -q '"outcome":"interrupted"' "$temp_dir/history/$history_id/end.json" || fail "restart reconciliation did not complete pending history"

# Completed history is bounded by age and count. An unfinished attempt must
# remain available so a later controller start can reconcile it.
old_record=$(find "$temp_dir/history" -mindepth 1 -maxdepth 1 -type d | head -n 1)
sed 's/"started_at":"[0-9]*"/"started_at":"1"/' "$old_record/start.json" > "$old_record/start.json.new"
mv "$old_record/start.json.new" "$old_record/start.json"
history_retention_days=7
history_max_records=100
history_prune
[ ! -d "$old_record" ] || fail "record older than retention window was not pruned"

history_trigger_elapsed=20
history_trigger_events=1
history_begin sim2 sustained_outage sim1 || fail "active history record could not be created"
active_history_dir="$temp_dir/history/$history_id"
history_max_records=2
history_prune
completed_count=$(find "$temp_dir/history" -mindepth 2 -maxdepth 2 -name end.json | wc -l | tr -d ' ')
assert_eq "$completed_count" 2
[ -f "$active_history_dir/start.json" ] || fail "in-progress history was pruned"
[ ! -f "$active_history_dir/end.json" ] || fail "in-progress history unexpectedly completed"

echo "Automatic state-machine tests passed"
