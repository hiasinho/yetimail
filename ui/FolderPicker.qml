import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

Rectangle {
    id: view
    required property bool movePicker
    required property int currentIndex
    required property bool switchingBlocked
    required property bool loading
    required property string error
    required property var folders
    required property var icons
    required property string folderId
    signal folderChosen(int index)
    signal retryRequested()
    function focusList() { folderList.forceActiveFocus() }
    function reveal(index) { folderList.positionViewAtIndex(index, ListView.Contain) }
    function folderIcon(folder) {
        var name = String(folder.role || folder.name || "").toLowerCase()
        if (name === "inbox") return icons.inbox
        if (name === "sent" || name === "sent mail" || name === "sent items") return icons.sent
        if (name === "draft" || name === "drafts") return icons.drafts
        if (name === "archive" || name === "archives") return icons.archive
        if (name === "junk" || name === "spam") return icons.junk
        if (name === "trash" || name === "deleted items") return icons.trash
        return icons.folder
    }

    objectName: "folderMenu"
    z: 11
    // A sibling overlay stays interactive while mailbox controls are disabled.
    width: Math.min(180, parent.width - x)
    height: Math.max(0, Math.min(322, parent.height - y,
        view.folders.length * 32 + 2 + (movePickerTitle.visible ? movePickerTitle.implicitHeight + 12 : 0) +
        (folderStatus.visible ? folderStatus.implicitHeight + 12 : 0) +
        (folderRetry.visible ? folderRetry.implicitHeight + 4 : 0)))
    color: Color.background
    border.color: Color.accent
    MouseArea { anchors.fill: parent }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0
        MailLabel {
            id: movePickerTitle
            Layout.fillWidth: true
            Layout.margins: 6
            visible: view.movePicker
            text: "Move message to…"
            font.pixelSize: 11
            color: Color.accent
        }
        MailLabel {
            id: folderStatus
            Layout.fillWidth: true
            Layout.margins: 6
            visible: view.loading || !!view.error || !view.folders.length
            text: view.loading ? "Loading folders…" : view.error || "No folders available."
            font.pixelSize: 11
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
            color: Color.accent
        }
        ListView {
            id: folderList
            objectName: "folderPicker"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            model: view.folders
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: folderList.width
                height: 32
                color: index === view.currentIndex ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.09) : "transparent"
                opacity: view.movePicker && modelData.id === view.folderId ? 0.4 : 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8
                    MailLabel { Layout.preferredWidth: 14; text: view.folderIcon(modelData); color: Color.accent }
                    MailLabel { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !view.switchingBlocked && !view.loading
                    onClicked: { view.folderChosen(index) }
                }
            }
        }
        MailButton {
            id: folderRetry
            Layout.fillWidth: true
            Layout.margins: 2
            visible: !view.loading && (!!view.error || !view.folders.length)
            text: "Retry (r)"
            enabled: !view.switchingBlocked
            onClicked: view.retryRequested()
        }
    }
}
