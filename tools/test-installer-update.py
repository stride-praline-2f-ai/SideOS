#!/usr/bin/env python3
"""Untrusted or mismatched checkouts must not replace working engine sources."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('installer_update', ROOT / 'tools/update-installer.py')
UPDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE)


class InstallerUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.upstream = self.root / 'upstream'
        self.upstream.mkdir()
        self.engine = self.root / 'engine'
        (self.engine / 'ios-app').mkdir(parents=True)
        self.sentinel = self.engine / 'ios-app/working.swift'
        self.sentinel.write_text('working source')
        self.git('init', '-q')
        (self.upstream / 'source.swift').write_text('official source')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 'commit', '-qm', 'Fixture')
        self.revision = self.git('rev-parse', 'HEAD').strip()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.upstream), *args], text=True)

    def tearDown(self):
        self.temp.cleanup()

    def attempt(self, revision, message):
        (self.root / 'Installer.lock.json').write_text(json.dumps({'revision': revision}))
        with patch.object(UPDATE, 'SOURCE', self.root):
            with self.assertRaisesRegex(ValueError, message):
                UPDATE.apply(self.engine, self.upstream)
        self.assertEqual(self.sentinel.read_text(), 'working source')

    def test_wrong_revision_keeps_working_sources(self):
        self.attempt('0' * 40, 'Expected installer')

    def test_modified_official_source_keeps_working_sources(self):
        (self.upstream / 'source.swift').write_text('unreviewed replacement')
        self.attempt(self.revision, 'must be clean')


if __name__ == '__main__':
    unittest.main()
