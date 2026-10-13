# akashic-rc4 — RC4

The RC4 stream cipher. RC4 is broken as a cipher; it is here because PDF's
standard security handler encrypts strings and streams with it.

```forth
REQUIRE rc4.f
```

`PROVIDED akashic-rc4`. It depends on nothing and keeps no state of its own.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `RC4-SIZE` | `( -- 272 )` | A key stream's record. |
| `RC4-INIT` | `( key-a key-u rc4 -- )` | Start the stream of a key of `key-u` bytes. |
| `RC4-XOR` | `( a u rc4 -- )` | Xor the stream's next `u` bytes into the `u` bytes at `a`. |

A key is 1 to 256 bytes; a key of no bytes starts the stream of the
permutation alone. `RC4-XOR` encrypts and decrypts alike, in place, and a
stream continues across calls. The caller owns the record, which holds the
permutation and its two indices.

## Cost

`RC4-INIT` takes about 20,000 guest steps, and `RC4-XOR` about 90 a byte.
