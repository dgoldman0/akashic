\ =================================================================
\  aes.f  —  AES-256/128-GCM Authenticated Encryption
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: AES-GCM-
\  Depends on: (none — uses BIOS/KDOS AES MMIO accelerator)
\
\  Public API — one-shot:
\   AES-GCM-ENCRYPT      ( key iv pt ct len -- )      encrypt, tag in AES-GCM-TAG
\   AES-GCM-DECRYPT      ( key iv ct pt len tag -- f ) decrypt+verify
\   AES-GCM-ENCRYPT-AAD  ( key iv aad alen pt ct len -- )   encrypt with AAD
\   AES-GCM-DECRYPT-AAD  ( key iv aad alen ct pt len tag -- f ) decrypt+verify with AAD
\
\  Public API — streaming:
\   AES-GCM-BEGIN         ( key iv aadlen datalen dir -- )  init GCM context
\   AES-GCM-FEED-AAD      ( addr len -- )                  feed AAD
\   AES-GCM-FEED-DATA     ( src dst len -- )                encrypt/decrypt data
\   AES-GCM-FINISH        ( -- )                            finalize
\   AES-GCM-TAG@          ( dst -- )                        read computed tag
\
\  Display / Comparison:
\   AES-GCM-TAG.       ( -- )           print last tag as 32 hex chars
\   AES-GCM-TAG-EQ?    ( a -- flag )    constant-time compare tag at a vs last tag
\
\  Constants:
\   AES-GCM-KEY-LEN    ( -- 32 )        AES-256 key size
\   AES-GCM-KEY128-LEN ( -- 16 )        AES-128 key size
\   AES-GCM-IV-LEN     ( -- 12 )        nonce size
\   AES-GCM-TAG-LEN    ( -- 16 )        authentication tag size
\   AES-GCM-BLK-LEN    ( -- 16 )        block size
\
\  Mode selection:
\   AES-GCM-USE-256    ( -- )           select AES-256 (default)
\   AES-GCM-USE-128    ( -- )           select AES-128
\
\  BIOS primitives used:
\   AES-KEY!  AES-IV!  AES-AAD-LEN!  AES-DATA-LEN!
\   AES-CMD!  AES-STATUS@  AES-KEY-MODE!
\   AES-DIN!  AES-DOUT@  AES-TAG@  AES-TAG!
\
\  Not reentrant.  One encryption at a time.
\ =================================================================

PROVIDED akashic-aes

\ =====================================================================
\  Constants
\ =====================================================================

32 CONSTANT AES-GCM-KEY-LEN
16 CONSTANT AES-GCM-KEY128-LEN
12 CONSTANT AES-GCM-IV-LEN
16 CONSTANT AES-GCM-TAG-LEN
16 CONSTANT AES-GCM-BLK-LEN

\ =====================================================================
\  Mode selection
\ =====================================================================

: AES-GCM-USE-256  ( -- )  0 AES-KEY-MODE! ;
: AES-GCM-USE-128  ( -- )  1 AES-KEY-MODE! ;

\ =====================================================================
\  Scratch buffers and variables
\ =====================================================================

CREATE _AES-TAG-BUF 16 ALLOT
CREATE _AES-PAD     16 ALLOT

VARIABLE _AES-VSRC   VARIABLE _AES-VDST   VARIABLE _AES-VLEN
VARIABLE _AES-VAAD   VARIABLE _AES-VAADL

\ =====================================================================
\  Internal: hex display
\ =====================================================================

: _AES-HEXNIB  ( n -- )
    DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;

: _AES-HEXBYTE  ( c -- )
    DUP 4 RSHIFT _AES-HEXNIB 0x0F AND _AES-HEXNIB ;

\ =====================================================================
\  Internal: feed data blocks through hardware
\ =====================================================================

\ _AES-FEED  Feed _AES-VLEN bytes from _AES-VSRC to _AES-VDST.
: _AES-FEED  ( -- )
    _AES-VLEN @ 4 RSHIFT
    0 ?DO
        _AES-VSRC @ AES-DIN!
        _AES-VDST @ AES-DOUT@
        _AES-VSRC @ 16 + _AES-VSRC !
        _AES-VDST @ 16 + _AES-VDST !
    LOOP
    _AES-VLEN @ 15 AND DUP 0> IF
        _AES-PAD 16 0 FILL
        _AES-VSRC @ _AES-PAD ROT CMOVE
        _AES-PAD AES-DIN!
        _AES-PAD AES-DOUT@
        _AES-PAD _AES-VDST @ _AES-VLEN @ 15 AND CMOVE
    ELSE
        DROP
    THEN ;

