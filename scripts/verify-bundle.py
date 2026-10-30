"""Offline verification of a relocatable, self-contained FenJing app bundle."""
from pathlib import Path
import hashlib
import plistlib
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
engine = app / 'Contents/Resources/FenJing Browser.app'
for path, identifier, executable in [(app, 'local.fenjing.browser-manager', 'FenJing'), (engine, 'local.fenjing.engine', 'FenJingBrowser')]:
    metadata = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
    assert metadata['CFBundleIdentifier'] == identifier
    assert metadata['CFBundleExecutable'] == executable
    assert 'CCBaga' not in metadata.get('CFBundleDisplayName', '')
    assert (path / 'Contents/MacOS' / executable).is_file()
assert (engine / 'Contents/MacOS/Chromium').is_file()
assert not (engine / 'Contents/MacOS/CCBrowser').exists()
assert (app / 'Contents/Resources/ThirdPartyNotices.txt').is_file()
icon = (app / 'Contents/Resources/AppIcon.icns').read_bytes()
browser_icon = (app / 'Contents/Resources/BrowserIcon.icns').read_bytes()
assert browser_icon == (engine / 'Contents/Resources/FenJingBrowser.icns').read_bytes()
assert icon != browser_icon, 'Manager and browser must have visually distinct Dock icons'
assert plistlib.loads((engine / 'Contents/Info.plist').read_bytes())['CFBundleIconFile'] == 'FenJingBrowser.icns'
for path in app.rglob('*'):
    if path.is_symlink():
        assert path.resolve().is_relative_to(app), f'External bundle link: {path}'
main = (app / 'Contents/MacOS/FenJing').read_bytes()
for legacy in [b'/Applications/CCBaga', b'ai.local.requirement-french', b'local.ccbroswer']:
    assert legacy not in main, f'Legacy runtime reference: {legacy}'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('PASS own application identities, own icons, embedded engine and launcher, no external bundle links or legacy runtime app references, retained licenses, valid local signatures')
print('Icon SHA256:', hashlib.sha256(icon).hexdigest()[:16])
print('Browser icon SHA256:', hashlib.sha256(browser_icon).hexdigest()[:16])
