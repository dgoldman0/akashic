\ =====================================================================
\  format.f - Sandbox checked scalar geometry and bounded byte reader
\ =====================================================================
\  This is the shared mechanical byte substrate for execution-profile,
\  artifact, typed-value, and compiler codecs.  It owns no format policy,
\  allocation, profile table, VM state, callback, or mutable global
\  scratch.
\
\  Reader state belongs entirely to the caller.  The owning public operation
\  MUST qualify each nonempty source and reader span with CALLER-SPAN-STATUS
\  and keep it mapped and quiescent for the reader lifetime.  This low-level
\  module proves geometry and aliasing; it is not a caller-memory boundary.
\  Under that contract reads are sequential and all-or-nothing for every
\  returned status.  The first invalid-length or capacity failure is sticky
\  and does not advance the offset.  After initialization, RESET clears that
\  status; successful reinitialization replaces the complete reader.
\
\  The production target has 8-bit address units, 64-bit two's-complement
\  cells, bitwise shifts, and logical RSHIFT.  Wire decoding never uses native
\  alignment or byte order.
\ =====================================================================

: _SBOX-BYTE-GEOMETRY-ABORT  ( -- )
    ." sandbox byte geometry mismatch" CR ABORT ;

\ Fail before registering the module or compiling its 64-bit wire geometry.
1 CELLS 8 <> [IF]
    _SBOX-BYTE-GEOMETRY-ABORT
[THEN]

PROVIDED akashic-sbx-format

REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Shared status and signed-length-safe arithmetic
\ =====================================================================

0 CONSTANT SBOX-BYTE-S-OK
1 CONSTANT SBOX-BYTE-S-INVALID
2 CONSTANT SBOX-BYTE-S-CAPACITY
3 CONSTANT SBOX-BYTE-S-ALIAS

-1 1 RSHIFT CONSTANT SBOX-BYTE-LENGTH-MAX

: SBOX-BYTE-STATUS-VALID?  ( status -- flag )
    DUP SBOX-BYTE-S-OK >=
    SWAP SBOX-BYTE-S-ALIAS <= AND ;

: _SBOX-BYTE-NONNEGATIVE-PAIR?  ( a b -- flag )
    2DUP 0< SWAP 0< OR 0= >R 2DROP R> ;

: SBOX-BYTE-LENGTH+  ( a b -- sum status )
    2DUP _SBOX-BYTE-NONNEGATIVE-PAIR? 0= IF
        2DROP 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    >R
    DUP SBOX-BYTE-LENGTH-MAX R@ - U> IF
        DROP R> DROP 0 SBOX-BYTE-S-CAPACITY EXIT
    THEN
    R> + SBOX-BYTE-S-OK ;

: SBOX-BYTE-LENGTH*  ( a b -- product status )
    2DUP _SBOX-BYTE-NONNEGATIVE-PAIR? 0= IF
        2DROP 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    DUP 0= IF 2DROP 0 SBOX-BYTE-S-OK EXIT THEN
    >R
    DUP SBOX-BYTE-LENGTH-MAX R@ / U> IF
        DROP R> DROP 0 SBOX-BYTE-S-CAPACITY EXIT
    THEN
    R> * SBOX-BYTE-S-OK ;

: _SBOX-BYTE-POWER-OF-TWO?  ( value -- flag )
    DUP 0> SWAP DUP 1- AND 0= AND ;

: SBOX-BYTE-ALIGN  ( length alignment -- padded status )
    DUP _SBOX-BYTE-POWER-OF-TWO? 0= IF
        2DROP 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    1- >R
    DUP 0< IF
        DROP R> DROP 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    DUP SBOX-BYTE-LENGTH-MAX R@ - U> IF
        DROP R> DROP 0 SBOX-BYTE-S-CAPACITY EXIT
    THEN
    R@ + R> INVERT AND SBOX-BYTE-S-OK ;

: SBOX-BYTE-PAD8  ( length -- padded status )
    8 SBOX-BYTE-ALIGN ;

: SBOX-BYTE-CEIL8  ( length -- units status )
    SBOX-BYTE-PAD8
    DUP IF >R DROP 0 R> EXIT THEN
    DROP 8 / SBOX-BYTE-S-OK ;

: SBOX-BYTE-PAD16  ( length -- padded status )
    16 SBOX-BYTE-ALIGN ;

