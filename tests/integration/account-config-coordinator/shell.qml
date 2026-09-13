import QtQuick
import Quickshell
import "Yetimail"

ShellRoot {
    id: test
    property bool failed: false

    function fail(reason) {
        failed = true
        console.error("ACCOUNT_CONFIG_COORDINATOR_FAIL: " + reason)
        Qt.quit()
    }
    function check(ok, reason) { if (!ok && !failed) fail(reason); return ok }
    function resetParticipant(participant) {
        participant.busy = false
        participant.rejectPrepare = false
        participant.saveAccepted = true
        participant.writerSaving = false
        participant.fenceToken = ""
        participant.prepares = 0
        participant.commits = 0
        participant.cancels = 0
        participant.renews = 0
        participant.saves = 0
    }
    function resetAll() {
        if (coordinator.active) coordinator.failed(coordinator.transaction)
        resetParticipant(first)
        resetParticipant(second)
        resetParticipant(third)
    }
    function verifyCount(propertyName, expected, reason) {
        return check(first[propertyName] === expected && second[propertyName] === expected
                     && third[propertyName] === expected, reason)
    }
    function run() {
        var participants = [first, second, third]

        resetAll()
        check(coordinator.start(participants, first, ({accountId: "alpha"})), "unanimous prepare was rejected")
        if (failed) return
        var committedToken = coordinator.transaction
        check(verifyCount("prepares", 1, "unanimous prepare did not reach every participant"), "")
        check(first.saves === 1 && coordinator.phase === "saving", "writer save did not start")
        coordinator.saved(committedToken)
        check(verifyCount("commits", 1, "commit did not release every prepared participant"), "")
        check(!coordinator.active, "commit retained active transaction")

        resetAll()
        second.busy = true
        check(!coordinator.start(participants, first, ({})), "busy participant allowed save")
        check(verifyCount("prepares", 0, "busy rejection prepared a participant"), "")
        check(first.saves === 0, "busy rejection started writer")

        resetAll()
        second.rejectPrepare = true
        check(!coordinator.start(participants, first, ({})), "partial prepare failure allowed save")
        check(first.prepares === 1 && first.cancels === 1, "partial prepare did not release first participant")
        check(second.prepares === 1 && second.cancels === 1 && third.prepares === 0,
              "partial prepare did not release the rejecting participant and stop")

        resetAll()
        check(coordinator.start(participants, first, ({})), "save-failure setup was rejected")
        var failedToken = coordinator.transaction
        coordinator.failed(failedToken)
        check(verifyCount("cancels", 1, "save failure did not release all participants"), "")
        check(!coordinator.active, "save failure retained transaction")

        resetAll()
        check(coordinator.start(participants, first, ({})), "expiry setup was rejected")
        var expiredToken = coordinator.transaction
        coordinator.fenceExpired(expiredToken)
        check(verifyCount("renews", 1, "live writer did not renew every fence"), "")
        first.writerSaving = false
        coordinator.fenceExpired(expiredToken)
        check(verifyCount("cancels", 1, "dead writer expiry did not release every fence"), "")
        check(!coordinator.active, "expiry retained transaction")

        resetAll()
        check(coordinator.start(participants, first, ({})), "orphan recovery setup was rejected")
        var orphanedToken = coordinator.transaction
        coordinator.clear() // Simulate destruction of the initiating widget/coordinator.
        coordinator.recoverOrphanedFence(orphanedToken, participants)
        check(verifyCount("cancels", 1, "orphaned coordinator did not release surviving fences"), "")

        resetAll()
        check(coordinator.start(participants, first, ({})), "obsolete-result setup was rejected")
        var obsoleteToken = coordinator.transaction
        coordinator.failed(obsoleteToken)
        check(coordinator.start(participants, first, ({})), "replacement transaction was rejected")
        var currentToken = coordinator.transaction
        check(currentToken !== obsoleteToken, "transaction token was reused")
        check(!coordinator.saved(obsoleteToken), "late result completed replacement transaction")
        check(coordinator.transaction === currentToken && verifyCount("commits", 0, "late result committed participants"),
              "late result changed replacement transaction")
        coordinator.failed(currentToken)

        resetAll()
        first.saveAccepted = false
        check(!coordinator.start(participants, first, ({})), "synchronous writer rejection was accepted")
        check(verifyCount("cancels", 1, "writer rejection did not release every participant"), "")

        if (!failed) console.log("ACCOUNT_CONFIG_COORDINATOR_OK")
        Qt.quit()
    }

    AccountConfigCoordinator { id: coordinator }

    QtObject {
        id: first
        property bool busy: false
        property bool rejectPrepare: false
        property bool saveAccepted: true
        property bool writerSaving: false
        property string fenceToken: ""
        property int prepares: 0
        property int commits: 0
        property int cancels: 0
        property int renews: 0
        property int saves: 0
        function canPrepareAccountConfig() { return !busy }
        function prepareAccountConfig(token) { prepares++; if (rejectPrepare) return false; fenceToken = token; return true }
        function commitAccountConfig(token) { if (token === fenceToken) { commits++; fenceToken = ""; writerSaving = false } }
        function cancelAccountConfig(token) { if (token === fenceToken) { cancels++; fenceToken = ""; writerSaving = false } }
        function renewAccountConfig(token) { if (token === fenceToken) renews++ }
        function isAccountConfigWriter(token) { return writerSaving && fenceToken === token }
        function startAccountConfigSave(token, request) { saves++; if (!saveAccepted) return false; writerSaving = true; return true }
    }
    QtObject {
        id: second
        property bool busy: false
        property bool rejectPrepare: false
        property bool saveAccepted: true
        property bool writerSaving: false
        property string fenceToken: ""
        property int prepares: 0
        property int commits: 0
        property int cancels: 0
        property int renews: 0
        property int saves: 0
        function canPrepareAccountConfig() { return !busy }
        function prepareAccountConfig(token) { prepares++; fenceToken = token; if (rejectPrepare) return false; return true }
        function commitAccountConfig(token) { if (token === fenceToken) { commits++; fenceToken = "" } }
        function cancelAccountConfig(token) { if (token === fenceToken) { cancels++; fenceToken = "" } }
        function renewAccountConfig(token) { if (token === fenceToken) renews++ }
        function isAccountConfigWriter(token) { return false }
        function startAccountConfigSave(token, request) { return false }
    }
    QtObject {
        id: third
        property bool busy: false
        property bool rejectPrepare: false
        property bool saveAccepted: true
        property bool writerSaving: false
        property string fenceToken: ""
        property int prepares: 0
        property int commits: 0
        property int cancels: 0
        property int renews: 0
        property int saves: 0
        function canPrepareAccountConfig() { return !busy }
        function prepareAccountConfig(token) { prepares++; if (rejectPrepare) return false; fenceToken = token; return true }
        function commitAccountConfig(token) { if (token === fenceToken) { commits++; fenceToken = "" } }
        function cancelAccountConfig(token) { if (token === fenceToken) { cancels++; fenceToken = "" } }
        function renewAccountConfig(token) { if (token === fenceToken) renews++ }
        function isAccountConfigWriter(token) { return false }
        function startAccountConfigSave(token, request) { return false }
    }

    Component.onCompleted: Qt.callLater(run)
}
