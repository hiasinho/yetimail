import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

Rectangle {
    id: view
    required property var icons
    signal dismissed()

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
                MailButton { iconText: view.icons.close; tooltipText: "Close help (Esc)"; onClicked: view.dismissed() }
            }
            Repeater {
                model: [
                    ["j k / ↓ ↑", "Move / scroll"],
                    ["Enter / l / →", "Open message / link"],
                    ["Space", "Toggle message selection (list)"],
                    ["Ctrl+a", "Select current page (list)"],
                    ["h / ←", "Back to body / list"],
                    ["Tab", "Switch list / reader"],
                    ["gg / G", "First / last"],
                    ["Ctrl+d / u", "Half-page down / up"],
                    ["n / p", "Older / newer page"],
                    ["[ / ]", "Switch account"],
                    ["f", "Choose folder · r retry"],
                    ["gi / gs", "Inbox / sent"],
                    ["ga / gt", "Archive / trash"],
                    ["o", "Show / hide links"],
                    ["v", "Full selectable headers"],
                    ["a", "Attachments: j/k select"],
                    ["s / Enter", "Save / open attachment (in a)"],
                    ["M", "Move selection / message to folder"],
                    ["x / Shift+X", "Archive / trash selection or message"],
                    ["Delete", "Trash · in Trash, confirm removal"],
                    ["m / u", "Mark selection / message read / unread"],
                    ["r", "Refresh folder"],
                    ["Ctrl+c", "Copy selected text"],
                    ["?", "Toggle shortcuts"],
                    ["Esc", "Dismiss / clear selection / back / close"],
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
