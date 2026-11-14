# Sidecar browser reference refinement

The supplied image is displayed at 1280 × 960. File byte count cannot establish
Sidecar logical resolution. Existing 28-point menu, 52-point windowed toolbar
and 36-point tab strip match its approximate row proportions; these are retained.
Status glyphs and toolbar icons now use regular weight. Toolbar/tab hover uses
a subtle background highlight; native iPadOS still controls the pointer shape.

Browser toolbar and tabs have a separate persisted transparency preference,
defaulting to 35% clarity with neutral native material. Zero uses an opaque
surface, and Reduce Transparency remains authoritative. Desktop menu and panel
settings do not change browser chrome.

Tab page containers now retain identity across selection. Their WKWebViews remain
attached, and inactive native child views are hidden, excluded from input and
accessibility, and resigned from editing. Tab switches disable page animation;
there is no artificial crossfade or page reload. The full tab label rectangle is
clickable. A native regression switches between two local interactive pages and
checks retained counters, including a click near the tab edge. This does not
prove physical-device frame pacing.

WebKit keeps its real engine/device identification and preferred desktop mode;
Safari Version/product compatibility tokens are appended to configurations that
have no application-name suffix. Google can vary its layout by account, cookies,
region and rollout. Its latest appearance has not been verified on-device.

Portable fixtures and Swift syntax checks pass. The next native workflow builds
the combined IPA and runs the expanded UI suite. Preview failures remain advisory.

## Paired screenshots: menu calibration

The user supplied both native Sidecar and the older app at 1280 × 960.
The app menu is approximately 26px tall and the reference approximately 28px.
On the standard 1376 × 1032 logical canvas of the 13-inch M4, 30 points maps to
27.9px at this image size; the former 28 points maps to 26.0px. The shared menu
height is now 30pt, menu labels 14pt (formerly 13), date 13pt (formerly 12), with
status hit regions and fullscreen reveal offsets updated together. This is a
calibration for the supplied pair, not a claim that byte size determines scale
or that every iPad display-zoom configuration uses the same logical canvas.

## Integration with user PR #1

Base: Aaqjb/SideOS `4d0aca5286d01d8bb21afa73c250080d62625792`.
Preserves the merged website identity profiles/scripts, appearance syncing,
WebKit obscuredContentInsets, full-window under-scroll layout, identity tests,
preference migration and browser/menu defaults. Those identity profiles supersede
the earlier appended-UA approach described above; the PR's default clarity is
72%, superseding the earlier 35%. Menu height was already 30pt in this PR.
This follow-up centralises that height, raises labels to 14pt, adjusts status
controls and aligns fullscreen offsets. It does not replace the user's engine
configuration with the older implementation.
