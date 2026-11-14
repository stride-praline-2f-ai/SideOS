# Desktop fidelity and performance audit — 31 October 2026

## Evidence and scope

Reviewed the desktop's shared rendering, menus, window state/gestures, Dock,
Applications, browser sessions, files, settings, persistence, downloads, guest
presentation bridge and build/preview integration. Compared the supplied macOS
Sidecar images with actual iPad Simulator screenshots from run 41142179342.
Checked the four retained source projects' window, Dock, glass and typography
implementations. This is not an independent security/compatibility audit of all
upstream LiveContainer, SideInstaller or WebKit source.

The reference images are 1280 × 960 (4:3); the previous simulator canvas was
1180 × 820. Direct pixel subtraction between these different layouts/content
would give misleading results. The preview now prefers a 13-inch iPad, captures
windowed/fullscreen/revealed browser states, and retains original screenshots.
All measurements remain in logical points; no screenshot is presented as proof
of frame pacing or native guest compatibility.

## Findings corrected in this change

| Finding and evidence | Change | Verification |
| --- | --- | --- |
| `TahoeGlass` faded the complete material with `.opacity`, exposing sharp content behind the panel. Native Applications screenshot confirms this. | Keep native glass compositing at full strength; the clarity setting controls neutral tint and regular/clear material. Zero clarity and Reduce Transparency use an opaque surface. Content identity stays stable. | Native screenshot comparison required after build. |
| Browser toolbar material was layered over the window's opaque background. | Opaque fill now belongs to the web page. Toolbar glass can sample the desktop. Hidden toolbar glass is omitted. | Stable WKWebView fullscreen regression remains enabled. |
| App-name text expanded into a 130-point menu slot even for short names. | Intrinsic app-name width, capped at 130 points. | Native screenshots. |
| Status buttons exposed approximately 13-point hit rectangles in the failure hierarchy. | Give status buttons full menu-height hit areas; toolbar buttons have explicit content shapes. Visual glyph sizes stay compact. | Retain failing Spotlight test. |
| Integrated title bars removed the large drag region from Notes and other built-ins. | Share title-bar drag/zoom actions with toolbar backgrounds. Buttons retain their own actions; fullscreen disables window dragging. | Notes test now drags its toolbar before editing/minimising. |
| The traffic-light group was inset 10 points and tightly spaced relative to the reference. | Shared 92-point occupied width, 14-point leading inset, 22-point button slots and existing 12-point lights. | Native screenshots. |
| Dock fit omitted separator slots; magnification could exceed available width. | Pure geometry function accounts for gaps/padding/separators, reserves magnification room, and bounds hover expansion. Resting centers stay stable. Very crowded Docks scroll at their minimum size. | Portable tests: five screen widths, five app counts and three pointer positions; explicit crowded/removal cases. |
| Fill/Tile reserved the configured maximum Dock size even when icons shrank. | Reserve the actual resting Dock height without re-constraining floating restore frames. Floating windows still move behind the Dock. | Existing window geometry tests plus native preview. |
| Clicks in an active window repeatedly focused/reordered it, and repeated page-title notifications scheduled unchanged state writes. | Guard redundant focus/title writes and unchanged snap previews. | Code evidence; no measured CPU saving asserted. |
| Preference sliders encoded/wrote UserDefaults on every change. | Debounce writes by 250 ms and flush preferences when leaving the active scene. | Syntax/native compilation; existing preference UI test retained. |
| Browser popovers and desktop menus shared one fullscreen hold flag. | Independent popup/menu holds prevent one surface from dismissing another's controls. | Fullscreen menu/page-state test. |
| Native test found the fullscreen File menu but its command label included the shortcut. | Explicit command accessibility label; shortcut is an accessibility hint. | Baseline hierarchy contains `Open Location…, ⌘L`; test keeps checking the actual command. |
| A minimised Notes editor remained in accessibility at one tenth scale. | Apply hidden state after the window accessibility container; the native Notes editor also sets UIKit visibility, input and accessibility state explicitly. | Existing minimise/restore test retained, not weakened. |
| Applications categories inherited blue button text instead of the reference's neutral labels. | Plain primary-text category controls and a readable Applications prompt. | Native screenshot. |

## Validation baseline

