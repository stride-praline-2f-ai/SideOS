# Standalone web apps and guest hosting

Notes now opens https://www.icloud.com/notes/; the custom Notes editor and
Calculator UI are removed. Calculator is a Desmos Scientific web app. Finder,
Settings, Applications and Downloads remain desktop tools. The one-time migration
pins Notes/Calculator, preserves existing pins, and translates restored legacy
windows into web apps. Old local notes.json is left intact; it is not imported
into iCloud, and iCloud sign-in remains the user's account flow.

Every pinned web app is recognised by its existing browser-window launch URL.
It keeps the same WebKit session, website identity modes and shared website data
store, with no address field or visible tab strip. Compact traffic lights remain
in the corner; fullscreen hides them until reveal. No separate title bar is
added. Background popups remain in that app's session. New Tab from a standalone
app opens a normal browser. Normal browser windows retain navigation and tabs.
App names stay stable in the window and menu bar while the page title changes.

Guest sessions retain their viewport/controller across SwiftUI updates. Scene
activation configures the viewport's orientation/zero insets and sets the
contentView flexible-width/flexible-height mask used by upstream's native live
resize path. Resizing never explicitly relaunches a process. A UIKit hover
recognizer on the app window observes pointer motion without swallowing clicks;
the top reveal strip also handles hover directly. This supplements SwiftUI
hover, which can be bypassed by hosted content. No promise is made about guest
apps that themselves reload on bounds/orientation changes.

The desktop's blanket JIT rejection is removed. Launching uses LCAppModel.runApp
with multitask enabled, preserving signing, PID callbacks, the configured JIT
provider and scripts. A missing launch delegate reports an error instead of
silently skipping JIT. Classic/32-bit guests still require the original runtime
path. First-time JIT pairing/provider setup and provider authentication are not
bypassed; availability remains dependent on the installed signing environment.

Local core, identity, motion and standalone-classification fixtures pass, as
does Swift syntax parsing. Local packaging checks: 15 passed, 4 macOS-only skips.
Optional native UI tests replace the obsolete Notes/Calculator UI cases with a
local standalone WKWebView page, chrome-hidden checks and lifecycle transitions.
These newly edited UI cases have not yet run. The combined native build must
compile Guest.swift and the UIKit observer on the actual SDK. Physical iPad tests
remain required for guest PID continuity on resize, pointer reveal, and one
configured JIT emulator launched directly from Applications. This source change
is not evidence those hardware checks have passed.
