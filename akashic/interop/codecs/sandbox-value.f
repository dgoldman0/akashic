\ =====================================================================
\  sandbox-value.f - Interoperability values to and from sandbox values
\ =====================================================================
\  A value enters or leaves a sandbox job only in the sandbox's canonical
\  value codec (docs/sandbox/value-codec.md).  ENCODE writes an owned CV
\  as one canonical root, and DECODE builds an owned CV from one.  NULL,
\  BOOL, INT, BYTES, STRING, LIST and MAP correspond one to one to NULL,
\  BOOL, I64, BYTES, UTF8, LIST and MAP.  F32 and RESOURCE have no
\  sandbox form and never cross.
\
\  ENCODE writes MAP entries in the codec's raw-byte key order whatever
\  their order in the CV.  It refuses duplicate keys, keys that are not
\  strings, and strings that are not exact UTF-8.  MEASURE runs the same
\  checks without writing, so ENCODE fails only on capacity or memory.
\  DECODE validates every header, extent, UTF-8 payload and key order as
\  it builds, and leaves its value NULL when it refuses.
\
\  Both directions check the caller's sealed sandbox value limits as they
\  walk: the input fields when encoding and the result fields when
\  decoding.  So a value fails here, not later in its job, and neither
\  walk recurses deeper than the limits' depth.  The codec proves
\  structure only; schema validation stays with the caller.
\ =====================================================================

PROVIDED akashic-interop-sandbox-value

REQUIRE ../value.f
REQUIRE ../../sandbox/value.f
REQUIRE ../../concurrency/guard.f

0 CONSTANT SBCV-S-OK
1 CONSTANT SBCV-S-INVALID
2 CONSTANT SBCV-S-TYPE
3 CONSTANT SBCV-S-UTF8
4 CONSTANT SBCV-S-KEY
5 CONSTANT SBCV-S-LIMIT
6 CONSTANT SBCV-S-CAPACITY
7 CONSTANT SBCV-S-ALIAS
8 CONSTANT SBCV-S-NOMEM

\ One walk at a time owns this scratch; the public words hold the guard.
VARIABLE _SBCV-STATUS
VARIABLE _SBCV-NODES
VARIABLE _SBCV-BYTES
VARIABLE _SBCV-WIRE
VARIABLE _SBCV-POS
VARIABLE _SBCV-DEPTH-MAX
VARIABLE _SBCV-BLOB-MAX
VARIABLE _SBCV-LIST-MAX
VARIABLE _SBCV-MAP-MAX
VARIABLE _SBCV-NODES-MAX
VARIABLE _SBCV-BYTES-MAX
VARIABLE _SBCV-SORT-A
VARIABLE _SBCV-SORT-M
GUARD _sbcv-guard

: _SBCV-FAIL  ( status -- )
    _SBCV-STATUS @ IF DROP ELSE _SBCV-STATUS ! THEN ;

: _SBCV-OK?  ( -- flag ) _SBCV-STATUS @ 0= ;

