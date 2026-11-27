# RM500U dedicated CFUN control-port fix

## Status

Deployed to the first router on 27 November 2026 after a controlled live CFUN
test proved the correct modem port and response semantics.

## Confirmed evidence

With SMS sync and the vendor polling worker paused:

- `/dev/ttyUSB2` returned crossed SMS/vendor replies and is not reliable for
  exclusive SIM-switch control.
- `/dev/ttyUSB3` answered `AT` and `AT+CFUN?` correctly.
- `AT+CFUN=0` changed the proved state to `+CFUN: 0` in about one second but
  omitted a trailing `OK` on this firmware.
- `AT+CFUN=1` restored `+CFUN: 1` and `CPIN: READY` about two seconds later,
  also without a trailing `OK`.
- The complete controlled CFUN cycle took approximately four seconds with no
  USB disconnect, SIM change, GPIO change, router restart or `br-lan` outage.

## Change

The isolated fast-switch helper now:

1. Uses `/dev/ttyUSB3` for CFUN, ICCID and SIM-readiness proof, falling back to
   the configured AT device only if that control device does not exist.
2. Treats `AT+CFUN?` state `0` as the authoritative proof for `CFUN=0`.
3. Requires `AT+CFUN?` state `1`, `CPIN: READY` and a valid changed ICCID before
   accepting the target SIM after `CFUN=1`.
4. Keeps `/dev/ttyUSB2` unchanged for the vendor worker and SMS stack.
5. Retains the unchanged hard-power fallback for every unproved state.

## File and checksums

| Router file | Original | Changed |
| --- | --- | --- |
| `/usr/sbin/simmanager-fast-switch` | `27cd7ae6870240c71749fe2f7708f48946957a8768546e8765c5aed1440cd4f8` | `1b98d79b95411fcc8b214516a0452c6d6275bb1fd164969f1fe9e575d9929df2` |

## Tests

- POSIX shell syntax passed.
- The mocked modem omits `OK` from both CFUN transitions; the proved-state fast
  path still completes.
- The test confirms the dedicated control-port override is used.
- Existing GPIO precondition, GPIO read-back, hard fallback and lock-release
  tests pass.

## Deployment safety

Replacing this helper does not initiate a switch, send an AT command, restart
the modem, reload the network or alter UCI. The first subsequent user-triggered
switch is the live verification.

The deployed checksum matched the reviewed file. SIM1 remained selected with
GPIO `1`; activation remained `success`; `br-lan` stayed up; and all three
interface-bound Internet probes passed. The pre-change live helper is backed
up under `/root/rm500u-cfun-control-port-fix-backup-20261127-1310/`.

## Rollback

Restore the exact file from `original/usr/sbin/simmanager-fast-switch` to
`/usr/sbin/simmanager-fast-switch` with mode `0755`.
