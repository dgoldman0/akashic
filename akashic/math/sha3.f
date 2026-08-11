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
\   SHAKE-128-BEGIN ( -- )            start streaming SHAKE-128
\   SHAKE-128-ADD   ( addr len -- )   feed data
\   SHAKE-128-END   ( dst dlen -- )   finalize and read dlen bytes
\   SHAKE-256-BEGIN ( -- )            start streaming SHAKE-256
\   SHAKE-256-ADD   ( addr len -- )   feed data
\   SHAKE-256-END   ( dst dlen -- )   finalize and read dlen bytes
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
\   SHA3-256-HASH-COMPARE ( src len expected -- flag )
\   SHA3-256-END-COMPARE ( expected -- flag )
\
\  Constants:
\   SHA3-256-LEN    ( -- 32 )
\   SHA3-256-HEX-LEN ( -- 64 )
\   SHA3-512-LEN    ( -- 64 )
\   SHA3-512-HEX-LEN ( -- 128 )
\
\  Checked BIOS primitives used:
\   SHA3-BEGIN  SHA3-UPDATE  SHA3-FINAL  SHAKE-FINAL
\   SHAKE-READ  SHA3-CLEAR
\  Checked KDOS composites used:
\   SHA3  SHA3-512  HMAC
\
\  Every nonzero checked status is thrown unchanged so the established
\  result-only Akashic API remains intact.  SHAKE output is read in bounded
\  chunks and every accepted SHAKE transaction ends in SHA3-CLEAR.
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

: _SHA3-CHECK-STATUS  ( status -- )
    ?DUP IF THROW THEN ;

\ Preserve the first operation failure when cleanup succeeds.  A cleanup
\ failure takes precedence because the BIOS guard then remains fail-closed.
: _SHA3-CLEAR-ERROR  ( status -- status )
    >R
    SHA3-CLEAR
    DUP IF R> DROP EXIT THEN
    DROP R> ;

\ CALLER-SPAN-STATUS uses its protocol-neutral 0/2/3 namespace.  Translate
\ it to the checked-crypto 0/3/4 namespace used by this module's throws.
: _SHA3-OUTPUT-STATUS  ( address length -- status )
    CALLER-SPAN-STATUS
    DUP 2 = IF DROP CRYPTO-RANGE EXIT THEN
    DUP 3 = IF DROP CRYPTO-PROTECTED THEN ;

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
    SHA3 _SHA3-CHECK-STATUS ;

\ SHA3-512-HASH ( src len dst -- )  SHA3-512 hash, 64 bytes to dst.
: SHA3-512-HASH  ( src len dst -- )
    SHA3-512 _SHA3-CHECK-STATUS ;

\ Finish an accepted SHAKE transaction.  The complete destination is
\ qualified before finalization so a later page/range failure cannot publish
\ a prefix.  BIOS reads are deliberately capped at 32 bytes.
: _SHA3-SHAKE-END-STATUS  ( dst dlen -- status )
    2DUP _SHA3-OUTPUT-STATUS
    DUP IF >R 2DROP R> _SHA3-CLEAR-ERROR EXIT THEN DROP
    SHAKE-FINAL
    DUP IF >R 2DROP R> _SHA3-CLEAR-ERROR EXIT THEN DROP
    BEGIN DUP 0> WHILE
        OVER OVER 32 MIN SHAKE-READ
        DUP IF >R 2DROP R> _SHA3-CLEAR-ERROR EXIT THEN DROP
        DUP 32 MIN >R
        R@ -
        SWAP R> + SWAP
    REPEAT
    2DROP
    SHA3-CLEAR ;

\ Absorb one SHAKE segment.  A checked UPDATE failure normally performs BIOS
\ cleanup itself; the explicit CLEAR also covers every handled error path and
\ is idempotent after successful cleanup.
: _SHA3-SHAKE-UPDATE-STATUS  ( src len -- status )
    SHA3-UPDATE
    DUP IF _SHA3-CLEAR-ERROR THEN ;

: _SHA3-SHAKE-STATUS  ( src len dst dlen mode -- status )
    DUP SHA3-BEGIN
    DUP IF >R 2DROP 2DROP DROP R> EXIT THEN DROP DROP
    2DUP _SHA3-OUTPUT-STATUS
    DUP IF >R 2DROP 2DROP R> _SHA3-CLEAR-ERROR EXIT THEN DROP
    2SWAP SHA3-UPDATE
    DUP IF >R 2DROP R> _SHA3-CLEAR-ERROR EXIT THEN DROP
    _SHA3-SHAKE-END-STATUS ;

\ SHAKE-128 ( src len dst dlen -- )  SHAKE-128 XOF, dlen bytes to dst.
: SHAKE-128  ( src len dst dlen -- )
    SHAKE128-MODE _SHA3-SHAKE-STATUS _SHA3-CHECK-STATUS ;

\ SHAKE-256 ( src len dst dlen -- )  SHAKE-256 XOF, dlen bytes to dst.
: SHAKE-256  ( src len dst dlen -- )
    SHAKE256-MODE _SHA3-SHAKE-STATUS _SHA3-CHECK-STATUS ;

