# Cellular worker single-instance signal fix

> Status: active and incorporated into the cumulative RM500U worker archived
> under `../current_first_router/files/usr/sbin/cellular/quectel_rm500u`.

## Problem

The RM500U worker used the same cleanup function for `EXIT`, `HUP`, `INT` and
`TERM`. On a signal it removed its lock directory but did not terminate. The
launcher could then start a replacement while the old worker continued
running. Both workers dialled and recovered the same modem, repeatedly taking
the cellular interface down and up.

## Change

- Keep lock cleanup on normal process exit.
- On `HUP`, `INT` or `TERM`, release the owned lock and immediately exit.
- Preserve stale-lock recovery for genuinely dead processes.

## Files

- Router: `/usr/sbin/cellular/quectel_rm500u`
- Current cumulative source:
  `tweaks/current_first_router/files/usr/sbin/cellular/quectel_rm500u`
- Reproducible delta: `change.patch`

## Verification

After deployment, exactly one `quectel_rm500u` process must remain. Sending a
termination signal must end the old process before the launcher starts a new
one. Cellular DHCP and the physical `lan5` link must remain stable after Jio
connectivity succeeds.

## Rollback

Restore the router copy backed up immediately before deployment and restart
only the cellular worker.
