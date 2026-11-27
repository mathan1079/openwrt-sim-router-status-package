# OpenWrt router tweaks

This directory archives router-level changes that are intentionally kept separate from `luci-app-simmanager`.

Every new tweak must contain:

- `original/` — the exact file preserved on the router before the change.
- `changed/` — the exact file produced by that tweak at the time it was deployed.
- `change.patch` — a reproducible unified diff.
- `README.md` — cause, ownership status, implementation, deployment, verification and rollback documentation.

[`current_first_router/`](current_first_router/README.md) is the authoritative
byte-for-byte snapshot of files currently deployed on the first router. When
multiple tweaks modify the same vendor file, the current snapshot takes
precedence over an older tweak's historical `changed/` copy.

[`STATUS.md`](STATUS.md) records which tweaks are active, incorporated into a
newer cumulative file, or reverted.

## Available tweaks

| Tweak | Ownership status | Router file |
| --- | --- | --- |
| [`celluar_crash_fix`](celluar_crash_fix/README.md) | Active, incorporated into cumulative worker | `/usr/sbin/cellular/quectel_rm500u` |
| [`router_watchdog_restart_prevention`](router_watchdog_restart_prevention/README.md) | Active, exact standalone file | `/etc/config/watchdog` |
| [`sim_switch_network_isolation_fix`](sim_switch_network_isolation_fix/README.md) | Active; preparation/detector exact, worker delta incorporated | Three cellular vendor scripts |
| [`sim_switch_timing_fix`](sim_switch_timing_fix/README.md) | Reverted/inactive; retained for history only | `/etc/init.d/cellular`, `/usr/sbin/simmanager-control` |
| [`jio_ipv6_xlat_fix`](jio_ipv6_xlat_fix/README.md) | Active, incorporated into cumulative worker and helper | Worker, controller and Jio helper |
| [`cellular_worker_single_instance_fix`](cellular_worker_single_instance_fix/README.md) | Active, incorporated into cumulative worker | `/usr/sbin/cellular/quectel_rm500u` |
| [`cellular_ping_monitor_stability_fix`](cellular_ping_monitor_stability_fix/README.md) | Active, exact standalone file | `/usr/sbin/ping_cellular.sh` |
| [`modem_command_collision_restart_fix`](modem_command_collision_restart_fix/README.md) | Active, latest cumulative worker delta | `/usr/sbin/cellular/quectel_rm500u` |
| [`opkg_feed_cleanup`](opkg_feed_cleanup/README.md) | Active, exact standalone file | `/etc/opkg/distfeeds.conf` |
| [`sim_switch_fast_connectivity_acceptance`](sim_switch_fast_connectivity_acceptance/README.md) | Active, latest activation-control delta | `/usr/sbin/simmanager-control` |
| [`jio_return_fast_path`](jio_return_fast_path/README.md) | Active, latest Jio-helper delta | `/usr/sbin/simmanager-jio-ensure` |

These files are hardware/firmware-specific to the ZBT-Z8106AX-2SIM router and its vendor OpenWrt build. Do not apply them blindly to another model or firmware revision.

## Mandatory maintenance rule

Every router deployment must update its tweak folder and
`current_first_router/` in the same task. The work is not complete until the
live checksum, current snapshot checksum, real unified patch and documentation
all agree. Never silently overwrite an earlier tweak's `changed/` file.
