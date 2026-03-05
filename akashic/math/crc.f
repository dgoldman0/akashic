\ =================================================================
\  crc.f  —  CRC-32 / CRC-32C / CRC-64 (hardware-accelerated)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: CRC-
\  Depends on: (none — uses BIOS CRC MMIO accelerator)
\
\  Public API — one-shot:
\   CRC32       ( data len -- crc )    CRC-32 (ISO 3309)
\   CRC32C      ( data len -- crc )    CRC-32C (Castagnoli / iSCSI)
\   CRC64       ( data len -- crc )    CRC-64-ECMA
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
\   CRC-POLY!  CRC-INIT!  CRC-FEED  CRC@  CRC-FINAL
\
\  The hardware CRC accelerator processes data in 8-byte chunks
\  via CRC-FEED.  This module feeds aligned chunks through hardware
\  and handles any remaining 1–7 bytes via software bit-by-bit
\  CRC, giving byte-exact results for all input lengths.
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
\  Software per-byte CRC (MSB-first, bit-by-bit)
\ =====================================================================
\  Used for trailing 1–7 bytes that can't go through the 8-byte
\  hardware CRC-FEED path.
\
\  Algorithm per byte:
\    crc ← crc XOR (byte << (width − 8))
\    repeat 8:
\      if top bit set: crc ← (crc << 1) XOR polynomial
\      else:           crc ← crc << 1
\      crc ← crc AND width-mask

