# OPKG feed cleanup

## Status

Active on the first router from 26 November 2026.

## Cause

`/etc/opkg/distfeeds.conf` contained two mixed feed sets. The obsolete
`21.02-SNAPSHOT` URLs no longer exist, the vendor-only
`mtk_openwrt_feed` URL returned HTTP 404, and five feed names were declared
twice. The first `openwrt_core` entry also duplicated the generic `packages`
feed rather than pointing to a valid target repository.

## Change

- Removed the obsolete `21.02-SNAPSHOT` block.
- Removed the invalid `mtk_openwrt_feed` source.
- Removed the incorrectly labelled duplicate `openwrt_core` source.
- Retained one each of the official OpenWrt 21.02.2 `base`, `luci`,
  `packages`, `routing` and `telephony` user-space feeds.
- Removed only the orphaned `/var/opkg-lists/openwrt_core*` and
  `openwrt_mtk_openwrt_feed*` cache files left by deleted feeds.
- Did not install, remove or upgrade any package.

This only controls future package-list refreshes and package selection. Kernel,
MediaTek, bootloader and vendor packages must not be installed from these
standard feeds, and `opkg upgrade` must not be used on this firmware.

## Checksums

- Original: `4955539044dedd2454b660d4175dc11644e40b788e22c9188da7268d5ead6401`
- Changed: `ca5e0f7503aacdc696743becb394a5d2076e6cc9a61e22edfc3d4c70ae1fffc8`

## Deployment

Back up the live file under `/root/`, copy the reviewed changed file to
`/etc/opkg/distfeeds.conf` with mode `0644`, then run only `opkg update`.
No service, network interface, modem or router restart is required.

The live pre-change backup is
`/root/opkg-feed-cleanup-backup-20261126-1116/`.

## Verification

- The live checksum equals the changed checksum above.
- `opkg update` downloads all five indexes without duplicate declarations or
  failed snapshot/vendor-feed downloads.
- `/var/opkg-lists` contains indexes only for the five configured feeds.
- The router uptime and cellular interface remain unchanged.

Deployment verification confirmed all five indexes downloaded with valid
signatures, no OPKG errors, the live checksum matched, cellular uptime
continued, and IPv4 connectivity remained available.

## Rollback

Restore the preserved live backup or copy `original/etc/opkg/distfeeds.conf`
back to `/etc/opkg/distfeeds.conf`. The original file intentionally restores
the broken and duplicate feeds for historical reproducibility.
