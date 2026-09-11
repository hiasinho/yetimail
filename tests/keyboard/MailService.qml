import QtQuick

// Deliberately no Process/import of production service, helper, or account files.
Item {
    property bool active: false
    property string account: ""
    property string config: ""
    property int generation: 0
    property var folderCache: ({})
    function folderCacheKey() { return JSON.stringify([String(config), String(account), !!demo]) }
    function restoreFolders(clearCache) {
        if (clearCache) folderCache = ({})
        var entry = folderCache[folderCacheKey()]
        foldersLoaded = !!(entry && entry.loaded)
        if (foldersLoaded) folders = entry.folders.slice()
    }
    onConfigChanged: { generation++; restoreFolders(true) }
    property bool demo: false
    readonly property string accountLabel: account || "Fixture"
    property var accountLabels: ({alpha: "Personal", beta: "Work"})
    property var accountOverview: []
    property bool accountOverviewLoading: false
    property string accountOverviewError: ""
    property bool accountLabelSaving: false
    function loadAccountLabels() {}
    function loadAccountOverview() {
        record("accounts")
        accountOverview = [
            {id: "alpha", label: accountLabels.alpha || "", email: "alpha@example.test", "display-name": "Alpha Sender", default: true, receiving: ["imap"], sending: ["smtp"]},
            {id: "beta", label: accountLabels.beta || "", email: "beta@example.test", "display-name": "Beta Sender", default: false, receiving: ["jmap"], sending: ["jmap"]},
            {id: "configured-only", label: "", email: "extra@example.test", "display-name": "Extra Sender", default: false, receiving: ["imap"], sending: []}
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
    property string folderId: ""
    property string folderName: "Inbox"
    property bool foldersLoading: false
    property bool foldersLoaded: false
    property string foldersError: ""
    property var folders: [
        {id: "INBOX", name: "Inbox", role: "inbox"},
        {id: "Sent", name: "Sent mail", role: "sent"},
        {id: "Archive", name: "Archive", role: "archive"},
        {id: "Trash", name: "Trash", role: "trash"},
        {id: "Projects/2026", name: "Projects / 2026", role: ""}
    ]
    function loadFolders() {
        record("folders")
        foldersError = ""
        foldersLoaded = true
        var next = ({})
        Object.keys(folderCache).forEach(function(key) { next[key] = folderCache[key] })
        next[folderCacheKey()] = {loaded: true, folders: folders.slice()}
        folderCache = next
    }
    function selectFolder(id) {
        record("folder", id)
        folderId = id
        var folder = folders.find(function(item) { return item.id === id })
        folderName = folder ? folder.name : "Inbox"
        populate()
    }
    function selectFolderRole(role) {
        record("role", role)
        var folder = folders.find(function(item) { return item.role === role })
        if (folder) selectFolder(folder.id)
        else foldersError = "Folder role unavailable: " + role
    }
    function resolveFolderRole(role) {
        var matches = folders.filter(function(item) { return item.role === role })
        return matches.length === 1 ? matches[0] : null
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
    readonly property int unread: messages.filter(function(m) { return m.unread }).length
    property var calls: []
    property var fixtures: []

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
    function refresh() { record("refresh"); messages = fixtures.slice((page - 1) * 50, page * 50) }
    // Guards intentionally belong to Widget in these tests: do not hide UI bugs.
    function readMessage(id) {
        record("read", id)
        selectedId = id
        var body = ""
        for (var i = 0; i < 180; i++) body += "Long offline message line " + i + "\n"
        message = {id: id, subject: "Long fixture", from: "Sender", to: "Recipient", date: "today", body: body}
    }
    function nextPage() {
        record("next")
        if (!hasNext) return
        page++
        selectedId = ""
        message = null
        messages = fixtures.slice(50)
    }
    function previousPage() {
        record("previous")
        if (page === 1) return
        page--
        selectedId = ""
        message = null
        messages = fixtures.slice(0, 50)
    }
    function setRead(id, seen) { return setReadMany([id], seen) }
    function setReadMany(ids, seen) {
        if (!validIds(ids)) return false
        ids.forEach(function(id) { record("mark", id, seen) })
        fixtures = fixtures.map(function(row) {
            if (ids.indexOf(row.id) < 0) return row
            return {id: row.id, from: row.from, to: row.to, subject: row.subject, date: row.date, unread: !seen}
        })
        messages = fixtures.slice((page - 1) * 50, page * 50)
        return true
    }
    onAccountChanged: { folderId = ""; folderName = "Inbox"; restoreFolders(false); foldersError = ""; populate() }
    Component.onCompleted: populate()
}
