# First-router tweak status

Last audited: 27 November 2026, 12:18 PM IST.

This is the ownership map for router-level changes. The exact current files are
under `current_first_router/files/`.

| Tweak | Status | Notes |
| --- | --- | --- |
| `router_watchdog_restart_prevention` | Active | Local changed file exactly matched `/etc/config/watchdog`. |
| `sim_switch_network_isolation_fix` | Active/incorporated | Preparation and detector match live. Its historical worker stage is incorporated into the cumulative current worker. |
| `cellular_ping_monitor_stability_fix` | Active | Local changed file exactly matched `/usr/sbin/ping_cellular.sh`. |
| `jio_ipv6_xlat_fix` | Active/incorporated | Worker integration remains live, including retention of prepared state across invalid ICCID samples; helper behavior is superseded by `jio_return_fast_path`. |
| `cellular_worker_single_instance_fix` | Active/incorporated | Signal and PID-lock behavior is in the cumulative worker. |
| `modem_command_collision_restart_fix` | Active/latest delta | Complete before/after worker files and a real unified patch are archived here. |
| `opkg_feed_cleanup` | Active | Removes duplicate, obsolete snapshot and missing MediaTek feeds without changing installed packages. |
| `sim_switch_fast_connectivity_acceptance` | Active/latest delta | Skips the redundant post-switch reload and accepts a new SIM after two consecutive 2-of-3 Internet proofs. |
| `jio_return_fast_path` | Active/latest delta | Preserves prepared Jio state per ICCID and avoids a second modem restart when returning to a known Jio SIM with live NAT/CLAT enabled. |
| `celluar_crash_fix` | Active/incorporated | Atomic JSON behavior remains in the cumulative worker. Its old standalone changed worker is historical and must not be deployed over the current worker. |
| `sim_switch_timing_fix` | Reverted/inactive | Neither archived changed file matches the router. Do not deploy without a fresh review and merge. |

## No longer present

`sim_switch_network_reload_prevention` is not present and is not required. Its
useful behavior was superseded by `sim_switch_network_isolation_fix`.

## Required workflow for every future tweak

1. Save the exact live pre-change file under the tweak's `original/` path.
2. Save the exact reviewed post-change file under `changed/`.
3. Generate a real unified `change.patch` from those two files.
4. Document cause, scope, deployment, verification and rollback in `README.md`.
5. Update `current_first_router/files/` only after successful deployment.
6. Update `current_first_router/MANIFEST.sha256` and this status file.
7. Verify every current snapshot checksum equals the corresponding live router file.

Historical tweak files must never be assumed to be the latest cumulative
version merely because they are under a `changed/` directory.
