# SideInstaller IPA picker repair

Home used SwiftUI fileImporter, although the pinned install screen documents
untappable file rows on iOS 27 and already uses UIDocumentPickerViewController.
IPA type filtering also depended on how individual Files providers classify
an IPA (IPA, ZIP or generic data).

Home, Install and signing repair now share the existing UIKit/asCopy picker.
It shows files without the IPA-only UTI filter; Engine still validates a staged
copy before replacing the custom IPA. Repair still requires the installed
bundle identity and exact source revision. Cancellation performs no import.

The shared modifier dismisses the picker before handing off its temporary URL.
Home waits for a successful import before selecting Custom and switching tabs,
and disables both install-entry buttons while an import is in progress.
Repair uses Engine's existing temporary-directory-only cleanup even when its
revision check rejects the selected copy. Pairing-file selection is unchanged.

Validation: checked patches applied to the pinned source, release/refresh guard
and cache policy checks, followed by the required workflow checks and device
compilation. Only guest sources change; desktop/JIT/Rust caches remain eligible.
No simulator or preview job is requested. The device workflow produces one
SideOS IPA with the embedded installer.

On iPad, check Home and Install imports from local Files and iCloud, cancel and
reopen the picker, and select a non-IPA to confirm it reports an error while
keeping the previous valid import. Check that repair rejects a different build.

## Hosted runtime correction after build 7

Build 7 opened Files but files remained untappable on the user's iPad. Its
native UIKit selection path was therefore insufficient. Investigation of the
pinned LiveContainer source and the actual build-7 IPA found that the built-in
installer's TweakLoader load used `Frameworks/TweakLoader.dylib` relative to
`PlugIns/LiveProcess.appex`. The IPA contains that library only in the parent
application's Frameworks folder. The built-in app metadata disables ordinary
tweak injection, making this explicit bootstrap load necessary.

The hosted path now uses `../../Frameworks/TweakLoader.dylib`; classic in-app
launch keeps its existing app-relative path. This loads LiveContainer's original
DocumentPicker constructor, which automatically enables its DOCConfiguration
host-identity correction for the built-in installer. It uses the process's actual
signed application identifier. No legacy always-successful security-scope hook,
Inbox symlinking or additional shared-directory grants are enabled.

Bootstrap records whether the library loaded and whether the host-identity setter
points into TweakLoader. Opening an IPA picker copies that status into the
existing installer log as `Files access runtime: ...`. This is a diagnostic,
not a claim that a device permission or UI test has passed.

The release gate now requires the corrected bootstrap and original identity-hook
library in their real packaged locations and fingerprints both. Regression
fixtures reject the old loader, a misplaced library and a missing identity hook.
Physical iPad testing remains necessary for successful Files selection/import.
