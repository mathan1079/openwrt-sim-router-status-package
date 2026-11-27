# luci-app-ipv6-cleaner

Architecture-independent OpenWrt package with a **Network → IPv6 Cleaner** LuCI page.
Uses modern JavaScript LuCI with a legacy Lua/CBI fallback for vendor firmware without view.js, plus rpcd, procd, UCI, POSIX shell and iproute2; no compiled application code. Intended for OpenWrt 23.05/24.10 and newer modern LuCI installations; these release targets require SDK/device validation. No existing project files were read or changed: the requested `duplicate_ipv6` folder was initially absent, so no project-specific release convention could be established.

## Behavior

- Defaults: scheduling disabled, monitor only, 120-second interval.
- Discovers addresses on every kernel IPv6 device each scan, supporting multiple WANs, PPP, bridges, VLANs and tunnels without hard-coded interface names. This includes LAN devices; it is not restricted to WAN roles.
- Requires `scope global`, public unicast range `2000::/3`, and an explicit `deprecated` flag. Excludes ULA, link-local, tentative and DAD-failed addresses. It does not infer deprecation from lifetime values or remove duplicate addresses merely because they match.
- Removal is optional. Each candidate is rechecked immediately before deletion. A small kernel check/delete race remains possible. Existing connections using a removed address can be interrupted.
- Manual runs follow the **saved** mode, even if scheduling is off. Save & Apply before running a new mode.
- Uses an exclusive kernel file lock to prevent overlapping scans. Removal failures are counted and shown in LuCI; successful removals are logged with the `ipv6-cleaner` tag.
- A procd-managed scheduler waits the configured interval after start and after each completed scheduled scan. Apply restarts the schedule; a manual scan does not reset it. Custom intervals: 60–86400 seconds. No cron modification.
- Shows scheduler status, last scan, last successful address removal, next scheduled scan/clearing attempt, counts and per-device results from the last scan. It cannot promise that an address will be cleared at the next scan.
- Runtime state stays in `/var/run/ipv6-cleaner`, avoiding periodic flash writes; history resets on reboot. UCI settings persist.

## Local build and router installation

```sh
make build     # builds both IPK and APK locally
make install   # detects opkg or apk on the default router and installs matching package
make verify
make uninstall
make clean
```

Default router: `mathancbe-er605-local`, set near the top of the Makefile. To target another router: `make install ROUTER=your-router`. No FORMAT argument is needed. Installation builds the detected format automatically; plain builds never contact the router.

Current outputs: `dist/luci-app-ipv6-cleaner_1.0.0-10_all.ipk` and `dist/luci-app-ipv6-cleaner-1.0.0-r10.apk`. This release increments the package revision so installed copies receive the updated UI.

Build requirements: make, Python 3, native apk-tools 3 with `mkpkg`, and fakeroot for non-root builds. Both formats build locally without Docker. APK metadata uses `noarch`; IPK uses `all`. If apk is outside PATH, APK_TOOL can point to its executable. The default scp flags are `-O`.

Local APKs are unsigned. Installation uses `apk add --allow-untrusted` only for the explicitly copied local file, without changing router trust settings. Both formats include configuration preservation metadata and service lifecycle hooks. Dependencies come from the router's configured feeds.

## Build in an OpenWrt SDK / source tree

Place this directory at `package/luci-app-ipv6-cleaner` in the SDK. When `TOPDIR` is set by the SDK, the Makefile uses the standard LuCI build rules, retaining `LUCI_PKGARCH:=all`.

```sh
./scripts/feeds update luci
./scripts/feeds install luci-base
make menuconfig
# Select LuCI -> Applications -> luci-app-ipv6-cleaner
make package/luci-app-ipv6-cleaner/compile V=s
```

Use an SDK matching the router release; the SDK selects its native IPK or APK package format. Dependencies are `luci-base`, `rpcd`, `ip-full`, `jshn`, and `flock`.

## Validation

Run `python3 tests/test_package.py` from this directory. Tests exercise address eligibility, multiple devices and the actual worker using mocked OpenWrt commands, including monitor mode, removal mode, renewed addresses and deletion failure. They also check shell/JavaScript syntax (when Node is available), JSON permissions/menu files and package metadata.

A real SDK build and router smoke test are required before production use: install, verify the menu, exercise Save & Apply, inspect `ubus call ipv6-cleaner status`, verify service restart/disable, and observe a scheduled scan. Do removal tests only with disposable test addresses and an alternative management path.

Implementation references: [LuCI example structure](https://github.com/openwrt/luci/tree/master/applications/luci-app-example), [LuCI build rules](https://github.com/openwrt/luci/blob/master/luci.mk).

## Unreachable IPv6: restart only its IPv6 interface

Enable **Check for stale ISP addresses** and choose Remove mode. A separate watcher checks source/device-bound connectivity independently of the deprecated cleanup interval. When one preferred public /64 address with infinite lifetimes repeatedly fails both targets across at least three rounds and 30 seconds, while another address on that device reaches both, the cleaner restarts only the uniquely owning logical DHCPv6 interface (for example `wan2_6`). It does not delete the preferred address with `ip addr del`, rewrite netifd state, restart the parent IPv4 interface, or restart other WANs.

The target is roughly one minute for two addresses; probe timeouts or more addresses can extend it. Each logical IPv6 interface has a 60-second restart cooldown. All checks are repeated before restarting. Monitor mode reports only. curl 8.9+ is required for automatic action, to bind both source and device. If the upstream continues to advertise an old prefix, a restart may receive it again; no prefix blacklists or network configuration rewrites are applied.

The existing explicit-deprecated-address cleanup remains controlled by the normal scan interval. LuCI shows the last IPv6-only restart separately from the last address deletion.
