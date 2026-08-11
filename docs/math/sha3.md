# akashic-sha3 — SHA-3 and SHAKE

`akashic-sha3` is the result-only Akashic wrapper around MegaPad/KDOS's
checked SHA-3 service. It supports SHA3-256, SHA3-512, SHAKE-128, SHAKE-256,
and HMAC-SHA3-256 without exposing the accelerator's transaction registers.

```forth
REQUIRE sha3.f
```

The module publishes `PROVIDED akashic-sha3`. Guarded builds also load
`../concurrency/guard.f` and serialize the module's private scratch and
stream-family state.

## Checked failure contract

The public hashing words retain their established result-only stack effects.
The checked BIOS/KDOS status is consumed internally; every nonzero status is
thrown unchanged:

| Status | Meaning |
|---:|---|
| `1` | unsupported capability |
| `2` | state or owner conflict |
| `3` | invalid or non-addressable range |
| `4` | protected span |
| `5` | timeout |
| `6` | hardware or protocol failure |

Callers that need to recover use `CATCH`. A timeout or protocol failure can
retain the lower BIOS guard fail-closed when hardware could not be proven
quiescent. The exact owner must retry `SHA3-CLEAR` or reset before subsequent
hardware use.

The removed prototype words `SHA3-MODE!`, `SHA3-INIT`,
`SHA3-SQUEEZE-NEXT`, and `SHA3-DOUT@` are not compatibility APIs. Akashic
uses `SHA3-BEGIN`, `SHA3-UPDATE`, `SHA3-FINAL`, `SHAKE-FINAL`, bounded
`SHAKE-READ`, and `SHA3-CLEAR`.

## Constants

| Word | Value | Meaning |
|---|---:|---|
| `SHA3-256-LEN` | 32 | SHA3-256 digest bytes |
| `SHA3-256-HEX-LEN` | 64 | SHA3-256 lowercase hexadecimal characters |
| `SHA3-512-LEN` | 64 | SHA3-512 digest bytes |
| `SHA3-512-HEX-LEN` | 128 | SHA3-512 lowercase hexadecimal characters |

## One-shot hashing

```forth
SHA3-256-HASH  ( src len dst -- )
SHA3-512-HASH  ( src len dst -- )
SHAKE-128      ( src len dst dlen -- )
SHAKE-256      ( src len dst dlen -- )
SHA3-256-HMAC  ( key klen data dlen dst -- )
```

`SHA3-256-HASH` and `SHA3-512-HASH` publish exactly 32 and 64 digest bytes.
`SHA3-256-HMAC` uses the checked KDOS HMAC-SHA3-256 composite. Its block size
is 136 bytes, and keys longer than one block are normalized by hashing rather
than rejected or truncated.

```forth
CREATE msg 3 ALLOT  97 msg C!  98 msg 1+ C!  99 msg 2 + C!
CREATE out 32 ALLOT
msg 3 out SHA3-256-HASH
\ out contains SHA3-256("abc") = 3a985da7...
```

For SHAKE, Akashic qualifies the complete destination before finalization,
then calls `SHAKE-FINAL`, reads sequential chunks of at most 32 bytes, and
calls `SHA3-CLEAR`. A bad later address therefore cannot publish only a prefix
of a requested multi-window result. Zero output length is valid and still
finalizes and clears the accepted transaction.

Cleanup is attempted on every handled SHAKE terminal path. The first operation
failure is preserved when cleanup succeeds; a cleanup failure takes precedence
because the lower guard remains held fail-closed.

```forth
CREATE xof 64 ALLOT
msg 3 xof 64 SHAKE-128
\ xof contains the first 64 bytes of SHAKE-128("abc")
```

## Streaming

Streaming families allow a message to arrive in independently owned segments.
All `ADD` words accept a zero length and otherwise require a complete readable
source span.

### Fixed-output SHA-3

```forth
SHA3-256-BEGIN  ( -- )
SHA3-256-ADD    ( addr len -- )
SHA3-256-END    ( dst -- )

SHA3-512-BEGIN  ( -- )
SHA3-512-ADD    ( addr len -- )
SHA3-512-END    ( dst -- )
```

```forth
SHA3-256-BEGIN
part1 n1 SHA3-256-ADD
part2 n2 SHA3-256-ADD
my-hash SHA3-256-END
\ my-hash = SHA3-256(part1 || part2)
```

### Extendable-output SHAKE

```forth
SHAKE-128-BEGIN  ( -- )
SHAKE-128-ADD    ( addr len -- )
SHAKE-128-END    ( dst dlen -- )

SHAKE-256-BEGIN  ( -- )
SHAKE-256-ADD    ( addr len -- )
SHAKE-256-END    ( dst dlen -- )
```

`END` applies the same whole-destination preflight, bounded-read, and cleanup
rules as one-shot SHAKE. This interface is suitable for variable-length
messages without staging their concatenation in a private fixed-capacity
buffer.

