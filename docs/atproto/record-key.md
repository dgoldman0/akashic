# AT Protocol record keys

`akashic/atproto/record-key.f` is the stateless syntax boundary for the
protocol-wide AT record-key string format:

```forth
REQUIRE atproto/record-key.f
```

It follows the official [AT Protocol record-key specification][record-key].
A key contains 1 through 512 ASCII characters selected from letters, digits,
period, hyphen, underscore, colon, and tilde. The exact values `.` and `..`
are rejected. Keys are case-sensitive and are never normalized.

```forth
S" 3jui7kd54zh2y" AT-RKEY-VALIDATE  \ AT-RKEY-S-OK
S" self" AT-RKEY-VALID?             \ true
S" alpha/beta" AT-RKEY-VALID?       \ false
```

This component validates the general `any` grammar only. A Lexicon may impose
the narrower `tid`, `nsid`, or `literal:<value>` policy; that policy belongs to
the record schema or repository operation consuming the key.

The module owns no mutable state and copies no caller data. The source is a
synchronous read-only borrow. Invalid physical memory, protected spans, and
platform admission failures are reported separately from syntax and capacity.

Public bounds and operations:

```forth
AT-RKEY-LENGTH-MIN       \ 1
AT-RKEY-LENGTH-MAX       \ 512
AT-RKEY-STATUS-VALID?    ( status -- flag )
AT-RKEY-VALIDATE         ( source source-u -- status )
AT-RKEY-VALID?           ( source source-u -- flag )
```

[record-key]: https://atproto.com/specs/record-key
