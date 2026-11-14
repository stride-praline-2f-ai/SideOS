# Motion integration: staged implementation and evidence

Primary visual target: the supplied macOS 27/Sidecar references, with Tahoe
components retained where applicable. This is community recreation. All timing
values in MotionPolicy.swift are project tuning values, not extracted Apple data.

## Source and compatibility review

Exact inspected revisions and GitHub licence metadata are in motion-sources.json.
Read alexwidua/genie's SwiftUI and Metal prototype, souph1s' Gaussian Dock example,
YordiLorenzo's motion/feel skills and SDK availability reference, and repository
README/licence material for the remaining candidates. Apple motion, menu-bar,
pointer, WWDC2026/289 and macOS pages were retrieved; layerEffect DocC confirms
the public SwiftUI shader approach. Community assertions remain community claims.

| Reference | Status / use |
| --- | --- |
| alexwidua/genie | MIT LICENSE.md verified; architecture reference, attribution retained. Original shader mapping uses inverse horizontal strips rather than copying its fixed squeeze/translation constants. |
| SekiroKenjii/macos-genie | GPL v2 metadata; GNOME-specific. Geometric reference, no copied runtime code. |
| baikaihao/EchoDock | AGPLv3, AppKit-specific; Dock reference, no new dependency. |
| Kaww/magnification-effect | No detected licence. SwiftUI reference, no direct copy. |
| souph1s/dock-macos | No detected licence, despite handoff describing MIT. Gaussian/bounce reference, no React runtime. |
| LikhithSP/MacOS-Web-Simulator | MIT; desktop interaction reference, no web-shell dependency. |
| juanlara-aidev/macos-26-design | LICENSE text is MIT though API says NOASSERTION; design reference, no Apple-original timing claim. |
| YordiLorenzo/liquid-glass-skills | MIT; read motion, feel and availability guidance. SDK compilation remains authoritative. |
| GetStream/awesome-liquid-glass | No detected repository licence. Native example reference, no wholesale import. |
| usagimaru/GenieWarpMesh | MIT; macOS private CGS API, excluded from iPad motion code. |

Attribution is retained. This report does not label unknown upstream licences
MIT or assign third-party ownership. Existing LiveContainer AGPL
obligations and private iPad guest mechanisms remain as previously documented.
Only public iPadOS APIs are used in the new motion files; the entire pre-existing
LiveContainer runtime is not claimed to use only public APIs.

## Implemented stages

1. MotionPolicy.swift maps typed semantic events to shared duration/displacement.
   Dock keeps its existing bounded Gaussian neighbour displacement and width
   response. Launches get a finite lift/return without delaying activation.
   Touch does not turn on magnification; hover exit still restores base geometry.
2. WindowMotion.swift captures an unobscured frontmost app-owned window once,
   at <=1024 pixels on its longest dimension. Motion.metal warps the snapshot
   toward that window's Dock target. Restore pairs with the same snapshot.
   Up to two captures are retained; no full-screen image is repainted each frame.
   Renderer TimelineViews exist only for active flights. Reduce Motion skips them.
3. Tracks retarget from current progress and use completion tokens. Close, scene
   inactivity, resize, Spaces, desktop exposure, fullscreen and Reduce Motion
   clear flights. Semantic minimise state changes immediately; cancellation never
   rolls it back. Snapshot overlays never receive input; Dock restore remains usable.
4. Menu titles have hover and active highlights, open-menu pointer switching is
   retained, and menu entry scales subtly from its anchor. Existing menu-row and
   traffic-light glyph hover remain. Custom controls compress 2% while pressed,
   gated by Reduce Motion; static panels do not bounce or fade their materials.

## Explicit limits / next stages

The Genie is a prototype approximation, not an exact two-phase macOS funnel.
It uses a visible-region UIWindow capture, so only frontmost, fully visible,
non-guest windows above the Dock are eligible. Others use the existing scale
transition. Occluded guests, protected video and private surfaces are not claimed
capturable. Restoring uses the last captured appearance until the live view
returns. It is not a real-time recording of background page changes.

Overlay families other than menu entry retain their existing presentation;
no claim is made that every notification/popover now has a new morph.
Physical mouse/trackpad trajectories, 60/120Hz frame pacing, snapshot latency,
Metal output and energy use still require the M4. No measured smoothness or
pixel-identity claim is made without that evidence.

## Validation

Portable tests cover the motion registry, all Reduce Motion policies, continuous
mid-flight reversal, distinct tokens for independent windows, zero-duration
completion, plus existing Dock geometry, lifecycle and website identity tests.
Swift source syntax and engine overlay/package checks run locally. The explicit
native build compiles the actual Swift/Metal target and produces the IPA; its
result must be checked before calling this native-build validated. Existing
simulator touch/minimise/restore/drag tests remain available as optional previews;
physical pointer and memory/frame-time tests have not run in this Linux session.

## User correction: label-only Dock hover

Dock magnification defaults to off. A one-time upgrade migration also disables
it for existing installations; users can explicitly enable it later in Settings.
Hover labels remain active. Pointer movement no longer has a spring when
magnification is off. Click launch feedback is separate from hover.

The IPA workflow now shares one repository-wide concurrency group and cancels
older active runs of the same workflow in its first core step. This also retires
older runs created under the previous per-commit concurrency policy. Previews
remain optional. Other PR/check workflows are outside this cancellation scope.
