\ ws.f — WebSocket client for KDOS / Megapad-64 (RFC 6455)
\
\ WebSocket protocol for real-time bidirectional communication.
\ Uses HTTP for the upgrade handshake, then switches to framed mode.
\
\ REQUIRE http.f
\
\ Prefix: WS-   (public API)
\         _WS-  (internal helpers)
\
\ Load with:   REQUIRE ws.f

REQUIRE http.f
REQUIRE ../concurrency/guard.f

PROVIDED akashic-websocket

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE WS-ERR
1 CONSTANT WS-E-CONNECT
2 CONSTANT WS-E-HANDSHAKE
3 CONSTANT WS-E-OVERFLOW
4 CONSTANT WS-E-FRAME
5 CONSTANT WS-E-CLOSED
6 CONSTANT WS-E-PROTOCOL

: WS-FAIL       ( code -- )  WS-ERR ! ;
: WS-OK?        ( -- flag )  WS-ERR @ 0= ;
: WS-CLEAR-ERR  ( -- )       0 WS-ERR ! ;

\ =====================================================================
\  Opcode Constants
\ =====================================================================

0  CONSTANT WS-OP-CONT
1  CONSTANT WS-OP-TEXT
2  CONSTANT WS-OP-BINARY
8  CONSTANT WS-OP-CLOSE
9  CONSTANT WS-OP-PING
10 CONSTANT WS-OP-PONG

\ =====================================================================
\  Connection State
\ =====================================================================

VARIABLE _WS-CTX                \ underlying TCP/TLS context
VARIABLE _WS-TLS                \ -1 = TLS, 0 = plain
VARIABLE _WS-OPEN               \ -1 = connected, 0 = closed

VARIABLE WS-AUTO-PONG           \ -1 = auto-reply to pings (default)
-1 WS-AUTO-PONG !

\ =====================================================================
\  SHA-1 — Minimal Implementation (RFC 3174)
\ =====================================================================
\
\  Only used for Sec-WebSocket-Accept validation.
\  Not for cryptographic security — WebSocket spec mandates it.
\  Input must be ≤ 55 bytes (single 64-byte block after padding).

CREATE _SHA1-H  5 CELLS ALLOT   \ 5 × 32-bit hash state
CREATE _SHA1-W  80 CELLS ALLOT  \ 80 × 32-bit schedule
CREATE _SHA1-BLK 128 ALLOT      \ padded message (up to 2 blocks)
VARIABLE _SHA1-A  VARIABLE _SHA1-B  VARIABLE _SHA1-C
VARIABLE _SHA1-D  VARIABLE _SHA1-E  VARIABLE _SHA1-T

