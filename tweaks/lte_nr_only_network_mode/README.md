# LTE and 5G-only network mode

## Status

Deployed to the first router on 27 November 2026. The `original/` tree contains
the exact live router files from the pre-deployment backup. The `changed/` tree
contains the corresponding live router files after deployment. Repository
build files and tests remain in their normal project locations and are not
duplicated in this tweak archive.

## Purpose

Both installed operators provide LTE and 5G service, so WCDMA scanning is not
needed. The SIM Profiles page now presents three checkboxes in the existing
Preferred network mode row:

- 4G LTE
- 5G SA
- 5G NSA

At least one must be selected. The recommended Jio and Airtel configuration is
all three options. Automatic band selection remains enabled; this change does
not lock or remove any LTE or NR band.

## RM500U mapping

| Selected UI modes | Stored RM500U `mode_pref` |
| --- | --- |
| LTE | `LTE` |
| 5G SA | `NR5G-SA` |
| 5G NSA | `NR5G-NSA` |
| 5G SA + NSA | `NR5G` |
| LTE + 5G SA | `NR5G-SA:LTE` |
| LTE + 5G NSA | `NR5G-NSA:LTE` |
| LTE + 5G SA + NSA | `NR5G:LTE` |

Legacy `AUTO` values render as all three choices and are migrated to
`NR5G:LTE`. The activation validator accepts only the seven documented safe
combinations above.

## Jio interaction

The Jio IPv6/CLAT helper previously forced both the profile and modem back to
`AUTO`. It now reads the selected SIM profile, validates the mode, applies it
through the shared AT lock only when needed, stores it in cellular UCI and
includes it in the per-ICCID prepared-state signature. NAT, CLAT, APN and
restart-cooldown safeguards remain unchanged.

## Upgrade behavior

Package release 3 migrates existing SIM1, SIM2 and vendor cellular `AUTO`
values to `NR5G:LTE`. Existing explicit LTE- or 5G-specific selections are
preserved. Installing the package does not restrict bands.

## Archived router files

- `/etc/config/cellular`
- `/etc/config/simmanager`
- `/usr/lib/lua/luci/model/cbi/simmanager/profiles.lua`
- `/usr/sbin/simmanager-control`
- `/usr/sbin/simmanager-jio-ensure`

## Verification

- Every single and multi-selection combination maps to the intended RM500U
  value.
- Empty selection is rejected.
- Legacy `AUTO` expands to LTE, SA and NSA in the UI.
- Jio preparation applies the selected mode and never writes `AUTO`.
- Existing automatic-switch, rollback, fast-switch, GPIO, Jio, SMS, Lua and
  shell checks pass.

## Deployment verification

After installing release 3:

1. Confirm SIM1 and SIM2 display LTE, 5G SA and 5G NSA as selected.
2. Confirm `AT+QNWPREFCFG="mode_pref"` returns `NR5G:LTE` after applying the
   active profile.
3. Confirm Jio still obtains routed IPv4 through CLAT and native IPv6.
4. Confirm Airtel can register on LTE or 5G NSA/SA as available.
5. Confirm SIM switching, rollback and `br-lan` remain unaffected.

Release `1.6.0-3` upgraded successfully from `1.6.0-2`. The post-install
migration set SIM1, SIM2 and vendor `m_netmode` to `NR5G:LTE`. The live modem
was then changed through the shared AT lock and confirmed:

- `AT+QNWPREFCFG="mode_pref"` returned `NR5G:LTE`.
- `AT+QNWINFO` remained Jio `NR5G-SA` on n78.
- IPv4 and IPv6 recovered after the expected brief packet-session reconnect.
- `br-lan` remained `UP,LOWER_UP`; router uptime was uninterrupted.
- Automatic switching observed two degraded rounds during the reconnect, did
  not reach the failover threshold, and returned to healthy monitoring.

The live pre-deployment backup is:

`/root/lte-nr-only-mode-backup-20261127-1530/`

## Rollback

Restore the five router files from `original/`, preserving their paths and
permissions, then clear the LuCI cache. To restore the modem's live search
behavior immediately, apply the active profile through the normal guarded
activation path. The same exact originals remain available on the router under
`/root/lte-nr-only-mode-backup-20261127-1530/`.
