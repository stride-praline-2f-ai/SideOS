#!/usr/bin/env python3
"""Exercise toolchain selection without an Apple SDK; never accept SDK 26/27.0."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SDKSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sideos sdk ')
        self.root = Path(self.temp.name)
        self.apps = self.root / 'Applications'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name, code in {
            'xcrun': "from pathlib import Path; import os; print((Path(os.environ['DEVELOPER_DIR']) / 'sdk').read_text().strip())",
            'xcodebuild': "print('Fixture Xcode')",
        }.items():
            path = self.bin / name
            path.write_text('#!/usr/bin/env python3\n' + code + '\n')
            path.chmod(0o755)
        self.env_file = self.root / 'env'

    def tearDown(self):
        self.temp.cleanup()

    def xcode(self, name, sdk):
        path = self.apps / name / 'Contents/Developer'
        path.mkdir(parents=True)
        (path / 'sdk').write_text(sdk)
        return path

    def run_selection(self):
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                   SIDEOS_XCODE_ROOT=str(self.apps), GITHUB_ENV=str(self.env_file))
        return subprocess.run(['bash', str(ROOT / 'tools/select-xcode.sh')], env=env,
                              capture_output=True, text=True)

    def test_prefers_27_2_and_records_the_selected_developer_directory(self):
        expected = self.xcode('Xcode_27.2.app', '27.2')
        self.xcode('Xcode_27.1.app', '27.1')
        result = self.run_selection()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.env_file.read_text().strip(), 'DEVELOPER_DIR=' + str(expected))

    def test_checks_the_actual_sdk_instead_of_trusting_the_xcode_filename(self):
        self.xcode('Xcode_27.2.app', '26.5')
        expected = self.xcode('Xcode_27.1.app', '27.1')
        result = self.run_selection()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(expected), self.env_file.read_text())

    def test_old_and_unknown_sdks_fail_without_exporting_a_fallback(self):
        candidate = self.xcode('Xcode.app', '27.0')
        for sdk in ('26.5', '27.0', 'unknown'):
            with self.subTest(sdk=sdk):
                (candidate / 'sdk').write_text(sdk)
                result = self.run_selection()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.env_file.exists())


if __name__ == '__main__':
    unittest.main()
