#!/usr/bin/env python3
import copy
import importlib.util
import unittest
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('recipes', ROOT / 'tools/device-recipe-fingerprints.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RecipeTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / '.github/workflows/private-build.yml').read_text())
        self.original = MODULE.fingerprints(self.workflow)

    def test_artifact_only_edits_preserve_binary_keys(self):
        edited = copy.deepcopy(self.workflow)
        for step in edited['jobs']['combined']['steps']:
            if step.get('uses', '').startswith('actions/upload-artifact@'):
                step['with']['name'] = 'Renamed artifact'
                step['with']['retention-days'] = 7
        self.assertEqual(self.original, MODULE.fingerprints(edited))

    def test_native_display_test_edits_preserve_product_keys(self):
        edited = copy.deepcopy(self.workflow)
        names = {'Check the native display codec without a simulator',
                 'Check encrypted display pairing and input rejection'}
        checks = [s for s in edited['jobs']['combined']['steps'] if s.get('name') in names]
        self.assertEqual(len(checks), 2)
        for check in checks:
            check['run'] += '\n# a native fixture-only change\n'
        self.assertEqual(self.original, MODULE.fingerprints(edited))

    def test_compiler_change_invalidates_its_product(self):
        edited = copy.deepcopy(self.workflow)
        step = next(s for s in edited['jobs']['combined']['steps'] if s.get('name') == 'Build the desktop host and runtime')
        step['run'] += '\n# changed host recipe\n'
        actual = MODULE.fingerprints(edited)
        self.assertNotEqual(self.original['host'], actual['host'])
        for product in ('jit', 'ffi', 'guest'):
            self.assertEqual(self.original[product], actual[product])

    def test_preparation_or_checkout_changes_invalidate_all_products(self):
        edited = copy.deepcopy(self.workflow)
        checkout = next(s for s in edited['jobs']['combined']['steps'] if s.get('with', {}).get('repository') == 'aaULTra/SideContainer')
        checkout['with']['ref'] = 'different-pin'
        actual = MODULE.fingerprints(edited)
        self.assertTrue(all(self.original[p] != actual[p] for p in self.original))

    def test_exact_cache_policy_is_preserved(self):
        for step in self.workflow['jobs']['combined']['steps']:
            if not step.get('uses', '').startswith('actions/cache/restore@') or step.get('id') == 'cargo-cache':
                continue
            self.assertNotIn('restore-keys', step['with'])
            if step.get('id') == 'browser-cache':
                self.assertIn('desktop-source/.github/workflows/private-build.yml', step['with']['key'])
            else:
                self.assertIn('steps.recipes.outputs.', step['with']['key'])
            self.assertIn('steps.toolchain.outputs.id', step['with']['key'])

    def test_installer_update_preserves_completed_host_and_jit_recipes(self):
        edited = copy.deepcopy(self.workflow)
        steps = edited['jobs']['combined']['steps']
        edited['jobs']['combined']['steps'] = [s for s in steps
            if s.get('with', {}).get('repository') != 'FrizzleM/SideInstaller'
            and s.get('name') != 'Integrate the pinned SideInstaller 2.0.1']
        actual = MODULE.fingerprints(edited)
        for product in ('host', 'jit'):
            self.assertEqual(self.original[product], actual[product])


if __name__ == '__main__':
    unittest.main()
