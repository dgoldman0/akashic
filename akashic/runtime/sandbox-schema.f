\ =====================================================================
\  sandbox-schema.f - Canonical host-side sandbox value schemas
\ =====================================================================
\  This is trusted runtime policy.  It is deliberately outside the neutral
\  VM and is not required by any file in akashic/sandbox/.
\
\  Schemas and values are immutable caller-owned byte spans.  Schema bytes
\  are pointer-free, complete-span canonical records suitable for exact
\  content digesting.  Validation owns no allocation, caller-supplied
\  callback, Context, module pointer, or mutable operation scratch.  Recursive
\  walkers explicitly thread their own execution token; all operation state
\  lives in a caller-owned workspace, and every recursive walk is bounded by
\  that workspace's configured depth.
\
\  SBOX-SCHEMA-VALUE-VALIDATE performs three ordered passes:
\    1. validate the complete schema document;
\    2. validate the complete canonical value independently; and
\    3. match the already-valid value against the already-valid schema.
\  Consequently malformed schema bytes, malformed value bytes, and an
\  ordinary well-formed value mismatch have distinct public statuses.
\ =====================================================================

PROVIDED akashic-rt-sbx-schema

REQUIRE ../sandbox/format.f
REQUIRE ../utils/caller-span.f

\ =====================================================================
\  Public status
\ =====================================================================

0 CONSTANT SBOX-SCHEMA-S-OK
1 CONSTANT SBOX-SCHEMA-S-INVALID
2 CONSTANT SBOX-SCHEMA-S-MALFORMED-SCHEMA
3 CONSTANT SBOX-SCHEMA-S-MALFORMED-VALUE
4 CONSTANT SBOX-SCHEMA-S-VALUE-MISMATCH
5 CONSTANT SBOX-SCHEMA-S-CAPACITY
6 CONSTANT SBOX-SCHEMA-S-ALIAS
7 CONSTANT SBOX-SCHEMA-S-RANGE
8 CONSTANT SBOX-SCHEMA-S-PROTECTED
9 CONSTANT SBOX-SCHEMA-S-PLATFORM

: SBOX-SCHEMA-STATUS-VALID?  ( status -- flag )
    DUP SBOX-SCHEMA-S-OK >=
    SWAP SBOX-SCHEMA-S-PLATFORM <= AND ;

: _SS-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP SBOX-SCHEMA-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP SBOX-SCHEMA-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP SBOX-SCHEMA-S-PROTECTED EXIT
    THEN
    DROP SBOX-SCHEMA-S-PLATFORM ;

\ =====================================================================
\  Canonical schema wire constants
\ =====================================================================

\ The little-endian bytes of this cell spell "AKSCHEMA".
0x414D454843534B41 CONSTANT SBOX-SCHEMA-DOCUMENT-MAGIC
1                  CONSTANT SBOX-SCHEMA-DOCUMENT-VERSION

32 CONSTANT SBOX-SCHEMA-DOCUMENT-HEADER-SIZE
32 CONSTANT SBOX-SCHEMA-NODE-HEADER-SIZE
16 CONSTANT SBOX-SCHEMA-FIELD-HEADER-SIZE

0 CONSTANT SBOX-SCHEMA-T-NULL
1 CONSTANT SBOX-SCHEMA-T-BOOL
2 CONSTANT SBOX-SCHEMA-T-I64
3 CONSTANT SBOX-SCHEMA-T-BYTES
4 CONSTANT SBOX-SCHEMA-T-UTF8
5 CONSTANT SBOX-SCHEMA-T-LIST
6 CONSTANT SBOX-SCHEMA-T-MAP

1 CONSTANT SBOX-SCHEMA-FIELD-F-REQUIRED
2 CONSTANT SBOX-SCHEMA-FIELD-F-OPTIONAL

: SBOX-SCHEMA-TYPE-VALID?  ( type -- flag )
    DUP SBOX-SCHEMA-T-NULL >=
    SWAP SBOX-SCHEMA-T-MAP <= AND ;

: SBOX-SCHEMA-FIELD-FLAGS-VALID?  ( flags -- flag )
    DUP SBOX-SCHEMA-FIELD-F-REQUIRED =
    SWAP SBOX-SCHEMA-FIELD-F-OPTIONAL = OR ;

\ Digest callers hash this domain, one zero byte, and the exact validated
\ document span.  Keeping the hash primitive out of this file avoids making
\ schema validation depend on a particular digest implementation.
: SBOX-SCHEMA-DIGEST-DOMAIN  ( -- address length )
    S" akashic.sandbox.schema" ;

\ =====================================================================
\  Internal fixed-width reads and span predicates
\ =====================================================================

: _SS-U16@  ( address -- value )
    DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;

: _SS-U32@  ( address -- value )
    DUP _SS-U16@
    SWAP 2 + _SS-U16@ 16 LSHIFT OR ;

: _SS-U64@  ( address -- value )
    DUP _SS-U32@
    SWAP 4 + _SS-U32@ 32 LSHIFT OR ;

: _SS-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0> 2 PICK 0= AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SS-QUALIFY  ( address length -- status )
    2DUP _SS-SPAN? 0= IF 2DROP SBOX-SCHEMA-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _SS-CALLER>STATUS ;

: _SS-CONTINUATION?  ( byte -- flag )
    DUP 0x80 >= SWAP 0xBF <= AND ;

: _SS-SKIP  ( address length count -- address' length' )
    >R SWAP R@ + SWAP R> - ;

\ Stack-only canonical UTF-8 validation.  The general UTF8-VALID? utility
\ predates the sandbox and owns mutable scratch, so this reentrant boundary
\ intentionally does not call it.
: _SS-UTF8-2?  ( address length -- address' length' flag )
    DUP 2 < IF 0 EXIT THEN
    OVER 1+ C@ _SS-CONTINUATION? 0= IF 0 EXIT THEN
    2 _SS-SKIP -1 ;

: _SS-UTF8-3?  ( address length lead -- address' length' flag )
    >R
    DUP 3 < IF R> DROP 0 EXIT THEN
    OVER 1+ C@ DUP _SS-CONTINUATION? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ 0xE0 = IF
        DUP 0xA0 < IF DROP R> DROP 0 EXIT THEN
    THEN
    R@ 0xED = IF
        DUP 0x9F > IF DROP R> DROP 0 EXIT THEN
    THEN
    DROP
    OVER 2 + C@ _SS-CONTINUATION? 0= IF
        R> DROP 0 EXIT
    THEN
    3 _SS-SKIP R> DROP -1 ;

: _SS-UTF8-4?  ( address length lead -- address' length' flag )
    >R
    DUP 4 < IF R> DROP 0 EXIT THEN
    OVER 1+ C@ DUP _SS-CONTINUATION? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ 0xF0 = IF
        DUP 0x90 < IF DROP R> DROP 0 EXIT THEN
    THEN
    R@ 0xF4 = IF
        DUP 0x8F > IF DROP R> DROP 0 EXIT THEN
    THEN
    DROP
    OVER 2 + C@ _SS-CONTINUATION? 0= IF
        R> DROP 0 EXIT
    THEN
    OVER 3 + C@ _SS-CONTINUATION? 0= IF
        R> DROP 0 EXIT
    THEN
    4 _SS-SKIP R> DROP -1 ;

