\ =====================================================================
\  aturi.f - Stateless restricted AT URI syntax and construction
\ =====================================================================
\  This module admits only the normalized Lexicon AT URI shape:
\
\    at://AUTHORITY[/COLLECTION[/RKEY]]
\
\  AUTHORITY is an exact normalized DID or lowercase handle, COLLECTION
\  is an exact NSID whose authority is lowercase, and RKEY is an exact
\  general record key.  Query, fragment, userinfo, ports, empty path
\  segments, trailing slashes, and generic URI resolution are outside this
\  boundary.  Split views synchronously borrow the admitted source.
\
\  Construction validates and measures every component before initializing
\  the caller's CBW workspace or touching its destination.  The destination
\  capacity therefore belongs entirely to the caller and every ordinary
\  failure is all-or-nothing; no module storage or truncation is involved.
\
\  Public API:
\    ATURI-LENGTH-MAX     ( -- 8192 )
\    ATURI-STATUS-VALID?  ( status -- flag )
\    ATURI-VALIDATE       ( source source-u -- status )
\    ATURI-VALID?         ( source source-u -- flag )
\    ATURI-SPLIT
\      ( source source-u -- authority-a authority-u
\                           collection-a collection-u
\                           rkey-a rkey-u status )
\    ATURI-BUILD
\      ( authority-a authority-u collection-a collection-u
\        rkey-a rkey-u destination capacity writer
\        -- written status )
\ =====================================================================

PROVIDED akashic-atproto-aturi

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/buffer-writer.f
REQUIRE did.f
REQUIRE handle.f
REQUIRE nsid.f
REQUIRE record-key.f

\ =====================================================================
\  Public status vocabulary
\ =====================================================================

8192 CONSTANT ATURI-LENGTH-MAX

0  CONSTANT ATURI-S-OK
1  CONSTANT ATURI-S-INVALID
2  CONSTANT ATURI-S-CAPACITY
3  CONSTANT ATURI-S-SYNTAX
4  CONSTANT ATURI-S-AUTHORITY
5  CONSTANT ATURI-S-COLLECTION
6  CONSTANT ATURI-S-RKEY
7  CONSTANT ATURI-S-NORMALIZATION
8  CONSTANT ATURI-S-ALIAS
9  CONSTANT ATURI-S-RANGE
10 CONSTANT ATURI-S-PROTECTED
11 CONSTANT ATURI-S-PLATFORM
12 CONSTANT ATURI-S-INTERNAL

: ATURI-STATUS-VALID?  ( status -- flag )
    DUP ATURI-S-OK >= SWAP ATURI-S-INTERNAL <= AND ;

\ =====================================================================
\  Caller admission and stack helpers
\ =====================================================================

: _ATURI-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP ATURI-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP ATURI-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP ATURI-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP ATURI-S-PLATFORM EXIT
    THEN
    DROP ATURI-S-PLATFORM ;

: _ATURI-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP ATURI-S-INVALID EXIT THEN
    DUP 0= IF
        DROP IF ATURI-S-INVALID ELSE ATURI-S-OK THEN EXIT
    THEN
    OVER 0= IF 2DROP ATURI-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATURI-CALLER>STATUS ;

: _ATURI-DROP6  ( x1 x2 x3 x4 x5 x6 -- )
    2DROP 2DROP 2DROP ;

: _ATURI-DROP8  ( x1 x2 x3 x4 x5 x6 x7 x8 -- )
    2DROP 2DROP 2DROP 2DROP ;

: _ATURI-DROP9  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 -- )
    DROP 2DROP 2DROP 2DROP 2DROP ;

: _ATURI-RETURN6  ( x1 x2 x3 x4 x5 x6 status -- status )
    >R _ATURI-DROP6 R> ;

: _ATURI-RETURN9-ZERO
  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 status -- 0 status )
    >R _ATURI-DROP9 0 R> ;

: _ATURI-/STRING  ( address length prefix-u -- address' length' )
    >R SWAP R@ + SWAP R> - ;

\ =====================================================================
\  Restricted shape scanning
\ =====================================================================

