\ url.f — URL parsing, encoding, and query strings for KDOS / Megapad-64
\
\ Parses URLs into components: scheme, host, port, path, query, fragment.
\ Provides percent-encoding/decoding (RFC 3986) and query string handling.
\
\ Operates on (addr len) cursor pairs — same model as json.f.
\
\ Prefix: URL-   (public API)
\         _URL-  (internal helpers)
\
\ Load with:   REQUIRE url.f

PROVIDED akashic-url

\ =====================================================================
\  Utility — may already exist; safe to redefine
\ =====================================================================

: /STRING  ( addr len n -- addr+n len-n )
    ROT OVER + -ROT - ;

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE URL-ERR
VARIABLE URL-ABORT-ON-ERROR
0 URL-ERR !
0 URL-ABORT-ON-ERROR !               \ default: soft-fail

1 CONSTANT URL-E-MALFORMED
2 CONSTANT URL-E-UNKNOWN-SCHEME
3 CONSTANT URL-E-OVERFLOW

: URL-FAIL  ( err-code -- )
    URL-ERR !
    URL-ABORT-ON-ERROR @ IF ABORT" URL error" THEN ;

: URL-OK?  ( -- flag )
    URL-ERR @ 0= ;

: URL-CLEAR-ERR  ( -- )
    0 URL-ERR ! ;

\ =====================================================================
\  Layer 0 — Percent Encoding (RFC 3986 §2)
\ =====================================================================
\
\  URL-ENCODE writes percent-encoded output into a caller-provided
\  buffer.  URL-DECODE reverses the process.

\ _URL-HEX-DIGIT ( n -- char )
\   Convert nibble 0-15 to hex character '0'-'9' / 'A'-'F'.
: _URL-HEX-DIGIT  ( n -- char )
    DUP 10 < IF 48 + ELSE 10 - 65 + THEN ;

\ _URL-HEX-VAL ( char -- n | -1 )
\   Convert hex character to nibble.  Returns -1 for invalid.
: _URL-HEX-VAL  ( char -- n )
    DUP 48 >= OVER 57 <= AND IF 48 - EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - EXIT THEN
    DROP -1 ;

\ URL-UNRESERVED? ( c -- flag )
\   RFC 3986 §2.3: ALPHA / DIGIT / '-' / '.' / '_' / '~'
: URL-UNRESERVED?  ( c -- flag )
    DUP 65 >= OVER  90 <= AND IF DROP -1 EXIT THEN   \ A-Z
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN   \ a-z
    DUP 48 >= OVER  57 <= AND IF DROP -1 EXIT THEN   \ 0-9
    DUP 45 = OVER 46 = OR OVER 95 = OR SWAP 126 = OR ;
    \ '-' = 45, '.' = 46, '_' = 95, '~' = 126

\ URL-ENCODE ( src slen dst dmax -- written )
\   Percent-encode src into dst.  Returns bytes written.
\   Characters outside the unreserved set become %XX.
VARIABLE _UE-OUT   \ output pointer
VARIABLE _UE-MAX   \ output capacity
VARIABLE _UE-W     \ bytes written

: URL-ENCODE  ( src slen dst dmax -- written )
    _UE-MAX !  _UE-OUT !  0 _UE-W !
    0 DO                                    ( src )
        DUP I + C@                          ( src c )
        DUP URL-UNRESERVED? IF
            \ Write literal character
            _UE-W @ _UE-MAX @ >= IF
                DROP URL-E-OVERFLOW URL-FAIL
                UNLOOP DROP _UE-W @ EXIT
            THEN
            _UE-OUT @ _UE-W @ + C!
            1 _UE-W +!
        ELSE
            \ Write %XX
            _UE-W @ 3 + _UE-MAX @ > IF
                DROP URL-E-OVERFLOW URL-FAIL
                UNLOOP DROP _UE-W @ EXIT
            THEN
            37 _UE-OUT @ _UE-W @ + C!              \ '%'
            DUP 4 RSHIFT _URL-HEX-DIGIT
            _UE-OUT @ _UE-W @ 1 + + C!             \ high nibble
            15 AND _URL-HEX-DIGIT
            _UE-OUT @ _UE-W @ 2 + + C!             \ low nibble
            3 _UE-W +!
        THEN
    LOOP
    DROP _UE-W @ ;

