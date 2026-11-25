# SIM-switch network isolation fix

## Purpose

This second-stage tweak prevents a physical SIM change from restarting the
complete OpenWrt network and Wi-Fi stack. It also prevents concurrent vendor
detector and RM500U worker processes from repeatedly flapping the modem-facing
`lan5` link.

The first RM500U-only guard exposed a second vendor path. During the controlled
test on 25 November 2026, `cellular_Prepare` wrote `usb0`, reloaded all network
interfaces, and the RM500U worker then corrected the interface back to `lan5`
with another reload. Both `ra0` and `rax0` left `br-lan` temporarily.

## Archived live files

The `original/` files were copied from the router before this tweak was edited
or deployed. The RM500U original already contains the earlier atomic status
JSON fix and first-stage network guard.

| Router path | Original SHA-256 | Changed SHA-256 |
| --- | --- | --- |
| `/usr/sbin/cellular/cellular_Prepare` | `8673828af4d3db599536974d842ba29834f86b8a5d22ea76b4452a9761502da6` | `2989ce2cbb4d80b878b8e84970a573a5c7451ae41cb56101f1e1f634d481721e` |
| `/usr/sbin/cellular/cellular_detect` | `1069fed330bbd5013ef7aaa9fe88ce00583cd5fa113229510a38cb5f9515f812` | `d4065fcf4534e5c5bf87abe2340d1091ee1df10ed8108b50061dbbf952fa966a` |
| `/usr/sbin/cellular/quectel_rm500u` | `f039009d59a6c7e28f8d8bb303d4247375e67bf163e7e83f027bfc3079277af5` | `5c48dfa08ccf3a4ccac7243f3998de2905ab04d147b0bcac1f49b4fba6bebb17` |

## Confirmed root causes

### Wrong interface passed by `cellular_Prepare`

For this board, `phy=1` means the modem data path is the Ethernet-facing
interface `lan5`. The vendor script correctly assigned `ifname=lan5` but later
passed `_ifname=usb0` to `network_config`. That temporarily changed
`network.cellular.ifname` to `usb0`.

### Global network reload

Both preparation and RM500U startup could execute:

```sh
/etc/init.d/network reload
```

On this firmware that command also runs `wifi reload_legacy`, disconnecting
`ra0` and `rax0` from `br-lan` even though only cellular changed.

### Overlapping processes

The vendor `watchsystem` helper can start more than one detector. Repeated
detection produced multiple RM500U workers using different transient AT ports,
which repeatedly took `lan5` down and up.

## Implemented changes

### `cellular_Prepare`

- Uses a per-modem preparation lock before loading the vendor library, so only
  one preparation can configure or reactivate the modem at a time.
- Uses `lan5` as the network interface whenever `phy=1`.
- Exits before configuration or modem reactivation when a later detector finds
  that the modem's RM500U worker is already active.
- Compares both the configured script and interface.
- Calls `network_config` only when either value actually differs.
- Applies a necessary change with `ifdown cellular` and `ifup cellular` only.
- Never calls the global network reload.

### `quectel_rm500u`

- Retains the physical-interface correction as a safety fallback.
- Applies that correction with cellular-only `ifdown`/`ifup`.
- Never calls the global network reload.
- Uses a per-modem PID lock so a second RM500U worker exits instead of running
  concurrently.
- Acquires the lock before loading either vendor library, so duplicate worker
  shells exit immediately.

### `cellular_detect`

- Replaces the unreliable `ps | grep` count with an atomic directory/PID lock.
- Acquires the lock before loading the vendor function library.
- Removes a stale lock only when its recorded process is no longer the vendor
  detector.
- Logs and exits when another detector is already active.

Diagnostic messages use the `simmanager-cellular-guard` log tag.

## Behaviour intentionally retained

