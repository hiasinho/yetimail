import QtQuick

// Deliberately no Process/import of production service, helper, or account files.
Item {
    signal accountConfigSaved(string transaction)
    signal accountConfigSaveFailed(string transaction)
    signal accountConfigFenceExpired(string transaction)
    property bool active: false
    property string account: ""
    property string config: ""
    property int generation: 0
    property var folderCache: ({})
    function canonicalFolders() {
        return [
            {id: "INBOX", name: "Inbox", role: "inbox"},
            {id: "Sent", name: "Sent mail", role: "sent"},
            {id: "Archive", name: "Archive", role: "archive"},
            {id: "Trash", name: "Trash", role: "trash"},
            {id: "Projects/2026", name: "Projects / 2026", role: ""}
        ]
    }
    function folderCacheKey() { return JSON.stringify([String(config), String(account), !!demo]) }
    function restoreFolders(clearCache) {
        if (clearCache) folderCache = ({})
        var entry = folderCache[folderCacheKey()]
        foldersLoaded = !!(entry && entry.loaded)
        folders = foldersLoaded ? entry.folders.slice() : []
    }
    onConfigChanged: { generation++; pendingFolderRole = ""; restoreFolders(true) }
    property bool demo: false
    readonly property string accountLabel: account || "Fixture"
    property var accountLabels: ({alpha: "Personal", beta: "Work"})
    property var accountOverview: []
    property bool accountOverviewLoading: false
    property string accountOverviewError: ""
    property bool accountLabelSaving: false
    property bool accountConfigSaving: false
    property bool accountConfigBlocked: false
    property bool accountConfigRefreshPending: false
    property string accountConfigFenceToken: ""
    function prepareAccountConfigSave(transaction) { accountConfigFenceToken = transaction; accountConfigBlocked = true; accountConfigRefreshPending = true }
    function renewAccountConfigFence(transaction) {}
    function commitAccountConfigSave(transaction, deferFetch) { if (transaction !== accountConfigFenceToken) return; accountConfigFenceToken = ""; accountConfigBlocked = false; accountConfigRefreshPending = deferFetch }
    function cancelAccountConfigSave(transaction) { if (transaction !== accountConfigFenceToken) return; accountConfigFenceToken = ""; accountConfigBlocked = false; accountConfigRefreshPending = false }
    function resumeAccountConfig() { accountConfigRefreshPending = false }
    function loadAccountLabels() {}
    function loadAccountOverview() {
        record("accounts")
        accountOverview = [
            {id: "alpha", label: accountLabels.alpha || "", email: "alpha@example.test", "display-name": "Alpha Sender", default: true, receiving: ["imap"], sending: ["smtp"], editable: true, "editable-reason": "", revision: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "mailbox-mappings": {inbox: "INBOX", sent: "Sent", drafts: "Drafts", trash: "Trash", archive: "Archive"}},
            {id: "beta", label: accountLabels.beta || "", email: "beta@example.test", "display-name": "Beta Sender", default: false, receiving: ["jmap"], sending: ["jmap"], editable: true, "editable-reason": "", revision: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "mailbox-mappings": {inbox: "", sent: "", drafts: "", trash: "", archive: ""}},
            {id: "configured-only", label: "", email: "extra@example.test", "display-name": "Extra Sender", default: false, receiving: ["imap"], sending: [], editable: false, "editable-reason": "Merged configurations are read-only.", revision: "", "mailbox-mappings": {inbox: "", sent: "", drafts: "", trash: "", archive: ""}}
        ]
    }
    function saveAccountLabel(id, label) {
        record("account-label", id, label)
        var updatedLabels = Object.assign({}, accountLabels)
        if (label) updatedLabels[id] = label
        else delete updatedLabels[id]
        accountLabels = updatedLabels
        accountOverview = accountOverview.map(function(item) {
            if (item.id !== id) return item
            var updated = Object.assign({}, item)
            updated.label = label
            return updated
        })
        return true
    }
    function saveAccountConfig(transaction, id, revision, email, displayName, makeDefault, inbox, sent, drafts, trash, archive) {
        record("account-save", id, email)
        accountOverview = accountOverview.map(function(item) {
            var updated = Object.assign({}, item)
            if (makeDefault) updated.default = item.id === id
            if (item.id === id) {
                updated.email = email
                updated["display-name"] = displayName
                updated["mailbox-mappings"] = {inbox: inbox, sent: sent, drafts: drafts, trash: trash, archive: archive}
            }
            return updated
        })
        accountConfigSaved(transaction)
        return true
    }
    property string folderId: ""
    property string folderName: "Inbox"
    property bool foldersLoading: false
    property bool foldersLoaded: false
    property string foldersError: ""
    property string pendingFolderRole: ""
    property var folders: canonicalFolders()
    function loadFolders() {
        if (foldersLoading) return
        record("folders")
        foldersError = ""
        foldersLoading = true
        if (!folders.length) folders = canonicalFolders()
        foldersLoaded = true
        foldersLoading = false
        var next = ({})
        Object.keys(folderCache).forEach(function(key) { next[key] = folderCache[key] })
        next[folderCacheKey()] = {loaded: true, folders: folders.slice()}
        folderCache = next
        retryPendingFolderRole()
    }
    function selectFolder(id) {
        record("folder", id)
        folderId = id
        var folder = folders.find(function(item) { return item.id === id })
        folderName = folder ? folder.name : "Inbox"
        populate()
    }
    function conventionalFolderName(folder) {
        var name = String(folder.name || "").toLowerCase()
        var separator = name.lastIndexOf("/")
        return separator >= 0 ? name.slice(separator + 1) : name
    }
    function retryPendingFolderRole() {
        if (!pendingFolderRole || !foldersLoaded) return
        var role = pendingFolderRole
        pendingFolderRole = ""
        selectFolderRole(role)
    }
    function selectFolderRole(role) {
        if (["inbox", "sent", "archive", "trash"].indexOf(role) < 0) return false
        record("role", role)
        if (!foldersLoaded) {
            pendingFolderRole = role
            loadFolders()
            return true
        }
        var folder = resolveFolderRole(role)
        if (folder) { selectFolder(folder.id); return true }
        if (role === "inbox" && !foldersError) { selectFolder(""); return true }
        return false
    }
    function resolveFolderRole(role) {
        foldersError = ""
        if (["inbox", "sent", "archive", "trash"].indexOf(role) < 0) return null
        if (!foldersLoaded) {
            loadFolders()
            foldersError = "Loading folders. Retry the action when discovery finishes."
            return null
        }
        var matches = folders.filter(function(item) { return item.role === role })
        if (!matches.length) {
            var names = {inbox: ["inbox"], sent: ["sent", "sent mail", "sent items", "sent messages"],
                         archive: ["archive", "archives", "all mail"], trash: ["trash", "deleted items", "deleted messages"]}
            matches = folders.filter(function(item) {
                return !item.role && names[role].indexOf(conventionalFolderName(item)) >= 0
            })
        }
        if (matches.length === 1) return matches[0]
        if (!matches.length && role === "inbox") return null
        foldersError = matches.length ? "More than one " + role + " folder is available. Choose a folder."
                                      : "No known " + role + " folder is available."
        return null
    }
    function moveMessageToRole(id, role) { return moveMessagesToRole([id], role) }
    function moveMessagesToRole(ids, role) {
        var folder = resolveFolderRole(role)
        return folder && folder.id !== folderId ? moveMessages(ids, folder.id) : false
    }
    property bool loading: false
    property bool reading: false
    property bool marking: false
    property int listRequest: 0
    property int readRequest: 0
    property bool deleting: false
    function deleteMessage(id) {
        record("delete", id)
        fixtures = fixtures.filter(function(row) { return row.id !== id })
        messages = messages.filter(function(row) { return row.id !== id })
        if (selectedId === id) { selectedId = ""; message = null }
        return true
    }
    property bool moving: false
    property int pendingMoves: 0
    property bool movePending: moving || pendingMoves > 0
    property bool movePaused: false
    function retryMoves() { record("retryMoves"); movePaused = false; return true }
    function cancelPendingMoves() { record("cancelMoves"); pendingMoves = 0; movePaused = false; return true }
    function validIds(ids) {
        return Array.isArray(ids) && ids.length > 0 && ids.every(function(id, index) {
            return typeof id === "string" && ids.indexOf(id) === index
                && messages.some(function(row) { return row.id === id })
        })
    }
    function moveMessage(id, destination) { return moveMessages([id], destination) }
    function moveMessages(ids, destination) {
        if (!validIds(ids)) return false
        ids.forEach(function(id) { record("move", id, destination) })
        fixtures = fixtures.filter(function(row) { return ids.indexOf(row.id) < 0 })
        messages = messages.filter(function(row) { return ids.indexOf(row.id) < 0 })
        if (ids.indexOf(selectedId) >= 0) { selectedId = ""; message = null }
        return true
    }
    property bool savingAttachment: false
    property bool openingAttachment: false
    property string attachmentStatus: ""
    function cancelAttachmentOpen() {}
    function saveAttachment(id, openAfter) { record(openAfter ? "openAttachment" : "saveAttachment", id) }
    property string listError: ""
    property string readError: ""
    property string actionError: ""
    property var messages: []
    property var message: null
    property string selectedId: ""
    property int page: 1
    readonly property bool hasNext: page === 1
    property bool loadingMore: false
    property string loadMoreError: ""
    property bool newMessagesAvailable: false
    property int cacheFreshMs: 120000
    function applyNewestMessages() { newMessagesAvailable = false; return true }
    readonly property int unread: messages.filter(function(m) { return m.unread }).length
    property var calls: []
    property var fixtures: []
    property bool deferReads: false
    property string pendingReadId: ""

    function record(operation, id, seen) {
        calls = calls.concat([{operation: operation, id: id || "", seen: seen, account: account}])
    }
    function populate() {
        var rows = []
        for (var i = 0; i < 63; i++)
            rows.push({id: account + "/" + (i + 1), from: "Offline sender", to: "Offline recipient",
                       subject: "Fixture " + (i + 1), date: "2026-01-01", unread: true})
        fixtures = rows
        page = 1
        selectedId = ""
        message = null
        messages = fixtures.slice(0, 50)
    }
    function refresh() { record("refresh"); messages = fixtures.slice(0, page * 50) }
    // Guards intentionally belong to Widget in these tests: do not hide UI bugs.
    function readMessage(id) {
        if (reading) return
        record("read", id)
        selectedId = id
        if (deferReads) {
            pendingReadId = id
            message = null
            reading = true
            return
        }
        publishRead(id)
    }
    function publishRead(id) {
        var body = ""
        for (var i = 0; i < 180; i++) body += "Long offline message line " + i + "\n"
        message = {id: id, subject: "Long fixture", from: "Sender", to: "Recipient", date: "today", body: body}
    }
    function finishRead() {
        var id = pendingReadId
        pendingReadId = ""
        reading = false
        if (id) publishRead(id)
    }
    function loadMore() {
        record("loadMore")
        if (!hasNext || loadingMore) return false
        page++
        messages = fixtures.slice(0, 100)
        return true
    }
    function retryLoadMore() { return loadMore() }
    function nextPage() { return loadMore() }
    function previousPage() {}
    function setRead(id, seen) { return setReadMany([id], seen) }
    function setReadMany(ids, seen) {
        if (!validIds(ids)) return false
        ids.forEach(function(id) { record("mark", id, seen) })
        fixtures = fixtures.map(function(row) {
            if (ids.indexOf(row.id) < 0) return row
            return {id: row.id, from: row.from, to: row.to, subject: row.subject, date: row.date, unread: !seen}
        })
        messages = fixtures.slice(0, page * 50)
        return true
    }
    function resetFixture() {
        generation = 0
        folderCache = ({})
        accountLabels = ({alpha: "Personal", beta: "Work"})
        accountOverview = []
        accountOverviewLoading = false
        accountOverviewError = ""
        accountLabelSaving = false
        accountConfigSaving = false
        accountConfigBlocked = false
        accountConfigRefreshPending = false
        accountConfigFenceToken = ""
        folderId = ""
        folderName = "Inbox"
        foldersLoading = false
        foldersLoaded = false
        foldersError = ""
        pendingFolderRole = ""
        folders = canonicalFolders()
        loading = false
        reading = false
        marking = false
        listRequest = 0
        readRequest = 0
        deleting = false
        moving = false
        pendingMoves = 0
        movePaused = false
        savingAttachment = false
        openingAttachment = false
        attachmentStatus = ""
        listError = ""
        readError = ""
        actionError = ""
        page = 1
        loadingMore = false
        loadMoreError = ""
        newMessagesAvailable = false
        deferReads = false
        pendingReadId = ""
        calls = []
        populate()
        calls = []
    }
    onAccountChanged: { pendingFolderRole = ""; folderId = ""; folderName = "Inbox"; restoreFolders(false); foldersError = ""; populate() }
    Component.onCompleted: populate()
}
