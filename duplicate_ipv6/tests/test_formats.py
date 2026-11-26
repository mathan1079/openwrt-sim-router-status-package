#!/usr/bin/env python3
"""Test build metadata and routing with isolated tools, never a real router."""
import ast
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class FormatTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ['scripts', 'root', 'htdocs']:
            shutil.copytree(ROOT / name, self.root / name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
            APK_TOOL=str(self.bin / 'apk'), FAKEROOT=str(self.bin / 'fakeroot'),
            MOCK_LOG=str(self.root / 'log'), MOCK_MANAGER='opkg', ROUTER='test-router',
            VERSION='1.2.3', RELEASE='4', APK_ALLOW_UNTRUSTED='1')
        self.command('fakeroot', """#!/usr/bin/env python3
import os,runpy,sys
# Isolate ownership effects in unit tests; the real local build verifies fakeroot.
os.chown = lambda *args, **kwargs: None
sys.argv = sys.argv[2:]
runpy.run_path(sys.argv[0], run_name='__main__')
""")
        self.command('chown', '#!/bin/sh\nexit 0\n')
        self.command('apk', """#!/usr/bin/env python3
import sys,os,json
from pathlib import Path
a=sys.argv[1:]
if a==['mkpkg','--help']:
 print('Usage: apk mkpkg [<OPTIONS>...]'); sys.exit(1)
assert a[0]=='--root' and a[2]=='mkpkg'
assert not (Path(a[1])/'etc/group').exists()
files=Path(a[a.index('--files')+1])
record={'args':a, 'files':{str(f.relative_to(files)):f.read_text() for f in files.rglob('*') if f.is_file()},
 'scripts':{v.split(':',1)[0]:Path(v.split(':',1)[1]).read_text() for i,v in enumerate(a) if i and a[i-1]=='--script'}}
with open(os.environ['MOCK_LOG'],'a') as f: f.write(json.dumps(record)+'\\n')
Path(a[a.index('--output')+1]).write_bytes(b'FAKE-APK-FOR-COMMAND-TEST')
""")
        self.command('ssh', """#!/usr/bin/env python3
import os,sys,json
with open(os.environ['MOCK_LOG'],'a') as f: f.write(json.dumps({'ssh':sys.argv[1:]})+'\\n')
if 'command -v' in sys.argv[-1]: print(os.environ['MOCK_MANAGER'])
""")
        self.command('scp', """#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
assert Path(sys.argv[-2]).is_file()
with open(os.environ['MOCK_LOG'],'a') as f: f.write(json.dumps({'scp':sys.argv[1:]})+'\\n')
""")

    def command(self, name, content):
        f = self.bin / name
        f.write_text(content)
        f.chmod(0o755)

    def run_script(self, script, *args, **env):
        return subprocess.run(['python3', str(self.root / 'scripts' / script), *args],
            env=dict(self.env, **env), cwd=self.root, capture_output=True, text=True)

    def records(self):
        return [json.loads(s) for s in (self.root / 'log').read_text().splitlines()]

    def test_apk_metadata(self):
        r = self.run_script('build-apk.py')
        self.assertEqual(r.returncode, 0, r.stderr)
        record = self.records()[0]
        for value in ['arch:noarch', 'version:1.2.3-r4', 'depends:luci-base rpcd ip-full jshn flock']:
            self.assertIn(value, record['args'])
        self.assertEqual(set(record['scripts']), {'post-install', 'post-upgrade', 'pre-deinstall', 'post-deinstall'})
        self.assertIn('etc/config/ipv6_cleaner', record['files'])
        self.assertEqual(record['files']['lib/apk/packages/luci-app-ipv6-cleaner.conffiles'], '/etc/config/ipv6_cleaner\n')
        for script in record['scripts'].values():
            subprocess.run(['sh', '-n'], input=script, text=True, check=True)
        self.assertTrue((self.root / 'dist/luci-app-ipv6-cleaner-1.2.3-r4.apk').exists())
        self.assertFalse(list((self.root / 'dist').glob('*.ipk')))

    def test_install_and_uninstall_detection(self):
        for manager in ['opkg', 'apk']:
            with self.subTest(manager=manager):
                log = self.root / 'log'
                if log.exists(): log.unlink()
                r = self.run_script('router-package.py', 'install', MOCK_MANAGER=manager)
                self.assertEqual(r.returncode, 0, r.stderr)
                records = self.records()
                install = records[-1]['ssh'][-1]
                self.assertTrue(install.startswith('opkg install ' if manager == 'opkg' else 'apk add --allow-untrusted '))
                copy = [row['scp'] for row in records if 'scp' in row][0]
                self.assertTrue(copy[-2].endswith('.ipk' if manager == 'opkg' else '.apk'))
                r = self.run_script('router-package.py', 'uninstall', MOCK_MANAGER=manager)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(self.records()[-1]['ssh'][-1], manager + (' remove ' if manager == 'opkg' else ' del ') + 'luci-app-ipv6-cleaner')

    def test_missing_tool_fails_before_copy(self):
        r = self.run_script('router-package.py', 'install', MOCK_MANAGER='apk', APK_TOOL='/missing/apk')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('APK build requires', r.stderr)
        self.assertFalse(any('scp' in row for row in self.records()))

    def test_python_syntax(self):
        for file in (ROOT / 'scripts').glob('*.py'):
            ast.parse(file.read_text(), filename=str(file))

if __name__ == '__main__':
    unittest.main(verbosity=2)
