# Offline keyboard regression

Run `scripts/test-keyboard`. Requires Quickshell, Qt 6 QtTest QML, and the shared
Omarchy shell types (`OMARCHY_SHELL_PATH`, default `/usr/share/omarchy/shell`).

The script copies the current production `Widget.qml` to a temporary shell root,
substitutes an in-memory 63-envelope/two-chunk continuous MailService, and retains shared Ui
and Commons types except for the compositor-only KeyboardPanel container. No
production MailService, Python helper, account config, or mail command is loaded.
The process has an empty executable search path and a hard timeout.

QtTest `keyClick` delivers actual Qt key events to the offscreen FloatingWindow:
these tests exercise real `Shortcut` resolution, including while the production
reader TextArea owns active focus. No desktop key injection is involved. Assertions
cover cursor limits, automatic latest-cursor preview without marking seen, reader
scrolling and half-screens, gg/G, h/Escape, Tab/Shift+Tab, incremental loading and resets,
account allowlisting and cycling, list-versus-reader mark targets, busy guards, help
and closed shortcuts.

Quickshell does not install QtTest's CLI reporter. The test explicitly emits
assertion failures, per-test status, and QtTest result counts; the runner requires
the final success sentinel and rejects errors. A deliberately incorrect assertion
was used to verify that a test failure makes the runner exit nonzero.

Limits: the fake intentionally does not test real service concurrency or helper
semantics (covered elsewhere). Offscreen testing cannot validate compositor popup
focus acquisition. Shared Commons may log missing `hyprctl`/`fc-match` warnings
because PATH is intentionally isolated; these do not affect keyboard delivery.
