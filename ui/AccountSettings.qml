import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui as Ui
import qs.Commons

FocusScope {
    id: view
    required property var accounts
    required property string currentAccount
    required property bool loading
    required property bool saving
    required property string error
    required property var icons
    property int currentIndex: 0
    property string requestedAccountId: ""
    property bool accountsUpdating: false
    readonly property var selectedAccount: accounts[currentIndex] || null
    readonly property Item focusTarget: accountList
    signal dismissRequested()
    signal retryRequested()
    signal saveLabelRequested(string accountId, string label)

    function accountId(account) {
        if (!account) return ""
        return String(account.id === undefined ? (account.name === undefined ? "" : account.name) : account.id)
    }
    function accountLabel(account) {
        if (!account) return ""
        return String(account.label || accountId(account))
    }
    function selectRequestedAccount() {
        var index = accounts.findIndex(function(account) { return accountId(account) === requestedAccountId })
        if (index < 0 && !requestedAccountId)
            index = accounts.findIndex(function(account) { return account && account.default === true })
        currentIndex = Math.max(0, index)
        accountList.currentIndex = currentIndex
        syncEditor()
    }
    function focusAccount(id) {
        requestedAccountId = String(id || "")
        selectRequestedAccount()
        accountList.forceActiveFocus()
    }
    function syncEditor() {
        labelField.text = selectedAccount ? String(selectedAccount.label || "") : ""
    }
    function backendText(value) {
        if (!value) return "Not configured"
        var entries = Array.isArray(value) ? value : [value]
        if (!entries.length) return "Not configured"
        return entries.map(function(entry) {
            if (typeof entry === "string") return entry
            var type = String(entry.type || entry.kind || "Backend")
            var endpoint = entry.host ? String(entry.host) + (entry.port ? ":" + entry.port : "") : ""
            var encryption = entry.encryption ? String(entry.encryption) : ""
            return [type.toUpperCase(), endpoint, encryption].filter(function(part) { return part !== "" }).join(" · ")
        }).join("\n")
    }
    function metadata(account, camel, dashed) {
        if (!account) return ""
        var value = account[camel]
        if (value === undefined && dashed) value = account[dashed]
        return value === undefined || value === null ? "" : String(value)
    }

    onCurrentIndexChanged: Qt.callLater(syncEditor)
    onAccountsChanged: {
        accountsUpdating = true
        Qt.callLater(function() {
            selectRequestedAccount()
            accountsUpdating = false
        })
    }

    objectName: "accountSettings"
    z: 13
    Rectangle {
        anchors.fill: parent
        color: Color.background
        border.color: Color.accent
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            MailLabel { text: view.icons.settings; font.pixelSize: 18 }
            MailLabel { Layout.fillWidth: true; text: "ACCOUNT SETTINGS"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.2 }
            MailButton { objectName: "accountSettingsClose"; text: "Close"; onClicked: view.dismissRequested() }
        }
        MailLabel {
            Layout.fillWidth: true
            text: "Configuration details are read-only. Friendly labels are stored by Yetimail."
            wrapMode: Text.WordWrap
            opacity: 0.65
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Color.foreground; opacity: 0.15 }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: 220
                Layout.minimumWidth: 150
                Layout.fillHeight: true
                spacing: 8
                MailLabel { text: "ACCOUNTS"; font.pixelSize: 10; font.letterSpacing: 1.2; opacity: 0.55 }
                ListView {
                    id: accountList
                    objectName: "accountSettingsList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: view.accounts
                    activeFocusOnTab: true
                    keyNavigationEnabled: true
                    currentIndex: view.currentIndex
                    onCurrentIndexChanged: if (currentIndex >= 0) {
                        view.currentIndex = currentIndex
                        if (!view.accountsUpdating && view.accounts[currentIndex])
                            view.requestedAccountId = view.accountId(view.accounts[currentIndex])
                    }
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: accountList.width
                        height: 44
                        color: index === view.currentIndex ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.09) : "transparent"
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 1
                            MailLabel { Layout.fillWidth: true; text: view.accountLabel(modelData); elide: Text.ElideRight }
                            MailLabel { Layout.fillWidth: true; text: view.accountId(modelData); font.pixelSize: 10; opacity: 0.5; elide: Text.ElideRight }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { view.requestedAccountId = view.accountId(modelData); view.currentIndex = index; accountList.currentIndex = index; accountList.forceActiveFocus() } }
                    }
                }
            }

            Rectangle { Layout.fillHeight: true; width: 1; color: Color.foreground; opacity: 0.15 }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: Math.max(1, parent.width)
                    spacing: 12

                    MailLabel {
                        visible: view.loading
                        text: "Loading account configuration…"
                    }
                    ColumnLayout {
                        visible: !!view.error
                        Layout.fillWidth: true
                        spacing: 8
                        MailLabel { Layout.fillWidth: true; text: view.error; color: Color.urgent; wrapMode: Text.WordWrap }
                        MailButton { text: "Retry"; enabled: !view.loading; onClicked: view.retryRequested() }
                    }
                    MailLabel {
                        visible: !view.loading && !view.error && !view.accounts.length
                        Layout.fillWidth: true
                        text: "No Himalaya accounts were found."
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                    }
                    ColumnLayout {
                        visible: !!view.selectedAccount && !view.error
                        Layout.fillWidth: true
                        spacing: 10

                        MailLabel { text: "FRIENDLY LABEL"; font.pixelSize: 10; font.letterSpacing: 1.2; opacity: 0.55 }
                        Ui.TextField {
                            id: labelField
                            objectName: "accountLabelField"
                            Layout.fillWidth: true
                            placeholderText: view.accountId(view.selectedAccount)
                            maximumLength: 80
                            enabled: !view.saving
                            onAccepted: if (saveButton.enabled) saveButton.clicked()
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            MailLabel { Layout.fillWidth: true; text: "Leave empty to use the Himalaya account ID."; font.pixelSize: 10; opacity: 0.5; wrapMode: Text.WordWrap }
                            MailButton {
                                id: saveButton
                                objectName: "saveAccountLabelButton"
                                text: view.saving ? "Saving…" : "Save label"
                                enabled: !view.saving && !!view.selectedAccount
                                    && labelField.text.trim() !== String(view.selectedAccount.label || "")
                                onClicked: view.saveLabelRequested(view.accountId(view.selectedAccount), labelField.text.trim())
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Color.foreground; opacity: 0.15 }
                        MailLabel { text: "HIMALAYA ACCOUNT"; font.pixelSize: 10; font.letterSpacing: 1.2; opacity: 0.55 }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 14
                            rowSpacing: 8
                            MailLabel { text: "Account ID"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: view.accountId(view.selectedAccount); textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere }
                            MailLabel { text: "Email"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: view.metadata(view.selectedAccount, "email", "email") || "Not set"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere }
                            MailLabel { text: "Sender name"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: view.metadata(view.selectedAccount, "displayName", "display-name") || "Not set"; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere }
                            MailLabel { text: "Default"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: view.selectedAccount && view.selectedAccount.default ? "Yes" : "No" }
                            MailLabel { text: "Receiving"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: view.backendText(view.selectedAccount ? (view.selectedAccount.receiving || view.selectedAccount.incoming) : null); textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere }
                            MailLabel { text: "Sending"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: view.backendText(view.selectedAccount ? (view.selectedAccount.sending || view.selectedAccount.outgoing) : null); textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere }
                        }
                        MailLabel {
                            Layout.fillWidth: true
                            text: "Authentication details and credential commands are intentionally hidden."
                            font.pixelSize: 10
                            opacity: 0.5
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