: _SS-UTF8?  ( address length -- flag )
    2DUP _SS-SPAN? 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP 0> WHILE
        OVER C@ DUP 0x80 < IF
            DROP 1 _SS-SKIP
        ELSE
            DUP 0xC2 >= OVER 0xDF <= AND IF
                DROP _SS-UTF8-2? 0= IF 2DROP 0 EXIT THEN
            ELSE
                DUP 0xE0 >= OVER 0xEF <= AND IF
                    _SS-UTF8-3? 0= IF 2DROP 0 EXIT THEN
                ELSE
                    DUP 0xF0 >= OVER 0xF4 <= AND IF
                        _SS-UTF8-4? 0= IF 2DROP 0 EXIT THEN
                    ELSE
                        DROP 2DROP 0 EXIT
                    THEN
                THEN
            THEN
        THEN
    REPEAT
    2DROP -1 ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================

0x53534348454D4157 CONSTANT _SSW-MAGIC  \ "SSCHEMAW"

  0 CONSTANT _SSW-MAGIC-OFF
  8 CONSTANT _SSW-SELF-OFF
 16 CONSTANT _SSW-BYTES-OFF
 24 CONSTANT _SSW-DEPTH-LIMIT-OFF
 32 CONSTANT _SSW-PHASE-OFF
 40 CONSTANT _SSW-SCHEMA-NODES-OFF
 48 CONSTANT _SSW-SCHEMA-DEPTH-OFF
 56 CONSTANT _SSW-VALUE-NODES-OFF
 64 CONSTANT _SSW-VALUE-DEPTH-OFF
 72 CONSTANT _SSW-EXPECTED-NODES-OFF
 80 CONSTANT _SSW-EXPECTED-DEPTH-OFF
 88 CONSTANT _SSW-VALUE-NODE-LIMIT-OFF
 96 CONSTANT _SSW-RESERVED-A-OFF
104 CONSTANT _SSW-RESERVED-B-OFF
112 CONSTANT _SSW-FRAMES-OFF

0 CONSTANT _SS-PHASE-IDLE
1 CONSTANT _SS-PHASE-SCHEMA
2 CONSTANT _SS-PHASE-VALUE
3 CONSTANT _SS-PHASE-MATCH

: _SSW.MAGIC             ( work -- address ) _SSW-MAGIC-OFF + ;
: _SSW.SELF              ( work -- address ) _SSW-SELF-OFF + ;
: _SSW.BYTES             ( work -- address ) _SSW-BYTES-OFF + ;
: _SSW.DEPTH-LIMIT       ( work -- address ) _SSW-DEPTH-LIMIT-OFF + ;
: _SSW.PHASE             ( work -- address ) _SSW-PHASE-OFF + ;
: _SSW.SCHEMA-NODES      ( work -- address ) _SSW-SCHEMA-NODES-OFF + ;
: _SSW.SCHEMA-DEPTH      ( work -- address ) _SSW-SCHEMA-DEPTH-OFF + ;
: _SSW.VALUE-NODES       ( work -- address ) _SSW-VALUE-NODES-OFF + ;
: _SSW.VALUE-DEPTH       ( work -- address ) _SSW-VALUE-DEPTH-OFF + ;
: _SSW.EXPECTED-NODES    ( work -- address ) _SSW-EXPECTED-NODES-OFF + ;
: _SSW.EXPECTED-DEPTH    ( work -- address ) _SSW-EXPECTED-DEPTH-OFF + ;
: _SSW.VALUE-NODE-LIMIT  ( work -- address ) _SSW-VALUE-NODE-LIMIT-OFF + ;
: _SSW.RESERVED-A        ( work -- address ) _SSW-RESERVED-A-OFF + ;
: _SSW.RESERVED-B        ( work -- address ) _SSW-RESERVED-B-OFF + ;

\ One frame is reused at a given depth.  Recursive children use the next
\ frame, so parent cursors survive without globals or allocator state.
  0 CONSTANT _SSF-CURSOR-OFF
  8 CONSTANT _SSF-REMAIN-OFF
 16 CONSTANT _SSF-COUNT-OFF
 24 CONSTANT _SSF-PREV-A-OFF
 32 CONSTANT _SSF-PREV-U-OFF
 40 CONSTANT _SSF-KEY-A-OFF
 48 CONSTANT _SSF-KEY-U-OFF
 56 CONSTANT _SSF-CHILD-A-OFF
 64 CONSTANT _SSF-CHILD-U-OFF
 72 CONSTANT _SSF-ADVANCE-OFF
 80 CONSTANT _SSF-FLAGS-OFF
 88 CONSTANT _SSF-DEPTH-OFF
 96 CONSTANT _SSF-WORK-OFF
104 CONSTANT _SSF-USED-OFF
112 CONSTANT _SSF-NODE-A-OFF
120 CONSTANT _SSF-NODE-U-OFF
128 CONSTANT _SSF-VCURSOR-OFF
136 CONSTANT _SSF-VREMAIN-OFF
144 CONSTANT _SSF-VCOUNT-OFF
152 CONSTANT _SSF-VKEY-A-OFF
160 CONSTANT _SSF-VKEY-U-OFF
168 CONSTANT _SSF-VCHILD-A-OFF
176 CONSTANT _SSF-VCHILD-U-OFF
184 CONSTANT _SSF-VADVANCE-OFF
192 CONSTANT _SSF-HAS-PREV-OFF
200 CONSTANT _SSF-RESERVED-OFF
208 CONSTANT _SSF-SIZE

: _SSF.CURSOR     ( frame -- address ) _SSF-CURSOR-OFF + ;
: _SSF.REMAIN     ( frame -- address ) _SSF-REMAIN-OFF + ;
: _SSF.COUNT      ( frame -- address ) _SSF-COUNT-OFF + ;
: _SSF.PREV-A     ( frame -- address ) _SSF-PREV-A-OFF + ;
: _SSF.PREV-U     ( frame -- address ) _SSF-PREV-U-OFF + ;
: _SSF.KEY-A      ( frame -- address ) _SSF-KEY-A-OFF + ;
: _SSF.KEY-U      ( frame -- address ) _SSF-KEY-U-OFF + ;
: _SSF.CHILD-A    ( frame -- address ) _SSF-CHILD-A-OFF + ;
: _SSF.CHILD-U    ( frame -- address ) _SSF-CHILD-U-OFF + ;
: _SSF.ADVANCE    ( frame -- address ) _SSF-ADVANCE-OFF + ;
: _SSF.FLAGS      ( frame -- address ) _SSF-FLAGS-OFF + ;
: _SSF.DEPTH      ( frame -- address ) _SSF-DEPTH-OFF + ;
: _SSF.WORK       ( frame -- address ) _SSF-WORK-OFF + ;
: _SSF.USED       ( frame -- address ) _SSF-USED-OFF + ;
: _SSF.NODE-A     ( frame -- address ) _SSF-NODE-A-OFF + ;
: _SSF.NODE-U     ( frame -- address ) _SSF-NODE-U-OFF + ;
: _SSF.VCURSOR    ( frame -- address ) _SSF-VCURSOR-OFF + ;
: _SSF.VREMAIN    ( frame -- address ) _SSF-VREMAIN-OFF + ;
: _SSF.VCOUNT     ( frame -- address ) _SSF-VCOUNT-OFF + ;
: _SSF.VKEY-A     ( frame -- address ) _SSF-VKEY-A-OFF + ;
: _SSF.VKEY-U     ( frame -- address ) _SSF-VKEY-U-OFF + ;
: _SSF.VCHILD-A   ( frame -- address ) _SSF-VCHILD-A-OFF + ;
: _SSF.VCHILD-U   ( frame -- address ) _SSF-VCHILD-U-OFF + ;
: _SSF.VADVANCE   ( frame -- address ) _SSF-VADVANCE-OFF + ;
: _SSF.HAS-PREV   ( frame -- address ) _SSF-HAS-PREV-OFF + ;

