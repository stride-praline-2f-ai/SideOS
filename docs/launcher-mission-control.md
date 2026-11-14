# Native launcher glass, app-owned Mission Control and live dragging

The launcher uses Apple's native glassEffect(.regular.tint(...)) on iPadOS 26+,
including iPadOS 27, with no whole-material opacity fade. Blur/refraction, neutral
tint, dark readable content styling and a double rim give the panel definition.
Reduce Transparency or zero panel clarity selects an opaque surface. The existing
panel transparency preference still controls tint. The 878×602-point maximum and
64-point icons approximate the supplied 816×560 / 60px reference at 1280px wide
on a standard 1376-point 13-inch M4 canvas. Four category pills match the reference;
selecting a category again or Show All Applications clears its filter. This is
not a claim that Apple's exact macOS optical output is reproduced on iPadOS.

Mission Control replaces the old fixed-height card grid with aspect-preserving
window rectangles over the wallpaper and a compact desktop strip. Add, select,
remove desktops, select/close a window, or drag a window card onto a desktop.
Removing a desktop relocates its windows without terminating sessions. The Dock
remains available; selecting it exits the overview. The menu bar is hidden while
this strip is shown. Existing live windows stay mounted and are hidden from input
and rendering; no guest or WKWebView is reparented for an overview thumbnail.
Web snapshots are refreshed on entry/desktop changes, with stale-space callbacks
rejected. Unsupported app/guest captures display Preview unavailable. Snapshot
contents may not reproduce complete app chrome; this is an app-owned overview,
not control over the real iPadOS system windows or Spaces.

Open from View → Window Overview, Applications Dock context menu → Mission Control,
Control-Up, or Command-Shift-M. A delivered 3/4-finger touchscreen swipe up also
opens it, and down dismisses it. UIKit's direct-touch observer does not request
trackpad scroll events or intercept system navigation. iPadOS-reserved 3/4-finger
trackpad swipes cannot reliably be assigned to an in-app Mission Control through
public APIs. Touch gesture delivery may also yield to system editing/navigation;
keyboard and menu paths remain available.

Live window drag/resize updates a per-window @State preview frame. A value-copy
of the existing geometry policy enforces bounds without publishing workspace
state or scheduling persistence on each movement. Release commits geometry and
snap layout through the existing window manager. Focus changes once at gesture
start; snap preview changes only at region crossings. Overlay/fullscreen/visibility
changes cancel local previews. Native content still receives real bounds changes
while resizing; this does not suspend its layout cost. No measured FPS/CPU saving
or physical-device smoothness claim is made.

Validation: local fixtures cover overview bounds, aspect ratios and non-overlap
for 1–40 windows on three canvas sizes, plus desktop removal/window retention.
Existing geometry/lifecycle/identity/motion/icon tests and Swift parsing pass.
Packaging checks run locally (15 pass / 4 macOS-only skips). The optional native
UI suite adds overview entry, desktop creation and window selection. Hardware
trackpad delivery, image matching and frame-time measurements remain unverified.
The native build must validate the new SwiftUI/UIKit code before IPA delivery.
