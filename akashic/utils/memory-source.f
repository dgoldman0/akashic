\ =====================================================================
\  memory-source.f -- caller memory that a component grows into
\ =====================================================================
\
\  A component that starts with what it needs and grows takes its blocks
\  from a memory source its caller supplies, and gives them back.  The
\  caller decides how much memory there is: its allocator, and optionally a
\  byte budget.  A refusal from either is the caller's limit, which the
\  component reports instead of working around it.
\
\  The allocator is ( bytes context -- addr|0 ) and returns eight-byte
\  aligned blocks; the release is ( addr bytes context -- ).  HELD counts
\  the bytes handed out and not yet given back.  A BUDGET of zero leaves the
\  allocator as the only limit.
\
\  Prefix: MSRC- (public), _MSRC- (private)

PROVIDED akashic-memory-source

0x4352534D4D454D41 CONSTANT _MSRC-MAGIC

48 CONSTANT MSRC-SIZE
: MSRC.MAGIC     ( m -- a )      ;
: MSRC.ALLOC-XT  ( m -- a )  8 + ;
: MSRC.FREE-XT   ( m -- a ) 16 + ;
: MSRC.CONTEXT   ( m -- a ) 24 + ;
: MSRC.BUDGET    ( m -- a ) 32 + ;
: MSRC.HELD      ( m -- a ) 40 + ;

: MSRC-INIT  ( alloc-xt free-xt context budget m -- )
    >R
    R@ MSRC.BUDGET ! R@ MSRC.CONTEXT ! R@ MSRC.FREE-XT ! R@ MSRC.ALLOC-XT !
    0 R@ MSRC.HELD !
    _MSRC-MAGIC R> MSRC.MAGIC ! ;

: MSRC-VALID?  ( m -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP MSRC.MAGIC @ _MSRC-MAGIC <> IF DROP 0 EXIT THEN
    DUP MSRC.ALLOC-XT @ 0<> SWAP MSRC.FREE-XT @ 0<> AND ;

\ MSRC-ALLOC ( bytes m -- addr|0 )
\   A block of at least BYTES, eight-byte aligned, or 0 when the budget or
\   the allocator has no room.  The block's contents are undefined.
: MSRC-ALLOC  ( bytes m -- addr|0 )
    OVER 0= IF 2DROP 0 EXIT THEN
    DUP MSRC.BUDGET @ IF
        DUP MSRC.HELD @ 2 PICK + DUP 3 PICK U<
        OVER 3 PICK MSRC.BUDGET @ U> OR IF 2DROP DROP 0 EXIT THEN DROP
    THEN
    OVER OVER MSRC.CONTEXT @ 2 PICK MSRC.ALLOC-XT @ EXECUTE
    DUP 0= IF NIP NIP EXIT THEN
    DUP 7 AND IF
        \ An allocator that breaks the alignment contract is refused, and
        \ its block given back.
        2 PICK 2 PICK MSRC.CONTEXT @ 3 PICK MSRC.FREE-XT @ EXECUTE
        2DROP 0 EXIT
    THEN
    >R TUCK MSRC.HELD +! DROP R> ;

\ MSRC-FREE ( addr bytes m -- )
\   Give back a block MSRC-ALLOC returned, with the size asked for.
: MSRC-FREE  ( addr bytes m -- )
    OVER 0= 3 PICK 0= OR IF 2DROP DROP EXIT THEN
    2DUP MSRC.HELD @ SWAP - OVER MSRC.HELD !
    DUP MSRC.CONTEXT @ SWAP MSRC.FREE-XT @ EXECUTE ;

: MSRC-HELD@  ( m -- bytes )  MSRC.HELD @ ;
