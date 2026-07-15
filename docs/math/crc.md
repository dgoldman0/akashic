# akashic-crc — CRC-32 / CRC-32C / CRC-64

Hardware-backed, byte-exact CRC computations using MegaPad's CRC ISA engine.
The module supports one-shot buffers, stateful streaming, and continuation from
a previously finalized result.

```forth
REQUIRE crc.f
```

`PROVIDED akashic-crc`

## Algorithms

All three algorithms are MSB-first and non-reflected.

| Word | Polynomial | Init | Xorout | `"123456789"` |
|---|---:|---:|---:|---:|
| `CRC32` | `0x04C11DB7` | `0xFFFFFFFF` | `0xFFFFFFFF` | `0xFC891918` |
| `CRC32C` | `0x1EDC6F41` | `0xFFFFFFFF` | `0xFFFFFFFF` | `0x05440F15` |
| `CRC64` | `0x42F0E1EBA9EA3693` | `0xFFFFFFFFFFFFFFFF` | `0xFFFFFFFFFFFFFFFF` | `0x62EC59E3F1A4F00A` |

These parameter sets correspond to CRC-32/BZIP2, non-reflected Castagnoli,
and CRC-64/WE. In particular, `CRC32C` does not produce the reflected
CRC-32C/iSCSI check value.

## Hardware path

Every computation uses the MegaPad CRC accelerator. Complete eight-byte
groups are loaded and passed to the BIOS `CRC-FEED` word, which issues
`CRC.Q`. The exact zero-to-seven-byte remainder is passed one byte at a time
to `CRC-FEED-BYTE`, which issues `CRC.B`; no zero padding or software CRC
transition is used. `CRC-FINAL@` finalizes and returns the result as one
accelerator operation.

The low-level transaction is:

```forth
polynomial CRC-POLY!
initial-value CRC-INIT!
data ... CRC-FEED / CRC-FEED-BYTE
CRC-FINAL@  ( -- crc )
```

`CRC-INIT!` accepts an arbitrary accumulator. This is what allows the
incremental API to restore a finalized CRC and continue it. MegaPad arbitrates
the transaction from polynomial selection through finalization, so another
core cannot change its mode or accumulator midway through the operation.

When Akashic is built with guarded wrappers enabled, one-shot and incremental
calls are scoped by the module guard. A streaming `BEGIN` acquires that guard
and its matching `END` releases it, so streaming calls must be balanced and
must remain on the owning task. A nested `BEGIN`, a one-shot or incremental
call made while that task owns a stream, and a mismatched-family `ADD` or `END`
throw the stream-state error `-258`. Rejected nested or cross-family calls leave
the original stream active and unchanged.

If a guarded hardware computation throws after acquisition, Akashic attempts
to finalize and discard the partial accumulator as the same hardware owner,
releases the module guard, and rethrows the original error. This gives ordinary
buffer and argument faults a bounded unwind path. Raw BIOS CRC sequences still
follow MegaPad's lower-level rule: the machine does not automatically release a
micro-cluster transaction on an exception, and a failed cleanup itself requires
same-owner recovery.

## Constants

```forth
CRC-POLY-CRC32   ( -- 0 )
CRC-POLY-CRC32C  ( -- 1 )
CRC-POLY-CRC64   ( -- 2 )

CRC32-INIT-VAL   ( -- 0xFFFFFFFF )
CRC64-INIT-VAL   ( -- 0xFFFFFFFFFFFFFFFF )
```

The polynomial constants are the selector values accepted by
`CRC-POLY!`. The init constants are also the xorout masks for their respective
widths.

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
S" 123456789" CRC32  \ 0xFC891918
```

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
| `CRC32` | `( data len -- crc )` | One-shot CRC-32/BZIP2 |
| `CRC32C` | `( data len -- crc )` | One-shot non-reflected CRC-32C |
| `CRC64` | `( data len -- crc )` | One-shot CRC-64/WE |
| `CRC32-BEGIN` / `ADD` / `END` | see above | Streaming CRC-32 |
| `CRC32C-BEGIN` / `ADD` / `END` | see above | Streaming CRC-32C |
| `CRC64-BEGIN` / `ADD` / `END` | see above | Streaming CRC-64 |
| `CRC32-UPDATE` | `( crc data len -- crc' )` | Continue CRC-32 |
| `CRC32C-UPDATE` | `( crc data len -- crc' )` | Continue CRC-32C |
| `CRC64-UPDATE` | `( crc data len -- crc' )` | Continue CRC-64 |
| `CRC32->HEX` | `( crc dst -- 8 )` | Write eight lowercase hex digits |
| `CRC64->HEX` | `( crc dst -- 16 )` | Write sixteen lowercase hex digits |