\ Return a borrowed subspan only when both the source and requested
\ half-open interval are nonwrapping and signed-length-safe.
: SBOX-BYTE-SLICE  ( source source-u offset length -- slice length status )
    3 PICK 3 PICK
    DUP 0< IF
        2DROP 2DROP 2DROP 0 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    DUP 0> 2 PICK 0= AND IF
        2DROP 2DROP 2DROP 0 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    MSPAN-NONWRAPPING? 0= IF
        2DROP 2DROP 0 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    2DUP _SBOX-BYTE-NONNEGATIVE-PAIR? 0= IF
        2DROP 2DROP 0 0 SBOX-BYTE-S-INVALID EXIT
    THEN
    2 PICK 2 PICK U< IF
        2DROP 2DROP 0 0 SBOX-BYTE-S-CAPACITY EXIT
    THEN
    2 PICK 2 PICK - OVER SWAP U> IF
        2DROP 2DROP 0 0 SBOX-BYTE-S-CAPACITY EXIT
    THEN
    >R
    SWAP DROP +
    R> SBOX-BYTE-S-OK ;

\ =====================================================================
\  Caller-owned reader descriptor
\ =====================================================================

0x5342584259544552 CONSTANT _SBOX-BR-MAGIC  \ "SBXBYTER"

 0 CONSTANT _SBOX-BR-MAGIC-OFF
 8 CONSTANT _SBOX-BR-SELF-OFF
16 CONSTANT _SBOX-BR-SOURCE-OFF
24 CONSTANT _SBOX-BR-LENGTH-OFF
32 CONSTANT _SBOX-BR-OFFSET-OFF
40 CONSTANT _SBOX-BR-STATUS-OFF
48 CONSTANT _SBOX-BR-RESERVED-OFF
56 CONSTANT SBOX-BYTE-READER-SIZE

: _SBOX-BR.MAGIC     ( reader -- address ) _SBOX-BR-MAGIC-OFF + ;
: _SBOX-BR.SELF      ( reader -- address ) _SBOX-BR-SELF-OFF + ;
: _SBOX-BR.SOURCE    ( reader -- address ) _SBOX-BR-SOURCE-OFF + ;
: _SBOX-BR.LENGTH    ( reader -- address ) _SBOX-BR-LENGTH-OFF + ;
: _SBOX-BR.OFFSET    ( reader -- address ) _SBOX-BR-OFFSET-OFF + ;
: _SBOX-BR.STATUS    ( reader -- address ) _SBOX-BR-STATUS-OFF + ;
: _SBOX-BR.RESERVED  ( reader -- address ) _SBOX-BR-RESERVED-OFF + ;

