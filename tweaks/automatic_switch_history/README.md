# Persistent automatic switch history

## Status

Reviewed locally on 27 November 2026. **Not deployed.** This feature was built
after `automatic_switch_reliability_fix`; its `original/` controller and policy
files are the exact local pre-feature versions. The history view is a new file
and therefore has no corresponding original file.

The live-router snapshot under `current_first_router/` remains unchanged until
deployment and live checksum reconciliation are explicitly requested.

## Purpose

Every automatic SIM switch attempt now has a durable audit record under:

`/etc/simmanager/auto-history/RECORD_ID/`

Each directory contains:

- `start.json` — immutable trigger and policy evidence written before the
  disruptive switch begins.
- `end.json` — completion time, duration, result, final SIM and guarded
  controller result.

The directory is on persistent OpenWrt overlay storage, so completed records
survive service and router restarts. To protect limited router flash, completed
records are automatically removed when they are older than seven days, and the
remaining completed set is capped at the newest 100 records. Either limit can
therefore trigger cleanup first. In-progress records are never pruned.

Measured test records average approximately 1.3 KB of logical JSON. Because
each record uses two small files and one directory, conservative flash planning
uses about 8 KB per record. The 100-record cap therefore limits expected
history allocation to approximately 800 KB, with margin below 1 MB for larger
status values and filesystem differences.

## Recorded information

- Exact reason code and human-readable trigger reason.
- Start time, end time and total duration in seconds.
- Source SIM, target SIM, final SIM and configured default SIM.
- Sustained-failure duration and configured threshold.
- Disconnect count, threshold and observation window.
- Each probe target's up/down result, probe family, quorum and interface.
- Daily attempt number/limit, cooldown and primary retry state.
- Target profile PDP type, APN mode and APN.
- Operator, MCC/MNC, registration, signal, RSRP, band, cell ID, ICCID and APN
  from the status cache at trigger time when available.
- Activation-controller state/message, final outcome and rollback result.

Possible outcomes are successful switch, activation failure, target connectivity
failure with successful rollback, critical rollback failure and interrupted
attempt. An unfinished record is finalized as interrupted when the controller
starts again. A graceful service stop also completes the active record.

## LuCI behavior

The Automatic Switching page now includes a history table with:

- Ten records per page and Previous/Next pagination.
- Newest record first.
- Individual selection and select-all for the current page.
- Bulk deletion with confirmation.
- In-progress records protected from deletion.
- Automatic seven-day retention and a 100-completed-record hard cap.
- Expandable details containing the complete trigger snapshot.
- Automatic refresh every ten seconds.
- Browser-local 12-hour timestamps, consistent with the other SIM Manager
  pages.

Deletion validates every record ID, only operates inside the fixed history
directory, and only removes completed records.

## Router/package files

- `/usr/sbin/simmanager-auto`
- `/usr/lib/lua/luci/controller/simmanager.lua`
- `/usr/lib/lua/luci/model/cbi/simmanager/automation.lua`
- `/usr/lib/lua/luci/view/simmanager/automation_history.htm` (new)

Project verification files were also updated:

- `tests/test-auto-switch-state-machine.sh`
- `scripts/verify.sh`

## Verification

- Persistent start and end records were created for successful, failed and
  critical automatic attempts.
- A pending record was reconciled to `interrupted` after a simulated restart.
- Retention tests prove that records older than seven days are removed, the
  completed set is capped, and an active record survives cleanup.
- The full policy, backup, fast-switch, GPIO, Jio and SMS suites passed.
- Modified shell and Lua files passed syntax checks.
- The history-table JavaScript passed `node --check` after replacing LuCI
  template expressions.
- `change.patch` reproduces the archived changed router files from `original/`.

No router, modem or live-network change was made.

## Deployment notes

Before deployment, compare all existing router files with `original/`. Rebase
if the live files differ. Install the new view file, clear LuCI caches, and
restart `simmanager-auto`. After one controlled automatic attempt, verify:

1. `start.json` and `end.json` exist under `/etc/simmanager/auto-history/`.
2. The LuCI table shows matching start/end times and outcome.
3. Restarting the service does not remove the record.
4. Selecting and deleting a completed record removes only that record.

After live verification, update `current_first_router/files/`, its manifest and
`tweaks/STATUS.md` to active/deployed.

## Rollback

Restore the three existing files from `original/`, remove only the new
`automation_history.htm` view, clear LuCI caches and restart the service.
Existing `/etc/simmanager/auto-history/` records may be preserved; the restored
older code ignores them.
