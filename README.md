> [!WARNING]
> **Do not store sensitive information in the embedded browser.** It is not sandboxed away from hosted LiveContainer apps. Malicious hosted apps may access cookies, signed-in sessions and saved browser data. Keep passwords, banking/payment details and confidential information in Safari or another trusted, separately sandboxed browser. Private mode does not remove this risk. Read [SECURITY.md](SECURITY.md).
> **Run trusted IPAs only.** The same trust limitation applies to signing credentials, pairing records and host-granted permissions. The embedded installer is not an isolated secure vault.

# SideOS

**Built with [SideInstaller by FrizzleM](https://github.com/FrizzleM/SideInstaller),
[LiveContainer by its contributors](https://github.com/LiveContainer/LiveContainer)
and [StikJIT by the StikDebug contributors](https://github.com/StikDebug/StikJIT).**
Original authors retain their copyrights. [Full credits](CREDITS.md).

An iOS/iPadOS desktop workspace with movable windows, a native Liquid Glass Dock,
a browser with ChatGPT chat tabs, LiveContainer management and embedded SideInstaller.

**Experimental pre-releases are published in [GitHub Releases](https://github.com/stride-praline-2f-ai/SideOS/releases).** See
[release status](docs/release-readiness.md) and [licensing](LICENSING.md).
The app is unsigned: each user signs it with their own credentials. It does not
turn an iPhone into macOS or run ordinary Mac applications.

## Start here

- [Install, sign and update](docs/install.md)
- [First-run guide and everyday controls](docs/user-guide.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Privacy and security](SECURITY.md)
- [Release notes](CHANGELOG.md)
- [Build from source](docs/build-from-source.md)

Inside the app, open **Help → Getting Started**. No ChatGPT conversation or personal
access to the developer is needed. Report reproducible issues through this
repository's Issues page using the supplied template; remove personal data first.

## What is included

- A desktop browser with profiles, downloads, detachable tabs and an optional
  ChatGPT conversation row on chatgpt.com.
- LiveContainer as a movable, resizable desktop window. Hosted apps have their
  own windows and Dock entries. Classic Mode remains an upstream launch path.
- SideInstaller by FrizzleM: [official project](https://github.com/FrizzleM/SideInstaller),
  with a SideOS Home dashboard, host-owned file picker and protected self-refresh.
- Phone/inner-display/iPad layouts driven by native window points. The Golden Gate
  wallpaper fills from the centre, cropping both sides equally when needed.
- Native Clear/Regular Dock glass on iOS 26+, with an opaque accessibility option.

The pinned runtime is [LiveContainer nightly 2026-11-08](https://github.com/LiveContainer/LiveContainer/tree/9d6ea09b05afa2c8fc537c372795a294db631311).
The embedded installer is official SideInstaller 2.0.1 with documented local
integration changes. Locks: `Engine.lock.json` and `Installer.lock.json`.

Only **one unsigned SideOS IPA** is produced by the device workflow. The separate
experimental `browser-app/` sources are not packaged and do not provide isolation
to the embedded browser. Never assume hosted apps cannot access the host's data.

This repository is `stride-praline-2f-ai/SideOS`. Regular commits run Linux checks.
An IPA is requested explicitly through **SideOS3 Device IPA** or the fixed
`ipa/device` branch. No simulator/preview jobs run in that workflow. Component
caches require exact source/toolchain matches. See [build efficiency](docs/build-efficiency.md).
