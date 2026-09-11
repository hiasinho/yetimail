# Agent instructions

Yetimail is a Quickshell/QML mail panel for Omarchy.
The backend uses Python 3.11+ (standard library only) and Himalaya 2.1.x.
Read the relevant README.md sections before changing behavior.

## Validation

Run commands from the repository root:
- Python tests: `python3 -m unittest discover -s tests -v`
- QML smoke test: `scripts/smoke-ui`
- Interactive offline demo: `scripts/demo-ui`
- Run relevant `scripts/test-*` suites for changed behavior.
  Available suites and prerequisites are documented in README.md.

Add regression tests for behavior changes. Report which checks ran,
and explicitly identify checks that could not run.

## Architecture

- Widget.qml: presentation, keyboard navigation, and user interaction.
- MailService.qml: asynchronous requests and UI-facing state.
- bin/yetimail-helper: Himalaya adapter, normalization, and file safety.
- manifest.json: plugin metadata and settings.

Keep these boundaries; do not invoke Himalaya directly from the widget.
Preserve stale-result rejection across account/config/folder/message changes.

## Safety boundaries

- Use demo data and offline fixtures for development and testing.
  Ask before accessing real mail or changing live desktop configuration.
- Demo mode must never invoke Himalaya or access mail configuration.
- Reading or navigating must not mark messages seen.
- Deletion requires explicit confirmation; never introduce automatic expunge.
- Treat mail content and attachment filenames as untrusted data.
- Render mail as plain text; never fetch remote images automatically.
- Open links and attachments only through explicit user actions.
- Use subprocess argument arrays, never shell-interpolated commands.
- Preserve attachment path, permission, and safe-opening checks.
- Never expose credentials, private configuration, or backend stderr in UI logs.

## Changes

Follow nearby code conventions and preserve unrelated working-tree changes.
Update README.md when shortcuts, settings, or user-visible behavior change.
