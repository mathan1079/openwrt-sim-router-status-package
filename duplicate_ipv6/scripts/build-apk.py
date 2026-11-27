#!/usr/bin/env python3
"""Generate APKv3 with the official apk-tools 3 mkpkg command."""
import hashlib
import json
import sys
import os
from pathlib import Path
import re
import runpy
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def resolve_tool(command):
    command = os.path.expanduser(command)
    found = shutil.which(command)
    if found:
        return found
    # Respect explicit executable overrides; only search standard locations for
    # bare defaults. New terminal sessions may omit ~/.local/bin from PATH.
    if command not in ('apk', 'fakeroot'):
        return None
    for directory in (Path.home() / '.local/bin', Path.home() / '.local/sbin',
            Path('/opt/homebrew/bin'), Path('/usr/local/bin')):
        candidate = directory / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def build():
    shared = runpy.run_path(str(ROOT / 'scripts/build-ipk.py'))
    version, release = shared['version'], shared['release']
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*[a-z]?(?:_(?:alpha|beta|pre|rc|cvs|svn|git|hg|p)[0-9]*)*(?:~[0-9a-f]+)?', version) or not release.isdigit():
        raise SystemExit('APK requires an APK-compatible VERSION (for example 1.0.0) and numeric RELEASE')
    tool = resolve_tool(os.environ.get('APK_TOOL', 'apk'))
    if not tool:
        raise SystemExit('APK build requires apk-tools 3 with mkpkg. Set APK_TOOL=/path/to/SDK/staging_dir/host/bin/apk on a compatible build host.')
    # mkpkg records filesystem ownership; fakeroot ensures installed files are root-owned.
    fakeroot = [] if os.geteuid() == 0 else shlex.split(os.environ.get('FAKEROOT', 'fakeroot'))
    if fakeroot:
        executable = resolve_tool(fakeroot[0])
        if not executable:
            raise SystemExit('APK build requires fakeroot (or a root build environment) for root-owned package files.')
        fakeroot[0] = executable
    elif os.geteuid() != 0:
        raise SystemExit('APK build requires fakeroot (or a root build environment) for root-owned package files.')
    probe = subprocess.run([tool, 'mkpkg', '--help'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if 'Usage: apk mkpkg' not in probe.stdout:
        raise SystemExit('APK_TOOL must support apk mkpkg (full apk-tools 3 / OpenWrt SDK host tool).')
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    path = dist / f"{shared['PACKAGE']}-{version}-r{release}.apk"
    with tempfile.TemporaryDirectory(prefix='ipv6-apk-') as tmp:
        stage = Path(tmp)
        files = stage / 'files'
        files.mkdir()
        for name, content, mode in shared['payload']:
            f = files / name
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(content)
            f.chmod(mode)
        # OpenWrt sysupgrade's package configuration metadata.
        info = files / 'lib/apk/packages'
        info.mkdir(parents=True, exist_ok=True)
        package = shared['PACKAGE']
        config = '/etc/config/ipv6_cleaner'
        (info / (package + '.conffiles')).write_text(config + '\n')
        checksum = hashlib.sha256((files / config.lstrip('/')).read_bytes()).hexdigest()
        (info / (package + '.conffiles_static')).write_text(config + ' ' + checksum + '\n')
        (info / (package + '.list')).write_text(''.join('/' + f.relative_to(files).as_posix() + '\n' for f in sorted(files.rglob('*')) if f.is_file()))
        # Empty identity root makes apk use its built-in root/root fallback
        # for uid/gid 0. Supplying group files triggers host account enumeration
        # in apk-tools on macOS, which would encode gid 0 as wheel.
        identity = stage / 'identity'
        (identity / 'etc').mkdir(parents=True)
        args = [tool, '--root', str(identity), 'mkpkg', '--info', 'name:' + package,
            '--info', f'version:{version}-r{release}', '--info', 'arch:noarch',
            '--info', 'license:MIT', '--info', 'description:Automatic deprecated public IPv6 cleaner with LuCI controls',
            '--info', 'depends:luci-base rpcd ip-full jshn flock']
        for kind, script in [('post-install', 'postinst'), ('post-upgrade', 'postinst'),
                ('pre-deinstall', 'prerm'), ('post-deinstall', 'postrm')]:
            f = stage / kind
            f.write_text(shared[script])
            f.chmod(0o755)
            args.extend(['--script', kind + ':' + str(f)])
        temp_output = stage / 'package.apk'
        args.extend(['--files', str(files), '--output', str(temp_output)])
        # Avoid shell -c: macOS fakeroot's BSD getopt can corrupt quoted
        # arguments. Keep metadata in JSON, and chown/exec in one native process.
        spec = stage / 'build.json'
        helper = stage / 'build-owned.py'
        helper.write_text("""import json, os, sys
from pathlib import Path
spec = json.loads(Path(sys.argv[1]).read_text())
root = Path(spec['files'])
for path in [root, *root.rglob('*')]:
    os.chown(path, 0, 0)
os.execv(spec['args'][0], spec['args'])
""")
        args[0] = tool
        spec.write_text(json.dumps({'files': str(files), 'args': args}))
        command = fakeroot + [sys.executable, str(helper), str(spec)]
        subprocess.run(command, check=True, env=dict(os.environ, SOURCE_DATE_EPOCH='0'))
        if not temp_output.is_file() or not temp_output.stat().st_size:
            raise SystemExit('apk mkpkg did not generate a package')
        temporary = path.with_suffix('.apk.tmp')
        shutil.copyfile(temp_output, temporary)
        temporary.replace(path)
    print(path)

if __name__ == '__main__':
    build()
