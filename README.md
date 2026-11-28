# LuCI SIM Manager

A standalone LuCI application for the vendor OpenWrt 21.02 RM500U firmware. Its dashboards are read-only, it stores independent SIM 1/SIM 2 profiles, and all optional switching is isolated behind explicit manual confirmation or a separately enabled guarded failover policy.

## Current features

- Live active-SIM, operator, signal, band, tower and modem information from `/tmp/4ginfo` plus query-only RM500U status reads.
- Separate measured signal and vendor-cache values; invalid vendor percentages derived from `RSRP=0` are explicitly flagged instead of treated as real measurements.
- Current LTE/5G serving bands and channels plus complete modem-supported 3G, LTE, 5G NSA and 5G SA band lists.
- Separate SIM 1 and SIM 2 profiles in `/etc/config/simmanager`.
- APN input is always visible for both SIM profiles; Automatic APN controls activation behavior without hiding the saved manual value.
- Dashboard layout presents modem information full-width above three focused cards for measured signal, tower, and bands/channels.
- Activation page visually marks the currently active SIM and distinguishes reapplying its profile from switching to the inactive SIM.
- Stable identity and network observations are retained per SIM in the independent `simmanager` configuration, allowing inactive cards to show last-known operator, ICCID, APN, bands and a signal snapshot without switching.
- Empty APN and phone-number profile fields are populated from modem observations when those values are available; user-entered values are never overwritten.
- A slot-transition gate suppresses stale operator, ICCID, APN, signal, tower and band values until the newly active SIM has produced a confirmed vendor-status update.
- A detailed, responsive Status → Overview panel shows both SIMs, live network, signal, tower, modem and supported-band information without replacing the vendor 4G/5G panel.
- Separate SIM 1 and SIM 2 dashboard cards; only the active slot is labelled as live because both slots share one modem.
- Profile fields for phone number, APN, PDP type, PIN, authentication, preferred network mode and bands.
- Five-second dashboard refresh with an eight-second query cache on the RM500U secondary AT port.
- Standalone IPK build, install and uninstall targets.
- No vendor files are replaced.
- Explicit, CSRF-protected activation with persistent pre-change backups and automatic rollback on failure.
- Optional automatic failover is disabled by default, runs three interface-bound probes in parallel every five seconds, uses a 20-second failure default, detects reconnect loops, and retries the selected primary SIM after 6, 12, 18 and 24 hours.
- Fast failover is the default: recovery of the failing SIM before switching is optional and disabled because it can extend client downtime by one or more minutes.
- During a failed connectivity check, two consecutive explicit modem replies confirming that the active SIM is not inserted trigger immediate failover without waiting for the normal sustained-outage timer. Unknown AT replies never count as removal. A target slot confirmed empty is retained in controller state and disruptive retries are paused for five minutes; the inactive slot cannot be queried without physically selecting it on this single-modem design.
- Automatic failover cannot be enabled while the vendor `cellular.cellular.hw_asw` controller is active. A vendor `cellular` configuration change immediately reloads this service; if the vendor controller was enabled, package automation cancels further work, rolls back an in-progress automatic activation when necessary, clears its own enable flag and startup entry, and stops.
- Manual activations retain a selectable five-checkpoint rollback history. Older package-created backup directories remain untouched even after they leave the five-entry UI history.
- Automatic operations use a separate private checkpoint captured immediately before each algorithm-driven change. A standby SIM that fails registration or Internet verification restores that exact pre-switch SIM and cellular configuration without consuming or replacing manual rollback points.
- Emergency LAN rollback command: `/usr/sbin/simmanager-control rollback`.
- Active-SIM SMS inbox and sending support using the RM500U secondary AT port, with separate persistent SIM 1/SIM 2 histories.
- SMS menu and per-SIM unread counts, inbox/sent filters, search, read/unread controls, reply, single or bulk deletion, and a 150-message limit per SIM.
- PDU-mode Unicode and multipart sending with requested network delivery reports. Delivery is shown as sent, delivered, failed, or unavailable according to carrier feedback.
- The active SIM is synchronized every ten seconds. Messages are committed locally before their modem copies are removed; inactive SIM histories remain available until that SIM is activated again.
- Dashboard, activation and SMS operations share one modem lock so command responses and interactive SMS prompts cannot overlap.

The collector queries `AT+CNUM`, but this SIM/modem currently returns `CME ERROR: 4`. The dashboard therefore uses a vendor-provided MSISDN if one appears in `/tmp/4ginfo`; otherwise it labels and displays the phone number stored in the active SIM profile.

## Build and verify

```sh
make verify
make build
```

The package is written to `dist/luci-app-simmanager_<version>-<release>_all.ipk`.

## Install and uninstall

These targets default to the SSH host `mathansims-local`:

```sh
make install
make uninstall
```

The install target uses legacy SCP mode (`scp -O`) because this OpenWrt image does not provide an SFTP server.

Installation adds only files owned by this package, including its independent `/etc/config/simmanager` file. Upgrades add a missing automation section in the disabled state without replacing existing profiles. Installation does not start failover, invoke `/etc/init.d/cellular reload`, or change `/etc/config/cellular` or `/etc/config/hw_info`. Modified profile configuration is treated as an opkg conffile and may be retained by opkg after uninstall.

To use another router:

```sh
make install ROUTER=root@192.168.1.1
```

## Vendor integration findings

The active SIM is selected through `cellular.cellular.hw_sim`. The vendor `cellular_sw()` function commits that value, stops the dial script, changes the SIM GPIO through `_hardware_setting reload`, and starts the dial watcher again. A full cellular reload also applies APN/PDP/authentication settings with AT commands before hardware switching and can power-cycle the modem.

Activation is deliberately separate from profile saving. It requires a confirmation in LuCI, creates a persistent backup under `/etc/simmanager/backups`, writes only documented vendor cellular UCI keys, uses the existing vendor switch function and reloads cellular service. A failed switch or registration attempts automatic rollback. Manual band application remains blocked; only automatic band selection is allowed in the initial activation implementation.

The activation implementation must be reviewed and installed separately before use. A router test must not be run without explicit approval because it changes runtime cellular configuration and interrupts mobile connectivity.

## Source layout

- `luci-app-simmanager/luasrc` - LuCI controller, dashboards, profile editor and automatic-switching policy page.
- `luci-app-simmanager/root` - package-owned UCI defaults, status collectors and guarded switching services.
- `scripts/build-ipk.sh` - standalone architecture-independent IPK builder using the gzip-compressed tar format accepted by this OpenWrt 21.02 `opkg` build.
- `scripts/verify.sh` - non-invasive source/package checks.

