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
        accountLabel = account || "Default account"
        // In-flight results are discarded; refresh after they finish.
        Qt.callLater(refresh)
    }

    function refresh() {
        if (!ready || !active || loading) return
        listError = ""
        listGeneration = generation
        loading = true
        listRequest++
        listProcess.command = command("list")
        listProcess.running = true
    }

    function readMessage(id) {
        if (!active || reading) return
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
                root.messages = data.messages
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
                if (root.readGeneration === root.generation)
                    root.readError = "Could not launch Python 3. Check that python3 is installed and on PATH."
            })
        }
        onExited: function(code, status) {
            root.reading = false
            if (root.readGeneration !== root.generation) return
            try { root.message = root.result(readOutput.text, code) }
            catch (e) { root.readError = e.message }
        }
    }
}
