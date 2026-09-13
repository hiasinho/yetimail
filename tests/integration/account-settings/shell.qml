import QtQuick
import Quickshell
import "Yetimail"

ShellRoot {
    id: test
    property string scenario: Quickshell.env("YETIMAIL_SCENARIO")
    property int phase: 0
    property int ticks: 0
    property bool failed: false
    property bool saveFailed: false

    function fail(reason) {
        failed = true
        console.error("ACCOUNT_SETTINGS_FAIL " + scenario + ": " + reason)
        Qt.quit()
    }
    function check(ok, reason) { if (!ok) fail(reason); return ok }
    function pass() { if (!failed) console.log("ACCOUNT_SETTINGS_OK " + scenario); Qt.quit() }

    MailService {
        id: service
        active: false
        onAccountConfigSaveFailed: function(transaction) {
            if (transaction === "stale-save") test.saveFailed = true
        }
    }

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            test.ticks++
            if (test.failed) return
            if (test.ticks > 350) { test.fail("timeout at phase " + test.phase); return }

            if (test.scenario === "missing") {
                if (test.phase === 0) {
                    service.active = true
                    service.loadAccountOverview()
                    test.phase = 1
                } else if (service.accountOverviewError) {
                    if (!test.check(!service.accountOverviewLoading, "failed launch retained overview latch")) return
                    test.pass()
                }
                return
            }

            if (test.phase === 0) {
                service.config = "/old.toml"
                service.active = true
                service.loadAccountOverview()
                if (!test.check(service.accountOverviewLoading, "overview latch was not synchronous")) return
                service.config = "/new.toml"
                test.phase = 1
            } else if (test.phase === 1 && !service.accountOverviewLoading && service.accountOverview.length) {
                if (!test.check(service.accountOverview[0].id === "new", "stale overview survived config change")) return
                service.loadAccountLabels()
                if (!test.check(service.accountLabelsLoading, "labels latch was not synchronous")) return
                service.demo = true
                test.phase = 2
            } else if (test.phase === 2 && !service.accountLabelsLoading
                       && service.accountLabels.fixture === "demo-label" && !service.accountOverviewLoading) {
                if (!test.check(service.accountOverview[0].id === "new", "demo reload changed overview context")) return
                if (!test.check(service.saveAccountLabel("new", "stale-label"), "label save was rejected")) return
                service.demo = false
                test.phase = 3
            } else if (test.phase === 3 && !service.accountLabelSaving && !service.accountLabelsLoading
                       && !service.accountOverviewLoading && service.accountLabels.fixture === "real-label") {
                if (!test.check(service.accountOverview[0].label !== "stale-label", "stale label save was applied")) return
                if (!test.check(service.prepareAccountConfigSave("stale-save"), "config fence was rejected")) return
                if (!test.check(service.saveAccountConfig("stale-save", "new",
                    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "new@example.invalid", "New", false, "INBOX", "Sent", "Drafts", "Trash", "Archive"),
                    "config save was rejected")) return
                service.config = "/changed.toml"
                test.phase = 4
            } else if (test.phase === 4 && test.saveFailed && !service.accountConfigSaving
                       && !service.accountOverviewLoading && service.accountOverview.length) {
                if (!test.check(service.accountOverview[0].id === "changed", "stale config save replaced new overview")) return
                if (!test.check(!service.accountConfigBlocked && service.accountConfigFenceToken === "",
                                "config change retained transaction fence")) return
                test.pass()
            }
        }
    }
}
