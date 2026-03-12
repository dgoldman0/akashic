\ =================================================================
\  sha3.f  —  SHA-3 / SHAKE cryptographic hash (hardware-accelerated)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SHA3-
\  Depends on: (none — uses BIOS SHA-3 MMIO accelerator)
\
\  Public API — one-shot:
\   SHA3-256-HASH   ( src len dst -- )      SHA3-256, 32 bytes to dst
\   SHA3-512-HASH   ( src len dst -- )      SHA3-512, 64 bytes to dst
\   SHAKE-128       ( src len dst dlen -- ) SHAKE-128 XOF, dlen bytes
\   SHAKE-256       ( src len dst dlen -- ) SHAKE-256 XOF, dlen bytes
\
\  Public API — streaming:
\   SHA3-256-BEGIN  ( -- )            start streaming SHA3-256
\   SHA3-256-ADD    ( addr len -- )   feed data
\   SHA3-256-END    ( dst -- )        finalize, 32 bytes to dst
\   SHA3-512-BEGIN  ( -- )            start streaming SHA3-512
\   SHA3-512-ADD    ( addr len -- )   feed data
\   SHA3-512-END    ( dst -- )        finalize, 64 bytes to dst
\
\  Public API — HMAC:
\   SHA3-256-HMAC   ( key klen data dlen dst -- ) HMAC-SHA3-256
\
\  Display / conversion:
\   SHA3-256-.      ( addr -- )       print 32-byte hash as 64 hex chars
\   SHA3-512-.      ( addr -- )       print 64-byte hash as 128 hex chars
\   SHA3-256->HEX   ( src dst -- n )  32-byte hash → 64-char hex string
\   SHA3-512->HEX   ( src dst -- n )  64-byte hash → 128-char hex string
\
\  Comparison:
\   SHA3-256-COMPARE ( a b -- flag )  constant-time 32-byte compare
\   SHA3-512-COMPARE ( a b -- flag )  constant-time 64-byte compare
\
\  Constants:
\   SHA3-256-LEN    ( -- 32 )
\   SHA3-256-HEX-LEN ( -- 64 )
\   SHA3-512-LEN    ( -- 64 )
\   SHA3-512-HEX-LEN ( -- 128 )
\
\  BIOS primitives used:
\   SHA3-INIT  SHA3-UPDATE  SHA3-FINAL  SHA3-MODE!  SHA3-MODE@
\   SHA3-DOUT@  SHA3-SQUEEZE-NEXT
\
\  The BIOS provides the low-level MMIO words.  KDOS adds SHA3,
\  SHA3-512, SHAKE128, SHAKE256.  This module wraps them with a
\  clean Akashic-style API and adds hex, compare, and HMAC helpers.
\
\  Not reentrant.  One hash computation at a time.
\ =================================================================

PROVIDED akashic-sha3

\ =====================================================================
\  Constants
\ =====================================================================

32  CONSTANT SHA3-256-LEN
64  CONSTANT SHA3-256-HEX-LEN
64  CONSTANT SHA3-512-LEN
128 CONSTANT SHA3-512-HEX-LEN

\ =====================================================================
\  Internal: nibble-to-hex lookup
\ =====================================================================

CREATE _SHA3-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

: _SHA3-NIB>C  ( n -- c )
    0x0F AND _SHA3-HEX + C@ ;

\ =====================================================================
\  One-shot API
\ =====================================================================

\ SHA3-256-HASH ( src len dst -- )  SHA3-256 hash, 32 bytes to dst.
: SHA3-256-HASH  ( src len dst -- )
    >R
    SHA3-256-MODE SHA3-MODE!
    SHA3-INIT  SHA3-UPDATE
    R> SHA3-FINAL ;

\ SHA3-512-HASH ( src len dst -- )  SHA3-512 hash, 64 bytes to dst.
: SHA3-512-HASH  ( src len dst -- )
    >R
    SHA3-512-MODE SHA3-MODE!
    SHA3-INIT  SHA3-UPDATE
    R> SHA3-FINAL
    SHA3-256-MODE SHA3-MODE! ;

