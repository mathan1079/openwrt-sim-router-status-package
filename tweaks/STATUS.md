# Consolidated first-router tweak status

Last updated: 28 November 2026.

| Topic | Cumulative state | Managed files |
| --- | --- | --- |
| `01-platform_maintenance` | Active | Watchdog and opkg feed configuration; packaged permission behavior documented |
| `02-cellular_runtime_stability` | Active | RM500U worker, cellular prepare/detect and ping monitor |
| `03-sim_switching_and_activation` | Active | Cellular init, activation controller, fast-switch helper, explicit empty-slot result and SMS helper |
| `04-carrier_profiles_and_jio` | Active | Cellular/SIM configuration, profiles UI and Jio helper |
| `05-automatic_switching` | Active | Automatic service, controller/UI, persistent history and confirmed SIM-removal failover guard |

## Historical status retained

Former stage-specific files remain available through Git history. The reverted
`sim_switch_timing_fix` is intentionally not applied to the cumulative changed
files.

`sim_switch_network_reload_prevention` was already obsolete and absent before this consolidation. Its useful behavior is represented by the cumulative cellular runtime stability files.

## Integrity result

Before consolidation, every one of the 18 files in the authoritative `current_first_router/files/` snapshot was compared byte-for-byte with its new topic owner and matched. The latest `/etc/config/cellular` also matched the merged carrier-profile copy. Manifests provide continuing integrity checks.
