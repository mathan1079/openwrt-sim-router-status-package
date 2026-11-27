# RM500U ICCID padding normalization fix

## Status

Deployed to the first router on 27 November 2026 after the first dedicated
`/dev/ttyUSB3` fast-switch test.

## Confirmed cause

The SIM1 to SIM2 CFUN/GPIO transition completed without a USB restart, but the
helper waited for 15 seconds and reported that the new ICCID was not ready.
Live control-port queries proved `CFUN: 1`, `CPIN: READY` and SIM2 ICCID
`8991000923788177231F`.

The final `F` is the unused BCD padding nibble commonly exposed by modem ICCID
responses. It is not part of the decimal ICCID. The digits-only validator
therefore rejected an otherwise valid and ready SIM2.

## Change

One trailing `F` or `f` is removed from old and new modem ICCID replies before
decimal validation and identity comparison. No internal or middle character is
changed. The normalized value must still contain exactly 19 or 20 digits.

All existing CFUN-state, CPIN, changed-ICCID, GPIO read-back, lock-release and
hard-fallback proofs remain mandatory.

## File and checksums

| Router file | Original | Changed |
| --- | --- | --- |
| `/usr/sbin/simmanager-fast-switch` | `1b98d79b95411fcc8b214516a0452c6d6275bb1fd164969f1fe9e575d9929df2` | `f18388ddaf5457e14deb3134dc086b60ce93248aff5d330a9bad15c11d44b0fb` |

## Tests

- POSIX shell syntax passed.
- Mock SIM2 exposes a trailing `F`; switching to unpadded SIM1 succeeds.
- Existing dedicated-port, firmware-omitted CFUN `OK`, GPIO, fallback and lock
  tests all pass.

## Deployment safety

Replacing this helper does not send AT commands, switch SIMs, restart the
modem, reload the network or touch `br-lan`.

The deployed checksum matched the reviewed helper. SIM2 remained selected with
GPIO `0`; activation remained `success`; `br-lan` stayed up; and all three
Internet probes passed. The exact pre-change helper is backed up under
`/root/rm500u-iccid-padding-fix-backup-20261127-1316/`.

## Live switch verification

The first post-deployment SIM2 to SIM1 test started at 13:19:58 PM. The helper
proved `CFUN`, GPIO, `CPIN: READY` and SIM1 ICCID
`89918690400895597114` at 13:20:09 PM, approximately 11 seconds later. It
logged a successful fast GPIO switch and no USB disconnect or re-enumeration
occurred.

Jio routed Internet required additional carrier/packet-session recovery. The
controller reached final `success` at 13:20:42 PM, approximately 44 seconds
after activation began. All three interface-bound probes passed afterward and
`br-lan` remained up. This separates the proved 11-second modem/SIM transition
from the slower Jio Internet attachment stage.

The reverse SIM1 to SIM2 test started at 13:21:43 PM. The helper normalized the
raw padded ICCID, proved SIM2 as `8991000923788177231`, and logged fast-path
success at 13:21:51 PM, approximately 8 seconds later. The controller reached
final `success` at approximately 13:22:15 PM, about 32 seconds after activation
began. All probes passed, GPIO was `0`, and there was no USB restart or fallback.

Both switch directions are therefore live-proven on this router. SIM/CFUN/GPIO
transition takes 8 to 11 seconds; total Internet recovery measured 32 seconds
for Airtel and 44 seconds for Jio in these tests.

## Rollback

Restore `original/usr/sbin/simmanager-fast-switch` to
`/usr/sbin/simmanager-fast-switch` with mode `0755`.