```forth
SHAKE-256-BEGIN
domain domain-u SHAKE-256-ADD
payload payload-u SHAKE-256-ADD
xof 96 SHAKE-256-END
```

Streaming calls must stay within one family. A SHA3-256 stream cannot be
continued or ended with SHA3-512 or SHAKE words, and the two SHAKE families
are distinct.

## Hexadecimal conversion and display

```forth
SHA3-256->HEX  ( src dst -- 64 )
SHA3-512->HEX  ( src dst -- 128 )
SHA3-256-.     ( addr -- )
SHA3-512-.     ( addr -- )
```

Conversion writes lowercase hexadecimal without an added terminator. Display
emits the same lowercase representation.

## Comparison

```forth
SHA3-256-COMPARE       ( a b -- flag )
SHA3-512-COMPARE       ( a b -- flag )
SHA3-256-HASH-COMPARE  ( src len expected -- flag )
SHA3-256-END-COMPARE   ( expected -- flag )
```

The compare words accumulate byte differences across the complete digest and
return true (`-1`) only when all bytes match. `SHA3-256-END-COMPARE` is the
terminal operation for an active SHA3-256 stream.

## Caller-owned SHA3-256 contexts

The companion `sha3-context.f` API remains separate from the global streaming
transaction. Each 648-byte context owns its state and can be interleaved with
other contexts. Only each discrete permutation uses checked
`KECCAK-F1600`; the module does not retain global SHA3 ownership between
updates.

The context status vocabulary is `0` OK, `1` invalid, `2` state, `3`
capacity, `4` alias, and `5` hardware service failure. Any raw-permutation
failure wipes the complete context, making it structurally invalid, and no
digest is published. Callers must initialize that context again before reuse.

## Concurrency

When `GUARDED` is enabled, `sha3.f` creates `_sha3-guard`:

- One-shot hardware words acquire the guard, reject entry from an active
  Akashic stream, and release on success or throw.
- Each `BEGIN` acquires the guard and records its exact family.
- Each `ADD` requires the same owner and family.
- Each `END` requires the same owner and family, then clears the family and
  releases the guard on both success and throw.
- A missing, nested, or mismatched stream operation throws `-258` without
  silently converting the active family.
- Hex conversion uses the same guard for its module-scoped destination
  pointer. Pure compare and display words remain unguarded.

The Akashic guard coordinates module scratch and family semantics. The BIOS
crypto guard independently protects the shared Keccak service across SHA3,
raw permutation, and WOTS operations.

## Quick reference

| Word | Stack | Description |
|---|---|---|
| `SHA3-256-HASH` | `( src len dst -- )` | One-shot SHA3-256 |
| `SHA3-512-HASH` | `( src len dst -- )` | One-shot SHA3-512 |
| `SHAKE-128` | `( src len dst dlen -- )` | One-shot SHAKE-128 |
| `SHAKE-256` | `( src len dst dlen -- )` | One-shot SHAKE-256 |
| `SHA3-256-BEGIN` | `( -- )` | Start SHA3-256 streaming |
| `SHA3-256-ADD` | `( addr len -- )` | Add a SHA3-256 segment |
| `SHA3-256-END` | `( dst -- )` | Finish SHA3-256 |
| `SHA3-512-BEGIN` | `( -- )` | Start SHA3-512 streaming |
| `SHA3-512-ADD` | `( addr len -- )` | Add a SHA3-512 segment |
| `SHA3-512-END` | `( dst -- )` | Finish SHA3-512 |
| `SHAKE-128-BEGIN` | `( -- )` | Start SHAKE-128 streaming |
| `SHAKE-128-ADD` | `( addr len -- )` | Add a SHAKE-128 segment |
| `SHAKE-128-END` | `( dst dlen -- )` | Finish and read SHAKE-128 |
| `SHAKE-256-BEGIN` | `( -- )` | Start SHAKE-256 streaming |
| `SHAKE-256-ADD` | `( addr len -- )` | Add a SHAKE-256 segment |
| `SHAKE-256-END` | `( dst dlen -- )` | Finish and read SHAKE-256 |
| `SHA3-256-HMAC` | `( key klen data dlen dst -- )` | Checked HMAC-SHA3-256 |
| `SHA3-256-HASH-COMPARE` | `( src len expected -- flag )` | Hash and compare |
| `SHA3-256-END-COMPARE` | `( expected -- flag )` | Finish SHA3-256 and compare |
| `SHA3-256-COMPARE` | `( a b -- flag )` | Compare 32-byte digests |
| `SHA3-512-COMPARE` | `( a b -- flag )` | Compare 64-byte digests |
| `SHA3-256->HEX` | `( src dst -- 64 )` | Encode a SHA3-256 digest |
| `SHA3-512->HEX` | `( src dst -- 128 )` | Encode a SHA3-512 digest |
| `SHA3-256-.` | `( addr -- )` | Display a SHA3-256 digest |
| `SHA3-512-.` | `( addr -- )` | Display a SHA3-512 digest |
