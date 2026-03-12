\ =================================================================
\  sha256.f  —  SHA-256 cryptographic hash (hardware-accelerated)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SHA256-
\  Depends on: (none — uses BIOS SHA-256 MMIO accelerator)
\
\  Public API:
\   SHA256-HASH     ( src len dst -- )    one-shot hash, 32 bytes to dst
\   SHA256-BEGIN    ( -- )                start streaming hash
\   SHA256-ADD      ( addr len -- )       feed data to streaming hash
\   SHA256-END      ( dst -- )            finalize, 32 bytes to dst
\   SHA256-.        ( addr -- )           print 32-byte hash as 64 hex chars
\   SHA256->HEX     ( src dst -- n )      convert 32-byte hash to hex string
\   SHA256-COMPARE  ( a b -- flag )       compare two 32-byte hashes
\
\  Constants:
\   SHA256-LEN      ( -- 32 )            hash length in bytes
\   SHA256-HEX-LEN  ( -- 64 )            hex-encoded hash length
\
\  The BIOS provides SHA256-INIT, SHA256-UPDATE, SHA256-FINAL as
\  hardware-accelerated MMIO words.  This module wraps them with
\  a clean Akashic-style API and adds convenience helpers.
\ =================================================================

PROVIDED akashic-sha256

\ =====================================================================
\  Constants
\ =====================================================================

32 CONSTANT SHA256-LEN
64 CONSTANT SHA256-HEX-LEN

\ =====================================================================
\  Internal: nibble-to-hex lookup
\ =====================================================================

CREATE _SHA256-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

\ _SHA256-NIB>C ( nibble -- char )   0-15 → '0'-'9','a'-'f'
: _SHA256-NIB>C  ( n -- c )
    0x0F AND _SHA256-HEX + C@ ;

\ =====================================================================
\  Streaming API  —  wraps BIOS MMIO words
\ =====================================================================

\ SHA256-BEGIN ( -- )  Initialize hardware for a new hash.
: SHA256-BEGIN  ( -- )
    SHA256-INIT ;

\ SHA256-ADD ( addr len -- )  Feed bytes to the running hash.
: SHA256-ADD  ( addr len -- )
    SHA256-UPDATE ;

\ SHA256-END ( dst -- )  Finalize and write 32 bytes to dst.
: SHA256-END  ( dst -- )
    SHA256-FINAL ;

\ =====================================================================
\  One-shot API
\ =====================================================================

\ SHA256-HASH ( src len dst -- )  Hash src/len, store 32 bytes at dst.
: SHA256-HASH  ( src len dst -- )
    >R
    SHA256-INIT
    SHA256-UPDATE
    R> SHA256-FINAL ;

\ =====================================================================
\  Hex conversion
\ =====================================================================

VARIABLE _SHA256-DST

\ SHA256->HEX ( src dst -- n )
\   Convert 32-byte hash at src to 64-char lowercase hex at dst.
\   Returns 64 (the number of chars written).
: SHA256->HEX  ( src dst -- n )
    _SHA256-DST !               ( src )
    32 0 DO
        DUP I + C@              ( src byte )
        DUP 4 RSHIFT _SHA256-NIB>C
        _SHA256-DST @ I 2* + C!
        0x0F AND _SHA256-NIB>C
        _SHA256-DST @ I 2* 1+ + C!
    LOOP
    DROP SHA256-HEX-LEN ;

\ =====================================================================
\  Display
\ =====================================================================

\ SHA256-. ( addr -- )  Print 32-byte hash as 64 lowercase hex chars.
: SHA256-.  ( addr -- )
    32 0 DO
        DUP I + C@
        DUP 4 RSHIFT _SHA256-NIB>C EMIT
        0x0F AND _SHA256-NIB>C EMIT
    LOOP
    DROP ;

\ =====================================================================
\  Comparison
\ =====================================================================

\ SHA256-COMPARE ( a b -- flag )
\   Constant-time comparison of two 32-byte hashes.
\   Returns TRUE (-1) if equal, FALSE (0) if different.
: SHA256-COMPARE  ( a b -- flag )
    0                           ( a b acc )
    32 0 DO
        >R                      ( a b  R: acc )
        OVER I + C@
        OVER I + C@
        XOR R> OR               ( a b acc' )
    LOOP
    >R 2DROP R>
    0= IF TRUE ELSE FALSE THEN ;

\ ── Concurrency Guard ─────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _sha256-guard

\ Save original XTs before shadowing
' SHA256-HASH   CONSTANT _sha256-hash-xt
' SHA256->HEX   CONSTANT _sha256-hex-xt
' SHA256-BEGIN   CONSTANT _sha256-begin-xt
' SHA256-ADD     CONSTANT _sha256-add-xt
' SHA256-END     CONSTANT _sha256-end-xt

: SHA256-HASH     _sha256-hash-xt     _sha256-guard WITH-GUARD ;
: SHA256->HEX     _sha256-hex-xt      _sha256-guard WITH-GUARD ;

: SHA256-BEGIN  ( -- )
    _sha256-guard GUARD-ACQUIRE
    _sha256-begin-xt CATCH
    ?DUP IF _sha256-guard GUARD-RELEASE THROW THEN ;

: SHA256-ADD  ( addr len -- )
    _sha256-guard GUARD-MINE? 0= IF -258 THROW THEN
    _sha256-add-xt EXECUTE ;

: SHA256-END  ( dst -- )
    _sha256-guard GUARD-MINE? 0= IF -258 THROW THEN
    _sha256-end-xt CATCH
    _sha256-guard GUARD-RELEASE
    ?DUP IF THROW THEN ;

[THEN] [THEN]
