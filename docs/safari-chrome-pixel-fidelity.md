# Safari chrome fidelity, 1 November 2026

## Reference basis

SideOS image: 2752 x 2064 PNG. Target Safari image: 1536 x 1152 JPEG.
The audit resized the SideOS capture to 1536 x 1152 before estimating bounds. These are comparison pixels, not Xcode layout points. On a 1376-point-wide iPad canvas, each SwiftUI point becomes approximately 1.116 comparison pixels. Display Zoom, camera/screenshot processing and JPEG antialiasing prevent absolute point reconstruction.

| Surface | Previous SideOS | Target implementation |
| --- | --- | --- |
| Toolbar | 48 pt (~54 comparison px) | 53 pt (~59 px) |
| Tab band | 36 pt (~40 px) | 41 pt (~46 px) |
| Address | 525x34 pt max | 565x38 pt max |
| Sidebar | bare toolbar glyph | 39x38 pt glass capsule |
| Profile | absent | Personal, 122x38 pt |
| History | no internal divider | two 38pt button slots and divider |
| Right actions | 3 independent controls | 116pt glass group |
| Tab surface | 28pt capsule | 32pt capsule in 41pt band |
| Text | 12pt URL/tab | URL 13pt medium, tab 13.5pt medium |

## Implementation decisions

- Browser.swift uses a window-centred address surface on wide layouts; responsive stack on narrow window widths.
- Browser.swift makes browser options, translation and reload share the address capsule, preserving the editable TextField.
- Browser.swift now implements real Personal, Work and Private profile selection. Personal uses WKWebsiteDataStore.default(), Work has a separate persistent store via WKWebsiteDataStore(forIdentifier:), and Private gets a session-owned nonpersistent store. Per-profile tabs are isolated and switching preserves their live state.
- Browser.swift loads favicons directly from a page's advertised HTTPS icon, falling back to /favicon.ico and then a neutral globe. No third-party proxy. Icon tasks check navigation identity, cancel on reload and reject responses larger than 256 KiB.
- Browser.swift offers Apple Translation for a user-requested excerpt of page text. This does not claim Safari's private full-page translation feature. Full DOM rewriting is intentionally omitted to avoid altering untrusted sites' scripts, forms, or selected content.
- Tabs.swift keeps the live WKWebView associated with each tab. It retains tab selection, drag reordering, close targets, keyboard navigation and hover/selected states.
- Design.swift provides native SwiftUI Liquid Glass capsules on iOS 26+, regular-material fallback earlier, and opaque capsules for Reduce Transparency. The existing native full-window glass is retained; no simulated CSS blur is used.
- DesktopWindow.swift matches the new 53pt navigation height. WebKit obscuredContentInsets remains aligned to toolbar+tabs. The address field compensates for the separate 92pt title-bar traffic-light group when windowed so it stays centred on the full window.
- Workspace.swift persists only Personal tabs, never Private URLs or titles; Work's WebKit cookies remain persistent but Work tab URLs are not added to the generic workspace restoration file.

## Primary Apple APIs

- https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/documentation/translation

## Verification

The native Xcode build, iPadOS Simulator screenshots, and on-device comparison are separate gates. Compare lossless images at the same native screen scale, page titles, active tab, appearance, Display Zoom and Reduce Transparency setting. Inspect the URL baseline, capsule bounds, favicon and close glyph alignment, hover/selection, tap targets and content scroll viewport. Apple's proprietary Safari optics and actual per-device tint may remain irreproducible with public SwiftUI APIs. Do not call the result pixel-perfect before an on-device comparison.

## Latest validation scope

- Native Xcode browser compilation and core tests must pass on the final commit, not just an earlier PR revision.
- Combined host packaging uses another Swift compiler path; MotionPolicy explicitly imports CoreGraphics and uses separate rectangle interpolation expressions to avoid host-only type-check failures.
- The browser profile UI suite verifies visible tab isolation and return to earlier Personal pages. On-device visual inspection is still required for exact text rasterization and Safari's proprietary glass refraction.
