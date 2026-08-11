# akashic-crc — CRC-32 / CRC-32C / CRC-64

Hardware-backed, byte-exact CRC computations using MegaPad's CRC ISA engine.
The module supports one-shot buffers, stateful streaming, and continuation from
a previously finalized result.

```forth
REQUIRE crc.f
```

`PROVIDED akashic-crc`

## Algorithms

`CRC32` and `CRC32C` use the standard reflected tuples. `CRC64` is the distinct
non-reflected CRC-64/WE algorithm; it is not a compatibility alias for either
32-bit mode.

| Word | Polynomial | Init | Xorout | `"123456789"` |
|---|---:|---:|---:|---:|
| `CRC32` | `0xEDB88320` (reciprocal) | `0xFFFFFFFF` | `0xFFFFFFFF` | `0xCBF43926` |
| `CRC32C` | `0x82F63B78` (reciprocal) | `0xFFFFFFFF` | `0xFFFFFFFF` | `0xE3069283` |
| `CRC64` | `0x42F0E1EBA9EA3693` | `0xFFFFFFFFFFFFFFFF` | `0xFFFFFFFFFFFFFFFF` | `0x62EC59E3F1A4F00A` |

These parameter sets correspond to CRC-32/ISO-HDLC (IEEE), CRC-32C/iSCSI
(Castagnoli), and CRC-64/WE. Akashic does not retain public aliases for the old
non-reflected CRC-32/BZIP2 or non-reflected Castagnoli words: this project is
unreleased, and carrying the former meanings under compatibility names would
make new storage-format code needlessly ambiguous.

## Hardware path

Every computation uses the MegaPad CRC accelerator. Complete eight-byte
groups are loaded and passed to the BIOS `CRC-FEED` word, which issues
`CRC.Q`. The exact zero-to-seven-byte remainder is passed one byte at a time
to `CRC-FEED-BYTE`, which issues `CRC.B`; no zero padding or software CRC
transition is used. `CRC-FINAL@` finalizes and returns the result as one
accelerator operation.

The ordinary finalized transaction is:

```forth
mode CRC-MODE!       ( -- status )
CRC-RESET            ( -- status )
data ... CRC-FEED / CRC-FEED-BYTE  ( -- status )
CRC-FINAL@  ( -- crc )
```

Akashic checks every status returned by `CRC-MODE!`, `CRC-RESET`, `CRC-INIT!`,
`CRC-FEED`, `CRC-FEED-BYTE`, and `CRC-RAW-FINAL@`, throwing a nonzero status
unchanged. `CRC-FINAL@` is the one result-only operation. `CRC-INIT!` accepts
an arbitrary accumulator; the incremental and raw APIs use it to restore or
install caller state. MegaPad arbitrates the transaction from mode selection
through finalization, so another core cannot change its mode or accumulator
midway through the operation.

When Akashic is built with guarded wrappers enabled, one-shot and incremental
calls are scoped by the module guard. A streaming `BEGIN` acquires that guard
and its matching `END` releases it, so streaming calls must be balanced and
must remain on the owning task. A nested `BEGIN`, a one-shot or incremental
call made while that task owns a stream, and a mismatched-family `ADD` or `END`
throw the stream-state error `-258`. Rejected nested or cross-family calls leave
the original stream active and unchanged.

If a guarded hardware computation throws after Akashic successfully acquires
the CRC engine, Akashic attempts to finalize and discard the partial
accumulator as the same hardware owner, releases the module guard, and rethrows
the original error. Acquisition is tracked explicitly: when `CRC-MODE!`
returns `STATE/OWNER`, Akashic does not finalize a transaction that the task
already owned through a direct BIOS sequence. This gives ordinary buffer and
argument faults a bounded unwind path without disturbing unrelated ownership.
Raw BIOS CRC sequences still follow MegaPad's lower-level rule: the machine
does not automatically release a micro-cluster transaction on an exception,
and a failed cleanup itself requires same-owner recovery.

## Constants

```forth
CRC-MODE-CRC32   ( -- 4 )
CRC-MODE-CRC32C  ( -- 5 )
CRC-MODE-CRC64   ( -- 2 )

CRC32-INIT-VAL   ( -- 0xFFFFFFFF )
CRC64-INIT-VAL   ( -- 0xFFFFFFFFFFFFFFFF )
```

The mode constants are the exact selector values accepted by `CRC-MODE!`:
modes 4 and 5 are reflected IEEE and Castagnoli, while mode 2 remains
non-reflected CRC-64/WE. The init constants are also the xorout masks for their
respective widths. These names intentionally expose the current hardware
vocabulary; there are no aliases for the removed `CRC-POLY!` interface.

