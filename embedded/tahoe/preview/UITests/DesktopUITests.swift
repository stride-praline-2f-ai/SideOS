import XCTest

final class DesktopUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
    }
    private func launchDefaultDesktop() {
        app.launchArguments = ["--uitest", "--light"]
        app.launch()
        let dock = app.buttons["dock-files"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in dock.exists && dock.isHittable }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, "The native desktop must be ready before interaction")
    }
    func testStandaloneWebAppMinimiseRestoreAndFullscreen() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--standalone-test", "--dark"]
        app.launch()
        let pageButton = app.webViews.buttons["Try the browser"].firstMatch
        XCTAssertTrue(pageButton.waitForExistence(timeout: 30))
        pageButton.tap()
        let window = app.otherElements["Standalone Test window"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let original = window.frame
        let header = window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.035))
        header.press(forDuration: 0.2, thenDragTo: header.withOffset(CGVector(dx: 45, dy: 35)))
        XCTAssertGreaterThan(window.frame.minX, original.minX + 20)
        let moved = window.frame
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.035)).doubleTap()
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in window.frame.width > moved.width + 20 }, object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [filled], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["dock-files"].exists, "Fill keeps the Dock")
        XCTAssertTrue(app.buttons["File menu"].exists, "Fill keeps the menu bar")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.02)).doubleTap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(window.frame.width - moved.width) < 2 }, object: window)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: -55, dy: -35)))
        XCTAssertLessThan(window.frame.width, moved.width - 20)
        XCTAssertTrue(app.webViews.buttons["Clicked 1"].firstMatch.exists, "Moving and resizing preserve the live page")
        XCTAssertFalse(app.textFields["Search or enter website"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-tab-")).count, 0)
        app.buttons["Minimise Standalone Test"].tap()
        app.buttons["Restore Standalone Test"].tap()
        XCTAssertTrue(app.webViews.buttons["Clicked 1"].firstMatch.waitForExistence(timeout: 5))
        let green = window.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fullscreen '")).firstMatch
        XCTAssertTrue(green.exists)
        green.tap()
        XCTAssertFalse(app.buttons["File menu"].exists)
        app.buttons["fullscreen-reveal"].tap()
        XCTAssertTrue(app.buttons["Exit Fullscreen"].waitForExistence(timeout: 5))
        app.buttons["Exit Fullscreen"].tap()
        XCTAssertTrue(app.webViews.buttons["Clicked 1"].firstMatch.waitForExistence(timeout: 5))
        attach("Standalone-Web-App")
    }
    func testMenuCommandsAndSpotlight() {
        launchDefaultDesktop()
        app.buttons["Spotlight"].tap()
        let search = app.textFields["Spotlight Search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("System Settings")
        search.typeText("\n")
        XCTAssertTrue(app.buttons["settings-section-Browser"].waitForExistence(timeout: 5))
        attach("Spotlight-Launch")
    }
    func testMissionControlSelectsWindowAndAddsDesktop() {
        launchDefaultDesktop()
        app.buttons["dock-files"].tap()
        app.buttons["View menu"].tap()
        app.buttons["Window Overview"].tap()
        let overview = app.descendants(matching: .any)["mission-control"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        let desktops = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Switch to Desktop "))
        let before = desktops.count
        app.buttons["Add Desktop"].tap()
        XCTAssertEqual(desktops.count, before + 1)
        app.buttons["Switch to Desktop 1"].tap()
        app.buttons["Show Finder"].tap()
        XCTAssertTrue(app.buttons["New Folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dock-files"].isHittable)
        attach("Mission-Control-Restored")
    }
    func testFinderSelectionAndRename() {
        launchDefaultDesktop()
        app.buttons["dock-files"].tap()
        let create = app.buttons["New Folder"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let item = app.descendants(matching: .any)["finder-item-New Folder"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertFalse(app.buttons["Dismiss menu"].exists, "A primary touch selects without opening a context menu")
        app.buttons["Selection Actions"].tap()
        app.buttons["Rename…"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "New Folder".count) + "My Folder")
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["finder-item-My Folder"].firstMatch.waitForExistence(timeout: 5))
        attach("Finder-Renamed")
    }
    func testRenameSheetSurvivesMinimiseAndRestore() {
        launchDefaultDesktop()
        app.buttons["dock-files"].tap()
        app.buttons["New Folder"].tap()
        let item = app.descendants(matching: .any)["finder-item-New Folder"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertFalse(app.buttons["Dismiss menu"].exists, "A primary touch selects without opening a context menu")
        app.buttons["Selection Actions"].tap()
        app.buttons["Rename…"].tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        app.buttons["Minimise Finder"].tap()
        let dock = app.buttons["dock-files"]
        XCTAssertTrue(dock.isHittable)
        waitUntilNotHittable(app.keyboards.firstMatch)
        dock.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "New Folder")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        attach("Finder-Rename-Restored")
    }
    func testSevenBrowserToolbarShadesPersistAcrossSettingsNavigation() {
        launchDefaultDesktop()
        app.buttons["dock-settings"].tap()
        let browser = app.buttons["settings-section-Browser"]
        XCTAssertTrue(browser.waitForExistence(timeout: 8))
        browser.tap()

        let names = ["standard", "charcoal", "graphite", "deepBlack",
                     "nearBlack", "midnight", "oledBlack"]
        for shade in names {
            XCTAssertTrue(app.buttons["browser-toolbar-shade-\(shade)"].exists,
                          "All seven solid browser shade presets must be accessible")
        }
        let oled = app.buttons["browser-toolbar-shade-oledBlack"]
        oled.tap()
        XCTAssertTrue(oled.isSelected, "OLED Black must be selectable")
        app.buttons["settings-section-Desktop & Dock"].tap()
        browser.tap()
        XCTAssertTrue(app.buttons["browser-toolbar-shade-oledBlack"].isSelected,
                      "Returning to Browser settings must retain the chosen shade")
        let original = app.buttons["browser-toolbar-shade-standard"]
        original.tap()
        XCTAssertTrue(original.isSelected, "Standard must remain available as a reversible choice")
        attach("Browser-Seven-Solid-Shades")
    }

    func testBrowserDefaultRadioSelection() {
        launchDefaultDesktop()
        app.buttons["dock-settings"].tap()
        let section = app.buttons["settings-section-Browser"]
        XCTAssertTrue(section.waitForExistence(timeout: 8))
        section.tap()
        let mobile = app.buttons["iPadOS Original"]
        XCTAssertTrue(mobile.waitForExistence(timeout: 5))
        mobile.tap()
        XCTAssertTrue(mobile.isSelected)
        app.buttons["macOS Safari"].tap()
        XCTAssertTrue(app.buttons["macOS Safari"].isSelected)
        attach("Settings-Radio")
    }
    func testZZShowcaseAndBrowserInput() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--light"]
        app.launch()
        let button = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(app.webViews.buttons["Clicked 1"].waitForExistence(timeout: 5))
        attach("Desktop-Light")
    }
    func testBrowserFullscreenRevealPreservesPageAndWindow() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--light"]
        app.launch()
        let first = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        first.tap()
        let page = app.webViews.firstMatch
        let original = page.frame
        let green = app.buttons["Fullscreen A place for your ideas"]
        XCTAssertTrue(green.waitForExistence(timeout: 5)); green.tap()
        let reveal = app.buttons["fullscreen-reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["File menu"].exists)
        XCTAssertFalse(app.buttons["dock-files"].exists)
        // Wait for the window transition before measuring the fixed viewport.
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in page.frame.width > original.width + 20 }, object: page)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        let clicked = app.webViews.buttons["Clicked 1"]
        XCTAssertTrue(clicked.waitForExistence(timeout: 5))
        let before = page.frame
        reveal.tap()
        XCTAssertTrue(app.buttons["File menu"].waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame.minY, before.minY, accuracy: 1, "Revealed controls overlay the page")
        XCTAssertEqual(page.frame.height, before.height, accuracy: 1, "No viewport resize on reveal")
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Exit Fullscreen"])
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 8), .completed, "Touch reveal hides again when idle")
        app.buttons["fullscreen-reveal"].tap()
        app.buttons["File menu"].tap()
        XCTAssertTrue(app.buttons["Open Location…"].waitForExistence(timeout: 5))
        attach("Browser-Fullscreen-Menu")
        app.buttons["File menu"].tap()
        app.buttons["Exit Fullscreen"].tap()
        XCTAssertTrue(app.buttons["dock-files"].waitForExistence(timeout: 5))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(page.frame.width - original.width) < 1 }, object: page)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertEqual(page.frame.width, original.width, accuracy: 1)
        XCTAssertEqual(page.frame.height, original.height, accuracy: 1)
        clicked.tap()
        XCTAssertTrue(app.webViews.buttons["Clicked 2"].waitForExistence(timeout: 5), "Fullscreen must retain the original live page")
        attach("Browser-Fullscreen-Restored")
    }
    func testBrowserTabSwitchPreservesBothLivePages() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--tab-switch-test", "--dark"]
        app.launch()
        let firstButton = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(firstButton.waitForExistence(timeout: 30))
        firstButton.tap()
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-tab-"))
        XCTAssertEqual(tabs.count, 2)
        // Click near the end of the tab, beyond its text, to verify the full hit area.
        tabs.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let secondButton = app.webViews.buttons["Try second tab"]
        XCTAssertTrue(secondButton.waitForExistence(timeout: 5))
        secondButton.tap()
        for _ in 0..<3 {
            tabs.element(boundBy: 0).tap()
            XCTAssertTrue(app.webViews.buttons["Clicked 1"].waitForExistence(timeout: 5))
            tabs.element(boundBy: 1).tap()
            XCTAssertTrue(app.webViews.buttons["Clicked 1"].waitForExistence(timeout: 5))
        }
        tabs.element(boundBy: 0).tap()
        let clickedButtons = app.webViews.buttons.matching(NSPredicate(format: "label == %@", "Clicked 1"))
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            clickedButtons.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        guard let visibleClicked = clickedButtons.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("The selected tab must expose its live page button")
            return
        }
        visibleClicked.tap()
        XCTAssertTrue(app.webViews.buttons["Clicked 2"].waitForExistence(timeout: 5))
        attach("Browser-Tabs-Retained")
    }
    func testBrowserChromeControlsRemainAccessible() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--tab-switch-test", "--dark"]
        app.launch()
        let open = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        open.tap()
        XCTAssertTrue(app.buttons["browser-sidebar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Back"].exists)
        XCTAssertTrue(app.buttons["Forward"].exists)
        XCTAssertTrue(app.buttons["Share website"].exists)
        XCTAssertTrue(app.buttons["New tab"].exists)
        XCTAssertTrue(app.buttons["Show all tabs"].exists)
        XCTAssertTrue(app.buttons["Translate page text"].exists)
        XCTAssertTrue(app.buttons["Reload"].exists || app.buttons["Stop loading"].exists)
        XCTAssertTrue(app.textFields["browser-address"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-tab-")).count, 2)
        attach("Browser-Safari-Chrome")
    }

    func testGoogleSearchPanelAppearsBeforeRemoteAutocomplete() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--tab-switch-test", "--dark"]
        app.launch()
        let open = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        open.tap()

        let address = app.textFields["browser-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("b")

        // One character is not sent to Google. The local search action
        // nevertheless appears immediately, without any network dependency.
        let panel = app.otherElements["browser-suggestions-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        let searchAction = app.buttons["browser-suggestion-search"]
        XCTAssertTrue(searchAction.exists)
        XCTAssertTrue(searchAction.label.contains("b"))

        address.typeText("arbican library")
        XCTAssertTrue(panel.exists, "Panel must stay visible during continuous typing")
        XCTAssertTrue(searchAction.label.lowercased().contains("barbican library"))
        attach("Google-Live-Typing")
    }

    func testBrowserGoogleSuggestionPanelAndSearchFallback() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--tab-switch-test", "--dark"]
        app.launch()
        let open = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        open.tap()

        let address = app.textFields["browser-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("barbican library")
        let panel = app.otherElements["browser-suggestions-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Suggestions should float under the address bar without navigation")
        XCTAssertTrue(app.buttons["browser-suggestion-search"].exists,
                      "A normal Google search must remain available even without autocomplete responses")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-tab-")).count, 2,
                       "Opening suggestions must not replace or recreate any browser tabs")
        attach("Browser-Google-Liquid-Glass-Suggestions")
    }

    func testGlassToolbarCancelsDraggedPressAndActivatesOnce() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--tab-switch-test", "--dark"]
        app.launch()
        let page = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(page.waitForExistence(timeout: 30))
        page.tap()
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-tab-"))
        XCTAssertEqual(tabs.count, 2)
        let newTab = app.buttons["New tab"]
        XCTAssertTrue(newTab.isHittable)
        let start = newTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 100)))
        XCTAssertEqual(tabs.count, 2, "Releasing outside a glass action cancels activation")
        newTab.tap()
        let added = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in tabs.count == 3 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [added], timeout: 5), .completed, "A tap adds exactly one tab")
        tabs.element(boundBy: 0).tap()
        XCTAssertTrue(app.webViews.buttons["Clicked 1"].waitForExistence(timeout: 5), "Toolbar feedback must retain the existing live page")
    }

    func testBrowserTopPocketAndUnderScrollScreenshots() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--scroll-under-test", "--dark"]
        app.launch()
        let browser = app.webViews.firstMatch
        let first = browser.staticTexts["DOCUMENT START 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        let strip = app.descendants(matching: .any)["browser-chrome-tab-strip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        func assertStartsBelowChrome(_ marker: XCUIElement) {
            let positioned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                marker.exists && marker.frame.minY >= strip.frame.maxY - 2 && marker.frame.minY <= strip.frame.maxY + 4
            }, object: marker)
            XCTAssertEqual(XCTWaiter.wait(for: [positioned], timeout: 5), .completed,
                "The first document pixels must start directly below the complete tab/toolbar chrome")
            XCTAssertTrue(marker.isHittable, "Document-start content must be fully visible")
        }
        assertStartsBelowChrome(first)
        attach("Browser-Starts-Below-Chrome")
        browser.swipeUp()
        let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !first.exists || !first.isHittable }, object: first)
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed)
        attach("Browser-Page-Under-Glass-After-Scroll")
        browser.buttons["Back to top"].tap()
        assertStartsBelowChrome(first)
        attach("Browser-Top-Pocket-Restored")
        browser.swipeUp()
        browser.buttons["Open next page"].tap()
        let next = browser.staticTexts["DOCUMENT START 2"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        assertStartsBelowChrome(next)
        attach("Browser-New-Navigation-Starts-Below-Chrome")
    }

    func testBrowserProfilesKeepTabsSeparateAndRestorable() {
        app.terminate()
        app.launchArguments = ["--uitest", "--showcase", "--tab-switch-test", "--dark"]
        app.launch()
        let open = app.webViews.buttons["Try the browser"]
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        open.tap()
        // Safari hides the profile selector in compact window chrome. Open
        // fullscreen before inspecting the wide-screen profile control.
        let fullscreen = app.buttons["Fullscreen A place for your ideas"]
        XCTAssertTrue(fullscreen.waitForExistence(timeout: 5))
        fullscreen.tap()
        let profile = app.buttons["browser-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        let tabs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser-tab-"))
        XCTAssertEqual(tabs.count, 2)

        profile.tap()
        XCTAssertTrue(app.buttons["Work"].waitForExistence(timeout: 5))
        app.buttons["Work"].tap()
        XCTAssertEqual(tabs.count, 1, "Work starts with its own tab row")
        profile.tap()
        app.buttons["Private"].tap()
        XCTAssertEqual(tabs.count, 1, "Private starts in a distinct tab group")
        profile.tap()
        app.buttons["Personal"].tap()
        XCTAssertEqual(tabs.count, 2, "Switching back keeps both Personal tabs alive")
        XCTAssertTrue(app.webViews.buttons["Clicked 1"].firstMatch.waitForExistence(timeout: 5), "Returning to Personal must retain the page state changed before switching profiles")
        attach("Browser-Profile-Isolation")
    }

    private func waitUntilNotHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let completed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: element)], timeout: 5)
        XCTAssertEqual(completed, .completed, "Wait for the window/keyboard transition to complete", file: file, line: line)
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

