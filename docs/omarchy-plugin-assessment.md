# Yetimail: Omarchy plugin assessment

## Overall assessment

Yetimail has a solid architecture and unusually good offline regression coverage, but it is not ready for marketplace submission. The main gaps are specific safety/lifecycle issues and publication requirements—not a need to rewrite the application.

This records the completed read-only assessment. File locations, findings, and validation results describe the code at review time; they have not been revalidated while saving this document. No repository changes were made during the assessment.

## Findings

### 1. High: demo settings arrive too late to prevent real-config requests

Location: `Widget.qml:737–752`

Omarchy injects `bar` before `settings`. Setting `bar` activates MailService, immediately starting account-label and account-overview requests while `demo` is still false.

An isolated reproduction with a fake helper produced:

```text
account-labels … demo=false
accounts … demo=false
list … demo=true
```

This violates the promised demo isolation. Defer initialization until host settings have settled. Stale-result rejection cannot undo a configuration read already started.

### 2. High: untrusted mail processing has no effective resource ceiling

Locations: `bin/yetimail-helper:217–220`, `MailService.qml:1708,1756`

Himalaya stdout/stderr are buffered without byte limits. MIME parsing, decoded content, and helper JSON can then feed unbounded QML collectors inside the desktop shell.

The subprocess timeout and cache quotas do not bound this pipeline. A sufficiently large message can exhaust memory during ordinary reading or automatic prefetching. Omarchy marketplace reviews have explicitly blocked this pattern.

Apply limits before buffering/parsing, plus separate limits for displayed bodies, headers, links, attachment metadata, and final JSON.

### 3. Medium: missing `open()` breaks standard shell panel routing

Locations: `Widget.qml:600,843`

Yetimail exposes `opened` and `close()`, but no root `open()`. Omarchy’s bar requires all three to recognize a popup widget.

Consequently, shell summon/toggle/hide routing and panel-navigation integration skip Yetimail, although clicking its button works. Add an idempotent `open()` and share that lifecycle with button handling.

### 4. Medium: background warming bypasses the configuration-save pause

Locations: `MailService.qml:608–612,666–695`

`prepareAccountConfigSave()` blocks mail access and clears queues, but warming can repopulate them. Its launchers do not check `accountConfigBlocked`.

An isolated reproduction launched folder discovery and account listing while that flag remained true. Gate both scheduling and execution until the save pause is released.

### 5. Medium: URL normalization can consume quadratic processing time

Location: `bin/yetimail-helper:81–89`

Trailing closing brackets repeatedly trigger whole-string scans and copies. Synthetic tests showed approximately fourfold processing time whenever input doubled.

This happens after the Himalaya timeout has ended and can stall prefetch/read processing. Use linear-time trimming and bounded URL lengths.

## Marketplace readiness

Publication essentials missing or unconfirmed at review time:

- No root `LICENSE` or equivalent.
- README documents local development linking, but lacks a clear standard installation/removal section for published Yetimail.
- Public repository availability was not established.

The manifest passes Omarchy validation. That is useful, but it is not marketplace approval or a security review.

## What already meets the expectations well

- Clear presentation → asynchronous service → backend adapter boundaries.
- Argument-array subprocess execution and redacted backend errors.
- Explicit plain-text rendering; no automatic remote images or link opening.
- Strong attachment filename, permission, safe-opening, and filesystem protections.
- Explicit destructive-action confirmation and substantial stale-result rejection.
- Shared Omarchy bar/popup components and shell settings APIs.
- Extensive offline fixtures that avoid real mail.

## Architecture and polish recommendations

These are improvements, not formal acceptance requirements:

- Split the large `Widget.qml` and `MailService.qml` by responsibility without weakening their coordination.
- Adopt `Style.font` and `Style.space` more consistently; much typography and geometry remains fixed.
- Validate narrow-screen layouts: the fixed 310-pixel sidebar and reader toolbar need adaptive behavior.
- Bound the continuously accumulated in-memory message list; the snapshot-cache limit does not bound loaded rows.

## Validation performed during the assessment

Passed:

- 187 Python tests.
- Omarchy plugin validation.
- `qmllint`.
- Smoke test and all nine `scripts/test-*` suites.

Not performed:

- Live-mail testing.
- Compositor-level visual/multi-monitor testing.
- Marketplace approval workflows.

## Recommended priority

1. Fix demo isolation and resource bounds.
2. Fix panel lifecycle, configuration-save coordination, and URL normalization.
3. Complete publication documentation and licensing.
4. Address architecture and visual-polish recommendations.

## Upstream reference material

The assessment draws on Omarchy Quattro documentation, implementation patterns, marketplace policies, and concrete maintainer reviews. Technical validation, marketplace listing approval, and upstream PR acceptance are separate processes. Verification applies to an exact reviewed snapshot and is not a security audit or guarantee.

- [Omarchy shell architecture](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md)
- [Plugin development guide](https://omarchyplugins.com/develop.html)
- [Omarchy contribution and testing guidance](https://github.com/omacom/omarchy/blob/quattro/AGENTS.md)
- [Marketplace submission requirements](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md)
- [Marketplace security policy](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md)
- [Marketplace verification policy](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md)
- [Loopbox review and remediation history](https://github.com/omacom/omarchy-plugin-marketplace/issues/2002)
- [Omaclippy maintainer review: input monitoring, process bounds, and state safety](https://github.com/omacom/omarchy-plugin-marketplace/issues/3996#issuecomment-5505714908)
