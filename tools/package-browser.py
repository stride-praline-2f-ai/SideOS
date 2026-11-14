#!/usr/bin/env python3
"""Package the independent browser and synthetic probe; never embed either in SideOS."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess

BROWSER_ID = 'com.aault.sideos.browser'

def verify(app, bundle_id):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != bundle_id or info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Expected an independent iPhoneOS app with its own bundle identity')
    if info.get('UIFileSharingEnabled') or info.get('LSSupportsOpeningDocumentsInPlace'):
        raise ValueError('The browser must not publish its private data container to file sharing')
    executable = app / info['CFBundleExecutable']
    header = executable.read_bytes()[:16]
    if len(header) < 16 or struct.unpack('<IIII', header) != (0xfeedfacf, 0x100000c, 0, 2):
        # CPU subtype may vary; ARM64 and MH_EXECUTE are the security-relevant fields.
        if len(header) < 16 or struct.unpack_from('<I', header)[0] != 0xfeedfacf or struct.unpack_from('<I', header, 4)[0] != 0x100000c or struct.unpack_from('<I', header, 12)[0] != 2:
            raise ValueError('Expected a standalone ARM64 executable, not a hosted dylib or Simulator binary')
    for file in app.rglob('*'):
        if any(name in file.name for name in ('LiveContainer', 'SideInstallerApp', 'TweakLoader', 'LiveProcess')) or file.suffix == '.appex':
            raise ValueError('Hosted-app runtime/extension must not enter the isolated browser')
    return executable

def package(products, output, entitlements):
    output.mkdir(parents=True, exist_ok=True)
    report = {'sourceRevision': os.environ['SI_SOURCE_REVISION'], 'separateApplication': True,
              'requestedSharedGroups': [], 'requestedDebugAccess': False,
              'runtimeSignatureGate': 'Must verify actual re-signed process entitlements before creating website sessions',
              'deviceIsolationStatus': 'NOT TESTED here. Run the synthetic probe on the actual signed apps/device.', 'apps': []}
    for name, bundle_id in [('SideOSBrowser', BROWSER_ID), ('SideOSIsolationProbe', 'com.aault.sideos.isolationprobe')]:
        staging = output / ('.stage-' + name)
        if staging.exists(): shutil.rmtree(staging)
        app = staging / 'Payload' / (name + '.app')
        shutil.copytree(products / (name + '.app'), app, symlinks=True)
        executable = verify(app, bundle_id)
        dependencies = subprocess.check_output(['otool', '-L', str(executable)], text=True).splitlines()[1:]
        for dependency in dependencies:
            library = dependency.strip().split(' ', 1)[0]
            if not library.startswith(('/System/Library/', '/usr/lib/', '@rpath/libswift')):
                raise ValueError('Unexpected non-system runtime dependency: ' + library)
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        info.update(CFBundleVersion=os.environ.get('SI_BUILD_NUMBER', '1'), SIEmbeddedSourceRevision=os.environ['SI_SOURCE_REVISION'])
        (app / 'Info.plist').write_bytes(plistlib.dumps(info))
        if name == 'SideOSBrowser':
            requested = plistlib.loads(entitlements.read_bytes())
            if requested != {'get-task-allow': False}: raise ValueError('Unexpected isolated-browser entitlement requests')
            subprocess.run(['ldid', '-S' + str(entitlements), str(executable)], check=True)
            actual = plistlib.loads(subprocess.check_output(['ldid', '-e', str(executable)]))
            if actual != requested: raise ValueError('Unsigned browser entitlement template changed')
        ipa = output / (name + '-' + os.environ.get('SI_BUILD_NUMBER', '1') + '-unsigned.ipa')
        subprocess.run(['ditto', '-c', '-k', '--keepParent', 'Payload', str(ipa.resolve())], cwd=staging, check=True)
        report['apps'].append({'bundleID': bundle_id, 'ipa': ipa.name})
        shutil.rmtree(staging)
    (output / 'isolated-browser-verification.json').write_text(json.dumps(report, indent=2) + '\n')

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--products', type=Path, required=True); p.add_argument('--output', type=Path, required=True)
    p.add_argument('--entitlements', type=Path, required=True)
    a = p.parse_args(); package(a.products, a.output, a.entitlements)
