#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/simmanager-backup-test.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
mkdir -p "$temp_dir/backups"
printf 'config cellular test\n' > "$temp_dir/cellular"
printf '0\n' > "$temp_dir/date-counter"

SIMMANAGER_CONTROL_LIBRARY_ONLY=1
SIMMANAGER_CONTROL_BACKUP_ROOT="$temp_dir/backups"
SIMMANAGER_CONTROL_CELLULAR_CONFIG="$temp_dir/cellular"
SIMMANAGER_CONTROL_STATUS_FILE="$temp_dir/status.json"
SIMMANAGER_CONTROL_STATUS_NEW="$temp_dir/status.new"
SIMMANAGER_CONTROL_LOCK_DIR="$temp_dir/lock"
export SIMMANAGER_CONTROL_LIBRARY_ONLY SIMMANAGER_CONTROL_BACKUP_ROOT
export SIMMANAGER_CONTROL_CELLULAR_CONFIG SIMMANAGER_CONTROL_STATUS_FILE
export SIMMANAGER_CONTROL_STATUS_NEW SIMMANAGER_CONTROL_LOCK_DIR

uci() {
	case "$*" in
		"-q get cellular.cellular.hw_sim") printf 'sim1\n' ;;
		"export cellular") printf 'package cellular\n' ;;
		*) return 1 ;;
	esac
}

date() {
	case "${1:-}" in
		+%Y%m%d-%H%M%S)
			counter=$(cat "$temp_dir/date-counter")
			counter=$((counter + 1))
			printf '%s\n' "$counter" > "$temp_dir/date-counter"
			printf '20261125-13%04d\n' "$counter"
			;;
		+%s) printf '1795590000\n' ;;
		*) command date "$@" ;;
	esac
}

. "$project_dir/luci-app-simmanager/root/usr/sbin/simmanager-control"

fail() { echo "Backup policy test failed: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1'"; }

first=""
latest=""
count=1
while [ "$count" -le 6 ]; do
	latest=$(create_backup sim2 manual)
	[ -n "$first" ] || first="$latest"
	count=$((count + 1))
done

assert_eq "$(wc -l < "$manual_history_file" | tr -d ' ')" 5
assert_eq "$(sed -n '1p' "$manual_history_file")" "$latest"
if grep -Fqx "$first" "$manual_history_file"; then fail "oldest manual checkpoint remained in five-entry history"; fi
[ -d "$first" ] || fail "old checkpoint directory was deleted"
manual_pointer=$(cat "$manual_latest_file")
manual_history_before=$(cat "$manual_history_file")

automatic=$(create_backup sim1 automatic)
assert_eq "$(cat "$automatic_latest_file")" "$automatic"
assert_eq "$(cat "$manual_latest_file")" "$manual_pointer"
assert_eq "$(cat "$manual_history_file")" "$manual_history_before"
assert_eq "$(metadata_value "$automatic" backup_kind)" automatic
assert_eq "$(metadata_value "$manual_pointer" backup_kind)" manual

selected_id=$(basename "$manual_pointer")
assert_eq "$(resolve_manual_backup "$selected_id")" "$manual_pointer"
if resolve_manual_backup 'invalid/path' >/dev/null 2>&1; then fail "unsafe backup identifier was accepted"; fi

echo "Backup policy tests passed"
