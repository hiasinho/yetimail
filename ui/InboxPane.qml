import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

ColumnLayout {
    id: view
    required property bool demo
    required property int unread
    required property bool loading
    required property string folderName
    required property string accountLabel
    required property var messages
    required property string listError
    required property int page
    required property bool hasNext
    required property bool deleting
    required property bool moving
    required property bool marking
    required property var icons
    required property bool busy
    required property bool showFolders
    required property bool switchingBlocked
    required property var accounts
    required property string currentAccount
    required property string cursorId
    required property bool showHelp
    signal refreshRequested()
    signal foldersRequested()
    signal accountRequested(string name)
    signal listFocused()
    signal messageRequested(string messageId)
    signal previousRequested()
    signal nextRequested()
    signal helpRequested()
    readonly property point folderAnchor: Qt.point(accountFlow.x + folderButton.x, accountFlow.y + folderButton.y + folderButton.height + 2)
    readonly property real listHeight: inbox.height
    readonly property Item focusTarget: inbox
    function focusList() { inbox.forceActiveFocus() }
    function reveal(index) { inbox.positionViewAtIndex(index, ListView.Contain) }
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

    Layout.fillHeight: true
    spacing: 10
    RowLayout {
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            MailLabel { text: view.demo ? "MAIL / DEMO" : "MAIL"; font.pixelSize: 10; font.letterSpacing: 1.5; opacity: 0.55 }
            MailLabel { Layout.fillWidth: true; text: view.unread + " unread"; font.pixelSize: 14 }
        }
        MailButton { text: view.loading ? "…" : "Refresh"; iconText: view.loading ? "" : view.icons.refresh; tooltipText: "Refresh (r)"; enabled: !view.busy; onClicked: view.refreshRequested() }
    }
    Flow {
        id: accountFlow
        Layout.fillWidth: true
        spacing: 6
        MailButton {
            id: folderButton
            objectName: "folderButton"
            iconText: view.icons.inbox
            tooltipText: view.folderName + " · Choose folder (f)"
            bordered: true
            selected: view.showFolders
            enabled: !view.switchingBlocked
            onClicked: view.foldersRequested()
        }
        Repeater {
            model: view.accounts.length ? view.accounts : [view.currentAccount || view.accountLabel]
            MailButton {
                required property string modelData
                width: Math.min(implicitWidth, view.width)
                clip: true
                text: modelData
                bordered: true
                selected: view.currentAccount === modelData || !view.accounts.length
                enabled: !view.switchingBlocked
                tooltipText: modelData + " · [ / ] switch account"
                onClicked: view.accountRequested(modelData)
            }
        }
    }
    ListView {
        id: inbox
        onActiveFocusChanged: if (activeFocus) view.listFocused()
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        model: view.messages
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            width: inbox.width
            height: 66
            radius: 0
            color: modelData.id === view.cursorId ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14) : mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07) : "transparent"
            MailLabel {
                x: 7; y: 9
                text: view.icons.unread
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
                    MailLabel { Layout.fillWidth: true; Layout.minimumWidth: 0; text: view.senderName(modelData.from); color: Color.accent; font.bold: modelData.unread; elide: Text.ElideRight }
                    MailLabel { text: view.shortDate(modelData.date); font.pixelSize: 10; opacity: 0.55; Layout.maximumWidth: 65; elide: Text.ElideRight }
                }
                MailLabel { Layout.fillWidth: true; text: modelData.subject || "(No subject)"; elide: Text.ElideRight }
                MailLabel { Layout.fillWidth: true; text: view.senderAddress(modelData.from); opacity: 0.5; font.pixelSize: 11; elide: Text.ElideRight }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !view.busy
                onClicked: { view.messageRequested(modelData.id) }
            }
        }
        MailLabel {
            anchors.centerIn: parent
            width: parent.width
            visible: view.messages.length === 0
            text: view.loading ? "Loading " + view.folderName + "…" : view.listError ? "Folder unavailable" : "No messages on this page."
            color: Color.foreground
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }
    RowLayout {
        Layout.fillWidth: true
        MailButton { text: "Newer"; iconText: view.icons.previous; tooltipText: "Previous page (p)"; enabled: view.page > 1 && !view.busy; onClicked: view.previousRequested() }
        MailLabel { Layout.fillWidth: true; text: "Page " + view.page; horizontalAlignment: Text.AlignHCenter; opacity: 0.55; font.pixelSize: 10 }
        MailButton { text: "Older"; iconText: view.icons.next; tooltipText: "Next page (n)"; enabled: view.hasNext && !view.busy; onClicked: view.nextRequested() }
    }
    RowLayout {
        Layout.fillWidth: true
        MailLabel { Layout.fillWidth: true; text: view.deleting ? "Deleting…" : view.moving ? "Moving…" : view.marking ? "Updating…" : view.loading ? "Refreshing…" : view.listError ? "Refresh failed · stale" : view.messages.length + " messages on page"; opacity: 0.55; font.pixelSize: 10; elide: Text.ElideRight }
        MailButton { text: "Shortcuts ?"; selected: view.showHelp; onClicked: view.helpRequested() }
    }
}
