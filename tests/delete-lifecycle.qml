import QtQuick
import Quickshell
import "Jitsmail"
ShellRoot {
    id: test
    property int phase: 0
    property int ticks: 0
    property bool failed: false
    property int requests: 0
    function check(ok, reason) {
        if (!ok) { failed = true; console.error("DELETIONS_FAIL " + reason); Qt.quit() }
        return ok
    }
    function has(id) { return mail.messages.some(function(m) { return m.id === id }) }
    MailService { id: mail; account: "offline" }
    Timer {
        running: true; repeat: true; interval: 20
        onTriggered: {
            if (test.failed) return
            if (++test.ticks > 450) { test.check(false, "timeout phase " + test.phase); return }
            if (test.phase === 0 && mail.messages.length && !mail.loading) {
                if (!test.check(!mail.deleteMessage(1) && !mail.deleteMessage("") && !mail.deleteMessage("absent"), "invalid IDs")) return
                for (var flag of ["loading", "reading", "marking", "moving", "savingAttachment", "openingAttachment"]) {
                    mail[flag] = true
                    if (!test.check(!mail.deleteMessage("same"), flag + " guard")) return
                    mail[flag] = false
                }
                mail.ready = false
                if (!test.check(!mail.deleteMessage("same"), "ready guard")) return
                mail.ready = true
                mail.readMessage("same")
                test.phase++
            } else if (test.phase === 1 && mail.message && !mail.reading) {
                test.requests = mail.listRequest
                if (!test.check(mail.deleteMessage("same") && mail.deleting, "request latched")) return
                if (!test.check(!mail.deleteMessage("same") && !mail.deleteMessage("fail"), "duplicate guard")) return
                mail.refresh(); mail.nextPage(); mail.readMessage("fail"); mail.setRead("fail", true); mail.saveAttachment("a", false)
                if (!test.check(!mail.selectFolder("") && !mail.selectFolderRole("trash") && !mail.moveMessage("fail", "Trash")
                    && mail.listRequest === test.requests && !mail.reading && !mail.marking && !mail.savingAttachment, "concurrent actions guarded")) return
                test.phase++
            } else if (test.phase === 2 && !mail.deleting && !mail.loading && test.has("fill")) {
                if (!test.check(!test.has("same") && mail.selectedId === "" && mail.message === null && !mail.actionError, "success clears reader and refills")) return
                mail.readMessage("fail")
                test.phase++
            } else if (test.phase === 3 && mail.message && !mail.reading) {
                mail.deleteMessage("fail")
                test.phase++
            } else if (test.phase === 4 && !mail.deleting) {
                if (!test.check(test.has("fail") && mail.message.id === "fail" && mail.actionError === "Offline delete failed", "error preserves reader/row")) return
                mail.deleteMessage("bad")
                test.phase++
            } else if (test.phase === 5 && !mail.deleting) {
                if (!test.check(test.has("bad") && mail.message.id === "fail" && mail.actionError.indexOf("Invalid delete") >= 0, "invalid response")) return
                mail.deleteMessage("fill")
                test.phase++
            } else if (test.phase === 6 && !mail.deleting && !mail.loading) {
                if (!test.check(mail.message.id === "fail", "unrelated reader preserved")) return
                mail.deleteMessage("fail")
                mail.account = "second"
                test.phase++
            } else if (test.phase === 7 && !mail.deleting && !mail.loading && test.has("same")) {
                if (!test.check(!mail.actionError && mail.messages[0].subject === "second", "stale error discarded")) return
                mail.folders = [{id: "Exact / Folder", name: "Exact"}]
                mail.selectFolder("Exact / Folder")
                test.phase++
            } else if (test.phase === 8 && !mail.loading && test.has("same")) {
                mail.deleteMessage("same")
                mail.account = "third"
                test.phase++
            } else if (test.phase === 9 && !mail.deleting && !mail.loading && test.has("same")) {
                if (!test.check(mail.messages[0].subject === "third" && !mail.actionError, "stale success discarded")) return
                mail.nextPage()
                test.phase++
            } else if (test.phase === 10 && !mail.loading && mail.page === 2) {
                mail.deleteMessage("same")
                test.phase++
            } else if (test.phase === 11 && !mail.deleting && !mail.loading) {
                if (!test.check(mail.page === 1 && mail.messages.length === 4, "empty last page falls back")) return
                mail.account = ""
                test.phase++
            } else if (test.phase === 12 && !mail.loading && test.has("same")) {
                if (!test.check(!mail.deleteMessage("same") && mail.actionError.indexOf("explicit account") >= 0, "explicit account required")) return
                mail.account = "launch-test"
                test.phase++
            } else if (test.phase === 13 && !mail.loading && test.has("same")) {
                mail.deleteMessage("launch")
                test.phase++
            } else if (test.phase === 14 && !mail.deleting) {
                if (!test.check(mail.actionError === "Launch failure armed", "arm failed launch")) return
                mail.deleteMessage("same")
                test.phase++
            } else if (test.phase === 15 && !mail.deleting) {
                if (!test.check(test.has("same") && mail.actionError.indexOf("Could not launch Python") >= 0, "launch failure releases latch")) return
                mail.active = false
                if (!test.check(!mail.deleteMessage("same"), "inactive guard")) return
                console.log("JITSMAIL_DELETIONS_OK")
                Qt.quit()
            }
        }
    }
}
