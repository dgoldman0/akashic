\ =====================================================================
\  page-snapshot.f - bounded deterministic watched-page normalization
\ =====================================================================
\  A page snapshot owns a normalized UTF-8 text projection and identity
\  evidence for one admitted, bounded response.  It deliberately does not
\  own the raw response.  HTML is scanned with a fixed-depth tag stack; no
\  DOM is allocated and there is no script execution or active-content path.
\
\  Public API:
\    STREAMS-PAGE-SNAPSHOT-INIT       ( snapshot -- )
\    STREAMS-PAGE-NORMALIZE
\      ( raw-a raw-u media-a media-u snapshot -- status )
\    STREAMS-PAGE-SNAPSHOT-VALID?     ( snapshot -- flag )
\    STREAMS-PAGE-SNAPSHOT-MEDIA@     ( snapshot -- media )
\    STREAMS-PAGE-SNAPSHOT-MEDIA$     ( snapshot -- media-a media-u )
\    STREAMS-PAGE-SNAPSHOT-RAW-SIZE@  ( snapshot -- raw-u )
\    STREAMS-PAGE-SNAPSHOT-TEXT$      ( snapshot -- text-a text-u )
\    STREAMS-PAGE-SNAPSHOT-RAW-DIGEST ( snapshot -- digest-a )
\    STREAMS-PAGE-SNAPSHOT-NORMALIZED-DIGEST
\                                      ( snapshot -- digest-a )
\
\  MEDIA must be exactly "text/plain" or "text/html" (ASCII case is
\  ignored; parameters are intentionally unsupported).  RAW is limited to
\  STREAMS-PAGE-RAW-MAX bytes and must be valid UTF-8.  ASCII whitespace is
\  folded to one U+0020 and trimmed; all other UTF-8 bytes are preserved.
\
\  The HTML subset accepts ordinary start/end tags, quoted attributes,
\  void tags, comments, and a doctype.  It removes script, style, nav,
\  header, footer, and aside subtrees.  The five XML entities, nbsp, and
\  valid numeric Unicode scalar references are decoded.  Other named
\  entities return SPAGE-S-UNSUPPORTED; malformed references or markup
\  return SPAGE-S-INVALID.
\
\  NORMALIZE is transactional with respect to SNAPSHOT: all validation,
\  extraction, and hashing occur in private bounded storage, followed by a
\  single commit.  Every non-OK status leaves SNAPSHOT byte-for-byte
\  unchanged.  VALID? verifies the model seal and normalized digest; it does
\  not claim that a digest authenticates or makes source content trustworthy.
\ =====================================================================

PROVIDED akashic-tui-streams-page-snapshot

REQUIRE ../../../text/utf8.f
REQUIRE ../../../math/sha3.f
REQUIRE ../../../concurrency/guard.f

\ =====================================================================
\  Public bounds, media discriminators, and exact statuses
\ =====================================================================

131072 CONSTANT STREAMS-PAGE-RAW-MAX
  8192 CONSTANT STREAMS-PAGE-TEXT-MAX

1 CONSTANT SPAGE-MEDIA-TEXT-PLAIN
2 CONSTANT SPAGE-MEDIA-TEXT-HTML

0 CONSTANT SPAGE-S-OK
1 CONSTANT SPAGE-S-INVALID
2 CONSTANT SPAGE-S-CAPACITY
3 CONSTANT SPAGE-S-UNSUPPORTED

\ =====================================================================
\  Sealed snapshot model
\ =====================================================================

0x535047534E415031 CONSTANT _SPAGE-MAGIC  \ "SPGSNAP1"
1 CONSTANT STREAMS-PAGE-SNAPSHOT-V1

  0 CONSTANT _SPG-MAGIC
  8 CONSTANT _SPG-VERSION
 16 CONSTANT _SPG-MEDIA
 24 CONSTANT _SPG-RAW-SIZE
 32 CONSTANT _SPG-TEXT-SIZE
 40 CONSTANT _SPG-FLAGS
 48 CONSTANT _SPG-RAW-DIGEST
 80 CONSTANT _SPG-NORMAL-DIGEST
112 CONSTANT _SPG-SEAL
144 CONSTANT _SPG-TEXT

_SPG-TEXT STREAMS-PAGE-TEXT-MAX +
    CONSTANT STREAMS-PAGE-SNAPSHOT-SIZE

: STREAMS-PAGE-SNAPSHOT-INIT  ( snapshot -- )
    ?DUP IF STREAMS-PAGE-SNAPSHOT-SIZE 0 FILL THEN ;

: STREAMS-PAGE-SNAPSHOT-MEDIA@  ( snapshot -- media )
    _SPG-MEDIA + @ ;

