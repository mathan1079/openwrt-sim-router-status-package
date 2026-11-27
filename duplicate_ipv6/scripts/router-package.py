#!/usr/bin/env python3
"""Detect the router package manager before building/copying any artifact."""
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'luci-app-ipv6-cleaner'

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ('install', 'uninstall'):
        raise SystemExit('Usage: router-package.py {install|uninstall}')
    router = os.environ.get('ROUTER', 'mathancbe-er605-local')
    if not router or router.startswith('-'):
        raise SystemExit('ROUTER must be an SSH alias or user@host')
    detect = 'if command -v apk >/dev/null 2>&1; then echo apk; elif command -v opkg >/dev/null 2>&1; then echo opkg; else echo "No supported package manager" >&2; exit 1; fi'
    manager = subprocess.check_output(['ssh', router, detect], text=True).strip()
    if manager not in ('apk', 'opkg'):
        raise SystemExit('Could not detect router package manager: ' + manager)
    print('Router package manager: ' + manager, flush=True)
    if sys.argv[1] == 'uninstall':
        subprocess.run(['ssh', router, manager + (' del ' if manager == 'apk' else ' remove ') + PACKAGE], check=True)
        return
    env = dict(os.environ, FORMAT='apk' if manager == 'apk' else 'ipk')
    subprocess.run([str(ROOT / 'scripts/build.sh')], cwd=ROOT, env=env, check=True)
    version = os.environ.get('VERSION', '1.0.0')
    release = os.environ.get('RELEASE', '14')
    name = (f'{PACKAGE}-{version}-r{release}.apk' if manager == 'apk'
        else f'{PACKAGE}_{version}-{release}_all.ipk')
    remote = '/tmp/' + name
    subprocess.run(['scp'] + shlex.split(os.environ.get('SCP_FLAGS', '-O')) +
        [str(ROOT / 'dist' / name), router + ':' + remote], check=True)
    if manager == 'apk':
        flags = ' --allow-untrusted' if os.environ.get('APK_ALLOW_UNTRUSTED', '1') == '1' else ''
        command = 'apk add' + flags + ' ' + shlex.quote(remote)
    else:
        command = 'opkg install ' + shlex.quote(remote)
    subprocess.run(['ssh', router, command], check=True)

if __name__ == '__main__':
    main()
