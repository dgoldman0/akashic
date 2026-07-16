# Syndication codec qualification fixtures

These immutable payloads belong to the reusable `akashic/syndication/`
library qualification profile. They are not Streams startup data, demo
content, recovery data, or a runtime fallback.

Each base feed contains a stable item and version one of a changing item. Its
update keeps the stable item unchanged, revises the changing item under the
same native identity, and adds one new item.

| Format | Stable identity | Revised identity | New identity |
| --- | --- | --- | --- |
| RSS | `rss:item:stable` | `rss:item:changed` | `rss:item:new` |
| Atom | `urn:example:atom:item:stable` | `urn:example:atom:item:changed` | `urn:example:atom:item:new` |
| JSON Feed | `jsonfeed:item:stable` | `jsonfeed:item:changed` | `jsonfeed:item:new` |

The files exercise Unicode, native metadata, enclosures or attachments, and
next-page links. `malformed.xml` and `malformed.json` must be rejected without
a partial destination commit; transactional scratch is wiped after decode.
