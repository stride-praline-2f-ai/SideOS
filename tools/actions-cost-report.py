#!/usr/bin/env python3
"""Estimate compute value from allocated job durations, never claim invoice data."""
import argparse
from datetime import datetime
from decimal import Decimal
import json
import math
from pathlib import Path

RATES = {'macos': Decimal('0.062'), 'ubuntu': Decimal('0.006'), 'windows': Decimal('0.010')}

def estimate(jobs):
    rows = []
    for job in jobs:
        labels = {label.lower() for label in job.get('labels', [])}
        standard = {'macos': {'macos-latest','macos-13','macos-14','macos-15','macos-15-intel','macos-26','macos-26-intel'},
                    'ubuntu': {'ubuntu-latest','ubuntu-20.04','ubuntu-22.04','ubuntu-24.04'},
                    'windows': {'windows-latest','windows-2022','windows-2025'}}
        os = next((key for key, known in standard.items() if labels & known), None) if 'self-hosted' not in labels else None
        start, end = job.get('started_at'), job.get('completed_at')
        if job.get('conclusion') == 'skipped' or not job.get('runner_name') or not start or not end:
            continue
        seconds = max(0, (datetime.fromisoformat(end.replace('Z', '+00:00')) - datetime.fromisoformat(start.replace('Z', '+00:00'))).total_seconds())
        minutes = math.ceil(seconds / 60)
        rows.append({'name': job['name'], 'os': os or 'unknown', 'seconds': seconds, 'roundedMinutes': minutes,
                     'estimatedUSD': str(minutes * RATES[os]) if os else None, 'conclusion': job.get('conclusion')})
    return {'basis': 'Allocated completed jobs; rounded per job; standard-runner published rates as checked 2026-11-07. Estimate, not billing ledger. Unknown runners are not priced.',
            'jobs': rows, 'estimatedUSD': str(sum((Decimal(r['estimatedUSD']) for r in rows if r['estimatedUSD'] is not None), Decimal(0)))}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('jobs_json', type=Path)
    data = json.loads(parser.parse_args().jobs_json.read_text())
    print(json.dumps(estimate(data['jobs'] if isinstance(data, dict) else data), indent=2))