: _ATURI-PREFIX?  ( source source-u -- flag )
    DUP 5 < IF 2DROP 0 EXIT THEN
    OVER C@ [CHAR] a =
    2 PICK 1+ C@ [CHAR] t = AND
    2 PICK 2 + C@ [CHAR] : = AND
    2 PICK 3 + C@ [CHAR] / = AND
    2 PICK 4 + C@ [CHAR] / = AND
    >R 2DROP R> ;

: _ATURI-DID-PREFIX?  ( authority authority-u -- flag )
    DUP 4 < IF 2DROP 0 EXIT THEN
    OVER C@ [CHAR] d =
    2 PICK 1+ C@ [CHAR] i = AND
    2 PICK 2 + C@ [CHAR] d = AND
    2 PICK 3 + C@ [CHAR] : = AND
    >R 2DROP R> ;

: _ATURI-FIND-SLASH  ( source source-u -- index found? )
    0 >R
    BEGIN
        DUP
    WHILE
        OVER C@ [CHAR] / = IF
            2DROP R> -1 EXIT
        THEN
        1 _ATURI-/STRING
        R> 1+ >R
    REPEAT
    2DROP R> 0 ;

\ Stack: path path-u slash-index -- collection-a collection-u
\        rkey-a rkey-u status
: _ATURI-PATH-WITH-RKEY
    >R
    OVER R@
    3 PICK R@ + 1+
    3 PICK R@ - 1-
    2>R 2>R 2DROP
    2R> 2R>
    R> DROP
    ATURI-S-OK ;

: _ATURI-SPLIT-PATH
  ( path path-u -- collection-a collection-u rkey-a rkey-u status )
    DUP 0= IF
        2DROP 0 0 0 0 ATURI-S-SYNTAX EXIT
    THEN
    2DUP _ATURI-FIND-SLASH
    IF
        DUP 0= IF
            DROP 2DROP 0 0 0 0 ATURI-S-SYNTAX EXIT
        THEN
        DUP 2 PICK 1- = IF
            DROP 2DROP 0 0 0 0 ATURI-S-SYNTAX EXIT
        THEN
        _ATURI-PATH-WITH-RKEY
    ELSE
        DROP 0 0 ATURI-S-OK
    THEN ;

\ Stack: authority-and-path-a authority-and-path-u slash-index --
\        authority-a authority-u collection-a collection-u
\        rkey-a rkey-u status
: _ATURI-WITH-PATH
    >R
    OVER R@
    3 PICK R@ + 1+
    3 PICK R@ - 1-
    2>R 2>R 2DROP
    2R> 2R>
    R> DROP
    _ATURI-SPLIT-PATH ;

\ Stack: source source-u -- authority-a authority-u collection-a
\        collection-u rkey-a rkey-u status
: _ATURI-SPLIT-AFTER-PREFIX
    2DUP _ATURI-FIND-SLASH
    IF
        _ATURI-WITH-PATH
    ELSE
        DROP 0 0 0 0 ATURI-S-OK
    THEN ;

\ Stack: source source-u -- authority-a authority-u collection-a
\        collection-u rkey-a rkey-u status
: _ATURI-SPLIT-RAW
    5 _ATURI-/STRING _ATURI-SPLIT-AFTER-PREFIX ;

\ =====================================================================
\  Component validation and normalization
\ =====================================================================

: _ATURI-UPPER?  ( byte -- flag )
    [CHAR] A [CHAR] Z 1+ WITHIN ;

: _ATURI-LOWER?  ( byte -- flag )
    [CHAR] a [CHAR] z 1+ WITHIN ;

: _ATURI-DIGIT?  ( byte -- flag )
    [CHAR] 0 [CHAR] 9 1+ WITHIN ;

: _ATURI-ALPHA?  ( byte -- flag )
    DUP _ATURI-LOWER? IF DROP -1 EXIT THEN
    _ATURI-UPPER? ;

: _ATURI-NO-UPPER?  ( source source-u -- flag )
    BEGIN
        DUP
    WHILE
        OVER C@ _ATURI-UPPER? IF 2DROP 0 EXIT THEN
        1 _ATURI-/STRING
    REPEAT
    2DROP -1 ;

: _ATURI-HEX-UPPER?  ( byte -- flag )
    DUP _ATURI-DIGIT? IF DROP -1 EXIT THEN
    [CHAR] A [CHAR] F 1+ WITHIN ;

: _ATURI-HEX-VALUE  ( byte -- value )
    DUP [CHAR] 9 <= IF
        [CHAR] 0 -
    ELSE
        [CHAR] A - 10 +
    THEN ;

