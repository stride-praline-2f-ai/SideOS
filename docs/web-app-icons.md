# Custom web app icons

Applications → … → Add Web App → Choose Icon opens the editor before adding.
Choose Photos or Files, drag the image inside the rounded square, and use Zoom
or the horizontal/vertical position sliders to select the crop. Save returns to
the add form. Existing pins expose Edit Icon… from Dock, Applications and the
Applications panel context menus. Use Website Icon removes the custom crop.

The same crop geometry drives the preview and 512×512 PNG output. Source images
are decoded off the main actor with ImageIO orientation correction and downsampled
to a maximum 1024 pixels. Input is limited to 25 MB. A source copy is kept under
web-icons/<pin UUID>.png for later crop edits; only final icon data and crop
metadata enter the existing web-app catalogue. Cancelling the editor leaves the
pin unchanged. Unpin removes that copy. A custom icon fills the app icon mask;
automatic favicons retain their existing inset. Pending favicon requests check
customIcon again before updating the record.

Build repair: the previous host compilation failed because the Notes/Calculator
web-icon special cases were mistakenly inserted in TahoeNativeAppIcon, where
`link` resolves to a C function rather than a TahoeWebLink. They are now in
TahoeWebAppIcon; native guest artwork again uses only its LCAppModel.

Validation: core/lifecycle, website identity, motion and crop geometry tests pass.
Crop fixtures cover landscape/portrait/square, min/max zoom and pan extremes,
coverage of the output square, and invalid sizes/non-finite inputs. Swift syntax
parsing passes. Local package checks: 15 passed, 4 macOS-only skips. Native SwiftUI
compilation, picker/crop interaction and physical-device appearance remain subject
to the replacement SDK build and device validation; no new IPA is claimed ready
until that workflow completes.