\ URL-ENCODE-COMPONENT ( src slen dst dmax -- written )
\   Percent-encode for query parameter values.
\   Like URL-ENCODE but also encodes '/' ':' '@' '?' '#' '&' '=' '+'.
VARIABLE _UEC-OUT
VARIABLE _UEC-MAX
VARIABLE _UEC-W

: _URL-COMP-SAFE?  ( c -- flag )
    \ Only unreserved chars minus some that URL-UNRESERVED? allows,
    \ and explicitly excluding / : @ ? # & = +
    DUP URL-UNRESERVED? 0= IF DROP 0 EXIT THEN
    \ unreserved chars are always safe for components
    DROP -1 ;

: URL-ENCODE-COMPONENT  ( src slen dst dmax -- written )
    _UEC-MAX !  _UEC-OUT !  0 _UEC-W !
    0 DO
        DUP I + C@
        DUP _URL-COMP-SAFE? IF
            _UEC-W @ _UEC-MAX @ >= IF
                DROP URL-E-OVERFLOW URL-FAIL
                UNLOOP DROP _UEC-W @ EXIT
            THEN
            _UEC-OUT @ _UEC-W @ + C!
            1 _UEC-W +!
        ELSE
            _UEC-W @ 3 + _UEC-MAX @ > IF
                DROP URL-E-OVERFLOW URL-FAIL
                UNLOOP DROP _UEC-W @ EXIT
            THEN
            37 _UEC-OUT @ _UEC-W @ + C!
            DUP 4 RSHIFT _URL-HEX-DIGIT
            _UEC-OUT @ _UEC-W @ 1 + + C!
            15 AND _URL-HEX-DIGIT
            _UEC-OUT @ _UEC-W @ 2 + + C!
            3 _UEC-W +!
        THEN
    LOOP
    DROP _UEC-W @ ;

\ URL-DECODE ( src slen dst dmax -- written )
\   Decode percent-encoded string.  %XX → byte.
VARIABLE _UD-OUT
VARIABLE _UD-MAX
VARIABLE _UD-W
VARIABLE _UD-SRC

: URL-DECODE  ( src slen dst dmax -- written )
    _UD-MAX !  _UD-OUT !  0 _UD-W !
    BEGIN
        DUP 0>
    WHILE
        _UD-W @ _UD-MAX @ >= IF
            URL-E-OVERFLOW URL-FAIL  2DROP _UD-W @ EXIT
        THEN
        OVER C@ DUP 37 = IF                \ '%'
            DROP
            DUP 3 < IF
                \ Malformed: not enough chars after %
                URL-E-MALFORMED URL-FAIL  2DROP _UD-W @ EXIT
            THEN
            OVER _UD-SRC !                  \ save src ptr
            _UD-SRC @ 1 + C@ _URL-HEX-VAL  ( src len hi )
            DUP -1 = IF
                DROP URL-E-MALFORMED URL-FAIL  2DROP _UD-W @ EXIT
            THEN
            _UD-SRC @ 2 + C@ _URL-HEX-VAL  ( src len hi lo )
            DUP -1 = IF
                DROP DROP URL-E-MALFORMED URL-FAIL  2DROP _UD-W @ EXIT
            THEN
            SWAP 4 LSHIFT OR               ( src len byte )
            _UD-OUT @ _UD-W @ + C!
            1 _UD-W +!
            SWAP 3 + SWAP 3 -              \ advance past %XX
        ELSE DUP 43 = IF                   \ '+' → space (form encoding)
            DROP
            32 _UD-OUT @ _UD-W @ + C!
            1 _UD-W +!
            SWAP 1 + SWAP 1 -
        ELSE
            _UD-OUT @ _UD-W @ + C!
            1 _UD-W +!
            SWAP 1 + SWAP 1 -
        THEN THEN
    REPEAT
    2DROP _UD-W @ ;

