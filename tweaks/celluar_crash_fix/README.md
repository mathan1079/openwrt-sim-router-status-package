# Cellular status page crash fix

> Status: active but incorporated into the cumulative RM500U worker. The
> standalone `changed/` worker in this folder is a historical stage and must
> not replace the current worker.

## Purpose

This tweak fixes intermittent failures of the vendor Cellular/LuCI status page caused by invalid or partially-written `/tmp/4ginfo` JSON.

Tested environment:

- Router: ZBT-Z8106AX-2SIM
- Modem: Quectel RM500U-EA
- OpenWrt: `21.02-SNAPSHOT r0-c400625`
- Vendor status producer: `/usr/sbin/cellular/quectel_rm500u`
- Status cache: `/tmp/4ginfo`

## Archived files

| Copy | Path in this archive | SHA-256 |
| --- | --- | --- |
| Original | `original/usr/sbin/cellular/quectel_rm500u` | `9cde83908e9b5ba0c80078f8864b47eea65b2b8517b560317ff65739bf5dabff` |
| Changed | `changed/usr/sbin/cellular/quectel_rm500u` | `c9dcc49d19cf4cdfd8f2f786ce954ef21109368752b3f99ff36c445f6c5f1cd2` |

The original was recovered from the router's `/usr/sbin/cellular/quectel_rm500u.bak`. The changed file was copied from the active router path on 25 November 2026.

## Root cause

The original status loop rebuilt `/tmp/4ginfo` every eight seconds using a shell heredoc:

```sh
cat > /tmp/4ginfo${option} <<EOF
{
"device_model":"${vendor} ${_model}",
...
}
EOF
```

This had two independent failure modes:

1. **Non-atomic replacement** — `cat > /tmp/4ginfo` truncates the live file before rewriting it. A LuCI request reading during that window can receive an empty or incomplete document.
2. **Unescaped modem values** — raw AT-command output was inserted directly into JSON. Quotes, backslashes, control characters or embedded newlines could produce syntactically invalid JSON. `currband` and `nwscanmode` were particularly exposed.

When LuCI or another consumer decoded the malformed cache, the Cellular page could fail or show an error until a later loop happened to write valid content.

## Implemented change

The changed script:

- Uses OpenWrt's `/usr/share/libubox/jshn.sh` JSON builder.
- Adds each value with `json_add_string`, which performs JSON escaping.
- Flattens newlines in `currband`.
- Removes embedded quote characters from `nwscanmode` before storage.
- Writes the complete document to `/tmp/4ginfo.new`.
- Atomically replaces `/tmp/4ginfo` with `mv -f` only after `json_dump` succeeds.
- Calls `json_cleanup` after every status cycle.

The atomic rename guarantees that readers see either the previous complete document or the new complete document, never an in-progress write.

## Behavioural scope

This tweak changes only status-cache serialization. It does not intentionally change:

- SIM selection
- APN configuration
- registration or dialing
- cellular recovery logic
- modem firmware
- network interfaces
- watchdog behaviour

## Deployment

Apply during a maintenance window because restarting the vendor cellular process may briefly interrupt mobile Internet.

```sh
cp -p /usr/sbin/cellular/quectel_rm500u \
  /usr/sbin/cellular/quectel_rm500u.pre-status-json-fix

cp changed/usr/sbin/cellular/quectel_rm500u \
  /usr/sbin/cellular/quectel_rm500u
chmod 0755 /usr/sbin/cellular/quectel_rm500u
sync
```

The running shell process may still hold the old script inode. Restart the cellular service or reboot at a controlled time so the changed script is loaded:

```sh
/etc/init.d/cellular reload
```

That command interrupts cellular connectivity and may reload vendor modem handling. It must not be run over an unprotected cellular-only management session.

## Verification

Confirm the installed checksum:

```sh
sha256sum /usr/sbin/cellular/quectel_rm500u
```

Historical stage checksum (not the current cumulative worker):

```text
c9dcc49d19cf4cdfd8f2f786ce954ef21109368752b3f99ff36c445f6c5f1cd2
```

Confirm the atomic write logic is present:

```sh
grep -n 'json_dump\|4ginfo.*new\|mv -f' \
  /usr/sbin/cellular/quectel_rm500u
```

Validate the generated cache repeatedly while the producer is updating it:

```sh
for i in $(seq 1 30); do
  jsonfilter -i /tmp/4ginfo -e '@.device_model' >/dev/null || {
    echo "invalid JSON on iteration $i"
    break
  }
  sleep 1
done
```

Success means all iterations parse without an empty, truncated or malformed document.

## Rollback

```sh
cp original/usr/sbin/cellular/quectel_rm500u \
  /usr/sbin/cellular/quectel_rm500u
chmod 0755 /usr/sbin/cellular/quectel_rm500u
sync

/etc/init.d/cellular reload
```

Rollback restores the known original behaviour, including its non-atomic JSON write risk.

## Firmware-update note

This is a vendor file. A firmware upgrade may replace it. After any upgrade, compare the new vendor script before reapplying this patch; do not overwrite a newer script solely because its checksum differs.