\ 32-bit left rotate (64-bit cells, mask to 32 bits)
: _SHA1-ROTL  ( x n -- x' )
    >R DUP R@ LSHIFT 4294967295 AND
    SWAP 32 R> - RSHIFT 4294967295 AND
    OR ;

\ SHA-1 round function f(t, b, c, d)
: _SHA1-F  ( t b c d -- result )
    >R >R >R
    DUP 20 < IF
        DROP R> R> R>           \ ( b c d )
        SWAP >R                  \ ( b d ) R: c
        OVER INVERT 4294967295 AND AND  \ ( b ~b&d ) R: c
        SWAP R> AND              \ ( ~b&d b&c )
        OR                       \ Ch(b,c,d)
        EXIT
    THEN
    DUP 40 < IF
        DROP R> R> R>           \ ( b c d )
        ROT ROT XOR XOR         \ b XOR c XOR d
        EXIT
    THEN
    DUP 60 < IF
        DROP R> R> R>           \ ( b c d )
        >R 2DUP AND             \ ( b c b&c ) R: d
        ROT R@ AND              \ ( c b&c b&d ) R: d
        OR SWAP R> AND OR        \ ( (b&c)|(b&d)|(c&d) )
        EXIT
    THEN
    DROP R> R> R>               \ ( b c d )
    ROT ROT XOR XOR ;           \ b XOR c XOR d

\ SHA-1 round constant K(t)
: _SHA1-K  ( t -- k )
    DUP 20 < IF DROP 1518500249 EXIT THEN
    DUP 40 < IF DROP 1859775393 EXIT THEN
    DUP 60 < IF DROP 2400959708 EXIT THEN
    DROP 3395469782 ;

\ Load big-endian 32-bit word from address
: _SHA1-BE@  ( addr -- u32 )
    DUP     C@ 24 LSHIFT
    OVER 1 + C@ 16 LSHIFT OR
    OVER 2 + C@  8 LSHIFT OR
    SWAP 3 + C@            OR ;

\ Store big-endian 32-bit word to address
: _SHA1-BE!  ( u32 addr -- )
    OVER 24 RSHIFT 255 AND OVER     C!
    OVER 16 RSHIFT 255 AND OVER 1 + C!
    OVER  8 RSHIFT 255 AND OVER 2 + C!
    SWAP             255 AND SWAP 3 + C! ;

\ Process one 64-byte block starting at blk-addr through the SHA-1 rounds.
\ Reads _SHA1-H as input state, updates _SHA1-H with result.
VARIABLE _SHA1-BLK-PTR
: _SHA1-BLOCK  ( blk-addr -- )
    _SHA1-BLK-PTR !
    \ Prepare schedule W[0..15]
    16 0 DO
        _SHA1-BLK-PTR @ I 4 * + _SHA1-BE@
        _SHA1-W I CELLS + !
    LOOP
    \ Extend W[16..79]
    80 16 DO
        _SHA1-W I 3 -  CELLS + @
        _SHA1-W I 8 -  CELLS + @ XOR
        _SHA1-W I 14 - CELLS + @ XOR
        _SHA1-W I 16 - CELLS + @ XOR
        1 _SHA1-ROTL
        _SHA1-W I CELLS + !
    LOOP
    \ Initialize working variables
    _SHA1-H @                  _SHA1-A !
    _SHA1-H 1 CELLS + @       _SHA1-B !
    _SHA1-H 2 CELLS + @       _SHA1-C !
    _SHA1-H 3 CELLS + @       _SHA1-D !
    _SHA1-H 4 CELLS + @       _SHA1-E !
    \ 80 rounds
    80 0 DO
        _SHA1-A @ 5 _SHA1-ROTL
        I _SHA1-B @ _SHA1-C @ _SHA1-D @ _SHA1-F +
        _SHA1-E @ +
        I _SHA1-K +
        _SHA1-W I CELLS + @ +
        4294967295 AND
        _SHA1-T !
        _SHA1-D @ _SHA1-E !
        _SHA1-C @ _SHA1-D !
        _SHA1-B @ 30 _SHA1-ROTL _SHA1-C !
        _SHA1-A @ _SHA1-B !
        _SHA1-T @ _SHA1-A !
    LOOP
    \ Add to hash
    _SHA1-A @ _SHA1-H @                  + 4294967295 AND _SHA1-H !
    _SHA1-B @ _SHA1-H 1 CELLS + @       + 4294967295 AND _SHA1-H 1 CELLS + !
    _SHA1-C @ _SHA1-H 2 CELLS + @       + 4294967295 AND _SHA1-H 2 CELLS + !
    _SHA1-D @ _SHA1-H 3 CELLS + @       + 4294967295 AND _SHA1-H 3 CELLS + !
    _SHA1-E @ _SHA1-H 4 CELLS + @       + 4294967295 AND _SHA1-H 4 CELLS + ! ;

\ SHA-1 hash: ( src len dst -- )
\   dst must have 20 bytes.  len must be < 120 (up to two blocks).
VARIABLE _SHA1-NBLK
: SHA1  ( src len dst -- )
    >R                           \ save dst
    \ Initialize H0-H4
    1732584193 _SHA1-H !
    4023233417 _SHA1-H 1 CELLS + !
    2562383102 _SHA1-H 2 CELLS + !
     271733878 _SHA1-H 3 CELLS + !
    3285377520 _SHA1-H 4 CELLS + !
    \ Pad message into _SHA1-BLK (128 bytes max)
    _SHA1-BLK 128 0 FILL
    DUP >R                       \ save original length
    _SHA1-BLK SWAP CMOVE         \ copy message
    128 _SHA1-BLK R@ + C!        \ 0x80 after message
    \ Determine number of blocks (1 or 2)
    R@ 55 > IF 2 ELSE 1 THEN _SHA1-NBLK !
    \ Length in bits (big-endian) at end of last block
    R> 3 LSHIFT                  \ len * 8 = bit length
    _SHA1-BLK _SHA1-NBLK @ 64 * 4 - + _SHA1-BE!
    \ Process block(s)
    _SHA1-BLK _SHA1-BLOCK
    _SHA1-NBLK @ 2 = IF
        _SHA1-BLK 64 + _SHA1-BLOCK
    THEN
    \ Output 20 bytes big-endian
    R>                           \ recover dst
    _SHA1-H @                  OVER      _SHA1-BE!
    _SHA1-H 1 CELLS + @       OVER  4 + _SHA1-BE!
    _SHA1-H 2 CELLS + @       OVER  8 + _SHA1-BE!
    _SHA1-H 3 CELLS + @       OVER 12 + _SHA1-BE!
    _SHA1-H 4 CELLS + @       SWAP 16 + _SHA1-BE! ;

\ =====================================================================
\  Layer 1 — Frame Encoding/Decoding
\ =====================================================================
\
\  Defined before Layer 0 (handshake) because WS-DISCONNECT needs
\  WS-FRAME-SEND, and WS-FRAME-RECV needs WS-PONG.

\ Frame header build buffer
CREATE _WS-FHDR 14 ALLOT       \ max frame header: 2 + 8 + 4 = 14

\ _WS-MASK ( data len mask-key -- )
\   XOR-mask data in place with 4-byte rotating key.
\   Mask bytes in network order (MSB first): byte[i] XOR key>>(24-8*(i%4)).
VARIABLE _WS-MKEY-TMP
: _WS-MASK  ( data-a data-u mask -- )
    _WS-MKEY-TMP !
    0 ?DO
        DUP I + DUP C@
        _WS-MKEY-TMP @ 24 I 3 AND 8 * - RSHIFT 255 AND
        XOR SWAP C!
    LOOP
    DROP ;

\ WS-FRAME-SEND ( ctx opcode payload-a payload-u -- )
\   Build and send one WebSocket frame.
\   Client frames are always masked (RFC 6455 §5.3).
: WS-FRAME-SEND  ( ctx opcode payload-a payload-u -- )
    >R >R                        \ save payload ( R: len addr )
    \ Byte 0: FIN + opcode
    128 OR _WS-FHDR C!           \ FIN=1, opcode in low 4 bits
    \ Payload length + mask bit (0x80)
    R@ R@ DROP                   \ get len
    2R> SWAP >R >R               \ rearrange: ( ctx ) R: addr len
    R@                           \ len
    DUP 126 < IF
        128 OR _WS-FHDR 1+ C!   \ mask bit + 7-bit length
        \ Total header = 2 + 4 (mask key) = 6
        \ Generate mask key
        RANDOM _WS-FHDR 2 + !
        \ Send header
        _WS-FHDR 6 HTTP-SEND DROP
    ELSE DUP 65536 < IF
        254 _WS-FHDR 1+ C!      \ mask bit + 126
        \ 16-bit extended length (big-endian)
        DUP 8 RSHIFT 255 AND _WS-FHDR 2 + C!
        255 AND _WS-FHDR 3 + C!
        \ Mask key at offset 4
        RANDOM _WS-FHDR 4 + !
        _WS-FHDR 8 HTTP-SEND DROP
    ELSE
        \ 64-bit length — unlikely on Megapad but handle it
        255 _WS-FHDR 1+ C!      \ mask bit + 127
        _WS-FHDR 2 + 4 0 FILL   \ high 32 bits = 0
        DUP 24 RSHIFT 255 AND _WS-FHDR 6 + C!
        DUP 16 RSHIFT 255 AND _WS-FHDR 7 + C!
        DUP  8 RSHIFT 255 AND _WS-FHDR 8 + C!
        255 AND _WS-FHDR 9 + C!
        RANDOM _WS-FHDR 10 + !
        _WS-FHDR 14 HTTP-SEND DROP
    THEN THEN
    \ Mask payload in place and send
    R> R>                        \ ( addr len )
    DUP 0> IF
        \ Read mask key back from header
        \ Mask key position depends on length encoding
        _WS-FHDR 1+ C@ 127 AND  \ length byte without mask bit
        DUP 126 < IF
            DROP _WS-FHDR 2 + @
        ELSE 126 = IF
            _WS-FHDR 4 + @
        ELSE
            _WS-FHDR 10 + @
        THEN THEN
        >R 2DUP R> _WS-MASK     \ mask payload
        HTTP-SEND DROP
    ELSE
        2DROP
    THEN
    DROP ;                       \ drop ctx

\ WS-PING ( ctx -- )
\   Send a ping frame.
: WS-PING  ( ctx -- )
    WS-OP-PING 0 0 WS-FRAME-SEND ;

\ WS-PONG ( ctx payload-a payload-u -- )
\   Send a pong frame (echo payload from ping).
: WS-PONG  ( ctx payload-a payload-u -- )
    >R >R WS-OP-PONG R> R> WS-FRAME-SEND ;

\ Frame receive state
CREATE _WS-RBUF 4096 ALLOT      \ raw receive staging
VARIABLE _WS-RBUF-LEN
VARIABLE _WS-RX-OP              \ received opcode
VARIABLE _WS-RX-FIN             \ FIN flag
VARIABLE _WS-RX-MASK            \ mask flag
VARIABLE _WS-RX-PLEN            \ payload length
VARIABLE _WS-RX-MKEY            \ mask key

\ _WS-RECV-BYTES ( buf max -- n )
\   Receive exactly max bytes (blocking poll loop).
VARIABLE _WRB-GOT
: _WS-RECV-BYTES  ( buf max -- n )
    0 _WRB-GOT !
    BEGIN
        _WRB-GOT @ OVER <
    WHILE
        TCP-POLL NET-IDLE
        OVER _WRB-GOT @ +       \ buf + got
        OVER _WRB-GOT @ -       \ max - got
        HTTP-RECV
        DUP 0> IF
            _WRB-GOT +!
        ELSE DUP -1 = IF
            2DROP _WRB-GOT @ EXIT  \ error
        ELSE
            DROP
        THEN THEN
    REPEAT
    NIP _WRB-GOT @ ;

\ WS-FRAME-RECV ( ctx buf max -- opcode payload-a payload-u | -1 0 0 )
\   Receive and decode one frame.
\   Returns opcode + payload, or -1 on error/closed.
: WS-FRAME-RECV  ( ctx buf max -- opcode payload-a payload-u )
    >R >R DROP                   \ save buf max, drop ctx
    \ Read 2-byte header
    _WS-RBUF 2 _WS-RECV-BYTES
    2 < IF R> R> 2DROP -1 0 0 EXIT THEN
    \ Parse byte 0: FIN + opcode
    _WS-RBUF C@ DUP 128 AND 0<> _WS-RX-FIN !
    15 AND _WS-RX-OP !
    \ Parse byte 1: mask + length
    _WS-RBUF 1+ C@
    DUP 128 AND 0<> _WS-RX-MASK !
    127 AND
    \ Extended length
    DUP 126 = IF
        DROP
        _WS-RBUF 2 _WS-RECV-BYTES DROP
        _WS-RBUF C@ 8 LSHIFT _WS-RBUF 1+ C@ OR
    ELSE DUP 127 = IF
        DROP
        _WS-RBUF 8 _WS-RECV-BYTES DROP
        \ Use low 32 bits only
        _WS-RBUF 4 + _SHA1-BE@    \ big-endian 32-bit
    THEN THEN
    _WS-RX-PLEN !
    \ Read mask key if present
    _WS-RX-MASK @ IF
        _WS-RBUF 4 _WS-RECV-BYTES DROP
        _WS-RBUF @ _WS-RX-MKEY !
    THEN
    \ Read payload into caller's buffer
    _WS-RX-PLEN @ R> MIN         \ don't exceed caller's max ( R: buf )
    R> OVER _WS-RECV-BYTES        \ ( plen actual )
    DROP                          \ drop actual (use plen)
    \ Unmask if needed
    _WS-RX-MASK @ IF
        R> _WS-RX-PLEN @ _WS-RX-MKEY @ _WS-MASK
    THEN
    \ Auto-pong
    _WS-RX-OP @ WS-OP-PING = WS-AUTO-PONG @ AND IF
        _WS-CTX @ 2 PICK 2 PICK WS-PONG
    THEN
    \ Return
    _WS-RX-OP @ -ROT ;

\ =====================================================================
\  Layer 0 — Handshake
\ =====================================================================

\ WebSocket GUID (RFC 6455 §4.2.2)
CREATE _WS-GUID 36 ALLOT
: _WS-INIT-GUID
    S" 258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    _WS-GUID SWAP CMOVE ;
_WS-INIT-GUID

\ Key generation
CREATE _WS-KEY-RAW 16 ALLOT     \ 16 random bytes
CREATE _WS-KEY-B64 32 ALLOT     \ Base64-encoded key (24 chars)
VARIABLE _WS-KEY-LEN

\ _WS-MAKE-KEY ( -- addr len )
\   Generate 16-byte random nonce, Base64-encode to 24 chars.
: _WS-MAKE-KEY  ( -- addr len )
    \ Fill 16 bytes from TRNG
    4 0 DO
        RANDOM
        _WS-KEY-RAW I 4 * + !
    LOOP
    _WS-KEY-RAW 16 _WS-KEY-B64 32 B64-ENCODE
    _WS-KEY-LEN !
    _WS-KEY-B64 _WS-KEY-LEN @ ;

\ Accept validation buffers
CREATE _WS-ACCEPT-IN  128 ALLOT \ key + GUID concatenation (≤64)
CREATE _WS-ACCEPT-SHA 20 ALLOT  \ SHA-1 result
CREATE _WS-ACCEPT-B64 32 ALLOT  \ Base64 of SHA-1
VARIABLE _WS-ACCEPT-LEN
VARIABLE _WS-VAL-KEYA           \ saved key-a
VARIABLE _WS-VAL-KEYU           \ saved key-u

\ _WS-VALIDATE ( resp-hdr-a resp-hdr-u key-a key-u -- flag )
\   Validate Sec-WebSocket-Accept header against our key.
\   accept = Base64(SHA-1(key + GUID))
: _WS-VALIDATE  ( hdr-a hdr-u key-a key-u -- flag )
    \ Save key addr/len
    _WS-VAL-KEYU !  _WS-VAL-KEYA !
    \ Stack: ( hdr-a hdr-u )
    \ Build expected: key + GUID → _WS-ACCEPT-IN
    _WS-VAL-KEYA @ _WS-ACCEPT-IN _WS-VAL-KEYU @ CMOVE
    _WS-GUID _WS-ACCEPT-IN _WS-VAL-KEYU @ + 36 CMOVE
    \ Total length = key-len + 36
    _WS-VAL-KEYU @ 36 +
    \ SHA-1(concat)
    _WS-ACCEPT-IN SWAP _WS-ACCEPT-SHA SHA1
    \ Base64(sha1-result)
    _WS-ACCEPT-SHA 20 _WS-ACCEPT-B64 32 B64-ENCODE
    _WS-ACCEPT-LEN !
    \ Find Sec-WebSocket-Accept in response headers
    S" Sec-WebSocket-Accept" HDR-FIND
    0= IF 2DROP 0 EXIT THEN
    \ Compare
    _WS-ACCEPT-B64 _WS-ACCEPT-LEN @
    STR-STR= ;

\ Receive buffer for handshake response
CREATE _WS-HS-BUF 2048 ALLOT

\ WS-CONNECT ( url-a url-u -- ctx | 0 )
\   Full WebSocket connection:
\   1. URL-PARSE (expect ws:// or wss://)
\   2. TCP or TLS connect
\   3. Send HTTP Upgrade request with Sec-WebSocket-Key
\   4. Validate 101 Switching Protocols response
: WS-CONNECT  ( url-a url-u -- ctx | 0 )
    WS-CLEAR-ERR
    \ Parse URL
    URL-PARSE 0<> IF
        WS-E-CONNECT WS-FAIL 0 EXIT
    THEN
    \ Verify ws:// or wss://
    URL-SCHEME @ DUP URL-S-WS <> SWAP URL-S-WSS <> AND IF
        WS-E-CONNECT WS-FAIL 0 EXIT
    THEN
    \ Connect
    URL-HOST URL-HOST-LEN @
    URL-PORT @
    URL-SCHEME @ URL-S-WSS =
    HTTP-CONNECT
    DUP 0= IF WS-E-CONNECT WS-FAIL 0 EXIT THEN
    _WS-CTX !
    URL-SCHEME @ URL-S-WSS = _WS-TLS !
    \ Generate key
    _WS-MAKE-KEY 2DROP
    \ Build upgrade request
    HDR-RESET
    S" GET" URL-PATH URL-PATH-LEN @ HDR-METHOD
    URL-HOST URL-HOST-LEN @ HDR-HOST
    S" Upgrade" S" websocket" HDR-ADD
    S" Connection" S" Upgrade" HDR-ADD
    S" Sec-WebSocket-Version" S" 13" HDR-ADD
    S" Sec-WebSocket-Key" _WS-KEY-B64 _WS-KEY-LEN @ HDR-ADD
    HDR-END
    \ Send
    HDR-RESULT HTTP-SEND
    0= IF
        HTTP-DISCONNECT
        WS-E-HANDSHAKE WS-FAIL 0 EXIT
    THEN
    \ Receive response
    _WS-HS-BUF 2048 HTTP-USE-STATIC
    HTTP-RECV-LOOP
    \ Check for 101
    HTTP-RECV-BUF @ HTTP-RECV-LEN @
    2DUP HDR-PARSE-STATUS 101 <> IF
        2DROP HTTP-DISCONNECT
        WS-E-HANDSHAKE WS-FAIL 0 EXIT
    THEN
    \ Validate accept header
    _WS-KEY-B64 _WS-KEY-LEN @ _WS-VALIDATE 0= IF
        2DROP HTTP-DISCONNECT
        WS-E-HANDSHAKE WS-FAIL 0 EXIT
    THEN
    2DROP
    -1 _WS-OPEN !
    _WS-CTX @ ;

\ WS-DISCONNECT ( ctx -- )
\   Send close frame, tear down connection.
: WS-DISCONNECT  ( ctx -- )
    DROP
    _WS-OPEN @ IF
        \ Send close frame (opcode 8, empty payload)
        _WS-CTX @ WS-OP-CLOSE 0 0 WS-FRAME-SEND
        0 _WS-OPEN !
    THEN
    HTTP-DISCONNECT ;

\ =====================================================================
\  Layer 2 — High-Level API
\ =====================================================================

\ WS-SEND-TEXT ( ctx text-a text-u -- )
\   Send a text message.
: WS-SEND-TEXT  ( ctx text-a text-u -- )
    >R >R WS-OP-TEXT R> R> WS-FRAME-SEND ;

\ WS-SEND-BINARY ( ctx data-a data-u -- )
\   Send a binary message.
: WS-SEND-BINARY  ( ctx data-a data-u -- )
    >R >R WS-OP-BINARY R> R> WS-FRAME-SEND ;

\ WS-RECV ( ctx buf max -- opcode len )
\   Receive next complete message (reassembles fragments).
\   opcode: 1=text, 2=binary.  Returns -1 on close.
VARIABLE _WR-TOTAL
VARIABLE _WR-FIRST-OP

: WS-RECV  ( ctx buf max -- opcode len )
    0 _WR-TOTAL !
    >R OVER >R                   \ save buf, max on R
    \ First frame
    R> R> WS-FRAME-RECV          \ ( opcode addr len )
    ROT DUP -1 = IF
        >R 2DROP R> 0 EXIT      \ error
    THEN
    _WR-FIRST-OP !
    _WR-TOTAL +!                 \ accumulate length
    DROP                         \ drop addr
    \ Handle control frames (close)
    _WR-FIRST-OP @ WS-OP-CLOSE = IF
        0 _WS-OPEN !
        -1 0 EXIT
    THEN
    \ If FIN is set, we're done
    _WS-RX-FIN @ IF
        _WR-FIRST-OP @ _WR-TOTAL @ EXIT
    THEN
    \ Continuation frames
    BEGIN
        _WS-RX-FIN @ 0=
    WHILE
        _WS-CTX @
        2 PICK _WR-TOTAL @ +    \ buf + total (append position)
        3 PICK _WR-TOTAL @ -    \ max - total (remaining space)
        WS-FRAME-RECV            \ ( opcode addr len )
        ROT -1 = IF
            2DROP -1 0 EXIT
        THEN
        _WR-TOTAL +!
        DROP
    REPEAT
    _WR-FIRST-OP @ _WR-TOTAL @ ;

\ =====================================================================
\  Concurrency Guard
\ =====================================================================
\
\ WS-CONNECT, WS-DISCONNECT, WS-SEND-TEXT, WS-SEND-BINARY, and
\ WS-RECV share module-level VARIABLEs (connection state, SHA-1
\ scratch, frame staging buffers).  A GUARD-BLOCKING serialises all
\ WebSocket operations so a background task cannot corrupt an active
\ session.

GUARD-BLOCKING _wsc-guard

' WS-CONNECT     CONSTANT _wsc-conn-xt
' WS-DISCONNECT  CONSTANT _wsc-disc-xt
' WS-SEND-TEXT   CONSTANT _wsc-stxt-xt
' WS-SEND-BINARY CONSTANT _wsc-sbin-xt
' WS-RECV        CONSTANT _wsc-recv-xt

: WS-CONNECT     ( url-a url-u -- ctx | 0 )
    _wsc-conn-xt _wsc-guard WITH-GUARD ;
: WS-DISCONNECT  ( ctx -- )
    _wsc-disc-xt _wsc-guard WITH-GUARD ;
: WS-SEND-TEXT   ( ctx text-a text-u -- )
    _wsc-stxt-xt _wsc-guard WITH-GUARD ;
: WS-SEND-BINARY ( ctx data-a data-u -- )
    _wsc-sbin-xt _wsc-guard WITH-GUARD ;
: WS-RECV        ( ctx buf max -- opcode len )
    _wsc-recv-xt _wsc-guard WITH-GUARD ;
