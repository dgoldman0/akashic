\ =====================================================================
\  frame.f - Caller-owned incremental Rabbit frame codec
\ =====================================================================
\  This is the policy-neutral wire boundary for the provisional Rabbit
\  profile.  It owns no socket, session, lane, authority, or application
\  state.  A parser copies at most one frame into a caller-provided byte
\  arena; its descriptor and caller-sized header table are also supplied by
\  the caller.  Published frame slices borrow that arena and remain valid
\  only until RBF-PARSER-RESET or caller mutation of the arena.
\  Descriptor storage is caller-allocated but opaque: only this module may
\  mutate its cells between INIT and RESET.  Envelope validation is not a
\  recovery boundary for arbitrary caller corruption of intermediate state.
\
\  Accepted wire grammar is deliberately exact:
\
\      <nonempty start line> CR LF
\      <Name>: <Value> CR LF       (zero or more)
\      End: CR LF
\      <exactly Length bytes>
\
\  Length is an unsigned decimal byte count.  Its absence means a zero-byte
\  body, so a coalesced next frame is never mistaken for an implicit body.
\  Start lines, header fields, and bodies are strict UTF-8.  Bare CR/LF and
\  other textual controls are rejected; HT is admitted only in bodies and
\  header values.  Transfer and Part are outside this first profile and are
\  rejected rather than half-implemented.  Known core headers are singleton;
\  unknown verbs and headers remain representable as borrowed slices.
\
\  Caller sizing and parser API:
\
\    RBF-PARSER-BYTES  ( header-capacity -- bytes|0 )
\    RBF-PARSER-INIT   ( arena-a arena-u header-capacity parser -- status )
\    RBF-PARSER-RESET  ( parser -- status )
\    RBF-FEED          ( input-a input-u parser -- consumed status )
\    RBF-EOF           ( parser -- status )
\
\  RBF-FEED accepts arbitrary fragmentation.  It stops at the first READY
\  frame and returns the exact consumed prefix, leaving coalesced bytes to the
\  caller.  NEED-MORE is not an error.  Wire errors are latched until RESET;
\  invalid API geometry is returned with consumed=0 without changing parser
\  state.
\
\  The private VARIABLE cells below are operation scratch only.  FEED,
\  lookup, measure, and encode have no callback or yielding edge, so this
\  checkpoint is synchronous and deliberately non-reentrant; all persistent
\  parser/frame state and every retained byte remain caller-owned.  A later
\  concurrency ratchet can move these temporary cells into the descriptor
\  without changing the public layout-independent API.
\
\  READY accessors (all slices are borrowed):
\
\    RBF-START$        ( frame -- a u )
\    RBF-VERB$         ( frame -- a u )
\    RBF-ARGS$         ( frame -- a u )
\    RBF-BODY$         ( frame -- a u )
\    RBF-HEADER-COUNT@ ( frame -- count )
\    RBF-HEADER@       ( index frame -- name-a name-u value-a value-u flag )
\    RBF-HEADER$       ( name-a name-u frame -- value-a value-u flag )
\    RBF-FRAME-VALID?  ( frame -- flag )
\    RBF-DESCRIPTOR-BYTES@ ( frame -- bytes|0 )
\    RBF-CORE-HEADER?  ( name-a name-u -- flag )
\
\  Outbound descriptors use the same caller-sized layout but borrow all
\  supplied slices instead of copying them.  Parser and outbound descriptors
\  carry distinct magics so their mutation/reset lifecycles cannot cross:
\
\    RBF-FRAME-INIT     ( header-capacity frame -- status )
\    RBF-FRAME-RESET    ( frame -- status )
\    RBF-FRAME-START!   ( start-a start-u frame -- status )
\    RBF-FRAME-HEADER+  ( name-a name-u value-a value-u frame -- status )
\    RBF-FRAME-BODY!    ( body-a body-u frame -- status )
\    RBF-FRAME-SEAL     ( frame -- status )
\    RBF-FRAME-MEASURE  ( frame -- exact-u status )
\    RBF-FRAME-ENCODE   ( output-a capacity frame -- written status )
\
\  Add Length before a nonempty body, then seal.  MEASURE and ENCODE accept
\  only READY descriptors and revalidate every borrowed slice.  ENCODE
\  preflights the complete frame, exact size, destination geometry, capacity,
\  and overlap before touching output.  Every failure therefore returns a
\  written count of zero and leaves the destination unchanged.
\ =====================================================================

PROVIDED akashic-rabbit-frame

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/string.f
REQUIRE ../../text/utf8.f

\ =====================================================================
\  Public states and statuses
\ =====================================================================

0 CONSTANT RBF-STATE-START
1 CONSTANT RBF-STATE-HEADERS
2 CONSTANT RBF-STATE-BODY
3 CONSTANT RBF-STATE-READY
4 CONSTANT RBF-STATE-ERROR
5 CONSTANT RBF-STATE-BUILD

\ OK is returned by constructors, mutations, pristine EOF, and successful
\ encode.  NEED-MORE and READY are ordinary parser outcomes.  INVALID covers
\ API geometry or textual grammar; the narrower statuses distinguish arena or
\ header-table exhaustion, UTF-8, CRLF, Length, duplicate singleton, excluded
\ profile features, lifecycle misuse, and partial EOF respectively.
0  CONSTANT RBF-S-OK
1  CONSTANT RBF-S-NEED-MORE
2  CONSTANT RBF-S-READY
3  CONSTANT RBF-S-INVALID
4  CONSTANT RBF-S-CAPACITY
5  CONSTANT RBF-S-UTF8
6  CONSTANT RBF-S-CRLF
7  CONSTANT RBF-S-LENGTH
8  CONSTANT RBF-S-DUPLICATE
9  CONSTANT RBF-S-UNSUPPORTED
10 CONSTANT RBF-S-STATE
11 CONSTANT RBF-S-TRUNCATED

\ =====================================================================
\  Caller-owned descriptor layout
\ =====================================================================

0x31504252 CONSTANT RBF-PARSER-MAGIC  \ "RBP1" in little-endian memory
0x31464252 CONSTANT RBF-FRAME-MAGIC   \ "RBF1" in little-endian memory
1          CONSTANT RBF-ABI-VERSION

  0 CONSTANT _RBF-MAGIC
  8 CONSTANT _RBF-ABI
 16 CONSTANT _RBF-BYTES
 24 CONSTANT _RBF-STATE
 32 CONSTANT _RBF-STATUS
 40 CONSTANT _RBF-BUFFER
 48 CONSTANT _RBF-BUFFER-CAPACITY
 56 CONSTANT _RBF-BUFFER-USED
 64 CONSTANT _RBF-HEADER-CAPACITY
 72 CONSTANT _RBF-HEADER-COUNT
 80 CONSTANT _RBF-LINE-START
 88 CONSTANT _RBF-CR-PENDING
 96 CONSTANT _RBF-LENGTH
104 CONSTANT _RBF-HAVE-LENGTH
112 CONSTANT _RBF-START-A
120 CONSTANT _RBF-START-U
128 CONSTANT _RBF-VERB-A
136 CONSTANT _RBF-VERB-U
144 CONSTANT _RBF-ARGS-A
152 CONSTANT _RBF-ARGS-U
160 CONSTANT _RBF-BODY-A
168 CONSTANT _RBF-BODY-U
176 CONSTANT RBF-DESCRIPTOR-BASE

0  CONSTANT _RBFH-NAME-A
8  CONSTANT _RBFH-NAME-U
16 CONSTANT _RBFH-VALUE-A
24 CONSTANT _RBFH-VALUE-U
32 CONSTANT RBF-HEADER-SIZE

