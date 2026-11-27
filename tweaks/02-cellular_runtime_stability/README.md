# Cellular runtime stability

This merged topic owns the cumulative RM500U vendor-worker, ping-monitor and
cellular-only network recovery changes.

## Cumulative changed files

- `/usr/sbin/cellular/quectel_rm500u`
- `/usr/sbin/cellular/cellular_Prepare`
- `/usr/sbin/cellular/cellular_detect`
- `/usr/sbin/ping_cellular.sh`

Together they provide atomic modem-status output, single-worker ownership,
safe signal termination, AT-reply validation, restart-loop prevention, stable
ping monitoring and SIM-change isolation from `br-lan` and the full network.

## Source stages merged

1. `celluar_crash_fix` (legacy spelling retained in history)
2. `sim_switch_network_isolation_fix`
3. `cellular_ping_monitor_stability_fix`
4. `cellular_worker_single_instance_fix`
5. `modem_command_collision_restart_fix`

`changed/` is the cumulative current state. Earlier intermediate stages remain
available through Git history.
