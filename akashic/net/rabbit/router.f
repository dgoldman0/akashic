\ =====================================================================
\  router.f - Caller-owned exact Rabbit selector routing
\ =====================================================================
\  This module owns immutable route configuration, not server dispatch.
\  The caller supplies one opaque router descriptor and, for a nonempty
\  capacity, a pairwise-disjoint entry array and byte arena.  Capacity zero
\  has the canonical binding (entries=0, arena=0, arena-u=0) and represents a
\  useful sealed deny-all router without dummy allocations.
\  Registration copies each exact verb and selector into the arena before
\  publishing an entry.  Handler execution tokens and their opaque contexts
\  are borrowed; the caller keeps them stable until RESET or FINI.
\
\  Rabbit request routing is an exact, case-sensitive match on the pair
\  (verb, selector).  A verb is the nonempty first token of a Rabbit start
\  line: strict UTF-8 with no ASCII space, control byte, or DEL.  A selector
\  is the nonempty remainder of that line: strict UTF-8, no leading/trailing
\  or repeated ASCII space, and no control byte or DEL.  Thus joining an
\  admitted verb, one ASCII space, and an admitted selector always satisfies
\  the frame start-line grammar.  This layer does not impose a path syntax or
\  product length limit; the caller's entry and arena capacities are the only
\  ordinary bounds.
\  Descriptor and entry storage are opaque while owned.  Semantic validation
\  is linear in the published entry count; duplicate prevention happens once
\  during ADD rather than being rescanned by every validation.  A narrower
\  binding validator lets FINI wipe the originally bound regions even when
\  route content, count, or used-byte evidence is damaged.  Caller mutation
\  or forgery of the opaque binding cells themselves is outside that recovery
\  contract: without an external ownership witness, their addresses cannot be
\  distinguished from attacker-chosen wipe targets.
\
\  Lifecycle and lookup API:
\
\    RROUTER-CAPACITY-VALID? ( capacity -- flag )
\    RROUTER-ENTRY-BYTES  ( capacity -- bytes|0 )
\    RROUTER-BINDING-VALID? ( router -- flag )
\    RROUTER-VALID?       ( router -- flag )
\    RROUTER-INIT         ( entries capacity arena arena-u router -- status )
\    RROUTER-ADD          ( verb-a verb-u selector-a selector-u
\                           handler-xt handler-context router -- status )
\    RROUTER-SEAL         ( router -- status )
\    RROUTER-MATCH        ( verb-a verb-u selector-a selector-u router
\                           -- handler-xt handler-context status )
\    RROUTER-RESET        ( router -- status )
\    RROUTER-FINI         ( router -- status )
\
\  INIT wipes all supplied storage before taking ownership.  ADD preflights
\  grammar, source aliasing, duplicates, entry capacity, and byte capacity
\  before copying or changing any published state.  SEAL makes the route set
\  immutable.  MATCH invokes nothing and only returns the selected borrowed
\  handler/context.  RESET wipes the complete entry array and arena while
\  retaining their binding for a fresh BUILDING configuration; FINI wipes all
\  three regions and releases the binding.
\
\  The private VARIABLE cells are synchronous operation scratch only; even
\  read-only validation and matching use them.  No word in this module calls
\  a handler, calls back, blocks, or yields, but every call must be serialized
\  until the scratch moves into caller-owned working storage.  FINI clears the
\  scratch cells that can retain input, handler, context, or storage pointers.
\  All persistent route state and retained route bytes are caller-owned.
\ =====================================================================

PROVIDED akashic-rabbit-router

REQUIRE ../../utils/memory-span.f
REQUIRE ../../text/utf8.f

\ =====================================================================
\  Public status and state vocabulary
\ =====================================================================

0 CONSTANT RROUTER-S-OK
1 CONSTANT RROUTER-S-INVALID
2 CONSTANT RROUTER-S-STATE
3 CONSTANT RROUTER-S-CAPACITY
4 CONSTANT RROUTER-S-DUPLICATE
5 CONSTANT RROUTER-S-NOT-FOUND
6 CONSTANT RROUTER-S-UTF8
7 CONSTANT RROUTER-S-GRAMMAR
8 CONSTANT RROUTER-S-ALIAS

1 CONSTANT RROUTER-STATE-BUILDING
2 CONSTANT RROUTER-STATE-SEALED

: RROUTER-STATUS-VALID?  ( status -- flag )
    DUP RROUTER-S-OK >= SWAP RROUTER-S-ALIAS <= AND ;

: RROUTER-STATE-VALID?  ( state -- flag )
    DUP RROUTER-STATE-BUILDING =
    SWAP RROUTER-STATE-SEALED = OR ;

\ =====================================================================
\  Caller-owned entry array
\ =====================================================================

 0 CONSTANT _RROUTE-VERB-A
 8 CONSTANT _RROUTE-VERB-U
16 CONSTANT _RROUTE-SELECTOR-A
24 CONSTANT _RROUTE-SELECTOR-U
32 CONSTANT _RROUTE-HANDLER-XT
40 CONSTANT _RROUTE-HANDLER-CONTEXT
48 CONSTANT RROUTER-ENTRY-SIZE

