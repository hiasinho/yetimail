import QtQuick

// Coordinates one account-configuration save across narrow per-widget
// participant interfaces. Widget discovery remains with the shell host.
QtObject {
    id: root

    property string transaction: ""
    property string phase: "idle"
    property string lastError: ""
    property var transactionParticipants: []
    property var writerParticipant: null
    property int sequence: 0
    readonly property bool active: transaction !== ""

    function newTransaction() {
        sequence++
        return String(Date.now()) + "-" + String(sequence) + "-" + String(Math.random())
    }

    function validParticipant(participant) {
        return participant
            && typeof participant.canPrepareAccountConfig === "function"
            && typeof participant.prepareAccountConfig === "function"
            && typeof participant.commitAccountConfig === "function"
            && typeof participant.cancelAccountConfig === "function"
            && typeof participant.renewAccountConfig === "function"
    }

    function release(participants, method, token) {
        participants.forEach(function(participant) {
            try { participant[method](token) } catch (error) { /* Release every participant. */ }
        })
    }

    function clear() {
        transaction = ""
        phase = "idle"
        transactionParticipants = []
        writerParticipant = null
    }

    function reject(message, prepared, token) {
        release(prepared || [], "cancelAccountConfig", token || transaction)
        clear()
        lastError = message
        return false
    }

    function start(participants, writer, request) {
        lastError = ""
        if (active) {
            lastError = "An account configuration save is already in progress."
            return false
        }
        if (!Array.isArray(participants) || !participants.length || !validParticipant(writer)
            || typeof writer.startAccountConfigSave !== "function") {
            lastError = "Account configuration participants are unavailable."
            return false
        }
        for (var i = 0; i < participants.length; ++i) {
            var participant = participants[i]
            if (!validParticipant(participant)) {
                lastError = "Account configuration participants are unavailable."
                return false
            }
            try {
                if (!participant.canPrepareAccountConfig()) {
                    lastError = "Wait for mail actions on every display to finish before saving account settings."
                    return false
                }
            } catch (error) {
                lastError = "Account configuration participants are unavailable."
                return false
            }
        }

        var token = newTransaction()
        transaction = token
        phase = "preparing"
        writerParticipant = writer
        var prepared = []
        for (var j = 0; j < participants.length; ++j) {
            try {
                if (participants[j].prepareAccountConfig(token) !== true)
                    return reject("Could not prepare every display for the account configuration save.",
                                  prepared.concat([participants[j]]), token)
            } catch (error) {
                return reject("Could not prepare every display for the account configuration save.",
                              prepared.concat([participants[j]]), token)
            }
            prepared.push(participants[j])
        }
        transactionParticipants = prepared.slice()
        phase = "saving"
        var accepted = false
        try { accepted = writer.startAccountConfigSave(token, request) === true } catch (error) { accepted = false }
        if (!accepted && transaction === token)
            return reject("Could not start the account configuration save.", prepared, token)
        return accepted
    }

    function saved(token) {
        if (!active || token !== transaction) return false
        var participants = transactionParticipants.slice()
        clear()
        release(participants, "commitAccountConfig", token)
        return true
    }

    function failed(token) {
        if (!active || token !== transaction) return false
        var participants = transactionParticipants.slice()
        clear()
        release(participants, "cancelAccountConfig", token)
        return true
    }

    function fenceExpired(token) {
        if (!active || token !== transaction) return false
        var writerAlive = false
        try {
            writerAlive = writerParticipant
                && typeof writerParticipant.isAccountConfigWriter === "function"
                && writerParticipant.isAccountConfigWriter(token) === true
        } catch (error) { writerAlive = false }
        if (writerAlive) {
            release(transactionParticipants, "renewAccountConfig", token)
            return true
        }
        return failed(token)
    }

    // If the initiating widget disappeared, no surviving coordinator owns the
    // token. Token-aware participant cancellation prevents an old expiry from
    // disturbing a newer transaction while releasing every matching fence.
    function recoverOrphanedFence(token, participants) {
        if (typeof token !== "string" || !token || !Array.isArray(participants)) return false
        release(participants.filter(validParticipant), "cancelAccountConfig", token)
        return true
    }
}
