# Consolidated OpenWrt router tweaks

This directory is the single technical archive for first-router changes. It is
organized by five functional topics, with one shared pre-change baseline.

```text
tweaks/
├── original/
├── 01-platform_maintenance/
├── 02-cellular_runtime_stability/
├── 03-sim_switching_and_activation/
├── 04-carrier_profiles_and_jio/
└── 05-automatic_switching/
```

## Layout

- `original/` contains the earliest preserved baseline for every managed file.
- Each numbered topic contains its cumulative `changed/` files.
- Each topic's `change.patch` compares the central baseline with that topic's cumulative changed files.
- Every directory has a `MANIFEST.sha256` integrity manifest.

The cumulative changed files were verified byte-for-byte against the former authoritative `current_first_router` snapshot before the fragmented folders were removed. The exception is `/etc/config/cellular`, which was verified against the later LTE/NR network-mode stage because it was not part of that snapshot.

Intermediate pre-consolidation stages remain available through Git history. The
files in this directory represent the maintained cumulative state.

## Topics

1. [`01-platform_maintenance`](01-platform_maintenance/README.md) — watchdog, package feeds and packaged helper permissions.
2. [`02-cellular_runtime_stability`](02-cellular_runtime_stability/README.md) — modem worker, monitoring and network-isolation stability.
3. [`03-sim_switching_and_activation`](03-sim_switching_and_activation/README.md) — activation, rollback, connectivity proof and fast switching.
4. [`04-carrier_profiles_and_jio`](04-carrier_profiles_and_jio/README.md) — carrier profiles, LTE/NR selection and Jio IPv6/464XLAT behavior.
5. [`05-automatic_switching`](05-automatic_switching/README.md) — automatic failover policy, lifecycle and persistent history.

## Maintenance rule

For a future change, update the relevant numbered topic instead of creating a new top-level tweak folder. Preserve a new baseline in `original/` only when a previously unmanaged file is introduced. Then update the topic documentation, cumulative changed file, `change.patch`, topic manifest, root status and root manifest in the same task.

These files are specific to the ZBT-Z8106AX-2SIM vendor OpenWrt build and the Quectel RM500U modem. Do not apply them blindly to another device or firmware.
