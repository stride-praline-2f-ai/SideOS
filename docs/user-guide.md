> **Warning:** The embedded browser is not sandboxed away from hosted apps. Do not store sensitive details in it; malicious guests may access browser data. Use a trusted separate browser for sensitive activity.

# SideOS user guide

**SideInstaller by [FrizzleM](https://github.com/FrizzleM/SideInstaller), with
LiveContainer and StikJIT by their upstream contributors.** [Full credits](../CREDITS.md).

## Appearance

Settings → Appearance offers Light, Dark, OLED Black and System. OLED Black uses
pure black for SideOS's solid backgrounds and browser toolbar; it does not recolour
websites or third-party apps. Native Glass Dock materials keep their optical effect;
the Solid Dock and Reduce Transparency fallback use black in OLED mode.

The Dock defaults to 48 pt icons (about 40.3 pt in Compact mode), with automatic
fitting and at least 44 pt touch slots. The fully transparent desktop/windowed menu
bar is on for new/unset preferences, without changing saved choices or fullscreen.

## Desktop and windows

For a second SideOS device over Wi-Fi, see [Wireless extended display](wireless-display.md).
The experimental display-only mode lives in Settings → Wireless Display; no
remote controller/input mode is included. All window kinds can be placed there,
but hosted-scene capture needs physical device verification.

Tap an app in the Dock or Applications to open it. An app with several windows
shows a window chooser when its Dock icon is tapped. Drag a window's title bar
to move it. Drag either bottom-corner grip to resize it; the same controls work
for native screens and hosted LiveContainer apps. Red closes, yellow minimises,
and green enters/exits fullscreen. Hold green for additional layouts. Restore a
minimised window from the Dock. Window → Arrange Window offers tiling and filling.

In fullscreen, hover at the top-left to reveal the menu and traffic lights.
Without a mouse, use the visible glass ellipsis at bottom-right for Minimise,
Restore, Windows and Close. Existing installer busy-operation protection still
applies to Close. Escape or Control-Command-F also exits fullscreen.

Open **LiveContainer** from the Dock/Applications for its Apps, Sources, Tweaks and
Settings tabs in a regular window. Configure JIT and install your own trusted
apps there. Apps needing helper processes/RAM donors currently use upstream
Classic Mode; they are not made compatible with hosted windows by this interface.

## Browser and ChatGPT

Tap the address field to search or enter a URL. Narrow windows put secondary
commands and browsing profiles in the ellipsis menu. Hold and drag a tab onto
the desktop to make another window. On chatgpt.com, enable **Chats** to show the
conversation row. Use its chat options for split view. If missing, check the
ChatGPT chat-tabs setting and reload the page; website changes can affect the adapter.

Personal and Work profiles keep separate WebKit stores; Private is temporary and
is not restored. This is browser profile separation, not a security boundary
against malicious hosted apps. macOS Enhanced Spoofing is the fresh-install
browser default; it changes website identity signals, not the underlying OS.
Choose iPadOS Original if a site breaks.

## SideInstaller

Open SideInstaller from the Dock. Choose IPA imports a file through the host's
Files picker. Allow iCloud files to download before choosing them. Home shows
registered IDs, device apps, Memory+ only when signed entitlement evidence exists,
and refresh times recorded by SideInstaller. Missing or externally performed
refresh history is shown as not recorded. Sign in/configure your own credentials
through the installer's setup. Refresh before your provisioning expires.

## Appearance and diagnostics

Settings → Dock selects Native Clear, Native Regular or Solid. Native system glass
requires iOS 26+ and follows Reduce Transparency. Other panels/menus start opaque;
their slider is independent of the Dock and control buttons. Settings → Windows
changes desktop density and touch feedback. Wallpaper uses centred aspect fill:
when too wide, both sides lose the same amount; when too tall, top/bottom crop equally.

About → Diagnostics identifies the build/source revision and display dimensions.
Include it in a bug report, with reproduction steps and device/OS details. Remove
account names, browsing history, pairing data, tokens and personal content.

Built-in JIT has a guided setup in **SideOS Settings → Built-in JIT**, including a link to the existing pairing/preparation controls. Device preparation is separate from enabling JIT for each launched guest.
