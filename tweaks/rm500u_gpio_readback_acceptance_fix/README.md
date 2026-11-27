# RM500U GPIO read-back acceptance fix

## Status

Deployed to the first router on 27 November 2026.

## Confirmed cause

During the SIM2 to SIM1 test, the activation ran from 12:53:27 PM to 12:54:00
PM. The board's SIM selector changed successfully to GPIO value `1`, the
physical SIM1 ICCID became active, and Internet recovered. However, the sysfs
write returned a failure status after applying the value. The helper therefore
logged `SIM GPIO could not be changed` and entered fallback before performing
its existing read-back check.

No USB modem disconnect occurred in that test. The physical GPIO and SIM1
ICCID proved that the write itself had taken effect.

## Change

The helper now treats the immediate GPIO read-back as authoritative:

1. Attempt to write the target selector value.
2. Read `/sys/class/gpio/sim/value` immediately.
3. Continue only when the read value exactly equals the target.
4. Use the unchanged vendor fallback when the value does not match.

Ignoring only the write return code is safe here because the following
read-back remains mandatory. No modem, APN, rollback, network or firmware
behavior is otherwise changed.

## File and checksums

| Router file | Original | Changed |
| --- | --- | --- |
| `/usr/sbin/simmanager-fast-switch` | `a81fa9602d633bef2e710f912a99c7dd7778b8a895a7b33fdf7114dbeae452d7` | `27cd7ae6870240c71749fe2f7708f48946957a8768546e8765c5aed1440cd4f8` |

`original/` is the exact pre-change live helper. `changed/` is the reviewed
replacement. `change.patch` is their reproducible unified diff.

## Tests

- POSIX shell syntax passed.
- Existing CFUN/GPIO success, fallback and GPIO-precondition tests passed.
- Policy test confirms that GPIO acceptance remains protected by exact
  read-back and no longer falls back on the write return code alone.

## Deployment

Deployment replaces only the helper and does not initiate a SIM switch,
restart the modem, reload the cellular interface or touch `br-lan`.

The deployed checksum matched the reviewed helper. SIM1 remained selected with
GPIO value `1`, activation remained `success`, and all three interface-bound
Internet probes passed after installation. The exact live pre-change helper is
backed up under
`/root/rm500u-gpio-readback-fix-backup-20261127-1258/`.

## Rollback

Restore `original/usr/sbin/simmanager-fast-switch` to
`/usr/sbin/simmanager-fast-switch` with mode `0755`.
