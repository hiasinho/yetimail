# Jitsmail

A keyboard-first Omarchy mail panel powered by **Himalaya 2.1**. Read and manage inbox status without leaving the desktop.

- Mail bar widget and two-pane inbox/reader.
- Inbox messages in pages of 50, newest first; mouse or Vim-like keyboard navigation.
- Optional account selector restricted to an explicit allowlist; only the selected account is queried.
- Unread badge counts **only the current page**, not the whole mailbox.
- Automatic refresh every 120 seconds, plus Refresh / Ctrl+R.
- Safe text-only message display with compact numbered web links and destination previews.
- Explicit mark-read / mark-unread actions. Opening a message does **not** mark it seen.
- No sending, deleting, or remote images.
- Demo mode requires no account and never invokes Himalaya.

Inspired by [omarchy-mail](https://github.com/roymckenzie/omarchy-mail). This is an independent implementation using Himalaya rather than implementing IMAP itself.

## Requirements

- Current Omarchy with the Quickshell-based shell and third-party plugin support.
- Python 3 (standard library only).
- Himalaya **2.1.x**, with an IMAP account configured and noninteractive authentication working. Older CLI versions use different commands/JSON and are not supported.

Configure your account outside Jitsmail:

```sh
himalaya --version
himalaya configure
himalaya --account personal --json envelope list --page-size 5
```

Use the default account or select an account through plugin settings. Jitsmail reads the account's default inbox alias. Keep passwords in your password manager/keyring, not plugin settings or this repository. Authentication must work without an interactive prompt; the helper has closed stdin and a 30-second timeout.

Gmail/OAuth, compose/reply, folders, attachments, search, and offline sync are outside this milestone.

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

All commands work inside the panel, including while the selectable message text has focus. The highlighted row is the list cursor; the ▸ indicator shows which pane the navigation keys control.

| Key | Action |
| --- | --- |
| `j` / `k`, `↓` / `↑` | Select next/previous message in list; scroll in reader |
| `Enter`, `l`, `→` | Open the highlighted message and focus reader |
| `h`, `←` | Return from links to reader, or reader to list |
| `o` | Toggle the reader's link list |
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

## Develop and test

```sh
python3 -m unittest discover -s tests -v
scripts/smoke-ui
scripts/test-lifecycle
scripts/test-pagination
scripts/test-keyboard
bin/jitsmail-helper list --demo
bin/jitsmail-helper read --demo --id demo-1
```

The smoke test launches a temporary **offscreen** Quickshell with demo data, tests the QML → helper → inbox/read round trip, then exits. It does not install/enable anything or access your mail. Override `OMARCHY_SHELL_PATH` if Omarchy's shell is elsewhere. A guard executable prevents accidental Himalaya access even if demo mode regresses.

The lifecycle tests use shell fixtures instead of Python/Himalaya to check delayed host settings, overlapping requests, stale-result rejection, and failed launches. They replace only the compositor popup container for offscreen operation. Missing-executable warnings are expected in these tests.

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

The reference-inspired layout uses a compact monospace sidebar, bordered account selectors, dense sender/subject rows, and a separate message header above the reader. Press `v` (or the header's ≡ button) to view and copy complete headers, including long subjects and recipient lists. Keyboard help opens as a floating shortcut card rather than shifting the inbox. Controls only expose implemented actions; compose, search, and folders are not placeholders.

```text
Widget.qml → MailService.qml → bin/jitsmail-helper → Himalaya → IMAP
  UI            async JSON       normalization
```

The adapter executes argument arrays, never shell command strings. Account credentials stay under Himalaya's control. The helper suppresses backend stderr in UI errors because it may contain private configuration details. For connection errors, troubleshoot with Himalaya directly in a private terminal.

No mail is written to a Jitsmail cache. Fetched messages remain in memory while the widget is loaded; there is no offline sync. Email text is explicitly displayed as plain text, never executable HTML. Large messages still need to be fetched by Himalaya; this prototype does not yet enforce a download-size cap.

Offline tests cover fixtures, JSON normalization, MIME parsing, safe command arguments, errors, and the QML integration. A live-server smoke test is still required with your configured account before treating this as a daily mail client.
