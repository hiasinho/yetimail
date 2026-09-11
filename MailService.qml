import QtQuick
import Quickshell.Io

Item {
    id: root
    signal accountConfigSaved(string transaction)
    signal accountConfigSaveFailed(string transaction)
    signal accountConfigFenceExpired(string transaction)
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
    property bool foldersProbe: false
    property var folderCacheProbed: ({})
    property var folderWarmQueue: []
    property var folderWarmJob: null
    // Successful discovery is retained per effective configuration/account for
    // this process. Cache entries include an explicit loaded bit so a valid
    // empty result remains distinct from a context that was never discovered.
    property var folderCache: ({})

    function folderCacheKeyFor(configPath, accountId, demoMode) {
        return JSON.stringify([String(configPath), String(accountId), !!demoMode])
    }

    function folderCacheKey() {
        return folderCacheKeyFor(config, account, demo)
    }

    function restoreFolderCache(clearCache) {
        if (clearCache) {
            folderCache = ({})
            pageSnapshots = ({})
            preferredPages = ({})
            snapshotOrder = []
            accountEpochs = ({})
            snapshotEpoch++
            listQueue = []
            folderCacheProbed = ({})
            folderWarmQueue = []
        }
        var entry = folderCache[folderCacheKey()]
        if (entry && entry.loaded && Array.isArray(entry.folders)) {
            folders = entry.folders.slice()
            foldersLoaded = true
        } else {
            folders = []
            foldersLoaded = false
        }
    }

    function cacheFoldersFor(key, discovered) {
        var next = ({})
        Object.keys(folderCache).forEach(function(existing) { next[existing] = folderCache[existing] })
        next[key] = {loaded: true, folders: discovered.slice()}
        folderCache = next
    }

    function cacheFolders(discovered) { cacheFoldersFor(folderCacheKey(), discovered) }

    function folderCommand(accountId, configPath, demoMode, cacheOnly) {
        var args = ["python3", decodeURIComponent(Qt.resolvedUrl("bin/yetimail-helper").toString().replace(/^file:\/\//, "")), "folders"]
        if (accountId) args.push("--account", accountId)
        if (configPath) args.push("--config", configPath)
        if (demoMode) args.push("--demo")
        if (cacheOnly) args.push("--cache-only")
        return args
    }

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
        var key = folderCacheKey()
        foldersProbe = !demo && !foldersLoaded && !folderCacheProbed[key]
        if (foldersProbe) {
            var probed = Object.assign({}, folderCacheProbed)
            probed[key] = true
            folderCacheProbed = probed
        }
        foldersProcess.command = folderCommand(account, config, demo, foldersProbe)
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
    onDeletingChanged: if (!deleting) { Qt.callLater(retryPendingFolderRole); Qt.callLater(resumeLists) }
    onMovingChanged: if (!moving) { Qt.callLater(retryPendingFolderRole); Qt.callLater(resumeLists) }
    onMarkingChanged: if (!marking) { Qt.callLater(retryPendingFolderRole); Qt.callLater(resumeLists) }

    function resumeLists() {
        if (!ready || !active || deleting || movePending || marking) return
        Qt.callLater(startListJob)
    }
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
        if (!foldersLoaded) {
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
    property var accountLabels: ({})
    property var accountOverview: []
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
    // Quickshell's running flips only after launch, so latch requests ourselves.
    property bool loading: false
    property bool refreshing: false
    property var pageSnapshots: ({})
    property var preferredPages: ({})
    property var snapshotOrder: []
    property int snapshotLimit: 32
    property int snapshotEpoch: 0
    property var accountEpochs: ({})
    property var listQueue: []
    property var listJob: null
    property string visibleListKey: ""
    property var allowedWarmAccounts: []
    property var markContext: null
    property var deleteContext: null
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

    function mailboxViewKey(accountId, mailbox) {
        return JSON.stringify([String(config), String(accountId), !!demo, String(mailbox)])
    }

    function listContext(accountId, mailbox, target) {
        var scope = JSON.stringify([String(config), String(accountId), !!demo])
        return {config: config, account: accountId, demo: demo, folder: mailbox, page: target,
                scope: scope, epoch: snapshotEpoch, revision: accountEpochs[scope] || 0,
                key: JSON.stringify([String(config), String(accountId), !!demo, mailbox, target])}
    }

    function defaultAccountId() {
        var defaults = accountOverview.filter(function(item) { return item && item.default === true && item.id })
        return defaults.length === 1 ? String(defaults[0].id) : ""
    }

    function equivalentListScopes(c) {
        var scopes = [c.scope]
        function include(accountId) {
            var scope = JSON.stringify([String(c.config), String(accountId), !!c.demo])
            if (scopes.indexOf(scope) < 0) scopes.push(scope)
        }
        var defaultId = defaultAccountId()
        // The helper treats omitted and literal "default" as aliases. A named
        // account may also be the default even if safe overview parsing failed.
        if (c.account) { include(""); include("default") }
        if (defaultId && (c.account === defaultId || !c.account || c.account === "default")) include(defaultId)
        if (!c.account || c.account === "default") {
            // Without a resolvable overview, conservatively fence every allowed
            // account rather than risk restoring an aliased pre-mutation page.
            allowedWarmAccounts.forEach(include)
            Object.keys(pageSnapshots).forEach(function(key) {
                var context = pageSnapshots[key].context
                if (context.config === c.config && context.demo === c.demo) include(context.account)
            })
            listQueue.forEach(function(job) {
                if (job.context.config === c.config && job.context.demo === c.demo) include(job.context.account)
            })
            if (listJob && listJob.context.config === c.config && listJob.context.demo === c.demo)
                include(listJob.context.account)
        }
        return scopes
    }

    function validListContext(c) {
        return c && c.epoch === snapshotEpoch && c.revision === (accountEpochs[c.scope] || 0)
    }

    function visibleList(c) {
        return active && validListContext(c) && c.key === visibleListKey
    }

    function storePage(c, data) {
        if (!validListContext(c)) return
        var next = Object.assign({}, pageSnapshots)
        next[c.key] = {context: c, value: JSON.parse(JSON.stringify(data))}
        var order = snapshotOrder.filter(function(key) { return key !== c.key }).concat([c.key])
        while (order.length > Math.max(1, snapshotLimit)) delete next[order.shift()]
        pageSnapshots = next
        snapshotOrder = order
    }

    function showPage(c, data) {
        messages = data.messages.map(function(m) {
            var row = Object.assign({}, m)
            if (c.demo && Object.prototype.hasOwnProperty.call(demoSeen, row.id)) row.unread = !demoSeen[row.id]
            return row
        })
        page = data.page === undefined ? c.page : data.page
        hasNext = data.hasNext === undefined ? messages.length >= 50 : !!data.hasNext
        accountLabel = data.account || c.account || "Default account"
        var views = Object.assign({}, preferredPages)
        views[mailboxViewKey(c.account, c.folder)] = page
        preferredPages = views
        loading = false
    }

    // Conservative account-wide fencing covers configured Inbox aliases and
    // destination IDs that differ from source IDs. Never probe pre-mutation disk pages.
    function fenceLists(c, discard) {
        if (!c || c.epoch !== snapshotEpoch) return
        var scopes = equivalentListScopes(c)
        var revisions = Object.assign({}, accountEpochs)
        scopes.forEach(function(scope) { revisions[scope] = (revisions[scope] || 0) + 1 })
        accountEpochs = revisions
        var next = Object.assign({}, pageSnapshots)
        Object.keys(next).forEach(function(key) {
            var entry = next[key]
            if (scopes.indexOf(entry.context.scope) < 0) return
            if (discard) delete next[key]
            else next[key] = {context: Object.assign({}, entry.context, {revision: revisions[entry.context.scope]}),
                value: entry.value}
        })
        pageSnapshots = next
        snapshotOrder = snapshotOrder.filter(function(key) { return !!next[key] })
        listQueue = listQueue.filter(function(job) { return root.validListContext(job.context) })
        if (scopes.indexOf(listContext(account, folderId, page).scope) >= 0) refreshing = false
    }

    function patchSnapshots(c, id, seen) {
        // Preserve pages for the exact source spelling, but discard every other
        // potentially aliased mailbox in equivalent default-account contexts.
        var old = Object.assign({}, pageSnapshots)
        var scopes = equivalentListScopes(c)
        fenceLists(c, true)
        Object.keys(old).forEach(function(key) {
            var entry = old[key]
            if (scopes.indexOf(entry.context.scope) < 0 || entry.context.folder !== c.folder) return
            var rows = entry.value.messages.map(function(row) {
                return row.id === id ? Object.assign({}, row, {unread: !seen}) : Object.assign({}, row)
            })
            var updated = listContext(entry.context.account, entry.context.folder, entry.context.page)
            storePage(updated, {messages: rows, page: entry.context.page,
                hasNext: !!entry.value.hasNext, account: entry.value.account || entry.context.account || "Default account"})
        })
    }

    function queueList(c, probe, foreground) {
        if (!validListContext(c)) return
        if (listJob && listJob.context.key === c.key && validListContext(listJob.context)) return
        var queue = listQueue.slice()
        var index = queue.findIndex(function(job) { return job.context.key === c.key && root.validListContext(job.context) })
        if (index >= 0) {
            if (foreground) queue[index] = {context: c, probe: queue[index].probe, foreground: true}
        } else queue.push({context: c, probe: probe, foreground: foreground})
        listQueue = queue
        Qt.callLater(startListJob)
    }

    function startListJob() {
        if (listJob || !ready || !active || deleting || movePending || marking) return
        var queue = listQueue.filter(function(job) {
            return root.validListContext(job.context) && (job.foreground
                || (!root.demo && root.allowedWarmAccounts.indexOf(job.context.account) >= 0))
        })
        if (!queue.length) { listQueue = []; return }
        var index = queue.findIndex(function(job) { return job.context.key === root.visibleListKey })
        if (index < 0) index = queue.findIndex(function(job) { return job.foreground })
        if (index < 0) index = 0
        var job = queue.splice(index, 1)[0]
        listQueue = queue
        listJob = job
        var c = job.context
        // Capture all arguments now; no queued work consults later account settings.
        var args = ["python3", decodeURIComponent(Qt.resolvedUrl("bin/yetimail-helper").toString().replace(/^file:\/\//, "")), "list"]
        if (c.account) args.push("--account", c.account)
        if (c.config) args.push("--config", c.config)
        if (c.demo) args.push("--demo")
        if (c.folder) args.push("--mailbox=" + c.folder)
        args.push("--page", String(c.page))
        if (job.probe) args.push("--cache-only")
        listProcess.command = args
        listProcess.running = true
    }

    function finishList(text, code, launchError) {
        var job = listJob
        if (!job) return
        listJob = null
        var c = job.context
        var current = visibleList(c)
        if (validListContext(c)) {
            try {
                if (launchError) throw new Error(launchError)
                var data = result(text, code)
                if (job.probe) data = data.hit === true ? data.value : null
                if (data) {
                    if (!Array.isArray(data.messages)) throw new Error("Invalid message list from mail helper.")
                    storePage(c, data)
                    if (current) { showPage(c, data); refreshing = job.probe }
                }
            } catch (e) { if (current && !job.probe) listError = e.message }
            if (job.probe) queueList(c, false, current)
            else if (current) {
                loading = false
                refreshing = false
                // Adjacent pages warm after the visible page, without changing it.
                var previous = c.page > 1 ? listContext(c.account, c.folder, c.page - 1) : null
                var following = data && data.hasNext === true ? listContext(c.account, c.folder, c.page + 1) : null
                if (previous && !pageSnapshots[previous.key]) queueList(previous, false, true)
                if (following && !pageSnapshots[following.key]) queueList(following, false, true)
            }
        }
        Qt.callLater(startListJob)
    }

    function warmAccounts(allowedAccounts) {
        allowedWarmAccounts = Array.isArray(allowedAccounts) ? allowedAccounts.filter(function(id, index) {
            return typeof id === "string" && !!id.trim() && allowedAccounts.indexOf(id) === index
        }) : []
        if (demo || !ready || !active) return
        var folderQueue = folderWarmQueue.slice()
        allowedWarmAccounts.forEach(function(id) {
            if (id !== root.account) {
                var c = root.listContext(id, "", 1)
                if (!root.pageSnapshots[c.key]) root.queueList(c, !(root.accountEpochs[c.scope] || 0), false)
            }
            var key = root.folderCacheKeyFor(root.config, id, false)
            var queued = folderQueue.some(function(job) { return job.key === key })
            if (!root.folderCache[key] && !queued && (!root.folderWarmJob || root.folderWarmJob.key !== key))
                folderQueue.push({account: id, config: root.config, key: key, epoch: root.snapshotEpoch})
        })
        folderWarmQueue = folderQueue
        Qt.callLater(startFolderWarm)
    }

    function startFolderWarm() {
        if (folderWarmJob || demo || !ready || !active || !folderWarmQueue.length) return
        var queue = folderWarmQueue.filter(function(job) {
            return job.epoch === root.snapshotEpoch && root.allowedWarmAccounts.indexOf(job.account) >= 0
        })
        folderWarmQueue = queue.slice(1)
        if (!queue.length) return
        folderWarmJob = queue[0]
        folderWarmProcess.command = folderCommand(folderWarmJob.account, folderWarmJob.config, false, false)
        folderWarmProcess.running = true
    }

    function finishFolderWarm(text, code) {
        var job = folderWarmJob
        folderWarmJob = null
        if (job && job.epoch === snapshotEpoch) {
            try {
                var data = result(text, code)
                if (!Array.isArray(data.folders)) throw new Error("Invalid warmed folder list.")
                var discovered = inboxFirst(data.folders)
                cacheFoldersFor(job.key, discovered)
                if (job.key === folderCacheKey() && !foldersLoaded) {
                    folders = discovered.slice()
                    foldersLoaded = true
                }
            } catch (e) { /* Background warming never replaces foreground errors. */ }
        }
        Qt.callLater(startFolderWarm)
    }

    function command(operation) {
        var args = ["python3", decodeURIComponent(Qt.resolvedUrl("bin/yetimail-helper").toString().replace(/^file:\/\//, "")), operation]
        if (account) args.push("--account", account)
        if (config) args.push("--config", config)
        if (demo) args.push("--demo")
        if (operation !== "folders" && folderId) args.push("--mailbox=" + folderId)
        return args
    }

    function accountSettingsCommand(operation) {
        var args = ["python3", decodeURIComponent(Qt.resolvedUrl("bin/yetimail-helper").toString().replace(/^file:\/\//, "")), operation]
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
        accountLabelsProcess.command = accountSettingsCommand("account-labels")
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
        accountOverviewProcess.command = accountSettingsCommand("accounts")
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
        accountLabelProcess.command = accountSettingsCommand("account-label").concat(["--account=" + accountId, "--label=" + label])
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
        accountConfigProcess.command = accountSettingsCommand("account-save").concat([
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

    function messageReadCommand(id) {
        var args = command("read").concat(["--id", id])
        var envelope = messages.find(function(m) { return m.id === id })
        if (envelope && typeof envelope.cacheIdentity === "string" && /^[0-9a-f]{64}$/.test(envelope.cacheIdentity))
            args.push("--cache-identity", envelope.cacheIdentity)
        return args
    }

    function reset(clearFolderCache, deferFetch) {
        discoveryGeneration++
        restoreFolderCache(!!clearFolderCache)
        foldersError = ""
        foldersReload = false
        pendingFolderRole = ""
        folderId = ""
        folderName = "Inbox"
        resetMessages(!!deferFetch)
    }

    function prepareAccountConfigSave(transaction) {
        if (typeof transaction !== "string" || !transaction) return false
        accountConfigFenceToken = transaction
        accountConfigBlocked = true
        accountConfigRefreshPending = true
        accountConfigFenceTimer.restart()
        reset(true, true)
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
        reset(true, !!deferFetch)
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
        if (ready && active) fetchPage(page)
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

    function resetMessages(deferFetch) {
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
        var rememberedPage = Number(preferredPages[mailboxViewKey(account, folderId)]) || 1
        page = Math.max(1, Math.floor(rememberedPage))
        hasNext = false
        demoSeen = ({})
        accountLabel = account || "Default account"
        loading = false
        refreshing = false
        visibleListKey = ""
        listQueue = listQueue.filter(function(job) { return !job.foreground })
        // Memory restoration is synchronous even while another account is fetching.
        if (ready && active && !deferFetch) fetchPage(page)
    }

    function refresh() { fetchPage(page) }

    function nextPage() {
        if (hasNext) fetchPage(page + 1)
    }

    function previousPage() {
        if (page > 1) fetchPage(page - 1)
    }

    function fetchPage(target) {
        if (!ready || !active || accountConfigBlocked || loading || deleting || movePending || marking || (reading && readGeneration === generation && target !== page)) return
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
        listRequest++
        var c = listContext(account, folderId, target)
        visibleListKey = c.key
        var cached = pageSnapshots[c.key]
        if (cached && !validListContext(cached.context)) cached = null
        loading = !cached && !(target === page && messages.length)
        refreshing = !loading
        if (cached) { showPage(c, cached.value); refreshing = true }
        queueList(c, !cached && !demo && !(accountEpochs[c.scope] || 0), true)
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
        markContext = listContext(account, folderId, page)
        fenceLists(markContext, false)
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
        deleteContext = listContext(account, folderId, page)
        fenceLists(deleteContext, true)
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
        entry.listContext = listContext(entry.account, entry.folder, entry.page)
        fenceLists(entry.listContext, true)
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
        fenceLists(listContext(account, folderId, page), true)
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

    onActiveChanged: reset(false)
    onAccountChanged: { accountConfigFenceTimer.stop(); accountConfigFenceToken = ""; accountConfigBlocked = false; accountConfigRefreshPending = false; reset(false) }
    onConfigChanged: {
        accountOverviewRequest++
        accountConfigRequest++
        accountOverview = []
        accountOverviewLoading = false
        accountConfigSaving = false
        accountConfigFenceTimer.stop()
        accountConfigFenceToken = ""
        accountConfigBlocked = false
        accountConfigRefreshPending = false
        accountOverviewError = ""
        reset(true)
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
        accountConfigFenceTimer.stop()
        accountConfigFenceToken = ""
        accountConfigBlocked = false
        accountConfigRefreshPending = false
        accountOverviewError = ""
        reset(true)
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
    Process {
        id: folderWarmProcess
        stdout: StdioCollector { id: folderWarmOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var job = root.folderWarmJob
            Qt.callLater(function() {
                if (job && root.folderWarmJob === job && !folderWarmProcess.running)
                    root.finishFolderWarm("", -1)
            })
        }
        onExited: function(code, status) { root.finishFolderWarm(folderWarmOutput.text, code) }
    }
    Process {
        id: foldersProcess
        stdout: StdioCollector { id: foldersOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var request = root.foldersRequest
            var probe = root.foldersProbe
            Qt.callLater(function() {
                if (request !== root.foldersRequest || !root.foldersLoading || foldersProcess.running) return
                root.foldersLoading = false
                root.foldersProbe = false
                if (root.foldersGeneration !== root.discoveryGeneration) {
                    if (root.pendingFolderRole || root.foldersReload) Qt.callLater(root.loadFolders)
                } else if (probe) Qt.callLater(root.loadFolders)
                else {
                    root.pendingFolderRole = ""
                    root.foldersError = "Could not launch Python 3 to list folders."
                }
            })
        }
        onExited: function(code, status) {
            var probe = root.foldersProbe
            root.foldersLoading = false
            root.foldersProbe = false
            if (root.foldersGeneration !== root.discoveryGeneration) {
                if (root.pendingFolderRole || root.foldersReload) Qt.callLater(root.loadFolders)
                return
            }
            try {
                var data = root.result(foldersOutput.text, code)
                if (probe) data = data && data.hit === true ? data.value : null
                if (data) {
                    if (!Array.isArray(data.folders) || data.folders.some(function(f) {
                        return !f || typeof f.id !== "string" || !f.id || typeof f.name !== "string" || !f.name
                    })) throw new Error("Invalid folder list from mail helper.")
                    var discovered = root.inboxFirst(data.folders)
                    root.folders = discovered
                    root.foldersLoaded = true
                    root.cacheFolders(discovered)
                    root.retryPendingFolderRole()
                }
            } catch (e) {
                if (!probe) { root.pendingFolderRole = ""; root.foldersError = e.message }
            }
            if (probe) Qt.callLater(root.loadFolders)
        }
    }
    Process {
        id: listProcess
        stdout: StdioCollector { id: listOutput; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onRunningChanged: {
            if (running) return
            var job = root.listJob
            Qt.callLater(function() {
                if (!job || root.listJob !== job || listProcess.running) return
                root.finishList("", -1, "Could not launch Python 3. Check that python3 is installed and on PATH.")
            })
        }
        onExited: function(code, status) { root.finishList(listOutput.text, code, "") }
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
            if (entry) root.fenceLists(entry.listContext, true)
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
            root.fenceLists(root.deleteContext, true)
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
            if (root.markGeneration !== root.generation) {
                root.fenceLists(root.markContext, true)
                root.stopMarks("")
                return
            }
            try {
                var data = root.result(markOutput.text, code)
                if (data.id !== root.markId || data.seen !== root.markSeen)
                    throw new Error("Invalid read-status response from mail helper.")
                root.patchSnapshots(root.markContext, root.markId, root.markSeen)
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
