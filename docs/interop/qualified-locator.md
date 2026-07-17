# Qualified resource locators

`akashic/interop/qualified-locator.f` defines the closed, pointer-free QLOC
format for durable semantic resource identity and exact domain evidence. A
QLOC never contains an LBIND, live component revision, token, component
pointer, path, capability, or authority grant.

Every locator contains an owner contract ID and an embedded semantic RREF.
The embedded RREF revision is always zero. Two modes are supported:

| Mode | Domain revision | Digest | Projection contract |
|---|---:|---|---|
| `QLOC-M-IDENTITY` | 0 | none | empty |
| `QLOC-M-EXACT-DOMAIN` | positive | SHA3-256 with an explicit kind | nonempty |

The digest kind is either `QLOC-DK-SEMANTIC-STATE` or
`QLOC-DK-PROJECTION-CONTENT`. Projection-content evidence hashes the bytes
defined by the named projection contract; semantic-state evidence follows the
owner's named state contract. A digest without its kind and projection ID is
not exact evidence.

The 320-byte ABI is canonical: exact magic, ABI and size, zero flags and
reserved bytes, bounded valid UTF-8 owner/projection strings, zero-filled
unused string tails, an exact-size RREF with zero revision/reserved field, and
mode-specific zero or positive fields. `QLOC-VALID?` rejects weaker or
noncanonical encodings.

`QLOC-IDENTITY!` and `QLOC-EXACT!` build caller-owned locators. `QLOC-COPY`
and `QLOC=` operate only on valid canonical values. `QLOC-VALUE!` and
`QLOC-VALUE@` convert to and from a closed seven-field interoperability map:
`owner`, `resource`, `mode`, `domain_revision`, `digest_kind`,
`state_digest`, and `projection`.

Only the semantic owner can qualify an exact locator. If it cannot honestly
match the requested retained state, it returns `UNQUALIFIED`, `GONE`, or the
specific revision/digest mismatch; it must never substitute current or weaker
evidence.
