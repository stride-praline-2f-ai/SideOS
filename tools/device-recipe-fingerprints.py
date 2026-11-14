#!/usr/bin/env python3
"""Hash executable build inputs without artifact/log-only workflow churn.

Exact source paths and the observed Xcode/SDK fingerprint remain separate cache
inputs. Never use this digest with a prefix cache fallback.
"""
import hashlib
import json
import sys
from pathlib import Path
import yaml


def fingerprints(workflow):
    job = workflow['jobs']['combined']
    steps = job['steps']
    first_cache = next(i for i, step in enumerate(steps) if step.get('uses', '').startswith('actions/cache/restore@'))
    common = {
        'defaults': job.get('defaults', {}),
        'environment': [workflow.get('env', {}), job.get('env', {})],
        'preparation': [step for step in steps[:first_cache] if step.get('id') != 'recipes'],
        'fingerprinter': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    }
    result = {}
    for product in ('host', 'jit', 'ffi', 'guest'):
        builds = [step for step in steps if step.get('name', '').startswith('Build ') and
                  product + '-cache.outputs.cache-hit' in step.get('if', '')]
        if len(builds) != 1:
            raise ValueError('Expected exactly one build recipe for ' + product)
        build = {key: value for key, value in builds[0].items() if key not in ('name', 'if')}
        encoded = json.dumps({'common': common, 'build': build}, sort_keys=True, separators=(',', ':')).encode()
        result[product] = hashlib.sha256(encoded).hexdigest()
    return result


if __name__ == '__main__':
    for product, digest in fingerprints(yaml.safe_load(Path(sys.argv[1]).read_text())).items():
        print(product + '=' + digest)
