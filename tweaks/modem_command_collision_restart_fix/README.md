# RM500U command-collision restart prevention

> Status: active and the latest change to the cumulative RM500U worker.

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

## Archived files

| Copy | SHA-256 |
| --- | --- |
| `original/usr/sbin/cellular/quectel_rm500u` | `964d7c2c38cbe80ca7ef9d83456fcf77a599377f0099a1423bf2f78ad4309594` |
| `changed/usr/sbin/cellular/quectel_rm500u` | `e160b6270ff7b654320d84be11c1296b71e10138a20f763f44b7dbb7aa8d3c6a` |

`change.patch` is a complete unified diff between these exact files.

## Rollback

Restore the timestamped copy from `/root/modem-command-collision-backup-*`, stop
the active worker and allow the vendor cellular service to start it again.

## Verification

After deployment, verify that router uptime, modem USB device number and
cellular interface uptime continue increasing. There must be no unplanned
`USB disconnect` or `AT+CFUN=1,1` event.