: _ATURI-DID-PLAIN?  ( byte -- flag )
    DUP _ATURI-ALPHA? IF DROP -1 EXIT THEN
    DUP _ATURI-DIGIT? IF DROP -1 EXIT THEN
    DUP [CHAR] . = IF DROP -1 EXIT THEN
    DUP [CHAR] - = IF DROP -1 EXIT THEN
    DUP [CHAR] _ = IF DROP -1 EXIT THEN
    [CHAR] : = ;

\ DID-VALIDATE has already established percent-triplet syntax.  Restricted
\ AT URIs additionally require uppercase hex, no encoding of a byte which
\ the DID grammar admits literally, and no encoded percent introducing a
\ second level of encoding.
: _ATURI-DID-NORMALIZED?  ( source source-u -- flag )
    BEGIN
        DUP
    WHILE
        OVER C@ [CHAR] % = IF
            DUP 3 < IF 2DROP 0 EXIT THEN
            OVER 1+ C@ DUP _ATURI-HEX-UPPER? 0= IF
                DROP 2DROP 0 EXIT
            THEN
            _ATURI-HEX-VALUE 16 *
            2 PICK 2 + C@ DUP _ATURI-HEX-UPPER? 0= IF
                DROP 2DROP DROP 0 EXIT
            THEN
            _ATURI-HEX-VALUE +
            DUP _ATURI-DID-PLAIN?
            SWAP [CHAR] % = OR IF
                2DROP 0 EXIT
            THEN
            3 _ATURI-/STRING
        ELSE
            1 _ATURI-/STRING
        THEN
    REPEAT
    2DROP -1 ;

: _ATURI-DID>STATUS  ( did-status -- status )
    DUP DID-S-OK = IF DROP ATURI-S-OK EXIT THEN
    DUP DID-S-INVALID = IF DROP ATURI-S-INVALID EXIT THEN
    DUP DID-S-CAPACITY = IF DROP ATURI-S-CAPACITY EXIT THEN
    DUP DID-S-RANGE = IF DROP ATURI-S-RANGE EXIT THEN
    DUP DID-S-PROTECTED = IF DROP ATURI-S-PROTECTED EXIT THEN
    DUP DID-S-PLATFORM = IF DROP ATURI-S-PLATFORM EXIT THEN
    DROP ATURI-S-AUTHORITY ;

: _ATURI-HANDLE>STATUS  ( handle-status -- status )
    DUP AT-HANDLE-S-OK = IF DROP ATURI-S-OK EXIT THEN
    DUP AT-HANDLE-S-INVALID = IF DROP ATURI-S-INVALID EXIT THEN
    DUP AT-HANDLE-S-CAPACITY = IF DROP ATURI-S-CAPACITY EXIT THEN
    DUP AT-HANDLE-S-RANGE = IF DROP ATURI-S-RANGE EXIT THEN
    DUP AT-HANDLE-S-PROTECTED = IF DROP ATURI-S-PROTECTED EXIT THEN
    DUP AT-HANDLE-S-PLATFORM = IF DROP ATURI-S-PLATFORM EXIT THEN
    DROP ATURI-S-AUTHORITY ;

: _ATURI-NSID>STATUS  ( nsid-status -- status )
    DUP NSID-S-OK = IF DROP ATURI-S-OK EXIT THEN
    DUP NSID-S-INVALID = IF DROP ATURI-S-INVALID EXIT THEN
    DUP NSID-S-CAPACITY = IF DROP ATURI-S-CAPACITY EXIT THEN
    DUP NSID-S-RANGE = IF DROP ATURI-S-RANGE EXIT THEN
    DUP NSID-S-PROTECTED = IF DROP ATURI-S-PROTECTED EXIT THEN
    DUP NSID-S-PLATFORM = IF DROP ATURI-S-PLATFORM EXIT THEN
    DROP ATURI-S-COLLECTION ;

