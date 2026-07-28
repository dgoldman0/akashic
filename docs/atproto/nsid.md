# AT Protocol namespaced identifiers

`akashic/atproto/nsid.f` is the stateless exact-NSID syntax boundary used by
Lexicon record identifiers and XRPC methods. It admits the protocol maximum of
317 ASCII bytes: a reversed DNS authority of at most 253 bytes, followed by a
period and a case-sensitive alphanumeric name of at most 63 bytes. This is the
grammar specified by the [AT Protocol NSID specification][nsid-spec]; the
library performs syntax and canonicalization only.

```forth
REQUIRE atproto/nsid.f

S" com.atproto.sync.getRecord" NSID-CHECK
\ NSID-S-OK

S" com.atproto.sync.getRecord" NSID-SPLIT
\ authority-a authority-u name-a name-u NSID-S-OK
```

The authority has at least two labels. Every authority label is 1–63 ASCII
letters, digits, or hyphens, cannot begin or end with a hyphen, and the first
label—the reversed top-level domain—must begin with a letter. The final name
begins with a letter and otherwise contains only ASCII letters and digits.
Authority matching is case-insensitive, so uppercase authority bytes are valid
input and canonicalize to lowercase. The name remains case-sensitive.
Namespace globs ending in `.*` are a distinct syntax variation and are rejected
by this exact-identifier API.

`NSID-SPLIT` returns synchronous borrowed views into the admitted source.
`NSID-CANONICALIZE` lowercases only the authority and preserves the
case-sensitive name:

```forth
CREATE canonical 317 ALLOT
S" COM.Example.fooBar" canonical 317 NSID-CANONICALIZE
\ written NSID-S-OK; canonical contains com.example.fooBar
```

Canonicalization validates the complete source before writing. The destination
may begin exactly at the source for in-place publication or be fully disjoint
from it; partial overlap is rejected without publication. A larger capacity is
permitted for exact in-place publication, but only the admitted source length
is written.

`NSID-CHECK` reports `NSID-S-SYNTAX` when the input is too short or has no
authority/name separator, `NSID-S-AUTHORITY` for an invalid or overlong
authority, `NSID-S-NAME` for an invalid or overlong name, and
`NSID-S-CAPACITY` when the complete identifier exceeds 317 bytes. Invalid
caller geometry and platform span failures retain their distinct `INVALID`,
`RANGE`, `PROTECTED`, and `PLATFORM` statuses. `NSID-SPLIT` returns four zero
values on failure; `NSID-CANONICALIZE` returns zero bytes written and leaves
the destination untouched on every failure.

The module owns no mutable state and performs no DNS, Lexicon lookup, HTTP,
OAuth, XRPC, or application policy.

[nsid-spec]: https://atproto.com/specs/nsid