Run [41142179342](https://github.com/aaULTra/Sideos/actions/runs/41142179342)
compiled and produced an IPA. Its native test result was **5 passed, 3 failed**:

- Passed: browser defaults, calculator/fullscreen, Finder rename, rename-sheet
  minimise/restore, and interaction with a real WKWebView page.
- Failed: fullscreen File-menu command lookup (label mismatch), Spotlight search
  opening, and Notes editor hiding after minimise.
- Fullscreen reveal and auto-hide, fixed page viewport during reveal, and live
  page retention up to the menu assertion passed in that run. Restore and the
  second click were not reached; they must not be claimed as tested there.

This change passes the portable lifecycle/geometry/control/file fixtures,
including the expanded Dock cases, and Swift syntax parsing. Packaging checks
run locally: 19 tests, 15 passed and 4 macOS-only skips. The consolidated native
build and UI rerun are required before calling the regressions resolved.

Follow-up run [41177277356](https://github.com/aaULTra/Sideos/actions/runs/41177277356)
compiled the simulator and combined IPA successfully. **7 of 8 UI tests passed**,
including the complete fullscreen/reveal/auto-hide/restore/live-page test and
Spotlight. Notes toolbar dragging passed, but its minimised editor remained
AX-hittable despite SwiftUI hiding modifiers; the keyboard assertion was not
reached. Notes now uses a retained native UITextView with explicit visibility,
interaction, accessibility and responder state. This preserves its text,
selection and scroll position without keeping an invisible input target alive.
The unchanged Notes regression remains enabled for follow-up diagnosis.

Inspected this run's Applications and fullscreen screenshots: the Applications
backdrop is now blurred, app-name spacing is compact, and revealed fullscreen
controls have the expected position. These are actual 13-inch iPad Simulator
captures. The procedural wallpaper, icon set, panel tone and animation still
prevent an exact match to the supplied macOS desktop.

The Downloads Dock item also now honors its Remove from Dock setting; previously
it was appended again after the hidden-item filter. Browser popup creation now
allows WebKit-configured `about:blank` windows, which script-driven sign-in and
document workflows can populate/redirect. It still refuses file, JavaScript and
data URLs at the popup boundary. Portable policy tests cover this; specific
third-party login flows have not been end-to-end tested. Menu rows and Applications
category pills now use their full visible hit rectangles. The browser's navigation
arrows share a capsule and its page-options button is inside the address field,
closer to the supplied Safari toolbar arrangement.

## What remains before a pixel-faithful claim

1. Review fresh light/dark screenshots on the matching aspect ratio with the
   same wallpaper, content and Dock population. The current procedural wallpaper
   is not the supplied Golden Gate image; custom wallpaper import is supported.
2. The current minimise animation is a scale transition, not the macOS Genie deformation; the overview grid is not an exact Mission Control reproduction. Compare on-device pointer acceleration, resize cursors, Dock hover trajectory,
   traffic-light hover symbols, window shadows and animation frame pacing.
   Linux plus hosted Simulator provide no physical M4 CPU/GPU/energy trace.
3. Preserve the native material pipeline. iPadOS Liquid Glass and macOS Tahoe
   may render differently even with matching geometry; a CSS displacement port
   cannot establish Apple's exact optical output.
4. The built-in Finder, Settings, Notes and Calculator are functional desktop
   applications with a smaller feature set. They do not implement Apple's full
   application behavior. Browser profiles, Reading List, translation and Safari
   extension support are not implemented. Avoid decorative nonfunctional controls.
5. Further performance work should narrow broad `TahoeWorkspace` observation
   only after a SwiftUI Instruments trace identifies expensive update chains.
   File directory enumeration/metadata and workspace JSON writes still include
   synchronous work; large-folder/storage workloads need a separate measured pass.
6. Desktop guest launch still excludes JIT/classic/32-bit guests; their original
   management path remains. Guest capture, focus, keyboard/controller routing,
   resize cadence and emulator performance need hardware tests. The weak delegate,
   bounded launch wait, close/startup race protection and retained guest view
   identity are maintained. The iPhone remote workspace is not implemented.
7. Background web pages are not automatically suspended by hiding their windows.
   Performance fullscreen explicitly hibernates eligible browser sessions after
   warning about page-state loss. No invented memory/power percentages are used.

## Source projects

The existing notices and revisions remain authoritative. macos-ui contributes
window/Dock interactions, macos-components window/control geometry, MacVue glass
and control tokens, and Flutter macos_ui typography/sidebar/control patterns.
For example, macos-components uses 12-point traffic lights and 14-point toolbar
padding; Flutter's standard body text is 13 points. Overlapping implementations
are not stacked. Browser-only SVG refraction and macOS-specific platform calls
are not portable iPad runtime features, and no blanket claim of porting every API
is made.

## Delivery verification — 1 November 2026

Run [41198335007](https://github.com/aaULTra/Sideos/actions/runs/41198335007)
built the combined IPA successfully from `e81bcfdbfe715245cc131cb649e7b6c0d93dd565`.
Portable tests passed. The simulator compiled and again passed 7/8 interaction
tests, including the complete fullscreen browser lifecycle, Spotlight, Finder
rename and calculator. Explicit native Notes visibility did not resolve its
minimised-editor accessibility assertion; restore/keyboard assertions in that
case were not reached. This is an unresolved finding, not a passing test.

The IPA artifact is `13042181107`; the preview artifact is `13041887570`.
The downloaded IPA's embedded source revision, host bundle ID and all five
extension bundle IDs match the intended existing SideContainer installation.
Compilation/package verification does not independently prove this revision
on a physical iPad; the user confirmed earlier delivered builds work there.

At the user's request, preview failures are now advisory at job level. Tests,
logs, screenshots and failure warnings remain enabled. The core and combined
build/package checks remain required; previews cannot block IPA delivery.
This workflow/documentation adjustment changes no application code relative
to the verified IPA revision above.
