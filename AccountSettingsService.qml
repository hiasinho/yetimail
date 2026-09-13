import QtQuick
import Quickshell.Io

// Internal owner for account overview, private labels, and configuration saves.
// MailService exposes this object's stable API without sharing mailbox state.
Item {
    id: root

    signal accountConfigSaved(string transaction)
    signal accountConfigSaveFailed(string transaction)
    signal accountConfigFenceExpired(string transaction)
    signal mailboxResetRequested(bool clearFolderCache, bool deferFetch)
    signal mailboxResumeRequested()

    property bool active: true
    property string config: ""
    property bool demo: false
    property url helperUrl
    property bool ready: false

    property var accountLabels: ({})
    property var accountOverview: []
    readonly property string defaultAccountId: {
        var defaults = accountOverview.filter(function(item) { return item && item.default === true && item.id })
        return defaults.length === 1 ? String(defaults[0].id) : ""
    }
    property bool accountOverviewLoading: false
    property string accountOverviewError: ""
    property int accountOverviewRequest: 0
    property string accountOverviewConfig: ""
    property bool accountOverviewDemo: false
    property bool accountLabelsLoading: false
    property bool accountLabelsReload: false
    property bool accountOverviewReload: false
    property bool accountOverviewEnabled: false
    property bool accountLabelSaving: false
    property bool accountConfigSaving: false
    property bool accountConfigRefreshPending: false
    property bool accountConfigBlocked: false
    property string accountConfigFenceToken: ""
    property int accountConfigRequest: 0
    property string accountConfigId: ""
    property int accountLabelsRequest: 0
    property string accountLabelId: ""

    function result(text, code) {
        try {
            var data = JSON.parse(text)
            if (data.error) throw new Error(data.error)
            if (code !== 0) throw new Error("Mail helper failed (exit " + code + ").")
            return data
        } catch (e) {
            throw new Error(text.trim() ? e.message : "Mail helper could not run. Check Python 3 and Himalaya 2.1 are installed.")
        }
    }

    function command(operation) {
        var path = decodeURIComponent(helperUrl.toString().replace(/^file:\/\//, ""))
        var args = ["python3", path, operation]
        if (config && (operation === "accounts" || operation === "account-save")) args.push("--config", config)
        if (demo) args.push("--demo")
        return args
    }

    function withAccountLabel(source, accountId, label) {
        var entries = []
        Object.keys(source || ({})).forEach(function(id) {
            if (id !== accountId) entries.push(JSON.stringify(id) + ":" + JSON.stringify(String(source[id])))
        })
        if (label) entries.push(JSON.stringify(accountId) + ":" + JSON.stringify(label))
        return JSON.parse("{" + entries.join(",") + "}")
    }

    function applyAccountOverview(data) {
        if (!data || !Array.isArray(data.accounts)) throw new Error("Invalid account overview from mail helper.")
        var labels = JSON.parse(JSON.stringify(accountLabels || ({})))
        var roles = ["inbox", "sent", "drafts", "trash", "archive"]
        data.accounts.forEach(function(item) {
            if (!item || typeof item.id !== "string" || !item.id || typeof item.label !== "string"
                || typeof item.email !== "string" || typeof item["display-name"] !== "string"
                || typeof item.default !== "boolean" || !Array.isArray(item.receiving) || !Array.isArray(item.sending)
                || item.receiving.some(function(value) { return typeof value !== "string" })
                || item.sending.some(function(value) { return typeof value !== "string" })
                || typeof item.revision !== "string"
                || (item.editable === true && !/^[0-9a-f]{64}$/.test(item.revision))
                || (item.editable === false && item.revision !== "")
                || typeof item.editable !== "boolean" || typeof item["editable-reason"] !== "string"
                || !item["mailbox-mappings"] || typeof item["mailbox-mappings"] !== "object"
                || Array.isArray(item["mailbox-mappings"])
                || roles.some(function(role) { return typeof item["mailbox-mappings"][role] !== "string" }))
                throw new Error("Invalid account overview from mail helper.")
            labels = withAccountLabel(labels, item.id, item.label)
        })
        accountLabels = labels
        accountOverview = data.accounts
    }

    function loadAccountLabels() {
        if (!ready || !active) return
        if (accountLabelsLoading || accountLabelSaving || accountLabelsProcess.running) {
            accountLabelsReload = true
            return
        }
        accountLabelsReload = false
        accountLabelsLoading = true
        accountLabelsProcess.request = ++accountLabelsRequest
        accountLabelsProcess.contextDemo = demo
        accountLabelsProcess.command = command("account-labels")
        accountLabelsProcess.running = true
    }

    function loadAccountOverview() {
        accountOverviewEnabled = true
        if (!ready || !active) return
        if (accountOverviewLoading || accountLabelSaving || accountConfigSaving || accountOverviewProcess.running) {
            accountOverviewReload = true
            return
        }
        accountOverviewReload = false
        accountOverviewError = ""
        accountOverviewLoading = true
        accountOverviewConfig = config
        accountOverviewDemo = demo
        accountOverviewProcess.request = ++accountOverviewRequest
        accountOverviewProcess.contextConfig = config
        accountOverviewProcess.contextDemo = demo
        accountOverviewProcess.command = command("accounts")
        accountOverviewProcess.running = true
    }

    function saveAccountLabel(accountId, label) {
        if (!ready || !active || accountOverviewLoading || accountLabelSaving || accountConfigSaving || accountLabelProcess.running
            || typeof accountId !== "string" || !accountId || typeof label !== "string") return false
        accountOverviewError = ""
        accountLabelsLoading = false
        accountLabelSaving = true
        accountLabelId = accountId
        accountLabelProcess.request = ++accountLabelsRequest
        accountLabelProcess.contextDemo = demo
        accountLabelProcess.command = command("account-label").concat(["--account=" + accountId, "--label=" + label])
        accountLabelProcess.running = true
        return true
    }

    function saveAccountConfig(transaction, accountId, revision, email, displayName, makeDefault, inbox, sent, drafts, trash, archive) {
        if (!ready || !active || accountOverviewLoading || accountLabelSaving || accountConfigSaving
            || accountConfigProcess.running || typeof transaction !== "string" || !transaction
            || transaction !== accountConfigFenceToken || typeof accountId !== "string" || !accountId
            || typeof revision !== "string" || !/^[0-9a-f]{64}$/.test(revision)) return false
        var accountData = accountOverview.find(function(item) { return item && item.id === accountId })
        if (!accountData || accountData.editable !== true) return false
        accountOverviewError = ""
        accountConfigSaving = true
        accountConfigId = accountId
        accountConfigProcess.request = ++accountConfigRequest
        accountConfigProcess.transaction = transaction
        accountConfigProcess.contextConfig = config
        accountConfigProcess.contextDemo = demo
        accountConfigProcess.command = command("account-save").concat([
            "--account=" + accountId, "--revision=" + revision,
            "--email=" + String(email), "--display-name=" + String(displayName),
            "--default=" + String(!!accountData.default || !!makeDefault),
            "--inbox=" + String(inbox), "--sent=" + String(sent),
            "--drafts=" + String(drafts), "--trash=" + String(trash),
            "--archive=" + String(archive)
        ])
        accountConfigProcess.running = true
        return true
    }

    function prepareAccountConfigSave(transaction) {
        if (typeof transaction !== "string" || !transaction) return false
        accountConfigFenceToken = transaction
        accountConfigBlocked = true
        accountConfigRefreshPending = true
        accountConfigFenceTimer.restart()
        mailboxResetRequested(true, true)
        return true
    }

    function renewAccountConfigFence(transaction) {
        if (transaction && transaction === accountConfigFenceToken && accountConfigBlocked)
            accountConfigFenceTimer.restart()
    }

    function commitAccountConfigSave(transaction, deferFetch) {
        if (!transaction || transaction !== accountConfigFenceToken) return
        accountConfigFenceTimer.stop()
        accountConfigFenceToken = ""
        accountConfigBlocked = false
        accountConfigRefreshPending = !!deferFetch
        mailboxResetRequested(true, !!deferFetch)
    }

    function cancelAccountConfigSave(transaction) {
        if (!transaction || transaction !== accountConfigFenceToken) return
        accountConfigFenceTimer.stop()
        accountConfigFenceToken = ""
        accountConfigBlocked = false
        resumeAccountConfig()
    }

    function resumeAccountConfig() {
        if (accountConfigBlocked || !accountConfigRefreshPending) return
        accountConfigRefreshPending = false
        mailboxResumeRequested()
    }

    function clearFenceContext() {
        accountConfigFenceTimer.stop()
        accountConfigFenceToken = ""
        accountConfigBlocked = false
        accountConfigRefreshPending = false
    }

    onConfigChanged: {
        accountOverviewRequest++
        accountConfigRequest++
        accountOverview = []
        accountOverviewLoading = false
        accountConfigSaving = false
        clearFenceContext()
        accountOverviewError = ""
        if (active && accountOverviewEnabled) Qt.callLater(loadAccountOverview)
    }

    onDemoChanged: {
        accountOverviewRequest++
        accountLabelsRequest++
        accountConfigRequest++
        accountOverview = []
        accountLabels = ({})
        accountOverviewLoading = false
        accountLabelsLoading = false
        accountLabelSaving = false
        accountConfigSaving = false
        clearFenceContext()
        accountOverviewError = ""
        if (active) {
            Qt.callLater(loadAccountLabels)
            if (accountOverviewEnabled) Qt.callLater(loadAccountOverview)
        }
    }

    Timer {
        id: accountConfigFenceTimer
        interval: 30000
        onTriggered: root.accountConfigFenceExpired(root.accountConfigFenceToken)
    }

    Process {
        id: accountLabelsProcess
        property int request: 0
        property bool contextDemo: false
        stdout: StdioCollector { id: accountLabelsOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = accountLabelsProcess.request
            Qt.callLater(function() {
                if (request !== root.accountLabelsRequest || !root.accountLabelsLoading || accountLabelsProcess.running) return
                root.accountLabelsLoading = false
                if (root.accountLabelsReload) {
                    root.accountLabelsReload = false
                    Qt.callLater(root.loadAccountLabels)
                }
            })
        }
        onExited: function(code, status) {
            var request = accountLabelsProcess.request
            root.accountLabelsLoading = false
            var reload = root.accountLabelsReload
            root.accountLabelsReload = false
            if (request !== root.accountLabelsRequest || accountLabelsProcess.contextDemo !== root.demo) {
                if (reload) Qt.callLater(root.loadAccountLabels)
                return
            }
            try {
                var data = root.result(accountLabelsOutput.text, code)
                if (!data || !data.labels || typeof data.labels !== "object" || Array.isArray(data.labels))
                    throw new Error("Invalid account labels from mail helper.")
                Object.keys(data.labels).forEach(function(id) {
                    if (!id || typeof data.labels[id] !== "string" || !data.labels[id] || data.labels[id].length > 80)
                        throw new Error("Invalid account labels from mail helper.")
                })
                root.accountLabels = data.labels
            } catch (e) { /* Labels are optional; account IDs remain available. */ }
            if (reload) Qt.callLater(root.loadAccountLabels)
        }
    }

    Process {
        id: accountOverviewProcess
        property int request: 0
        property string contextConfig: ""
        property bool contextDemo: false
        stdout: StdioCollector { id: accountOverviewOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = accountOverviewProcess.request
            Qt.callLater(function() {
                if (request !== root.accountOverviewRequest || !root.accountOverviewLoading || accountOverviewProcess.running) return
                root.accountOverviewLoading = false
                if (root.accountOverviewConfig === root.config && root.accountOverviewDemo === root.demo)
                    root.accountOverviewError = "Could not launch Python 3 to read account settings."
                if (root.accountOverviewReload) {
                    root.accountOverviewReload = false
                    Qt.callLater(root.loadAccountOverview)
                }
            })
        }
        onExited: function(code, status) {
            var request = accountOverviewProcess.request
            root.accountOverviewLoading = false
            var reload = root.accountOverviewReload
            root.accountOverviewReload = false
            if (request !== root.accountOverviewRequest || accountOverviewProcess.contextConfig !== root.config
                || accountOverviewProcess.contextDemo !== root.demo) {
                if (reload) Qt.callLater(root.loadAccountOverview)
                return
            }
            try {
                root.applyAccountOverview(root.result(accountOverviewOutput.text, code))
            } catch (e) { root.accountOverviewError = e.message }
            if (reload) Qt.callLater(root.loadAccountOverview)
        }
    }

    Process {
        id: accountLabelProcess
        property int request: 0
        property bool contextDemo: false
        stdout: StdioCollector { id: accountLabelOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = accountLabelProcess.request
            Qt.callLater(function() {
                if (request !== root.accountLabelsRequest || !root.accountLabelSaving || accountLabelProcess.running) return
                root.accountLabelSaving = false
                root.accountOverviewError = "Could not launch Python 3 to save the account label."
                if (root.accountLabelsReload) {
                    root.accountLabelsReload = false
                    Qt.callLater(root.loadAccountLabels)
                }
                if (root.accountOverviewReload) {
                    root.accountOverviewReload = false
                    Qt.callLater(root.loadAccountOverview)
                }
            })
        }
        onExited: function(code, status) {
            var request = accountLabelProcess.request
            root.accountLabelSaving = false
            if (request !== root.accountLabelsRequest || accountLabelProcess.contextDemo !== root.demo) {
                if (root.accountLabelsReload) {
                    root.accountLabelsReload = false
                    Qt.callLater(root.loadAccountLabels)
                }
                if (root.accountOverviewReload) {
                    root.accountOverviewReload = false
                    Qt.callLater(root.loadAccountOverview)
                }
                return
            }
            try {
                var data = root.result(accountLabelOutput.text, code)
                if (!data || data.id !== root.accountLabelId || typeof data.label !== "string" || data.label.length > 80)
                    throw new Error("Invalid account label response from mail helper.")
                root.accountLabels = root.withAccountLabel(root.accountLabels, data.id, data.label)
                root.accountOverview = root.accountOverview.map(function(item) {
                    if (item.id !== data.id) return item
                    var updated = Object.assign({}, item)
                    updated.label = data.label
                    return updated
                })
            } catch (e) { root.accountOverviewError = e.message }
            if (root.accountLabelsReload) {
                root.accountLabelsReload = false
                Qt.callLater(root.loadAccountLabels)
            }
            if (root.accountOverviewReload) {
                root.accountOverviewReload = false
                Qt.callLater(root.loadAccountOverview)
            }
        }
    }

    Process {
        id: accountConfigProcess
        property int request: 0
        property string transaction: ""
        property string contextConfig: ""
        property bool contextDemo: false
        stdout: StdioCollector { id: accountConfigOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = accountConfigProcess.request
            Qt.callLater(function() {
                if (request !== root.accountConfigRequest || !root.accountConfigSaving || accountConfigProcess.running) return
                root.accountConfigSaving = false
                if (accountConfigProcess.contextConfig === root.config && accountConfigProcess.contextDemo === root.demo) {
                    root.accountOverviewError = "Could not launch Python 3 to save account configuration."
                    root.accountConfigSaveFailed(accountConfigProcess.transaction)
                }
            })
        }
        onExited: function(code, status) {
            var request = accountConfigProcess.request
            root.accountConfigSaving = false
            if (request !== root.accountConfigRequest || accountConfigProcess.contextConfig !== root.config
                || accountConfigProcess.contextDemo !== root.demo) {
                root.accountConfigSaveFailed(accountConfigProcess.transaction)
                return
            }
            try {
                var data = root.result(accountConfigOutput.text, code)
                if (!data || !Array.isArray(data.accounts)
                    || !data.accounts.some(function(item) { return item && item.id === root.accountConfigId }))
                    throw new Error("Invalid account configuration response from mail helper.")
                root.applyAccountOverview(data)
                root.accountConfigSaved(accountConfigProcess.transaction)
            } catch (e) {
                root.accountOverviewError = e.message
                root.accountConfigSaveFailed(accountConfigProcess.transaction)
            }
        }
    }
}
