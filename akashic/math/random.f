\ =================================================================
\  random.f  —  True Random / CSPRNG  (hardware TRNG)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: RNG-
\  Depends on: fp16.f (for RNG-FP16), BIOS TRNG at MMIO 0x0800
\
\  Public API:
\   RNG-U64      ( -- u64 )         64-bit hardware random
\   RNG-U32      ( -- u32 )         32-bit hardware random
\   RNG-BYTE     ( -- b )           single random byte
\   RNG-BYTES    ( dst n -- )       fill buffer with random bytes
\   RNG-RANGE    ( lo hi -- n )     uniform random in [lo, hi)
\   RNG-BOOL     ( -- flag )        random TRUE or FALSE
\   RNG-SEED     ( u -- )           mix 64-bit entropy into pool
\   RNG-FP16     ( -- fp16 )        random FP16 in [0.0, 1.0)
\
\  Display:
\   RNG-BYTES-.  ( addr n -- )      print n random bytes as hex
\
\  Constants:
\   RNG-AVAILABLE ( -- flag )       TRUE (hardware TRNG present)
\
\  The BIOS provides RANDOM (64-bit), RANDOM8 (8-bit), SEED-RNG.
\  KDOS adds RANDOM32, RANDOM16, RAND-RANGE.
\  This module wraps them with a clean Akashic-style API and adds
\  buffer-fill, bounded-range, FP16, and display helpers.
\
\  All randomness comes from the hardware TRNG backed by OS entropy
\  (std::random_device / /dev/urandom).  Suitable for cryptographic
\  key generation.
\
\  Not reentrant.  Thread-safe only if callers serialize access.
\ =================================================================

PROVIDED akashic-random
REQUIRE fp16.f

\ =====================================================================
\  Constants
\ =====================================================================

TRUE CONSTANT RNG-AVAILABLE

\ =====================================================================
\  Core random primitives
\ =====================================================================

\ RNG-U64 ( -- u64 )  Hardware TRNG: 64 random bits.
: RNG-U64  ( -- u64 )
    RANDOM ;

\ RNG-U32 ( -- u32 )  32-bit random.
: RNG-U32  ( -- u32 )
    RANDOM32 ;

\ RNG-BYTE ( -- b )  Single random byte.
: RNG-BYTE  ( -- b )
    RANDOM8 ;

\ =====================================================================
\  Buffer fill
\ =====================================================================

\ RNG-BYTES ( dst n -- )  Fill buffer with n random bytes.
: RNG-BYTES  ( dst n -- )
    0 DO
        RANDOM8 OVER I + C!
    LOOP
    DROP ;

\ =====================================================================
\  Bounded range
\ =====================================================================

\ RNG-RANGE ( lo hi -- n )  Uniform random integer in [lo, hi).
\   Uses rejection sampling to avoid modulo bias.
\   hi must be > lo.  Range = hi - lo must be > 0.
: RNG-RANGE  ( lo hi -- n )
    OVER -                             ( lo range )
    DUP 1 = IF
        DROP EXIT                      \ [lo, lo+1) → lo
    THEN
    \ Rejection sampling: find mask ≥ range
    DUP                                ( lo range range )
    1 -                                ( lo range range-1 )
    \ Build bitmask: fill all bits at or below highest set bit
    DUP  1 RSHIFT OR
    DUP  2 RSHIFT OR
    DUP  4 RSHIFT OR
    DUP  8 RSHIFT OR
    DUP 16 RSHIFT OR
    DUP 32 RSHIFT OR                  ( lo range mask )
    \ Loop: generate masked random, reject if ≥ range
    BEGIN
        RANDOM OVER AND                ( lo range mask candidate )
        DUP 3 PICK < IF               ( lo range mask candidate )
            \ Accept: candidate < range
            >R DROP DROP R> +  EXIT
        THEN
        DROP                           ( lo range mask )
    AGAIN ;

\ RNG-BOOL ( -- flag )  Random TRUE or FALSE.
: RNG-BOOL  ( -- flag )
    RANDOM8 1 AND IF TRUE ELSE FALSE THEN ;

\ =====================================================================
\  Entropy seeding
\ =====================================================================

\ RNG-SEED ( u -- )  Mix 64-bit user entropy into hardware pool.
: RNG-SEED  ( u -- )
    SEED-RNG ;

\ =====================================================================
\  FP16 random
\ =====================================================================
\  Constructs an IEEE 754 half-precision float in [0.0, 1.0).
\  Method: build 1.mmmmmmmmmm (exponent=15, 10 random mantissa bits)
\  giving [1.0, 2.0), then subtract 1.0 → [0.0, 1.0).
\  Uses FP16-SUB from fp16.f.

: RNG-FP16  ( -- fp16 )
    RANDOM 0x3FF AND                   \ random 10-bit mantissa
    0x3C00 OR                          \ exponent=15, value in 1.0 to 2.0
    FP16-POS-ONE FP16-SUB ;            \ subtract 1.0 -> 0.0 to 1.0

\ =====================================================================
\  Display
\ =====================================================================

CREATE _RNG-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

: _RNG-NIB>C  ( n -- c )
    0x0F AND _RNG-HEX + C@ ;

\ RNG-BYTES-. ( addr n -- )  Print n bytes as hex.
: RNG-BYTES-.  ( addr n -- )
    0 DO
        DUP I + C@
        DUP 4 RSHIFT _RNG-NIB>C EMIT
        0x0F AND _RNG-NIB>C EMIT
    LOOP
    DROP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _rng-guard

' RNG-U64         CONSTANT _rng-u64-xt
' RNG-U32         CONSTANT _rng-u32-xt
' RNG-BYTE        CONSTANT _rng-byte-xt
' RNG-BYTES       CONSTANT _rng-bytes-xt
' RNG-RANGE       CONSTANT _rng-range-xt
' RNG-BOOL        CONSTANT _rng-bool-xt
' RNG-SEED        CONSTANT _rng-seed-xt
' RNG-FP16        CONSTANT _rng-fp16-xt
' RNG-BYTES-.     CONSTANT _rng-bytes-dot-xt

: RNG-U64         _rng-u64-xt _rng-guard WITH-GUARD ;
: RNG-U32         _rng-u32-xt _rng-guard WITH-GUARD ;
: RNG-BYTE        _rng-byte-xt _rng-guard WITH-GUARD ;
: RNG-BYTES       _rng-bytes-xt _rng-guard WITH-GUARD ;
: RNG-RANGE       _rng-range-xt _rng-guard WITH-GUARD ;
: RNG-BOOL        _rng-bool-xt _rng-guard WITH-GUARD ;
: RNG-SEED        _rng-seed-xt _rng-guard WITH-GUARD ;
: RNG-FP16        _rng-fp16-xt _rng-guard WITH-GUARD ;
: RNG-BYTES-.     _rng-bytes-dot-xt _rng-guard WITH-GUARD ;
[THEN] [THEN]
