import Foundation

/// The real restoration driver runs against controlled pages, without WebKit.
@MainActor final class TahoeBrowserTab {
    let id = UUID()
    var needsAutomaticRestore = true
    var starts = 0
    var timeouts = 0
    var canStart = true
    func beginAutomaticRestore() -> Bool {
        needsAutomaticRestore = false
        starts += 1
        return canStart
    }
    func automaticRestoreTimedOut() { timeouts += 1 }
}

@main struct PageRestorationTests {
    @MainActor static func settle(until condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        precondition(condition(), "Restoration driver did not make progress")
    }
    @MainActor static func main() async {
        var queue = TahoePageRestoreQueue<String>()
        queue.enqueue("background-a"); queue.enqueue("background-b")
        queue.enqueue("selected", priority: true)
        precondition(queue.next() == "selected")
        queue.enqueue("selected", priority: true)
        precondition(queue.next() == "background-a" && queue.next() == nil)
        queue.remove("selected")
        precondition(queue.next() == "background-b")
        queue.remove("background-a"); queue.remove("background-b")
        precondition(queue.pending.isEmpty && queue.active.isEmpty)

        let driver = TahoePageRestoration()
        let first = TahoeBrowserTab(), second = TahoeBrowserTab(), selected = TahoeBrowserTab()
        driver.setActive(false)
        driver.request(first); driver.request(second); driver.request(selected, priority: true)
        try? await Task.sleep(for: .milliseconds(10))
        precondition(first.starts + second.starts + selected.starts == 0, "Background app must not initiate restores")
        driver.setActive(true)
        await settle { selected.starts == 1 && first.starts == 1 }
        precondition(second.starts == 0, "Only two loads may start concurrently across windows")
        driver.request(selected, priority: true)
        driver.finish(selected.id)
        await settle { second.starts == 1 }
        precondition(selected.starts == 1, "Selecting a loaded page must not navigate again")
        driver.finish(first.id); driver.finish(second.id)

        let cancelled = TahoeBrowserTab(), replacement = TahoeBrowserTab()
        driver.setActive(false)
        driver.request(cancelled); driver.finish(cancelled.id)
        driver.request(replacement)
        driver.setActive(true)
        await settle { replacement.starts == 1 }
        precondition(cancelled.starts == 0, "A closed pending tab must never be resurrected")
        driver.finish(replacement.id)

        let invalid = TahoeBrowserTab(), afterInvalid = TahoeBrowserTab()
        invalid.canStart = false
        driver.request(invalid); driver.request(afterInvalid)
        await settle { afterInvalid.starts == 1 }
        driver.finish(afterInvalid.id)
        let further = TahoeBrowserTab()
        driver.request(further)
        await settle { further.starts == 1 }
        driver.finish(further.id)

        let timeoutDriver = TahoePageRestoration(timeout: .milliseconds(10))
        let hungA = TahoeBrowserTab(), hungB = TahoeBrowserTab(), waiting = TahoeBrowserTab()
        timeoutDriver.request(hungA); timeoutDriver.request(hungB); timeoutDriver.request(waiting)
        await settle { waiting.starts == 1 }
        precondition(hungA.timeouts == 1 || hungB.timeouts == 1, "A hung page must release its queue slot")
        timeoutDriver.finish(hungA.id); timeoutDriver.finish(hungB.id); timeoutDriver.finish(waiting.id)

        let suspensionDriver = TahoePageRestoration(timeout: .milliseconds(500))
        let suspended = TahoeBrowserTab()
        suspensionDriver.request(suspended)
        await settle { suspended.starts == 1 }
        suspensionDriver.setActive(false)
        try? await Task.sleep(for: .milliseconds(600))
        precondition(suspended.timeouts == 0, "App suspension must not consume the page timeout")
        suspensionDriver.setActive(true)
        await settle { suspended.timeouts == 1 }

        var budget = TahoePageRecoveryBudget()
        precondition(budget.allow(at: 100) && budget.allow(at: 110))
        precondition(!budget.allow(at: 120), "Repeated crashes must not cause an endless reload loop")
        precondition(budget.allow(at: 160), "An isolated crash can recover after the cooldown")
        print("Automatic restoration priority, bounded loading, pause/resume, cancellation, invalid-page, timeout and crash recovery checks passed")
    }
}