: STREAMS-PAGE-SNAPSHOT-MEDIA$  ( snapshot -- media-a media-u )
    STREAMS-PAGE-SNAPSHOT-MEDIA@
    DUP SPAGE-MEDIA-TEXT-PLAIN = IF DROP S" text/plain" EXIT THEN
    SPAGE-MEDIA-TEXT-HTML = IF S" text/html" ELSE 0 0 THEN ;

: STREAMS-PAGE-SNAPSHOT-RAW-SIZE@  ( snapshot -- raw-u )
    _SPG-RAW-SIZE + @ ;

: STREAMS-PAGE-SNAPSHOT-TEXT$  ( snapshot -- text-a text-u )
    DUP _SPG-TEXT + SWAP _SPG-TEXT-SIZE + @ ;

: STREAMS-PAGE-SNAPSHOT-RAW-DIGEST  ( snapshot -- digest-a )
    _SPG-RAW-DIGEST + ;

: STREAMS-PAGE-SNAPSHOT-NORMALIZED-DIGEST  ( snapshot -- digest-a )
    _SPG-NORMAL-DIGEST + ;

\ =====================================================================
\  Shared private candidate and validation storage
\ =====================================================================

CREATE _SPN-CANDIDATE STREAMS-PAGE-SNAPSHOT-SIZE ALLOT
CREATE _SPN-CHECK-NORMAL SHA3-256-LEN ALLOT
CREATE _SPN-CHECK-SEAL   SHA3-256-LEN ALLOT

GUARD _streams-page-normalize-guard

: _SPN-SEAL-HASH  ( snapshot destination -- )
    >R
    SHA3-256-BEGIN
    DUP _SPG-VERSION + _SPG-SEAL _SPG-VERSION - SHA3-256-ADD
    DUP _SPG-TEXT + SWAP _SPG-TEXT-SIZE + @ SHA3-256-ADD
    R> SHA3-256-END ;

VARIABLE _SPV-S

