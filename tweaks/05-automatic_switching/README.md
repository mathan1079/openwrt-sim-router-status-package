# Automatic switching

This merged topic owns automatic failover policy, service lifecycle and
persistent automatic-switch audit history.

## Cumulative changed files

- `/etc/init.d/simmanager-auto`
- `/usr/sbin/simmanager-auto`
- `/usr/lib/lua/luci/controller/simmanager.lua`
- `/usr/lib/lua/luci/model/cbi/simmanager/automation.lua`
- `/usr/lib/lua/luci/view/simmanager/automation_history.htm`

The cumulative state implements absolute 6/12/18/24-hour preferred-SIM retry
offsets, bounded failed-attempt backoff, daily disruptive-attempt accounting,
critical rollback propagation, manual-operation deferral, IPv6-aware probes,
procd recovery, persistent reason/evidence records, seven-day retention,
100-record cap, pagination and protected deletion.

## Source stages merged

1. `automatic_switch_reliability_fix`
2. `automatic_switch_history`

The former stage READMEs said these changes were pending at their creation
time. Their final changed files later became byte-identical to the authoritative
`current_first_router` snapshot; that later current state is what this merged
topic preserves.