: SBOX-SCHEMA-WORKSPACE-MEASURE  ( max-depth -- bytes|0 status )
    DUP 0> 0= IF DROP 0 SBOX-SCHEMA-S-INVALID EXIT THEN
    _SSF-SIZE SBOX-BYTE-LENGTH*
    DUP IF
        >R DROP 0
        R> SBOX-BYTE-S-INVALID = IF
            SBOX-SCHEMA-S-INVALID
        ELSE
            SBOX-SCHEMA-S-CAPACITY
        THEN
        EXIT
    THEN
    DROP
    _SSW-FRAMES-OFF SBOX-BYTE-LENGTH+
    DUP IF
        >R DROP 0
        R> SBOX-BYTE-S-INVALID = IF
            SBOX-SCHEMA-S-INVALID
        ELSE
            SBOX-SCHEMA-S-CAPACITY
        THEN
        EXIT
    THEN
    DROP SBOX-SCHEMA-S-OK ;

: SBOX-SCHEMA-WORKSPACE-INIT
  ( max-depth workspace workspace-u -- status )
    2 PICK SBOX-SCHEMA-WORKSPACE-MEASURE
    DUP IF
        >R DROP 2DROP DROP R> EXIT
    THEN
    DROP >R
    2DUP _SS-SPAN? 0= IF
        2DROP DROP R> DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    OVER 7 AND IF
        2DROP DROP R> DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    DUP R@ < IF
        2DROP DROP R> DROP SBOX-SCHEMA-S-CAPACITY EXIT
    THEN
    DROP
    DUP R@ CALLER-SPAN-STATUS _SS-CALLER>STATUS
    DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    DUP R@ 0 FILL
    DUP DUP _SSW.SELF !
    R@ OVER _SSW.BYTES !
    _SSW-MAGIC OVER _SSW.MAGIC !
    SWAP OVER _SSW.DEPTH-LIMIT !
    DROP R> DROP SBOX-SCHEMA-S-OK ;

