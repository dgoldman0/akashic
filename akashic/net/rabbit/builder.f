\ =====================================================================
\  builder.f - Caller-owned typed Rabbit message construction
\ =====================================================================
\  A builder embeds one outbound RBF descriptor and copies every start-line,
\  header, and body byte into a separate caller-provided arena.  A READY
\  builder therefore borrows no application input.  RESET wipes every arena
\  byte used by the previous construction before making the builder reusable.
\  INIT loans the descriptor exclusively until FINI.  During BUILD/READY the
\  entire arena is also exclusive; RESET wipes and releases its live content.
\
\  Header capacity and byte-arena capacity are caller choices.  There is no
\  product message-size or header-count constant here.  Only exact wire scalar
\  widths (u16 lane, u32 credit, u64 sequence/cursor) are fixed by Rabbit.
\
\  Construction is transactional from the caller's point of view: the first
\  mutation failure latches ERROR, resets the embedded frame, wipes copied
\  bytes, and requires RESET.  SEAL runs RMSG admission and requires its kind
\  to match the constructor's expected kind.  ENCODE is all-or-nothing and
\  refuses output that aliases either builder storage or its entire arena.
\
\  Private VARIABLEs are synchronous operation scratch only.  The module is
\  non-reentrant until this scratch moves into caller-owned workspaces.  No
\  word below calls back or yields.
\
\  RBF-DETAIL@ and RMSG-DETAIL@ report latched construction/seal failures.
\  MEASURE/ENCODE caller errors are retryable and do not mutate that evidence.
\ =====================================================================

PROVIDED akashic-rabbit-builder

REQUIRE frame.f
REQUIRE message.f
REQUIRE profile.f
REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/string.f

\ =====================================================================
\  Public status/state vocabulary and caller-owned layout
\ =====================================================================

0 CONSTANT RMSGB-S-OK
1 CONSTANT RMSGB-S-INVALID
2 CONSTANT RMSGB-S-CAPACITY
3 CONSTANT RMSGB-S-STATE
4 CONSTANT RMSGB-S-FRAME
5 CONSTANT RMSGB-S-MESSAGE
6 CONSTANT RMSGB-S-UNSUPPORTED
7 CONSTANT RMSGB-S-ALIAS

0 CONSTANT RMSGB-STATE-EMPTY
1 CONSTANT RMSGB-STATE-BUILD
2 CONSTANT RMSGB-STATE-READY
3 CONSTANT RMSGB-STATE-ERROR

0x524D5347424C4431 CONSTANT _RMSGB-MAGIC-VALUE  \ "RMSGBLD1"
1                  CONSTANT _RMSGB-ABI-VERSION

1 CONSTANT _RMSGB-F-BODY

 0 CONSTANT _RMSGB-MAGIC
 8 CONSTANT _RMSGB-ABI
16 CONSTANT _RMSGB-BYTES
24 CONSTANT _RMSGB-STATE
32 CONSTANT _RMSGB-STATUS
40 CONSTANT _RMSGB-RBF-DETAIL
48 CONSTANT _RMSGB-RMSG-DETAIL
56 CONSTANT _RMSGB-ARENA
64 CONSTANT _RMSGB-ARENA-CAP
72 CONSTANT _RMSGB-ARENA-USED
80 CONSTANT _RMSGB-KIND
88 CONSTANT _RMSGB-FLAGS
96 CONSTANT _RMSGB-FRAME-OFF
96 CONSTANT RMSGB-BUILDER-BASE

: _RMSGB.MAGIC       ( builder -- field ) _RMSGB-MAGIC + ;
: _RMSGB.ABI         ( builder -- field ) _RMSGB-ABI + ;
: _RMSGB.BYTES       ( builder -- field ) _RMSGB-BYTES + ;
: _RMSGB.STATE       ( builder -- field ) _RMSGB-STATE + ;
: _RMSGB.STATUS      ( builder -- field ) _RMSGB-STATUS + ;
: _RMSGB.RBF-DETAIL  ( builder -- field ) _RMSGB-RBF-DETAIL + ;
: _RMSGB.RMSG-DETAIL ( builder -- field ) _RMSGB-RMSG-DETAIL + ;
: _RMSGB.ARENA       ( builder -- field ) _RMSGB-ARENA + ;
: _RMSGB.ARENA-CAP   ( builder -- field ) _RMSGB-ARENA-CAP + ;
: _RMSGB.ARENA-USED  ( builder -- field ) _RMSGB-ARENA-USED + ;
: _RMSGB.KIND        ( builder -- field ) _RMSGB-KIND + ;
: _RMSGB.FLAGS       ( builder -- field ) _RMSGB-FLAGS + ;
: _RMSGB.FRAME       ( builder -- frame ) _RMSGB-FRAME-OFF + ;

0x7FFFFFFFFFFFFFFF RMSGB-BUILDER-BASE -
    CONSTANT _RMSGB-FRAME-BYTES-MAX

: RMSGB-BUILDER-BYTES  ( header-capacity -- bytes|0 )
    RBF-FRAME-BYTES DUP 0= IF EXIT THEN
    DUP _RMSGB-FRAME-BYTES-MAX U> IF DROP 0 EXIT THEN
    RMSGB-BUILDER-BASE + ;

: RMSGB-STATUS-VALID?  ( status -- flag )
    DUP RMSGB-S-OK >= SWAP RMSGB-S-ALIAS <= AND ;

: RMSGB-STATE-VALID?  ( state -- flag )
    DUP RMSGB-STATE-EMPTY >= SWAP RMSGB-STATE-ERROR <= AND ;

VARIABLE _RMSGBV-B
VARIABLE _RMSGBV-BYTES
VARIABLE _RMSGBV-FBYTES
VARIABLE _RMSGBV-STATE
VARIABLE _RMSGBV-STATUS

