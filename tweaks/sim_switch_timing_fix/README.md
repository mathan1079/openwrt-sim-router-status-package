# SIM switch timing fix

> Status: reverted/inactive as of 26 November 2026. Neither `changed/` file in
> this folder matches the first router. Keep this folder for investigation and
> history only; do not deploy it without merging and revalidating later Jio and
> activation-control changes.

## Scope

This first-router-only change removes a redundant second modem reboot from both SIM Manager activation and the vendor Cellular page's physical SIM-change path. It does not modify the downstream OpenWrt router.

## Confirmed failure timeline

The 25 November 2026 switch started at 18:17:28 IST. The RM500U disappeared from USB at 18:17:29 and returned at 18:17:52. SIM Manager reported success at 18:19:46, but a background cellular reload caused another USB reboot from 18:20:43 until 18:21:06. Cellular IPv4 became stable at 18:21:51 and the downstream router declared WAN2 online at 18:22:03. Effective recovery time was about 4 minutes 35 seconds.

The downstream `br-lan` did not restart. The modem-facing link repeatedly dropped, causing WAN, firewall, routing and connection-tracking events that appeared to clients as a LAN outage.

## Root cause

- The vendor physical SIM switch already changes the GPIO selector, performs the required modem hardware cycle and starts modem detection.
- SIM Manager then called `/etc/init.d/cellular reload` again. The vendor reload reapplied modem settings and could schedule another asynchronous power cycle.
- The vendor Cellular page always used the full reload path after saving, even when the only disruptive operation needed was the physical SIM change.
- Registration could be observed before the asynchronous second reboot, so the previous controller could report success too early.

## Changes

### `/usr/sbin/simmanager-control`

- Records whether the activation actually changed the physical SIM.
- Skips the redundant full cellular reload after a physical switch; the vendor switch already starts the RM500U worker using the saved profile.
- Keeps the ordinary reload path when reapplying the currently active SIM profile.
- Requires registration, a cellular IPv4 address and three consecutive interface-bound Internet checks before reporting success.
- Uses three parallel probes and requires at least two successes per check.
- Avoids the redundant reload when rollback physically switches back to the previous SIM.

### `/etc/init.d/cellular`

- Detects whether the desired SIM differs from the GPIO selector's current value.
- For a physical SIM change, performs one hardware switch cycle and restarts modem detection without running the redundant full cellular-settings reload first.
- Preserves the original full reload path when the physical SIM is unchanged.

## Expected behavior

- One unavoidable modem power cycle per physical SIM change.
- Typical recovery target: 30 to 60 seconds, subject to carrier registration.
- No full OpenWrt network restart.
- Success is not reported while the modem is still rebooting or before Internet connectivity is stable.

## Deployment files

- `original/` contains exact pre-change copies from the first router.
- `changed/` contains the files deployed by this tweak.
- `change.patch` is the reproducible diff.

## Deployment record

- Deployed to the first SIM router on 25 November 2026 without restarting the cellular service or network.
- Router-side originals are also stored under `/root/sim-switch-timing-backup-20261125-1836/`.
- Post-deployment hashes matched the reviewed `changed/` files, router uptime was preserved, and no USB disconnect or `br-lan` event was logged during installation.

## Verification

After a controlled SIM switch, verify:

1. Exactly one USB disconnect/reconnect pair for the RM500U.
2. Exactly one physical SIM selector change.
3. Cellular IPv4 becomes available.
4. Three consecutive connectivity checks pass before success.
5. No `br-lan` down/up event and no full network reload.

## Rollback

Restore both files from `original/`, preserve their executable permissions, and restart only the cellular service if operationally required. Restoring files alone does not require a router reboot.
