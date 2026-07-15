\ =================================================================
\  crc.f  —  CRC-32 / CRC-32C / CRC-64 (hardware-accelerated)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: CRC-
\  Depends on: (none — uses the MegaPad BIOS CRC accelerator)
\
\  Public API — one-shot:
\   CRC32       ( data len -- crc )    CRC-32/BZIP2 parameters
\   CRC32C      ( data len -- crc )    non-reflected Castagnoli
\   CRC64       ( data len -- crc )    CRC-64/WE parameters
\
\  Public API — streaming:
\   CRC32-BEGIN   ( -- )               start streaming CRC-32
\   CRC32-ADD     ( addr len -- )      feed data
\   CRC32-END     ( -- crc )           finalize, return CRC
\   CRC32C-BEGIN  ( -- )               start streaming CRC-32C
\   CRC32C-ADD    ( addr len -- )      feed data
\   CRC32C-END    ( -- crc )           finalize, return CRC
\   CRC64-BEGIN   ( -- )               start streaming CRC-64
\   CRC64-ADD     ( addr len -- )      feed data
\   CRC64-END     ( -- crc )           finalize, return CRC
\
\  Public API — incremental update:
\   CRC32-UPDATE  ( crc data len -- crc' )  streaming CRC-32
\   CRC32C-UPDATE ( crc data len -- crc' )  streaming CRC-32C
\   CRC64-UPDATE  ( crc data len -- crc' )  streaming CRC-64
\
\  Display / conversion:
\   CRC32-.     ( crc -- )             print CRC-32 as 8 hex chars
\   CRC64-.     ( crc -- )             print CRC-64 as 16 hex chars
\   CRC32->HEX  ( crc dst -- n )      CRC-32 to 8-char hex string
\   CRC64->HEX  ( crc dst -- n )      CRC-64 to 16-char hex string
\
\  Constants:
\   CRC-POLY-CRC32   ( -- 0 )         polynomial selector ID
\   CRC-POLY-CRC32C  ( -- 1 )         polynomial selector ID
\   CRC-POLY-CRC64   ( -- 2 )         polynomial selector ID
\   CRC32-INIT-VAL   ( -- 0xFFFFFFFF )
\   CRC64-INIT-VAL   ( -- 0xFFFFFFFFFFFFFFFF )
\
\  BIOS primitives used:
\   CRC-POLY!  CRC-INIT!  CRC-FEED  CRC-FEED-BYTE  CRC-FINAL@
\
\  Full 8-byte cells use CRC-FEED.  Every remaining byte uses the native
\  CRC-FEED-BYTE instruction, so no padding or software state transition
\  is needed.  CRC-FINAL@ returns the finalized result atomically.
\
\  Not reentrant.  One CRC computation at a time.
\ =================================================================

PROVIDED akashic-crc

\ =====================================================================
\  Constants
\ =====================================================================

0 CONSTANT CRC-POLY-CRC32
1 CONSTANT CRC-POLY-CRC32C
2 CONSTANT CRC-POLY-CRC64

0xFFFFFFFF             CONSTANT CRC32-INIT-VAL
0xFFFFFFFFFFFFFFFF     CONSTANT CRC64-INIT-VAL

\ =====================================================================
\  Internal: nibble-to-hex lookup
\ =====================================================================

CREATE _CRC-HEX
  48 C, 49 C, 50 C, 51 C, 52 C, 53 C, 54 C, 55 C,
  56 C, 57 C, 97 C, 98 C, 99 C, 100 C, 101 C, 102 C,

: _CRC-NIB>C  ( n -- c )
    0x0F AND _CRC-HEX + C@ ;

\ =====================================================================
\  Hardware buffer feed
\ =====================================================================

\ _CRC-FEED-BUFFER ( addr len -- )
\   Feed complete 8-byte cells through CRC.Q, then feed the exact 0–7-byte
\   remainder through CRC.B.  The byte path avoids implicit zero padding.
: _CRC-FEED-BUFFER  ( addr len -- )
    DUP 0< IF 2DROP -24 THROW THEN
    BEGIN DUP 8 >= WHILE
        OVER @ CRC-FEED
        SWAP 8 + SWAP 8 -
    REPEAT
    0 ?DO
        DUP C@ CRC-FEED-BYTE
        1+
    LOOP
    DROP ;

\ =====================================================================
\  One-shot API
\ =====================================================================

\ CRC32 ( data len -- crc )  MSB-first CRC-32/BZIP2 parameters.
: CRC32  ( data len -- crc )
    CRC-POLY-CRC32 CRC-POLY!
    CRC32-INIT-VAL CRC-INIT!
    _CRC-FEED-BUFFER
    CRC-FINAL@ ;

\ CRC32C ( data len -- crc )  MSB-first, non-reflected Castagnoli.
: CRC32C  ( data len -- crc )
    CRC-POLY-CRC32C CRC-POLY!
    CRC32-INIT-VAL CRC-INIT!
    _CRC-FEED-BUFFER
    CRC-FINAL@ ;

\ CRC64 ( data len -- crc )  CRC-64/WE parameters (ECMA polynomial).
: CRC64  ( data len -- crc )
    CRC-POLY-CRC64 CRC-POLY!
    CRC64-INIT-VAL CRC-INIT!
    _CRC-FEED-BUFFER
    CRC-FINAL@ ;

\ =====================================================================
\  Streaming API  —  BEGIN / ADD / END
\ =====================================================================
\  Each ADD feeds its complete cells and exact byte remainder directly to
\  the accelerator.  Fragment boundaries therefore do not affect results.

: CRC32-BEGIN  ( -- )
    CRC-POLY-CRC32 CRC-POLY!
    CRC32-INIT-VAL CRC-INIT! ;

: CRC32-ADD  ( addr len -- )
    _CRC-FEED-BUFFER ;

: CRC32-END  ( -- crc )
    CRC-FINAL@ ;

: CRC32C-BEGIN  ( -- )
    CRC-POLY-CRC32C CRC-POLY!
    CRC32-INIT-VAL CRC-INIT! ;

: CRC32C-ADD  ( addr len -- )
    _CRC-FEED-BUFFER ;

: CRC32C-END  ( -- crc )
    CRC-FINAL@ ;

: CRC64-BEGIN  ( -- )
    CRC-POLY-CRC64 CRC-POLY!
    CRC64-INIT-VAL CRC-INIT! ;

: CRC64-ADD  ( addr len -- )
    _CRC-FEED-BUFFER ;

: CRC64-END  ( -- crc )
    CRC-FINAL@ ;

\ =====================================================================
\  Incremental update API
\ =====================================================================
\  CRC32-UPDATE ( crc data len -- crc' )
\    Continue a CRC from a previous (finalized) result.  Pass 0 as
\    crc for the first chunk.  Example:
\      0 buf1 n1 CRC32-UPDATE  buf2 n2 CRC32-UPDATE  ( -- final-crc )
\
\  Internally: XOR crc with xorout to recover the raw accumulator, restore
\  it through CRC-INIT!, feed the next fragment, then finalize atomically.

: CRC32-UPDATE  ( crc data len -- crc' )
    >R >R
    CRC32-INIT-VAL XOR
    CRC-POLY-CRC32 CRC-POLY!
    CRC-INIT!
    R> R>
    _CRC-FEED-BUFFER
    CRC-FINAL@ ;

: CRC32C-UPDATE  ( crc data len -- crc' )
    >R >R
    CRC32-INIT-VAL XOR
    CRC-POLY-CRC32C CRC-POLY!
    CRC-INIT!
    R> R>
    _CRC-FEED-BUFFER
    CRC-FINAL@ ;

: CRC64-UPDATE  ( crc data len -- crc' )
    >R >R
    CRC64-INIT-VAL XOR
    CRC-POLY-CRC64 CRC-POLY!
    CRC-INIT!
    R> R>
    _CRC-FEED-BUFFER
    CRC-FINAL@ ;

\ =====================================================================
\  Hex conversion
\ =====================================================================

VARIABLE _CRC-HDST

\ CRC32->HEX ( crc dst -- n )
\   Convert 32-bit CRC to 8 lowercase hex chars at dst.  Returns 8.
: CRC32->HEX  ( crc dst -- n )
    _CRC-HDST !
    4 0 DO
        DUP                             ( crc crc )
        24 I 8 * - RSHIFT 0xFF AND     ( crc byte )
        DUP 4 RSHIFT _CRC-NIB>C
        _CRC-HDST @ I 2* + C!
        0x0F AND _CRC-NIB>C
        _CRC-HDST @ I 2* 1+ + C!
    LOOP
    DROP 8 ;

\ CRC64->HEX ( crc dst -- n )
\   Convert 64-bit CRC to 16 lowercase hex chars at dst.  Returns 16.
: CRC64->HEX  ( crc dst -- n )
    _CRC-HDST !
    8 0 DO
        DUP                             ( crc crc )
        56 I 8 * - RSHIFT 0xFF AND     ( crc byte )
        DUP 4 RSHIFT _CRC-NIB>C
        _CRC-HDST @ I 2* + C!
        0x0F AND _CRC-NIB>C
        _CRC-HDST @ I 2* 1+ + C!
    LOOP
    DROP 16 ;

\ =====================================================================
\  Display
\ =====================================================================

: CRC32-.  ( crc -- )
    4 0 DO
        DUP 24 I 8 * - RSHIFT 0xFF AND
        DUP 4 RSHIFT _CRC-NIB>C EMIT
        0x0F AND _CRC-NIB>C EMIT
    LOOP
    DROP ;

\ CRC64-. ( crc -- )  Print CRC-64 as 16 lowercase hex chars.
: CRC64-.  ( crc -- )
    8 0 DO
        DUP 56 I 8 * - RSHIFT 0xFF AND
        DUP 4 RSHIFT _CRC-NIB>C EMIT
        0x0F AND _CRC-NIB>C EMIT
    LOOP
    DROP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _crc-guard

0 CONSTANT _CRC-STREAM-NONE
1 CONSTANT _CRC-STREAM-CRC32
2 CONSTANT _CRC-STREAM-CRC32C
3 CONSTANT _CRC-STREAM-CRC64
VARIABLE _CRC-STREAM-MODE
VARIABLE _CRC-BEGIN-MODE
_CRC-STREAM-NONE _CRC-STREAM-MODE !

' CRC32           CONSTANT _crc32-xt
' CRC32C          CONSTANT _crc32c-xt
' CRC64           CONSTANT _crc64-xt
' CRC32-BEGIN     CONSTANT _crc32-begin-xt
' CRC32-ADD       CONSTANT _crc32-add-xt
' CRC32-END       CONSTANT _crc32-end-xt
' CRC32C-BEGIN    CONSTANT _crc32c-begin-xt
' CRC32C-ADD      CONSTANT _crc32c-add-xt
' CRC32C-END      CONSTANT _crc32c-end-xt
' CRC64-BEGIN     CONSTANT _crc64-begin-xt
' CRC64-ADD       CONSTANT _crc64-add-xt
' CRC64-END       CONSTANT _crc64-end-xt
' CRC32-UPDATE    CONSTANT _crc32-update-xt
' CRC32C-UPDATE   CONSTANT _crc32c-update-xt
' CRC64-UPDATE    CONSTANT _crc64-update-xt
' CRC32->HEX      CONSTANT _crc32-to-hex-xt
' CRC64->HEX      CONSTANT _crc64-to-hex-xt
' CRC32-.         CONSTANT _crc32-dot-xt
' CRC64-.         CONSTANT _crc64-dot-xt

\ A guarded hardware call that throws may already own the shared micro-core
\ CRC transaction.  The same owner can always execute FIN, so unwind by
\ finalizing and discarding the partial accumulator before releasing the
\ task guard.  If FIN itself faults, preserve and rethrow the original error;
\ the raw hardware contract then requires same-owner recovery.
: _CRC-FINAL-DISCARD  ( -- ) CRC-FINAL@ DROP ;
: _CRC-HARDWARE-RELEASE  ( -- )
    ['] _CRC-FINAL-DISCARD CATCH DROP ;

: _CRC-WITH-HARDWARE-GUARD  ( ... xt -- ... )
    _crc-guard GUARD-ACQUIRE
    _CRC-STREAM-MODE @ _CRC-STREAM-NONE <> IF
        _crc-guard GUARD-RELEASE
        -258 THROW
    THEN
    CATCH
    DUP IF
        >R _CRC-HARDWARE-RELEASE R>
    THEN
    _crc-guard GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;

: _CRC-STREAM-BEGIN  ( mode xt -- )
    _crc-guard GUARD-ACQUIRE
    _CRC-STREAM-MODE @ _CRC-STREAM-NONE <> IF
        _crc-guard GUARD-RELEASE
        2DROP -258 THROW
    THEN
    SWAP _CRC-BEGIN-MODE !
    CATCH ?DUP IF
        >R _CRC-HARDWARE-RELEASE
        _CRC-STREAM-NONE _CRC-STREAM-MODE !
        _crc-guard GUARD-RELEASE
        R> THROW
    THEN
    _CRC-BEGIN-MODE @ _CRC-STREAM-MODE ! ;

: _CRC-STREAM-ADD  ( addr len mode xt -- )
    _crc-guard GUARD-MINE? 0= IF -258 THROW THEN
    OVER _CRC-STREAM-MODE @ <> IF 2DROP 2DROP -258 THROW THEN
    SWAP DROP
    CATCH ?DUP IF
        >R _CRC-HARDWARE-RELEASE
        _CRC-STREAM-NONE _CRC-STREAM-MODE !
        _crc-guard GUARD-RELEASE
        R> THROW
    THEN ;

: _CRC-STREAM-END  ( mode xt -- crc )
    _crc-guard GUARD-MINE? 0= IF -258 THROW THEN
    OVER _CRC-STREAM-MODE @ <> IF 2DROP -258 THROW THEN
    SWAP DROP
    CATCH
    DUP IF
        >R _CRC-HARDWARE-RELEASE R>
    THEN
    _CRC-STREAM-NONE _CRC-STREAM-MODE !
    _crc-guard GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;

: CRC32           _crc32-xt _CRC-WITH-HARDWARE-GUARD ;
: CRC32C          _crc32c-xt _CRC-WITH-HARDWARE-GUARD ;
: CRC64           _crc64-xt _CRC-WITH-HARDWARE-GUARD ;
: CRC32-UPDATE    _crc32-update-xt _CRC-WITH-HARDWARE-GUARD ;
: CRC32C-UPDATE   _crc32c-update-xt _CRC-WITH-HARDWARE-GUARD ;
: CRC64-UPDATE    _crc64-update-xt _CRC-WITH-HARDWARE-GUARD ;
: CRC32->HEX      _crc32-to-hex-xt _crc-guard WITH-GUARD ;
: CRC64->HEX      _crc64-to-hex-xt _crc-guard WITH-GUARD ;
: CRC32-.         _crc32-dot-xt _crc-guard WITH-GUARD ;
: CRC64-.         _crc64-dot-xt _crc-guard WITH-GUARD ;
: CRC32-BEGIN   _CRC-STREAM-CRC32 _crc32-begin-xt _CRC-STREAM-BEGIN ;
: CRC32C-BEGIN  _CRC-STREAM-CRC32C _crc32c-begin-xt _CRC-STREAM-BEGIN ;
: CRC64-BEGIN   _CRC-STREAM-CRC64 _crc64-begin-xt _CRC-STREAM-BEGIN ;
: CRC32-ADD     _CRC-STREAM-CRC32 _crc32-add-xt _CRC-STREAM-ADD ;
: CRC32C-ADD    _CRC-STREAM-CRC32C _crc32c-add-xt _CRC-STREAM-ADD ;
: CRC64-ADD     _CRC-STREAM-CRC64 _crc64-add-xt _CRC-STREAM-ADD ;
: CRC32-END     _CRC-STREAM-CRC32 _crc32-end-xt _CRC-STREAM-END ;
: CRC32C-END    _CRC-STREAM-CRC32C _crc32c-end-xt _CRC-STREAM-END ;
: CRC64-END     _CRC-STREAM-CRC64 _crc64-end-xt _CRC-STREAM-END ;
[THEN] [THEN]
