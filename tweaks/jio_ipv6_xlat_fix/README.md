# Jio IPv6 and 464XLAT permanent fix

## Problem

Jio can register the RM500U on 5G SA and provide only a native IPv6 PDP address. The router's IPv4 DHCP interface may appear up, but IPv4 destinations fail unless the modem's built-in CLAT is fully configured. The previous registration check also looked only at LTE `CEREG`, incorrectly treating a valid 5G SA `C5GREG` registration as offline.

## Permanent behavior

- Detect Jio primarily from IMSI/MCC-MNC `405869` and secondarily from the operator response.
- Fall back to the same recovery when an active PDP contains IPv6 but no IPv4 address.
- Save `jionet`, `IPV4V6` and `AUTO` in both the vendor configuration and the active SIM profile.
- Enable RM500U NAT router mode and the complete CLAT profile using `ipv4only.arpa.` NAT64 discovery.
- Restart the modem exactly once when entering a Jio/IPv6-only SIM, even when
  NAT was already enabled by the previous SIM. The ICCID-specific marker is
  written before restart to prevent a restart loop.
- Accept either LTE `CEREG` or 5G SA `C5GREG` registration.
- Leave standard dual-stack SIMs unchanged.

## Files

- `/usr/sbin/simmanager-jio-ensure`: idempotent carrier/IPv6-only detection and RM500U configuration.
- `/usr/sbin/cellular/quectel_rm500u`: invokes the helper before the normal data call.
- `/usr/sbin/simmanager-control`: recognizes 5G SA registration.

The exact integration delta is archived in `change.patch`. The pre-change
vendor worker is already archived under
`tweaks/sim_switch_network_isolation_fix/changed/`, and the pre-change
controller is archived under `tweaks/sim_switch_timing_fix/original/`.

## Verified working settings

- `AT+QCFG="nat",1`
- full `AT+QCFG="CLAT",..."ipv4only.arpa."...` profile
- APN `jionet`
- PDP `IPV4V6`
- network mode `AUTO`

On 25 November 2026, these settings produced native Jio IPv6, an OpenWrt address of `192.168.42.3`, and successful IPv4 traffic to `1.1.1.1` through XLAT.

## 25 November follow-up correction

Switching from Airtel left NAT enabled, so the first helper version did not
restart the modem after changing the CLAT context. Jio registered and supplied
IPv6, but IPv4 translation did not activate. Marker format `v2` now forces one
activation restart whenever the router enters a Jio/IPv6-only SIM, regardless
of the prior NAT value.

## Safety

The helper is idempotent and uses a per-modem state marker. It does not restart the router, reload the full network, or modify the downstream router.
