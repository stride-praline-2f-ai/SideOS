# SideOS release candidate — DRAFT, NOT FOR PUBLIC IPA DISTRIBUTION

SideOS provides an iOS/iPadOS desktop workspace with windowed LiveContainer,
embedded SideInstaller, a browser, detachable tabs and touch/pointer window controls.

## New in this candidate

- Golden Gate default wallpaper, cropped equally from both sides as needed.
- New full-bleed app icon with the surrounding black padding removed.
- LiveContainer management in its own window, with its tab/navigation state retained.
- Both lower window corners resize native and hosted apps.
- Hover at the top-left of fullscreen hosted apps for traffic lights; touch users
  can use the bottom-right glass ellipsis to minimise, restore, switch or close.
- Native Clear/Regular/Solid Dock glass selection.
- Fresh-install defaults: macOS Enhanced Spoofing and opaque other panels/menus.
  Existing explicit preferences are preserved.

## Before using

Read [installation](install.md), [user guide](user-guide.md),
[troubleshooting](troubleshooting.md) and [security/privacy](../SECURITY.md).
Recipients provide their own signing material and configure JIT when required.
Hosted apps and the embedded browser are not guaranteed isolated against a malicious guest.
SideInstaller by FrizzleM: https://github.com/FrizzleM/SideInstaller.

## Maintainer completion fields

Exact source revision: fill from the successful native source check.
Device acceptance/known issues: record actual hardware results; do not equate a
compiler pass with device validation. Once distribution permission is obtained,
request the single-IPA device workflow and attach its source-matching IPA,
release/verification manifests and SHA-256, plus corresponding source.

**Do not publish a combined IPA until the blocks in [release readiness](release-readiness.md)
are resolved.** This text is a prepared draft, not an authorization or permission grant.
