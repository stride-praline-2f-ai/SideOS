#!/usr/bin/env python3
"""Create minimal browser signing requests locally; never read a signing private key."""
import argparse
from datetime import datetime, timezone
import fnmatch
from pathlib import Path
import plistlib
import shutil
import subprocess

BASE_ID = 'com.aault.sideos.browser'

def requests(profile, bundle_id=None, now=None):
    entitlements = profile.get('Entitlements', {})
    pattern = entitlements.get('application-identifier', '')
    if not isinstance(pattern, str) or '.' not in pattern:
        raise ValueError('Profile has no application identifier')
    prefix, declared_bundle = pattern.split('.', 1)
    bundle_id = bundle_id or (BASE_ID if '*' in declared_bundle else declared_bundle)
    suffix = bundle_id[len(BASE_ID) + 1:] if bundle_id.startswith(BASE_ID + '.') else ''
    if bundle_id != BASE_ID and not (len(suffix) == 10 and suffix.isalnum() and suffix.upper() == suffix):
        raise ValueError('Use a profile for the independent SideOS Browser, not the host or another app')
    app_id = prefix + '.' + bundle_id
    if not fnmatch.fnmatchcase(app_id, pattern):
        raise ValueError('Profile does not cover this browser bundle ID')
    allowed_groups = entitlements.get('keychain-access-groups', [])
    if not isinstance(allowed_groups, list) or not any(isinstance(g, str) and fnmatch.fnmatchcase(app_id, g) for g in allowed_groups):
        raise ValueError('Profile does not authorize the browser own-only keychain group')
    team = entitlements.get('com.apple.developer.team-identifier')
    if not isinstance(team, str) or not team or team not in profile.get('TeamIdentifier', []):
        raise ValueError('Profile team identity is missing or inconsistent')
    expires = profile.get('ExpirationDate')
    if not isinstance(expires, datetime) or expires.replace(tzinfo=expires.tzinfo or timezone.utc) <= (now or datetime.now(timezone.utc)):
        raise ValueError('Profile is expired or has no expiry date')
    return bundle_id, {'application-identifier': app_id, 'com.apple.developer.team-identifier': team,
                       'get-task-allow': False, 'keychain-access-groups': [app_id]}

def load_profile(path, openssl=None):
    data = path.read_bytes()
    if data.startswith((b'<?xml', b'bplist', b'<plist')):
        return plistlib.loads(data), 'Decoded metadata only; profile trust is checked by iOS on installation.'
    executable = openssl or shutil.which('openssl')
    if not executable:
        raise ValueError('OpenSSL is needed to decode this CMS profile. Pass --openssl with its local path; Git for Windows includes usr/bin/openssl.exe.')
    result = subprocess.run([executable, 'cms', '-verify', '-inform', 'DER', '-noverify', '-in', str(path)], capture_output=True, check=False)
    if result.returncode:
        raise ValueError('CMS integrity verification failed. Obtain the profile from your trusted signer.')
    return plistlib.loads(result.stdout), 'CMS integrity verified; this is not Apple-chain validation. iOS checks profile trust on installation.'

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile', type=Path, required=True)
    p.add_argument('--bundle-id')
    p.add_argument('--openssl')
    p.add_argument('--output', type=Path, default=Path('Browser.entitlements'))
    a = p.parse_args()
    try:
        profile, note = load_profile(a.profile, a.openssl)
        bundle, entitlements = requests(profile, a.bundle_id)
        a.output.write_bytes(plistlib.dumps(entitlements))
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        p.exit(1, str(error) + '\n')
    print('Browser bundle ID: ' + bundle)
    print('Own-only signing requests written to ' + str(a.output))
    print(note)
    print('Use a replacement-entitlements signer on your trusted computer, then install without re-signing. The on-device gate verifies the resulting signature.')
