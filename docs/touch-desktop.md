# Touch desktop release

The Duo inner display keeps the iPad desktop and uses native window points,
not a transformed or guessed-resolution canvas. Compact density is the default:
Dock, application-grid and launcher artwork is smaller, browser navigation is
48pt tall, and new windows fit 88% of the available work area up to each app's
preferred size. Settings → Windows offers Standard density and optional touch
feedback. Existing saved window positions, website zoom and third-party app
content are preserved.

The Dock is anchored at the bottom of the desktop. On the inner display the
former full bottom safe-area gap is reduced to at most 12pt of home-indicator
clearance. Touch icon slots stay at least 44pt wide; an overcrowded Dock scrolls
instead of shrinking touch targets. Auto-hide exposes a visible 44pt reveal
target. Pointer magnification remains optional.

Shared action and toolbar controls use native interactive Liquid Glass with
press feedback; menus and Finder rows have 44pt touch heights. Finder and
desktop items open with one direct finger tap, while indirect pointer input
retains selection and double-click opening. Long press keeps context actions.
SideInstaller Home uses native glass buttons, grouped locally, with an adaptive
vertical arrangement when its install actions cannot fit in one row.

Every fullscreen window has a visible bottom-right glass ellipsis. Tap it for
Minimise, Restore, Windows and Close. These controls are owned by the host and
sit above embedded LiveContainer and SideInstaller content; they do not resize
or reparent the guest. Closing an installer with an active operation still uses
the existing busy-operation protection. Pointer/top-edge revelation is retained.
The floating controls affect only their own bounds, not underlying gestures
elsewhere in an app. Third-party application interfaces are not restyled.

Validation covers native viewport/safe-area arithmetic, fitting new windows
above the Dock on short and wide canvases, compact/standard initial sizing,
fullscreen minimise/restore identity and geometry, fullscreen close, touch Dock
spacing, existing folding/tiling restoration, source and package guards, and
browser/ChatGPT regressions. The device workflow compiles only an unsigned
SideOS IPA with the iOS 27.1+ SDK gate. Hardware touch delivery, haptics and
appearance in individual hosted apps still require device verification.