: RMSGB-VALID?  ( builder -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP RMSGB-BUILDER-BASE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    _RMSGBV-B !
    _RMSGBV-B @ _RMSGB.MAGIC @ _RMSGB-MAGIC-VALUE <> IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.ABI @ _RMSGB-ABI-VERSION <> IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.FRAME RBF-FRAME-VALID? 0= IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.FRAME RBF-DESCRIPTOR-BYTES@ DUP 0= IF
        DROP 0 EXIT
    THEN _RMSGBV-FBYTES !
    _RMSGBV-FBYTES @ _RMSGB-FRAME-BYTES-MAX U> IF 0 EXIT THEN
    _RMSGBV-FBYTES @ RMSGB-BUILDER-BASE + DUP _RMSGBV-BYTES !
    _RMSGBV-B @ _RMSGB.BYTES @ <> IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGBV-BYTES @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.STATE @ DUP _RMSGBV-STATE !
    RMSGB-STATE-VALID? 0= IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.STATUS @ DUP _RMSGBV-STATUS !
    RMSGB-STATUS-VALID? 0= IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.RBF-DETAIL @ DUP RBF-S-OK < IF DROP 0 EXIT THEN
    RBF-S-TRUNCATED > IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.RMSG-DETAIL @ RMSG-STATUS-VALID? 0= IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.ARENA-CAP @ DUP 0< IF DROP 0 EXIT THEN
    DUP 0> _RMSGBV-B @ _RMSGB.ARENA @ 0= AND IF DROP 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.ARENA @ SWAP MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.ARENA-USED @ DUP 0< IF DROP 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.ARENA-CAP @ > IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.ARENA @ _RMSGBV-B @ _RMSGB.ARENA-CAP @
        _RMSGBV-B @ _RMSGBV-BYTES @ MSPAN-OVERLAP? IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.FLAGS @ DUP 0< IF DROP 0 EXIT THEN
    _RMSGB-F-BODY INVERT AND IF 0 EXIT THEN
    _RMSGBV-B @ _RMSGB.KIND @ RMSG-KIND-VALID? 0= IF 0 EXIT THEN
    _RMSGBV-STATE @ RMSGB-STATE-ERROR = IF
        _RMSGBV-STATUS @ 0<>
        _RMSGBV-B @ _RMSGB.KIND @ RMSG-KIND-INVALID = AND
        _RMSGBV-B @ _RMSGB.ARENA-USED @ 0= AND
        _RMSGBV-B @ _RMSGB.FLAGS @ 0= AND
        _RMSGBV-B @ _RMSGB.FRAME RBF-READY? 0= AND EXIT
    THEN
    _RMSGBV-STATUS @ IF 0 EXIT THEN
    _RMSGBV-STATE @ RMSGB-STATE-EMPTY = IF
        _RMSGBV-B @ _RMSGB.KIND @ RMSG-KIND-INVALID =
        _RMSGBV-B @ _RMSGB.ARENA-USED @ 0= AND
        _RMSGBV-B @ _RMSGB.FLAGS @ 0= AND
        _RMSGBV-B @ _RMSGB.FRAME RBF-READY? 0= AND EXIT
    THEN
    _RMSGBV-B @ _RMSGB.KIND @ RMSG-KIND-INVALID = IF 0 EXIT THEN
    _RMSGBV-STATE @ RMSGB-STATE-BUILD = IF
        _RMSGBV-B @ _RMSGB.FRAME RBF-READY? 0= EXIT
    THEN
    _RMSGBV-B @ _RMSGB.FRAME RBF-READY? ;

\ =====================================================================
\  Initialization, reset, and public evidence
\ =====================================================================

VARIABLE _RMSGBI-A
VARIABLE _RMSGBI-U
VARIABLE _RMSGBI-HCAP
VARIABLE _RMSGBI-B
VARIABLE _RMSGBI-BYTES

: RMSGB-INIT  ( arena-a arena-u header-capacity builder -- status )
    _RMSGBI-B ! _RMSGBI-HCAP ! _RMSGBI-U ! _RMSGBI-A !
    _RMSGBI-HCAP @ RMSGB-BUILDER-BYTES DUP 0= IF
        DROP RMSGB-S-INVALID EXIT
    THEN _RMSGBI-BYTES !
    _RMSGBI-B @ 0= IF RMSGB-S-INVALID EXIT THEN
    _RMSGBI-B @ 7 AND IF RMSGB-S-INVALID EXIT THEN
    _RMSGBI-B @ _RMSGBI-BYTES @ MSPAN-NONWRAPPING? 0= IF
        RMSGB-S-INVALID EXIT
    THEN
    _RMSGBI-U @ 0< IF RMSGB-S-INVALID EXIT THEN
    _RMSGBI-U @ 0> _RMSGBI-A @ 0= AND IF RMSGB-S-INVALID EXIT THEN
    _RMSGBI-A @ _RMSGBI-U @ MSPAN-NONWRAPPING? 0= IF
        RMSGB-S-INVALID EXIT
    THEN
    _RMSGBI-A @ _RMSGBI-U @ _RMSGBI-B @ _RMSGBI-BYTES @
        MSPAN-OVERLAP? IF RMSGB-S-ALIAS EXIT THEN
    _RMSGBI-B @ RMSGB-VALID? IF RMSGB-S-STATE EXIT THEN
    _RMSGBI-B @ _RMSGBI-BYTES @ 0 FILL
    _RMSGBI-HCAP @ _RMSGBI-B @ _RMSGB.FRAME RBF-FRAME-INIT
    DUP IF DROP RMSGB-S-FRAME EXIT THEN DROP
    _RMSGB-MAGIC-VALUE _RMSGBI-B @ _RMSGB.MAGIC !
    _RMSGB-ABI-VERSION _RMSGBI-B @ _RMSGB.ABI !
    _RMSGBI-BYTES @ _RMSGBI-B @ _RMSGB.BYTES !
    RMSGB-STATE-EMPTY _RMSGBI-B @ _RMSGB.STATE !
    RMSGB-S-OK _RMSGBI-B @ _RMSGB.STATUS !
    RBF-S-OK _RMSGBI-B @ _RMSGB.RBF-DETAIL !
    RMSG-S-OK _RMSGBI-B @ _RMSGB.RMSG-DETAIL !
    _RMSGBI-A @ _RMSGBI-B @ _RMSGB.ARENA !
    _RMSGBI-U @ _RMSGBI-B @ _RMSGB.ARENA-CAP !
    RMSG-KIND-INVALID _RMSGBI-B @ _RMSGB.KIND !
    RMSGB-S-OK ;

: _RMSGB-WIPE  ( builder -- )
    DUP _RMSGB.ARENA @ OVER _RMSGB.ARENA-USED @ 0 FILL
    0 SWAP _RMSGB.ARENA-USED ! ;

: RMSGB-RESET  ( builder -- status )
    DUP RMSGB-VALID? 0= IF DROP RMSGB-S-INVALID EXIT THEN
    DUP _RMSGB.FRAME RBF-FRAME-RESET DUP IF
        SWAP _RMSGB.RBF-DETAIL ! RMSGB-S-FRAME EXIT
    THEN DROP
    DUP _RMSGB-WIPE
    RMSGB-STATE-EMPTY OVER _RMSGB.STATE !
    RMSGB-S-OK OVER _RMSGB.STATUS !
    RBF-S-OK OVER _RMSGB.RBF-DETAIL !
    RMSG-S-OK OVER _RMSGB.RMSG-DETAIL !
    RMSG-KIND-INVALID OVER _RMSGB.KIND !
    0 SWAP _RMSGB.FLAGS !
    RMSGB-S-OK ;

VARIABLE _RMSGBF-BYTES

: RMSGB-FINI  ( builder -- status )
    DUP RMSGB-VALID? 0= IF DROP RMSGB-S-INVALID EXIT THEN
    DUP _RMSGB.BYTES @ _RMSGBF-BYTES !
    DUP _RMSGB-WIPE
    _RMSGBF-BYTES @ 0 FILL
    RMSGB-S-OK ;

: RMSGB-STATE@  ( builder -- state|RMSGB-STATE-ERROR )
    DUP RMSGB-VALID? 0= IF DROP RMSGB-STATE-ERROR EXIT THEN
    _RMSGB.STATE @ ;

: RMSGB-STATUS@  ( builder -- status )
    DUP RMSGB-VALID? 0= IF DROP RMSGB-S-INVALID EXIT THEN
    _RMSGB.STATUS @ ;

: RMSGB-RBF-DETAIL@  ( builder -- rbf-status )
    DUP RMSGB-VALID? 0= IF DROP RBF-S-INVALID EXIT THEN
    _RMSGB.RBF-DETAIL @ ;

: RMSGB-RMSG-DETAIL@  ( builder -- rmsg-status )
    DUP RMSGB-VALID? 0= IF DROP RMSG-S-INVALID EXIT THEN
    _RMSGB.RMSG-DETAIL @ ;

: RMSGB-KIND@  ( builder -- kind )
    DUP RMSGB-VALID? 0= IF DROP RMSG-KIND-INVALID EXIT THEN
    _RMSGB.KIND @ ;

\ Immutable synchronous inspection for an owning connection.  The returned
\ READY frame is builder-owned and expires on RESET or FINI; callers may read
\ typed message fields during enqueue but must never retain or mutate it.
: RMSGB-READY-FRAME@  ( builder -- frame|0 )
    DUP RMSGB-VALID? 0= IF DROP 0 EXIT THEN
    DUP _RMSGB.STATE @ RMSGB-STATE-READY <> IF DROP 0 EXIT THEN
    _RMSGB.FRAME ;

: RMSGB-ARENA-USED@  ( builder -- bytes )
    DUP RMSGB-VALID? 0= IF DROP 0 EXIT THEN
    _RMSGB.ARENA-USED @ ;

\ Stable enumeration of the two allocations in the builder ownership graph.
\ This keeps field layout private while allowing another neutral owner to
\ compare its complete pointer graph with both the descriptor and the full
\ caller-provided arena.  Arena capacity, rather than currently used bytes,
\ is the ownership boundary.  A valid zero-capacity arena reports an empty
\ span with OK status.
2 CONSTANT RMSGB-OWNED-SPAN-COUNT

: RMSGB-OWNED-SPAN@  ( index builder -- address bytes status )
    >R
    DUP 0< OVER RMSGB-OWNED-SPAN-COUNT >= OR IF
        DROP R> DROP 0 0 RMSGB-S-INVALID EXIT
    THEN
    R@ RMSGB-VALID? 0= IF
        DROP R> DROP 0 0 RMSGB-S-INVALID EXIT
    THEN
    CASE
        0 OF R@ R@ _RMSGB.BYTES @ RMSGB-S-OK ENDOF
        1 OF
            R@ _RMSGB.ARENA @ R@ _RMSGB.ARENA-CAP @ RMSGB-S-OK
        ENDOF
    ENDCASE
    R> DROP ;

VARIABLE _RMSGBO-A
VARIABLE _RMSGBO-U
VARIABLE _RMSGBO-B

\ Compare a checked span with a builder whose complete validity has already
\ been established by the enclosing graph operation.  Keeping this core
\ separate prevents pairwise graph checks from re-walking the same builder
\ frame and arena for every constituent span.
: _RMSGB-OWNED-SPAN-OVERLAP-VALID?  ( address bytes builder -- flag )
    _RMSGBO-B ! _RMSGBO-U ! _RMSGBO-A !
    _RMSGBO-A @ _RMSGBO-U @
        _RMSGBO-B @ _RMSGBO-B @ _RMSGB.BYTES @
        MSPAN-OVERLAP? IF -1 EXIT THEN
    _RMSGBO-A @ _RMSGBO-U @
        _RMSGBO-B @ _RMSGB.ARENA @
        _RMSGBO-B @ _RMSGB.ARENA-CAP @
        MSPAN-OVERLAP? ;

\ Report whether a caller span touches any builder-owned storage: both the
\ complete descriptor and the complete arena allocation, including currently
\ unused arena bytes.  Invalid span geometry or an invalid builder reports
\ overlap conservatively so ownership checks fail closed.  An otherwise valid
\ empty span never overlaps.
: RMSGB-OWNED-SPAN-OVERLAP?  ( address bytes builder -- flag )
    _RMSGBO-B ! _RMSGBO-U ! _RMSGBO-A !
    _RMSGBO-U @ 0< IF -1 EXIT THEN
    _RMSGBO-U @ IF
        _RMSGBO-A @ 0= IF -1 EXIT THEN
    THEN
    _RMSGBO-A @ _RMSGBO-U @ MSPAN-NONWRAPPING? 0= IF -1 EXIT THEN
    _RMSGBO-B @ RMSGB-VALID? 0= IF -1 EXIT THEN
    _RMSGBO-A @ _RMSGBO-U @ _RMSGBO-B @
        _RMSGB-OWNED-SPAN-OVERLAP-VALID? ;

VARIABLE _RMSGBGG-A
VARIABLE _RMSGBGG-B

\ Compare the complete owned allocations of two builders.  This is the
\ pairwise composition seam for higher protocol owners: both descriptors and
\ both complete caller-provided arenas must be valid and disjoint.  Invalid
\ inputs, including a builder compared with itself, fail closed.
: RMSGB-OWNED-GRAPHS-DISJOINT?  ( builder-a builder-b -- flag )
    _RMSGBGG-B ! _RMSGBGG-A !
    _RMSGBGG-A @ RMSGB-VALID? 0= IF 0 EXIT THEN
    _RMSGBGG-B @ RMSGB-VALID? 0= IF 0 EXIT THEN
    _RMSGBGG-A @ _RMSGBGG-A @ _RMSGB.BYTES @ _RMSGBGG-B @
        _RMSGB-OWNED-SPAN-OVERLAP-VALID? IF 0 EXIT THEN
    _RMSGBGG-A @ _RMSGB.ARENA @
        _RMSGBGG-A @ _RMSGB.ARENA-CAP @ _RMSGBGG-B @
        _RMSGB-OWNED-SPAN-OVERLAP-VALID? 0= ;

\ =====================================================================
\  Failure mapping and owned-arena helpers
\ =====================================================================

: _RMSGB-RBF>STATUS  ( rbf-status -- builder-status )
    CASE
        RBF-S-OK OF RMSGB-S-OK ENDOF
        RBF-S-CAPACITY OF RMSGB-S-CAPACITY ENDOF
        RBF-S-STATE OF RMSGB-S-STATE ENDOF
        RBF-S-UNSUPPORTED OF RMSGB-S-UNSUPPORTED ENDOF
        RMSGB-S-FRAME SWAP
    ENDCASE ;

: _RMSGB-RMSG>STATUS  ( rmsg-status -- builder-status )
    RMSG-S-UNSUPPORTED = IF RMSGB-S-UNSUPPORTED ELSE RMSGB-S-MESSAGE THEN ;

: _RMSGB-LATCH  ( builder-status builder -- status )
    >R
    DUP R@ _RMSGB.STATUS !
    RMSGB-STATE-ERROR R@ _RMSGB.STATE !
    RMSG-KIND-INVALID R@ _RMSGB.KIND !
    0 R@ _RMSGB.FLAGS !
    R@ _RMSGB.FRAME RBF-FRAME-RESET DROP
    R@ _RMSGB-WIPE
    R> DROP ;

: _RMSGB-RBF-FAIL  ( rbf-status builder -- status )
    >R DUP R@ _RMSGB.RBF-DETAIL !
    _RMSGB-RBF>STATUS R> _RMSGB-LATCH ;

: _RMSGB-RMSG-FAIL  ( rmsg-status builder -- status )
    >R DUP R@ _RMSGB.RMSG-DETAIL !
    _RMSGB-RMSG>STATUS R> _RMSGB-LATCH ;

: _RMSGB-EMPTY-STATUS  ( builder -- status )
    DUP RMSGB-VALID? 0= IF DROP RMSGB-S-INVALID EXIT THEN
    _RMSGB.STATE @ RMSGB-STATE-EMPTY = IF
        RMSGB-S-OK
    ELSE
        RMSGB-S-STATE
    THEN ;

: _RMSGB-BUILD-STATUS  ( builder -- status )
    DUP RMSGB-VALID? 0= IF DROP RMSGB-S-INVALID EXIT THEN
    _RMSGB.STATE @ RMSGB-STATE-BUILD = IF
        RMSGB-S-OK
    ELSE
        RMSGB-S-STATE
    THEN ;

VARIABLE _RMSGBS-A
VARIABLE _RMSGBS-U
VARIABLE _RMSGBS-B

: _RMSGB-SOURCE-STATUS  ( address length builder -- status )
    _RMSGBS-B ! _RMSGBS-U ! _RMSGBS-A !
    _RMSGBS-U @ 0< IF RMSGB-S-INVALID EXIT THEN
    _RMSGBS-U @ 0> _RMSGBS-A @ 0= AND IF RMSGB-S-INVALID EXIT THEN
    _RMSGBS-A @ _RMSGBS-U @ MSPAN-NONWRAPPING? 0= IF
        RMSGB-S-INVALID EXIT
    THEN
    _RMSGBS-A @ _RMSGBS-U @
        _RMSGBS-B @ _RMSGB.BYTES @ _RMSGBS-B @ SWAP
        MSPAN-OVERLAP? IF RMSGB-S-ALIAS EXIT THEN
    _RMSGBS-A @ _RMSGBS-U @
        _RMSGBS-B @ _RMSGB.ARENA @ _RMSGBS-B @ _RMSGB.ARENA-CAP @
        MSPAN-OVERLAP? IF RMSGB-S-ALIAS EXIT THEN
    RMSGB-S-OK ;

VARIABLE _RMSGBA-N
VARIABLE _RMSGBA-B

: _RMSGB-RESERVE  ( bytes builder -- destination status )
    _RMSGBA-B ! _RMSGBA-N !
    _RMSGBA-N @ 0< IF 0 RMSGB-S-INVALID EXIT THEN
    _RMSGBA-B @ _RMSGB.ARENA-CAP @ _RMSGBA-B @ _RMSGB.ARENA-USED @ -
        _RMSGBA-N @ < IF 0 RMSGB-S-CAPACITY EXIT THEN
    _RMSGBA-B @ _RMSGB.ARENA @ _RMSGBA-B @ _RMSGB.ARENA-USED @ +
    _RMSGBA-N @ _RMSGBA-B @ _RMSGB.ARENA-USED +!
    RMSGB-S-OK ;

VARIABLE _RMSGBC-A
VARIABLE _RMSGBC-U
VARIABLE _RMSGBC-B
VARIABLE _RMSGBC-D

: _RMSGB-COPY  ( source-a source-u builder -- copied-a copied-u status )
    _RMSGBC-B ! _RMSGBC-U ! _RMSGBC-A !
    _RMSGBC-A @ _RMSGBC-U @ _RMSGBC-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF 0 0 ROT EXIT THEN
    _RMSGBC-U @ _RMSGBC-B @ _RMSGB-RESERVE DUP IF
        >R DROP 0 0 R> EXIT
    THEN DROP _RMSGBC-D !
    _RMSGBC-A @ _RMSGBC-D @ _RMSGBC-U @ MOVE
    _RMSGBC-D @ _RMSGBC-U @ RMSGB-S-OK ;

\ =====================================================================
\  Canonical scalar output into the owned arena
\ =====================================================================

: _RMSGB-U/10  ( u -- quotient remainder )
    DUP >R 0xCCCCCCCCCCCCCCCD UM* NIP 3 RSHIFT
    DUP 10 * R> SWAP - ;

: _RMSGB-U-DIGITS  ( u -- count )
    1 SWAP
    BEGIN DUP 10 U< 0= WHILE
        _RMSGB-U/10 DROP SWAP 1+ SWAP
    REPEAT
    DROP ;

VARIABLE _RMSGBN-V
VARIABLE _RMSGBN-A
VARIABLE _RMSGBN-U
VARIABLE _RMSGBN-P

: _RMSGB-WRITE-U  ( value destination digits -- )
    _RMSGBN-U ! _RMSGBN-A ! _RMSGBN-V !
    _RMSGBN-A @ _RMSGBN-U @ + _RMSGBN-P !
    BEGIN
        _RMSGBN-V @ _RMSGB-U/10
        SWAP _RMSGBN-V !
        _RMSGBN-P @ 1- DUP _RMSGBN-P !
        SWAP [CHAR] 0 + SWAP C!
        _RMSGBN-V @ 0=
    UNTIL ;

VARIABLE _RMSGBO-V
VARIABLE _RMSGBO-B
VARIABLE _RMSGBO-U
VARIABLE _RMSGBO-A

: _RMSGB-U-COPY  ( value builder -- copied-a copied-u status )
    _RMSGBO-B ! _RMSGBO-V !
    _RMSGBO-V @ _RMSGB-U-DIGITS DUP _RMSGBO-U !
    _RMSGBO-B @ _RMSGB-RESERVE DUP IF
        >R DROP 0 0 R> EXIT
    THEN DROP _RMSGBO-A !
    _RMSGBO-V @ _RMSGBO-A @ _RMSGBO-U @ _RMSGB-WRITE-U
    _RMSGBO-A @ _RMSGBO-U @ RMSGB-S-OK ;

: _RMSGB-CREDIT-COPY  ( credit builder -- copied-a copied-u status )
    _RMSGBO-B ! _RMSGBO-V !
    _RMSGBO-V @ _RMSGB-U-DIGITS 1+ DUP _RMSGBO-U !
    _RMSGBO-B @ _RMSGB-RESERVE DUP IF
        >R DROP 0 0 R> EXIT
    THEN DROP _RMSGBO-A !
    [CHAR] + _RMSGBO-A @ C!
    _RMSGBO-V @ _RMSGBO-A @ 1+ _RMSGBO-U @ 1- _RMSGB-WRITE-U
    _RMSGBO-A @ _RMSGBO-U @ RMSGB-S-OK ;

\ =====================================================================
\  Start lines and owned headers
\ =====================================================================

VARIABLE _RMSGBG-KIND
VARIABLE _RMSGBG-VA
VARIABLE _RMSGBG-VU
VARIABLE _RMSGBG-AA
VARIABLE _RMSGBG-AU
VARIABLE _RMSGBG-B
VARIABLE _RMSGBG-N
VARIABLE _RMSGBG-D
VARIABLE _RMSGBG-EXTRA

: _RMSGB-BEGIN$  ( kind verb-a verb-u args-a args-u builder -- status )
    _RMSGBG-B ! _RMSGBG-AU ! _RMSGBG-AA !
    _RMSGBG-VU ! _RMSGBG-VA ! _RMSGBG-KIND !
    _RMSGBG-B @ _RMSGB-EMPTY-STATUS ?DUP IF EXIT THEN
    _RMSGBG-KIND @ DUP RMSG-KIND-VALID? 0= SWAP RMSG-KIND-INVALID = OR IF
        RMSGB-S-INVALID _RMSGBG-B @ _RMSGB-LATCH EXIT
    THEN
    _RMSGBG-VU @ 0> 0= IF
        RMSGB-S-INVALID _RMSGBG-B @ _RMSGB-LATCH EXIT
    THEN
    _RMSGBG-VA @ _RMSGBG-VU @ _RMSGBG-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF _RMSGBG-B @ _RMSGB-LATCH EXIT THEN
    _RMSGBG-AA @ _RMSGBG-AU @ _RMSGBG-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF _RMSGBG-B @ _RMSGB-LATCH EXIT THEN
    _RMSGBG-VU @ _RMSGBG-N !
    _RMSGBG-AU @ IF
        _RMSGBG-AU @ 1+ DUP 0< IF
            DROP RMSGB-S-CAPACITY _RMSGBG-B @ _RMSGB-LATCH EXIT
        THEN _RMSGBG-EXTRA !
        _RMSGBG-EXTRA @ 0x7FFFFFFFFFFFFFFF _RMSGBG-N @ - U> IF
            RMSGB-S-CAPACITY _RMSGBG-B @ _RMSGB-LATCH EXIT
        THEN
        _RMSGBG-EXTRA @ _RMSGBG-N +!
    THEN
    _RMSGBG-N @ _RMSGBG-B @ _RMSGB-RESERVE DUP IF
        >R DROP R> _RMSGBG-B @ _RMSGB-LATCH EXIT
    THEN DROP _RMSGBG-D !
    _RMSGBG-VA @ _RMSGBG-D @ _RMSGBG-VU @ MOVE
    _RMSGBG-AU @ IF
        32 _RMSGBG-D @ _RMSGBG-VU @ + C!
        _RMSGBG-AA @ _RMSGBG-D @ _RMSGBG-VU @ + 1+
            _RMSGBG-AU @ MOVE
    THEN
    _RMSGBG-D @ _RMSGBG-N @ _RMSGBG-B @ _RMSGB.FRAME
        RBF-FRAME-START! DUP IF
        _RMSGBG-B @ _RMSGB-RBF-FAIL EXIT
    THEN DROP
    _RMSGBG-KIND @ _RMSGBG-B @ _RMSGB.KIND !
    RMSGB-STATE-BUILD _RMSGBG-B @ _RMSGB.STATE !
    RMSGB-S-OK ;

VARIABLE _RMSGBH-NA
VARIABLE _RMSGBH-NU
VARIABLE _RMSGBH-VA
VARIABLE _RMSGBH-VU
VARIABLE _RMSGBH-B
VARIABLE _RMSGBH-CNA
VARIABLE _RMSGBH-CNU
VARIABLE _RMSGBH-CVA
VARIABLE _RMSGBH-CVU

: _RMSGB-HEADER+  ( name-a name-u value-a value-u builder -- status )
    _RMSGBH-B ! _RMSGBH-VU ! _RMSGBH-VA ! _RMSGBH-NU ! _RMSGBH-NA !
    _RMSGBH-B @ _RMSGB-BUILD-STATUS ?DUP IF EXIT THEN
    _RMSGBH-NA @ _RMSGBH-NU @ _RMSGBH-B @ _RMSGB-COPY
    DUP IF >R 2DROP R> _RMSGBH-B @ _RMSGB-LATCH EXIT THEN
    DROP _RMSGBH-CNU ! _RMSGBH-CNA !
    _RMSGBH-VA @ _RMSGBH-VU @ _RMSGBH-B @ _RMSGB-COPY
    DUP IF >R 2DROP R> _RMSGBH-B @ _RMSGB-LATCH EXIT THEN
    DROP _RMSGBH-CVU ! _RMSGBH-CVA !
    _RMSGBH-CNA @ _RMSGBH-CNU @ _RMSGBH-CVA @ _RMSGBH-CVU @
        _RMSGBH-B @ _RMSGB.FRAME RBF-FRAME-HEADER+ DUP IF
        _RMSGBH-B @ _RMSGB-RBF-FAIL EXIT
    THEN DROP RMSGB-S-OK ;

VARIABLE _RMSGBP-NA
VARIABLE _RMSGBP-NU
VARIABLE _RMSGBP-VA
VARIABLE _RMSGBP-VU
VARIABLE _RMSGBP-B

: RMSGB-HEADER+  ( name-a name-u value-a value-u builder -- status )
    _RMSGBP-B ! _RMSGBP-VU ! _RMSGBP-VA ! _RMSGBP-NU ! _RMSGBP-NA !
    _RMSGBP-B @ _RMSGB-BUILD-STATUS ?DUP IF EXIT THEN
    _RMSGBP-NA @ _RMSGBP-NU @ _RMSGBP-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF _RMSGBP-B @ _RMSGB-LATCH EXIT THEN
    _RMSGBP-VA @ _RMSGBP-VU @ _RMSGBP-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF _RMSGBP-B @ _RMSGB-LATCH EXIT THEN
    _RMSGBP-NA @ _RMSGBP-NU @ RBF-CORE-HEADER? IF
        RMSGB-S-UNSUPPORTED _RMSGBP-B @ _RMSGB-LATCH EXIT
    THEN
    _RMSGBP-NA @ _RMSGBP-NU @ _RMSGBP-VA @ _RMSGBP-VU @ _RMSGBP-B @
        _RMSGB-HEADER+ ;

VARIABLE _RMSGBNH-V
VARIABLE _RMSGBNH-NA
VARIABLE _RMSGBNH-NU
VARIABLE _RMSGBNH-B
VARIABLE _RMSGBNH-CNA
VARIABLE _RMSGBNH-CNU
VARIABLE _RMSGBNH-CVA
VARIABLE _RMSGBNH-CVU

: _RMSGB-U-HEADER+  ( value name-a name-u builder -- status )
    _RMSGBNH-B ! _RMSGBNH-NU ! _RMSGBNH-NA ! _RMSGBNH-V !
    _RMSGBNH-B @ _RMSGB-BUILD-STATUS ?DUP IF EXIT THEN
    _RMSGBNH-NA @ _RMSGBNH-NU @ _RMSGBNH-B @ _RMSGB-COPY
    DUP IF >R 2DROP R> _RMSGBNH-B @ _RMSGB-LATCH EXIT THEN
    DROP _RMSGBNH-CNU ! _RMSGBNH-CNA !
    _RMSGBNH-V @ _RMSGBNH-B @ _RMSGB-U-COPY
    DUP IF >R 2DROP R> _RMSGBNH-B @ _RMSGB-LATCH EXIT THEN
    DROP _RMSGBNH-CVU ! _RMSGBNH-CVA !
    _RMSGBNH-CNA @ _RMSGBNH-CNU @ _RMSGBNH-CVA @ _RMSGBNH-CVU @
        _RMSGBNH-B @ _RMSGB.FRAME RBF-FRAME-HEADER+ DUP IF
        _RMSGBNH-B @ _RMSGB-RBF-FAIL EXIT
    THEN DROP RMSGB-S-OK ;

: _RMSGB-CREDIT-HEADER+  ( credit builder -- status )
    _RMSGBNH-B ! _RMSGBNH-V !
    _RMSGBNH-B @ _RMSGB-BUILD-STATUS ?DUP IF EXIT THEN
    S" Credit" _RMSGBNH-B @ _RMSGB-COPY
    DUP IF >R 2DROP R> _RMSGBNH-B @ _RMSGB-LATCH EXIT THEN
    DROP _RMSGBNH-CNU ! _RMSGBNH-CNA !
    _RMSGBNH-V @ _RMSGBNH-B @ _RMSGB-CREDIT-COPY
    DUP IF >R 2DROP R> _RMSGBNH-B @ _RMSGB-LATCH EXIT THEN
    DROP _RMSGBNH-CVU ! _RMSGBNH-CVA !
    _RMSGBNH-CNA @ _RMSGBNH-CNU @ _RMSGBNH-CVA @ _RMSGBNH-CVU @
        _RMSGBNH-B @ _RMSGB.FRAME RBF-FRAME-HEADER+ DUP IF
        _RMSGBNH-B @ _RMSGB-RBF-FAIL EXIT
    THEN DROP RMSGB-S-OK ;

\ =====================================================================
\  Typed headers and body
\ =====================================================================

: _RMSGB-BUILD-INVALID  ( builder -- status )
    DUP _RMSGB-BUILD-STATUS ?DUP IF NIP EXIT THEN
    RMSGB-S-INVALID SWAP _RMSGB-LATCH ;

: RMSGB-LANE!  ( lane builder -- status )
    OVER RABBIT-LANE-MAX U> IF NIP _RMSGB-BUILD-INVALID EXIT THEN
    S" Lane" ROT _RMSGB-U-HEADER+ ;

: RMSGB-TXN!  ( txn-a txn-u builder -- status )
    OVER 0> 0= IF >R 2DROP R> _RMSGB-BUILD-INVALID EXIT THEN
    >R S" Txn" 2SWAP R> _RMSGB-HEADER+ ;

: RMSGB-SEQ!  ( seq builder -- status )
    OVER 0= IF NIP _RMSGB-BUILD-INVALID EXIT THEN
    S" Seq" ROT _RMSGB-U-HEADER+ ;

: RMSGB-ACK!  ( ack builder -- status )
    OVER 0= IF NIP _RMSGB-BUILD-INVALID EXIT THEN
    S" ACK" ROT _RMSGB-U-HEADER+ ;

: RMSGB-CREDIT!  ( amount builder -- status )
    OVER DUP 0= SWAP RABBIT-CREDIT-MAX U> OR IF
        NIP _RMSGB-BUILD-INVALID EXIT
    THEN
    _RMSGB-CREDIT-HEADER+ ;

: RMSGB-SINCE!  ( event-seq builder -- status )
    OVER 0= IF NIP _RMSGB-BUILD-INVALID EXIT THEN
    S" Since" ROT _RMSGB-U-HEADER+ ;

: RMSGB-EVENT-SEQ!  ( event-seq builder -- status )
    OVER 0= IF NIP _RMSGB-BUILD-INVALID EXIT THEN
    S" Event-Seq" ROT _RMSGB-U-HEADER+ ;

: RMSGB-IDEM!  ( idem-a idem-u builder -- status )
    OVER 0> 0= IF >R 2DROP R> _RMSGB-BUILD-INVALID EXIT THEN
    >R S" Idem" 2SWAP R> _RMSGB-HEADER+ ;

: RMSGB-VIEW!  ( view-a view-u builder -- status )
    OVER 0> 0= IF >R 2DROP R> _RMSGB-BUILD-INVALID EXIT THEN
    >R S" View" 2SWAP R> _RMSGB-HEADER+ ;

: RMSGB-ACCEPT-VIEW!  ( view-a view-u builder -- status )
    OVER 0> 0= IF >R 2DROP R> _RMSGB-BUILD-INVALID EXIT THEN
    >R S" Accept-View" 2SWAP R> _RMSGB-HEADER+ ;

: RMSGB-BURROW-ID!  ( identity-a identity-u builder -- status )
    OVER 0> 0= IF >R 2DROP R> _RMSGB-BUILD-INVALID EXIT THEN
    >R S" Burrow-ID" 2SWAP R> _RMSGB-HEADER+ ;

: RMSGB-TIMEOUT!  ( seconds builder -- status )
    S" Timeout" ROT _RMSGB-U-HEADER+ ;

VARIABLE _RMSGBQ-A
VARIABLE _RMSGBQ-U
VARIABLE _RMSGBQ-B

: RMSGB-QOS!  ( qos-a qos-u builder -- status )
    _RMSGBQ-B ! _RMSGBQ-U ! _RMSGBQ-A !
    _RMSGBQ-B @ _RMSGB-BUILD-STATUS ?DUP IF EXIT THEN
    _RMSGBQ-A @ _RMSGBQ-U @ _RMSGBQ-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF _RMSGBQ-B @ _RMSGB-LATCH EXIT THEN
    _RMSGBQ-A @ _RMSGBQ-U @ S" event" STR-STR= 0= IF
        _RMSGBQ-A @ _RMSGBQ-U @ S" stream" STR-STR= 0= IF
            _RMSGBQ-B @ _RMSGB-BUILD-INVALID EXIT
        THEN
    THEN
    S" QoS" _RMSGBQ-A @ _RMSGBQ-U @ _RMSGBQ-B @ _RMSGB-HEADER+ ;

VARIABLE _RMSGBB-A
VARIABLE _RMSGBB-U
VARIABLE _RMSGBB-B
VARIABLE _RMSGBB-CA
VARIABLE _RMSGBB-CU

: RMSGB-BODY!  ( body-a body-u builder -- status )
    _RMSGBB-B ! _RMSGBB-U ! _RMSGBB-A !
    _RMSGBB-B @ _RMSGB-BUILD-STATUS ?DUP IF EXIT THEN
    _RMSGBB-B @ _RMSGB.FLAGS @ _RMSGB-F-BODY AND IF
        RMSGB-S-STATE _RMSGBB-B @ _RMSGB-LATCH EXIT
    THEN
    _RMSGBB-A @ _RMSGBB-U @ _RMSGBB-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF _RMSGBB-B @ _RMSGB-LATCH EXIT THEN
    _RMSGBB-U @ IF
        _RMSGBB-U @ S" Length" _RMSGBB-B @ _RMSGB-U-HEADER+
        ?DUP IF EXIT THEN
    THEN
    _RMSGBB-A @ _RMSGBB-U @ _RMSGBB-B @ _RMSGB-COPY
    DUP IF >R 2DROP R> _RMSGBB-B @ _RMSGB-LATCH EXIT THEN
    DROP _RMSGBB-CU ! _RMSGBB-CA !
    _RMSGBB-CA @ _RMSGBB-CU @ _RMSGBB-B @ _RMSGB.FRAME
        RBF-FRAME-BODY! DUP IF
        _RMSGBB-B @ _RMSGB-RBF-FAIL EXIT
    THEN DROP
    _RMSGB-F-BODY _RMSGBB-B @ _RMSGB.FLAGS !
    RMSGB-S-OK ;

\ =====================================================================
\  Typed start constructors
\ =====================================================================

: _RMSGB-REQUEST-VERB$  ( kind -- a u )
    CASE
        RMSG-KIND-LIST OF S" LIST" ENDOF
        RMSG-KIND-DESCRIBE OF S" DESCRIBE" ENDOF
        RMSG-KIND-FETCH OF S" FETCH" ENDOF
        RMSG-KIND-SEARCH OF S" SEARCH" ENDOF
        RMSG-KIND-SUBSCRIBE OF S" SUBSCRIBE" ENDOF
        RMSG-KIND-PUBLISH OF S" PUBLISH" ENDOF
        RMSG-KIND-DELEGATE OF S" DELEGATE" ENDOF
        RMSG-KIND-OFFER OF S" OFFER" ENDOF
        0 0 ROT
    ENDCASE ;

VARIABLE _RMSGBRQ-KIND
VARIABLE _RMSGBRQ-TA
VARIABLE _RMSGBRQ-TU
VARIABLE _RMSGBRQ-LANE
VARIABLE _RMSGBRQ-XA
VARIABLE _RMSGBRQ-XU
VARIABLE _RMSGBRQ-B

: RMSGB-BEGIN-REQUEST
    ( kind target-a target-u lane txn-a txn-u builder -- status )
    _RMSGBRQ-B ! _RMSGBRQ-XU ! _RMSGBRQ-XA ! _RMSGBRQ-LANE !
    _RMSGBRQ-TU ! _RMSGBRQ-TA ! _RMSGBRQ-KIND !
    _RMSGBRQ-KIND @ RMSG-KIND-REQUEST? 0= IF
        _RMSGBRQ-B @ _RMSGB-EMPTY-STATUS ?DUP IF EXIT THEN
        RMSGB-S-UNSUPPORTED _RMSGBRQ-B @ _RMSGB-LATCH EXIT
    THEN
    _RMSGBRQ-KIND @ _RMSGBRQ-KIND @ _RMSGB-REQUEST-VERB$
    _RMSGBRQ-TA @ _RMSGBRQ-TU @ _RMSGBRQ-B @ _RMSGB-BEGIN$
    ?DUP IF EXIT THEN
    _RMSGBRQ-LANE @ _RMSGBRQ-B @ RMSGB-LANE! ?DUP IF EXIT THEN
    _RMSGBRQ-XA @ _RMSGBRQ-XU @ _RMSGBRQ-B @ RMSGB-TXN! ;

VARIABLE _RMSGBEV-TA
VARIABLE _RMSGBEV-TU
VARIABLE _RMSGBEV-LANE
VARIABLE _RMSGBEV-SEQ
VARIABLE _RMSGBEV-ESEQ
VARIABLE _RMSGBEV-B

: RMSGB-BEGIN-EVENT
    ( target-a target-u lane seq event-seq builder -- status )
    _RMSGBEV-B ! _RMSGBEV-ESEQ ! _RMSGBEV-SEQ ! _RMSGBEV-LANE !
    _RMSGBEV-TU ! _RMSGBEV-TA !
    RMSG-KIND-EVENT S" EVENT" _RMSGBEV-TA @ _RMSGBEV-TU @
        _RMSGBEV-B @ _RMSGB-BEGIN$ ?DUP IF EXIT THEN
    _RMSGBEV-LANE @ _RMSGBEV-B @ RMSGB-LANE! ?DUP IF EXIT THEN
    _RMSGBEV-SEQ @ _RMSGBEV-B @ RMSGB-SEQ! ?DUP IF EXIT THEN
    _RMSGBEV-ESEQ @ _RMSGBEV-B @ RMSGB-EVENT-SEQ! ;

VARIABLE _RMSGBC-LANE
VARIABLE _RMSGBC-V
VARIABLE _RMSGBC-BUILDER

: RMSGB-BEGIN-ACK  ( lane ack builder -- status )
    _RMSGBC-BUILDER ! _RMSGBC-V ! _RMSGBC-LANE !
    RMSG-KIND-ACK S" ACK" 0 0 _RMSGBC-BUILDER @ _RMSGB-BEGIN$
    ?DUP IF EXIT THEN
    _RMSGBC-LANE @ _RMSGBC-BUILDER @ RMSGB-LANE! ?DUP IF EXIT THEN
    _RMSGBC-V @ _RMSGBC-BUILDER @ RMSGB-ACK! ;

: RMSGB-BEGIN-CREDIT  ( lane amount builder -- status )
    _RMSGBC-BUILDER ! _RMSGBC-V ! _RMSGBC-LANE !
    RMSG-KIND-CREDIT S" CREDIT" 0 0 _RMSGBC-BUILDER @ _RMSGB-BEGIN$
    ?DUP IF EXIT THEN
    _RMSGBC-LANE @ _RMSGBC-BUILDER @ RMSGB-LANE! ?DUP IF EXIT THEN
    _RMSGBC-V @ _RMSGBC-BUILDER @ RMSGB-CREDIT! ;

: RMSGB-BEGIN-PING  ( builder -- status )
    >R RMSG-KIND-PING S" PING" 0 0 R@ _RMSGB-BEGIN$
    ?DUP IF R> DROP EXIT THEN
    0 R> RMSGB-LANE! ;

: _RMSGB-CAPS$  ( caps -- a u flag )
    DUP RABBIT-CAPS-KNOWN INVERT AND IF DROP 0 0 0 EXIT THEN
    CASE
        0 OF 0 0 -1 ENDOF
        RABBIT-CAP-F-LANES OF S" lanes" -1 ENDOF
        RABBIT-CAP-F-ASYNC OF S" async" -1 ENDOF
        RABBIT-CAPS-LANES-ASYNC OF S" lanes,async" -1 ENDOF
        0 0 0 ROT
    ENDCASE ;

VARIABLE _RMSGBHE-CAPS
VARIABLE _RMSGBHE-B

: RMSGB-BEGIN-HELLO  ( caps builder -- status )
    _RMSGBHE-B ! _RMSGBHE-CAPS !
    _RMSGBHE-CAPS @ _RMSGB-CAPS$ 0= IF
        2DROP
        _RMSGBHE-B @ _RMSGB-EMPTY-STATUS ?DUP IF EXIT THEN
        RMSGB-S-INVALID _RMSGBHE-B @ _RMSGB-LATCH EXIT
    THEN
    2DROP
    RMSG-KIND-HELLO S" HELLO" S" RABBIT/1.0" _RMSGBHE-B @
        _RMSGB-BEGIN$ ?DUP IF EXIT THEN
    _RMSGBHE-CAPS @ _RMSGB-CAPS$ DROP
    DUP IF
        _RMSGBHE-B @ >R S" Caps" 2SWAP R> _RMSGB-HEADER+
    ELSE
        2DROP RMSGB-S-OK
    THEN ;

VARIABLE _RMSGBRS-CODE
VARIABLE _RMSGBRS-LA
VARIABLE _RMSGBRS-LU
VARIABLE _RMSGBRS-B
VARIABLE _RMSGBRS-N
VARIABLE _RMSGBRS-D

: _RMSGB-BEGIN-RESPONSE$  ( code label-a label-u builder -- status )
    _RMSGBRS-B ! _RMSGBRS-LU ! _RMSGBRS-LA ! _RMSGBRS-CODE !
    _RMSGBRS-B @ _RMSGB-EMPTY-STATUS ?DUP IF EXIT THEN
    _RMSGBRS-CODE @ DUP 100 < SWAP 599 > OR IF
        RMSGB-S-INVALID _RMSGBRS-B @ _RMSGB-LATCH EXIT
    THEN
    _RMSGBRS-LU @ 0> 0= IF
        RMSGB-S-INVALID _RMSGBRS-B @ _RMSGB-LATCH EXIT
    THEN
    _RMSGBRS-LA @ _RMSGBRS-LU @ _RMSGBRS-B @ _RMSGB-SOURCE-STATUS
    ?DUP IF _RMSGBRS-B @ _RMSGB-LATCH EXIT THEN
    _RMSGBRS-LU @ 4 + DUP 0< IF
        DROP RMSGB-S-CAPACITY _RMSGBRS-B @ _RMSGB-LATCH EXIT
    THEN _RMSGBRS-N !
    _RMSGBRS-N @ _RMSGBRS-B @ _RMSGB-RESERVE DUP IF
        >R DROP R> _RMSGBRS-B @ _RMSGB-LATCH EXIT
    THEN DROP _RMSGBRS-D !
    _RMSGBRS-CODE @ 100 / [CHAR] 0 + _RMSGBRS-D @ C!
    _RMSGBRS-CODE @ 100 MOD 10 / [CHAR] 0 + _RMSGBRS-D @ 1+ C!
    _RMSGBRS-CODE @ 10 MOD [CHAR] 0 + _RMSGBRS-D @ 2 + C!
    32 _RMSGBRS-D @ 3 + C!
    _RMSGBRS-LA @ _RMSGBRS-D @ 4 + _RMSGBRS-LU @ MOVE
    _RMSGBRS-D @ _RMSGBRS-N @ _RMSGBRS-B @ _RMSGB.FRAME
        RBF-FRAME-START! DUP IF
        _RMSGBRS-B @ _RMSGB-RBF-FAIL EXIT
    THEN DROP
    RMSG-KIND-RESPONSE _RMSGBRS-B @ _RMSGB.KIND !
    RMSGB-STATE-BUILD _RMSGBRS-B @ _RMSGB.STATE !
    RMSGB-S-OK ;

: RMSGB-BEGIN-CONTROL-RESPONSE  ( code label-a label-u builder -- status )
    _RMSGB-BEGIN-RESPONSE$ ;

VARIABLE _RMSGBCR-CODE
VARIABLE _RMSGBCR-LA
VARIABLE _RMSGBCR-LU
VARIABLE _RMSGBCR-LANE
VARIABLE _RMSGBCR-XA
VARIABLE _RMSGBCR-XU
VARIABLE _RMSGBCR-B

: RMSGB-BEGIN-RESPONSE
    ( code label-a label-u lane txn-a txn-u builder -- status )
    _RMSGBCR-B ! _RMSGBCR-XU ! _RMSGBCR-XA ! _RMSGBCR-LANE !
    _RMSGBCR-LU ! _RMSGBCR-LA ! _RMSGBCR-CODE !
    _RMSGBCR-CODE @ _RMSGBCR-LA @ _RMSGBCR-LU @ _RMSGBCR-B @
        _RMSGB-BEGIN-RESPONSE$ ?DUP IF EXIT THEN
    _RMSGBCR-LANE @ _RMSGBCR-B @ RMSGB-LANE! ?DUP IF EXIT THEN
    _RMSGBCR-XA @ _RMSGBCR-XU @ _RMSGBCR-B @ RMSGB-TXN! ;

: RMSGB-BEGIN-PONG  ( builder -- status )
    >R 200 S" PONG" R@ RMSGB-BEGIN-CONTROL-RESPONSE ?DUP IF
        R> DROP EXIT
    THEN
    0 R> RMSGB-LANE! ;

VARIABLE _RMSGBHE-IA
VARIABLE _RMSGBHE-IU

: RMSGB-BEGIN-HELLO-OK  ( caps burrow-a burrow-u builder -- status )
    _RMSGBHE-B ! _RMSGBHE-IU ! _RMSGBHE-IA ! _RMSGBHE-CAPS !
    _RMSGBHE-CAPS @ _RMSGB-CAPS$ 0= IF
        2DROP
        _RMSGBHE-B @ _RMSGB-EMPTY-STATUS ?DUP IF EXIT THEN
        RMSGB-S-INVALID _RMSGBHE-B @ _RMSGB-LATCH EXIT
    THEN
    2DROP
    200 S" HELLO" _RMSGBHE-B @ RMSGB-BEGIN-CONTROL-RESPONSE
        ?DUP IF EXIT THEN
    _RMSGBHE-IA @ _RMSGBHE-IU @ _RMSGBHE-B @ RMSGB-BURROW-ID!
        ?DUP IF EXIT THEN
    _RMSGBHE-CAPS @ _RMSGB-CAPS$ DROP
    DUP IF
        _RMSGBHE-B @ >R S" Caps" 2SWAP R> _RMSGB-HEADER+
    ELSE
        2DROP RMSGB-S-OK
    THEN ;

VARIABLE _RMSGBX-VA
VARIABLE _RMSGBX-VU
VARIABLE _RMSGBX-AA
VARIABLE _RMSGBX-AU
VARIABLE _RMSGBX-B

: RMSGB-BEGIN-EXTENSION  ( verb-a verb-u args-a args-u builder -- status )
    _RMSGBX-B ! _RMSGBX-AU ! _RMSGBX-AA ! _RMSGBX-VU ! _RMSGBX-VA !
    RMSG-KIND-UNKNOWN _RMSGBX-VA @ _RMSGBX-VU @
        _RMSGBX-AA @ _RMSGBX-AU @ _RMSGBX-B @ _RMSGB-BEGIN$ ;

\ =====================================================================
\  Seal, measure, and all-or-nothing encode
\ =====================================================================

VARIABLE _RMSGBSE-B
VARIABLE _RMSGBSE-KIND
VARIABLE _RMSGBSE-MSTATUS

: RMSGB-SEAL  ( builder -- status )
    DUP _RMSGBSE-B ! _RMSGB-BUILD-STATUS ?DUP IF EXIT THEN
    _RMSGBSE-B @ _RMSGB.FRAME RBF-FRAME-SEAL DUP IF
        _RMSGBSE-B @ _RMSGB-RBF-FAIL EXIT
    THEN DROP
    _RMSGBSE-B @ _RMSGB.FRAME RMSG-ADMIT
    _RMSGBSE-MSTATUS ! _RMSGBSE-KIND !
    _RMSGBSE-MSTATUS @ IF
        _RMSGBSE-MSTATUS @ _RMSGBSE-B @ _RMSGB-RMSG-FAIL EXIT
    THEN
    _RMSGBSE-KIND @ _RMSGBSE-B @ _RMSGB.KIND @ <> IF
        RMSG-S-CONFLICT _RMSGBSE-B @ _RMSGB.RMSG-DETAIL !
        RMSGB-S-MESSAGE _RMSGBSE-B @ _RMSGB-LATCH EXIT
    THEN
    RMSGB-STATE-READY _RMSGBSE-B @ _RMSGB.STATE !
    RMSGB-S-OK ;

: RMSGB-MEASURE  ( builder -- exact-bytes status )
    DUP RMSGB-VALID? 0= IF DROP 0 RMSGB-S-INVALID EXIT THEN
    DUP _RMSGB.STATE @ RMSGB-STATE-READY <> IF
        DROP 0 RMSGB-S-STATE EXIT
    THEN
    _RMSGB.FRAME RBF-FRAME-MEASURE
    DUP IF _RMSGB-RBF>STATUS ELSE DROP RMSGB-S-OK THEN ;

VARIABLE _RMSGBE-A
VARIABLE _RMSGBE-U
VARIABLE _RMSGBE-B
VARIABLE _RMSGBE-N
VARIABLE _RMSGBE-RS

: RMSGB-ENCODE  ( output-a output-capacity builder -- written status )
    _RMSGBE-B ! _RMSGBE-U ! _RMSGBE-A !
    _RMSGBE-B @ RMSGB-VALID? 0= IF 0 RMSGB-S-INVALID EXIT THEN
    _RMSGBE-B @ _RMSGB.STATE @ RMSGB-STATE-READY <> IF
        0 RMSGB-S-STATE EXIT
    THEN
    _RMSGBE-U @ 0< IF 0 RMSGB-S-INVALID EXIT THEN
    _RMSGBE-U @ 0> _RMSGBE-A @ 0= AND IF 0 RMSGB-S-INVALID EXIT THEN
    _RMSGBE-A @ _RMSGBE-U @ MSPAN-NONWRAPPING? 0= IF
        0 RMSGB-S-INVALID EXIT
    THEN
    _RMSGBE-A @ _RMSGBE-U @
        _RMSGBE-B @ _RMSGB.BYTES @ _RMSGBE-B @ SWAP
        MSPAN-OVERLAP? IF 0 RMSGB-S-ALIAS EXIT THEN
    _RMSGBE-A @ _RMSGBE-U @
        _RMSGBE-B @ _RMSGB.ARENA @ _RMSGBE-B @ _RMSGB.ARENA-CAP @
        MSPAN-OVERLAP? IF 0 RMSGB-S-ALIAS EXIT THEN
    _RMSGBE-A @ _RMSGBE-U @ _RMSGBE-B @ _RMSGB.FRAME
        RBF-FRAME-ENCODE
    _RMSGBE-RS ! _RMSGBE-N !
    _RMSGBE-RS @ IF
        0 _RMSGBE-RS @ _RMSGB-RBF>STATUS
    ELSE
        _RMSGBE-N @ RMSGB-S-OK
    THEN ;
