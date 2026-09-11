import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import qs.Commons
import "ui"

BarWidget {
    id: root
    moduleName: "hiasinho.yetimail"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    property bool opened: false
    // Material Design icons bundled with Omarchy's Nerd Font.
    readonly property var icons: ({
        mail: "󰇰",
        inbox: "󰚇",
        sent: "󰒊",
        drafts: "󰷉",
        archive: "󱈎",
        junk: "󰀪",
        trash: "󰩺",
        folder: "󰉖",
        attachment: "󰏢",
        headers: "󰷐",
        link: "󰏌",
        read: "󰄬",
        unread: "󰧞",
        close: "󰅖",
        previous: "󰅁",
        next: "󰅂",
        refresh: "󰑐",
        delete: "󰧧"
    })
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
    property string pane: "list"
    property string cursorId: ""
    property bool showHelp: false
    property bool showFolders: false
    property int folderIndex: 0
    property bool movePicker: false
    property string moveTargetId: ""
    property string moveNextId: ""
    property var deleteSnapshot: null
    readonly property bool confirmingDelete: deleteSnapshot !== null
    function moveToRole(id, role) {
        if (!opened || busy || confirmingDelete || showHelp || showFolders) return
        var index = mail.messages.findIndex(function(m) { return m.id === id })
        if (index < 0) return
        var next = mail.messages[index + 1] || mail.messages[index - 1]
        moveNextId = next ? next.id : ""
        if (!mail.moveMessageToRole(id, role)) moveNextId = ""
    }
    function requestDelete(id) {
        if (!opened || busy || confirmingDelete || showHelp || showFolders) return
        var envelope = mail.messages.find(function(m) { return m.id === id })
        if (!envelope) return
        var trash = mail.resolveFolderRole("trash")
        if (!trash) return
        if (trash.id !== mail.folderId) { moveToRole(id, "trash"); return }
        deleteSnapshot = {account: mail.account, folder: mail.folderId, folderName: mail.folderName,
            id: id, subject: envelope.subject || "(No subject)", generation: mail.generation,
            page: mail.page, listRequest: mail.listRequest, readRequest: mail.readRequest,
            target: targetId, pane: pane, messages: mail.messages}
        deleteOverlay.forceActiveFocus()
    }
    function cancelDelete(restoreFocus) {
        var snapshot = deleteSnapshot
        deleteSnapshot = null
        // State invalidation must not steal focus from the new context.
        if (restoreFocus !== false && snapshot && opened && snapshot.pane === pane) {
            if (pane === "reader") {
                if (showLinks) readerPane.focusLinks()
                else readerPane.focusBody()
            } else sidebar.focusList()
        }
    }
    function confirmDelete() {
        var snapshot = deleteSnapshot
        // Consume before submitting: held Enter and double clicks cannot repeat.
        cancelDelete()
        if (!snapshot || !opened || busy || snapshot.account !== mail.account
            || snapshot.folder !== mail.folderId || snapshot.generation !== mail.generation
            || snapshot.page !== mail.page || snapshot.listRequest !== mail.listRequest
            || snapshot.readRequest !== mail.readRequest || snapshot.target !== targetId || snapshot.pane !== pane
            || snapshot.messages !== mail.messages) return
        var index = mail.messages.findIndex(function(m) { return m.id === snapshot.id
            && (m.subject || "(No subject)") === snapshot.subject })
        if (index < 0) return
        var next = mail.messages[index + 1] || mail.messages[index - 1]
        moveNextId = next ? next.id : ""
        if (!mail.deleteMessage(snapshot.id)) moveNextId = ""
    }
    onTargetIdChanged: cancelDelete(false)
    function updatePrefetchSelection() {
        if (typeof mail.setPrefetchSelection === "function")
            mail.setPrefetchSelection(opened && pane === "list" ? cursorId : "")
    }
    onCursorIdChanged: updatePrefetchSelection()
    onPaneChanged: { cancelDelete(false); updatePrefetchSelection() }
    readonly property bool switchingBlocked: confirmingDelete || mail.deleting || mail.moving || mail.marking || mail.savingAttachment || mail.openingAttachment
    function toggleFolders() {
        if (switchingBlocked) return
        if (showFolders) { dismissFolders(); return }
        showHelp = false
        showLinks = false
        showHeaders = false
        showAttachments = false
        movePicker = false
        moveTargetId = ""
        showFolders = true
        mail.loadFolders()
        syncFolderCursor()
        folderOverlay.focusList()
    }
    function openMovePicker() {
        if (busy || showHelp || showFolders || !targetEnvelope) return
        var id = targetId
        toggleFolders()
        movePicker = true
        moveTargetId = id
    }
    function isCurrentFolder(folder) {
        // An empty source is a configured alias, not necessarily the folder
        // named Inbox. The helper resolves that case before any server action.
        return folder.id === mail.folderId
    }
    function syncFolderCursor() {
        var index = mail.folders.findIndex(function(folder) {
            return folder.id === mail.folderId || (!mail.folderId && folder.role === "inbox")
        })
        folderIndex = Math.max(0, index)
        Qt.callLater(function() {
            if (root.showFolders && mail.folders.length) folderOverlay.reveal(root.folderIndex)
        })
    }
    function moveFolder(delta) {
        folderIndex = Math.max(0, Math.min(mail.folders.length - 1, folderIndex + delta))
        if (mail.folders.length) folderOverlay.reveal(folderIndex)
    }
    function dismissFolders() {
        showFolders = false
        movePicker = false
        moveTargetId = ""
        if (pane === "reader") readerPane.focusBody()
        else sidebar.focusList()
    }
    function chooseFolder() {
        if (!showFolders || switchingBlocked || mail.foldersLoading || !mail.folders[folderIndex]) return
        var folder = mail.folders[folderIndex]
        if (movePicker) {
            if (busy || isCurrentFolder(folder)) return
            var index = mail.messages.findIndex(function(message) { return message.id === root.moveTargetId })
            if (index < 0) { dismissFolders(); return }
            var next = mail.messages[index + 1] || mail.messages[index - 1]
            moveNextId = next ? next.id : ""
            if (mail.moveMessage(moveTargetId, folder.id)) dismissFolders()
            else moveNextId = ""
        } else if (mail.selectFolder(folder.id) !== false) dismissFolders()
    }
    function goFolderRole(role) {
        if (showHelp || showFolders || switchingBlocked) return
        mail.selectFolderRole(role)
    }
    function toggleHelp() {
        if (confirmingDelete) return
        if (showFolders) dismissFolders()
        showHelp = !showHelp
    }
    property bool showLinks: false
    property bool showHeaders: false
    property bool showAttachments: false
    property int attachmentIndex: 0
    readonly property var selectedAttachment: messageAttachments[attachmentIndex] || null
    function moveAttachment(delta) {
        attachmentIndex = Math.max(0, Math.min(messageAttachments.length - 1, attachmentIndex + delta))
    }
    function attachmentAction(openAfter) {
        if (!opened || showHelp || showFolders || !showAttachments || !selectedAttachment || busy) return
        mail.saveAttachment(selectedAttachment.id, openAfter)
    }
    readonly property var messageAttachments: mail.message && Array.isArray(mail.message.attachments) ? mail.message.attachments : []
    function toggleAttachments() {
        if (showHelp || showFolders || !mail.message || busy) return
        showAttachments = !showAttachments
        showLinks = false
        showHeaders = false
        pane = "reader"
        readerPane.focusBody()
    }
    property int linkIndex: 0
    readonly property var messageLinks: mail.message && Array.isArray(mail.message.links) ? mail.message.links : []
    readonly property var selectedLink: messageLinks[linkIndex] || null
    property var openUrl: function(url) { return Qt.openUrlExternally(url) }

    function toggleHeaders() {
        if (showHelp || showFolders || !mail.message || busy) return
        showHeaders = !showHeaders
        showLinks = false
        showAttachments = false
        pane = "reader"
        readerPane.focusBody()
    }
    function toggleLinks() {
        if (showHelp || showFolders || !mail.message || busy) return
        pane = "reader"
        showLinks = !showLinks
        showHeaders = false
        showAttachments = false
        if (showLinks) readerPane.focusLinks()
        else readerPane.focusBody()
    }
    function moveLink(delta) {
        linkIndex = Math.max(0, Math.min(messageLinks.length - 1, linkIndex + delta))
        if (linkIndex >= 0) readerPane.revealLink(linkIndex)
    }
    function openLink() {
        if (showHelp || showFolders || !showLinks || !selectedLink || busy) return
        // Defense in depth: only explicit browser navigation, never shell/HTML.
        if (/^https?:\/\/[^\s/]+(?:[/?#]|$)/i.test(selectedLink.url)) openUrl(selectedLink.url)
    }
    readonly property int cursorIndex: mail.messages.findIndex(function(m) { return m.id === root.cursorId })
    readonly property string targetId: pane === "reader" ? mail.selectedId : cursorId
    readonly property var targetEnvelope: mail.messages.find(function(m) { return m.id === root.targetId }) || null
    readonly property var displayedEnvelope: mail.messages.find(function(m) { return m.id === mail.selectedId }) || null
    readonly property bool busy: mail.deleting || mail.moving || mail.loading || mail.reading || mail.marking || mail.savingAttachment || mail.openingAttachment

    function selectAccount(name) {
        if (accounts.indexOf(name) !== -1 && !switchingBlocked && !showHelp) selectedAccount = name
    }
    function moveAccount(delta) {
        if (accounts.length < 2) return
        var index = accounts.indexOf(currentAccount)
        selectAccount(accounts[(index + delta + accounts.length) % accounts.length])
    }
    function close() { opened = false }
    function focusList() { showLinks = false; showAttachments = false; pane = "list"; sidebar.focusList() }
    function back() {
        if (showFolders) { dismissFolders(); return }
        if (showHelp) return
        if (showAttachments) { showAttachments = false; readerPane.focusBody() }
        else if (showLinks) { showLinks = false; readerPane.focusBody() }
        else focusList()
    }
    function syncCursor() {
        if (cursorIndex < 0) {
            cursorId = moveNextId && mail.messages.some(function(message) { return message.id === root.moveNextId })
                ? moveNextId : mail.messages.length ? mail.messages[0].id : ""
        }
        moveNextId = ""
        Qt.callLater(function() {
            if (root.cursorIndex >= 0) sidebar.reveal(root.cursorIndex)
        })
    }
    function moveCursor(delta) {
        if (!mail.messages.length) return
        var index = Math.max(0, Math.min(mail.messages.length - 1, cursorIndex + delta))
        cursorId = mail.messages[index].id
        sidebar.reveal(index)
    }
    function scrollReader(delta) {
        readerPane.scroll(delta)
    }
    function navigate(delta) {
        if (showHelp) return
        if (showFolders) moveFolder(delta)
        else if (showAttachments) moveAttachment(delta)
        else if (showLinks) moveLink(delta)
        else if (pane === "reader") scrollReader(delta * 42)
        else moveCursor(delta)
    }
    function jump(last) {
        if (showHelp) return
        if (showFolders) moveFolder(last ? mail.folders.length : -mail.folders.length)
        else if (showAttachments) moveAttachment(last ? messageAttachments.length : -messageAttachments.length)
        else if (showLinks) moveLink(last ? messageLinks.length : -messageLinks.length)
        else if (pane === "reader") scrollReader(last ? 1000000000 : -1000000000)
        else if (mail.messages.length) moveCursor(last ? mail.messages.length : -mail.messages.length)
    }
    function halfPage(delta) {
        if (showHelp || showFolders) return
        if (showLinks) moveLink(delta * 5)
        else if (pane === "reader") scrollReader(delta * readerPane.availableHeight / 2)
        else moveCursor(delta * Math.max(1, Math.floor(sidebar.listHeight / 68 / 2)))
    }
    function openCurrent() {
        if (!cursorId || busy || showHelp || showFolders) return
        mail.readMessage(cursorId)
        pane = "reader"
        readerPane.focusBody()
    }
    function switchPane() {
        if (showHelp || showFolders) return
        if (pane === "reader") focusList()
        else if (mail.selectedId) { pane = "reader"; readerPane.focusBody() }
        else openCurrent()
    }
    function markCurrent(seen) { markMessage(targetId, seen) }
    function markMessage(id, seen) {
        var envelope = mail.messages.find(function(m) { return m.id === id })
        if (!envelope || busy || showHelp || showFolders || envelope.unread === !seen) return
        mail.setRead(id, seen)
    }
    function handleEscape() {
        if (showFolders) dismissFolders()
        else if (showHelp) showHelp = false
        else if (pane === "reader") back()
        else close()
    }
    onCurrentAccountChanged: { cancelDelete(false); moveNextId = ""; moveTargetId = ""; movePicker = false; cursorId = ""; pane = "list"; showHelp = false; showFolders = false; showLinks = false; showHeaders = false; showAttachments = false }
    onOpenedChanged: {
        cancelDelete(false)
        if (opened) { showHelp = false; Qt.callLater(focusList) }
        else { showFolders = false; showHelp = false; mail.cancelAttachmentOpen() }
        updatePrefetchSelection()
    }

    MailService {
        id: mail
        active: root.bar !== null || demo
        account: root.currentAccount
        config: String(root.setting("config", ""))
        demo: root.setting("demo", false) === true
    }
    Connections {
        target: mail
        function onGenerationChanged() {
            root.cancelDelete(false)
            if (root.showFolders && root.movePicker) root.dismissFolders()
            root.moveNextId = ""
        }
        function onMessagesChanged() { root.cancelDelete(false); root.syncCursor(); Qt.callLater(root.updatePrefetchSelection) }
        function onLoadingChanged() { if (mail.loading) root.cancelDelete(false) }
        function onReadingChanged() { if (mail.reading) root.cancelDelete(false) }
        function onPageChanged() { root.cancelDelete(false) }
        function onListRequestChanged() { root.cancelDelete(false) }
        function onReadRequestChanged() { root.cancelDelete(false) }
        function onMarkingChanged() { if (mail.marking) root.cancelDelete(false) }
        function onMovingChanged() { if (mail.moving) root.cancelDelete(false) }
        function onDeletingChanged() { if (mail.deleting) root.cancelDelete(false) }
        function onSavingAttachmentChanged() { if (mail.savingAttachment) root.cancelDelete(false) }
        function onOpeningAttachmentChanged() { if (mail.openingAttachment) root.cancelDelete(false) }
        function onFoldersChanged() { root.syncFolderCursor() }
        function onFolderIdChanged() { root.cancelDelete(false); root.showFolders = false; root.movePicker = false; root.moveTargetId = ""; root.moveNextId = ""; root.cursorId = ""; root.pane = "list"; root.showLinks = false; root.showHeaders = false; root.showAttachments = false }
        function onMessageChanged() { root.cancelDelete(false); root.showLinks = false; root.showHeaders = false; root.showAttachments = false; root.linkIndex = 0; root.attachmentIndex = 0 }
        function onSelectedIdChanged() { root.cancelDelete(false); if (!mail.selectedId) root.pane = "list" }
    }
    Timer {
        interval: Math.max(30, Number(root.setting("refreshSeconds", 120)) || 120) * 1000
        running: true
        repeat: true
        onTriggered: if (!root.confirmingDelete) mail.refresh()
    }
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.icons.mail + (mail.listError ? " !" : mail.unread ? " " + mail.unread : "")
        tooltipText: "Yetimail · " + mail.accountLabel + " · " + (mail.listError ? "Refresh failed" : mail.unread + " unread on page " + mail.page)
        onPressed: { root.opened = !root.opened; if (root.opened) mail.refresh() }
    }
    KeyboardPanel {
        id: panel
        objectName: "mailPanel"
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        contentWidth: Math.max(1, Math.min(940, availableCardWidth - padding * 2))
        contentHeight: {
            var desired = mail.message || mail.reading || mail.readError || root.confirmingDelete || root.showFolders || root.showHelp ? 640 : Math.max(300, sidebar.preferredContentHeight)
            var inset = "verticalContentInset" in panel ? panel.verticalContentInset : panel.padding * 2
            return Math.max(1, Math.round(Math.min(desired + inset, 640, panel.availableCardHeight)))
        }
        focusTarget: sidebar.focusTarget

        FocusScope {
            id: content
            anchors.fill: parent
            // Window shortcuts also work when the selectable message TextArea
            // or a header button owns focus; they don't depend on key bubbling.
            Shortcut { sequences: ["J", "Down"]; enabled: root.opened && !root.confirmingDelete; onActivated: root.navigate(1) }
            Shortcut { sequences: ["K", "Up"]; enabled: root.opened && !root.confirmingDelete; onActivated: root.navigate(-1) }
            Shortcut { sequences: ["Return", "Enter"]; autoRepeat: false; enabled: root.opened && !root.confirmingDelete && !root.showHelp && (root.showFolders || root.pane === "list"); onActivated: root.showFolders ? root.chooseFolder() : root.openCurrent() }
            Shortcut { sequences: ["L", "Right"]; enabled: root.opened && !root.confirmingDelete && !root.showHelp && !(root.showFolders && root.movePicker) && (root.showFolders || root.pane === "list"); onActivated: root.showFolders ? root.chooseFolder() : root.openCurrent() }
            Shortcut { sequence: "F"; enabled: root.opened && !root.confirmingDelete; onActivated: root.toggleFolders() }
            Shortcut { sequence: "G, I"; enabled: root.opened && !root.confirmingDelete; onActivated: root.goFolderRole("inbox") }
            Shortcut { sequence: "G, S"; enabled: root.opened && !root.confirmingDelete; onActivated: root.goFolderRole("sent") }
            Shortcut { sequence: "G, A"; enabled: root.opened && !root.confirmingDelete; onActivated: root.goFolderRole("archive") }
            Shortcut { sequence: "G, T"; enabled: root.opened && !root.confirmingDelete; onActivated: root.goFolderRole("trash") }
            Shortcut { sequences: ["H", "Left"]; enabled: root.opened && !root.confirmingDelete; onActivated: root.back() }
            Shortcut { sequence: "O"; enabled: root.opened && !root.confirmingDelete; onActivated: root.toggleLinks() }
            Shortcut { sequence: "V"; enabled: root.opened && !root.confirmingDelete; onActivated: root.toggleHeaders() }
            Shortcut { sequence: "A"; enabled: root.opened && !root.confirmingDelete; onActivated: root.toggleAttachments() }
            Shortcut { sequence: "S"; autoRepeat: false; enabled: root.opened && !root.confirmingDelete && root.showAttachments; onActivated: root.attachmentAction(false) }
            Shortcut { sequences: ["Return", "Enter"]; autoRepeat: false; enabled: root.opened && !root.confirmingDelete && root.showAttachments; onActivated: root.attachmentAction(true) }
            Shortcut { sequences: ["Return", "Enter", "L", "Right"]; enabled: root.opened && !root.confirmingDelete && root.showLinks; autoRepeat: false; onActivated: root.openLink() }
            Shortcut { sequence: "G, G"; enabled: root.opened && !root.confirmingDelete; onActivated: root.jump(false) }
            Shortcut { sequence: "Shift+G"; enabled: root.opened && !root.confirmingDelete; onActivated: root.jump(true) }
            Shortcut { sequence: "Ctrl+D"; enabled: root.opened && !root.confirmingDelete; onActivated: root.halfPage(1) }
            Shortcut { sequence: "Ctrl+U"; enabled: root.opened && !root.confirmingDelete; onActivated: root.halfPage(-1) }
            Shortcut { sequences: ["Tab", "Shift+Tab"]; enabled: root.opened && !root.confirmingDelete; onActivated: root.switchPane() }
            Shortcut { sequence: "N"; enabled: root.opened && !root.confirmingDelete && !root.busy && !root.showFolders && !root.showHelp; onActivated: mail.nextPage() }
            Shortcut { sequence: "P"; enabled: root.opened && !root.confirmingDelete && !root.busy && !root.showFolders && !root.showHelp; onActivated: mail.previousPage() }
            Shortcut { sequence: "["; enabled: root.opened && !root.confirmingDelete; onActivated: root.moveAccount(-1) }
            Shortcut { sequence: "]"; enabled: root.opened && !root.confirmingDelete; onActivated: root.moveAccount(1) }
            Shortcut { sequence: "Shift+M"; autoRepeat: false; enabled: root.opened && !root.confirmingDelete; onActivated: root.openMovePicker() }
            Shortcut { sequence: "M"; autoRepeat: false; enabled: root.opened && !root.confirmingDelete; onActivated: root.markCurrent(true) }
            Shortcut { sequence: "U"; autoRepeat: false; enabled: root.opened && !root.confirmingDelete; onActivated: root.markCurrent(false) }
            Shortcut { sequences: ["R", "Ctrl+R"]; enabled: root.opened && !root.confirmingDelete && !root.showHelp; onActivated: { if (root.showFolders) { if (!mail.foldersLoading && !root.switchingBlocked) mail.loadFolders() } else mail.refresh() } }
            Shortcut { sequence: "?"; enabled: root.opened && !root.confirmingDelete; onActivated: root.toggleHelp() }
            Shortcut { sequence: "Escape"; enabled: root.opened && !root.confirmingDelete; onActivated: root.handleEscape() }
            Shortcut { sequence: "Q"; enabled: root.opened && !root.confirmingDelete; onActivated: root.close() }

            Shortcut { sequence: "X"; autoRepeat: false; enabled: root.opened && !root.confirmingDelete && !root.busy; onActivated: root.moveToRole(root.targetId, "archive") }
            Shortcut { sequence: "Shift+X"; autoRepeat: false; enabled: root.opened && !root.confirmingDelete && !root.busy; onActivated: root.moveToRole(root.targetId, "trash") }
            Shortcut { sequence: "Delete"; autoRepeat: false; enabled: root.opened && !root.confirmingDelete && !root.busy; onActivated: root.requestDelete(root.targetId) }
            Shortcut { sequences: ["Return", "Enter"]; autoRepeat: false; enabled: root.opened && root.confirmingDelete; onActivated: root.confirmDelete() }
            Shortcut { sequences: ["H", "Escape"]; autoRepeat: false; enabled: root.opened && root.confirmingDelete; onActivated: root.cancelDelete() }

            RowLayout {
                anchors.fill: parent
                enabled: !root.confirmingDelete && !root.showFolders && !root.showHelp
                spacing: 16
                InboxPane {
                    id: sidebar
                    Layout.preferredWidth: Math.min(310, content.width * 0.35)
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: Layout.preferredWidth
                    demo: mail.demo
                    unread: mail.unread
                    loading: mail.loading
                    folderName: mail.folderName
                    accountLabel: mail.accountLabel
                    messages: mail.messages
                    listError: mail.listError
                    page: mail.page
                    hasNext: mail.hasNext
                    deleting: mail.deleting
                    moving: mail.moving
                    marking: mail.marking
                    icons: root.icons
                    busy: root.busy
                    showFolders: root.showFolders
                    switchingBlocked: root.switchingBlocked
                    accounts: root.accounts
                    currentAccount: root.currentAccount
                    cursorId: root.cursorId
                    showHelp: root.showHelp
                    onRefreshRequested: mail.refresh()
                    onFoldersRequested: root.toggleFolders()
                    onAccountRequested: function(name) { root.selectAccount(name) }
                    onListFocused: root.pane = "list"
                    onMessageRequested: function(messageId) { root.cursorId = messageId; root.openCurrent() }
                    onPreviousRequested: mail.previousPage()
                    onNextRequested: mail.nextPage()
                    onHelpRequested: root.toggleHelp()
                }
                Rectangle { Layout.fillHeight: true; width: 1; color: Color.foreground; opacity: 0.15 }
                ReaderPane {
                    id: readerPane
                    panelWidth: content.width
                    message: mail.message
                    folderName: mail.folderName
                    listError: mail.listError
                    actionError: mail.actionError
                    foldersError: mail.foldersError
                    reading: mail.reading
                    readError: mail.readError
                    accountLabel: mail.accountLabel
                    savingAttachment: mail.savingAttachment
                    attachmentStatus: mail.attachmentStatus
                    icons: root.icons
                    showHeaders: root.showHeaders
                    showAttachments: root.showAttachments
                    showLinks: root.showLinks
                    busy: root.busy
                    displayedEnvelope: root.displayedEnvelope
                    messageAttachments: root.messageAttachments
                    messageLinks: root.messageLinks
                    linkIndex: root.linkIndex
                    selectedLink: root.selectedLink
                    attachmentIndex: root.attachmentIndex
                    selectedAttachment: root.selectedAttachment
                    onHeadersRequested: root.toggleHeaders()
                    onAttachmentsRequested: root.toggleAttachments()
                    onLinksRequested: root.toggleLinks()
                    onMarkRequested: function(seen) { root.markMessage(mail.selectedId, seen) }
                    onDeleteRequested: root.requestDelete(mail.selectedId)
                    onCloseRequested: root.close()
                    onAttachmentSelected: function(index) { if (root.busy) return; if (!root.showAttachments) root.toggleAttachments(); root.attachmentIndex = index }
                    onLinkSelected: function(index) { root.linkIndex = index; readerPane.focusLinks() }
                    onOpenLinkRequested: root.openLink()
                    onAttachmentMoved: function(delta) { root.moveAttachment(delta) }
                    onAttachmentActionRequested: function(openAfter) { root.attachmentAction(openAfter) }
                    onReaderFocused: { if (mail.selectedId) root.pane = "reader" }
                }
            }
            DeleteConfirmation {
                id: deleteOverlay
                snapshot: root.deleteSnapshot
                demo: mail.demo
                busy: root.busy
                visible: root.confirmingDelete
                // No focused background button or TextArea receives modal keys.
                Keys.onPressed: function(event) { event.accepted = root.opened && root.confirmingDelete }
                onCancelRequested: root.cancelDelete()
                onConfirmRequested: root.confirmDelete()
            }
            FolderPicker {
                id: folderOverlay
                visible: root.showFolders
                folderId: mail.folderId
                x: sidebar.x + sidebar.folderAnchor.x
                y: sidebar.y + sidebar.folderAnchor.y
                movePicker: root.movePicker
                currentIndex: root.folderIndex
                switchingBlocked: root.switchingBlocked
                loading: mail.foldersLoading
                error: mail.foldersError
                folders: mail.folders
                icons: root.icons
                onFolderChosen: function(index) { root.folderIndex = index; root.chooseFolder() }
                onRetryRequested: mail.loadFolders()
            }
            ShortcutHelp {
                id: helpOverlay
                visible: root.showHelp
                icons: root.icons
                onDismissed: root.showHelp = false
            }
        }
    }
}
