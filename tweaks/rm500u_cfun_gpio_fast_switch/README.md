# RM500U CFUN/GPIO fast-switch R&D path

## Status

Active for controlled testing on the first router from 27 November 2026.
This is an experimental fast path with the unchanged vendor hard power-cycle
mechanism retained as the automatic fallback.

## Confirmed cause of the 23-second hardware delay

The ZBT router does not use RM500U native SIM slots 1 and 2. Both saved SIM
profiles map to the module's internal slot 1, while `/sys/class/gpio/sim/value`
selects which physical card reaches that slot. The vendor `cellular_sw()` path
changes this GPIO and then unconditionally powers the complete modem off.

`turn_off_on_cellular()` holds modem power off for five seconds, powers it on,
and waits another five seconds. In measured switches the USB modem returned
approximately 23 seconds after disconnection, so most of the remaining delay
was RM500U boot and USB enumeration.

Quectel's RM500U AT manual documents `AT+QUIMSLOT` as immediate with a maximum
500 ms command response, but that does not select this board's external GPIO
multiplexer. The same manual documents `AT+CFUN=0` as minimum functionality and
`AT+CFUN=1` as full functionality, and says SIM hot-swap control is valid when
the module does not detect a SIM or is in `CFUN=0`.

Official reference:
<https://quectel.com/content/uploads/2024/02/Quectel_RGx00URM500U_Series_AT_Commands_Manual_V1.0.pdf>

## Safe fast path

`/usr/sbin/simmanager-fast-switch` is used only by SIM Manager. It does not
replace or modify `/lib/functions/cellular.sh`.

1. Validate RM500U model, target SIM, current SIM, GPIO paths and complementary
   GPIO values before sending commands.
2. Confirm the live GPIO still matches the currently active SIM.
3. Stop the vendor RM500U polling worker to prevent crossed AT replies.
4. Serialize the complete operation with the existing SIM Manager AT lock.
5. Record the currently active ICCID when available.
6. Send `AT+CFUN=0` and require both `OK` and a `+CFUN: 0` read-back.
7. Commit the target SIM and change the external GPIO only after minimum
   functionality is proved.
8. Read the GPIO back and require an exact match.
9. Send `AT+CFUN=1` and require `OK`.
10. For at most 15 wall-clock seconds, require `CPIN: READY`, a valid ICCID and,
    when the old ICCID was readable, a different ICCID.
11. Restart normal cellular detection only after the new SIM is proved.

The first live fallback revealed that the AT-lock descriptor was inherited by
the long-running vendor worker. The follow-up
`simmanager_at_lock_inheritance_fix` closes that descriptor before either the
normal detector or hard fallback is started. This folder remains the exact
historical first R&D deployment stage.

## Automatic fallback

Any failure after the experiment begins calls the original `cellular_sw()`
function, which performs the existing hard power cycle. Unsupported hardware,
invalid configuration or a GPIO precondition mismatch causes the controller to
use the original function directly. Activation's existing Internet proof and
automatic rollback remain unchanged.

This means a failed experiment can be slower than the existing method, but it
must not leave an unproved SIM selected without attempting the known recovery
path.

## Expected timing

- Successful CFUN/GPIO transition and SIM readiness: approximately 3–15 seconds.
- Carrier registration and verified Internet: target approximately 10–30
  seconds, carrier dependent.
- Jio 5G SA/XLAT can take longer.
- Two-to-five-second client Internet recovery is not guaranteed because carrier
  attachment is outside router control.

## Files and checksums

| Router file | Original | Changed |
| --- | --- | --- |
| `/usr/sbin/simmanager-control` | `d46a0d53ef26fe9a0891dbfe18d1409941dc06ffb00c9cac54db81667bacef56` | `820656798c6292fa9133f00cb79726212a2cfb87836bde1aa197b99f4588888a` |
| `/usr/sbin/simmanager-fast-switch` | absent | `ec6f078e71694a7e17c6d12c10f3e6c0f8645b05403e015d7bbd6cb1aa6f14cc` |

`original/` preserves the exact live controller and records that the helper was
absent. `changed/` contains both reviewed deployment files. `change.patch` is
their reproducible unified diff.

## Tests

- POSIX shell syntax validation.
- Fast-path success without `AT+CFUN=1,1` or vendor fallback.
- Automatic vendor fallback when `CFUN=0` is not acknowledged.
- Rejection before any AT command when the GPIO precondition is inconsistent.
- Existing activation connectivity, backup and Jio state regression tests.

## Controlled verification

No SIM switch is initiated during deployment. On the next user-triggered
switch, confirm:

1. A `simmanager-fast-switch` success or fallback log is present.
2. A successful fast path has no RM500U USB disconnect/reconnect event.
3. GPIO, ICCID and target profile agree.
4. Two consecutive 2-of-3 Internet proofs pass.
5. No global network reload or `br-lan` down/up event occurs.
6. Both directions are tested repeatedly before considering the R&D path
   production-proven.

## Rollback

Restore the archived original `/usr/sbin/simmanager-control` and remove
`/usr/sbin/simmanager-fast-switch`. The controller will immediately return to
the unchanged vendor hard power-cycle path. Replacing these files does not
itself restart the modem, cellular interface, network or router.

## Deployment record

Deployed at 12:37 PM IST without initiating a SIM switch. SIM1/Jio remained
online on `lan5` with `192.168.42.2`, and cellular uptime continued through the
file replacement.

Live checksums matched the reviewed files. The pre-change controller backup is
under `/root/rm500u-cfun-fast-switch-backup-20261127-123732/`; the helper did
not previously exist.
