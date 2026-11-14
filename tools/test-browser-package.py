import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import yaml

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package_browser', root / 'tools/package-browser.py')
package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)

class BrowserPackage(unittest.TestCase):
    def test_standalone_target_has_no_host_sources_or_shared_entitlements(self):
        project = yaml.safe_load((root / 'browser-app/project.yml').read_text())
        target = project['targets']['SideOSBrowser']
        self.assertEqual(target['sources'], ['Browser', 'Shared'])
        self.assertEqual(plistlib.loads((root / 'browser-app/Browser.entitlements').read_bytes()), {'get-task-allow': False})
        props = target['info']['properties']
        self.assertFalse(props.get('UIFileSharingEnabled', False))
        self.assertFalse(props['NSAppTransportSecurity']['NSAllowsArbitraryLoads'])
    def test_rejects_host_dylib_wrong_identity_shared_files_and_extensions(self):
        with tempfile.TemporaryDirectory() as d:
            app = Path(d); info = {'CFBundleIdentifier': package.BROWSER_ID, 'CFBundleExecutable': 'Browser', 'CFBundleSupportedPlatforms': ['iPhoneOS']}
            def write(): (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            write(); binary = app / 'Browser'; binary.write_bytes(struct.pack('<IIII', 0xfeedfacf, 0x100000c, 0, 2))
            self.assertEqual(package.verify(app, package.BROWSER_ID), binary)
            binary.write_bytes(struct.pack('<IIII', 0xfeedfacf, 0x100000c, 0, 6))
            with self.assertRaises(ValueError): package.verify(app, package.BROWSER_ID)
            binary.write_bytes(struct.pack('<IIII', 0xfeedfacf, 0x100000c, 0, 2))
            info['UIFileSharingEnabled'] = True; write()
            with self.assertRaises(ValueError): package.verify(app, package.BROWSER_ID)
            del info['UIFileSharingEnabled']; write(); (app / 'LiveProcess.appex').mkdir()
            with self.assertRaises(ValueError): package.verify(app, package.BROWSER_ID)

if __name__ == '__main__': unittest.main()
