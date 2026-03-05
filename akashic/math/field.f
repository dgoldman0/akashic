\ =================================================================
\  field.f  —  Field Arithmetic (hardware 512-bit Field ALU)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: FIELD-
\  Depends on: (none — uses KDOS Field ALU words at MMIO 0x0840)
\
\  Public API — prime selection:
\   FIELD-USE-25519   ( -- )     select Curve25519 prime 2^255-19
\   FIELD-USE-SECP    ( -- )     select secp256k1 prime
\   FIELD-USE-P256    ( -- )     select NIST P-256 prime
\   FIELD-USE-CUSTOM  ( -- )     select user-loaded custom prime
\   FIELD-LOAD-PRIME  ( p pinv -- )  load custom prime + Montgomery p_inv
\
\  Public API — buffer management:
\   FIELD-BUF         ( "name" -- )     create named 32-byte element
\   FIELD-ZERO        ( addr -- )       zero a field element
\   FIELD-ONE         ( addr -- )       set element to 1
\   FIELD-SET-U64     ( u64 addr -- )   store a 64-bit integer
\   FIELD-COPY        ( src dst -- )    copy 32 bytes
\
\  Public API — arithmetic:
\   FIELD-ADD   ( a b r -- )   r = (a + b) mod p
\   FIELD-SUB   ( a b r -- )   r = (a - b) mod p
\   FIELD-MUL   ( a b r -- )   r = (a * b) mod p
\   FIELD-SQR   ( a r -- )     r = a^2 mod p
\   FIELD-INV   ( a r -- )     r = a^(p-2) mod p
\   FIELD-POW   ( a e r -- )   r = a^e mod p  (e is 256-bit addr)
\   FIELD-NEG   ( a r -- )     r = p - a mod p  (additive inverse)
\   FIELD-MAC   ( a b r -- )   r += (a * b) mod p  (accumulate)
\
\  Public API — raw multiply (no reduction):
\   FIELD-MUL-RAW     ( a b rlo rhi -- )  512-bit product
\   FIELD-MAC-RAW     ( a b rlo rhi -- )  512-bit accumulate
\
\  Public API — comparison:
\   FIELD-EQ?    ( a b -- flag )   constant-time equality
\   FIELD-ZERO?  ( a -- flag )     test if element is zero
\
\  Public API — display:
\   FIELD.       ( addr -- )       print 256-bit element as hex
\
\  Constants:
\   FIELD-BYTES  ( -- 32 )
\
\  Buffers (internal, available for convenience):
\   _FLD-ZERO   ( -- addr )   32-byte zero element
\   _FLD-ONE    ( -- addr )   32-byte element = 1
\   _FLD-TMP    ( -- addr )   scratch buffer for NEG, ZERO?, etc.
\   _FLD-CMP    ( -- addr )   scratch buffer for FCEQ result
\
\  KDOS primitives used:
\   PRIME-25519 PRIME-SECP PRIME-P256 PRIME-CUSTOM LOAD-PRIME
\   FIELD-A! FIELD-B! FIELD-WAIT FIELD-RESULT@ FIELD-CMD!
\   FADD FSUB FMUL FSQR FINV FPOW FMUL-RAW FCMOV FCEQ
\   FMAC FMUL-ADD-RAW
\
\  Not reentrant.  One field computation at a time.
\ =================================================================

PROVIDED akashic-field

\ =====================================================================
\  Constants
\ =====================================================================

32 CONSTANT FIELD-BYTES

\ =====================================================================
\  Internal: hex lookup table
\ =====================================================================

CREATE _FLD-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

: _FLD-NIB>C  ( n -- c )
    0x0F AND _FLD-HEX + C@ ;

\ =====================================================================
\  Internal: static buffers
\ =====================================================================

\ _FLD-ZERO — 32-byte zero element
CREATE _FLD-ZERO  32 ALLOT
_FLD-ZERO 32 0 FILL

\ _FLD-ONE — 32-byte element with value 1 (little-endian)
CREATE _FLD-ONE  32 ALLOT
_FLD-ONE 32 0 FILL
1 _FLD-ONE C!

\ _FLD-TMP — scratch for NEG, ZERO?, etc.
CREATE _FLD-TMP  32 ALLOT

\ _FLD-CMP — scratch for FCEQ result
CREATE _FLD-CMP  32 ALLOT

\ =====================================================================
\  Prime selection
\ =====================================================================

\ FIELD-USE-25519 ( -- )  Select Curve25519 prime 2^255 - 19.
: FIELD-USE-25519  ( -- )
    PRIME-25519 ;

\ FIELD-USE-SECP ( -- )  Select secp256k1 prime.
: FIELD-USE-SECP  ( -- )
    PRIME-SECP ;