: RBF.MAGIC            ( frame -- a ) _RBF-MAGIC + ;
: RBF.ABI              ( frame -- a ) _RBF-ABI + ;
: RBF.BYTES            ( frame -- a ) _RBF-BYTES + ;
: RBF.STATE            ( frame -- a ) _RBF-STATE + ;
: RBF.STATUS           ( frame -- a ) _RBF-STATUS + ;
: RBF.BUFFER           ( frame -- a ) _RBF-BUFFER + ;
: RBF.BUFFER-CAPACITY  ( frame -- a ) _RBF-BUFFER-CAPACITY + ;
: RBF.BUFFER-USED      ( frame -- a ) _RBF-BUFFER-USED + ;
: RBF.HEADER-CAPACITY  ( frame -- a ) _RBF-HEADER-CAPACITY + ;
: RBF.HEADER-COUNT     ( frame -- a ) _RBF-HEADER-COUNT + ;
: RBF.LINE-START       ( frame -- a ) _RBF-LINE-START + ;
: RBF.CR-PENDING       ( frame -- a ) _RBF-CR-PENDING + ;
: RBF.LENGTH           ( frame -- a ) _RBF-LENGTH + ;
: RBF.HAVE-LENGTH      ( frame -- a ) _RBF-HAVE-LENGTH + ;
: RBF.START-A          ( frame -- a ) _RBF-START-A + ;
: RBF.START-U          ( frame -- a ) _RBF-START-U + ;
: RBF.VERB-A           ( frame -- a ) _RBF-VERB-A + ;
: RBF.VERB-U           ( frame -- a ) _RBF-VERB-U + ;
: RBF.ARGS-A           ( frame -- a ) _RBF-ARGS-A + ;
: RBF.ARGS-U           ( frame -- a ) _RBF-ARGS-U + ;
: RBF.BODY-A           ( frame -- a ) _RBF-BODY-A + ;
: RBF.BODY-U           ( frame -- a ) _RBF-BODY-U + ;

: _RBFH.NAME-A   ( entry -- a ) _RBFH-NAME-A + ;
: _RBFH.NAME-U   ( entry -- a ) _RBFH-NAME-U + ;
: _RBFH.VALUE-A  ( entry -- a ) _RBFH-VALUE-A + ;
: _RBFH.VALUE-U  ( entry -- a ) _RBFH-VALUE-U + ;

0x7FFFFFFFFFFFFFFF RBF-DESCRIPTOR-BASE - RBF-HEADER-SIZE /
    CONSTANT _RBF-HEADER-CAPACITY-MAX

: RBF-PARSER-BYTES  ( header-capacity -- bytes|0 )
    DUP 0< IF DROP 0 EXIT THEN
    DUP _RBF-HEADER-CAPACITY-MAX U> IF DROP 0 EXIT THEN
    RBF-HEADER-SIZE * RBF-DESCRIPTOR-BASE + ;

\ A zero header capacity is valid and admits start+End frames.  Zero from the
\ sizing word means only that the requested count is negative or its inline
\ descriptor byte size cannot be represented as a nonnegative cell length.

: RBF-FRAME-BYTES  ( header-capacity -- bytes|0 )
    RBF-PARSER-BYTES ;

: _RBF-ENTRY  ( index frame -- entry )
    RBF-DESCRIPTOR-BASE + SWAP RBF-HEADER-SIZE * + ;