- Physical SIM GPIO selection and modem re-enumeration
- Temporary cellular Internet loss while one modem changes SIM
- APN, PDP, registration and profile application
- SIM Manager backup, automatic rollback and automatic-switching policy
- Modem-facing `lan5` link transitions required by the hardware

The objective is to keep client-facing `br-lan`, wired LAN ports and Wi-Fi
running while cellular alone recovers.

## Deployment

Verify all live hashes match the archived originals. Create router-side
rollback copies before replacement:

```sh
cp -p /usr/sbin/cellular/cellular_Prepare \
  /usr/sbin/cellular/cellular_Prepare.pre-network-isolation
cp -p /usr/sbin/cellular/cellular_detect \
  /usr/sbin/cellular/cellular_detect.pre-network-isolation
cp -p /usr/sbin/cellular/quectel_rm500u \
  /usr/sbin/cellular/quectel_rm500u.pre-network-isolation
```

Copy the changed files, restore executable permissions, validate syntax and
sync storage. Replacing files alone does not restart any service.

## Controlled test

After deployment, perform one intentional SIM switch while capturing logs.
Success requires all of the following:

1. No `/etc/init.d/network reload` effect and no Wi-Fi driver reload.
2. No `ra0` or `rax0` disabled event under `br-lan`.
3. `network.cellular.ifname` remains `lan5`; it never becomes `usb0`.
4. At most one RM500U worker remains after recovery.
5. Cellular obtains an address and reports `up=true`.
6. The selected SIM is reported by `cellular.cellular.hw_sim`.

Expected guard messages include:

```text
Kept cellular on lan5; no network reconfiguration was required.
Kept cellular.ifname on lan5; full network reload was not required.
Skipped duplicate cellular detector start ...
Skipped duplicate RM500U worker ...
```

## Rollback

Restore all three router-side backups and permissions, then sync. The restored
scripts take effect on the next vendor cellular lifecycle. Rolling back restores
the known global network/Wi-Fi reload risk.

```sh
cp /usr/sbin/cellular/cellular_Prepare.pre-network-isolation \
  /usr/sbin/cellular/cellular_Prepare
cp /usr/sbin/cellular/cellular_detect.pre-network-isolation \
  /usr/sbin/cellular/cellular_detect
cp /usr/sbin/cellular/quectel_rm500u.pre-network-isolation \
  /usr/sbin/cellular/quectel_rm500u
chmod 0755 /usr/sbin/cellular/cellular_Prepare \
  /usr/sbin/cellular/cellular_detect \
  /usr/sbin/cellular/quectel_rm500u
sync
```

## Deployment and test record

Deployed on 25 November 2026. The router-side rollback copies were created
before replacement and their hashes matched the archived originals.

A controlled SIM1-to-SIM2 activation was run through `simmanager-control`.
The first pass reached SIM2 without any client-network reload. A sequential
second detector was then observed reactivating the modem before its duplicate
worker was rejected. The early preparation guard was added from that evidence,
redeployed, and a final SIM2-to-SIM1 validation was performed.

After clearing all in-flight pre-lock test processes, one clean lifecycle was
started with the final files. The completed final result was:

- SIM Manager state: `success`
- Active SIM: `sim2`
- Cellular interface: `lan5`
- Cellular state: up, with DHCP address `100.77.212.80`
- Persistent RM500U workers after recovery: one (`PID 24141` during validation)
- `network.cellular.ifname` changes to `usb0`: zero
- `br-lan` Wi-Fi-port disabled events during the test: zero
- Client-facing `lan1` through `lan4` link-down events during the test: zero
- `mtwifi called!` reload events during the test: zero

The modem-facing `lan5` link went down and up as expected during physical SIM
selection and modem recovery. This is cellular interruption, not a client LAN
or Wi-Fi restart.

## Firmware note

These are vendor-owned, hardware-specific scripts. A firmware update may
replace them. Compare a newer vendor implementation before reapplying this
tweak; never overwrite a newer script solely because its checksum differs.