\ _CRC32-SW1 ( crc byte -- crc' )  CRC-32, poly 0x04C11DB7
: _CRC32-SW1  ( crc byte -- crc' )
    24 LSHIFT XOR
    8 0 DO
        DUP 0x80000000 AND IF
            1 LSHIFT 0x04C11DB7 XOR
        ELSE
            1 LSHIFT
        THEN
        0xFFFFFFFF AND
    LOOP ;

\ _CRC32C-SW1 ( crc byte -- crc' )  CRC-32C, poly 0x1EDC6F41
: _CRC32C-SW1  ( crc byte -- crc' )
    24 LSHIFT XOR
    8 0 DO
        DUP 0x80000000 AND IF
            1 LSHIFT 0x1EDC6F41 XOR
        ELSE
            1 LSHIFT
        THEN
        0xFFFFFFFF AND
    LOOP ;

\ _CRC64-SW1 ( crc byte -- crc' )  CRC-64-ECMA, poly 0x42F0E1EBA9EA3693
: _CRC64-SW1  ( crc byte -- crc' )
    56 LSHIFT XOR
    8 0 DO
        DUP 0< IF
            1 LSHIFT 0x42F0E1EBA9EA3693 XOR
        ELSE
            1 LSHIFT
        THEN
    LOOP ;

\ =====================================================================
\  Internal variables
\ =====================================================================

VARIABLE _CRC-ADDR     \ buffer address for tail / streaming loops
VARIABLE _CRC-REM      \ remaining byte count
VARIABLE _CRC-SREG     \ software CRC register (streaming API)

\ =====================================================================
\  Hardware bulk feeding
\ =====================================================================

\ _CRC-FEED-BULK ( addr len -- addr' rem )
\   Feed full 8-byte chunks to hardware CRC accelerator via @/CRC-FEED.
\   Returns updated address and remaining byte count (0–7).
: _CRC-FEED-BULK  ( addr len -- addr' rem )
    BEGIN DUP 8 >= WHILE
        OVER @ CRC-FEED
        SWAP 8 + SWAP 8 -
    REPEAT ;

\ =====================================================================
\  Tail byte processing (software, reads/writes HW register)
\ =====================================================================
\  After hardware has processed full 8-byte chunks, these words
\  handle the remaining 0–7 bytes in software.  They read the hw
\  CRC register (CRC@), process bytes via per-byte software words,
\  and write the result back via CRC-INIT! for finalization.

: _CRC32-TAIL  ( addr rem -- )
    DUP 0= IF 2DROP EXIT THEN
    _CRC-REM ! _CRC-ADDR !
    CRC@
    _CRC-REM @ 0 DO
        _CRC-ADDR @ I + C@  _CRC32-SW1
    LOOP
    CRC-INIT! ;

: _CRC32C-TAIL  ( addr rem -- )
    DUP 0= IF 2DROP EXIT THEN
    _CRC-REM ! _CRC-ADDR !
    CRC@
    _CRC-REM @ 0 DO
        _CRC-ADDR @ I + C@  _CRC32C-SW1
    LOOP
    CRC-INIT! ;

: _CRC64-TAIL  ( addr rem -- )
    DUP 0= IF 2DROP EXIT THEN
    _CRC-REM ! _CRC-ADDR !
    CRC@
    _CRC-REM @ 0 DO
        _CRC-ADDR @ I + C@  _CRC64-SW1
    LOOP
    CRC-INIT! ;

\ =====================================================================
\  One-shot API  (hardware bulk + software tail)
\ =====================================================================

\ CRC32 ( data len -- crc )  CRC-32 (ISO 3309 / ITU-T V.42).
: CRC32  ( data len -- crc )
    CRC-POLY-CRC32 CRC-POLY!
    CRC32-INIT-VAL CRC-INIT!
    _CRC-FEED-BULK  _CRC32-TAIL
    CRC-FINAL CRC@ ;

\ CRC32C ( data len -- crc )  CRC-32C (Castagnoli / iSCSI).
: CRC32C  ( data len -- crc )
    CRC-POLY-CRC32C CRC-POLY!
    CRC32-INIT-VAL CRC-INIT!
    _CRC-FEED-BULK  _CRC32C-TAIL
    CRC-FINAL CRC@ ;

\ CRC64 ( data len -- crc )  CRC-64-ECMA-182.
: CRC64  ( data len -- crc )
    CRC-POLY-CRC64 CRC-POLY!
    CRC64-INIT-VAL CRC-INIT!
    _CRC-FEED-BULK  _CRC64-TAIL
    CRC-FINAL CRC@ ;

\ =====================================================================
\  Streaming API  —  BEGIN / ADD / END  (pure software)
\ =====================================================================
\  Software byte-by-byte processing guarantees byte-exact results
\  regardless of how data is split across multiple ADD calls.

: CRC32-BEGIN  ( -- )   CRC32-INIT-VAL _CRC-SREG ! ;

: CRC32-ADD  ( addr len -- )
    DUP 0= IF 2DROP EXIT THEN
    SWAP _CRC-ADDR !  _CRC-REM !
    _CRC-REM @ 0 DO
        _CRC-SREG @  _CRC-ADDR @ I + C@  _CRC32-SW1  _CRC-SREG !
    LOOP ;

: CRC32-END  ( -- crc )
    _CRC-SREG @ CRC32-INIT-VAL XOR ;

: CRC32C-BEGIN  ( -- )  CRC32-INIT-VAL _CRC-SREG ! ;

: CRC32C-ADD  ( addr len -- )
    DUP 0= IF 2DROP EXIT THEN
    SWAP _CRC-ADDR !  _CRC-REM !
    _CRC-REM @ 0 DO
        _CRC-SREG @  _CRC-ADDR @ I + C@  _CRC32C-SW1  _CRC-SREG !
    LOOP ;

: CRC32C-END  ( -- crc )
    _CRC-SREG @ CRC32-INIT-VAL XOR ;

: CRC64-BEGIN  ( -- )   CRC64-INIT-VAL _CRC-SREG ! ;

: CRC64-ADD  ( addr len -- )
    DUP 0= IF 2DROP EXIT THEN
    SWAP _CRC-ADDR !  _CRC-REM !
    _CRC-REM @ 0 DO
        _CRC-SREG @  _CRC-ADDR @ I + C@  _CRC64-SW1  _CRC-SREG !
    LOOP ;

: CRC64-END  ( -- crc )
    _CRC-SREG @ CRC64-INIT-VAL XOR ;

\ =====================================================================
\  Incremental update API  (hardware bulk + software tail)
\ =====================================================================
\  CRC32-UPDATE ( crc data len -- crc' )
\    Continue a CRC from a previous (finalized) result.  Pass 0 as
\    crc for the first chunk.  Example:
\      0 buf1 n1 CRC32-UPDATE  buf2 n2 CRC32-UPDATE  ( -- final-crc )
\
\  Internally: XOR crc with init-val to un-finalize, feed data
\  through hardware bulk + software tail, then re-finalize.

: CRC32-UPDATE  ( crc data len -- crc' )
    >R >R
    CRC32-INIT-VAL XOR
    CRC-POLY-CRC32 CRC-POLY!
    CRC-INIT!
    R> R>
    _CRC-FEED-BULK  _CRC32-TAIL
    CRC-FINAL CRC@ ;

: CRC32C-UPDATE  ( crc data len -- crc' )
    >R >R
    CRC32-INIT-VAL XOR
    CRC-POLY-CRC32C CRC-POLY!
    CRC-INIT!
    R> R>
    _CRC-FEED-BULK  _CRC32C-TAIL
    CRC-FINAL CRC@ ;

: CRC64-UPDATE  ( crc data len -- crc' )
    >R >R
    CRC64-INIT-VAL XOR
    CRC-POLY-CRC64 CRC-POLY!
    CRC-INIT!
    R> R>
    _CRC-FEED-BULK  _CRC64-TAIL
    CRC-FINAL CRC@ ;

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

\ CRC32-. ( crc -- )  Print CRC-32 as 8 lowercase hex chars.
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
