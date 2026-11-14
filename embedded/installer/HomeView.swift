import SwiftUI

struct SideInstallerHomeView: View {
    @ObservedObject var entitlements: EntitlementsManager
    let install: () -> Void
    let tools: () -> Void
    @Environment(Engine.self) private var engine
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = SideInstallerHomeModel()
    @ObservedObject private var history = SideInstallerRefreshHistory.shared
    @State private var importing = false
    @State private var filter = "sideloaded"
    @State private var query = ""
    private var visibleApps: [SideInstallerDeviceApp] {
        model.apps.filter { (filter == "all" || $0.isSideloaded) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)) }
    }
    private var counts: [String: Int] { SideInstallerAppIDAttribution.counts(apps: model.apps, registered: entitlements.apps.map(\.identifier)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                VStack(alignment: .leading, spacing: 8) {
                    Label("Use trusted apps only", systemImage: "exclamationmark.shield.fill").font(.headline).foregroundStyle(.orange)
                    Text("SideInstaller runs inside SideOS. Malicious hosted apps are not securely isolated from signing credentials, pairing records or browser sessions. Only install and run IPAs you trust; do not treat this host as secure storage.").font(.callout)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                installCard
                summary
                deviceSection
            }.padding(20).frame(maxWidth: 980).frame(maxWidth: .infinity)
        }
        .background(AppBackground())
        .task(id: accounts.revision) { await model.reload(); entitlements.autoLoad() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { history.reload() } }
        .sideInstallerIPAImporter(isPresented: $importing) { url in
            Task {
                await engine.importCustomIPA(from: url)
                guard engine.lastError == nil else { return }
                engine.installSource = .custom
                install()
            }
        }
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack { introduction.fixedSize(horizontal: true, vertical: false); Spacer(); checkButton.fixedSize() }
            VStack(alignment: .leading, spacing: 12) { introduction; checkButton }
        }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SideInstaller").font(.largeTitle.bold())
            Link("SideInstaller by FrizzleM", destination: URL(string: "https://github.com/FrizzleM/SideInstaller")!)
                .font(.headline).tint(Theme.accent)
            Text("Install and refresh your apps").foregroundStyle(.secondary)
        }
    }
    private var checkButton: some View {
        Button { Task { await model.reload(); entitlements.loadApps() } } label: {
            Label(model.loading ? "Checking…" : "Check Device", systemImage: "arrow.clockwise")
        }.modifier(SideInstallerHomeAction()).disabled(model.loading || entitlements.isBusy || engine.isRunning || AppRefreshService.shared.isRefreshing)
    }
    private var installCard: some View {
        HStack(spacing: 18) {
            Image(systemName: "square.and.arrow.down.fill").font(.system(size: 34)).foregroundStyle(Theme.accent).frame(width: 58)
            VStack(alignment: .leading, spacing: 6) {
                Text("Install an IPA").font(.title2.bold())
                Text("Choose an IPA from Files, or open the existing guided installer.").font(.callout).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { installActions }
                    VStack(alignment: .leading, spacing: 8) { installActions }
                }.modifier(SideInstallerHomeGlassGroup())
                    .disabled(importing || engine.isImportingIPA || engine.isRunning || AppRefreshService.shared.isRefreshing)
            }
            Spacer(minLength: 0)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20))
    }
    @ViewBuilder private var installActions: some View {
        Button(engine.isImportingIPA || importing ? "Importing IPA…" : "Choose IPA…") { importing = true }.modifier(SideInstallerHomeAction(primary: true))
        Button("Open Installer", action: install).modifier(SideInstallerHomeAction())
    }
    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { appIDTile; installedTile; refreshedTile }
            VStack(spacing: 12) { appIDTile; installedTile; refreshedTile }
        }
    }
    private var appIDTile: some View {
        metric("Registered App IDs", value: entitlements.hasLoaded ? "\(Set(entitlements.apps.map(\.identifier)).count)" : "—", detail: entitlements.teamSummary ?? "Sign in to check your account", symbol: "number.square")
    }
    private var installedTile: some View {
        metric("Installed Apps", value: model.hasLoaded ? "\(model.apps.count)" : "—", detail: model.hasLoaded ? "\(model.apps.filter(\.isSideloaded).count) sideloaded" : "Connect this device to load apps", symbol: "square.grid.2x2")
    }
    private var refreshedTile: some View {
        let latest = model.deviceID.flatMap { history.records.latest(device: $0) }
        return metric("Last Successful Refresh", value: latest?.formatted(date: .abbreviated, time: .shortened) ?? "Not recorded", detail: "Tracks successful SideInstaller refreshes. Earlier or external refreshes may not be recorded.", symbol: "clock.arrow.circlepath")
    }
    private func metric(_ title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).lineLimit(2)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
    }
    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("On This Device").font(.title2.bold()); Spacer()
                Button("Manage & Refresh Apps", action: tools).modifier(SideInstallerHomeAction())
            }
            Picker("Apps", selection: $filter) { Text("Sideloaded").tag("sideloaded"); Text("All Apps").tag("all") }.pickerStyle(.segmented)
            TextField("Search apps or bundle IDs", text: $query).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("App ID counts show related registrations on the selected Apple account, including extensions. Unused IDs may remain registered.").font(.caption).foregroundStyle(.secondary)
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let error = entitlements.lastError {
                Text("App IDs could not be checked: \(error)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if model.loading { ProgressView("Reading device…").frame(maxWidth: .infinity) }
            if model.hasLoaded && visibleApps.isEmpty { Text(query.isEmpty ? "No apps in this view." : "No matching apps.").foregroundStyle(.secondary).padding(.vertical, 20) }
            let assigned = counts
            LazyVStack(spacing: 1) {
                ForEach(visibleApps) { app in
                    SideInstallerHomeAppRow(app: app, appIDs: entitlements.hasLoaded ? assigned[app.id, default: 0] : nil,
                        refreshed: model.deviceID.flatMap { history.records.lastRefresh(device: $0, app: app.id) })
                }
            }.background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            if let checked = model.checkedAt {
                Text("Device checked \(checked.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Use the same native material as the host's touch controls without layering
/// glass underneath app lists or copying a private framework into the guest.
private struct SideInstallerHomeAction: ViewModifier {
    var primary = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !opaque {
            if primary { content.controlSize(.large).buttonStyle(.glassProminent) }
            else { content.controlSize(.large).buttonStyle(.glass) }
        } else {
            if primary { content.controlSize(.large).buttonStyle(.borderedProminent) }
            else { content.controlSize(.large).buttonStyle(.bordered) }
        }
    }
}

private struct SideInstallerHomeGlassGroup: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 8) { content } }
        else { content }
    }
}

private struct SideInstallerHomeAppRow: View {
    let app: SideInstallerDeviceApp
    let appIDs: Int?
    let refreshed: Date?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "app.fill").font(.title2).foregroundStyle(Theme.accent).frame(width: 36, height: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(app.name).font(.headline)
                    if app.increasedMemory {
                        Label("Memory+", systemImage: "memorychip").font(.caption.bold()).foregroundStyle(.green)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(.green.opacity(0.12), in: Capsule())
                            .accessibilityLabel("Increased Memory Limit enabled")
                    }
                }
                Text(app.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text(refreshed.map { "Last refreshed " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Last refresh not recorded")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(appIDs.map { "\($0) App ID\($0 == 1 ? "" : "s")" } ?? "App IDs —").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}
