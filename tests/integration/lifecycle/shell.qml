import QtQuick
import Quickshell
import "Yetimail"
ShellRoot {
    id: test
    property string scenario: Quickshell.env("YETIMAIL_SCENARIO")
    property int phase: 0
    property int ticks: 0
    property bool failed: false
    property var widget: null
    property var widgetMail: null
    function fail(reason) {
        failed = true
        console.error("LIFECYCLE_FAIL " + scenario + ": " + reason)
        Qt.quit()
    }
    function check(ok, reason) { if (!ok) fail(reason); return ok }
    function pass() { if (!failed) console.log("LIFECYCLE_OK " + scenario); Qt.quit() }
    Component { id: widgetFactory; Widget {} }
    FloatingWindow { id: window; visible: true; implicitWidth: 1000; implicitHeight: 700 }
    MailService {
        id: service
        active: false
        onMessagesChanged: {
            if (test.scenario === "race" && messages.length && messages[0].id !== account + "/" + config)
                test.fail("accepted stale list: " + messages[0].id)
        }
        onMessageChanged: {
            if (test.scenario === "race" && message && message.id !== "fresh")
                test.fail("accepted stale read: " + message.id)
        }
    }
    Component.onCompleted: {
        if (scenario === "widget" || scenario === "accounts") {
            widget = widgetFactory.createObject(window.contentItem)
            if (!check(widget !== null, "could not construct Widget")) return
            // MailService is a direct visual child; no production-only test API needed.
            for (var i = 0; i < widget.children.length; i++) {
                var child = widget.children[i]
                if (typeof child.readMessage === "function") widgetMail = child
            }
            check(widgetMail !== null, "could not find Widget MailService")
        }
    }
    Timer {
        interval: 25; repeat: true; running: true
        onTriggered: {
            test.ticks++
            if (test.failed) return
            if (test.ticks > 200) { test.fail("timeout at phase " + test.phase); return }
            if (test.scenario === "widget") {
                if (test.phase === 0) {
                    if (!test.check(!test.widgetMail.loading && !test.widgetMail.messages.length && !test.widgetMail.listError,
                                    "launched before host settings injection")) return
                    if (test.ticks < 12) return
                    console.log("LIFECYCLE_INJECT_SETTINGS")
                    test.widget.settings = {demo: true, account: "widget", config: "widget-config"}
                    test.phase = 1
                } else if (test.widgetMail.messages.length) {
                    if (!test.check(test.widgetMail.demo && test.widgetMail.messages[0].id === "widget/widget-config", "injected demo settings ignored")) return
                    test.pass()
                }
                return
            }
            if (test.scenario === "accounts") {
                if (test.phase === 0) {
                    if (!test.check(!test.widgetMail.loading && !test.widgetMail.messages.length && !test.widgetMail.listError,
                                    "launched before account settings injection")) return
                    if (test.ticks < 12) return
                    test.widget.settings = {demo: true, accounts: "personal,work", account: "gmail", config: "accounts-config"}
                    if (!test.check(test.widget.currentAccount === "personal" && test.widgetMail.account === "personal",
                                    "invalid preferred account did not fall back to first allowed account")) return
                    test.phase = 1
                } else if (test.phase === 1 && test.widgetMail.messages.length && !test.widgetMail.loading) {
                    if (!test.check(test.widgetMail.messages[0].id === "personal/accounts-config",
                                    "fallback inbox used wrong account")) return
                    test.widgetMail.readMessage(test.widgetMail.messages[0].id)
                    test.phase = 2
                } else if (test.phase === 2 && test.widgetMail.message && !test.widgetMail.reading) {
                    if (!test.check(test.widgetMail.message.id === "personal/accounts-config",
                                    "could not populate old account reader")) return
                    test.widget.selectAccount("work")
                    if (!test.check(test.widget.currentAccount === "work" && test.widgetMail.account === "work",
                                    "allowed account switch did not reach MailService")) return
                    if (!test.check(test.widgetMail.message === null && test.widgetMail.selectedId === "" && !test.widgetMail.messages.length,
                                    "account switch retained stale reader or inbox")) return
                    test.phase = 3
                } else if (test.phase === 3 && test.widgetMail.messages.length && !test.widgetMail.loading) {
                    if (!test.check(test.widgetMail.messages[0].id === "work/accounts-config" && test.widgetMail.message === null,
                                    "switched account retained stale results")) return
                    test.widget.selectAccount("gmail")
                    if (!test.check(test.widget.currentAccount === "work" && test.widgetMail.account === "work" &&
                                    test.widgetMail.messages.length && test.widgetMail.messages[0].id === "work/accounts-config",
                                    "outside account accepted or rejection reset inbox")) return
                    test.ticks = 0
                    test.phase = 4
                } else if (test.phase === 4 && test.ticks >= 20) {
                    // Give any incorrectly queued refresh time to reach the fixture log.
                    if (!test.check(test.widget.currentAccount === "work" && test.widgetMail.account === "work" &&
                                    !test.widgetMail.loading && !test.widgetMail.listError && !test.widgetMail.readError &&
                                    test.widgetMail.message === null && test.widgetMail.selectedId === "",
                                    "rejection changed account or left stale reader/errors")) return
                    test.pass()
                }
                return
            }
            if (test.scenario === "missing" || test.scenario === "unlaunchable") {
                if (test.phase === 0) {
                    service.active = true
                    service.refresh()
                    service.readMessage("missing")
                    test.phase = 1
                } else if (service.listError && service.readError) {
                    if (!test.check(!service.loading && !service.reading && !service.messages.length && !service.message,
                                    "failed launch left a latch or successful result")) return
                    console.log("LIFECYCLE_ERRORS list=" + service.listError + " read=" + service.readError)
                    test.pass()
                }
                return
            }
            if (test.phase === 0) {
                service.account = "old"
                service.config = "old-config"
                service.active = true
                service.refresh()
                if (!test.check(service.loading, "list loading latch not synchronous")) return
                service.account = "middle"
                service.config = "middle-config"
                service.refresh()
                test.phase = 1
            } else if (test.phase === 1) {
                // Also invalidate after Process has had a chance to start.
                service.account = "final"
                service.config = "final-config"
                service.refresh()
                test.phase = 2
            } else if (test.phase === 2 && service.messages.length && !service.loading) {
                service.readMessage("stale")
                if (!test.check(service.reading, "read latch not synchronous")) return
                service.readMessage("duplicate")
                service.config = "changed-for-read"
                test.phase = 3
            } else if (test.phase === 3 && !service.reading) {
                if (!test.check(service.message === null, "stale read survived reset")) return
                // Stop list refreshes before changing config back; stale in-flight
                // list output must also remain discarded while inactive.
                service.active = false
                service.config = "final-config"
                test.phase = 4
            } else if (test.phase === 4 && !service.loading) {
                service.active = true
                service.readMessage("fresh")
                test.phase = 5
            } else if (test.phase === 5 && service.message) {
                if (!test.check(!service.readError && !service.listError, "unexpected helper error")) return
                test.pass()
            }
        }
    }
}
