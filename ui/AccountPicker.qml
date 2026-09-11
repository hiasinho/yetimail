import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

Rectangle {
    id: view
    required property int currentIndex
    required property bool switchingBlocked
    required property var accounts
    required property var labels
    required property string currentAccount
    signal accountChosen(int index)
    function focusList() { accountList.forceActiveFocus() }
    function reveal(index) { accountList.positionViewAtIndex(index, ListView.Contain) }

    objectName: "accountMenu"
    z: 11
    width: Math.min(180, parent.width - x)
    height: Math.max(0, Math.min(322, parent.height - y, view.accounts.length * 32 + 2))
    color: Color.background
    border.color: Color.accent
    MouseArea { anchors.fill: parent }
    ListView {
        id: accountList
        objectName: "accountPicker"
        anchors.fill: parent
        anchors.margins: 1
        clip: true
        model: view.accounts
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: accountList.width
            height: 32
            color: index === view.currentIndex ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.09) : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8
                MailLabel {
                    Layout.fillWidth: true
                    text: {
                        var id = String(modelData)
                        return String(Object.prototype.hasOwnProperty.call(view.labels, id) ? view.labels[id] : id)
                    }
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !view.switchingBlocked
                onClicked: view.accountChosen(index)
            }
        }
    }
}
