import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

ColumnLayout {
    id: view
    objectName: "inboxPane"
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
    required property int pendingMoves
    required property bool movePaused
    required property bool marking
    required property var icons
    required property bool busy
    required property bool showFolders
    required property bool switchingBlocked
    required property var accounts
    required property string currentAccount
    required property string cursorId
    required property var selectedIds
    required property int selectedCount
    required property bool showHelp
    signal refreshRequested()
    signal foldersRequested()
    signal accountRequested(string name)
    signal listFocused()
    signal messageRequested(string messageId)
    signal toggleSelectionRequested(string messageId)
    signal selectAllRequested()
    signal clearSelectionRequested()
    signal bulkReadRequested()
    signal bulkUnreadRequested()
    signal bulkArchiveRequested()
    signal bulkTrashRequested()
    signal bulkMoveRequested()
    signal previousRequested()
    signal nextRequested()
    signal helpRequested()
    signal retryMovesRequested()
    signal cancelMovesRequested()
    readonly property point folderAnchor: Qt.point(accountFlow.x + folderButton.x, accountFlow.y + folderButton.y + folderButton.height + 2)
    readonly property real desiredListHeight: Math.max(90, Math.min(7, messages.length) * 68)
    readonly property real preferredContentHeight: headerRow.implicitHeight + accountFlow.implicitHeight + selectionFlow.implicitHeight + desiredListHeight + footerRow.implicitHeight + spacing * 4
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
    function footerStatus() {
        var queued = view.pendingMoves + (view.pendingMoves === 1 ? " message" : " messages")
        var status = view.deleting ? "Deleting…" : view.movePaused ? "Move failed · " + queued + " pending" : view.pendingMoves ? "Moving " + queued + "…" : view.marking ? "Updating…" : view.loading ? "Refreshing…" : view.listError ? "Refresh failed · stale" : view.messages.length + (view.messages.length === 1 ? " message" : " messages")
        return (view.selectedCount ? view.selectedCount + " selected · " : "") + status + " · Page " + view.page
    }

    Layout.fillHeight: true
    spacing: 10
    RowLayout {
        id: headerRow
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            MailLabel { objectName: "currentFolderTitle"; Layout.fillWidth: true; Layout.minimumWidth: 0; text: (view.folderName || "Mail").toUpperCase() + (view.demo ? " / DEMO" : ""); font.pixelSize: 10; font.letterSpacing: 1.5; opacity: 0.55; elide: Text.ElideRight }
            MailLabel { Layout.fillWidth: true; text: view.unread + " unread"; font.pixelSize: 14 }
        }
        MailButton { objectName: "inboxRefreshButton"; text: view.loading ? "…" : "Refresh"; iconText: view.loading ? "" : view.icons.refresh; tooltipText: "Refresh (r)"; enabled: !view.busy; onClicked: view.refreshRequested() }
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
    Flow {
        id: selectionFlow
        objectName: "inboxSelectionControls"
        Layout.fillWidth: true
        spacing: 6
        MailButton { objectName: "selectAllMessagesButton"; text: "Select page"; tooltipText: "Select all messages on this page (Ctrl+A)"; enabled: view.messages.length > 0 && !view.busy; onClicked: view.selectAllRequested() }
        MailButton { objectName: "bulkReadButton"; text: "Read"; tooltipText: "Mark selected messages read (m)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkReadRequested() }
        MailButton { objectName: "bulkUnreadButton"; text: "Unread"; tooltipText: "Mark selected messages unread (u)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkUnreadRequested() }
        MailButton { objectName: "bulkArchiveButton"; text: "Archive"; tooltipText: "Archive selected messages (x)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkArchiveRequested() }
        MailButton { objectName: "bulkTrashButton"; text: "Trash"; tooltipText: "Move selected messages to Trash (Shift+X)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkTrashRequested() }
        MailButton { objectName: "bulkMoveButton"; text: "Move"; tooltipText: "Move selected messages to a folder (Shift+M)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkMoveRequested() }
        MailButton { objectName: "clearSelectionButton"; text: "Clear"; tooltipText: "Clear message selection (Esc)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.clearSelectionRequested() }
    }
    ListView {
        id: inbox
        onActiveFocusChanged: if (activeFocus) view.listFocused()
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: view.desiredListHeight
        clip: true
        spacing: 2
        model: view.messages
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            id: messageRow
            objectName: "messageRow"
            required property var modelData
            readonly property bool selected: !!view.selectedIds && view.selectedIds.indexOf(String(modelData.id)) !== -1
            readonly property bool cursor: modelData.id === view.cursorId
            width: inbox.width
            height: 66
            radius: 0
            color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.26) : cursor ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14) : mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.07) : "transparent"
            border.width: cursor ? 1 : 0
            border.color: Color.accent
            Rectangle {
                width: 3
                height: parent.height
                color: Color.accent
                visible: messageRow.selected
            }
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
                objectName: "messageRowMouseArea"
                anchors.fill: parent
                hoverEnabled: true
                enabled: !view.busy
                onClicked: function(event) {
                    if (event.modifiers & Qt.ControlModifier)
                        view.toggleSelectionRequested(String(modelData.id))
                    else
                        view.messageRequested(modelData.id)
                }
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
        id: footerRow
        Layout.fillWidth: true
        spacing: 4
        MailButton { objectName: "newerPageButton"; text: "Newer"; iconText: view.icons.previous; tooltipText: "Previous page (p)"; visible: !view.movePaused; enabled: view.page > 1 && !view.busy && !view.pendingMoves; onClicked: view.previousRequested() }
        MailButton { objectName: "retryMovesButton"; text: "Retry"; visible: view.movePaused; onClicked: view.retryMovesRequested() }
        MailLabel { objectName: "inboxFooterStatus"; Layout.fillWidth: true; Layout.minimumWidth: 0; text: view.footerStatus(); horizontalAlignment: Text.AlignHCenter; opacity: 0.55; font.pixelSize: 10; elide: Text.ElideRight }
        MailButton { objectName: "cancelMovesButton"; text: "Cancel"; visible: view.movePaused; onClicked: view.cancelMovesRequested() }
        MailButton { objectName: "olderPageButton"; text: "Older"; iconText: view.icons.next; tooltipText: "Next page (n)"; visible: !view.movePaused; enabled: view.hasNext && !view.busy && !view.pendingMoves; onClicked: view.nextRequested() }
        MailButton { objectName: "shortcutHelpButton"; text: "?"; tooltipText: "Keyboard shortcuts (?)"; selected: view.showHelp; onClicked: view.helpRequested() }
    }
}
