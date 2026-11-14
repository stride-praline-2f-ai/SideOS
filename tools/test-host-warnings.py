#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('warnings_gate', ROOT / 'tools/check-host-warnings.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class WarningTests(unittest.TestCase):
    def test_catches_and_deduplicates_desktop_warnings(self):
        line = '/engine/LiveContainerSwiftUI/TahoeDesktop/ChatWorkspace.swift:320:10: warning: nearly matches optional requirement'
        self.assertEqual(MODULE.extract(line + '\n' + line), [dict(file='ChatWorkspace.swift', message='nearly matches optional requirement')])

    def test_preserves_upstream_boundary(self):
        self.assertEqual(MODULE.extract('/vendor/Runtime.swift:1:2: warning: inherited diagnostic'), [])


if __name__ == '__main__':
    unittest.main()
