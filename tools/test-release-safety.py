#!/usr/bin/env python3
"""Exercise actual hostile member data and advisory ranges, without credentials."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent
def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / (name + '.py'))
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result
SAFETY = module('release-safety')
DEPENDENCIES = module('installer-security')

class ReleaseSafetyTests(unittest.TestCase):
    def test_original_license_text_is_preserved(self):
        self.assertEqual(SAFETY.inspect('LICENSE.txt', b'Permission is hereby granted, free of charge, to any person obtaining a copy.'), [])

    def test_discussion_assertion_is_refused_without_echoing_its_value(self):
        text = b'owner' + b' permission' + b' confirmed' + b' in a private discussion'
        errors = SAFETY.inspect('framework/notice.txt', text)
        self.assertEqual(errors, [('framework/notice.txt', 'private discussion reference')])

    def test_scans_nested_framework_resources_in_real_ipa(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'fixture.ipa'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('Payload/App.app/Frameworks/UI.framework/notice.txt', b'project owner' + b' confirmed permission')
            self.assertTrue(SAFETY.inspect_ipa(path))

    def test_provisioning_file_cannot_ship(self):
        self.assertEqual(SAFETY.inspect('Payload/App.app/embedded.mobileprovision', b'fixture'), [('Payload/App.app/embedded.mobileprovision', 'signing/provisioning file')])

    def test_cargo_ranges_include_patch_lines_and_prerelease_rules(self):
        for value, rule, wanted in [('8.6.0', '>=9.0.0', False), ('9.5.1', '>=9.0.0', True),
            ('0.3.26', '^0.3.26', True), ('0.4.0', '^0.3.26', False), ('1.0.9', '>=1.0.10', False),
            ('0.26.11', '=0.26.11', True), ('0.103.16', '>=0.103.16, <0.104.0-alpha.1', True),
            ('0.104.0-alpha.8', '>=0.104.0-alpha.8', True), ('0.104.0-alpha.1', '>=0.103.16', False)]:
            self.assertEqual(DEPENDENCIES.matches(value, rule), wanted, (value, rule))

    def test_vulnerable_lockfile_is_blocked(self):
        with tempfile.TemporaryDirectory() as root:
            lock = Path(root) / 'Cargo.lock'
            lock.write_text('[[package]]\nname="zip"\nversion="8.6.0"\n')
            self.assertTrue(DEPENDENCIES.inspect(lock, {'zip': ['>=9.0.0']})['blocking'])

if __name__ == '__main__': unittest.main()
