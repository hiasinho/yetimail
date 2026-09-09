import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

BarWidget {
    id: root
    moduleName: "hiasinho.jitsmail"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    property bool opened: false
    // An explicit allowlist avoids discovering/querying unrelated accounts.
    readonly property var accounts: String(setting("accounts", "")).split(",").map(function(name) {
        return name.trim()
    }).filter(function(name, index, names) { return name !== "" && names.indexOf(name) === index })
    property string selectedAccount: ""
    readonly property string currentAccount: {
        var preferred = String(setting("account", ""))
        if (!accounts.length) return preferred
        if (accounts.indexOf(selectedAccount) !== -1) return selectedAccount
        return accounts.indexOf(preferred) !== -1 ? preferred : accounts[0]
    }
    property string pane: "list"
    property string cursorId: ""
    property bool showHelp: false
    property bool showLinks: false
    property int linkIndex: 0
    readonly property var messageLinks: mail.message && Array.isArray(mail.message.links) ? mail.message.links : []
    readonly property var selectedLink: messageLinks[linkIndex] || null
    property var openUrl: function(url) { return Qt.openUrlExternally(url) }

    function toggleLinks() {
        if (showHelp || !mail.message || busy) return
        pane = "reader"
        showLinks = !showLinks
        if (showLinks) linkList.forceActiveFocus()
        else messageText.forceActiveFocus()
    }
    function moveLink(delta) {
        linkIndex = Math.max(0, Math.min(messageLinks.length - 1, linkIndex + delta))
        if (linkIndex >= 0) linkList.positionViewAtIndex(linkIndex, ListView.Contain)
    }
    function openLink() {
        if (showHelp || !showLinks || !selectedLink || busy) return
        // Defense in depth: only explicit browser navigation, never shell/HTML.
        if (/^https?:\/\/[^\s/]+(?:[/?#]|$)/i.test(selectedLink.url)) openUrl(selectedLink.url)
    }
    readonly property int cursorIndex: mail.messages.findIndex(function(m) { return m.id === root.cursorId })
    readonly property string targetId: pane === "reader" ? mail.selectedId : cursorId
    readonly property var targetEnvelope: mail.messages.find(function(m) { return m.id === root.targetId }) || null
    readonly property bool busy: mail.loading || mail.reading || mail.marking

    function selectAccount(name) {
        if (accounts.indexOf(name) !== -1 && !mail.marking) selectedAccount = name
    }
    function moveAccount(delta) {
        if (accounts.length < 2) return
        var index = accounts.indexOf(currentAccount)
        selectAccount(accounts[(index + delta + accounts.length) % accounts.length])
    }
    function close() { opened = false }
    function focusList() { showLinks = false; pane = "list"; inbox.forceActiveFocus() }
    function back() {
        if (showLinks) { showLinks = false; messageText.forceActiveFocus() }
        else focusList()
    }
    function syncCursor() {
        if (cursorIndex < 0) cursorId = mail.messages.length ? mail.messages[0].id : ""
        Qt.callLater(function() {
            if (root.cursorIndex >= 0) inbox.positionViewAtIndex(root.cursorIndex, ListView.Contain)
        })
    }
    function moveCursor(delta) {
        if (!mail.messages.length) return
        var index = Math.max(0, Math.min(mail.messages.length - 1, cursorIndex + delta))
        cursorId = mail.messages[index].id
        inbox.positionViewAtIndex(index, ListView.Contain)
    }
    function scrollReader(delta) {
        var view = reader.contentItem
        view.contentY = Math.max(0, Math.min(Math.max(0, view.contentHeight - view.height), view.contentY + delta))
    }
    function navigate(delta) {
        if (showHelp) return
        if (showLinks) moveLink(delta)
        else if (pane === "reader") scrollReader(delta * 42)
        else moveCursor(delta)
    }
    function jump(last) {
        if (showHelp) return
        if (showLinks) moveLink(last ? messageLinks.length : -messageLinks.length)
        else if (pane === "reader") scrollReader(last ? 1000000000 : -1000000000)
        else if (mail.messages.length) moveCursor(last ? mail.messages.length : -mail.messages.length)
    }
    function halfPage(delta) {
        if (showHelp) return
        if (showLinks) moveLink(delta * 5)
        else if (pane === "reader") scrollReader(delta * reader.availableHeight / 2)
        else moveCursor(delta * Math.max(1, Math.floor(inbox.height / 86 / 2)))
    }
    function openCurrent() {
        if (!cursorId || busy) return
        mail.readMessage(cursorId)
        pane = "reader"
        messageText.forceActiveFocus()
    }
    function switchPane() {
        if (pane === "reader") focusList()
        else if (mail.selectedId) { pane = "reader"; messageText.forceActiveFocus() }
        else openCurrent()
    }
    function markCurrent(seen) {
        if (!targetEnvelope || busy || showHelp || targetEnvelope.unread === !seen) return
        mail.setRead(targetId, seen)
    }
    function handleEscape() {
        if (showHelp) showHelp = false
        else if (pane === "reader") back()
        else close()
    }
    onCurrentAccountChanged: { cursorId = ""; pane = "list" }
    onOpenedChanged: if (opened) { showHelp = false; Qt.callLater(focusList) }

    MailService {
        id: mail
        active: root.bar !== null || demo
        account: root.currentAccount
        config: String(root.setting("config", ""))
        demo: root.setting("demo", false) === true
    }
    Connections {
        target: mail
        function onMessagesChanged() { root.syncCursor() }
        function onMessageChanged() { root.showLinks = false; root.linkIndex = 0 }
        function onSelectedIdChanged() { if (!mail.selectedId) root.pane = "list" }
    }
    Timer {
        interval: Math.max(30, Number(root.setting("refreshSeconds", 120)) || 120) * 1000
        running: true
        repeat: true
        onTriggered: mail.refresh()
    }
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "✉" + (mail.listError ? " !" : mail.unread ? " " + mail.unread : "")
        tooltipText: "Jitsmail · " + mail.accountLabel + " · " + (mail.listError ? "Refresh failed" : mail.unread + " unread on page " + mail.page)
        onPressed: { root.opened = !root.opened; if (root.opened) mail.refresh() }
    }
    KeyboardPanel {
        id: panel
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        contentWidth: Math.max(1, Math.min(940, availableCardWidth - padding * 2))
        contentHeight: Math.max(1, Math.min(640, availableCardHeight - padding * 2))
        focusTarget: inbox

        FocusScope {
            id: content
            anchors.fill: parent
            // Window shortcuts also work when the selectable message TextArea
            // or a header button owns focus; they don't depend on key bubbling.
            Shortcut { sequences: ["J", "Down"]; enabled: root.opened; onActivated: root.navigate(1) }
            Shortcut { sequences: ["K", "Up"]; enabled: root.opened; onActivated: root.navigate(-1) }
            Shortcut { sequences: ["Return", "Enter", "L", "Right"]; enabled: root.opened && root.pane === "list"; onActivated: root.openCurrent() }
            Shortcut { sequences: ["H", "Left"]; enabled: root.opened; onActivated: root.back() }
            Shortcut { sequence: "O"; enabled: root.opened; onActivated: root.toggleLinks() }
            Shortcut { sequences: ["Return", "Enter", "L", "Right"]; enabled: root.opened && root.showLinks; autoRepeat: false; onActivated: root.openLink() }
            Shortcut { sequence: "G, G"; enabled: root.opened; onActivated: root.jump(false) }
            Shortcut { sequence: "Shift+G"; enabled: root.opened; onActivated: root.jump(true) }
            Shortcut { sequence: "Ctrl+D"; enabled: root.opened; onActivated: root.halfPage(1) }
            Shortcut { sequence: "Ctrl+U"; enabled: root.opened; onActivated: root.halfPage(-1) }
            Shortcut { sequences: ["Tab", "Shift+Tab"]; enabled: root.opened; onActivated: root.switchPane() }
            Shortcut { sequence: "N"; enabled: root.opened && !root.busy; onActivated: mail.nextPage() }
            Shortcut { sequence: "P"; enabled: root.opened && !root.busy; onActivated: mail.previousPage() }
            Shortcut { sequence: "["; enabled: root.opened; onActivated: root.moveAccount(-1) }
            Shortcut { sequence: "]"; enabled: root.opened; onActivated: root.moveAccount(1) }
            Shortcut { sequence: "M"; autoRepeat: false; enabled: root.opened; onActivated: root.markCurrent(true) }
            Shortcut { sequence: "U"; autoRepeat: false; enabled: root.opened; onActivated: root.markCurrent(false) }
            Shortcut { sequences: ["R", "Ctrl+R"]; enabled: root.opened; onActivated: mail.refresh() }
            Shortcut { sequence: "?"; enabled: root.opened; onActivated: root.showHelp = !root.showHelp }
            Shortcut { sequence: "Escape"; enabled: root.opened; onActivated: root.handleEscape() }
            Shortcut { sequence: "Q"; enabled: root.opened; onActivated: root.close() }

            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Jitsmail / Inbox" + (mail.demo ? " · Demo" : "")
                        color: Color.foreground
                        font.bold: true
                        font.pixelSize: 18
                        textFormat: Text.PlainText
                    }
                    Text { Layout.fillWidth: true; text: mail.accountLabel; color: Color.foreground; opacity: 0.65; elide: Text.ElideRight; textFormat: Text.PlainText }
                    Button { text: mail.loading ? "Refreshing…" : "Refresh"; enabled: !root.busy; focusable: true; onClicked: mail.refresh() }
                    Button { text: "?"; focusable: true; onClicked: root.showHelp = !root.showHelp }
                    Button { text: "Close"; focusable: true; onClicked: root.close() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.accounts.length > 1
                    spacing: 6
                    Repeater {
                        model: root.accounts
                        Button {
                            required property string modelData
                            text: modelData
                            selected: root.currentAccount === modelData
                            enabled: !mail.marking
                            focusable: true
                            onClicked: root.selectAccount(modelData)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text { text: "[ / ] switch account"; color: Color.foreground; opacity: 0.55 }
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.showHelp
                    text: "LIST: j/k or ↓/↑ select · Enter/l/→ open · gg/G first/last\nREADER: j/k scroll · Ctrl+d/u half-page · gg/G top/bottom · h/← back\nLINKS: o shows destinations · j/k select · Enter opens in browser · h back\nTab switches panes · n/p next/previous page · [/] accounts\nm mark read · u mark unread · r refresh · ? help · q close\nEsc closes help, returns to list, then closes panel. Ctrl+C copies selected text."
                    color: Color.foreground
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    visible: mail.listError !== "" || mail.actionError !== ""
                    text: mail.actionError || mail.listError
                    color: Color.foreground
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 14
                    ColumnLayout {
                        Layout.preferredWidth: Math.min(310, content.width * 0.38)
                        Layout.fillHeight: true
                        Text {
                            Layout.fillWidth: true
                            text: (root.pane === "list" ? "▸ " : "") + "Page " + mail.page + " · " + mail.unread + " unread here" + (mail.listError ? " · stale" : "")
                            color: root.pane === "list" ? Color.accent : Color.foreground
                            textFormat: Text.PlainText
                        }
                        ListView {
                            id: inbox
                            onActiveFocusChanged: if (activeFocus) root.pane = "list"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 4
                            model: mail.messages
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Rectangle {
                                required property var modelData
                                width: inbox.width
                                height: 82
                                radius: 5
                                color: modelData.id === root.cursorId ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07) : "transparent"
                                border.width: modelData.id === root.cursorId && root.pane === "list" ? 1 : 0
                                border.color: Color.accent
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 4
                                    Text { width: parent.width; text: (modelData.unread ? "● " : "") + modelData.from; color: Color.foreground; font.bold: modelData.unread; elide: Text.ElideRight; textFormat: Text.PlainText }
                                    Text { width: parent.width; text: modelData.subject || "(No subject)"; color: Color.foreground; elide: Text.ElideRight; textFormat: Text.PlainText }
                                    Text { width: parent.width; text: modelData.date; color: Color.foreground; opacity: 0.55; font.pixelSize: 11; elide: Text.ElideRight; textFormat: Text.PlainText }
                                }
                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !root.busy
                                    onClicked: { root.cursorId = modelData.id; root.openCurrent() }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width
                                visible: mail.messages.length === 0
                                text: mail.loading ? "Loading inbox…" : mail.listError ? "Inbox unavailable" : "No messages on this page."
                                color: Color.foreground
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Button { text: "‹ Newer (p)"; enabled: mail.page > 1 && !root.busy; focusable: true; onClicked: mail.previousPage() }
                            Item { Layout.fillWidth: true }
                            Button { text: "Older (n) ›"; enabled: mail.hasNext && !root.busy; focusable: true; onClicked: mail.nextPage() }
                        }
                    }
                    Rectangle { Layout.fillHeight: true; width: 1; color: Color.foreground; opacity: 0.15 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: root.pane === "reader" ? "▸ Reader" : "Reader"; color: root.pane === "reader" ? Color.accent : Color.foreground }
                            Button { text: "Links (o)"; enabled: !!mail.message && !root.busy; focusable: true; onClicked: root.toggleLinks() }
                            Button { text: "Read (m)"; enabled: !!root.targetEnvelope && root.targetEnvelope.unread && !root.busy; focusable: true; onClicked: root.markCurrent(true) }
                            Button { text: "Unread (u)"; enabled: !!root.targetEnvelope && !root.targetEnvelope.unread && !root.busy; focusable: true; onClicked: root.markCurrent(false) }
                        }
                        ColumnLayout {
                            visible: root.showLinks
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Text { text: "Links · j/k select · Enter opens in browser · h back"; color: Color.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            ListView {
                                id: linkList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: 4
                                model: root.messageLinks
                                ScrollBar.vertical: ScrollBar {}
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    width: linkList.width
                                    height: 56
                                    radius: 4
                                    color: index === root.linkIndex ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
                                    border.width: index === root.linkIndex ? 1 : 0
                                    border.color: Color.accent
                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        Text { width: parent.width; text: "[" + (index + 1) + "] " + modelData.label; textFormat: Text.PlainText; color: Color.foreground; elide: Text.ElideRight }
                                        Text { width: parent.width; text: modelData.url; textFormat: Text.PlainText; color: Color.foreground; opacity: 0.65; elide: Text.ElideMiddle }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: { root.linkIndex = index; linkList.forceActiveFocus() } }
                                }
                                Text { anchors.centerIn: parent; visible: !root.messageLinks.length; text: "No web links in this message."; color: Color.foreground }
                            }
                            Text { text: "Destination (may contain tracking):"; color: Color.foreground; visible: !!root.selectedLink }
                            ScrollView {
                                id: linkPreview
                                contentWidth: availableWidth
                                Layout.fillWidth: true
                                Layout.preferredHeight: 100
                                visible: !!root.selectedLink
                                clip: true
                                TextArea {
                                    width: linkPreview.availableWidth
                                    text: root.selectedLink ? root.selectedLink.url : ""
                                    textFormat: TextEdit.PlainText
                                    readOnly: true
                                    selectByMouse: true
                                    wrapMode: TextEdit.WrapAnywhere
                                    color: Color.foreground
                                    background: null
                                }
                            }
                            Button { text: "Open in browser (Enter)"; enabled: !!root.selectedLink && !root.busy; focusable: true; onClicked: root.openLink() }
                        }
                        ScrollView {
                            id: reader
                            objectName: "messageReader"
                            visible: !root.showLinks
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth
                            TextArea {
                                id: messageText
                                objectName: "messageBody"
                                width: reader.availableWidth
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                color: Color.foreground
                                background: null
                                font.pixelSize: 14
                                onActiveFocusChanged: if (activeFocus && mail.selectedId) root.pane = "reader"
                                text: mail.reading ? "Loading message…" : mail.readError ? mail.readError : mail.message ?
                                    (mail.message.subject || "(No subject)") + "\n\nFrom: " + mail.message.from + "\nTo: " + mail.message.to + "\nDate: " + mail.message.date + "\n\n" + mail.message.body :
                                    "Select a message with j/k, then press Enter to read.\n\nOpening a message does not mark it as read. Use m / u to change its status."
                                onTextChanged: { cursorPosition = 0; reader.contentItem.contentY = 0 }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: mail.marking ? "Updating message status…" : "o links · j/k navigate · Enter open · h back · n/p pages · m/u read/unread · ? help · q close"
                    color: Color.foreground
                    opacity: 0.65
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
