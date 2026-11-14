> Historical development report. Account-specific links were removed for public sharing; relative source links now refer to the current tree.

# SideOS3: full project review and improvement backlog

Reviewed 6 November 2026 against application source **`fd1681e3b4e75e0c877e21c57624c387ff18ada7`** in **`earlier development repository`**. This report describes the current implementation, including the new automatic-tab-restoration change. It is a review and implementation backlog; the suggestions below have not all been implemented.

## Overall assessment

SideOS is already a substantial working desktop shell, rather than a static visual mock-up. Browser profiles, multiple windows, Spaces, guest hosting, downloads, real ChatGPT panes, live tab detachment and system Liquid Glass are present. The strongest next improvement is consistency: a page should keep its draft through every exit path, an app should have the same identity from every launch surface, and pointer/keyboard/touch actions should produce immediate, predictable feedback.

The remaining roughness spans three layers. There are concrete correctness problems in close handling, restore limits and input callbacks; resource-management gaps around resident WebViews, snapshots and filesystem work; and product gaps in discoverability, browser tools and window/file organization. More visual effects alone will not resolve the first two layers.

## Scope, evidence and limits

- Reviewed the private shell source families across browser/runtime/restoration, ChatGPT adapter, window state and motion, Dock/apps, menus/controls, files/downloads/search, settings/assets, persistence and build/packaging. The current tree contains roughly 8,905 lines of production Swift across 48 files, plus portable test files and supporting JavaScript/Python/shell/workflows.
- Followed the pinned engine boundaries through targeted runtime, host, launch, signing, account, refresh, logging, download, device-connection and Rust FFI files at the revisions in `Engine.lock.json`. This is **not** a claim that every line of every upstream dependency, private runtime or cryptographic implementation was audited.
- Reviewed the complete **2:01.69** supplied recording, with denser frame sequences around enlargement, movement, ChatGPT split view and menus. The export is **1200×900 at approximately 48.98 fps** and effectively silent. It establishes visible symptoms, not application frame time or CPU/GPU attribution. The user's recording and chat screenshots are not included in this repository report.
- No live authenticated ChatGPT DOM, Instruments trace, memory profile or new physical-device before/after capture was available for this review. Candidates are labelled accordingly. No simulator or preview build was requested.
- Evidence links below are pinned to the reviewed application commit. A code link supports source findings or identifies the extension point; an addition is not a claim that the linked source is defective.

## What is already completed and verified

**Automatic restoration is implemented and its device IPA built successfully.** Selected pages are prioritized; other restored pages load through a shared two-slot queue without requiring selection. The driver handles foreground suspension, cancellation, stalled requests and bounded process recovery. WebKit's opaque white backing was also cleared to address the enlargement flash. The visual effect of that backing change still needs an on-device comparison.

- Successful device build and IPA (historical account link omitted), artifact **SideOS3-Device-IPA**, source **fd1681e3**.
- Successful Linux checks for that exact source (historical account link omitted).
- Verification included eight core executable groups, the actual restore-driver regression tests, 22 ChatGPT DOM fixtures, four build-Rust tests, four workflow-policy tests, Swift syntax checks, workflow linting and native device compilation/package generation.
- The native run reused exact JIT, FFI and installer component caches; only the changed host needed rebuilding. There was no simulator/preview job. This documentation review does not request another IPA.

## Findings that matter first

1. **Draft protection is inconsistent.** Closing an individual inner chat protects its draft; some outer close/leave routes bypass that check.
2. **Restoration can silently discard session overflow.** Loading only the first 20 tabs or 40 windows is not sufficient if saving permits more.
3. **Concurrent loading is bounded, resident memory is not.** Restoring everything still needs a measured memory-pressure policy.
4. **ChatGPT viewport behavior needs a focused layout fix.** The recording shows disappearing top controls and displaced composers during split/keyboard interactions.
5. **The native chat drag-end delegate method is wrong.** A successful compile contains a warning that explains the missing cleanup callback.
6. **Input and app identity have small, visible inconsistencies.** Single-click delay, nonfunctional glass slider values, browser/web-app Dock grouping and keyboard ownership deserve early fixes.
7. **Filesystem work can block the main actor.** Large folders or recursive operations should not make the entire desktop feel rough.

## How to use the backlog

**P1** means correctness/data preservation or a major resource/responsiveness risk worth addressing before adding complexity. It does not mean every affected user encounters it today. **P2** is the next quality/capability layer. **P3** is an optional extension or a longer-term experiment.

**Confirmed** means a source path establishes the behavior; **Observed** means the recording demonstrates the symptom; **Candidate** means profiling or runtime testing must establish impact; **Addition** means proposed product functionality; **Architecture** means a structural change to enable safer evolution. No unverified candidate is presented as a measured performance defect.

Effort is a rough engineering sizing aid, not a delivery promise: **S** about a day or less, **M** several days, **L** about one to two weeks, **XL** a multi-week initiative including integration/validation. Sizes assume familiarity with this project; device/runtime uncertainty can increase them.

The [CSV backlog](project-audit-2026-11-06.csv) and [JSON backlog](project-audit-2026-11-06.json) contain the same items for sorting or turning selected work into issues. Review priority and dependencies before scheduling; do not treat the whole list as one implementation batch.

## Backlog size

115 individually described items: 7 P1, 87 P2, 21 P3. These combine defects, investigation targets and optional additions; they are not all current bugs.

## Session safety and browser lifecycle

### R001 — Protect drafts through every close route

**P1 · Confirmed · M**

Closing one inner chat checks draft/generating status, but closing its outer browser tab or window, or leaving the workspace, can release the same pages without that aggregate check.

**Change:** Use one asynchronous close/leave decision for chat, tab, window, integration toggle and navigation. Ask once for the affected pages. Preserve the existing rule that chat text is not collected through the bridge.

**Verify:** Exercise each exit route with a draft, a streaming response, a clean chat and a cancelled confirmation.

**Source:** [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift).

### R002 — Stop silently dropping oversized restored sessions

**P1 · Confirmed · M**

Ordinary browser restore takes the first 20 URLs, window restoration takes 40 windows, and a saved chat workspace exceeding 200 URLs is rejected. Creation and saving do not consistently enforce the corresponding limits.

**Change:** Keep overflow URLs in a recoverable archive or enforce an explicit creation limit. Restore the selected item and window-to-session mapping deterministically; show the user when part of a session is deferred.

**Verify:** Round-trip 21 tabs, 41 windows and 201 chats, including a selected item outside the first range, without silently losing addresses.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/ChatWorkspaceState.swift](../embedded/tahoe/ChatWorkspaceState.swift).

### R003 — Separate restore concurrency from resident-page memory

**P1 · Confirmed · L**

The new queue caps simultaneous restoration starts at two. Hidden loaded WKWebViews are still retained, and there is no measured resident-page budget or memory-pressure/thermal policy.

**Change:** Introduce active, protected-background and safely-suspendable page states. Back off queued work on pressure, and only unload eligible pages. Protect drafts, active media, uploads, downloads and streaming chats.

**Verify:** Measure physical-device memory and process terminations at increasing tab counts. Verify that pressure recovery never destroys a protected page or starts a reload loop.

