#!/usr/bin/env python3
"""Keep desktop-owned Swift warnings at zero; upstream diagnostics stay visible."""
import argparse
import json
from pathlib import Path
import re


def extract(text):
    warnings = set()
    for line in text.splitlines():
        match = re.search(r'TahoeDesktop/([^/:]+\.swift):\d+:\d+: warning: (.*)', line)
        if match:
            warnings.add((match[1], match[2].strip()))
    return [dict(file=file, message=message) for file, message in sorted(warnings)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--summary', type=Path, required=True)
    args = parser.parse_args()
    if args.log.exists():
        value = dict(version=1, warnings=extract(args.log.read_text(errors='replace')))
        args.summary.write_text(json.dumps(value, indent=2) + '\n')
    elif args.summary.exists():
        value = json.loads(args.summary.read_text())
        if value.get('version') != 1:
            raise SystemExit('Cached host warning metadata has an unsupported version.')
    else:
        raise SystemExit('No desktop compiler warning evidence is available for this host product.')
    for warning in value['warnings']:
        print(warning['file'] + ': ' + warning['message'])
    if value['warnings']:
        raise SystemExit(f"{len(value['warnings'])} desktop compiler warning(s) need correction.")
    print('Desktop Swift compiler warning budget passed (zero warnings).')


if __name__ == '__main__':
    main()
