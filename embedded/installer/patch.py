#!/usr/bin/env python3
"""Add the SideInstaller home dashboard to the pinned installer source."""
from pathlib import Path
import argparse
import shutil


def replace(path, old, new):
    source = path.read_text()
    if source.count(old) != 1:
        raise ValueError(f'Installer UI anchor changed: {path.name}: {old[:70]!r}')
    path.write_text(source.replace(old, new, 1))


def apply(engine):
    engine = Path(engine)
    ios = engine / 'ios-app'
    if (ios / 'SideInstallerHomeView.swift').exists():
        raise ValueError('Use a fresh pinned engine; the installer dashboard is already present.')
    root = ios / 'RootView.swift'
    replace(root, 'case install, tools, about', 'case home, install, tools, about')
    # Pre-v2 roots used per-page background enums; v2 has one themed background.
    if 'case .install: .bright' in root.read_text():
        replace(root, 'case .install: .bright', 'case .home, .install: .bright')
    replace(root, '@State private var page: Page = .install', '@State private var page: Page = .home')
    replace(root, '            ContentView()\n',
            '            SideInstallerHomeView(entitlements: entitlementsManager, install: { page = .install }, tools: { page = .tools })\n'
            '                .tabItem { Label(L("Home"), systemImage: "house") }\n'
            '                .tag(Page.home)\n'
            '            ContentView()\n')
    target = ios / 'Engine.swift'
    anchor = '    @MainActor\n    func sideloadedAppInventory() async throws -> (apps: [[String: Any]], profiles: [Data]) {'
    replace(target, anchor,
            '    @MainActor\n'
            '    func homeInstalledApps() async throws -> [[String: Any]] {\n'
            '        try await ensurePairingConnection()\n'
            '        return try await onDeviceQueue { try self.connection.installedAppPlists() }\n'
            '    }\n\n' + anchor)
    replace(target, '        log("\\(name) refreshed — its seven days start again now.")',
            '        do {\n'
            '            try SideInstallerRefreshHistory.shared.record(device: deviceUDID, app: Bundle(path: signed)?.bundleIdentifier)\n'
            '        } catch { log("Refresh completed, but its history could not be saved: \\(error.localizedDescription)") }\n'
            '        log("\\(name) refreshed — its seven days start again now.")')
    source = Path(__file__).resolve().parent
    shutil.copyfile(Path(__file__).resolve().parent.parent / 'tahoe/HostPickerHandoff.swift', ios / 'SideOSHostPickerHandoff.swift')
    patch_ipa_pickers(ios)
    for name in ('HomeData', 'HomeModel', 'HomeView', 'IPAPicker'):
        shutil.copyfile(source / (name + '.swift'), ios / ('SideInstaller' + name + '.swift'))
    print('SideInstaller home, installed-app inventory and success-only refresh history added.')


def patch_ipa_pickers(ios):
    # All IPA entry points use the same UIKit/asCopy picker and wait for its
    # dismissal. Pairing-file filters and the engine's IPA validation stay intact.
    replace(ios / 'Engine.swift',
            '    private static func discardInboxCopy(_ url: URL) {',
            '    static func discardInboxCopy(_ url: URL) {\n'
            '        if let directory = TahoeHostPickerHandoff.stagedDirectory(for: url,\n'
            '            home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {\n'
            '            try? FileManager.default.removeItem(at: url)\n'
            '            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {\n'
            '                try? FileManager.default.removeItem(at: directory)\n'
            '            }\n'
            '            return\n'
            '        }')
    replace(ios / 'ContentView.swift',
            '            .sheet(isPresented: $showImporter) {\n'
            '                FileImporterRepresentableView(allowedContentTypes: [.ipa]) { urls in\n'
            '                    guard let url = urls.first else { return }   // empty means cancelled\n'
            '                    Task { await engine.importCustomIPA(from: url) }\n'
            '                }\n'
            '                .ignoresSafeArea()\n'
            '            }',
            '            .sideInstallerIPAImporter(isPresented: $showImporter) { url in\n'
            '                Task { await engine.importCustomIPA(from: url) }\n'
            '            }')
    repair = ios / 'EmbeddedLiveContainer.swift'
    replace(repair,
            '            .fileImporter(isPresented: $pickingIPA, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { result in\n'
            '                switch result {\n'
            '                case .success(let url):',
            '            .sideInstallerIPAImporter(isPresented: $pickingIPA) { url in')
    replace(repair,
            '            .sideInstallerIPAImporter(isPresented: $pickingIPA) { url in\n'
            '                    start {',
            '            .sideInstallerIPAImporter(isPresented: $pickingIPA) { url in\n'
            '                    start {\n'
            '                        defer { Engine.discardInboxCopy(url) }')
    replace(repair,
            '                case .failure(let error): message = error.localizedDescription\n'
            '                }\n'
            '            }\n'
            '            .confirmationDialog("Repair LiveContainer signing?",',
            '            }\n'
            '            .confirmationDialog("Repair LiveContainer signing?",')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine', type=Path)
    apply(parser.parse_args().engine)
