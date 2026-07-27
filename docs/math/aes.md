# `akashic-aes` — caller-owned AES-GCM

`akashic/math/aes.f` is the generic authenticated-encryption boundary for
Megapad's AES-GCM engine. It provides AES-128-GCM and AES-256-GCM without
owning a current key, selected mode, tag, stream, or operation buffer.
Protocol choices such as OAuth credential envelopes, AT Protocol records,
and Streams persistence belong to their respective callers.

```forth
REQUIRE math/aes.f
```

The current native-model qualification profile admits a 96-bit IV and a
128-bit authentication tag. AAD and data may have any byte length from zero
through `0xFFFFFFFF`. Larger Forth cells are rejected instead of being
narrowed into the 32-bit MMIO length registers.

## API

```forth
AES-GCM-DESCRIPTOR-SIZE       ( -- 88 )
AES-GCM-WORKSPACE-SIZE        ( -- 240 )

AES-GCM-DESCRIPTOR-CLEAR      ( descriptor -- status )
AES-GCM-WORKSPACE-CLEAR       ( workspace -- status )
AES-GCM-DESCRIPTOR-VALID?     ( descriptor -- flag )
AES-GCM-STATUS-VALID?         ( status -- flag )

AES-GCM-SEAL                  ( descriptor workspace -- status )
AES-GCM-OPEN                  ( descriptor workspace -- status )
```

`SEAL` encrypts `INPUT` into `OUTPUT` and writes a tag to `TAG`. `OPEN`
first authenticates all of `INPUT` without reading or publishing DOUT, clears
the engine, and then repeats the authenticated operation to publish plaintext.
The publication pass rechecks the tag. Both APIs are one-shot, scoped calls.
There is deliberately no public begin/feed/finish lifecycle and no “last tag”
state.

## Descriptor

The descriptor contains eleven cells. Field words return the address of the
cell so callers populate them with `!`.

| Field | Meaning |
|---|---|
| `AES-GCM-D.KEY` | Borrowed key address |
| `AES-GCM-D.KEY-U` | Exactly 16 or 32 |
| `AES-GCM-D.IV` | Borrowed IV address |
| `AES-GCM-D.IV-U` | Exactly 12 |
| `AES-GCM-D.AAD` | Borrowed AAD address; zero is allowed when `AAD-U` is zero |
| `AES-GCM-D.AAD-U` | Unsigned 32-bit byte length |
| `AES-GCM-D.INPUT` | Borrowed plaintext for `SEAL`, ciphertext for `OPEN` |
| `AES-GCM-D.OUTPUT` | Ciphertext destination for `SEAL`, plaintext destination for `OPEN` |
| `AES-GCM-D.DATA-U` | Shared input/output byte length, unsigned 32-bit |
| `AES-GCM-D.TAG` | Tag destination for `SEAL`, expected tag for `OPEN` |
| `AES-GCM-D.TAG-U` | Exactly 16 |

Key size selects AES-128 or AES-256 for that operation; there is no
persistent mode switch. The workspace stages a 16-byte key into a safe
32-byte BIOS key window, avoiding an out-of-bounds read by the machine's
fixed-width `AES-KEY!` primitive.

Example descriptor setup:

```forth
CREATE D AES-GCM-DESCRIPTOR-SIZE ALLOT
CREATE W AES-GCM-WORKSPACE-SIZE ALLOT

D AES-GCM-DESCRIPTOR-CLEAR DROP
MY-KEY D AES-GCM-D.KEY !
32     D AES-GCM-D.KEY-U !
MY-IV  D AES-GCM-D.IV !
12     D AES-GCM-D.IV-U !
MY-AAD D AES-GCM-D.AAD !
MY-AAD-U D AES-GCM-D.AAD-U !
MY-PLAINTEXT D AES-GCM-D.INPUT !
MY-CIPHERTEXT D AES-GCM-D.OUTPUT !
MY-DATA-U D AES-GCM-D.DATA-U !
MY-TAG D AES-GCM-D.TAG !
16     D AES-GCM-D.TAG-U !

D W AES-GCM-SEAL
```

## Aliasing and publication

Exact in-place data operation is supported by setting `INPUT` and `OUTPUT`
to the same address. If those addresses differ, their spans must be
disjoint. The output and tag spans must also be disjoint from all borrowed
inputs, and descriptor/workspace storage must be disjoint from each other
and every external span. Borrowed key, IV, AAD, and input spans may overlap
one another.

