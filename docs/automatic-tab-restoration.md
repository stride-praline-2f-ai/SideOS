# Automatic page restoration

Saved browser pages previously started with `load: false`. The main resumption path only loaded the selected page of the active desktop window, leaving other visible windows and inactive tabs waiting for selection. A WebKit process termination retained its WKWebView object and therefore also bypassed the existing non-nil-view check.

Restoration now uses a shared two-slot queue across browser windows and ChatGPT workspace pages. Selection prioritises the next available slot. A browser window appearing or becoming visible queues its restored pages automatically; selected pages have priority. Already loaded pages keep their current document. Restored/hibernated pages display progress rather than an instruction to click Resume.

Requests hold pages weakly. Closing, unloading, transferring ownership or manually navigating a page removes its request and cancels its watchdog. Completion, failure and timeout free a slot for the next waiting page. Native Back/Reload navigations also cancel the old restoration watchdog so it cannot stop the replacement navigation. Suspending the app pauses new starts and timeout accounting; foreground resumption rearms active requests.

A terminated WebKit process triggers automatic recovery even when its WKWebView still exists. At most two automatic recoveries per page are attempted in a rolling minute. Repeated crashes and ordinary connection errors retain a Retry action. Reloading after OS process loss cannot reconstruct an unsent draft that WebKit has already discarded.

The same change clears the web view and scroll view’s opaque white backing, addressing the white repaint region seen while a dark page enlarges. Page document backgrounds continue to render normally. This does not claim to solve the independent ChatGPT root-scroll/keyboard viewport behavior seen during split view.

## Checks

`tools/test-core.sh` compiles the actual restoration driver against controlled page stand-ins. Tests cover priority, maximum concurrent starts, duplicate requests, app inactivity, close cancellation, invalid starts, hung-load progression, suspended watchdogs and the crash cooldown. Existing state, motion, overview, identity, ChatGPT state/DOM and workflow checks remain in place. UIKit/WebKit integration is compiled by the device-only IPA workflow; no simulator or preview is required.
