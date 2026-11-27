# Carrier profiles and Jio

This merged topic owns SIM profile network modes and Jio IPv6-only/464XLAT
preparation.

## Cumulative changed files

- `/etc/config/cellular`
- `/etc/config/simmanager`
- `/usr/lib/lua/luci/model/cbi/simmanager/profiles.lua`
- `/usr/sbin/simmanager-jio-ensure`

The cumulative implementation supports LTE, 5G SA and 5G NSA multi-selection,
correct LuCI 21.02 checkbox state, Jio IMSI/operator detection, persistent
per-ICCID preparation, NAT and CLAT configuration, and guarded restart
suppression when a prepared Jio SIM returns.

## Source stages merged

1. `jio_ipv6_xlat_fix`
2. `jio_return_fast_path`
3. `lte_nr_only_network_mode`
4. `network_mode_checkbox_state_fix`

The central original tree records that `simmanager-jio-ensure` was introduced
by this topic.