: _SBCV-PAD8  ( n -- n' ) 7 + -8 AND ;

\ One occurrence: its expanded value bytes and its own wire bytes.
: _SBCV-CHARGE  ( value-bytes wire-bytes -- )
    _SBCV-WIRE +! _SBCV-BYTES +! 1 _SBCV-NODES +!
    _SBCV-NODES @ _SBCV-NODES-MAX @ >
    _SBCV-BYTES @ _SBCV-BYTES-MAX @ > OR IF SBCV-S-LIMIT _SBCV-FAIL THEN ;

: _SBCV-LIMIT@  ( field limits -- value ) SBOX-VALUE-LIMIT@ DROP ;

\ Loads the walk's limits; NODES and BYTES name the totals it checks.
: _SBCV-BEGIN  ( limits nodes-field bytes-field -- status )
    0 _SBCV-STATUS ! 0 _SBCV-NODES ! 0 _SBCV-BYTES ! 0 _SBCV-WIRE !
    2 PICK SBOX-VALUE-LIMITS-VALID? 0= IF
        2DROP DROP SBCV-S-INVALID EXIT
    THEN
    2 PICK _SBCV-LIMIT@ _SBCV-BYTES-MAX !
    OVER _SBCV-LIMIT@ _SBCV-NODES-MAX !
    >R
    SBOX-VALUE-LIMIT-DEPTH R@ _SBCV-LIMIT@ _SBCV-DEPTH-MAX !
    SBOX-VALUE-LIMIT-BLOB-BYTES R@ _SBCV-LIMIT@ _SBCV-BLOB-MAX !
    SBOX-VALUE-LIMIT-LIST-COUNT R@ _SBCV-LIMIT@ _SBCV-LIST-MAX !
    SBOX-VALUE-LIMIT-MAP-COUNT R> _SBCV-LIMIT@ _SBCV-MAP-MAX !
    SBCV-S-OK ;

\ =====================================================================
\  UTF-8 and key order, exactly as the codec defines them
\ =====================================================================

: _SBCV-IN?  ( x lo hi -- flag )
    2 PICK < 0= -ROT >= AND ;

\ The length of the sequence a lead byte starts and the range of its
\ second byte, or a zero length for a byte that cannot lead.
: _SBCV-LEAD  ( b0 -- n lo hi )
    DUP 0x80 < IF DROP 1 0 0 EXIT THEN
    DUP 0xC2 0xDF _SBCV-IN? IF DROP 2 0x80 0xBF EXIT THEN
    DUP 0xE0 = IF DROP 3 0xA0 0xBF EXIT THEN
    DUP 0xE1 0xEC _SBCV-IN? IF DROP 3 0x80 0xBF EXIT THEN
    DUP 0xED = IF DROP 3 0x80 0x9F EXIT THEN
    DUP 0xEE 0xEF _SBCV-IN? IF DROP 3 0x80 0xBF EXIT THEN
    DUP 0xF0 = IF DROP 4 0x90 0xBF EXIT THEN
    DUP 0xF1 0xF3 _SBCV-IN? IF DROP 4 0x80 0xBF EXIT THEN
    0xF4 = IF 4 0x80 0x8F EXIT THEN
    0 0 0 ;

\ The length of the valid sequence at ADDR within U bytes, or 0.
: _SBCV-SEQ  ( addr u -- n )
    OVER C@ _SBCV-LEAD
    2 PICK 0= IF 2DROP DROP 2DROP 0 EXIT THEN
    2 PICK 4 PICK > IF 2DROP DROP 2DROP 0 EXIT THEN
    2 PICK 1 = IF 2DROP NIP NIP EXIT THEN
    4 PICK 1+ C@ -ROT _SBCV-IN? 0= IF DROP 2DROP 0 EXIT THEN
    DUP 2 ?DO
        2 PICK I + C@ 0xC0 AND 0x80 <> IF DROP 2DROP 0 UNLOOP EXIT THEN
    LOOP
    NIP NIP ;

: _SBCV-UTF8?  ( addr u -- flag )
    BEGIN DUP 0> WHILE
        2DUP _SBCV-SEQ ?DUP 0= IF 2DROP 0 EXIT THEN
        TUCK - >R + R>
    REPEAT
    2DROP -1 ;

\ Unsigned bytes, the shorter of two equal prefixes first: -1, 0 or 1.
: _SBCV-COMPARE  ( a au b bu -- n )
    2 PICK OVER MIN 0 ?DO
        3 PICK I + C@ 2 PICK I + C@
        2DUP <> IF
            U< IF -1 ELSE 1 THEN
            >R 2DROP 2DROP R> UNLOOP EXIT
        THEN
        2DROP
    LOOP
    NIP ROT DROP
    2DUP = IF 2DROP 0 EXIT THEN
    U< IF -1 ELSE 1 THEN ;

\ A blob's bytes, when its length and data are well formed.
: _SBCV-BLOB$  ( value -- addr u flag )
    DUP CV-LEN@ DUP 0< OVER CV-MAX-STRING-LEN > OR IF
        2DROP 0 0 0 EXIT
    THEN
    SWAP CV-DATA@ SWAP
    DUP 0> 2 PICK 0= AND IF 2DROP 0 0 0 EXIT THEN
    -1 ;

: _SBCV-KEY$  ( index map -- key-a key-u )
    CV-MAP-NTH CV-MAP-KEY _SBCV-BLOB$ DROP ;

\ =====================================================================
\  Measuring and encoding an interoperability value
\ =====================================================================

: _SBCV-MEASURE-BLOB  ( value utf8? -- )
    >R _SBCV-BLOB$ 0= IF
        2DROP R> DROP SBCV-S-INVALID _SBCV-FAIL EXIT
    THEN
    R> IF 2DUP _SBCV-UTF8? 0= IF 2DROP SBCV-S-UTF8 _SBCV-FAIL EXIT THEN THEN
    NIP DUP _SBCV-BLOB-MAX @ > IF DROP SBCV-S-LIMIT _SBCV-FAIL EXIT THEN
    DUP _SBCV-PAD8 16 + SWAP 16 + _SBCV-CHARGE ;

: _SBCV-COUNT?  ( count limit -- status )
    OVER 0< 2 PICK CV-MAX-CONTAINER-LEN > OR IF 2DROP SBCV-S-INVALID EXIT THEN
    > IF SBCV-S-LIMIT ELSE SBCV-S-OK THEN ;

: _SBCV-DUPLICATE?  ( map -- flag )
    DUP CV-LEN@ DUP 0 ?DO
        DUP I 1+ ?DO
            J 2 PICK _SBCV-KEY$ I 4 PICK _SBCV-KEY$
            _SBCV-COMPARE 0= IF 2DROP -1 UNLOOP UNLOOP EXIT THEN
        LOOP
    LOOP
    2DROP 0 ;

: _SBCV-MEASURE  ( value depth -- )
    _SBCV-OK? 0= IF 2DROP EXIT THEN
    DUP _SBCV-DEPTH-MAX @ > IF 2DROP SBCV-S-LIMIT _SBCV-FAIL EXIT THEN
    OVER 0= IF 2DROP SBCV-S-INVALID _SBCV-FAIL EXIT THEN
    OVER CV-TYPE@
    DUP CV-T-NULL = IF DROP 2DROP 16 16 _SBCV-CHARGE EXIT THEN
    DUP CV-T-BOOL = OVER CV-T-INT = OR IF
        DROP 2DROP 24 24 _SBCV-CHARGE EXIT
    THEN
    DUP CV-T-STRING = IF DROP DROP -1 _SBCV-MEASURE-BLOB EXIT THEN
    DUP CV-T-BYTES = IF DROP DROP 0 _SBCV-MEASURE-BLOB EXIT THEN
    DUP CV-T-LIST = IF
        DROP OVER CV-LEN@ _SBCV-LIST-MAX @ _SBCV-COUNT? ?DUP IF
            >R 2DROP R> _SBCV-FAIL EXIT
        THEN
        OVER CV-LEN@ 8 * 16 + 16 _SBCV-CHARGE
        OVER CV-LEN@ 0 ?DO
            I 2 PICK CV-LIST-NTH ?DUP 0= IF
                2DROP SBCV-S-INVALID _SBCV-FAIL UNLOOP EXIT
            THEN
            OVER 1+ RECURSE
            _SBCV-OK? 0= IF 2DROP UNLOOP EXIT THEN
        LOOP
        2DROP EXIT
    THEN
    DUP CV-T-MAP = IF
        DROP OVER CV-LEN@ _SBCV-MAP-MAX @ _SBCV-COUNT? ?DUP IF
            >R 2DROP R> _SBCV-FAIL EXIT
        THEN
        OVER CV-LEN@ 16 * 16 + 16 _SBCV-CHARGE
        OVER CV-LEN@ 0 ?DO
            I 2 PICK CV-MAP-NTH ?DUP 0= IF
                2DROP SBCV-S-INVALID _SBCV-FAIL UNLOOP EXIT
            THEN
            DUP CV-MAP-KEY DUP CV-TYPE@ CV-T-STRING <> IF
                2DROP 2DROP SBCV-S-KEY _SBCV-FAIL UNLOOP EXIT
            THEN
            -1 _SBCV-MEASURE-BLOB
            CV-MAP-VALUE OVER 1+ RECURSE
            _SBCV-OK? 0= IF 2DROP UNLOOP EXIT THEN
        LOOP
        OVER _SBCV-DUPLICATE? IF SBCV-S-KEY _SBCV-FAIL THEN
        2DROP EXIT
    THEN
    DUP CV-T-F32 = SWAP CV-T-RESOURCE = OR
    IF SBCV-S-TYPE ELSE SBCV-S-INVALID THEN
    >R 2DROP R> _SBCV-FAIL ;

: _SBCV-STORE  ( u addr n -- )
    0 ?DO OVER 0xFF AND OVER I + C! SWAP 8 RSHIFT SWAP LOOP 2DROP ;

: _SBCV-PUT  ( u n -- )
    _SBCV-POS @ OVER >R SWAP _SBCV-STORE R> _SBCV-POS +! ;

: _SBCV-HEADER  ( tag count payload -- )
    ROT 4 _SBCV-PUT SWAP 4 _SBCV-PUT 8 _SBCV-PUT ;

: _SBCV-PUTS  ( addr u -- )
    _SBCV-POS @ SWAP DUP _SBCV-POS +! CMOVE ;

\ The payload of the aggregate whose header starts at START.
: _SBCV-PATCH  ( start -- )
    _SBCV-POS @ OVER - 16 - SWAP 8 + 8 _SBCV-STORE ;

: _SBCV-EMIT-BLOB  ( value tag -- )
    SWAP _SBCV-BLOB$ DROP ROT 0 2 PICK _SBCV-HEADER _SBCV-PUTS ;

\ Sorts the indices at ARRAY by the raw bytes of the map's keys.
: _SBCV-SORT  ( array n map -- )
    _SBCV-SORT-M ! SWAP _SBCV-SORT-A !
    1 ?DO
        I BEGIN
            DUP 0> IF
                DUP 1- 8 * _SBCV-SORT-A @ + @ _SBCV-SORT-M @ _SBCV-KEY$
                2 PICK 8 * _SBCV-SORT-A @ + @ _SBCV-SORT-M @ _SBCV-KEY$
                _SBCV-COMPARE 0>
            ELSE 0 THEN
        WHILE
            DUP 8 * _SBCV-SORT-A @ + DUP 8 -
            2DUP @ SWAP @ ROT ! SWAP !
            1-
        REPEAT
        DROP
    LOOP ;

\ The value has passed MEASURE, so only memory can fail here.
: _SBCV-EMIT  ( value -- )
    DUP CV-TYPE@
    DUP CV-T-NULL = IF 2DROP SBOX-VALUE-T-NULL 0 0 _SBCV-HEADER EXIT THEN
    DUP CV-T-BOOL = IF
        DROP SBOX-VALUE-T-BOOL 0 8 _SBCV-HEADER
        CV-DATA@ 0<> 8 _SBCV-PUT EXIT
    THEN
    DUP CV-T-INT = IF
        DROP SBOX-VALUE-T-I64 0 8 _SBCV-HEADER
        CV-DATA@ 8 _SBCV-PUT EXIT
    THEN
    DUP CV-T-STRING = IF DROP SBOX-VALUE-T-UTF8 _SBCV-EMIT-BLOB EXIT THEN
    DUP CV-T-BYTES = IF DROP SBOX-VALUE-T-BYTES _SBCV-EMIT-BLOB EXIT THEN
    CV-T-LIST = IF
        _SBCV-POS @ SWAP
        SBOX-VALUE-T-LIST OVER CV-LEN@ 0 _SBCV-HEADER
        DUP CV-LEN@ 0 ?DO I OVER CV-LIST-NTH RECURSE LOOP
        DROP _SBCV-PATCH EXIT
    THEN
    _SBCV-POS @ SWAP
    SBOX-VALUE-T-MAP OVER CV-LEN@ 0 _SBCV-HEADER
    DUP CV-LEN@ ?DUP IF
        DUP 8 * ALLOCATE IF
            2DROP SBCV-S-NOMEM _SBCV-FAIL
        ELSE
            OVER 0 ?DO I OVER I 8 * + ! LOOP
            2DUP SWAP 4 PICK _SBCV-SORT
            SWAP 0 ?DO
                DUP I 8 * + @ 2 PICK CV-MAP-NTH
                DUP CV-MAP-KEY SBOX-VALUE-T-UTF8 _SBCV-EMIT-BLOB
                CV-MAP-VALUE RECURSE
            LOOP
            FREE
        THEN
    THEN
    DROP _SBCV-PATCH ;

: _SBCV-MEASURE-VALUE  ( value limits -- bytes status )
    SBOX-VALUE-LIMIT-INPUT-NODES SBOX-VALUE-LIMIT-INPUT-BYTES _SBCV-BEGIN
    ?DUP IF NIP 0 SWAP EXIT THEN
    1 _SBCV-MEASURE
    _SBCV-OK? IF _SBCV-WIRE @ SBCV-S-OK ELSE 0 _SBCV-STATUS @ THEN ;

: _SBCV-ENCODE-VALUE  ( value limits buffer capacity -- bytes status )
    2SWAP OVER >R _SBCV-MEASURE-VALUE ?DUP IF
        R> DROP >R 2DROP DROP 0 R> EXIT
    THEN
    ( buffer capacity bytes )
    TUCK < IF R> DROP 2DROP 0 SBCV-S-CAPACITY EXIT THEN
    OVER 0= IF R> DROP 2DROP 0 SBCV-S-INVALID EXIT THEN
    2DUP R@ CV-OWNED-SPAN-OVERLAP? IF R> DROP 2DROP 0 SBCV-S-ALIAS EXIT THEN
    SWAP _SBCV-POS !
    R> _SBCV-EMIT
    _SBCV-OK? IF SBCV-S-OK ELSE DROP 0 _SBCV-STATUS @ THEN ;

\ =====================================================================
\  Decoding canonical bytes into an interoperability value
\ =====================================================================

: _SBCV-U@  ( addr n -- u )
    0 SWAP 0 ?DO OVER I + C@ I 8 * LSHIFT OR LOOP NIP ;

\ The header at POS, when its fields are canonical and its payload lies
\ within END.
: _SBCV-HEADER@  ( pos end -- body tag count payload flag )
    OVER 16 + OVER U> IF 2DROP 0 0 0 0 0 EXIT THEN
    OVER 1+ C@ 2 PICK 2 + C@ OR 2 PICK 3 + C@ OR IF
        2DROP 0 0 0 0 0 EXIT
    THEN
    >R
    DUP 16 + SWAP
    DUP C@ SWAP
    DUP 4 + 4 _SBCV-U@ SWAP
    8 + 8 _SBCV-U@
    R> 4 PICK - OVER U< IF 2DROP 2DROP 0 0 0 0 0 EXIT THEN
    -1 ;

\ A NULL, BOOL, I64, BYTES or UTF8 occurrence.
: _SBCV-SCALAR  ( value body tag count payload -- )
    SWAP IF 2DROP 2DROP SBCV-S-INVALID _SBCV-FAIL EXIT THEN
    OVER SBOX-VALUE-T-NULL = IF
        IF 2DROP DROP SBCV-S-INVALID _SBCV-FAIL EXIT THEN
        2DROP CV-NULL! 16 16 _SBCV-CHARGE EXIT
    THEN
    OVER DUP SBOX-VALUE-T-BOOL = SWAP SBOX-VALUE-T-I64 = OR IF
        8 <> IF 2DROP DROP SBCV-S-INVALID _SBCV-FAIL EXIT THEN
        SWAP 8 _SBCV-U@ SWAP
        SBOX-VALUE-T-BOOL = IF
            DUP 0= OVER -1 = OR 0= IF
                2DROP SBCV-S-INVALID _SBCV-FAIL EXIT
            THEN
            SWAP CV-BOOL!
        ELSE
            SWAP CV-INT!
        THEN
        24 24 _SBCV-CHARGE EXIT
    THEN
    OVER DUP SBOX-VALUE-T-BYTES = SWAP SBOX-VALUE-T-UTF8 = OR IF
        DUP _SBCV-BLOB-MAX @ > OVER CV-MAX-STRING-LEN > OR IF
            2DROP 2DROP SBCV-S-LIMIT _SBCV-FAIL EXIT
        THEN
        SWAP SBOX-VALUE-T-UTF8 = IF
            2DUP _SBCV-UTF8? 0= IF 2DROP DROP SBCV-S-UTF8 _SBCV-FAIL EXIT THEN
            DUP >R ROT CV-STRING!
        ELSE
            DUP >R ROT CV-BYTES!
        THEN
        IF R> DROP SBCV-S-NOMEM _SBCV-FAIL EXIT THEN
        R> DUP _SBCV-PAD8 16 + SWAP 16 + _SBCV-CHARGE EXIT
    THEN
    2DROP 2DROP SBCV-S-INVALID _SBCV-FAIL ;

\ One MAP key: a canonical UTF8 occurrence.
: _SBCV-KEY  ( pos end -- key-a key-u next flag )
    _SBCV-HEADER@ 0= IF
        2DROP 2DROP SBCV-S-INVALID _SBCV-FAIL 0 0 0 0 EXIT
    THEN
    ROT SBOX-VALUE-T-UTF8 <> IF
        2DROP DROP SBCV-S-KEY _SBCV-FAIL 0 0 0 0 EXIT
    THEN
    SWAP IF 2DROP SBCV-S-INVALID _SBCV-FAIL 0 0 0 0 EXIT THEN
    DUP _SBCV-BLOB-MAX @ > OVER CV-MAX-STRING-LEN > OR IF
        2DROP SBCV-S-LIMIT _SBCV-FAIL 0 0 0 0 EXIT
    THEN
    2DUP _SBCV-UTF8? 0= IF 2DROP SBCV-S-UTF8 _SBCV-FAIL 0 0 0 0 EXIT THEN
    DUP _SBCV-PAD8 16 + OVER 16 + _SBCV-CHARGE
    2DUP + -1 ;

\ Parses the occurrence at POS into VALUE; NEXT follows it.  On failure
\ the status is set and NEXT is meaningless.
: _SBCV-PARSE  ( pos end value depth -- next )
    _SBCV-OK? 0= IF 2DROP 2DROP 0 EXIT THEN
    DUP _SBCV-DEPTH-MAX @ > IF
        2DROP 2DROP SBCV-S-LIMIT _SBCV-FAIL 0 EXIT
    THEN
    2SWAP _SBCV-HEADER@ 0= IF
        2DROP 2DROP 2DROP SBCV-S-INVALID _SBCV-FAIL 0 EXIT
    THEN
    \ ( value depth body tag count payload )
    3 PICK OVER + >R
    2 PICK DUP SBOX-VALUE-T-LIST <> SWAP SBOX-VALUE-T-MAP <> AND IF
        >R >R >R NIP R> R> R> _SBCV-SCALAR R> EXIT
    THEN
    2 PICK SBOX-VALUE-T-LIST = IF
        DROP NIP
        DUP _SBCV-LIST-MAX @ _SBCV-COUNT? ?DUP IF
            >R 2DROP 2DROP R> _SBCV-FAIL R> DROP 0 EXIT
        THEN
        DUP 8 * 16 + 16 _SBCV-CHARGE
        DUP 4 PICK CV-LIST! IF
            2DROP 2DROP SBCV-S-NOMEM _SBCV-FAIL R> DROP 0 EXIT
        THEN
        R> SWAP >R SWAP R>
        \ ( value depth bend cursor ) for each child
        0 ?DO
            I 4 PICK CV-LIST-NTH
            >R OVER R> 4 PICK 1+ RECURSE
            _SBCV-OK? 0= IF 2DROP 2DROP 0 UNLOOP EXIT THEN
        LOOP
        OVER <> IF DROP 2DROP SBCV-S-INVALID _SBCV-FAIL 0 EXIT THEN
        NIP NIP EXIT
    THEN
    DROP NIP
    DUP _SBCV-MAP-MAX @ _SBCV-COUNT? ?DUP IF
        >R 2DROP 2DROP R> _SBCV-FAIL R> DROP 0 EXIT
    THEN
    DUP 16 * 16 + 16 _SBCV-CHARGE
    DUP 4 PICK CV-MAP! IF
        2DROP 2DROP SBCV-S-NOMEM _SBCV-FAIL R> DROP 0 EXIT
    THEN
    R> SWAP >R SWAP >R 0 0 R> R>
    \ ( value depth bend prev-a prev-u cursor ) for each entry
    0 ?DO
        3 PICK _SBCV-KEY 0= IF
            2DROP DROP 2DROP 2DROP DROP 0 UNLOOP EXIT
        THEN
        \ ( value depth bend prev-a prev-u key-a key-u next )
        I IF
            2 PICK 2 PICK 6 PICK 6 PICK _SBCV-COMPARE 0> 0= IF
                2DROP DROP 2DROP 2DROP DROP
                SBCV-S-KEY _SBCV-FAIL 0 UNLOOP EXIT
            THEN
        THEN
        2 PICK 2 PICK I 10 PICK CV-MAP-SLOT! IF
            2DROP 2DROP DROP 2DROP 2DROP
            SBCV-S-NOMEM _SBCV-FAIL 0 UNLOOP EXIT
        THEN
        \ The key becomes the previous key; the value follows it.
        >R >R 2SWAP 2DROP R> R>
        5 PICK 1+ >R >R 3 PICK R> R> RECURSE
        _SBCV-OK? 0= IF 2DROP 2DROP 2DROP 0 UNLOOP EXIT THEN
    LOOP
    NIP NIP OVER <> IF DROP 2DROP SBCV-S-INVALID _SBCV-FAIL 0 EXIT THEN
    NIP NIP ;

: _SBCV-DECODE-VALUE  ( bytes bytes-u limits value -- status )
    >R SBOX-VALUE-LIMIT-OUTPUT-RESULT-NODES
    SBOX-VALUE-LIMIT-OUTPUT-RESULT-BYTES _SBCV-BEGIN ?DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    R@ 0= OVER 0< OR 2 PICK 0= OR IF 2DROP R> DROP SBCV-S-INVALID EXIT THEN
    OVER + TUCK R@ CV-NULL! R@ 1 _SBCV-PARSE
    \ The root must fill the whole span.
    <> _SBCV-OK? AND IF SBCV-S-INVALID _SBCV-FAIL THEN
    _SBCV-OK? 0= IF R@ CV-NULL! THEN
    R> DROP _SBCV-STATUS @ ;

\ =====================================================================
\  Public codec
\ =====================================================================

: SBCV-MEASURE  ( value limits -- bytes status )
    ['] _SBCV-MEASURE-VALUE _sbcv-guard WITH-GUARD ;

: SBCV-ENCODE  ( value limits buffer capacity -- bytes status )
    ['] _SBCV-ENCODE-VALUE _sbcv-guard WITH-GUARD ;

: SBCV-DECODE  ( bytes bytes-u limits value -- status )
    ['] _SBCV-DECODE-VALUE _sbcv-guard WITH-GUARD ;
