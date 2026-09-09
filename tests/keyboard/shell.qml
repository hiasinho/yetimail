import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "Jitsmail"

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
                widget.selectedAccount = "alpha"
                mail.loading = false; mail.reading = false; mail.marking = false; mail.moving = false; mail.savingAttachment = false; mail.openingAttachment = false
                mail.folderId = ""; mail.folderName = "Inbox"; mail.foldersLoading = false; mail.foldersError = ""
                widget.showFolders = false
                widget.cursorId = ""
                mail.populate(); mail.calls = []
                widget.opened = true
                widget.showHelp = false
                widget.focusList()
                wait(50)
            }
            function test_move_picker() {
                mail.folderId = "INBOX"
                widget.syncCursor()
                press(Qt.Key_J)
                press(Qt.Key_M, Qt.ShiftModifier)
                check(widget.showFolders && widget.movePicker, "Shift+M opens move picker")
                equal(widget.moveTargetId, "alpha/2")
                equal(mail.calls.length, 1, "opening picker only discovers folders")
                press(Qt.Key_Return)
                equal(mail.calls.length, 1, "current folder cannot be a destination")
                press(Qt.Key_M); press(Qt.Key_U)
                equal(mail.calls.length, 1, "mark actions blocked in picker")
                press(Qt.Key_J); press(Qt.Key_J); press(Qt.Key_Return)
                check(!widget.showFolders)
                equal(mail.calls[1].operation, "move")
                equal(mail.calls[1].id, "alpha/2")
                equal(mail.calls[1].seen, "Archive", "chosen destination")
                equal(mail.folderId, "INBOX", "move does not navigate")
                equal(widget.cursorId, "alpha/3", "next row selected")
                press(Qt.Key_M)
                equal(mail.calls[2].operation, "mark", "lowercase m still marks read")
                press(Qt.Key_M, Qt.ShiftModifier); press(Qt.Key_H)
                check(!widget.showFolders)
                press(Qt.Key_M, Qt.ShiftModifier); press(Qt.Key_Escape)
                check(!widget.showFolders && widget.opened)
                equal(mail.calls.filter(function(call) { return call.operation === "move" }).length, 1, "cancel never moves")
                press(Qt.Key_Return)
                widget.cursorId = "alpha/4"
                press(Qt.Key_M, Qt.ShiftModifier)
                equal(widget.moveTargetId, "alpha/3", "reader targets displayed message not cursor")
                press(Qt.Key_G, Qt.ShiftModifier); press(Qt.Key_Return)
                equal(mail.calls[mail.calls.length - 1].id, "alpha/3")
                equal(mail.calls[mail.calls.length - 1].seen, "Projects/2026")
                press(Qt.Key_M, Qt.ShiftModifier)
                check(widget.showFolders, "move picker open before config change")
                mail.config = "new-offline-config"
                wait(30)
                check(!widget.showFolders, "configuration generation change dismisses stale move target")
                for (var flag of ["loading", "reading", "marking", "moving", "savingAttachment", "openingAttachment"]) {
                    mail[flag] = true
                    press(Qt.Key_M, Qt.ShiftModifier)
                    check(!widget.showFolders, flag + " prevents moving")
                    mail[flag] = false
                }
            }
            function test_folder_navigation() {
                press(Qt.Key_Return); press(Qt.Key_N)
                equal(mail.page, 2)
                var folderButton = find(widget, function(item) { return item.objectName === "folderButton" })
                check(folderButton !== null, "folder icon button found")
                equal(folderButton.x, 0, "folder icon comes before account chips")
                check(folderButton.width < 50 && folderButton.tooltipText.indexOf("Inbox") !== -1, "compact icon exposes current folder in tooltip")
                mouseClick(folderButton, folderButton.width / 2, folderButton.height / 2); wait(30)
                check(widget.showFolders, "folder icon opens dropdown")
                var menu = find(widget, function(item) { return item.objectName === "folderMenu" })
                var picker = find(widget, function(item) { return item.objectName === "folderPicker" })
                check(menu.width >= 160 && menu.width <= 200, "dropdown has compact width")
                equal(menu.height, mail.folders.length * 32 + 2, "short menu hugs discovered rows")
                var anchor = menu.mapToItem(folderButton, 0, 0)
                equal(anchor.x, 0, "menu left aligns with icon")
                equal(anchor.y, folderButton.height + 2, "menu sits beneath icon")
                equal(picker.count, mail.folders.length, "only discovered folders are listed")
                check(find(picker, function(item) { return item.text === "Sent mail" }) !== null, "folder name shown without role suffix")
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
                mail.foldersLoading = true
                count = mail.calls.length
                press(Qt.Key_Return); press(Qt.Key_R)
                equal(mail.calls.length, count, "loading prevents choice and duplicate folder request")
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
            function test_navigation() {
                equal(mail.messages.length, 50)
                equal(widget.cursorId, "alpha/1")
                press(Qt.Key_J); equal(widget.cursorId, "alpha/2")
                press(Qt.Key_K); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_K); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_G, Qt.ShiftModifier); equal(widget.cursorId, "alpha/50")
                press(Qt.Key_J); equal(widget.cursorId, "alpha/50")
                press(Qt.Key_G); press(Qt.Key_G); equal(widget.cursorId, "alpha/1")
                press(Qt.Key_D, Qt.ControlModifier); check(widget.cursorIndex > 0)
                press(Qt.Key_U, Qt.ControlModifier); equal(widget.cursorId, "alpha/1")
                equal(mail.calls.length, 0, "navigation never reads or marks")
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
                equal(mail.calls[1].operation, "mark"); equal(mail.calls[1].id, "alpha/1")
                equal(mail.calls[1].seen, true); check(!mail.messages[0].unread)
                press(Qt.Key_U); equal(mail.calls[2].seen, false); check(mail.messages[0].unread)
                press(Qt.Key_H); press(Qt.Key_J); press(Qt.Key_M)
                equal(mail.calls[3].id, "alpha/2", "list mark targets cursor, not open reader")
                press(Qt.Key_Tab); check(area.activeFocus); press(Qt.Key_M)
                equal(mail.calls[4].id, "alpha/1", "reader mark targets open message, not cursor")
                press(Qt.Key_U); equal(mail.calls[5].id, "alpha/1"); equal(mail.calls[5].seen, false)
                press(Qt.Key_H); press(Qt.Key_J)
                check(!area.activeFocus, "h transfers actual focus out of the TextArea")
                mouseClick(area, 20, 100); wait(30)
                check(area.activeFocus, "click restores reader focus")
                equal(widget.pane, "reader")
                press(Qt.Key_M)
                equal(mail.calls[6].id, "alpha/1", "clicking the reader restores the visible message as mark target")
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
                equal(widget.attachmentSize(0), "0 B")
                equal(widget.attachmentSize(null), "Unknown size")
                equal(widget.attachmentSize(1536), "1.5 KiB")
                equal(widget.attachmentSize(2097152), "2.0 MiB")
                press(Qt.Key_H); press(Qt.Key_A)
                check(widget.showAttachments); equal(widget.pane, "reader"); check(area.activeFocus)
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
                equal(mail.selectedId, "alpha/1")
                mouseClick(readButton, readButton.width / 2, readButton.height / 2); wait(30)
                equal(mail.calls[1].id, "alpha/1", "reader toolbar ignores list cursor")
                equal(mail.calls[1].seen, true)
                check(mail.messages[1].unread, "other message remains untouched")
                mouseClick(unreadButton, unreadButton.width / 2, unreadButton.height / 2); wait(30)
                equal(mail.calls[2].id, "alpha/1")
                equal(mail.calls[2].seen, false)
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
                if (qtest_results.failCount === 0 && qtest_results.passCount === 14)
                    console.log("JITSMAIL_KEYBOARD_OK")
                Qt.quit()
            }
        }
    }
}