\ FIELD-USE-P256 ( -- )  Select NIST P-256 prime.
: FIELD-USE-P256  ( -- )
    PRIME-P256 ;

\ FIELD-USE-CUSTOM ( -- )  Select user-loaded custom prime.
: FIELD-USE-CUSTOM  ( -- )
    PRIME-CUSTOM ;

\ FIELD-LOAD-PRIME ( p-addr pinv-addr -- )
\   Load a custom prime and its Montgomery p_inv, then select it.
\   p and pinv are 32-byte buffers.
: FIELD-LOAD-PRIME  ( p pinv -- )
    LOAD-PRIME
    PRIME-CUSTOM ;

\ =====================================================================
\  Buffer management
\ =====================================================================

\ FIELD-BUF ( "name" -- )  Create a named 32-byte field element buffer.
: FIELD-BUF  ( "name" -- )
    CREATE FIELD-BYTES ALLOT ;

\ FIELD-ZERO ( addr -- )  Zero a 32-byte field element.
: FIELD-ZERO  ( addr -- )
    FIELD-BYTES 0 FILL ;

\ FIELD-ONE ( addr -- )  Set field element to 1 (little-endian).
: FIELD-ONE  ( addr -- )
    DUP FIELD-BYTES 0 FILL
    1 SWAP C! ;

\ FIELD-SET-U64 ( u64 addr -- )  Store a 64-bit integer as field element.
\   Clears all 32 bytes, then writes u64 in little-endian at offset 0.
: FIELD-SET-U64  ( u64 addr -- )
    DUP FIELD-BYTES 0 FILL
    ! ;

\ FIELD-COPY ( src dst -- )  Copy 32-byte field element.
: FIELD-COPY  ( src dst -- )
    FIELD-BYTES CMOVE ;

\ =====================================================================
\  Core arithmetic
\ =====================================================================

\ FIELD-ADD ( a b r -- )  r = (a + b) mod p.
: FIELD-ADD  ( a b r -- )
    FADD ;

\ FIELD-SUB ( a b r -- )  r = (a - b) mod p.
: FIELD-SUB  ( a b r -- )
    FSUB ;

\ FIELD-MUL ( a b r -- )  r = (a * b) mod p.
: FIELD-MUL  ( a b r -- )
    FMUL ;

\ FIELD-SQR ( a r -- )  r = a^2 mod p.
: FIELD-SQR  ( a r -- )
    FSQR ;

\ FIELD-INV ( a r -- )  r = a^(p-2) mod p  (Fermat inversion).
: FIELD-INV  ( a r -- )
    FINV ;

\ FIELD-POW ( a exp r -- )  r = a^exp mod p.
\   exp is a 32-byte buffer address containing the exponent.
: FIELD-POW  ( a exp r -- )
    FPOW ;

\ FIELD-NEG ( a r -- )  r = (0 - a) mod p = additive inverse.
: FIELD-NEG  ( a r -- )
    >R _FLD-ZERO SWAP R> FSUB ;

\ FIELD-MAC ( a b r -- )  r += (a * b) mod p  (multiply-accumulate).
: FIELD-MAC  ( a b r -- )
    FMAC ;

\ =====================================================================
\  Raw multiply (no modular reduction)
\ =====================================================================

\ FIELD-MUL-RAW ( a b rlo rhi -- )  512-bit raw product.
: FIELD-MUL-RAW  ( a b rlo rhi -- )
    FMUL-RAW ;

\ FIELD-MAC-RAW ( a b rlo rhi -- )  512-bit multiply-accumulate.
: FIELD-MAC-RAW  ( a b rlo rhi -- )
    FMUL-ADD-RAW ;

\ =====================================================================
\  Comparison
\ =====================================================================

\ FIELD-EQ? ( a b -- flag )  Constant-time equality test.
\   Returns TRUE if a == b, FALSE otherwise.
: FIELD-EQ?  ( a b -- flag )
    _FLD-CMP FCEQ
    _FLD-CMP C@ 1 = ;

\ FIELD-ZERO? ( a -- flag )  Test if field element is zero.
: FIELD-ZERO?  ( a -- flag )
    _FLD-ZERO FIELD-EQ? ;

\ =====================================================================
\  Display
\ =====================================================================

\ FIELD. ( addr -- )  Print 256-bit field element as 64 hex chars.
\   Prints big-endian (most significant byte first).
: FIELD.  ( addr -- )
    FIELD-BYTES 1 - BEGIN DUP 0>= WHILE
        OVER OVER + C@
        DUP 4 RSHIFT _FLD-NIB>C EMIT
        0x0F AND _FLD-NIB>C EMIT
        1 -
    REPEAT
    2DROP ;
