#!/usr/bin/env python3
"""Overlay the private desktop onto a verified public runtime foundation."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

source = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('engine', type=Path)
args = parser.parse_args()
engine = args.engine.resolve()
lock = json.loads((source / 'Engine.lock.json').read_text())
revision = subprocess.check_output(['git','-C',str(engine),'rev-parse','HEAD'],text=True).strip()
if revision != lock['revision']:
    raise SystemExit(f'Expected engine {lock["revision"]}, got {revision}')
destination = engine / 'embedded/tahoe'
if destination.exists():
    shutil.rmtree(destination)
shutil.copytree(source / 'embedded/tahoe', destination, ignore=shutil.ignore_patterns('__pycache__','Generated-*.plist'))
installer = engine / 'embedded/installer'
if installer.exists():
    shutil.rmtree(installer)
shutil.copytree(source / 'embedded/installer', installer, ignore=shutil.ignore_patterns('__pycache__'))
for name in ('prepare_livecontainer.py','package.py'):
    shutil.copy2(source / 'embedded' / name, engine / 'embedded' / name)
shutil.copy2(source / 'build-rust.sh', engine / 'build-rust.sh')
print('Private desktop overlaid on the pinned engine. Original checkout identity and data paths are retained.')
