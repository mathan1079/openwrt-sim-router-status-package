#!/usr/bin/env python3
"""Build an architecture-independent opkg package using Python's standard library."""
import io
import os
from pathlib import Path
import re
import tarfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'luci-app-ipv6-cleaner'
version = os.environ.get('VERSION', '1.0.0')
release = os.environ.get('RELEASE', '4')
for value in (version, release):
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+~]*', value):
        raise SystemExit('VERSION and RELEASE must start with a digit and contain only letters, digits, . + ~')


def archive(entries):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w:gz', format=tarfile.USTAR_FORMAT) as tar:
        directories = set()
        for name, _, _ in entries:
            parent = Path(name).parent
            while parent.as_posix() != '.':
                directories.add(parent.as_posix())
                parent = parent.parent
        for name in sorted(directories, key=lambda value: (value.count('/'), value)):
            info = tarfile.TarInfo('./' + name + '/')
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.uid = info.gid = 0
            info.uname = info.gname = 'root'
            info.mtime = 0
            tar.addfile(info)
        for name, content, mode in entries:
            info = tarfile.TarInfo('./' + name)
            info.size = len(content)
            info.mode = mode
            info.uid = info.gid = 0
            info.uname = info.gname = 'root'
            info.mtime = 0
            tar.addfile(info, io.BytesIO(content))
    return stream.getvalue()


payload = []
for base, prefix in [('root', ''), ('htdocs', 'www/')]:
    for file in sorted((ROOT / base).rglob('*')):
        if file.is_file():
            payload.append((prefix + file.relative_to(ROOT / base).as_posix(),
                file.read_bytes(), file.stat().st_mode & 0o777))
size = sum(len(content) for _, content, _ in payload)
control = f"""Package: {PACKAGE}
Version: {version}-{release}
Architecture: all
Maintainer: luci-app-ipv6-cleaner contributors
Section: luci
Priority: optional
License: MIT
Depends: luci-base, rpcd, ip-full, jshn, flock
Installed-Size: {size}
Description: Automatic deprecated public IPv6 cleaner with LuCI controls
"""
postinst = """#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
/etc/init.d/ipv6-cleaner enable
/etc/init.d/ipv6-cleaner restart
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd restart
"""
prerm = """#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
/etc/init.d/ipv6-cleaner stop
/etc/init.d/ipv6-cleaner disable
exit 0
"""
postrm = """#!/bin/sh
[ -n "$IPKG_INSTROOT" ] && exit 0
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache
/etc/init.d/rpcd restart
"""
metadata = [('control', control.encode(), 0o644),
    ('conffiles', b'/etc/config/ipv6_cleaner\n', 0o644),
    ('postinst', postinst.encode(), 0o755),
    ('prerm', prerm.encode(), 0o755), ('postrm', postrm.encode(), 0o755)]
def build():
    # Match OpenWrt scripts/ipkg-build: gzip-compressed tar outer container.
    # Older opkg builds reject GNU ar member names with trailing slashes.
    output = archive([('debian-binary', b'2.0\n', 0o644),
        ('data.tar.gz', archive(payload), 0o644),
        ('control.tar.gz', archive(metadata), 0o644)])
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    path = dist / f'{PACKAGE}_{version}-{release}_all.ipk'
    temp = path.with_suffix('.ipk.tmp')
    temp.write_bytes(output)
    temp.replace(path)
    print(path)


if __name__ == "__main__":
    build()
