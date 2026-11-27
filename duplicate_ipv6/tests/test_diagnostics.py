#!/usr/bin/env python3
"""Exercise the WAN address count and restart policy with isolated fixtures."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
OLD = '2409:40f4:201b:a894::1/64'
NEW = '2401:4900:cd3d:59bf::1/64'

class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.run = self.root / 'state'
        self.script = self.root / 'diagnostics'
        self.script.write_text((ROOT / 'root/usr/libexec/ipv6-cleaner-diagnostics').read_text().replace('/var/run/ipv6-cleaner', str(self.run)).replace('/usr/libexec/ipv6-cleaner-restart', str(self.bin / 'restart-ipv6')))
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
            MOCK_MODE='stale', MOCK_TIME='1000', MOCK_DATA=str(self.root / 'addresses'),
            MOCK_DELETE=str(self.root / 'kernel-deleted'), MOCK_RESTART=str(self.root / 'restarted'))
        data = ''.join('4: lan2 inet6 ' + addr + ' scope global noprefixroute valid_lft forever preferred_lft forever\n'
            for addr in [OLD, NEW, 'fd10:1234::1/64', 'fe80::1/64'])
        (self.root / 'addresses').write_text(data.replace(OLD + ' scope global noprefixroute valid_lft forever preferred_lft forever', OLD + ' scope global dynamic noprefixroute valid_lft 900sec preferred_lft 800sec'))
        self.command('restart-ipv6', '#!/bin/sh\nprintf \'%s %s\\n\' "$1" "$2" >> "$MOCK_RESTART"\n')
        self.command('flock', '#!/bin/sh\nexit 0\n')
        self.command('logger', '#!/bin/sh\nexit 0\n')
        self.command('uci', '#!/bin/sh\ncase "$*" in *enabled) echo "${MOCK_ENABLED:-1}";; *stale_detection) echo 1;; *mode) echo "${MOCK_ACTION:-remove}";; esac\n')
        self.command('date', '#!/bin/sh\necho "$MOCK_TIME"\n')
        self.command('ip', """#!/bin/sh
case "$*" in
 *"addr del"*) echo "$*" >> "$MOCK_DELETE"; exit 0;;
 *"route get"*) echo ":: via fe80::1 dev ${MOCK_ROUTE:-lan2}";;
 *"route show"*) echo 'default via fe80::1 dev lan2';;
 *) cat "$MOCK_DATA";;
esac
""")
    def command(self, name, content):
        file = self.bin / name
        file.write_text(content)
        file.chmod(0o755)

    def invoke(self, mode='auto', **env):
        subprocess.run(['sh', str(self.script), mode], env=dict(self.env, **env),
            text=True, capture_output=True, check=True)

    def test_two_public_addresses_restart_once(self):
        self.invoke()
        self.assertEqual((self.root / 'restarted').read_text().splitlines(),
            ['lan2 ' + NEW])
        self.assertFalse((self.root / 'kernel-deleted').exists())

    def test_monitor_or_manual_check_does_not_restart(self):
        self.invoke(MOCK_ACTION='monitor')
        self.invoke('run')
        self.assertFalse((self.root / 'restarted').exists())

    def test_one_public_address_does_not_restart(self):
        data = self.root / 'addresses'
        data.write_text(''.join(line for line in data.read_text().splitlines(keepends=True)
            if OLD not in line))
        self.invoke()
        self.assertFalse((self.root / 'restarted').exists())
