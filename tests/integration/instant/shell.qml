import QtQuick
import Quickshell
ShellRoot {
    id: test
    property string scenario: Quickshell.env("YETIMAIL_SCENARIO")
    property int phase: 0
    property int ticks: 0
    property bool failed: false
    property string oldKey: ""
    property string bKey: ""
    property bool sawProbe: false
    property bool sawColdLoad: false
    function check(ok, why) {
        if (!ok) {
            failed = true
            console.error("INSTANT_FAIL " + scenario + " phase " + phase + ": " + why)
            Qt.quit()
        }
        return ok
    }
    function pass() { console.log("INSTANT_OK " + scenario); Qt.quit() }
    function live(account, version) {
        return mail.messages.length === 1 && mail.messages[0].subject === account + ":" + version + ":live"
    }
    function idle() { return !mail.listJob && !mail.listQueue.length && !mail.loading && !mail.refreshing }
    MailService { id: mail; account: "A"; config: "/synthetic/old.toml" }
    Timer {
        interval: 10; running: true; repeat: true
        onTriggered: {
            if (test.failed) return
            if (!test.check(++test.ticks < 1000, "timeout")) return
            if (!test.check(!mail.listError && !mail.readError, "unexpected service error")) return
            if (!test.check(mail.messages.every(function(m) { return m.id === mail.account + "-1" && m.unread }),
                            "wrong account displayed or seen state changed")) return
            var s = test.scenario
            if (test.phase === 0) {
                if (mail.listJob && mail.listJob.probe) {
                    test.sawProbe = true
                    if (!test.check(mail.loading && !mail.messages.length, "cold probe must block empty list")) return
                }
                if (mail.listJob && !mail.listJob.probe) {
                    test.sawColdLoad = true
                    if (s === "hit") {
                        if (!test.check(!mail.loading && mail.refreshing && mail.messages.length === 1 &&
                                        mail.messages[0].subject === "A:old:disk", "disk hit not shown during revalidation")) return
                    } else if (!test.check(mail.loading && !mail.messages.length, "miss unexpectedly populated list")) return
                }
                if (!idle() || !live("A", "old")) return
                if (!test.check(test.sawProbe && test.sawColdLoad, "missing probe/authoritative phases")) return
                test.oldKey = mail.visibleListKey
                if (s === "cold" || s === "hit") { test.pass(); return }
                if (s === "switch" || s === "stale") {
                    mail.account = "B"
                    test.bKey = mail.visibleListKey
                    if (!test.check(mail.loading && !mail.messages.length, "uncached B did not start cold")) return
                } else if (s === "refresh" || s === "config") {
                    mail.refresh()
                    if (!test.check(!mail.loading && mail.refreshing && live("A", "old"), "cached refresh blanked/blocked list")) return
                } else if (s === "warm") {
                    // No implicit/default account, duplicates, or non-string entries.
                    mail.warmAccounts(["A", "B", "B", "", "  ", null, 42, "C"])
                    if (!test.check(mail.listQueue.length === 2 && mail.listQueue.every(function(j) {
                        return !j.foreground && (j.context.account === "B" || j.context.account === "C") &&
                               j.context.folder === "" && j.context.page === 1
                    }), "warming queued current/unallowlisted account or non-Inbox page")) return
                    if (!test.check(!mail.loading && !mail.refreshing && live("A", "old"), "warming disturbed foreground")) return
                }
                test.phase = 1
                return
            }
            if (s === "switch") {
                if (test.phase === 1) {
                    if (!idle() || !live("B", "old")) return
                    mail.account = "A"
                    if (!test.check(!mail.loading && live("A", "old"), "A was not restored synchronously")) return
                    test.phase = 2
                } else {
                    if (!test.check(!mail.loading && live("A", "old"), "restored list blanked while refreshing")) return
                    if (idle()) test.pass()
                }
            } else if (s === "stale") {
                if (test.phase === 1) {
                    if (!mail.listJob || mail.listJob.probe || mail.listJob.context.account !== "B") return
                    mail.account = "A"
                    if (!test.check(!mail.loading && live("A", "old"), "return blocked by B in flight")) return
                    test.phase = 2
                } else {
                    if (!test.check(!mail.loading && live("A", "old"), "inactive B completion replaced A")) return
                    if (!idle()) return
                    if (!test.check(!!mail.pageSnapshots[test.bKey] &&
                                    mail.pageSnapshots[test.bKey].value.messages[0].id === "B-1", "inactive completion not cached")) return
                    mail.account = "B"
                    if (test.check(!mail.loading && live("B", "old"), "inactive snapshot not synchronously reusable")) test.phase = 3
                }
                if (test.phase === 3) {
                    // Exit after restoration, before deferred revalidation starts.
                    test.pass()
                }
            } else if (s === "refresh") {
                if (test.phase === 1) {
                    if (!mail.listJob) return
                    mail.readMessage("A-1")
                    if (!test.check(mail.reading && !mail.loading, "cached refresh blocked explicit read")) return
                    test.phase = 2
                } else if (test.phase === 2) {
                    if (!mail.message) return
                    if (!test.check(mail.message.id === "A-1" && !!mail.listJob && mail.refreshing,
                                    "read waited for list refresh")) return
                    test.phase = 3
                } else if (idle() && !mail.reading) test.pass()
            } else if (s === "config") {
                if (test.phase === 1) {
                    if (!mail.listJob) return
                    mail.config = "/synthetic/new.toml"
                    if (!test.check(!mail.pageSnapshots[test.oldKey] && mail.loading && !mail.messages.length,
                                    "config change restored old snapshot")) return
                    test.phase = 2
                } else {
                    if (!test.check(!mail.pageSnapshots[test.oldKey] && Object.keys(mail.pageSnapshots).every(function(k) {
                        return mail.pageSnapshots[k].context.config === "/synthetic/new.toml"
                    }) && mail.messages.every(function(m) { return m.subject === "A:new:live" }),
                                    "old config completion repopulated snapshots/UI")) return
                    if (idle() && live("A", "new")) test.pass()
                }
            } else if (s === "warm") {
                if (!test.check(!mail.loading && !mail.refreshing && live("A", "old"), "background warm blocked/changed A")) return
                if (!idle() || mail.folderWarmJob || mail.folderWarmQueue.length) return
                var b = mail.listContext("B", "", 1).key
                var c = mail.listContext("C", "", 1).key
                if (!test.check(!!mail.pageSnapshots[b] && !!mail.pageSnapshots[c], "allowlisted pages not warmed")) return
                mail.account = "B"
                if (test.check(!mail.loading && live("B", "old"), "warm page not instant")) test.pass()
            }
        }
    }
}
