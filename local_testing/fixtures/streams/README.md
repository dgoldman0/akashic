# Streams-specific qualification fixtures

These immutable payloads exist only for local Streams contract and
qualification profiles. Tests may install them through `Profile.initial_files`;
production and standalone Streams profiles must never use them as startup
data, demo content, recovery data, or a runtime fallback. Reusable feed-codec
fixtures live separately under `local_testing/fixtures/syndication/`.

## Watched pages

The harness supplies one logical source identity for each page pair. `base.html` and `nav-change.html` have the same meaningful article text, so the navigation-only change must not create a revision. `content-change.html` changes the article state and must create one revision. The text pair follows the same base/update rule. `malformed.html` must have an explicit deterministic outcome and must never replace the last good observation on failure.

## Notifications

`poll.ndjson` contains one connection event and two messages with stable IDs `ntfy-inbound-001` and `ntfy-inbound-002`. Replaying it must suppress both message duplicates while preserving priority, tags, and Unicode. `publish-accepted.json` acknowledges an outbound message as `ntfy-outbound-001`.

Empty documents, body-overflow cases, encodings, redirects, content types, HTTP failures, timeouts, and indeterminate sends are transport or bound conditions and should be synthesized by the deterministic harness rather than treated as alternate runtime content.
