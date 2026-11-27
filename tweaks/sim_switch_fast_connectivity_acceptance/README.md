# Fast SIM-switch connectivity acceptance

## Status

Active on the first router from 27 November 2026. This supersedes the reverted
`sim_switch_timing_fix`; that historical folder remains inactive.

## Confirmed timing

The SIM1-to-SIM2 activation on 27 November 2026 started at 11:44:31 AM. The
RM500U disconnected at 11:44:32 AM, returned at 11:44:55 AM and the cellular
interface obtained `192.168.42.2` at 11:45:07 AM. Internet was therefore ready
after about 36 seconds, but SIM Manager did not report success until 11:46:23
AM: approximately 76 seconds of avoidable post-connectivity waiting.

## Cause

The vendor `cellular_sw` path already changes the physical slot, performs the
required RM500U hardware cycle and restarts detection. The controller then ran
`/etc/init.d/cellular reload` again and waited for serial `CEREG`/`C5GREG`
responses. Several processes share the AT port, so those replies may be delayed
or crossed even after real Internet connectivity is available.

## Change

- Records whether the activation physically changed SIM slots.
- Skips the redundant cellular reload only after a physical slot change.
- Keeps the normal cellular reload when reapplying the currently active SIM.
- Treats an up cellular interface with an IPv4 address plus at least two of
  three successful interface-bound probes as one healthy round.
- Requires two consecutive healthy rounds, two seconds apart, before success.
- Uses `1.1.1.1`, `8.8.8.8` and `9.9.9.9` in parallel.
- Retains up to 45 rounds for genuinely slow registration and preserves the
  existing automatic rollback path when connectivity cannot be proved.
- Applies the same connectivity proof before declaring rollback complete.
- Keeps SIM-ready validation and all existing backup, vendor-conflict and
  manual/automatic rollback protections.

## Expected behavior

- One unavoidable RM500U USB disconnect/reconnect per physical SIM change.
- Typical successful switch target: 35–50 seconds, carrier dependent.
- No global network reload and no `br-lan` restart.
- A new SIM is never accepted merely because the SIM is present; real
  interface-bound Internet connectivity must pass twice.

## Files and checksums

| Router file | Original | Changed |
| --- | --- | --- |
| `/usr/sbin/simmanager-control` | `947c1724060913d1f9b4517f515a246a1a7387740b83040972fad624f0af6163` | `d46a0d53ef26fe9a0891dbfe18d1409941dc06ffb00c9cac54db81667bacef56` |

This historical controller stage is now incorporated into
`rm500u_cfun_gpio_fast_switch`; its connectivity-proof behavior remains active.

`original/` is the exact live pre-change file, `changed/` is the reviewed
deployment file and `change.patch` is their reproducible unified diff.

## Tests

- POSIX shell syntax validation.
- Existing backup-policy regression test.
- Fast-switch policy test proving that 2-of-3 probes pass, 1-of-3 fails, two
  consecutive healthy rounds are required and persistent failure is rejected.

## Deployment

Back up the live controller under `/root/`, copy the reviewed changed file to
`/usr/sbin/simmanager-control` with mode `0755`, and verify its checksum. File
replacement alone does not restart cellular, the modem, networking or router.

The live pre-change backup is
`/root/sim-switch-fast-acceptance-backup-20261127-1201/`.

Deployment verification at 12:02 PM IST confirmed the live checksum matched,
the controller remained idle, SIM2 stayed active, router uptime continued and
cellular uptime was not reset. No switch was initiated during deployment.
The deployed two-round 2-of-3 Internet proof passed against the active SIM in
two seconds.

## Controlled switch verification

1. Record activation start time.
2. Confirm exactly one RM500U USB disconnect/reconnect pair.
3. Confirm cellular obtains an address and two consecutive 2-of-3 probe rounds
   pass.
4. Confirm success is reported within the 35–50 second target when the carrier
   registers normally.
5. Confirm no second cellular reload, no global network reload and no
   `br-lan` down/up event.
6. Confirm failure still restores the pre-switch SIM/configuration checkpoint.

## Rollback

Restore `/usr/sbin/simmanager-control` from `original/` or the matching
`/root/` deployment backup and preserve mode `0755`. Replacing this file does
not require restarting cellular or the router.
