# Wireless extended display — experimental

Install the same current SideOS IPA on both devices. This is a display-only Wi-Fi
link: apps run on the host, while the second device receives an independent
presentation. Mouse, keyboard, touch, clipboard and file commands are not sent
back. It does not connect to the Henge app or start a macOS virtual machine.

## Connect

1. Connect both devices to the same trusted local Wi-Fi network. Guest networks
   may block peers. Keep both SideOS apps in the foreground.
2. On the host, open **Settings → Wireless Display → Extend this SideOS desktop**.
   Allow Local Network access. Note the nearby host suffix and session key.
3. On the second device, open **Settings → Wireless Display → Use this device as
   a display**. Rotate first, select the matching host, enter its 43-character
   key and connect. Allow Local Network access here too.
4. On the host, use **Window → Move to Wireless Display**, the app's Dock context
   menu → **Display Placement**, or the window list in Wireless Display settings.
5. The chosen window fills the second screen. Selecting a different remote
   window in the host's Dock changes the shown app. The main display remains
   available for other windows. **Bring to Main Display** returns a window for
   interaction; remote input is deliberately absent.
6. Stop sharing on either device to return every window to its main-display
   placement. Backgrounding, a broken connection, capture/codec failure or host
   memory pressure also ends the session. App processes and browser sessions are
   retained across a display move rather than relaunched.

If discovery is blocked, choose **Use manual IP and port** on the viewer. Find
the host's private IPv4 address in iOS Settings → Wi-Fi → network information;
use the port currently shown in SideOS. No cloud account, internet relay, public
endpoint or port forwarding is required. This feature does not implement USB or
an AirPlay receiver. The viewer does not need JIT or an installed copy of a guest.

Three-finger tap hides/shows the viewer's local controls. Disconnect/status is
revealed on failure so the last image is not presented as a live stream. Rotate
before pairing; reconnect to negotiate a new size after rotation or folding.

## Scope and limitations

All SideOS window kinds can be assigned to the display, including LiveContainer
management, hosted apps and SideInstaller. This first version presents one
selected app window at a time on the second screen. Native app operations and
file pickers remain on the host. It is not an additional OS-level iOS display.

The source uses a separate non-key UIKit presentation window, UIKit hierarchy
capture and hardware H.264 encode/decode. iOS can omit protected/uncapturable
layers, and a successful draw call does not prove every remote scene's pixels
were captured. **Physical testing of LC/SideInstaller capture on a host/viewer
pair is still required.** This implementation must not be described as verified
support for every hosted application. A failed capture returns windows locally;
blank protected content cannot always be detected automatically.

Native pixel dimensions and logical window size are negotiated from the actual
viewer viewport. Odd dimensions receive at most one padding pixel, excluded by
a clean-aperture crop. There is no guessed Duo resolution. The initial capture
path is capped at 60 fps, with capture time included in each frame period. Actual
delivery depends on capture, encoding, decoding and the network. It is not Henge's
zero-copy VM Metal path, a lossless monitor or a measured sustained-rate claim.

## Pairing and bounds

The per-session random 256-bit key authenticates TLS 1.2 PSK with AES-GCM. No
plaintext or certificate-bypass fallback is provided. Bonjour advertises an
opaque random service ID, not a device/user name or key. Keys are memory-only,
rotated on restart and not written to logs/preferences/source. The optional
copy action uses a local-only clipboard item expiring after five minutes.

Only share with trusted devices. Possession of the current key permits viewing
the projection while the host listens. This does not add isolation from
malicious LC apps: the browser/security warnings still apply, and this is not a
security certification. Do not share sensitive content through an untrusted host.

The protocol accepts only negotiation, acknowledgements, keepalive and shutdown
messages. No input/launch/file commands exist. Packet size, control rate,
display geometry, codec parameters and decode queues are bounded. Two frame
credits cover capture, encode, send and actual decoder consumption, with
out-of-order send/ACK handling and an ACK timeout. Presentation uses one
replaceable pixel buffer, preventing an unbounded main-thread frame queue.

## Validation

Linux tests cover hostile framing/metadata, forbidden commands, geometry,
fragmented receives, credit ordering and all window-kind placement/recovery.
The device workflow also runs a small native Mac hardware-codec fixture covering
BGRA → H.264 → BGRA, odd-size clean aperture and decode ACK. This is neither a
simulator build nor an iOS hosted-scene test. A second short native loopback
fixture verifies TLS-PSK negotiation, wrong-key rejection and refusal of an
inbound input command. It does not establish physical Wi-Fi behaviour. The IPA still links all four owned
components with the actual iOS 27.1+ SDK and retains the existing refresh guard.

On physical devices, check LC, a normal hosted app, SideInstaller and a browser:
compare the actual app content, switch remote windows, bring each back without
relaunch, fold/rotate/reconnect, background each side, interrupt Wi-Fi and stop
sharing during an idle app. Confirm the primary screen's layout and input stay
local. Do not perform destructive installer operations as a display test.

The design was informed by the user's Henge Link work in
[henge-](https://github.com/stride-praline-2f-ai/henge-), supplied as a pinned patch
over Henge `be027b492bac818a3bb0c76fc8bbdd7aee42cbd2`. SideOS uses its own
display-only protocol and UIKit presentation backend; Henge VM/GPU/HID sources
are not imported into this feature.
