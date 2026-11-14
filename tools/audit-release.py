#!/usr/bin/env python3
"""Bounded release-tree checks; reports rules/paths, never credential values."""
from pathlib import Path
import hashlib
import json
import re
import struct
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
tracked = subprocess.check_output(['git', '-c', 'safe.directory=' + str(root), '-C', str(root), 'ls-files', '-z'], text=True).split('\0')
new = subprocess.check_output(['git', '-c', 'safe.directory=' + str(root), '-C', str(root), 'ls-files', '--others', '--exclude-standard', '-z'], text=True).split('\0')
paths = sorted(set(filter(None, tracked + new)))
errors = []
patterns = {
    'GitHub credential': re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})'),
    'AWS access key': re.compile(rb'\bAKIA[A-Z0-9]{16}\b'),
    'PEM private key': re.compile(rb'^-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{80,}-----END (?:[A-Z]+ )?PRIVATE KEY-----', re.M),
}
for name in paths:
    p = root / name
    if not p.is_file():
        continue  # tracked deletions
    if p.suffix.lower() in {'.p12', '.pfx', '.mobileprovision', '.provisionprofile', '.p8', '.key'}:
        errors.append((name, 'personal signing/provisioning file'))
    if p.stat().st_size > 4 * 1024 * 1024:
        errors.append((name, 'unexpected large release-tree file'))
        continue
    data = p.read_bytes()
    for rule, pattern in patterns.items():
        if pattern.search(data):
            errors.append((name, rule))

icon = root / 'embedded/tahoe/AppIcon.appiconset/AppIcon1024.png'
data = icon.read_bytes()
width, height, depth, color = struct.unpack('>IIBB', data[16:26])
if data[:8] != b'\x89PNG\r\n\x1a\n' or (width, height) != (1024, 1024) or depth != 8 or color != 2:
    errors.append((str(icon.relative_to(root)), 'icon must be 1024x1024 opaque RGB PNG'))
for asset in ['TahoeFinder', 'TahoeSafari', 'TahoeSettings', 'TahoeCalculator']:
    if (root / 'embedded/tahoe/Assets.xcassets' / (asset + '.imageset')).exists():
        errors.append((asset, 'legacy reused Apple artwork still in release tree'))
wallpaper = root / 'embedded/tahoe/Assets.xcassets/TahoeGoldenGate.imageset/wallpaper.jpg'
if not wallpaper.is_file():
    errors.append((str(wallpaper), 'default wallpaper missing'))
for name in ['README.md', 'SECURITY.md', 'LICENSING.md', 'CHANGELOG.md', 'docs/install.md', 'docs/user-guide.md', 'docs/troubleshooting.md', 'docs/release-readiness.md']:
    if not (root / name).is_file(): errors.append((name, 'release guidance missing'))
for name, reason in errors:
    print(f'FAIL {name}: {reason}')
if errors: sys.exit(1)
print(json.dumps({'filesChecked': len(paths), 'knownCredentialPatterns': 'no matches in current tree',
    'iconSHA256': hashlib.sha256(data).hexdigest(),
    'wallpaperSHA256': hashlib.sha256(wallpaper.read_bytes()).hexdigest(),
    'binaryReleaseStatus': 'experimental pre-release; physical acceptance and security review remain; not a security certification'}, indent=2))
