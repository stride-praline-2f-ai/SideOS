#!/usr/bin/env python3
"""Exercise Rust build selection with command stubs; no Apple SDK is required."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'build-rust.sh'
STUB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
with open(os.environ['BUILD_RUST_TEST_LOG'], 'a') as log:
    log.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
if name == 'cargo':
    target = sys.argv[sys.argv.index('--target') + 1]
    output = pathlib.Path('target') / target / 'release'
    output.mkdir(parents=True, exist_ok=True)
    (output / 'libsideinstaller_ffi.a').write_bytes(b'fixture')
else:
    pathlib.Path(sys.argv[sys.argv.index('-output') + 1]).mkdir()
'''


class RustBuildSelection(unittest.TestCase):
    def exercise(self, *arguments):
        with tempfile.TemporaryDirectory(prefix='sideos-build-selection-') as task:
            root = Path(task)
            shutil.copy2(SOURCE, root / 'build-rust.sh')
            (root / 'rust-core/include').mkdir(parents=True)
            (root / 'bin').mkdir()
            for name in ('cargo', 'xcodebuild'):
                stub = root / 'bin' / name
                stub.write_text(STUB)
                stub.chmod(0o755)
            log = root / 'commands.jsonl'
            environment = os.environ.copy()
            environment['PATH'] = str(root / 'bin') + os.pathsep + environment['PATH']
            environment['BUILD_RUST_TEST_LOG'] = str(log)
            result = subprocess.run(['bash', str(root / 'build-rust.sh'), *arguments],
                                    env=environment, text=True, capture_output=True)
            commands = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, commands

    def test_device_build_never_compiles_or_packages_a_simulator_slice(self):
        result, commands = self.exercise('--device-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        cargo = [command for command in commands if command[0] == 'cargo']
        self.assertEqual(len(cargo), 1)
        self.assertEqual(cargo[0][-1], 'aarch64-apple-ios')
        self.assertEqual(commands[-1].count('-library'), 1)
        self.assertNotIn('aarch64-apple-ios-sim', ' '.join(' '.join(command) for command in commands))

    def test_local_default_keeps_both_platforms(self):
        result, commands = self.exercise()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([command[-1] for command in commands if command[0] == 'cargo'],
                         ['aarch64-apple-ios', 'aarch64-apple-ios-sim'])
        self.assertEqual(commands[-1].count('-library'), 2)

    def test_explicit_local_all_platforms(self):
        result, commands = self.exercise('--all-platforms')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands[-1].count('-library'), 2)

    def test_unknown_mode_does_not_start_a_build(self):
        result, commands = self.exercise('--typo')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(commands, [])


if __name__ == '__main__':
    unittest.main()
