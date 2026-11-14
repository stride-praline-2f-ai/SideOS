#!/usr/bin/env python3
"""Release gates inspect executable contents, not just version labels."""
import hashlib
import importlib.util
import json
import plistlib
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('desktop_package', ROOT / 'embedded/package.py')
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


def macho(markers=b'', sdk=(27, 2, 0), platform=2, kind=6):
    encoded_sdk = sdk[0] << 16 | sdk[1] << 8 | sdk[2]
    header = struct.pack('<IIIIIIII', 0xfeedfacf, 0x100000c, 0, kind, 1, 24, 0, 0)
    command = struct.pack('<IIIIII', 0x32, 24, platform, 17 << 16 | 5 << 8, encoded_sdk, 0)
    return header + command + markers


class DesktopPackage(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = Path(self.directory.name)
        self.host = self.app / 'Frameworks/LiveContainerSwiftUI.framework/LiveContainerSwiftUI'
        self.guest = self.app / 'Frameworks/SideInstallerApp.framework/SideInstaller'
        self.host.parent.mkdir(parents=True)
        self.guest.parent.mkdir(parents=True)
        self.host.write_bytes(macho(b'Native framework\0Search Open Tabs\0Storage & Recovery\0TahoeInstallerPickerServer\0'))
        self.guest.write_bytes(macho(b'Refresh stopped to preserve the installed SideOS desktop. More details\0Files access runtime: SideOS host picker requested\0IPA contains an unsafe path, link, size or duplicate entry\0'))
        self.bootstrap = self.app / 'Frameworks/LiveContainerShared.framework/LiveContainerShared'
        self.bootstrap.parent.mkdir(parents=True)
        self.bootstrap.write_bytes(b'Bootstrap\0../../Frameworks/TweakLoader.dylib\0SideInstaller Files runtime:\0LCGuestExtension\0')
        self.picker = self.app / 'Frameworks/TweakLoader.dylib'
        self.picker.write_bytes(b'DOCConfiguration\0hook_setHostIdentifier:\0')
        def plist(path, data):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(plistlib.dumps(data))
        plist(self.app / 'Info.plist', {'CFBundleIdentifier': PACKAGE.HOST_ID,
                                      'CFBundleExecutable': 'LiveContainer', 'DTSDKName': 'iphoneos27.2',
                                      'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}})
        plist(self.app / 'PlugIns/LiveProcess.appex/Info.plist', {'CFBundleIdentifier': PACKAGE.HOST_ID + '.LiveProcess'})
        self.executable = self.app / 'LiveContainer'
        self.executable.write_bytes(macho(kind=2))
        self.live_process = self.app / 'PlugIns/LiveProcess.appex/LiveProcess'
        self.live_process.write_bytes(macho(kind=2))
        plist(self.app / 'PlugIns/SIJITHelper.appex/Info.plist', {
            'CFBundleIdentifier': PACKAGE.HOST_ID + '.JITHelper',
            'NSExtension': {'NSExtensionPrincipalClass': 'SIJITHelperHandler'}})
        jit = self.app / 'Frameworks/StikJIT.framework'
        plist(jit / 'Info.plist', {'CFBundleIdentifier': 'com.stik.StikJIT', 'CFBundleExecutable': 'StikJIT',
            'CFBundleName': 'StikJIT', 'CFBundlePackageType': 'FMWK', 'CFBundleShortVersionString': '1.9.0',
            'CFBundleVersion': '10', 'MinimumOSVersion': '17.4', 'CFBundleSupportedPlatforms': ['iPhoneOS']})
        (jit / 'StikJIT').write_bytes(b'framework')
        (jit / 'universal.js').write_text('// script')
        metadata = self.app / 'Metadata.appintents'
        metadata.mkdir()
        (metadata / 'extract.actionsdata').write_text(json.dumps({'actions': {'RefreshAllAppsIntent': {
            'isDiscoverable': True, 'openAppWhenRun': False, 'fullyQualifiedTypeName': 'SideStoreSupport.RefreshAllAppsIntent',
            'systemProtocols': ['com.apple.link.systemProtocol.ForegroundContinuable', 'com.apple.link.systemProtocol.ProgressReporting']}},
            'autoShortcuts': [{'actionIdentifier': 'RefreshAllAppsIntent'}]}))

    def tearDown(self):
        self.directory.cleanup()

    def test_current_components_are_fingerprinted(self):
        report = PACKAGE.verify_desktop_components(self.app)
        self.assertTrue(report['modernDesktopVerified'])
        self.assertTrue(report['selfRefreshSourceGuardVerified'])
        self.assertTrue(report['installerFilesRuntimePackaged'])
        self.assertTrue(report['nativeDisplayConfigurationVerified'])
        self.assertTrue(report['duoLinkedSDKVerified'])
        self.assertEqual(report['desktopRuntimeSHA256'], hashlib.sha256(self.host.read_bytes()).hexdigest())

    def test_legacy_archive_extractor_cannot_be_relabelled_as_hardened(self):
        self.guest.write_bytes(self.guest.read_bytes().replace(b'IPA contains an unsafe path, link, size or duplicate entry', b'legacy extraction'))
        with self.assertRaisesRegex(ValueError, 'bounded IPA extraction'):
            PACKAGE.verify_desktop_components(self.app)

    def test_real_sdk_load_command_cannot_be_overridden_by_a_new_version_label(self):
        self.executable.write_bytes(macho(sdk=(26, 5, 0), kind=2))
        self.assertEqual(PACKAGE.linked_ios_sdk(self.executable.read_bytes()), (26, 5, 0))
        with self.assertRaisesRegex(ValueError, 'host is linked against iOS 26.5'):
            PACKAGE.verify_duo_linked_sdks(self.app)

    def test_old_live_process_and_non_device_binaries_are_rejected(self):
        self.live_process.write_bytes(macho(sdk=(27, 0, 0), kind=2))
        with self.assertRaisesRegex(ValueError, 'liveProcess is linked against'):
            PACKAGE.verify_duo_linked_sdks(self.app)
        with self.assertRaisesRegex(ValueError, 'iOS device'):
            PACKAGE.linked_ios_sdk(macho(platform=7))
        with self.assertRaisesRegex(ValueError, 'Mach-O'):
            PACKAGE.linked_ios_sdk(b'truncated')

    def test_legacy_launch_sizing_cannot_pass_the_display_gate(self):
        current = {'UIDeviceFamily': [1, 2], 'UILaunchScreen': {}}
        for legacy in ({'UILaunchStoryboardName': 'LaunchScreen'},
                       {'UILaunchImages': [{'UILaunchImageSize': '{320, 480}'}]},
                       {'UILaunchImageFile': 'LaunchImage'}):
            with self.subTest(legacy=legacy), self.assertRaisesRegex(ValueError, 'adaptive launch screen'):
                PACKAGE.verify_native_display_configuration({**current, **legacy})
        with self.assertRaisesRegex(ValueError, 'adaptive launch screen'):
            PACKAGE.verify_native_display_configuration({'UIDeviceFamily': [1, 2]})
        with self.assertRaisesRegex(ValueError, 'iPhone and iPad'):
            PACKAGE.verify_native_display_configuration({'UIDeviceFamily': [1], 'UILaunchScreen': {}})

    def test_old_installer_cannot_be_relabelled_as_the_new_official_version(self):
        info = self.guest.parent / 'Info.plist'
        info.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.5.2',
                                        'SIEmbeddedInstallerRevision': 'old'}))
        with patch.dict('os.environ', SI_INSTALLER_VERSION='2.0.1', SI_INSTALLER_REVISION='pinned'):
            with self.assertRaisesRegex(ValueError, 'pinned official version'):
                PACKAGE.verify_desktop_components(self.app)
            info.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '2.0.1',
                                            'SIEmbeddedInstallerRevision': 'pinned'}))
            self.assertTrue(PACKAGE.verify_desktop_components(self.app)['selfRefreshSourceGuardVerified'])

    def test_old_hosted_loader_cannot_be_relabelled_as_fixed(self):
        self.bootstrap.write_bytes(b'Bootstrap\0Frameworks/TweakLoader.dylib\0')
        with self.assertRaisesRegex(ValueError, 'old hosted-process loader'):
            PACKAGE.verify_release(self.app)

    def test_picker_hooks_must_be_in_the_containing_app(self):
        misplaced = self.app / 'PlugIns/LiveProcess.appex/Frameworks/TweakLoader.dylib'
        misplaced.parent.mkdir(parents=True)
        self.picker.rename(misplaced)
        with self.assertRaisesRegex(ValueError, 'LiveContainer Files runtime'):
            PACKAGE.verify_release(self.app)

    def test_old_picker_and_runtime_cannot_claim_host_presentation_or_nightly_helpers(self):
        self.host.write_bytes(b'Search Open Tabs\0Storage & Recovery\0')
        with self.assertRaisesRegex(ValueError, 'host-owned IPA picker'):
            PACKAGE.verify_release(self.app)
        self.host.write_bytes(b'Search Open Tabs\0Storage & Recovery\0TahoeInstallerPickerServer\0')
        self.bootstrap.write_bytes(b'../../Frameworks/TweakLoader.dylib\0SideInstaller Files runtime:\0')
        with self.assertRaisesRegex(ValueError, 'nightly'):
            PACKAGE.verify_release(self.app)

    def test_missing_file_access_identity_hook_is_rejected(self):
        self.picker.write_bytes(b'Generic tweak library')
        with self.assertRaisesRegex(ValueError, 'file-access identity hook'):
            PACKAGE.verify_release(self.app)

    def test_old_framework_cannot_be_relabelled_using_current_metadata(self):
        (self.app / 'Info.plist').write_text('Current version and source revision')
        self.host.write_bytes(b'Old desktop and old browser')
        with self.assertRaisesRegex(ValueError, 'legacy renderer'):
            PACKAGE.verify_desktop_components(self.app)

    def test_missing_ui_capability_is_rejected(self):
        self.host.write_bytes(b'Storage & Recovery')
        with self.assertRaises(ValueError):
            PACKAGE.verify_desktop_components(self.app)

    def test_old_installer_cannot_reintroduce_self_refresh_rollback(self):
        self.guest.write_bytes(b'Legacy refresh installer')
        with self.assertRaisesRegex(ValueError, 'self-refresh source guard'):
            PACKAGE.verify_desktop_components(self.app)

    def test_generic_layout_stays_compatible_but_release_requires_guarded_binaries(self):
        self.assertTrue(PACKAGE.verify_release(self.app)['selfRefreshSourceGuardVerified'])
        self.guest.write_bytes(struct.pack('<IIII', 0xfeedfacf, 0x100000c, 0, 6))
        self.assertTrue(PACKAGE.verify(self.app)['nativeRefreshIntent'])
        with self.assertRaisesRegex(ValueError, 'self-refresh source guard'):
            PACKAGE.verify_release(self.app)


if __name__ == '__main__':
    unittest.main()
