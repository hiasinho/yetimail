import QtQuick
import Quickshell
ShellRoot {
    id: test
    property string scenario: Quickshell.env("YETIMAIL_SCENARIO")
    property int phase: 0
    property double since: Date.now()
    property int ticks: 0
    property bool failed: false
    function check(ok, reason) {
        if (!ok) {
            failed = true
            console.error("PREFETCH_FAIL " + scenario + " phase " + phase + ": " + reason)
            Qt.quit()
        }
        return ok
    }
    function advance() { phase++; since = Date.now() }
    function pass() { console.log("PREFETCH_OK " + scenario); Qt.quit() }
    MailService { id: mail; account: "fixture" }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (test.failed) return
            if (++test.ticks > 350) { test.check(false, "timeout"); return }
            var elapsed = Date.now() - test.since
            var s = test.scenario
            if (!test.check(!mail.readError && !mail.actionError && !mail.listError,
                            "background error escaped into UI")) return
            if (!test.check(mail.messages.every(function(m) { return m.unread }),
                            "navigation changed seen state")) return
            switch (test.phase) {
            case 0:
                if (mail.loading || !mail.messages.length) return
                mail.setPrefetchSelection("a")
                if (!test.check(!mail.prefetching, "selection bypassed debounce")) return
                test.advance(); return
            case 1:
                if (elapsed < 100) return
                if (!test.check(!mail.prefetching, "early background launch")) return
                if (s === "debounce") mail.setPrefetchSelection("b")
                if (s === "pending-withdrawal") mail.setPrefetchSelection("")
                test.advance(); return
            case 2:
                if (s === "pending-withdrawal") {
                    if (elapsed < 850) return
                    if (test.check(!mail.prefetching && !mail.prefetchQueue.length && !mail.message,
                                   "withdrawn debounce launched")) test.pass()
                    return
                }
                if (s === "debounce" && elapsed < 250) {
                    test.check(!mail.prefetching, "cursor change did not restart debounce")
                    return
                }
                if (!mail.prefetching) return
                if (!test.check(mail.prefetchId === (s === "debounce" ? "b" : "a"),
                                "wrong cursor prefetched")) return
                if (s === "promotion" || s === "promoted-stale") {
                    mail.readMessage("a")
                    if (!test.check(mail.reading && mail.prefetchForeground, "same-ID not promoted")) return
                    // Widget withdraws list interest when it switches to the reader.
                    mail.setPrefetchSelection("")
                    if (s === "promoted-stale") mail.account = "other"
                } else if (s === "different") {
                    mail.readMessage("e")
                    if (!test.check(mail.reading && !mail.prefetchForeground,
                                    "different-ID foreground blocked/promoted")) return
                    mail.setPrefetchSelection("")
                } else if (s === "account") mail.account = "other"
                else if (s === "config") mail.config = "/synthetic/never-read.toml"
                else if (s === "folder") {
                    mail.folders = [{id: "Archive", name: "Archive", role: "archive"}]
                    if (!test.check(mail.selectFolder("Archive"), "folder transition rejected")) return
                } else if (s === "page") mail.nextPage()
                else if (s === "withdrawal") mail.setPrefetchSelection("")
                else if (s === "inactive") mail.active = false
                test.advance(); return
            case 3:
                // Allow time for accidental queued launches after the first exit.
                if (elapsed < (s === "debounce" || s === "failure" || s === "page" ? 2400 : 1500)) return
                if (!test.check(!mail.prefetching && !mail.reading && !mail.loading &&
                                !mail.prefetchQueue.length, "requests did not drain")) return
                if (s === "promotion" || s === "different") {
                    if (!test.check(mail.message && mail.message.id === (s === "promotion" ? "a" : "e"),
                                    "foreground result missing/wrong")) return
                } else if (!test.check(!mail.message && !mail.selectedId, "background/stale result published")) return
                if (s === "page" && !test.check(mail.page === 2, "page transition missing")) return
                if (s === "folder" && !test.check(mail.folderId === "Archive", "folder transition missing")) return
                test.pass()
            }
        }
    }
}