## One-shot API

```forth
CRC32   ( data len -- crc )
CRC32C  ( data len -- crc )
CRC64   ( data len -- crc )
```

Compute a CRC over exactly `len` readable bytes at `data`. Length must be
non-negative; a negative length throws the standard invalid-numeric-argument
error `-24`. Length zero is valid and returns zero for all three parameter
sets.

```forth
S" 123456789" CRC32  \ 0xCBF43926
```

## Raw seeded CRC-32C

```forth
CRC32C-RAW  ( seed data len -- raw )
```

`CRC32C-RAW` selects reflected Castagnoli mode, installs the caller-supplied
raw accumulator with `CRC-INIT!`, feeds exactly `len` bytes, and publishes the
raw accumulator through `CRC-RAW-FINAL@`. It does not apply xorout. The low 32
bits of `seed` are the initial accumulator; hardware zero-extends the returned
raw result to one cell.

Because raw finalization also releases the shared CRC transaction, its result
can seed the next fragment without holding the engine across an intervening
disk read:

```forth
CRC32-INIT-VAL first first-len CRC32C-RAW
               second second-len CRC32C-RAW  ( -- raw )
```

With the all-ones seed, `"123456789"` produces raw `0x1CF96D7C`. Applying
`CRC32-INIT-VAL XOR` to that value gives finalized CRC-32C `0xE3069283`.

## Streaming API

```forth
CRC32-BEGIN   ( -- )
CRC32-ADD     ( data len -- )
CRC32-END     ( -- crc )

CRC32C-BEGIN  ( -- )
CRC32C-ADD    ( data len -- )
CRC32C-END    ( -- crc )

CRC64-BEGIN   ( -- )
CRC64-ADD     ( data len -- )
CRC64-END     ( -- crc )
```

Use streaming when input already arrives in fragments. Each `ADD` may have
any non-negative length, including zero. Fragment boundaries do not alter the
result.

```forth
CRC32-BEGIN
header header-len CRC32-ADD
payload payload-len CRC32-ADD
CRC32-END
```

Only use the `ADD` and `END` words matching the selected `BEGIN` word.

## Incremental update API

```forth
CRC32-UPDATE   ( crc data len -- crc' )
CRC32C-UPDATE  ( crc data len -- crc' )
CRC64-UPDATE   ( crc data len -- crc' )
```

Continue from a previously finalized CRC. Pass zero for the first fragment.
The result of each call is finalized and can be stored or passed directly to
the next call.

```forth
0 first first-len CRC32-UPDATE
  second second-len CRC32-UPDATE
```

This produces the same value as one `CRC32` call over the concatenated bytes.

## Hex conversion and display

```forth
CRC32->HEX  ( crc dst -- 8 )
CRC64->HEX  ( crc dst -- 16 )
CRC32-.     ( crc -- )
CRC64-.     ( crc -- )
```

`CRC32->HEX` and `CRC64->HEX` write fixed-width lowercase hexadecimal text to
the caller's buffer and return its length. They do not add a terminator.
`CRC32-.` and `CRC64-.` emit the same fixed-width representation.

## Quick reference

| Word | Stack | Purpose |
|---|---|---|
| `CRC32` | `( data len -- crc )` | One-shot reflected CRC-32/ISO-HDLC |
| `CRC32C` | `( data len -- crc )` | One-shot reflected CRC-32C |
| `CRC32C-RAW` | `( seed data len -- raw )` | Caller-seeded reflected CRC-32C without xorout |
| `CRC64` | `( data len -- crc )` | One-shot CRC-64/WE |
| `CRC32-BEGIN` / `ADD` / `END` | see above | Streaming CRC-32 |
| `CRC32C-BEGIN` / `ADD` / `END` | see above | Streaming CRC-32C |
| `CRC64-BEGIN` / `ADD` / `END` | see above | Streaming CRC-64 |
| `CRC32-UPDATE` | `( crc data len -- crc' )` | Continue CRC-32 |
| `CRC32C-UPDATE` | `( crc data len -- crc' )` | Continue CRC-32C |
| `CRC64-UPDATE` | `( crc data len -- crc' )` | Continue CRC-64 |
| `CRC32->HEX` | `( crc dst -- 8 )` | Write eight lowercase hex digits |
| `CRC64->HEX` | `( crc dst -- 16 )` | Write sixteen lowercase hex digits |
