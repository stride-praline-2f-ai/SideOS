#!/usr/bin/env python3
"""Integrate a pinned official installer with the embedded SideOS runtime.

Run after host/JIT preparation and before FFI/guest cache evaluation. Updating
the installer must not change the already-adapted desktop or runtime pin.
"""
import argparse
import json
import plistlib
import shutil
import subprocess
from pathlib import Path
import yaml

SOURCE = Path(__file__).resolve().parents[1]


def apply(engine, upstream):
    engine, upstream = Path(engine).resolve(), Path(upstream).resolve()
    lock = json.loads((SOURCE / 'Installer.lock.json').read_text())
    revision = subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != lock['revision']:
        raise ValueError(f"Expected installer {lock['revision']}, got {revision}")
    dirty = subprocess.check_output(['git', '-C', str(upstream), 'status', '--porcelain'], text=True)
    if dirty.strip():
        raise ValueError('The official installer checkout must be clean before integration.')
    if (engine / 'ios-app/SideInstallerHomeView.swift').exists():
        raise ValueError('Integrate the official installer before applying the Home dashboard.')
    for name in ('ios-app', 'ios-live-activity', 'rust-core'):
        target = engine / name
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(upstream / name, target)
    shutil.copy2(upstream / 'project.yml', engine / 'project.yml')
    subprocess.run(['git', '-C', str(engine), 'apply', '--check',
                    str(SOURCE / 'embedded/installer/upstream-2.0.1.patch')], check=True)
    subprocess.run(['git', '-C', str(engine), 'apply',
                    str(SOURCE / 'embedded/installer/upstream-2.0.1.patch')], check=True)
    security = SOURCE / 'embedded/installer/security'
    subprocess.run(['git', '-C', str(engine), 'apply', '--check', str(security / 'hardening.patch')], check=True)
    subprocess.run(['git', '-C', str(engine), 'apply', str(security / 'hardening.patch')], check=True)
    shutil.copyfile(security / 'Cargo.lock', engine / 'rust-core/Cargo.lock')
    shutil.copyfile(security / 'safe_extract.rs', engine / 'rust-core/vendor/isideload/src/sideload/safe_extract.rs')
    shutil.copyfile(security / 'cms-fixture.rs', engine / 'rust-core/vendor/apple-codesign-quick/src/sideos_fixture.rs')
    shutil.copytree(security / 'vendor/srp', engine / 'rust-core/vendor/srp', ignore=shutil.ignore_patterns('target', '__pycache__'))
    subprocess.run(['python3', str(SOURCE / 'tools/installer-security.py'), '--lock', str(engine / 'rust-core/Cargo.lock')], check=True)
    project_path = engine / 'project.yml'
    project = yaml.safe_load(project_path.read_text())
    project['settings']['base']['MARKETING_VERSION'] = lock['version']
    target = project['targets']['SideInstaller']
    target['sources'].append({'path': 'embedded/Runtime.m'})
    conditions = '$(inherited) SIDEINSTALLER_EMBEDDED'
    # SDK declarations are checked separately from runtime availability. The
    # stable runner may have an older SDK even when the device runs iOS 27.
    if shutil.which('xcrun'):
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], text=True).strip()
        if int(sdk.split('.')[0]) >= 27:
            conditions += ' SIDEINSTALLER_IOS27_SDK'
    target['settings']['base']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = conditions
    target['settings']['base']['SWIFT_OBJC_BRIDGING_HEADER'] = 'embedded/Runtime.h'
    project_path.write_text(yaml.safe_dump(project, sort_keys=False))
    info_path = engine / 'ios-app/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    if info['CFBundleShortVersionString'] not in (lock['version'], '$(MARKETING_VERSION)'):
        raise ValueError('The pinned installer does not report the expected version.')
    info['SIEmbeddedInstallerRevision'] = revision
    info['SIEmbeddedInstallerRepository'] = lock['repository']
    info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    print(f"SideInstaller {lock['version']} integrated from {revision}; embedded identity and signing support retained.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine', type=Path)
    parser.add_argument('upstream', type=Path)
    args = parser.parse_args()
    apply(args.engine, args.upstream)
