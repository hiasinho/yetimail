import QtQuick
import Quickshell
ShellRoot {
    id: test
    property bool demoMode: Quickshell.env("YETIMAIL_SCENARIO") === "demo"
    property int phase: 0
    property int ticks: 0
    property bool failed: false
    property bool sawPartialMark: false
    function check(ok, reason) {
        if (!ok) {
            failed = true
            console.error("PAGINATION_FAIL phase " + phase + ": " + reason)
            Qt.quit()
        }
        return ok
    }
    function pass() { console.log("PAGINATION_OK " + (demoMode ? "demo" : "fixture")); Qt.quit() }
    function busyGuards() {
        var listRequest = mail.listRequest
        var markRequest = mail.markRequest
        mail.nextPage()
        mail.previousPage()
        mail.setRead(mail.messages[0].id, true)
        return check(mail.listRequest === listRequest && mail.markRequest === markRequest,
                     "busy pagination/mutation launched another request")
    }
    MailService {
        id: mail
        demo: test.demoMode
        account: test.demoMode ? "" : "personal"
        onMessagesChanged: {
            if (!test.demoMode && messages.length)
                test.check(messages[0].subject.indexOf((account || "default") + " page ") === 0,
                           "transient stale account envelopes")
        }
    }
    Timer {
        interval: 25; running: true; repeat: true
        onTriggered: {
            if (test.failed) return
            if (++test.ticks > 400) { test.check(false, "timeout"); return }
            if (!test.demoMode && (test.phase === 9 || test.phase === 11) && mail.marking) {
                if (!test.check(mail.messages[0].unread && (mail.pendingMarks === 1
                    ? !mail.messages[1].unread : mail.messages[1].unread),
                    "failed/unsent marks changed optimistically")) return
                if (mail.pendingMarks === 2) {
                    if (!test.check(!mail.messages[2].unread, "successful head not published before next mark")) return
                    test.sawPartialMark = true
                }
                if (!test.busyGuards()) return
            }
            if (mail.loading || mail.loadingMore || mail.reading || mail.marking) return
            if (test.demoMode) { demoStep(); return }
            fixtureStep()
        }
        function fixtureStep() {
            switch (test.phase) {
            case 0:
                if (!mail.messages.length) return
                if (!test.check(mail.page === 1 && mail.messages.length === 1 && mail.hasNext, "initial chunk")) return
                mail.loadMore()
                if (!test.check(mail.loadingMore && mail.page === 1 && mail.messages.length === 1,
                    "older load keeps visible chunk")) return
                break
            case 1:
                if (!test.check(mail.page === 2 && mail.messages.length === 2
                    && mail.messages[1].subject === "personal page 2", "older chunk appended")) return
                mail.setRead("personal-2", true)
                if (!test.check(mail.marking && mail.messages[1].unread, "loaded-row mark waits for success")) return
                if (!test.busyGuards()) return
                break
            case 2:
                if (!test.check(!mail.messages[1].unread && !mail.actionError, "loaded-row seen success")) return
                mail.setRead("personal-2", false)
                break
            case 3:
                if (!test.check(!mail.messages[1].unread && mail.actionError === "fixture mark failure",
                    "failed mark preserves loaded row")) return
                mail.loadMore()
                break
            case 4:
                if (!test.check(mail.page === 2 && mail.messages.length === 2 && !!mail.loadMoreError,
                    "failed older chunk retains continuous list")) return
                mail.showPage(mail.listContext(mail.account, mail.folderId, 1), {
                    page: 1, hasNext: true, account: mail.account,
                    messages: [{id: "personal-new", subject: "personal page new", unread: true}]
                })
                if (!test.check(mail.newMessagesAvailable && mail.messages.length === 2,
                    "changed newest chunk replaced visible older rows")) return
                mail.applyNewestMessages()
                if (!test.check(!mail.newMessagesAvailable && mail.page === 1
                    && mail.messages[0].id === "personal-new", "new list generation was not applied safely")) return
                mail.account = "work"
                break
            case 5:
                if (!mail.messages.length) return
                if (!test.check(mail.page === 1 && mail.messages[0].subject === "work page 1",
                    "account reset starts a new continuous list")) return
                mail.loadMore()
                mail.account = "final"
                break
            case 6:
                if (!mail.messages.length) return
                if (!test.check(mail.page === 1 && mail.messages[0].subject === "final page 1" && !mail.listError,
                    "stale older result rejected after account switch")) return
                mail.account = ""
                break
            case 7:
                if (!mail.messages.length) return
                var request = mail.markRequest
                mail.setRead("default-1", true)
                if (!test.check(!mail.marking && mail.markRequest === request && mail.actionError,
                    "default account mutation was allowed")) return
                mail.account = "batch-success"
                break
            case 8:
                if (mail.messages.length !== 3) return
                var markRequest = mail.markRequest
                var invalid = [[], ["third", "absent"], ["third", "third"], ["third", 3], ["third", ""]]
                for (var i = 0; i < invalid.length; i++) {
                    if (!test.check(!mail.setReadMany(invalid[i], true) && !mail.marking && mail.pendingMarks === 0
                        && mail.markRequest === markRequest && mail.messages.every(function(m) { return m.unread }),
                        "mark batch validation must be atomic")) return
                }
                test.sawPartialMark = false
                if (!test.check(mail.setReadMany(["third", "other", "shared"], true), "mark batch starts")) return
                break
            case 9:
                if (!test.check(test.sawPartialMark && !mail.actionError
                    && mail.messages.every(function(m) { return !m.unread }), "serial mark batch success")) return
                mail.account = "batch-failure"
                break
            case 10:
                if (mail.messages.length !== 3) return
                test.sawPartialMark = false
                mail.setReadMany(["third", "other", "shared"], true)
                break
            case 11:
                if (!test.check(test.sawPartialMark && !mail.markInFlight
                    && !mail.messages[2].unread && mail.messages[0].unread && mail.messages[1].unread
                    && mail.actionError === "fixture batch failure Remaining read-status changes were cancelled.",
                    "failure preserves success and cancels unsent marks")) return
                test.pass(); return
            }
            test.phase++
        }
        function demoStep() {
            if (!test.check(!mail.listError && !mail.readError && !mail.actionError, "demo helper error")) return
            switch (test.phase) {
            case 0:
                if (!mail.messages.length) return
                if (!test.check(mail.page === 1 && mail.messages.length === 50 && mail.hasNext, "demo first page")) return
                mail.setRead("demo-1", true)
                if (!test.check(mail.marking && mail.messages[0].unread, "demo optimistic mutation")) return
                break
            case 1:
                if (!test.check(!mail.messages[0].unread, "demo seen success")) return
                mail.refresh(); break
            case 2:
                if (!test.check(!mail.messages[0].unread, "demo mark lost on refresh")) return
                if (!test.check(mail.loadMore(), "demo loadMore accepted")) return
                if (!test.check(mail.loadingMore, "demo loadMore latched")) return
                break
            case 3:
                if (!test.check(mail.page === 2 && mail.messages.length === 63 && !mail.hasNext,
                    "demo older chunk appended: page=" + mail.page + " messages=" + mail.messages.length + " hasNext=" + mail.hasNext)) return
                var request = mail.listRequest
                mail.loadMore()
                if (!test.check(mail.listRequest === request, "loaded past end of mailbox")) return
                mail.setRead("demo-1", false); break
            case 4:
                if (!test.check(mail.messages[0].unread, "demo unread success")) return
                mail.refresh(); break
            case 5:
                if (!test.check(mail.messages.length === 63 && mail.messages[0].unread,
                    "demo refresh preserved continuous list")) return
                mail.account = "other-demo"
                if (!test.check(mail.page === 1 && !mail.messages.length && !mail.hasNext, "demo account reset")) return
                break
            case 6:
                if (!mail.messages.length) return
                if (!test.check(mail.page === 1 && mail.messages.length === 50 && mail.messages[0].unread,
                    "demo account isolation")) return
                test.pass(); return
            }
            test.phase++
        }
    }
}