**Source:** [embedded/tahoe/PageRestoration.swift](../embedded/tahoe/PageRestoration.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R004 — Give persistence a recovery path

**P1 · Confirmed · M**

Atomic writes protect against a partially written single file, but session/preferences storage has no last-known-good snapshot or explicit migration/recovery workflow. Decode failures can fall back to defaults.

**Change:** Add versioned migration, a bounded previous snapshot, and a recover/reset choice. Move serialization and disk work off the main actor using immutable snapshots and ordered writes.

**Verify:** Load older, truncated, unknown-version and partially malformed fixtures; interrupt saving; ensure recovery preserves the last useful session and does not resurrect Private pages.

**Source:** [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift); [embedded/tahoe/Preferences.swift](../embedded/tahoe/Preferences.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift).

### R005 — Restore profiles deliberately

**P2 · Confirmed · M**

Saved browser entries contain addresses and selection but no profile identity. Personal URLs are persisted while Work URLs are excluded; a restored window can retain a Work-looking title while becoming Personal. Private-only windows can return as default Personal windows.

**Change:** Save an explicit restorable profile ID, offer opt-in Work session restoration, and omit Private-only windows. Keep the already separate website data stores separate.

**Verify:** Restart mixed Personal/Work/Private windows and verify title, selected profile, addresses and cookie-store identity. This is a restoration mismatch, not evidence of cookie leakage.

**Source:** [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R006 — Provide session recovery and closed-browser-tab history

**P2 · Addition · M**

Inner chats have reopening support, but outer browser tabs do not have an equivalent durable, discoverable recovery history.

**Change:** Add Reopen Closed Tab, recently closed windows and a URL/layout-only recovery panel. Bound retention, exclude Private browsing and make Clear History understandable.

**Verify:** Recover a closed multi-chat tab, a normal tab and an entire window; verify no private addresses or message bodies enter the archive.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/ChatWorkspaceState.swift](../embedded/tahoe/ChatWorkspaceState.swift); [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift).

### R007 — Persist stable tab metadata

**P2 · Addition · M**

Browser snapshots do not preserve stable outer-tab identity, per-tab zoom or a fuller set of presentation metadata.

**Change:** Introduce a versioned tab descriptor for URL, profile, stable ID and user-controlled zoom/pinning. Keep transient WebKit objects and sensitive form contents outside the descriptor.

**Verify:** Restart reordered tabs with different zoom levels and ensure restoration and history point at the same logical tabs.

**Source:** [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R008 — Show restoration and sleeping states clearly

**P2 · Addition · M**

Automatic restoration now works without selection, but users still need to distinguish queued, loading, failed and intentionally unloaded pages.

**Change:** Use a small consistent tab status affordance with Retry and Keep Awake actions. Surface one useful failure reason instead of an indefinite spinner or automatic retry storm.

**Verify:** Test offline startup, authentication failure, a hung navigation, process termination and background/foreground transitions.

**Source:** [embedded/tahoe/PageRestoration.swift](../embedded/tahoe/PageRestoration.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift).

## ChatGPT integration, split view and tab transfers

### R009 — Stabilize split-view viewport and composer visibility

**P1 · Observed · M**

In the recording around 1:19–1:43, the chat row and sidebar top controls scroll away, while composers can move partly below the visible edge during split resizing and typing.

**Change:** Choose one viewport owner, anchor the integrated row consistently and account for visualViewport and keyboard changes. Separate website scrolling from workspace chrome.

**Verify:** Compare before/after device recordings for split entry, divider dragging, composer focus, long conversations and keyboard dismissal. The recording establishes the symptom, not its exact cause.

**Source:** [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R010 — Implement the actual native drag-end callback

**P1 · Confirmed · S**

The UIDragInteraction delegate implements dragInteraction(_:sessionDidEnd:), which is not its required end callback; the native build emits a nearly-matching delegate warning.

**Change:** Use dragInteraction(_:session:didEndWith:) and clear transfer state for successful, cancelled and rejected drags. Keep the live page ownership transfer rather than rebuilding it from its URL.

**Verify:** Drag out, cancel with Escape, drop back in the source, and drop outside all windows; assert that the next drag starts cleanly.

**Source:** [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift); [embedded/tahoe/BrowserTabTransfer.swift](../embedded/tahoe/BrowserTabTransfer.swift).

### R011 — Clean up ordinary browser drags on cancellation

**P2 · Confirmed · S**

Outer-tab onDrag/onDrop state is cleared on successful drop, but lacks a reliable matching end/cancel path.

**Change:** Give native browser drags the same explicit transfer lifecycle and source token as chat drags.

**Verify:** Cancel and reject outer-tab drags repeatedly, then detach another tab; verify no stale source tab is moved.

**Source:** [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift); [embedded/tahoe/BrowserTabTransfer.swift](../embedded/tahoe/BrowserTabTransfer.swift).

### R012 — Refresh pane geometry when the root viewport moves

**P2 · Confirmed · M**

The page adapter listens to resize and the chat-list scroll, but not root/window or visualViewport scrolling. Reported native pane and hit-region rectangles can therefore become stale.

**Change:** Coalesce relevant scroll, visualViewport and resize events into one geometry update per frame. Update only when rectangles change.

**Verify:** Scroll the root, resize with the keyboard open and drag tabs afterward; native hit regions must remain aligned with their visible controls.

**Source:** [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R013 — Remove repetitive layout restoration and forced measurement

**P2 · Candidate · M**

Every layout pass first restores DOM changes and then reapplies them. Input-triggered status calls can enter rendering/layout even when status output is unchanged. This is a credible layout-cost source, not a measured bottleneck yet.

**Change:** Profile first; then make style updates idempotent, batch reads before writes, and skip layout when only chat status changes. Keep adapter cleanup reversible.

**Verify:** Record layout count, long tasks, typing latency and scroll position on a live page before and after the change.

**Source:** [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift); [tools/test-chatgpt-workspace.cjs](../tools/test-chatgpt-workspace.cjs).

### R014 — Expose Chats where users expect it

**P2 · Addition · S**

The user previously saw an enabled menu item yet could not tell whether integration was active. The one-chat hidden-row behavior makes that confusion plausible.

**Change:** Add the same ChatGPT Chats preference to Browser Settings and a small page-level Chats action/count when on a supported site. Explain when a second chat reveals the row.

**Verify:** From a fresh profile, enable the feature, create a second chat and split it without consulting the menu bar or documentation.

**Source:** [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift).

### R015 — Use available space for chat titles and focus

**P2 · Observed · S**

The recording shows early truncation despite spare row space, and split-pane focus could be more obvious.

**Change:** Use bounded flexible tab widths, a full-title tooltip and a restrained focused-pane indicator. Keep inactive labels readable without making every tab look selected.

**Verify:** Check short and long titles at narrow and wide widths, with two panes, pointer hover and increased text size.

**Source:** [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R016 — Support moving tabs into existing windows

**P2 · Addition · L**

Detaching preserves live page ownership and drafts, but the interaction is oriented toward creating a new window rather than merging into an existing one.

**Change:** Add explicit insertion targets for compatible browser/chat bars, with a live insertion preview and cancel-to-origin behavior. Reject profile or workspace combinations that cannot preserve isolation.

**Verify:** Move active streams and drafts both ways between windows without reloading, duplication, accidental closure or cross-profile storage reuse.

**Source:** [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/BrowserTabTransfer.swift](../embedded/tahoe/BrowserTabTransfer.swift); [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R017 — Make split actions visible and reversible

**P2 · Addition · M**

Split view and its divider exist, but the context menu carries much of their discoverability.

**Change:** Provide compact Split, Swap Panes and Exit Split actions, clear focus, and a usable minimum width. Explain when the window is too narrow instead of silently failing.

**Verify:** Complete the same workflow by pointer, touch, keyboard and VoiceOver; closing one pane must retain the intended remaining chat.

**Source:** [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift); [embedded/tahoe/ChatWorkspaceState.swift](../embedded/tahoe/ChatWorkspaceState.swift); [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift).

### R018 — Offer named chat workspaces and search

**P3 · Addition · M**

Multiple chats are supported, but larger research workflows need organization beyond a long row.

**Change:** Add optional named workspace sets and a lightweight open-chat switcher. Keep local workspace organization distinct from ChatGPT account-side projects or pinned chats.

**Verify:** Restore a named set, locate a chat by title, and verify no message contents are collected merely to implement search.

**Source:** [embedded/tahoe/ChatWorkspaceState.swift](../embedded/tahoe/ChatWorkspaceState.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R019 — Test real DOM and layout variants

**P2 · Candidate · M**

Current jsdom fixtures cover semantic behavior, but mocked rectangles are all 1000×800 and cannot validate the geometry shown in the recording.

**Change:** Add realistic layout fixtures and a cheap headless browser layout suite, plus a small physical-device checklist for the real authenticated site. Include signed-out, collapsed-sidebar and alternate responsive markup.

**Verify:** Detect a deliberately scrolled-off chat row and incorrect pane bounds. Keep previews and simulator jobs out of the IPA workflow.

**Source:** [tools/test-chatgpt-workspace.cjs](../tools/test-chatgpt-workspace.cjs); [tools/web-tests/package.json](../tools/web-tests/package.json); [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift).

## Windows, Spaces and the app bar

### R020 — Separate browser and standalone-web-app Dock groups

**P2 · Confirmed · S**

Dock browser filtering and activation include all browser-kind windows, including standalone web apps. The browser icon can therefore list or focus a ChatGPT app window.

**Change:** Centralize an application identity key combining window kind and resource identity; reuse it for running state, window lists, activation and badges.

**Verify:** Launch ordinary browser windows and two pinned web apps; each icon must select only its own windows. Preserve the guest-app icon grouping already fixed.

**Source:** [embedded/tahoe/Dock.swift](../embedded/tahoe/Dock.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift).

### R021 — Keep web-app identity in New Window actions

**P2 · Confirmed · S**

The Applications web-app Open in New Window action uses openBrowser(url:), unlike the Dock path that uses openWebApp(newWindow: true).

**Change:** Route every web-app launch through the same resource-aware command so title, standalone treatment and Dock ownership remain consistent.

**Verify:** Launch the same app from Applications, Dock and Spotlight and compare icon, grouping and chrome.

**Source:** [embedded/tahoe/Applications.swift](../embedded/tahoe/Applications.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/Dock.swift](../embedded/tahoe/Dock.swift).

### R022 — Keep window-picker opening and fullscreen changes atomic

**P2 · Candidate · S**

Dock activation can change fullscreen state and then open a picker, while the root fullscreen observer dismisses menus. This creates a plausible dismissal race.

**Change:** Sequence mode transitions and picker ownership in one command, or defer presentation until the layout transition is committed.

**Verify:** Open an app with several windows from overview and fullscreen repeatedly; the picker should remain open until selection or dismissal.

**Source:** [embedded/tahoe/Dock.swift](../embedded/tahoe/Dock.swift); [embedded/tahoe/DesktopView.swift](../embedded/tahoe/DesktopView.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift).

### R023 — Handle narrow tiling and rotation without losing layouts

**P2 · Confirmed · M**

Half-width tiling can fall below the floating minimum width. Canvas changes clamp saved frames in place, which can discard a useful larger-screen arrangement.

**Change:** Define minimum sizes per layout, use a fallback when two columns cannot fit, and retain normalized or per-display restore frames separately from the current clamped frame.

**Verify:** Rotate, enter narrow multitasking and return to a wide canvas; windows stay reachable and the earlier layout can return.

**Source:** [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift); [embedded/tahoe/WindowInteraction.swift](../embedded/tahoe/WindowInteraction.swift).

### R024 — Make Show Desktop transfer keyboard ownership

**P2 · Confirmed · S**

Showing the desktop leaves an active window ID, while desktop keyboard handling depends on desktop activation.

**Change:** Represent desktop focus explicitly and return focus to the correct window when leaving Show Desktop.

**Verify:** Use Show Desktop, select icons and invoke keyboard actions immediately; restore windows without sending commands to a hidden page.

**Source:** [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift); [embedded/tahoe/DesktopView.swift](../embedded/tahoe/DesktopView.swift); [embedded/tahoe/DesktopIcons.swift](../embedded/tahoe/DesktopIcons.swift).

### R025 — Profile minimize and overview snapshot costs

**P2 · Candidate · M**

Window animation captures use main-thread drawHierarchy and a large shader surface. Overview can request many thumbnails together; image retention is not budgeted. These are profiling targets rather than measured regressions.

**Change:** Measure capture cost, use window-sized bounded images, prioritize visible previews and limit concurrent snapshots. Evict by explicit age rather than dictionary order.

**Verify:** Measure frame time and memory during minimize/restore and overview with 1, 10 and 30 windows on a physical device.

**Source:** [embedded/tahoe/WindowMotion.swift](../embedded/tahoe/WindowMotion.swift); [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift); [embedded/tahoe/OverviewLayout.swift](../embedded/tahoe/OverviewLayout.swift).

### R026 — Reduce desktop-wide invalidation

**P2 · Candidate · M**

Broad observed workspace state and repeated firstIndex-based z-order lookup can make unrelated windows participate in updates; the root z-order lookup is quadratic in window count.

**Change:** Precompute z-order and pass stable per-window state. Keep transient drag state local, preserving the isolation already introduced in the polish work.

**Verify:** Count view updates while dragging one window with many others open; optimize only paths confirmed to be expensive.

**Source:** [embedded/tahoe/DesktopView.swift](../embedded/tahoe/DesktopView.swift); [embedded/tahoe/DesktopWindow.swift](../embedded/tahoe/DesktopWindow.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift).

### R027 — Offer a window layout palette

**P2 · Addition · M**

Basic tiling exists, but a discoverable layout palette would make arrangement easier than repeated manual dragging.

**Change:** Add half, third and quarter layouts where space permits, snap previews and keyboard equivalents. Share geometry with resize constraints rather than adding separate magic numbers.

**Verify:** Apply layouts on narrow and wide canvases, cancel a snap, and verify accessible move/resize commands produce the same frames.

**Source:** [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift); [embedded/tahoe/WindowInteraction.swift](../embedded/tahoe/WindowInteraction.swift); [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift).

### R028 — Save named window arrangements

**P3 · Addition · L**

The last workspace is restored, but users cannot explicitly save and switch named task layouts.

**Change:** Store named arrangements of URLs, app identities and frames with a preview. Distinguish reopening web pages from relaunching native guests, which should remain an explicit choice.

**Verify:** Switch between study and writing layouts, resolve missing apps, and ensure Private pages never enter saved templates.

**Source:** [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift).

### R029 — Extend Spaces organization

**P3 · Addition · M**

Spaces already exist; naming them and assigning apps would make them easier to remember and navigate.

**Change:** Add names, optional per-Space wallpaper and Move to Space/Show on All Spaces actions where ownership allows. Add clear keyboard commands and an overview destination preview.

**Verify:** Move minimized and fullscreen windows between Spaces, restore the session and check focus and Dock ownership.

**Source:** [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift); [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift).

### R030 — Support shared-edge resizing for tiled windows

**P3 · Addition · L**

Independent tiled window resizing does not offer the convenience of an intentional shared divider.

**Change:** Add adjustable tile groups with minimum widths and a visible divider affordance, after the basic layout constraints are unified.

**Verify:** Resize a group, detach a member, minimize one and rotate the device without overlap or unreachable content.

**Source:** [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift); [embedded/tahoe/WindowInteraction.swift](../embedded/tahoe/WindowInteraction.swift).

### R031 — Add native-app pinning and recent launches

**P3 · Addition · M**

Guest apps now get individual running icons, while persistent pinning is more developed for web apps than native guests.

**Change:** Allow pin/unpin for an installed native app using its stable installed identity, and offer a small recent-app list. Show missing installations as recoverable state.

**Verify:** Pin, relaunch, update and remove a guest; verify no duplicate Dock entries or stale paths.

**Source:** [embedded/tahoe/Dock.swift](../embedded/tahoe/Dock.swift); [embedded/tahoe/Applications.swift](../embedded/tahoe/Applications.swift); [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift).

### R032 — Prototype multiple scenes and external displays

**P3 · Architecture · XL**

Workspace singletons and first-key-window lookups assume one shell scene. Hosted guest scenes also have private API constraints.

**Change:** First prototype scene-scoped command and presentation ownership. Define one supported external-display behavior before promising independent desktops or arbitrary guest movement.

**Verify:** Test two host scenes, display removal, keyboard focus and guest recovery on supported hardware; document platform limits.

**Source:** [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/Keyboard.swift](../embedded/tahoe/Keyboard.swift); [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift); [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift).

## Input, animation, accessibility and visual design

### R033 — Remove avoidable single-click selection latency

**P2 · Confirmed · S**

PointerSurface requires the single tap to fail the double tap before selection, so single-click feedback waits for the double-click interval.

**Change:** Select immediately on a valid first press and reserve the second click for opening. Keep drag initiation and modifier selection coherent.

**Verify:** Compare click-to-selection latency; test single/double click, Shift/Command selection and drag without accidental opening.

**Source:** [embedded/tahoe/SelectionViews.swift](../embedded/tahoe/SelectionViews.swift).

### R034 — Apply disabled state to gesture callbacks

**P2 · Candidate · S**

The pointer surface uses active/visible/enabled flags for visual feedback, but its coordinator invokes callbacks without checking those flags.

**Change:** Define which actions may activate an inactive window, and reject disabled or hidden interactions in the gesture layer itself.

**Verify:** Use a real UIKit interaction test for a disabled surface and a hidden/covered window; distinguish intended click-to-focus from disallowed activation.

**Source:** [embedded/tahoe/SelectionViews.swift](../embedded/tahoe/SelectionViews.swift).

### R035 — Make the browser glass preference truthful

**P2 · Confirmed · S**

The glass modifier only tests whether browserGlass equals zero. All positive slider values use the same material and tint, despite a continuous transparency label.

**Change:** Prefer an honest System Glass/Solid setting, or map the control to a supported meaningful visual parameter. Retain the approved opaque browser-bar shades and accessibility overrides.

**Verify:** Compare endpoints and middle settings in light/dark mode and Reduce Transparency. Do not simulate optical glass with additional blur layers.

**Source:** [embedded/tahoe/Design.swift](../embedded/tahoe/Design.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift).

### R036 — Give each control one hover and press owner

**P2 · Candidate · S**

Native glass interaction, row hover, pressed tint and child highlights can overlap. The outer tab hover ID can also be cleared by an older tab exit event.

**Change:** Use one hit shape and feedback owner per control; guard hover exit by the current owner ID, as the corrected Dock/menu paths already do.

**Verify:** Sweep the pointer rapidly across adjacent tabs and disabled controls; check one active hover, stable selected text and no double highlight.

**Source:** [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift); [embedded/tahoe/Design.swift](../embedded/tahoe/Design.swift); [embedded/tahoe/Interaction.swift](../embedded/tahoe/Interaction.swift).

### R037 — Use semantic motion and geometry tokens

**P2 · Architecture · M**

MotionPolicy exists, but controls, menus and windows still contain independent timings. Menu-bar work-area metrics include both 30 and 32-point values.

**Change:** Create a small vocabulary for press, hover, menu, resize and window transitions, plus explicit chrome metrics and intentional gutters. Respect Reduce Motion and Low Power behavior centrally.

**Verify:** Compare opening, closing, minimizing and switching with normal motion, reduced motion and low power; remove timing mismatches without adding delay.

**Source:** [embedded/tahoe/MotionPolicy.swift](../embedded/tahoe/MotionPolicy.swift); [embedded/tahoe/Design.swift](../embedded/tahoe/Design.swift); [embedded/tahoe/WindowState.swift](../embedded/tahoe/WindowState.swift); [embedded/tahoe/Controls.swift](../embedded/tahoe/Controls.swift).

### R038 — Offer compact pointer and comfortable touch sizing

**P2 · Addition · M**

Several shell controls use 24-point metrics and traffic-light controls around 22×30; the injected chat row already has a coarse-pointer treatment.

**Change:** Expand hit regions for touch without unnecessarily enlarging pointer visuals. Provide a comfortable density mode and consistent minimum targets.

**Verify:** Use finger-only navigation on a small iPad, including close buttons, resize handles, tabs and menus; verify adjacent targets do not overlap.

**Source:** [embedded/tahoe/Controls.swift](../embedded/tahoe/Controls.swift); [embedded/tahoe/DesktopWindow.swift](../embedded/tahoe/DesktopWindow.swift); [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift).

### R039 — Audit text size and contrast across the shell

**P2 · Candidate · M**

Fixed small fonts are common, and a light custom accent with white selected text can have poor contrast.

**Change:** Use semantic text styles where practical, constrain or adapt selected foreground contrast, and test accessibility sizes without clipping key actions.

**Verify:** Check large Dynamic Type, Increase Contrast, Reduce Transparency, light/dark mode and very pale accent colors.

**Source:** [embedded/tahoe/Design.swift](../embedded/tahoe/Design.swift); [embedded/tahoe/Controls.swift](../embedded/tahoe/Controls.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift).

### R040 — Make window operations accessible without dragging

**P2 · Addition · M**

Pointer resize grips and title-bar movement do not provide equivalent discoverable accessibility actions.

**Change:** Expose Move, Resize, Tile, Minimize and Close commands with clear VoiceOver labels, and include the actual page title in tab close labels.

**Verify:** Arrange and close windows using VoiceOver and a keyboard only; ensure hidden windows and offscreen controls are excluded.

**Source:** [embedded/tahoe/DesktopWindow.swift](../embedded/tahoe/DesktopWindow.swift); [embedded/tahoe/WindowInteraction.swift](../embedded/tahoe/WindowInteraction.swift); [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift).

### R041 — Scope keyboard commands to the visible owner

**P2 · Confirmed · M**

The desktop remains mounted with opacity zero behind management UI, and hidden keyboard-shortcut buttons remain registered. Local dialogs and global commands can also compete.

**Change:** Introduce a command context for management, modal, focused window, focused pane and desktop. Route each key once to the top eligible owner.

**Verify:** Use Command-W, Enter, Escape, Delete and app shortcuts with management, menus, dialogs and background windows present.

**Source:** [embedded/tahoe/DesktopView.swift](../embedded/tahoe/DesktopView.swift); [embedded/tahoe/Keyboard.swift](../embedded/tahoe/Keyboard.swift); [embedded/tahoe/patch.py](../embedded/tahoe/patch.py); [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift).

### R042 — Define outer-tab versus inner-chat keyboard behavior

**P2 · Addition · S**

Command-W currently follows the outer browser/window model even when an inner chat has focus. The right policy is a product decision, not an automatic bug fix.

**Change:** Document one hierarchy and expose distinct commands for Close Chat, Close Browser Tab and Close Window. Include the effective shortcut in each menu.

**Verify:** Test focused left/right split panes, address editing and a normal website; closing the intended object must still honor draft protection.

**Source:** [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift); [embedded/tahoe/Keyboard.swift](../embedded/tahoe/Keyboard.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R043 — Add submenu pointer-intent handling

**P2 · Candidate · M**

The single menu owner is an improvement, but nested menus do not have a pointer corridor for diagonal travel into a submenu.

**Change:** Add a short pointer-intent corridor for submenu traversal while retaining immediate top-level menu switching and one open menu chain.

**Verify:** Travel diagonally, rapidly switch top-level menus, leave the chain and use keyboard arrows; do not reintroduce multiple lingering dropdowns.

**Source:** [embedded/tahoe/Menus.swift](../embedded/tahoe/Menus.swift); [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift).

### R044 — Use stable menu item identities

**P2 · Candidate · S**

Generic menu identity can fall back to title/key combinations, which are not unique for repeated labels.

**Change:** Require stable keys for dynamic duplicate entries and preserve focus by identity rather than index.

**Verify:** Show two entries with the same title, change their order while a menu is open, and select each by pointer and keyboard.

**Source:** [embedded/tahoe/Menus.swift](../embedded/tahoe/Menus.swift).

### R045 — Give Calendar a moving keyboard focus

**P2 · Confirmed · S**

Arrow handling calculates from a captured day cell but does not move focus with the chosen date, so repeated key presses can reuse the old origin.

**Change:** Maintain an explicit focused date and roving focus, including month/year boundaries and locale direction.

**Verify:** Hold arrows across month boundaries and use Home/End with VoiceOver and RTL layouts.

**Source:** [embedded/tahoe/Calendar.swift](../embedded/tahoe/Calendar.swift).

### R046 — Cancel repeating controls on interrupted gestures

**P2 · Candidate · S**

Stepper repeat cleanup relies on normal gesture completion; cancellation or focus changes may bypass that path. Home/End assignments also need the same disabled guard as increment/decrement.

**Change:** Cancel repeat tasks on gesture cancellation, disappearance and ownership loss, and centralize enabled/range checks.

**Verify:** Start a hold, open another window or interrupt the gesture, then verify no continued changes; test disabled focused controls.

**Source:** [embedded/tahoe/Controls.swift](../embedded/tahoe/Controls.swift).

### R047 — Support localization and directional layouts

**P2 · Addition · M**

Most desktop strings are English literals despite localization in the upstream installer. RTL keyboard/layout behavior is not consistently specified.

**Change:** Move shell strings to a catalog and audit leading/trailing layout, segmented controls, date navigation and shortcut descriptions. Start with pseudo-localization before adding languages.

**Verify:** Run long-string and RTL passes across Settings, dialogs, menus, Dock pickers and file lists.

**Source:** [embedded/tahoe/Controls.swift](../embedded/tahoe/Controls.swift); [embedded/tahoe/Calendar.swift](../embedded/tahoe/Calendar.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift).

### R048 — Show complete error details

**P2 · Confirmed · S**

The generic dialog limits messages to eight lines in a compact fixed-width card, which can hide useful recovery details.

**Change:** Keep a short explanation and primary recovery action visible, with expandable scrollable details and Copy Diagnostics for technical failures.

**Verify:** Present a long signing error and a browser error at large text sizes without hiding the action or leaking secrets in copied text.

**Source:** [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift).

### R049 — Scope dialogs and share sheets to their owners

**P2 · Candidate · M**

A global single-slot dialog can replace pending context; share presentation uses a first-active-scene/center anchor rather than the invoking control.

**Change:** Track presentation owner and cancellation, queue or reject conflicting requests explicitly, and anchor popovers to the source control in the correct scene.

**Verify:** Trigger two prompts, close the originating window and use a share action with a second scene active.

**Source:** [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R050 — Track all fullscreen popover owners

**P2 · Confirmed · S**

The browser fullscreen visibility boolean includes bookmarks, tabs and profile popovers but omits translation. Disappearance can clear the shared flag independently of another owner.

**Change:** Replace the boolean with owner-scoped presentation tokens, including translation and keyboard focus.

**Verify:** Open each popover near the fullscreen chrome edge, switch directly between them and verify the toolbar does not hide underneath it.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/FullscreenChrome.swift](../embedded/tahoe/FullscreenChrome.swift).

### R051 — Improve closing continuity

**P3 · Observed · S**

The recording around 1:55 shows a fast browser disappearance back to the desktop; it does not establish exact frame pacing.

**Change:** Use a short, consistent close transition with immediate input completion, and reserve heavier effects for minimize/restore.

**Verify:** Compare device recordings with normal and reduced motion and ensure repeated close commands cannot act on the next window accidentally.

**Source:** [embedded/tahoe/DesktopWindow.swift](../embedded/tahoe/DesktopWindow.swift); [embedded/tahoe/WindowMotion.swift](../embedded/tahoe/WindowMotion.swift); [embedded/tahoe/MotionPolicy.swift](../embedded/tahoe/MotionPolicy.swift).

## Browser capabilities and website compatibility

### R052 — Recognize local development addresses

**P2 · Confirmed · S**

Bare localhost:8080 is treated as a scheme-like input and rejected, while explicit http://localhost:8080 works.

**Change:** Recognize localhost, loopback and valid host:port forms before general scheme rejection. Keep explicit scheme and host validation.

**Verify:** Test localhost with ports/paths, IPv4, bracketed IPv6, malformed ports and ordinary search queries.

**Source:** [embedded/tahoe/Address.swift](../embedded/tahoe/Address.swift); [embedded/tahoe/WindowStateTests.swift](../embedded/tahoe/WindowStateTests.swift).

### R053 — Add Find on Page

**P2 · Addition · M**

A standard find-in-page command and small result navigator are absent.

**Change:** Use WebKit find support with a compact search field, next/previous, result count and Escape dismissal. Target the focused split pane.

**Verify:** Find text in normal pages, long chats and each split pane; keep focus and keyboard routing predictable.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift).

### R054 — Add searchable browsing history

**P2 · Addition · M**

The existing history menu reflects current WebKit back/forward state rather than a persistent cross-window history library.

**Change:** Store a bounded profile-aware title/URL history with clear retention and deletion controls; exclude Private browsing.

**Verify:** Search across windows, clear one profile, restart and verify that Private visits are absent.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift); [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift).

### R055 — Make bookmarks manageable

**P2 · Addition · M**

Bookmark opening works in the recording, but organization and editing are limited.

**Change:** Add rename, move, delete, folders and import/export, using the same library for the menu and management UI.

**Verify:** Edit duplicate titles, move nested folders and recover gracefully from invalid imports without replacing the existing collection.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift); [embedded/tahoe/Preferences.swift](../embedded/tahoe/Preferences.swift).

### R056 — Add per-site permissions and data controls

**P2 · Addition · M**

Website permissions use prompts, but there is no cohesive site panel for grants, revocation and stored data.

**Change:** Expose origin, profile, camera/microphone decisions, zoom and clear-site-data where WebKit supports it. Make the active requesting origin clear and scope decisions to the requesting page.

**Verify:** Test foreground/background requests, changed origins, revoked access and independent profiles.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Authentication.swift](../embedded/tahoe/Authentication.swift).

### R057 — Use appropriate authentication field semantics

**P2 · Addition · S**

HTTP authentication is origin-labelled and ephemeral, but the custom fields could better advertise username/password roles to the system.

**Change:** Set the relevant textContentType and secure entry semantics, retain origin context and avoid persisting credentials casually.

**Verify:** Check keyboard/password-manager behavior, cancellation and repeated challenges on the correct origin.

**Source:** [embedded/tahoe/Authentication.swift](../embedded/tahoe/Authentication.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R058 — Test popup and sign-in compatibility

**P2 · Candidate · M**

Popup creation changes userContentController setup, and about:blank/opener-dependent flows need verification. Source inspection alone does not prove current OAuth is broken.

**Change:** Create a compatibility matrix for opener messaging, blank-to-navigation popups, sign-in, print and download windows before changing configuration ownership.

**Verify:** Run controlled fixture pages for each flow plus representative real sign-ins, preserving the chosen profile store and bridge isolation.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [tools/test-chatgpt-workspace.cjs](../tools/test-chatgpt-workspace.cjs).

### R059 — Support intentional external-app handoff

**P2 · Addition · M**

The browser policy rejects mailto:, tel: and app links rather than offering a user-controlled handoff.

**Change:** Allow a narrow set of user-initiated external actions through the system opener, with clear destination context. Retain blocking for arbitrary executable/file navigation.

**Verify:** Test user clicks, scripted attempts, missing handlers and return-to-browser focus. Do not broadly allow all schemes.

**Source:** [embedded/tahoe/Address.swift](../embedded/tahoe/Address.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R060 — Improve favicon candidate fallback

**P2 · Candidate · M**

ChatGPT remains a globe in the recording. The icon pipeline selects an early declared icon and uses raster decoding, so SVG-first sites are a plausible failure case rather than a proven cause here.

**Change:** Rank supported icon candidates, try raster/apple-touch fallbacks, bound image decoding and cache size, and cancel obsolete requests. Keep requests direct rather than adding a tracking proxy.

**Verify:** Use SVG-first, PNG-only, invalid-icon, redirect and dark-mode fixtures; inspect the actual ChatGPT icon request failure on device.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/WebsiteIdentity.swift](../embedded/tahoe/WebsiteIdentity.swift).

### R061 — Test user-agent compatibility instead of guessing versions

**P2 · Candidate · S**

The presented browser version is derived from the iPadOS major rather than a measured WebKit/Safari compatibility mapping.

**Change:** Document the intentional user-agent policy, minimize unnecessary spoofing and validate sites that branch on browser versions.

**Verify:** Compare desktop/mobile site negotiation, login and media behavior with the current and a controlled default user agent.

**Source:** [embedded/tahoe/WebsiteIdentity.swift](../embedded/tahoe/WebsiteIdentity.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R062 — Add open-tab search and tab organization

**P2 · Addition · M**

A growing number of ordinary tabs needs a faster switcher than scanning the strip.

**Change:** Add a searchable tab overview with profile/window context, optional pinned tabs and named groups. Share page identity with session recovery rather than duplicating URL lists.

**Verify:** Find one of many same-host tabs, move it between windows and restore its group without losing the live page.

**Source:** [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift).

### R063 — Offer reading and offline page tools

**P3 · Addition · L**

Reader-style presentation and offline reading are not currently a cohesive feature.

**Change:** Start with Save PDF/Print and reading-list entries; evaluate article extraction or web archives separately. Do not assume Safari Reader internals are a public reusable API.

**Verify:** Save long articles, login-required pages and pages with missing assets, with clear limits and no promise of perfect offline fidelity.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/Downloads.swift](../embedded/tahoe/Downloads.swift).

### R064 — Expose media-playing tabs and mute controls

**P3 · Addition · M**

Tabs do not provide a clear audio-playing indicator or a user-facing media management surface.

**Change:** Add a modest supported audio state/mute action where WebKit permits it and integrate media protection with any future sleeping policy.

**Verify:** Play audio in a background tab, mute/unmute, close it and verify page suspension does not interrupt explicitly protected media.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift).

### R065 — Evaluate optional content blocking

**P3 · Addition · L**

There is no curated content-blocking capability.

**Change:** Prototype WKContentRuleList with explicit opt-in, per-site exceptions and a visible reload/recovery path. Measure breakage and update needs before making it a default.

**Verify:** Test sign-in, payments, video and ChatGPT with blocking enabled and disabled; avoid a silent remote rule-update dependency.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift).

## Files, downloads, desktop icons and search

### R066 — Move file enumeration and recursive operations off the UI actor

**P1 · Confirmed · M**

Files refresh enumerates directories and reads metadata on the main actor; trash operations can also perform recursive filesystem work there. Filtering/sorting is recomputed from view helpers.

**Change:** Use a filesystem worker with immutable directory snapshots, generation cancellation and explicit operation progress. Cache derived presentation results by snapshot and sort/filter inputs.

**Verify:** Browse folders with thousands of entries and empty a large trash while dragging another window; verify responsiveness and correct partial-failure reporting.

**Source:** [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/FileOperations.swift](../embedded/tahoe/FileOperations.swift).

### R067 — Prevent an older paste from clearing a newer clipboard

**P2 · Confirmed · S**

A move-style paste captures old URLs, awaits work and then clears the shared URL list. A new Copy performed during that wait can be erased.

**Change:** Attach a revision to clipboard contents and clear only the revision consumed by the completed move.

**Verify:** Start a slow cut/paste, copy another file before completion, and verify the new clipboard remains available.

**Source:** [embedded/tahoe/FileClipboard.swift](../embedded/tahoe/FileClipboard.swift); [embedded/tahoe/FileOperations.swift](../embedded/tahoe/FileOperations.swift).

### R068 — Use grid geometry for arrow navigation

**P2 · Confirmed · S**

File-grid up/down navigation moves by one linear item rather than the visible column count.

**Change:** Compute navigation from the current grid geometry, preserve an anchor column and reveal the selected item.

**Verify:** Navigate a resized grid with incomplete final rows and Shift selection, including RTL layouts.

**Source:** [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift).

### R069 — Preserve desktop icon placement through rename

**P2 · Confirmed · M**

Icon positions use absolute URL strings as identities. Renaming changes the key, and old position entries can remain stored.

**Change:** Use a stable file identity where available, migrate position keys on rename/move and prune missing entries.

**Verify:** Rename, move, delete and recreate files; the intended icon keeps its position without accumulating stale keys.

**Source:** [embedded/tahoe/DesktopIcons.swift](../embedded/tahoe/DesktopIcons.swift); [embedded/tahoe/FileOperations.swift](../embedded/tahoe/FileOperations.swift).

### R070 — Give Desktop its own folder

**P2 · Addition · M**

The desktop currently presents the root Documents contents rather than a separate Desktop directory.

**Change:** Offer a real Desktop folder with a migration choice, leaving existing documents discoverable. Keep filesystem and visual desktop ownership consistent.

**Verify:** Upgrade with existing files and icon placements, then add a document in Finder and on Desktop and verify their locations.

**Source:** [embedded/tahoe/DesktopIcons.swift](../embedded/tahoe/DesktopIcons.swift); [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift).

### R071 — Support multiple Finder windows and file transfer

**P2 · Addition · L**

The Files app is effectively a single shared window/location, which limits moving items between folders.

**Change:** Store navigation and selection per Finder window, then support drag/copy/move between them and the desktop. Add system Files-provider integration through supported document APIs.

**Verify:** Open two folders, transfer mixed selections and cancel midway; verify security-scoped URLs and per-window navigation remain valid.

**Source:** [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/FileOperations.swift](../embedded/tahoe/FileOperations.swift).

### R072 — Restore trash items to their original locations

**P2 · Addition · M**

The current UI accurately says Put Back in Documents; original locations are not recorded.

**Change:** Store original URL and deletion date in trash metadata, offer Restore and resolve missing parent/conflicting filenames explicitly.

**Verify:** Restore nested files and duplicate names after the original folder has been removed.

**Source:** [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/FileOperations.swift](../embedded/tahoe/FileOperations.swift).

### R073 — Add undo and operation-level recovery

**P2 · Addition · L**

File mutations need clearer recovery than a final success/error result.

**Change:** Build a bounded undo journal for reversible rename/move/trash actions, plus per-item progress, safe cancellation points and partial-result summaries. Do not imply permanent deletion is always reversible.

**Verify:** Cancel halfway through a multi-file operation, retry failed items only and undo supported operations after a name conflict.

**Source:** [embedded/tahoe/FileOperations.swift](../embedded/tahoe/FileOperations.swift); [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift).

### R074 — Add preview and file information

**P3 · Addition · M**

File browsing would benefit from faster inspection before opening an external handler.

**Change:** Add supported Quick Look previews, a Get Info panel and bounded thumbnails. Keep preview decoding off the interaction path.

**Verify:** Preview large images, PDFs and unsupported files while maintaining selection and bounded memory.

**Source:** [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/Artwork.swift](../embedded/tahoe/Artwork.swift).

### R075 — Add batch rename and conflict resolution

**P3 · Addition · M**

Repeated file organization requires many individual actions and consistent conflict handling.

**Change:** Provide a preview-first batch rename flow, Skip/Replace/Keep Both options where appropriate and one undoable operation summary.

**Verify:** Preview duplicate outputs, invalid names and case-only changes before making filesystem mutations.

**Source:** [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/FileOperations.swift](../embedded/tahoe/FileOperations.swift).

### R076 — Make Spotlight work cancellable and ranked

**P2 · Confirmed · M**

Each query starts detached scanning. Cancelling the UI task suppresses stale display but does not stop the underlying enumerator. Entry/result caps can favor apps over files/web results.

**Change:** Use a cancellable worker or incremental local index, budget each result category and rank by relevance/recency. Make indexing scope visible.

**Verify:** Type and delete queries rapidly in a large directory; measure abandoned work and confirm a matching file is not crowded out by apps.

**Source:** [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift).

### R077 — Reveal the actual search result in Finder

**P2 · Confirmed · S**

Opening a file search result opens its containing folder without selecting the matched file.

**Change:** Pass a reveal selection to the destination Finder instance and scroll it into view.

**Verify:** Reveal a file in a large sorted folder, including one renamed while search was running.

**Source:** [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift).

### R078 — Include open windows and chats in global search

**P2 · Addition · M**

Global search already includes apps/files/web suggestions, but not a unified Jump to Window or Chat result.

**Change:** Add explicit window/tab/chat categories using existing titles and IDs, with profile context and immediate focus. Do not index chat message contents.

**Verify:** Find two same-title chats in different windows and activate the intended pane without reloading it.

**Source:** [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift).

### R079 — Use download resume data

**P2 · Confirmed · M**

The WebKit failure callback receives resumeData but discards it. The UI has no corresponding pause/resume/retry flow.

**Change:** Retain supported resume data securely and expose Retry/Resume with accurate fallback to restart when resumption is unsupported.

**Verify:** Interrupt a large download, relaunch and resume or clearly restart it without generating duplicate final files.

**Source:** [embedded/tahoe/Downloads.swift](../embedded/tahoe/Downloads.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R080 — Give downloads history and useful progress

**P2 · Addition · M**

Download state is in memory and lacks a durable completed list, byte totals, speed/ETA and destination choice. Completed files themselves survive in Finder.

**Change:** Persist bounded metadata, show bytes/progress and a destination action, add Reveal in Finder and a clear completion/failure notification.

**Verify:** Test unknown content lengths, filename collisions, cancelled downloads and relaunch with both completed and interrupted items.

**Source:** [embedded/tahoe/Downloads.swift](../embedded/tahoe/Downloads.swift); [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/Preferences.swift](../embedded/tahoe/Preferences.swift).

### R081 — Add file favorites and recent locations

**P3 · Addition · M**

Repeated navigation would benefit from user-controlled shortcuts beyond the current basic locations.

**Change:** Add favorite folders, recent files/locations and optional tags backed by app-owned metadata, respecting available sandbox/provider access.

**Verify:** Move or revoke an external location and show a repair action instead of a dead favorite.

**Source:** [embedded/tahoe/Files.swift](../embedded/tahoe/Files.swift); [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift).

## Hosted apps, installation and background work

### R082 — Queue rapid native-app launches visibly

**P2 · Confirmed · M**

The launch coordinator silently returns when a launch is already in progress. Some launch surfaces can still accept rapid clicks.

**Change:** Use a small serial launch queue with queued/connecting/launching status and safe cancellation. Preserve the upstream selected-storage-path handoff; do not parallelize it casually.

**Verify:** Launch three different guests quickly from different surfaces and verify every request is either executed or explicitly cancelled.

**Source:** [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift); [embedded/tahoe/Applications.swift](../embedded/tahoe/Applications.swift); [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift).

### R083 — Pause the guest watchdog during app suspension

**P2 · Confirmed · S**

The guest launch timeout is approximately 45 seconds and does not account for background suspension like the new browser restore watchdog does.

**Change:** Use foreground elapsed time or an explicit lifecycle pause, retaining a bounded real failure path.

**Verify:** Background during launch for longer than the timeout, return and verify that a healthy launch is not marked failed immediately.

**Source:** [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift); [embedded/tahoe/DesktopView.swift](../embedded/tahoe/DesktopView.swift).

### R084 — Make guest recovery actionable

**P2 · Addition · M**

A failed hosted launch mainly presents error text, leaving users to infer whether to relaunch, enable JIT or return to management.

**Change:** Offer context-appropriate Relaunch, JIT Setup, Open Management and Copy Diagnostics actions. Keep the original error details accessible.

**Verify:** Exercise missing JIT, disconnected device connection, removed app and hosted scene termination; verify actions return to the same app context.

**Source:** [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift); [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift).

### R085 — Create a host activity center

**P2 · Architecture · M**

Downloads, signing, refresh and launch operations expose status through separate parts of the shell and engine.

**Change:** Present one app-owned job model with phase, progress, owner and safe cancel/retry actions. Reuse the upstream refresh lease and background queues rather than creating competing runners.

**Verify:** Run refresh plus download and queued launch; verify one operation owner, accurate status and cancellation only at safe boundaries.

**Source:** [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift); [embedded/tahoe/Downloads.swift](../embedded/tahoe/Downloads.swift).

### R086 — Validate lifecycle and private-scene compatibility

**P2 · Candidate · M**

Guest hosting depends on upstream private runtime and scene contracts; compile success does not establish behavior on every supported iPadOS/device combination.

**Change:** Maintain a physical-device compatibility matrix for JIT, launch, background/foreground, scene destruction and relaunch. Document the supported boundary.

**Verify:** Run a repeatable smoke sequence on each supported OS/device family before a release, with redacted logs and no simulator requirement.

**Source:** [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift); [Engine.lock.json](../Engine.lock.json).

### R087 — Name guest identities by what they contain

**P3 · Architecture · S**

A guest field called bundleID is used as a relative bundle path in shell integration.

**Change:** Introduce a typed installed-app identifier/path at the facade boundary to prevent confusing display names, bundle IDs and on-disk paths.

**Verify:** Update the shell facade without changing the pinned runtime contract; test update/reinstall path changes.

**Source:** [embedded/tahoe/Guest.swift](../embedded/tahoe/Guest.swift); [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift).

### R088 — Measure background keep-alive costs

**P2 · Candidate · M**

The pinned runtime has audio/location keep-alive mechanisms. Their presence alone does not establish misuse or battery drain in the embedded configuration.

**Change:** Trace actual enabled callers, document the user-facing mode and measure idle/background energy before changing cleanup or defaults.

**Verify:** Compare energy and task cleanup with keep-alive enabled/disabled, successful refresh and failed connection; preserve required refresh reliability.

**Source:** [Engine.lock.json](../Engine.lock.json).

## Settings, onboarding, assets and release clarity

### R089 — Show installed version, build and source revision

**P2 · Confirmed · S**

About still uses Tahoe Desktop branding and lacks a visible app build/source revision. Identical IPA naming makes it hard to confirm which build is installed.

**Change:** Adopt a consistent SideOS product name and show version, build number, short source SHA and channel. Include the same information in the artifact filename and release notes.

**Verify:** Install two successive builds and verify the user can identify them from inside the app without checking GitHub.

**Source:** [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/package.py](../embedded/package.py); [.github/workflows/private-build.yml](../.github/workflows/private-build.yml).

### R090 — Correct stale settings and coverage documentation

**P2 · Confirmed · S**

Settings says other pages load only when selected, which is obsolete after automatic restoration. Source coverage and some older UI documents mention a native Notes editor or simulator/preview CI that are not the current product/build policy.

**Change:** Update descriptions to match real behavior and publish a compact implemented/tested/manual-only coverage matrix. Distinguish optional web apps from native utilities.

**Verify:** Cross-check user-visible settings and build docs against current source and workflow jobs; no new native build is needed for documentation-only edits.

**Source:** [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [SOURCE-COVERAGE.md](../SOURCE-COVERAGE.md); [docs/liquid-glass-interactions.md](../docs/liquid-glass-interactions.md).

### R091 — Add lightweight first-run discovery

**P2 · Addition · M**

The ChatGPT activation confusion shows that features can work yet remain hard to discover.

**Change:** Provide a dismissible first-run checklist for windows, right-click/long press, tabs, ChatGPT integration, guest setup and recovery. Link to a searchable shortcut sheet rather than repeated intrusive tips.

**Verify:** Have a new user create a split chat, detach a tab and find its window from the Dock without prior instruction.

**Source:** [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/tahoe/Applications.swift](../embedded/tahoe/Applications.swift); [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift).

### R092 — Offer privacy-aware diagnostic export

**P2 · Addition · M**

Troubleshooting currently requires correlating app behavior, source revisions and workflow artifacts manually.

**Change:** Export build manifest, recent redacted operation errors, page counts and non-sensitive lifecycle states with a preview. Omit credentials, cookies, chat text and browsing URLs by default.

**Verify:** Inspect exported data from authenticated browsing and signing flows; ensure redaction is preserved and export is user initiated.

**Source:** [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/tahoe/Dialogs.swift](../embedded/tahoe/Dialogs.swift); [Engine.lock.json](../Engine.lock.json).

### R093 — Bound photo and icon preparation work

**P2 · Candidate · M**

The photo picker loads full data before applying its size limit, and icon PNG encoding/writing can occur on the main actor. File-import paths already inspect metadata earlier.

**Change:** Use transferable file representations or metadata-first checks, downsample before decode, and perform image preparation off the interaction path with a cancellation token.

**Verify:** Select a very large photo, cancel halfway through and rapidly replace an icon; memory stays bounded and the newest selection wins.

**Source:** [embedded/tahoe/WallpaperPhoto.swift](../embedded/tahoe/WallpaperPhoto.swift); [embedded/tahoe/WebIconEditor.swift](../embedded/tahoe/WebIconEditor.swift); [embedded/tahoe/Artwork.swift](../embedded/tahoe/Artwork.swift).

### R094 — Add a focused command palette

**P3 · Addition · M**

Menus and Spotlight cover many actions, but a searchable action surface would help users learn shortcuts and reach less visible window commands.

**Change:** Add commands for the active context, showing disabled reasons and shortcuts. Reuse the command router instead of inventing a second action implementation.

**Verify:** Find Split Chat, Move to Space, Downloads and Browser Settings by keyboard; commands must target the visible owner.

**Source:** [embedded/tahoe/Overlays.swift](../embedded/tahoe/Overlays.swift); [embedded/tahoe/MenuBar.swift](../embedded/tahoe/MenuBar.swift); [embedded/tahoe/Keyboard.swift](../embedded/tahoe/Keyboard.swift).

### R095 — Evaluate optional offline utilities

**P3 · Addition · L**

The approved Notes/Calculator experiences use web services; an unused calculator model is not evidence of a shipped native calculator or Notes editor.

**Change:** If desired, add a small offline scratchpad or calculator alongside the current web apps, with clear naming and local storage/export. Do not silently replace the existing choices.

**Verify:** Use the optional utility offline, export its data and verify upgrade/migration behavior.

**Source:** [embedded/tahoe/Applications.swift](../embedded/tahoe/Applications.swift); [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift).

### R096 — Evaluate a real agenda integration

**P3 · Addition · L**

The calendar is a useful date surface but is not a full event/calendar app.

**Change:** An optional EventKit-backed agenda could add upcoming events with explicit permission and clear read/write capabilities; keep basic date selection independent of permission.

**Verify:** Test denied permission, multiple calendars, timezone changes and revoked access without breaking the basic calendar.

**Source:** [embedded/tahoe/Calendar.swift](../embedded/tahoe/Calendar.swift).

### R097 — Design a SideOS-aware update channel

**P3 · Addition · L**

The upstream update checker is disabled in the embedded build, so it is not currently sending users to the wrong upstream update. A dedicated SideOS update experience is still absent.

**Change:** Expose a release channel and version manifest linked to authorized distribution. Private artifacts need an appropriate user-authenticated path or release feed; never embed a GitHub token in the app.

**Verify:** Test unavailable releases, expired artifacts, wrong channels and downgrade checks; show the installed build next to the candidate build.

**Source:** [Engine.lock.json](../Engine.lock.json); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [.github/workflows/private-build.yml](../.github/workflows/private-build.yml).

### R098 — Consider a constrained resource-update loader

**P3 · Architecture · XL**

The ChatGPT adapter is embedded in Swift today, so even JavaScript edits need a host rebuild and IPA. Native Swift/entitlement/runtime changes inherently still need a new app build.

**Change:** Only if adapter iteration justifies the complexity, move a deliberately limited adapter resource into a verified versioned loader with minimum-host compatibility, last-known-good rollback and an explicit update policy. Preserve origin restrictions and distribution rules.

**Verify:** Reject incompatible or corrupted bundles, recover offline and roll back a broken adapter. Keep credentials out of update assets and do not present this as native-code hot reload.

**Source:** [embedded/tahoe/ChatGPTPageScript.swift](../embedded/tahoe/ChatGPTPageScript.swift); [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift); [AGENTS.md](../AGENTS.md).

## Code structure, testing and GitHub Actions efficiency

### R099 — Split Browser by responsibility

**P2 · Architecture · L**

Browser.swift is approximately 1,310 lines combining WebKit lifecycle, navigation policy, sessions, dialogs, identity requests and SwiftUI navigation chrome.

**Change:** Extract a page runtime, session model, navigation policy and browser chrome through small behavior-preserving seams. Keep profile ownership and restore scheduling explicit.

**Verify:** Retain the current core/DOM checks and device smoke flows after each extraction; do not combine this with a broad visual rewrite.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/PageRestoration.swift](../embedded/tahoe/PageRestoration.swift).

### R100 — Reduce singleton coupling with scoped services

**P2 · Architecture · L**

Workspace, preferences, keyboard and menus rely heavily on global shared instances, making ownership and isolated tests harder.

**Change:** Inject scene/workspace command, presentation and persistence services at the desktop boundary. Keep a compatibility facade while migrating individual features.

**Verify:** Instantiate two independent workspaces in a test harness without shared menu/dialog state, then verify the production single-scene behavior remains unchanged.

**Source:** [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/Preferences.swift](../embedded/tahoe/Preferences.swift); [embedded/tahoe/Keyboard.swift](../embedded/tahoe/Keyboard.swift); [embedded/tahoe/Menus.swift](../embedded/tahoe/Menus.swift).

### R101 — Use typed resource and command identities

**P2 · Architecture · M**

String IDs and browser-kind checks are repeated across Dock, app launch, windows and persistence, contributing to inconsistent grouping.

**Change:** Introduce small typed AppIdentity, WindowIdentity and command contexts rather than a large new framework; use one resolver for app display/icon/launch behavior.

**Verify:** Run the same launch/focus/close sequence for a normal browser, pinned web app and guest app and assert consistent identity.

**Source:** [embedded/tahoe/Workspace.swift](../embedded/tahoe/Workspace.swift); [embedded/tahoe/Dock.swift](../embedded/tahoe/Dock.swift); [embedded/tahoe/Applications.swift](../embedded/tahoe/Applications.swift).

### R102 — Cover packaging changes in cheap CI triggers

**P2 · Confirmed · S**

The Linux workflow watches embedded/tahoe/** but omits packaging scripts such as embedded/package.py and embedded/prepare_livecontainer.py.

**Change:** Include relevant packaging paths and add cheap contract checks for their inputs/outputs. Keep Mac compilation manual or on the fixed device branch.

**Verify:** Change only a packaging script and verify that Linux checks run while no device build starts.

**Source:** [.github/workflows/checks.yml](../.github/workflows/checks.yml); [embedded/package.py](../embedded/package.py); [embedded/prepare_livecontainer.py](../embedded/prepare_livecontainer.py).

### R103 — Fingerprint exact build recipes without unrelated workflow churn

**P2 · Candidate · M**

Binary cache keys correctly include exact source/toolchain inputs, but hashing the whole workflow can invalidate compiled products for artifact-only workflow edits.

**Change:** Move product build recipes into scripts and hash exact recipe/toolchain/source inputs. Keep independent host/JIT/FFI/installer caches and never use a partial-prefix binary hit.

**Verify:** Verify artifact naming changes keep product cache hits, while compiler flags, source, SDK or recipe changes force the appropriate miss.

**Source:** [.github/workflows/private-build.yml](../.github/workflows/private-build.yml); [docs/build-efficiency.md](../docs/build-efficiency.md); [AGENTS.md](../AGENTS.md).

### R104 — Avoid redundant cheap checks only with same-SHA evidence

**P3 · Candidate · S**

Main pushes and a requested IPA can both run Linux validation. This duplication is much smaller than native build cost and should not be removed at the expense of a clear gate.

**Change:** If useful, reuse a successful exact-SHA checks result before native compilation; otherwise retain the inexpensive reliable duplicate.

**Verify:** Never accept a result from another commit, skip a missing result or bypass a failed check.

**Source:** [.github/workflows/checks.yml](../.github/workflows/checks.yml); [.github/workflows/private-build.yml](../.github/workflows/private-build.yml).

### R105 — Triage compiler warnings and prevent new ones

**P2 · Candidate · M**

The successful native build still reports actor-isolation warnings and the nearly-matching drag delegate. Build success alone therefore misses meaningful integration issues.

**Change:** Fix actionable warnings in shell code, record upstream exceptions and gate new warnings against a reviewed baseline. Avoid globally treating inherited upstream warnings as errors immediately.

**Verify:** Confirm the wrong delegate warning disappears and a deliberately introduced shell warning is detected without flooding reviewers with unchanged upstream output.

**Source:** [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift); [.github/workflows/private-build.yml](../.github/workflows/private-build.yml).

### R106 — Expand tests around lifecycle contracts rather than implementation mirrors

**P2 · Addition · M**

Portable model tests and 22 DOM fixtures are useful, but aggregate close protection, oversized sessions, clipboard races and several presentation lifecycles are not covered by the current suite.

**Change:** Add focused regression cases as each confirmed defect is fixed, using controlled time/actors and observable behavior. Keep the actual restore driver tests rather than testing only a copied queue model.

**Verify:** Each new test should fail for the corresponding pre-fix behavior and avoid depending on private implementation order.

**Source:** [tools/test-core.sh](../tools/test-core.sh); [embedded/tahoe/PageRestorationTests.swift](../embedded/tahoe/PageRestorationTests.swift); [tools/test-chatgpt-workspace.cjs](../tools/test-chatgpt-workspace.cjs).

### R107 — Create a physical-device release checklist

**P2 · Addition · M**

A device IPA compile verifies UIKit/WebKit integration but does not validate scrolling, hover, memory, JIT or authenticated site behavior. The user explicitly excludes simulator/preview builds.

**Change:** Maintain a short repeatable manual matrix for cold/warm restore, backgrounding, drag cancellation, drafts, split typing, file jobs, downloads and guests. Attach build identity and device/OS to results.

**Verify:** Run it for release candidates on actual hardware and compare the same recordings rather than claiming performance from a compressed clip alone.

**Source:** [tools/test-native.sh](../tools/test-native.sh); [.github/workflows/private-build.yml](../.github/workflows/private-build.yml); [docs/automatic-tab-restoration.md](../docs/automatic-tab-restoration.md).

### R108 — Publish the actual validation and dependency boundary

**P2 · Architecture · M**

The private overlay is small enough for a broad source audit; the pinned engine and native dependencies are much larger. Portable tests include some legacy model coverage that is not a shipped feature.

**Change:** Document which production behavior is covered by Linux, DOM fixtures, native compilation and device testing, and record exact dependency revisions and update decisions.

**Verify:** Every claimed feature and validation method should point to shipped source or an executed check; no implied full third-party security audit.

**Source:** [Engine.lock.json](../Engine.lock.json); [SOURCE-COVERAGE.md](../SOURCE-COVERAGE.md); [tools/test-core.sh](../tools/test-core.sh).

### R109 — Review packaged source/notices deliberately

**P3 · Candidate · M**

Packaging copies source and notices into EmbeddedSourceNotices, including material that may not be needed at runtime. This is intentional packaging behavior, not evidence of data exfiltration.

**Change:** Measure artifact contribution, preserve required license/source obligations and document exactly what ships. Prune development-only files only after those requirements are understood.

**Verify:** Compare IPA contents and size before/after a reviewed packaging change; ensure required acknowledgments and source notices remain accessible.

**Source:** [embedded/package.py](../embedded/package.py); [embedded/tahoe/Notices/ExistingIconArtwork.txt](../embedded/tahoe/Notices/ExistingIconArtwork.txt).

### R110 — Preserve pinned-engine integration contracts

**P2 · Architecture · M**

The pinned runtime already has useful signing identity checks, refresh leases, redaction and background FFI queues. Broad shell cleanup must not inadvertently bypass them.

**Change:** Keep the shell behind a narrow host facade, maintain patch anchor assertions and review upstream updates as compatibility changes. Test contracts before adopting a new pin.

**Verify:** Validate signing/team selection, refresh mutual exclusion, launch handoff and redacted errors against the exact new revision before requesting an IPA.

**Source:** [Engine.lock.json](../Engine.lock.json); [embedded/tahoe/patch.py](../embedded/tahoe/patch.py); [tools/overlay-engine.py](../tools/overlay-engine.py).

## Privacy, trust and native-material coherence

### R111 — Expose search-suggestion and provider choices

**P2 · Addition · S**

Google suggestions already use an ephemeral cookie-free session, suppress likely addresses and disable remote requests in Private browsing. Normal search terms are still sent to Google while typing, without a dedicated setting in Browser Settings.

**Change:** Explain this briefly beside a Suggestions switch, and optionally offer a default search-provider choice. Preserve immediate local Search behavior when remote suggestions are disabled or unavailable.

**Verify:** Disable suggestions and verify no suggestion requests occur; switch to Private mid-request and confirm cancellation and cleared predictions.

**Source:** [embedded/tahoe/BrowserSuggestions.swift](../embedded/tahoe/BrowserSuggestions.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/tahoe/Address.swift](../embedded/tahoe/Address.swift).

### R112 — Keep bridge-origin restrictions under regression test

**P2 · Addition · M**

The native ChatGPT bridge already checks the main frame, exact HTTPS origin/port and matching WKWebView, and the adapter uses an isolated content world. Saved chat state intentionally excludes message bodies, drafts and titles.

**Change:** Preserve these boundaries with native contract coverage for iframe messages, lookalike hosts, wrong ports, stale views and unsupported routes. Keep geometry/title/status payloads bounded as the adapter grows.

**Verify:** Prove rejected messages cannot open, close, split or detach pages and that exported/restored chat state contains only approved URL/layout metadata.

**Source:** [embedded/tahoe/ChatWorkspace.swift](../embedded/tahoe/ChatWorkspace.swift); [embedded/tahoe/ChatWorkspaceState.swift](../embedded/tahoe/ChatWorkspaceState.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

### R113 — Provide clear local-data and backup controls

**P2 · Addition · M**

The app owns session URLs, preferences, downloads and icon/wallpaper files, while profile website stores have separate lifetimes. Users need to understand what Clear or Reset will remove.

**Change:** Add a storage view with per-category cleanup and an optional user-initiated settings/layout export. Exclude credentials, cookies and Private addresses; validate imports before replacing the current workspace.

**Verify:** Export/import a supported layout, reject malformed input, and verify cleaning browsing metadata does not delete downloaded documents accidentally.

**Source:** [embedded/tahoe/Persistence.swift](../embedded/tahoe/Persistence.swift); [embedded/tahoe/Preferences.swift](../embedded/tahoe/Preferences.swift); [embedded/tahoe/Settings.swift](../embedded/tahoe/Settings.swift); [embedded/tahoe/Downloads.swift](../embedded/tahoe/Downloads.swift).

### R114 — Make website identity inspectable

**P2 · Addition · S**

Compact host presentation is useful, but the user also needs a straightforward way to inspect the full origin/URL and the active profile when a page requests trust.

**Change:** Offer a compact site information panel with copyable full URL, secure-origin context and profile identity, linked to permissions/data controls. Keep website-supplied titles visually separate from origin.

**Verify:** Check long hosts, internationalized domains, redirects, non-default ports and similarly titled sites; never infer trust solely from a favicon or title.

**Source:** [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift); [embedded/tahoe/Authentication.swift](../embedded/tahoe/Authentication.swift).

### R115 — Refine native glass hierarchy rather than adding optical layers

**P2 · Candidate · M**

The current project already uses glassEffect, interactive glass and GlassEffectContainer. Outer tabs each receive a pill material, with relatively small selected/unselected tint differences; the old all-blue screenshot does not establish that the current source still has that styling defect.

**Change:** Compare the current build on device and tune shared grouping, spacing, neutral foregrounds and selected emphasis. Keep only the selected tab visually primary and use system interaction for optical response. Do not promise identical pointer deformation across all iPadOS devices or future Safari versions.

**Verify:** Capture current light/dark, hover, press, selected, inactive-window and reduced-transparency states; check that one selected tab remains unambiguous and touch interaction stays clear.

**Source:** [embedded/tahoe/Tabs.swift](../embedded/tahoe/Tabs.swift); [embedded/tahoe/Design.swift](../embedded/tahoe/Design.swift); [embedded/tahoe/Browser.swift](../embedded/tahoe/Browser.swift).

## Recommended implementation sequence

### Batch 1 — trustworthy lifecycle and immediate interaction

Unify draft/close protection, preserve restore overflow, correct the drag delegate and cancel paths, fix clipboard revision handling, remove single-click waiting, correct Dock/web-app identity, expose build identity and update stale restoration text. Add focused regression cases for the affected behavior. These changes are concrete and reviewable without a broad rewrite.

Do not build an IPA for every item. Consolidate, run Linux checks, request one build on the fixed `ipa/device` branch and reuse its artifact for the device checklist.

### Batch 2 — smooth under real workloads

Profile resident pages, snapshots and large folders on device. Then implement pressure-aware background restoration/page retention, bounded snapshot work, asynchronous filesystem snapshots and correctly scoped keyboard/presentation ownership. Stabilize ChatGPT root/visual viewport geometry with a live authenticated device comparison. This is the batch most likely to improve the feeling of quality across the whole desktop.

### Batch 3 — finish the everyday experience

Add Find on Page, useful download recovery, accessible window commands, comfortable touch targets, clear Chats discovery, flexible chat titles, open-window search and improved error recovery. Use one visual/state vocabulary for hover, pressed, selected, focused, loading and disabled. Keep the native glass already present rather than layering on a simulated replacement.

### Batch 4 — make the desktop more capable

Choose from bidirectional tab/window merging, layout palettes, saved arrangements, multi-window Finder, history/bookmark management and app pinning. Each should reuse the identity, lifecycle, persistence and command foundations from the earlier batches.

### Batch 5 — evaluate larger bets separately

External displays/multiple scenes, resource updates, optional offline utilities and deeper reading/media features need individual product decisions and prototypes. None should block correctness or be bundled into an opaque all-at-once rewrite.

## Architecture direction

Keep a thin composition root for each desktop scene. Under it, separate (1) window/layout/focus state, (2) app and resource identity, (3) page/session lifecycle, (4) the ChatGPT adapter, (5) file/download/guest jobs, (6) persistence snapshots and migrations, and (7) command/presentation routing. Prefer small typed boundaries over a new general-purpose framework.

Preserve the stable upstream contracts for signing, JIT, installation, refresh mutual exclusion and guest storage selection. The engine already moves important blocking FFI work to dedicated queues and includes useful identity/redaction checks. Refactoring those contracts while polishing chrome would multiply risk without improving the immediate user experience.

## Release and performance acceptance

- A saved session round-trips without silently losing supported tabs/windows; overflow is preserved and discoverable.
- Closing or leaving any chat container uses the same draft policy; cancellation leaves live pages and streams intact.
- Moving a live tab preserves its page and state, and cancelled transfers leave no stale drag ownership.
- One focused command owner receives keyboard actions, and one hover/presentation owner controls each visible interaction.
- Large directory work, image preparation and thumbnail generation do not monopolize the UI thread.
- Resident-page and thumbnail budgets are based on measured device memory; the policy protects active user work.
- ChatGPT row, panes and composers remain reachable during root scroll, keyboard appearance and split resizing.
- Every release displays its version/build/SHA and links to one matching verified IPA. Source review or doc-only edits do not consume a new native build.

Measure on an actual supported device using repeatable scenarios: cold/warm start, 1/10/30 windows, increasing ordinary/chat tab counts, overview/minimize, large folders and background/foreground transitions. Record median and tail input/frame latency, main-thread stalls, memory high-water mark, WebKit terminations and launch/download success. Set budgets from a baseline instead of inventing performance gains from the video.

## Video-specific conclusions

- **0:08.2–0:08.6:** white enlargement backing flash. Backing adjustment is in the successful IPA; visual comparison remains open.
- **0:11–0:19:** repeated moves retain rendered content in the inspected sequences. This is not a claim of measured perfect animation.
- **0:20–0:35:** address editing, Google suggestions and navigation work.
- **0:38–1:18:** chat creation, selection, renaming and the context menu work; discovery and title sizing need refinement.
- **1:19–1:43:** split panes are real and independently usable; top-row/composer viewport stability needs work.
- **1:46–1:49:** the bookmark parent/submenu is an intentional hierarchy, not proof of the former multiple-menu linger bug.
- **About 1:55:** the closing transition feels abrupt; no exact frame-duration claim is made.
- **Final seconds:** iPadOS Control Center is system UI, not a SideOS defect.

The clip does not clearly show a cold-start Resume failure. The automatic-restoration defect was established through source paths and regression tests rather than invented as a video observation.

## Reference boundaries

- [Apple: UIDragInteractionDelegate](https://developer.apple.com/documentation/uikit/uidraginteractiondelegate). The drag end callback is `dragInteraction(_:session:didEndWith:)`; `sessionDidEnd` is not the matching UIDragInteraction delegate requirement.
- [Automatic restoration implementation notes](automatic-tab-restoration.md).
- [Existing build policy](../AGENTS.md) and [component cache notes](build-efficiency.md).

This audit intentionally avoids claiming control over arbitrary iPadOS system processes, unsupported private Safari features, a full cryptographic audit, or runtime validation that has not happened. It also does not classify the existing opaque browser toolbar, approved web apps, isolated profile stores or already-fixed guest Dock icons as missing features.
