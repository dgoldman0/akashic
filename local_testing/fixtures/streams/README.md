# Streams-specific qualification fixtures

These immutable payloads exist only for local Streams contract and
qualification profiles. Tests may install them through `Profile.initial_files`;
production and standalone Streams profiles must never use them as startup
data, demo content, recovery data, or a runtime fallback. Reusable feed-codec
fixtures live separately under `local_testing/fixtures/syndication/`.

## Watched pages

The `streams-page-contracts` profile installs all six files and treats each
related pair as successive payloads for one logical source. The V1 snapshot
itself intentionally contains no source identity or observation revision.
`base.html` and `nav-change.html` have the same meaningful article text, so
their normalized digests must match even though their raw digests differ.
`content-change.html` changes the article state, so its normalized digest must
differ. The text pair likewise produces distinct normalized content.
`malformed.html` must fail deterministically and leave the last good snapshot
byte-for-byte unchanged.

## Notifications

`poll.ndjson` contains one connection event and two messages with stable IDs `ntfy-inbound-001` and `ntfy-inbound-002`. Replaying it must suppress both message duplicates while preserving priority, tags, and Unicode. `publish-accepted.json` acknowledges an outbound message as `ntfy-outbound-001`.

Empty documents, body-overflow cases, encodings, redirects, content types, HTTP failures, timeouts, and indeterminate sends are transport or bound conditions and should be synthesized by the deterministic harness rather than treated as alternate runtime content.