: SBOX-SCHEMA-WORKSPACE-VALID?  ( workspace -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SSW-FRAMES-OFF CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK <> IF DROP 0 EXIT THEN
    DUP _SSW.MAGIC @ _SSW-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SSW.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SSW.DEPTH-LIMIT @ DUP 0> 0= IF 2DROP 0 EXIT THEN
    SBOX-SCHEMA-WORKSPACE-MEASURE
    DUP IF 2DROP DROP 0 EXIT THEN
    DROP
    OVER _SSW.BYTES @ <> IF DROP 0 EXIT THEN
    DUP DUP _SSW.BYTES @ CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK <> IF DROP 0 EXIT THEN
    DUP _SSW.PHASE @ DUP _SS-PHASE-IDLE <
        SWAP _SS-PHASE-MATCH > OR IF DROP 0 EXIT THEN
    DUP _SSW.RESERVED-A @ IF DROP 0 EXIT THEN
    _SSW.RESERVED-B @ 0= ;

: _SS-FRAME  ( depth workspace -- frame )
    _SSW-FRAMES-OFF +
    SWAP 1- _SSF-SIZE * + ;

: _SS-WORK-CLEAR-FRAMES  ( workspace -- )
    DUP _SSW.BYTES @ _SSW-FRAMES-OFF -
    SWAP _SSW-FRAMES-OFF + SWAP 0 FILL ;

: _SS-WORK-BEGIN  ( phase workspace -- status )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? 0= IF
        2DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    DUP _SSW.PHASE @ _SS-PHASE-IDLE <> IF
        2DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    DUP _SS-WORK-CLEAR-FRAMES
    0 OVER _SSW.SCHEMA-NODES !
    0 OVER _SSW.SCHEMA-DEPTH !
    0 OVER _SSW.VALUE-NODES !
    0 OVER _SSW.VALUE-DEPTH !
    0 OVER _SSW.EXPECTED-NODES !
    0 OVER _SSW.EXPECTED-DEPTH !
    0 OVER _SSW.VALUE-NODE-LIMIT !
    SWAP OVER _SSW.PHASE !
    DROP SBOX-SCHEMA-S-OK ;

: _SS-WORK-PHASE!  ( phase workspace -- )
    DUP _SS-WORK-CLEAR-FRAMES
    SWAP OVER _SSW.PHASE ! DROP ;

: _SS-WORK-END  ( workspace -- )
    DUP _SS-WORK-CLEAR-FRAMES
    0 OVER _SSW.EXPECTED-NODES !
    0 OVER _SSW.EXPECTED-DEPTH !
    0 OVER _SSW.VALUE-NODE-LIMIT !
    _SS-PHASE-IDLE SWAP _SSW.PHASE ! ;

: SBOX-SCHEMA-WORKSPACE-RELEASE  ( workspace -- status )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? 0= IF
        DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    DUP _SSW.BYTES @ 0 FILL SBOX-SCHEMA-S-OK ;

: SBOX-SCHEMA-WORKSPACE-MAX-DEPTH@  ( workspace -- depth|0 )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? IF
        _SSW.DEPTH-LIMIT @
    ELSE
        DROP 0
    THEN ;

: SBOX-SCHEMA-WORKSPACE-SCHEMA-NODES@  ( workspace -- count|0 )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? IF
        _SSW.SCHEMA-NODES @
    ELSE
        DROP 0
    THEN ;

: SBOX-SCHEMA-WORKSPACE-SCHEMA-DEPTH@  ( workspace -- depth|0 )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? IF
        _SSW.SCHEMA-DEPTH @
    ELSE
        DROP 0
    THEN ;

: SBOX-SCHEMA-WORKSPACE-VALUE-NODES@  ( workspace -- count|0 )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? IF
        _SSW.VALUE-NODES @
    ELSE
        DROP 0
    THEN ;

: SBOX-SCHEMA-WORKSPACE-VALUE-DEPTH@  ( workspace -- depth|0 )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? IF
        _SSW.VALUE-DEPTH @
    ELSE
        DROP 0
    THEN ;

: _SS-WORK-OVERLAP?  ( address length workspace -- flag )
    DUP _SSW.BYTES @ MSPAN-OVERLAP? ;

\ =====================================================================
\  Shared frame mechanics
\ =====================================================================

: _SS-FRAME-BIND-NODE
  ( node node-u depth workspace frame -- )
    >R
    R@ _SSF-SIZE 0 FILL
    DUP R@ _SSF.WORK !
    OVER R@ _SSF.DEPTH !
    3 PICK R@ _SSF.NODE-A !
    2 PICK R@ _SSF.NODE-U !
    2DROP 2DROP
    R> DROP ;

: _SS-FRAME-BIND-MATCH
  ( schema schema-u value value-u depth workspace frame -- )
    >R
    R@ _SSF-SIZE 0 FILL
    DUP R@ _SSF.WORK !
    OVER R@ _SSF.DEPTH !
    5 PICK R@ _SSF.NODE-A !
    4 PICK R@ _SSF.NODE-U !
    3 PICK R@ _SSF.VCURSOR !
    2 PICK R@ _SSF.VREMAIN !
    2DROP 2DROP 2DROP
    R> DROP ;

: _SS-FRAME-ADVANCE  ( bytes frame -- flag )
    >R
    DUP 0< IF DROP R> DROP 0 EXIT THEN
    DUP R@ _SSF.REMAIN @ U> IF DROP R> DROP 0 EXIT THEN
    DUP R@ _SSF.CURSOR +!
    NEGATE R@ _SSF.REMAIN +!
    R> DROP -1 ;

: _SS-FRAME-VADVANCE  ( bytes frame -- flag )
    >R
    DUP 0< IF DROP R> DROP 0 EXIT THEN
    DUP R@ _SSF.VREMAIN @ U> IF DROP R> DROP 0 EXIT THEN
    DUP R@ _SSF.VCURSOR +!
    NEGATE R@ _SSF.VREMAIN +!
    R> DROP -1 ;

: _SS-ENTER-SCHEMA  ( depth workspace -- frame|0 status )
    >R
    DUP 0> 0= IF DROP R> DROP 0 SBOX-SCHEMA-S-INVALID EXIT THEN
    DUP R@ _SSW.EXPECTED-DEPTH @ > IF
        DROP R> DROP 0 SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSW.SCHEMA-NODES @ R@ _SSW.EXPECTED-NODES @ >= IF
        DROP R> DROP 0 SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    1 R@ _SSW.SCHEMA-NODES +!
    DUP R@ _SSW.SCHEMA-DEPTH @ > IF
        DUP R@ _SSW.SCHEMA-DEPTH !
    THEN
    DUP R@ _SS-FRAME SWAP DROP
    R> DROP SBOX-SCHEMA-S-OK ;

: _SS-ENTER-VALUE  ( depth workspace -- frame|0 status )
    >R
    DUP 0> 0= IF DROP R> DROP 0 SBOX-SCHEMA-S-INVALID EXIT THEN
    DUP R@ _SSW.DEPTH-LIMIT @ > IF
        DROP R> DROP 0 SBOX-SCHEMA-S-CAPACITY EXIT
    THEN
    R@ _SSW.VALUE-NODES @ R@ _SSW.VALUE-NODE-LIMIT @ >= IF
        DROP R> DROP 0 SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    1 R@ _SSW.VALUE-NODES +!
    DUP R@ _SSW.VALUE-DEPTH @ > IF
        DUP R@ _SSW.VALUE-DEPTH !
    THEN
    DUP R@ _SS-FRAME SWAP DROP
    R> DROP SBOX-SCHEMA-S-OK ;

: _SS-ENTER-MATCH  ( depth workspace -- frame|0 status )
    >R
    DUP 0> 0= IF DROP R> DROP 0 SBOX-SCHEMA-S-INVALID EXIT THEN
    DUP R@ _SSW.DEPTH-LIMIT @ > IF
        DROP R> DROP 0 SBOX-SCHEMA-S-CAPACITY EXIT
    THEN
    DUP R@ _SS-FRAME SWAP DROP
    R> DROP SBOX-SCHEMA-S-OK ;

\ =====================================================================
\  Canonical schema document validation
\ =====================================================================

: _SS-SCHEMA-HEADER  ( frame -- status )
    >R
    R@ _SSF.NODE-U @ SBOX-SCHEMA-NODE-HEADER-SIZE < IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSF.NODE-A @ DUP C@ SBOX-SCHEMA-TYPE-VALID? 0= IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP 1+ C@ IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP 2 + _SS-U16@ IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DROP
    R@ _SSF.NODE-A @ 24 + _SS-U64@ DUP 0< IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    SBOX-SCHEMA-NODE-HEADER-SIZE SBOX-BYTE-LENGTH+
    DUP IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DROP
    DUP R@ _SSF.NODE-U @ U> IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP R@ _SSF.USED !
    DROP
    R@ _SSF.NODE-A @ SBOX-SCHEMA-NODE-HEADER-SIZE +
        R@ _SSF.CURSOR !
    R@ _SSF.NODE-A @ 24 + _SS-U64@ R@ _SSF.REMAIN !
    R@ _SSF.NODE-A @ 4 + _SS-U32@ R@ _SSF.COUNT !
    R> DROP SBOX-SCHEMA-S-OK ;

: _SS-SCHEMA-ZERO-SHAPE?  ( frame -- flag )
    DUP _SSF.COUNT @ 0=
    OVER _SSF.NODE-A @ 8 + _SS-U64@ 0= AND
    OVER _SSF.NODE-A @ 16 + _SS-U64@ 0= AND
    SWAP _SSF.REMAIN @ 0= AND ;

: _SS-SCHEMA-BOUNDS?  ( frame -- flag )
    DUP _SSF.COUNT @ IF DROP 0 EXIT THEN
    DUP _SSF.REMAIN @ IF DROP 0 EXIT THEN
    DUP _SSF.NODE-A @ 8 + _SS-U64@ DUP 0< IF
        2DROP 0 EXIT
    THEN
    OVER _SSF.NODE-A @ 16 + _SS-U64@ DUP 0< IF
        2DROP DROP 0 EXIT
    THEN
    >R SWAP DROP R> <= ;

: _SS-SCHEMA-LIST-SHAPE?  ( frame -- flag )
    DUP _SSF.COUNT @ 1 <> IF DROP 0 EXIT THEN
    DUP _SSF.REMAIN @ SBOX-SCHEMA-NODE-HEADER-SIZE < IF
        DROP 0 EXIT
    THEN
    DUP _SSF.NODE-A @ 8 + _SS-U64@ DUP 0< IF
        2DROP 0 EXIT
    THEN
    OVER _SSF.NODE-A @ 16 + _SS-U64@ DUP 0< IF
        2DROP DROP 0 EXIT
    THEN
    >R SWAP DROP R> <= ;

: _SS-SCHEMA-MAP-SHAPE?  ( frame -- flag )
    DUP _SSF.NODE-A @ 8 + _SS-U64@ 0=
    SWAP _SSF.NODE-A @ 16 + _SS-U64@ 0= AND ;

: _SS-SCHEMA-FIELD-PREP  ( frame -- status )
    >R
    R@ _SSF.COUNT @ 0> 0= IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSF.REMAIN @ SBOX-SCHEMA-FIELD-HEADER-SIZE < IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSF.CURSOR @ DUP 4 + C@
    DUP SBOX-SCHEMA-FIELD-FLAGS-VALID? 0= IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSF.FLAGS !
    DUP 5 + C@ IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP 6 + _SS-U16@ IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP _SS-U32@ R@ _SSF.KEY-U !
    8 + _SS-U64@ DUP 0< IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP SBOX-SCHEMA-NODE-HEADER-SIZE < IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSF.CHILD-U !
    SBOX-SCHEMA-FIELD-HEADER-SIZE R@ _SSF.KEY-U @
        SBOX-BYTE-LENGTH+
    DUP IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DROP
    R@ _SSF.CHILD-U @ SBOX-BYTE-LENGTH+
    DUP IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DROP
    DUP R@ _SSF.REMAIN @ U> IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSF.ADVANCE !
    R@ _SSF.CURSOR @ SBOX-SCHEMA-FIELD-HEADER-SIZE +
        DUP R@ _SSF.KEY-A !
    R@ _SSF.KEY-U @ _SS-UTF8? 0= IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSF.HAS-PREV @ IF
        R@ _SSF.PREV-A @ R@ _SSF.PREV-U @
        R@ _SSF.KEY-A @ R@ _SSF.KEY-U @
        COMPARE 0< 0= IF
            R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
        THEN
    THEN
    R@ _SSF.KEY-A @ R@ _SSF.PREV-A !
    R@ _SSF.KEY-U @ R@ _SSF.PREV-U !
    -1 R@ _SSF.HAS-PREV !
    R@ _SSF.KEY-A @ R@ _SSF.KEY-U @ +
        R@ _SSF.CHILD-A !
    R@ _SSF.ADVANCE @ R@ _SS-FRAME-ADVANCE 0= IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    -1 R@ _SSF.COUNT +!
    R> DROP SBOX-SCHEMA-S-OK ;

: _SS-SCHEMA-ZERO-TAG  ( self-xt frame -- status )
    NIP _SS-SCHEMA-ZERO-SHAPE?
    IF SBOX-SCHEMA-S-OK ELSE SBOX-SCHEMA-S-MALFORMED-SCHEMA THEN ;

: _SS-SCHEMA-BOUNDS-TAG  ( self-xt frame -- status )
    NIP _SS-SCHEMA-BOUNDS?
    IF SBOX-SCHEMA-S-OK ELSE SBOX-SCHEMA-S-MALFORMED-SCHEMA THEN ;

: _SS-SCHEMA-LIST-TAG  ( self-xt frame -- status )
    DUP _SS-SCHEMA-LIST-SHAPE? 0= IF
        2DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP _SSF.CURSOR @
    1 PICK _SSF.REMAIN @
    2 PICK _SSF.DEPTH @ 1+
    3 PICK _SSF.WORK @
    5 PICK DUP EXECUTE
    DUP IF
        >R DROP 2DROP R> EXIT
    THEN
    DROP
    1 PICK _SSF.REMAIN @ <> IF
        2DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    0 OVER _SSF.REMAIN !
    0 OVER _SSF.COUNT !
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-SCHEMA-MAP-ONE  ( self-xt frame -- status )
    DUP _SS-SCHEMA-FIELD-PREP ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP _SSF.CHILD-A @
    1 PICK _SSF.CHILD-U @
    2 PICK _SSF.DEPTH @ 1+
    3 PICK _SSF.WORK @
    5 PICK DUP EXECUTE
    DUP IF
        >R DROP 2DROP R> EXIT
    THEN
    DROP
    1 PICK _SSF.CHILD-U @ <> IF
        2DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-SCHEMA-MAP-TAG  ( self-xt frame -- status )
    DUP _SS-SCHEMA-MAP-SHAPE? 0= IF
        2DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    BEGIN DUP _SSF.COUNT @ 0> WHILE
        2DUP _SS-SCHEMA-MAP-ONE ?DUP IF
            >R 2DROP R> EXIT
        THEN
    REPEAT
    DUP _SSF.REMAIN @ IF
        2DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-SCHEMA-TAG-DISPATCH  ( self-xt frame -- status )
    DUP _SSF.NODE-A @ C@
    CASE
        SBOX-SCHEMA-T-NULL OF _SS-SCHEMA-ZERO-TAG ENDOF
        SBOX-SCHEMA-T-BOOL OF _SS-SCHEMA-ZERO-TAG ENDOF
        SBOX-SCHEMA-T-I64  OF _SS-SCHEMA-ZERO-TAG ENDOF
        SBOX-SCHEMA-T-BYTES OF _SS-SCHEMA-BOUNDS-TAG ENDOF
        SBOX-SCHEMA-T-UTF8  OF _SS-SCHEMA-BOUNDS-TAG ENDOF
        SBOX-SCHEMA-T-LIST OF _SS-SCHEMA-LIST-TAG ENDOF
        SBOX-SCHEMA-T-MAP  OF _SS-SCHEMA-MAP-TAG ENDOF
    ENDCASE ;

: _SS-SCHEMA-NODE-R
  ( node node-u depth workspace self-xt -- used|0 status )
    >R
    2DUP _SS-ENTER-SCHEMA
    DUP IF
        >R DROP 2DROP 2DROP 0 R> R> DROP EXIT
    THEN
    DROP >R
    R@ _SS-FRAME-BIND-NODE
    R@ _SS-SCHEMA-HEADER
    DUP IF R> DROP 0 SWAP R> DROP EXIT THEN
    DROP
    R> R> SWAP DUP >R
    R@ _SS-SCHEMA-TAG-DISPATCH
    DUP IF R> DROP 0 SWAP EXIT THEN
    DROP
    R@ _SSF.USED @ R> DROP SBOX-SCHEMA-S-OK ;

: _SS-SCHEMA-DOCUMENT  ( schema schema-u workspace -- status )
    >R
    DUP SBOX-SCHEMA-DOCUMENT-HEADER-SIZE
        SBOX-SCHEMA-NODE-HEADER-SIZE + < IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    OVER _SS-U64@ SBOX-SCHEMA-DOCUMENT-MAGIC <> IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    OVER 8 + _SS-U16@ SBOX-SCHEMA-DOCUMENT-VERSION <> IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    OVER 10 + _SS-U16@ IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    OVER 20 + _SS-U32@ IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    OVER 24 + _SS-U64@ DUP 0< IF
        DROP 2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    OVER <> IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    OVER 12 + _SS-U32@ DUP 0= IF
        DROP 2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSW.EXPECTED-NODES !
    OVER 16 + _SS-U32@ DUP 0= IF
        DROP 2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    DUP R@ _SSW.DEPTH-LIMIT @ > IF
        DROP 2DROP R> DROP SBOX-SCHEMA-S-CAPACITY EXIT
    THEN
    R@ _SSW.EXPECTED-DEPTH !
    OVER SBOX-SCHEMA-DOCUMENT-HEADER-SIZE +
    OVER SBOX-SCHEMA-DOCUMENT-HEADER-SIZE -
    1 R@ ['] _SS-SCHEMA-NODE-R DUP EXECUTE
    DUP IF
        >R DROP 2DROP R> R> DROP EXIT
    THEN
    DROP
    ROT DROP SWAP SBOX-SCHEMA-DOCUMENT-HEADER-SIZE - <> IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSW.SCHEMA-NODES @ R@ _SSW.EXPECTED-NODES @ <> IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R@ _SSW.SCHEMA-DEPTH @ R@ _SSW.EXPECTED-DEPTH @ <> IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-SCHEMA EXIT
    THEN
    R> DROP SBOX-SCHEMA-S-OK ;

\ =====================================================================
\  Independent canonical value validation
\ =====================================================================

: _SS-VALUE-EXTENT  ( value available-u -- used|0 status )
    DUP 16 < IF 2DROP 0 SBOX-SCHEMA-S-MALFORMED-VALUE EXIT THEN
    OVER 8 + _SS-U64@ DUP 0< IF
        DROP 2DROP 0 SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    16 SBOX-BYTE-LENGTH+
    DUP IF
        2DROP 2DROP 0 SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP
    DUP 2 PICK U> IF
        DROP 2DROP 0 SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    >R 2DROP R> SBOX-SCHEMA-S-OK ;

: _SS-VALUE-HEADER  ( frame -- status )
    >R
    R@ _SSF.NODE-U @ 16 < IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R@ _SSF.NODE-A @ DUP C@ SBOX-SCHEMA-TYPE-VALID? 0= IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DUP 1+ C@ IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DUP 2 + _SS-U16@ IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP
    R@ _SSF.NODE-A @ R@ _SSF.NODE-U @ _SS-VALUE-EXTENT
    DUP IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP R@ _SSF.USED !
    R@ _SSF.NODE-A @ 16 + R@ _SSF.CURSOR !
    R@ _SSF.NODE-A @ 8 + _SS-U64@ R@ _SSF.REMAIN !
    R@ _SSF.NODE-A @ 4 + _SS-U32@ R@ _SSF.COUNT !
    R> DROP SBOX-SCHEMA-S-OK ;

: _SS-VALUE-NULL-TAG  ( self-xt frame -- status )
    NIP DUP _SSF.COUNT @ SWAP _SSF.REMAIN @ OR
    IF SBOX-SCHEMA-S-MALFORMED-VALUE ELSE SBOX-SCHEMA-S-OK THEN ;

: _SS-VALUE-BOOL-TAG  ( self-xt frame -- status )
    NIP
    >R
    R@ _SSF.COUNT @ IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R@ _SSF.REMAIN @ 8 <> IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R@ _SSF.CURSOR @ _SS-U64@
    DUP 0= SWAP -1 = OR
    R> DROP
    IF SBOX-SCHEMA-S-OK ELSE SBOX-SCHEMA-S-MALFORMED-VALUE THEN ;

: _SS-VALUE-I64-TAG  ( self-xt frame -- status )
    NIP
    DUP _SSF.COUNT @ IF
        DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    _SSF.REMAIN @ 8 =
    IF SBOX-SCHEMA-S-OK ELSE SBOX-SCHEMA-S-MALFORMED-VALUE THEN ;

: _SS-VALUE-BYTES-TAG  ( self-xt frame -- status )
    NIP
    _SSF.COUNT @ 0=
    IF SBOX-SCHEMA-S-OK ELSE SBOX-SCHEMA-S-MALFORMED-VALUE THEN ;

: _SS-VALUE-UTF8-TAG  ( self-xt frame -- status )
    NIP
    >R
    R@ _SSF.COUNT @ IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R@ _SSF.CURSOR @ R@ _SSF.REMAIN @ _SS-UTF8?
    R> DROP
    IF SBOX-SCHEMA-S-OK ELSE SBOX-SCHEMA-S-MALFORMED-VALUE THEN ;

: _SS-VALUE-LIST-ONE  ( self-xt frame -- status )
    DUP _SSF.CURSOR @
    1 PICK _SSF.REMAIN @
    2 PICK _SSF.DEPTH @ 1+
    3 PICK _SSF.WORK @
    5 PICK DUP EXECUTE
    DUP IF
        >R DROP 2DROP R> EXIT
    THEN
    DROP
    DUP 2 PICK _SS-FRAME-ADVANCE 0= IF
        DROP 2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP
    -1 OVER _SSF.COUNT +!
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-VALUE-LIST-TAG  ( self-xt frame -- status )
    BEGIN DUP _SSF.COUNT @ 0> WHILE
        2DUP _SS-VALUE-LIST-ONE ?DUP IF
            >R 2DROP R> EXIT
        THEN
    REPEAT
    DUP _SSF.REMAIN @ IF
        2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-VALUE-MAP-KEY  ( self-xt frame -- status )
    DUP _SSF.REMAIN @ 16 < IF
        2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DUP _SSF.CURSOR @ C@ SBOX-SCHEMA-T-UTF8 <> IF
        2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DUP _SSF.CURSOR @
    1 PICK _SSF.REMAIN @
    2 PICK _SSF.DEPTH @ 1+
    3 PICK _SSF.WORK @
    5 PICK DUP EXECUTE
    DUP IF
        >R DROP 2DROP R> EXIT
    THEN
    DROP
    DUP 2 PICK _SSF.ADVANCE !
    DROP NIP >R
    R@ _SSF.CURSOR @ 16 + R@ _SSF.KEY-A !
    R@ _SSF.CURSOR @ 8 + _SS-U64@ R@ _SSF.KEY-U !
    R@ _SSF.HAS-PREV @ IF
        R@ _SSF.PREV-A @ R@ _SSF.PREV-U @
        R@ _SSF.KEY-A @ R@ _SSF.KEY-U @
        COMPARE 0< 0= IF
            R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
        THEN
    THEN
    R@ _SSF.KEY-A @ R@ _SSF.PREV-A !
    R@ _SSF.KEY-U @ R@ _SSF.PREV-U !
    -1 R@ _SSF.HAS-PREV !
    R@ _SSF.ADVANCE @ R@ _SS-FRAME-ADVANCE 0= IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R> DROP SBOX-SCHEMA-S-OK ;

: _SS-VALUE-MAP-VALUE  ( self-xt frame -- status )
    DUP _SSF.CURSOR @
    1 PICK _SSF.REMAIN @
    2 PICK _SSF.DEPTH @ 1+
    3 PICK _SSF.WORK @
    5 PICK DUP EXECUTE
    DUP IF
        >R DROP 2DROP R> EXIT
    THEN
    DROP
    DUP 2 PICK _SS-FRAME-ADVANCE 0= IF
        DROP 2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP
    -1 OVER _SSF.COUNT +!
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-VALUE-MAP-ONE  ( self-xt frame -- status )
    2DUP _SS-VALUE-MAP-KEY ?DUP IF
        >R 2DROP R> EXIT
    THEN
    _SS-VALUE-MAP-VALUE ;

: _SS-VALUE-MAP-TAG  ( self-xt frame -- status )
    BEGIN DUP _SSF.COUNT @ 0> WHILE
        2DUP _SS-VALUE-MAP-ONE ?DUP IF
            >R 2DROP R> EXIT
        THEN
    REPEAT
    DUP _SSF.REMAIN @ IF
        2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-VALUE-TAG-DISPATCH  ( self-xt frame -- status )
    DUP _SSF.NODE-A @ C@
    CASE
        SBOX-SCHEMA-T-NULL  OF _SS-VALUE-NULL-TAG ENDOF
        SBOX-SCHEMA-T-BOOL  OF _SS-VALUE-BOOL-TAG ENDOF
        SBOX-SCHEMA-T-I64   OF _SS-VALUE-I64-TAG ENDOF
        SBOX-SCHEMA-T-BYTES OF _SS-VALUE-BYTES-TAG ENDOF
        SBOX-SCHEMA-T-UTF8  OF _SS-VALUE-UTF8-TAG ENDOF
        SBOX-SCHEMA-T-LIST  OF _SS-VALUE-LIST-TAG ENDOF
        SBOX-SCHEMA-T-MAP   OF _SS-VALUE-MAP-TAG ENDOF
    ENDCASE ;

: _SS-VALUE-NODE-R
  ( value value-u depth workspace self-xt -- used|0 status )
    >R
    2DUP _SS-ENTER-VALUE
    DUP IF
        >R DROP 2DROP 2DROP 0 R> R> DROP EXIT
    THEN
    DROP >R
    R@ _SS-FRAME-BIND-NODE
    R@ _SS-VALUE-HEADER
    DUP IF R> DROP 0 SWAP R> DROP EXIT THEN
    DROP
    R> R> SWAP DUP >R
    R@ _SS-VALUE-TAG-DISPATCH
    DUP IF R> DROP 0 SWAP EXIT THEN
    DROP
    R@ _SSF.USED @ R> DROP SBOX-SCHEMA-S-OK ;

: _SS-VALUE-DOCUMENT  ( value value-u workspace -- status )
    >R
    DUP 16 < IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DUP 16 / R@ _SSW.VALUE-NODE-LIMIT !
    OVER OVER
    1 R@ ['] _SS-VALUE-NODE-R DUP EXECUTE
    DUP IF
        >R DROP 2DROP R> R> DROP EXIT
    THEN
    DROP
    ROT DROP <> IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R> DROP SBOX-SCHEMA-S-OK ;

\ =====================================================================
\  Matching an already-valid value against an already-valid schema
\ =====================================================================

: _SS-MATCH-BLOB?  ( frame -- flag )
    DUP _SSF.VCURSOR @ 8 + _SS-U64@
    OVER _SSF.NODE-A @ 8 + _SS-U64@ >=
    SWAP
    DUP _SSF.VCURSOR @ 8 + _SS-U64@
    SWAP _SSF.NODE-A @ 16 + _SS-U64@ <= AND ;

: _SS-MATCH-LIST?  ( frame -- flag )
    DUP _SSF.VCURSOR @ 4 + _SS-U32@
    OVER _SSF.NODE-A @ 8 + _SS-U64@ >=
    SWAP
    DUP _SSF.VCURSOR @ 4 + _SS-U32@
    SWAP _SSF.NODE-A @ 16 + _SS-U64@ <= AND ;

: _SS-MATCH-VPAIR-PREP  ( frame -- status )
    >R
    R@ _SSF.VCOUNT @ 0> 0= IF
        R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R@ _SSF.VCURSOR @ R@ _SSF.VREMAIN @ _SS-VALUE-EXTENT
    DUP IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP
    R@ _SSF.VCURSOR @ C@ SBOX-SCHEMA-T-UTF8 <> IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R@ _SSF.ADVANCE !
    R@ _SSF.VCURSOR @ 16 + R@ _SSF.VKEY-A !
    R@ _SSF.VCURSOR @ 8 + _SS-U64@ R@ _SSF.VKEY-U !
    R@ _SSF.VCURSOR @ R@ _SSF.ADVANCE @ +
        R@ _SSF.VCHILD-A !
    R@ _SSF.VREMAIN @ R@ _SSF.ADVANCE @ -
        R@ _SSF.VCHILD-A @ SWAP _SS-VALUE-EXTENT
    DUP IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP
    DUP R@ _SSF.VCHILD-U !
    R@ _SSF.ADVANCE @ SBOX-BYTE-LENGTH+
    DUP IF
        2DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    DROP
    DUP R@ _SSF.VREMAIN @ U> IF
        DROP R> DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    R@ _SSF.VADVANCE !
    R> DROP SBOX-SCHEMA-S-OK ;

: _SS-MATCH-SCALAR-TAG  ( self-xt frame -- status )
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-MATCH-BLOB-TAG  ( self-xt frame -- status )
    NIP _SS-MATCH-BLOB?
    IF SBOX-SCHEMA-S-OK ELSE SBOX-SCHEMA-S-VALUE-MISMATCH THEN ;

: _SS-MATCH-LIST-TAG  ( self-xt frame -- status )
    DUP _SS-MATCH-LIST? 0= IF
        2DROP SBOX-SCHEMA-S-VALUE-MISMATCH EXIT
    THEN
    DUP _SSF.NODE-A @ SBOX-SCHEMA-NODE-HEADER-SIZE +
        OVER _SSF.CURSOR !
    DUP _SSF.NODE-A @ 24 + _SS-U64@ OVER _SSF.REMAIN !
    DUP _SSF.VCURSOR @ 8 + _SS-U64@ OVER _SSF.VREMAIN !
    DUP _SSF.VCURSOR @ 4 + _SS-U32@ OVER _SSF.VCOUNT !
    16 OVER _SSF.VCURSOR +!
    BEGIN DUP _SSF.VCOUNT @ 0> WHILE
        DUP _SSF.VCURSOR @ OVER _SSF.VREMAIN @ _SS-VALUE-EXTENT
        DUP IF
            >R DROP 2DROP R> EXIT
        THEN
        DROP
        DUP 2 PICK _SSF.VCHILD-U !
        DROP
        DUP _SSF.VCURSOR @ OVER _SSF.VCHILD-A !
        DUP _SSF.CURSOR @
        1 PICK _SSF.REMAIN @
        2 PICK _SSF.VCHILD-A @
        3 PICK _SSF.VCHILD-U @
        4 PICK _SSF.DEPTH @ 1+
        5 PICK _SSF.WORK @
        7 PICK DUP EXECUTE
        ?DUP IF
            >R 2DROP R> EXIT
        THEN
        DUP _SSF.VCHILD-U @ OVER _SS-FRAME-VADVANCE 0= IF
            2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
        THEN
        -1 OVER _SSF.VCOUNT +!
    REPEAT
    DUP _SSF.VREMAIN @ IF
        2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-MATCH-MAP-CONSUME  ( self-xt frame -- status )
    DUP _SSF.CHILD-A @
    1 PICK _SSF.CHILD-U @
    2 PICK _SSF.VCHILD-A @
    3 PICK _SSF.VCHILD-U @
    4 PICK _SSF.DEPTH @ 1+
    5 PICK _SSF.WORK @
    7 PICK DUP EXECUTE
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP _SSF.VADVANCE @ OVER _SS-FRAME-VADVANCE 0= IF
        2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    -1 OVER _SSF.VCOUNT +!
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-MATCH-MAP-ONE  ( self-xt frame -- status )
    DUP _SS-SCHEMA-FIELD-PREP ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP _SSF.VCOUNT @ 0= IF
        DUP _SSF.FLAGS @ SBOX-SCHEMA-FIELD-F-REQUIRED = IF
            2DROP SBOX-SCHEMA-S-VALUE-MISMATCH EXIT
        THEN
        2DROP SBOX-SCHEMA-S-OK EXIT
    THEN
    DUP _SS-MATCH-VPAIR-PREP ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP _SSF.KEY-A @ OVER _SSF.KEY-U @
    2 PICK _SSF.VKEY-A @ 3 PICK _SSF.VKEY-U @ COMPARE
    DUP 0< IF
        DROP
        DUP _SSF.FLAGS @ SBOX-SCHEMA-FIELD-F-REQUIRED = IF
            2DROP SBOX-SCHEMA-S-VALUE-MISMATCH EXIT
        THEN
        2DROP SBOX-SCHEMA-S-OK EXIT
    THEN
    DUP 0> IF
        DROP 2DROP SBOX-SCHEMA-S-VALUE-MISMATCH EXIT
    THEN
    DROP
    _SS-MATCH-MAP-CONSUME ;

: _SS-MATCH-MAP-TAG  ( self-xt frame -- status )
    DUP _SSF.NODE-A @ SBOX-SCHEMA-NODE-HEADER-SIZE +
        OVER _SSF.CURSOR !
    DUP _SSF.NODE-A @ 24 + _SS-U64@ OVER _SSF.REMAIN !
    DUP _SSF.NODE-A @ 4 + _SS-U32@ OVER _SSF.COUNT !
    DUP _SSF.VCURSOR @ 8 + _SS-U64@ OVER _SSF.VREMAIN !
    DUP _SSF.VCURSOR @ 4 + _SS-U32@ OVER _SSF.VCOUNT !
    16 OVER _SSF.VCURSOR +!
    BEGIN DUP _SSF.COUNT @ 0> WHILE
        2DUP _SS-MATCH-MAP-ONE ?DUP IF
            >R 2DROP R> EXIT
        THEN
    REPEAT
    DUP _SSF.VCOUNT @ IF
        2DROP SBOX-SCHEMA-S-VALUE-MISMATCH EXIT
    THEN
    DUP _SSF.VREMAIN @ IF
        2DROP SBOX-SCHEMA-S-MALFORMED-VALUE EXIT
    THEN
    2DROP SBOX-SCHEMA-S-OK ;

: _SS-MATCH-TAG-DISPATCH  ( self-xt frame -- status )
    DUP _SSF.NODE-A @ C@
    CASE
        SBOX-SCHEMA-T-NULL  OF _SS-MATCH-SCALAR-TAG ENDOF
        SBOX-SCHEMA-T-BOOL  OF _SS-MATCH-SCALAR-TAG ENDOF
        SBOX-SCHEMA-T-I64   OF _SS-MATCH-SCALAR-TAG ENDOF
        SBOX-SCHEMA-T-BYTES OF _SS-MATCH-BLOB-TAG ENDOF
        SBOX-SCHEMA-T-UTF8  OF _SS-MATCH-BLOB-TAG ENDOF
        SBOX-SCHEMA-T-LIST  OF _SS-MATCH-LIST-TAG ENDOF
        SBOX-SCHEMA-T-MAP   OF _SS-MATCH-MAP-TAG ENDOF
    ENDCASE ;

: _SS-MATCH-NODE-R
  ( schema schema-u value value-u depth workspace self-xt -- status )
    >R
    2DUP _SS-ENTER-MATCH
    DUP IF
        >R DROP 2DROP 2DROP 2DROP R> R> DROP EXIT
    THEN
    DROP >R
    R@ _SS-FRAME-BIND-MATCH
    R@ _SSF.NODE-A @ C@
    R@ _SSF.VCURSOR @ C@ <> IF
        R> DROP R> DROP SBOX-SCHEMA-S-VALUE-MISMATCH EXIT
    THEN
    R> R> SWAP DUP >R
    R@ _SS-MATCH-TAG-DISPATCH
    R> DROP ;

: _SS-MATCH-DOCUMENT
  ( schema schema-u value value-u workspace -- status )
    >R
    3 PICK SBOX-SCHEMA-DOCUMENT-HEADER-SIZE +
    3 PICK SBOX-SCHEMA-DOCUMENT-HEADER-SIZE -
    3 PICK 3 PICK
    1 R@ ['] _SS-MATCH-NODE-R DUP EXECUTE
    >R 2DROP 2DROP R> R> DROP ;

\ =====================================================================
\  Public synchronous operations
\ =====================================================================

: SBOX-SCHEMA-VALIDATE  ( schema schema-u workspace -- status )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? 0= IF
        2DROP DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    DUP _SSW.PHASE @ _SS-PHASE-IDLE <> IF
        2DROP DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    >R
    2DUP _SS-QUALIFY ?DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    2DUP R@ _SS-WORK-OVERLAP? IF
        2DROP R> DROP SBOX-SCHEMA-S-ALIAS EXIT
    THEN
    _SS-PHASE-SCHEMA R@ _SS-WORK-BEGIN ?DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    R@ _SS-SCHEMA-DOCUMENT
    R> _SS-WORK-END ;

: SBOX-SCHEMA-VALUE-VALIDATE
  ( schema schema-u value value-u workspace -- status )
    DUP SBOX-SCHEMA-WORKSPACE-VALID? 0= IF
        2DROP 2DROP DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    DUP _SSW.PHASE @ _SS-PHASE-IDLE <> IF
        2DROP 2DROP DROP SBOX-SCHEMA-S-INVALID EXIT
    THEN
    >R
    3 PICK 3 PICK _SS-QUALIFY ?DUP IF
        >R 2DROP 2DROP R> R> DROP EXIT
    THEN
    2DUP _SS-QUALIFY ?DUP IF
        >R 2DROP 2DROP R> R> DROP EXIT
    THEN
    3 PICK 3 PICK R@ _SS-WORK-OVERLAP? IF
        2DROP 2DROP R> DROP SBOX-SCHEMA-S-ALIAS EXIT
    THEN
    2DUP R@ _SS-WORK-OVERLAP? IF
        2DROP 2DROP R> DROP SBOX-SCHEMA-S-ALIAS EXIT
    THEN
    _SS-PHASE-SCHEMA R@ _SS-WORK-BEGIN ?DUP IF
        >R 2DROP 2DROP R> R> DROP EXIT
    THEN
    3 PICK 3 PICK R@ _SS-SCHEMA-DOCUMENT ?DUP IF
        >R 2DROP 2DROP R> R> _SS-WORK-END EXIT
    THEN
    _SS-PHASE-VALUE R@ _SS-WORK-PHASE!
    2DUP R@ _SS-VALUE-DOCUMENT ?DUP IF
        >R 2DROP 2DROP R> R> _SS-WORK-END EXIT
    THEN
    _SS-PHASE-MATCH R@ _SS-WORK-PHASE!
    R@ _SS-MATCH-DOCUMENT
    R> _SS-WORK-END ;