The caller must retain exclusive ownership of the descriptor, workspace, key,
IV, AAD, input, output, and tag spans until the call returns. In particular,
another core must neither mutate the authenticated inputs between OPEN's two
passes nor observe the destination during its publication pass. This ownership
rule is part of the API contract, not merely a performance recommendation.
The second pass reauthenticates the bytes it observes and wipes on a failed
tag check; it is not a general detector for concurrent mutation. No bounded
workspace can make concurrent observation of an arbitrarily large destination
safe. The library guard serializes compliant API callers; code that bypasses
the library and writes the AES MMIO window must participate in the same
exclusive-ownership discipline.

All geometry is checked before the workspace, output, or tag is changed.
`SEAL` stages its tag in the workspace and publishes it only after the
complete encryption and engine-clearing transaction succeed. Once an operation
is admitted, any `SEAL` failure clears the entire ciphertext destination. Any
`OPEN` failure—including a bad tag in either pass—clears the entire plaintext
destination. Engine cleanup is attempted before caller-output cleanup, and
workspace wiping is independently attempted after every other admitted stage.
Engine and memory-operation THROWs inside the locked call boundary are
converted to `AES-GCM-S-INTERNAL`; recovery independently attempts engine,
output, and workspace cleanup.

## IV uniqueness

For a fixed AES key, a 96-bit GCM IV must never be reused. Reusing a key/IV
pair can destroy both confidentiality and authentication; a merely different
plaintext, AAD value, or tag destination does not make reuse safe.

This library neither allocates IVs nor persists nonce history. The caller must
provide a production nonce strategy—normally a durable, non-wrapping counter
or another reviewed construction—and rotate the key before that strategy can
repeat or exhaust its space. If random IVs are used, collision probability and
the permitted invocation count must be bounded by the application's security
policy. Failure to obtain a definitely fresh IV must fail closed before
`AES-GCM-SEAL` is called.

## Status

| Constant | Value | Meaning |
|---|---:|---|
| `AES-GCM-S-OK` | 0 | Operation completed and, for `OPEN`, authenticated |
| `AES-GCM-S-INVALID` | 1 | Invalid descriptor, span, fixed size, or length |
| `AES-GCM-S-ALIAS` | 2 | Forbidden overlap |
| `AES-GCM-S-TIMEOUT` | 3 | Bounded engine-state poll expired |
| `AES-GCM-S-HARDWARE` | 4 | Incoherent or rejected engine transaction |
| `AES-GCM-S-AUTH` | 5 | Authentication failed during `OPEN` |
| `AES-GCM-S-INTERNAL` | 6 | Unexpected THROW or cleanup failure |

The locked operation boundary maps exceptions to status, and the unconditional
cross-core guard is released on both ordinary and caught-failure paths. The API
never exposes the hardware status byte as an application result.

## Machine lifecycle and qualification boundary

The BIOS byte-window ABI is unchanged:

- `AES-KEY!`, `AES-IV!`, `AES-KEY-MODE!`
- `AES-AAD-LEN!`, `AES-DATA-LEN!`, `AES-CMD!`
- `AES-DIN!`, `AES-DOUT@`, `AES-TAG!`, `AES-TAG@`, `AES-STATUS@`

Status zero is idle, one is active, two is complete, and three is terminal
authentication/transaction failure. Every complete DIN window accounts for
exactly the remaining declared AAD or data bytes. Partial final windows are
zero-padded inside the native model. A tag mismatch clears native DOUT before
status three becomes observable.

The native model tracks which bytes of KEY, IV, both lengths, and (for OPEN)
TAG were written. CMD accepts only a complete configuration; key mode uses the
architectural AES-256 default when it is not explicitly selected.
Writing configuration while status is active aborts and zeroizes that
transaction; the byte that initiated reconfiguration is accepted as the first
byte of a new configuration, but CMD cannot restart until all required fields
have been rewritten. This is the native model's robust-entry behavior in the
absence of an architectural reset register.

The register contract has no dedicated abort/reset command. The scoped
cleanup therefore runs a zero-key, zero-length transaction, waits for its
terminal state with a fixed poll budget, then clears the visible tag
window. This overwrites the native key schedule and keeps cleanup inside the
existing BIOS ABI. A future machine-contract revision should add an
explicit abort-and-zeroize command.

The C++ native model is the qualification target for this landing.
Native-model qualification covers NIST SP 800-38D/CAVP vectors for empty,
AAD-only, partial, multi-block, AES-128, AES-256, in-place, stale-active
recovery, DOUT clearing, and bad-tag paths. The build embeds the SHA-256 digest
of `mp64_crypto.h`, and the focused runner requires the linked accelerator to
contain that exact source-derived fingerprint. A stale native extension
therefore fails the build gate before vectors run.

RTL parity is intentionally deferred. This landing makes no claim that the RTL
state machine has acquired the native model's tightened feed accounting,
configuration latching, authenticate-first publication, or zeroization
behavior.
