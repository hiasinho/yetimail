# Yetimail

A keyboard-first Omarchy mail panel powered by **Himalaya 2.1**. Read and manage inbox status without leaving the desktop.

- Mail bar widget and two-pane inbox/reader.
- Folder messages in pages of 50, newest first; mouse or Vim-like keyboard navigation.
- Keyboard folder picker and Inbox / Sent / Archive / Trash shortcuts.
- `Shift+M` moves one message to a chosen folder; lowercase `m` still marks read.
- Optional account selector restricted to an explicit allowlist; only the selected account is queried.
- Unread badge counts **only the current page**, not the whole mailbox.
- Automatic refresh every 120 seconds, plus Refresh / Ctrl+R.
- Safe text-only message display with compact numbered web links and destination previews.
- Keyboard-accessible attachment details, safe saving, and explicit opening of supported types.
- Explicit mark-read / mark-unread actions. Opening or prefetching a message does **not** mark it seen.
- Private, bounded SQLite body cache with debounced prefetching for faster opens.
- Immediate archive/trash moves; permanent removal requires confirmation. No sending or remote images.
- Demo mode requires no account and never invokes Himalaya.

Inspired by [omarchy-mail](https://github.com/roymckenzie/omarchy-mail). This is an independent implementation using Himalaya rather than implementing IMAP itself.

## Requirements

- Current Omarchy with the Quickshell-based shell and third-party plugin support.
- Python 3.11+ (standard library only); `xdg-open` and a default viewer for opening attachments.
- Himalaya **2.1.x**, with an IMAP account configured and noninteractive authentication working. Older CLI versions use different commands/JSON and are not supported.

Configure your account outside Yetimail:

```sh
himalaya --version
himalaya configure
himalaya --account personal --json envelope list --page-size 5
```

Use the default account or select an account through plugin settings. Yetimail starts at the account's default inbox alias; the folder picker discovers that account's selectable mailboxes. Keep passwords in your password manager/keyring, not plugin settings or this repository. Authentication must work without an interactive prompt; the helper has closed stdin and a 30-second timeout.

Gmail/OAuth, compose/reply, bulk operations, search, and full offline sync are outside this milestone.

## Install the local checkout

This links your development checkout; changes remain user-owned and survive Omarchy updates. Do not run the link command if that destination already exists.

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s "$(pwd)" ~/.config/omarchy/plugins/hiasinho.yetimail
omarchy-shell shell rescanPlugins
omarchy plugin enable hiasinho.yetimail
```

Run from this repository's root. Enabling with defaults will query your default Himalaya account. To try the UI without any mail access first, use the isolated demo below.

### Migrating from Jitsmail

The plugin ID changed from `hiasinho.jitsmail` to `hiasinho.yetimail`, so existing Omarchy widget settings do not transfer automatically. Disable and remove the old plugin entry or symlink, install Yetimail as shown above, then copy the non-secret widget settings you still want into the new `hiasinho.yetimail` entry. Yetimail starts with a fresh cache and never copies cached mail from `~/.cache/jitsmail`; remove that old directory manually when you no longer need it.

Settings are declared in `manifest.json` and stored in the widget's entry in `~/.config/omarchy/shell.json`. Preserve the rest of that file when editing. A widget entry looks like:

```json
{
  "id": "hiasinho.yetimail",
  "accounts": "hiash,hiasinho",
  "account": "hiash",
  "config": "",
  "demo": false,
  "refreshSeconds": 120
}
```

`accounts` is an optional comma-separated allowlist. Buttons switch between those accounts, clearing the previous inbox and reader; excluded accounts are never discovered or queried. The badge belongs to the selected account, not a combined inbox. Selection is per bar instance and resets to `account` after reload (or the first allowed account if the preferred account is excluded).

With an empty allowlist, the single-account behavior is unchanged. An empty `account` or `config` uses Himalaya's default. A nonempty config is a path passed directly to Himalaya. `demo: true` uses synthetic messages. `q` or Close dismisses the panel. Selecting another message waits until the current read completes.

## Keyboard navigation

All commands work inside the panel, including while the selectable message text has focus. The highlighted row is the list cursor; opening a message switches navigation to the reader, and `h` returns to the list.

| Key | Action |
| --- | --- |
| `j` / `k`, `↓` / `↑` | Select next/previous message in list; scroll in reader |
| `Enter`, `l`, `→` | Open the highlighted message and focus reader |
| `h`, `←` | Return from links to reader, or reader to list |
| `x` / `Shift+X` | Immediately archive / move to Trash; no-op already in the destination |
| `Delete` | Immediately trash; inside Trash, confirm removal with `Enter` or Delete button; `h/Esc` cancels |
| `Shift+M` | Move picker: `j/k` select destination, `Enter` moves, `h/Esc` cancels |
| `f` | Open/close folder picker; `j/k` select, `Enter/l` opens, `h/Esc` dismisses |
| `gi` / `gs` / `ga` / `gt` | Go to Inbox / Sent / Archive / Trash |
| `o` | Toggle the reader's link list |
| `a` | Toggle selectable attachment details; `j/k` select an attachment |
| `s` / `Enter` in attachments | Save / save and explicitly open the selected attachment |
| `v` | Toggle full selectable message headers |
| `j` / `k`, `Enter` in links | Select a link; explicitly open its destination in the browser |
| `Tab`, `Shift+Tab` | Switch panes (opens highlighted message if needed) |
| `gg` / `G` | First/last row on this page; top/bottom of reader |
| `Ctrl+d` / `Ctrl+u` | Half-page down/up in active pane |
| `n` / `p` | Older/newer page |
| `[` / `]` | Previous/next allowed account |
| `m` / `u` | Mark target message read/unread |
| `r`, `Ctrl+r` | Refresh current page |
| `?` | Toggle shortcut help |
| `Esc` | Dismiss help, return from links to reader to list, then close panel |
| `q` | Close panel |
| `Ctrl+c` | Copy selected message text |

Status changes target the highlighted row in list mode, or the open message in reader mode. Only explicit `m`/`u` commands or their buttons change read status. Real status changes require an explicitly selected account (not an unnamed default); the `hiash,hiasinho` allowlist supplies this. Actions wait for server success before updating the badge; failures leave the old status intact. No automatic marking when opening or navigating.

Older/newer navigation preserves the current page on failure. Yetimail explicitly requests descending date order instead of relying on backend defaults. A full page enables Older; an exact multiple of 50 can therefore have a final empty page. IMAP pages can shift as new mail arrives. Account switching returns to page 1.

## Folders

Press `f` or click the folder icon beside the account tabs to open the compact dropdown. The picker lists the folders Himalaya exposes for the current account, with Inbox first and Drafts, Junk, and custom folders following in server order when present. Use `j/k`, `gg/G`, and `Enter` to choose; `r` refreshes folder discovery while the picker is open. `gi`, `gs`, `ga`, and `gt` select known Inbox, Sent, Archive, and Trash folders. Himalaya 2.1's shared listing does not expose special-use roles, so role shortcuts currently match unambiguous conventional names among discovered folders, including the final component of hierarchical names such as `[Gmail]/Trash`; Gmail's `All Mail` is treated as Archive. Localized names remain available in the picker. Missing special folders report an error rather than guessing an unknown destination.

Changing folders resets to page 1 and clears the old reader; changing accounts returns to Inbox. All message reads, status changes, and attachment saves are scoped to the selected mailbox, even when two folders contain the same message ID. Before explicit-folder operations, the helper reads Himalaya's configuration to verify that a folder ID is not redirected by a mailbox alias. Conflicting aliases or configurations it cannot safely interpret are rejected rather than accessing a different folder; credentials are never logged. Folder navigation itself never moves, archives, deletes, or marks a message read. Use `x` to archive; there is no `e` binding.

Press `Shift+M` to move the highlighted message (or the displayed message in reader mode). The destination picker uses discovered folders; `j/k` selects, `Enter` moves, and `h/Esc` cancels without changes. Moves to the same folder are rejected, including when the configured Inbox alias resolves to that destination. Moving does not navigate to the destination or explicitly change read flags. Accepted moves immediately hide their source rows and advance selection, then run through Himalaya one at a time. The footer shows the pending count, and the page refreshes once after the queue drains. Both source and destination receive alias-routing checks. Moving to Trash is a folder move, not permanent deletion. There is no bulk move or undo yet.

Press `x` to archive or `Shift+X` to trash the highlighted row in list mode or the displayed message in reader mode, immediately without confirmation. These actions use the same safe folder-move queue as the picker, never `message delete`; `Shift+X` is a no-op in Trash, and `x` is a no-op in Archive. Missing or ambiguous roles fail closed. If discovery is not ready, the action loads folders and asks you to retry; it never guesses a destination. Actions are blocked while busy, closed, or in help, folder picker, or deletion confirmation. Real moves require an explicit account.

If a queued move fails, its row is restored and the remaining queue pauses. **Retry** submits that move again; **Cancel** restores unsent rows and reconciles with the server, but cannot undo a move already accepted by the server. Reading and list navigation remain available while moves run. Account, folder, and page changes stay disabled until the queue drains or is cancelled. Closing the panel does not cancel accepted moves; direct account/configuration changes discard unsent entries and reject stale results.

## Deleting one message

Press `Delete` for the highlighted row in list mode or the displayed message in reader mode. The reader toolbar's **Delete** button always targets its displayed message. Outside the uniquely resolved Trash folder, both immediately move to Trash without confirmation, just like `Shift+X`. Inside that Trash folder, they **ask for confirmation of permanent removal**, showing a snapshot of the account, folder, message ID, and subject. Only `Enter` or the modal's Delete button confirms; `h`, `Esc`, or Cancel dismisses without changes. Other panel shortcuts and background controls are disabled during confirmation. Closing, navigating, or changing message/account/config state invalidates the prompt; repeated submission is guarded. Real deletion requires an explicit account.

Himalaya 2.1's `message delete` follows its **trash-first policy**: it moves to the configured Trash, or requests permanent removal when already in Trash. On IMAP without UIDPLUS, a message may instead be flagged `Deleted` pending expunge; success does **not** guarantee permanent removal. An unresolved or ambiguous Trash blocks the action, not permission to bypass Trash. Role discovery uses the rules above; Himalaya's configured Trash policy remains authoritative for confirmed removal, so a differing configuration may move rather than permanently remove the message. Yetimail never expunges or performs bulk deletion.

After success, the source row is removed locally, selection advances to the next row (previous at the end), a matching reader is cleared, and the page is refreshed. The server's refreshed state remains authoritative, including messages pending expunge. Errors preserve the row and reader. Explicit source folders receive the same literal mailbox/alias-routing guard as other operations. Demo deletion never accesses config or Himalaya; refreshing restores synthetic messages. There is no undo in Yetimail.

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
scripts/test-pagination
scripts/test-folders
scripts/test-moves
scripts/test-deletions
scripts/test-keyboard
scripts/test-attachments
scripts/test-prefetch
bin/yetimail-helper list --demo
bin/yetimail-helper read --demo --id demo-1
```

The smoke test launches a temporary **offscreen** Quickshell with demo data, tests the QML → helper → inbox/read round trip, then exits. It does not install/enable anything or access your mail. Override `OMARCHY_SHELL_PATH` if Omarchy's shell is elsewhere. A guard executable prevents accidental Himalaya access even if demo mode regresses.

The lifecycle tests use shell fixtures instead of Python/Himalaya to check delayed host settings, overlapping requests, stale-result rejection, and failed launches. They replace only the compositor popup container for offscreen operation. Missing-executable warnings are expected in these tests.

Deletion tests cover safe CLI arguments, explicit-account and mailbox guards, synthetic demo operation, service failures/stale results/duplicate latches, and keyboard confirmation/cancellation/stale snapshots. Only mocked subprocesses, synthetic configs, and offline QML fixtures are used—no real mail commands run.

Attachment tests cover safe extraction, private unique writes in temporary homes, traversal/symlink defenses, runnable-type restrictions, and service save/open guards with offline fixtures. No tests open real attachments or alter real mail flags.

Pagination tests exercise the actual service with offline fixtures and demo data, including failed requests and stale account results. Keyboard tests send real Qt key events to the production widget and `ui/` components, including navigation while the TextArea has focus, mouse-to-keyboard attachment selection, stable reader lifetime, and folder anchor geometry. The harness copies `Widget.qml` and `ui/` together; only the backend and compositor popup are replaced, with no production helper staged. Install Qt's QML `QtTest` module to run keyboard tests.

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

The reference-inspired layout uses a compact monospace sidebar, bordered account selectors, dense sender/subject rows, and a separate message header above the reader. The sidebar names the current folder, sizes short mailbox pages closer to their content until the reader opens, and combines message count, page status, navigation, and shortcut help in one footer. The compact reader header shows the sender, recipients, and a short timestamp without redundant From/Date rows. HTML-to-text conversion preserves paragraph breaks while collapsing excessive blank space; it still never renders active HTML. Press `v` (or the header's ≡ button) to view and copy complete headers, including long subjects and recipient lists. Keyboard help opens as a floating shortcut card rather than shifting the inbox. Controls only expose implemented actions; compose and search are not placeholders.

```text
Widget.qml → MailService.qml → bin/yetimail-helper → Himalaya → IMAP
  commands      async JSON       normalization
  ↕ data / signals
ui/*.qml
  presentation
```

`Widget.qml` remains the BarWidget shell integration and sole interaction coordinator: it owns keyboard commands, selection and reader modes, modal guards, deletion snapshots, mutation coordination, and service/external-link calls. `ui/InboxPane.qml` and `ui/ReaderPane.qml` render independent data inputs and emit user-intent signals; their imperative APIs only focus, reveal rows, or scroll. `ui/FolderPicker.qml`, `ui/DeleteConfirmation.qml`, and `ui/ShortcutHelp.qml` are stable sibling overlays, not children of disabled mailbox controls. The inbox exposes the folder button's anchor geometry so the picker stays directly beneath it. `ui/MailLabel.qml` and `ui/MailButton.qml` share the monospace presentation defaults; labels and selectable message text remain plain text. Components never receive the widget/controller or call MailService, and no loaders recreate panes on mode changes.

The adapter executes argument arrays, never shell command strings. Account credentials stay under Himalaya's control. The helper suppresses backend stderr in UI errors because it may contain private configuration details. For connection errors, troubleshoot with Himalaya directly in a private terminal.

Processed messages are cached in `$XDG_CACHE_HOME/yetimail/messages.sqlite3` (normally `~/.cache/yetimail/messages.sqlite3`). The cache contains displayed headers, plain-text bodies, links, and attachment metadata, but not raw MIME or attachment payloads. It expires entries after 30 days, evicts least-recently-used entries above 100 MiB, and skips individual processed messages above 5 MiB. The directory is owner-only and database/sidecar permissions are tightened to 0600; this is not encryption, so system disk encryption is still recommended.

While the panel's message list is open, resting on a row for 300 ms queues that message and the next two for one-at-a-time background prefetch. Cached opens avoid Himalaya and network access, although they still start the small Python helper. Effective config/account, mailbox, raw message ID, parser version, and a versioned envelope fingerprint isolate entries. Fingerprints exclude mutable flags and persist across list refreshes and restarts. Envelopes lacking a nonempty ID/date/sender address or a string subject bypass caching. This is a best-effort identity: Himalaya's cross-backend listing does not expose durable mailbox generations, so reused IDs with identical envelope metadata or content-only server edits cannot be detected; force reload or clear the cache when needed. Moves and deletes invalidate the affected raw ID across all mailbox aliases in that account/config, retaining unrelated cached messages and in-flight prefetch writes. This may also evict an unrelated same-ID message in another mailbox; destination IDs are backend-assigned, and changed destination envelopes use new fingerprints. Old listing-token cache entries are discarded automatically on schema upgrade. Opening and prefetching omit Himalaya's `--seen` flag.

Clear all cached messages with `bin/yetimail-helper cache-clear`. Set `YETIMAIL_CACHE=0` in the shell environment to disable both cache reads and writes (background prefetch still runs but provides no speed benefit, so disabling the cache is mainly intended for troubleshooting). The legacy `JITSMAIL_CACHE` variable remains a compatibility fallback when `YETIMAIL_CACHE` is unset; the new name takes precedence. Cache failures fall back to ordinary Himalaya reads. This is a performance cache, not full offline sync: listing mail and uncached messages still requires the configured backend. Email text is explicitly displayed as plain text, never executable HTML. Large messages still need to be fetched by Himalaya; this implementation does not yet enforce a raw-download size cap.

Offline tests cover fixtures, JSON normalization, MIME parsing, safe command arguments, errors, and the QML integration. A live-server smoke test is still required with your configured account before treating this as a daily mail client.
