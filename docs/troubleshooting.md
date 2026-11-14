# Troubleshooting

| Symptom | What to check |
| --- | --- |
| Installation fails or app closes immediately | Confirm correct signing, extensions, provisioning and required entitlements with your signer. Use your own certificate and current upstream requirements. |
| Large black bars on Duo | Check About source/build and real SDK in the release manifest. Install a build linked with SDK 27.1+; changing Info.plist labels does not fix a legacy linked SDK. Fully reopen unfolded. |
| Hosted app needs JIT | Open the LiveContainer window and configure its supported provider/pairing path. An unsigned IPA does not grant JIT automatically. |
| Helper/RAM-donor app will not open in a window | Use the upstream Classic Mode path. Do not assume helper processes work with hosted LiveProcess windows. |
| Fullscreen window controls missing | Hover at top-left, or use the bottom-right glass ellipsis. Verify you installed the release containing this fix in About. |
| Files are greyed out | Select a real .ipa, download it from iCloud first, and open the host-owned picker from SideInstaller Home. Include the source/build and a redacted recording if it persists. |
| All App IDs used | Check the active Apple account and registered extensions. Existing signing does not prove a new profile/identifier is unnecessary. Do not delete registrations blindly. |
| Self-refresh rejects a build | Expected when its source differs or is unknown. Install the desired signed IPA explicitly over the current app identity instead of using Refresh to upgrade. |
| Login/site breaks with macOS spoofing | Switch browser identity to iPadOS Original or macOS Safari and reload. Enhanced spoofing cannot provide Mac-only APIs. |
| Glass looks opaque | Check Reduce Transparency, Solid Dock style, OS support and the independent panel/menu slider. |
| New defaults did not apply | Upgrades preserve explicit saved preferences. Select the desired style/wallpaper manually. |

For unresolved problems, use the repository's Bug Report issue template. Include
exact steps, expected/actual behaviour, source/build, device/OS and whether it
occurs with third-party apps closed. Never attach credentials, certificates,
provisioning profiles or pairing records. No support through a private chat is required.

## SideInstaller opens on iPad but exits on iPhone

The LiveContainer management window opening does not prove the separate
LiveProcess installer can start. The exit banner can hide a more specific startup
error. The launch path now preserves a late initialization error, gives each
reopened session a fresh controller identity, and seeds guest scene geometry from
the measured window instead of allowing a zero-size initial frame. These changes
are regression-tested in code; the reported iPhone failure still requires device
confirmation in a later installable build. Use **Copy Error** and About diagnostics
if it persists, after removing personal data. Pairing can be imported manually
from **Settings → Built-in JIT** if the installer is unavailable.
