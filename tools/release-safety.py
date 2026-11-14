#!/usr/bin/env python3
"""Scan actual release members, reporting paths/rules without secret values."""
from pathlib import Path, PurePosixPath
import argparse
import re
import zipfile

RULES = {
    'private discussion reference': re.compile(rb'(owner\s+permission\s+(?:confirmed|reported)|project\s+owner\s+confirmed.{0,160}permission|development\s+conversation\s+on|user.s\s+permission\s+allows|permission\s+(?:was\s+)?(?:obtained|confirmed)\s+(?:in|by|from))', re.I),
    'GitHub credential': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})'),
    'AWS credential': re.compile(rb'\bAKIA[A-Z0-9]{16}\b'),
    'private key': re.compile(rb'-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----\s+[A-Za-z0-9+/=\r\n]{80,}')
}
SENSITIVE = {'.p12', '.pfx', '.p8', '.key', '.mobileprovision', '.provisionprofile'}
def inspect(name, data):
    errors = []
    if Path(name).suffix.lower() in SENSITIVE: errors.append((name, 'signing/provisioning file'))
    for rule, pattern in RULES.items():
        if pattern.search(data): errors.append((name, rule))
    return errors

def inspect_ipa(path):
    errors = []
    with zipfile.ZipFile(path) as archive:
        members = archive.infolist()
        if len(members) > 20_000 or sum(x.file_size for x in members) > 512 * 1024 * 1024: raise ValueError('Unexpected release package size')
        for item in members:
            name = PurePosixPath(item.filename)
            if name.is_absolute() or '..' in name.parts: errors.append((item.filename, 'unsafe archive member')); continue
            if item.file_size > 128 * 1024 * 1024: errors.append((item.filename, 'unexpected member size')); continue
            if not item.is_dir(): errors.extend(inspect(item.filename, archive.read(item)))
    return errors

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path, required=True)
    args = parser.parse_args()
    errors = inspect_ipa(args.ipa)
    for path, rule in errors: print(f'FAIL {path}: {rule}')
    if errors: raise SystemExit(1)
    print('Actual IPA privacy and credential-pattern gate passed; this is not runtime isolation certification.')
