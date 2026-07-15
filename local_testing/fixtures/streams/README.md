# Streams qualification fixtures

These immutable payloads exist only for local contract and qualification profiles. Tests may install them through `Profile.initial_files`; production and standalone Streams profiles must never use them as startup data, demo content, recovery data, or a runtime fallback.

## Feed pairs

Each base feed contains a stable item and version one of a changing item. Its update keeps the stable item unchanged, revises the changing item under the same native identity, and adds one new item.

| Format | Stable identity | Revised identity | New identity |
| --- | --- | --- | --- |
| RSS | `rss:item:stable` | `rss:item:changed` | `rss:item:new` |
| Atom | `urn:example:atom:item:stable` | `urn:example:atom:item:changed` | `urn:example:atom:item:new` |
| JSON Feed | `jsonfeed:item:stable` | `jsonfeed:item:changed` | `jsonfeed:item:new` |

Replaying a base file must produce no new observations. Applying its update must produce one revision and one new observation while retaining the stable observation. The files also exercise Unicode, native metadata, enclosures or attachments, and next-page links. `malformed.xml` and `malformed.json` must be rejected without a partial commit or loss of the last good observations.

## Watched pages

The harness supplies one logical source identity for each page pair. `base.html` and `nav-change.html` have the same meaningful article text, so the navigation-only change must not create a revision. `content-change.html` changes the article state and must create one revision. The text pair follows the same base/update rule. `malformed.html` must have an explicit deterministic outcome and must never replace the last good observation on failure.

## Notifications

`poll.ndjson` contains one connection event and two messages with stable IDs `ntfy-inbound-001` and `ntfy-inbound-002`. Replaying it must suppress both message duplicates while preserving priority, tags, and Unicode. `publish-accepted.json` acknowledges an outbound message as `ntfy-outbound-001`.

Empty documents, body-overflow cases, encodings, redirects, content types, HTTP failures, timeouts, and indeterminate sends are transport or bound conditions and should be synthesized by the deterministic harness rather than treated as alternate runtime content.
