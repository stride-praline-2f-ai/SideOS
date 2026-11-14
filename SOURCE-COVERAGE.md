# Four-project implementation coverage

The desktop uses one native Tahoe design system. Source adaptations, native
platform replacements and irrelevant platform code are distinguished below.
The shared controls are connected to working screens; code presence alone does
not establish native visual fidelity or device compatibility.

## macos-ui (React)

Reference `sylonik/macos-ui` at `bcdea1df8c52b97cfa3f0b9620e4953dc7a6633d`.

| Family | Native implementation |
| --- | --- |
| Window / window manager | `WindowState.swift`, `DesktopWindow.swift`: drag, eight resize edges, focus/stacking, minimise/restore, zoom, fullscreen from green, separate Fill/Zoom, floating movement behind the Dock, bounds, tiling, Spaces and persisted restoration. |
| Dock | `Dock.swift`: source distance falloff, pointer magnification, labels, running indicators, launch/restore, pinned links, ordering, real guest artwork, distinct window previews, active-download badges, context actions, Trash and auto-hide. |
| Desktop icons | `DesktopIcons.swift`, `SelectionViews.swift`: source selection appearance and activation, extended with command/shift selection, drag placement, persisted positions, rubber-band selection, Quick Look, clipboard and contextual actions. |
| Menu bar | `MenuBar.swift`, `Menus.swift`: working commands, check/disabled states, nested submenus, edge-aware placement, pointer/touch, arrow/Home/End/Enter/Escape navigation and type-ahead. |
| Theme | Native appearance/accent preferences and shared palette; React theme-provider APIs are replaced by SwiftUI environment/state. |

## macos-components (React) and MacVue (Vue)

References `tamnguyenvan/macos-components` at
`e82dbfa3702a156e4b9947337dea3d496a162905` and `antonreshetov/macvue` at
`7a9cc21515e3522e63d91d70690a94eecec50564`.

| Component family | Implementation / use |
| --- | --- |
| Button / icon button | `Design.swift`: sizes, variants, pressed/disabled styling; app toolbars, dialogs and settings. |
| Switch / switch row | Native toggle bindings and source track/thumb sizes in `Design.swift`; Dock/browser settings and Control Center. |
| Checkbox / mixed checkbox | `Design.swift`, `Controls.swift`: native toggle and off/on/mixed states; settings and Finder Select All. MacVue's 16pt Tahoe checkbox takes precedence over the React library's older 13pt variant. |
| Radio group | `Controls.swift`: source geometry, selected/disabled states and roving keyboard selection; browser defaults. |
| Slider | `Controls.swift`, `Interaction.swift`: size tokens, thumb/track, ticks, bounds/steps, pointer/keyboard/VoiceOver adjustment; Dock size and brightness. |
| Stepper | `Controls.swift`, `Interaction.swift`: sizes, boundaries, optional wrapping, keyboard and MacVue's accelerating press-and-hold; Dock size. Repeats cancel on blur/hiding/backgrounding. |
| Text/search/secure fields | `Controls.swift`: shared field chrome, focus halos, disabled/error styling; Finder/app search, address entry, rename and real WebKit HTTP-authentication forms. Native secure text entry replaces browser inputs. |
| Text area | Optional local Scratchpad with autosave; iCloud Notes remains a separate web app. |
| Segmented control | `Controls.swift`: single/multiple modes, selection pill, sizes, disabled options and keyboard selection; Finder view modes. |
| Tabs | `Tabs.swift`: shared native tab strip, close/add, selected state, roving keyboard and global next/previous shortcuts; browser sessions retain ownership of page objects. |
| Menu / popup / pulldown / navigation | `Menus.swift`: shared entries, separators, shortcuts, checks, disabled/destructive states, nested menus, bounded placement and keyboard navigation; menu bar, Finder toolbar and browser options. |
| Progress / spinner | `Controls.swift`: determinate/indeterminate progress and spinner; browser loading, downloads and file/wallpaper work. Motion respects Reduce Motion and hidden-window state. |
| Window / traffic lights | `DesktopWindow.swift`: source colours, compact document and unified browser/Settings chrome, neutral toolbar glass, active/inactive state, hover glyphs, native focus/lifecycle. |
| Sidebar / list rows | `Design.swift` and app screens: shared bounded sidebar, native row selection and narrow-window navigation recovery. |
| Table | `SelectionViews.swift`, `Files.swift`: compact headers/zebra rows, column sorting/resizing, horizontal overflow, single/range/toggle selection and contextual actions. |
| Alert / sheet | `Dialogs.swift`: shared in-window modal, field validation, cancellation and destructive confirmation; Finder, Notes, performance fullscreen and Dock Trash. Keyboard-aware layout keeps rename actions above the on-screen keyboard without moving the desktop. Browser site dialogs resolve real WebKit callbacks. |
| Badge / disclosure | `Controls.swift`: source-style compact badges and collapsible disclosure; Finder item count and source/about details. |
| Settings group / row / box / label / separator | Shared settings cards, typography, native rows and dividers in `Controls.swift`, `Settings.swift` and app layouts. Duplicate framework wrapper APIs are not reproduced independently. |
| Help / tooltip | `Tabs.swift`: shared help control and anchored explanation, delayed hover tooltip with cancellation; Settings and toolbar actions. |
| Popover / glass panel | Anchored native help popovers, calendar/Control Center overlays, bounded shared menus, native Apple glass on supported iPadOS with accessible material fallback. Chromium SVG displacement is replaced, not executed. |