: _ATURI-RKEY>STATUS  ( rkey-status -- status )
    DUP AT-RKEY-S-OK = IF DROP ATURI-S-OK EXIT THEN
    DUP AT-RKEY-S-INVALID = IF DROP ATURI-S-INVALID EXIT THEN
    DUP AT-RKEY-S-CAPACITY = IF DROP ATURI-S-CAPACITY EXIT THEN
    DUP AT-RKEY-S-RANGE = IF DROP ATURI-S-RANGE EXIT THEN
    DUP AT-RKEY-S-PROTECTED = IF DROP ATURI-S-PROTECTED EXIT THEN
    DUP AT-RKEY-S-PLATFORM = IF DROP ATURI-S-PLATFORM EXIT THEN
    DROP ATURI-S-RKEY ;

: _ATURI-CBW>STATUS  ( cbw-status -- status )
    DUP CBW-S-OK = IF DROP ATURI-S-OK EXIT THEN
    DUP CBW-S-CAPACITY = IF DROP ATURI-S-CAPACITY EXIT THEN
    DROP ATURI-S-INTERNAL ;

: _ATURI-AUTHORITY-STATUS  ( authority authority-u -- status )
    2DUP _ATURI-DID-PREFIX? IF
        2DUP DID-VALIDATE _ATURI-DID>STATUS
        ?DUP IF >R 2DROP R> EXIT THEN
        _ATURI-DID-NORMALIZED? IF
            ATURI-S-OK
        ELSE
            ATURI-S-NORMALIZATION
        THEN
        EXIT
    THEN
    AT-HANDLE-NORMALIZED? _ATURI-HANDLE>STATUS
    ?DUP IF NIP EXIT THEN
    IF ATURI-S-OK ELSE ATURI-S-NORMALIZATION THEN ;

: _ATURI-COLLECTION-STATUS  ( collection collection-u -- status )
    2DUP NSID-CHECK _ATURI-NSID>STATUS
    ?DUP IF >R 2DROP R> EXIT THEN
    NSID-SPLIT _ATURI-NSID>STATUS
    ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    2DROP
    _ATURI-NO-UPPER? IF
        ATURI-S-OK
    ELSE
        ATURI-S-NORMALIZATION
    THEN ;

: _ATURI-RKEY-STATUS  ( rkey rkey-u -- status )
    AT-RKEY-VALIDATE _ATURI-RKEY>STATUS ;

\ Stack: authority-a authority-u collection-a collection-u
\        rkey-a rkey-u -- status
: _ATURI-VALIDATE-PARTS
    5 PICK 5 PICK _ATURI-AUTHORITY-STATUS
    ?DUP IF _ATURI-RETURN6 EXIT THEN
    2 PICK 0= IF
        DUP IF
            ATURI-S-SYNTAX _ATURI-RETURN6 EXIT
        THEN
        _ATURI-DROP6 ATURI-S-OK EXIT
    THEN
    3 PICK 3 PICK _ATURI-COLLECTION-STATUS
    ?DUP IF _ATURI-RETURN6 EXIT THEN
    DUP IF
        1 PICK 1 PICK _ATURI-RKEY-STATUS
        ?DUP IF _ATURI-RETURN6 EXIT THEN
    THEN
    _ATURI-DROP6 ATURI-S-OK ;

\ =====================================================================
\  Public validation and borrowed split
\ =====================================================================

: ATURI-VALIDATE  ( source source-u -- status )
    2DUP _ATURI-SPAN-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP 0= IF 2DROP ATURI-S-SYNTAX EXIT THEN
    DUP ATURI-LENGTH-MAX U> IF
        2DROP ATURI-S-CAPACITY EXIT
    THEN
    2DUP _ATURI-PREFIX? 0= IF
        2DROP ATURI-S-SYNTAX EXIT
    THEN
    _ATURI-SPLIT-RAW
    DUP IF >R _ATURI-DROP6 R> EXIT THEN
    DROP _ATURI-VALIDATE-PARTS ;

: ATURI-VALID?  ( source source-u -- flag )
    ATURI-VALIDATE ATURI-S-OK = ;

\ Stack: source source-u -- authority-a authority-u collection-a
\        collection-u rkey-a rkey-u status
: ATURI-SPLIT
    2DUP ATURI-VALIDATE ?DUP IF
        >R 2DROP 0 0 0 0 0 0 R> EXIT
    THEN
    _ATURI-SPLIT-RAW ;

\ =====================================================================
\  Transactional caller-buffered construction
\ =====================================================================