\ SHAKE-128 ( src len dst dlen -- )  SHAKE-128 XOF, dlen bytes to dst.
\   For dlen <= 32, uses the initial finalize output.
\   For dlen > 32, reads 32-byte blocks via DOUT + SQUEEZE-NEXT.
: SHAKE-128  ( src len dst dlen -- )
    >R >R
    SHAKE128-MODE SHA3-MODE!
    SHA3-INIT  SHA3-UPDATE
    R> R>                        ( dst dlen )
    OVER SHA3-FINAL              ( dst dlen )
    \ Now DOUT has first 32 bytes written to dst.
    \ If dlen > 32, we need to stream additional blocks.
    DUP 32 <= IF
        2DROP
    ELSE
        \ Stream remaining bytes in 32-byte chunks
        32 -  SWAP 32 +  SWAP   ( dst+32 remaining )
        BEGIN DUP 0> WHILE
            SHA3-SQUEEZE-NEXT
            OVER SHA3-DOUT@
            DUP 32 >= IF
                SWAP 32 + SWAP  32 -
            ELSE
                \ Last partial block — already written full 32 bytes
                \ by DOUT@, but we only needed 'remaining' bytes.
                \ Since DOUT@ always writes 32 bytes and we allocated
                \ enough space via dlen, this is fine.
                DROP 0
            THEN
        REPEAT
        2DROP
    THEN
    SHA3-256-MODE SHA3-MODE! ;

\ SHAKE-256 ( src len dst dlen -- )  SHAKE-256 XOF, dlen bytes to dst.
: SHAKE-256  ( src len dst dlen -- )
    >R >R
    SHAKE256-MODE SHA3-MODE!
    SHA3-INIT  SHA3-UPDATE
    R> R>                        ( dst dlen )
    OVER SHA3-FINAL              ( dst dlen )
    DUP 32 <= IF
        2DROP
    ELSE
        32 -  SWAP 32 +  SWAP
        BEGIN DUP 0> WHILE
            SHA3-SQUEEZE-NEXT
            OVER SHA3-DOUT@
            DUP 32 >= IF
                SWAP 32 + SWAP  32 -
            ELSE
                DROP 0
            THEN
        REPEAT
        2DROP
    THEN
    SHA3-256-MODE SHA3-MODE! ;

\ =====================================================================
\  Streaming API
\ =====================================================================

: SHA3-256-BEGIN  ( -- )
    SHA3-256-MODE SHA3-MODE!  SHA3-INIT ;

: SHA3-256-ADD  ( addr len -- )
    SHA3-UPDATE ;

: SHA3-256-END  ( dst -- )
    SHA3-FINAL ;

: SHA3-512-BEGIN  ( -- )
    SHA3-512-MODE SHA3-MODE!  SHA3-INIT ;

: SHA3-512-ADD  ( addr len -- )
    SHA3-UPDATE ;

: SHA3-512-END  ( dst -- )
    SHA3-FINAL
    SHA3-256-MODE SHA3-MODE! ;

\ =====================================================================
\  HMAC-SHA3-256
\ =====================================================================
\  HMAC(K, m) = SHA3-256( (K ^ opad) || SHA3-256( (K ^ ipad) || m ) )
\  Block size = SHA3-256 rate = 136 bytes.

136 CONSTANT _SHA3-HMAC-BLKSZ

CREATE _SHA3-IPAD 136 ALLOT
CREATE _SHA3-OPAD 136 ALLOT
CREATE _SHA3-INNER 32 ALLOT
VARIABLE _SHA3-PAD-PTR
VARIABLE _SHA3-XBYTE
VARIABLE _SHA3-HMAC-OUT

