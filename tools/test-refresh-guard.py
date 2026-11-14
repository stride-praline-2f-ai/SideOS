#!/usr/bin/env python3
"""Check the pinned source patch and execute the real injected signing gate."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('refresh_patch', ROOT / 'tools/guard-host-refresh.py')
PATCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCH)


class RefreshGuard(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        (self.root / 'ios-app').mkdir()
        self.engine = self.root / 'ios-app/Engine.swift'
        self.engine.write_text('class Engine {\n' + PATCH.ANCHOR + '        performSign()\n    }\n}\n')

    def tearDown(self):
        self.directory.cleanup()

    def test_patch_runs_before_signing_and_copies_the_exact_policy(self):
        PATCH.apply(self.root)
        source = self.engine.read_text()
        self.assertLess(source.index('SideOSRefreshSourcePolicy.permits'), source.index('performSign()'))
        self.assertEqual((self.root / 'ios-app/SideOSRefreshSourcePolicy.swift').read_bytes(), PATCH.SOURCE.read_bytes())

    def test_changed_anchor_and_repeated_application_fail_closed(self):
        self.engine.write_text('unexpected upstream source')
        with self.assertRaises(ValueError):
            PATCH.apply(self.root)
        self.assertFalse((self.root / 'ios-app/SideOSRefreshSourcePolicy.swift').exists())
        self.engine.write_text(PATCH.ANCHOR)
        PATCH.apply(self.root)
        before = self.engine.read_bytes()
        with self.assertRaises(ValueError):
            PATCH.apply(self.root)
        self.assertEqual(self.engine.read_bytes(), before)

    @unittest.skipUnless(shutil.which('swiftc'), 'Requires the Swift toolchain used by core CI')
    def test_real_injected_gate_preserves_other_apps_and_stops_old_self_ipa_before_signing(self):
        # The gate below is the actual injected code, compiled against small
        # boundary doubles. Signing and installation must never run on rejection.
        source = r'''
import Foundation
enum EngineError: Error { case message(String) }
struct HostBundle { func object(forInfoDictionaryKey key: String) -> Any? { Harness.installed } }
enum Harness {
    static let current = "a3ed60e1d198bcda092b84fccd327c40ff5e9195"
    static var installed: String? = current
    static var archived: String? = current
    static var candidate = "com.aault.livecontainer.sideinstaller"
    static var hostCalls = 0
    static var signing = 0
    static var installs = 0
}
enum IPALibrary {
    struct AppInfo { let bundleID: String }
    static func appInfo(at url: URL) -> AppInfo? { AppInfo(bundleID: Harness.candidate) }
    static func embeddedRevision(at url: URL) -> String? { Harness.archived }
}
enum ProfileMatcher {
    static func installed(_ bundleID: String, isBuiltFrom ipaBundleID: String, teamID: String?) -> Bool {
        if bundleID == ipaBundleID { return true }
        if let teamID, !teamID.isEmpty { return bundleID == "\(ipaBundleID).\(teamID)" }
        guard bundleID.hasPrefix(ipaBundleID + ".") else { return false }
        let suffix = bundleID.dropFirst(ipaBundleID.count + 1)
        return suffix.count == 10 && suffix.allSatisfy { $0.isUppercase || $0.isNumber }
    }
}
enum EmbeddedSigningIdentity {
    static let baseID = "com.aault.livecontainer.sideinstaller"
    static func host() throws -> (bundle: HostBundle, team: String, id: String) {
        Harness.hostCalls += 1
        return (HostBundle(), "A1B2C3D4E5", baseID + ".A1B2C3D4E5")
    }
}
func refresh() throws {
    let ipaPath = "/library/archived.ipa"
''' + PATCH.GUARD + r'''
    Harness.signing += 1; Harness.installs += 1
}
@main struct GateTests {
    static func main() throws {
        try refresh()
        precondition(Harness.signing == 1 && Harness.installs == 1)
        for archived: String? in [nil, "", "fd1681e3b4e75e0c877e21c57624c387ff18ada7"] {
            Harness.archived = archived
            do { try refresh(); preconditionFailure("Old or unknown self IPA was accepted") } catch { }
            precondition(Harness.signing == 1 && Harness.installs == 1)
        }
        Harness.archived = Harness.current; Harness.candidate += ".ZZZZZZZZZZ"
        do { try refresh(); preconditionFailure("Wrong signed app identity was accepted") } catch { }
        precondition(Harness.signing == 1 && Harness.installs == 1)
        Harness.candidate = "org.example.unrelated"; Harness.archived = nil
        let calls = Harness.hostCalls
        try refresh()
        precondition(Harness.hostCalls == calls && Harness.signing == 2 && Harness.installs == 2)
        print("Real refresh gate rejects old/unknown/wrong-identity self archives before signing and preserves other-app refresh")
    }
}
'''
        swift = self.root / 'GateTests.swift'
        swift.write_text(source)
        binary = self.root / 'gate-tests'
        subprocess.run(['swiftc', '-D', 'SIDEINSTALLER_EMBEDDED', str(PATCH.SOURCE), str(swift), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
