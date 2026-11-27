# Network mode checkbox state fix

## Status

Deployed to the first router on 27 November 2026 as SIM Manager `1.6.0-4`.

## Cause

OpenWrt 21.02's `cbi/mvalue` template uses whitespace when it deserializes the
configured values used to mark checkboxes as selected. The first implementation
returned colon-separated RM500U values such as `LTE:NR5G-SA:NR5G-NSA`, so LuCI
treated the entire string as one unknown choice. The UCI and modem setting were
correct, but the page rendered all three checkboxes unchecked and submitting
the equivalent choices correctly produced no configuration change.

## Change

The existing SIM Profiles page now returns whitespace-separated values only to
the LuCI renderer. Validation and storage continue to use the colon-separated
RM500U `mode_pref` format. No modem policy, band selection, activation or
automatic-switch behavior changes.

## Router file

- `/usr/lib/lua/luci/model/cbi/simmanager/profiles.lua`

`original/` is the exact live release-3 file. `changed/` is the reviewed
release-4 file.

## Verification

- Legacy `AUTO` and stored `NR5G:LTE` render LTE, 5G SA and 5G NSA as checked.
- Mixed modes such as `NR5G-SA:LTE` render both corresponding choices.
- Single and multi-select storage mappings remain unchanged.
- The full SIM Manager regression suite passes.

Live verification confirmed that LuCI's `util.imatch()` now receives and emits
three independent values: `LTE`, `NR5G-SA` and `NR5G-NSA`. Both SIM profiles
remain stored as `NR5G:LTE`, the live modem remains `NR5G:LTE`, and IPv4 and
IPv6 connectivity stayed healthy. The router-side pre-fix backup is:

`/root/network-mode-checkbox-fix-backup-20261127-1545/`

## Rollback

Restore the file from `original/`, preserve mode `0644`, clear
`/tmp/luci-indexcache*`, and reload the SIM Profiles page.