\ =====================================================================
\  Streaming API
\ =====================================================================

: SHA3-256-BEGIN  ( -- )
    SHA3-256-MODE SHA3-BEGIN _SHA3-CHECK-STATUS ;

: SHA3-256-ADD  ( addr len -- )
    SHA3-UPDATE _SHA3-CHECK-STATUS ;

: SHA3-256-END  ( dst -- )
    SHA3-FINAL _SHA3-CHECK-STATUS ;

: SHA3-512-BEGIN  ( -- )
    SHA3-512-MODE SHA3-BEGIN _SHA3-CHECK-STATUS ;

: SHA3-512-ADD  ( addr len -- )
    SHA3-UPDATE _SHA3-CHECK-STATUS ;

: SHA3-512-END  ( dst -- )
    SHA3-FINAL _SHA3-CHECK-STATUS ;

: SHAKE-128-BEGIN  ( -- )
    SHAKE128-MODE SHA3-BEGIN _SHA3-CHECK-STATUS ;

: SHAKE-128-ADD  ( addr len -- )
    _SHA3-SHAKE-UPDATE-STATUS _SHA3-CHECK-STATUS ;

: SHAKE-128-END  ( dst dlen -- )
    _SHA3-SHAKE-END-STATUS _SHA3-CHECK-STATUS ;

: SHAKE-256-BEGIN  ( -- )
    SHAKE256-MODE SHA3-BEGIN _SHA3-CHECK-STATUS ;

: SHAKE-256-ADD  ( addr len -- )
    _SHA3-SHAKE-UPDATE-STATUS _SHA3-CHECK-STATUS ;

: SHAKE-256-END  ( dst dlen -- )
    _SHA3-SHAKE-END-STATUS _SHA3-CHECK-STATUS ;

\ SHA3-256-HMAC ( key klen data dlen dst -- )
: SHA3-256-HMAC  ( key klen data dlen dst -- )
    HMAC _SHA3-CHECK-STATUS ;

\ =====================================================================
\  Hex conversion
\ =====================================================================

\ Stable bounds for callers that reject aliasing with dependency scratch.
\ Guarded builds extend this private span through the guard defined below.
CREATE _SHA3-PRIVATE-BEGIN 0 ALLOT
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
        2 PICK I + C@
        2 PICK I + C@
        XOR OR
    LOOP
    NIP NIP 0= ;

\ SHA3-512-COMPARE ( a b -- flag )
\   Constant-time comparison of two 64-byte hashes.
: SHA3-512-COMPARE  ( a b -- flag )
    0
    64 0 DO
        2 PICK I + C@
        2 PICK I + C@
        XOR OR
    LOOP
    NIP NIP 0= ;

\ Neutral scratch for compare-only hashing.  Guarded builds serialize this
\ buffer with the accelerator, so domains do not need private digest globals.
CREATE _SHA3-COMPARE-DIGEST SHA3-256-LEN ALLOT
CREATE _SHA3-PRIVATE-END 0 ALLOT

: SHA3-256-HASH-COMPARE  ( src len expected -- flag )
    2 PICK 2 PICK _SHA3-COMPARE-DIGEST SHA3-256-HASH
    NIP NIP
    _SHA3-COMPARE-DIGEST SHA3-256-COMPARE ;

: SHA3-256-END-COMPARE  ( expected -- flag )
    _SHA3-COMPARE-DIGEST SHA3-256-END
    _SHA3-COMPARE-DIGEST SHA3-256-COMPARE ;

\ ── Concurrency Guard ─────────────────────────────────────
\ Spinning GUARD serialises module scratch and enforces coherent Akashic
\ stream families above the checked BIOS transaction owner.
\ One-shot hardware words reject entry during an active Akashic stream.
\ Streaming: BEGIN acquires, END releases, ADD asserts owner and family.
\ Pure read / compare / print words are left unguarded.
\ Error -258 = missing, nested, or mismatched stream ownership.

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f

0 CONSTANT _SHA3-STREAM-NONE
1 CONSTANT _SHA3-STREAM-256
2 CONSTANT _SHA3-STREAM-512
3 CONSTANT _SHA3-STREAM-SHAKE128
4 CONSTANT _SHA3-STREAM-SHAKE256
VARIABLE _SHA3-STREAM-MODE
VARIABLE _SHA3-BEGIN-MODE
_SHA3-STREAM-NONE _SHA3-STREAM-MODE !
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
' SHAKE-128-BEGIN  CONSTANT _shake128-begin-xt
' SHAKE-128-ADD    CONSTANT _shake128-add-xt
' SHAKE-128-END    CONSTANT _shake128-end-xt
' SHAKE-256-BEGIN  CONSTANT _shake256-begin-xt
' SHAKE-256-ADD    CONSTANT _shake256-add-xt
' SHAKE-256-END    CONSTANT _shake256-end-xt
' SHA3-256-HASH-COMPARE CONSTANT _s3-256-hash-compare-xt
' SHA3-256-END-COMPARE CONSTANT _s3-256-end-compare-xt