## macos_ui (Flutter)

Reference `macosui/macos_ui` at `dec19cf6960721f80165ead6c9c19594030b292f`.

| Family | Adaptation |
| --- | --- |
| Sidebar / resizable panes / scaffold | Bounded sidebar, drag/VoiceOver resizing, compact sidebar drawer and shared app content composition. |
| Toolbar / overflow | `Interaction.swift`, `Menus.swift`: reserve overflow-button space, keep a visible command prefix and make remaining commands available in the same order. Finder uses this layout. |
| Table/list/navigation/dialog patterns | Shared native selection, file navigation/history, rows and parent-window modal presentation. |
| Colour well | Custom accent selection uses the host's native colour picker; the value is persisted and applied across the desktop. AppKit NSColorPanel is replaced by the iPad picker. |
| Date selector | `Calendar.swift`: native month navigation, locale-aware weekdays, day grid, selection, Today and arrow-key date movement. |
| Controls and theme | Selected control/layout/focus patterns are consolidated with the two React/Vue design sources. There are no duplicate Flutter control implementations in the app. |
| Scrollbars/text/input | Native scrolling, text editing, sharing and platform permissions preserve iPad input/accessibility behaviour. |
| macOS window utilities, accent listeners | macOS-only platform calls cannot run on iPadOS. Local window state and explicit desktop accent preferences provide the applicable behaviour. |
| Capacity/rating/relevance indicators, standalone time-picker variants | No current desktop screen needs these separate library components. They are not claimed as ported. |

## Validation and boundaries

Portable fixtures cover window lifecycle/geometry, Spaces/restoration, URL
handling, calculator, atomic copy/move, selection, numeric stepping/wrapping,
menu navigation, popup bounds, desktop placement and toolbar overflow.

Cheap Linux checks run ten portable Swift executable groups, 22 DOM fixtures,
14 real Chromium layout checks and 24 Python build/signing/policy tests. Device
GitHub Actions compile the combined native runtime and package the unsigned IPA;
they also validate adapter signatures and desktop-owned compiler warnings.
No simulator or preview job is part of this release path. Consult the exact
revision's Actions run for results. Compilation does not establish visual
fidelity, LiveContainer/JIT device compatibility or measured rendering performance.

The pinned-engine review inspected targeted integration source rather than every
upstream dependency. Private scene hosting, guest launch/signing contracts and
upstream serial queues remain intact. Multi-scene/external-display activation,
full localization, dynamic text and hardware performance need further validation.
See docs/full-project-implementation.md and docs/device-validation.md.