: _RROUTE.VERB-A          ( entry -- field ) _RROUTE-VERB-A + ;
: _RROUTE.VERB-U          ( entry -- field ) _RROUTE-VERB-U + ;
: _RROUTE.SELECTOR-A      ( entry -- field ) _RROUTE-SELECTOR-A + ;
: _RROUTE.SELECTOR-U      ( entry -- field ) _RROUTE-SELECTOR-U + ;
: _RROUTE.HANDLER-XT      ( entry -- field ) _RROUTE-HANDLER-XT + ;
: _RROUTE.HANDLER-CONTEXT ( entry -- field ) _RROUTE-HANDLER-CONTEXT + ;

-1 1 RSHIFT RROUTER-ENTRY-SIZE / CONSTANT _RROUTER-CAPACITY-MAX

: RROUTER-CAPACITY-VALID?  ( capacity -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    _RROUTER-CAPACITY-MAX U> 0= ;

\ Zero is both the exact byte size for a zero-capacity router and the sizing
\ failure sentinel.  Use RROUTER-CAPACITY-VALID? when that distinction matters.
: RROUTER-ENTRY-BYTES  ( capacity -- bytes|0 )
    DUP RROUTER-CAPACITY-VALID? 0= IF DROP 0 EXIT THEN
    RROUTER-ENTRY-SIZE * ;

\ =====================================================================
\  Opaque caller-owned descriptor
\ =====================================================================

0x52524F5554455231 CONSTANT _RROUTER-MAGIC-VALUE  \ "RROUTER1"
1                  CONSTANT _RROUTER-ABI-VERSION

 0 CONSTANT _RROUTER-MAGIC
 8 CONSTANT _RROUTER-ABI
16 CONSTANT _RROUTER-BYTES
24 CONSTANT _RROUTER-STATE
32 CONSTANT _RROUTER-ENTRIES
40 CONSTANT _RROUTER-ENTRY-CAPACITY
48 CONSTANT _RROUTER-COUNT
56 CONSTANT _RROUTER-ARENA-A
64 CONSTANT _RROUTER-ARENA-CAPACITY
72 CONSTANT _RROUTER-ARENA-USED
80 CONSTANT RROUTER-SIZE

: _RROUTER.MAGIC          ( router -- field ) _RROUTER-MAGIC + ;
: _RROUTER.ABI            ( router -- field ) _RROUTER-ABI + ;
: _RROUTER.BYTES          ( router -- field ) _RROUTER-BYTES + ;
: _RROUTER.STATE          ( router -- field ) _RROUTER-STATE + ;
: _RROUTER.ENTRIES        ( router -- field ) _RROUTER-ENTRIES + ;
: _RROUTER.ENTRY-CAPACITY ( router -- field ) _RROUTER-ENTRY-CAPACITY + ;
: _RROUTER.COUNT          ( router -- field ) _RROUTER-COUNT + ;
: _RROUTER.ARENA-A        ( router -- field ) _RROUTER-ARENA-A + ;
: _RROUTER.ARENA-CAPACITY ( router -- field ) _RROUTER-ARENA-CAPACITY + ;
: _RROUTER.ARENA-USED     ( router -- field ) _RROUTER-ARENA-USED + ;

: _RROUTER-ENTRY  ( index router -- entry )
    _RROUTER.ENTRIES @ SWAP RROUTER-ENTRY-SIZE * + ;

\ =====================================================================
\  Span equality and Rabbit start-line component grammar
\ =====================================================================

: _RROUTER-SPAN=  ( a1 u1 a2 u2 -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP -1 EXIT THEN
    >R SWAP DROP R>
    0 ?DO
        OVER I + C@ OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _RROUTER-NONEMPTY-SPAN?  ( address length -- flag )
    DUP 1 < IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

VARIABLE _RROUTER-GRAMMAR-A
VARIABLE _RROUTER-GRAMMAR-U
VARIABLE _RROUTER-GRAMMAR-PREV-SPACE

: _RROUTER-VERB-GRAMMAR?  ( address length -- flag )
    _RROUTER-GRAMMAR-U ! _RROUTER-GRAMMAR-A !
    _RROUTER-GRAMMAR-U @ 0= IF 0 EXIT THEN
    _RROUTER-GRAMMAR-U @ 0 ?DO
        _RROUTER-GRAMMAR-A @ I + C@
        DUP 32 <= OVER 127 = OR IF DROP 0 UNLOOP EXIT THEN
        DROP
    LOOP
    -1 ;

: _RROUTER-SELECTOR-GRAMMAR?  ( address length -- flag )
    _RROUTER-GRAMMAR-U ! _RROUTER-GRAMMAR-A !
    _RROUTER-GRAMMAR-U @ 0= IF 0 EXIT THEN
    0 _RROUTER-GRAMMAR-PREV-SPACE !
    _RROUTER-GRAMMAR-U @ 0 ?DO
        _RROUTER-GRAMMAR-A @ I + C@
        DUP 32 < OVER 127 = OR IF DROP 0 UNLOOP EXIT THEN
        DUP 32 = IF
            DROP
            I 0= IF 0 UNLOOP EXIT THEN
            I _RROUTER-GRAMMAR-U @ 1- = IF 0 UNLOOP EXIT THEN
            _RROUTER-GRAMMAR-PREV-SPACE @ IF 0 UNLOOP EXIT THEN
            -1 _RROUTER-GRAMMAR-PREV-SPACE !
        ELSE
            DROP 0 _RROUTER-GRAMMAR-PREV-SPACE !
        THEN
    LOOP
    -1 ;

\ =====================================================================
\  Persistent invariant validation
\ =====================================================================

VARIABLE _RROUTER-EV-R
VARIABLE _RROUTER-EV-E
VARIABLE _RROUTER-EV-OFFSET
VARIABLE _RROUTER-EV-U

: _RROUTER-ENTRIES-VALID?  ( router -- flag )
    _RROUTER-EV-R !
    0 _RROUTER-EV-OFFSET !
    _RROUTER-EV-R @ _RROUTER.COUNT @ 0 ?DO
        I _RROUTER-EV-R @ _RROUTER-ENTRY _RROUTER-EV-E !

        _RROUTER-EV-E @ _RROUTE.VERB-A @
        _RROUTER-EV-R @ _RROUTER.ARENA-A @
            _RROUTER-EV-OFFSET @ + <> IF
            0 UNLOOP EXIT
        THEN
        _RROUTER-EV-E @ _RROUTE.VERB-U @ DUP _RROUTER-EV-U !
        DUP 1 < IF DROP 0 UNLOOP EXIT THEN
        _RROUTER-EV-R @ _RROUTER.ARENA-CAPACITY @
            _RROUTER-EV-OFFSET @ - U> IF 0 UNLOOP EXIT THEN
        _RROUTER-EV-E @ _RROUTE.VERB-A @ _RROUTER-EV-U @
            UTF8-VALID? 0= IF 0 UNLOOP EXIT THEN
        _RROUTER-EV-E @ _RROUTE.VERB-A @ _RROUTER-EV-U @
            _RROUTER-VERB-GRAMMAR? 0= IF 0 UNLOOP EXIT THEN
        _RROUTER-EV-U @ _RROUTER-EV-OFFSET +!

        _RROUTER-EV-E @ _RROUTE.SELECTOR-A @
        _RROUTER-EV-R @ _RROUTER.ARENA-A @
            _RROUTER-EV-OFFSET @ + <> IF
            0 UNLOOP EXIT
        THEN
        _RROUTER-EV-E @ _RROUTE.SELECTOR-U @ DUP _RROUTER-EV-U !
        DUP 1 < IF DROP 0 UNLOOP EXIT THEN
        _RROUTER-EV-R @ _RROUTER.ARENA-CAPACITY @
            _RROUTER-EV-OFFSET @ - U> IF 0 UNLOOP EXIT THEN
        _RROUTER-EV-E @ _RROUTE.SELECTOR-A @ _RROUTER-EV-U @
            UTF8-VALID? 0= IF 0 UNLOOP EXIT THEN
        _RROUTER-EV-E @ _RROUTE.SELECTOR-A @ _RROUTER-EV-U @
            _RROUTER-SELECTOR-GRAMMAR? 0= IF 0 UNLOOP EXIT THEN
        _RROUTER-EV-U @ _RROUTER-EV-OFFSET +!

        _RROUTER-EV-E @ _RROUTE.HANDLER-XT @ 0= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    _RROUTER-EV-OFFSET @ _RROUTER-EV-R @ _RROUTER.ARENA-USED @ = ;

VARIABLE _RROUTER-V-R
VARIABLE _RROUTER-V-ENTRY-BYTES

: RROUTER-BINDING-VALID?  ( router -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP RROUTER-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    _RROUTER-V-R !
    _RROUTER-V-R @ _RROUTER.MAGIC @
        _RROUTER-MAGIC-VALUE <> IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.ABI @
        _RROUTER-ABI-VERSION <> IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.BYTES @ RROUTER-SIZE <> IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.STATE @
        RROUTER-STATE-VALID? 0= IF 0 EXIT THEN

    _RROUTER-V-R @ _RROUTER.ENTRY-CAPACITY @ DUP
        RROUTER-CAPACITY-VALID? 0= IF DROP 0 EXIT THEN
    DUP RROUTER-ENTRY-BYTES _RROUTER-V-ENTRY-BYTES !
    0= IF
        _RROUTER-V-R @ _RROUTER.ENTRIES @ 0=
        _RROUTER-V-R @ _RROUTER.ARENA-A @ 0= AND
        _RROUTER-V-R @ _RROUTER.ARENA-CAPACITY @ 0= AND
        EXIT
    THEN

    _RROUTER-V-R @ _RROUTER.ENTRIES @ DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    _RROUTER-V-ENTRY-BYTES @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.ENTRIES @ _RROUTER-V-ENTRY-BYTES @
        _RROUTER-V-R @ RROUTER-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN

    _RROUTER-V-R @ _RROUTER.ARENA-CAPACITY @ DUP 0> 0= IF
        DROP 0 EXIT
    THEN DROP
    _RROUTER-V-R @ _RROUTER.ARENA-A @ DUP 0= IF DROP 0 EXIT THEN
    DROP
    _RROUTER-V-R @ _RROUTER.ARENA-A @
        _RROUTER-V-R @ _RROUTER.ARENA-CAPACITY @
        MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.ARENA-A @
        _RROUTER-V-R @ _RROUTER.ARENA-CAPACITY @
        _RROUTER-V-R @ RROUTER-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.ARENA-A @
        _RROUTER-V-R @ _RROUTER.ARENA-CAPACITY @
        _RROUTER-V-R @ _RROUTER.ENTRIES @ _RROUTER-V-ENTRY-BYTES @
        MSPAN-OVERLAP? 0= ;

\ Semantic validity adds published count/used bounds and exact packed-entry
\ admission to the stable ownership geometry above.  It intentionally does
\ not rescan earlier entries for duplicates; only ADD can publish an entry.
: RROUTER-VALID?  ( router -- flag )
    DUP RROUTER-BINDING-VALID? 0= IF DROP 0 EXIT THEN
    _RROUTER-V-R !

    _RROUTER-V-R @ _RROUTER.COUNT @ DUP 0< IF DROP 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.ENTRY-CAPACITY @ > IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.ARENA-USED @ DUP 0< IF DROP 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER.ARENA-CAPACITY @ > IF 0 EXIT THEN
    _RROUTER-V-R @ _RROUTER-ENTRIES-VALID? ;

: RROUTER-SEALED?  ( router -- flag )
    DUP RROUTER-VALID? 0= IF DROP 0 EXIT THEN
    _RROUTER.STATE @ RROUTER-STATE-SEALED = ;

VARIABLE _RROUTER-O-A
VARIABLE _RROUTER-O-U
VARIABLE _RROUTER-O-R

\ Report whether a caller span touches the complete allocation owned by a
\ valid router.  Invalid span geometry or an invalid router reports overlap
\ conservatively so higher neutral owners can fail closed without importing
\ this descriptor's private layout.
: RROUTER-OWNED-SPAN-OVERLAP?  ( address bytes router -- flag )
    _RROUTER-O-R ! _RROUTER-O-U ! _RROUTER-O-A !
    _RROUTER-O-U @ 0< IF -1 EXIT THEN
    _RROUTER-O-U @ IF _RROUTER-O-A @ 0= IF -1 EXIT THEN THEN
    _RROUTER-O-A @ _RROUTER-O-U @ MSPAN-NONWRAPPING? 0= IF -1 EXIT THEN
    _RROUTER-O-R @ RROUTER-VALID? 0= IF -1 EXIT THEN
    _RROUTER-O-A @ _RROUTER-O-U @
        _RROUTER-O-R @ RROUTER-SIZE MSPAN-OVERLAP? IF -1 EXIT THEN
    _RROUTER-O-A @ _RROUTER-O-U @
        _RROUTER-O-R @ _RROUTER.ENTRIES @
        _RROUTER-O-R @ _RROUTER.ENTRY-CAPACITY @ RROUTER-ENTRY-SIZE *
        MSPAN-OVERLAP? IF -1 EXIT THEN
    _RROUTER-O-A @ _RROUTER-O-U @
        _RROUTER-O-R @ _RROUTER.ARENA-A @
        _RROUTER-O-R @ _RROUTER.ARENA-CAPACITY @ MSPAN-OVERLAP? ;

\ =====================================================================
\  Safe public evidence and route inspection
\ =====================================================================

: RROUTER-STATE@  ( router -- state|0 )
    DUP RROUTER-VALID? 0= IF DROP 0 EXIT THEN
    _RROUTER.STATE @ ;

: RROUTER-COUNT@  ( router -- count|0 )
    DUP RROUTER-VALID? 0= IF DROP 0 EXIT THEN
    _RROUTER.COUNT @ ;

: RROUTER-CAPACITY@  ( router -- capacity|0 )
    DUP RROUTER-VALID? 0= IF DROP 0 EXIT THEN
    _RROUTER.ENTRY-CAPACITY @ ;

: RROUTER-ARENA-CAPACITY@  ( router -- bytes|0 )
    DUP RROUTER-VALID? 0= IF DROP 0 EXIT THEN
    _RROUTER.ARENA-CAPACITY @ ;

: RROUTER-ARENA-USED@  ( router -- bytes|0 )
    DUP RROUTER-VALID? 0= IF DROP 0 EXIT THEN
    _RROUTER.ARENA-USED @ ;

: _RROUTER-ENTRY@  ( index router -- entry flag )
    DUP RROUTER-VALID? 0= IF 2DROP 0 0 EXIT THEN
    OVER 0< IF 2DROP 0 0 EXIT THEN
    OVER OVER _RROUTER.COUNT @ >= IF 2DROP 0 0 EXIT THEN
    _RROUTER-ENTRY -1 ;

\ Returned strings borrow the router arena and expire on RESET/FINI.
: RROUTER-VERB$  ( index router -- address length flag )
    _RROUTER-ENTRY@ 0= IF DROP 0 0 0 EXIT THEN
    DUP _RROUTE.VERB-A @ SWAP _RROUTE.VERB-U @ -1 ;

: RROUTER-SELECTOR$  ( index router -- address length flag )
    _RROUTER-ENTRY@ 0= IF DROP 0 0 0 EXIT THEN
    DUP _RROUTE.SELECTOR-A @ SWAP _RROUTE.SELECTOR-U @ -1 ;

: RROUTER-HANDLER@  ( index router -- handler-xt handler-context flag )
    _RROUTER-ENTRY@ 0= IF DROP 0 0 0 EXIT THEN
    DUP _RROUTE.HANDLER-XT @ SWAP _RROUTE.HANDLER-CONTEXT @ -1 ;

\ =====================================================================
\  Initialization, reset, and finalization
\ =====================================================================

VARIABLE _RROUTER-I-ENTRIES
VARIABLE _RROUTER-I-CAPACITY
VARIABLE _RROUTER-I-ENTRY-BYTES
VARIABLE _RROUTER-I-ARENA
VARIABLE _RROUTER-I-ARENA-U
VARIABLE _RROUTER-I-R

: RROUTER-INIT
    ( entries capacity arena arena-u router -- status )
    _RROUTER-I-R ! _RROUTER-I-ARENA-U ! _RROUTER-I-ARENA !
    _RROUTER-I-CAPACITY ! _RROUTER-I-ENTRIES !

    _RROUTER-I-R @ 0= IF RROUTER-S-INVALID EXIT THEN
    _RROUTER-I-R @ 7 AND IF RROUTER-S-INVALID EXIT THEN
    _RROUTER-I-R @ RROUTER-SIZE MSPAN-NONWRAPPING? 0= IF
        RROUTER-S-INVALID EXIT
    THEN
    _RROUTER-I-CAPACITY @ RROUTER-CAPACITY-VALID? 0= IF
        RROUTER-S-INVALID EXIT
    THEN
    _RROUTER-I-CAPACITY @ RROUTER-ENTRY-BYTES
        _RROUTER-I-ENTRY-BYTES !
    _RROUTER-I-CAPACITY @ 0= IF
        _RROUTER-I-ENTRIES @ 0<> IF RROUTER-S-INVALID EXIT THEN
        _RROUTER-I-ARENA @ 0<> IF RROUTER-S-INVALID EXIT THEN
        _RROUTER-I-ARENA-U @ 0<> IF RROUTER-S-INVALID EXIT THEN
    ELSE
        _RROUTER-I-ENTRIES @ 0= IF RROUTER-S-INVALID EXIT THEN
        _RROUTER-I-ENTRIES @ 7 AND IF RROUTER-S-INVALID EXIT THEN
        _RROUTER-I-ENTRIES @ _RROUTER-I-ENTRY-BYTES @
            MSPAN-NONWRAPPING? 0= IF RROUTER-S-INVALID EXIT THEN
        _RROUTER-I-ARENA-U @ 0> 0= IF RROUTER-S-INVALID EXIT THEN
        _RROUTER-I-ARENA @ 0= IF RROUTER-S-INVALID EXIT THEN
        _RROUTER-I-ARENA @ _RROUTER-I-ARENA-U @
            MSPAN-NONWRAPPING? 0= IF RROUTER-S-INVALID EXIT THEN

        _RROUTER-I-ENTRIES @ _RROUTER-I-ENTRY-BYTES @
            _RROUTER-I-R @ RROUTER-SIZE MSPAN-OVERLAP? IF
            RROUTER-S-ALIAS EXIT
        THEN
        _RROUTER-I-ARENA @ _RROUTER-I-ARENA-U @
            _RROUTER-I-R @ RROUTER-SIZE MSPAN-OVERLAP? IF
            RROUTER-S-ALIAS EXIT
        THEN
        _RROUTER-I-ARENA @ _RROUTER-I-ARENA-U @
            _RROUTER-I-ENTRIES @ _RROUTER-I-ENTRY-BYTES @
            MSPAN-OVERLAP? IF RROUTER-S-ALIAS EXIT THEN
    THEN

    \ A matching magic claims a live or damaged owner.  Never erase it via
    \ INIT: use RESET for semantically valid content or FINI when the binding
    \ geometry still proves which complete regions belong to the owner.
    _RROUTER-I-R @ _RROUTER.MAGIC @ _RROUTER-MAGIC-VALUE = IF
        RROUTER-S-STATE EXIT
    THEN

    _RROUTER-I-R @ RROUTER-SIZE 0 FILL
    _RROUTER-I-ENTRY-BYTES @ IF
        _RROUTER-I-ENTRIES @ _RROUTER-I-ENTRY-BYTES @ 0 FILL
    THEN
    _RROUTER-I-ARENA-U @ IF
        _RROUTER-I-ARENA @ _RROUTER-I-ARENA-U @ 0 FILL
    THEN
    _RROUTER-MAGIC-VALUE _RROUTER-I-R @ _RROUTER.MAGIC !
    _RROUTER-ABI-VERSION _RROUTER-I-R @ _RROUTER.ABI !
    RROUTER-SIZE _RROUTER-I-R @ _RROUTER.BYTES !
    RROUTER-STATE-BUILDING _RROUTER-I-R @ _RROUTER.STATE !
    _RROUTER-I-ENTRIES @ _RROUTER-I-R @ _RROUTER.ENTRIES !
    _RROUTER-I-CAPACITY @ _RROUTER-I-R @ _RROUTER.ENTRY-CAPACITY !
    _RROUTER-I-ARENA @ _RROUTER-I-R @ _RROUTER.ARENA-A !
    _RROUTER-I-ARENA-U @ _RROUTER-I-R @ _RROUTER.ARENA-CAPACITY !
    RROUTER-S-OK ;

: _RROUTER-WIPE-BOUND-STORAGE  ( router -- )
    DUP _RROUTER.ENTRY-CAPACITY @ RROUTER-ENTRY-BYTES DUP IF
        >R DUP _RROUTER.ENTRIES @ R> 0 FILL
    ELSE
        DROP
    THEN
    DUP _RROUTER.ARENA-CAPACITY @ DUP IF
        >R DUP _RROUTER.ARENA-A @ R> 0 FILL
    ELSE
        DROP
    THEN
    DROP ;

: RROUTER-RESET  ( router -- status )
    DUP RROUTER-VALID? 0= IF DROP RROUTER-S-INVALID EXIT THEN
    DUP _RROUTER-WIPE-BOUND-STORAGE
    0 OVER _RROUTER.COUNT !
    0 OVER _RROUTER.ARENA-USED !
    RROUTER-STATE-BUILDING SWAP _RROUTER.STATE !
    RROUTER-S-OK ;

\ =====================================================================
\  Transactional route registration and sealing
\ =====================================================================

VARIABLE _RROUTER-SD-A
VARIABLE _RROUTER-SD-U
VARIABLE _RROUTER-SD-R

: _RROUTER-SOURCE-DISJOINT?  ( address length router -- flag )
    _RROUTER-SD-R ! _RROUTER-SD-U ! _RROUTER-SD-A !
    _RROUTER-SD-A @ _RROUTER-SD-U @
        _RROUTER-SD-R @ RROUTER-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _RROUTER-SD-A @ _RROUTER-SD-U @
        _RROUTER-SD-R @ _RROUTER.ENTRIES @
        _RROUTER-SD-R @ _RROUTER.ENTRY-CAPACITY @
            RROUTER-ENTRY-BYTES
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RROUTER-SD-A @ _RROUTER-SD-U @
        _RROUTER-SD-R @ _RROUTER.ARENA-A @
        _RROUTER-SD-R @ _RROUTER.ARENA-CAPACITY @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    -1 ;

VARIABLE _RROUTER-A-VERB-A
VARIABLE _RROUTER-A-VERB-U
VARIABLE _RROUTER-A-SELECTOR-A
VARIABLE _RROUTER-A-SELECTOR-U
VARIABLE _RROUTER-A-HANDLER-XT
VARIABLE _RROUTER-A-HANDLER-CONTEXT
VARIABLE _RROUTER-A-R
VARIABLE _RROUTER-A-E
VARIABLE _RROUTER-A-VERB-D
VARIABLE _RROUTER-A-SELECTOR-D
VARIABLE _RROUTER-A-NEW-USED

: _RROUTER-ADD-DUPLICATE?  ( -- flag )
    _RROUTER-A-R @ _RROUTER.COUNT @ 0 ?DO
        _RROUTER-A-VERB-A @ _RROUTER-A-VERB-U @
        I _RROUTER-A-R @ _RROUTER-ENTRY
        DUP _RROUTE.VERB-A @ SWAP _RROUTE.VERB-U @
        _RROUTER-SPAN= IF
            _RROUTER-A-SELECTOR-A @ _RROUTER-A-SELECTOR-U @
            I _RROUTER-A-R @ _RROUTER-ENTRY
            DUP _RROUTE.SELECTOR-A @ SWAP _RROUTE.SELECTOR-U @
            _RROUTER-SPAN= IF -1 UNLOOP EXIT THEN
        THEN
    LOOP
    0 ;

: _RROUTER-ADD-ROOM?  ( -- flag )
    _RROUTER-A-R @ _RROUTER.ARENA-CAPACITY @
        _RROUTER-A-R @ _RROUTER.ARENA-USED @ -
    _RROUTER-A-VERB-U @ OVER U> IF DROP 0 EXIT THEN
    _RROUTER-A-VERB-U @ -
    _RROUTER-A-SELECTOR-U @ U< 0= ;

: RROUTER-ADD
    ( verb-a verb-u selector-a selector-u )
    ( handler-xt handler-context router -- status )
    _RROUTER-A-R ! _RROUTER-A-HANDLER-CONTEXT !
    _RROUTER-A-HANDLER-XT ! _RROUTER-A-SELECTOR-U !
    _RROUTER-A-SELECTOR-A ! _RROUTER-A-VERB-U !
    _RROUTER-A-VERB-A !

    _RROUTER-A-R @ RROUTER-VALID? 0= IF
        RROUTER-S-INVALID EXIT
    THEN
    _RROUTER-A-R @ _RROUTER.STATE @
        RROUTER-STATE-BUILDING <> IF RROUTER-S-STATE EXIT THEN

    _RROUTER-A-VERB-A @ _RROUTER-A-VERB-U @
        _RROUTER-NONEMPTY-SPAN? 0= IF RROUTER-S-INVALID EXIT THEN
    _RROUTER-A-SELECTOR-A @ _RROUTER-A-SELECTOR-U @
        _RROUTER-NONEMPTY-SPAN? 0= IF RROUTER-S-INVALID EXIT THEN
    _RROUTER-A-VERB-A @ _RROUTER-A-VERB-U @ _RROUTER-A-R @
        _RROUTER-SOURCE-DISJOINT? 0= IF RROUTER-S-ALIAS EXIT THEN
    _RROUTER-A-SELECTOR-A @ _RROUTER-A-SELECTOR-U @ _RROUTER-A-R @
        _RROUTER-SOURCE-DISJOINT? 0= IF RROUTER-S-ALIAS EXIT THEN

    _RROUTER-A-VERB-A @ _RROUTER-A-VERB-U @
        UTF8-VALID? 0= IF RROUTER-S-UTF8 EXIT THEN
    _RROUTER-A-SELECTOR-A @ _RROUTER-A-SELECTOR-U @
        UTF8-VALID? 0= IF RROUTER-S-UTF8 EXIT THEN
    _RROUTER-A-VERB-A @ _RROUTER-A-VERB-U @
        _RROUTER-VERB-GRAMMAR? 0= IF RROUTER-S-GRAMMAR EXIT THEN
    _RROUTER-A-SELECTOR-A @ _RROUTER-A-SELECTOR-U @
        _RROUTER-SELECTOR-GRAMMAR? 0= IF RROUTER-S-GRAMMAR EXIT THEN
    _RROUTER-A-HANDLER-XT @ 0= IF RROUTER-S-INVALID EXIT THEN

    _RROUTER-ADD-DUPLICATE? IF RROUTER-S-DUPLICATE EXIT THEN
    _RROUTER-A-R @ _RROUTER.COUNT @
        _RROUTER-A-R @ _RROUTER.ENTRY-CAPACITY @ >= IF
        RROUTER-S-CAPACITY EXIT
    THEN
    _RROUTER-ADD-ROOM? 0= IF RROUTER-S-CAPACITY EXIT THEN

    \ Nothing below this point can fail.  Copy both strings before count is
    \ published; serialization guarantees no observer can see the transient
    \ packed bytes or partially initialized entry.
    _RROUTER-A-R @ _RROUTER.ARENA-A @
        _RROUTER-A-R @ _RROUTER.ARENA-USED @ +
        DUP _RROUTER-A-VERB-D !
    _RROUTER-A-VERB-U @ + DUP _RROUTER-A-SELECTOR-D !
    _RROUTER-A-SELECTOR-U @ + _RROUTER-A-R @ _RROUTER.ARENA-A @ -
        _RROUTER-A-NEW-USED !

    _RROUTER-A-VERB-A @ _RROUTER-A-VERB-D @
        _RROUTER-A-VERB-U @ MOVE
    _RROUTER-A-SELECTOR-A @ _RROUTER-A-SELECTOR-D @
        _RROUTER-A-SELECTOR-U @ MOVE

    _RROUTER-A-R @ _RROUTER.COUNT @ _RROUTER-A-R @ _RROUTER-ENTRY
        _RROUTER-A-E !
    _RROUTER-A-VERB-D @ _RROUTER-A-E @ _RROUTE.VERB-A !
    _RROUTER-A-VERB-U @ _RROUTER-A-E @ _RROUTE.VERB-U !
    _RROUTER-A-SELECTOR-D @ _RROUTER-A-E @ _RROUTE.SELECTOR-A !
    _RROUTER-A-SELECTOR-U @ _RROUTER-A-E @ _RROUTE.SELECTOR-U !
    _RROUTER-A-HANDLER-XT @ _RROUTER-A-E @ _RROUTE.HANDLER-XT !
    _RROUTER-A-HANDLER-CONTEXT @
        _RROUTER-A-E @ _RROUTE.HANDLER-CONTEXT !
    _RROUTER-A-NEW-USED @ _RROUTER-A-R @ _RROUTER.ARENA-USED !
    1 _RROUTER-A-R @ _RROUTER.COUNT +!
    RROUTER-S-OK ;

: RROUTER-SEAL  ( router -- status )
    DUP RROUTER-VALID? 0= IF DROP RROUTER-S-INVALID EXIT THEN
    DUP _RROUTER.STATE @ RROUTER-STATE-BUILDING <> IF
        DROP RROUTER-S-STATE EXIT
    THEN
    RROUTER-STATE-SEALED SWAP _RROUTER.STATE !
    RROUTER-S-OK ;

\ =====================================================================
\  Immutable exact lookup
\ =====================================================================

VARIABLE _RROUTER-M-VERB-A
VARIABLE _RROUTER-M-VERB-U
VARIABLE _RROUTER-M-SELECTOR-A
VARIABLE _RROUTER-M-SELECTOR-U
VARIABLE _RROUTER-M-R
VARIABLE _RROUTER-M-E

: RROUTER-MATCH
    ( verb-a verb-u selector-a selector-u router )
    ( -- handler-xt handler-context status )
    _RROUTER-M-R ! _RROUTER-M-SELECTOR-U !
    _RROUTER-M-SELECTOR-A ! _RROUTER-M-VERB-U !
    _RROUTER-M-VERB-A !

    _RROUTER-M-R @ RROUTER-VALID? 0= IF
        0 0 RROUTER-S-INVALID EXIT
    THEN
    _RROUTER-M-R @ _RROUTER.STATE @ RROUTER-STATE-SEALED <> IF
        0 0 RROUTER-S-STATE EXIT
    THEN
    _RROUTER-M-VERB-A @ _RROUTER-M-VERB-U @
        _RROUTER-NONEMPTY-SPAN? 0= IF 0 0 RROUTER-S-INVALID EXIT THEN
    _RROUTER-M-SELECTOR-A @ _RROUTER-M-SELECTOR-U @
        _RROUTER-NONEMPTY-SPAN? 0= IF 0 0 RROUTER-S-INVALID EXIT THEN
    _RROUTER-M-VERB-A @ _RROUTER-M-VERB-U @
        UTF8-VALID? 0= IF 0 0 RROUTER-S-UTF8 EXIT THEN
    _RROUTER-M-SELECTOR-A @ _RROUTER-M-SELECTOR-U @
        UTF8-VALID? 0= IF 0 0 RROUTER-S-UTF8 EXIT THEN
    _RROUTER-M-VERB-A @ _RROUTER-M-VERB-U @
        _RROUTER-VERB-GRAMMAR? 0= IF 0 0 RROUTER-S-GRAMMAR EXIT THEN
    _RROUTER-M-SELECTOR-A @ _RROUTER-M-SELECTOR-U @
        _RROUTER-SELECTOR-GRAMMAR? 0= IF
        0 0 RROUTER-S-GRAMMAR EXIT
    THEN

    _RROUTER-M-R @ _RROUTER.COUNT @ 0 ?DO
        I _RROUTER-M-R @ _RROUTER-ENTRY _RROUTER-M-E !
        _RROUTER-M-VERB-A @ _RROUTER-M-VERB-U @
        _RROUTER-M-E @
            DUP _RROUTE.VERB-A @ SWAP _RROUTE.VERB-U @
        _RROUTER-SPAN= IF
            _RROUTER-M-SELECTOR-A @ _RROUTER-M-SELECTOR-U @
            _RROUTER-M-E @
                DUP _RROUTE.SELECTOR-A @ SWAP _RROUTE.SELECTOR-U @
            _RROUTER-SPAN= IF
                _RROUTER-M-E @ _RROUTE.HANDLER-XT @
                _RROUTER-M-E @ _RROUTE.HANDLER-CONTEXT @
                RROUTER-S-OK UNLOOP EXIT
            THEN
        THEN
    LOOP
    0 0 RROUTER-S-NOT-FOUND ;

\ =====================================================================
\  Recovering finalization
\ =====================================================================

: _RROUTER-CLEAR-SCRATCH  ( -- )
    0 _RROUTER-GRAMMAR-A !
    0 _RROUTER-GRAMMAR-U !
    0 _RROUTER-GRAMMAR-PREV-SPACE !
    0 _RROUTER-EV-R !
    0 _RROUTER-EV-E !
    0 _RROUTER-EV-OFFSET !
    0 _RROUTER-EV-U !
    0 _RROUTER-V-R !
    0 _RROUTER-V-ENTRY-BYTES !
    0 _RROUTER-O-A !
    0 _RROUTER-O-U !
    0 _RROUTER-O-R !
    0 _RROUTER-I-ENTRIES !
    0 _RROUTER-I-CAPACITY !
    0 _RROUTER-I-ENTRY-BYTES !
    0 _RROUTER-I-ARENA !
    0 _RROUTER-I-ARENA-U !
    0 _RROUTER-I-R !
    0 _RROUTER-SD-A !
    0 _RROUTER-SD-U !
    0 _RROUTER-SD-R !
    0 _RROUTER-A-VERB-A !
    0 _RROUTER-A-VERB-U !
    0 _RROUTER-A-SELECTOR-A !
    0 _RROUTER-A-SELECTOR-U !
    0 _RROUTER-A-HANDLER-XT !
    0 _RROUTER-A-HANDLER-CONTEXT !
    0 _RROUTER-A-R !
    0 _RROUTER-A-E !
    0 _RROUTER-A-VERB-D !
    0 _RROUTER-A-SELECTOR-D !
    0 _RROUTER-A-NEW-USED !
    0 _RROUTER-M-VERB-A !
    0 _RROUTER-M-VERB-U !
    0 _RROUTER-M-SELECTOR-A !
    0 _RROUTER-M-SELECTOR-U !
    0 _RROUTER-M-R !
    0 _RROUTER-M-E ! ;

\ FINI deliberately uses only binding geometry.  It can therefore erase a
\ live owner after route bytes, handler cells, count, or used-byte evidence is
\ damaged.  If magic/ABI/state or a binding address/capacity was mutated, no
\ internal fact remains that can authorize a write through that geometry.
: RROUTER-FINI  ( router -- status )
    DUP RROUTER-BINDING-VALID? 0= IF
        DROP _RROUTER-CLEAR-SCRATCH RROUTER-S-INVALID EXIT
    THEN
    DUP _RROUTER-WIPE-BOUND-STORAGE
    RROUTER-SIZE 0 FILL
    _RROUTER-CLEAR-SCRATCH
    RROUTER-S-OK ;
