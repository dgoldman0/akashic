# akashic-crypto-acc — Shared EXT.CRYPTO Accumulator Ownership

`crypto-acc.f` is the generic ownership boundary for Megapad-64
cryptographic instructions that reuse per-core `ACC0`–`ACC3`.

```forth
REQUIRE crypto-acc.f
```

`PROVIDED akashic-crypto-acc` — requires `concurrency/guard.f`.

SHA-256 and the Field ALU are distinct instruction families, but their
multi-instruction operations share accumulator registers. A cooperative
same-core task switch can therefore corrupt either operation unless both
participate in one outer transaction.

## API

```forth
CRYPTO-ACC-WITH-TRANSACTION  ( i*x xt -- j*x )
CRYPTO-ACC-TRANSACTION-MINE? ( -- flag )
```

`CRYPTO-ACC-WITH-TRANSACTION` is recursive for the same execution owner.
Unit libraries acquire their own state guard inside it; the canonical lock
order is always:

```text
crypto-ACC transaction -> unit-specific guard
```

Nested scopes preserve Field previous-result state so an explicitly scoped
multi-operation computation remains valid. On the outermost normal or
exceptional exit, the library performs a public zero raw multiply before
releasing ownership. This overwrites `ACC0`–`ACC3`, the Field ALU
`prev_lo`/`prev_hi` state, and the tile destination, then clears its own
scrub buffers.

This module owns no key or protocol policy. Applications normally use it
indirectly through `SHA256-HASH*` or `FIELD-WITH-TRANSACTION`.
