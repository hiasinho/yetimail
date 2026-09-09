# Jitsmail

A keyboard-first Omarchy mail panel powered by **Himalaya 2.1**. Read and manage inbox status without leaving the desktop.

- Mail bar widget and two-pane inbox/reader.
- Inbox messages in pages of 50, newest first; mouse or Vim-like keyboard navigation.
- Optional account selector restricted to an explicit allowlist; only the selected account is queried.
- Unread badge counts **only the current page**, not the whole mailbox.
- Automatic refresh every 120 seconds, plus Refresh / Ctrl+R.
- Safe text-only message display with compact numbered web links and destination previews.
- Keyboard-accessible attachment details, safe saving, and explicit opening of supported types.
- Explicit mark-read / mark-unread actions. Opening a message does **not** mark it seen.
- No sending, deleting, or remote images.
- Demo mode requires no account and never invokes Himalaya.

Inspired by [omarchy-mail](https://github.com/roymckenzie/omarchy-mail). This is an independent implementation using Himalaya rather than implementing IMAP itself.

## Requirements

- Current Omarchy with the Quickshell-based shell and third-party plugin support.
- Python 3 (standard library only); `xdg-open` and a default viewer for opening attachments.
- Himalaya **2.1.x**, with an IMAP account configured and noninteractive authentication working. Older CLI versions use different commands/JSON and are not supported.

Configure your account outside Jitsmail:

```sh
himalaya --version
himalaya configure
himalaya --account personal --json envelope list --page-size 5
```

Use the default account or select an account through plugin settings. Jitsmail reads the account's default inbox alias. Keep passwords in your password manager/keyring, not plugin settings or this repository. Authentication must work without an interactive prompt; the helper has closed stdin and a 30-second timeout.

Gmail/OAuth, compose/reply, folders, search, and offline sync are outside this milestone.

## Install the local checkout

This links your development checkout; changes remain user-owned and survive Omarchy updates. Do not run the link command if that destination already exists.

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s "$(pwd)" ~/.config/omarchy/plugins/hiasinho.jitsmail
omarchy-shell shell rescanPlugins
omarchy plugin enable hiasinho.jitsmail
```

Run from this repository's root. Enabling with defaults will query your default Himalaya account. To try the UI without any mail access first, use the isolated demo below.

Settings are declared in `manifest.json` and stored in the widget's entry in `~/.config/omarchy/shell.json`. Preserve the rest of that file when editing. A widget entry looks like:

```json
{
  "id": "hiasinho.jitsmail",
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

Status changes target the highlighted row in list mode, or the open message in reader mode. Only explicit `m`/`u` commands or their buttons change server flags. Real status changes require an explicitly selected account (not an unnamed default); the `hiash,hiasinho` allowlist supplies this. Actions wait for server success before updating the badge; failures leave the old status intact. No automatic marking when opening or navigating.

Older/newer navigation preserves the current page on failure. A full page enables Older; an exact multiple of 50 can therefore have a final empty page. IMAP pages can shift as new mail arrives. Account switching returns to page 1.

## Reading links

Long web URLs become compact references such as `[1]` in the message body. In the reader, press `o` for the link list, use `j/k` to select, inspect the destination preview, then press `Enter` to open it in your default browser. `h` or `Esc` returns to the body. Mouse clicks select a link; the Open button opens it.

Only HTTP(S) destinations are supported. Links are never opened automatically; remote images and scripts remain blocked. Original destinations, including tracking parameters, are preserved—we do not follow redirects or silently rewrite URLs. The displayed sender-provided label is not proof of the destination's identity; check the URL before opening. Opening a link can trigger tracking in your browser.

## Attachments

Messages show compact attachment metadata beneath the header. Press `a` to inspect complete filenames, MIME types, and sizes in selectable text; use `j/k` to select, `gg`/`G` for first/last, `Ctrl+d/u` to scroll long details, and `h` or `Esc` to return. Click a filename chip or use the previous/next buttons to select with the mouse. The compact summary stays bounded when a message has many attachments.

In attachment mode, `s` or **Save** writes a copy to **`~/Downloads`**. `Enter` or **Open** saves a new copy, then invokes `xdg-open` with an argument array. These keys have no attachment actions outside this mode. Nothing is opened by inspection, selection, message reading, or saving alone. Each save creates a unique filename (`name (1).ext`, etc.), never overwrites existing files or follows file symlinks, and gives the file private non-executable permissions (0600). Sender path components, controls, and overlong filenames are sanitized. Downloads must be a real directory owned by you, not writable by other users; symlinked Downloads directories are intentionally rejected. This version uses the literal `~/Downloads`, not Himalaya's or XDG's configured download directory.

Opening is deliberately conservative: only `.txt` (UTF-8 plain text), PDF, PNG, JPEG, and GIF with matching MIME and basic content checks are supported. Executables, scripts, desktop shortcuts, HTML/SVG, archives, attached emails, unknown types, and mismatches remain **save-only**. This is not malware detection or a sandbox: only open files you trust, keep viewers updated, and remember that external viewers may access the network. A failed opener leaves the saved copy in place. Each viewer has an independent launcher: once it starts, further saves and opens are available immediately. Viewers may stay open indefinitely; Jitsmail does not impose a viewer lifetime timeout. Late launcher errors are shown only for the same account, message, and attachment action.

Account/config/message changes discard pending results and prevent a deferred open; closing the panel cancels a pending open too. An already-requested save can still finish on disk after navigation. Already-launched external viewers are not recalled. Demo saves produce a real synthetic `welcome.txt`, but demo opening is always suppressed.

Sizes are decoded payload sizes, not the encoded transfer size; unknown sizes are labeled explicitly. Named inline parts may be listed, but unnamed inline images are omitted. Attached emails are listed as attachments without exposing their nested attachments separately. Metadata comes from the already-fetched MIME message; inspection adds no server requests. A save refetches that same message through `message read --raw` without `--seen`, preserving the selected account/config and default inbox alias. Attachment IDs are Jitsmail-local ordinal/content hashes, **not** Himalaya's sparse MIME part IDs. Name, type, and payload must still match the inspected attachment or saving fails with a reload instruction. Attached emails are saved as RFC 5322 bytes; attached multipart containers are serialized as MIME.

## Develop and test

```sh
python3 -m unittest discover -s tests -v
scripts/smoke-ui
scripts/test-lifecycle
scripts/test-pagination
scripts/test-keyboard
scripts/test-attachments
bin/jitsmail-helper list --demo
bin/jitsmail-helper read --demo --id demo-1
```

The smoke test launches a temporary **offscreen** Quickshell with demo data, tests the QML → helper → inbox/read round trip, then exits. It does not install/enable anything or access your mail. Override `OMARCHY_SHELL_PATH` if Omarchy's shell is elsewhere. A guard executable prevents accidental Himalaya access even if demo mode regresses.

The lifecycle tests use shell fixtures instead of Python/Himalaya to check delayed host settings, overlapping requests, stale-result rejection, and failed launches. They replace only the compositor popup container for offscreen operation. Missing-executable warnings are expected in these tests.

Attachment tests cover safe extraction, private unique writes in temporary homes, traversal/symlink defenses, runnable-type restrictions, and service save/open guards with offline fixtures. No tests open real attachments or alter real mail flags.

Pagination tests exercise the actual service with offline fixtures and demo data, including failed requests and stale account results. Keyboard tests send real Qt key events to the production widget, including navigation while its TextArea has focus; only the backend and compositor popup are replaced. Install Qt's QML `QtTest` module to run keyboard tests.

For an interactive demo:

```sh
scripts/demo-ui
```

This opens a separate demo shell with two synthetic accounts, not your running Omarchy shell. Stop it with Ctrl+C in the terminal. Its logged temporary config path can also be used for demo-only visual checks:

```sh
quickshell -p /tmp/<demo-config> ipc call jitsmailDemo readFirst
quickshell -p /tmp/<demo-config> ipc call jitsmailDemo help
```

Neither command accesses real accounts.

## Design

The reference-inspired layout uses a compact monospace sidebar, bordered account selectors, dense sender/subject rows, and a separate message header above the reader. The compact header shows the sender, recipients, and a short timestamp without redundant From/Date rows. HTML-to-text conversion preserves paragraph breaks while collapsing excessive blank space; it still never renders active HTML. Press `v` (or the header's ≡ button) to view and copy complete headers, including long subjects and recipient lists. Keyboard help opens as a floating shortcut card rather than shifting the inbox. Controls only expose implemented actions; compose, search, and folders are not placeholders.

```text
Widget.qml → MailService.qml → bin/jitsmail-helper → Himalaya → IMAP
  UI            async JSON       normalization
```

The adapter executes argument arrays, never shell command strings. Account credentials stay under Himalaya's control. The helper suppresses backend stderr in UI errors because it may contain private configuration details. For connection errors, troubleshoot with Himalaya directly in a private terminal.

No mail is written to a Jitsmail cache; only explicit attachment save/open actions write downloaded files. Fetched messages remain in memory while the widget is loaded; there is no offline sync. Email text is explicitly displayed as plain text, never executable HTML. Large messages still need to be fetched by Himalaya; this prototype does not yet enforce a download-size cap.

Offline tests cover fixtures, JSON normalization, MIME parsing, safe command arguments, errors, and the QML integration. A live-server smoke test is still required with your configured account before treating this as a daily mail client.
