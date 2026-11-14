# SideInstaller desktop app and Home

SideInstaller is a built-in desktop app, available from the Dock, Applications,
Launchpad and command search. Opening it again focuses the same window. Its
window supports the existing Spaces, minimize, fullscreen and saved-workspace
controls. A saved window launches its guest only when visible. Third-party
guests remain excluded from automatic relaunch.

The installer runs in LiveProcess using the existing `Documents/SideInstaller`
data folder, preserving account, pairing, IPA-library and onboarding state.
The window shares the installer's operation lease: closing is blocked while an
install or refresh holds that lease. Interactive launches do not create a
background-refresh XPC connection or install notification forwarding hooks;
background refresh retains its existing transport. Ordinary management buttons
open the desktop window; URL-bearing installer launches keep the existing
upstream deep-link flow.

## Home dashboard

- **Choose IPA** opens Files and imports into the existing guided Install flow.
  **Open Installer** keeps the existing built-in download/source choices.
- **Registered App IDs** counts unique registrations returned by the selected
  Apple account's existing read-only App ID query. This is an account count,
  rather than the number of installed apps or an assumed ten-ID quota.
- **Installed Apps** and the app list use the existing installation-proxy
  inventory. The default filter shows sideloaded apps; **All Apps** shows the
  full returned inventory. Search accepts app names and bundle IDs.
- Per-app App ID counts match registrations against installed bundle IDs,
  signed application identifiers and extension metadata. If extension metadata
  is unavailable, a registration under an installed app's dot-delimited bundle
  namespace belongs to the longest matching installed app. These are related
  registrations on the selected account; unused historical extension IDs can
  remain registered. Each registration counts once. Until the account query
  succeeds, the UI shows a dash rather than a guessed zero.
- **Memory+** appears only when the installed app's reported signed entitlements
  contain `com.apple.developer.kernel.increased-memory-limit = true`. Enabling a
  portal capability alone is insufficient. Missing and false values have no
  badge.
- **Last refreshed** records successful SideInstaller refresh completion,
  including background and Shortcuts refreshes through the shared engine.
  History is stored by device UDID and installed bundle identifier in the
  existing installer container, with atomic writes and a previous-file backup.
  Failed or cancelled installs do not advance the time. Earlier or external
  refreshes have no invented date and show **not recorded**. Device inventory
  check time is labelled separately.

The Home tab uses the same EntitlementsManager as Tools, retaining its existing
account reset and two-factor authentication popup handling. Checking Home does
not sign, refresh or change app capabilities.

## Build integration and validation

`embedded/installer/patch.py` applies checked edits to the pinned engine's
RootView and Engine and adds the new Swift files before the guest product cache
lookup. The cache hashes the generated `engine/ios-app/**` sources, so an older
installer binary cannot satisfy these changed inputs. New installer adaptation
sources accompany the existing packaged source notices.

Local checks cover signed memory evidence, unique App ID attribution, durable
device-scoped history and recovery, the actual POSIX busy-operation lock,
installer window persistence, and the existing core regression groups. The
patches were also applied against the pinned installer/host source files and
the Swift sources parsed successfully. Workflow/cache, device-only Rust build,
compiler-warning and signed-adapter policy checks pass.

Apple SDK compilation, an installable IPA and on-device checks remain pending
until GitHub Actions capacity is available. No simulator or preview build is
requested. On device, verify existing-account preservation, narrow/fullscreen
layout, minimize/restore, Files import, two-factor prompts, installed-app
entitlement reporting, and foreground/background refresh history.
