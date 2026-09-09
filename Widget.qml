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
    property bool showHeaders: false
    property bool showAttachments: false
    property int attachmentIndex: 0
    readonly property var selectedAttachment: messageAttachments[attachmentIndex] || null
    function moveAttachment(delta) {
        attachmentIndex = Math.max(0, Math.min(messageAttachments.length - 1, attachmentIndex + delta))
    }
    function attachmentAction(openAfter) {
        if (!opened || showHelp || !showAttachments || !selectedAttachment || busy) return
        mail.saveAttachment(selectedAttachment.id, openAfter)
    }
    readonly property var messageAttachments: mail.message && Array.isArray(mail.message.attachments) ? mail.message.attachments : []
    function attachmentSize(size) {
        if (typeof size !== "number" || !isFinite(size) || size < 0) return "Unknown size"
        if (size < 1024) return size + " B"
        var units = ["KiB", "MiB", "GiB", "TiB"]
        var value = size / 1024
        var unit = 0
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++ }
        return value.toFixed(1) + " " + units[unit]
    }
    function attachmentMetadata(attachment) {
        var size = attachmentSize(attachment.size)
        return "Name: " + (attachment.name || "Unnamed attachment") + "\nType: " + (attachment.type || "Unknown type") +
            "\nSize: " + size + (typeof attachment.size === "number" && isFinite(attachment.size) && attachment.size >= 1024 ? " (" + attachment.size + " bytes)" : "")
    }
    function toggleAttachments() {
        if (showHelp || !mail.message || busy) return
        showAttachments = !showAttachments
        showLinks = false
        showHeaders = false
        pane = "reader"
        messageText.forceActiveFocus()
    }
    property int linkIndex: 0
    readonly property var messageLinks: mail.message && Array.isArray(mail.message.links) ? mail.message.links : []
    readonly property var selectedLink: messageLinks[linkIndex] || null
    property var openUrl: function(url) { return Qt.openUrlExternally(url) }

    // Keep the panel on the shell's configured monospace font, not Qt's UI font.
    component MailLabel: Text {
        font.family: Style.font.family
        font.pixelSize: 12
        color: Color.foreground
        textFormat: Text.PlainText
    }
    component MailButton: Button {
        fontFamily: Style.font.family
        fontSize: 11
        horizontalPadding: 6
        verticalPadding: 4
        radius: 0
        focusable: true
    }
    function senderName(from) {
        var value = String(from || "")
        var name = value.replace(/\s*<[^>]*>\s*$/, "").trim().replace(/^"(.*)"$/, "$1")
        return name || senderAddress(value) || "Unknown sender"
    }
    function senderAddress(from) {
        var value = String(from || "")
        var match = value.match(/<([^>]+)>/)
        return match ? match[1] : value.indexOf("@") !== -1 ? value : ""
    }
    function shortDate(value) {
        var date = new Date(value)
        if (isNaN(date.getTime())) return String(value || "")
        return Qt.formatDateTime(date, date.toDateString() === new Date().toDateString() ? "HH:mm" : "MMM d")
    }

    function headerDate(value) {
        var date = new Date(value)
        return isNaN(date.getTime()) ? String(value || "") : Qt.formatDateTime(date, "MMM d  HH:mm")
    }
    function toggleHeaders() {
        if (showHelp || !mail.message || busy) return
        showHeaders = !showHeaders
        showLinks = false
        showAttachments = false
        pane = "reader"
        messageText.forceActiveFocus()
    }
    function toggleLinks() {
        if (showHelp || !mail.message || busy) return
        pane = "reader"
        showLinks = !showLinks
        showHeaders = false
        showAttachments = false
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
    readonly property var displayedEnvelope: mail.messages.find(function(m) { return m.id === mail.selectedId }) || null
    readonly property bool busy: mail.loading || mail.reading || mail.marking || mail.savingAttachment || mail.openingAttachment

    function selectAccount(name) {
        if (accounts.indexOf(name) !== -1 && !mail.marking) selectedAccount = name
    }
    function moveAccount(delta) {
        if (accounts.length < 2) return
        var index = accounts.indexOf(currentAccount)
        selectAccount(accounts[(index + delta + accounts.length) % accounts.length])
    }
    function close() { opened = false }
    function focusList() { showLinks = false; showAttachments = false; pane = "list"; inbox.forceActiveFocus() }
    function back() {
        if (showAttachments) { showAttachments = false; messageText.forceActiveFocus() }
        else if (showLinks) { showLinks = false; messageText.forceActiveFocus() }
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
        if (showAttachments) moveAttachment(delta)
        else if (showLinks) moveLink(delta)
        else if (pane === "reader") scrollReader(delta * 42)
        else moveCursor(delta)
    }
    function jump(last) {
        if (showHelp) return
        if (showAttachments) moveAttachment(last ? messageAttachments.length : -messageAttachments.length)
        else if (showLinks) moveLink(last ? messageLinks.length : -messageLinks.length)
        else if (pane === "reader") scrollReader(last ? 1000000000 : -1000000000)
        else if (mail.messages.length) moveCursor(last ? mail.messages.length : -mail.messages.length)
    }
    function halfPage(delta) {
        if (showHelp) return
        if (showLinks) moveLink(delta * 5)
        else if (pane === "reader") scrollReader(delta * reader.availableHeight / 2)
        else moveCursor(delta * Math.max(1, Math.floor(inbox.height / 68 / 2)))
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
    function markCurrent(seen) { markMessage(targetId, seen) }
    function markMessage(id, seen) {
        var envelope = mail.messages.find(function(m) { return m.id === id })
        if (!envelope || busy || showHelp || envelope.unread === !seen) return
        mail.setRead(id, seen)
    }
    function handleEscape() {
        if (showHelp) showHelp = false
        else if (pane === "reader") back()
        else close()
    }
    onCurrentAccountChanged: { cursorId = ""; pane = "list"; showLinks = false; showHeaders = false; showAttachments = false }
    onOpenedChanged: {
        if (opened) { showHelp = false; Qt.callLater(focusList) }
        else mail.cancelAttachmentOpen()
    }

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
        function onMessageChanged() { root.showLinks = false; root.showHeaders = false; root.showAttachments = false; root.linkIndex = 0; root.attachmentIndex = 0 }
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
            Shortcut { sequence: "V"; enabled: root.opened; onActivated: root.toggleHeaders() }
            Shortcut { sequence: "A"; enabled: root.opened; onActivated: root.toggleAttachments() }
            Shortcut { sequence: "S"; autoRepeat: false; enabled: root.opened && root.showAttachments; onActivated: root.attachmentAction(false) }
            Shortcut { sequences: ["Return", "Enter"]; autoRepeat: false; enabled: root.opened && root.showAttachments; onActivated: root.attachmentAction(true) }
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

            RowLayout {
                anchors.fill: parent
                spacing: 16
                ColumnLayout {
                    id: sidebar
                    Layout.preferredWidth: Math.min(310, content.width * 0.35)
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: Layout.preferredWidth
                    Layout.fillHeight: true
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            MailLabel { text: mail.demo ? "MAIL / DEMO" : "MAIL"; font.pixelSize: 10; font.letterSpacing: 1.5; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: mail.unread + " unread"; font.pixelSize: 14 }
                        }
                        MailButton { text: mail.loading ? "…" : "Refresh"; tooltipText: "Refresh (r)"; enabled: !root.busy; onClicked: mail.refresh() }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.accounts.length ? root.accounts : [root.currentAccount || mail.accountLabel]
                            MailButton {
                                required property string modelData
                                width: Math.min(implicitWidth, sidebar.width)
                                clip: true
                                text: modelData
                                bordered: true
                                selected: root.currentAccount === modelData || !root.accounts.length
                                enabled: !mail.marking
                                tooltipText: modelData + " · [ / ] switch account"
                                onClicked: root.selectAccount(modelData)
                            }
                        }
                    }
                        ListView {
                            id: inbox
                            onActiveFocusChanged: if (activeFocus) root.pane = "list"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: mail.messages
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Rectangle {
                                required property var modelData
                                width: inbox.width
                                height: 66
                                radius: 0
                                color: modelData.id === root.cursorId ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14) : mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07) : "transparent"
                                MailLabel {
                                    x: 7; y: 9
                                    text: "●"
                                    font.pixelSize: 9
                                    color: Color.accent
                                    visible: modelData.unread
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 22
                                    anchors.rightMargin: 9
                                    anchors.topMargin: 7
                                    anchors.bottomMargin: 7
                                    spacing: 3
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        MailLabel { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.senderName(modelData.from); color: Color.accent; font.bold: modelData.unread; elide: Text.ElideRight }
                                        MailLabel { text: root.shortDate(modelData.date); font.pixelSize: 10; opacity: 0.55; Layout.maximumWidth: 65; elide: Text.ElideRight }
                                    }
                                    MailLabel { Layout.fillWidth: true; text: modelData.subject || "(No subject)"; elide: Text.ElideRight }
                                    MailLabel { Layout.fillWidth: true; text: root.senderAddress(modelData.from); opacity: 0.5; font.pixelSize: 11; elide: Text.ElideRight }
                                }
                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !root.busy
                                    onClicked: { root.cursorId = modelData.id; root.openCurrent() }
                                }
                            }
                            MailLabel {
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
                            MailButton { text: "‹ Newer"; tooltipText: "Previous page (p)"; enabled: mail.page > 1 && !root.busy; onClicked: mail.previousPage() }
                            MailLabel { Layout.fillWidth: true; text: "Page " + mail.page; horizontalAlignment: Text.AlignHCenter; opacity: 0.55; font.pixelSize: 10 }
                            MailButton { text: "Older ›"; tooltipText: "Next page (n)"; enabled: mail.hasNext && !root.busy; onClicked: mail.nextPage() }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            MailLabel { Layout.fillWidth: true; text: mail.marking ? "Updating…" : mail.loading ? "Refreshing…" : mail.listError ? "Refresh failed · stale" : mail.messages.length + " messages on page"; opacity: 0.55; font.pixelSize: 10; elide: Text.ElideRight }
                            MailButton { text: "Shortcuts ?"; selected: root.showHelp; onClicked: root.showHelp = !root.showHelp }
                        }
                    }
                    Rectangle { Layout.fillHeight: true; width: 1; color: Color.foreground; opacity: 0.15 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            MailLabel { Layout.fillWidth: true; Layout.minimumWidth: 0; text: mail.message ? mail.message.subject || "(No subject)" : "Inbox"; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
                            MailButton { text: "≡"; tooltipText: "Full selectable headers (v)"; selected: root.showHeaders; enabled: !!mail.message && !root.busy; onClicked: root.toggleHeaders() }
                            MailButton { text: "📎"; tooltipText: "Attachment metadata (a)"; selected: root.showAttachments; enabled: !!mail.message && !root.busy; onClicked: root.toggleAttachments() }
                            MailButton { text: "↗"; tooltipText: "Show links (o)"; selected: root.showLinks; enabled: !!mail.message && !root.busy; onClicked: root.toggleLinks() }
                            MailButton { objectName: "readerMarkRead"; text: "✓"; tooltipText: "Mark this message read (m)"; enabled: !!mail.message && !!root.displayedEnvelope && root.displayedEnvelope.unread && !root.busy; onClicked: root.markMessage(mail.selectedId, true) }
                            MailButton { objectName: "readerMarkUnread"; text: "●"; tooltipText: "Mark this message unread (u)"; enabled: !!mail.message && !!root.displayedEnvelope && !root.displayedEnvelope.unread && !root.busy; onClicked: root.markMessage(mail.selectedId, false) }
                            MailButton { text: "×"; tooltipText: "Close (q)"; onClicked: root.close() }
                        }
                        MailLabel {
                            Layout.fillWidth: true
                            visible: mail.listError !== "" || mail.actionError !== ""
                            text: [mail.listError, mail.actionError].filter(function(error) { return !!error }).join("\n")
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            color: Color.accent
                        }
                        ColumnLayout {
                            visible: !!mail.message && !mail.reading && !mail.readError && !root.showHeaders
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            Layout.bottomMargin: 8
                            spacing: 4
                            MailLabel { Layout.fillWidth: true; text: mail.accountLabel; opacity: 0.5; font.pixelSize: 11; elide: Text.ElideRight }
                            RowLayout {
                                Layout.fillWidth: true
                                MailLabel { Layout.fillWidth: true; text: mail.message ? root.senderName(mail.message.from) : ""; color: Color.accent; font.bold: true; elide: Text.ElideRight }
                                MailLabel { Layout.maximumWidth: 125; elide: Text.ElideRight; text: mail.message ? root.headerDate(mail.message.date) : ""; opacity: 0.55; font.pixelSize: 11 }
                            }
                            MailLabel { Layout.fillWidth: true; text: mail.message ? "To    " + mail.message.to : ""; opacity: 0.55; font.pixelSize: 11; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight }
                        }
                        ListView {
                            id: attachmentChips
                            objectName: "attachmentChips"
                            visible: !!mail.message && !mail.reading && !mail.readError && root.messageAttachments.length > 0
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredHeight: 36
                            Layout.maximumHeight: 36
                            orientation: ListView.Horizontal
                            spacing: 6
                            clip: true
                            model: root.messageAttachments
                            ScrollBar.horizontal: ScrollBar {}
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: Math.max(0, Math.min(240, attachmentChips.width))
                                height: 26
                                clip: true
                                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07)
                                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 5
                                    spacing: 5
                                    MailLabel { text: "📎"; font.pixelSize: 11 }
                                    MailLabel { Layout.fillWidth: true; Layout.minimumWidth: 0; text: modelData.name || "Unnamed attachment"; elide: Text.ElideMiddle; font.pixelSize: 11 }
                                    MailLabel { text: root.attachmentSize(modelData.size); font.pixelSize: 10; opacity: 0.6 }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.busy) return
                                        if (!root.showAttachments) root.toggleAttachments()
                                        root.attachmentIndex = index
                                    }
                                }
                                HoverHandler { id: attachmentHover }
                                ToolTip {
                                    id: attachmentTooltip
                                    visible: attachmentHover.hovered
                                    delay: 500
                                    text: root.attachmentMetadata(modelData)
                                    font.family: Style.font.family
                                    width: Math.min(400, content.width)
                                    contentItem: MailLabel { text: attachmentTooltip.text; wrapMode: Text.WrapAnywhere }
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.showLinks
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            MailLabel { text: "Links · j/k select · Enter opens in browser · h back"; color: Color.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
                                    height: 48
                                    radius: 0
                                    color: index === root.linkIndex ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
                                    border.width: index === root.linkIndex ? 1 : 0
                                    border.color: Color.accent
                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        MailLabel { width: parent.width; text: "[" + (index + 1) + "] " + modelData.label; textFormat: Text.PlainText; color: Color.foreground; elide: Text.ElideRight }
                                        MailLabel { width: parent.width; text: modelData.url; textFormat: Text.PlainText; color: Color.foreground; opacity: 0.65; elide: Text.ElideMiddle }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: { root.linkIndex = index; linkList.forceActiveFocus() } }
                                }
                                MailLabel { anchors.centerIn: parent; visible: !root.messageLinks.length; text: "No web links in this message."; color: Color.foreground }
                            }
                            MailLabel { text: "Destination (may contain tracking):"; color: Color.foreground; visible: !!root.selectedLink }
                            ScrollView {
                                id: linkPreview
                                contentWidth: availableWidth
                                Layout.fillWidth: true
                                Layout.preferredHeight: 100
                                visible: !!root.selectedLink
                                clip: true
                                TextArea {
                                    font.family: Style.font.family
                                    font.pixelSize: 12
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
                            MailButton { text: "Open in browser (Enter)"; enabled: !!root.selectedLink && !root.busy; focusable: true; onClicked: root.openLink() }
                        }
                        RowLayout {
                            visible: root.showAttachments
                            Layout.fillWidth: true
                            MailButton { text: "‹"; enabled: root.attachmentIndex > 0; onClicked: root.moveAttachment(-1) }
                            MailLabel { text: (root.selectedAttachment ? root.attachmentIndex + 1 : 0) + " / " + root.messageAttachments.length }
                            MailButton { text: "›"; enabled: root.attachmentIndex + 1 < root.messageAttachments.length; onClicked: root.moveAttachment(1) }
                            MailButton { objectName: "saveAttachment"; text: "Save (s)"; enabled: !!root.selectedAttachment && !root.busy; onClicked: root.attachmentAction(false) }
                            MailButton { objectName: "openAttachment"; text: "Open (Enter)"; enabled: !!root.selectedAttachment && !!root.selectedAttachment.openable && !root.busy; onClicked: root.attachmentAction(true) }
                        }
                        MailLabel {
                            visible: root.showAttachments && (mail.savingAttachment || mail.attachmentStatus !== "")
                            Layout.fillWidth: true
                            text: mail.savingAttachment ? "Saving attachment…" : mail.attachmentStatus
                            wrapMode: Text.WrapAnywhere
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
                                font.family: Style.font.family
                                // Native monospace metrics preserve plain-text spacing and copying.
                                font.pixelSize: 13
                                padding: 0
                                onActiveFocusChanged: if (activeFocus && mail.selectedId) root.pane = "reader"
                                text: mail.reading ? "Loading message…" : mail.readError ? mail.readError : mail.message ?
                                    root.showAttachments ? ("Attachments · j/k select · s save · Enter open · h / Esc back\nSaves a unique private file in ~/Downloads. Open also saves a copy.\n\n" +
                                        (root.selectedAttachment ? "[" + (root.attachmentIndex + 1) + "]\n" + root.attachmentMetadata(root.selectedAttachment) +
                                         "\n\n" + (root.selectedAttachment.openable ? "Open with the default application only if you trust this file." : "Save-only type: opening is blocked.") : "No attachments in this message.")) :
                                    (root.showHeaders ? "Subject: " + mail.message.subject + "\nFrom: " + mail.message.from + "\nTo: " + mail.message.to + "\nDate: " + mail.message.date + "\n\n" : "") + mail.message.body :
                                    "Select a message with j/k, then press Enter to read.\n\nOpening a message does not mark it as read. Use m / u to change its status."
                                onTextChanged: { cursorPosition = 0; reader.contentItem.contentY = 0 }
                            }
                        }
                    }
            }
            Rectangle {
                id: helpOverlay
                visible: root.showHelp
                z: 10
                anchors.left: parent.left
                anchors.leftMargin: Math.min(68, parent.width * 0.08)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 32
                width: Math.min(360, parent.width - anchors.leftMargin)
                height: Math.min(helpContent.implicitHeight + 24, parent.height - 40)
                color: Color.background
                border.color: Color.accent
                border.width: 1
                // Help floats over the inbox and never changes pane geometry.
                MouseArea { anchors.fill: parent }
                ScrollView {
                    id: helpScroll
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        id: helpContent
                        width: helpScroll.availableWidth
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            MailLabel { Layout.fillWidth: true; text: "SHORTCUTS"; font.pixelSize: 10; font.letterSpacing: 1.5; opacity: 0.55 }
                            MailButton { text: "×"; tooltipText: "Close help (Esc)"; onClicked: root.showHelp = false }
                        }
                        Repeater {
                            model: [
                                ["j k / ↓ ↑", "Move / scroll"],
                                ["Enter / l / →", "Open message / link"],
                                ["h / ←", "Back to body / list"],
                                ["Tab", "Switch list / reader"],
                                ["gg / G", "First / last"],
                                ["Ctrl+d / u", "Half-page down / up"],
                                ["n / p", "Older / newer page"],
                                ["[ / ]", "Switch account"],
                                ["o", "Show / hide links"],
                                ["v", "Full selectable headers"],
                                ["a", "Attachments: j/k select"],
                                ["s / Enter", "Save / open attachment (in a)"],
                                ["m / u", "Mark read / unread"],
                                ["r", "Refresh inbox"],
                                ["Ctrl+c", "Copy selected text"],
                                ["?", "Toggle shortcuts"],
                                ["Esc", "Dismiss / back / close"],
                                ["q", "Close mail"]
                            ]
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8
                                MailLabel { Layout.preferredWidth: 110; text: modelData[0]; font.pixelSize: 11 }
                                MailLabel { Layout.fillWidth: true; text: modelData[1]; opacity: 0.6; font.pixelSize: 11; wrapMode: Text.Wrap }
                            }
                        }
                    }
                }
            }
        }
    }
}
