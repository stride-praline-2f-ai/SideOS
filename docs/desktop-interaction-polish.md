> Historical development report. Account-specific links were removed for public sharing; relative source links now refer to the current tree.

# Desktop interaction polish

Window dragging now publishes presentation changes to a small placement modifier,
instead of reevaluating the window's content builder for every pointer sample.
Movement preserves the hosted view's size and uses a translation. Resize still
updates the actual content size. Live geometry and committed geometry share the
same constraints, and pulling a tiled window free preserves the point grabbed.
Snapping uses a short spring; direct manipulation has no animation lag. Browser
suggestions use window-local address geometry, eliminating a global-frame
preference update on each drag sample. Backgrounding resets an unfinished drag.

All desktop dropdowns share one coordinator and one surface. Moving between
menu headings replaces the content in place; contextual menus and menu-bar
menus cannot coexist. Only the first entrance animates, with immediate switching
and dismissal. Keyboard selection resets on a content switch, while the editor's
original responder is retained for editing commands. A change of active window
does not restore focus to the previous window.

LiveContainer passes `relativeBundlePath` as its launch identifier. Dock icon
lookup now resolves this path, with the real bundle identifier as a compatibility
fallback. Running applications have stable launch order, independent of window
focus order, with one app icon for multiple container windows. Their window
picker and Quit commands act on the corresponding application's windows.
Exited guests lose the running dot; their window remains available to read the
exit message. The guest launch surface also shows progress before the PID arrives.
Icon preparation happens before display instead of decoding at first paint.

Dock magnification measures the pointer in a fixed viewport, rather than feeding
the animated panel origin back into the next sample. It computes the item list
and baseline geometry once per update. Pointer travel follows immediately;
enter/exit and app insertion/removal animate. Shared buttons gain native pointer
highlighting and consistent short press feedback. Existing interactive native
glass controls retain their own system interaction. Reduce Motion suppresses
scaling, magnification and animated transitions.

The interaction approach follows Apple's [Liquid Glass custom-view guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
and [native hover effects](https://developer.apple.com/documentation/swiftui/view/hovereffect(_:isenabled:)).

## Verification

`tools/test-core.sh` includes single-owner menu transitions, app grouping and
close/relaunch lifecycle, grab-point restoration, and 264 pointer samples across
all eight resize edges. The existing lifecycle, Spaces, minimize/fullscreen,
restoration, motion, overview, address and ChatGPT tests remain required. Swift
sources are syntax-parsed locally; the device IPA workflow validates UIKit and
SwiftUI compilation with the pinned native dependencies.

Device review should cover a live guest and a browser moving together, pulling a
tiled window free, rapid menu switching and nested menus, Escape and Cut/Copy/Paste,
two guest apps and multiple containers, app quitting, minimized-window restoration,
Dock auto-hide, pointer travel, and Reduce Motion. No device frame-time measurement
or authenticated live-site interaction is claimed by the automated fixtures.

The change uses the normal cheap checks and the fixed `ipa/device` branch.
The first device build completed and saved the host, JIT, Rust FFI and installer
products. Final review found that `hoverEffectDisabled` also affects descendants;
the correction scopes the optional highlight with `hoverEffect(_:isEnabled:)`
so native glass keeps its own feedback. The running build was preserved, and the
corrected device request reuses the unchanged component products. No simulator
or preview build is needed.

Final device build: 42090421457 (historical account link omitted)
passed on app revision `ef265d8d4164b71bd82b10a51df44e9559d1c394`.
Its log confirms exact JIT, device FFI and installer cache hits; all three build
steps were skipped. The corrected host compiled and the packaged IPA passed
verification. Download the IPA artifact (historical account link omitted).