: _STREAMS-PAGE-SNAPSHOT-VALID?  ( snapshot -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _SPV-S !
    DUP _SPG-MAGIC + @ _SPAGE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SPG-VERSION + @ STREAMS-PAGE-SNAPSHOT-V1 <> IF
        DROP 0 EXIT
    THEN
    DUP _SPG-MEDIA + @ DUP SPAGE-MEDIA-TEXT-PLAIN =
        SWAP SPAGE-MEDIA-TEXT-HTML = OR 0= IF DROP 0 EXIT THEN
    DUP _SPG-RAW-SIZE + @ DUP 0< SWAP STREAMS-PAGE-RAW-MAX > OR IF
        DROP 0 EXIT
    THEN
    DUP _SPG-TEXT-SIZE + @ DUP 0< SWAP STREAMS-PAGE-TEXT-MAX > OR IF
        DROP 0 EXIT
    THEN
    DUP _SPG-FLAGS + @ IF DROP 0 EXIT THEN
    DUP _SPG-TEXT + OVER _SPG-TEXT-SIZE + @ UTF8-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP _SPG-TEXT + OVER _SPG-TEXT-SIZE + @ _SPN-CHECK-NORMAL
        SHA3-256-HASH
    DUP _SPG-NORMAL-DIGEST + _SPN-CHECK-NORMAL SHA3-256-COMPARE 0= IF
        DROP 0 EXIT
    THEN
    _SPN-CHECK-SEAL _SPN-SEAL-HASH
    _SPV-S @ _SPG-SEAL + _SPN-CHECK-SEAL SHA3-256-COMPARE ;

' _STREAMS-PAGE-SNAPSHOT-VALID? CONSTANT _spage-valid-q-xt
: STREAMS-PAGE-SNAPSHOT-VALID?  ( snapshot -- flag )
    _spage-valid-q-xt _streams-page-normalize-guard WITH-GUARD ;

\ =====================================================================
\  Small ASCII helpers
\ =====================================================================

: _SPN-ASCII-SPACE?  ( c -- flag )
    DUP 32 = IF DROP -1 EXIT THEN
    9 14 WITHIN ;

: _SPN-LOWER  ( c -- c' )
    DUP 65 91 WITHIN IF 32 + THEN ;

VARIABLE _SPCI-A1
VARIABLE _SPCI-U1
VARIABLE _SPCI-A2
VARIABLE _SPCI-U2

: _SPN-ASCII-CI=  ( a1 u1 a2 u2 -- flag )
    _SPCI-U2 ! _SPCI-A2 ! _SPCI-U1 ! _SPCI-A1 !
    _SPCI-U1 @ _SPCI-U2 @ <> IF 0 EXIT THEN
    _SPCI-U1 @ 0 ?DO
        _SPCI-A1 @ I + C@ _SPN-LOWER
        _SPCI-A2 @ I + C@ _SPN-LOWER <> IF 0 UNLOOP EXIT THEN
    LOOP -1 ;

: _SPN-NAME-CHAR?  ( c -- flag )
    DUP 65 91 WITHIN IF DROP -1 EXIT THEN
    DUP 97 123 WITHIN IF DROP -1 EXIT THEN
    DUP 48 58 WITHIN IF DROP -1 EXIT THEN
    DUP 45 = SWAP 58 = OR ;

: _SPN-NAME-START?  ( c -- flag )
    DUP 65 91 WITHIN SWAP 97 123 WITHIN OR ;

: _SPN-SKIP-NAME?  ( a u -- flag )
    2DUP S" script" _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" style"  _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" nav"    _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" header" _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" footer" _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" aside" _SPN-ASCII-CI= ;

: _SPN-RAW-NAME?  ( a u -- flag )
    2DUP S" script" _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" style" _SPN-ASCII-CI= ;

: _SPN-VOID-NAME?  ( a u -- flag )
    2DUP S" area"   _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" base"   _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" br"     _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" col"    _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" embed"  _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" hr"     _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" img"    _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" input"  _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" link"   _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" meta"   _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" param"  _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" source" _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" track"  _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" wbr" _SPN-ASCII-CI= ;

: _SPN-BLOCK-NAME?  ( a u -- flag )
    2DUP S" address"    _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" article"    _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" aside"      _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" blockquote" _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" body"       _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" br"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" dd"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" div"        _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" dl"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" dt"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" fieldset"   _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" figcaption" _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" figure"     _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" footer"     _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h1"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h2"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h3"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h4"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h5"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" h6"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" header"     _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" hr"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" html"       _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" li"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" main"       _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" nav"        _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" ol"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" p"          _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" pre"        _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" section"    _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" table"      _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" tbody"      _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" td"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" tfoot"      _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" th"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" thead"      _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    2DUP S" tr"         _SPN-ASCII-CI= IF 2DROP -1 EXIT THEN
    S" ul" _SPN-ASCII-CI= ;

\ =====================================================================
\  Normalized output writer
\ =====================================================================

VARIABLE _SPN-OUT-U
VARIABLE _SPN-PENDING-SPACE
VARIABLE _SPN-STATUS

: _SPN-FAIL  ( status -- )
    _SPN-STATUS @ SPAGE-S-OK = IF _SPN-STATUS ! ELSE DROP THEN ;

: _SPN-BOUNDARY  ( -- )
    _SPN-OUT-U @ IF -1 _SPN-PENDING-SPACE ! THEN ;

: _SPN-EMIT-NONSPACE  ( c -- )
    _SPN-STATUS @ IF DROP EXIT THEN
    _SPN-PENDING-SPACE @ _SPN-OUT-U @ 0> AND IF
        _SPN-OUT-U @ STREAMS-PAGE-TEXT-MAX >= IF
            DROP SPAGE-S-CAPACITY _SPN-FAIL EXIT
        THEN
        32 _SPN-CANDIDATE _SPG-TEXT + _SPN-OUT-U @ + C!
        1 _SPN-OUT-U +!
    THEN
    0 _SPN-PENDING-SPACE !
    _SPN-OUT-U @ STREAMS-PAGE-TEXT-MAX >= IF
        DROP SPAGE-S-CAPACITY _SPN-FAIL EXIT
    THEN
    _SPN-CANDIDATE _SPG-TEXT + _SPN-OUT-U @ + C!
    1 _SPN-OUT-U +! ;

: _SPN-EMIT-BYTE  ( c -- )
    DUP _SPN-ASCII-SPACE? IF DROP _SPN-BOUNDARY EXIT THEN
    _SPN-EMIT-NONSPACE ;

VARIABLE _SPN-CP

: _SPN-EMIT-CP  ( cp -- )
    DUP _SPN-CP !
    DUP 0x80 < IF _SPN-EMIT-BYTE EXIT THEN
    DUP 0x800 < IF
        DUP 6 RSHIFT 0xC0 OR _SPN-EMIT-NONSPACE
        0x3F AND 0x80 OR _SPN-EMIT-NONSPACE EXIT
    THEN
    DUP 0x10000 < IF
        DUP 12 RSHIFT 0xE0 OR _SPN-EMIT-NONSPACE
        DUP 6 RSHIFT 0x3F AND 0x80 OR _SPN-EMIT-NONSPACE
        0x3F AND 0x80 OR _SPN-EMIT-NONSPACE EXIT
    THEN
    DUP 18 RSHIFT 0xF0 OR _SPN-EMIT-NONSPACE
    DUP 12 RSHIFT 0x3F AND 0x80 OR _SPN-EMIT-NONSPACE
    DUP 6 RSHIFT 0x3F AND 0x80 OR _SPN-EMIT-NONSPACE
    0x3F AND 0x80 OR _SPN-EMIT-NONSPACE ;

\ =====================================================================
\  Fixed-depth streaming HTML scanner
\ =====================================================================

64 CONSTANT _SPN-TAG-DEPTH-MAX
CREATE _SPN-TAG-A    _SPN-TAG-DEPTH-MAX CELLS ALLOT
CREATE _SPN-TAG-U    _SPN-TAG-DEPTH-MAX CELLS ALLOT
CREATE _SPN-TAG-SKIP _SPN-TAG-DEPTH-MAX CELLS ALLOT

VARIABLE _SPN-A
VARIABLE _SPN-U
VARIABLE _SPN-POS
VARIABLE _SPN-DEPTH
VARIABLE _SPN-SKIP-DEPTH

: _SPN-TAG-A[]     ( index -- a ) CELLS _SPN-TAG-A + ;
: _SPN-TAG-U[]     ( index -- a ) CELLS _SPN-TAG-U + ;
: _SPN-TAG-SKIP[]  ( index -- a ) CELLS _SPN-TAG-SKIP + ;

: _SPN-AT  ( position -- c ) _SPN-A @ + C@ ;

VARIABLE _SPNM-POS
VARIABLE _SPNM-A
VARIABLE _SPNM-U

: _SPN-MATCH-CI?  ( position a u -- flag )
    _SPNM-U ! _SPNM-A ! _SPNM-POS !
    _SPNM-POS @ _SPNM-U @ + _SPN-U @ > IF 0 EXIT THEN
    _SPN-A @ _SPNM-POS @ + _SPNM-U @
    _SPNM-A @ _SPNM-U @ _SPN-ASCII-CI= ;

VARIABLE _SPNP-A
VARIABLE _SPNP-U
VARIABLE _SPNP-SKIP

: _SPN-PUSH  ( name-a name-u own-skip -- )
    _SPNP-SKIP ! _SPNP-U ! _SPNP-A !
    _SPN-DEPTH @ _SPN-TAG-DEPTH-MAX >= IF
        SPAGE-S-CAPACITY _SPN-FAIL EXIT
    THEN
    _SPNP-A @ _SPN-DEPTH @ _SPN-TAG-A[] !
    _SPNP-U @ _SPN-DEPTH @ _SPN-TAG-U[] !
    _SPNP-SKIP @ _SPN-DEPTH @ _SPN-TAG-SKIP[] !
    1 _SPN-DEPTH +!
    _SPNP-SKIP @ IF 1 _SPN-SKIP-DEPTH +! THEN ;

: _SPN-TOP-RAW?  ( -- flag )
    _SPN-DEPTH @ 0= IF 0 EXIT THEN
    _SPN-DEPTH @ 1- DUP _SPN-TAG-A[] @
    SWAP _SPN-TAG-U[] @ _SPN-RAW-NAME? ;

VARIABLE _SPNC-A
VARIABLE _SPNC-U

: _SPN-CLOSE-NAME  ( name-a name-u -- )
    _SPNC-U ! _SPNC-A !
    _SPN-DEPTH @ 0= IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    _SPN-DEPTH @ 1- DUP _SPN-TAG-A[] @ SWAP _SPN-TAG-U[] @
    _SPNC-A @ _SPNC-U @ _SPN-ASCII-CI= 0= IF
        SPAGE-S-INVALID _SPN-FAIL EXIT
    THEN
    -1 _SPN-DEPTH +!
    _SPN-DEPTH @ _SPN-TAG-SKIP[] @ IF -1 _SPN-SKIP-DEPTH +! THEN
    _SPN-SKIP-DEPTH @ 0= IF
        _SPNC-A @ _SPNC-U @ _SPN-BLOCK-NAME? IF _SPN-BOUNDARY THEN
    THEN ;

: _SPN-SKIP-SPACES  ( -- )
    BEGIN _SPN-POS @ _SPN-U @ < WHILE
        _SPN-POS @ _SPN-AT _SPN-ASCII-SPACE? 0= IF EXIT THEN
        1 _SPN-POS +!
    REPEAT ;

\ Find and consume the raw-text element's first syntactically matching close
\ tag.  Script and style bytes are never interpreted as markup or entity
\ references.  Consuming the close here is important: leaving POS at its '<'
\ would cause the outer loop to rediscover the same close indefinitely while
\ the raw-text element remained on top of the stack.
VARIABLE _SPNR-I
VARIABLE _SPNR-AFTER

: _SPN-SKIP-RAW-TEXT  ( -- )
    _SPN-DEPTH @ 0= IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    _SPN-DEPTH @ 1- DUP _SPN-TAG-A[] @ _SPNP-A !
    _SPN-TAG-U[] @ _SPNP-U !
    _SPN-POS @ _SPNR-I !
    BEGIN _SPNR-I @ _SPN-U @ < WHILE
        _SPNR-I @ _SPN-AT 60 =
        _SPNR-I @ 1+ _SPN-U @ < AND IF
            _SPNR-I @ 1+ _SPN-AT 47 = IF
                _SPNR-I @ 2 + _SPNP-A @ _SPNP-U @ _SPN-MATCH-CI? IF
                    _SPNR-I @ 2 + _SPNP-U @ + DUP _SPNR-AFTER !
                    _SPN-U @ < IF
                        _SPNR-AFTER @ _SPN-AT DUP 62 =
                        SWAP _SPN-ASCII-SPACE? OR IF
                            _SPNR-AFTER @ _SPN-POS !
                            _SPN-SKIP-SPACES
                            _SPN-POS @ _SPN-U @ >= IF
                                SPAGE-S-INVALID _SPN-FAIL EXIT
                            THEN
                            _SPN-POS @ _SPN-AT 62 <> IF
                                SPAGE-S-INVALID _SPN-FAIL EXIT
                            THEN
                            1 _SPN-POS +!
                            _SPNP-A @ _SPNP-U @ _SPN-CLOSE-NAME EXIT
                        THEN
                    THEN
                THEN
            THEN
        THEN
        1 _SPNR-I +!
    REPEAT
    SPAGE-S-INVALID _SPN-FAIL ;

VARIABLE _SPNT-NAME-A
VARIABLE _SPNT-NAME-U
VARIABLE _SPNT-QUOTE
VARIABLE _SPNT-LAST-NONSPACE
VARIABLE _SPNT-SELF-CLOSE

: _SPN-PARSE-NAME  ( -- )
    _SPN-POS @ _SPN-U @ >= IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    _SPN-POS @ _SPN-AT _SPN-NAME-START? 0= IF
        SPAGE-S-INVALID _SPN-FAIL EXIT
    THEN
    _SPN-A @ _SPN-POS @ + _SPNT-NAME-A !
    0 _SPNT-NAME-U !
    BEGIN _SPN-POS @ _SPN-U @ < WHILE
        _SPN-POS @ _SPN-AT _SPN-NAME-CHAR? 0= IF EXIT THEN
        1 _SPN-POS +! 1 _SPNT-NAME-U +!
    REPEAT ;

\ Consume attributes through a quote-aware '>'.  Unquoted '<' and an
\ unterminated quote are malformed.  SELF-CLOSE records a final slash.
: _SPN-SCAN-TAG-END  ( -- )
    0 _SPNT-QUOTE ! 0 _SPNT-LAST-NONSPACE ! 0 _SPNT-SELF-CLOSE !
    BEGIN _SPN-POS @ _SPN-U @ < WHILE
        _SPN-POS @ _SPN-AT
        _SPNT-QUOTE @ IF
            DUP _SPNT-QUOTE @ = IF 0 _SPNT-QUOTE ! THEN
            DROP 1 _SPN-POS +!
        ELSE
            DUP 34 = OVER 39 = OR IF
                _SPNT-QUOTE ! 1 _SPN-POS +!
            ELSE
                DUP 60 = IF
                    DROP SPAGE-S-INVALID _SPN-FAIL EXIT
                THEN
                DUP 62 = IF
                    DROP _SPNT-LAST-NONSPACE @ 47 =
                        _SPNT-SELF-CLOSE !
                    1 _SPN-POS +! EXIT
                THEN
                DUP _SPN-ASCII-SPACE? 0= IF
                    _SPNT-LAST-NONSPACE !
                ELSE DROP THEN
                1 _SPN-POS +!
            THEN
        THEN
    REPEAT
    SPAGE-S-INVALID _SPN-FAIL ;

: _SPN-PARSE-COMMENT  ( -- )
    4 _SPN-POS +!
    BEGIN _SPN-POS @ 2 + _SPN-U @ < WHILE
        _SPN-POS @ _SPN-AT 45 =
        _SPN-POS @ 1+ _SPN-AT 45 = AND
        _SPN-POS @ 2 + _SPN-AT 62 = AND IF
            3 _SPN-POS +! EXIT
        THEN
        1 _SPN-POS +!
    REPEAT
    SPAGE-S-INVALID _SPN-FAIL ;

: _SPN-PARSE-DECLARATION  ( -- )
    _SPN-POS @ S" <!--" _SPN-MATCH-CI? IF
        _SPN-PARSE-COMMENT EXIT
    THEN
    _SPN-POS @ 2 + S" doctype" _SPN-MATCH-CI? 0= IF
        SPAGE-S-UNSUPPORTED _SPN-FAIL EXIT
    THEN
    _SPN-POS @ 9 + DUP _SPN-U @ >= IF
        DROP SPAGE-S-INVALID _SPN-FAIL EXIT
    THEN
    _SPN-AT DUP 62 = SWAP _SPN-ASCII-SPACE? OR 0= IF
        SPAGE-S-INVALID _SPN-FAIL EXIT
    THEN
    _SPN-POS @ 2 + _SPN-POS !
    _SPN-PARSE-NAME
    _SPN-STATUS @ IF EXIT THEN
    _SPN-SCAN-TAG-END ;

: _SPN-PARSE-CLOSE-TAG  ( -- )
    2 _SPN-POS +!
    _SPN-PARSE-NAME _SPN-STATUS @ IF EXIT THEN
    _SPN-SKIP-SPACES
    _SPN-POS @ _SPN-U @ >= IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    _SPN-POS @ _SPN-AT 62 <> IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    1 _SPN-POS +!
    _SPNT-NAME-A @ _SPNT-NAME-U @ _SPN-CLOSE-NAME ;

: _SPN-PARSE-OPEN-TAG  ( -- )
    1 _SPN-POS +!
    _SPN-PARSE-NAME _SPN-STATUS @ IF EXIT THEN
    _SPN-POS @ _SPN-U @ < IF
        _SPN-POS @ _SPN-AT DUP 62 = OVER 47 = OR
        SWAP _SPN-ASCII-SPACE? OR 0= IF
            SPAGE-S-INVALID _SPN-FAIL EXIT
        THEN
    THEN
    _SPNT-NAME-A @ _SPNT-NAME-U @ _SPN-SKIP-NAME? _SPNP-SKIP !
    _SPN-SKIP-DEPTH @ 0= IF
        _SPNT-NAME-A @ _SPNT-NAME-U @ _SPN-BLOCK-NAME? IF
            _SPN-BOUNDARY
        THEN
    THEN
    _SPN-SCAN-TAG-END _SPN-STATUS @ IF EXIT THEN
    _SPNT-SELF-CLOSE @ IF EXIT THEN
    _SPNT-NAME-A @ _SPNT-NAME-U @ _SPN-VOID-NAME? IF EXIT THEN
    _SPNT-NAME-A @ _SPNT-NAME-U @ _SPNP-SKIP @ _SPN-PUSH ;

: _SPN-PARSE-TAG  ( -- )
    _SPN-POS @ 1+ _SPN-U @ >= IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    _SPN-POS @ 1+ _SPN-AT
    DUP 33 = IF DROP _SPN-PARSE-DECLARATION EXIT THEN
    DUP 47 = IF DROP _SPN-PARSE-CLOSE-TAG EXIT THEN
    DUP 63 = IF DROP SPAGE-S-UNSUPPORTED _SPN-FAIL EXIT THEN
    DROP _SPN-PARSE-OPEN-TAG ;

\ =====================================================================
\  HTML entity decoding
\ =====================================================================

VARIABLE _SPNE-A
VARIABLE _SPNE-U
VARIABLE _SPNE-I
VARIABLE _SPNE-BASE
VARIABLE _SPNE-VALUE
VARIABLE _SPNE-DIGIT
VARIABLE _SPNE-END

: _SPN-ENTITY=  ( a u literal-a literal-u -- flag )
    COMPARE 0= ;

: _SPN-HEX-DIGIT  ( c -- digit valid? )
    DUP 48 58 WITHIN IF 48 - -1 EXIT THEN
    DUP 65 71 WITHIN IF 55 - -1 EXIT THEN
    DUP 97 103 WITHIN IF 87 - -1 EXIT THEN
    DROP 0 0 ;

: _SPN-DEC-DIGIT  ( c -- digit valid? )
    DUP 48 58 WITHIN IF 48 - -1 ELSE DROP 0 0 THEN ;

: _SPN-DECODE-NUMERIC-ENTITY  ( body-a body-u -- )
    _SPNE-U ! _SPNE-A !
    _SPNE-U @ 2 < IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    1 _SPNE-I ! 10 _SPNE-BASE !
    _SPNE-A @ 1+ C@ DUP 120 = SWAP 88 = OR IF
        16 _SPNE-BASE ! 2 _SPNE-I !
    THEN
    _SPNE-I @ _SPNE-U @ >= IF SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    0 _SPNE-VALUE !
    BEGIN _SPNE-I @ _SPNE-U @ < WHILE
        _SPNE-A @ _SPNE-I @ + C@
        _SPNE-BASE @ 16 = IF _SPN-HEX-DIGIT ELSE _SPN-DEC-DIGIT THEN
        0= IF DROP SPAGE-S-INVALID _SPN-FAIL EXIT THEN
        _SPNE-DIGIT !
        _SPNE-VALUE @ _SPNE-BASE @ * _SPNE-DIGIT @ +
        DUP 0x10FFFF > IF DROP SPAGE-S-INVALID _SPN-FAIL EXIT THEN
        _SPNE-VALUE ! 1 _SPNE-I +!
    REPEAT
    _SPNE-VALUE @ DUP 0= IF DROP SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    DUP 0xD800 0xE000 WITHIN IF DROP SPAGE-S-INVALID _SPN-FAIL EXIT THEN
    _SPN-EMIT-CP ;

: _SPN-DECODE-NAMED-ENTITY  ( body-a body-u -- )
    2DUP S" amp"  _SPN-ENTITY= IF 2DROP 38 _SPN-EMIT-BYTE EXIT THEN
    2DUP S" lt"   _SPN-ENTITY= IF 2DROP 60 _SPN-EMIT-BYTE EXIT THEN
    2DUP S" gt"   _SPN-ENTITY= IF 2DROP 62 _SPN-EMIT-BYTE EXIT THEN
    2DUP S" quot" _SPN-ENTITY= IF 2DROP 34 _SPN-EMIT-BYTE EXIT THEN
    2DUP S" apos" _SPN-ENTITY= IF 2DROP 39 _SPN-EMIT-BYTE EXIT THEN
    2DUP S" nbsp" _SPN-ENTITY= IF 2DROP 32 _SPN-EMIT-BYTE EXIT THEN
    2DROP SPAGE-S-UNSUPPORTED _SPN-FAIL ;

\ A semicolon within 32 non-whitespace bytes denotes an entity attempt.
\ Without one, '&' is ordinary literal text (for example, "A & B").
: _SPN-PARSE-ENTITY  ( -- )
    _SPN-POS @ 1+ _SPNE-I !
    BEGIN _SPNE-I @ _SPN-U @ <
          _SPNE-I @ _SPN-POS @ - 33 < AND WHILE
        _SPNE-I @ _SPN-AT DUP 59 = IF
            DROP
            _SPNE-I @ _SPNE-END !
            _SPN-A @ _SPN-POS @ 1+ +
            _SPNE-I @ _SPN-POS @ 1+ - DUP 0= IF
                2DROP SPAGE-S-INVALID _SPN-FAIL EXIT
            THEN
            OVER C@ 35 = IF
                _SPN-DECODE-NUMERIC-ENTITY
            ELSE
                _SPN-DECODE-NAMED-ENTITY
            THEN
            _SPNE-END @ 1+ _SPN-POS ! EXIT
        THEN
        DUP 60 = OVER 38 = OR SWAP _SPN-ASCII-SPACE? OR IF
            38 _SPN-EMIT-BYTE 1 _SPN-POS +! EXIT
        THEN
        1 _SPNE-I +!
    REPEAT
    38 _SPN-EMIT-BYTE 1 _SPN-POS +! ;

\ =====================================================================
\  Media-specific normalizers
\ =====================================================================

: _SPN-NORMALIZE-PLAIN  ( -- )
    0 _SPN-POS !
    BEGIN _SPN-POS @ _SPN-U @ < _SPN-STATUS @ 0= AND WHILE
        _SPN-POS @ _SPN-AT _SPN-EMIT-BYTE
        1 _SPN-POS +!
    REPEAT ;

: _SPN-NORMALIZE-HTML  ( -- )
    0 _SPN-POS ! 0 _SPN-DEPTH ! 0 _SPN-SKIP-DEPTH !
    BEGIN _SPN-POS @ _SPN-U @ < _SPN-STATUS @ 0= AND WHILE
        _SPN-TOP-RAW? IF
            _SPN-SKIP-RAW-TEXT
        ELSE
            _SPN-POS @ _SPN-AT 60 = IF
                _SPN-PARSE-TAG
            ELSE
                _SPN-SKIP-DEPTH @ IF
                    1 _SPN-POS +!
                ELSE
                    _SPN-POS @ _SPN-AT 38 = IF
                        _SPN-PARSE-ENTITY
                    ELSE
                        _SPN-POS @ _SPN-AT _SPN-EMIT-BYTE
                        1 _SPN-POS +!
                    THEN
                THEN
            THEN
        THEN
    REPEAT
    _SPN-STATUS @ 0= _SPN-DEPTH @ 0<> AND IF
        SPAGE-S-INVALID _SPN-FAIL
    THEN ;

\ =====================================================================
\  Transactional public operation
\ =====================================================================

VARIABLE _SPNN-RAW-A
VARIABLE _SPNN-RAW-U
VARIABLE _SPNN-MEDIA-A
VARIABLE _SPNN-MEDIA-U
VARIABLE _SPNN-MEDIA
VARIABLE _SPNN-DEST

: _SPN-CLASSIFY-MEDIA  ( -- status )
    _SPNN-MEDIA-U @ 0= _SPNN-MEDIA-A @ 0= OR IF SPAGE-S-INVALID EXIT THEN
    _SPNN-MEDIA-A @ _SPNN-MEDIA-U @ S" text/plain" _SPN-ASCII-CI= IF
        SPAGE-MEDIA-TEXT-PLAIN _SPNN-MEDIA ! SPAGE-S-OK EXIT
    THEN
    _SPNN-MEDIA-A @ _SPNN-MEDIA-U @ S" text/html" _SPN-ASCII-CI= IF
        SPAGE-MEDIA-TEXT-HTML _SPNN-MEDIA ! SPAGE-S-OK EXIT
    THEN
    SPAGE-S-UNSUPPORTED ;

: _STREAMS-PAGE-NORMALIZE
    ( raw-a raw-u media-a media-u snapshot -- status )
    _SPNN-DEST ! _SPNN-MEDIA-U ! _SPNN-MEDIA-A !
    _SPNN-RAW-U ! _SPNN-RAW-A !
    _SPNN-DEST @ 0= IF SPAGE-S-INVALID EXIT THEN
    _SPNN-RAW-U @ 0< _SPNN-MEDIA-U @ 0< OR IF
        SPAGE-S-INVALID EXIT
    THEN
    _SPNN-RAW-U @ STREAMS-PAGE-RAW-MAX > IF SPAGE-S-CAPACITY EXIT THEN
    _SPNN-RAW-U @ 0> _SPNN-RAW-A @ 0= AND IF SPAGE-S-INVALID EXIT THEN
    _SPNN-MEDIA-U @ 0> _SPNN-MEDIA-A @ 0= AND IF SPAGE-S-INVALID EXIT THEN
    _SPN-CLASSIFY-MEDIA DUP IF EXIT THEN DROP
    _SPNN-RAW-U @ IF
        _SPNN-RAW-A @ _SPNN-RAW-U @ UTF8-VALID? 0= IF
            SPAGE-S-INVALID EXIT
        THEN
    THEN

    _SPN-CANDIDATE STREAMS-PAGE-SNAPSHOT-SIZE 0 FILL
    STREAMS-PAGE-SNAPSHOT-V1 _SPN-CANDIDATE _SPG-VERSION + !
    _SPNN-MEDIA @ _SPN-CANDIDATE _SPG-MEDIA + !
    _SPNN-RAW-U @ _SPN-CANDIDATE _SPG-RAW-SIZE + !
    _SPNN-RAW-A @ _SPNN-RAW-U @ _SPN-CANDIDATE _SPG-RAW-DIGEST +
        SHA3-256-HASH

    0 _SPN-OUT-U ! 0 _SPN-PENDING-SPACE ! SPAGE-S-OK _SPN-STATUS !
    _SPNN-RAW-A @ _SPN-A ! _SPNN-RAW-U @ _SPN-U !
    _SPNN-MEDIA @ SPAGE-MEDIA-TEXT-PLAIN = IF
        _SPN-NORMALIZE-PLAIN
    ELSE
        _SPN-NORMALIZE-HTML
    THEN
    _SPN-STATUS @ DUP IF EXIT THEN DROP

    _SPN-OUT-U @ _SPN-CANDIDATE _SPG-TEXT-SIZE + !
    _SPN-CANDIDATE _SPG-TEXT + _SPN-OUT-U @
        _SPN-CANDIDATE _SPG-NORMAL-DIGEST + SHA3-256-HASH
    _SPN-CANDIDATE DUP _SPG-SEAL + _SPN-SEAL-HASH
    _SPAGE-MAGIC _SPN-CANDIDATE _SPG-MAGIC + !
    _SPN-CANDIDATE _SPNN-DEST @ STREAMS-PAGE-SNAPSHOT-SIZE CMOVE
    SPAGE-S-OK ;

' _STREAMS-PAGE-NORMALIZE CONSTANT _spage-normalize-xt
: STREAMS-PAGE-NORMALIZE
    ( raw-a raw-u media-a media-u snapshot -- status )
    _spage-normalize-xt _streams-page-normalize-guard WITH-GUARD ;
