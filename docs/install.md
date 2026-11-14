# Install, sign and update SideOS

**Includes [SideInstaller by FrizzleM](https://github.com/FrizzleM/SideInstaller).**
See [all component credits](../CREDITS.md).

## Before installing

This is an unsigned sideloaded app, not an App Store download. Use your own Apple
account, signing certificate and supported signing tool. Never accept somebody
else's account, pairing file, certificate/private key or mobile provisioning
profile. Public builds use the experimental pre-release channel; read the known
issues and [release status](release-readiness.md) before installing.

The current device build uses Xcode/iOS SDK 27.2; Duo full-display eligibility
requires linking against SDK 27.1 or newer. iOS 26+ provides native Liquid Glass.
Earlier system support depends on upstream LiveContainer and the signer's
capabilities; a successful build does not establish every device is supported.
The Duo layout has user-reported device evidence; this is not a complete device
certification matrix.

## Install

1. Obtain an approved release from this repository's Releases page. For developer
   testing, use the matching successful **SideOS3 Device IPA** workflow artifact.
   Open the ZIP and locate its single `*-unsigned.ipa` file.
2. Check its source revision, build number and published SHA-256 against the
   release manifest. An Actions artifact alone is not a public release approval.
3. Sign the IPA with your own trusted tool (for example a supported desktop iLoader
   installation) preserving its extensions. Follow that tool's current setup and
   entitlement requirements; a generic web signer may not support LiveContainer.
4. Install it on your device. If iOS requests Developer Mode, device trust or
   pairing approval, follow Apple's on-device instructions and the signer's guide.
5. Open SideOS. Open **Help → Getting Started** and **About → Diagnostics** to
   confirm the installed build. Configure LiveContainer/JIT only if your apps need it.

Apple account limits and signing expiry depend on account type and Apple's
current rules. SideInstaller cannot bypass those limits. Keep the desktop signer
available as a recovery route and back up important data before changing builds.

## Update without losing your workspace

Use an explicitly signed installation of the new IPA with the same app identity.
Do not delete the installed app just to update it: deleting an app removes its
local data. Self-refresh intentionally refuses an older, different or unknown
SideOS source revision; refresh renews the existing build, not a version upgrade.
Confirm the new source/build in About after installation and fully close/reopen
SideOS if it was running during the update.

A first installation uses Golden Gate wallpaper, Compact desktop density, Native
Clear Dock glass, macOS Enhanced Spoofing for browser identity, and 0 transparency
for other panels/menus. Explicit saved choices remain in place after upgrades.

## Configure LiveContainer after the desktop opens

1. Tap **LiveContainer** in the Dock, then **Apps**. Use the plus button to import
   a trusted IPA. Long-press an installed app for its settings/container options.
2. Start with an ordinary non-JIT app. Guest signing uses the host's signing
   configuration where required; complete LiveContainer's certificate/setup
   prompts using your own material. An unsigned SideOS download is not a certificate.
3. For a JIT-dependent app, configure a provider that supports attaching by PID
   for hosted/multitasked apps. Follow the current [official JIT guide](https://livecontainer.github.io/docs/guides/jit-support)
   for your OS/provider; the pinned runtime identifies StikDebug as one supported
   PID-capable route. Keep pairing records on your own device/computer.
4. Apps using helper processes/RAM donors currently require Classic Mode in the
   app's LiveContainer settings. Open them through management; the desktop does
   not promise hosted-window support for those processes.
5. When a setup step differs from the guide, use the [upstream installation guide](https://livecontainer.github.io/docs/installation)
   and [FAQ](https://livecontainer.github.io/docs/faq) for the underlying runtime.
   Report SideOS-specific window/desktop issues in this repository, not as an
   assumed officially supported LiveContainer build.

SideInstaller Home is a separate window for installing/refreshing signed apps.
Its registered App ID count includes related extensions. A single combined IPA
can still need multiple registrations, and it does not bypass Apple's account
limits. Confirm the account and signing setup before deleting registrations.
