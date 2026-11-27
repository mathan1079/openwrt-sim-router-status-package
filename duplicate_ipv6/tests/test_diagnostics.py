#!/usr/bin/env python3
"""Exercise the real diagnostic shell and removal guards with isolated fixtures."""
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
            MOCK_DELETE=str(self.root / 'kernel-deleted'), MOCK_RESTART=str(self.root / 'restarted'), MOCK_CURL_LOG=str(self.root / 'probes'))
        data = ''.join('4: lan2 inet6 ' + addr + ' scope global noprefixroute valid_lft forever preferred_lft forever\n'
            for addr in [OLD, NEW, 'fd10:1234::1/64', 'fe80::1/64'])
        (self.root / 'addresses').write_text(data)
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
        self.command('curl', """#!/usr/bin/env python3
import os,sys
args=sys.argv[1:]
if args==['--version']:
 print('curl '+os.environ.get('MOCK_VERSION','8.21.0')); sys.exit(0)
binding=args[args.index('--interface')+1]
with open(os.environ['MOCK_CURL_LOG'],'a') as f: f.write(binding+'\\n')
mode=os.environ.get('MOCK_MODE','stale')
if mode=='unknown': sys.exit(45)
if mode=='outage': sys.exit(7)
if '2409:' in binding and mode!='recovered': sys.exit(7)
print('2001:4860:4860::8888',end='')
""")

    def command(self, name, content):
        f = self.bin / name
        f.write_text(content)
        f.chmod(0o755)

    def invoke(self, *args, **env):
        return subprocess.run(['sh', str(self.script), *args], env=dict(self.env, **env),
            text=True, capture_output=True)

    def rows(self):
        return {r[1]:r for r in (line.split() for line in (self.run/'diagnostics.tsv').read_text().splitlines())}

    def qualify(self):
        for now in ['1000','1015','1030']:
            r = self.invoke('run', MOCK_TIME=now)
            self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.rows()[OLD][8], 'suspected_stale')

    def test_grace_repetition_and_device_binding(self):
        for now, verdict in [('1000','checking'),('1015','checking'),('1029','checking'),('1030','suspected_stale')]:
            r = self.invoke('run', MOCK_TIME=now)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertEqual(self.rows()[OLD][8],verdict)
            self.assertEqual(self.rows()[NEW][8],'reachable')
        probes=(self.root/'probes').read_text().splitlines()
        self.assertTrue(probes and all(s.startswith('ifhost!lan2!') for s in probes))
        self.assertFalse((self.root/'restarted').exists())

    def test_recovery_and_outage_reset(self):
        self.qualify()
        for mode in ['recovered','outage','unknown']:
            r = self.invoke('run', MOCK_MODE=mode, MOCK_TIME='1100')
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertEqual(self.rows()[OLD][8], 'reachable' if mode=='recovered' else 'unverified')
            self.assertEqual(self.rows()[OLD][4],'0')
        self.assertFalse((self.root/'restarted').exists())

    def test_old_curl_cannot_cross_wan(self):
        r = self.invoke('run',MOCK_VERSION='7.88.0',MOCK_ROUTE='pppoe-wan1')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.rows()[OLD][8],'unverified')
        self.assertFalse((self.root/'probes').exists())

    def test_removal_guards(self):
        self.qualify()
        cases=[(('remove','lan2',OLD),{}),
               (('remove','lan2',OLD,'confirmed'),{'MOCK_MODE':'recovered'}),
               (('remove','lan2',OLD,'confirmed'),{'MOCK_MODE':'outage'}),
               (('remove','lan2',OLD,'confirmed'),{'MOCK_TIME':'1400'}),
               (('remove','lan2','fd10:1234::1/64','confirmed'),{})]
        for args, changes in cases:
            env={'MOCK_TIME':'1031'}; env.update(changes)
            r=self.invoke(*args,**env)
            self.assertNotEqual(r.returncode,0,r.stdout)
            self.assertFalse((self.root/'restarted').exists())
        r=self.invoke('remove','lan2',OLD,'confirmed',MOCK_TIME='1031')
        self.assertEqual(r.returncode,0,r.stderr+r.stdout)
        self.assertIn('"restarted":true',r.stdout)
        self.assertIn(OLD,(self.root/'restarted').read_text())
        self.assertFalse((self.root/'kernel-deleted').exists())

    def test_automatic_removal_within_minute(self):
        for now in ['1000','1015']:
            r=self.invoke('auto',MOCK_TIME=now)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertFalse((self.root/'restarted').exists())
        r=self.invoke('auto',MOCK_TIME='1030')
        self.assertEqual(r.returncode,0,r.stderr+r.stdout)
        self.assertIn(OLD,(self.root/'restarted').read_text())
        self.assertNotIn(NEW,(self.root/'restarted').read_text())
        self.assertFalse((self.root/'kernel-deleted').exists())

    def test_auto_monitor_disabled_and_old_curl_never_delete(self):
        for changes in [dict(MOCK_ACTION='monitor'),dict(MOCK_ENABLED='0'),dict(MOCK_VERSION='7.88.0')]:
            for now in ['1000','1015','1030']:
                r=self.invoke('auto',MOCK_TIME=now,**changes)
                self.assertEqual(r.returncode,0,r.stderr)
            self.assertFalse((self.root/'restarted').exists())

    def test_gaps_reset_evidence(self):
        for now in ['1000','1015','1200']:
            r=self.invoke('auto',MOCK_TIME=now)
            self.assertEqual(r.returncode,0,r.stderr)
        self.assertFalse((self.root/'restarted').exists())
        self.assertEqual(self.rows()[OLD][4],'1')

if __name__=='__main__':
    unittest.main(verbosity=2)
