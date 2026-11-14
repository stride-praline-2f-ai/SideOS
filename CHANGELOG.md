# Changes

## Unreleased — release candidate

- Hardened IPA extraction, patched dependency lock, independent CMS signature/tamper fixtures and current RustSec checks.
- Six-step built-in JIT tutorial with setup status, direct controls and common-error recovery.
- Actual-IPA privacy gate, explicit signing/pairing trust warnings and immutable Action pins.
- A stalled unauthenticated display handshake releases its slot without shutting down hosting.
- Prominent, linked upstream credits in SideOS About/Help, SideInstaller Home and its window title bar, plus public documentation and release notes. Existing component licences/notices remain retained.
- Experimental display-only Wi-Fi extension between SideOS devices, with per-session TLS pairing, bounded hardware video, Dock/window placement and automatic local recovery. All window kinds are eligible; physical LC scene capture remains unverified. No remote input is included.
- App display name is SideOS; existing bundle identity and user data remain intact.
- OLED Black appearance option for pure-black solid desktop UI backgrounds.
- Hosted title bars clip inside the full rounded window; tapping hosted content focuses its window without consuming the app's touches.
- Guest startup uses measured content geometry, retains actual initialization errors after exit callbacks, and recreates the viewport on a new launch.
- Built-in JIT setup tutorial and preparation controls in Settings.
- Explicit browser security warning in the README, app onboarding and browser: hosted malicious apps may access browser data.
- Clear desktop/windowed menu bar enabled for unset preferences; official LiveContainer Dock artwork.
- Current-source privacy cleanup and documented scan results/history limitations.
- Golden Gate default wallpaper with centred, symmetric aspect-fill cropping.
- Project-owner app icon adapted to full-bleed square artwork without black padding.
- LiveContainer management in a retained movable/resizable desktop window.
- Restored fullscreen hosted-app traffic lights and independent hover ownership.
- Visible resize grips at both bottom corners, including native/hosted windows.
- Native Clear/Regular/Solid Dock material options; independent opaque default for other panels/menus.
- macOS Enhanced Spoofing as the fresh-install browser default; saved explicit choices remain.
- User-facing install/update/help/troubleshooting/privacy documentation and licensing review.

These changes retain the Duo SDK gate, touch desktop, embedded SideInstaller 2.0.1,
pinned LiveContainer nightly, host-owned Files picker and source-protected refresh.
Public binaries remain experimental; device acceptance and trust limitations are
documented in the release-readiness and security guides.
