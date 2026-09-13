import QtQuick
import Quickshell
import "Yetimail"
ShellRoot {
    id: test
    property int phase: 0
    property int ticks: 0
    property bool failed: false
    property int listRequests: 0
    function check(ok, reason) {
        if (!ok) { failed = true; console.error("MOVES_FAIL " + reason); Qt.quit() }
        return ok
    }
    function has(id) { return mail.messages.some(function(m) { return m.id === id }) }
    MailService { id: mail; account: "offline" }
    Timer {
        running: true; repeat: true; interval: 20
        onTriggered: {
            if (test.failed) return
            if (++test.ticks > 600) { test.check(false, "timeout phase " + test.phase); return }
            if (test.phase === 0 && mail.messages.length === 3 && !mail.loading) {
                if (!test.check(!mail.moveMessage("same", "archive"), "undiscovered destination")) return
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 1 && mail.foldersLoaded) {
                if (!test.check(!mail.moveMessage("absent", "archive") && !mail.moveMessage("same", "unknown")
                    && !mail.moveMessage("same", ""), "move validation")) return
                test.listRequests = mail.listRequest
                if (!test.check(mail.moveMessage("same", "archive"), "first move accepted")) return
                if (!test.check(mail.moveMessage("other", "trash"), "second move queued")) return
                if (!test.check(mail.pendingMoves === 2 && !test.has("same") && !test.has("other") && test.has("third"), "optimistic queue projection")) return
                test.phase++
            } else if (test.phase === 2 && mail.moving) {
                if (!test.check(!mail.selectFolder("in"), "folder switch blocked")) return
                mail.nextPage(); mail.previousPage(); mail.refresh()
                if (!test.check(mail.listRequest === test.listRequests, "page refresh blocked while pending")) return
                mail.readMessage("third")
                test.phase++
            } else if (test.phase === 3 && mail.message && !mail.reading) {
                if (!test.check(mail.moveMessage("third", "archive"), "third move queued after navigation")) return
                if (!test.check(mail.pendingMoves >= 2 && !mail.messages.length, "third row hidden")) return
                test.phase++
            } else if (test.phase === 4 && !mail.movePending && !mail.loading) {
                if (!test.check(!mail.messages.length && mail.listRequest === test.listRequests + 1 && !mail.actionError, "single final reconciliation")) return
                mail.account = "failure-offline"
                test.phase++
            } else if (test.phase === 5 && mail.messages.length === 3 && !mail.loading) {
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 6 && mail.foldersLoaded) {
                if (!test.check(mail.moveMessage("other", "flaky") && mail.moveMessage("same", "archive"), "failure queue setup")) return
                test.phase++
            } else if (test.phase === 7 && mail.movePaused) {
                if (!test.check(mail.pendingMoves === 2 && !test.has("same") && test.has("other") && test.has("third")
                    && mail.messages.map(function(m) { return m.id }).join(",") === "other,third", "failed head restored in stable order")) return
                if (!test.check(mail.retryMoves() && !test.has("other"), "retry re-hides failed head")) return
                test.phase++
            } else if (test.phase === 8 && !mail.movePending && !mail.loading) {
                if (!test.check(!test.has("same") && !test.has("other") && test.has("third") && !mail.actionError, "retry drains queue")) return
                mail.account = "cancel-offline"
                test.phase++
            } else if (test.phase === 9 && mail.messages.length === 3 && !mail.loading) {
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 10 && mail.foldersLoaded) {
                mail.moveMessage("same", "fail")
                mail.moveMessage("other", "archive")
                test.phase++
            } else if (test.phase === 11 && mail.movePaused) {
                if (!test.check(mail.cancelPendingMoves(), "cancel accepted")) return
                if (!test.check(mail.pendingMoves === 0 && mail.messages.map(function(m) { return m.id }).join(",") === "same,other,third", "cancel restores unsent rows in order")) return
                test.phase++
            } else if (test.phase === 12 && !mail.loading) {
                mail.page = 3
                mail.reconcileMoves({generation: mail.generation, account: mail.account, config: mail.config,
                    folder: mail.folderId, page: mail.page})
                mail.account = "stale-offline"
                test.phase++
            } else if (test.phase === 13 && mail.messages.length === 3 && !mail.loading && mail.page === 1) {
                if (!test.check(mail.page === 1, "stale reconciliation keeps reset page")) return
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 14 && mail.foldersLoaded) {
                mail.moveMessage("same", "archive")
                mail.moveMessage("other", "archive")
                mail.account = "new-offline"
                test.phase++
            } else if (test.phase === 15 && !mail.movePending && !mail.loading && mail.account === "new-offline" && mail.messages.length === 3) {
                if (!test.check(mail.messages[0].subject === "new-offline-same" && !mail.actionError, "stale queue discarded")) return
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 16 && mail.foldersLoaded) {
                mail.moveMessage("same", "bad")
                test.phase++
            } else if (test.phase === 17 && mail.movePaused) {
                if (!test.check(test.has("same") && mail.actionError.indexOf("Invalid move") >= 0, "bad response restored")) return
                mail.cancelPendingMoves()
                test.phase++
            } else if (test.phase === 18 && !mail.loading) {
                mail.account = "page-offline"
                test.phase++
            } else if (test.phase === 19 && mail.messages.length === 3 && !mail.loading) {
                mail.nextPage()
                test.phase++
            } else if (test.phase === 20 && mail.page === 2 && mail.messages.length === 4 && !mail.loadingMore) {
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 21 && mail.foldersLoaded) {
                mail.moveMessage("older", "archive")
                test.phase++
            } else if (test.phase === 22 && !mail.movePending && !mail.loading && !mail.refreshing && !mail.listJob) {
                if (!test.check(mail.page === 1 && mail.messages.length === 3,
                    "cross-chunk move rebuilds the continuous list")) return
                mail.account = "batch-offline"
                test.phase = 30
            } else if (test.phase === 30 && mail.messages.length === 3 && !mail.loading) {
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 31 && mail.foldersLoaded) {
                var invalid = [[], ["same", "absent"], ["same", "same"], ["same", 3], ["same", ""]]
                for (var i = 0; i < invalid.length; i++) {
                    if (!test.check(!mail.moveMessages(invalid[i], "archive") && mail.pendingMoves === 0
                        && mail.messages.map(function(m) { return m.id }).join(",") === "same,other,third",
                        "batch validation must not hide or enqueue a valid prefix")) return
                }
                if (!test.check(!mail.moveMessages(["same", "other"], "unknown") && mail.pendingMoves === 0
                    && mail.messages.length === 3, "batch destination validation is atomic")) return
                test.listRequests = mail.listRequest
                if (!test.check(mail.moveMessages(["third", "same"], "archive") && mail.pendingMoves === 2
                    && mail.messages.map(function(m) { return m.id }).join(",") === "other", "batch optimistic projection")) return
                if (!test.check(!mail.moveMessages(["other", "same"], "trash") && mail.pendingMoves === 2
                    && test.has("other"), "queued duplicate rejects entire appended batch")) return
                if (!test.check(mail.moveMessages(["other"], "trash") && mail.pendingMoves === 3
                    && !mail.messages.length, "batch append accepted")) return
                test.phase++
            } else if (test.phase === 32 && !mail.movePending && !mail.loading) {
                if (!test.check(!mail.messages.length && !mail.actionError && mail.listRequest === test.listRequests + 1,
                    "batch drains with one reconciliation")) return
                mail.account = "launch-offline"
                test.phase = 23
            } else if (test.phase === 23 && mail.messages.length === 3 && !mail.loading) {
                mail.loadFolders()
                test.phase++
            } else if (test.phase === 24 && mail.foldersLoaded) {
                mail.moveMessage("same", "launch")
                test.phase++
            } else if (test.phase === 25 && mail.movePaused && mail.actionError === "Launch failure armed Retry or cancel the pending moves.") {
                mail.retryMoves()
                test.phase++
            } else if (test.phase === 26 && mail.movePaused) {
                if (!test.check(test.has("same") && mail.actionError.indexOf("Could not launch Python") >= 0, "failed launch restores and pauses")) return
                console.log("YETIMAIL_MOVES_OK")
                Qt.quit()
            }
        }
    }
}
