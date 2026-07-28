# Generic DID identifier syntax

`akashic/atproto/did.f` is the stateless syntax boundary for DID identifiers
carried by AT Protocol Lexicon values. It validates the generic identifier
form without deciding whether Akashic supports the method or can resolve the
identifier.

The contract follows the [AT Protocol DID profile](https://atproto.com/specs/did)
and the identifier grammar in
[W3C DID Core](https://www.w3.org/TR/did-core/#did-syntax).

```forth
REQUIRE atproto/did.f
```

## Contract

A valid identifier:

- is between `DID-LENGTH-MIN` (7) and `DID-LENGTH-MAX` (2048) bytes;
- begins with the exact lowercase prefix `did:`;
- has a nonempty method containing only lowercase ASCII letters;
- has a nonempty method-specific identifier containing ASCII letters, digits,
  `.`, `_`, `:`, `%`, or `-`;
- uses `%` only as a complete two-hex-digit percent triplet; and
- does not end in `:` or contain DID-URL path, query, or fragment syntax.

Empty colon-separated method-specific segments are permitted, so
`did:method::::value` is syntactically valid. DID bytes are case-sensitive.
The library never lowercases or otherwise normalizes them.

Generic syntax deliberately accepts methods other than the AT Protocol
resolution set. For example, a valid `did:key` passes this library even though
a later AT Protocol identity resolver may report that method as unsupported.
Callers must distinguish invalid syntax, unsupported method, and failed
resolution.

AT Protocol permits some syntax-only implementations to defer malformed
percent-triplet rejection until registration or resolution. This strict
boundary validates the W3C `%HH` production immediately and reports
`DID-S-ENCODING`.

## API and ownership

```forth
DID-STATUS-VALID?  ( status -- flag )
DID-VALIDATE       ( did-a did-u -- status )
DID-VALID?         ( did-a did-u -- flag )

DID-METHOD@
  ( did-a did-u -- method-a method-u status )

DID-SPECIFIC-ID@
  ( did-a did-u -- id-a id-u status )
```

The statusful validator is the production boundary. `DID-VALID?` is a
convenience predicate that collapses every non-success status to false.

The two accessors validate the complete source before returning a view. Their
successful addresses are synchronous, read-only borrows into the caller's
source and remain valid only as long as that source remains stable. On failure
they return `0 0 status`.

The module owns no storage, guard, resolver, transport, or mutable operation
state. It qualifies every nonempty source through the architectural
caller-span boundary.

## Status values

| Status | Meaning |
| --- | --- |
| `DID-S-OK` | The identifier is syntactically valid |
| `DID-S-INVALID` | Invalid scalar or null nonempty span |
| `DID-S-CAPACITY` | The identifier exceeds 2048 bytes |
| `DID-S-SYNTAX` | Prefix, method, identifier character, or terminal syntax is invalid |
| `DID-S-ENCODING` | A percent triplet is incomplete or non-hexadecimal |
| `DID-S-RANGE` | The caller span is outside admitted memory |
| `DID-S-PROTECTED` | The caller span intersects protected storage |
| `DID-S-PLATFORM` | Caller-span qualification violated its platform contract |

The module intentionally has no “unsupported method” status. Method support
belongs to the AT Protocol identity and resolution layer.
