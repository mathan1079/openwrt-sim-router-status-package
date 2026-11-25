# OpenWrt router tweaks

This directory archives router-level changes that are intentionally kept separate from `luci-app-simmanager`.

Each tweak contains:

- `original/` — the exact file preserved on the router before the change.
- `changed/` — the exact file currently deployed on the router.
- `change.patch` — a reproducible unified diff.
- `README.md` — cause, implementation, deployment, verification and rollback documentation.

## Available tweaks

| Tweak | Purpose | Router file |
| --- | --- | --- |
| [`celluar_crash_fix`](celluar_crash_fix/README.md) | Prevent malformed or partially-written `/tmp/4ginfo` JSON from crashing the Cellular/LuCI status page. The directory name intentionally follows the requested spelling. | `/usr/sbin/cellular/quectel_rm500u` |
| [`router_watchdog_restart_prevention`](router_watchdog_restart_prevention/README.md) | Continuously feed the board's external hardware watchdog so it does not reboot a healthy router every few minutes. | `/etc/config/watchdog` |
| [`sim_switch_network_isolation_fix`](sim_switch_network_isolation_fix/README.md) | Correct the vendor physical-interface selection, replace global reloads with cellular-only recovery, and prevent overlapping detector and RM500U workers. | `/usr/sbin/cellular/cellular_Prepare`, `/usr/sbin/cellular/cellular_detect`, `/usr/sbin/cellular/quectel_rm500u` |

These files are hardware/firmware-specific to the ZBT-Z8106AX-2SIM router and its vendor OpenWrt build. Do not apply them blindly to another model or firmware revision.