\ =====================================================================
\  Layer 1 — URL Parsing
\ =====================================================================
\
\  Parses a URL into component variables.  Generalised from the
\  tools.f URL-PARSE implementation.

\ Scheme constants
 0 CONSTANT URL-S-HTTP
 1 CONSTANT URL-S-HTTPS
 2 CONSTANT URL-S-FTP
 3 CONSTANT URL-S-FTPS
 4 CONSTANT URL-S-TFTP
 5 CONSTANT URL-S-GOPHER
 6 CONSTANT URL-S-RABBIT
 7 CONSTANT URL-S-IRC
 8 CONSTANT URL-S-IRCS
 9 CONSTANT URL-S-SMTP
10 CONSTANT URL-S-NTP
11 CONSTANT URL-S-WS
12 CONSTANT URL-S-WSS

\ Component storage
VARIABLE URL-SCHEME            \ scheme constant (URL-S-HTTP etc.)

CREATE URL-HOST 64 ALLOT       \ hostname copy buffer
VARIABLE URL-HOST-LEN

VARIABLE URL-PORT              \ numeric port

CREATE URL-PATH 256 ALLOT      \ path copy buffer
VARIABLE URL-PATH-LEN

CREATE URL-QUERY-BUF 256 ALLOT \ query string (after ?)
VARIABLE URL-QUERY-LEN

