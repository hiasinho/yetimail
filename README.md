![Yetimail — Your inbox. At your fingertips.](docs/assets/yetimail-header.png)

# Yetimail

A keyboard-first Omarchy mail panel powered by **Himalaya 2.1**. Read and manage inbox status without leaving the desktop.

- Mail bar widget and two-pane inbox/reader.
- Continuous newest-first folder lists, loaded ahead in cached chunks of 50.
- Keyboard folder picker and Inbox / Sent / Archive / Trash shortcuts.
- Loaded-list multi-selection supports bulk move, archive, trash, and read/unread actions.
- Optional account selector restricted to an explicit allowlist; allowed inboxes are warmed in the background for instant switching.
- Account overview with editable identity, default account, folder mappings, mail access, and private Yetimail labels.
- Unread badge counts **only loaded messages**, not the whole mailbox.
- Automatic refresh every 120 seconds, plus Refresh / Ctrl+R.
- Safe text-only message display with compact numbered web links and destination previews.
- Explicit **Ask agent** action opens the configured Omarchy agent with a mailbox-scoped Himalaya reference.
- Keyboard-accessible attachment details, safe saving, and explicit opening of supported types.
- Explicit mark-read / mark-unread actions. Opening or prefetching a message does **not** mark it seen.
- Private, bounded SQLite snapshots plus debounced body prefetching for instant repeat navigation.
- Immediate archive/trash moves; permanent removal requires confirmation. No sending or remote images.
- Demo mode requires no account and never invokes Himalaya.