: _RBF-SPAN-VALID?  ( address length -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RBF-STATE-VALID?  ( state -- flag )
    DUP RBF-STATE-START >= SWAP RBF-STATE-BUILD <= AND ;

: _RBF-STATUS-VALID?  ( status -- flag )
    DUP RBF-S-OK >= SWAP RBF-S-TRUNCATED <= AND ;

VARIABLE _RBFV-P
VARIABLE _RBFV-BYTES
VARIABLE _RBFV-STATE
VARIABLE _RBFV-STATUS
VARIABLE _RBFV-MAGIC

: RBF-DESCRIPTOR-VALID?  ( frame -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP RBF-DESCRIPTOR-BASE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    _RBFV-P !
    _RBFV-P @ RBF.MAGIC @ DUP _RBFV-MAGIC !
    DUP RBF-PARSER-MAGIC = SWAP RBF-FRAME-MAGIC = OR 0= IF 0 EXIT THEN
    _RBFV-P @ RBF.ABI @ RBF-ABI-VERSION <> IF 0 EXIT THEN
    _RBFV-P @ RBF.HEADER-CAPACITY @ DUP 0< IF DROP 0 EXIT THEN
    RBF-PARSER-BYTES DUP 0= IF DROP 0 EXIT THEN _RBFV-BYTES !
    _RBFV-P @ RBF.BYTES @ _RBFV-BYTES @ <> IF 0 EXIT THEN
    _RBFV-P @ _RBFV-BYTES @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RBFV-P @ RBF.BUFFER-CAPACITY @ DUP 0< IF DROP 0 EXIT THEN
    DUP 0> _RBFV-P @ RBF.BUFFER @ 0= AND IF DROP 0 EXIT THEN
    _RBFV-P @ RBF.BUFFER @ SWAP MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RBFV-P @ RBF.BUFFER @ _RBFV-P @ RBF.BUFFER-CAPACITY @
        _RBFV-P @ _RBFV-BYTES @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RBFV-P @ RBF.BUFFER-USED @ DUP 0< IF DROP 0 EXIT THEN
    _RBFV-P @ RBF.BUFFER-CAPACITY @ > IF 0 EXIT THEN
    _RBFV-P @ RBF.HEADER-COUNT @ DUP 0< IF DROP 0 EXIT THEN
    _RBFV-P @ RBF.HEADER-CAPACITY @ > IF 0 EXIT THEN
    _RBFV-P @ RBF.LINE-START @ DUP 0< IF DROP 0 EXIT THEN
    _RBFV-P @ RBF.BUFFER-USED @ > IF 0 EXIT THEN
    _RBFV-P @ RBF.CR-PENDING @ DUP 0= SWAP -1 = OR 0= IF 0 EXIT THEN
    _RBFV-P @ RBF.HAVE-LENGTH @ DUP 0= SWAP -1 = OR 0= IF 0 EXIT THEN
    _RBFV-P @ RBF.LENGTH @ 0< IF 0 EXIT THEN
    _RBFV-P @ RBF.STATE @ DUP _RBFV-STATE !
    _RBF-STATE-VALID? 0= IF 0 EXIT THEN
    _RBFV-P @ RBF.STATUS @ DUP _RBFV-STATUS !
    _RBF-STATUS-VALID? 0= IF 0 EXIT THEN
    _RBFV-MAGIC @ RBF-FRAME-MAGIC = IF
        _RBFV-STATE @ RBF-STATE-BUILD = IF
            _RBFV-STATUS @ RBF-S-OK = EXIT
        THEN
        _RBFV-STATE @ RBF-STATE-READY = IF
            _RBFV-STATUS @ RBF-S-READY = EXIT
        THEN
        0 EXIT
    THEN
    _RBFV-STATE @ RBF-STATE-BUILD = IF 0 EXIT THEN
    _RBFV-STATE @ RBF-STATE-READY = IF
        _RBFV-STATUS @ RBF-S-READY = EXIT
    THEN
    _RBFV-STATE @ RBF-STATE-ERROR = IF
        _RBFV-STATUS @ RBF-S-INVALID >= EXIT
    THEN
    _RBFV-STATUS @ RBF-S-NEED-MORE = ;

: _RBF-PARSER-DESCRIPTOR?  ( descriptor -- flag )
    DUP RBF-DESCRIPTOR-VALID? 0= IF DROP 0 EXIT THEN
    RBF.MAGIC @ RBF-PARSER-MAGIC = ;

: _RBF-FRAME-DESCRIPTOR?  ( descriptor -- flag )
    DUP RBF-DESCRIPTOR-VALID? 0= IF DROP 0 EXIT THEN
    RBF.MAGIC @ RBF-FRAME-MAGIC = ;

: RBF-FRAME-VALID?  ( frame -- flag )
    _RBF-FRAME-DESCRIPTOR? ;

: RBF-DESCRIPTOR-BYTES@  ( frame -- bytes|0 )
    DUP RBF-DESCRIPTOR-VALID? 0= IF DROP 0 EXIT THEN
    RBF.BYTES @ ;

VARIABLE _RBFI-A
VARIABLE _RBFI-U
VARIABLE _RBFI-HCAP
VARIABLE _RBFI-P
VARIABLE _RBFI-BYTES

: RBF-PARSER-INIT  ( arena-a arena-u header-capacity parser -- status )
    _RBFI-P ! _RBFI-HCAP ! _RBFI-U ! _RBFI-A !
    _RBFI-HCAP @ RBF-PARSER-BYTES DUP 0= IF
        DROP RBF-S-INVALID EXIT
    THEN _RBFI-BYTES !
    _RBFI-P @ 0= IF RBF-S-INVALID EXIT THEN
    _RBFI-P @ 7 AND IF RBF-S-INVALID EXIT THEN
    _RBFI-P @ _RBFI-BYTES @ MSPAN-NONWRAPPING? 0= IF
        RBF-S-INVALID EXIT
    THEN
    _RBFI-U @ 0< IF RBF-S-INVALID EXIT THEN
    _RBFI-U @ 0> _RBFI-A @ 0= AND IF RBF-S-INVALID EXIT THEN
    _RBFI-A @ _RBFI-U @ MSPAN-NONWRAPPING? 0= IF
        RBF-S-INVALID EXIT
    THEN
    _RBFI-A @ _RBFI-U @ _RBFI-P @ _RBFI-BYTES @
        MSPAN-OVERLAP? IF RBF-S-INVALID EXIT THEN
    _RBFI-P @ _RBFI-BYTES @ 0 FILL
    RBF-PARSER-MAGIC _RBFI-P @ RBF.MAGIC !
    RBF-ABI-VERSION _RBFI-P @ RBF.ABI !
    _RBFI-BYTES @ _RBFI-P @ RBF.BYTES !
    RBF-STATE-START _RBFI-P @ RBF.STATE !
    RBF-S-NEED-MORE _RBFI-P @ RBF.STATUS !
    _RBFI-A @ _RBFI-P @ RBF.BUFFER !
    _RBFI-U @ _RBFI-P @ RBF.BUFFER-CAPACITY !
    _RBFI-HCAP @ _RBFI-P @ RBF.HEADER-CAPACITY !
    RBF-S-OK ;

: RBF-FRAME-INIT  ( header-capacity frame -- status )
    >R 0 0 ROT R@ RBF-PARSER-INIT
    DUP IF R> DROP EXIT THEN DROP
    RBF-FRAME-MAGIC R@ RBF.MAGIC !
    RBF-STATE-BUILD R@ RBF.STATE !
    RBF-S-OK R@ RBF.STATUS !
    R> DROP RBF-S-OK ;

: _RBF-CLEAR-CONTENT  ( frame -- )
    0 OVER RBF.BUFFER-USED !
    0 OVER RBF.HEADER-COUNT !
    0 OVER RBF.LINE-START !
    0 OVER RBF.CR-PENDING !
    0 OVER RBF.LENGTH !
    0 OVER RBF.HAVE-LENGTH !
    0 OVER RBF.START-A !
    0 OVER RBF.START-U !
    0 OVER RBF.VERB-A !
    0 OVER RBF.VERB-U !
    0 OVER RBF.ARGS-A !
    0 OVER RBF.ARGS-U !
    0 OVER RBF.BODY-A !
    0 SWAP RBF.BODY-U ! ;

: RBF-PARSER-RESET  ( parser -- status )
    DUP _RBF-PARSER-DESCRIPTOR? 0= IF DROP RBF-S-INVALID EXIT THEN
    DUP _RBF-CLEAR-CONTENT
    RBF-STATE-START OVER RBF.STATE !
    RBF-S-NEED-MORE SWAP RBF.STATUS !
    RBF-S-OK ;

: RBF-FRAME-RESET  ( frame -- status )
    DUP _RBF-FRAME-DESCRIPTOR? 0= IF DROP RBF-S-INVALID EXIT THEN
    DUP RBF.BUFFER-CAPACITY @ IF DROP RBF-S-STATE EXIT THEN
    DUP _RBF-CLEAR-CONTENT
    RBF-STATE-BUILD OVER RBF.STATE !
    RBF-S-OK SWAP RBF.STATUS !
    RBF-S-OK ;

\ =====================================================================
\  Text and header admission
\ =====================================================================

VARIABLE _RBFSG-A
VARIABLE _RBFSG-U
VARIABLE _RBFSG-PREV-SPACE

: _RBF-START-GRAMMAR?  ( address length -- flag )
    _RBFSG-U ! _RBFSG-A !
    _RBFSG-U @ 0= IF 0 EXIT THEN
    0 _RBFSG-PREV-SPACE !
    _RBFSG-U @ 0 ?DO
        _RBFSG-A @ I + C@
        DUP 32 < OVER 127 = OR IF DROP 0 UNLOOP EXIT THEN
        DUP 32 = IF
            DROP
            I 0= IF 0 UNLOOP EXIT THEN
            I _RBFSG-U @ 1- = IF 0 UNLOOP EXIT THEN
            _RBFSG-PREV-SPACE @ IF 0 UNLOOP EXIT THEN
            -1 _RBFSG-PREV-SPACE !
        ELSE
            DROP 0 _RBFSG-PREV-SPACE !
        THEN
    LOOP
    -1 ;

: _RBF-NAME-CHAR?  ( byte -- flag )
    DUP 65 >= OVER 90 <= AND IF DROP -1 EXIT THEN
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP -1 EXIT THEN
    45 = ;

VARIABLE _RBFNG-A
VARIABLE _RBFNG-U

: _RBF-NAME-GRAMMAR?  ( address length -- flag )
    _RBFNG-U ! _RBFNG-A !
    _RBFNG-U @ 0= IF 0 EXIT THEN
    _RBFNG-U @ 0 ?DO
        _RBFNG-A @ I + C@ _RBF-NAME-CHAR? 0= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

VARIABLE _RBFVG-A
VARIABLE _RBFVG-U

: _RBF-VALUE-GRAMMAR?  ( address length -- flag )
    _RBFVG-U ! _RBFVG-A !
    _RBFVG-U @ 0 ?DO
        _RBFVG-A @ I + C@
        DUP 9 = IF DROP ELSE
            DUP 32 < OVER 127 = OR IF DROP 0 UNLOOP EXIT THEN
            DROP
        THEN
    LOOP
    -1 ;

VARIABLE _RBFBG-A
VARIABLE _RBFBG-U

: _RBF-BODY-CRLF?  ( address length -- flag )
    _RBFBG-U ! _RBFBG-A !
    _RBFBG-U @ 0 ?DO
        _RBFBG-A @ I + C@
        DUP 13 = IF
            DROP
            I 1+ _RBFBG-U @ >= IF 0 UNLOOP EXIT THEN
            _RBFBG-A @ I 1+ + C@ 10 <> IF 0 UNLOOP EXIT THEN
        ELSE DUP 10 = IF
            DROP
            I 0= IF 0 UNLOOP EXIT THEN
            _RBFBG-A @ I 1- + C@ 13 <> IF 0 UNLOOP EXIT THEN
        ELSE DUP 9 = IF
            DROP
        ELSE
            DUP 32 < OVER 127 = OR IF DROP 0 UNLOOP EXIT THEN
            DROP
        THEN THEN THEN
    LOOP
    -1 ;

: _RBF-CORE-SINGLETON?  ( name-a name-u -- flag )
    2DUP S" Lane" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Txn" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Seq" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" ACK" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Credit" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Length" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" View" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Accept-View" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Idem" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Timeout" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" QoS" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Burrow-ID" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Channel-Binding" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" PQ-Exchange" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" PQ-Proof" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Caps" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Nonce" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Proof" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Session-Token" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Server-Proof" STR-STRI= IF 2DROP -1 EXIT THEN
    2DUP S" Since" STR-STRI= IF 2DROP -1 EXIT THEN
    S" Event-Seq" STR-STRI= ;

: RBF-CORE-HEADER?  ( name-a name-u -- flag )
    2DUP _RBF-SPAN-VALID? 0= IF 2DROP 0 EXIT THEN
    _RBF-CORE-SINGLETON? ;

VARIABLE _RBFP-A
VARIABLE _RBFP-U
VARIABLE _RBFP-P

: _RBF-HEADER-PRESENT?  ( name-a name-u frame -- flag )
    _RBFP-P ! _RBFP-U ! _RBFP-A !
    _RBFP-P @ RBF.HEADER-COUNT @ 0 ?DO
        I _RBFP-P @ _RBF-ENTRY
        DUP _RBFH.NAME-A @ SWAP _RBFH.NAME-U @
        _RBFP-A @ _RBFP-U @ STR-STRI= IF
            -1 UNLOOP EXIT
        THEN
    LOOP
    0 ;

0x0CCCCCCCCCCCCCCC CONSTANT _RBF-UDEC-QUOTIENT-MAX
7                  CONSTANT _RBF-UDEC-REMAINDER-MAX

VARIABLE _RBFD-A
VARIABLE _RBFD-U
VARIABLE _RBFD-N

: _RBF-DECIMAL  ( address length -- value flag )
    _RBFD-U ! _RBFD-A ! 0 _RBFD-N !
    _RBFD-U @ 0= IF 0 0 EXIT THEN
    _RBFD-U @ 0 ?DO
        _RBFD-A @ I + C@ DUP 48 < OVER 57 > OR IF
            DROP 0 0 UNLOOP EXIT
        THEN
        48 -
        _RBFD-N @ _RBF-UDEC-QUOTIENT-MAX U> IF
            DROP 0 0 UNLOOP EXIT
        THEN
        _RBFD-N @ _RBF-UDEC-QUOTIENT-MAX = IF
            DUP _RBF-UDEC-REMAINDER-MAX > IF
                DROP 0 0 UNLOOP EXIT
            THEN
        THEN
        _RBFD-N @ 10 * + _RBFD-N !
    LOOP
    _RBFD-N @ -1 ;

VARIABLE _RBFSS-A
VARIABLE _RBFSS-U
VARIABLE _RBFSS-P
VARIABLE _RBFSS-SPACE

: _RBF-SET-START  ( start-a start-u frame -- status )
    _RBFSS-P ! _RBFSS-U ! _RBFSS-A !
    _RBFSS-A @ _RBFSS-U @ _RBF-SPAN-VALID? 0= IF
        RBF-S-INVALID EXIT
    THEN
    _RBFSS-A @ _RBFSS-U @ _RBFSS-P @ RBF.BYTES @
        _RBFSS-P @ SWAP MSPAN-OVERLAP? IF RBF-S-INVALID EXIT THEN
    _RBFSS-A @ _RBFSS-U @ UTF8-VALID? 0= IF RBF-S-UTF8 EXIT THEN
    _RBFSS-A @ _RBFSS-U @ _RBF-START-GRAMMAR? 0= IF
        RBF-S-INVALID EXIT
    THEN
    _RBFSS-A @ _RBFSS-P @ RBF.START-A !
    _RBFSS-U @ _RBFSS-P @ RBF.START-U !
    _RBFSS-A @ _RBFSS-U @ 32 STR-INDEX DUP _RBFSS-SPACE !
    0< IF
        _RBFSS-A @ _RBFSS-P @ RBF.VERB-A !
        _RBFSS-U @ _RBFSS-P @ RBF.VERB-U !
        _RBFSS-A @ _RBFSS-U @ + _RBFSS-P @ RBF.ARGS-A !
        0 _RBFSS-P @ RBF.ARGS-U !
    ELSE
        _RBFSS-A @ _RBFSS-P @ RBF.VERB-A !
        _RBFSS-SPACE @ _RBFSS-P @ RBF.VERB-U !
        _RBFSS-A @ _RBFSS-SPACE @ + 1+
            _RBFSS-P @ RBF.ARGS-A !
        _RBFSS-U @ _RBFSS-SPACE @ - 1-
            _RBFSS-P @ RBF.ARGS-U !
    THEN
    RBF-S-OK ;

VARIABLE _RBFA-NA
VARIABLE _RBFA-NU
VARIABLE _RBFA-VA
VARIABLE _RBFA-VU
VARIABLE _RBFA-P
VARIABLE _RBFA-LENGTH
VARIABLE _RBFA-IS-LENGTH
VARIABLE _RBFA-E

: _RBF-ADD-HEADER  ( name-a name-u value-a value-u frame -- status )
    _RBFA-P ! _RBFA-VU ! _RBFA-VA ! _RBFA-NU ! _RBFA-NA !
    _RBFA-P @ RBF-DESCRIPTOR-VALID? 0= IF RBF-S-INVALID EXIT THEN
    _RBFA-P @ RBF.STATE @ DUP RBF-STATE-HEADERS =
        SWAP RBF-STATE-BUILD = OR 0= IF RBF-S-STATE EXIT THEN
    _RBFA-NA @ _RBFA-NU @ _RBF-SPAN-VALID? 0= IF RBF-S-INVALID EXIT THEN
    _RBFA-VA @ _RBFA-VU @ _RBF-SPAN-VALID? 0= IF RBF-S-INVALID EXIT THEN
    _RBFA-NA @ _RBFA-NU @ _RBFA-P @ _RBFA-P @ RBF.BYTES @
        MSPAN-OVERLAP? IF RBF-S-INVALID EXIT THEN
    _RBFA-VA @ _RBFA-VU @ _RBFA-P @ _RBFA-P @ RBF.BYTES @
        MSPAN-OVERLAP? IF RBF-S-INVALID EXIT THEN
    _RBFA-NA @ _RBFA-NU @ UTF8-VALID? 0= IF RBF-S-UTF8 EXIT THEN
    _RBFA-VA @ _RBFA-VU @ UTF8-VALID? 0= IF RBF-S-UTF8 EXIT THEN
    _RBFA-NA @ _RBFA-NU @ _RBF-NAME-GRAMMAR? 0= IF
        RBF-S-INVALID EXIT
    THEN
    _RBFA-VA @ _RBFA-VU @ _RBF-VALUE-GRAMMAR? 0= IF
        RBF-S-INVALID EXIT
    THEN
    _RBFA-NA @ _RBFA-NU @ S" End" STR-STRI= IF RBF-S-INVALID EXIT THEN
    _RBFA-NA @ _RBFA-NU @ S" Transfer" STR-STRI= IF
        RBF-S-UNSUPPORTED EXIT
    THEN
    _RBFA-NA @ _RBFA-NU @ S" Part" STR-STRI= IF
        RBF-S-UNSUPPORTED EXIT
    THEN
    _RBFA-NA @ _RBFA-NU @ _RBF-CORE-SINGLETON? IF
        _RBFA-NA @ _RBFA-NU @ _RBFA-P @ _RBF-HEADER-PRESENT? IF
            RBF-S-DUPLICATE EXIT
        THEN
    THEN
    _RBFA-P @ RBF.HEADER-COUNT @ _RBFA-P @ RBF.HEADER-CAPACITY @ >= IF
        RBF-S-CAPACITY EXIT
    THEN
    0 _RBFA-IS-LENGTH !
    _RBFA-NA @ _RBFA-NU @ S" Length" STR-STRI= IF
        _RBFA-VA @ _RBFA-VU @ _RBF-DECIMAL 0= IF
            DROP RBF-S-LENGTH EXIT
        THEN
        _RBFA-LENGTH ! -1 _RBFA-IS-LENGTH !
    THEN
    _RBFA-P @ RBF.HEADER-COUNT @ _RBFA-P @ _RBF-ENTRY _RBFA-E !
    _RBFA-NA @ _RBFA-E @ _RBFH.NAME-A !
    _RBFA-NU @ _RBFA-E @ _RBFH.NAME-U !
    _RBFA-VA @ _RBFA-E @ _RBFH.VALUE-A !
    _RBFA-VU @ _RBFA-E @ _RBFH.VALUE-U !
    1 _RBFA-P @ RBF.HEADER-COUNT +!
    _RBFA-IS-LENGTH @ IF
        _RBFA-LENGTH @ _RBFA-P @ RBF.LENGTH !
        -1 _RBFA-P @ RBF.HAVE-LENGTH !
    THEN
    RBF-S-OK ;

VARIABLE _RBFPL-A
VARIABLE _RBFPL-U
VARIABLE _RBFPL-P
VARIABLE _RBFPL-COLON

: _RBF-PARSE-HEADER-LINE  ( line-a line-u parser -- status )
    _RBFPL-P ! _RBFPL-U ! _RBFPL-A !
    -1 _RBFPL-COLON !
    _RBFPL-U @ 0 ?DO
        _RBFPL-A @ I + C@ 58 = IF I _RBFPL-COLON ! LEAVE THEN
    LOOP
    _RBFPL-COLON @ 1 < IF RBF-S-INVALID EXIT THEN
    _RBFPL-COLON @ 1+ _RBFPL-U @ >= IF RBF-S-INVALID EXIT THEN
    _RBFPL-A @ _RBFPL-COLON @ 1+ + C@ 32 <> IF RBF-S-INVALID EXIT THEN
    _RBFPL-A @ _RBFPL-COLON @
    _RBFPL-A @ _RBFPL-COLON @ + 2 +
    _RBFPL-U @ _RBFPL-COLON @ - 2 -
    _RBFPL-P @ _RBF-ADD-HEADER ;

\ =====================================================================
\  Complete-frame revalidation
\ =====================================================================

VARIABLE _RBFSM-P
VARIABLE _RBFSM-SPACE

: _RBF-START-METADATA?  ( frame -- flag )
    _RBFSM-P !
    _RBFSM-P @ RBF.START-A @ _RBFSM-P @ RBF.START-U @
        32 STR-INDEX DUP _RBFSM-SPACE !
    0< IF
        _RBFSM-P @ RBF.VERB-A @ _RBFSM-P @ RBF.START-A @ =
        _RBFSM-P @ RBF.VERB-U @ _RBFSM-P @ RBF.START-U @ = AND
        _RBFSM-P @ RBF.ARGS-U @ 0= AND
        _RBFSM-P @ RBF.ARGS-A @
            _RBFSM-P @ RBF.START-A @ _RBFSM-P @ RBF.START-U @ + = AND
        EXIT
    THEN
    _RBFSM-P @ RBF.VERB-A @ _RBFSM-P @ RBF.START-A @ =
    _RBFSM-P @ RBF.VERB-U @ _RBFSM-SPACE @ = AND
    _RBFSM-P @ RBF.ARGS-A @
        _RBFSM-P @ RBF.START-A @ _RBFSM-SPACE @ + 1+ = AND
    _RBFSM-P @ RBF.ARGS-U @
        _RBFSM-P @ RBF.START-U @ _RBFSM-SPACE @ - 1- = AND ;

VARIABLE _RBFEP-A
VARIABLE _RBFEP-U
VARIABLE _RBFEP-BEFORE
VARIABLE _RBFEP-P

: _RBF-HEADER-EARLIER?  ( name-a name-u before-index frame -- flag )
    _RBFEP-P ! _RBFEP-BEFORE ! _RBFEP-U ! _RBFEP-A !
    _RBFEP-BEFORE @ 0 ?DO
        I _RBFEP-P @ _RBF-ENTRY
        DUP _RBFH.NAME-A @ SWAP _RBFH.NAME-U @
        _RBFEP-A @ _RBFEP-U @ STR-STRI= IF -1 UNLOOP EXIT THEN
    LOOP
    0 ;

VARIABLE _RBFC-P
VARIABLE _RBFC-NA
VARIABLE _RBFC-NU
VARIABLE _RBFC-VA
VARIABLE _RBFC-VU
VARIABLE _RBFC-E
VARIABLE _RBFC-HAVE-LENGTH
VARIABLE _RBFC-LENGTH

: _RBF-COMPLETE-STATUS  ( frame -- status )
    DUP RBF-DESCRIPTOR-VALID? 0= IF DROP RBF-S-INVALID EXIT THEN
    DUP _RBFC-P ! RBF.STATE @ DUP RBF-STATE-BUILD =
        SWAP RBF-STATE-READY = OR 0= IF RBF-S-STATE EXIT THEN
    _RBFC-P @ RBF.START-A @ _RBFC-P @ RBF.START-U @
        _RBF-SPAN-VALID? 0= IF RBF-S-INVALID EXIT THEN
    _RBFC-P @ RBF.START-A @ _RBFC-P @ RBF.START-U @
        _RBFC-P @ _RBFC-P @ RBF.BYTES @ MSPAN-OVERLAP? IF
        RBF-S-INVALID EXIT
    THEN
    _RBFC-P @ RBF.START-A @ _RBFC-P @ RBF.START-U @
        UTF8-VALID? 0= IF RBF-S-UTF8 EXIT THEN
    _RBFC-P @ RBF.START-A @ _RBFC-P @ RBF.START-U @
        _RBF-START-GRAMMAR? 0= IF RBF-S-INVALID EXIT THEN
    _RBFC-P @ _RBF-START-METADATA? 0= IF RBF-S-INVALID EXIT THEN
    0 _RBFC-HAVE-LENGTH ! 0 _RBFC-LENGTH !
    _RBFC-P @ RBF.HEADER-COUNT @ 0 ?DO
        I _RBFC-P @ _RBF-ENTRY DUP _RBFC-E !
        DUP _RBFH.NAME-A @ _RBFC-NA !
        DUP _RBFH.NAME-U @ _RBFC-NU !
        DUP _RBFH.VALUE-A @ _RBFC-VA !
        _RBFH.VALUE-U @ _RBFC-VU !
        _RBFC-NA @ _RBFC-NU @ _RBF-SPAN-VALID? 0= IF
            RBF-S-INVALID UNLOOP EXIT
        THEN
        _RBFC-VA @ _RBFC-VU @ _RBF-SPAN-VALID? 0= IF
            RBF-S-INVALID UNLOOP EXIT
        THEN
        _RBFC-NA @ _RBFC-NU @ _RBFC-P @ _RBFC-P @ RBF.BYTES @
            MSPAN-OVERLAP? IF RBF-S-INVALID UNLOOP EXIT THEN
        _RBFC-VA @ _RBFC-VU @ _RBFC-P @ _RBFC-P @ RBF.BYTES @
            MSPAN-OVERLAP? IF RBF-S-INVALID UNLOOP EXIT THEN
        _RBFC-NA @ _RBFC-NU @ UTF8-VALID? 0= IF
            RBF-S-UTF8 UNLOOP EXIT
        THEN
        _RBFC-VA @ _RBFC-VU @ UTF8-VALID? 0= IF
            RBF-S-UTF8 UNLOOP EXIT
        THEN
        _RBFC-NA @ _RBFC-NU @ _RBF-NAME-GRAMMAR? 0= IF
            RBF-S-INVALID UNLOOP EXIT
        THEN
        _RBFC-VA @ _RBFC-VU @ _RBF-VALUE-GRAMMAR? 0= IF
            RBF-S-INVALID UNLOOP EXIT
        THEN
        _RBFC-NA @ _RBFC-NU @ S" End" STR-STRI= IF
            RBF-S-INVALID UNLOOP EXIT
        THEN
        _RBFC-NA @ _RBFC-NU @ S" Transfer" STR-STRI=
        _RBFC-NA @ _RBFC-NU @ S" Part" STR-STRI= OR IF
            RBF-S-UNSUPPORTED UNLOOP EXIT
        THEN
        _RBFC-NA @ _RBFC-NU @ _RBF-CORE-SINGLETON? IF
            _RBFC-NA @ _RBFC-NU @ I _RBFC-P @
                _RBF-HEADER-EARLIER? IF
                RBF-S-DUPLICATE UNLOOP EXIT
            THEN
        THEN
        _RBFC-NA @ _RBFC-NU @ S" Length" STR-STRI= IF
            _RBFC-VA @ _RBFC-VU @ _RBF-DECIMAL 0= IF
                DROP RBF-S-LENGTH UNLOOP EXIT
            THEN
            _RBFC-LENGTH ! -1 _RBFC-HAVE-LENGTH !
        THEN
    LOOP
    _RBFC-HAVE-LENGTH @ _RBFC-P @ RBF.HAVE-LENGTH @ <> IF
        RBF-S-INVALID EXIT
    THEN
    _RBFC-HAVE-LENGTH @ IF
        _RBFC-LENGTH @ _RBFC-P @ RBF.LENGTH @ <> IF
            RBF-S-INVALID EXIT
        THEN
    THEN
    _RBFC-P @ RBF.BODY-A @ _RBFC-P @ RBF.BODY-U @
        _RBF-SPAN-VALID? 0= IF RBF-S-INVALID EXIT THEN
    _RBFC-P @ RBF.BODY-A @ _RBFC-P @ RBF.BODY-U @
        _RBFC-P @ _RBFC-P @ RBF.BYTES @ MSPAN-OVERLAP? IF
        RBF-S-INVALID EXIT
    THEN
    _RBFC-P @ RBF.BODY-A @ _RBFC-P @ RBF.BODY-U @
        UTF8-VALID? 0= IF RBF-S-UTF8 EXIT THEN
    _RBFC-P @ RBF.BODY-A @ _RBFC-P @ RBF.BODY-U @
        _RBF-BODY-CRLF? 0= IF RBF-S-CRLF EXIT THEN
    _RBFC-HAVE-LENGTH @ IF
        _RBFC-LENGTH @ _RBFC-P @ RBF.BODY-U @ <> IF
            RBF-S-LENGTH EXIT
        THEN
    ELSE
        _RBFC-P @ RBF.BODY-U @ IF RBF-S-LENGTH EXIT THEN
    THEN
    RBF-S-OK ;

\ =====================================================================
\  Outbound construction
\ =====================================================================

: RBF-FRAME-START!  ( start-a start-u frame -- status )
    DUP _RBF-FRAME-DESCRIPTOR? 0= IF
        DROP 2DROP RBF-S-INVALID EXIT
    THEN
    DUP RBF.STATE @ RBF-STATE-BUILD <> IF DROP 2DROP RBF-S-STATE EXIT THEN
    _RBF-SET-START ;

: RBF-FRAME-HEADER+  ( name-a name-u value-a value-u frame -- status )
    DUP _RBF-FRAME-DESCRIPTOR? 0= IF
        DROP 2DROP 2DROP RBF-S-INVALID EXIT
    THEN
    _RBF-ADD-HEADER ;

VARIABLE _RBFBS-A
VARIABLE _RBFBS-U
VARIABLE _RBFBS-P

: RBF-FRAME-BODY!  ( body-a body-u frame -- status )
    _RBFBS-P ! _RBFBS-U ! _RBFBS-A !
    _RBFBS-P @ _RBF-FRAME-DESCRIPTOR? 0= IF RBF-S-INVALID EXIT THEN
    _RBFBS-P @ RBF.STATE @ RBF-STATE-BUILD <> IF RBF-S-STATE EXIT THEN
    _RBFBS-A @ _RBFBS-U @ _RBF-SPAN-VALID? 0= IF RBF-S-INVALID EXIT THEN
    _RBFBS-A @ _RBFBS-U @ _RBFBS-P @ _RBFBS-P @ RBF.BYTES @
        MSPAN-OVERLAP? IF RBF-S-INVALID EXIT THEN
    _RBFBS-A @ _RBFBS-U @ UTF8-VALID? 0= IF RBF-S-UTF8 EXIT THEN
    _RBFBS-A @ _RBFBS-U @ _RBF-BODY-CRLF? 0= IF RBF-S-CRLF EXIT THEN
    _RBFBS-P @ RBF.HAVE-LENGTH @ IF
        _RBFBS-U @ _RBFBS-P @ RBF.LENGTH @ <> IF RBF-S-LENGTH EXIT THEN
    ELSE
        _RBFBS-U @ IF RBF-S-LENGTH EXIT THEN
    THEN
    _RBFBS-A @ _RBFBS-P @ RBF.BODY-A !
    _RBFBS-U @ _RBFBS-P @ RBF.BODY-U !
    RBF-S-OK ;

: RBF-FRAME-SEAL  ( frame -- status )
    DUP _RBF-FRAME-DESCRIPTOR? 0= IF DROP RBF-S-INVALID EXIT THEN
    DUP RBF.STATE @ RBF-STATE-BUILD <> IF DROP RBF-S-STATE EXIT THEN
    DUP _RBF-COMPLETE-STATUS DUP IF NIP EXIT THEN DROP
    RBF-STATE-READY OVER RBF.STATE !
    RBF-S-READY SWAP RBF.STATUS !
    RBF-S-OK ;

\ =====================================================================
\  Incremental parser
\ =====================================================================

VARIABLE _RBFFAIL-P

: _RBF-FAIL  ( status parser -- )
    _RBFFAIL-P !
    _RBFFAIL-P @ RBF.STATE @ RBF-STATE-ERROR <> IF
        _RBFFAIL-P @ RBF.STATUS !
        RBF-STATE-ERROR _RBFFAIL-P @ RBF.STATE !
    ELSE
        DROP
    THEN ;

: _RBF-MARK-READY  ( parser -- )
    RBF-STATE-READY OVER RBF.STATE !
    RBF-S-READY SWAP RBF.STATUS ! ;

VARIABLE _RBFEND-P
VARIABLE _RBFEND-REMAINING

: _RBF-END-HEADERS  ( parser -- )
    _RBFEND-P !
    _RBFEND-P @ RBF.BUFFER @ _RBFEND-P @ RBF.BUFFER-USED @ +
        _RBFEND-P @ RBF.BODY-A !
    0 _RBFEND-P @ RBF.BODY-U !
    _RBFEND-P @ RBF.HAVE-LENGTH @ IF
        _RBFEND-P @ RBF.LENGTH @ _RBFEND-REMAINING !
    ELSE
        0 _RBFEND-REMAINING !
    THEN
    _RBFEND-REMAINING @
        _RBFEND-P @ RBF.BUFFER-CAPACITY @
        _RBFEND-P @ RBF.BUFFER-USED @ - > IF
        RBF-S-CAPACITY _RBFEND-P @ _RBF-FAIL EXIT
    THEN
    _RBFEND-REMAINING @ 0= IF
        _RBFEND-P @ _RBF-MARK-READY
    ELSE
        RBF-STATE-BODY _RBFEND-P @ RBF.STATE !
    THEN ;

VARIABLE _RBFLINE-P
VARIABLE _RBFLINE-A
VARIABLE _RBFLINE-U
VARIABLE _RBFLINE-S

: _RBF-PROCESS-LINE  ( parser -- )
    _RBFLINE-P !
    _RBFLINE-P @ RBF.BUFFER @ _RBFLINE-P @ RBF.LINE-START @ +
        _RBFLINE-A !
    _RBFLINE-P @ RBF.BUFFER-USED @
        _RBFLINE-P @ RBF.LINE-START @ - 2 - _RBFLINE-U !
    _RBFLINE-P @ RBF.STATE @ RBF-STATE-START = IF
        _RBFLINE-A @ _RBFLINE-U @ _RBFLINE-P @ _RBF-SET-START
            DUP _RBFLINE-S ! IF
            _RBFLINE-S @ _RBFLINE-P @ _RBF-FAIL EXIT
        THEN
        RBF-STATE-HEADERS _RBFLINE-P @ RBF.STATE !
        _RBFLINE-P @ RBF.BUFFER-USED @ _RBFLINE-P @ RBF.LINE-START !
        EXIT
    THEN
    _RBFLINE-A @ _RBFLINE-U @ S" End:" STR-STR= IF
        _RBFLINE-P @ RBF.BUFFER-USED @ _RBFLINE-P @ RBF.LINE-START !
        _RBFLINE-P @ _RBF-END-HEADERS EXIT
    THEN
    _RBFLINE-A @ _RBFLINE-U @ _RBFLINE-P @
        _RBF-PARSE-HEADER-LINE DUP _RBFLINE-S ! IF
        _RBFLINE-S @ _RBFLINE-P @ _RBF-FAIL EXIT
    THEN
    _RBFLINE-P @ RBF.BUFFER-USED @ _RBFLINE-P @ RBF.LINE-START ! ;

VARIABLE _RBFFEED-A
VARIABLE _RBFFEED-U
VARIABLE _RBFFEED-P
VARIABLE _RBFFEED-I
VARIABLE _RBFFEED-C
VARIABLE _RBFFEED-TAKE
VARIABLE _RBFFEED-REMAINING

: _RBF-FEED-LINE-BYTE  ( -- )
    _RBFFEED-P @ RBF.BUFFER-USED @
        _RBFFEED-P @ RBF.BUFFER-CAPACITY @ >= IF
        RBF-S-CAPACITY _RBFFEED-P @ _RBF-FAIL EXIT
    THEN
    _RBFFEED-A @ _RBFFEED-I @ + C@ DUP _RBFFEED-C !
    _RBFFEED-P @ RBF.BUFFER @ _RBFFEED-P @ RBF.BUFFER-USED @ + C!
    1 _RBFFEED-P @ RBF.BUFFER-USED +!
    1 _RBFFEED-I +!
    _RBFFEED-P @ RBF.CR-PENDING @ IF
        _RBFFEED-C @ 10 <> IF
            RBF-S-CRLF _RBFFEED-P @ _RBF-FAIL EXIT
        THEN
        0 _RBFFEED-P @ RBF.CR-PENDING !
        _RBFFEED-P @ _RBF-PROCESS-LINE EXIT
    THEN
    _RBFFEED-C @ 10 = IF
        RBF-S-CRLF _RBFFEED-P @ _RBF-FAIL EXIT
    THEN
    _RBFFEED-C @ 13 = IF -1 _RBFFEED-P @ RBF.CR-PENDING ! THEN ;

: _RBF-FEED-BODY  ( -- )
    _RBFFEED-P @ RBF.LENGTH @ _RBFFEED-P @ RBF.BODY-U @ -
        _RBFFEED-REMAINING !
    _RBFFEED-U @ _RBFFEED-I @ - _RBFFEED-REMAINING @ MIN
        _RBFFEED-TAKE !
    _RBFFEED-A @ _RBFFEED-I @ +
    _RBFFEED-P @ RBF.BUFFER @ _RBFFEED-P @ RBF.BUFFER-USED @ +
    _RBFFEED-TAKE @ CMOVE
    _RBFFEED-TAKE @ _RBFFEED-I +!
    _RBFFEED-TAKE @ _RBFFEED-P @ RBF.BUFFER-USED +!
    _RBFFEED-TAKE @ _RBFFEED-P @ RBF.BODY-U +!
    _RBFFEED-P @ RBF.BODY-U @ _RBFFEED-P @ RBF.LENGTH @ = IF
        _RBFFEED-P @ RBF.BODY-A @ _RBFFEED-P @ RBF.BODY-U @
            UTF8-VALID? 0= IF
            RBF-S-UTF8 _RBFFEED-P @ _RBF-FAIL EXIT
        THEN
        _RBFFEED-P @ RBF.BODY-A @ _RBFFEED-P @ RBF.BODY-U @
            _RBF-BODY-CRLF? 0= IF
            RBF-S-CRLF _RBFFEED-P @ _RBF-FAIL EXIT
        THEN
        _RBFFEED-P @ _RBF-MARK-READY
    THEN ;

: RBF-FEED  ( input-a input-u parser -- consumed status )
    _RBFFEED-P ! _RBFFEED-U ! _RBFFEED-A !
    _RBFFEED-P @ _RBF-PARSER-DESCRIPTOR? 0= IF
        0 RBF-S-INVALID EXIT
    THEN
    _RBFFEED-P @ RBF.STATE @ RBF-STATE-READY = IF
        0 RBF-S-READY EXIT
    THEN
    _RBFFEED-P @ RBF.STATE @ RBF-STATE-ERROR = IF
        0 _RBFFEED-P @ RBF.STATUS @ EXIT
    THEN
    _RBFFEED-P @ RBF.STATE @ RBF-STATE-BUILD = IF
        0 RBF-S-STATE EXIT
    THEN
    _RBFFEED-A @ _RBFFEED-U @ _RBF-SPAN-VALID? 0= IF
        0 RBF-S-INVALID EXIT
    THEN
    _RBFFEED-A @ _RBFFEED-U @
        _RBFFEED-P @ _RBFFEED-P @ RBF.BYTES @ MSPAN-OVERLAP? IF
        0 RBF-S-INVALID EXIT
    THEN
    _RBFFEED-A @ _RBFFEED-U @
        _RBFFEED-P @ RBF.BUFFER @
        _RBFFEED-P @ RBF.BUFFER-CAPACITY @ MSPAN-OVERLAP? IF
        0 RBF-S-INVALID EXIT
    THEN
    0 _RBFFEED-I !
    BEGIN
        _RBFFEED-I @ _RBFFEED-U @ <
        _RBFFEED-P @ RBF.STATE @ RBF-STATE-READY <> AND
        _RBFFEED-P @ RBF.STATE @ RBF-STATE-ERROR <> AND
    WHILE
        _RBFFEED-P @ RBF.STATE @ RBF-STATE-BODY = IF
            _RBF-FEED-BODY
        ELSE
            _RBF-FEED-LINE-BYTE
        THEN
    REPEAT
    _RBFFEED-I @ _RBFFEED-P @ RBF.STATUS @ ;

\ EOF is clean only before the first byte of a new frame.  Once any start
\ line, header, End marker, or declared body byte has been accepted, EOF is
\ terminal truncation and remains latched until RESET.
: RBF-EOF  ( parser -- status )
    DUP _RBF-PARSER-DESCRIPTOR? 0= IF DROP RBF-S-INVALID EXIT THEN
    DUP RBF.STATE @ RBF-STATE-READY = IF DROP RBF-S-READY EXIT THEN
    DUP RBF.STATE @ RBF-STATE-ERROR = IF RBF.STATUS @ EXIT THEN
    DUP RBF.STATE @ RBF-STATE-BUILD = IF DROP RBF-S-STATE EXIT THEN
    DUP RBF.STATE @ RBF-STATE-START =
    OVER RBF.BUFFER-USED @ 0= AND IF DROP RBF-S-OK EXIT THEN
    RBF-S-TRUNCATED OVER _RBF-FAIL
    DROP RBF-S-TRUNCATED ;

\ =====================================================================
\  READY accessors and lookup
\ =====================================================================

: RBF-PARSER-STATE@  ( parser -- state|RBF-STATE-ERROR )
    DUP _RBF-PARSER-DESCRIPTOR? 0= IF DROP RBF-STATE-ERROR EXIT THEN
    RBF.STATE @ ;

: RBF-PARSER-STATUS@  ( parser -- status )
    DUP _RBF-PARSER-DESCRIPTOR? 0= IF DROP RBF-S-INVALID EXIT THEN
    RBF.STATUS @ ;

: RBF-PARSER-USED@  ( parser -- bytes )
    DUP _RBF-PARSER-DESCRIPTOR? 0= IF DROP 0 EXIT THEN
    RBF.BUFFER-USED @ ;

: RBF-READY?  ( frame -- flag )
    DUP RBF-DESCRIPTOR-VALID? 0= IF DROP 0 EXIT THEN
    RBF.STATE @ RBF-STATE-READY = ;

: RBF-START$  ( frame -- address length )
    DUP RBF-READY? 0= IF DROP 0 0 EXIT THEN
    DUP RBF.START-A @ SWAP RBF.START-U @ ;

: RBF-VERB$  ( frame -- address length )
    DUP RBF-READY? 0= IF DROP 0 0 EXIT THEN
    DUP RBF.VERB-A @ SWAP RBF.VERB-U @ ;

: RBF-ARGS$  ( frame -- address length )
    DUP RBF-READY? 0= IF DROP 0 0 EXIT THEN
    DUP RBF.ARGS-A @ SWAP RBF.ARGS-U @ ;

: RBF-BODY$  ( frame -- address length )
    DUP RBF-READY? 0= IF DROP 0 0 EXIT THEN
    DUP RBF.BODY-A @ SWAP RBF.BODY-U @ ;

: RBF-HEADER-COUNT@  ( frame -- count )
    DUP RBF-READY? 0= IF DROP 0 EXIT THEN
    RBF.HEADER-COUNT @ ;

VARIABLE _RBFHG-I
VARIABLE _RBFHG-P
VARIABLE _RBFHG-E

: RBF-HEADER@  ( index frame -- name-a name-u value-a value-u flag )
    _RBFHG-P ! _RBFHG-I !
    _RBFHG-P @ RBF-READY? 0= IF 0 0 0 0 0 EXIT THEN
    _RBFHG-I @ 0< IF 0 0 0 0 0 EXIT THEN
    _RBFHG-I @ _RBFHG-P @ RBF.HEADER-COUNT @ >= IF
        0 0 0 0 0 EXIT
    THEN
    _RBFHG-I @ _RBFHG-P @ _RBF-ENTRY _RBFHG-E !
    _RBFHG-E @ _RBFH.NAME-A @
    _RBFHG-E @ _RBFH.NAME-U @
    _RBFHG-E @ _RBFH.VALUE-A @
    _RBFHG-E @ _RBFH.VALUE-U @ -1 ;

VARIABLE _RBFHL-A
VARIABLE _RBFHL-U
VARIABLE _RBFHL-P
VARIABLE _RBFHL-E

: RBF-HEADER$  ( name-a name-u frame -- value-a value-u flag )
    _RBFHL-P ! _RBFHL-U ! _RBFHL-A !
    _RBFHL-P @ RBF-READY? 0= IF 0 0 0 EXIT THEN
    _RBFHL-A @ _RBFHL-U @ _RBF-SPAN-VALID? 0= IF 0 0 0 EXIT THEN
    _RBFHL-P @ RBF.HEADER-COUNT @ 0 ?DO
        I _RBFHL-P @ _RBF-ENTRY DUP _RBFHL-E !
        DUP _RBFH.NAME-A @ SWAP _RBFH.NAME-U @
        _RBFHL-A @ _RBFHL-U @ STR-STRI= IF
            _RBFHL-E @ _RBFH.VALUE-A @
            _RBFHL-E @ _RBFH.VALUE-U @ -1 UNLOOP EXIT
        THEN
    LOOP
    0 0 0 ;

\ =====================================================================
\  Exact sizing and all-or-nothing encoding
\ =====================================================================

VARIABLE _RBFM-P
VARIABLE _RBFM-TOTAL

: _RBF-MEASURE-ADD  ( nonnegative-u -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    DUP 0x7FFFFFFFFFFFFFFF _RBFM-TOTAL @ - U> IF DROP 0 EXIT THEN
    _RBFM-TOTAL +! -1 ;

: RBF-FRAME-MEASURE  ( frame -- exact-u status )
    DUP _RBF-FRAME-DESCRIPTOR? 0= IF DROP 0 RBF-S-INVALID EXIT THEN
    DUP RBF.STATE @ RBF-STATE-READY <> IF DROP 0 RBF-S-STATE EXIT THEN
    DUP _RBF-COMPLETE-STATUS DUP IF
        >R DROP 0 R> EXIT
    THEN DROP _RBFM-P !
    0 _RBFM-TOTAL !
    _RBFM-P @ RBF.START-U @ _RBF-MEASURE-ADD 0= IF
        0 RBF-S-CAPACITY EXIT
    THEN
    2 _RBF-MEASURE-ADD 0= IF 0 RBF-S-CAPACITY EXIT THEN
    _RBFM-P @ RBF.HEADER-COUNT @ 0 ?DO
        I _RBFM-P @ _RBF-ENTRY DUP _RBFH.NAME-U @
            _RBF-MEASURE-ADD 0= IF
            DROP 0 RBF-S-CAPACITY UNLOOP EXIT
        THEN
        2 _RBF-MEASURE-ADD 0= IF
            DROP 0 RBF-S-CAPACITY UNLOOP EXIT
        THEN
        _RBFH.VALUE-U @ _RBF-MEASURE-ADD 0= IF
            0 RBF-S-CAPACITY UNLOOP EXIT
        THEN
        2 _RBF-MEASURE-ADD 0= IF 0 RBF-S-CAPACITY UNLOOP EXIT THEN
    LOOP
    6 _RBF-MEASURE-ADD 0= IF 0 RBF-S-CAPACITY EXIT THEN
    _RBFM-P @ RBF.BODY-U @ _RBF-MEASURE-ADD 0= IF
        0 RBF-S-CAPACITY EXIT
    THEN
    _RBFM-TOTAL @ RBF-S-OK ;

: RBF-ENCODE-SIZE  ( frame -- exact-u status )
    RBF-FRAME-MEASURE ;

VARIABLE _RBFOD-A
VARIABLE _RBFOD-U
VARIABLE _RBFOD-P
VARIABLE _RBFOD-E

: _RBF-OUTPUT-DISJOINT?  ( output-a exact-u frame -- flag )
    _RBFOD-P ! _RBFOD-U ! _RBFOD-A !
    _RBFOD-A @ _RBFOD-U @ _RBFOD-P @ _RBFOD-P @ RBF.BYTES @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RBFOD-A @ _RBFOD-U @
        _RBFOD-P @ RBF.START-A @ _RBFOD-P @ RBF.START-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RBFOD-A @ _RBFOD-U @
        _RBFOD-P @ RBF.BODY-A @ _RBFOD-P @ RBF.BODY-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RBFOD-P @ RBF.HEADER-COUNT @ 0 ?DO
        I _RBFOD-P @ _RBF-ENTRY _RBFOD-E !
        _RBFOD-A @ _RBFOD-U @
            _RBFOD-E @ _RBFH.NAME-A @ _RBFOD-E @ _RBFH.NAME-U @
            MSPAN-OVERLAP? IF 0 UNLOOP EXIT THEN
        _RBFOD-A @ _RBFOD-U @
            _RBFOD-E @ _RBFH.VALUE-A @ _RBFOD-E @ _RBFH.VALUE-U @
            MSPAN-OVERLAP? IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

VARIABLE _RBFE-A
VARIABLE _RBFE-CAP
VARIABLE _RBFE-P
VARIABLE _RBFE-N
VARIABLE _RBFE-STATUS
VARIABLE _RBFE-POS
VARIABLE _RBFE-SA
VARIABLE _RBFE-SU
VARIABLE _RBFE-E

: _RBF-EMIT  ( source-a source-u -- )
    _RBFE-SU ! _RBFE-SA !
    _RBFE-SA @ _RBFE-A @ _RBFE-POS @ + _RBFE-SU @ CMOVE
    _RBFE-SU @ _RBFE-POS +! ;

: _RBF-EMIT-CHAR  ( byte -- )
    _RBFE-A @ _RBFE-POS @ + C! 1 _RBFE-POS +! ;

: _RBF-EMIT-CRLF  ( -- )
    13 _RBF-EMIT-CHAR 10 _RBF-EMIT-CHAR ;

: RBF-FRAME-ENCODE  ( output-a capacity frame -- written status )
    _RBFE-P ! _RBFE-CAP ! _RBFE-A !
    _RBFE-P @ RBF-FRAME-MEASURE
    _RBFE-STATUS ! _RBFE-N !
    _RBFE-STATUS @ IF 0 _RBFE-STATUS @ EXIT THEN
    _RBFE-CAP @ 0< IF 0 RBF-S-INVALID EXIT THEN
    _RBFE-CAP @ 0> _RBFE-A @ 0= AND IF 0 RBF-S-INVALID EXIT THEN
    _RBFE-A @ _RBFE-CAP @ MSPAN-NONWRAPPING? 0= IF
        0 RBF-S-INVALID EXIT
    THEN
    _RBFE-N @ _RBFE-CAP @ > IF 0 RBF-S-CAPACITY EXIT THEN
    _RBFE-A @ _RBFE-N @ _RBFE-P @ _RBF-OUTPUT-DISJOINT? 0= IF
        0 RBF-S-INVALID EXIT
    THEN
    0 _RBFE-POS !
    _RBFE-P @ RBF.START-A @ _RBFE-P @ RBF.START-U @ _RBF-EMIT
    _RBF-EMIT-CRLF
    _RBFE-P @ RBF.HEADER-COUNT @ 0 ?DO
        I _RBFE-P @ _RBF-ENTRY DUP _RBFE-E !
        DUP _RBFH.NAME-A @ SWAP _RBFH.NAME-U @ _RBF-EMIT
        58 _RBF-EMIT-CHAR 32 _RBF-EMIT-CHAR
        _RBFE-E @ _RBFH.VALUE-A @ _RBFE-E @ _RBFH.VALUE-U @ _RBF-EMIT
        _RBF-EMIT-CRLF
    LOOP
    S" End:" _RBF-EMIT _RBF-EMIT-CRLF
    _RBFE-P @ RBF.BODY-A @ _RBFE-P @ RBF.BODY-U @ _RBF-EMIT
    _RBFE-N @ RBF-S-OK ;

: RBF-ENCODE  ( output-a capacity frame -- written status )
    RBF-FRAME-ENCODE ;
