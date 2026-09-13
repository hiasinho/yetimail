import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "Yetimail"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1000
        implicitHeight: 700
        Widget { id: widget; settings: ({demo: true, accounts: "alpha,beta", account: "forbidden"}) }
        TestCase {
            id: test
            name: "OfflineKeyboard"
            when: window.visible
            property var mail
            property var area
            property var scroll
            function find(item, predicate) {
                if (predicate(item)) return item
                var children = item.children || []
                for (var i = 0; i < children.length; i++) {
                    var found = find(children[i], predicate)
                    if (found) return found
                }
                return null
            }
            // Quickshell has no QtTest CLI reporter; expose failures explicitly.
            function equal(actual, expected, message) {
                if (actual !== expected)
                    console.error("KEYBOARD_FAIL " + (message || "comparison") + ": actual=" + actual + " expected=" + expected + "\n" + new Error().stack)
                compare(actual, expected, message)
            }
            function check(condition, message) {
                if (!condition) console.error("KEYBOARD_FAIL " + (message || "verification") + "\n" + new Error().stack)
                verify(condition, message)
            }
            function press(key, modifiers) { keyClick(key, modifiers || Qt.NoModifier); wait(30) }
            function initTestCase() {
                wait(200)
                mail = find(widget, function(item) { return typeof item.readMessage === "function" })
                check(mail !== null, "fixture service found")
                area = find(widget, function(item) { return item.objectName === "messageBody" })
                check(area !== null, "actual message TextArea found")
                scroll = find(widget, function(item) { return item.objectName === "messageReader" })
                check(scroll !== null, "actual reader ScrollView found")
                equal(widget.currentAccount, "alpha", "invalid configured preference falls back to allowlist")
                equal(mail.fixtures.length, 63)
            }
            function init() {
                widget.settings = ({demo: true, accounts: "alpha,beta", account: "forbidden"})
                widget.selectedAccount = "alpha"
                widget.cancelDelete(); mail.deleting = false
                mail.loading = false; mail.reading = false; mail.deferReads = false; mail.pendingReadId = ""; mail.marking = false; mail.moving = false; mail.savingAttachment = false; mail.openingAttachment = false
                mail.folderId = ""; mail.folderName = "Inbox"; mail.foldersLoading = false; mail.foldersLoaded = false; mail.foldersError = ""; mail.folderCache = ({})
                widget.showFolders = false
                widget.showSettings = false
                mail.accountLabels = ({alpha: "Personal", beta: "Work"})
                mail.accountOverview = []
                widget.clearSelection()
                widget.cursorId = ""
                mail.actionError = ""
                mail.populate(); mail.calls = []
                widget.opened = true
                widget.showHelp = false
                widget.focusList()
                wait(50)
            }
            function test_filled_material_icons() {
                equal(widget.icons.mail, "󰇮")
                equal(widget.icons.inbox, "󰻪")
                equal(widget.icons.drafts, "󰷈")
                equal(widget.icons.archive, "󰀼")
                equal(widget.icons.junk, "󰯈")
                equal(widget.icons.trash, "󰩹")
                equal(widget.icons.folder, "󰉋")
                equal(widget.icons.attachment, "󰁦")
                equal(widget.icons.delete, "󰆴")
                equal(widget.icons.agent, "󰙴")
            }
            function test_presentation_lifetime() {
                press(Qt.Key_Return)
                var originalBody = area
                var originalReader = scroll
                var menu = find(widget, function(item) { return item.objectName === "folderMenu" })
                var confirmation = find(widget, function(item) { return item.objectName === "deleteConfirmation" })
                check(menu.parent === confirmation.parent, "modal overlays remain siblings")
                for (var key of [Qt.Key_O, Qt.Key_H, Qt.Key_V, Qt.Key_A,
                        Qt.Key_H, Qt.Key_Question, Qt.Key_Escape, Qt.Key_F, Qt.Key_Escape]) press(key)
                press(Qt.Key_Q)
                widget.opened = true; wait(50)
                equal(find(widget, function(item) { return item.objectName === "messageBody" }), originalBody,
                    "mode changes and reopening preserve the TextArea instance")
                equal(find(widget, function(item) { return item.objectName === "messageReader" }), originalReader,
                    "mode changes and reopening preserve the ScrollView instance")
                equal(area.textFormat, TextEdit.PlainText, "reader remains plain text")
                equal(mail.calls.filter(function(call) { return call.operation === "read" }).length, 1,
                    "presentation mode changes never reread mail")
            }
            function test_inbox_chrome() {
                var title = find(widget, function(item) { return item.objectName === "currentFolderTitle" })
                var footer = find(widget, function(item) { return item.objectName === "inboxFooterStatus" })
                var panel = find(widget, function(item) { return item.objectName === "mailPanel" })
                var newer = find(widget, function(item) { return item.objectName === "newerPageButton" })
                var help = find(widget, function(item) { return item.objectName === "shortcutHelpButton" })
                var inbox = find(widget, function(item) { return item.objectName === "inboxPane" })
                var refresh = find(widget, function(item) { return item.objectName === "inboxRefreshButton" })
                check(title !== null && footer !== null && panel !== null && inbox !== null && refresh !== null, "inbox chrome found")
                equal(title.text, "INBOX / DEMO", "heading names current folder")
                equal(footer.text, "50 unread · 50 msgs · p1", "footer combines unread, count, and page compactly")
                check(!newer.enabled, "Newer is disabled on page one")
                equal(help.text, "?", "shortcut help stays compact")
                var fullPageHeight = panel.contentHeight
                mail.messages = mail.messages.slice(0, 3)
                wait(30)
                equal(footer.text, "3 unread · 3 msgs · p1", "short-page counts update")
                equal(panel.contentHeight, fullPageHeight, "short mailbox page keeps a fixed panel height")
                mail.folderName = "Projects / 2026"
                wait(30)
                equal(title.text, "PROJECTS / 2026 / DEMO", "heading follows folder navigation")
                mail.folderName = "A very long folder name that must not displace refresh"
                wait(30)
                var refreshPosition = refresh.mapToItem(inbox, 0, 0)
                check(title.width <= title.parent.width, "long folder heading stays within its column")
                check(refreshPosition.x + refresh.width <= inbox.width + 0.5, "long folder heading keeps Refresh inside sidebar")
            }
            function test_delete_confirmation() {
                mail.folderId = "Trash"; widget.syncCursor()
                mail.messages = mail.messages.slice(0, 3)
                press(Qt.Key_J); press(Qt.Key_Delete)
                check(widget.confirmingDelete, "Delete in Trash asks")
                var panel = find(widget, function(item) { return item.objectName === "mailPanel" })
                equal(panel.contentHeight, 640, "confirmation preserves the fixed inbox height")
                equal(widget.deleteSnapshot.id, "alpha/2")
                equal(widget.deleteSnapshot.account, "alpha")
                equal(widget.deleteSnapshot.folder, "Trash")
                equal(widget.deleteSnapshot.subject, "Fixture 2")
                var previewCalls = mail.calls.length
                for (var key of [Qt.Key_J, Qt.Key_K, Qt.Key_L, Qt.Key_Right, Qt.Key_Left,
                        Qt.Key_F, Qt.Key_O, Qt.Key_V, Qt.Key_A, Qt.Key_S, Qt.Key_M, Qt.Key_U,
                        Qt.Key_N, Qt.Key_P, Qt.Key_R, Qt.Key_Tab, Qt.Key_BracketRight,
                        Qt.Key_BracketLeft, Qt.Key_Question, Qt.Key_Q, Qt.Key_Delete, Qt.Key_X, Qt.Key_Space]) press(key)
                press(Qt.Key_X, Qt.ShiftModifier)
                press(Qt.Key_M, Qt.ShiftModifier); press(Qt.Key_D, Qt.ControlModifier)
                press(Qt.Key_G); press(Qt.Key_T)
                equal(mail.calls.length, previewCalls, "all other modal shortcuts blocked")
                equal(widget.cursorId, "alpha/2")
                check(widget.confirmingDelete && widget.opened)
                press(Qt.Key_H)
                check(!widget.confirmingDelete && widget.opened)
                press(Qt.Key_Delete); press(Qt.Key_Escape)
                equal(mail.calls.length, previewCalls, "cancellation is inert")
                press(Qt.Key_Delete)
                var cancel = find(widget, function(item) { return item.objectName === "cancelDelete" })
                mouseClick(cancel, cancel.width / 2, cancel.height / 2); wait(30)
                check(!widget.confirmingDelete)
                equal(mail.calls.length, previewCalls, "Cancel button is inert")
                press(Qt.Key_Delete); press(Qt.Key_Return)
                var deletes = mail.calls.filter(function(call) { return call.operation === "delete" })
                equal(deletes.length, 1)
                equal(deletes[0].id, "alpha/2")
                equal(widget.cursorId, "alpha/3", "next row preserved")
                widget.confirmDelete()
                equal(mail.calls.filter(function(call) { return call.operation === "delete" }).length, 1,
                    "duplicate confirmation is inert")
                press(Qt.Key_Return)
                widget.cursorId = "alpha/4"
                var button = find(widget, function(item) { return item.objectName === "readerDelete" })
                mouseClick(button, button.width / 2, button.height / 2); wait(30)
                check(widget.confirmingDelete, "toolbar in Trash asks")
                equal(widget.deleteSnapshot.id, "alpha/3", "toolbar targets displayed message")
                var confirm = find(widget, function(item) { return item.objectName === "confirmDelete" })
                mouseClick(confirm, confirm.width / 2, confirm.height / 2); wait(30)
                equal(mail.calls[mail.calls.length - 1].id, "alpha/3")
                equal(mail.selectedId, ""); equal(mail.message, null)
            }
            function test_delete_cancel_restores_focus() {
                mail.folderId = "Trash"; widget.syncCursor()
                press(Qt.Key_Return)
                check(area.activeFocus, "reader starts focused")
                var calls = mail.calls.length
                var cancel = find(widget, function(item) { return item.objectName === "cancelDelete" })
                for (var action of ["h", "escape", "button"]) {
                    press(Qt.Key_Delete)
                    check(widget.confirmingDelete && !area.activeFocus, "confirmation owns focus")
                    if (action === "h") press(Qt.Key_H)
                    else if (action === "escape") press(Qt.Key_Escape)
                    else { mouseClick(cancel, cancel.width / 2, cancel.height / 2); wait(30) }
                    check(!widget.confirmingDelete && widget.opened, action + " dismisses only confirmation")
                    equal(widget.pane, "reader")
                    check(area.activeFocus, action + " restores reader TextArea focus")
                    // Native TextArea handling, not a Yetimail Shortcut, must work.
                    press(Qt.Key_A, Qt.ControlModifier)
                    check(area.selectedText.length > 0, action + " restores native text selection")
                    area.deselect()
                    equal(mail.calls.length, calls, "cancellation never invokes backend")
                }
                press(Qt.Key_Delete)
                mail.generation++
                check(!widget.confirmingDelete && !area.activeFocus, "state reset does not force reader focus")
                area.forceActiveFocus()
                press(Qt.Key_Delete)
                widget.close()
                check(!widget.confirmingDelete && !area.activeFocus, "closing does not restore reader focus")
            }
            function test_delete_stale_and_busy() {
                mail.folderId = "Trash"; widget.syncCursor()
                for (var flag of ["loading", "reading", "marking", "moving", "deleting", "savingAttachment", "openingAttachment"]) {
                    mail[flag] = true
                    press(Qt.Key_Delete)
                    check(!widget.confirmingDelete, flag + " blocks prompt")
                    mail[flag] = false
                    widget.requestDelete(widget.targetId)
                    check(widget.confirmingDelete)
                    mail[flag] = true
                    check(!widget.confirmingDelete, flag + " clears existing prompt")
                    widget.confirmDelete()
                    equal(mail.calls.length, 0, "busy changes cannot submit")
                    mail[flag] = false
                }
                var mutations = [function() { widget.close() }, function() { mail.generation++ },
                    function() { mail.folderId = "INBOX" }, function() { widget.selectedAccount = "beta" },
                    function() { widget.cursorId = "alpha/9" }, function() { mail.loading = true },
                    function() { mail.messages = mail.messages.slice() }, function() { mail.readRequest++ },
                    function() { mail.listRequest++ }, function() { mail.page++ },
                    function() { mail.config += "changed" }, function() { widget.pane = "reader" },
                    function() { mail.messages = mail.messages.map(function(row) {
                        return Object.assign({}, row, {subject: "changed"}) }) }]
                for (var mutate of mutations) {
                    init()
                    mail.folderId = "Trash"; widget.syncCursor()
                    widget.requestDelete(widget.targetId)
                    check(widget.confirmingDelete)
                    var stale = widget.deleteSnapshot
                    mutate()
                    check(!widget.confirmingDelete, "state change clears prompt")
                    // Even if a stale UI snapshot survives notification delivery,
                    // confirmation must revalidate rather than retarget.
                    widget.deleteSnapshot = stale
                    widget.confirmDelete()
                    equal(mail.calls.filter(function(c) { return c.operation === "delete" }).length, 0, "stale snapshot never deletes")
                }
            }
            function test_archive_and_trash() {
                press(Qt.Key_J); press(Qt.Key_X)
                var firstMove = mail.calls.filter(function(call) { return call.operation === "move" })[0]
                equal(firstMove.id, "alpha/2")
                equal(firstMove.seen, "Archive")
                equal(widget.cursorId, "alpha/3")
                check(!widget.confirmingDelete)
                press(Qt.Key_Return)
                widget.cursorId = "alpha/4"
                press(Qt.Key_X, Qt.ShiftModifier)
                equal(mail.calls[mail.calls.length - 1].id, "alpha/3", "reader target")
                equal(mail.calls[mail.calls.length - 1].seen, "Trash")
                check(!widget.confirmingDelete)
                var count = mail.calls.length
                press(Qt.Key_Delete)
                equal(mail.calls.length, count + 1)
                equal(mail.calls[mail.calls.length - 1].operation, "move")
                equal(mail.calls[mail.calls.length - 1].seen, "Trash", "Delete outside Trash moves immediately")
                check(!widget.confirmingDelete)
                press(Qt.Key_Return)
                var displayed = mail.selectedId
                widget.cursorId = "alpha/9"
                var button = find(widget, function(item) { return item.objectName === "readerDelete" })
                mouseClick(button, button.width / 2, button.height / 2); wait(30)
                equal(mail.calls[mail.calls.length - 1].operation, "move")
                equal(mail.calls[mail.calls.length - 1].id, displayed, "toolbar trashes displayed message")
                equal(mail.calls[mail.calls.length - 1].seen, "Trash")
                check(!widget.confirmingDelete)
                mail.folderId = "Trash"
                widget.syncCursor()
                mail.calls = []
                press(Qt.Key_X, Qt.ShiftModifier)
                equal(mail.calls.length, 0, "Shift+X in Trash is inert")
                check(!widget.confirmingDelete)
                mail.folderId = "Archive"
                widget.syncCursor()
                press(Qt.Key_X)
                equal(mail.calls.length, 0, "x in Archive is inert")
                mail.folderId = "INBOX"
                widget.syncCursor()
                for (var flag of ["loading", "reading", "marking", "deleting", "savingAttachment", "openingAttachment"]) {
                    mail[flag] = true
                    press(Qt.Key_X); press(Qt.Key_X, Qt.ShiftModifier); press(Qt.Key_Delete)
                    equal(mail.calls.length, 0, flag + " blocks moves")
                    mail[flag] = false
                }
                for (var modal of ["showHelp", "showFolders"]) {
                    widget[modal] = true
                    press(Qt.Key_X); press(Qt.Key_X, Qt.ShiftModifier); press(Qt.Key_Delete)
                    equal(mail.calls.length, 0, modal + " blocks moves")
                    widget[modal] = false
                }
                widget.close()
                widget.moveToRole(widget.targetId, "trash")
                equal(mail.calls.length, 0, "closed panel is inert")
                widget.opened = true
                var folders = mail.folders
                for (var unavailable of [[], folders.concat([{id: "Trash2", name: "Trash2", role: "trash"}, {id: "Archive2", name: "Archive2", role: "archive"}])]) {
                    mail.folders = unavailable
                    press(Qt.Key_X); press(Qt.Key_X, Qt.ShiftModifier); press(Qt.Key_Delete)
                    equal(mail.calls.length, 0, "unresolved roles never mutate")
                    check(!widget.confirmingDelete)
                }
                mail.folders = folders
            }
            function test_move_queue_shortcuts_remain_responsive() {
                mail.folderId = "INBOX"
                widget.syncCursor()
                mail.moving = true
                var first = widget.targetId
                press(Qt.Key_X)
                equal(mail.calls[mail.calls.length - 1].id, first, "archive accepted while another move runs")
                var second = widget.targetId
                press(Qt.Key_X, Qt.ShiftModifier)
                equal(mail.calls[mail.calls.length - 1].id, second, "trash accepted while another move runs")
                press(Qt.Key_M, Qt.ShiftModifier)
                check(widget.showFolders && widget.movePicker, "move picker opens while queue runs")
                widget.dismissFolders()
                mail.moving = false
                mail.pendingMoves = 2
                mail.movePaused = true
                var retry = find(widget, function(item) { return item.objectName === "retryMovesButton" })
                var cancel = find(widget, function(item) { return item.objectName === "cancelMovesButton" })
                var status = find(widget, function(item) { return item.objectName === "inboxFooterStatus" })
                check(retry.visible && cancel.visible && status.text.indexOf("2 messages pending") >= 0, "paused queue controls and status")
                retry.clicked()
                equal(mail.calls[mail.calls.length - 1].operation, "retryMoves")
                mail.movePaused = true
                cancel.clicked()
                equal(mail.calls[mail.calls.length - 1].operation, "cancelMoves")
            }
            function test_bulk_selection_and_actions() {
                equal(widget.cursorId, "alpha/1")
                press(Qt.Key_Space)
                equal(widget.selectedCount, 1, "Space selects cursor without opening")
                equal(mail.calls.length, 0)
                press(Qt.Key_J); press(Qt.Key_Space)
                equal(widget.selectedCount, 2, "navigation preserves selection")
                press(Qt.Key_M)
                var marks = mail.calls.filter(function(call) { return call.operation === "mark" })
                equal(marks.length, 2, "mark applies to selected rows")
                equal(marks[0].id, "alpha/1"); equal(marks[1].id, "alpha/2")
                equal(widget.selectedCount, 2, "marking preserves selection")
                press(Qt.Key_Escape)
                equal(widget.selectedCount, 0, "Escape clears selection first")
                check(widget.opened)
                press(Qt.Key_A, Qt.ControlModifier)
                equal(widget.selectedCount, 50, "Ctrl+A selects only current page")
                press(Qt.Key_N)
                equal(mail.page, 2)
                equal(widget.selectedCount, 0, "page change clears selection")
                equal(mail.messages.length, 13)
                press(Qt.Key_P)
                widget.cursorId = "alpha/1"
                press(Qt.Key_Space); press(Qt.Key_J); press(Qt.Key_J); press(Qt.Key_Space)
                press(Qt.Key_X)
                var moves = mail.calls.filter(function(call) { return call.operation === "move" })
                equal(moves.length, 2, "archive applies to selected rows")
                equal(moves[0].id, "alpha/1"); equal(moves[1].id, "alpha/3")
                equal(moves[0].seen, "Archive"); equal(moves[1].seen, "Archive")
                equal(widget.selectedCount, 0, "accepted bulk move clears selection")
                equal(widget.cursorId, "alpha/4", "cursor advances to surviving row")
            }
            function test_selection_mouse_reader_and_permanent_delete_safety() {
                var rowMouse = find(widget, function(item) { return item.objectName === "messageRowMouseArea" })
                check(rowMouse !== null, "message row found")
                mouseClick(rowMouse, rowMouse.width / 2, rowMouse.height / 2, Qt.LeftButton, Qt.ControlModifier); wait(30)
                equal(widget.selectedCount, 1, "Ctrl-click selects without opening")
                equal(mail.selectedId, "")
                press(Qt.Key_J); press(Qt.Key_Return)
                equal(mail.selectedId, "alpha/2")
                widget.focusList()
                var readerDelete = find(widget, function(item) { return item.objectName === "readerDelete" })
                readerDelete.clicked(); wait(30)
                equal(mail.calls[mail.calls.length - 1].id, "alpha/2", "reader toolbar ignores retained list selection")
                equal(widget.selectedCount, 1)
                widget.focusList()
                mail.folderId = "Trash"; mail.folderName = "Trash"
                equal(widget.selectedCount, 0, "folder change clears selection")
                widget.cursorId = "alpha/1"
                press(Qt.Key_Space); press(Qt.Key_J); press(Qt.Key_Space)
                equal(widget.selectedCount, 2)
                var before = mail.calls.length
                press(Qt.Key_Delete)
                equal(mail.calls.length, before, "multiple Trash selections never delete")
                check(!widget.confirmingDelete)
                check(mail.actionError.indexOf("one message at a time") >= 0)
            }
            function test_move_picker() {
                mail.folderId = "INBOX"
                widget.syncCursor()
                press(Qt.Key_J)
                press(Qt.Key_M, Qt.ShiftModifier)
                check(widget.showFolders && widget.movePicker, "Shift+M opens move picker")
                compare(widget.moveTargetIds, ["alpha/2"])
                equal(mail.calls.filter(function(call) { return call.operation === "folders" }).length, 1,
                    "opening picker only discovers folders")
                var pickerCallCount = mail.calls.length
                press(Qt.Key_Return)
                equal(mail.calls.length, pickerCallCount, "current folder cannot be a destination")
                press(Qt.Key_M); press(Qt.Key_U)
                equal(mail.calls.length, pickerCallCount, "mark actions blocked in picker")
                press(Qt.Key_J); press(Qt.Key_J); press(Qt.Key_Return)
                check(!widget.showFolders)
                var chosenMove = mail.calls.filter(function(call) { return call.operation === "move" })[0]
                equal(chosenMove.id, "alpha/2")
                equal(chosenMove.seen, "Archive", "chosen destination")
                equal(mail.folderId, "INBOX", "move does not navigate")
                equal(widget.cursorId, "alpha/3", "next row selected")
                press(Qt.Key_M)
                equal(mail.calls.filter(function(call) { return call.operation === "mark" }).length, 1,
                    "lowercase m still marks read")
                press(Qt.Key_M, Qt.ShiftModifier); press(Qt.Key_H)
                check(!widget.showFolders)
                press(Qt.Key_M, Qt.ShiftModifier); press(Qt.Key_Escape)
                check(!widget.showFolders && widget.opened)
                equal(mail.calls.filter(function(call) { return call.operation === "move" }).length, 1, "cancel never moves")
                press(Qt.Key_Return)
                widget.cursorId = "alpha/4"
                press(Qt.Key_M, Qt.ShiftModifier)
                compare(widget.moveTargetIds, ["alpha/3"], "reader targets displayed message not cursor")
                press(Qt.Key_G, Qt.ShiftModifier); press(Qt.Key_Return)
                equal(mail.calls[mail.calls.length - 1].id, "alpha/3")
                equal(mail.calls[mail.calls.length - 1].seen, "Projects/2026")
                press(Qt.Key_M, Qt.ShiftModifier)
                check(widget.showFolders, "move picker open before config change")
                mail.config = "new-offline-config"
                wait(30)
                check(!widget.showFolders, "configuration generation change dismisses stale move target")
                for (var flag of ["loading", "reading", "marking", "savingAttachment", "openingAttachment"]) {
                    mail[flag] = true
                    press(Qt.Key_M, Qt.ShiftModifier)
                    check(!widget.showFolders, flag + " prevents moving")
                    mail[flag] = false
                }
            }
            function test_account_settings_and_labels() {
                var settingsButton = find(widget, function(item) { return item.objectName === "accountSettingsButton" })
                var folderButton = find(widget, function(item) { return item.objectName === "folderButton" })
                check(settingsButton !== null, "account settings button found")
                check(settingsButton.x > folderButton.x, "settings gear follows mailbox controls")
                var before = mail.calls.length
                mouseClick(settingsButton, settingsButton.width / 2, settingsButton.height / 2); wait(50)
                check(widget.showSettings, "gear opens account overview")
                equal(mail.calls.length, before + 1, "opening settings only requests offline account metadata")
                equal(mail.calls[mail.calls.length - 1].operation, "accounts")
                var list = find(widget, function(item) { return item.objectName === "accountSettingsList" })
                var field = find(widget, function(item) { return item.objectName === "accountLabelField" })
                var save = find(widget, function(item) { return item.objectName === "saveAccountLabelButton" })
                var enabled = find(widget, function(item) { return item.objectName === "accountEnabledButton" })
                var email = find(widget, function(item) { return item.objectName === "accountEmailField" })
                var sender = find(widget, function(item) { return item.objectName === "accountDisplayNameField" })
                var inboxMapping = find(widget, function(item) { return item.objectName === "accountInboxField" })
                var makeDefault = find(widget, function(item) { return item.objectName === "accountDefaultButton" })
                var saveConfig = find(widget, function(item) { return item.objectName === "saveAccountConfigButton" })
                var settings = find(widget, function(item) { return item.objectName === "accountSettings" })
                check(list !== null && field !== null && save !== null && enabled !== null && email !== null
                    && sender !== null && inboxMapping !== null && makeDefault !== null && saveConfig !== null && settings !== null,
                    "account editor controls found")
                equal(list.count, 3, "overview includes configured accounts outside the mail allowlist")
                var overview = mail.accountOverview
                mail.accountOverview = []
                settings.focusAccount("beta")
                mail.accountOverview = overview
                wait(30)
                equal(field.text, "Work", "asynchronous discovery preserves the requested account")
                equal(email.text, "beta@example.test", "Himalaya email is editable")
                email.text = "new-beta@example.test"
                widget.saveAllowedAccount("configured-only", true)
                wait(30)
                equal(email.text, "new-beta@example.test", "mail access changes preserve unsaved configuration fields")
                field.text = "Pending Beta Label"
                var refreshed = mail.accountOverview.map(function(item) {
                    if (item.id !== "beta") return item
                    var copy = Object.assign({}, item)
                    copy.revision = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
                    copy["mailbox-mappings"] = Object.assign({}, item["mailbox-mappings"], {inbox: "External Inbox"})
                    return copy
                })
                mail.accountOverview = refreshed
                wait(30)
                equal(field.text, "Pending Beta Label", "overview refresh preserves an unsaved label")
                equal(email.text, "new-beta@example.test", "overview refresh preserves an unsaved identity")
                equal(settings.editorRevision, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    "preserved drafts retain their stale-write revision")
                equal(inboxMapping.text, "", "an external mapping is not merged invisibly into a draft")
                sender.text = "New Beta Sender"
                makeDefault.clicked()
                saveConfig.clicked()
                wait(30)
                equal(mail.accountOverview[1].email, "new-beta@example.test", "identity edits reach the service")
                check(mail.accountOverview[1].default && !mail.accountOverview[0].default, "default edit remains unique")
                equal(mail.calls[mail.calls.length - 1].operation, "account-save")
                settings.focusAccount("configured-only")
                check(!email.enabled, "unsupported configurations remain read-only")
                check(widget.accounts.indexOf("configured-only") >= 0, "mail access updates the persisted allowlist state")
                settings.focusAccount("alpha")
                equal(field.text, "Personal", "saved friendly label is editable")
                var page = mail.page
                before = mail.calls.length
                press(Qt.Key_N); press(Qt.Key_R); press(Qt.Key_BracketRight); press(Qt.Key_Delete)
                equal(mail.calls.length, before, "settings blocks mailbox shortcuts")
                equal(mail.page, page)
                field.text = "Home mail"
                mouseClick(save, save.width / 2, save.height / 2); wait(30)
                equal(mail.accountLabels.alpha, "Home mail", "saving updates the display label")
                equal(mail.calls[mail.calls.length - 1].operation, "account-label")
                equal(mail.calls[mail.calls.length - 1].id, "alpha")
                equal(mail.calls[mail.calls.length - 1].seen, "Home mail")
                press(Qt.Key_Escape)
                check(!widget.showSettings && widget.opened, "Escape returns to mail")
                widget.settings = ({demo: true, accounts: "", account: ""})
                mail.accountOverview = [{id: "alpha", label: "Home mail", email: "alpha@example.test", "display-name": "Alpha Sender", default: true, receiving: ["imap"], sending: ["smtp"]}]
                wait(30)
                equal(widget.accountDisplayName(mail.accountLabel), "Home mail", "unnamed default account resolves its configured label")
                widget.settings = ({demo: true, accounts: "alpha,beta", account: "forbidden"})
                wait(30)
                mouseClick(find(widget, function(item) { return item.objectName === "accountButton" }), 18, 18); wait(30)
                check(find(widget, function(item) { return item.text === "Home mail" }) !== null,
                    "account picker uses the friendly label while retaining account IDs")
                press(Qt.Key_Escape)
                widget.settings = ({demo: true, accounts: "constructor,__proto__", account: "constructor"})
                mail.accountLabels = JSON.parse('{"constructor":"Builder","__proto__":"Prototype"}')
                wait(30)
                equal(widget.accountDisplayName("constructor"), "Builder", "inherited JavaScript names remain valid account IDs")
                mouseClick(find(widget, function(item) { return item.objectName === "accountButton" }), 18, 18); wait(30)
                check(find(widget, function(item) { return item.text === "Builder" }) !== null
                    && find(widget, function(item) { return item.text === "Prototype" }) !== null,
                    "picker uses own label properties for unusual account IDs")
                press(Qt.Key_Escape)
                widget.settings = ({demo: true, accounts: "alpha,beta", account: "forbidden"})
                wait(30)
            }
            function test_folder_navigation() {
                press(Qt.Key_Return); press(Qt.Key_N)
                equal(mail.page, 2)
                var accountButton = find(widget, function(item) { return item.objectName === "accountButton" })
                var folderButton = find(widget, function(item) { return item.objectName === "folderButton" })
                check(accountButton !== null && folderButton !== null, "account and mailbox icon buttons found")
                equal(accountButton.x, 0, "account dropdown comes first")
                equal(accountButton.y, folderButton.y, "account and mailbox buttons align")
                equal(accountButton.height, folderButton.height, "account and mailbox buttons share a height")
                equal(accountButton.bordered, false, "footer utility buttons have no outline")
                check(folderButton.x > accountButton.x && folderButton.width <= 30 && folderButton.tooltipText.indexOf("Inbox") !== -1,
                    "compact mailbox icon follows account icon")
                var inboxPane = find(widget, function(item) { return item.objectName === "inboxPane" })
                var accountPosition = accountButton.mapToItem(inboxPane, 0, 0)
                check(accountPosition.y > inboxPane.height / 2, "account and mailbox controls live in the footer")
                mouseClick(accountButton, accountButton.width / 2, accountButton.height / 2); wait(30)
                check(widget.showAccounts, "account icon opens dropdown")
                var dismissArea = find(widget, function(item) { return item.objectName === "pickerDismissArea" })
                var buttonPoint = accountButton.mapToItem(window.contentItem, accountButton.width / 2, accountButton.height / 2)
                mouseClick(window.contentItem, buttonPoint.x, buttonPoint.y); wait(30)
                check(!widget.showAccounts, "clicking the account icon area again closes dropdown")
                mouseClick(accountButton, accountButton.width / 2, accountButton.height / 2); wait(30)
                mouseClick(dismissArea, dismissArea.width - 5, dismissArea.height - 5); wait(30)
                check(!widget.showAccounts, "clicking outside closes dropdown")
                mouseClick(accountButton, accountButton.width / 2, accountButton.height / 2); wait(30)
                var accountMenu = find(widget, function(item) { return item.objectName === "accountMenu" })
                var accountPicker = find(widget, function(item) { return item.objectName === "accountPicker" })
                equal(accountPicker.count, 2, "account dropdown lists allowed accounts")
                var accountAnchor = accountMenu.mapToItem(accountButton, 0, 0)
                equal(accountAnchor.x, 0, "account menu left aligns with icon")
                equal(accountAnchor.y, -accountMenu.height - 2, "account menu opens above footer icon")
                press(Qt.Key_J); press(Qt.Key_Return)
                equal(widget.currentAccount, "beta", "account dropdown chooses highlighted account")
                check(!widget.showAccounts)
                press(Qt.Key_BracketLeft); equal(widget.currentAccount, "alpha")
                press(Qt.Key_N); equal(mail.page, 2)
                mouseClick(folderButton, folderButton.width / 2, folderButton.height / 2); wait(30)
                check(widget.showFolders, "folder icon opens dropdown")
                var menu = find(widget, function(item) { return item.objectName === "folderMenu" })
                var picker = find(widget, function(item) { return item.objectName === "folderPicker" })
                check(menu.width >= 160 && menu.width <= 200, "dropdown has compact width")
                equal(menu.height, mail.folders.length * 32 + 2, "short menu hugs discovered rows")
                var anchor = menu.mapToItem(folderButton, 0, 0)
                equal(anchor.x, 0, "menu left aligns with icon")
                equal(anchor.y, -menu.height - 2, "menu opens above footer icon")
                equal(picker.count, mail.folders.length, "only discovered folders are listed")
                check(find(picker, function(item) { return item.text === "Sent mail" }) !== null, "folder name shown without role suffix")
                equal(mail.calls.filter(function(call) { return call.operation === "folders" }).length, 1,
                    "first opening discovers folders")
                mouseClick(dismissArea, dismissArea.width - 5, dismissArea.height - 5); wait(30)
                mouseClick(folderButton, folderButton.width / 2, folderButton.height / 2); wait(30)
                equal(mail.calls.filter(function(call) { return call.operation === "folders" }).length, 1,
                    "reopening reuses cached folders")
                equal(widget.folderIndex, 0)
                var count = mail.calls.length
                press(Qt.Key_M); press(Qt.Key_U); press(Qt.Key_N); press(Qt.Key_P)
                press(Qt.Key_O); press(Qt.Key_V); press(Qt.Key_A); press(Qt.Key_S); press(Qt.Key_Tab)
                equal(mail.calls.length, count, "picker blocks mailbox actions")
                equal(mail.page, 2)
                press(Qt.Key_J); equal(widget.folderIndex, 1)
                press(Qt.Key_K); equal(widget.folderIndex, 0)
                press(Qt.Key_G, Qt.ShiftModifier); equal(widget.folderIndex, 4)
                press(Qt.Key_G); press(Qt.Key_G); equal(widget.folderIndex, 0)
                press(Qt.Key_G, Qt.ShiftModifier); press(Qt.Key_L)
                check(!widget.showFolders)
                equal(mail.folderId, "Projects/2026"); equal(mail.folderName, "Projects / 2026")
                equal(mail.page, 1); equal(mail.selectedId, ""); equal(widget.pane, "list")
                equal(mail.calls[mail.calls.length - 1].operation, "folder", "l chooses, never reads")
                var roles = [Qt.Key_I, Qt.Key_S, Qt.Key_A, Qt.Key_T]
                var ids = ["INBOX", "Sent", "Archive", "Trash"]
                for (var i = 0; i < roles.length; i++) {
                    press(Qt.Key_G); press(roles[i]); equal(mail.folderId, ids[i])
                }
                press(Qt.Key_F); press(Qt.Key_H); check(!widget.showFolders)
                press(Qt.Key_F); press(Qt.Key_Escape); check(!widget.showFolders); check(widget.opened)
                press(Qt.Key_Question); check(widget.showHelp)
                press(Qt.Key_F); check(widget.showFolders && !widget.showHelp)
                press(Qt.Key_Question); check(widget.showHelp && !widget.showFolders)
                count = mail.calls.length
                press(Qt.Key_Return); press(Qt.Key_G); press(Qt.Key_S)
                equal(mail.calls.length, count, "help blocks read and role shortcuts")
                press(Qt.Key_Escape)
                press(Qt.Key_Return)
                mail.message = {body: "Links", links: [{label: "Example", url: "https://example.test/"}]}
                var urls = []
                widget.openUrl = function(url) { urls.push(url) }
                press(Qt.Key_O); check(widget.showLinks)
                press(Qt.Key_F); check(!widget.showLinks)
                press(Qt.Key_J); press(Qt.Key_Return)
                equal(urls.length, 0, "picker Enter never opens a link")
                equal(mail.calls[mail.calls.length - 1].operation, "folder")
                var flags = ["moving", "marking", "savingAttachment", "openingAttachment"]
                for (i = 0; i < flags.length; i++) {
                    mail[flags[i]] = true
                    count = mail.calls.length
                    var folder = mail.folderId
                    press(Qt.Key_F); check(!widget.showFolders, flags[i] + " blocks picker")
                    press(Qt.Key_G); press(Qt.Key_I); press(Qt.Key_BracketRight)
                    widget.selectAccount("beta")
                    equal(widget.currentAccount, "alpha"); equal(mail.folderId, folder)
                    equal(mail.calls.length, count, flags[i] + " blocks switching")
                    mail[flags[i]] = false
                    press(Qt.Key_F)
                    mail[flags[i]] = true
                    count = mail.calls.length
                    press(Qt.Key_Return); press(Qt.Key_R); press(Qt.Key_BracketRight)
                    equal(mail.calls.length, count, "busy picker blocks choose/retry/account")
                    check(widget.showFolders)
                    mail[flags[i]] = false
                    press(Qt.Key_Escape)
                }
                press(Qt.Key_F)
                mail.foldersLoaded = false
                mail.foldersLoading = true
                count = mail.calls.length
                press(Qt.Key_Return); press(Qt.Key_R)
                equal(mail.calls.length, count, "cold loading prevents choice and duplicate folder request")
                mail.foldersLoading = false; mail.foldersError = "Offline folder failure"
                press(Qt.Key_R); equal(mail.foldersError, "")
                equal(mail.calls[mail.calls.length - 1].operation, "folders", "r retries folder discovery")
                press(Qt.Key_BracketRight)
                equal(widget.currentAccount, "beta"); equal(mail.folderId, ""); equal(mail.folderName, "Inbox")
                check(!widget.showFolders, "account change clears picker")
                var folders = mail.folders
                mail.folders = folders.filter(function(folder) { return folder.role !== "archive" })
                press(Qt.Key_G); press(Qt.Key_A)
                check(mail.foldersError.indexOf("archive") !== -1, "unavailable role error preserved")
                equal(mail.folderId, "")
                var errors = find(widget, function(item) { return item.objectName === "mailErrors" })
                check(errors.visible && errors.text.indexOf("archive") !== -1, "role error is visible in UI")
                count = mail.calls.length
                press(Qt.Key_E); equal(mail.calls.length, count, "e adds no archive mutation")
                var manyFolders = folders.slice()
                for (i = 0; i < 30; i++) manyFolders.push({id: "extra/" + i, name: "Extra " + i, role: ""})
                mail.folders = manyFolders
                press(Qt.Key_F)
                check(menu.height <= 322 && picker.contentHeight > picker.height, "long dropdown is capped and scrollable")
                press(Qt.Key_G, Qt.ShiftModifier)
                equal(widget.folderIndex, manyFolders.length - 1)
                check(picker.contentY > 0, "last folder scrolls into view")
                press(Qt.Key_G); press(Qt.Key_G); equal(widget.folderIndex, 0)
                mail.folders = folders
                press(Qt.Key_Q); check(!widget.showFolders && !widget.opened)
            }
            function test_folder_cache_by_account() {
                function folderLoads() {
                    return mail.calls.filter(function(call) { return call.operation === "folders" })
                }
                press(Qt.Key_F)
                equal(folderLoads().length, 1, "first account discovery loads folders")
                press(Qt.Key_Escape); press(Qt.Key_F)
                equal(folderLoads().length, 1, "reopening uses current account cache")
                press(Qt.Key_Escape); press(Qt.Key_BracketRight)
                equal(widget.currentAccount, "beta")
                check(!mail.foldersLoaded, "new account starts without cached discovery")
                press(Qt.Key_F)
                equal(folderLoads().length, 2, "new account loads its own folders")
                press(Qt.Key_Escape); press(Qt.Key_BracketLeft)
                equal(widget.currentAccount, "alpha")
                check(mail.foldersLoaded, "returning account restores cached discovery")
                press(Qt.Key_F)
                equal(folderLoads().length, 2, "restored account does not reload folders")
                press(Qt.Key_J)
                var originalFolders = mail.folders.slice()
                var highlightedId = mail.folders[widget.folderIndex].id
                mail.folders = mail.folders.slice().reverse()
                equal(mail.folders[widget.folderIndex].id, highlightedId,
                    "refresh reorder preserves the highlighted folder by id")

                var status = find(widget, function(item) { return item.objectName === "folderStatus" })
                mail.foldersLoading = true
                check(!status.visible, "cached folders hide background refresh state")
                var count = mail.calls.length
                press(Qt.Key_Return)
                equal(mail.calls.length, count + 1, "cached folders remain selectable while refreshing")
                check(!widget.showFolders)
                mail.foldersLoading = false
                mail.folders = originalFolders
                press(Qt.Key_F); press(Qt.Key_R)
                equal(folderLoads().length, 3, "r explicitly refreshes the current account cache")
                press(Qt.Key_Escape)
            }
            function test_navigation() {
                equal(mail.messages.length, 50)
                equal(widget.cursorId, "alpha/1")
                press(Qt.Key_J); equal(widget.cursorId, "alpha/2")
                equal(mail.selectedId, "alpha/2"); equal(mail.message.id, "alpha/2")
                equal(widget.pane, "list", "preview keeps keyboard focus in the list")
                check(mail.messages[1].unread, "preview does not mark the message seen")
                press(Qt.Key_K); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_K); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_G, Qt.ShiftModifier); equal(widget.cursorId, "alpha/50")
                press(Qt.Key_J); equal(widget.cursorId, "alpha/50")
                press(Qt.Key_G); press(Qt.Key_G); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_D, Qt.ControlModifier); check(widget.cursorIndex > 0)
                press(Qt.Key_U, Qt.ControlModifier); equal(widget.cursorId, "alpha/1")
                check(mail.calls.some(function(call) { return call.operation === "read" }), "navigation previews messages")
                check(!mail.calls.some(function(call) { return call.operation === "mark" }), "navigation never changes read status")
                equal(mail.selectedId, widget.cursorId, "the preview follows the list cursor")
            }
            function test_rapid_navigation_previews_latest_message() {
                mail.deferReads = true
                press(Qt.Key_J)
                equal(mail.pendingReadId, "alpha/2")
                press(Qt.Key_Space); equal(widget.selectedCount, 1, "selection remains responsive during preview reads")
                press(Qt.Key_J); press(Qt.Key_J)
                equal(widget.cursorId, "alpha/4")
                equal(mail.calls.filter(function(call) { return call.operation === "read" }).length, 1,
                    "an in-flight preview is not replaced unsafely")
                widget.showHelp = true
                mail.finishRead(); wait(30)
                equal(mail.pendingReadId, "", "an overlay pauses the queued preview")
                widget.showHelp = false; wait(30)
                equal(mail.pendingReadId, "alpha/4", "latest cursor resumes after the overlay closes")
                equal(mail.calls.filter(function(call) { return call.operation === "read" }).length, 2)
                mail.finishRead(); wait(30)
                equal(mail.message.id, "alpha/4")
                equal(mail.selectedId, "alpha/4")
                equal(widget.pane, "list")
                check(mail.messages[3].unread)
                check(!mail.calls.some(function(call) { return call.operation === "mark" }))
                mail.deferReads = false
                mail.marking = true; press(Qt.Key_J)
                equal(mail.selectedId, "alpha/4", "a mutation pauses previews")
                mail.marking = false; wait(30)
                equal(mail.selectedId, "alpha/5", "preview resumes after a mutation")
                mail.deferReads = true
                press(Qt.Key_J); press(Qt.Key_J); press(Qt.Key_Tab)
                equal(widget.pane, "reader")
                mail.finishRead(); wait(30)
                equal(mail.pendingReadId, "", "reader focus pauses a queued list preview")
                press(Qt.Key_H); wait(30)
                equal(mail.pendingReadId, "alpha/7", "returning to the list resumes its latest preview")
                mail.finishRead(); wait(30)
                equal(mail.selectedId, "alpha/7")
            }
            function test_reader_focus() {
                press(Qt.Key_J)
                press(Qt.Key_Return)
                equal(widget.pane, "reader")
                equal(mail.selectedId, "alpha/2")
                check(area.activeFocus, "TextArea really owns focus")
                equal(mail.calls.length, 1)
                equal(mail.calls[0].operation, "read")
                check(mail.messages[1].unread, "opening never automatically marks seen")
                var cursor = widget.cursorId
                var y = scroll.contentItem.contentY
                press(Qt.Key_J)
                check(scroll.contentItem.contentY > y, "j scrolls with TextArea focus")
                equal(widget.cursorId, cursor)
                press(Qt.Key_K); equal(scroll.contentItem.contentY, y)
                press(Qt.Key_D, Qt.ControlModifier); check(scroll.contentItem.contentY > y)
                // Flickable rounds fractional half-page positions to pixels.
                press(Qt.Key_U, Qt.ControlModifier)
                check(Math.abs(scroll.contentItem.contentY - y) <= 1, "Ctrl+u reverses half-page scroll")
                press(Qt.Key_G, Qt.ShiftModifier); check(scroll.contentItem.contentY > 500)
                press(Qt.Key_G); press(Qt.Key_G); equal(scroll.contentItem.contentY, 0)
                equal(widget.cursorId, cursor)
                press(Qt.Key_H); equal(widget.pane, "list")
                press(Qt.Key_Tab); equal(widget.pane, "reader"); check(area.activeFocus)
                press(Qt.Key_Tab, Qt.ShiftModifier); equal(widget.pane, "list")
                press(Qt.Key_Tab); equal(widget.pane, "reader")
                press(Qt.Key_Escape); equal(widget.pane, "list"); check(widget.opened)
                press(Qt.Key_Escape); check(!widget.opened)
                equal(mail.calls.length, 1, "pane changes don't reread or mark")
            }
            function test_pages_accounts() {
                equal(widget.currentAccount, "alpha", "invalid preferred account falls back")
                press(Qt.Key_Return); check(area.activeFocus)
                press(Qt.Key_N); equal(mail.page, 2); equal(mail.messages.length, 13)
                equal(widget.cursorId, "alpha/51"); equal(widget.pane, "list")
                equal(mail.selectedId, ""); equal(mail.message, null)
                press(Qt.Key_N); equal(mail.page, 2)
                press(Qt.Key_P); equal(mail.page, 1); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_P); equal(mail.page, 1)
                press(Qt.Key_Return); check(area.activeFocus)
                press(Qt.Key_BracketRight); equal(widget.currentAccount, "beta")
                equal(widget.cursorId, "beta/1"); equal(mail.selectedId, "")
                press(Qt.Key_BracketRight); equal(widget.currentAccount, "alpha")
                press(Qt.Key_BracketLeft); equal(widget.currentAccount, "beta")
                widget.selectAccount("forbidden"); equal(widget.currentAccount, "beta")
                check(mail.calls.every(function(call) { return call.account === "alpha" || call.account === "beta" }))
            }
            function test_mark_targets() {
                press(Qt.Key_Return); check(area.activeFocus)
                press(Qt.Key_M)
                var marks = mail.calls.filter(function(call) { return call.operation === "mark" })
                equal(marks[0].id, "alpha/1"); equal(marks[0].seen, true); check(!mail.messages[0].unread)
                press(Qt.Key_U); check(mail.messages[0].unread)
                press(Qt.Key_H); press(Qt.Key_J); press(Qt.Key_M)
                marks = mail.calls.filter(function(call) { return call.operation === "mark" })
                equal(marks[2].id, "alpha/2", "list mark targets the cursor preview")
                press(Qt.Key_Tab); check(area.activeFocus); press(Qt.Key_U)
                marks = mail.calls.filter(function(call) { return call.operation === "mark" })
                equal(marks[3].id, "alpha/2", "reader mark targets the previewed message")
                equal(marks[3].seen, false)
                press(Qt.Key_H); press(Qt.Key_J)
                check(!area.activeFocus, "h transfers actual focus out of the TextArea")
                mouseClick(area, 20, 100); wait(30)
                check(area.activeFocus, "click restores reader focus")
                equal(widget.pane, "reader")
                press(Qt.Key_M)
                marks = mail.calls.filter(function(call) { return call.operation === "mark" })
                equal(marks[4].id, "alpha/3", "clicking the reader keeps the previewed message as mark target")
            }
            function test_full_selectable_headers() {
                press(Qt.Key_Return)
                mail.message = {subject: "Long subject ".repeat(50), from: "Sender <sender@example.test>",
                    to: "Recipient <recipient@example.test>, ".repeat(40), date: "Malformed date ".repeat(100), body: "Body"}
                press(Qt.Key_V)
                check(widget.showHeaders, "full metadata view enabled")
                check(area.activeFocus, "metadata is selectable in reader")
                check(area.text.indexOf(mail.message.subject) !== -1, "complete subject retained")
                check(area.text.indexOf(mail.message.to) !== -1, "all recipients accessible")
                check(area.text.indexOf(mail.message.date) !== -1, "malformed date accessible without overflowing header")
                press(Qt.Key_V)
                check(!widget.showHeaders)
                equal(area.text, "Body")
            }
            function test_attachment_metadata() {
                var openedUrls = []
                widget.openUrl = function(url) { openedUrls.push(url) }
                press(Qt.Key_Return)
                var attachments = [
                    {id: "pdf", name: "reference.pdf", type: "application/pdf", size: 1536, openable: true},
                    {id: "txt", name: "empty.txt", type: "text/plain", size: 0, openable: true},
                    {name: "unknown", type: "application/octet-stream", size: null},
                    {name: "long-name-".repeat(200) + ".pdf", type: "application/" + "long-type".repeat(100), size: 2097152}
                ]
                mail.message = {subject: "Attachments", from: "Sender", to: "Recipient", date: "today", body: "Body", attachments: attachments}
                wait(30)
                var chips = find(widget, function(item) { return item.objectName === "attachmentChips" })
                check(chips.visible, "metadata chips visible")
                check(chips.height <= 36, "chips have bounded height")
                press(Qt.Key_H); press(Qt.Key_A)
                check(widget.showAttachments); equal(widget.pane, "reader"); check(area.activeFocus)
                check(area.text.indexOf("1.5 KiB") !== -1)
                press(Qt.Key_J); check(area.text.indexOf("0 B") !== -1)
                press(Qt.Key_J); check(area.text.indexOf("Unknown size") !== -1)
                press(Qt.Key_J); check(area.text.indexOf("2.0 MiB") !== -1)
                press(Qt.Key_G); press(Qt.Key_G)
                // A chip emits selection upward; later keyboard changes must still
                // reach the same presentation instance (no broken input binding).
                var secondChip = chips.itemAtIndex(1)
                check(secondChip !== null)
                mouseClick(secondChip, secondChip.width / 2, secondChip.height / 2); wait(30)
                equal(widget.attachmentIndex, 1)
                press(Qt.Key_K); equal(widget.attachmentIndex, 0)
                check(area.text.indexOf("reference.pdf") !== -1)
                check(area.readOnly && area.selectByMouse, "details selectable and read-only")
                check(area.text.indexOf("1536 bytes") !== -1, "exact decoded size retained")
                press(Qt.Key_G, Qt.ShiftModifier)
                check(area.text.indexOf(attachments[3].name) !== -1, "full long filename retained")
                check(area.text.indexOf(attachments[3].type) !== -1, "full media type retained")
                press(Qt.Key_D, Qt.ControlModifier); check(scroll.contentItem.contentY > 0, "long details scroll by keyboard")
                press(Qt.Key_U, Qt.ControlModifier)
                press(Qt.Key_K); check(area.text.indexOf("Unknown size") !== -1)
                press(Qt.Key_G); press(Qt.Key_G)
                area.selectAll(); equal(area.selectedText, area.text, "all metadata can be copied"); area.deselect(); area.cursorPosition = 0; wait(30)
                press(Qt.Key_G); press(Qt.Key_G)
                equal(mail.calls.length, 1, "inspection never saves or opens")
                press(Qt.Key_J); equal(widget.attachmentIndex, 1, "j selects attachment")
                press(Qt.Key_S); equal(mail.calls[1].operation, "saveAttachment"); equal(mail.calls[1].id, "txt")
                press(Qt.Key_Return); equal(mail.calls[2].operation, "openAttachment"); equal(mail.calls[2].id, "txt")
                mail.savingAttachment = true
                press(Qt.Key_S); press(Qt.Key_Return); equal(mail.calls.length, 3, "busy prevents duplicate actions")
                mail.savingAttachment = false
                press(Qt.Key_Question); press(Qt.Key_S); press(Qt.Key_Return); equal(mail.calls.length, 3, "help blocks actions")
                press(Qt.Key_Escape)
                press(Qt.Key_K); equal(widget.attachmentIndex, 0)
                press(Qt.Key_G, Qt.ShiftModifier); equal(widget.attachmentIndex, 3)
                press(Qt.Key_G); press(Qt.Key_G); equal(widget.attachmentIndex, 0)
                equal(openedUrls.length, 0, "attachments never use URL opener")
                press(Qt.Key_H); check(!widget.showAttachments); equal(area.text, "Body"); equal(widget.pane, "reader")
                press(Qt.Key_S); press(Qt.Key_Return); equal(mail.calls.length, 3, "save/open keys scoped to attachments")
                press(Qt.Key_A); press(Qt.Key_Escape); check(!widget.showAttachments); equal(widget.pane, "reader")
                press(Qt.Key_A); press(Qt.Key_A); check(!widget.showAttachments)
                press(Qt.Key_V); press(Qt.Key_A); check(!widget.showHeaders && widget.showAttachments)
                press(Qt.Key_O); check(widget.showLinks && !widget.showAttachments && !widget.showHeaders)
                press(Qt.Key_A); check(widget.showAttachments && !widget.showLinks)
                press(Qt.Key_V); check(widget.showHeaders && !widget.showAttachments)
                press(Qt.Key_O); check(widget.showLinks && !widget.showHeaders)
                press(Qt.Key_H)
                press(Qt.Key_Question); press(Qt.Key_A); check(!widget.showAttachments, "help blocks attachment toggle")
                press(Qt.Key_Escape)
                mail.reading = true; press(Qt.Key_A); check(!widget.showAttachments, "busy guard"); mail.reading = false
                press(Qt.Key_A); press(Qt.Key_BracketRight); check(!widget.showAttachments, "account change resets details")
                equal(openedUrls.length, 0)
            }
            function test_attachment_empty_and_reset() {
                press(Qt.Key_Return)
                mail.message = {subject: "Legacy", from: "Sender", to: "Recipient", date: "today", body: "Legacy body"}
                press(Qt.Key_A)
                check(widget.showAttachments)
                check(area.text.indexOf("No attachments in this message.") !== -1, "missing attachment field supported")
                var chips = find(widget, function(item) { return item.objectName === "attachmentChips" })
                check(!chips.visible)
                mail.message = {subject: "Empty", from: "Sender", to: "Recipient", date: "today", body: "Empty body", attachments: []}
                check(!widget.showAttachments, "message change resets details")
                press(Qt.Key_A); check(area.text.indexOf("No attachments") !== -1)
                press(Qt.Key_Tab); check(!widget.showAttachments); equal(widget.pane, "list")
                equal(mail.calls.length, 1, "metadata view never reads or marks")
            }
            function test_reader_toolbar_targets_displayed_message() {
                var readButton = find(widget, function(item) { return item.objectName === "readerMarkRead" })
                var unreadButton = find(widget, function(item) { return item.objectName === "readerMarkUnread" })
                check(readButton !== null && unreadButton !== null, "reader actions found")
                press(Qt.Key_Return)
                press(Qt.Key_H); press(Qt.Key_J)
                equal(widget.cursorId, "alpha/2")
                equal(mail.selectedId, "alpha/2", "list navigation updates the displayed preview")
                mouseClick(readButton, readButton.width / 2, readButton.height / 2); wait(30)
                equal(mail.calls[2].id, "alpha/2", "reader toolbar targets the displayed preview")
                equal(mail.calls[2].seen, true)
                check(mail.messages[0].unread, "other message remains untouched")
                mouseClick(unreadButton, unreadButton.width / 2, unreadButton.height / 2); wait(30)
                equal(mail.calls[3].id, "alpha/2")
                equal(mail.calls[3].seen, false)
            }
            function test_ask_agent_prompt() {
                var button = find(widget, function(item) { return item.objectName === "readerAskAgent" })
                check(button !== null, "Ask agent button found")
                press(Qt.Key_Return)
                check(!button.enabled, "demo mail cannot be sent to an agent")
                equal(widget.askAgent(), false, "demo guard blocks direct launch")

                var prompts = []
                var originalLauncher = widget.launchAgentPrompt
                widget.launchAgentPrompt = function(prompt) { prompts.push(prompt) }
                mail.demo = false
                wait(30)
                check(button.enabled, "loaded real message enables Ask agent")
                button.clicked(); wait(30)
                equal(prompts.length, 1, "one explicit click launches once")
                check(prompts[0].indexOf("himalaya") >= 0 && prompts[0].indexOf("alpha/1") >= 0,
                    "prompt points the agent at the displayed Himalaya message")
                check(prompts[0].indexOf("--account=alpha") >= 0, "prompt preserves account context")
                check(prompts[0].indexOf("Long fixture") < 0 && prompts[0].indexOf("Long offline message line 0") < 0,
                    "prompt does not export the displayed email content")
                check(prompts[0].indexOf("untrusted data") >= 0 && prompts[0].indexOf("confirmation") >= 0,
                    "prompt keeps safety boundaries around retrieved mail")
                var command = widget.agentCommand()
                equal(command.length, 2, "agent launch uses a fixed argument array")
                equal(command[0], "python3")
                check(command[1].indexOf("yetimail-agent-launcher") >= 0, "private launcher receives the prompt over stdin")
                check(command.join(" ").indexOf("Long fixture") < 0, "email content is absent from desktop launch arguments")
                widget.launchAgentPrompt = originalLauncher
                mail.demo = true
            }
            function test_busy_guards() {
                var flags = ["loading", "reading", "marking"]
                for (var i = 0; i < flags.length; i++) {
                    mail[flags[i]] = true
                    var count = mail.calls.length
                    press(Qt.Key_Return); equal(widget.pane, "list")
                    press(Qt.Key_M); press(Qt.Key_U); press(Qt.Key_N); press(Qt.Key_P)
                    equal(mail.calls.length, count, flags[i] + " guards read/mark/page")
                    mail[flags[i]] = false
                }
                press(Qt.Key_Return); check(area.activeFocus)
                mail.marking = true
                var account = widget.currentAccount
                var count = mail.calls.length
                press(Qt.Key_M); press(Qt.Key_U); press(Qt.Key_N); press(Qt.Key_P)
                press(Qt.Key_BracketRight); equal(widget.currentAccount, account)
                equal(mail.calls.length, count, "busy guards also work from reader focus")
                mail.marking = false
            }
            function test_links() {
                var openedUrls = []
                widget.openUrl = function(url) { openedUrls.push(url) }
                press(Qt.Key_Return)
                mail.message = {subject: "Links", from: "Sender", to: "Recipient", date: "today", body: "Read [1] or [2]", links: [
                    {label: "First", url: "https://example.test/a?tracking=123"},
                    {label: "Second", url: "https://other.test/b"},
                    {label: "Unsafe fixture", url: "javascript:alert(1)"}
                ]}
                press(Qt.Key_H); equal(widget.pane, "list")
                press(Qt.Key_O); check(widget.showLinks); equal(widget.pane, "reader", "links can open from the visible reader while list has focus")
                equal(widget.linkIndex, 0)
                equal(openedUrls.length, 0, "showing links never opens them")
                press(Qt.Key_J); equal(widget.linkIndex, 1)
                press(Qt.Key_Return); equal(openedUrls[0], "https://other.test/b")
                press(Qt.Key_G, Qt.ShiftModifier); equal(widget.linkIndex, 2)
                press(Qt.Key_Return); equal(openedUrls.length, 1, "unsafe schemes blocked")
                press(Qt.Key_G); press(Qt.Key_G); equal(widget.linkIndex, 0)
                press(Qt.Key_Return); equal(openedUrls[1], "https://example.test/a?tracking=123", "destination preserved exactly")
                press(Qt.Key_H); check(!widget.showLinks); equal(widget.pane, "reader"); check(area.activeFocus)
                press(Qt.Key_O); check(widget.showLinks)
                press(Qt.Key_Escape); check(!widget.showLinks); equal(widget.pane, "reader")
                press(Qt.Key_O); press(Qt.Key_BracketRight)
                check(!widget.showLinks); equal(widget.linkIndex, 0); equal(widget.pane, "list")
                equal(openedUrls.length, 2)
            }
            function test_help_and_closed() {
                press(Qt.Key_Question); check(widget.showHelp)
                press(Qt.Key_J); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_M); equal(mail.calls.length, 0)
                press(Qt.Key_Escape); check(!widget.showHelp); check(widget.opened)
                press(Qt.Key_Q); check(!widget.opened)
                press(Qt.Key_J); press(Qt.Key_Return); press(Qt.Key_N); press(Qt.Key_M)
                equal(widget.cursorId, "alpha/1"); equal(mail.calls.length, 0)
            }
            function cleanup() {
                console.log((qtest_results.failed ? "KEYBOARD_FAIL " : "KEYBOARD_PASS ") + qtest_results.functionName)
            }
            function cleanupTestCase() {
                console.log("KEYBOARD_RESULTS passed=" + qtest_results.passCount + " failed=" + qtest_results.failCount)
                if (qtest_results.failCount === 0 && qtest_results.passCount === 28)
                    console.log("YETIMAIL_KEYBOARD_OK")
                Qt.quit()
            }
        }
    }
}
