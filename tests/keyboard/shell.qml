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
                mail.loading = false; mail.reading = false; mail.marking = false
                widget.cursorId = ""
                mail.populate(); mail.calls = []
                widget.opened = true
                widget.showHelp = false
                widget.focusList()
                wait(50)
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
                if (qtest_results.failCount === 0 && qtest_results.passCount === 10)
                    console.log("JITSMAIL_KEYBOARD_OK")
                Qt.quit()
            }
        }
    }
}
