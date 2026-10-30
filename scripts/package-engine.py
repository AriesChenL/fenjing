"""Produce a self-contained, independently branded browser bundle. No runtime lookup.

Source builds can use a pinned upstream Browser.app prepared by fetch-engine.py, or
FENJING_ENGINE_SOURCE pointing at a compatible local engine. The installed source is
only a development input; no reference to its path is embedded in the product.
"""
from pathlib import Path
import hashlib
import os
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
resources = app / 'Contents/Resources'
prepared = ROOT / 'runtime/Browser.app'
source = Path(os.environ.get('FENJING_ENGINE_SOURCE', str(prepared)))
if not source.is_dir():
    raise SystemExit('Prepare the pinned engine with python3 scripts/fetch-engine.py, or set FENJING_ENGINE_SOURCE to a compatible engine bundle.')
metadata = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
if metadata.get('CFBundleShortVersionString') != '148.0.7778.215':
    raise SystemExit('Expected pinned Fingerprint Chromium 148.0.7778.215')
if not (source / 'Contents/MacOS/Chromium').is_file():
    raise SystemExit('Expected a Chromium engine executable')
target = resources / 'FenJing Browser.app'
if target.exists():
    shutil.rmtree(target)
shutil.copytree(source, target, symlinks=True)
for legacy in ['CCBrowser']:
    (target / 'Contents/MacOS' / legacy).unlink(missing_ok=True)

metadata.update(CFBundleName='FenJing Browser', CFBundleDisplayName='分境浏览器',
                CFBundleIdentifier='local.fenjing.engine', CFBundleExecutable='FenJingBrowser',
                CFBundleIconFile='FenJingBrowser.icns', CFBundleGetInfoString='FenJing Browser. Includes Chromium and Fingerprint Chromium.')
metadata.pop('LSHasLocalizedDisplayName', None)
# Chromium's custom identity/channel associates all profile instances with our engine.
(target / 'Contents/Info.plist').write_bytes(plistlib.dumps(metadata))
for localized in (target / 'Contents/Resources').glob('*.lproj/InfoPlist.strings'):
    text = re.sub(r'^\s*CFBundle(?:Name|DisplayName)\s*=.*?;\s*$', '', localized.read_text(), flags=re.MULTILINE)
    text += '\nCFBundleName = "FenJing Browser";\nCFBundleDisplayName = "分境浏览器";\n'
    localized.write_text(text)
shutil.copyfile(resources / 'BrowserIcon.icns', target / 'Contents/Resources/FenJingBrowser.icns')
(target / 'Contents/Resources/app.icns').unlink(missing_ok=True)
subprocess.run(['xcrun', 'clang', '-mmacosx-version-min=13.0', str(ROOT / 'Sources/EngineLauncher.c'), '-o', str(target / 'Contents/MacOS/FenJingBrowser')], check=True)

magic = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
binaries, bundles = [], []
for base, directories, files in os.walk(target, followlinks=False):
    directories[:] = [d for d in directories if not (Path(base) / d).is_symlink()]
    bundles += [Path(base) / d for d in directories if Path(d).suffix in ['.app', '.framework']]
    for name in files:
        path = Path(base) / name
        if not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in magic:
                    binaries.append(path)
entitlements = ROOT / 'scripts/engine-entitlements.plist'
def sign(path, jit=False):
    command = ['/usr/bin/codesign', '--force', '--sign', '-', '--options', '0', '--timestamp=none']
    if path.name in ['Chromium', 'FenJingBrowser']:
        command += ['--identifier', 'local.fenjing.engine']
    if jit:
        command += ['--entitlements', str(entitlements)]
    subprocess.run([*command, str(path)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
for path in sorted(binaries, key=lambda p: len(p.parts), reverse=True):
    sign(path)
for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
    sign(path, path.name in ['Chromium Helper (Renderer).app', 'Chromium Helper (GPU).app'])
sign(target)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(target)], check=True)
notices = (
    'FenJing / 分境 - Third-party notices\n\n'
    'Native process recognition and browser parameter adaptation: CCBaga, https://github.com/liseami/CCBaga, commit 6db5ad55e799c5b020be8ff5e4def2c147cd5602\n\n'
    + (ROOT / 'licenses/CCBaga-MIT.txt').read_text() + '\n\n'
    + (ROOT / 'licenses/Fingerprint-Chromium-BSD.txt').read_text()
)
(resources / 'ThirdPartyNotices.txt').write_text(notices)
manifest = {'engine': 'Fingerprint Chromium', 'version': metadata['CFBundleShortVersionString'],
            'source': 'https://github.com/adryfish/fingerprint-chromium', 'bundleIdentifier': 'local.fenjing.engine',
            'upstreamExecutableSHA256': hashlib.sha256((source / 'Contents/MacOS/Chromium').read_bytes()).hexdigest()}
(resources / 'EngineManifest.plist').write_bytes(plistlib.dumps(manifest))
print('Embedded FenJing Browser: self-contained, own launcher, icon and bundle identity.')