\ _AES-FEED-AAD-BLK  Feed AAD from _AES-VAAD/_AES-VAADL (multi-block).
: _AES-FEED-AAD-BLK  ( -- )
    _AES-VAAD @ _AES-VAADL @            \ addr len
    BEGIN DUP 16 >= WHILE
        OVER AES-DIN!                   \ feed full 16-byte block
        SWAP 16 + SWAP 16 -
    REPEAT
    DUP 0> IF
        _AES-PAD 16 0 FILL
        OVER _AES-PAD ROT CMOVE         \ copy partial to pad
        DROP
        _AES-PAD AES-DIN!
    ELSE
        2DROP
    THEN ;

\ =====================================================================
\  One-shot API — No AAD
\ =====================================================================

: AES-GCM-ENCRYPT  ( key iv pt ct len -- )
    _AES-VLEN ! _AES-VDST ! _AES-VSRC !
    AES-IV! AES-KEY!
    0 AES-AAD-LEN!
    _AES-VLEN @ AES-DATA-LEN!
    0 AES-CMD!
    _AES-FEED
    _AES-TAG-BUF AES-TAG@ ;

: AES-GCM-DECRYPT  ( key iv ct pt len tag -- flag )
    AES-TAG!
    _AES-VLEN ! _AES-VDST ! _AES-VSRC !
    AES-IV! AES-KEY!
    0 AES-AAD-LEN!
    _AES-VLEN @ AES-DATA-LEN!
    1 AES-CMD!
    _AES-FEED
    AES-STATUS@ 2 = IF TRUE ELSE FALSE THEN ;

\ =====================================================================
\  One-shot API — With AAD
\ =====================================================================

: AES-GCM-ENCRYPT-AAD  ( key iv aad alen pt ct len -- )
    _AES-VLEN ! _AES-VDST ! _AES-VSRC !
    _AES-VAADL ! _AES-VAAD !
    AES-IV! AES-KEY!
    _AES-VAADL @ AES-AAD-LEN!
    _AES-VLEN @ AES-DATA-LEN!
    0 AES-CMD!
    _AES-FEED-AAD-BLK
    _AES-FEED
    _AES-TAG-BUF AES-TAG@ ;

: AES-GCM-DECRYPT-AAD  ( key iv aad alen ct pt len tag -- flag )
    AES-TAG!
    _AES-VLEN ! _AES-VDST ! _AES-VSRC !
    _AES-VAADL ! _AES-VAAD !
    AES-IV! AES-KEY!
    _AES-VAADL @ AES-AAD-LEN!
    _AES-VLEN @ AES-DATA-LEN!
    1 AES-CMD!
    _AES-FEED-AAD-BLK
    _AES-FEED
    AES-STATUS@ 2 = IF TRUE ELSE FALSE THEN ;

\ =====================================================================
\  Streaming API
\ =====================================================================

: AES-GCM-BEGIN  ( key iv aadlen datalen dir -- )
    >R >R >R
    AES-IV! AES-KEY!
    R> AES-AAD-LEN!
    R> AES-DATA-LEN!
    R> AES-CMD! ;

: AES-GCM-FEED-AAD  ( addr len -- )
    BEGIN DUP 16 >= WHILE
        OVER AES-DIN!
        SWAP 16 + SWAP 16 -
    REPEAT
    DUP 0> IF
        _AES-PAD 16 0 FILL
        OVER _AES-PAD ROT CMOVE
        DROP
        _AES-PAD AES-DIN!
    ELSE
        2DROP
    THEN ;

: AES-GCM-FEED-DATA  ( src dst len -- )
    _AES-VLEN ! _AES-VDST ! _AES-VSRC !
    _AES-FEED ;

: AES-GCM-FINISH  ( -- )
    _AES-TAG-BUF AES-TAG@ ;

\ AES-GCM-TAG@ ( dst -- )  Copy last tag to dst.
: AES-GCM-TAG@  ( dst -- )
    _AES-TAG-BUF SWAP 16 CMOVE ;

: AES-GCM-STATUS  ( -- n )  AES-STATUS@ ;

\ =====================================================================
\  Display / Comparison
\ =====================================================================

: AES-GCM-TAG.  ( -- )
    16 0 DO _AES-TAG-BUF I + C@ _AES-HEXBYTE LOOP ;

: AES-GCM-TAG-EQ?  ( a -- flag )
    0
    16 0 DO
        OVER I + C@ _AES-TAG-BUF I + C@ XOR OR
    LOOP
    NIP
    0= IF TRUE ELSE FALSE THEN ;
