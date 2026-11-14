import SwiftUI

struct TahoeArrangement: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var snapshot: TahoeSavedWorkspace
    var date = Date()
}
@MainActor final class TahoeArrangements: ObservableObject {
    static let shared = TahoeArrangements()
    @Published private(set) var items: [TahoeArrangement] = []
    private var revision: UInt64 = 0
    init() { items = (try? TahoeStorage.read("arrangements.json", as: [TahoeArrangement].self)) ?? [] }
    func save(_ title: String, snapshot: TahoeSavedWorkspace) { items.insert(TahoeArrangement(title: String(title.prefix(100)), snapshot: snapshot), at: 0); persist() }
    func remove(_ id: UUID) { items.removeAll { $0.id == id }; persist() }
    private func persist() {
        revision &+= 1; let revision = revision, snapshot = items
        Task { do { try await TahoeStorageWriter.shared.write(snapshot, to: "arrangements.json", revision: revision) } catch { TahoeWorkspace.shared.error = error.localizedDescription } }
    }
}
struct TahoeCommand: Identifiable {
    var id: String { title }
    var title: String
    var shortcut = ""
    var enabled = true
    var action: () -> Void
}

struct TahoeWorkspaceTools: View {
    @ObservedObject var workspace: TahoeWorkspace
    @ObservedObject private var arrangements = TahoeArrangements.shared
    @ObservedObject private var activity = TahoeActivityCenter.shared
    @ObservedObject private var downloads = TahoeDownloads.shared
    @State private var query = ""
    @AppStorage("SideOSScratchpad.v1") private var scratchpad = ""
    @State private var calculator = TahoeCalculator()
    @Environment(\.tahoeTrafficInset) private var trafficInset
    private let sections = ["Actions", "Layouts", "Activity", "Security", "Help", "Scratchpad", "Calculator", "Agenda"]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(TahoeStrings.ui("Workspace Tools")).font(.headline); Spacer()
                Picker(TahoeStrings.ui("Section"), selection: $workspace.toolsSection) { ForEach(sections, id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 220)
            }.padding(14).padding(.leading, trafficInset).background(TahoeDesign.window).tahoeWindowDragRegion()
            Divider()
            Group {
                switch workspace.toolsSection {
                case "Layouts": layouts
                case "Activity": jobs
                case "Help": help
                case "Security": TahoeBrowserSafetyGuide()
                case "Scratchpad": scratch
                case "Calculator": calculatorView
                case "Agenda": TahoeAgenda()
                default: actions
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(TahoeDesign.content)
    }
    private var actions: some View {
        VStack {
            TahoeSearchField(title: "Find a command", text: $query)
            List(workspace.commands.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { command in
                Button { command.action() } label: {
                    HStack { Text(command.title); Spacer(); Text(command.shortcut).foregroundStyle(.secondary) }.contentShape(Rectangle())
                }.disabled(!command.enabled)
            }.listStyle(.plain)
        }.padding(16)
    }
    private var layouts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(TahoeStrings.ui("Saved Arrangements")).font(.title3.bold())
                Text(TahoeStrings.ui("Save window geometry and eligible web addresses. Private pages and running native processes are excluded. Opening a layout adds its windows without closing your current work.")).font(.callout).foregroundStyle(.secondary)
                Button(TahoeStrings.ui("Save Current Arrangement…")) {
                    TahoeDialogCoordinator.shared.dialog = TahoeDialog(title: "Save Arrangement", message: "Choose a name for this window layout.", primary: "Save", initialText: "My Workspace", validate: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, accept: { value in
                        if let value { arrangements.save(value, snapshot: workspace.makeSnapshot()) }
                    })
                }.buttonStyle(TahoeControlStyle())
                ForEach(arrangements.items) { item in
                    HStack {
                        VStack(alignment: .leading) { Text(item.title).fontWeight(.medium); Text("\(item.snapshot.windows.count) windows · \(item.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button(TahoeStrings.ui("Open")) { workspace.openArrangement(item) }.buttonStyle(TahoeControlStyle())
                        Button(role: .destructive) { arrangements.remove(item.id) } label: { Image(systemName: "trash") }.accessibilityLabel("Delete \(item.title)")
                    }.padding(12).background(TahoeDesign.group, in: RoundedRectangle(cornerRadius: 10))
                }
                Text(TahoeStrings.ui("Spaces")).font(.title3.bold())
                ForEach(0..<workspace.state.spaceCount, id: \.self) { space in
                    HStack {
                        Button(workspace.spaceName(space)) { workspace.state.switchSpace(space) }
                        Spacer()
                        Button(TahoeStrings.ui("Rename…")) { workspace.renameSpace(space) }
                        Menu("Wallpaper") {
                            ForEach(["Default", "coast", "dawn", "graphite", "custom"], id: \.self) { value in
                                Button(value.capitalized) {
                                    var choices = TahoePreferences.shared.value.spaceWallpapers ?? [:]
                                    choices[String(space)] = value == "Default" ? nil : value
                                    TahoePreferences.shared.value.spaceWallpapers = choices
                                }
                            }
                        }
                    }.padding(8)
                }
            }.padding(20)
        }
    }
    private var jobs: some View {
        VStack {
            HStack { Text(TahoeStrings.ui("App-owned operations")).font(.headline); Spacer(); Button(TahoeStrings.ui("Clear Finished")) { activity.clearFinished() } }.padding()
            List {
                ForEach(activity.jobs) { job in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(job.title).fontWeight(.medium)
                            Text("\(job.owner) · \(job.detail)").font(.caption).foregroundStyle(.secondary)
                            if let progress = job.progress { ProgressView(value: progress) }
                        }
                        Spacer()
                        if job.cancellable { Button(TahoeStrings.ui("Cancel")) { activity.cancel(job.id) } }
                        else { Text(job.state).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                ForEach(downloads.items) { item in
                    HStack { Text(item.name); Spacer(); Text(item.status).font(.caption).foregroundStyle(.secondary) }
                }
            }.listStyle(.plain)
            Text(TahoeStrings.ui("Guest launches, file operations and downloads are shown here. Installation and refresh details remain available in Management.")).font(.caption).foregroundStyle(.secondary).padding()
        }
    }
    private var scratch: some View {
        VStack(alignment: .leading) {
            HStack { Text(TahoeStrings.ui("Offline Scratchpad")).font(.headline); Spacer(); ShareLink(item: scratchpad) { Label(TahoeStrings.ui("Export"), systemImage: "square.and.arrow.up") } }
            Text(TahoeStrings.ui("Saved locally on this iPad. This is separate from iCloud Notes and ChatGPT.")).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $scratchpad).font(.body).scrollContentBackground(.hidden)
        }.padding(16)
    }
    private var calculatorView: some View {
        VStack(spacing: 12) {
            Text(TahoeStrings.ui("Offline Calculator")).font(.headline)
            Text(calculator.display).font(.largeTitle.monospacedDigit()).frame(maxWidth: .infinity, alignment: .trailing).textSelection(.enabled).padding()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                ForEach(["AC", "+/−", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "0", ".", "=", "="].enumerated().map { index, key in (id: index, key: key) }, id: \.id) { cell in
                    Button(cell.key) { calculator.press(cell.key) }.buttonStyle(TahoeControlStyle()).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            Text(TahoeStrings.ui("Desmos remains available as a separate web app.")).font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: 440)
    }
    private var help: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(TahoeStrings.ui("Getting Started")).font(.title2.bold())
                TahoeUpstreamCredits()
                Text(TahoeStrings.ui("Open apps from the Dock or Applications. Click an app's Dock icon to choose among its windows. Hold a browser or chat tab and drag it onto the desktop to detach it, or into a compatible browser bar to merge it."))
                Text(TahoeStrings.ui("On chatgpt.com, use Chats to reveal the conversation row. Open another chat from the sidebar without replacing your current one; its options menu offers split view. The divider resizes two real chat panes."))
                Text(TahoeStrings.ui("Use Window → Arrange Window for halves, thirds and quarters where the screen has room. Saved Arrangements reopen a task layout. Show Desktop lets you work with icons without closing windows."))
                Text("LiveContainer and SideInstaller").font(.headline)
                Text("Open LiveContainer from the Dock for Apps, Sources, Tweaks and Settings in its own window. Drag either bottom corner to resize. In fullscreen, hover at top-left for traffic lights, or tap the bottom-right glass ellipsis to minimise, restore or close.")
                Text("Sign SideOS using your own account and trusted signing tool. Install a newer signed IPA over the same identity to update; Refresh renews the current build and refuses a different source. Never share certificates, passwords or pairing files. Helper-process/RAM-donor apps currently require upstream Classic Mode.")
                Text("Appearance and browser identity").font(.headline)
                Text("Settings offers Native Clear/Regular Dock glass, Compact density and touch feedback. Other panels/menus default to opaque. The default browser identity is macOS Enhanced Spoofing; switch to iPadOS Original if a website fails. The app remains iOS/iPadOS software.")
                Text("Privacy and help").font(.headline)
                Text("Hosted apps and the embedded browser are not guaranteed isolated from a malicious guest. Use trusted apps and a separate system browser for sensitive logins. Consult the repository install guide and troubleshooting before reporting a redacted issue. Include About diagnostics, reproduction steps, device and OS; remove personal data.")
                Link("User guide and troubleshooting", destination: URL(string: "https://github.com/stride-praline-2f-ai/SideOS/blob/main/docs/user-guide.md")!)
                Text(TahoeStrings.ui("Keyboard Shortcuts")).font(.headline)
                Text("⌘N New Browser Window\n⌘T New Browser Tab\n⇧⌘T Reopen Closed\n⌘L Address\n⌘F Find on Page\n⌘W Close Browser Tab/Window\n⌥⌘W Close Chat\n⇧⌘W Close Window\n⌘M Minimize\n⌘` Cycle Windows\n⌃⌘F Fullscreen\n⌘Space Search\n⇧⌘P Commands\nEscape Dismiss").font(.body.monospaced())
                Text(TahoeStrings.ui("Browser pages restore automatically. Eligible background pages may sleep to control memory; select one to wake it. Private pages are never saved. Use About → Diagnostics to identify your build."))
                Button(TahoeStrings.ui("Diagnostics")) { TahoeReleaseInfo.showDiagnostics() }.buttonStyle(TahoeControlStyle())
                Text(TahoeReleaseInfo.label).font(.caption.monospaced()).textSelection(.enabled)
            }.padding(24)
        }
    }
}
