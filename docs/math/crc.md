# akashic-crc — CRC-32 / CRC-32C / CRC-64

Hardware-accelerated CRC wrapper.  Full 8-byte chunks are processed
by the BIOS CRC coprocessor at MMIO `0xFFFF_FF00_0000_0980`; any
remaining 1–7 tail bytes are handled in software (bit-by-bit) for
byte-exact, standards-compliant results.

```forth
REQUIRE crc.f
```

`PROVIDED akashic-crc` — no additional dependencies.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [One-Shot API](#one-shot-api)
- [Streaming API](#streaming-api)
- [Incremental Update API](#incremental-update-api)
- [Hex Conversion & Display](#hex-conversion--display)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Hardware-accelerated** | 8-byte bulk chunks are processed by the BIOS CRC device — 8 bytes / cycle throughput. |
| **Byte-exact** | Tail bytes (1–7) are processed via software bit-by-bit CRC to avoid the zero-padding that the raw hardware path imposes. |
| **Standards-compliant** | Results match CRC-32 (ISO 3309), CRC-32C (Castagnoli / iSCSI), and CRC-64-ECMA-182 reference implementations. |
| **Three APIs** | One-shot for simple use, streaming for fragmented data, incremental update for resumable CRC. |
| **MSB-first** | All polynomials use the "normal" (MSB-first) convention, not reflected/LSB-first.  This differs from Intel CRC32C (which uses reflected) and Python's `binascii.crc32` (also reflected). |
| **Not reentrant** | Module-scoped VARIABLEs for internal state.  One CRC computation at a time. |

### Relationship to KDOS CRC-BUF

KDOS provides `CRC32-BUF`, `CRC32C-BUF`, and `CRC64-BUF` which use the
hardware CRC device directly.  These zero-pad the final sub-8-byte chunk,
which is fast and correct for system-internal integrity checks (both sides
use the same padding) but does **not** match standard CRC values for inputs
whose length is not a multiple of 8.

The Akashic wrappers add the software tail-byte path so results always
match the standards, regardless of input length.

---

## Constants

### CRC-POLY-CRC32

```forth
CRC-POLY-CRC32  ( -- 0 )
```

Hardware polynomial selector for CRC-32 (polynomial `0x04C11DB7`).

### CRC-POLY-CRC32C

```forth
CRC-POLY-CRC32C  ( -- 1 )
```

Hardware polynomial selector for CRC-32C (polynomial `0x1EDC6F41`).

### CRC-POLY-CRC64

```forth
CRC-POLY-CRC64  ( -- 2 )
```

Hardware polynomial selector for CRC-64-ECMA (polynomial `0x42F0E1EBA9EA3693`).

### CRC32-INIT-VAL

```forth
CRC32-INIT-VAL  ( -- 0xFFFFFFFF )
```

Standard initial value for CRC-32 and CRC-32C.

### CRC64-INIT-VAL

```forth
CRC64-INIT-VAL  ( -- 0xFFFFFFFFFFFFFFFF )
```

Standard initial value for CRC-64-ECMA.

---

## One-Shot API

### CRC32

```forth
CRC32  ( data len -- crc )
```

Compute CRC-32 (ISO 3309 / ITU-T V.42) of *len* bytes at *data*.

```forth
CREATE msg 3 ALLOT  97 msg C!  98 msg 1+ C!  99 msg 2 + C!
msg 3 CRC32  \ → 0x648CBB73
```

### CRC32C

```forth
CRC32C  ( data len -- crc )
```

Compute CRC-32C (Castagnoli / iSCSI) of *len* bytes at *data*.

### CRC64

```forth
CRC64  ( data len -- crc )
```

Compute CRC-64-ECMA-182 of *len* bytes at *data*.

---

## Streaming API

For data that arrives in fragments or is too large to buffer.
The streaming API uses pure software byte-by-byte processing,
so results are correct regardless of how the data is split
across `ADD` calls.

### CRC32-BEGIN / CRC32-ADD / CRC32-END

```forth
CRC32-BEGIN  ( -- )
CRC32-ADD    ( addr len -- )
CRC32-END    ( -- crc )
```

```forth
CRC32-BEGIN
part1 n1 CRC32-ADD
part2 n2 CRC32-ADD
CRC32-END    \ → CRC32( part1 || part2 )
```

### CRC32C-BEGIN / CRC32C-ADD / CRC32C-END

```forth
CRC32C-BEGIN  ( -- )
CRC32C-ADD    ( addr len -- )
CRC32C-END    ( -- crc )
```

### CRC64-BEGIN / CRC64-ADD / CRC64-END

```forth
CRC64-BEGIN  ( -- )
CRC64-ADD    ( addr len -- )
CRC64-END    ( -- crc )
```

---

## Incremental Update API

Resume a CRC from a previously finalized result.  Pass `0` as the
initial CRC for the first chunk.

### CRC32-UPDATE

```forth
CRC32-UPDATE  ( crc data len -- crc' )
```

Continue a CRC-32 computation.  Uses hardware bulk + software tail.

```forth
0 buf1 n1 CRC32-UPDATE    \ first chunk
  buf2 n2 CRC32-UPDATE    \ second chunk (crc stays on stack)
\ → CRC32( buf1 || buf2 )
```

### CRC32C-UPDATE

```forth
CRC32C-UPDATE  ( crc data len -- crc' )
```

### CRC64-UPDATE

```forth
CRC64-UPDATE  ( crc data len -- crc' )
```

---

## Hex Conversion & Display

### CRC32-.

```forth
CRC32-.  ( crc -- )
```

Print a 32-bit CRC as 8 lowercase hex characters.

### CRC64-.

```forth
CRC64-.  ( crc -- )
```

Print a 64-bit CRC as 16 lowercase hex characters.

### CRC32->HEX

```forth
CRC32->HEX  ( crc dst -- n )
```

Convert 32-bit CRC to 8 lowercase hex characters at *dst*.
Returns 8 (the character count).

### CRC64->HEX

```forth
CRC64->HEX  ( crc dst -- n )
```

Convert 64-bit CRC to 16 lowercase hex characters at *dst*.
Returns 16 (the character count).

---

## Hardware Detail

The BIOS CRC coprocessor lives at MMIO base `0xFFFF_FF00_0000_0980`:

| Offset | R/W | Register | Description |
|--------|-----|----------|-------------|
| `+0x00` | W | POLY | 0 = CRC32, 1 = CRC32C, 2 = CRC64 |
| `+0x08` | W | INIT | Initial CRC value (64-bit LE) |
| `+0x10` | W | DIN | 8-byte data input (triggers on byte 7) |
| `+0x18` | R | RESULT | Current CRC value (64-bit LE) |
| `+0x20` | W | CTRL | 0 = reset, 1 = finalize (XOR-out) |

The Akashic wrapper uses BIOS words `CRC-POLY!`, `CRC-INIT!`, `CRC-FEED`,
`CRC@`, and `CRC-FINAL` which manage these registers.

### Why software tail bytes?

The hardware DIN register accumulates 8 bytes and processes them as a
unit when byte 7 is written.  There is no single-byte feed mode.  KDOS's
`CRC-BUF` zero-pads the last chunk, which makes the CRC include padding
zeros — fine for internal integrity, wrong for standards compliance.
The Akashic wrapper reads the hardware register after bulk processing,
then continues with bit-by-bit software CRC for any remaining 1–7 bytes.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `CRC-POLY-CRC32` | `( -- 0 )` | Polynomial selector: CRC-32 |
| `CRC-POLY-CRC32C` | `( -- 1 )` | Polynomial selector: CRC-32C |
| `CRC-POLY-CRC64` | `( -- 2 )` | Polynomial selector: CRC-64 |
| `CRC32-INIT-VAL` | `( -- 0xFFFFFFFF )` | CRC-32 init value |
| `CRC64-INIT-VAL` | `( -- 0xFFFFFFFFFFFFFFFF )` | CRC-64 init value |
| `CRC32` | `( data len -- crc )` | One-shot CRC-32 |
| `CRC32C` | `( data len -- crc )` | One-shot CRC-32C |
| `CRC64` | `( data len -- crc )` | One-shot CRC-64 |
| `CRC32-BEGIN` | `( -- )` | Start streaming CRC-32 |
| `CRC32-ADD` | `( addr len -- )` | Feed data |
| `CRC32-END` | `( -- crc )` | Finalize CRC-32 |
| `CRC32C-BEGIN` | `( -- )` | Start streaming CRC-32C |
| `CRC32C-ADD` | `( addr len -- )` | Feed data |
| `CRC32C-END` | `( -- crc )` | Finalize CRC-32C |
| `CRC64-BEGIN` | `( -- )` | Start streaming CRC-64 |
| `CRC64-ADD` | `( addr len -- )` | Feed data |
| `CRC64-END` | `( -- crc )` | Finalize CRC-64 |
| `CRC32-UPDATE` | `( crc data len -- crc' )` | Incremental CRC-32 |
| `CRC32C-UPDATE` | `( crc data len -- crc' )` | Incremental CRC-32C |
| `CRC64-UPDATE` | `( crc data len -- crc' )` | Incremental CRC-64 |
| `CRC32-.` | `( crc -- )` | Print CRC-32 as hex |
| `CRC64-.` | `( crc -- )` | Print CRC-64 as hex |
| `CRC32->HEX` | `( crc dst -- n )` | CRC-32 to hex string |
| `CRC64->HEX` | `( crc dst -- n )` | CRC-64 to hex string |
