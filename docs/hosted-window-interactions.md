# Hosted-window interaction repair

The prior integrated overlay was only trafficInset (92pt) wide. The remaining
web-app/guest top edge belonged to the WKWebView or guest scene, with no universal
window drag/double-click region. This was a hit-area omission, not missing window
state algorithms.

Standalone web apps and overlaid guest windows now have a full-width 40pt compact
header with traffic lights and a drag surface across the remaining width. It uses
the existing shared windowDrag and toggleMaximize implementation, including edge
snap preview/tiling, pull out of Fill, focus and saved floating geometry. Double
click/tap toggles Fill Desktop/restore; Fill reserves both menu and Dock. Green
continues to enter real fullscreen. Header actions are accessibility-labelled.
Browser address/tab controls remain absent in standalone apps. Guest content is
inset below this strip so remote controls do not compete for its pointer events.
The guest's alternate non-overlay header mode continues to use the existing
normal title bar.

The shared eight resize handles are now above the header and UIKit content,
with 8pt edges/16pt corners and high-priority drag recognition. This preserves
content object identity and does not launch/reload pages or guest sessions.
Finder and other integrated desktop-tool headers retain their 92pt control
overlay, so the new drag strip does not cover their toolbar buttons.

Portable tests cover web-app/guest move, all eight resize edges, Fill versus
fullscreen, floating restoration, tiling, resource ID and window identity.
The optional native standalone test now drags the header, double-taps Fill and
restore while checking Dock/menu visibility, resizes a corner, and checks live
page state before its existing fullscreen/minimise tests. Native test execution
and physical mouse/guest PID continuity still require their respective simulator
or iPad checks. Syntax/core tests alone do not establish on-device hit delivery.
