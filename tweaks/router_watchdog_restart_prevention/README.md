# Router watchdog restart prevention

## Purpose

This tweak prevents periodic hardware-watchdog resets that occurred even while the router itself was otherwise healthy.

Tested environment:

- Router: ZBT-Z8106AX-2SIM
- OpenWrt: `21.02-SNAPSHOT r0-c400625`
- Vendor watchdog loop: `/usr/sbin/watchdog.sh`
- Hardware feed pulse helper: `/usr/sbin/feed_dog.sh`
- Configuration: `/etc/config/watchdog`

## Archived files

| Copy | Path in this archive | SHA-256 |
| --- | --- | --- |
| Original | `original/etc/config/watchdog` | `d98ee1bef17f2ba31da272516ea672091f0afef38613389479009f5391d72500` |
| Changed | `changed/etc/config/watchdog` | `e79cee178ccc963c04f1f31ef435a1f77c525098efb2b2bff225508ba9fffd73` |

The original was recovered from `/etc/config/watchdog.pre-continuous-feed`. The changed file was copied from the active router configuration on 25 November 2026.

## Root cause

This board has an external hardware watchdog controlled through:

```text
/sys/class/gpio/wdg/value
```

`/usr/sbin/watchdog.sh` reads `watchdog.device.feed_action` once per loop:

- `all` — always run `/usr/sbin/feed_dog.sh`, then sleep for the configured interval.
- `net` — feed only when the configured Internet probes succeed.
- `none` — sleep without feeding the hardware watchdog.

The original configuration used:

```text
option feed_action 'none'
```

After the initial boot grace period, this deliberately stopped sending GPIO feed pulses. The external watchdog therefore interpreted a healthy router as unresponsive and reset the board after its hardware timeout. This produced recurring restarts roughly every several minutes.

## Implemented change

The changed configuration uses:

```text
option feed_action 'all'
```

The running watchdog loop now calls `/usr/sbin/feed_dog.sh` every 60 seconds. That helper toggles the watchdog GPIO repeatedly, proving to the external watchdog that the system is alive.

Only one UCI value changed:

```diff
- option feed_action 'none'
+ option feed_action 'all'
```

## Behavioural scope

This tweak:

- Prevents the external board watchdog from resetting a functioning router.
- Does not disable the watchdog hardware.
- Does not change cellular recovery, SIM switching, APNs, LAN, Wi-Fi or firewall settings.
- Does not mask kernel panics or complete system hangs; if userspace can no longer feed the GPIO, the hardware watchdog can still reset the board.
- Makes feeding independent of Internet reachability. A carrier outage or DNS/ping failure will not reboot the whole router.

## Deployment

Using UCI is preferred because it preserves valid OpenWrt configuration syntax:

```sh
cp -p /etc/config/watchdog \
  /etc/config/watchdog.pre-continuous-feed

uci set watchdog.device.feed_action='all'
uci commit watchdog
```

The vendor loop reads the configuration every cycle, so it adopts the setting within the configured interval (60 seconds). A router reboot is not required.

Alternatively, install the archived changed file:

```sh
cp changed/etc/config/watchdog /etc/config/watchdog
chmod 0775 /etc/config/watchdog
sync
```

## Verification

Confirm the active setting:

```sh
uci -q get watchdog.device.feed_action
uci -q get watchdog.device.interval
```

Expected output:

```text
all
60
```

Confirm the vendor watchdog loop is running:

```sh
ps w | grep '[w]atchdog.sh'
```

Confirm uptime continues beyond the previous restart window:

```sh
uptime
cat /proc/uptime
```

The definitive operational check is that uptime no longer resets after the former five-to-ten-minute interval.

## Rollback

Restoring the original is intentionally documented but normally not recommended because it recreates the periodic reboot condition:

```sh
uci set watchdog.device.feed_action='none'
uci commit watchdog
```

Or restore the exact archived file:

```sh
cp original/etc/config/watchdog /etc/config/watchdog
chmod 0775 /etc/config/watchdog
sync
```

The vendor loop will observe the rollback within the next interval. Once set to `none`, it stops feeding the external watchdog after the boot grace period and the router may reset when the hardware timeout expires.

## Recovery note

If configuration access is lost after rollback, restore `feed_action 'all'` from a local wired session before the external watchdog timeout. Avoid performing rollback through a cellular-only remote connection.