CREATE URL-FRAG 64 ALLOT       \ fragment (after #)
VARIABLE URL-FRAG-LEN

CREATE URL-USERINFO 64 ALLOT   \ user:pass@ portion
VARIABLE URL-USER-LEN

\ Parser state
VARIABLE _UP-URL               \ URL base address
VARIABLE _UP-END               \ URL length (remaining)
VARIABLE _UP-POS               \ current parse offset

\ _UP-CH ( -- c | -1 )
\   Read next char from URL string, advance position.
: _UP-CH  ( -- c )
    _UP-POS @ _UP-END @ >= IF -1 EXIT THEN
    _UP-URL @ _UP-POS @ + C@
    1 _UP-POS +! ;

\ _UP-PEEK ( -- c | -1 )
\   Peek at next char without advancing.
: _UP-PEEK  ( -- c )
    _UP-POS @ _UP-END @ >= IF -1 EXIT THEN
    _UP-URL @ _UP-POS @ + C@ ;

\ _UP-MATCH ( addr len -- flag )
\   Check if URL at current position starts with addr/len.
: _UP-MATCH  ( addr len -- flag )
    DUP _UP-POS @ + _UP-END @ > IF 2DROP 0 EXIT THEN
    _UP-URL @ _UP-POS @ + SWAP        ( addr url-pos len )
    0 DO
        OVER I + C@  OVER I + C@
        <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ URL-DEFAULT-PORT ( scheme -- port )
\   Return the default port for a scheme constant.
: URL-DEFAULT-PORT  ( scheme -- port )
    DUP URL-S-HTTP   = IF DROP  80 EXIT THEN
    DUP URL-S-HTTPS  = IF DROP 443 EXIT THEN
    DUP URL-S-FTP    = IF DROP  21 EXIT THEN
    DUP URL-S-FTPS   = IF DROP 990 EXIT THEN
    DUP URL-S-TFTP   = IF DROP  69 EXIT THEN
    DUP URL-S-GOPHER = IF DROP  70 EXIT THEN
    DUP URL-S-RABBIT = IF DROP 7443 EXIT THEN
    DUP URL-S-IRC    = IF DROP 6667 EXIT THEN
    DUP URL-S-IRCS   = IF DROP 6697 EXIT THEN
    DUP URL-S-SMTP   = IF DROP  25 EXIT THEN
    DUP URL-S-NTP    = IF DROP 123 EXIT THEN
    DUP URL-S-WS     = IF DROP  80 EXIT THEN
    DUP URL-S-WSS    = IF DROP 443 EXIT THEN
    DROP 0 ;

\ _UP-PARSE-SCHEME ( -- ior )
\   Detect scheme prefix, set URL-SCHEME and advance past "://".
: _UP-PARSE-SCHEME  ( -- ior )
    S" https://"  _UP-MATCH IF URL-S-HTTPS  URL-SCHEME !  8 _UP-POS +! 0 EXIT THEN
    S" http://"   _UP-MATCH IF URL-S-HTTP   URL-SCHEME !  7 _UP-POS +! 0 EXIT THEN
    S" ftps://"   _UP-MATCH IF URL-S-FTPS   URL-SCHEME !  7 _UP-POS +! 0 EXIT THEN
    S" ftp://"    _UP-MATCH IF URL-S-FTP    URL-SCHEME !  6 _UP-POS +! 0 EXIT THEN
    S" tftp://"   _UP-MATCH IF URL-S-TFTP   URL-SCHEME !  7 _UP-POS +! 0 EXIT THEN
    S" gopher://" _UP-MATCH IF URL-S-GOPHER URL-SCHEME ! 9 _UP-POS +! 0 EXIT THEN
    S" rabbit://" _UP-MATCH IF URL-S-RABBIT URL-SCHEME ! 9 _UP-POS +! 0 EXIT THEN
    S" ircs://"   _UP-MATCH IF URL-S-IRCS   URL-SCHEME !  7 _UP-POS +! 0 EXIT THEN
    S" irc://"    _UP-MATCH IF URL-S-IRC    URL-SCHEME !  6 _UP-POS +! 0 EXIT THEN
    S" smtp://"   _UP-MATCH IF URL-S-SMTP   URL-SCHEME !  7 _UP-POS +! 0 EXIT THEN
    S" ntp://"    _UP-MATCH IF URL-S-NTP    URL-SCHEME !  6 _UP-POS +! 0 EXIT THEN
    S" wss://"    _UP-MATCH IF URL-S-WSS    URL-SCHEME !  6 _UP-POS +! 0 EXIT THEN
    S" ws://"     _UP-MATCH IF URL-S-WS     URL-SCHEME !  5 _UP-POS +! 0 EXIT THEN
    URL-E-UNKNOWN-SCHEME URL-FAIL -1 ;

\ _UP-PARSE-HOST-PORT ( -- )
\   Parse hostname, optional port, from authority section.
\   Stops at '/' or '?' or '#' or end.
: _UP-PARSE-HOST-PORT  ( -- )
    0 URL-HOST-LEN !
    BEGIN
        _UP-PEEK DUP -1 <>
        OVER 47 <> AND    \ not '/'
        OVER 63 <> AND    \ not '?'
        OVER 35 <> AND    \ not '#'
    WHILE
        DROP
        _UP-CH DUP 58 = IF                 \ ':'
            DROP
            \ Parse numeric port
            0                               ( accum )
            BEGIN
                _UP-PEEK DUP -1 <>
                OVER 47 <> AND              \ not '/'
                OVER 63 <> AND              \ not '?'
                OVER 35 <> AND              \ not '#'
            WHILE
                DROP _UP-CH 48 -  SWAP 10 * +
            REPEAT
            DROP URL-PORT !
            EXIT
        ELSE
            URL-HOST URL-HOST-LEN @ + C!
            1 URL-HOST-LEN +!
        THEN
    REPEAT
    DROP ;

\ _UP-PARSE-PATH ( -- )
\   Parse path component (up to '?' or '#' or end).
: _UP-PARSE-PATH  ( -- )
    0 URL-PATH-LEN !
    _UP-PEEK 47 <> IF                       \ no leading '/'
        47 URL-PATH C!  1 URL-PATH-LEN !    \ default "/"
        EXIT
    THEN
    BEGIN
        _UP-PEEK DUP -1 <>
        OVER 63 <> AND                       \ not '?'
        OVER 35 <> AND                       \ not '#'
    WHILE
        DROP _UP-CH
        URL-PATH URL-PATH-LEN @ + C!
        1 URL-PATH-LEN +!
    REPEAT
    DROP
    URL-PATH-LEN @ 0= IF
        47 URL-PATH C!  1 URL-PATH-LEN !
    THEN ;

\ _UP-PARSE-QUERY ( -- )
\   Parse query string (after '?', up to '#' or end).
: _UP-PARSE-QUERY  ( -- )
    0 URL-QUERY-LEN !
    _UP-PEEK 63 <> IF EXIT THEN             \ no '?'
    _UP-CH DROP                              \ skip '?'
    BEGIN
        _UP-PEEK DUP -1 <>
        OVER 35 <> AND                       \ not '#'
    WHILE
        DROP _UP-CH
        URL-QUERY-BUF URL-QUERY-LEN @ + C!
        1 URL-QUERY-LEN +!
    REPEAT
    DROP ;

\ _UP-PARSE-FRAG ( -- )
\   Parse fragment (after '#' to end).
: _UP-PARSE-FRAG  ( -- )
    0 URL-FRAG-LEN !
    _UP-PEEK 35 <> IF EXIT THEN             \ no '#'
    _UP-CH DROP                              \ skip '#'
    BEGIN
        _UP-PEEK -1 <>
    WHILE
        _UP-CH
        URL-FRAG URL-FRAG-LEN @ + C!
        1 URL-FRAG-LEN +!
    REPEAT ;

\ URL-PARSE ( addr len -- ior )
\   Parse a URL into component variables.  Returns 0 on success.
: URL-PARSE  ( addr len -- ior )
    URL-CLEAR-ERR
    _UP-END ! _UP-URL ! 0 _UP-POS !

    \ Clear all fields
    URL-HOST 64 0 FILL   0 URL-HOST-LEN !
    URL-PATH 256 0 FILL  0 URL-PATH-LEN !
    URL-QUERY-BUF 256 0 FILL  0 URL-QUERY-LEN !
    URL-FRAG 64 0 FILL   0 URL-FRAG-LEN !
    URL-USERINFO 64 0 FILL  0 URL-USER-LEN !
    0 URL-PORT !

    \ Parse scheme
    _UP-PARSE-SCHEME IF -1 EXIT THEN

    \ Set default port for scheme
    URL-SCHEME @ URL-DEFAULT-PORT URL-PORT !

    \ Parse host[:port]
    _UP-PARSE-HOST-PORT

    \ Parse /path
    _UP-PARSE-PATH

    \ Parse ?query
    _UP-PARSE-QUERY

    \ Parse #fragment
    _UP-PARSE-FRAG

    0 ;

\ =====================================================================
\  Layer 2 — Query String Parsing & Building
\ =====================================================================

\ Query string iteration state — uses variables to avoid stack gymnastics
VARIABLE _QN-SRC              \ current source pointer
VARIABLE _QN-LEN              \ remaining source length

CREATE _QN-KEY 128 ALLOT
VARIABLE _QN-KLEN
CREATE _QN-VAL 128 ALLOT
VARIABLE _QN-VLEN

\ URL-QUERY-NEXT ( a u -- a' u' key-a key-u val-a val-u flag )
\   Iterate key=value pairs in query string.
\   Handles & and ; separators.  Returns flag -1 found, 0 end.
: URL-QUERY-NEXT  ( a u -- a' u' key-a key-u val-a val-u flag )
    DUP 0= IF
        0 0 0 0 0 EXIT                    \ empty → not-found
    THEN
    _QN-LEN ! _QN-SRC !
    0 _QN-KLEN !  0 _QN-VLEN !
    \ Parse key (up to '=' or '&' or ';' or end)
    BEGIN
        _QN-LEN @ 0> IF
            _QN-SRC @ C@
            DUP 61 <>                      ( char flag )
            OVER 38 <> AND
            OVER 59 <> AND
        ELSE 0 0 THEN                     ( char flag | 0 0 )
    WHILE                                  ( char )
        _QN-KEY _QN-KLEN @ + C!
        1 _QN-KLEN +!
        1 _QN-SRC +!  -1 _QN-LEN +!
    REPEAT
    DROP                                   \ drop char or dummy
    \ Check for '='
    _QN-LEN @ 0> IF
        _QN-SRC @ C@ 61 = IF
            1 _QN-SRC +!  -1 _QN-LEN +!   \ skip '='
            \ Parse value (up to '&' or ';' or end)
            BEGIN
                _QN-LEN @ 0> IF
                    _QN-SRC @ C@
                    DUP 38 <>              ( char flag )
                    OVER 59 <> AND
                ELSE 0 0 THEN
            WHILE
                _QN-VAL _QN-VLEN @ + C!
                1 _QN-VLEN +!
                1 _QN-SRC +!  -1 _QN-LEN +!
            REPEAT
            DROP
        THEN
    THEN
    \ Skip separator if present
    _QN-LEN @ 0> IF
        _QN-SRC @ C@ DUP 38 = SWAP 59 = OR IF
            1 _QN-SRC +!  -1 _QN-LEN +!
        THEN
    THEN
    \ Return results
    _QN-SRC @ _QN-LEN @                   \ remaining string
    _QN-KEY _QN-KLEN @                     \ key
    _QN-VAL _QN-VLEN @                     \ value
    -1 ;                                   \ found flag

\ URL-QUERY-FIND ( a u key-a key-u -- val-a val-u flag )
\   Find a specific query parameter by key name.
VARIABLE _QF-KEY
VARIABLE _QF-KLEN

: URL-QUERY-FIND  ( a u key-a key-u -- val-a val-u flag )
    _QF-KLEN ! _QF-KEY !
    BEGIN
        URL-QUERY-NEXT                    ( a' u' k-a k-u v-a v-u flag )
        DUP 0= IF
            \ no more pairs — clean up & return not-found
            2DROP 2DROP 2DROP 0 0 0 EXIT
        THEN
        DROP                              \ drop flag (known true)
        2>R                               \ save val on R: ( v-a v-u )
        \ compare found key with target key
        _QF-KEY @ _QF-KLEN @ COMPARE 0= IF
            2DROP 2R> -1 EXIT             \ found: drop rest, return val
        THEN
        2R> 2DROP                         \ discard value, continue
    AGAIN ;

\ ── Query builder ──

CREATE _QB-BUF 256 ALLOT
VARIABLE _QB-DST
VARIABLE _QB-MAX
VARIABLE _QB-LEN

CREATE _QB-TMP 128 ALLOT   \ temp buffer for encoding

\ URL-QUERY-BUILD ( dst max -- )
\   Start building a query string.
: URL-QUERY-BUILD  ( dst max -- )
    _QB-MAX ! _QB-DST ! 0 _QB-LEN ! ;

\ URL-QUERY-ADD ( key-a key-u val-a val-u -- )
\   Append "key=value&" (percent-encoded).
: URL-QUERY-ADD  ( key-a key-u val-a val-u -- )
    \ Encode value first (into _QB-TMP)
    _QB-TMP 128 URL-ENCODE-COMPONENT    ( key-a key-u enc-len )
    >R
    \ Encode key
    2DUP _QB-DST @ _QB-LEN @ + _QB-MAX @ _QB-LEN @ -
    URL-ENCODE-COMPONENT                ( key-a key-u k-enc-len ) ( R: v-enc-len )
    _QB-LEN +!
    2DROP
    \ Append '='
    61 _QB-DST @ _QB-LEN @ + C!  1 _QB-LEN +!
    \ Copy encoded value
    _QB-TMP R> DUP >R
    _QB-DST @ _QB-LEN @ + SWAP CMOVE
    R> _QB-LEN +!
    \ Append '&'
    38 _QB-DST @ _QB-LEN @ + C!  1 _QB-LEN +! ;

\ URL-QUERY-RESULT ( -- addr len )
\   Return built query string (strip trailing '&').
: URL-QUERY-RESULT  ( -- addr len )
    _QB-LEN @ 0> IF
        _QB-DST @ _QB-LEN @ + 1 - C@ 38 = IF
            _QB-DST @ _QB-LEN @ 1 -
            EXIT
        THEN
    THEN
    _QB-DST @ _QB-LEN @ ;

\ =====================================================================
\  Layer 3 — URL Building
\ =====================================================================

CREATE _UB-BUF 512 ALLOT
VARIABLE _UB-DST
VARIABLE _UB-MAX
VARIABLE _UB-LEN
VARIABLE _UB-SCHEME

\ URL-BUILD ( dst max -- )
\   Start building a URL.
: URL-BUILD  ( dst max -- )
    _UB-MAX ! _UB-DST ! 0 _UB-LEN ! 0 _UB-SCHEME ! ;

\ _UB-APPEND ( addr len -- )
\   Append string to URL builder.
: _UB-APPEND  ( addr len -- )
    _UB-LEN @ OVER + _UB-MAX @ > IF
        URL-E-OVERFLOW URL-FAIL 2DROP EXIT
    THEN
    DUP >R
    _UB-DST @ _UB-LEN @ + SWAP CMOVE
    R> _UB-LEN +! ;

\ _UB-CHAR ( c -- )
\   Append single character.
: _UB-CHAR  ( c -- )
    _UB-LEN @ _UB-MAX @ >= IF DROP URL-E-OVERFLOW URL-FAIL EXIT THEN
    _UB-DST @ _UB-LEN @ + C!  1 _UB-LEN +! ;

\ URL-BUILD-SCHEME ( scheme-id -- )
\   Append "http://", "https://", etc.
: URL-BUILD-SCHEME  ( scheme-id -- )
    DUP _UB-SCHEME !
    DUP URL-S-HTTP   = IF DROP S" http://"   _UB-APPEND EXIT THEN
    DUP URL-S-HTTPS  = IF DROP S" https://"  _UB-APPEND EXIT THEN
    DUP URL-S-FTP    = IF DROP S" ftp://"    _UB-APPEND EXIT THEN
    DUP URL-S-FTPS   = IF DROP S" ftps://"   _UB-APPEND EXIT THEN
    DUP URL-S-TFTP   = IF DROP S" tftp://"   _UB-APPEND EXIT THEN
    DUP URL-S-GOPHER = IF DROP S" gopher://" _UB-APPEND EXIT THEN
    DUP URL-S-RABBIT = IF DROP S" rabbit://" _UB-APPEND EXIT THEN
    DUP URL-S-IRC    = IF DROP S" irc://"    _UB-APPEND EXIT THEN
    DUP URL-S-IRCS   = IF DROP S" ircs://"   _UB-APPEND EXIT THEN
    DUP URL-S-SMTP   = IF DROP S" smtp://"   _UB-APPEND EXIT THEN
    DUP URL-S-NTP    = IF DROP S" ntp://"    _UB-APPEND EXIT THEN
    DUP URL-S-WS     = IF DROP S" ws://"     _UB-APPEND EXIT THEN
    DUP URL-S-WSS    = IF DROP S" wss://"    _UB-APPEND EXIT THEN
    DROP ;

: URL-BUILD-HOST  ( host-a host-u -- )  _UB-APPEND ;

\ URL-BUILD-PORT ( port -- )
\   Append ":port" — omits if it's the default for current scheme.
CREATE _UBP-TMP 8 ALLOT
VARIABLE _UBP-LEN

: URL-BUILD-PORT  ( port -- )
    DUP _UB-SCHEME @ URL-DEFAULT-PORT = IF DROP EXIT THEN
    58 _UB-CHAR                             \ ':'
    \ Convert number to decimal string
    0 _UBP-LEN !
    DUP 0= IF
        DROP 48 _UB-CHAR EXIT              \ "0"
    THEN
    BEGIN DUP 0> WHILE
        DUP 10 MOD 48 + _UBP-TMP _UBP-LEN @ + C!
        1 _UBP-LEN +!
        10 /
    REPEAT DROP
    \ Reverse and append
    _UBP-LEN @ 0 DO
        _UBP-TMP _UBP-LEN @ 1 - I - + C@ _UB-CHAR
    LOOP ;

: URL-BUILD-PATH   ( path-a path-u -- )   _UB-APPEND ;

: URL-BUILD-QUERY  ( query-a query-u -- )
    DUP 0> IF 63 _UB-CHAR _UB-APPEND ELSE 2DROP THEN ;

: URL-BUILD-FRAG   ( frag-a frag-u -- )
    DUP 0> IF 35 _UB-CHAR _UB-APPEND ELSE 2DROP THEN ;

: URL-BUILD-RESULT  ( -- addr len )
    _UB-DST @ _UB-LEN @ ;
