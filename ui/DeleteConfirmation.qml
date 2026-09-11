import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

Rectangle {
    id: view
    required property var snapshot
    required property bool demo
    required property bool busy
    signal cancelRequested()
    signal confirmRequested()

    objectName: "deleteConfirmation"
    anchors.fill: parent
    z: 20
    color: Color.background
    border.color: Color.accent
    MouseArea { anchors.fill: parent }
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 48)
        spacing: 14
        MailLabel { text: "Permanently remove this message?"; font.pixelSize: 16; font.bold: true }
        MailLabel {
            Layout.fillWidth: true
            text: view.snapshot ? "Account: " + (view.snapshot.account || (view.demo ? "Demo" : "Default account (explicit account required)")) +
                "\nFolder: " + view.snapshot.folderName + " [" + (view.snapshot.folder || "configured Inbox") + "]" +
                "\nID: " + view.snapshot.id + "\nSubject: " + view.snapshot.subject : ""
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 6
            elide: Text.ElideRight
        }
        MailLabel {
            Layout.fillWidth: true
            text: "Request permanent removal from Trash. Without IMAP UIDPLUS, Himalaya may only flag the message Deleted pending expunge. Its configured Trash policy remains authoritative. Yetimail does not expunge."
            wrapMode: Text.Wrap
        }
        MailLabel { visible: view.demo; text: "Demo only: no real mail changes; refresh restores fixtures."; Layout.fillWidth: true; wrapMode: Text.Wrap }
        MailLabel { text: "Enter confirms · h / Esc cancels" }
        RowLayout {
            MailButton { objectName: "cancelDelete"; text: "Cancel"; focusable: false; onClicked: view.cancelRequested() }
            MailButton { objectName: "confirmDelete"; text: "Delete"; focusable: false; enabled: !view.busy; onClicked: view.confirmRequested() }
        }
    }
}
