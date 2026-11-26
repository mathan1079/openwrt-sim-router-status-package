#!/usr/bin/env python3
"""Run without an OpenWrt host; execute real filter and worker against fixtures."""
import json
import io
import tarfile
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FILTER = ROOT / 'root/usr/libexec/ipv6-cleaner-candidates'


def line(dev, addr, flags='deprecated', scope='global'):
    return f'2: {dev} inet6 {addr} scope {scope} {flags} valid_lft 100sec preferred_lft 0sec\n'


class PackageTests(unittest.TestCase):
    def test_filter(self):
        data = ''.join([
            line('wan1', '2401:abcd::1/64'),
            line('pppoe-wan2', '2606:4700::1/128'),
            line('eth0@eth1', '2a00:1450::1/64'),
            line('wan1', '2401:abcd::2/64', ''),
            line('wan1', 'fd00::1/64'), line('wan1', 'fc00::1/64'),
            line('wan1', 'fe80::1/64', scope='link'),
            line('wan1', 'ff02::1/128'), line('lo', '::1/128'),
            line('wan1', '2401:abcd::3/64', 'deprecated tentative'),
            line('wan1', '2401:abcd::4/64', 'deprecated dadfailed')])
        result = subprocess.check_output(['sh', str(FILTER)], input=data, text=True)
        self.assertEqual(result.splitlines(), ['wan1 2401:abcd::1/64',
            'pppoe-wan2 2606:4700::1/128', 'eth0 2a00:1450::1/64'])

    def test_files(self):
        for file in (ROOT / 'root').rglob('*'):
            if file.is_file() and file.read_text().startswith('#!/bin/sh'):
                subprocess.run(['sh', '-n', str(file)], check=True)
                self.assertTrue(file.stat().st_mode & 0o111)
        for file in ROOT.rglob('*.json'):
            json.loads(file.read_text())
        if shutil.which('node'):
            for file in ROOT.rglob('*.js'):
                subprocess.run(['node', '--check', str(file)], check=True)
        self.assertIn('LUCI_PKGARCH:=all', (ROOT / 'Makefile').read_text())

    def test_built_ipk(self):
        # The local build must use OpenWrt's gzip/tar wrapper, not GNU ar.
        with tempfile.TemporaryDirectory() as tmp:
            stage = Path(tmp)
            shutil.copytree(ROOT / 'root', stage / 'root')
            shutil.copytree(ROOT / 'htdocs', stage / 'htdocs')
            (stage / 'scripts').mkdir()
            builder = stage / 'scripts/build-ipk.py'
            shutil.copy2(ROOT / 'scripts/build-ipk.py', builder)
            subprocess.run(['python3', str(builder)], check=True, capture_output=True,
                env=dict(os.environ, VERSION='1.0.0', RELEASE='1'))
            ipk = stage / 'dist/luci-app-ipv6-cleaner_1.0.0-1_all.ipk'
            self.assertEqual(ipk.read_bytes()[:2], b'\x1f\x8b')
            with tarfile.open(ipk, 'r:gz') as outer:
                self.assertEqual(set(outer.getnames()),
                    {'./debian-binary', './control.tar.gz', './data.tar.gz'})
                self.assertEqual(outer.extractfile('./debian-binary').read(), b'2.0\n')
                with tarfile.open(fileobj=io.BytesIO(outer.extractfile('./control.tar.gz').read())) as control:
                    self.assertIn(b'Architecture: all', control.extractfile('./control').read())
                    self.assertEqual(control.extractfile('./conffiles').read(), b'/etc/config/ipv6_cleaner\n')
                    for name in ['postinst', 'prerm', 'postrm']:
                        subprocess.run(['sh', '-n'], input=control.extractfile('./' + name).read(), check=True)
                with tarfile.open(fileobj=io.BytesIO(outer.extractfile('./data.tar.gz').read())) as data:
                    self.assertEqual(data.getmember('./usr/sbin/ipv6-cleaner').mode, 0o755)
                    self.assertTrue(data.getmember('./www/luci-static/resources/view/ipv6-cleaner').isdir())
                    self.assertIn('./www/luci-static/resources/view/ipv6-cleaner/overview.js', data.getnames())

    def test_worker(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            # Small functional jshn substitute: keep the JSON tree and stack in a file.
            helper = d / 'mock_jshn.py'
            helper.write_text('''import json,sys,os
p=os.environ['MOCK_JSON']; op=sys.argv[1]; args=sys.argv[2:]
s={'root':{},'path':[]} if op=='init' else json.load(open(p))
r=s['root']
for k in s['path']: r=r[k]
if op=='load': s={'root':json.loads(args[0]),'path':[]}
elif op=='dump': print(json.dumps(s['root']))
elif op=='close': s['path'].pop()
elif op=='add':
 typ,key=args[:2]; value=args[2] if len(args)>2 else ''
 v={} if typ=='object' else [] if typ=='array' else int(value) if typ in ('int','boolean') else value
 if isinstance(r,list): key=len(r); r.append(v)
 else: r[key]=v
 if typ in ('array','object'): s['path'].append(key)
json.dump(s,open(p,'w'))
''')
            lib = d / 'jshn.sh'
            lib.write_text('j() { python3 "$MOCK_HELPER" "$@"; }\n' +
                'json_init() { j init; }\njson_load() { j load "$1"; }\njson_dump() { j dump; }\n' +
                ''.join(f'json_add_{t}() {{ j add {t} "$@"; }}\n' for t in ['array', 'object', 'string', 'int', 'boolean']) +
                'json_close_object() { j close; }\njson_close_array() { j close; }\n')
            def command(name, body):
                f=d/name; f.write_text('#!/bin/sh\n'+body); f.chmod(0o755)
            command('uci', 'case "$*" in *enabled) echo 1;; *mode) echo "$MOCK_MODE";; *interval) echo "${MOCK_INTERVAL:-120}";; esac\n')
            command('logger', 'exit 0\n')
            command('flock', 'exit 0\n')  # Lock implementation is supplied by OpenWrt flock.
            command('ip', '''case "$*" in
 *"addr del"*) echo "$*" >> "$MOCK_DELETE"; exit "${MOCK_FAIL:-0}";;
 *"show dev"*) [ "$MOCK_RENEW" = 1 ] || cat "$MOCK_INPUT";;
 *) cat "$MOCK_INPUT";;
esac
''')
            fixture=d/'input'; fixture.write_text(line('wan1','2401:abcd::1/64')+line('wan2','2606:4700::1/64'))
            worker=d/'worker'
            worker.write_text((ROOT/'root/usr/sbin/ipv6-cleaner').read_text()
                .replace('/usr/share/libubox/jshn.sh',str(lib))
                .replace('/var/run/ipv6-cleaner',str(d/'run'))
                .replace('/usr/libexec/ipv6-cleaner-candidates', '"' + str(FILTER) + '"'))
            env=dict(os.environ, PATH=str(d)+os.pathsep+os.environ['PATH'], MOCK_JSON=str(d/'json'),
                MOCK_HELPER=str(helper), MOCK_DELETE=str(d/'deleted'), MOCK_INPUT=str(fixture), MOCK_MODE='monitor')
            def run(**changes):
                result=subprocess.run(['sh',str(worker),'run'],env=dict(env,**changes),text=True,capture_output=True)
                
                if not result.stdout or (result.returncode and 'found' not in result.stdout): print(result.stdout, result.stderr)
                return result.returncode,json.loads(result.stdout)
            code,state=run()
            self.assertEqual((code,state['found'],state['removed']), (0,2,0))
            self.assertFalse((d/'deleted').exists())
            code,state=run(MOCK_MODE='remove',MOCK_RENEW='1')
            self.assertEqual(state['removed'],0)
            code,state=run(MOCK_MODE='remove')
            self.assertEqual((code,state['removed']), (0,2))
            self.assertGreater(state['last_clear'],0)
            code,state=run(MOCK_MODE='remove',MOCK_FAIL='1')
            self.assertEqual((code,state['failed']), (1,2))
            result=subprocess.check_output(['sh',str(worker),'status'],env=env,text=True)
            self.assertEqual(json.loads(result)['next_scan'],0)
            for interval in ['300', '60', '86400', 'bad', '0', '999999999999']:
                result = subprocess.check_output(['sh', str(worker), 'status'],
                    env=dict(env, MOCK_INTERVAL=interval), text=True)
                expected = int(interval) if interval in ['300', '60', '86400'] else 120
                self.assertEqual(json.loads(result)['interval'], expected)


if __name__ == '__main__':
    unittest.main(verbosity=2)
