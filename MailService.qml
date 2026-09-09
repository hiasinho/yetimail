import QtQuick
import Quickshell.Io

Item {
    id: root
    property bool active: true
    property string account: ""
    property string config: ""
    property bool demo: false
    property var messages: []
    property var message: null
    property string selectedId: ""
    property string listError: ""
    property string readError: ""
    property string actionError: ""
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
        return args
    }

    function reset() {
        generation++
        messages = []
        message = null
        selectedId = ""
        listError = ""
        readError = ""
        actionError = ""
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

    onActiveChanged: reset()
    onAccountChanged: reset()
    onConfigChanged: reset()
    onDemoChanged: reset()

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