\ Stack: authority-a authority-u collection-a collection-u
\        rkey-a rkey-u -- length
: _ATURI-MEASURE
    >R DROP >R DROP NIP
    5 +
    R> DUP IF 1+ + ELSE DROP THEN
    R> DUP IF 1+ + ELSE DROP THEN ;

\ Stack: authority-a authority-u collection-a collection-u
\        rkey-a rkey-u target-a target-u -- flag
: _ATURI-SOURCES-OVERLAP?
    7 PICK 7 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        _ATURI-DROP8 -1 EXIT
    THEN
    5 PICK 5 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        _ATURI-DROP8 -1 EXIT
    THEN
    3 PICK 3 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        _ATURI-DROP8 -1 EXIT
    THEN
    _ATURI-DROP8 0 ;

\ Stack: components destination capacity writer -- components
\        destination capacity writer components
: _ATURI-BUILD-PARTS
    8 PICK 8 PICK 8 PICK 8 PICK 8 PICK 8 PICK ;

\ Stack: authority-a authority-u collection-a collection-u
\        rkey-a rkey-u writer -- status
: _ATURI-COMMIT
    >R
    S" at://" R@ CBW-APPEND _ATURI-CBW>STATUS
    ?DUP IF >R _ATURI-DROP6 R> R> DROP EXIT THEN
    5 PICK 5 PICK R@ CBW-APPEND _ATURI-CBW>STATUS
    ?DUP IF >R _ATURI-DROP6 R> R> DROP EXIT THEN
    2 PICK IF
        [CHAR] / R@ CBW-CHAR _ATURI-CBW>STATUS
        ?DUP IF >R _ATURI-DROP6 R> R> DROP EXIT THEN
        3 PICK 3 PICK R@ CBW-APPEND _ATURI-CBW>STATUS
        ?DUP IF >R _ATURI-DROP6 R> R> DROP EXIT THEN
    THEN
    DUP IF
        [CHAR] / R@ CBW-CHAR _ATURI-CBW>STATUS
        ?DUP IF >R _ATURI-DROP6 R> R> DROP EXIT THEN
        1 PICK 1 PICK R@ CBW-APPEND _ATURI-CBW>STATUS
        ?DUP IF >R _ATURI-DROP6 R> R> DROP EXIT THEN
    THEN
    _ATURI-DROP6 R> DROP ATURI-S-OK ;

\ Stack: authority-a authority-u collection-a collection-u
\        rkey-a rkey-u destination capacity writer -- written status
: ATURI-BUILD
    _ATURI-BUILD-PARTS _ATURI-VALIDATE-PARTS
    ?DUP IF _ATURI-RETURN9-ZERO EXIT THEN

    2 PICK 2 PICK _ATURI-SPAN-STATUS ?DUP IF
        _ATURI-RETURN9-ZERO EXIT
    THEN
    DUP CBW-SIZE _ATURI-SPAN-STATUS ?DUP IF
        _ATURI-RETURN9-ZERO EXIT
    THEN

    _ATURI-BUILD-PARTS _ATURI-MEASURE >R
    R@ 2 PICK U> IF
        _ATURI-DROP9 R> DROP 0 ATURI-S-CAPACITY EXIT
    THEN

    2 PICK 2 PICK 2 PICK CBW-SIZE MSPAN-OVERLAP? IF
        _ATURI-DROP9 R> DROP 0 ATURI-S-ALIAS EXIT
    THEN

    _ATURI-BUILD-PARTS 8 PICK R@
    _ATURI-SOURCES-OVERLAP? IF
        _ATURI-DROP9 R> DROP 0 ATURI-S-ALIAS EXIT
    THEN

    _ATURI-BUILD-PARTS 6 PICK CBW-SIZE
    _ATURI-SOURCES-OVERLAP? IF
        _ATURI-DROP9 R> DROP 0 ATURI-S-ALIAS EXIT
    THEN

    2 PICK 2 PICK 2 PICK CBW-INIT _ATURI-CBW>STATUS
    ?DUP IF
        >R _ATURI-DROP9 R> R> DROP 0 SWAP EXIT
    THEN

    _ATURI-BUILD-PARTS 6 PICK _ATURI-COMMIT
    ?DUP IF
        >R _ATURI-DROP9 R> R> DROP 0 SWAP EXIT
    THEN

    _ATURI-DROP9 R> ATURI-S-OK ;
