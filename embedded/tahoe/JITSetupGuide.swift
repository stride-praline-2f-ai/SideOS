import SwiftUI

/// Tutorial over the existing coordinator. Reading a step never marks an
/// actual preparation or per-app JIT attach as successful.
struct TahoeJITSetupGuide: View {
    @EnvironmentObject private var workspace: TahoeWorkspace
    @ObservedObject private var jit = SIBuiltInJIT.shared
    @AppStorage("LCJITEnablerType", store: LCUtils.appGroupUserDefault) private var provider = 0
    @State private var controls = false
    @State private var expanded = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up built-in JIT").font(.title2.bold())
            Text("JIT lets some apps run code they generate while you use them. Most apps do not need it. SideInstaller should open without JIT. Use this guide only for an app whose instructions require JIT.").font(.callout)
            VStack(alignment: .leading, spacing: 10) {
                Text("Your current setup").font(.headline)
                status(provider == 7, "Built-in provider selected", "Provider not selected yet")
                status(jit.hasPairing, "Pairing record available", "Pairing record needed")
                status(jit.prepared, "Device prepared for this session", "Device not prepared yet")
                if jit.busy { ProgressView("Working — keep SideOS open") }
                Text(jit.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("These checks describe device setup. They do not confirm that a particular app has JIT.").font(.caption).foregroundStyle(.secondary)
            }.padding(14).background(TahoeDesign.group, in: RoundedRectangle(cornerRadius: 14))
            step(1, "Choose the built-in provider", "Tell SideOS which JIT method to use.") {
                Text("Tap the button below. You should then see “Built-in provider selected” above. This selects a method; it does not start JIT yet.")
                Button(provider == 7 ? "Built-in JIT selected" : "Use built-in JIT") { provider = 7 }.disabled(provider == 7 || jit.busy)
            }
            step(2, "Prepare the device connection", "Enable Developer Mode and connect LocalDevVPN.") {
                Text("1. Open your iPhone or iPad’s Settings → Privacy & Security → Developer Mode. Turn it on if required, restart when asked, then confirm it after restarting.")
                Text("2. Open the supported LocalDevVPN app and connect its device tunnel. A normal internet VPN does not replace it. If you do not have it, use the installation link in the official runtime guide below.")
                Button("Open LocalDevVPN") {
                    UIApplication.shared.open(URL(string: "localdevvpn://")!, options: [:]) { opened in
                        if !opened { Task { @MainActor in workspace.error = "LocalDevVPN could not be opened. Install the supported app using the official runtime guide, open it from the Home Screen and connect it, then return to SideOS." } }
                    }
                }
                Text("Check: LocalDevVPN says it is connected. If Developer Mode is missing, follow your signing tool’s device-setup instructions; SideOS cannot enable it for you.")
            }
            step(3, "Pair this device", "Create the record used by your own trusted device connection.") {
                Text("Open SideInstaller → Tools → Pairing. Start its pairing setup and follow its on-screen prompts, including any PIN or confirmation in iOS Settings. Keep SideOS open until it finishes, then return here.")
                Button("Open SideInstaller for pairing") { workspace.openInstaller() }
                Text("Check: the summary above says “Pairing record available”. SideOS shares the built-in SideInstaller record automatically; you do not need to export or send it anywhere.")
                DisclosureGroup("Already have a pairing file, or SideInstaller will not open?") {
                    Text("Open the controls below → Import pairing file… and choose a record created by your own trusted computer for this exact device. Another device’s record will not work. Never download someone else’s record or share yours.").padding(.top, 6)
                    Button("Open pairing controls") { controls = true }
                }
            }
            step(4, "Prepare the device", "Check connectivity and prepare Apple’s Developer Disk Image.") {
                Text("Open the controls below. If offered, tap “Use built-in SideInstaller pairing”. Then tap “Prepare device” (or “Check device again”). Keep SideOS in the foreground and wait for the result. The first download may take longer.")
                Button("Open preparation controls") { controls = true }
                Text("Check: “Device prepared for this session” appears above. If it fails, read the current status instead of repeatedly pressing Prepare. See the troubleshooting section below.")
            }
            step(5, "Launch the app that needs JIT", "Each running app needs its own JIT operation.") {
                Text("Open LiveContainer, open that app’s settings and enable its JIT option. Keep Classic/Compatibility Mode off for the built-in route, then launch the app from SideOS. Leave SideOS open while the operation finishes.")
                Button("Open LiveContainer") { workspace.showManagement = true }
                Text("Only if the app’s own instructions require a JIT Launch Script, select that trusted script in its settings. Leave “Force configured JIT script” off unless those instructions require it.")
                Text("Check: the JIT operation finishes without an error and the app’s JIT-dependent feature works. A prepared-device checkmark alone does not prove the app’s JIT is active.")
            }
            step(6, "Know when to repeat setup", "Pair once; prepare and enable JIT again when needed.") {
                Text("After closing an app, its next process needs a new JIT operation. After a restart, connection change, re-sign or expired session, reconnect LocalDevVPN and prepare again. Re-pair only when the record is invalid or belongs to another device.")
                Text("On iOS 26+, JIT does not replace LiveContainer’s required JIT-less signing setup. Helper/RAM-donor apps use the separate upstream Classic Mode route with an appropriate external provider; they are not supported by this built-in LiveProcess route.")
            }
            DisclosureGroup("Something went wrong? Start here") {
                VStack(alignment: .leading, spacing: 12) {
                    help("No pairing record", "Finish step 3, then reopen the controls and choose the built-in record. Import only your own correct-device file if needed.")
                    help("Connection refused or timed out", "Check Developer Mode, LocalDevVPN and the current connection. Keep SideOS open, close the guest and retry preparation once.")
                    help("Developer Disk Image download or mount failed", "Check the network and OS support. Only for this error, use preparation controls → Reset Developer Disk Image cache, then prepare again. Resetting does not create pairing or enable JIT.")
                    help("Device prepared, but app still fails", "Close and relaunch that app. Check its JIT setting, supported script and that Classic/Compatibility Mode is off. Confirm your signer kept LiveProcess, SIJITHelper, the app groups and get-task-allow.")
                    help("SideInstaller will not open", "Pairing-file import is still available in the controls above. Report your build/device/OS and a redacted error; never include pairing records, credentials or certificates.")
                }.padding(.top, 10)
            }
            Text("Only run trusted hosted apps. Signing credentials and pairing records are not isolated from malicious hosted code. Never attach the debugger to the SideOS UI process.").font(.caption).foregroundStyle(.orange)
            Link("Official runtime JIT guide and supported tools", destination: URL(string: "https://livecontainer.github.io/docs/guides/jit-support")!)
        }.buttonStyle(TahoeControlStyle())
        .onAppear { jit.refreshPairingSource() }
        .sheet(isPresented: $controls, onDismiss: { jit.refreshPairingSource() }) {
            NavigationStack {
                SIBuiltInJITSettings().toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { controls = false } }
                }
            }
        }
    }
    private func status(_ ready: Bool, _ yes: String, _ no: String) -> some View {
        Label(ready ? yes : no, systemImage: ready ? "checkmark.circle.fill" : "circle")
    }
    private func help(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(.secondary) }
    }
    private func step<Content: View>(_ number: Int, _ title: String, _ summary: String, @ViewBuilder content: () -> Content) -> some View {
        DisclosureGroup(isExpanded: Binding(get: { expanded == number }, set: { expanded = $0 ? number : 0 })) {
            VStack(alignment: .leading, spacing: 12) {
                content()
                if number < 6 { Button("Next step") { expanded = number + 1 } }
            }.font(.callout).padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 4) { Text("\(number). \(title)").font(.headline); Text(summary).font(.caption).foregroundStyle(.secondary) }
        }.padding(14).background(TahoeDesign.group, in: RoundedRectangle(cornerRadius: 14))
    }
}