Inspired by [omarchy-mail](https://github.com/roymckenzie/omarchy-mail). This is an independent implementation using Himalaya rather than implementing IMAP itself.

## Requirements

- Current Omarchy with the Quickshell-based shell and third-party plugin support.
- Python 3.11+ (standard library only); `xdg-open` and a default viewer for opening attachments.
- Himalaya **2.1.x**, with an IMAP account configured and noninteractive authentication working. Older CLI versions use different commands/JSON and are not supported.

Create your initial account outside Yetimail:

```sh
himalaya --version
himalaya configure
himalaya --account personal --json envelope list --page-size 5
```

Use the default account or select an account through plugin settings. Yetimail starts at the account's default inbox alias; the folder picker discovers that account's selectable mailboxes. Keep passwords in your password manager/keyring, not plugin settings or this repository. Authentication must work without an interactive prompt; the helper has closed stdin and a 30-second timeout.

Gmail/OAuth, compose/reply, search, and full offline sync are outside this milestone.

## Install the local checkout

This links your development checkout; changes remain user-owned and survive Omarchy updates. Do not run the link command if that destination already exists.

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s "$(pwd)" ~/.config/omarchy/plugins/hiasinho.yetimail
omarchy-shell shell rescanPlugins
omarchy plugin enable hiasinho.yetimail
```

Run from this repository's root. Enabling with defaults will query your default Himalaya account. To try the UI without any mail access first, use the isolated demo below.

Settings are declared in `manifest.json` and stored in the widget's entry in `~/.config/omarchy/shell.json`. Preserve the rest of that file when editing. A widget entry looks like:

```json
{
  "id": "hiasinho.yetimail",
  "accounts": "personal,work",
  "account": "personal",
  "config": "",
  "demo": false,
  "refreshSeconds": 120
}
```

`accounts` is an optional comma-separated allowlist. The account icon's dropdown switches between those accounts, clearing the previous reader and selection; excluded accounts are never queried for mail. After the active inbox is requested, Yetimail warms page 1 and folder discovery for the other allowed accounts in the background, so a later switch can render from a snapshot immediately. The badge belongs to the selected account, not a combined inbox. Selection is per bar instance and resets to `account` after reload (or the first allowed account if the preferred account is excluded).

The gear beside the account and mailbox controls opens an overview of the accounts declared in the effective Himalaya configuration. Yetimail reads this safe overview from local TOML when the widget starts and refreshes it when Settings opens; it does not invoke Himalaya, test connections, authenticate, or fetch mail for the overview. Account IDs and backend types remain read-only. Authentication values, login names, credential commands, tokens, server addresses, and arbitrary configuration values are never returned to QML.

For a supported single-file configuration, Settings can edit an existing account's email address, sender display name, default status, and account-local Inbox, Sent, Drafts, Trash, and Archive mailbox mappings. **Make default** saves the displayed configuration immediately; other configuration changes use the explicit **Save configuration** button. Yetimail accepts an owner-controlled `config.toml` symlink to a safe regular file, but rejects symlinked configuration directories, merged configurations, unsafe ownership or permissions, unsupported TOML layouts, and files changed since the form was loaded. It preserves unrelated text and comments, validates the result, writes through an atomic same-directory replacement, and leaves a `.yetimail-backup-*` copy beside the configuration. Reopen Settings before retrying a stale or rejected save. The configuration write itself remains offline; returning to the mail view refreshes its selected mailbox. Use Himalaya privately in a terminal to test authentication or connectivity.

Friendly labels can also be edited in the overview. They affect only Yetimail's account picker, tooltips, and headings; Himalaya commands continue to receive the original account ID. Labels are stored separately in `$XDG_CONFIG_HOME/yetimail/account-labels.json` (normally `~/.config/yetimail/account-labels.json`) using an owner-only directory, private file permissions, and atomic replacement. Clear a label to fall back to its account ID. Yetimail refuses unsafe label paths or files rather than following symlinks. Demo mode neither reads nor writes this file.

The Mail access toggle updates the widget's `accounts` allowlist through the Omarchy shell settings API. It never enables accounts merely because they appear in Himalaya, and the final enabled account cannot be disabled from the form. Enabling a configured account is an explicit grant for Yetimail to query it. **Move up** and **Move down** reorder enabled accounts in Yetimail's dropdown; `g1` through `g9` use this same one-based order. Reordering does not change Himalaya's default or the plugin's explicit startup `account`. Changing the Himalaya default affects commands that omit an account; changing the Yetimail label or allowlist does not.

With an empty allowlist, the single-account behavior is unchanged. An empty `account` or `config` uses Himalaya's default. A nonempty config is a path passed directly to Himalaya. `demo: true` uses synthetic messages. `q` or Close dismisses the panel. Opening the panel immediately previews the highlighted message; an empty inbox shows a simple all-caught-up state. List navigation keeps the preview synchronized, and rapid navigation waits for the current read to finish before loading only the latest highlighted message.

## Keyboard navigation

All commands work inside the panel, including while the selectable message text has focus. The highlighted row is the list cursor and its message is previewed automatically; focusing the reader switches navigation to it, and `h` returns to the list.

| Key | Action |
| --- | --- |
| `j` / `k`, `↓` / `↑` | Select and preview next/previous message in list; scroll in reader |
| `Space` / `Ctrl+A` | Toggle the highlighted message / select all currently loaded messages |
| `Enter`, `l`, `→` | Focus the highlighted message in the reader |
| `h`, `←` | Return from links to reader, or reader to list |
| `x` / `Shift+X` | Immediately archive / move to Trash; no-op already in the destination |
| `Delete` | Immediately trash; inside Trash, confirm removal with `Enter` or Delete button; `h/Esc` cancels |
| `Shift+M` | Move picker: `j/k` select destination, `Enter` moves, `h/Esc` cancels |
| `f` | Open/close folder picker; `j/k` select, `Enter/l` opens, `h/Esc` dismisses |
| `gi` / `gs` / `ga` / `gt` | Go to Inbox / Sent / Archive / Trash |
| `g1` … `g9` | Go to allowed account 1 … 9 in configured order |
| `o` | Toggle the reader's link list |
| `a` | Toggle selectable attachment details; `j/k` select an attachment |
| `s` / `Enter` in attachments | Save / save and explicitly open the selected attachment |
| `v` | Toggle full selectable message headers |
| `j` / `k`, `Enter` in links | Select a link; explicitly open its destination in the browser |
| `Tab`, `Shift+Tab` | Switch panes (opens highlighted message if needed) |
| `gg` / `G` | First/last loaded row; top/bottom of reader |
| `Ctrl+d` / `Ctrl+u` | Half-page down/up in active pane |
| `n` | Load the next older chunk immediately |
| `[` / `]` | Previous/next allowed account |
| `m` / `u` | Mark target message read/unread |
| `r`, `Ctrl+r` | Refresh the newest messages in the current folder |
| `?` | Toggle shortcut help |
| `Esc` | Dismiss help, return from links to reader, clear selection, then close panel |
| `q` | Close panel |
| `Ctrl+c` | Copy selected message text |

Status changes target the selected rows when the list has a selection, otherwise the highlighted row; reader actions always target only the previewed message. `Space` or Ctrl-click toggles a row, and `Ctrl+A` selects every message loaded at that moment. Messages appended later are not selected automatically. Selected rows use an accent background and left edge instead of checkboxes. Selection survives older-chunk appends, but is cleared by account/folder changes or closing the panel, and never marks mail by itself. Only explicit `m`/`u` commands or their buttons change read status. Real status changes require an explicitly selected account (not an unnamed default); the `personal,work` allowlist supplies this. Actions run serially and wait for each server success before updating the badge; a failure cancels the remaining unsubmitted status changes and leaves them unchanged. Previewing, opening, and navigating never mark a message automatically.

The list loads older messages in 50-message backend chunks about one viewport before scrolling reaches the end. Cached chunks appear immediately; only missing or stale chunks are checked in the background, and one older request runs at a time. A failed older request leaves the existing list intact and exposes Retry. The footer reports unread and loaded counts, both limited to the current loaded working set rather than the whole mailbox.

Yetimail explicitly requests descending date order instead of relying on backend defaults. Because IMAP page boundaries can shift as mail arrives or disappears, a changed newest chunk offers a subtle **New messages** action and starts a consistent list generation when accepted instead of being mixed with stale older chunks. Returning to an account or mailbox restores its loaded in-memory chunks, cursor, and list scroll position immediately; fresh snapshots avoid another network request. Eligible disk-cached chunks are reused on demand after a restart. Selection, readers, and destructive confirmations are never restored across contexts.

## Folders

The compact, borderless footer shows unread and loaded counts plus account, mailbox, settings, refresh, and shortcut-help controls. The panel keeps a fixed height even when a folder has only a few messages. The first two footer controls are aligned, icon-only dropdowns: account first, then mailbox. Click the account icon to choose from the configured allowlist. Press `f` or click the mailbox icon to open its compact dropdown above the footer. Click either icon again, click outside a dropdown, or press `h`/`Esc` to dismiss it. The picker discovers folders from Himalaya on first use and caches them in memory and private persistent storage per account and configuration, so reopening it, returning to an account, or restarting the shell can render immediately. Changing configuration clears in-memory folder entries; persistent entries are isolated by the effective configuration fingerprint. Inbox appears first, with Drafts, Junk, and custom folders following in server order when present. Use `j/k`, `gg/G`, and `Enter` to choose; `r` explicitly refreshes folder discovery while the picker is open. Initial discovery shows a loading state, while refreshes keep cached folders visible and usable and replace them seamlessly when discovery succeeds. `gi`, `gs`, `ga`, and `gt` select known Inbox, Sent, Archive, and Trash folders. Himalaya 2.1's shared listing does not expose special-use roles, so role shortcuts currently match unambiguous conventional names among discovered folders, including the final component of hierarchical names such as `[Gmail]/Trash`; Gmail's `All Mail` is treated as Archive. Localized names remain available in the picker. Missing special folders report an error rather than guessing an unknown destination.

Changing folders clears the old reader and restores that folder's continuous list; changing accounts returns to Inbox. All message reads, status changes, and attachment saves are scoped to the selected mailbox, even when two folders contain the same message ID. Before explicit-folder operations, the helper reads Himalaya's configuration to verify that a folder ID is not redirected by a mailbox alias. Conflicting aliases or configurations it cannot safely interpret are rejected rather than accessing a different folder; credentials are never logged. Folder navigation itself never moves, archives, deletes, or marks a message read. Use `x` to archive; there is no `e` binding.

Press `Shift+M` to move the selected messages, the highlighted message when nothing is selected, or the displayed message in reader mode. The destination picker uses discovered folders; `j/k` selects, `Enter` moves, and `h/Esc` cancels without changes. Moves to the same folder are rejected, including when the configured Inbox alias resolves to that destination. Moving does not navigate to the destination or explicitly change read flags. A batch is validated as a whole before accepted rows are hidden, then runs through Himalaya one message at a time. The footer shows the pending count, and the list reconciles once after the queue drains. Both source and destination receive alias-routing checks. Moving to Trash is a folder move, not permanent deletion. Bulk moves may target any currently loaded rows; there is no undo yet.

Press `x` to archive or `Shift+X` to trash the selected rows (or the highlighted row when nothing is selected) in list mode, or the displayed message in reader mode, immediately without confirmation. These actions use the same safe folder-move queue as the picker, never `message delete`; `Shift+X` is a no-op in Trash, and `x` is a no-op in Archive. Missing or ambiguous roles fail closed. If discovery is not ready, the action loads folders and asks you to retry; it never guesses a destination. Actions are blocked while busy, closed, or in help, folder picker, or deletion confirmation. Real moves require an explicit account.

If a queued move fails, its row is restored and the remaining queue pauses. **Retry** submits that move again; **Cancel** restores unsent rows and reconciles with the server, but cannot undo a move already accepted by the server. Reading and list navigation remain available while moves run. Account and folder changes stay disabled until the queue drains or is cancelled. Closing the panel does not cancel accepted moves; direct account/configuration changes discard unsent entries and reject stale results.

## Deleting one message

Press `Delete` for the selected rows (or highlighted row when nothing is selected) in list mode or the displayed message in reader mode. The reader toolbar's **Delete** button always targets its displayed message. Outside the uniquely resolved Trash folder, this immediately moves the targets to Trash without confirmation, just like `Shift+X`. Inside Trash, permanent removal remains one message at a time: multiple selected rows are rejected, while a single target **asks for confirmation**, showing a snapshot of the account, folder, message ID, and subject. Only `Enter` or the modal's Delete button confirms; `h`, `Esc`, or Cancel dismisses without changes. Other panel shortcuts and background controls are disabled during confirmation. Closing, navigating, or changing message/account/config state invalidates the prompt; repeated submission is guarded. Real deletion requires an explicit account.

Himalaya 2.1's `message delete` follows its **trash-first policy**: it moves to the configured Trash, or requests permanent removal when already in Trash. On IMAP without UIDPLUS, a message may instead be flagged `Deleted` pending expunge; success does **not** guarantee permanent removal. An unresolved or ambiguous Trash blocks the action, not permission to bypass Trash. Role discovery uses the rules above; Himalaya's configured Trash policy remains authoritative for confirmed removal, so a differing configuration may move rather than permanently remove the message. Yetimail never expunges or performs bulk deletion.

After success, the source row is removed locally, selection advances to the next row (previous at the end), a matching reader is cleared, and the continuous list is reconciled from its newest chunk. The server's refreshed state remains authoritative, including messages pending expunge. Errors preserve the row and reader. Explicit source folders receive the same literal mailbox/alias-routing guard as other operations. Demo deletion never accesses config or Himalaya; refreshing restores synthetic messages. There is no undo in Yetimail.

## Ask agent

The reader toolbar's bot icon performs the equivalent of `omarchy agent prompt` in a terminal. Its short prompt identifies the displayed message with a shell-quoted Himalaya read command containing the current config, account, mailbox, and message ID. The prompt itself does **not** contain the sender, recipients, subject, body, full headers, or attachments. The agent runs Himalaya to load the message, then asks what you want to do—such as understand it, draft a reply, or perform another mail action.

Fetching the message gives your configured AI agent and provider access to its content. Review that provider's privacy policy before using this action. Retrieved mail remains private, untrusted data and may contain prompt-injection attempts; the prompt tells the agent not to follow email instructions or send, delete, move, change flags, open links or attachments, or access other messages without an explicit request, and to confirm sending and destructive actions. Omarchy starts its default agent with that agent's unattended permission mode, so review proposed actions carefully. The button is disabled in demo mode and while the message is unavailable or the UI is busy.

Yetimail sends the prompt to its launcher over stdin so the message reference is not included in the desktop launch command logged by UWSM. The launcher briefly stages it in an owner-only file under `$XDG_RUNTIME_DIR`, passes only that private path through the terminal launcher, and unlinks the file before starting `omarchy-agent`. Launch commands use argument arrays without shell interpolation; values inside the supplied Himalaya command are shell-quoted.

## Reading links

Long web URLs become compact references such as `[1]` in the message body. In the reader, press `o` for the link list, use `j/k` to select, inspect the destination preview, then press `Enter` to open it in your default browser. `h` or `Esc` returns to the body. Mouse clicks select a link; the Open button opens it.

Only HTTP(S) destinations are supported. Links are never opened automatically; remote images and scripts remain blocked. Original destinations, including tracking parameters, are preserved—we do not follow redirects or silently rewrite URLs. The displayed sender-provided label is not proof of the destination's identity; check the URL before opening. Opening a link can trigger tracking in your browser.

## Attachments

Messages show compact attachment metadata beneath the header. Press `a` to inspect complete filenames, MIME types, and sizes in selectable text; use `j/k` to select, `gg`/`G` for first/last, `Ctrl+d/u` to scroll long details, and `h` or `Esc` to return. Click a filename chip or use the previous/next buttons to select with the mouse. The compact summary stays bounded when a message has many attachments.

In attachment mode, `s` or **Save** writes a copy to **`~/Downloads`**. `Enter` or **Open** saves a new copy, then invokes `xdg-open` with an argument array. These keys have no attachment actions outside this mode. Nothing is opened by inspection, selection, message reading, or saving alone. Each save creates a unique filename (`name (1).ext`, etc.), never overwrites existing files or follows file symlinks, and gives the file private non-executable permissions (0600). Sender path components, controls, and overlong filenames are sanitized. Downloads must be a real directory owned by you, not writable by other users; symlinked Downloads directories are intentionally rejected. This version uses the literal `~/Downloads`, not Himalaya's or XDG's configured download directory.

Opening is deliberately conservative: only `.txt` (UTF-8 plain text), PDF, PNG, JPEG, and GIF with matching MIME and basic content checks are supported. Executables, scripts, desktop shortcuts, HTML/SVG, archives, attached emails, unknown types, and mismatches remain **save-only**. This is not malware detection or a sandbox: only open files you trust, keep viewers updated, and remember that external viewers may access the network. A failed opener leaves the saved copy in place. Each viewer has an independent launcher: once it starts, further saves and opens are available immediately. Viewers may stay open indefinitely; Yetimail does not impose a viewer lifetime timeout. Late launcher errors are shown only for the same account, message, and attachment action.

Account/config/folder/message changes discard pending results and prevent a deferred open; closing the panel cancels a pending open too. An already-requested save can still finish on disk after navigation. Already-launched external viewers are not recalled. Demo saves produce a real synthetic `welcome.txt`, but demo opening is always suppressed.

Sizes are decoded payload sizes, not the encoded transfer size; unknown sizes are labeled explicitly. Named inline parts may be listed, but unnamed inline images are omitted. Attached emails are listed as attachments without exposing their nested attachments separately. Metadata comes from the already-fetched MIME message; inspection adds no server requests. A save refetches that same message through `message read --raw` without `--seen`, preserving the selected account/config and default inbox alias. Attachment IDs are Yetimail-local ordinal/content hashes, **not** Himalaya's sparse MIME part IDs. Name, type, and payload must still match the inspected attachment or saving fails with a reload instruction. Attached emails are saved as RFC 5322 bytes; attached multipart containers are serialized as MIME.

## Develop and test

```sh
python3 -m unittest discover -s tests -v
scripts/smoke-ui
scripts/test-lifecycle
scripts/test-account-settings
scripts/test-account-config-coordinator
scripts/test-pagination
scripts/test-folders
scripts/test-moves
scripts/test-deletions
scripts/test-keyboard
scripts/test-attachments
scripts/test-prefetch
scripts/test-instant
bin/yetimail-helper list --demo
bin/yetimail-helper read --demo --id demo-1
```

The smoke test launches a temporary **offscreen** Quickshell with demo data, tests the QML → helper → inbox/read round trip, then exits. It does not install/enable anything or access your mail. Override `OMARCHY_SHELL_PATH` if Omarchy's shell is elsewhere. A guard executable prevents accidental Himalaya access even if demo mode regresses.

The lifecycle tests use shell fixtures instead of Python/Himalaya to check delayed host settings, overlapping requests, stale-result rejection, and failed launches. They replace only the compositor popup container for offscreen operation. Missing-executable warnings are expected in these tests. The account-settings integration suite exercises the production MailService facade and its internal owner with delayed offline processes, including config/demo stale-result rejection, save failure fencing, and failed launches. The account-config coordinator suite uses three narrow synthetic participants to cover unanimous and partial preparation, busy displays, commit/failure release, fence expiry and orphan recovery, and obsolete late results without reading host settings or mail configuration.

The offline integration entry points require Bash, coreutils `timeout`, Quickshell, and Python 3 where a Python fixture is used. Their named QML, Python, and process fixtures live under `tests/integration/<suite>/`; the scripts remain thin launchers. A shared harness gives every suite a private temporary HOME/XDG environment, a fail-closed PATH and Himalaya guard, hard process timeouts, scenario-labeled failures, and child/temp cleanup. The harness guard itself has Python regression coverage. Scenario state is synchronized through service conditions; hard timeouts only bound a failed run.

Deletion tests cover safe CLI arguments, explicit-account and mailbox guards, synthetic demo operation, service failures/stale results/duplicate latches, and keyboard confirmation/cancellation/stale snapshots. Only mocked subprocesses, synthetic configs, and offline QML fixtures are used—no real mail commands run.

Attachment tests cover safe extraction, private unique writes in temporary homes, traversal/symlink defenses, runnable-type restrictions, and service save/open guards with offline fixtures. No tests open real attachments or alter real mail flags.

Continuous-list tests exercise the actual service with offline fixtures and demo data, including incremental loading, failed older requests, and stale account results. Instant-state tests cover persistent probes, in-memory account restoration, nonblocking refresh, allowlisted warming, and stale/config-changing requests. Keyboard tests send real Qt key events to the production widget and `ui/` components, including navigation while the TextArea has focus, agent prompt quoting and lifecycle fencing through an injected offline launcher, mouse-to-keyboard attachment selection, stable reader lifetime, and folder anchor geometry. The harness copies `Widget.qml` and `ui/` together; only the backend and compositor popup are replaced, with no production helper staged. Install Qt's QML `QtTest` module to run keyboard tests.

For an interactive demo:

```sh
scripts/demo-ui
```

This opens a separate demo shell with two synthetic accounts, not your running Omarchy shell. Stop it with Ctrl+C in the terminal. Its logged temporary config path can also be used for demo-only visual checks:

```sh
quickshell -p /tmp/<demo-config> ipc call yetimailDemo readFirst
quickshell -p /tmp/<demo-config> ipc call yetimailDemo help
```

Neither command accesses real accounts.

## Design

The reference-inspired layout uses a compact monospace sidebar, filled Material Design Nerd Font icons, aligned account/mailbox controls with a settings gear, dense sender/subject rows, and a separate message header above the reader. The sidebar keeps a fixed 310-pixel width and stable panel height, names the current account followed by its folder, loads older rows ahead of scrolling, and combines loaded/unread status with compact utility controls in the footer. The compact reader header shows the sender, recipients, and a short timestamp without redundant From/Date rows. HTML-to-text conversion preserves paragraph breaks while collapsing excessive blank space; it still never renders active HTML. Press `v` (or the header's ≡ button) to view and copy complete headers, including long subjects and recipient lists. Keyboard help opens as a floating shortcut card rather than shifting the inbox. Controls only expose implemented actions; compose and search are not placeholders.

```text
Widget.qml → MailService.qml → bin/yetimail-helper → Himalaya → IMAP
  commands      async JSON       normalization
  ↕ data / signals
ui/*.qml
  presentation
```

`Widget.qml` remains the BarWidget shell integration and interaction coordinator: it owns keyboard commands, selection and reader modes, modal guards, deletion snapshots, mutation coordination, host widget discovery, and service/external-link calls. `AgentLaunchService.qml` accepts only an explicit launch capability and a captured config/account/mailbox/message reference; it owns shell-safe prompt construction, private stdin transport, exactly-once process completion, and stale-context status rejection while the widget retains the Omarchy-facing action. `AccountConfigCoordinator.qml` owns the cross-instance account-save transaction token, unanimous preparation, commit/cancel release, writer expiry checks, and obsolete-result rejection through narrow participant operations. Each `MailService`/`AccountSettingsService` instance still owns its token-scoped mailbox fence and request invalidation; the coordinator never receives an unrestricted widget or service. `AccountSettingsService.qml` internally owns account overview, private-label and configuration-save request state and processes; `MailService.qml` preserves the UI-facing properties, methods and transaction signals as a narrow compatibility facade and retains mailbox reset/fetch fencing. `ui/InboxPane.qml` and `ui/ReaderPane.qml` render independent data inputs and emit user-intent signals; their imperative APIs only focus, reveal rows, or scroll. `ui/AccountPicker.qml`, `ui/AccountSettings.qml`, `ui/FolderPicker.qml`, `ui/DeleteConfirmation.qml`, and `ui/ShortcutHelp.qml` are stable sibling overlays, not children of disabled mailbox controls. The inbox exposes the account and mailbox buttons' anchor geometry so each picker stays directly above its footer icon. `ui/MailLabel.qml` and `ui/MailButton.qml` share the monospace presentation defaults; labels and selectable message text remain plain text. Components never receive the widget/controller or call MailService, and no loaders recreate panes on mode changes.

The adapter executes argument arrays, never shell command strings. Account credentials stay under Himalaya's control. The helper suppresses backend stderr in UI errors because it may contain private configuration details. For connection errors, troubleshoot with Himalaya directly in a private terminal.

Yetimail keeps three private SQLite caches under `$XDG_CACHE_HOME/yetimail`: `messages.sqlite3` for processed message bodies, `lists.sqlite3` for normalized 50-message chunk snapshots, and `folders.sqlite3` for folder snapshots. They contain displayed envelope/header data, plain-text bodies, links, attachment metadata, and folder names, but not raw MIME or attachment payloads. Snapshots are never authoritative: cached state renders immediately and remains usable while an authoritative Himalaya refresh runs in the background. Successful mutations fence or invalidate affected snapshots so an older response cannot resurrect changed rows. Entries expire after 30 days. The body cache is limited to 100 MiB with 5 MiB per message; list and folder caches are each limited to 10 MiB with 1 MiB per snapshot. The directory is owner-only and database/sidecar permissions are tightened to 0600; this is not encryption, so system disk encryption is still recommended.

While the panel's message list is open, resting on a row for 300 ms queues that message and the next two for one-at-a-time background prefetch. Cached opens avoid Himalaya and network access, although they still start the small Python helper. Effective config/account, mailbox, raw message ID, parser version, and a versioned envelope fingerprint isolate entries. Fingerprints exclude mutable flags and persist across list refreshes and restarts. Envelopes lacking a nonempty ID/date/sender address or a string subject bypass caching. This is a best-effort identity: Himalaya's cross-backend listing does not expose durable mailbox generations, so reused IDs with identical envelope metadata or content-only server edits cannot be detected; force reload or clear the cache when needed. Moves and deletes invalidate the affected raw ID across all mailbox aliases in that account/config, retaining unrelated cached messages and in-flight prefetch writes. This may also evict an unrelated same-ID message in another mailbox; destination IDs are backend-assigned, and changed destination envelopes use new fingerprints. Old listing-token cache entries are discarded automatically on schema upgrade. Opening and prefetching omit Himalaya's `--seen` flag.

Clear all cached bodies, lists, and folders with `bin/yetimail-helper cache-clear`. Set `YETIMAIL_CACHE=0` in the shell environment to disable cache reads and writes (background prefetch still runs but provides no speed benefit, so disabling the cache is mainly intended for troubleshooting). The legacy `JITSMAIL_CACHE` variable remains a compatibility fallback when `YETIMAIL_CACHE` is unset; the new name takes precedence. Cache failures fall back to ordinary Himalaya reads. This is a performance cache, not full offline sync: listing mail and uncached messages still requires the configured backend. Email text is explicitly displayed as plain text, never executable HTML. Large messages still need to be fetched by Himalaya; this implementation does not yet enforce a raw-download size cap.

Offline tests cover fixtures, JSON normalization, MIME parsing, safe command arguments, errors, and the QML integration. A live-server smoke test is still required with your configured account before treating this as a daily mail client.
