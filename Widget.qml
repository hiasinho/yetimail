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
    function selectAccount(name) {
        if (accounts.indexOf(name) !== -1) selectedAccount = name
    }
    function close() { opened = false }

    MailService {
        id: mail
        // The host injects bar/settings after construction. Do not query the
        // default account before those settings have arrived.
        active: root.bar !== null || demo
        account: root.currentAccount
        config: String(root.setting("config", ""))
        demo: root.setting("demo", false) === true
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
        tooltipText: "Jitsmail · " + mail.accountLabel + " · " + (mail.listError ? "Refresh failed" : mail.unread + " unread in latest 50")
        onPressed: {
            root.opened = !root.opened
            if (root.opened) mail.refresh()
        }
    }
    KeyboardPanel {
        id: panel
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        contentWidth: Math.max(1, Math.min(940, availableCardWidth - padding * 2))
        contentHeight: Math.max(1, Math.min(580, availableCardHeight - padding * 2))
        focusTarget: content

        FocusScope {
            id: content
            anchors.fill: parent
            Keys.onEscapePressed: root.close()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_R && event.modifiers & Qt.ControlModifier) {
                    mail.refresh()
                    event.accepted = true
                }
            }
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
                    Text {
                        Layout.fillWidth: true
                        text: mail.accountLabel
                        color: Color.foreground
                        opacity: 0.65
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                    Button { text: mail.loading ? "Refreshing…" : "Refresh"; enabled: !mail.loading; onClicked: mail.refresh() }
                    Button { text: "Close"; onClicked: root.close() }
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
                            focusable: true
                            onClicked: root.selectAccount(modelData)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                Text {
                    Layout.fillWidth: true
                    visible: mail.listError !== ""
                    text: mail.listError + " — Configure your account with `himalaya configure`, then refresh."
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
                            text: "Latest 50 · " + mail.unread + " unread" + (mail.listError ? " · stale" : "")
                            color: Color.foreground
                            opacity: 0.65
                            textFormat: Text.PlainText
                        }
                        ListView {
                            id: inbox
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
                                color: modelData.id === mail.selectedId ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07) : "transparent"
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 4
                                    Text { width: parent.width; text: (modelData.unread ? "● " : "") + modelData.from; color: Color.foreground; font.bold: modelData.unread; elide: Text.ElideRight; textFormat: Text.PlainText }
                                    Text { width: parent.width; text: modelData.subject || "(No subject)"; color: Color.foreground; elide: Text.ElideRight; textFormat: Text.PlainText }
                                    Text { width: parent.width; text: modelData.date; color: Color.foreground; opacity: 0.55; font.pixelSize: 11; elide: Text.ElideRight; textFormat: Text.PlainText }
                                }
                                MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; enabled: !mail.reading; onClicked: mail.readMessage(modelData.id) }
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width
                                visible: mail.messages.length === 0
                                text: mail.loading ? "Loading inbox…" : mail.listError ? "Inbox unavailable" : "Your inbox is empty."
                                color: Color.foreground
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                        }
                    }
                    Rectangle { Layout.fillHeight: true; width: 1; color: Color.foreground; opacity: 0.15 }
                    ScrollView {
                        id: reader
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: availableWidth
                        TextArea {
                            id: messageText
                            width: reader.availableWidth
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            color: Color.foreground
                            background: null
                            font.pixelSize: 14
                            text: mail.reading ? "Loading message…" : mail.readError ? mail.readError : mail.message ?
                                (mail.message.subject || "(No subject)") + "\n\nFrom: " + mail.message.from + "\nTo: " + mail.message.to + "\nDate: " + mail.message.date + "\n\n" + mail.message.body :
                                "Select a message to read.\n\nThis milestone is read-only. Opening a message does not mark it as read."
                            onTextChanged: { cursorPosition = 0; reader.contentItem.contentY = 0 }
                        }
                    }
                }
            }
        }
    }
}
