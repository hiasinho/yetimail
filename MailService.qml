import QtQuick
import Quickshell.Io

Item {
    id: root
    property bool active: true
    property string account: ""
    property string config: ""
    property bool demo: false
    // Folder navigation API: lazy loadFolders(); folders are {id,name,role?}.
    // selectFolder(id) / selectFolderRole(role) return true when accepted.
    // An empty id is Himalaya's configured Inbox alias. Role shortcuts may
    // defer until discovery finishes; unknown/ambiguous roles fail closed.
    property var folders: []
    property string folderId: ""
    property string folderName: "Inbox"
    property bool foldersLoading: false
    property string foldersError: ""
    property bool foldersLoaded: false
    property int foldersGeneration: 0
    property int foldersRequest: 0
    property int discoveryGeneration: 0
    property string pendingFolderRole: ""
    property bool foldersReload: false

    function loadFolders() {
        if (!ready || !active) return
        if (foldersLoading) {
            if (foldersGeneration !== discoveryGeneration) foldersReload = true
            return
        }
        foldersReload = false
        foldersError = ""
        foldersLoading = true
        foldersGeneration = discoveryGeneration
        foldersRequest++
        foldersProcess.command = command("folders")
        foldersProcess.running = true
    }

    function selectFolder(id) {
        if (!ready || !active || marking || savingAttachment || openingAttachment || typeof id !== "string") return false
        var folder = folders.find(function(f) { return f.id === id })
        if (id && !folder) { foldersError = "Folder is not available."; return false }
        pendingFolderRole = ""
        foldersError = ""
        if (id === folderId) return true
        folderId = id
        folderName = folder ? folder.name : "Inbox"
        resetMessages()
        return true
    }

    function retryPendingFolderRole() {
        if (!pendingFolderRole || !foldersLoaded || !ready || !active
            || marking || savingAttachment || openingAttachment) return
        var role = pendingFolderRole
        pendingFolderRole = ""
        selectFolderRole(role)
    }
    // Discovery may finish while an operation has latched. Retry next turn,
    // after exit handlers finish applying old-folder results or launching a viewer.
    onMarkingChanged: if (!marking) Qt.callLater(retryPendingFolderRole)
    onSavingAttachmentChanged: if (!savingAttachment) Qt.callLater(retryPendingFolderRole)
    onOpeningAttachmentChanged: if (!openingAttachment) Qt.callLater(retryPendingFolderRole)

    function selectFolderRole(role) {
        if (!ready || !active || marking || savingAttachment || openingAttachment
            || ["inbox", "sent", "archive", "trash"].indexOf(role) < 0) return false
        if (!foldersLoaded) {
            pendingFolderRole = role
            loadFolders()
            return true
        }
        var matches = folders.filter(function(f) { return f.role === role })
        if (!matches.length) {
            var names = {inbox: ["inbox"], sent: ["sent", "sent mail", "sent items", "sent messages"],
                         archive: ["archive", "archives"], trash: ["trash", "deleted items", "deleted messages"]}
            matches = folders.filter(function(f) { return !f.role && names[role].indexOf(f.name.toLowerCase()) >= 0 })
        }
        if (matches.length === 1) return selectFolder(matches[0].id)
        if (!matches.length && role === "inbox") return selectFolder("")
        foldersError = matches.length ? "More than one " + role + " folder is available. Choose a folder." : "No known " + role + " folder is available."
        return false
    }
    property var messages: []
    property var message: null
    property string selectedId: ""
    property string listError: ""
    property string readError: ""
    property string actionError: ""
    property bool savingAttachment: false
    property bool openingAttachment: false
    property string attachmentStatus: ""
    property int attachmentGeneration: 0
    property int attachmentReadRequest: 0
    property int attachmentRequest: 0
    property string attachmentMessageId: ""
    property string attachmentId: ""
    property bool attachmentOpen: false
    property int openerLaunch: 0
    property var attachmentOpeners: []
    // Injectable only for offline service tests. Each viewer owns its Process
    // until exit; only starting it (not its lifetime) latches the UI.
    property var launchAttachment: function(path) {
        openingAttachment = true
        var process = attachmentOpener.createObject(root, {
            command: ["xdg-open", path],
            launch: ++openerLaunch,
            request: attachmentRequest,
            contextGeneration: generation,
            contextReadRequest: readRequest,
            contextAccount: account,
            contextMessageId: selectedId
        })
        if (!process) {
            openingAttachment = false
            actionError = "Saved, but could not launch xdg-open."
            return
        }
        attachmentOpeners = attachmentOpeners.concat([process])
        process.running = true
    }

    function cancelAttachmentOpen() { attachmentOpen = false }
    function attachmentCurrent() {
        return active && attachmentGeneration === generation && attachmentReadRequest === readRequest
            && message && message.id === attachmentMessageId && selectedId === attachmentMessageId
    }
    function saveAttachment(id, openAfter) {
        if (!ready || !active || loading || reading || marking || savingAttachment || openingAttachment
            || !message || message.id !== selectedId || typeof id !== "string" || !id) return
        var attachment = (Array.isArray(message.attachments) ? message.attachments : []).find(function(a) { return a.id === id })
        if (!attachment) return
        actionError = ""
        attachmentStatus = ""
        if (openAfter && !attachment.openable) {
            actionError = "This attachment is save-only. Save it and inspect it manually."
            return
        }
        attachmentGeneration = generation
        attachmentReadRequest = readRequest
        attachmentMessageId = selectedId
        attachmentId = id
        attachmentOpen = !!openAfter
        savingAttachment = true
        attachmentRequest++
        attachmentProcess.command = command("save").concat(["--id", selectedId, "--attachment", id])
        attachmentProcess.running = true
    }
    property int page: 1
    property bool hasNext: false
    property bool marking: false
    property var demoSeen: ({})
    property string accountLabel: account || "Default account"
    // Quickshell's running flips only after launch, so latch requests ourselves.
    property bool loading: false
    property bool reading: false
    property bool ready: false
    Component.onCompleted: { ready = true; Qt.callLater(refresh) }
    property int generation: 0
    property int listGeneration: 0
    property int readGeneration: 0
    property int listRequest: 0
    property int readRequest: 0
    property int requestedPage: 1
    property int markGeneration: 0
    property int markRequest: 0
    property string markId: ""
    property bool markSeen: false
    readonly property int unread: messages.filter(function(m) { return m.unread }).length

    function command(operation) {
        var args = ["python3", decodeURIComponent(Qt.resolvedUrl("bin/jitsmail-helper").toString().replace(/^file:\/\//, "")), operation]
        if (account) args.push("--account", account)
        if (config) args.push("--config", config)
        if (demo) args.push("--demo")
        if (operation !== "folders" && folderId) args.push("--mailbox=" + folderId)
        return args
    }

    function reset() {
        discoveryGeneration++
        folders = []
        foldersLoaded = false
        foldersError = ""
        foldersReload = false
        pendingFolderRole = ""
        folderId = ""
        folderName = "Inbox"
        resetMessages()
    }

    function resetMessages() {
        generation++
        messages = []
        message = null
        selectedId = ""
        listError = ""
        readError = ""
        actionError = ""
        attachmentStatus = ""
        cancelAttachmentOpen()
        page = 1
        hasNext = false
        demoSeen = ({})
        accountLabel = account || "Default account"
        // In-flight results are discarded; refresh after they finish.
        Qt.callLater(refresh)
    }

    function refresh() { fetchPage(page) }

    function nextPage() {
        if (hasNext) fetchPage(page + 1)
    }

    function previousPage() {
        if (page > 1) fetchPage(page - 1)
    }

    function fetchPage(target) {
        if (!ready || !active || loading || marking || (reading && target !== page)) return
        if (target !== page) {
            selectedId = ""
            message = null
            readError = ""
        }
        listError = ""
        actionError = ""
        requestedPage = target
        listGeneration = generation
        loading = true
        listRequest++
        listProcess.command = command("list").concat(["--page", String(target)])
        listProcess.running = true
    }

    function setRead(id, seen) {
        if (!ready || !active || loading || reading || marking) return
        actionError = ""
        if (!account.trim() && !demo) {
            actionError = "Select an explicit account before changing read status."
            return
        }
        markId = String(id)
        if (!messages.some(function(m) { return m.id === markId })) {
            actionError = "Message is not on the current page."
            return
        }
        markSeen = !!seen
        markGeneration = generation
        marking = true
        markRequest++
        var args = command("mark")
        if (!account && demo) args.push("--account", "Demo")
        markProcess.command = args.concat(["--id", markId, markSeen ? "--seen" : "--unseen"])
        markProcess.running = true
    }

    function readMessage(id) {
        if (!active || reading || marking || (loading && requestedPage !== page)) return
        selectedId = String(id)
        attachmentStatus = ""
        cancelAttachmentOpen()
        message = null
        readError = ""
        readGeneration = generation
        reading = true
        readRequest++
        readProcess.command = command("read").concat(["--id", selectedId])
        readProcess.running = true
    }

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

    Process {
        id: attachmentProcess
        stdout: StdioCollector { id: attachmentOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.attachmentRequest
            Qt.callLater(function() {
                if (request !== root.attachmentRequest || !root.savingAttachment || attachmentProcess.running) return
                root.savingAttachment = false
                if (root.attachmentCurrent()) root.actionError = "Could not launch Python 3 to save attachment."
            })
        }
        onExited: function(code, status) {
            root.savingAttachment = false
            if (!root.attachmentCurrent()) return
            try {
                var data = root.result(attachmentOutput.text, code)
                if (data.id !== root.attachmentMessageId || data.attachment !== root.attachmentId
                    || typeof data.path !== "string" || data.path[0] !== "/" || /[\x00-\x1f]/.test(data.path)
                    || typeof data.openable !== "boolean")
                    throw new Error("Invalid attachment response from mail helper.")
                root.attachmentStatus = "Saved: " + data.path
                if (root.attachmentOpen) {
                    if (!data.openable) throw new Error("Saved, but this attachment is save-only.")
                    if (root.demo) root.attachmentStatus += " (demo: opening suppressed)"
                    else root.launchAttachment(data.path)
                }
            } catch (e) { root.actionError = e.message }
        }
    }
    Component {
        id: attachmentOpener
        Process {
            id: opener
            required property int launch
            required property int request
            required property int contextGeneration
            required property int contextReadRequest
            required property string contextAccount
            required property string contextMessageId
            property bool didStart: false
            property bool finished: false
            // Discard output without retaining viewer logs for its lifetime.
            stdout: SplitParser { onRead: function(data) {} }
            stderr: SplitParser { onRead: function(data) {} }
            function current() {
                return root.active && request === root.attachmentRequest
                    && contextGeneration === root.generation && contextAccount === root.account
                    && contextReadRequest === root.readRequest && contextMessageId === root.selectedId
                    && root.message && root.message.id === contextMessageId
            }
            function releaseLatch() {
                if (launch === root.openerLaunch) root.openingAttachment = false
            }
            function finish(error) {
                if (finished) return
                finished = true
                releaseLatch()
                if (error && current()) root.actionError = error
                root.attachmentOpeners = root.attachmentOpeners.filter(function(item) { return item !== opener })
                destroy()
            }
            onStarted: { didStart = true; releaseLatch() }
            onRunningChanged: {
                if (running || didStart || finished) return
                Qt.callLater(function() {
                    // FailedToStart has no exited signal. A normal exit is
                    // handled separately, even if another viewer has started.
                    if (!finished && !didStart && !running)
                        finish("Saved, but could not launch xdg-open.")
                })
            }
            onExited: function(code, status) {
                finish(code !== 0 ? "Saved, but xdg-open could not open the file." : "")
            }
        }
    }

    onActiveChanged: reset()
    onAccountChanged: reset()
    onConfigChanged: reset()
    onDemoChanged: reset()

    Process {
        id: foldersProcess
        stdout: StdioCollector { id: foldersOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.foldersRequest
            Qt.callLater(function() {
                if (request !== root.foldersRequest || !root.foldersLoading || foldersProcess.running) return
                root.foldersLoading = false
                if (root.foldersGeneration !== root.discoveryGeneration) {
                    if (root.pendingFolderRole || root.foldersReload) Qt.callLater(root.loadFolders)
                } else {
                    root.pendingFolderRole = ""
                    root.foldersError = "Could not launch Python 3 to list folders."
                }
            })
        }
        onExited: function(code, status) {
            root.foldersLoading = false
            if (root.foldersGeneration !== root.discoveryGeneration) {
                if (root.pendingFolderRole || root.foldersReload) Qt.callLater(root.loadFolders)
                return
            }
            try {
                var data = root.result(foldersOutput.text, code)
                if (!Array.isArray(data.folders) || data.folders.some(function(f) {
                    return !f || typeof f.id !== "string" || !f.id || typeof f.name !== "string" || !f.name
                })) throw new Error("Invalid folder list from mail helper.")
                root.folders = data.folders
                root.foldersLoaded = true
                root.retryPendingFolderRole()
            } catch (e) { root.pendingFolderRole = ""; root.foldersError = e.message }
        }
    }
    Process {
        id: listProcess
        stdout: StdioCollector { id: listOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.listRequest
            Qt.callLater(function() {
                // FailedToStart does not emit exited. Normal exits clear the
                // latch; a later request must not inherit this failure check.
                if (request !== root.listRequest || !root.loading || listProcess.running) return
                root.loading = false
                if (root.listGeneration !== root.generation) Qt.callLater(root.refresh)
                else root.listError = "Could not launch Python 3. Check that python3 is installed and on PATH."
            })
        }
        onExited: function(code, status) {
            root.loading = false
            if (root.listGeneration !== root.generation) { Qt.callLater(root.refresh); return }
            try {
                var data = root.result(listOutput.text, code)
                if (!Array.isArray(data.messages)) throw new Error("Invalid message list from mail helper.")
                root.messages = data.messages.map(function(m) {
                    if (root.demo && Object.prototype.hasOwnProperty.call(root.demoSeen, m.id))
                        m.unread = !root.demoSeen[m.id]
                    return m
                })
                // Older lifecycle fixtures omit pagination metadata.
                root.page = data.page === undefined ? root.requestedPage : data.page
                root.hasNext = data.hasNext === undefined ? data.messages.length >= 50 : !!data.hasNext
                root.accountLabel = data.account || root.account || "Default account"
            } catch (e) { root.listError = e.message }
        }
    }
    Process {
        id: readProcess
        stdout: StdioCollector { id: readOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.readRequest
            Qt.callLater(function() {
                if (request !== root.readRequest || !root.reading || readProcess.running) return
                root.reading = false
                if (root.readGeneration !== root.generation) Qt.callLater(root.refresh)
                else root.readError = "Could not launch Python 3. Check that python3 is installed and on PATH."
            })
        }
        onExited: function(code, status) {
            root.reading = false
            if (root.readGeneration !== root.generation) { Qt.callLater(root.refresh); return }
            try { root.message = root.result(readOutput.text, code) }
            catch (e) { root.readError = e.message }
        }
    }
    Process {
        id: markProcess
        stdout: StdioCollector { id: markOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.markRequest
            Qt.callLater(function() {
                if (request !== root.markRequest || !root.marking || markProcess.running) return
                root.marking = false
                if (root.markGeneration !== root.generation) Qt.callLater(root.refresh)
                else root.actionError = "Could not launch Python 3. Check that python3 is installed and on PATH."
            })
        }
        onExited: function(code, status) {
            root.marking = false
            if (root.markGeneration !== root.generation) { Qt.callLater(root.refresh); return }
            try {
                var data = root.result(markOutput.text, code)
                if (data.id !== root.markId || data.seen !== root.markSeen)
                    throw new Error("Invalid read-status response from mail helper.")
                root.messages = root.messages.map(function(m) {
                    if (m.id !== root.markId) return m
                    var updated = Object.assign({}, m)
                    updated.unread = !root.markSeen
                    return updated
                })
                if (root.demo) root.demoSeen[root.markId] = root.markSeen
            } catch (e) { root.actionError = e.message }
        }
    }
}
