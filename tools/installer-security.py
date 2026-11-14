#!/usr/bin/env python3
"""Fail closed on known affected installer dependencies; optionally check RustSec."""
import argparse
import functools
import json
from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parents[1]

def version(value):
    match = re.fullmatch(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?', value)
    if not match: raise ValueError('Unsupported dependency version')
    return tuple(int(x or 0) for x in match.groups()[:3]), match[4]

def compare(a, b):
    x, xp = version(a); y, yp = version(b)
    if x != y: return (x > y) - (x < y)
    if xp == yp: return 0
    if xp is None: return 1
    if yp is None: return -1
    xs, ys = xp.split('.'), yp.split('.')
    for left, right in zip(xs, ys):
        if left == right: continue
        if left.isdigit() and right.isdigit(): return (int(left) > int(right)) - (int(left) < int(right))
        if left.isdigit() != right.isdigit(): return -1 if left.isdigit() else 1
        return (left > right) - (left < right)
    return (len(xs) > len(ys)) - (len(xs) < len(ys))

def matches(value, requirement):
    terms = [x.strip() for x in requirement.split(',')]
    if not terms or any(not x for x in terms): raise ValueError('Empty advisory range')
    core, pre = version(value)
    if pre and not any('-' in term and version(re.sub(r'^[<>=~^ ]+', '', term))[0] == core for term in terms): return False
    for term in terms:
        match = re.fullmatch(r'(>=|<=|>|<|=|\^|~)?\s*(.+)', term)
        op, required = match.groups(); op = op or '^'
        if '*' in required or re.search(r'\bx\b', required):
            parts = required.split('.'); fixed = []
            for part in parts:
                if part in ('*', 'x'): break
                fixed.append(int(part))
            if core[:len(fixed)] != tuple(fixed): return False
            continue
        if op in ('^', '~'):
            lower, _ = version(required); upper = list(lower)
            pivot = 1 if op == '~' and '.' in required else next((i for i, n in enumerate(lower) if n), 2) if op == '^' else 0
            upper[pivot] += 1
            for i in range(pivot + 1, 3): upper[i] = 0
            if compare(value, required) < 0 or compare(value, '.'.join(map(str, upper))) >= 0: return False
        else:
            order = compare(value, required)
            if not {'>=': order >= 0, '<=': order <= 0, '>': order > 0, '<': order < 0, '=': order == 0}[op]: return False
    return True

def inspect(lock, policy, database=None):
    packages = tomllib.loads(Path(lock).read_text())['package']
    problems = []; notices = []; compared = 0
    for package in packages:
        name, value = package['name'], package['version']
        ranges = policy.get(name)
        if ranges and not any(matches(value, rule) for rule in ranges): problems.append({'package': name, 'version': value, 'rule': 'minimum patched dependency policy'})
        if not database: continue
        for path in (Path(database) / 'crates' / name).glob('*.md'):
            advisory = tomllib.loads(path.read_text().split('```toml', 1)[1].split('```', 1)[0])
            info = advisory['advisory']
            if info.get('withdrawn'): continue
            compared += 1
            versions = advisory.get('versions', {})
            if any(matches(value, rule) for rule in versions.get('patched', []) + versions.get('unaffected', [])): continue
            entry = {'package': name, 'version': value, 'advisory': info['id']}
            if info.get('informational') == 'unmaintained': notices.append(entry)
            else: problems.append(entry)
    return {'packages': len(packages), 'advisoriesCompared': compared, 'blocking': problems, 'maintenanceNotices': notices}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', type=Path, default=ROOT / 'embedded/installer/security/Cargo.lock')
    parser.add_argument('--database', type=Path)
    args = parser.parse_args()
    policy = json.loads((ROOT / 'embedded/installer/security/dependency-policy.json').read_text())
    report = inspect(args.lock, policy, args.database)
    print(json.dumps(report, indent=2))
    raise SystemExit(bool(report['blocking']))
