# First-router tweak status

Last audited: 27 November 2026, after the first live CFUN/GPIO switch test.

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
| `sim_switch_fast_connectivity_acceptance` | Active/incorporated | Its two-round 2-of-3 Internet proof remains in the controller; latest controller delta is `rm500u_cfun_gpio_fast_switch`. |
| `jio_return_fast_path` | Active/latest delta | Preserves prepared Jio state per ICCID and avoids a second modem restart when returning to a known Jio SIM with live NAT/CLAT enabled. |
| `rm500u_cfun_gpio_fast_switch` | Active R&D/incorporated | Tries a proved CFUN/GPIO switch without USB restart and automatically falls back to unchanged vendor hard power cycling. Its first live fallback exposed an inherited AT-lock descriptor, corrected by `simmanager_at_lock_inheritance_fix`. |
| `simmanager_at_lock_inheritance_fix` | Active/latest activation safety delta | Closes the AT lock before long-running workers, bounds controller/SMS lock waits, and lets proved Internet complete activation. |
| `rm500u_gpio_readback_acceptance_fix` | Active/latest fast-helper delta | Uses the exact post-write GPIO read-back because this board can report a sysfs write failure after applying the selector value. |
| `rm500u_cfun_control_port_fix` | Active/latest fast-helper delta | Uses dedicated `/dev/ttyUSB3` and proves CFUN states instead of requiring firmware-omitted `OK` replies. |
| `rm500u_iccid_padding_fix` | Active/latest fast-helper delta | Normalizes one trailing ICCID padding nibble before strict decimal validation and identity proof. |
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