\ Checked BIOS continuations clean accepted transactions on ordinary failure.
\ Status 5 or 6 may instead retain BIOS ownership fail-closed; the exact
\ owner must retry SHA3-CLEAR (or reset) before later hardware use.
: _SHA3-WITH-HARDWARE-GUARD  ( ... xt -- ... )
    _sha3-guard GUARD-ACQUIRE
    _SHA3-STREAM-MODE @ _SHA3-STREAM-NONE <> IF
        _sha3-guard GUARD-RELEASE
        -258 THROW
    THEN
    CATCH
    _sha3-guard GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;

: _SHA3-STREAM-BEGIN  ( mode xt -- )
    _sha3-guard GUARD-ACQUIRE
    _SHA3-STREAM-MODE @ _SHA3-STREAM-NONE <> IF
        _sha3-guard GUARD-RELEASE
        2DROP -258 THROW
    THEN
    SWAP _SHA3-BEGIN-MODE !
    CATCH ?DUP IF
        _SHA3-STREAM-NONE _SHA3-STREAM-MODE !
        _sha3-guard GUARD-RELEASE
        THROW
    THEN
    _SHA3-BEGIN-MODE @ _SHA3-STREAM-MODE ! ;

: _SHA3-STREAM-ADD  ( addr len mode xt -- )
    _sha3-guard GUARD-MINE? 0= IF -258 THROW THEN
    OVER _SHA3-STREAM-MODE @ <> IF 2DROP 2DROP -258 THROW THEN
    SWAP DROP
    CATCH ?DUP IF
        _SHA3-STREAM-NONE _SHA3-STREAM-MODE !
        _sha3-guard GUARD-RELEASE
        THROW
    THEN ;

: _SHA3-STREAM-END  ( ... mode xt -- ... )
    _sha3-guard GUARD-MINE? 0= IF -258 THROW THEN
    OVER _SHA3-STREAM-MODE @ <> IF -258 THROW THEN
    SWAP DROP
    CATCH
    _SHA3-STREAM-NONE _SHA3-STREAM-MODE !
    _sha3-guard GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;

\ ── one-shot entry points ──
: SHA3-256-HASH   _s3-256-hash-xt   _SHA3-WITH-HARDWARE-GUARD ;
: SHA3-512-HASH   _s3-512-hash-xt   _SHA3-WITH-HARDWARE-GUARD ;
: SHAKE-128       _shake128-xt      _SHA3-WITH-HARDWARE-GUARD ;
: SHAKE-256       _shake256-xt      _SHA3-WITH-HARDWARE-GUARD ;
: SHA3-256-HMAC   _s3-256-hmac-xt   _SHA3-WITH-HARDWARE-GUARD ;
: SHA3-256->HEX   _s3-256-hex-xt    _sha3-guard WITH-GUARD ;
: SHA3-512->HEX   _s3-512-hex-xt    _sha3-guard WITH-GUARD ;
: SHA3-256-HASH-COMPARE
    _s3-256-hash-compare-xt _SHA3-WITH-HARDWARE-GUARD ;

\ ── streaming entry points ──
: SHA3-256-BEGIN
    _SHA3-STREAM-256 _s3-256-begin-xt _SHA3-STREAM-BEGIN ;
: SHA3-512-BEGIN
    _SHA3-STREAM-512 _s3-512-begin-xt _SHA3-STREAM-BEGIN ;
: SHAKE-128-BEGIN
    _SHA3-STREAM-SHAKE128 _shake128-begin-xt _SHA3-STREAM-BEGIN ;
: SHAKE-256-BEGIN
    _SHA3-STREAM-SHAKE256 _shake256-begin-xt _SHA3-STREAM-BEGIN ;

: SHA3-256-ADD
    _SHA3-STREAM-256 _s3-256-add-xt _SHA3-STREAM-ADD ;
: SHA3-512-ADD
    _SHA3-STREAM-512 _s3-512-add-xt _SHA3-STREAM-ADD ;
: SHAKE-128-ADD
    _SHA3-STREAM-SHAKE128 _shake128-add-xt _SHA3-STREAM-ADD ;
: SHAKE-256-ADD
    _SHA3-STREAM-SHAKE256 _shake256-add-xt _SHA3-STREAM-ADD ;

: SHA3-256-END
    _SHA3-STREAM-256 _s3-256-end-xt _SHA3-STREAM-END ;
: SHA3-512-END
    _SHA3-STREAM-512 _s3-512-end-xt _SHA3-STREAM-END ;
: SHAKE-128-END
    _SHA3-STREAM-SHAKE128 _shake128-end-xt _SHA3-STREAM-END ;
: SHAKE-256-END
    _SHA3-STREAM-SHAKE256 _shake256-end-xt _SHA3-STREAM-END ;

: SHA3-256-END-COMPARE  ( expected -- flag )
    _SHA3-STREAM-256 _s3-256-end-compare-xt _SHA3-STREAM-END ;

[THEN] [THEN]
