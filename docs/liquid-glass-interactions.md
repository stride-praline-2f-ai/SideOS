# Desktop glass and interaction pass

This is a macOS-inspired interaction treatment for the native iPad desktop shell,
using available iOS 26 Liquid Glass APIs. It does not claim pixel parity with a
particular macOS 27 release.

## Coverage

| Surface | Treatment |
| --- | --- |
| Browser navigation and shared app toolbars | Preserve the current Safari sidebar/profile, history and action groups; add native interactive refraction, hover highlight and spring press/release |
| Browser address | Glass capsule and animated editing focus ring; text editing remains native |
| Dialog/action buttons | Shared glass surface, accent/destructive tint, press feedback |
| Tabs and tab close buttons | Hover and press feedback; existing selection, keyboard navigation and reordering retained |
| Dock and launcher | Press compression; existing dock magnification and launch bounce retained |
| Menu bar, popups, menu commands | Hover/press feedback; command rows do not scale their selection highlight |
| Finder and desktop files | Touch/hover feedback on the existing UIKit input adapter, including end/cancel cleanup |
| Settings, calendar, radio/checkbox/switch choices | Shared press feedback with existing selected-state visuals |
| Sliders and fields | Drag thumb response and animated focus feedback |
| Window lights and fullscreen reveal | Shared press/hover feedback without changing action hit frames |
| Window, dock, menu and overlay surfaces | Existing native glass and transparency settings retained |

The browser retains its 53pt toolbar, 565x38pt address capsule, 41pt tab band,
window-centred layout, profile isolation, translation and retained WKWebViews.

Related toolbar, tab, calendar and settings controls use local `GlassEffectContainer`s on
iOS 26. Content, file tables and hosted web pages remain readable content layers.
The shell does not inject glass into websites or native guest app interfaces;
those apps own their internal UI. The existing LiveContainer management interface
also remains owned by the upstream engine; returning to the desktop restores
these shell controls.

## Accessibility and compatibility

- Native glass is gated to iOS 26; earlier supported systems use regular material.
- Reduce Transparency and zero panel glass use opaque surfaces.
- Reduce Motion disables custom scaling/spring transitions and interactive glass
  motion; immediate color feedback remains visible.
- Disabled controls do not highlight or press. Inactive window controls suppress
  hover and press visuals until their window becomes active.
- Button labels, actions, keyboard shortcuts, selection traits and hit layout stay
  with their original views. No extra tap recognizers are installed on buttons.
- UIKit file feedback uses touch observation and hover only; the existing primary,
  secondary, double-click and drag recognizers continue to own input.

## Current validation policy

Run `bash tools/test-core.sh` for portable behavior, the DOM fixtures for adapter
contracts and `node tools/test-chatgpt-layout.cjs` for real layout geometry. The
release workflow is `.github/workflows/private-build.yml`, using device-only Rust
FFI and the fixed `ipa/device` branch. It packages an unsigned device IPA without
simulator or preview work. The legacy preview tools remain optional source tools
and are not release evidence.

Physical iPad review must cover light/dark appearance, Reduce Motion/Transparency,
selected versus inactive tabs, disabled Back/Forward, pointer hover, press drag-off,
reorder/detach/cancel, menu transitions, split composers and fullscreen recovery.
Linux checks and IPA compilation cannot validate native glass rendering or feel.
See `device-validation.md` for the release checklist.
