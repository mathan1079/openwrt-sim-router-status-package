# RM500U command-collision restart prevention

## Symptom

The router uptime remained stable, but the cellular interface and RM500U USB
device restarted every several minutes. Client Internet sessions were dropped.

## Confirmed cause

The vendor status worker, SMS service and management requests share the same AT
command port. Live testing returned a `QNWINFO` or `QNWPREFCFG` response to a
`QCFG` request, proving that replies can cross between callers.

The vendor worker only checked for generic `OK` and `+QCFG` text. A crossed
reply could therefore look like a transport mismatch and execute
`AT+CFUN=1,1`, which disconnects and re-enumerates the whole modem over USB.

The vendor dial helper also restarted cellular after a single empty ping result
and treated malformed `QNETDEVCTL` output as a stopped data call.

## Change

- Require the exact named `+QCFG` line for `pcie/mode`, `ethernet` and `usbnet`.
- Permit a hard modem restart only after an exact, validated mismatch.
- Replace the vendor dial helper inside this worker with a conservative helper.
- Ignore an isolated failed ping while the interface still owns an IPv4 address.
- Recover missing DHCP only at the cellular interface level.
- Act on `QNETDEVCTL` only when the response exactly identifies PDP context 1.
- Add explicit logs for every recovery and any ignored crossed reply.

## Router file

`/usr/sbin/cellular/quectel_rm500u`

## Rollback

Restore the timestamped copy from `/root/modem-command-collision-backup-*`, stop
the active worker and allow the vendor cellular service to start it again.

## Verification

After deployment, verify that router uptime, modem USB device number and
cellular interface uptime continue increasing. There must be no unplanned
`USB disconnect` or `AT+CFUN=1,1` event.
