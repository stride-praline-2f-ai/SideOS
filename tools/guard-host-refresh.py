#!/usr/bin/env python3
"""Add a fail-closed SideOS self-refresh check to the pinned installer source.

Run after host/JIT/FFI preparation, before the guest cache key is evaluated. Only
the installer's source changes; the modern host renderer remains unchanged.
"""
import argparse
from pathlib import Path
import shutil

SOURCE = Path(__file__).resolve().parents[1] / 'embedded/refresh/RefreshSourcePolicy.swift'
ANCHOR = '''    func refreshInstalledApp(named name: String, ipaPath: String, expectedEmbeddedHostID: String? = nil) async throws {
        guard let session = signSession else { throw EngineError.message(L("Not signed in.")) }
'''
GUARD = '''        #if SIDEINSTALLER_EMBEDDED
        // Refresh must never reinstall a different SideOS desktop from an old
        // cached IPA. Normal explicit Install remains the version-change path.
        let refreshIPA = URL(fileURLWithPath: ipaPath)
        if let candidate = IPALibrary.appInfo(at: refreshIPA),
           ProfileMatcher.installed(candidate.bundleID, isBuiltFrom: EmbeddedSigningIdentity.baseID, teamID: nil) {
            let host = try EmbeddedSigningIdentity.host()
            guard ProfileMatcher.installed(host.id, isBuiltFrom: candidate.bundleID, teamID: host.team) else {
                throw EngineError.message("Refresh stopped: this SideOS IPA belongs to a different app identity. Nothing was installed.")
            }
            guard SideOSRefreshSourcePolicy.permits(
                installed: host.bundle.object(forInfoDictionaryKey: "SIEmbeddedSourceRevision") as? String,
                archived: IPALibrary.embeddedRevision(at: refreshIPA)) else {
                throw EngineError.message("Refresh stopped to preserve the installed SideOS desktop. The IPA in the library belongs to a different or unknown source build. Import this installed build's original IPA to refresh it. To deliberately change versions, use Install. Nothing was installed.")
            }
        }
        #endif
'''


def apply(engine):
    engine = Path(engine)
    path = engine / 'ios-app/Engine.swift'
    original = path.read_text()
    if original.count(ANCHOR) != 1 or 'SideOSRefreshSourcePolicy' in original:
        raise ValueError('Pinned refresh anchor changed or the guard was already applied; refusing an unverified patch.')
    target = engine / 'ios-app/SideOSRefreshSourcePolicy.swift'
    if target.exists():
        raise ValueError('Unexpected existing refresh policy source; use a fresh engine checkout.')
    path.write_text(original.replace(ANCHOR, ANCHOR + GUARD, 1))
    shutil.copyfile(SOURCE, target)
    print('SideOS self-refresh now requires the running host source revision before signing or installing.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine', type=Path)
    apply(parser.parse_args().engine)
