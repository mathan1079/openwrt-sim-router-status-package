# LuCI SIM Manager

A standalone LuCI application for the vendor OpenWrt 21.02 RM500U firmware. It provides a live dashboard and independent SIM 1/SIM 2 profile storage, but it does not switch SIMs, apply APNs, restart the modem, or edit the vendor `cellular` configuration.

## Current features

- Live active-SIM, operator, signal, band, tower and modem information from `/tmp/4ginfo` plus query-only RM500U status reads.
- Separate SIM 1 and SIM 2 profiles in `/etc/config/simmanager`.
- Separate SIM 1 and SIM 2 dashboard cards; only the active slot is labelled as live because both slots share one modem.
- Profile fields for phone number, APN, PDP type, PIN, authentication, preferred network mode and bands.
- Five-second dashboard refresh with an eight-second query cache on the RM500U secondary AT port.
- Standalone IPK build, install and uninstall targets.
- No vendor files are replaced.

The collector queries `AT+CNUM`, but this SIM/modem currently returns `CME ERROR: 4`. The dashboard therefore uses a vendor-provided MSISDN if one appears in `/tmp/4ginfo`; otherwise it labels and displays the phone number stored in the active SIM profile.

## Build and verify

```sh
make verify
make build
```

The package is written to `dist/luci-app-simmanager_1.0.0-1_all.ipk`.

## Install and uninstall

These targets default to the SSH host `mathansims-local`:

```sh
make install
make uninstall
```

The install target uses legacy SCP mode (`scp -O`) because this OpenWrt image does not provide an SFTP server.

Installation adds only files owned by this package, including its independent `/etc/config/simmanager` file. It does not invoke `/etc/init.d/cellular reload` and does not change `/etc/config/cellular` or `/etc/config/hw_info`. Modified profile configuration is treated as an opkg conffile and may be retained by opkg after uninstall.

To use another router:

```sh
make install ROUTER=root@192.168.1.1
```

## Vendor integration findings

The active SIM is selected through `cellular.cellular.hw_sim`. The vendor `cellular_sw()` function commits that value, stops the dial script, changes the SIM GPIO through `_hardware_setting reload`, and starts the dial watcher again. A full cellular reload also applies APN/PDP/authentication settings with AT commands before hardware switching and can power-cycle the modem.

For that reason, this release contains no activation action. Adding activation requires a controlled router test and explicit approval because it will interrupt cellular connectivity and write runtime vendor configuration.

## Source layout

- `luci-app-simmanager/luasrc` - LuCI controller, dashboard and CBI profile editor.
- `luci-app-simmanager/root` - package-owned UCI defaults and ACL metadata.
- `scripts/build-ipk.sh` - standalone architecture-independent IPK builder using the gzip-compressed tar format accepted by this OpenWrt 21.02 `opkg` build.
- `scripts/verify.sh` - non-invasive source/package checks.

