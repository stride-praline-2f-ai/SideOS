# Desktop glass and hosted fullscreen controls

The SideInstaller Home and refresh-source guard from the device-tested
`2b65c4a46a8f18ca706fb12d47559238020d7776` are already ancestors of main.
This change retains both and the existing bundle identity/data paths.

Dock and nonfullscreen menu surfaces use native clear Liquid Glass on iOS 26,
with the material fallback on earlier releases and solid surfaces when Reduce
Transparency is enabled. Dock clarity adjusts the material tint, not icon
opacity. The extra painted Dock rim is removed.

The saved transparent-menu preference now applies on the desktop and with any
windowed app focused. Its stored key is unchanged. Fullscreen retains its
existing menu-bar material, black backing and controls, independent of that
preference. Window chrome is no longer drawn around fullscreen content; hosted
windowed apps retain one subtle edge rather than a double bright border.

The fullscreen reveal target includes the top-left menu-height corner as well
as the existing six-point top edge. It is above hosted scene content and does
not rely solely on remote-app hover delivery. Revealed controls retain pointer
tracking while crossing from the menu bar into traffic lights; the UIKit
observer converts pointer coordinates into the desktop observer's space.

Portable tests cover reveal geometry, the fullscreen/accessibility transparency
exclusions, and a single-SideOS-IPA workflow contract. All four binary recipe
fingerprints remain unchanged; only host source inputs need rebuilding. The
workflow keeps its required package/component/rollback verification gates.
Native compilation validates API use; physical-device appearance and pointer
behaviour still require checking on iPad.
