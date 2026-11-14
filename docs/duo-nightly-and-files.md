# Duo display, nightly runtime and native Files ownership

The runtime pin is the official 2026-11-08 nightly commit
`9d6ea09b05afa2c8fc537c372795a294db631311`. The release's actual build commit is
pinned, not its mutable nightly tag. Engine.lock, checkout and adaptation anchors
are checked together. This retains the source/identity refresh guard and one
unsigned SideOS IPA; no Simulator, preview or companion app build is added.

## Files

Earlier builds opened a document-picker remote view inside SideInstaller's
hosted remote app scene, but file rows remained untappable on the user's device.
The embedded IPA chooser now requests a UIKit document picker owned by the real
SideOS window. Its delegate keeps selected-file access until a background copy
finishes, then replies after modal dismissal. Only that IPA enters the existing
SideInstaller container. Home, Install and signing repair share this chooser;
standalone installer builds retain a local UIKit picker.

A private, per-launch channel is passed only to the built-in installer. Requests
contain UUIDs, a fixed choose/cancel operation and expiry, never an arbitrary host
path. Metadata is size bounded; host descriptors use openat/O_NOFOLLOW and
regular-file checks. Staging is descriptor relative, refuses replacement files,
and cleanup unlinks only known private imports. The guest still validates the
archive before replacing a valid import. Repair still checks identity/revision.
Darwin wakeups and a bounded foreground client wait keep this independent of
remote-view hit testing. Cancellation, reopening, stale replies and process exit
have explicit handling. Pending import records allow cleanup after restart.

## Native display layout

Full-display Duo support is selected by the **linked iOS SDK**, not by the
deployment target or launch-screen metadata. Apple's
[Duo preparation guidance](https://developer.apple.com/iphone-duo/prepare/)
describes iOS 26 SDK builds as centered with space around the window; the full
display requires the iOS 27.1+ SDK. The user's device runs iOS 27.2. Independent
inspection of all four owned UI/process binaries in Build 4 found SDK 26.5,
despite its corrected launch metadata and adaptive layout. That SDK restriction
was missed by the earlier display gate.

The device workflow now uses GitHub's standard `xcode-27` runner and selects
Xcode 27.2 (27.1 minimum), with no SDK 26 fallback. The
[runner image manifest](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
lists both SDKs. Packaging checks actual `LC_BUILD_VERSION` SDK records in the
main app, desktop framework, LiveProcess and embedded installer. An edited
`DTSDKName` cannot satisfy this gate. Cache toolchain fingerprints remain strict;
the new SDK requires a real rebuild of the native components.

No fixed hardware resolution is encoded. The desktop renders in actual UIWindow
points with native display scale. The inner display uses the same 30-point menu
bar, control sizes and floating-window defaults as iPad. The earlier phone-style
44-point chrome and automatic filled-window defaults apply only to the small
outer display. Menus retain their iPad headings on the inner display; the heading
row can scroll if needed. Windows, Dock and popovers fit the available canvas.
Safe areas protect hardware cutouts and wallpaper remains full bleed.

Automatic detection uses both UIKit and the hardware product family, so a phone
can retain inner-display detection when its traits or reported model are tablet
like. The explicit Duo profile also selects the iPad-style inner presentation.
About reports actual window, scene, screen, safe viewport and native pixel sizes.
Fold/unfold changes preserve preferred window geometry and existing user layouts.

Build 3 also declared a missing LaunchScreen storyboard and included fixed-size
launch images inherited from upstream. The host now declares a modern adaptive
`UILaunchScreen`, supports both device families and all orientations, and removes
the old launch-image entries. The packaging gate rejects missing/legacy launch
configuration. This metadata check alone did not establish full-display SDK
eligibility; the Mach-O SDK gate is now required as well. Physical-device testing
still needs to confirm the complete unfolded window and reserved areas.

## Helper processes and RAM donors

The pinned upstream code includes guest extension proxies, helper process
routing, RAM donor/JIT-helper support, and the background-task update. It
explicitly declines helper hooks in a hosted LiveProcess. SideOS therefore
points helper-enabled apps to the supported Classic Mode and management Apps
launch path, rather than advertising donor support for desktop guest windows.
Memory availability still depends on the app, its signed capabilities and iOS.
No new SideOS bundle IDs or separate donor IPA are introduced.

## Validation

Portable tests exercise bounded request/reply metadata, symlink/FIFO attacks,
protected writes/cleanup, cancellation, stale selection IDs, safe viewports and
fold/tile restoration. All adaptation anchors are applied to the exact nightly.
The release gate inspects compiled host-picker and guest logging markers and
nightly helper machinery, in addition to existing desktop and rollback guards.
Apple SDK compilation/package verification precedes promotion to main.
Physical Files selection and Duo display use still require an on-device check.

## Official SideInstaller update

The installer is based on official SideInstaller 2.0.1 (2026-11-12), commit
`50b2a0dea22d43659e2630e01daa9097145874cb`. `Installer.lock.json` pins this
separately from the LiveContainer engine. The build checks out that exact clean
source and applies the reviewed embedded compatibility patch, retaining the new
sign-in request isolation, private storage/logging changes, AltStore support,
ExtensionKit signing, setup flow and blue theme. SideOS keeps its Home dashboard,
refresh history, host picker and source/identity refresh guard.

The integration happens after host/JIT builds and before FFI/installer cache
evaluation. Thus the completed host/JIT binaries retain exact cache keys while
actual changed Rust and Swift sources invalidate their respective products.
Packaging checks the embedded installer version and source revision against the
lock, rather than relabelling an old installer as 2.0.1.
