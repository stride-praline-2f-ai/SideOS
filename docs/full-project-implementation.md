# Full-project implementation status

This tracks all 115 recommendations from the 2026-11-06 audit. “Implemented” means the code path is present in this release candidate, not that its device behavior has been verified. Portable tests, Chromium layout tests, native compilation and physical-device checks are distinct evidence. The Actions run for the exact source revision is the build authority.

## Delivered areas

- Session recovery, profile-aware metadata, protected drafts/forms, resource budgeting and explicit sleeping states.
- ChatGPT discovery, responsive split panes, geometry updates, reversible split actions, drag lifecycle and live-page transfer.
- Stable browser/web-app/native-app Dock identities, window arrangements, layout palette, shared tiling divider and Spaces options.
- Browser history, groups, site controls, Find, Reader/PDF/Print, icon fallbacks, downloads, provider choices and optional content blocking.
- Async file work, clipboard ownership, Trash restore, undo, batch rename, Finder transfer, search ranking and file details.
- Activity, queued guest launch/recovery, About/diagnostics, help, command palette, optional offline utilities and opt-in agenda.
- Optional signed ChatGPT resource updates; component recipe caches, exact-SHA validation reuse, warning gate and device-only packaging.

## Recommendation ledger

| ID | Recommendation | Status |
|---|---|---|
| R001 | Protect drafts through every close route | Implemented; native behavior requires the release checklist where applicable. |
| R002 | Stop silently dropping oversized restored sessions | Implemented; native behavior requires the release checklist where applicable. |
| R003 | Separate restore concurrency from resident-page memory | Implemented; native behavior requires the release checklist where applicable. |
| R004 | Give persistence a recovery path | Implemented; native behavior requires the release checklist where applicable. |
| R005 | Restore profiles deliberately | Implemented; native behavior requires the release checklist where applicable. |
| R006 | Provide session recovery and closed-browser-tab history | Implemented; native behavior requires the release checklist where applicable. |
| R007 | Persist stable tab metadata | Implemented; native behavior requires the release checklist where applicable. |
| R008 | Show restoration and sleeping states clearly | Implemented; native behavior requires the release checklist where applicable. |
| R009 | Stabilize split-view viewport and composer visibility | Implemented; native behavior requires the release checklist where applicable. |
| R010 | Implement the actual native drag-end callback | Implemented; native behavior requires the release checklist where applicable. |
| R011 | Clean up ordinary browser drags on cancellation | Implemented; native behavior requires the release checklist where applicable. |
| R012 | Refresh pane geometry when the root viewport moves | Implemented; native behavior requires the release checklist where applicable. |
| R013 | Remove repetitive layout restoration and forced measurement | Implemented; native behavior requires the release checklist where applicable. |
| R014 | Expose Chats where users expect it | Implemented; native behavior requires the release checklist where applicable. |
| R015 | Use available space for chat titles and focus | Implemented; native behavior requires the release checklist where applicable. |
| R016 | Support moving tabs into existing windows | Implemented; native behavior requires the release checklist where applicable. |
| R017 | Make split actions visible and reversible | Implemented; native behavior requires the release checklist where applicable. |
| R018 | Offer named chat workspaces and search | Implemented; native behavior requires the release checklist where applicable. |
| R019 | Test real DOM and layout variants | Implemented; native behavior requires the release checklist where applicable. |
| R020 | Separate browser and standalone-web-app Dock groups | Implemented; native behavior requires the release checklist where applicable. |
| R021 | Keep web-app identity in New Window actions | Implemented; native behavior requires the release checklist where applicable. |
| R022 | Keep window-picker opening and fullscreen changes atomic | Implemented; native behavior requires the release checklist where applicable. |
| R023 | Handle narrow tiling and rotation without losing layouts | Implemented; native behavior requires the release checklist where applicable. |
| R024 | Make Show Desktop transfer keyboard ownership | Implemented; native behavior requires the release checklist where applicable. |
| R025 | Profile minimize and overview snapshot costs | Bounded thumbnails and instrumentation added; hardware snapshot profiling pending. |
| R026 | Reduce desktop-wide invalidation | Linear stacking and scoped subscriptions added; whole-shell invalidation needs an Instruments comparison. |
| R027 | Offer a window layout palette | Implemented; native behavior requires the release checklist where applicable. |
| R028 | Save named window arrangements | Implemented; native behavior requires the release checklist where applicable. |
| R029 | Extend Spaces organization | Implemented; native behavior requires the release checklist where applicable. |
| R030 | Support shared-edge resizing for tiled windows | Implemented; native behavior requires the release checklist where applicable. |
| R031 | Add native-app pinning and recent launches | Implemented; native behavior requires the release checklist where applicable. |
| R032 | Prototype multiple scenes and external displays | Workspace injection and scene-window probe added; multiple scenes/external display activation remains a prototype, pending guest runtime testing. |
| R033 | Remove avoidable single-click selection latency | Implemented; native behavior requires the release checklist where applicable. |
| R034 | Apply disabled state to gesture callbacks | Implemented; native behavior requires the release checklist where applicable. |
| R035 | Make the browser glass preference truthful | Implemented; native behavior requires the release checklist where applicable. |
| R036 | Give each control one hover and press owner | Native control feedback retained and gesture ownership improved; device hover/press review pending. |
| R037 | Use semantic motion and geometry tokens | Existing motion policy retained and targeted transitions improved; not every hardcoded geometry/timing is centralized. |
| R038 | Offer compact pointer and comfortable touch sizing | Comfortable controls added to major surfaces; a complete touch target sweep remains. |
| R039 | Audit text size and contrast across the shell | Accent contrast and comfortable controls improved; full Dynamic Type/contrast audit remains. |
| R040 | Make window operations accessible without dragging | Implemented; native behavior requires the release checklist where applicable. |
| R041 | Scope keyboard commands to the visible owner | Implemented; native behavior requires the release checklist where applicable. |
| R042 | Define outer-tab versus inner-chat keyboard behavior | Implemented; native behavior requires the release checklist where applicable. |
| R043 | Add submenu pointer-intent handling | Implemented; native behavior requires the release checklist where applicable. |
| R044 | Use stable menu item identities | Implemented; native behavior requires the release checklist where applicable. |
| R045 | Give Calendar a moving keyboard focus | Implemented; native behavior requires the release checklist where applicable. |
| R046 | Cancel repeating controls on interrupted gestures | Implemented; native behavior requires the release checklist where applicable. |
| R047 | Support localization and directional layouts | 289 extracted UI keys, 72 core Spanish/Arabic translations and RTL fixes; remaining translations and bidirectional device review pending. |
| R048 | Show complete error details | Implemented; native behavior requires the release checklist where applicable. |
| R049 | Scope dialogs and share sheets to their owners | Implemented; native behavior requires the release checklist where applicable. |
| R050 | Track all fullscreen popover owners | Implemented; native behavior requires the release checklist where applicable. |
| R051 | Improve closing continuity | Close transition added; visual continuity needs real-device review. |
| R052 | Recognize local development addresses | Implemented; native behavior requires the release checklist where applicable. |
| R053 | Add Find on Page | Implemented; native behavior requires the release checklist where applicable. |
| R054 | Add searchable browsing history | Implemented; native behavior requires the release checklist where applicable. |
| R055 | Make bookmarks manageable | Implemented; native behavior requires the release checklist where applicable. |
| R056 | Add per-site permissions and data controls | Implemented; native behavior requires the release checklist where applicable. |
| R057 | Use appropriate authentication field semantics | Implemented; native behavior requires the release checklist where applicable. |
| R058 | Test popup and sign-in compatibility | Main-frame/opener guards corrected; authenticated popup/OAuth compatibility matrix pending. |
| R059 | Support intentional external-app handoff | Implemented; native behavior requires the release checklist where applicable. |
| R060 | Improve favicon candidate fallback | Implemented; native behavior requires the release checklist where applicable. |
| R061 | Test user-agent compatibility instead of guessing versions | No speculative UA version bump; live website compatibility matrix pending. |
| R062 | Add open-tab search and tab organization | Implemented; native behavior requires the release checklist where applicable. |
| R063 | Offer reading and offline page tools | Implemented; native behavior requires the release checklist where applicable. |
| R064 | Expose media-playing tabs and mute controls | Media indicator and pause/resume added; pause is not a true per-tab audio mute API. |
| R065 | Evaluate optional content blocking | Implemented; native behavior requires the release checklist where applicable. |
| R066 | Move file enumeration and recursive operations off the UI actor | Implemented; native behavior requires the release checklist where applicable. |
| R067 | Prevent an older paste from clearing a newer clipboard | Implemented; native behavior requires the release checklist where applicable. |
| R068 | Use grid geometry for arrow navigation | Implemented; native behavior requires the release checklist where applicable. |
| R069 | Preserve desktop icon placement through rename | Implemented; native behavior requires the release checklist where applicable. |
| R070 | Give Desktop its own folder | Implemented; native behavior requires the release checklist where applicable. |
| R071 | Support multiple Finder windows and file transfer | Implemented; native behavior requires the release checklist where applicable. |
| R072 | Restore trash items to their original locations | Implemented; native behavior requires the release checklist where applicable. |
| R073 | Add undo and operation-level recovery | Implemented; native behavior requires the release checklist where applicable. |
| R074 | Add preview and file information | Implemented; native behavior requires the release checklist where applicable. |
| R075 | Add batch rename and conflict resolution | Implemented; native behavior requires the release checklist where applicable. |
| R076 | Make Spotlight work cancellable and ranked | Implemented; native behavior requires the release checklist where applicable. |
| R077 | Reveal the actual search result in Finder | Implemented; native behavior requires the release checklist where applicable. |
| R078 | Include open windows and chats in global search | Implemented; native behavior requires the release checklist where applicable. |
| R079 | Use download resume data | Implemented; native behavior requires the release checklist where applicable. |
| R080 | Give downloads history and useful progress | Implemented; native behavior requires the release checklist where applicable. |
| R081 | Add file favorites and recent locations | Implemented; native behavior requires the release checklist where applicable. |
| R082 | Queue rapid native-app launches visibly | Implemented; native behavior requires the release checklist where applicable. |
| R083 | Pause the guest watchdog during app suspension | Implemented; native behavior requires the release checklist where applicable. |
| R084 | Make guest recovery actionable | Implemented; native behavior requires the release checklist where applicable. |
| R085 | Create a host activity center | Implemented; native behavior requires the release checklist where applicable. |
| R086 | Validate lifecycle and private-scene compatibility | Existing private scene and guest contracts preserved; physical lifecycle/JIT matrix pending. |
| R087 | Name guest identities by what they contain | Implemented; native behavior requires the release checklist where applicable. |
| R088 | Measure background keep-alive costs | Opt-in main-loop and host memory capture added; energy/background keep-alive costs have not been measured. |
| R089 | Show installed version, build and source revision | Implemented; native behavior requires the release checklist where applicable. |
| R090 | Correct stale settings and coverage documentation | Implemented; native behavior requires the release checklist where applicable. |
| R091 | Add lightweight first-run discovery | Implemented; native behavior requires the release checklist where applicable. |
| R092 | Offer privacy-aware diagnostic export | Implemented; native behavior requires the release checklist where applicable. |
| R093 | Bound photo and icon preparation work | Bounded icon fetch/downsample and crop geometry retained; photo decode peak memory profiling pending. |
| R094 | Add a focused command palette | Implemented; native behavior requires the release checklist where applicable. |
| R095 | Evaluate optional offline utilities | Implemented; native behavior requires the release checklist where applicable. |
| R096 | Evaluate a real agenda integration | Implemented; native behavior requires the release checklist where applicable. |
| R097 | Design a SideOS-aware update channel | Private build links, exact version/SHA and artifact release manifest added; no automatic signing or installer bypass. |
| R098 | Consider a constrained resource-update loader | Constrained signed adapter loader implemented; an owner-controlled feed/key must be configured to use remote resources. |
| R099 | Split Browser by responsibility | Implemented; native behavior requires the release checklist where applicable. |
| R100 | Reduce singleton coupling with scoped services | Root workspace injection and per-page ownership added; shared coordinator/services remain. |
| R101 | Use typed resource and command identities | Application identity and native path naming are typed; not all string commands have been replaced. |
| R102 | Cover packaging changes in cheap CI triggers | Implemented; native behavior requires the release checklist where applicable. |
| R103 | Fingerprint exact build recipes without unrelated workflow churn | Implemented; native behavior requires the release checklist where applicable. |
| R104 | Avoid redundant cheap checks only with same-SHA evidence | Implemented; native behavior requires the release checklist where applicable. |
| R105 | Triage compiler warnings and prevent new ones | Zero desktop-warning gate added; inherited engine warnings remain separately visible. |
| R106 | Expand tests around lifecycle contracts rather than implementation mirrors | Implemented; native behavior requires the release checklist where applicable. |
| R107 | Create a physical-device release checklist | Checklist committed; execution requires physical device. |
| R108 | Publish the actual validation and dependency boundary | Coverage and boundary documentation corrected; device evidence remains separate. |
| R109 | Review packaged source/notices deliberately | Packaging notices/source inventory retained and workflow reference corrected; full dependency/license counsel review is outside this source review. |
| R110 | Preserve pinned-engine integration contracts | Pinned engine and serial signing/JIT/FFI contracts preserved; device compatibility not established by source checks. |
| R111 | Expose search-suggestion and provider choices | Implemented; native behavior requires the release checklist where applicable. |
| R112 | Keep bridge-origin restrictions under regression test | Implemented; native behavior requires the release checklist where applicable. |
| R113 | Provide clear local-data and backup controls | Implemented; native behavior requires the release checklist where applicable. |
| R114 | Make website identity inspectable | Implemented; native behavior requires the release checklist where applicable. |
| R115 | Refine native glass hierarchy rather than adding optical layers | Implemented; native behavior requires the release checklist where applicable. |

## Evidence and limits

Local verification: nine portable Swift executable groups; 22 DOM fixtures; 14 real Chromium layout checks; 17 Python policy/build/signing tests; Swift frontend parsing; whitespace checks. Native Apple SDK compilation and the owner-signature CryptoKit executable run in the device workflow. No simulator/preview builds are requested.

A successful IPA proves compilation and package checks, not installed execution. No physical frame-rate, energy, thermal or memory comparison is claimed. Chromium fixtures do not substitute for authenticated ChatGPT on iPad WebKit. No credentials, cookies, chat text, screenshots or signing keys are included in diagnostics or workspace backups.

The engine review covered targeted pinned integration files; it was not a complete transitive dependency, cryptography or private-scene compatibility audit. Preserve upstream signing/team checks, process handoff and serial queues. See [device validation](device-validation.md) and [resource updates](signed-adapter-updates.md).
