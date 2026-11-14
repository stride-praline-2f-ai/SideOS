# Browser isolation review — 7 November 2026

## Finding and boundary

The embedded SideOS browser is **not a safe boundary against malicious native
LiveContainer guests**. WebKit protects websites from one another, and Private
mode avoids persistent browser storage; neither prevents native code running
with the host's authority from attacking host resources.

The pinned upstream README explicitly says: “Guest app containers are not
sandboxed. This means one guest app can access other guest apps' data.” Its
classic path loads guest code with `dlopen` into its process. LiveProcess adds
a separate extension process and scoped bookmarks, but still has the host's
shared app groups and 128 shared keychain groups. Userland keychain/path hooks
are compatibility mechanisms rather than a kernel-enforced trust boundary.
The optional full-Documents bookmark additionally exposes desktop metadata
and downloads. These paths do not establish complete cookie isolation.

Existing positives: the browser uses WebKit stores for profiles, does not bypass
TLS trust challenges, restricts native ChatGPT messages by origin/frame/webview,
and excludes cookies/credentials from workspace backups and diagnostics.
These are useful controls within their scope, not proof of native-app isolation.

## Independent browser implementation

`browser-app/project.yml` defines a separately **installed** iOS application,
`com.aault.sideos.browser`, and a synthetic probe. The browser target imports no
LiveContainer runtime, guest loader, SideInstaller or app extensions. Changing
a hosted guest's bundle ID would not create this isolation.

- Browser cookie/profile data live in this app's own private container.
- No app-group entitlement; no shared or wildcard keychain entitlement.
- `get-task-allow` is explicitly false. No JIT or dynamic guest loading.
- Before creating any browser model/WebView, the running process's signed
  entitlements are inspected. Unknown inspection, host identity, sharing,
  debugging/JIT/sandbox-bypass flags, file sharing or weakened ATS block sessions.
- HTTPS-only navigation, normal system TLS validation, Web Inspector disabled,
  no page-to-native data bridge, and no cookie/session export to SideOS.
- Personal and Work persist inside this separate app; Private uses an in-memory
  store. Search suggestions and automatic clipboard reads are absent.
- Incoming URL handoffs contain only a website URL and require confirmation.
  Callback/data-export parameters are rejected. Existing SideOS cookies are not
  migrated; websites require a new sign-in.

The isolation property relies on iOS enforcing the separately signed app's
sandbox and code-signing rules. Its window is managed by iPadOS/Stage Manager,
not rendered as a LiveContainer guest window. There is no generally available
public iOS API for embedding another arbitrary installed app's complete UI in
our desktop while preserving a separate app sandbox.

### Signing/update authority is part of the boundary

An installer holding this browser's signing credentials and installation access
can replace its code while keeping its app identity. Same-team signed updates
can retain its private data. A malicious replacement can remove a runtime gate.
**Keep this browser's signing identity outside SideOS. For the stronger threat
model involving malicious hosted software that can steal SideInstaller's
credentials, sign the browser with a separate Apple ID/team whose keys and
password are never placed in SideOS/LiveContainer/SideInstaller.**

Install the browser as a real app with a trusted external signer. Do not import
it into LiveContainer. Preserve the requested non-debug signature and remove
extra shared/wildcard groups. If a signer automatically adds debug access or
groups, the browser intentionally stays blocked. The unsigned build's template
is not proof of the final signature; the on-device check examines that signature.
The probe can be imported into LiveContainer, so it needs no additional installed
app slot. The real browser needs its own slot/App ID.

See the [external signing guide and tested minimal-entitlements helper](browser-signing.md).
The inspected default iLoader path copies profile entitlements; do not assume its
normal output preserves the browser's hardened template.

The signature check is defense in depth, not a trusted visual attestation inside
a malicious host: native code in a host can fake its own UI and userland calls.
Open the real browser from its iPadOS icon/app switcher. The kernel boundary of
the actual installed app is what protects its existing data.

## Device test procedure

No finite test establishes “100% secure against every threat.” The probe is
designed to falsify isolation with synthetic data and to distinguish a denied
access attempt from a broken test. A successful negative result covers only the
tested paths on that device/signature/runtime.

1. Install and launch SideOSBrowser as a separate app, using the signing identity
   described above. Confirm its signature gate allows sessions. Use no real
   accounts for the first test.
2. Open the shield → **Create Synthetic Test Canaries**. It creates 256-bit random
   data in a protected file, an own-group keychain item, and HttpOnly/Secure
   Personal/Work cookies on reserved `isolation.sideos.invalid`. No network server
   or real login credentials are used. Browser-side positive reads must succeed.
3. Keep that browser open beside SideOS. Import SideOSIsolationProbe IPA into
   LiveContainer and launch it, initially with custom tweaks disabled.
4. Copy the challenge JSON from the real browser and paste it into the probe.
   It contains the challenge name, file path, own keychain group and PID, not
   the random secret. Run **Canary Access Attempts**.
5. The probe tries a read-only POSIX open of only that named canary file, a
   direct-framework keychain query scoped to only the synthetic service/account,
   cookie lookup for only that reserved canary name/domain, and a task-port request
   without reading process memory. It checks its own file/cookie/task controls.
   It makes no network requests and exports no real cookie values or memory.
6. Paste its report into the browser's shield → **Check Report**. The browser
   checks that this is its current unexpired challenge from another process and
   rechecks its positive controls. File ENOENT or keychain item-not-found alone
   is **inconclusive**, rather than proof of a sandbox denial. Read access, a
   matching cookie, keychain success or a task port is an **isolation failure**.
7. Repeat with windowed and classic launch modes; with SideInstaller, JIT helper
   and another guest concurrently active; after minimize/resume, app restart,
   device reboot, re-signing and OS/runtime updates. Separately verify the actual
   JIT provider cannot attach to the non-debug browser; the probe's direct
   `task_for_pid` test does not cover every paired-device debugger protocol.
8. Remove test canaries afterward. Never test by trying to steal real sessions.

If a check fails, do not add shared groups/debug permissions to make it pass.
Investigate the signature, deployment and runtime with an independent reviewer.
Previously exposed embedded-browser sessions are not retroactively protected;
revoke/sign out of those sessions before relying on the new sign-in boundary.

## Limits and evidence

Local policy tests cover shared/wildcard groups, wrong process identity,
debugging/JIT flags, HTTPS-only handoff, live challenge limits and failure versus
inconclusive outcomes. Package tests reject hosted dylibs, wrong app/platform
identity, published files and host runtime/extension contamination. Native builds
check Apple SDK compilation and archive structure. None of these runs a physical
iPad or proves the behavior of its eventual re-signed apps.

Device concurrency tests and an independent adversarial review remain required.
An OS/WebKit exploit, compromised device, malicious signer/update authority,
untrusted full-access keyboard, phishing, manually exported secrets or an
installed interception root/VPN are not eliminated by changing a bundle ID.
Safari or another reputable App Store browser has a more mature security review
and distribution chain than this new companion app.

Sources:

- [Pinned LiveContainer README and limitations](https://github.com/LiveContainer/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/README.md)
- [Pinned extension entitlements](https://github.com/LiveContainer/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveProcess/LiveProcess.entitlements)
- [Pinned guest bookmarks](https://github.com/LiveContainer/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/MultitaskSupport/AppSceneViewController.m)
- [Pinned guest keychain hooks](https://github.com/LiveContainer/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LiveContainer/Tweaks/SecItem.m)
- [WebKit website-data-store API](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebsiteDataStore.h)
- [Apple Platform Security: app security](https://support.apple.com/guide/security/app-security-overview-sec35dd877d0/web)
