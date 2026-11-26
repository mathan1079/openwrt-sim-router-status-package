# Cellular ping-monitor stability fix

## Confirmed failure

At 21:42:51 on 25 November 2026, the router remained running but `lan5` and
the `cellular` interface were restarted. Two copies of `ping_cellular.sh` were
writing the same `/tmp/ping_cellular` file. Each cycle truncated that shared
file before appending probe results. The RM500U worker could read the file
during that empty window and falsely start cellular recovery.

## Change

- Permit only one ping monitor for each modem.
- Recover stale monitor locks safely.
- Write a complete probe cycle to a per-process temporary file.
- Atomically replace `/tmp/ping_cellular` only after the cycle is complete.
- Exit correctly on `HUP`, `INT` and `TERM`.

The modem, cellular interface and router do not need to restart when this file
is deployed.

## Files

- Router: `/usr/sbin/ping_cellular.sh`
- Exact pre-change file: `original/usr/sbin/ping_cellular.sh`
- Exact changed file: `changed/usr/sbin/ping_cellular.sh`
- Reproducible summary: `change.patch`

## Verification

Only one `ping_cellular.sh` process and one matching lock owner should remain.
The published ping file must never be observed at zero bytes during updates,
and `lan5` must not cycle when probes are succeeding.
