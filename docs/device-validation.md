# Physical-device release checklist

Record IPA build number, source SHA, device, iPadOS, install/sign method and result.
The workflow creates an unsigned IPA. It does not perform this checklist.

- [ ] Cold launch; relaunch a 21+ tab, 41+ window session. Selected pages restore without clicking; sleeping pages explain their status. Test corrupt current workspace with valid previous backup.
- [ ] Personal, Work and Private cookies/history/restore isolation. Work restore opt-in. No Private URL/title in exported backups/history or closed entries.
- [ ] ChatGPT login, temporary chat, unsent draft, streaming response. Close via inner tab, outer tab, window, Quit, navigate and disable integration; warnings preserve protected work.
- [ ] Split ChatGPT composer visible at both panes during scroll, keyboard, sidebar, resize and rotation. Swap/Exit/reopen, long titles, RTL. Never include chat content in diagnostics.
- [ ] Long-press tab reorder/detach/merge and cancellation; reject incompatible-profile transfers without losing a page. First click focuses/selects; double-click still works.
- [ ] Browser new navigation starts below toolbar; scroll underlap remains. Find, redirects, target=_blank, about:blank opener OAuth, Downloads resume after suspension/relaunch, Reader, PDF, Print and Share.
- [ ] Optional camera/mic permission origin/profile decisions and deny handling. Tracker-block exceptions. Local development URLs and explicit external-app confirmation.
- [ ] Active tab alone selected; native pointer/press feedback, disabled controls, light/dark, Reduce Motion/Transparency, large text, VoiceOver, compact/comfortable targets.
- [ ] Move, resize, minimize/restore, close, overview, narrow tile/rotation/shared divider. Measure own-host main-loop samples separately from rendered FPS and WebKit subprocess memory.
- [ ] Multiple Finder windows, reveal selected file, desktop rename and undo placement, Copy then newer Copy during paste, cancel transfer, batch conflict/rollback, Trash original restore, PDF and download destination.
- [ ] Web-app and guest icons/pinning/recents/window picker; rapidly queue native launches, background while starting, return, JIT timeout/recovery and guest termination. Test supported devices/iPadOS/signing identities.
- [ ] Menu hover crossing and submenu pointer corridor; only one menu open. Keyboard ownership with Management, dialog, share, translation and fullscreen popovers.
- [ ] Agenda denied/allowed; Scratchpad persistence; calculator; offline help; local backup import/recovery and owner-signed resource update/tamper/rollback.

Do not enable multiple iPad scenes or external-display guest hosting until the
private guest-scene lifecycle and process handoff are tested. No such support is
claimed by the workspace injection seam alone.
