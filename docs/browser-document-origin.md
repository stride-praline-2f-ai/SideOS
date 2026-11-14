Fresh documents now start below the entire browser toolbar and tab strip.
The WKWebView still fills the window, so scrolling can move the page behind the
translucent controls. The fix reserves real scroll-view space as well as declaring
the obscured WebKit viewport; a neutral cover alone cannot make obscured document
content visible.

On a fresh navigation, commit establishes the top offset from the adjusted scroll
inset. The loading completion callback does not reset a page that has already
committed, so scrolling while a website finishes loading is preserved. History
and reload restoration remain owned by WebKit. Chrome-height changes preserve
the distance from the document origin, including the additional menu bar when
fullscreen controls are revealed.

The top pocket is derived from the real distance scrolled, rather than the lowest
offset observed during loading. Returning to the top therefore restores the
neutral background for touch, trackpad, keyboard and programmatic scrolling.

The simulator regression uses local documents with a marker at the document's
first line. It checks that marker against the actual tab-strip frame, verifies
that it leaves the visible area on scroll, checks a return to the top, and opens
a second local document after scrolling. Screenshots cover all four states.
Production websites receive no layout CSS or scripts from this fix.

API references: [WKWebView viewport insets](https://developer.apple.com/documentation/webkit/wkwebview/obscuredcontentinsets)
and [WebKit's inset and initial-offset implementation](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/ios/WKWebViewIOS.mm).
