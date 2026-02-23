\ aturi.f — AT URI Parser & Builder for KDOS / Megapad-64
\
\ AT URI format: "at://authority/collection/rkey"
\   - authority = DID (did:plc:xxx or did:web:xxx) or handle
\   - collection = NSID (e.g. app.bsky.feed.post)
\   - rkey = record key (optional)
\
\ Prefix: ATURI-   (public API)
\         _ATU-    (internal helpers)
\
\ Load with:   REQUIRE aturi.f

PROVIDED akashic-aturi

\ =====================================================================
\  Storage Buffers
\ =====================================================================

CREATE ATURI-AUTHORITY 64 ALLOT
VARIABLE ATURI-AUTH-LEN

CREATE ATURI-COLLECTION 64 ALLOT
VARIABLE ATURI-COLL-LEN

CREATE ATURI-RKEY 32 ALLOT
VARIABLE ATURI-RKEY-LEN

\ =====================================================================
\  Internal State
\ =====================================================================

VARIABLE _ATU-PTR      \ parse pointer
VARIABLE _ATU-END      \ end of input
VARIABLE _ATU-OK       \ parse success flag

\ _ATU-AVAIL ( -- n )
: _ATU-AVAIL  ( -- n )  _ATU-END @ _ATU-PTR @ - ;

\ _ATU-CH ( -- c )  Read one char, advance.
: _ATU-CH  ( -- c )
    _ATU-PTR @ C@  1 _ATU-PTR +! ;

\ _ATU-EXPECT-STR ( addr len -- )  Expect exact string match.
: _ATU-EXPECT-STR  ( addr len -- )
    _ATU-OK @ 0= IF 2DROP EXIT THEN
    0 ?DO
        _ATU-AVAIL 0= IF 0 _ATU-OK ! UNLOOP EXIT THEN
        DUP I + C@ _ATU-CH <> IF
            0 _ATU-OK ! UNLOOP EXIT
        THEN
    LOOP DROP ;

\ _ATU-COPY-UNTIL ( delim dst max -- len )
\   Copy chars from input to dst until delim or end.
\   Returns bytes copied.  Does NOT consume the delimiter.
VARIABLE _ATU-DST
VARIABLE _ATU-DMAX
VARIABLE _ATU-DLEN

: _ATU-COPY-UNTIL  ( delim dst max -- len )
    _ATU-DMAX ! _ATU-DST ! 0 _ATU-DLEN !
    BEGIN
        _ATU-AVAIL 0> IF
            _ATU-PTR @ C@ OVER = IF DROP _ATU-DLEN @ EXIT THEN
            _ATU-DLEN @ _ATU-DMAX @ < IF
                _ATU-PTR @ C@ _ATU-DST @ _ATU-DLEN @ + C!
                1 _ATU-DLEN +!
            THEN
            1 _ATU-PTR +!
            0
        ELSE
            DROP _ATU-DLEN @ -1
        THEN
    UNTIL ;

\ =====================================================================
\  ATURI-PARSE
\ =====================================================================

\ ATURI-PARSE ( addr len -- ior )
\   Parse "at://authority/collection/rkey".
\   Returns 0 on success, -1 on failure.
: ATURI-PARSE  ( addr len -- ior )
    OVER + _ATU-END !  _ATU-PTR !
    -1 _ATU-OK !
    0 ATURI-AUTH-LEN !  0 ATURI-COLL-LEN !  0 ATURI-RKEY-LEN !
    \ Expect "at://"
    S" at://" _ATU-EXPECT-STR
    _ATU-OK @ 0= IF -1 EXIT THEN
    \ Copy authority (until '/')
    47 ATURI-AUTHORITY 64 _ATU-COPY-UNTIL
    ATURI-AUTH-LEN !
    ATURI-AUTH-LEN @ 0= IF -1 EXIT THEN
    \ Skip the '/'
    _ATU-AVAIL 0> IF
        _ATU-PTR @ C@ 47 = IF 1 _ATU-PTR +! THEN
    THEN
    \ Copy collection (until '/')
    _ATU-AVAIL 0> IF
        47 ATURI-COLLECTION 64 _ATU-COPY-UNTIL
        ATURI-COLL-LEN !
        \ Skip the '/'
        _ATU-AVAIL 0> IF
            _ATU-PTR @ C@ 47 = IF 1 _ATU-PTR +! THEN
        THEN
        \ Copy rkey (rest of input)
        _ATU-AVAIL 0> IF
            0 ATURI-RKEY 32 _ATU-COPY-UNTIL
            ATURI-RKEY-LEN !
        THEN
    THEN
    0 ;

\ =====================================================================
\  ATURI-BUILD
\ =====================================================================

VARIABLE _ATU-BPOS     \ build position
VARIABLE _ATU-BDST     \ build destination
VARIABLE _ATU-BMAX     \ build max

\ _ATU-BWRITE ( addr len -- )  Append string to build buffer.
: _ATU-BWRITE  ( addr len -- )
    0 ?DO
        _ATU-BPOS @ _ATU-BMAX @ < IF
            DUP I + C@ _ATU-BDST @ _ATU-BPOS @ + C!
            1 _ATU-BPOS +!
        THEN
    LOOP DROP ;

\ _ATU-BCH ( c -- )  Append one char to build buffer.
: _ATU-BCH  ( c -- )
    _ATU-BPOS @ _ATU-BMAX @ < IF
        _ATU-BDST @ _ATU-BPOS @ + C!
        1 _ATU-BPOS +!
    ELSE DROP THEN ;

\ ATURI-BUILD ( auth-a auth-u coll-a coll-u rkey-a rkey-u dst max -- written )
\   Build AT URI from components.

VARIABLE _ATU-RK-A
VARIABLE _ATU-RK-L
VARIABLE _ATU-CO-A
VARIABLE _ATU-CO-L

: ATURI-BUILD  ( auth-a auth-u coll-a coll-u rkey-a rkey-u dst max -- written )
    _ATU-BMAX ! _ATU-BDST ! 0 _ATU-BPOS !
    _ATU-RK-L ! _ATU-RK-A !
    _ATU-CO-L ! _ATU-CO-A !
    \ auth-a auth-u are now on top of stack
    S" at://" _ATU-BWRITE
    _ATU-BWRITE                  \ authority
    _ATU-CO-L @ 0> IF
        47 _ATU-BCH              \ '/'
        _ATU-CO-A @ _ATU-CO-L @ _ATU-BWRITE   \ collection
    THEN
    _ATU-RK-L @ 0> IF
        47 _ATU-BCH              \ '/'
        _ATU-RK-A @ _ATU-RK-L @ _ATU-BWRITE   \ rkey
    THEN
    _ATU-BPOS @ ;
