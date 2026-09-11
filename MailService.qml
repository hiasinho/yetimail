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
        if (!ready || !active || deleting || movePending || marking || savingAttachment || openingAttachment || typeof id !== "string") return false
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
            || deleting || movePending || marking || savingAttachment || openingAttachment) return
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
        if (!ready || !active || deleting || movePending || marking || savingAttachment || openingAttachment
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

    function conventionalFolderName(folder) {
        var name = folder.name.toLowerCase()
        var separator = name.lastIndexOf("/")
        return separator >= 0 ? name.slice(separator + 1) : name
    }

    function inboxFirst(discovered) {
        var inbox = []
        var other = []
        discovered.forEach(function(folder) {
            if (folder.role === "inbox" || (!folder.role && conventionalFolderName(folder) === "inbox")) inbox.push(folder)
            else other.push(folder)
        })
        return inbox.concat(other)
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
                         archive: ["archive", "archives", "all mail"], trash: ["trash", "deleted items", "deleted messages"]}
            matches = folders.filter(function(f) {
                return !f.role && names[role].indexOf(conventionalFolderName(f)) >= 0
            })
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
        if (!ready || !active || loading || reading || deleting || movePending || marking || savingAttachment || openingAttachment
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
    // marking stays latched across the whole serial batch, including deferred launches.
    property bool marking: false
    property bool markInFlight: false
    property var markQueue: []
    readonly property int pendingMarks: markQueue.length
    property bool deleting: false
    property int deleteGeneration: 0
    property int deleteRequest: 0
    property string deleteAccount: ""
    property string deleteFolder: ""
    property string deleteId: ""
    property bool moving: false
    property var moveQueue: []
    property var moveSequence: []
    property var moveActive: null
    property bool movePaused: false
    readonly property int pendingMoves: moveQueue.length
    readonly property bool movePending: moving || moveQueue.length > 0
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
        var args = ["python3", decodeURIComponent(Qt.resolvedUrl("bin/yetimail-helper").toString().replace(/^file:\/\//, "")), operation]
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
        if (!prefetchQueue.length || prefetching || reading || loading || deleting || movePending || marking
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
        // Direct account/config/folder changes invalidate unsent queued mutations.
        // An already-started helper is allowed to finish, but its result is stale.
        moveQueue = []
        moveSequence = []
        movePaused = false
        markQueue = []
        if (!markInFlight) marking = false
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
        if (!ready || !active || loading || deleting || movePending || marking || (reading && target !== page)) return
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

    function setRead(id, seen) { return setReadMany([String(id)], seen) }

    // Validate the whole batch before accepting anything. Flags change only
    // after each successful response; failure stops unsent work, without
    // rolling back successes or changing failed/unsent rows.
    function setReadMany(ids, seen) {
        if (!ready || !active || loading || reading || deleting || movePending || marking
            || savingAttachment || openingAttachment) return false
        actionError = ""
        if (!account.trim() && !demo) {
            actionError = "Select an explicit account before changing read status."
            return false
        }
        if (!validMessageIds(ids)) {
            actionError = "Messages must be unique IDs on the current page."
            return false
        }
        var pending = ids.filter(function(id) {
            var envelope = root.messages.find(function(message) { return message.id === id })
            return envelope && envelope.unread !== !seen
        })
        if (!pending.length) return true
        invalidatePrefetch()
        markQueue = pending.map(function(id) { return {id: id, seen: !!seen, generation: root.generation} })
        marking = true
        startNextMark()
        return true
    }

    function validMessageIds(ids) {
        return Array.isArray(ids) && ids.length > 0 && ids.every(function(id, index) {
            return typeof id === "string" && !!id.trim() && ids.indexOf(id) === index
                && root.messages.some(function(m) { return m.id === id })
        })
    }

    function startNextMark() {
        if (markInFlight || !markQueue.length) return
        var entry = markQueue[0]
        if (!active || entry.generation !== generation) {
            markQueue = []
            marking = false
            Qt.callLater(refresh)
            return
        }
        markId = entry.id
        markSeen = entry.seen
        markGeneration = entry.generation
        markInFlight = true
        markRequest++
        var args = command("mark")
        if (!account && demo) args.push("--account", "Demo")
        markProcess.command = args.concat(["--id", markId, markSeen ? "--seen" : "--unseen"])
        markProcess.running = true
    }

    function stopMarks(error) {
        var stale = markGeneration !== generation
        var remaining = markQueue.length
        markInFlight = false
        markQueue = []
        marking = false
        if (stale) Qt.callLater(refresh)
        else actionError = error + (remaining > 1 ? " Remaining read-status changes were cancelled." : "")
    }

    function deleteCurrent() {
        return active && deleteGeneration === generation && deleteAccount === account && deleteFolder === folderId
    }

    // The UI must confirm its snapshot before calling this single-message API.
    function deleteMessage(id) {
        if (!ready || !active || loading || reading || marking || deleting || movePending || savingAttachment || openingAttachment) return false
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
    function moveMessageToRole(id, role) { return moveMessagesToRole([id], role) }

    function moveMessagesToRole(ids, role) {
        if (!ready || !active || loading || reading || marking || deleting || movePaused || savingAttachment || openingAttachment
            || ["archive", "trash"].indexOf(role) < 0) return false
        var folder = resolveFolderRole(role)
        if (!folder || folder.id === folderId) return false
        return moveMessages(ids, folder.id)
    }

    function moveCurrent(entry) {
        return entry && active && entry.generation === generation && entry.account === account
            && entry.config === config && entry.folder === folderId && entry.page === page
    }

    function hideMoveEntry(entry) {
        messages = messages.filter(function(m) { return m.id !== entry.id })
        if (selectedId === entry.id) {
            selectedId = ""
            message = null
            readError = ""
            attachmentStatus = ""
            cancelAttachmentOpen()
        }
    }

    function restoreMoveEntry(entry) {
        if (!entry || messages.some(function(m) { return m.id === entry.id })) return
        var restored = messages.slice()
        var index = restored.findIndex(function(message) {
            var order = moveSequence.indexOf(message.id)
            return order >= 0 && order > entry.order
        })
        if (index < 0) index = restored.length
        restored.splice(index, 0, entry.envelope)
        messages = restored
    }

    function startNextMove() {
        if (moving || movePaused || !moveQueue.length) return
        var entry = moveQueue[0]
        if (!moveCurrent(entry)) {
            moveQueue = []
            moveSequence = []
            Qt.callLater(refresh)
            return
        }
        moveActive = entry
        moveGeneration = entry.generation
        moveAccount = entry.account
        moveFolder = entry.folder
        moveId = entry.id
        moveDestination = entry.destination
        moving = true
        moveRequest++
        var args = command("move")
        if (!account && demo) args.push("--account", "Demo")
        moveProcess.command = args.concat(["--id", entry.id, "--destination=" + entry.destination])
        moveProcess.running = true
    }

    function pauseMoveQueue(error) {
        var entry = moveActive
        moving = false
        moveActive = null
        if (!moveCurrent(entry)) {
            moveQueue = []
            moveSequence = []
            Qt.callLater(refresh)
            return
        }
        restoreMoveEntry(entry)
        movePaused = true
        actionError = error + " Retry or cancel the pending moves."
    }

    function retryMoves() {
        if (!movePaused || moving || !moveQueue.length || !moveCurrent(moveQueue[0])) return false
        actionError = ""
        hideMoveEntry(moveQueue[0])
        movePaused = false
        Qt.callLater(startNextMove)
        return true
    }

    function cancelPendingMoves() {
        if (moving || !moveQueue.length) return false
        var queued = moveQueue
        messages = messages.filter(function(message) {
            return !queued.some(function(entry) { return entry.id === message.id })
        })
        for (var i = queued.length - 1; i >= 0; --i) restoreMoveEntry(queued[i])
        moveQueue = []
        moveSequence = []
        movePaused = false
        actionError = ""
        Qt.callLater(refresh)
        return true
    }

    function reconcileMoves(entry) {
        var target = !messages.length && page > 1 ? page - 1 : page
        Qt.callLater(function() {
            if (!root.moveCurrent(entry)) root.refresh()
            else root.fetchPage(target)
        })
    }

    // Only discovered, exact destination IDs are accepted. The helper resolves
    // the empty source's configured Inbox alias for same-folder validation.
    function moveMessage(id, destination) { return moveMessages([id], destination) }

    // Atomic acceptance (not a server transaction): validate every ID before
    // hiding rows or appending entries to the existing serial move queue.
    function moveMessages(ids, destination) {
        if (!ready || !active || loading || reading || marking || deleting || movePaused || savingAttachment || openingAttachment) return false
        actionError = ""
        if (!account.trim() && !demo) {
            actionError = "Select an explicit account before moving messages."
            return false
        }
        if (!validMessageIds(ids) || moveQueue.some(function(entry) { return ids.indexOf(entry.id) >= 0 })) {
            actionError = "Messages must be unique IDs on the current page."
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
        if (!moveQueue.length) moveSequence = messages.map(function(message) { return message.id })
        var entries = ids.map(function(id) {
            return {
                generation: root.generation, account: root.account, config: root.config, folder: root.folderId, page: root.page,
                id: id, destination: destination, envelope: root.messages.find(function(m) { return m.id === id }),
                order: root.moveSequence.indexOf(id)
            }
        })
        moveQueue = moveQueue.concat(entries)
        messages = messages.filter(function(message) {
            return ids.indexOf(String(message.id)) < 0
        })
        if (ids.indexOf(selectedId) >= 0) {
            selectedId = ""
            message = null
            readError = ""
            attachmentStatus = ""
            cancelAttachmentOpen()
        }
        Qt.callLater(startNextMove)
        return true
    }

    function readMessage(id) {
        if (!active || reading || deleting || marking || (loading && requestedPage !== page)) return
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
                root.folders = root.inboxFirst(data.folders)
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
            if (root.reading || root.loading || root.deleting || root.movePending || root.marking
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
                root.pauseMoveQueue("Could not launch Python 3 to move message.")
            })
        }
        onExited: function(code, status) {
            var entry = root.moveActive
            if (!root.moveCurrent(entry)) {
                root.moving = false
                root.moveActive = null
                root.moveQueue = []
                root.moveSequence = []
                Qt.callLater(root.refresh)
                return
            }
            try {
                var data = root.result(moveOutput.text, code)
                if (data.id !== entry.id || data.destination !== entry.destination)
                    throw new Error("Invalid move response from mail helper.")
                root.moving = false
                root.moveActive = null
                root.moveQueue = root.moveQueue.slice(1)
                if (root.moveQueue.length) Qt.callLater(root.startNextMove)
                else {
                    root.moveSequence = []
                    root.reconcileMoves(entry)
                }
            } catch (e) { root.pauseMoveQueue(e.message) }
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
                if (request !== root.markRequest || !root.markInFlight || markProcess.running) return
                root.stopMarks("Could not launch Python 3. Check that python3 is installed and on PATH.")
            })
        }
        onExited: function(code, status) {
            if (root.markGeneration !== root.generation) { root.stopMarks(""); return }
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
                root.markInFlight = false
                root.markQueue = root.markQueue.slice(1)
                if (root.markQueue.length) Qt.callLater(root.startNextMark)
                else root.marking = false
            } catch (e) { root.stopMarks(e.message) }
        }
    }
}
