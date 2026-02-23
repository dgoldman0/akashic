\ aturi.f — AT URI Parser & Builder for KDOS / Megapad-64
\
\ AT URI format: "at://authority/collection/rkey"
\   - authority = DID (did:plc:xxx or did:web:xxx) or handle
\   - collection = NSID (e.g. app.bsky.feed.post)
\   - rkey = record key (optional)
\
\ Delegates generic parsing to uri.f; adds AT-specific path splitting.
\
\ Prefix: ATURI-   (public API)
\         _ATU-    (internal helpers)
\
\ Load with:   REQUIRE aturi.f

REQUIRE string.f
REQUIRE uri.f  

PROVIDED akashic-aturi

\ =====================================================================
\  Storage Buffers  (copied from URI results — stable across calls)
\ =====================================================================

CREATE ATURI-AUTHORITY 64 ALLOT
VARIABLE ATURI-AUTH-LEN

CREATE ATURI-COLLECTION 64 ALLOT
VARIABLE ATURI-COLL-LEN

CREATE ATURI-RKEY 32 ALLOT
VARIABLE ATURI-RKEY-LEN

\ =====================================================================
\  Internal helpers
\ =====================================================================

\ _ATU-COPY ( src len dst max -- actual )
\   Copy min(len, max) bytes from src to dst.
: _ATU-COPY  ( src len dst max -- actual )
    ROT MIN                      \ ( src dst actual )
    DUP 0 ?DO                    \ ( src dst actual )
        2 PICK I + C@            \ src[i]
        2 PICK I + C!            \ dst[i] = src[i]
    LOOP
    NIP NIP ;

\ _ATU-SPLIT-PATH ( addr len -- )
\   Split path (without leading '/') into collection + rkey.
\   Path is "collection/rkey" or "collection" or "".

VARIABLE _ATU-PA
VARIABLE _ATU-PL

: _ATU-SPLIT-PATH  ( addr len -- )
    _ATU-PL ! _ATU-PA !
    0 ATURI-COLL-LEN !  0 ATURI-RKEY-LEN !
    _ATU-PL @ 0= IF EXIT THEN
    \ Find first '/' in path
    _ATU-PA @ _ATU-PL @ 47 STR-INDEX  \ idx | -1
    DUP 0< IF
        \ No slash: entire path is collection
        DROP
        _ATU-PA @ _ATU-PL @ ATURI-COLLECTION 64 _ATU-COPY
        ATURI-COLL-LEN !
    ELSE
        \ Collection = path[0..idx), rkey = path[idx+1..)
        DUP                           \ idx idx
        _ATU-PA @ SWAP ATURI-COLLECTION 64 _ATU-COPY
        ATURI-COLL-LEN !
        \ rkey
        1+                            \ skip '/'
        _ATU-PA @ OVER +              \ rkey-addr
        _ATU-PL @ ROT -               \ rkey-len
        ATURI-RKEY 32 _ATU-COPY
        ATURI-RKEY-LEN !
    THEN ;

\ =====================================================================
\  ATURI-PARSE
\ =====================================================================

\ ATURI-PARSE ( addr len -- ior )
\   Parse "at://authority/collection/rkey".
\   Returns 0 on success, -1 on failure.
: ATURI-PARSE  ( addr len -- ior )
    0 ATURI-AUTH-LEN !  0 ATURI-COLL-LEN !  0 ATURI-RKEY-LEN !
    \ Delegate to generic URI parser
    URI-PARSE 0<> IF -1 EXIT THEN
    \ Verify scheme is "at"
    URI-SCHEME-L @ 2 <> IF -1 EXIT THEN
    URI-SCHEME-A @ C@ 97 <> IF -1 EXIT THEN      \ 'a'
    URI-SCHEME-A @ 1+ C@ 116 <> IF -1 EXIT THEN   \ 't'
    \ Must have authority
    URI-AUTH-L @ 0= IF -1 EXIT THEN
    \ Copy authority
    URI-AUTH-A @ URI-AUTH-L @ ATURI-AUTHORITY 64 _ATU-COPY
    ATURI-AUTH-LEN !
    \ Split path: skip leading '/' if present
    URI-PATH-A @ URI-PATH-L @
    DUP 0> IF
        OVER C@ 47 = IF
            1- SWAP 1+ SWAP     \ skip leading '/'
        THEN
    THEN
    _ATU-SPLIT-PATH
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
