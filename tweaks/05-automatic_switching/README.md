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

The automatic controller also distinguishes physical SIM removal from an
ordinary Internet outage. Two consecutive explicit `AT+CPIN?` absence replies
trigger immediate emergency failover, while unknown replies are ignored. A
target slot confirmed empty is persisted with a five-minute retry backoff so
the five-second monitor cannot repeatedly switch toward an empty slot. Because
the router uses one modem with a two-slot hardware mux, the inactive slot can
only be confirmed after selecting it.

The Dashboard, Activate / Roll Back page and Automatic Switching page show
per-slot card detection as last-checked evidence, including an explicit unknown
state. The automation page explains removal protection when enabled and the
absence of automatic failover when disabled. Empty-slot activation messages
remain visible through the existing activation-status polling.

## Source stages merged

1. `automatic_switch_reliability_fix`
2. `automatic_switch_history`

The former stage READMEs said these changes were pending at their creation
time. Their final changed files later became byte-identical to the authoritative
`current_first_router` snapshot; that later current state is what this merged
topic preserves.
