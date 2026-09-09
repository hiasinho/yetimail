import QtQuick

// Deliberately no Process/import of production service, helper, or account files.
Item {
    property bool active: false
    property string account: ""
    property string config: ""
    property int generation: 0
    onConfigChanged: generation++
    property bool demo: false
    readonly property string accountLabel: account || "Fixture"
    property string folderId: ""
    property string folderName: "Inbox"
    property bool foldersLoading: false
    property string foldersError: ""
    property var folders: [
        {id: "INBOX", name: "Inbox", role: "inbox"},
        {id: "Sent", name: "Sent mail", role: "sent"},
        {id: "Archive", name: "Archive", role: "archive"},
        {id: "Trash", name: "Trash", role: "trash"},
        {id: "Projects/2026", name: "Projects / 2026", role: ""}
    ]
    function loadFolders() { record("folders"); foldersError = "" }
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
    property bool loading: false
    property bool reading: false
    property bool marking: false
    property bool moving: false
    function moveMessage(id, destination) {
        record("move", id, destination)
        fixtures = fixtures.filter(function(row) { return row.id !== id })
        messages = messages.filter(function(row) { return row.id !== id })
        if (selectedId === id) { selectedId = ""; message = null }
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
    function setRead(id, seen) {
        record("mark", id, seen)
        fixtures = fixtures.map(function(row) {
            if (row.id !== id) return row
            return {id: row.id, from: row.from, to: row.to, subject: row.subject, date: row.date, unread: !seen}
        })
        messages = fixtures.slice((page - 1) * 50, page * 50)
    }
    onAccountChanged: { folderId = ""; folderName = "Inbox"; foldersError = ""; populate() }
    Component.onCompleted: populate()
}
