# Jio return fast path

## Status

Active on the first router from 27 November 2026. This is a cumulative update
to `/usr/sbin/simmanager-jio-ensure`; it preserves all persistent-state,
AT-locking, strict-reply and restart-cooldown safeguards already present on the
router.

## Confirmed cause

The existing helper stored one prepared ICCID in the shared file
`/etc/simmanager/state/xlat-cellular.state`. When another valid SIM ICCID was
observed, it deleted that shared marker. Returning to the previously prepared
Jio SIM therefore looked like a first-time Jio activation and triggered a
second `AT+CFUN=1,1` modem restart even when live NAT and CLAT queries both
reported enabled.

During the measured SIM2-to-SIM1 switch on 27 November 2026, that extra Jio
restart increased activation time to 98 seconds. The reverse SIM1-to-SIM2
switch, which did not need Jio preparation, completed in 50 seconds.

## Change

- Store prepared state per validated ICCID as
  `xlat-cellular-<ICCID>.state`.
- Store the restart cooldown per ICCID as
  `xlat-cellular-<ICCID>.restart`.
- Migrate the current shared persistent marker and matching cooldown without
  restarting the modem.
- Preserve markers belonging to inactive SIMs instead of deleting them when a
  different SIM becomes active.
- On return to a known Jio ICCID, skip configuration and modem restart only
  when live NAT and CLAT both report enabled.
- If either live setting explicitly reports disabled, repair the settings and
  retain the existing one-restart and 900-second cooldown behavior.
- If NAT/CLAT replies are uncertain for a known prepared ICCID, retain the
  existing safe behavior: do not restart the modem.
- A genuinely new Jio ICCID still receives one required activation restart.

## Expected result

Returning from SIM2/Airtel to the already prepared SIM1/Jio should use only the
physical SIM-switch modem cycle. With normal carrier registration, the target
is approximately 45–60 seconds instead of the measured 98 seconds. The exact
time remains carrier- and modem-registration-dependent.

## Files and checksums

| Router file | Original | Changed |
| --- | --- | --- |
| `/usr/sbin/simmanager-jio-ensure` | `139074f02b9a9af9c63e898713ab693a7abace80539b60beb618577ce6eed86c` | `f21161435a1d9991ad3a8e7b0741df495ed2c69332a8a9f0f42f533f5e98a9d1` |

`original/` contains the exact live pre-change helper. `changed/` contains the
reviewed deployment file. `change.patch` is their reproducible unified diff.

## Tests

`tests/test-jio-state-policy.sh` proves that:

1. Existing shared Jio state migrates to per-ICCID state without a restart.
2. Activating Airtel does not delete the saved Jio state.
3. Returning to prepared Jio with live NAT/CLAT enabled does not issue
   `AT+CFUN=1,1`.
4. Explicitly disabled NAT/CLAT is repaired and still requests one restart.

The backup-policy and fast-switch-policy regression tests are also required.

## Deployment

Back up the exact live helper under `/root/`, install the reviewed changed file
with mode `0755`, and verify its checksum. Replacing this helper alone does not
restart cellular, the modem, networking or the router.

Deployed at 12:18 PM IST. The live checksum matched the reviewed changed file:
`f21161435a1d9991ad3a8e7b0741df495ed2c69332a8a9f0f42f533f5e98a9d1`.
The live pre-change backup is
`/root/jio-return-fast-path-backup-20261127-121751/`.

Deployment did not restart cellular or the router. SIM2 remained online on
`lan5` with `192.168.42.2`; cellular uptime continued through deployment.

## Controlled verification

1. Switch from SIM2/Airtel to the previously prepared SIM1/Jio.
2. Confirm one RM500U USB disconnect/reconnect pair for the physical switch.
3. Confirm the log reports migration to per-SIM persistent storage at most
   once.
4. Confirm there is no `Restarting the RM500U` Jio-helper message when live NAT
   and CLAT are already enabled.
5. Confirm two consecutive 2-of-3 Internet proofs complete activation.
6. Confirm no global network reload and no `br-lan` down/up event.

## Rollback

Restore `/usr/sbin/simmanager-jio-ensure` from `original/` or the matching
deployment backup under `/root/`, preserving mode `0755`. File replacement does
not require restarting cellular or the router.
