# AT Protocol handle syntax

`akashic/atproto/handle.f` is the stateless syntax and normalization boundary
for AT Protocol handles. It treats a handle as the protocol's restricted
ASCII hostname form and performs no DNS, HTTPS, IDNA, registration, or trust
work.

The accepted grammar and lowercase canonical form follow the official
[AT Protocol handle specification](https://atproto.com/specs/handle).

```forth
REQUIRE atproto/handle.f
```

## Syntax

A valid handle:

- is between `AT-HANDLE-LENGTH-MIN` (3) and
  `AT-HANDLE-LENGTH-MAX` (253) bytes;
- contains at least two period-separated labels;
- has labels from 1 through `AT-HANDLE-LABEL-MAX` (63) bytes;
- uses only ASCII letters, digits, and `-` inside a label;
- begins and ends every label with an ASCII letter or digit; and
- begins its final label with an ASCII letter.

Uppercase ASCII is valid input, but the canonical form is lowercase. Encoded
IDN labels such as `xn--...` are ordinary ASCII syntax here; Unicode-to-IDNA
conversion and display policy are not part of this component.

Reserved or environment-specific TLDs remain syntactically valid.
Consequently `.arpa`, `.local`, `.onion`, `.test`, and the special
`handle.invalid` value pass syntax admission. A resolution or registration
policy must reject or specially interpret them as appropriate. The 244-byte
practical bound for the `_atproto.` DNS lookup route is likewise not a syntax
limit; the protocol handle limit remains 253.

## API and publication

```forth
AT-HANDLE-STATUS-VALID?  ( status -- flag )
AT-HANDLE-VALIDATE       ( source source-u -- status )
AT-HANDLE-VALID?         ( source source-u -- flag )

AT-HANDLE-NORMALIZED?
  ( source source-u -- normalized? status )

AT-HANDLE-NORMALIZE
  ( source source-u destination destination-capacity
    -- written status )
```

`AT-HANDLE-NORMALIZE` validates the complete source and output geometry before
changing the destination. It publishes exactly `source-u` bytes, converting
only ASCII `A` through `Z` to lowercase. Exact in-place normalization is
supported. A fully disjoint destination is supported. Any other overlap
returns `AT-HANDLE-S-ALIAS`.

Every failure returns zero bytes written and leaves the destination unchanged.
Bytes after the successfully written result remain caller-owned and
unchanged. The module owns no workspace, buffers, guard, or mutable operation
state.

## Status values

| Status | Meaning |
| --- | --- |
| `AT-HANDLE-S-OK` | Validation or normalization completed |
| `AT-HANDLE-S-INVALID` | Invalid scalar or null nonempty span |
| `AT-HANDLE-S-CAPACITY` | The source exceeds 253 bytes or the destination is too small |
| `AT-HANDLE-S-SYNTAX` | Label, character, separator, or final-label syntax is invalid |
| `AT-HANDLE-S-ALIAS` | Source and destination partially overlap |
| `AT-HANDLE-S-RANGE` | A caller span is outside admitted memory |
| `AT-HANDLE-S-PROTECTED` | A caller span intersects protected storage |
| `AT-HANDLE-S-PLATFORM` | Caller-span qualification violated its platform contract |
