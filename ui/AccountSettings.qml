import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui as Ui
import qs.Commons

FocusScope {
    id: view
    required property var accounts
    required property var allowedAccounts
    required property string currentAccount
    required property bool loading
    required property bool saving
    required property bool configSaving
    required property string error
    required property var icons
    property int currentIndex: 0
    property string requestedAccountId: ""
    property bool accountsUpdating: false
    property bool preservingDraft: false
    property bool makeDefault: false
    property string editorAccountId: ""
    property string editorRevision: ""
    readonly property var safeAccounts: Array.isArray(accounts) ? accounts : []
    readonly property var selectedAccount: safeAccounts[currentIndex] || null
    readonly property string selectedStoredLabel: selectedAccount ? String(selectedAccount.label || "") : ""
    readonly property bool locked: saving || configSaving
    readonly property Item focusTarget: accountList
    signal dismissRequested()
    signal retryRequested()
    signal saveLabelRequested(string accountId, string label)
    signal enabledRequested(string accountId, bool enabled)
    signal saveConfigRequested(string accountId, string revision, string email, string displayName,
                               bool makeDefault, string inbox, string sent, string drafts,
                               string trash, string archive)

    function accountId(account) {
        if (!account) return ""
        return String(account.id === undefined ? (account.name === undefined ? "" : account.name) : account.id)
    }
    function accountLabel(account) {
        if (!account) return ""
        return String(account.label || accountId(account))
    }
    function accountEnabled(account) {
        var id = accountId(account)
        if (allowedAccounts.length) return allowedAccounts.indexOf(id) !== -1
        if (currentAccount) return id === currentAccount
        return !!account && account.default === true
    }
    function canToggleEnabled(account) {
        return accountId(account).indexOf(",") < 0
    }
    function enabledCount() {
        return safeAccounts.filter(function(account) { return accountEnabled(account) }).length
    }
    function mailbox(account, role) {
        var values = account && account["mailbox-mappings"] && typeof account["mailbox-mappings"] === "object" ? account["mailbox-mappings"] : ({})
        return values[role] === undefined || values[role] === null ? "" : String(values[role])
    }
    function selectRequestedAccount(preserveDraft) {
        var previousId = editorAccountId
        var index = safeAccounts.findIndex(function(account) { return accountId(account) === requestedAccountId })
        if (index < 0 && !requestedAccountId)
            index = safeAccounts.findIndex(function(account) { return account && account.default === true })
        currentIndex = Math.max(0, index)
        accountList.currentIndex = currentIndex
        if (!preserveDraft || previousId !== accountId(selectedAccount)) syncEditors()
    }
    function focusAccount(id) {
        requestedAccountId = String(id || "")
        selectRequestedAccount()
        accountList.forceActiveFocus()
    }
    function syncEditors() {
        makeDefault = false
        var account = selectedAccount
        editorAccountId = accountId(account)
        editorRevision = account ? String(account.revision || "") : ""
        labelField.text = account ? String(account.label || "") : ""
        emailField.text = account ? String(account.email || "") : ""
        displayNameField.text = account ? String(account["display-name"] || "") : ""
        inboxField.text = mailbox(account, "inbox")
        sentField.text = mailbox(account, "sent")
        draftsField.text = mailbox(account, "drafts")
        trashField.text = mailbox(account, "trash")
        archiveField.text = mailbox(account, "archive")
    }
    function changedFields() {
        var account = selectedAccount
        if (!account) return []
        var changed = []
        if (emailField.text.trim() !== String(account.email || "")) changed.push("Email")
        if (displayNameField.text.trim() !== String(account["display-name"] || "")) changed.push("Sender name")
        if (makeDefault && !account.default) changed.push("Default account")
        if (inboxField.text.trim() !== mailbox(account, "inbox")) changed.push("Inbox mapping")
        if (sentField.text.trim() !== mailbox(account, "sent")) changed.push("Sent mapping")
        if (draftsField.text.trim() !== mailbox(account, "drafts")) changed.push("Drafts mapping")
        if (trashField.text.trim() !== mailbox(account, "trash")) changed.push("Trash mapping")
        if (archiveField.text.trim() !== mailbox(account, "archive")) changed.push("Archive mapping")
        return changed
    }
    function configDirty() { return changedFields().length > 0 }
    function backendText(value) {
        var entries = Array.isArray(value) ? value : []
        return entries.length ? entries.map(function(entry) { return String(entry).toUpperCase() }).join(" · ") : "Not configured"
    }

    onCurrentIndexChanged: if (!preservingDraft) Qt.callLater(syncEditors)
    onAccountsChanged: {
        var preserveConfigDraft = configDirty()
        var preserveLabelDraft = !!selectedAccount && labelField.text.trim() !== selectedStoredLabel
        var draftLabel = labelField.text
        preservingDraft = preserveConfigDraft || preserveLabelDraft
        accountsUpdating = true
        Qt.callLater(function() {
            selectRequestedAccount(preserveConfigDraft)
            if (!preserveConfigDraft && preserveLabelDraft) labelField.text = draftLabel
            accountsUpdating = false
            Qt.callLater(function() { preservingDraft = false })
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
            MailButton { objectName: "accountSettingsClose"; text: "Close"; enabled: !view.locked; onClicked: view.dismissRequested() }
        }
        MailLabel {
            Layout.fillWidth: true
            text: "Edit identity and folder mappings without exposing authentication details. Changes are validated, backed up, and written atomically."
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
                    model: view.safeAccounts
                    enabled: !view.locked
                    activeFocusOnTab: true
                    keyNavigationEnabled: true
                    currentIndex: view.currentIndex
                    onCurrentIndexChanged: if (currentIndex >= 0) {
                        view.currentIndex = currentIndex
                        if (!view.accountsUpdating && view.safeAccounts[currentIndex])
                            view.requestedAccountId = view.accountId(view.safeAccounts[currentIndex])
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
                        MouseArea { anchors.fill: parent; enabled: !view.locked; onClicked: { view.requestedAccountId = view.accountId(modelData); view.currentIndex = index; accountList.currentIndex = index; accountList.forceActiveFocus() } }
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
                    spacing: 10

                    MailLabel { visible: view.loading; text: "Loading account configuration…" }
                    ColumnLayout {
                        visible: !!view.error
                        Layout.fillWidth: true
                        spacing: 8
                        MailLabel { Layout.fillWidth: true; text: view.error; color: Color.accent; wrapMode: Text.WordWrap }
                        MailButton { text: "Retry"; enabled: !view.loading && !view.locked; onClicked: view.retryRequested() }
                    }
                    MailLabel {
                        visible: !view.loading && !view.error && !view.safeAccounts.length
                        Layout.fillWidth: true
                        text: "No Himalaya accounts were found."
                        wrapMode: Text.WordWrap
                        opacity: 0.65
                    }
                    ColumnLayout {
                        visible: !!view.selectedAccount && !view.error
                        Layout.fillWidth: true
                        spacing: 10

                        MailLabel { text: "YETIMAIL"; font.pixelSize: 10; font.letterSpacing: 1.2; opacity: 0.55 }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 8
                            MailLabel { text: "Friendly label"; opacity: 0.55 }
                            Ui.TextField {
                                id: labelField
                                objectName: "accountLabelField"
                                Layout.fillWidth: true
                                placeholderText: view.accountId(view.selectedAccount)
                                maximumLength: 80
                                enabled: !view.locked
                                onAccepted: if (saveLabelButton.enabled) saveLabelButton.clicked()
                            }
                            MailLabel { text: "Mail access"; opacity: 0.55 }
                            MailButton {
                                id: enabledButton
                                objectName: "accountEnabledButton"
                                text: view.accountEnabled(view.selectedAccount) ? "Enabled" : "Disabled"
                                enabled: !view.locked && !!view.selectedAccount && view.canToggleEnabled(view.selectedAccount)
                                    && (!view.accountEnabled(view.selectedAccount) || view.enabledCount() > 1)
                                tooltipText: view.canToggleEnabled(view.selectedAccount) ? "Allow Yetimail to access this account"
                                    : "This account ID cannot be represented in the comma-separated allowlist"
                                onClicked: view.enabledRequested(view.accountId(view.selectedAccount), !view.accountEnabled(view.selectedAccount))
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            MailLabel { Layout.fillWidth: true; text: "The label changes only Yetimail; access updates the explicit account allowlist."; font.pixelSize: 10; opacity: 0.5; wrapMode: Text.WordWrap }
                            MailButton {
                                id: saveLabelButton
                                objectName: "saveAccountLabelButton"
                                text: view.saving ? "Saving…" : "Save label"
                                enabled: !view.locked && !!view.selectedAccount && labelField.text.trim() !== view.selectedStoredLabel
                                onClicked: view.saveLabelRequested(view.accountId(view.selectedAccount), labelField.text.trim())
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Color.foreground; opacity: 0.15 }
                        MailLabel { text: "HIMALAYA ACCOUNT"; font.pixelSize: 10; font.letterSpacing: 1.2; opacity: 0.55 }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 8
                            MailLabel { text: "Account ID"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: view.accountId(view.selectedAccount); textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere }
                            MailLabel { text: "Email"; opacity: 0.55 }
                            Ui.TextField { id: emailField; objectName: "accountEmailField"; Layout.fillWidth: true; maximumLength: 1024; enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true }
                            MailLabel { text: "Sender name"; opacity: 0.55 }
                            Ui.TextField { id: displayNameField; objectName: "accountDisplayNameField"; Layout.fillWidth: true; maximumLength: 1024; enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true }
                            MailLabel { text: "Default"; opacity: 0.55 }
                            MailButton {
                                id: defaultButton
                                objectName: "accountDefaultButton"
                                text: view.selectedAccount && view.selectedAccount.default ? "Default account"
                                    : view.makeDefault ? "Will become default" : "Make default"
                                enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true
                                    && !view.selectedAccount.default && !view.makeDefault
                                onClicked: view.makeDefault = true
                            }
                            MailLabel { text: "Backends"; opacity: 0.55 }
                            MailLabel { Layout.fillWidth: true; text: "Receive: " + view.backendText(view.selectedAccount ? view.selectedAccount.receiving : []) + "\nSend: " + view.backendText(view.selectedAccount ? view.selectedAccount.sending : []); wrapMode: Text.WordWrap }
                        }

                        MailLabel { text: "FOLDER MAPPINGS"; font.pixelSize: 10; font.letterSpacing: 1.2; opacity: 0.55 }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 8
                            MailLabel { text: "Inbox"; opacity: 0.55 }
                            Ui.TextField { id: inboxField; objectName: "accountInboxField"; Layout.fillWidth: true; maximumLength: 1024; enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true }
                            MailLabel { text: "Sent"; opacity: 0.55 }
                            Ui.TextField { id: sentField; objectName: "accountSentField"; Layout.fillWidth: true; maximumLength: 1024; enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true }
                            MailLabel { text: "Drafts"; opacity: 0.55 }
                            Ui.TextField { id: draftsField; objectName: "accountDraftsField"; Layout.fillWidth: true; maximumLength: 1024; enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true }
                            MailLabel { text: "Trash"; opacity: 0.55 }
                            Ui.TextField { id: trashField; objectName: "accountTrashField"; Layout.fillWidth: true; maximumLength: 1024; enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true }
                            MailLabel { text: "Archive"; opacity: 0.55 }
                            Ui.TextField { id: archiveField; objectName: "accountArchiveField"; Layout.fillWidth: true; maximumLength: 1024; enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true }
                        }
                        MailLabel {
                            Layout.fillWidth: true
                            visible: !!view.selectedAccount && view.selectedAccount.editable !== true
                            text: view.selectedAccount && view.selectedAccount["editable-reason"] ? String(view.selectedAccount["editable-reason"]) : "This configuration cannot be edited safely from Yetimail."
                            color: Color.accent
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }
                        MailLabel {
                            objectName: "accountConfigChanges"
                            Layout.fillWidth: true
                            visible: view.configDirty()
                            text: "Changes: " + view.changedFields().join(", ")
                            font.pixelSize: 10
                            color: Color.accent
                            wrapMode: Text.WordWrap
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            MailLabel { Layout.fillWidth: true; text: "Authentication, login, server, and backend type remain read-only."; font.pixelSize: 10; opacity: 0.5; wrapMode: Text.WordWrap }
                            MailButton {
                                id: saveConfigButton
                                objectName: "saveAccountConfigButton"
                                text: view.configSaving ? "Saving…" : "Save configuration"
                                enabled: !view.locked && !!view.selectedAccount && view.selectedAccount.editable === true
                                    && (view.configDirty() || view.makeDefault)
                                onClicked: view.saveConfigRequested(view.accountId(view.selectedAccount), view.editorRevision,
                                    emailField.text.trim(), displayNameField.text.trim(), view.makeDefault,
                                    inboxField.text.trim(), sentField.text.trim(), draftsField.text.trim(),
                                    trashField.text.trim(), archiveField.text.trim())
                            }
                        }
                    }
                }
            }
        }
    }
}
