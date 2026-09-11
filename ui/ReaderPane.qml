import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons

ColumnLayout {
    id: view
    required property var message
    required property string folderName
    required property string listError
    required property string actionError
    required property string foldersError
    required property bool reading
    required property string readError
    required property string accountLabel
    required property bool savingAttachment
    required property string attachmentStatus
    required property var icons
    required property bool showHeaders
    required property bool showAttachments
    required property bool showLinks
    required property bool busy
    required property var displayedEnvelope
    required property var messageAttachments
    required property var messageLinks
    required property int linkIndex
    required property var selectedLink
    required property int attachmentIndex
    required property var selectedAttachment
    required property bool agentEnabled
    required property bool agentLaunching
    required property string agentStatus
    signal headersRequested()
    signal attachmentsRequested()
    signal linksRequested()
    signal markRequested(bool seen)
    signal deleteRequested()
    signal askAgentRequested()
    signal closeRequested()
    signal attachmentSelected(int index)
    signal linkSelected(int index)
    signal openLinkRequested()
    signal attachmentMoved(int delta)
    signal attachmentActionRequested(bool openAfter)
    signal readerFocused()
    required property real panelWidth
    readonly property real availableHeight: reader.availableHeight
    function focusBody() { messageText.forceActiveFocus() }
    function focusLinks() { linkList.forceActiveFocus() }
    function revealLink(index) { linkList.positionViewAtIndex(index, ListView.Contain) }
    function scroll(delta) {
        var flick = reader.contentItem
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + delta))
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
    function headerDate(value) {
        var date = new Date(value)
        return isNaN(date.getTime()) ? String(value || "") : Qt.formatDateTime(date, "MMM d  HH:mm")
    }
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
    Layout.fillWidth: true
    Layout.fillHeight: true
    RowLayout {
        Layout.fillWidth: true
        spacing: 2
        MailLabel { Layout.fillWidth: true; Layout.minimumWidth: 0; text: view.message ? view.message.subject || "(No subject)" : view.folderName; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight }
        MailButton { iconText: view.icons.headers; tooltipText: "Full selectable headers (v)"; selected: view.showHeaders; enabled: !!view.message && !view.busy; onClicked: view.headersRequested() }
        MailButton { iconText: view.icons.attachment; tooltipText: "Attachment metadata (a)"; selected: view.showAttachments; enabled: !!view.message && !view.busy; onClicked: view.attachmentsRequested() }
        MailButton { iconText: view.icons.link; tooltipText: "Show links (o)"; selected: view.showLinks; enabled: !!view.message && !view.busy; onClicked: view.linksRequested() }
        MailButton { objectName: "readerMarkRead"; iconText: view.icons.read; tooltipText: "Mark this message read (m)"; enabled: !!view.message && !!view.displayedEnvelope && view.displayedEnvelope.unread && !view.busy; onClicked: view.markRequested(true) }
        MailButton { objectName: "readerMarkUnread"; iconText: view.icons.unread; tooltipText: "Mark this message unread (u)"; enabled: !!view.message && !!view.displayedEnvelope && !view.displayedEnvelope.unread && !view.busy; onClicked: view.markRequested(false) }
        MailButton { objectName: "readerAskAgent"; text: view.agentLaunching ? "Opening…" : "Ask agent"; iconText: view.agentLaunching ? "" : view.icons.agent; tooltipText: view.agentEnabled ? "Discuss this email with your configured AI agent · sends sender, recipients, date, subject, and body" : "Ask agent is available for loaded, non-demo messages"; enabled: view.agentEnabled; onClicked: view.askAgentRequested() }
        MailButton { objectName: "readerDelete"; iconText: view.icons.delete; tooltipText: "Trash this message (Delete) · in Trash, confirm removal"; enabled: !!view.message && !!view.displayedEnvelope && !view.busy; onClicked: view.deleteRequested() }
        MailButton { iconText: view.icons.close; tooltipText: "Close (q)"; onClicked: view.closeRequested() }
    }
    MailLabel {
        objectName: "mailErrors"
        Layout.fillWidth: true
        visible: view.listError !== "" || view.actionError !== "" || view.foldersError !== ""
        text: [view.listError, view.actionError, view.foldersError].filter(function(error) { return !!error }).join("\n")
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        color: Color.accent
    }
    MailLabel {
        Layout.fillWidth: true
        visible: view.agentLaunching || view.agentStatus !== ""
        text: view.agentLaunching ? "Opening Ask agent…" : view.agentStatus
        color: view.agentStatus.indexOf("Could not") === 0 ? Color.accent : Color.foreground
        opacity: view.agentStatus.indexOf("Could not") === 0 ? 1 : 0.6
        wrapMode: Text.Wrap
    }
    ColumnLayout {
        visible: !!view.message && !view.reading && !view.readError && !view.showHeaders
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.bottomMargin: 8
        spacing: 4
        MailLabel { Layout.fillWidth: true; text: view.accountLabel; opacity: 0.5; font.pixelSize: 11; elide: Text.ElideRight }
        RowLayout {
            Layout.fillWidth: true
            MailLabel { Layout.fillWidth: true; text: view.message ? view.senderName(view.message.from) : ""; color: Color.accent; font.bold: true; elide: Text.ElideRight }
            MailLabel { Layout.maximumWidth: 125; elide: Text.ElideRight; text: view.message ? view.headerDate(view.message.date) : ""; opacity: 0.55; font.pixelSize: 11 }
        }
        MailLabel { Layout.fillWidth: true; text: view.message ? "To    " + view.message.to : ""; opacity: 0.55; font.pixelSize: 11; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight }
    }
    ListView {
        id: attachmentChips
        objectName: "attachmentChips"
        visible: !!view.message && !view.reading && !view.readError && view.messageAttachments.length > 0
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredHeight: 36
        Layout.maximumHeight: 36
        orientation: ListView.Horizontal
        spacing: 6
        clip: true
        model: view.messageAttachments
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
                MailLabel { text: view.icons.attachment; font.pixelSize: 11 }
                MailLabel { Layout.fillWidth: true; Layout.minimumWidth: 0; text: modelData.name || "Unnamed attachment"; elide: Text.ElideMiddle; font.pixelSize: 11 }
                MailLabel { text: view.attachmentSize(modelData.size); font.pixelSize: 10; opacity: 0.6 }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: view.attachmentSelected(index)
            }
            HoverHandler { id: attachmentHover }
            ToolTip {
                id: attachmentTooltip
                visible: attachmentHover.hovered
                delay: 500
                text: view.attachmentMetadata(modelData)
                font.family: Style.font.family
                width: Math.min(400, view.panelWidth)
                contentItem: MailLabel { text: attachmentTooltip.text; wrapMode: Text.WrapAnywhere }
            }
        }
    }
    ColumnLayout {
        visible: view.showLinks
        Layout.fillWidth: true
        Layout.fillHeight: true
        MailLabel { text: "Links · j/k select · Enter opens in browser · h back"; color: Color.foreground; wrapMode: Text.Wrap; Layout.fillWidth: true }
        ListView {
            id: linkList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: view.messageLinks
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: linkList.width
                height: 48
                radius: 0
                color: index === view.linkIndex ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
                border.width: index === view.linkIndex ? 1 : 0
                border.color: Color.accent
                Column {
                    anchors.fill: parent
                    anchors.margins: 7
                    MailLabel { width: parent.width; text: "[" + (index + 1) + "] " + modelData.label; textFormat: Text.PlainText; color: Color.foreground; elide: Text.ElideRight }
                    MailLabel { width: parent.width; text: modelData.url; textFormat: Text.PlainText; color: Color.foreground; opacity: 0.65; elide: Text.ElideMiddle }
                }
                MouseArea { anchors.fill: parent; onClicked: { view.linkSelected(index) } }
            }
            MailLabel { anchors.centerIn: parent; visible: !view.messageLinks.length; text: "No web links in this message."; color: Color.foreground }
        }
        MailLabel { text: "Destination (may contain tracking):"; color: Color.foreground; visible: !!view.selectedLink }
        ScrollView {
            id: linkPreview
            contentWidth: availableWidth
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            visible: !!view.selectedLink
            clip: true
            TextArea {
                font.family: Style.font.family
                font.pixelSize: 12
                width: linkPreview.availableWidth
                text: view.selectedLink ? view.selectedLink.url : ""
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: Color.foreground
                background: null
            }
        }
        MailButton { text: "Open in browser (Enter)"; enabled: !!view.selectedLink && !view.busy; focusable: true; onClicked: view.openLinkRequested() }
    }
    RowLayout {
        visible: view.showAttachments
        Layout.fillWidth: true
        MailButton { iconText: view.icons.previous; enabled: view.attachmentIndex > 0; onClicked: view.attachmentMoved(-1) }
        MailLabel { text: (view.selectedAttachment ? view.attachmentIndex + 1 : 0) + " / " + view.messageAttachments.length }
        MailButton { iconText: view.icons.next; enabled: view.attachmentIndex + 1 < view.messageAttachments.length; onClicked: view.attachmentMoved(1) }
        MailButton { objectName: "saveAttachment"; text: "Save (s)"; enabled: !!view.selectedAttachment && !view.busy; onClicked: view.attachmentActionRequested(false) }
        MailButton { objectName: "openAttachment"; text: "Open (Enter)"; enabled: !!view.selectedAttachment && !!view.selectedAttachment.openable && !view.busy; onClicked: view.attachmentActionRequested(true) }
    }
    MailLabel {
        visible: view.showAttachments && (view.savingAttachment || view.attachmentStatus !== "")
        Layout.fillWidth: true
        text: view.savingAttachment ? "Saving attachment…" : view.attachmentStatus
        wrapMode: Text.WrapAnywhere
    }
    ScrollView {
        id: reader
        objectName: "messageReader"
        visible: !view.showLinks
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
            onActiveFocusChanged: if (activeFocus) view.readerFocused()
            text: view.reading ? "Loading message…" : view.readError ? view.readError : view.message ?
                view.showAttachments ? ("Attachments · j/k select · s save · Enter open · h / Esc back\nSaves a unique private file in ~/Downloads. Open also saves a copy.\n\n" +
                    (view.selectedAttachment ? "[" + (view.attachmentIndex + 1) + "]\n" + view.attachmentMetadata(view.selectedAttachment) +
                     "\n\n" + (view.selectedAttachment.openable ? "Open with the default application only if you trust this file." : "Save-only type: opening is blocked.") : "No attachments in this message.")) :
                (view.showHeaders ? "Subject: " + view.message.subject + "\nFrom: " + view.message.from + "\nTo: " + view.message.to + "\nDate: " + view.message.date + "\n\n" : "") + view.message.body :
                "Select a message with j/k, then press Enter to read.\n\nOpening a message does not mark it as read. Use m / u to change its status."
            onTextChanged: { cursorPosition = 0; reader.contentItem.contentY = 0 }
        }
    }
}