: _SBOX-BR-SOURCE-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0> 2 PICK 0= AND IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: SBOX-BYTE-READER-VALID?  ( reader -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP SBOX-BYTE-READER-SIZE
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _SBOX-BR.MAGIC @ _SBOX-BR-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBOX-BR.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SBOX-BR.LENGTH @ DUP 0< IF 2DROP 0 EXIT THEN DROP
    DUP _SBOX-BR.OFFSET @ DUP 0< IF 2DROP 0 EXIT THEN DROP
    DUP _SBOX-BR.OFFSET @ OVER _SBOX-BR.LENGTH @ > IF DROP 0 EXIT THEN
    DUP _SBOX-BR.STATUS @ DUP SBOX-BYTE-S-OK <
        SWAP SBOX-BYTE-S-CAPACITY > OR IF DROP 0 EXIT THEN
    DUP _SBOX-BR.SOURCE @ OVER _SBOX-BR.LENGTH @
        _SBOX-BR-SOURCE-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SBOX-BR.SOURCE @ OVER _SBOX-BR.LENGTH @
        2 PICK SBOX-BYTE-READER-SIZE MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    _SBOX-BR.RESERVED @ 0= ;

: SBOX-BYTE-READER-INIT  ( source source-u reader -- status )
    >R
    2DUP _SBOX-BR-SOURCE-SPAN? 0= IF
        2DROP R> DROP SBOX-BYTE-S-INVALID EXIT
    THEN
    R@ 0= IF 2DROP R> DROP SBOX-BYTE-S-INVALID EXIT THEN
    R@ SBOX-BYTE-READER-SIZE
        MSPAN-NONWRAPPING? 0= IF
        2DROP R> DROP SBOX-BYTE-S-INVALID EXIT
    THEN
    2DUP R@ SBOX-BYTE-READER-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP SBOX-BYTE-S-ALIAS EXIT
    THEN
    \ Explicit invalidation makes reinitialization fail closed even if a
    \ contained native fault interrupts later staging.
    0 R@ _SBOX-BR.MAGIC !
    R@ SBOX-BYTE-READER-SIZE 0 FILL
    R@ R@ _SBOX-BR.SELF !
    OVER R@ _SBOX-BR.SOURCE !
    DUP R@ _SBOX-BR.LENGTH !
    _SBOX-BR-MAGIC R@ _SBOX-BR.MAGIC !
    2DROP R> DROP SBOX-BYTE-S-OK ;

: SBOX-BYTE-READER-RESET  ( reader -- status )
    DUP SBOX-BYTE-READER-VALID? 0= IF
        DROP SBOX-BYTE-S-INVALID EXIT
    THEN
    0 OVER _SBOX-BR.OFFSET !
    0 SWAP _SBOX-BR.STATUS !
    SBOX-BYTE-S-OK ;

: SBOX-BYTE-READER-STATUS@  ( reader -- status )
    DUP SBOX-BYTE-READER-VALID? IF
        _SBOX-BR.STATUS @
    ELSE
        DROP SBOX-BYTE-S-INVALID
    THEN ;

: SBOX-BYTE-READER-OFFSET@  ( reader -- offset|0 )
    DUP SBOX-BYTE-READER-VALID? IF _SBOX-BR.OFFSET @ ELSE DROP 0 THEN ;

: SBOX-BYTE-READER-REMAINING@  ( reader -- remaining|0 )
    DUP SBOX-BYTE-READER-VALID? IF
        DUP _SBOX-BR.LENGTH @ SWAP _SBOX-BR.OFFSET @ -
    ELSE
        DROP 0
    THEN ;

: SBOX-BYTE-READER-AT-END?  ( reader -- flag )
    DUP SBOX-BYTE-READER-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SBOX-BR.STATUS @ IF DROP 0 EXIT THEN
    DUP _SBOX-BR.OFFSET @ SWAP _SBOX-BR.LENGTH @ = ;

: _SBOX-BR-READY  ( reader -- status )
    DUP SBOX-BYTE-READER-VALID? 0= IF
        DROP SBOX-BYTE-S-INVALID EXIT
    THEN
    _SBOX-BR.STATUS @ ;

: _SBOX-BR-LATCH  ( status reader -- status )
    >R
    R@ _SBOX-BR.STATUS @ ?DUP IF
        NIP
    ELSE
        DUP R@ _SBOX-BR.STATUS !
    THEN
    R> DROP ;

: _SBOX-BR-RESERVE  ( length reader -- address status )
    DUP _SBOX-BR-READY DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    DROP
    OVER 0< IF
        SBOX-BYTE-S-INVALID OVER _SBOX-BR-LATCH >R
        2DROP 0 R> EXIT
    THEN
    >R
    DUP R@ _SBOX-BR.LENGTH @ R@ _SBOX-BR.OFFSET @ - U> IF
        DROP
        SBOX-BYTE-S-CAPACITY R@ _SBOX-BR-LATCH
        R> DROP 0 SWAP EXIT
    THEN
    R@ _SBOX-BR.SOURCE @ R@ _SBOX-BR.OFFSET @ +
    SWAP DUP R@ _SBOX-BR.OFFSET +! DROP
    R> DROP SBOX-BYTE-S-OK ;

: SBOX-BYTE-READ-SPAN  ( length reader -- address length status )
    OVER >R
    _SBOX-BR-RESERVE
    DUP IF
        >R DROP R> R> DROP
        0 0 ROT EXIT
    THEN
    DROP R> SBOX-BYTE-S-OK ;

: SBOX-BYTE-SKIP  ( length reader -- status )
    _SBOX-BR-RESERVE NIP ;

: SBOX-BYTE-READ-U8  ( reader -- value status )
    1 SWAP _SBOX-BR-RESERVE
    DUP IF NIP 0 SWAP EXIT THEN
    DROP C@ SBOX-BYTE-S-OK ;

: _SBOX-BYTE-U16@  ( address -- value )
    DUP C@
    SWAP 1+ C@ 8 LSHIFT OR ;

: _SBOX-BYTE-U32@  ( address -- value )
    DUP _SBOX-BYTE-U16@
    SWAP 2 + _SBOX-BYTE-U16@ 16 LSHIFT OR ;

: _SBOX-BYTE-U64@  ( address -- value )
    DUP _SBOX-BYTE-U32@
    SWAP 4 + _SBOX-BYTE-U32@ 32 LSHIFT OR ;

: SBOX-BYTE-READ-U16-LE  ( reader -- value status )
    2 SWAP _SBOX-BR-RESERVE
    DUP IF NIP 0 SWAP EXIT THEN
    DROP _SBOX-BYTE-U16@ SBOX-BYTE-S-OK ;

: SBOX-BYTE-READ-U32-LE  ( reader -- value status )
    4 SWAP _SBOX-BR-RESERVE
    DUP IF NIP 0 SWAP EXIT THEN
    DROP _SBOX-BYTE-U32@ SBOX-BYTE-S-OK ;

: SBOX-BYTE-READ-U64-LE  ( reader -- value status )
    8 SWAP _SBOX-BR-RESERVE
    DUP IF NIP 0 SWAP EXIT THEN
    DROP _SBOX-BYTE-U64@ SBOX-BYTE-S-OK ;

\ The scalar is one cell of bits.  Signed interpretation belongs to the
\ caller's format semantics, so I64 and U64 share the same exact byte read.
: SBOX-BYTE-READ-I64-LE  ( reader -- value status )
    SBOX-BYTE-READ-U64-LE ;
