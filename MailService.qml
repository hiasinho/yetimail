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
        if (!ready || !active || deleting || moving || marking || savingAttachment || openingAttachment || typeof id !== "string") return false
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
            || deleting || moving || marking || savingAttachment || openingAttachment) return
        var role = pendingFolderRole
        pendingFolderRole = ""
        selectFolderRole(role)
    }
    // Discovery may finish while an operation has latched. Retry next turn,
    // after exit handlers finish applying old-folder results or launching a viewer.
    onDeletingChanged: if (!deleting) Qt.callLater(retryPendingFolderRole)
    onMovingChanged: if (!moving) Qt.callLater(retryPendingFolderRole)
    onMarkingChanged: if (!marking) Qt.callLater(retryPendingFolderRole)
    onSavingAttachmentChanged: if (!savingAttachment) Qt.callLater(retryPendingFolderRole)
    onOpeningAttachmentChanged: if (!openingAttachment) Qt.callLater(retryPendingFolderRole)

    function selectFolderRole(role) {
        if (!ready || !active || deleting || moving || marking || savingAttachment || openingAttachment
            || ["inbox", "sent", "archive", "trash"].indexOf(role) < 0) return false
        if (!foldersLoaded) {
            pendingFolderRole = role
            loadFolders()
            return true
        }
        var folder = resolveFolderRole(role)
        if (folder) return selectFolder(folder.id)
        if (role === "inbox" && !foldersError) return selectFolder("")
        return false
    }

    // Never defer a message action across asynchronous discovery or navigation.
    // The caller must retry with its current target after discovery completes.
    function resolveFolderRole(role) {
        foldersError = ""
        if (["inbox", "sent", "archive", "trash"].indexOf(role) < 0) return null
        if (!foldersLoaded || foldersLoading) {
            loadFolders()
            foldersError = "Loading folders. Retry the action when discovery finishes."
            return null
        }
        var matches = folders.filter(function(f) { return f.role === role })
        if (!matches.length) {
            var names = {inbox: ["inbox"], sent: ["sent", "sent mail", "sent items", "sent messages"],
                         archive: ["archive", "archives"], trash: ["trash", "deleted items", "deleted messages"]}
            matches = folders.filter(function(f) { return !f.role && names[role].indexOf(f.name.toLowerCase()) >= 0 })
        }
        if (matches.length === 1) return matches[0]
        if (!matches.length && role === "inbox") return null
        foldersError = matches.length ? "More than one " + role + " folder is available. Choose a folder." : "No known " + role + " folder is available."
        return null
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
        if (!ready || !active || loading || reading || deleting || moving || marking || savingAttachment || openingAttachment
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
    property bool deleting: false
    property int deleteGeneration: 0
    property int deleteRequest: 0
    property string deleteAccount: ""
    property string deleteFolder: ""
    property string deleteId: ""
    property bool moving: false
    property int moveGeneration: 0
    property int moveRequest: 0
    property string moveAccount: ""
    property string moveFolder: ""
    property string moveId: ""
    property string moveDestination: ""
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
    // Background reads only warm the helper's SQLite cache. They never alter
    // message/readError unless an open promotes the same in-flight request.
    property string prefetchSelection: ""
    property var prefetchQueue: []
    property bool prefetching: false
    property string prefetchId: ""
    property int prefetchGeneration: 0
    property int prefetchListRequest: 0
    property int prefetchRequest: 0
    property bool prefetchForeground: false
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

    function messageReadCommand(id) {
        var args = command("read").concat(["--id", id])
        var envelope = messages.find(function(m) { return m.id === id })
        if (envelope && typeof envelope.cacheIdentity === "string" && /^[0-9a-f]{64}$/.test(envelope.cacheIdentity))
            args.push("--cache-identity", envelope.cacheIdentity)
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

    function invalidatePrefetch() {
        prefetchTimer.stop()
        prefetchQueue = []
        prefetchSelection = ""
        prefetchRequest++
        // A promoted request is now a foreground read and must survive the
        // Widget switching from list to reader.
        if (!prefetchForeground) prefetchId = ""
    }

    function setPrefetchSelection(id) {
        if (demo || !ready || !active || typeof id !== "string") return
        prefetchSelection = id
        prefetchQueue = []
        prefetchRequest++
        prefetchTimer.stop()
        if (!id) return
        var index = messages.findIndex(function(m) { return m.id === id })
        if (index < 0) return
        prefetchQueue = messages.slice(index, index + 3).map(function(m) { return String(m.id) })
        prefetchTimer.restart()
    }

    function startPrefetch() {
        if (!prefetchQueue.length || prefetching || reading || loading || deleting || moving || marking
            || savingAttachment || openingAttachment || !active) return
        prefetchId = prefetchQueue[0]
        prefetchQueue = prefetchQueue.slice(1)
        prefetchGeneration = generation
        prefetchListRequest = listRequest
        prefetchForeground = false
        prefetching = true
        prefetchProcess.command = messageReadCommand(prefetchId)
        prefetchProcess.running = true
    }

    function resetMessages() {
        invalidatePrefetch()
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
        if (!ready || !active || loading || deleting || moving || marking || (reading && target !== page)) return
        if (target !== page) {
            invalidatePrefetch()
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
        if (!ready || !active || loading || reading || deleting || moving || marking) return
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

    function deleteCurrent() {
        return active && deleteGeneration === generation && deleteAccount === account && deleteFolder === folderId
    }

    // The UI must confirm its snapshot before calling this single-message API.
    function deleteMessage(id) {
        if (!ready || !active || loading || reading || marking || deleting || moving || savingAttachment || openingAttachment) return false
        actionError = ""
        if (!account.trim() && !demo) {
            actionError = "Select an explicit account before deleting messages."
            return false
        }
        if (typeof id !== "string" || !id.trim() || !messages.some(function(m) { return m.id === id })) {
            actionError = "Message is not on the current page."
            return false
        }
        invalidatePrefetch()
        deleteGeneration = generation
        deleteAccount = account
        deleteFolder = folderId
        deleteId = id
        deleting = true
        deleteRequest++
        var args = command("delete")
        if (!account && demo) args.push("--account", "Demo")
        deleteProcess.command = args.concat(["--id", id])
        deleteProcess.running = true
        return true
    }

    // Archive/trash shortcuts are moves only, including when already in Trash.
    function moveMessageToRole(id, role) {
        if (!ready || !active || loading || reading || marking || deleting || moving || savingAttachment || openingAttachment
            || ["archive", "trash"].indexOf(role) < 0) return false
        var folder = resolveFolderRole(role)
        if (!folder || folder.id === folderId) return false
        return moveMessage(id, folder.id)
    }

    function moveCurrent() {
        return active && moveGeneration === generation && moveAccount === account && moveFolder === folderId
    }

    // Only discovered, exact destination IDs are accepted. The helper resolves
    // the empty source's configured Inbox alias for same-folder validation.
    function moveMessage(id, destination) {
        if (!ready || !active || loading || reading || marking || deleting || moving || savingAttachment || openingAttachment) return false
        actionError = ""
        if (!account.trim() && !demo) {
            actionError = "Select an explicit account before moving messages."
            return false
        }
        if (typeof id !== "string" || !id || !messages.some(function(m) { return m.id === id })) {
            actionError = "Message is not on the current page."
            return false
        }
        var folder = folders.find(function(f) { return f.id === destination })
        if (!foldersLoaded || typeof destination !== "string" || !destination || !folder) {
            actionError = "Destination folder is not available."
            return false
        }
        if (destination === folderId) {
            actionError = "Message is already in that folder."
            return false
        }
        invalidatePrefetch()
        moveGeneration = generation
        moveAccount = account
        moveFolder = folderId
        moveId = id
        moveDestination = destination
        moving = true
        moveRequest++
        var args = command("move")
        if (!account && demo) args.push("--account", "Demo")
        moveProcess.command = args.concat(["--id", id, "--destination=" + destination])
        moveProcess.running = true
        return true
    }

    function readMessage(id) {
        if (!active || reading || deleting || moving || marking || (loading && requestedPage !== page)) return
        selectedId = String(id)
        attachmentStatus = ""
        cancelAttachmentOpen()
        message = null
        readError = ""
        readGeneration = generation
        reading = true
        readRequest++
        if (prefetching && prefetchId === selectedId && prefetchGeneration === generation
            && prefetchListRequest === listRequest) {
            // Consume the already-running fetch instead of downloading twice.
            prefetchForeground = true
            prefetchQueue = []
            prefetchTimer.stop()
            return
        }
        readProcess.command = messageReadCommand(selectedId)
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
    Timer {
        id: prefetchTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (root.reading || root.loading || root.deleting || root.moving || root.marking
                || root.savingAttachment || root.openingAttachment) restart()
            else root.startPrefetch()
        }
    }
    Process {
        id: prefetchProcess
        stdout: StdioCollector { id: prefetchOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var id = root.prefetchId
            Qt.callLater(function() {
                if (!root.prefetching || prefetchProcess.running || id !== root.prefetchId) return
                var foreground = root.prefetchForeground
                root.prefetching = false
                root.prefetchForeground = false
                if (foreground) {
                    root.reading = false
                    if (root.readGeneration === root.generation && root.selectedId === id)
                        root.readError = "Could not launch Python 3. Check that python3 is installed and on PATH."
                }
                root.prefetchId = ""
                if (!foreground && !prefetchTimer.running) root.startPrefetch()
            })
        }
        onExited: function(code, status) {
            var id = root.prefetchId
            var foreground = root.prefetchForeground
            var current = root.prefetchGeneration === root.generation
                && (foreground || root.prefetchListRequest === root.listRequest)
            root.prefetching = false
            root.prefetchForeground = false
            root.prefetchId = ""
            if (foreground) {
                root.reading = false
                if (!current || root.readGeneration !== root.generation || root.selectedId !== id) {
                    if (root.readGeneration !== root.generation) Qt.callLater(root.refresh)
                    return
                }
                try {
                    var data = root.result(prefetchOutput.text, code)
                    if (!data || data.id !== id) throw new Error("Invalid message response from mail helper.")
                    root.message = data
                } catch (e) { root.readError = e.message }
                return
            }
            // Background failures are deliberately silent. A changed queue can
            // still begin after this old process exits.
            if ((current || root.prefetchQueue.length) && !prefetchTimer.running)
                Qt.callLater(root.startPrefetch)
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
            try {
                var data = root.result(readOutput.text, code)
                if (!data || data.id !== root.selectedId) throw new Error("Invalid message response from mail helper.")
                root.message = data
            } catch (e) { root.readError = e.message }
            if (root.prefetchQueue.length) Qt.callLater(root.startPrefetch)
        }
    }
    Process {
        id: moveProcess
        stdout: StdioCollector { id: moveOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.moveRequest
            Qt.callLater(function() {
                if (request !== root.moveRequest || !root.moving || moveProcess.running) return
                root.moving = false
                if (!root.moveCurrent()) Qt.callLater(root.refresh)
                else root.actionError = "Could not launch Python 3 to move message."
            })
        }
        onExited: function(code, status) {
            root.moving = false
            if (!root.moveCurrent()) { Qt.callLater(root.refresh); return }
            try {
                var data = root.result(moveOutput.text, code)
                if (data.id !== root.moveId || data.destination !== root.moveDestination)
                    throw new Error("Invalid move response from mail helper.")
                root.messages = root.messages.filter(function(m) { return m.id !== root.moveId })
                if (root.selectedId === root.moveId) {
                    root.selectedId = ""
                    root.message = null
                    root.readError = ""
                    root.attachmentStatus = ""
                    root.cancelAttachmentOpen()
                }
                // Refill the current page; an emptied final page falls back.
                var target = !root.messages.length && root.page > 1 ? root.page - 1 : root.page
                Qt.callLater(function() { root.fetchPage(root.moveCurrent() ? target : root.page) })
            } catch (e) { root.actionError = e.message }
        }
    }
    Process {
        id: deleteProcess
        stdout: StdioCollector { id: deleteOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.deleteRequest
            Qt.callLater(function() {
                if (request !== root.deleteRequest || !root.deleting || deleteProcess.running) return
                root.deleting = false
                if (!root.deleteCurrent()) Qt.callLater(root.refresh)
                else root.actionError = "Could not launch Python 3 to delete message."
            })
        }
        onExited: function(code, status) {
            root.deleting = false
            if (!root.deleteCurrent()) { Qt.callLater(root.refresh); return }
            try {
                var data = root.result(deleteOutput.text, code)
                if (data.id !== root.deleteId)
                    throw new Error("Invalid delete response from mail helper.")
                root.messages = root.messages.filter(function(m) { return m.id !== root.deleteId })
                if (root.selectedId === root.deleteId) {
                    root.selectedId = ""
                    root.message = null
                    root.readError = ""
                    root.attachmentStatus = ""
                    root.cancelAttachmentOpen()
                }
                // Refill the current page; an emptied final page falls back.
                var target = !root.messages.length && root.page > 1 ? root.page - 1 : root.page
                Qt.callLater(function() { root.fetchPage(root.deleteCurrent() ? target : root.page) })
            } catch (e) { root.actionError = e.message }
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
