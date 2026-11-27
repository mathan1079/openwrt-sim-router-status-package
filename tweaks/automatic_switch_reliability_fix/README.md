# Automatic switching reliability fix

## Status

Reviewed locally on 27 November 2026. **Not deployed.** The `original/` files
are the exact repository versions audited before this change; they were not
re-read from the router because this task was explicitly code-only. Therefore
`current_first_router/` and its manifest are intentionally unchanged.

## Problems corrected

1. The documented default-SIM checks at 6, 12, 18 and 24 hours were implemented
   as relative delays, producing approximately 6, 18, 36 and 60 hours.
2. A failed activation could be attempted again every five-second monitor cycle.
   Failed attempts did not consume the daily automatic-switch budget.
3. The activation controller returned the same result when rollback succeeded
   and when rollback also failed, leaving automation active in an unknown state.
4. A scheduled default-SIM check could be skipped for hours when a manual
   activation lock or short safety backoff temporarily deferred it.
5. The monitoring service had no crash-respawn policy and reloaded on unrelated
   cellular configuration events, which could interrupt its own transaction.
6. Health proof only supported IPv4 profiles.
7. Tests covered helper functions but not failed activation, retry backoff and
   rollback-critical state transitions.

## Implemented behavior

- Persists the failover start epoch and schedules default-SIM checks at absolute
  offsets of 6, 12, 18 and 24 hours. Later retries are every 24 hours.
- Counts every disruptive automatic switch attempt against the daily limit.
- Uses failure backoff of 30, 60, 120 and then 300 seconds. Backoff also applies
  to emergency failover so two unusable SIMs cannot create a switch storm. A
  proved healthy current path clears the failure streak while retaining the
  daily disruptive-attempt count.
- Uses exit status `3` to report “activation failed and rollback also failed.”
  The automatic controller immediately disables itself on this critical result,
  including when it occurs during optional active-profile recovery.
- Uses exit status `4` for temporary deferral. Manual-operation locks, cooldown
  and failed-attempt backoff are retried without consuming the next 6-hour slot.
- Adds bounded procd respawn (`3600 5 5`) and limits reload triggers to the
  `simmanager` configuration. Runtime vendor-controller conflict detection still
  runs every five seconds.
- Uses three interface-bound IPv6 probes for an explicitly `IPV6` profile.
  `IP` and `IPV4V6` profiles continue to require IPv4 reachability, preserving
  detection of a broken Jio XLAT/IPv4 path.
- Exposes the next failover-attempt time in runtime status.

The health proof deliberately remains routed-IP proof rather than DNS or HTTP
proof. DNS or web-service failures can be router/application configuration
faults and should not cause physical SIM churn. Three independent public IP
targets and a 2-of-3 quorum protect against one unreachable probe.

## Files

Router/package files:

- `/usr/sbin/simmanager-auto`
- `/usr/sbin/simmanager-control`
- `/etc/init.d/simmanager-auto`
- `/usr/lib/lua/luci/model/cbi/simmanager/automation.lua`

Project-only verification files were also updated:

- `luci-app-simmanager/Makefile` (package release 2)
- `tests/test-auto-policy.sh`
- `tests/test-auto-switch-state-machine.sh` (new)
- `tests/test-backup-policy.sh`
- `tests/test-fast-switch-policy.sh`
- `scripts/verify.sh`

## Verification performed

`sh scripts/verify.sh` passed and covered:

- Shell syntax and package safety checks.
- Absolute default-SIM retry offsets.
- Persistent retry/backoff state.
- Daily attempt budget and cooldown behavior.
- Temporary-defer return behavior.
- IPv4 and IPv6 2-of-3 probe policy.
- Failed activation backoff and retry-storm prevention.
- Critical rollback failure disabling.
- Backup separation and rollback result propagation.
- RM500U fast GPIO path, Jio state policy and SMS regression tests.

No router, modem or live network verification was performed.

The archived patch can be reproduced against a copy of `original/` with
`patch -p3 < change.patch` from the repository root path layout used here.
`MANIFEST.sha256` records every archived pre-change and post-change file.

## Future deployment

Before deployment, capture the exact live versions of all four router files and
compare them with `original/`. If any differ, rebase this patch onto those live
files rather than overwriting them. After deployment:

1. Restart `simmanager-auto` through its init script.
2. Verify `procd` reports the service running.
3. Simulate one short outage below threshold and confirm no switch.
4. Simulate one sustained outage and confirm one switch attempt only.
5. Verify failed-target rollback and the 30-second backoff.
6. Reconcile the deployed files into `current_first_router/files/`, regenerate
   its manifest and compare hashes with the live router.

## Rollback

Restore the four files from `original/`, clear LuCI caches if the CBI file was
installed, and restart `simmanager-auto`. Preserve `/etc/simmanager/backups/`;
this change does not alter or delete activation checkpoints.
