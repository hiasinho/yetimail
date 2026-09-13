import QtQuick
import Quickshell
ShellRoot {
    id: test
    property int phase: 0
    property int ticks: 0
    property var opens: []
    property bool failed: false
    property var originalLaunch
    property double viewerStarted: 0
    Component.onCompleted: {
        originalLaunch = mail.launchAttachment
        mail.launchAttachment = function(path) { test.opens = test.opens.concat([path]) }
    }
    function check(ok, reason) {
        if (!ok) { failed = true; console.error("ATTACHMENTS_FAIL phase " + phase + ": " + reason); Qt.quit() }
        return ok
    }
    MailService {
        id: mail
        account: "alpha"
    }
    Timer {
        interval: 25; running: true; repeat: true
        onTriggered: {
            if (test.failed) return
            if (++test.ticks > 2200) { test.check(false, "timeout"); return }
            if (mail.loading || mail.reading || mail.savingAttachment || mail.openingAttachment) return
            switch (test.phase) {
            case 0:
                if (!mail.messages.length) return
                mail.readMessage("shared"); break
            case 1:
                if (!test.check(mail.message && test.opens.length === 0, "read must not open")) return
                mail.saveAttachment("blocked", true)
                if (!test.check(!mail.savingAttachment && mail.actionError, "save-only guard")) return
                mail.saveAttachment("fixture", false)
                var request = mail.attachmentRequest
                mail.saveAttachment("fixture", true)
                if (!test.check(mail.attachmentRequest === request, "duplicate action guard")) return
                break
            case 2:
                if (!test.check(mail.attachmentStatus.indexOf("Saved:") === 0 && test.opens.length === 0, "save only")) return
                mail.saveAttachment("fixture", true); break
            case 3:
                if (!test.check(test.opens.length === 1 && test.opens[0] === "/tmp/attachment with spaces.txt", "explicit open")) return
                mail.saveAttachment("fixture", true)
                mail.account = "beta"; break
            case 4:
                if (!mail.messages.length) return
                if (!test.check(test.opens.length === 1 && !mail.attachmentStatus && !mail.actionError, "stale account result")) return
                mail.readMessage("shared"); break
            case 5:
                mail.saveAttachment("fixture", true)
                mail.readMessage("other"); break
            case 6:
                if (!test.check(test.opens.length === 1 && !mail.attachmentStatus && mail.selectedId === "other", "stale message result")) return
                mail.saveAttachment("fixture", true)
                mail.readMessage("other"); break
            case 7:
                if (!test.check(test.opens.length === 1 && !mail.attachmentStatus, "same-ID reread invalidates pending open")) return
                mail.saveAttachment("fixture", true)
                mail.cancelAttachmentOpen(); break
            case 8:
                if (!test.check(test.opens.length === 1 && mail.attachmentStatus, "close cancels open but preserves save")) return
                mail.saveAttachment("fail", true); break
            case 9:
                if (!test.check(mail.actionError === "fixture save failure" && test.opens.length === 1, "save failure")) return
                mail.saveAttachment("invalid", true); break
            case 10:
                if (!test.check(mail.actionError.indexOf("Invalid attachment") === 0 && test.opens.length === 1, "mismatched response")) return
                mail.demo = true; break
            case 11:
                if (!mail.messages.length) return
                mail.readMessage("shared"); break
            case 12:
                mail.saveAttachment("fixture", true); break
            case 13:
                if (!test.check(test.opens.length === 1 && mail.attachmentStatus.indexOf("opening suppressed") !== -1, "demo cannot open")) return
                mail.demo = false; break
            case 14:
                if (!mail.messages.length) return
                mail.readMessage("shared"); break
            case 15:
                mail.launchAttachment = test.originalLaunch
                mail.saveAttachment("fixture", true); break
            case 16:
                if (mail.attachmentOpeners.length) return
                if (!test.check(mail.actionError === "Saved, but xdg-open could not open the file.", "opener failure is visible")) return
                mail.saveAttachment("linger", true); break
            case 17:
                if (!test.check(mail.attachmentOpeners.length === 1 && !mail.openingAttachment, "started viewer releases launch latch")) return
                test.viewerStarted = Date.now()
                mail.saveAttachment("linger", true); break
            case 18:
                if (!test.check(mail.attachmentOpeners.length === 2 && !mail.actionError, "two independent viewers remain alive")) return
                mail.saveAttachment("fixture", false); break
            case 19:
                if (!test.check(mail.attachmentStatus.indexOf("Saved:") === 0 && !mail.actionError, "saving allowed while viewers live")) return
                // Both earlier errors must remain unrelated to this new save,
                // even before account/message context also changes.
                if (Date.now() - test.viewerStarted < 33000) return
                if (!test.check(mail.attachmentOpeners.length === 0 && !mail.actionError, "viewer lifetime has no timeout and stale request errors are ignored")) return
                mail.saveAttachment("linger", true); break
            case 20:
                if (!test.check(mail.attachmentOpeners.length === 1, "context test viewer launched")) return
                mail.account = "final"; break
            case 21:
                if (!mail.messages.length) return
                mail.readMessage("other"); break
            case 22:
                // End only this mock early to test stale account/message errors.
                if (mail.attachmentOpeners.length) {
                    mail.attachmentOpeners[0].signal(15)
                    return
                }
                if (!test.check(!mail.actionError, "old viewer error cannot attach to new account/message")) return
                mail.saveAttachment("missing", true); break
            case 23:
                if (!test.check(!mail.attachmentOpeners.length && mail.actionError === "Saved, but could not launch xdg-open.", "failed launch releases latch and reports error")) return
                mail.saveAttachment("fixture", false); break
            case 24:
                if (!test.check(!mail.actionError && mail.attachmentStatus.indexOf("Saved:") === 0, "save works after launch failure")) return
                console.log("YETIMAIL_ATTACHMENTS_OK"); Qt.quit(); return
            }
            test.phase++
        }
    }
}
