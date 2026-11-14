import SwiftUI
import WebKit

struct TahoeBrowserView: View {
    @ObservedObject var session: TahoeBrowserSession
    var windowID: UUID
    @EnvironmentObject private var workspace: TahoeWorkspace
    @ObservedObject private var preferences = TahoePreferences.shared
    @ObservedObject private var chrome = TahoeFullscreenChrome.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tahoeWindowVisible) private var windowVisible
    @Environment(\.tahoeWindowActive) private var windowActive
    private var standalone: Bool { workspace.state.windows.first(where: { $0.id == windowID })?.isWebApp == true }
    private var navigationHeight: CGFloat { standalone ? (workspace.state.fullscreenID == windowID ? 0 : TahoeDesign.titleHeight) : TahoeDesign.navigationHeight }
    private var tabHeight: CGFloat { standalone ? 0 : TahoeDesign.tabHeight }
    private var warningOffset: CGFloat {
        if standalone, workspace.state.fullscreenID == windowID, chrome.revealed {
            return TahoeDesign.menuBarHeight + TahoeDesign.titleHeight
        }
        let menu = !standalone && workspace.state.fullscreenID == windowID && chrome.revealed ? TahoeDesign.menuBarHeight : 0
        return navigationHeight + tabHeight + menu
    }
    private var chromeInset: CGFloat { warningOffset + TahoeBrowserSafety.height }
    private var selectedTab: TahoeBrowserTab? {
        session.tabs.first { $0.id == session.selectedID }
    }
    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                ForEach(session.tabs) { tab in
                    let selected = tab.id == session.selectedID
                    TahoeBrowserPage(tab: tab, windowID: windowID, chromeInset: chromeInset)
                        .environment(\.tahoeWindowVisible, windowVisible && selected)
                        .environment(\.tahoeWindowActive, windowActive && selected)
                        .opacity(selected ? 1 : 0)
                        .allowsHitTesting(selected && windowVisible)
                        .accessibilityHidden(!selected || !windowVisible)
                        .zIndex(selected ? 1 : 0)
                }
            }.animation(nil, value: session.selectedID)
            if !standalone, let tab = selectedTab {
                // Native empty scroll pocket, below the glass but above the
                // page. At top, no website colours or text bleed into chrome.
                // Once scrolled, the full WKWebView is revealed beneath it.
                TahoeBrowserScrollPocket(tab: tab.activePage, height: chromeInset)
                    .zIndex(1)
            }
            if !standalone {
                TahoeBrowserTabs(session: session)
                    .padding(.top, navigationHeight)
                    .offset(y: workspace.state.fullscreenID == windowID && chrome.revealed ? TahoeDesign.menuBarHeight : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: chrome.revealed)
                    .zIndex(2)
            }
            TahoeBrowserSafetyBanner()
                .offset(y: warningOffset).frame(maxHeight: .infinity, alignment: .top).zIndex(3)
        }.buttonStyle(TahoePressStyle())
            .onChange(of: windowVisible, initial: true) { _, visible in
                if visible { session.resumePages() }
            }
    }
}

private struct TahoeBrowserScrollPocket: View {
    @ObservedObject var tab: TahoeBrowserTab
    let height: CGFloat
    @ObservedObject private var preferences = TahoePreferences.shared

    var body: some View {
        Rectangle()
            .fill(preferences.value.appearance == "oled" ? Color.black : preferences.value.appearance == "dark" ? Color(white: 0.14) :
                  preferences.value.appearance == "light" ? Color.white : Color(uiColor: .systemBackground))
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(tab.hasScrolledBelowChrome ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: tab.hasScrolledBelowChrome)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct TahoeTabLabel: View {
    @ObservedObject var tab: TahoeBrowserTab
    var body: some View {
        HStack(spacing: 6) {
            if tab.isSleeping {
                Image(systemName: "moon.zzz").frame(width: 16, height: 16).foregroundStyle(.secondary).accessibilityLabel("Sleeping")
            } else if tab.loading {
                ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel("Loading")
            } else if let favicon = tab.favicon {
                Image(uiImage: favicon).resizable().interpolation(.high)
                    .scaledToFit().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "globe").font(.system(size: 13, weight: .regular))
                    .frame(width: 16, height: 16).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(tab.title).font(.system(size: 13.5, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
            if tab.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Pinned") }
            if tab.activePage.playingMedia { Image(systemName: "speaker.wave.2.fill").font(.caption2).foregroundStyle(.secondary).accessibilityLabel("Playing media") }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Safari-style unified toolbar: the window lights, navigation and address
/// live in one row. This toolbar never owns or recreates the WKWebView.
struct TahoeBrowserToolbar: View {
    @ObservedObject var session: TahoeBrowserSession
    let windowID: UUID
    var body: some View {
        if let tab = session.tabs.first(where: { $0.id == session.selectedID }) {
            TahoeBrowserNavigation(tab: tab.activePage, session: session, windowID: windowID,
                                   suggestions: tab.activePage.suggestions).id(tab.activePage.id)
        }
    }
}