\ _SHA3-HMAC-PAD ( key-addr key-len pad-addr xor-byte -- )
: _SHA3-HMAC-PAD
    _SHA3-XBYTE !  _SHA3-PAD-PTR !
    _SHA3-PAD-PTR @ _SHA3-HMAC-BLKSZ 0 FILL
    0 DO
        DUP I + C@
        _SHA3-PAD-PTR @ I + C!
    LOOP DROP
    _SHA3-HMAC-BLKSZ 0 DO
        _SHA3-PAD-PTR @ I + C@
        _SHA3-XBYTE @ XOR
        _SHA3-PAD-PTR @ I + C!
    LOOP ;

\ SHA3-256-HMAC ( key klen data dlen dst -- )
: SHA3-256-HMAC  ( key klen data dlen dst -- )
    _SHA3-HMAC-OUT !
    >R >R                               ( key klen  R: dlen data )
    2DUP _SHA3-IPAD 0x36 _SHA3-HMAC-PAD
    _SHA3-OPAD 0x5C _SHA3-HMAC-PAD
    SHA3-256-MODE SHA3-MODE!
    SHA3-INIT
    _SHA3-IPAD _SHA3-HMAC-BLKSZ SHA3-UPDATE
    R> R> SHA3-UPDATE                    ( )
    _SHA3-INNER SHA3-FINAL
    SHA3-INIT
    _SHA3-OPAD _SHA3-HMAC-BLKSZ SHA3-UPDATE
    _SHA3-INNER 32 SHA3-UPDATE
    _SHA3-HMAC-OUT @ SHA3-FINAL ;

\ =====================================================================
\  Hex conversion
\ =====================================================================

VARIABLE _SHA3-HDST

\ SHA3-256->HEX ( src dst -- n )
\   Convert 32-byte hash to 64 lowercase hex chars.  Returns 64.
: SHA3-256->HEX  ( src dst -- n )
    _SHA3-HDST !
    32 0 DO
        DUP I + C@
        DUP 4 RSHIFT _SHA3-NIB>C
        _SHA3-HDST @ I 2* + C!
        0x0F AND _SHA3-NIB>C
        _SHA3-HDST @ I 2* 1+ + C!
    LOOP
    DROP SHA3-256-HEX-LEN ;

\ SHA3-512->HEX ( src dst -- n )
\   Convert 64-byte hash to 128 lowercase hex chars.  Returns 128.
: SHA3-512->HEX  ( src dst -- n )
    _SHA3-HDST !
    64 0 DO
        DUP I + C@
        DUP 4 RSHIFT _SHA3-NIB>C
        _SHA3-HDST @ I 2* + C!
        0x0F AND _SHA3-NIB>C
        _SHA3-HDST @ I 2* 1+ + C!
    LOOP
    DROP SHA3-512-HEX-LEN ;

\ =====================================================================
\  Display
\ =====================================================================

\ SHA3-256-. ( addr -- )  Print 32-byte hash as 64 lowercase hex chars.
: SHA3-256-.  ( addr -- )
    32 0 DO
        DUP I + C@
        DUP 4 RSHIFT _SHA3-NIB>C EMIT
        0x0F AND _SHA3-NIB>C EMIT
    LOOP
    DROP ;

\ SHA3-512-. ( addr -- )  Print 64-byte hash as 128 lowercase hex chars.
: SHA3-512-.  ( addr -- )
    64 0 DO
        DUP I + C@
        DUP 4 RSHIFT _SHA3-NIB>C EMIT
        0x0F AND _SHA3-NIB>C EMIT
    LOOP
    DROP ;

\ =====================================================================
\  Comparison
\ =====================================================================

\ SHA3-256-COMPARE ( a b -- flag )
\   Constant-time comparison of two 32-byte hashes.
\   Returns TRUE (-1) if equal, FALSE (0) otherwise.
: SHA3-256-COMPARE  ( a b -- flag )
    0
    32 0 DO
        >R
        OVER I + C@
        OVER I + C@
        XOR R> OR
    LOOP
    >R 2DROP R>
    0= IF TRUE ELSE FALSE THEN ;

