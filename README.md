# Jitsmail

A small Omarchy mail panel powered by **Himalaya 2.1**. First milestone: read your inbox without leaving the desktop.

- Mail bar widget and two-pane inbox/reader.
- Latest 50 inbox messages, newest first; click to read.
- Unread badge counts **only the loaded 50**, not the whole mailbox.
- Automatic refresh every 120 seconds, plus Refresh / Ctrl+R.
- Plain-text message display, including inert HTML-to-text fallback.
- Read-only: opening a message does **not** mark it seen. No sending, deleting, or remote images.
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
  "account": "personal",
  "config": "",
  "demo": false,
  "refreshSeconds": 120
}
```

An empty `account` or `config` uses Himalaya's default. A nonempty config is a path passed directly to Himalaya. `demo: true` uses synthetic messages. Escape or Close dismisses the panel. Selecting another message waits until the current read completes.

## Develop and test

```sh
python3 -m unittest discover -s tests -v
scripts/smoke-ui
scripts/test-lifecycle
bin/jitsmail-helper list --demo
bin/jitsmail-helper read --demo --id demo-1
```

The smoke test launches a temporary **offscreen** Quickshell with demo data, tests the QML → helper → inbox/read round trip, then exits. It does not install/enable anything or access your mail. Override `OMARCHY_SHELL_PATH` if Omarchy's shell is elsewhere. A guard executable prevents accidental Himalaya access even if demo mode regresses.

The lifecycle tests use shell fixtures instead of Python/Himalaya to check delayed host settings, overlapping requests, stale-result rejection, and failed launches. They replace only the compositor popup container for offscreen operation. Missing-executable warnings are expected in these tests.

For an interactive demo:

```sh
scripts/demo-ui
```

This opens a separate demo shell, not your running Omarchy shell. Stop it with Ctrl+C in the terminal.

## Design

```text
Widget.qml → MailService.qml → bin/jitsmail-helper → Himalaya → IMAP
  UI            async JSON       normalization
```

The adapter executes argument arrays, never shell command strings. Account credentials stay under Himalaya's control. The helper suppresses backend stderr in UI errors because it may contain private configuration details. For connection errors, troubleshoot with Himalaya directly in a private terminal.

No mail is written to a Jitsmail cache. Fetched messages remain in memory while the widget is loaded; there is no offline sync. Email text is explicitly displayed as plain text, never executable HTML. Large messages still need to be fetched by Himalaya; this prototype does not yet enforce a download-size cap.

Offline tests cover fixtures, JSON normalization, MIME parsing, safe command arguments, errors, and the QML integration. A live-server smoke test is still required with your configured account before treating this as a daily mail client.
