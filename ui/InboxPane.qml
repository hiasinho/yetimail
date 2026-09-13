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
    required property bool hasNext
    required property bool loadingMore
    required property string loadMoreError
    required property bool newMessagesAvailable
    required property bool deleting
    required property bool moving
    required property int pendingMoves
    required property bool movePaused
    required property bool marking
    required property var icons
    required property bool busy
    required property bool selectionBlocked
    required property bool showFolders
    required property bool showAccounts
    required property bool switchingBlocked
    required property var accounts
    required property string currentAccount
    required property string cursorId
    required property var selectedIds
    required property int selectedCount
    required property bool showHelp
    signal refreshRequested()
    signal foldersRequested()
    signal accountsRequested()
    signal settingsRequested()
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
    signal loadMoreRequested()
    signal retryLoadMoreRequested()
    signal showNewMessagesRequested()
    signal helpRequested()
    signal retryMovesRequested()
    signal cancelMovesRequested()
    signal listScrollChanged(real contentY)
    readonly property point accountAnchor: Qt.point(footerRow.x + utilityRow.x + accountButton.x, footerRow.y + utilityRow.y + accountButton.y)
    readonly property point folderAnchor: Qt.point(footerRow.x + utilityRow.x + folderButton.x, footerRow.y + utilityRow.y + folderButton.y)
    readonly property real desiredListHeight: Math.max(90, Math.min(7, messages.length) * 68)
    readonly property real listHeight: inbox.height
    readonly property Item focusTarget: inbox
    function focusList() { inbox.forceActiveFocus() }
    function reveal(index) { inbox.positionViewAtIndex(index, ListView.Contain) }
    function listScrollY() { return inbox.contentY }
    function listScrollAnchor() {
        var index = inbox.indexAt(1, inbox.contentY + 1)
        var item = index >= 0 ? inbox.itemAtIndex(index) : null
        return index >= 0 && view.messages[index]
            ? {id: String(view.messages[index].id), offset: item ? inbox.contentY - item.y : 0}
            : {id: "", offset: 0}
    }
    function restoreListScroll(contentY, anchorId, anchorOffset) {
        Qt.callLater(function() {
            var index = anchorId ? view.messages.findIndex(function(row) { return String(row.id) === String(anchorId) }) : -1
            if (index >= 0) {
                inbox.positionViewAtIndex(index, ListView.Beginning)
                Qt.callLater(function() {
                    var item = inbox.itemAtIndex(index)
                    var maximum = Math.max(0, inbox.contentHeight - inbox.height)
                    var anchored = item ? item.y + (Number(anchorOffset) || 0) : Number(contentY) || 0
                    inbox.contentY = Math.max(0, Math.min(maximum, anchored))
                })
                return
            }
            var maximum = Math.max(0, inbox.contentHeight - inbox.height)
            inbox.contentY = Math.max(0, Math.min(maximum, Number(contentY) || 0))
        })
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
    function footerStatus() {
        var queued = view.pendingMoves + (view.pendingMoves === 1 ? " message" : " messages")
        var status = view.deleting ? "Deleting…" : view.movePaused ? "Move failed · " + queued + " pending" : view.pendingMoves ? "Moving " + queued + "…" : view.marking ? "Updating…" : view.loading ? "Refreshing…" : view.listError ? "Refresh failed · stale" : view.messages.length + " loaded"
        return (view.selectedCount ? view.selectedCount + " selected · " : "") + view.unread + " unread · " + status
    }

    Layout.fillHeight: true
    spacing: 10
    onBusyChanged: if (!busy) Qt.callLater(inbox.maybeLoadMore)
    onHasNextChanged: if (hasNext) Qt.callLater(inbox.maybeLoadMore)
    onLoadingMoreChanged: if (!loadingMore) Qt.callLater(inbox.maybeLoadMore)
    MailLabel {
        id: headerRow
        objectName: "currentFolderTitle"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: (view.folderName || "Mail").toUpperCase() + (view.demo ? " / DEMO" : "")
        font.pixelSize: 10
        font.letterSpacing: 1.5
        opacity: 0.55
        elide: Text.ElideRight
    }
    Flow {
        id: selectionFlow
        objectName: "inboxSelectionControls"
        Layout.fillWidth: true
        spacing: 6
        MailButton { objectName: "selectAllMessagesButton"; text: "Select loaded"; tooltipText: "Select all loaded messages (Ctrl+A)"; enabled: view.messages.length > 0 && !view.selectionBlocked; onClicked: view.selectAllRequested() }
        MailButton { objectName: "bulkReadButton"; text: "Read"; tooltipText: "Mark selected messages read (m)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkReadRequested() }
        MailButton { objectName: "bulkUnreadButton"; text: "Unread"; tooltipText: "Mark selected messages unread (u)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkUnreadRequested() }
        MailButton { objectName: "bulkArchiveButton"; text: "Archive"; tooltipText: "Archive selected messages (x)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkArchiveRequested() }
        MailButton { objectName: "bulkTrashButton"; text: "Trash"; tooltipText: "Move selected messages to Trash (Shift+X)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkTrashRequested() }
        MailButton { objectName: "bulkMoveButton"; text: "Move"; tooltipText: "Move selected messages to a folder (Shift+M)"; visible: view.selectedCount > 0; enabled: !view.busy; onClicked: view.bulkMoveRequested() }
        MailButton { objectName: "clearSelectionButton"; text: "Clear"; tooltipText: "Clear message selection (Esc)"; visible: view.selectedCount > 0; enabled: !view.selectionBlocked; onClicked: view.clearSelectionRequested() }
    }
    ListView {
        id: inbox
        onActiveFocusChanged: if (activeFocus) view.listFocused()
        function maybeLoadMore() {
            if (view.messages.length && view.hasNext && !view.loadingMore && !view.loadMoreError
                && !view.busy && contentY + height >= contentHeight - height)
                view.loadMoreRequested()
        }
        onContentYChanged: { view.listScrollChanged(contentY); maybeLoadMore() }
        onContentHeightChanged: Qt.callLater(maybeLoadMore)
        onHeightChanged: Qt.callLater(maybeLoadMore)
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
                enabled: !view.selectionBlocked
                onClicked: function(event) {
                    if (event.modifiers & Qt.ControlModifier)
                        view.toggleSelectionRequested(String(modelData.id))
                    else if (!view.busy)
                        view.messageRequested(modelData.id)
                }
            }
        }
        MailLabel {
            anchors.centerIn: parent
            width: parent.width
            visible: view.messages.length === 0
            text: view.loading ? "Loading " + view.folderName + "…" : view.listError ? "Folder unavailable" : "No messages in this folder."
            color: Color.foreground
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }
    ColumnLayout {
        id: footerRow
        Layout.fillWidth: true
        spacing: 2
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            MailButton { objectName: "retryMovesButton"; text: "Retry"; visible: view.movePaused; onClicked: view.retryMovesRequested() }
            MailLabel { objectName: "inboxFooterStatus"; Layout.fillWidth: true; Layout.minimumWidth: 0; text: view.footerStatus(); horizontalAlignment: Text.AlignHCenter; opacity: 0.55; font.pixelSize: 10; elide: Text.ElideRight }
            MailButton { objectName: "newMessagesButton"; text: "New messages"; visible: view.newMessagesAvailable; onClicked: view.showNewMessagesRequested() }
            MailLabel { objectName: "loadMoreStatus"; visible: view.loadingMore; text: "Loading older…"; opacity: 0.55; font.pixelSize: 10 }
            MailButton { objectName: "retryLoadMoreButton"; text: "Retry older"; visible: !!view.loadMoreError; enabled: !view.busy; tooltipText: view.loadMoreError; onClicked: view.retryLoadMoreRequested() }
            MailButton { objectName: "cancelMovesButton"; text: "Cancel"; visible: view.movePaused; onClicked: view.cancelMovesRequested() }
        }
        RowLayout {
            id: utilityRow
            Layout.fillWidth: true
            spacing: 2
            MailButton {
                id: accountButton
                objectName: "accountButton"
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                iconText: view.icons.account
                tooltipText: (view.currentAccount || view.accountLabel) + " · Choose account"
                bordered: false
                selected: view.showAccounts
                enabled: !view.switchingBlocked
                onClicked: view.accountsRequested()
            }
            MailButton {
                id: folderButton
                objectName: "folderButton"
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                iconText: view.icons.inbox
                tooltipText: view.folderName + " · Choose mailbox (f)"
                bordered: false
                selected: view.showFolders
                enabled: !view.switchingBlocked
                onClicked: view.foldersRequested()
            }
            MailButton {
                objectName: "accountSettingsButton"
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                iconText: view.icons.settings
                tooltipText: "Account settings"
                bordered: false
                enabled: !view.switchingBlocked
                onClicked: view.settingsRequested()
            }
            Item { Layout.fillWidth: true }
            MailButton {
                objectName: "inboxRefreshButton"
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                iconText: view.loading ? "…" : view.icons.refresh
                tooltipText: "Refresh (r)"
                bordered: false
                enabled: !view.busy
                onClicked: view.refreshRequested()
            }
            MailButton {
                objectName: "shortcutHelpButton"
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                text: "?"
                tooltipText: "Keyboard shortcuts (?)"
                bordered: false
                selected: view.showHelp
                onClicked: view.helpRequested()
            }
        }
    }
}
