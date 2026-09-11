import QtQuick
// Match test-lifecycle: preserve shared Ui, replacing only compositor container.
Item {
    property Item anchorItem
    property QtObject bar
    property var owner
    property bool open: false
    property Item focusTarget
    property int padding: 0
    property int contentWidth: 940
    property int contentHeight: 640
    property int availableCardWidth: 1000
    property int availableCardHeight: 700
    property int verticalContentInset: 24
    function fittedContentHeight(implicitHeight, cap) {
        var desired = Math.max(verticalContentInset, (Number(implicitHeight) || 0) + verticalContentInset)
        return Math.round(Math.min(desired, Number(cap) || desired, availableCardHeight || desired))
    }
    width: contentWidth
    height: contentHeight
    visible: open
}
