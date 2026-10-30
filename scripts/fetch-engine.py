#!/usr/bin/env python3
"""Fetch the pinned upstream engine without requiring another installed app.

Based on the CCBaga macOS fetch boundary (MIT, see licenses/CCBaga-MIT.txt).
Verify the publisher's archive digest and architecture before publishing the input.
"""
import hashlib
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = '148.0.7778.215'
URL = f'https://github.com/adryfish/fingerprint-chromium/releases/download/{VERSION}/ungoogled-chromium_{VERSION}-1.1_macos.dmg'
SHA256 = 'b72f091e2e1a7583eed389c4b8e3534ed355e568af8c8bbf8fc30a25e23ca679'

def digest(path):
    hasher = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()

def main():
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('The current FenJing build targets macOS Apple Silicon only.')
    target = ROOT / 'runtime/Browser.app'
    if target.exists():
        raise SystemExit('runtime/Browser.app already exists; refusing to overwrite it.')
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='fenjing-engine-') as temporary:
        image = Path(temporary) / 'browser.dmg'
        subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--output', str(image), URL], check=True)
        if digest(image) != SHA256:
            raise SystemExit('Upstream browser SHA-256 mismatch.')
        mounted = plistlib.loads(subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(image)]))
        volumes = [Path(item['mount-point']) for item in mounted['system-entities'] if 'mount-point' in item]
        try:
            apps = [app for volume in volumes for app in volume.glob('*.app')]
            if len(apps) != 1:
                raise SystemExit('Expected exactly one browser application in the upstream image.')
            metadata = plistlib.loads((apps[0] / 'Contents/Info.plist').read_bytes())
            if metadata['CFBundleShortVersionString'] != VERSION:
                raise SystemExit('Upstream browser version mismatch.')
            binary = apps[0] / 'Contents/MacOS' / metadata['CFBundleExecutable']
            if 'arm64' not in subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split():
                raise SystemExit('Upstream browser does not contain Apple Silicon code.')
            stage = Path(tempfile.mkdtemp(prefix='.engine-', dir=target.parent))
            try:
                subprocess.run(['ditto', str(apps[0]), str(stage / 'Browser.app')], check=True)
                (stage / 'Browser.app').rename(target)
            finally:
                shutil.rmtree(stage)
        finally:
            for volume in volumes:
                subprocess.run(['hdiutil', 'detach', str(volume)], check=True)
    print(f'Fingerprint Chromium {VERSION}: archive SHA-256 and arm64 verified.')

if __name__ == '__main__':
    main()
