# SIM Manager AT-lock inheritance fix

## Status

Deployed to the first router on 27 November 2026 after the first live CFUN/GPIO
R&D switch exposed a lock-lifetime defect.

## Confirmed failure

The SIM switch to SIM2 started at 12:39:57 PM. The experimental path could not
prove `AT+CFUN=0`, so it correctly selected the unchanged vendor hard-power
fallback. SIM2 obtained Internet connectivity by approximately 12:40:47 PM,
but the activation page remained in `switching`.

`/proc/locks` showed the AT lock originally acquired by PID 31071. The vendor
RM500U worker (PID 3983) had inherited file descriptor 9 from the fast-switch
fallback and remained alive as a normal long-running process. Therefore the
AT lock could never be released. The activation controller and SMS auto-sync
were both blocked behind it.

## Changes

1. `simmanager-fast-switch` explicitly unlocks and closes descriptor 9 before
   either `cellular_sw()` or `watchsystem()` can launch a long-running worker.
2. Controller AT queries wait at most three seconds for the shared lock and at
   most six seconds for a query response.
3. The controller accepts its existing interface-bound 2-of-3 Internet proof
   as sufficient evidence that SIM readiness and carrier registration have
   completed. A busy diagnostic AT port can no longer hold a working switch in
   `switching`.
4. SMS auto-sync waits at most five seconds for the AT lock. On contention it
   skips that cycle and the daemon retries ten seconds later.

These changes do not change SIM selection, APN configuration, the vendor
fallback, rollback policy, modem firmware, network configuration or `br-lan`.

## Files and checksums

| Router file | Original | Changed |
| --- | --- | --- |
| `/usr/sbin/simmanager-control` | `820656798c6292fa9133f00cb79726212a2cfb87836bde1aa197b99f4588888a` | `167430c7eefd517ec3afc6ad8577d879542d6949f8c74192ae54b944989efe7e` |
| `/usr/sbin/simmanager-fast-switch` | `ec6f078e71694a7e17c6d12c10f3e6c0f8645b05403e015d7bbd6cb1aa6f14cc` | `a81fa9602d633bef2e710f912a99c7dd7778b8a895a7b33fdf7114dbeae452d7` |
| `/usr/sbin/simmanager-sms` | `9ec65330e3d393a467a80c58a4566e472a99a3a8d0ce76a915adcf7d25f9d830` | `df71a78c28b26a560edb2709b61966500504f0eda4021374bdff2051fd7133ee` |

`original/` contains the exact files that matched the live router before this
change. `changed/` contains the reviewed replacements. `change.patch` is the
reproducible unified diff.

## Verification

- POSIX shell syntax passed for all three changed scripts.
- The fast-switch test proves descriptor 9 is unlocked before both detector
  startup and hard fallback.
- The activation policy test proves routed Internet bypasses a blocked AT
  readiness or registration query.
- Deployment does not itself switch SIMs or restart the cellular interface.

## Live recovery

The already-running old vendor worker must be stopped once after deployment
because it inherited the stale descriptor before this fix existed. Starting a
fresh worker releases that historical lock and allows the existing activation
controller to finish. This is a one-time recovery, not a recurring restart.

## Rollback

Restore all three files from `original/` with mode `0755`. If the historical
stale descriptor still exists, restart only the RM500U polling worker; do not
restart the router or the full network.

## Deployment and recovery record

The reviewed files were deployed with matching live checksums. The exact
pre-change files are backed up on the router under
`/root/simmanager-at-lock-fix-backup-20261127-1245/`.

The one old RM500U polling worker that had inherited descriptor 9 was stopped
and a clean detector was started. The already-running activation then advanced
to `success` for SIM2. `br-lan` remained up, cellular remained on `lan5` with
`192.168.42.2`, the AT lock cleared normally, and all three bound Internet
probes passed in three consecutive verification rounds.
