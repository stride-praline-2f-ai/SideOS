# Older desktop appearing after restart

The current SideOS shell has a unified browser toolbar, modern window controls,
Dock artwork and Settings/About. Session restoration saves layout and URLs; it
does not contain executable UI or a selectable legacy desktop renderer. The host
loads its UI framework from the installed app's own Frameworks directory.

An old-looking screenshot alone does not identify the running executable. Check
Apple menu → About or Settings → About for the version, build and source. Build 14
was 3.1.0 / `a3ed60e1`. A missing build/source readout is evidence to check which
copy or IPA was installed. An external sideloader can also reinstall its stored
older IPA; replace that tool's source IPA when updating the app.

## Confirmed refresh gap and correction

The pinned installer's Refresh All service paired installed app IDs with the first
matching local IPA without checking its source revision. Host signing repair
already required the installed revision, but generic refresh did not. This could
replace the entire SideOS binary with an older local IPA, affecting the Dock,
window chrome, settings and browser together. It has not been established that
this caused the reported screenshot.

Self-refresh now checks the actual host identity and requires the IPA's embedded
source revision to match the installed host before signing or installing. Missing
and different revisions fail closed. Normal explicit Install remains available
for intentional version changes. Other app refresh and all existing signing,
team, entitlement, queue and refresh-lease checks are retained.

The guard is applied to pinned installer source before the guest cache key. Its
changed source invalidates only that component; host/JIT/FFI cache inputs remain
unchanged. Packaging additionally checks the actual UI/installer executables for
modern-shell capabilities and the refresh gate, and records executable SHA-256s.
Editing a version plist or including modern source notices cannot satisfy it.

No bookmarks, cookies, downloads, tabs, layouts, certificates or saved preferences
are removed by this repair. Update the existing installed app with the new IPA;
deleting its data is not part of the repair. Device restart and refresh validation
still require the installed version information and an iPad test.
