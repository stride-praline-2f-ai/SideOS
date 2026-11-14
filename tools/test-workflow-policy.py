#!/usr/bin/env python3
"""Protect the release/check split and safe exact-product-cache policy."""
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


class WorkflowPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.native = yaml.safe_load((ROOT / '.github/workflows/private-build.yml').read_text())
        cls.checks = yaml.safe_load((ROOT / '.github/workflows/checks.yml').read_text())
        cls.steps = cls.native['jobs']['combined']['steps']

    def test_source_validation_never_packages_or_uploads_an_ipa(self):
        source = yaml.safe_load((ROOT / '.github/workflows/native-source-check.yml').read_text())
        events = source.get('on', source.get(True))
        self.assertEqual(events['push']['branches'], ['validation/native'])
        self.assertEqual(source['permissions'], {'contents': 'read', 'actions': 'read'})
        self.assertEqual(source['jobs']['host']['runs-on'], 'xcode-27')
        steps = source['jobs']['host']['steps']
        self.assertTrue(any(s.get('name') == 'Enforce the desktop compiler warning budget' for s in steps))
        for step in steps:
            self.assertNotIn('upload-artifact', step.get('uses', ''))
            self.assertNotIn('Package and verify', step.get('name', ''))
            self.assertNotIn('simulator', step.get('run', '').lower())

    def test_livecontainer_revision_matches_the_runtime_lock(self):
        import json
        lock = json.loads((ROOT / 'Engine.lock.json').read_text())
        checkout = next(step for step in self.steps if step.get('with', {}).get('repository') == 'LiveContainer/LiveContainer')
        self.assertEqual(checkout['with']['ref'], lock['livecontainer'])
        adapter = (ROOT / 'embedded/prepare_livecontainer.py').read_text()
        self.assertIn('LIVE_CONTAINER_COMMIT = "' + lock['livecontainer'] + '"', adapter)

    def test_duo_release_uses_the_native_sdk_runner_without_an_old_sdk_fallback(self):
        events = self.native.get('on', self.native.get(True))
        runner = events['workflow_dispatch']['inputs']['runner']
        self.assertEqual(runner['default'], 'xcode-27')
        self.assertEqual(runner['options'], ['xcode-27'])
        self.assertEqual(self.native['jobs']['combined']['runs-on'], "${{ inputs.runner || 'xcode-27' }}")

    def test_ordinary_edits_do_not_request_a_native_build(self):
        events = self.native.get('on', self.native.get(True))
        self.assertEqual(events['push']['branches'], ['ipa/device'])
        self.assertEqual(events['push']['tags'], ['ipa-*'])
        self.assertIn('workflow_dispatch', events)
        self.assertFalse(self.native['concurrency']['cancel-in-progress'])
        self.assertEqual(self.native['jobs']['core']['uses'], './.github/workflows/checks.yml')
        self.assertEqual(set(self.native['jobs']), {'reuse', 'core', 'combined'})
        self.assertEqual(self.native['jobs']['core']['needs'], 'reuse')
        self.assertEqual(self.native['jobs']['combined']['if'], "needs.reuse.outputs.reused != 'true'")
        self.assertEqual(self.native['jobs']['combined']['timeout-minutes'], 35)

    def test_cheap_checks_are_callable_and_cancel_only_their_own_superseded_runs(self):
        events = self.checks.get('on', self.checks.get(True))
        self.assertEqual(events['push']['branches'], ['main'])
        self.assertIn('workflow_call', events)
        self.assertTrue(self.checks['concurrency']['cancel-in-progress'])
        self.assertNotEqual(self.checks['concurrency']['group'], self.native['concurrency']['group'])
        self.assertEqual(self.checks['jobs']['validate']['runs-on'], 'ubuntu-latest')

    def test_binary_cache_hits_skip_their_builds_and_never_use_prefix_matching(self):
        caches = {step['id']: step for step in self.steps if step.get('uses', '').startswith('actions/cache/restore@')}
        for name in ('host', 'jit', 'ffi', 'guest'):
            cache = caches[name + '-cache']
            self.assertNotIn('restore-keys', cache['with'])
            self.assertIn('steps.toolchain.outputs.id', cache['with']['key'])
            builds = [step for step in self.steps if step.get('name', '').startswith('Build ') and
                      name + '-cache.outputs.cache-hit' in step.get('if', '')]
            self.assertEqual(len(builds), 1, name)
            saves = [step for step in self.steps if step.get('uses', '').startswith('actions/cache/save@') and
                     step.get('with', {}).get('key') == '${{ steps.' + name + '-cache.outputs.cache-primary-key }}']
            self.assertEqual(len(saves), 1, name)

    def test_device_build_and_packaging_remain_required(self):
        commands = '\n'.join(step.get('run', '') for step in self.steps)
        self.assertIn('build-rust.sh --device-only', commands)
        self.assertNotIn('aarch64-apple-ios-sim', commands)
        self.assertNotIn('tools/test-core.sh', commands)
        package = next(step for step in self.steps if step.get('name') == 'Package and verify the unsigned IPA')
        self.assertNotIn('if', package)
        ipa = next(step for step in self.steps if step.get('name') == 'Upload verified device IPA')
        self.assertNotIn('if', ipa)
        self.assertEqual(ipa['with']['if-no-files-found'], 'error')
        self.assertEqual(ipa['with']['compression-level'], 0)
        self.assertEqual(ipa['with']['retention-days'], 14)
        logs = next(step for step in self.steps if step.get('name') == 'Retain diagnostic logs only on failure')
        self.assertEqual(logs['if'], 'failure()')
        self.assertEqual(logs['with']['retention-days'], 3)

    def test_release_builds_only_the_sideos_ipa(self):
        commands = '\n'.join(step.get('run', '') for step in self.steps)
        self.assertNotIn('SideOSBrowser.xcodeproj', commands)
        self.assertNotIn('package-browser.py', commands)
        upload = next(step for step in self.steps if step.get('name') == 'Upload verified device IPA')
        paths = upload['with']['path'].splitlines()
        self.assertEqual([path for path in paths if path.endswith('.ipa')],
                         ['engine/combined-output/SideOS3-*-unsigned.ipa'])
        self.assertNotIn('isolated-browser-verification.json', upload['with']['path'])

    def test_installer_dashboard_is_applied_before_guest_product_cache_lookup(self):
        preparation = next(i for i, step in enumerate(self.steps)
                           if 'embedded/installer/patch.py' in step.get('run', ''))
        lookup = next(i for i, step in enumerate(self.steps) if step.get('id') == 'guest-cache')
        self.assertLess(preparation, lookup)
        self.assertIn('engine/ios-app/**', self.steps[lookup]['with']['key'])

    def test_official_installer_pin_and_version_are_integrated_before_compilation(self):
        import json
        lock = json.loads((ROOT / 'Installer.lock.json').read_text())
        checkout = next(s for s in self.steps if s.get('with', {}).get('repository') == lock['repository'])
        self.assertEqual(checkout['with']['ref'], lock['revision'])
        update = next(i for i, s in enumerate(self.steps) if 'tools/update-installer.py' in s.get('run', ''))
        ffi = next(i for i, s in enumerate(self.steps) if s.get('id') == 'ffi-cache')
        self.assertLess(update, ffi)
        guest = next(s for s in self.steps if s.get('name') == 'Build the embedded installer only when inputs change')
        self.assertIn('MARKETING_VERSION=' + lock['version'], guest['run'])

    def test_reuse_requires_success_for_the_exact_trusted_source(self):
        reuse = self.checks['jobs']['reuse']
        script = reuse['steps'][0]['with']['script']
        for required in ("head_sha: context.sha", "run.head_sha === context.sha", "run.conclusion === 'success'", "run.head_repository?.full_name === repository", "run.head_branch === 'ipa/device'", "context.ref !== 'refs/heads/main'"):
            self.assertIn(required, script)
        for job in ('layout', 'validate'):
            self.assertEqual(self.checks['jobs'][job]['needs'], 'reuse')
            self.assertEqual(self.checks['jobs'][job]['if'], "needs.reuse.outputs.validated != 'true'")


if __name__ == '__main__':
    unittest.main()