\ SHA3-512-COMPARE ( a b -- flag )
\   Constant-time comparison of two 64-byte hashes.
: SHA3-512-COMPARE  ( a b -- flag )
    0
    64 0 DO
        >R
        OVER I + C@
        OVER I + C@
        XOR R> OR
    LOOP
    >R 2DROP R>
    0= IF TRUE ELSE FALSE THEN ;

\ ── Concurrency Guard ─────────────────────────────────────
\ Spinning GUARD serialises all access to the shared Keccak
\ state and hex-conversion buffer (_SHA3-HDST).
\ One-shot words: WITH-GUARD (acquire-CATCH-release).
\ Streaming: BEGIN acquires, END releases, ADD asserts ownership.
\ Pure read / compare / print words are left unguarded.
\ Error -258 = operation called without holding the guard.

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _sha3-guard

\ Save original XTs before shadowing
' SHA3-256-HASH   CONSTANT _s3-256-hash-xt
' SHA3-512-HASH   CONSTANT _s3-512-hash-xt
' SHAKE-128       CONSTANT _shake128-xt
' SHAKE-256       CONSTANT _shake256-xt
' SHA3-256-HMAC   CONSTANT _s3-256-hmac-xt
' SHA3-256->HEX   CONSTANT _s3-256-hex-xt
' SHA3-512->HEX   CONSTANT _s3-512-hex-xt
' SHA3-256-BEGIN   CONSTANT _s3-256-begin-xt
' SHA3-512-BEGIN   CONSTANT _s3-512-begin-xt
' SHA3-256-ADD     CONSTANT _s3-256-add-xt
' SHA3-512-ADD     CONSTANT _s3-512-add-xt
' SHA3-256-END     CONSTANT _s3-256-end-xt
' SHA3-512-END     CONSTANT _s3-512-end-xt

\ ── one-shot entry points ──
: SHA3-256-HASH   _s3-256-hash-xt   _sha3-guard WITH-GUARD ;
: SHA3-512-HASH   _s3-512-hash-xt   _sha3-guard WITH-GUARD ;
: SHAKE-128       _shake128-xt      _sha3-guard WITH-GUARD ;
: SHAKE-256       _shake256-xt      _sha3-guard WITH-GUARD ;
: SHA3-256-HMAC   _s3-256-hmac-xt   _sha3-guard WITH-GUARD ;
: SHA3-256->HEX   _s3-256-hex-xt    _sha3-guard WITH-GUARD ;
: SHA3-512->HEX   _s3-512-hex-xt    _sha3-guard WITH-GUARD ;

\ ── streaming BEGIN (acquire guard) ──
: SHA3-256-BEGIN  ( -- )
    _sha3-guard GUARD-ACQUIRE
    _s3-256-begin-xt CATCH
    ?DUP IF _sha3-guard GUARD-RELEASE THROW THEN ;

: SHA3-512-BEGIN  ( -- )
    _sha3-guard GUARD-ACQUIRE
    _s3-512-begin-xt CATCH
    ?DUP IF _sha3-guard GUARD-RELEASE THROW THEN ;

\ ── streaming ADD (assert ownership) ──
: SHA3-256-ADD  ( addr len -- )
    _sha3-guard GUARD-MINE? 0= IF -258 THROW THEN
    _s3-256-add-xt EXECUTE ;

: SHA3-512-ADD  ( addr len -- )
    _sha3-guard GUARD-MINE? 0= IF -258 THROW THEN
    _s3-512-add-xt EXECUTE ;

\ ── streaming END (release guard, always) ──
: SHA3-256-END  ( dst -- )
    _sha3-guard GUARD-MINE? 0= IF -258 THROW THEN
    _s3-256-end-xt CATCH
    _sha3-guard GUARD-RELEASE
    ?DUP IF THROW THEN ;

: SHA3-512-END  ( dst -- )
    _sha3-guard GUARD-MINE? 0= IF -258 THROW THEN
    _s3-512-end-xt CATCH
    _sha3-guard GUARD-RELEASE
    ?DUP IF THROW THEN ;

[THEN] [THEN]
