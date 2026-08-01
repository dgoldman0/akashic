\ =====================================================================
\  subscription.f - Caller-owned Rabbit subscription and replay state
\ =====================================================================
\  This product-neutral layer composes with one RABBIT-CLIENT.  The caller
\  supplies a fixed-stride metadata array plus one target slot and one event
\  staging slot per entry.  Targets are copied at registration, and every
\  registration names a nonzero application Lane; control Lane 0 cannot carry
\  SUBSCRIBE/EVENT state.  Event bodies are copied completely before an
\  application callback sees them and are wiped when the enclosing
\  POLL/DISPATCH call returns; no parser view escapes the client callback.
\
\  Lane Seq and Event-Seq are deliberately independent.  Lane ordering and
\  ACK state stay in the connection/session.  Each subscription records the
\  last application Event-Seq committed through the client.  A rebind emits
\  that exact nonzero value as Since; zero omits Since.  Disconnect clears the
\  old lane-delivery evidence and bind handles but preserves target, lane,
\  generation, callback, and Event-Seq cursor.
\
\  SUBSCRIBE is built in a caller-supplied EMPTY RMSGB builder and correlated
\  by RABBIT-CLIENT-REQUEST.  A terminal response becomes BIND-RESULT.  This
\  module does not invent a success code: the caller inspects the ordinary
\  client operation/result and explicitly resolves it accepted or refused.
\
\  Per-entry event callback contract:
\
\    ( entry generation lane-seq event-seq delivery
\      target-a target-u event-a event-u context -- decision )
\
\  delivery is RSUB-DELIVERY-NEW or RSUB-DELIVERY-DUPLICATE.  decision is
\  RSUB-DISPATCH-COMMIT or RSUB-DISPATCH-DROP.  DUPLICATE is always offered
\  synchronously so an application can verify its digest/idempotency evidence;
\  it never advances the cursor.  This remains true at the maximum cursor so a
\  lost final transport ACK is recoverable.  NEW advances the Event-Seq cursor
\  only after the callback accepts it and the enclosing client commit succeeds.
\  A gap or oversized body calls no application handler, copies no prefix, and
\  returns explicit evidence.  NEXT-EVENT@ reports cursor exhaustion directly.
\  The entry handle plus target and event slices supplied to the callback are
\  read-only.  COMMIT accepts the complete copied event; DROP leaves both
\  Event-Seq and Lane Seq evidence unchanged.  Throwing or returning any other
\  value is reported as CALLBACK and drops an EVENT.  The event slot is wiped
\  before the enclosing wrapper returns in every case.
\
\  Optional fallback callbacks passed to POLL/DISPATCH use the client's exact
\  borrowed-view contract:
\
\    ( frame kind lane seq expected disposition context -- client-decision )
\
\  They are for nonmatching EVENTs, extension traffic, and optional response
\  inspection.  They are synchronous and must not retain frame slices.  With
\  xt=0, response frames commit so the client can publish correlated results;
\  unmatched EVENTs and extensions drop.  A supplied fallback's DROP, throw,
\  or invalid decision on a correlated response retains the client's existing
\  fatal-response-rejection effect and therefore cancels that client.
\
\  POLL and DISPATCH mirror the client's tagged four-cell result:
\
\    ( fallback-xt fallback-context owner
\      -- item subject generation subscription-status )
\
\  BIND and EVENT identify a subscription entry handle.  CLIENT-OP preserves
\  an unrelated terminal client operation and its client generation so a
\  shared client never makes that result unreachable.  OTHER and NONE use a
\  zero subject.  POLL may pump transport progress; DISPATCH only consumes an
\  already-held inbound item.
\  A BIND operation returned by BIND remains owned by this module until
\  BIND-RESOLVE; callers inspect it but do not cancel or release it directly.
\
\  DISCONNECT cancels the entire attached client, releases terminal bind
\  operations where possible, and converts every live entry to NEEDS-REBIND.
\  ATTACH accepts a fresh READY/ACTIVE disjoint client.  The caller then binds
\  retained entry handles again; each request emits Since from the preserved
\  committed Event-Seq cursor.  FINI requires the detached state and wipes the
\  complete metadata, target, event, and owner allocations.
\
\  All variable-size storage is caller-owned; there is no allocation and no
\  fixed product subscription count.  Private VARIABLE cells are synchronous
\  scratch, including read-only validation and dispatch, so calls outside one
\  callback chain must be serialized.  Callbacks may inspect stable evidence,
\  but recursive dispatch and registration/lifecycle mutation are refused.
\  Handler/context execution tokens remain borrowed and stable until entry
\  release or finalization.
\ =====================================================================

PROVIDED akashic-rabbit-subscription

REQUIRE client.f
REQUIRE ../../utils/memory-span.f
REQUIRE ../../text/utf8.f

\ =====================================================================
\  Public status, owner state, entry state, item, and delivery vocabulary
\ =====================================================================

0  CONSTANT RSUB-S-OK
1  CONSTANT RSUB-S-INVALID
2  CONSTANT RSUB-S-STATE
3  CONSTANT RSUB-S-CAPACITY
4  CONSTANT RSUB-S-ALIAS
5  CONSTANT RSUB-S-NOT-FOUND
6  CONSTANT RSUB-S-DUPLICATE
7  CONSTANT RSUB-S-CLIENT
8  CONSTANT RSUB-S-BUILDER
9  CONSTANT RSUB-S-MESSAGE
10 CONSTANT RSUB-S-PENDING
11 CONSTANT RSUB-S-BIND-RESULT
12 CONSTANT RSUB-S-EVENT
13 CONSTANT RSUB-S-EVENT-DUPLICATE
14 CONSTANT RSUB-S-GAP
15 CONSTANT RSUB-S-OVERFLOW
16 CONSTANT RSUB-S-DROPPED
17 CONSTANT RSUB-S-CALLBACK
18 CONSTANT RSUB-S-DISCONNECTED
19 CONSTANT RSUB-S-PROTOCOL
20 CONSTANT RSUB-S-OTHER

1 CONSTANT RSUB-ST-ATTACHED
2 CONSTANT RSUB-ST-DETACHED

0 CONSTANT RSUB-ENTRY-EMPTY
1 CONSTANT RSUB-ENTRY-CONFIGURED
2 CONSTANT RSUB-ENTRY-BINDING
3 CONSTANT RSUB-ENTRY-BIND-RESULT
4 CONSTANT RSUB-ENTRY-BOUND
5 CONSTANT RSUB-ENTRY-NEEDS-REBIND

0 CONSTANT RSUB-ITEM-NONE
1 CONSTANT RSUB-ITEM-BIND
2 CONSTANT RSUB-ITEM-EVENT
3 CONSTANT RSUB-ITEM-OTHER
4 CONSTANT RSUB-ITEM-CLIENT-OP

0 CONSTANT RSUB-DELIVERY-NONE
1 CONSTANT RSUB-DELIVERY-NEW
2 CONSTANT RSUB-DELIVERY-DUPLICATE
3 CONSTANT RSUB-DELIVERY-GAP
4 CONSTANT RSUB-DELIVERY-CAPACITY
5 CONSTANT RSUB-DELIVERY-DROPPED
6 CONSTANT RSUB-DELIVERY-CALLBACK
7 CONSTANT RSUB-DELIVERY-PROTOCOL

0 CONSTANT RSUB-DISPATCH-COMMIT
1 CONSTANT RSUB-DISPATCH-DROP

\ One module-global guard protects the synchronous callback adapter from
\ recursive polling and from lifecycle mutation while an RX loan is live.
VARIABLE _RSUBP-BUSY

: RSUB-STATUS-VALID?  ( status -- flag )
    DUP RSUB-S-OK >= SWAP RSUB-S-OTHER <= AND ;

: RSUB-STATE-VALID?  ( state -- flag )
    DUP RSUB-ST-ATTACHED = SWAP RSUB-ST-DETACHED = OR ;

: RSUB-ENTRY-STATE-VALID?  ( state -- flag )
    DUP RSUB-ENTRY-EMPTY >= SWAP RSUB-ENTRY-NEEDS-REBIND <= AND ;

: RSUB-DELIVERY-VALID?  ( delivery -- flag )
    DUP RSUB-DELIVERY-NONE >= SWAP RSUB-DELIVERY-PROTOCOL <= AND ;

: RSUB-DISPATCH-VALID?  ( decision -- flag )
    DUP RSUB-DISPATCH-COMMIT = SWAP RSUB-DISPATCH-DROP = OR ;

\ =====================================================================
\  Caller-owned entry metadata
\ =====================================================================

  0 CONSTANT _RSUBE-STATE
  8 CONSTANT _RSUBE-GENERATION
 16 CONSTANT _RSUBE-LANE
 24 CONSTANT _RSUBE-TARGET-U
 32 CONSTANT _RSUBE-CURSOR
 40 CONSTANT _RSUBE-LAST-LANE-SEQ
 48 CONSTANT _RSUBE-EVENT-U
 56 CONSTANT _RSUBE-EVENT-REQUIRED
 64 CONSTANT _RSUBE-BIND-OP
 72 CONSTANT _RSUBE-BIND-GENERATION
 80 CONSTANT _RSUBE-CALLBACK-XT
 88 CONSTANT _RSUBE-CALLBACK-CONTEXT
 96 CONSTANT _RSUBE-LAST-DELIVERY
104 CONSTANT _RSUBE-CLIENT-STATUS
112 CONSTANT _RSUBE-LAST-OBSERVED-EVENT-SEQ
120 CONSTANT _RSUBE-FLAGS
128 CONSTANT RABBIT-SUBSCRIPTION-ENTRY-SIZE

: RSUBE.STATE             ( entry -- field ) _RSUBE-STATE + ;
: RSUBE.GENERATION        ( entry -- field ) _RSUBE-GENERATION + ;
: RSUBE.LANE              ( entry -- field ) _RSUBE-LANE + ;
: RSUBE.TARGET-U          ( entry -- field ) _RSUBE-TARGET-U + ;
: RSUBE.CURSOR            ( entry -- field ) _RSUBE-CURSOR + ;
: RSUBE.LAST-LANE-SEQ     ( entry -- field ) _RSUBE-LAST-LANE-SEQ + ;
: RSUBE.EVENT-U           ( entry -- field ) _RSUBE-EVENT-U + ;
: RSUBE.EVENT-REQUIRED    ( entry -- field ) _RSUBE-EVENT-REQUIRED + ;
: RSUBE.BIND-OP           ( entry -- field ) _RSUBE-BIND-OP + ;
: RSUBE.BIND-GENERATION   ( entry -- field ) _RSUBE-BIND-GENERATION + ;
: RSUBE.CALLBACK-XT       ( entry -- field ) _RSUBE-CALLBACK-XT + ;
: RSUBE.CALLBACK-CONTEXT  ( entry -- field ) _RSUBE-CALLBACK-CONTEXT + ;
: RSUBE.LAST-DELIVERY     ( entry -- field ) _RSUBE-LAST-DELIVERY + ;
: RSUBE.CLIENT-STATUS     ( entry -- field ) _RSUBE-CLIENT-STATUS + ;
: RSUBE.LAST-OBSERVED-EVENT-SEQ  ( entry -- field )
    _RSUBE-LAST-OBSERVED-EVENT-SEQ + ;
: RSUBE.FLAGS             ( entry -- field ) _RSUBE-FLAGS + ;

-1 1 RSHIFT CONSTANT _RSUB-CELL-MAX
_RSUB-CELL-MAX RABBIT-SUBSCRIPTION-ENTRY-SIZE /
    CONSTANT _RSUB-CAPACITY-MAX

: RABBIT-SUBSCRIPTION-CAPACITY-VALID?  ( capacity -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    _RSUB-CAPACITY-MAX U> 0= ;

: RABBIT-SUBSCRIPTION-ENTRY-BYTES  ( capacity -- bytes|0 )
    DUP RABBIT-SUBSCRIPTION-CAPACITY-VALID? 0= IF DROP 0 EXIT THEN
    RABBIT-SUBSCRIPTION-ENTRY-SIZE * ;

\ =====================================================================
\  Opaque owner descriptor
\ =====================================================================

0x5253554253435231 CONSTANT _RSUB-MAGIC-VALUE  \ "RSUBSCR1"
1                  CONSTANT _RSUB-ABI-VERSION

  0 CONSTANT _RSUB-MAGIC
  8 CONSTANT _RSUB-ABI
 16 CONSTANT _RSUB-BYTES
 24 CONSTANT _RSUB-STATE
 32 CONSTANT _RSUB-LAST-STATUS
 40 CONSTANT _RSUB-DETAIL
 48 CONSTANT _RSUB-CLIENT
 56 CONSTANT _RSUB-ENTRIES
 64 CONSTANT _RSUB-CAPACITY
 72 CONSTANT _RSUB-TARGET-A
 80 CONSTANT _RSUB-TARGET-SLOT-BYTES
 88 CONSTANT _RSUB-EVENT-A
 96 CONSTANT _RSUB-EVENT-SLOT-BYTES
104 CONSTANT _RSUB-COUNT
112 CONSTANT _RSUB-NEXT-GENERATION
120 CONSTANT _RSUB-FLAGS
128 CONSTANT RABBIT-SUBSCRIPTIONS-SIZE

: RSUB.MAGIC             ( owner -- field ) _RSUB-MAGIC + ;
: RSUB.ABI               ( owner -- field ) _RSUB-ABI + ;
: RSUB.BYTES             ( owner -- field ) _RSUB-BYTES + ;
: RSUB.STATE             ( owner -- field ) _RSUB-STATE + ;
: RSUB.LAST-STATUS       ( owner -- field ) _RSUB-LAST-STATUS + ;
: RSUB.DETAIL            ( owner -- field ) _RSUB-DETAIL + ;
: RSUB.CLIENT            ( owner -- field ) _RSUB-CLIENT + ;
: RSUB.ENTRIES           ( owner -- field ) _RSUB-ENTRIES + ;
: RSUB.CAPACITY          ( owner -- field ) _RSUB-CAPACITY + ;
: RSUB.TARGET-A          ( owner -- field ) _RSUB-TARGET-A + ;
: RSUB.TARGET-SLOT-BYTES ( owner -- field ) _RSUB-TARGET-SLOT-BYTES + ;
: RSUB.EVENT-A           ( owner -- field ) _RSUB-EVENT-A + ;
: RSUB.EVENT-SLOT-BYTES  ( owner -- field ) _RSUB-EVENT-SLOT-BYTES + ;
: RSUB.COUNT             ( owner -- field ) _RSUB-COUNT + ;
: RSUB.NEXT-GENERATION   ( owner -- field ) _RSUB-NEXT-GENERATION + ;
: RSUB.FLAGS             ( owner -- field ) _RSUB-FLAGS + ;

: _RSUB-ENTRY@  ( index owner -- entry )
    RSUB.ENTRIES @ SWAP RABBIT-SUBSCRIPTION-ENTRY-SIZE * + ;

: _RSUB-TARGET@  ( index owner -- address )
    DUP RSUB.TARGET-SLOT-BYTES @ ROT * SWAP RSUB.TARGET-A @ + ;

: _RSUB-EVENT@  ( index owner -- address )
    DUP RSUB.EVENT-SLOT-BYTES @ ROT * SWAP RSUB.EVENT-A @ + ;

\ =====================================================================
\  Checked geometry and client-graph disjointness
\ =====================================================================

: _RSUB-CELL-ALIGNED?  ( address -- flag ) 7 AND 0= ;

: _RSUB-MUL?  ( count stride -- bytes flag )
    >R
    DUP 0< IF DROP R> DROP 0 0 EXIT THEN
    R@ 0< IF DROP R> DROP 0 0 EXIT THEN
    R@ 0= IF DROP R> DROP 0 -1 EXIT THEN
    DUP _RSUB-CELL-MAX R@ / U> IF DROP R> DROP 0 0 EXIT THEN
    R> * -1 ;

VARIABLE _RSUBCG-C

: _RSUB-SPAN-HITS-CLIENT?  ( address bytes client -- flag )
    RABBIT-CLIENT-OWNED-SPAN-OVERLAP? ;

VARIABLE _RSUBG-O
VARIABLE _RSUBG-EU
VARIABLE _RSUBG-TU
VARIABLE _RSUBG-VU

: _RSUB-OWN-GEOMETRY?  ( owner -- flag )
    DUP _RSUBG-O ! RSUB.CAPACITY @ DUP
        RABBIT-SUBSCRIPTION-CAPACITY-VALID? 0= IF DROP 0 EXIT THEN
    DUP RABBIT-SUBSCRIPTION-ENTRY-BYTES _RSUBG-EU !
    _RSUBG-O @ RSUB.TARGET-SLOT-BYTES @ DUP 0< IF
        2DROP 0 EXIT
    THEN
    _RSUB-MUL? 0= IF DROP 0 EXIT THEN _RSUBG-TU !
    _RSUBG-O @ RSUB.CAPACITY @
        _RSUBG-O @ RSUB.EVENT-SLOT-BYTES @ DUP 0< IF
        2DROP 0 EXIT
    THEN
    _RSUB-MUL? 0= IF DROP 0 EXIT THEN _RSUBG-VU !

    _RSUBG-O @ RSUB.CAPACITY @ 0= IF
        _RSUBG-O @ RSUB.ENTRIES @ 0=
        _RSUBG-O @ RSUB.TARGET-A @ 0= AND
        _RSUBG-O @ RSUB.TARGET-SLOT-BYTES @ 0= AND
        _RSUBG-O @ RSUB.EVENT-A @ 0= AND
        _RSUBG-O @ RSUB.EVENT-SLOT-BYTES @ 0= AND EXIT
    THEN
    _RSUBG-O @ RSUB.ENTRIES @ DUP 0= IF DROP 0 EXIT THEN
    DUP _RSUB-CELL-ALIGNED? 0= IF DROP 0 EXIT THEN
    _RSUBG-EU @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RSUBG-O @ RSUB.TARGET-SLOT-BYTES @ 0> 0= IF 0 EXIT THEN
    _RSUBG-O @ RSUB.TARGET-A @ DUP 0= IF DROP 0 EXIT THEN
    _RSUBG-TU @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    _RSUBG-O @ RSUB.EVENT-SLOT-BYTES @ IF
        _RSUBG-O @ RSUB.EVENT-A @ DUP 0= IF DROP 0 EXIT THEN
        _RSUBG-VU @ MSPAN-NONWRAPPING? 0= IF 0 EXIT THEN
    ELSE
        _RSUBG-O @ RSUB.EVENT-A @ IF 0 EXIT THEN
    THEN
    _RSUBG-O @ RABBIT-SUBSCRIPTIONS-SIZE
        _RSUBG-O @ RSUB.ENTRIES @ _RSUBG-EU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBG-O @ RABBIT-SUBSCRIPTIONS-SIZE
        _RSUBG-O @ RSUB.TARGET-A @ _RSUBG-TU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBG-O @ RABBIT-SUBSCRIPTIONS-SIZE
        _RSUBG-O @ RSUB.EVENT-A @ _RSUBG-VU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBG-O @ RSUB.ENTRIES @ _RSUBG-EU @
        _RSUBG-O @ RSUB.TARGET-A @ _RSUBG-TU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBG-O @ RSUB.ENTRIES @ _RSUBG-EU @
        _RSUBG-O @ RSUB.EVENT-A @ _RSUBG-VU @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBG-O @ RSUB.TARGET-A @ _RSUBG-TU @
        _RSUBG-O @ RSUB.EVENT-A @ _RSUBG-VU @
        MSPAN-OVERLAP? 0= ;

: _RSUB-CLIENT-GEOMETRY-DISJOINT?  ( client owner -- flag )
    _RSUBG-O ! _RSUBCG-C !
    _RSUBG-O @ RABBIT-SUBSCRIPTIONS-SIZE _RSUBCG-C @
        _RSUB-SPAN-HITS-CLIENT? IF 0 EXIT THEN
    _RSUBG-O @ RSUB.ENTRIES @ _RSUBG-EU @ _RSUBCG-C @
        _RSUB-SPAN-HITS-CLIENT? IF 0 EXIT THEN
    _RSUBG-O @ RSUB.TARGET-A @ _RSUBG-TU @ _RSUBCG-C @
        _RSUB-SPAN-HITS-CLIENT? IF 0 EXIT THEN
    _RSUBG-O @ RSUB.EVENT-A @ _RSUBG-VU @ _RSUBCG-C @
        _RSUB-SPAN-HITS-CLIENT? 0= ;

\ =====================================================================
\  Selector grammar and semantic entry validation
\ =====================================================================

VARIABLE _RSUBSG-A
VARIABLE _RSUBSG-U
VARIABLE _RSUBSG-PREV-SPACE

: _RSUB-SELECTOR-GRAMMAR?  ( address length -- flag )
    _RSUBSG-U ! _RSUBSG-A !
    _RSUBSG-U @ 0= IF 0 EXIT THEN
    0 _RSUBSG-PREV-SPACE !
    _RSUBSG-U @ 0 ?DO
        _RSUBSG-A @ I + C@
        DUP 32 < OVER 127 = OR IF DROP 0 UNLOOP EXIT THEN
        DUP 32 = IF
            DROP
            I 0= IF 0 UNLOOP EXIT THEN
            I _RSUBSG-U @ 1- = IF 0 UNLOOP EXIT THEN
            _RSUBSG-PREV-SPACE @ IF 0 UNLOOP EXIT THEN
            -1 _RSUBSG-PREV-SPACE !
        ELSE
            DROP 0 _RSUBSG-PREV-SPACE !
        THEN
    LOOP
    -1 ;

: _RSUB-APP-LANE?  ( lane -- flag )
    DUP 0> SWAP RABBIT-LANE-MAX U> 0= AND ;

VARIABLE _RSUBV-O
VARIABLE _RSUBV-E
VARIABLE _RSUBV-I
VARIABLE _RSUBV-N
VARIABLE _RSUBV-LIVE

VARIABLE _RSUBV-OPSTATE
VARIABLE _RSUBV-OPVALUE
VARIABLE _RSUBV-OPSTATUS

: _RSUB-BIND-OP-VALID?  ( entry owner -- flag )
    _RSUBV-O ! _RSUBV-E !
    _RSUBV-E @ RSUBE.BIND-OP @
        _RSUBV-E @ RSUBE.BIND-GENERATION @
        _RSUBV-O @ RSUB.CLIENT @ RABBIT-CLIENT-OP-MATCH?
        _RSUBV-OPSTATUS !
    _RSUBV-OPSTATUS @ IF DROP 0 EXIT THEN
    0= IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.BIND-OP @ _RSUBV-O @ RSUB.CLIENT @
        RABBIT-CLIENT-OP-KIND@
        _RSUBV-OPSTATUS ! _RSUBV-OPVALUE !
    _RSUBV-OPSTATUS @ IF 0 EXIT THEN
    _RSUBV-OPVALUE @ RMSG-KIND-SUBSCRIBE <> IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.BIND-OP @ _RSUBV-O @ RSUB.CLIENT @
        RABBIT-CLIENT-OP-LANE@
        _RSUBV-OPSTATUS ! _RSUBV-OPVALUE !
    _RSUBV-OPSTATUS @ IF 0 EXIT THEN
    _RSUBV-OPVALUE @ _RSUBV-E @ RSUBE.LANE @ <> IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.BIND-OP @ _RSUBV-O @ RSUB.CLIENT @
        RABBIT-CLIENT-OP-STATE@
        _RSUBV-OPSTATUS ! _RSUBV-OPSTATE !
    _RSUBV-OPSTATUS @ IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.STATE @ RSUB-ENTRY-BINDING = IF
        _RSUBV-OPSTATE @ RCLIENT-OP-PENDING = EXIT
    THEN
    _RSUBV-OPSTATE @ DUP RCLIENT-OP-COMPLETE =
    OVER RCLIENT-OP-CANCELLED = OR
    SWAP RCLIENT-OP-FAILED = OR ;

: _RSUB-ENTRY-ZERO?  ( entry -- flag )
    RABBIT-SUBSCRIPTION-ENTRY-SIZE 0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _RSUB-ENTRY-VALID?  ( index owner -- flag )
    _RSUBV-O ! _RSUBV-I !
    _RSUBV-I @ _RSUBV-O @ _RSUB-ENTRY@ DUP _RSUBV-E !
    RSUBE.STATE @ DUP RSUB-ENTRY-STATE-VALID? 0= IF DROP 0 EXIT THEN
    RSUB-ENTRY-EMPTY = IF _RSUBV-E @ _RSUB-ENTRY-ZERO? EXIT THEN
    _RSUBV-E @ RSUBE.GENERATION @ 0= IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.LANE @ _RSUB-APP-LANE? 0= IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.TARGET-U @ DUP 0> 0= IF DROP 0 EXIT THEN
    _RSUBV-O @ RSUB.TARGET-SLOT-BYTES @ U> IF 0 EXIT THEN
    _RSUBV-I @ _RSUBV-O @ _RSUB-TARGET@
        _RSUBV-E @ RSUBE.TARGET-U @ 2DUP UTF8-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    _RSUB-SELECTOR-GRAMMAR? 0= IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.EVENT-U @ IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.EVENT-REQUIRED @ 0< IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.CALLBACK-XT @ 0= IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.LAST-DELIVERY @ RSUB-DELIVERY-VALID? 0= IF
        0 EXIT
    THEN
    _RSUBV-E @ RSUBE.CLIENT-STATUS @ RCLIENT-STATUS-VALID? 0= IF
        0 EXIT
    THEN
    _RSUBV-E @ RSUBE.FLAGS @ IF 0 EXIT THEN
    _RSUBV-E @ RSUBE.STATE @ DUP RSUB-ENTRY-BINDING =
    SWAP RSUB-ENTRY-BIND-RESULT = OR IF
        _RSUBV-O @ RSUB.STATE @ RSUB-ST-ATTACHED <> IF 0 EXIT THEN
        _RSUBV-E @ RSUBE.BIND-OP @ DUP 0= IF DROP 0 EXIT THEN
        DROP _RSUBV-E @ _RSUBV-O @ _RSUB-BIND-OP-VALID? 0= IF
            0 EXIT
        THEN
    ELSE
        _RSUBV-E @ RSUBE.BIND-OP @
        _RSUBV-E @ RSUBE.BIND-GENERATION @ OR IF 0 EXIT THEN
    THEN
    _RSUBV-O @ RSUB.STATE @ RSUB-ST-DETACHED = IF
        _RSUBV-E @ RSUBE.STATE @ RSUB-ENTRY-NEEDS-REBIND <> IF
            0 EXIT
        THEN
    THEN
    -1 ;

: RABBIT-SUBSCRIPTIONS-VALID?  ( owner -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _RSUB-CELL-ALIGNED? 0= IF DROP 0 EXIT THEN
    DUP RABBIT-SUBSCRIPTIONS-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    DUP _RSUBV-O !
    DUP RSUB.MAGIC @ _RSUB-MAGIC-VALUE <> IF DROP 0 EXIT THEN
    DUP RSUB.ABI @ _RSUB-ABI-VERSION <> IF DROP 0 EXIT THEN
    DUP RSUB.BYTES @ RABBIT-SUBSCRIPTIONS-SIZE <> IF DROP 0 EXIT THEN
    DUP RSUB.STATE @ RSUB-STATE-VALID? 0= IF DROP 0 EXIT THEN
    DUP RSUB.LAST-STATUS @ RSUB-STATUS-VALID? 0= IF DROP 0 EXIT THEN
    DUP RSUB.NEXT-GENERATION @ 0= IF DROP 0 EXIT THEN
    DUP RSUB.FLAGS @ IF DROP 0 EXIT THEN
    DUP _RSUB-OWN-GEOMETRY? 0= IF DROP 0 EXIT THEN
    DUP RSUB.STATE @ RSUB-ST-ATTACHED = IF
        DUP RSUB.CLIENT @ DUP RABBIT-CLIENT-VALID? 0= IF
            2DROP 0 EXIT
        THEN
        OVER _RSUB-CLIENT-GEOMETRY-DISJOINT? 0= IF DROP 0 EXIT THEN
    ELSE
        DUP RSUB.CLIENT @ IF DROP 0 EXIT THEN
    THEN
    DUP RSUB.COUNT @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER RSUB.CAPACITY @ U> IF DROP 0 EXIT THEN
    0 _RSUBV-N !
    DUP RSUB.CAPACITY @ 0 ?DO
        I OVER _RSUB-ENTRY-VALID? 0= IF DROP 0 UNLOOP EXIT THEN
        I OVER _RSUB-ENTRY@ RSUBE.STATE @ RSUB-ENTRY-EMPTY <> IF
            1 _RSUBV-N +!
        THEN
    LOOP
    RSUB.COUNT @ _RSUBV-N @ = ;

\ =====================================================================
\  Initialization and basic evidence
\ =====================================================================

VARIABLE _RSUBI-ENTRIES
VARIABLE _RSUBI-CAP
VARIABLE _RSUBI-TA
VARIABLE _RSUBI-TS
VARIABLE _RSUBI-EA
VARIABLE _RSUBI-ES
VARIABLE _RSUBI-C
VARIABLE _RSUBI-O
VARIABLE _RSUBI-EU
VARIABLE _RSUBI-TU
VARIABLE _RSUBI-VU
VARIABLE _RSUBI-CS
VARIABLE _RSUBI-RS

: RABBIT-SUBSCRIPTIONS-INIT
  ( entries capacity target-a target-slot-bytes event-a event-slot-bytes )
  ( client owner -- status )
    _RSUBP-BUSY @ IF 2DROP 2DROP 2DROP 2DROP RSUB-S-STATE EXIT THEN
    _RSUBI-O ! _RSUBI-C ! _RSUBI-ES ! _RSUBI-EA !
    _RSUBI-TS ! _RSUBI-TA ! _RSUBI-CAP ! _RSUBI-ENTRIES !
    _RSUBI-O @ 0= IF RSUB-S-INVALID EXIT THEN
    _RSUBI-O @ _RSUB-CELL-ALIGNED? 0= IF RSUB-S-INVALID EXIT THEN
    _RSUBI-O @ RABBIT-SUBSCRIPTIONS-SIZE MSPAN-NONWRAPPING? 0= IF
        RSUB-S-INVALID EXIT
    THEN
    _RSUBI-O @ RSUB.MAGIC @ _RSUB-MAGIC-VALUE = IF RSUB-S-STATE EXIT THEN
    _RSUBI-C @ RABBIT-CLIENT-VALID? 0= IF RSUB-S-CLIENT EXIT THEN
    _RSUBI-C @ RABBIT-CLIENT-STATE@ _RSUBI-RS ! _RSUBI-CS !
    _RSUBI-RS @ IF RSUB-S-CLIENT EXIT THEN
    _RSUBI-CS @ DUP RCLIENT-ST-READY =
    SWAP RCLIENT-ST-ACTIVE = OR 0= IF RSUB-S-CLIENT EXIT THEN
    _RSUBI-CAP @ RABBIT-SUBSCRIPTION-CAPACITY-VALID? 0= IF
        RSUB-S-INVALID EXIT
    THEN
    _RSUBI-TS @ 0< _RSUBI-ES @ 0< OR IF RSUB-S-INVALID EXIT THEN
    _RSUBI-CAP @ RABBIT-SUBSCRIPTION-ENTRY-BYTES _RSUBI-EU !
    _RSUBI-CAP @ _RSUBI-TS @ _RSUB-MUL? 0= IF
        DROP RSUB-S-INVALID EXIT
    THEN _RSUBI-TU !
    _RSUBI-CAP @ _RSUBI-ES @ _RSUB-MUL? 0= IF
        DROP RSUB-S-INVALID EXIT
    THEN _RSUBI-VU !
    _RSUBI-CAP @ 0= IF
        _RSUBI-ENTRIES @ _RSUBI-TA @ OR _RSUBI-EA @ OR
        _RSUBI-TS @ OR _RSUBI-ES @ OR IF RSUB-S-INVALID EXIT THEN
    ELSE
        _RSUBI-ENTRIES @ 0= IF RSUB-S-INVALID EXIT THEN
        _RSUBI-ENTRIES @ _RSUB-CELL-ALIGNED? 0= IF RSUB-S-INVALID EXIT THEN
        _RSUBI-ENTRIES @ _RSUBI-EU @ MSPAN-NONWRAPPING? 0= IF
            RSUB-S-INVALID EXIT
        THEN
        _RSUBI-TS @ 0> 0= _RSUBI-TA @ 0= OR IF RSUB-S-INVALID EXIT THEN
        _RSUBI-TA @ _RSUBI-TU @ MSPAN-NONWRAPPING? 0= IF
            RSUB-S-INVALID EXIT
        THEN
        _RSUBI-ES @ IF
            _RSUBI-EA @ 0= IF RSUB-S-INVALID EXIT THEN
            _RSUBI-EA @ _RSUBI-VU @ MSPAN-NONWRAPPING? 0= IF
                RSUB-S-INVALID EXIT
            THEN
        ELSE
            _RSUBI-EA @ IF RSUB-S-INVALID EXIT THEN
        THEN
    THEN
    _RSUBI-O @ RABBIT-SUBSCRIPTIONS-SIZE
        _RSUBI-ENTRIES @ _RSUBI-EU @ MSPAN-OVERLAP? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-O @ RABBIT-SUBSCRIPTIONS-SIZE
        _RSUBI-TA @ _RSUBI-TU @ MSPAN-OVERLAP? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-O @ RABBIT-SUBSCRIPTIONS-SIZE
        _RSUBI-EA @ _RSUBI-VU @ MSPAN-OVERLAP? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-ENTRIES @ _RSUBI-EU @
        _RSUBI-TA @ _RSUBI-TU @ MSPAN-OVERLAP? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-ENTRIES @ _RSUBI-EU @
        _RSUBI-EA @ _RSUBI-VU @ MSPAN-OVERLAP? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-TA @ _RSUBI-TU @ _RSUBI-EA @ _RSUBI-VU @
        MSPAN-OVERLAP? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-O @ RABBIT-SUBSCRIPTIONS-SIZE _RSUBI-C @
        _RSUB-SPAN-HITS-CLIENT? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-ENTRIES @ _RSUBI-EU @ _RSUBI-C @
        _RSUB-SPAN-HITS-CLIENT? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-TA @ _RSUBI-TU @ _RSUBI-C @
        _RSUB-SPAN-HITS-CLIENT? IF RSUB-S-ALIAS EXIT THEN
    _RSUBI-EA @ _RSUBI-VU @ _RSUBI-C @
        _RSUB-SPAN-HITS-CLIENT? IF RSUB-S-ALIAS EXIT THEN

    _RSUBI-O @ RABBIT-SUBSCRIPTIONS-SIZE 0 FILL
    _RSUBI-EU @ IF _RSUBI-ENTRIES @ _RSUBI-EU @ 0 FILL THEN
    _RSUBI-TU @ IF _RSUBI-TA @ _RSUBI-TU @ 0 FILL THEN
    _RSUBI-VU @ IF _RSUBI-EA @ _RSUBI-VU @ 0 FILL THEN
    _RSUB-MAGIC-VALUE _RSUBI-O @ RSUB.MAGIC !
    _RSUB-ABI-VERSION _RSUBI-O @ RSUB.ABI !
    RABBIT-SUBSCRIPTIONS-SIZE _RSUBI-O @ RSUB.BYTES !
    RSUB-ST-ATTACHED _RSUBI-O @ RSUB.STATE !
    RSUB-S-OK _RSUBI-O @ RSUB.LAST-STATUS !
    _RSUBI-C @ _RSUBI-O @ RSUB.CLIENT !
    _RSUBI-ENTRIES @ _RSUBI-O @ RSUB.ENTRIES !
    _RSUBI-CAP @ _RSUBI-O @ RSUB.CAPACITY !
    _RSUBI-TA @ _RSUBI-O @ RSUB.TARGET-A !
    _RSUBI-TS @ _RSUBI-O @ RSUB.TARGET-SLOT-BYTES !
    _RSUBI-EA @ _RSUBI-O @ RSUB.EVENT-A !
    _RSUBI-ES @ _RSUBI-O @ RSUB.EVENT-SLOT-BYTES !
    1 _RSUBI-O @ RSUB.NEXT-GENERATION !
    RSUB-S-OK ;

: RABBIT-SUBSCRIPTIONS-STATE@  ( owner -- state status )
    DUP RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        DROP RSUB-ST-DETACHED RSUB-S-INVALID EXIT
    THEN
    RSUB.STATE @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTIONS-COUNT@  ( owner -- count status )
    DUP RABBIT-SUBSCRIPTIONS-VALID? 0= IF DROP 0 RSUB-S-INVALID EXIT THEN
    RSUB.COUNT @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTIONS-CAPACITY@  ( owner -- capacity status )
    DUP RABBIT-SUBSCRIPTIONS-VALID? 0= IF DROP 0 RSUB-S-INVALID EXIT THEN
    RSUB.CAPACITY @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTIONS-LAST-STATUS@  ( owner -- status )
    DUP RABBIT-SUBSCRIPTIONS-VALID? 0= IF DROP RSUB-S-INVALID EXIT THEN
    RSUB.LAST-STATUS @ ;

: RABBIT-SUBSCRIPTIONS-DETAIL@  ( owner -- detail status )
    DUP RABBIT-SUBSCRIPTIONS-VALID? 0= IF DROP 0 RSUB-S-INVALID EXIT THEN
    RSUB.DETAIL @ RSUB-S-OK ;

\ =====================================================================
\  Exact handles, copied-target registration, and entry evidence
\ =====================================================================

VARIABLE _RSUBS-O
VARIABLE _RSUBS-DETAIL
VARIABLE _RSUBS-GENERATION

: _RSUB-STATUS!  ( status detail owner -- status )
    _RSUBS-O ! _RSUBS-DETAIL !
    DUP _RSUBS-O @ RSUB.LAST-STATUS !
    _RSUBS-DETAIL @ _RSUBS-O @ RSUB.DETAIL ! ;

: _RSUB-NEXT-GENERATION  ( owner -- generation|0 )
    DUP RSUB.NEXT-GENERATION @ DUP _RSUBS-GENERATION !
    RABBIT-U64-MAX = IF DROP 0 EXIT THEN
    _RSUBS-GENERATION @ 1+ SWAP RSUB.NEXT-GENERATION !
    _RSUBS-GENERATION @ ;

VARIABLE _RSUBH-E
VARIABLE _RSUBH-G
VARIABLE _RSUBH-O
VARIABLE _RSUBH-I

: _RSUB-ENTRY-INDEX  ( entry owner -- index flag )
    _RSUBH-O ! _RSUBH-E !
    _RSUBH-O @ RSUB.CAPACITY @ 0= IF 0 0 EXIT THEN
    _RSUBH-E @ _RSUBH-O @ RSUB.ENTRIES @ U< IF 0 0 EXIT THEN
    _RSUBH-E @ _RSUBH-O @ RSUB.ENTRIES @ -
    DUP _RSUBH-O @ RSUB.CAPACITY @
        RABBIT-SUBSCRIPTION-ENTRY-BYTES U< 0= IF DROP 0 0 EXIT THEN
    DUP RABBIT-SUBSCRIPTION-ENTRY-SIZE MOD IF DROP 0 0 EXIT THEN
    RABBIT-SUBSCRIPTION-ENTRY-SIZE /
    DUP _RSUBH-O @ RSUB.CAPACITY @ U< 0= IF DROP 0 0 EXIT THEN
    -1 ;

: _RSUB-HANDLE?  ( entry generation owner -- index flag )
    _RSUBH-O ! _RSUBH-G ! _RSUBH-E !
    _RSUBH-G @ 0= IF 0 0 EXIT THEN
    _RSUBH-E @ _RSUBH-O @ _RSUB-ENTRY-INDEX 0= IF
        DROP 0 0 EXIT
    THEN
    DUP _RSUBH-I ! _RSUBH-O @ _RSUB-ENTRY@
    DUP RSUBE.STATE @ RSUB-ENTRY-EMPTY = IF DROP 0 0 EXIT THEN
    RSUBE.GENERATION @ _RSUBH-G @ = IF _RSUBH-I @ -1 ELSE 0 0 THEN ;

VARIABLE _RSUBSO-A
VARIABLE _RSUBSO-U
VARIABLE _RSUBSO-O

: _RSUB-SPAN-HITS-OWNER?  ( address bytes owner -- flag )
    _RSUBSO-O ! _RSUBSO-U ! _RSUBSO-A !
    _RSUBSO-A @ _RSUBSO-U @ MSPAN-NONWRAPPING? 0= IF -1 EXIT THEN
    _RSUBSO-A @ _RSUBSO-U @ _RSUBSO-O @ RABBIT-SUBSCRIPTIONS-SIZE
        MSPAN-OVERLAP? IF -1 EXIT THEN
    _RSUBSO-A @ _RSUBSO-U @
        _RSUBSO-O @ RSUB.ENTRIES @ _RSUBSO-O @ RSUB.CAPACITY @
        RABBIT-SUBSCRIPTION-ENTRY-BYTES MSPAN-OVERLAP? IF -1 EXIT THEN
    _RSUBSO-A @ _RSUBSO-U @
        _RSUBSO-O @ RSUB.TARGET-A @ _RSUBSO-O @ RSUB.CAPACITY @
        _RSUBSO-O @ RSUB.TARGET-SLOT-BYTES @ *
        MSPAN-OVERLAP? IF -1 EXIT THEN
    _RSUBSO-A @ _RSUBSO-U @
        _RSUBSO-O @ RSUB.EVENT-A @ _RSUBSO-O @ RSUB.CAPACITY @
        _RSUBSO-O @ RSUB.EVENT-SLOT-BYTES @ *
        MSPAN-OVERLAP? ;

: _RSUB-SPAN=  ( a1 u1 a2 u2 -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP -1 EXIT THEN
    COMPARE 0= ;

VARIABLE _RSUBF-A
VARIABLE _RSUBF-U
VARIABLE _RSUBF-LANE
VARIABLE _RSUBF-O
VARIABLE _RSUBF-E

: _RSUB-FIND  ( target-a target-u lane owner -- entry index flag )
    _RSUBF-O ! _RSUBF-LANE ! _RSUBF-U ! _RSUBF-A !
    _RSUBF-O @ RSUB.CAPACITY @ 0 ?DO
        I _RSUBF-O @ _RSUB-ENTRY@ DUP _RSUBF-E !
        RSUBE.STATE @ RSUB-ENTRY-EMPTY <> IF
            _RSUBF-E @ RSUBE.LANE @ _RSUBF-LANE @ = IF
                I _RSUBF-O @ _RSUB-TARGET@
                _RSUBF-E @ RSUBE.TARGET-U @ _RSUBF-A @ _RSUBF-U @
                _RSUB-SPAN= IF _RSUBF-E @ I -1 UNLOOP EXIT THEN
            THEN
        THEN
    LOOP
    0 0 0 ;

: RABBIT-SUBSCRIPTION-MATCH?  ( entry generation owner -- flag status )
    DUP RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        2DROP DROP 0 RSUB-S-INVALID EXIT
    THEN
    _RSUB-HANDLE? NIP RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-FIND
  ( target-a target-u lane owner -- entry generation status )
    _RSUBF-O ! _RSUBF-LANE ! _RSUBF-U ! _RSUBF-A !
    _RSUBF-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        0 0 RSUB-S-INVALID EXIT
    THEN
    _RSUBF-A @ 0= _RSUBF-U @ 0> 0= OR IF
        0 0 RSUB-S-INVALID EXIT
    THEN
    _RSUBF-A @ _RSUBF-U @ MSPAN-NONWRAPPING? 0= IF
        0 0 RSUB-S-INVALID EXIT
    THEN
    _RSUBF-A @ _RSUBF-U @ UTF8-VALID? 0= IF
        0 0 RSUB-S-MESSAGE EXIT
    THEN
    _RSUBF-A @ _RSUBF-U @ _RSUB-SELECTOR-GRAMMAR? 0= IF
        0 0 RSUB-S-MESSAGE EXIT
    THEN
    _RSUBF-LANE @ _RSUB-APP-LANE? 0= IF
        0 0 RSUB-S-INVALID EXIT
    THEN
    _RSUBF-A @ _RSUBF-U @ _RSUBF-LANE @ _RSUBF-O @
        _RSUB-FIND 0= IF
        2DROP 0 0 RSUB-S-NOT-FOUND EXIT
    THEN
    DROP DUP RSUBE.GENERATION @ RSUB-S-OK ;

VARIABLE _RSUBA-A
VARIABLE _RSUBA-U
VARIABLE _RSUBA-LANE
VARIABLE _RSUBA-CURSOR
VARIABLE _RSUBA-XT
VARIABLE _RSUBA-CONTEXT
VARIABLE _RSUBA-O
VARIABLE _RSUBA-I
VARIABLE _RSUBA-E
VARIABLE _RSUBA-G

: RABBIT-SUBSCRIPTIONS-ADD
  ( target-a target-u lane initial-cursor callback-xt callback-context owner )
  ( -- entry generation status )
    _RSUBP-BUSY @ IF
        2DROP 2DROP 2DROP DROP 0 0 RSUB-S-STATE EXIT
    THEN
    _RSUBA-O ! _RSUBA-CONTEXT ! _RSUBA-XT ! _RSUBA-CURSOR !
    _RSUBA-LANE ! _RSUBA-U ! _RSUBA-A !
    _RSUBA-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        0 0 RSUB-S-INVALID EXIT
    THEN
    _RSUBA-A @ 0= _RSUBA-U @ 0> 0= OR IF
        0 0 RSUB-S-INVALID 0 _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-A @ _RSUBA-U @ MSPAN-NONWRAPPING? 0= IF
        0 0 RSUB-S-INVALID 0 _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-A @ _RSUBA-U @ UTF8-VALID? 0= IF
        0 0 RSUB-S-MESSAGE RMSG-S-VALUE _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-A @ _RSUBA-U @ _RSUB-SELECTOR-GRAMMAR? 0= IF
        0 0 RSUB-S-MESSAGE RMSG-S-VALUE _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-LANE @ _RSUB-APP-LANE? 0= IF
        0 0 RSUB-S-INVALID 0 _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-XT @ 0= IF
        0 0 RSUB-S-CALLBACK 0 _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-U @ _RSUBA-O @ RSUB.TARGET-SLOT-BYTES @ U> IF
        0 0 RSUB-S-CAPACITY _RSUBA-U @ _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-A @ _RSUBA-U @ _RSUBA-O @ _RSUB-SPAN-HITS-OWNER? IF
        0 0 RSUB-S-ALIAS 0 _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-A @ _RSUBA-U @ _RSUBA-LANE @ _RSUBA-O @ _RSUB-FIND IF
        2DROP 0 0 RSUB-S-DUPLICATE 0 _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    2DROP
    -1 _RSUBA-I !
    _RSUBA-O @ RSUB.CAPACITY @ 0 ?DO
        I _RSUBA-O @ _RSUB-ENTRY@ RSUBE.STATE @ RSUB-ENTRY-EMPTY = IF
            I _RSUBA-I ! LEAVE
        THEN
    LOOP
    _RSUBA-I @ 0< IF
        0 0 RSUB-S-CAPACITY 0 _RSUBA-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBA-O @ RSUB.NEXT-GENERATION @ RABBIT-U64-MAX = IF
        0 0 RSUB-S-OVERFLOW RABBIT-U64-MAX _RSUBA-O @
            _RSUB-STATUS! EXIT
    THEN
    _RSUBA-I @ _RSUBA-O @ _RSUB-ENTRY@ _RSUBA-E !
    _RSUBA-I @ _RSUBA-O @ _RSUB-TARGET@
        _RSUBA-O @ RSUB.TARGET-SLOT-BYTES @ 0 FILL
    _RSUBA-O @ RSUB.EVENT-SLOT-BYTES @ IF
        _RSUBA-I @ _RSUBA-O @ _RSUB-EVENT@
            _RSUBA-O @ RSUB.EVENT-SLOT-BYTES @ 0 FILL
    THEN
    _RSUBA-E @ RABBIT-SUBSCRIPTION-ENTRY-SIZE 0 FILL
    _RSUBA-A @ _RSUBA-I @ _RSUBA-O @ _RSUB-TARGET@ _RSUBA-U @ MOVE
    _RSUBA-O @ _RSUB-NEXT-GENERATION DUP _RSUBA-G !
        _RSUBA-E @ RSUBE.GENERATION !
    _RSUBA-LANE @ _RSUBA-E @ RSUBE.LANE !
    _RSUBA-U @ _RSUBA-E @ RSUBE.TARGET-U !
    _RSUBA-CURSOR @ _RSUBA-E @ RSUBE.CURSOR !
    _RSUBA-XT @ _RSUBA-E @ RSUBE.CALLBACK-XT !
    _RSUBA-CONTEXT @ _RSUBA-E @ RSUBE.CALLBACK-CONTEXT !
    RSUB-DELIVERY-NONE _RSUBA-E @ RSUBE.LAST-DELIVERY !
    RCLIENT-S-OK _RSUBA-E @ RSUBE.CLIENT-STATUS !
    _RSUBA-O @ RSUB.STATE @ RSUB-ST-ATTACHED = IF
        RSUB-ENTRY-CONFIGURED
    ELSE
        RSUB-ENTRY-NEEDS-REBIND
    THEN _RSUBA-E @ RSUBE.STATE !
    1 _RSUBA-O @ RSUB.COUNT +!
    _RSUBA-E @ _RSUBA-G @ RSUB-S-OK 0 _RSUBA-O @ _RSUB-STATUS! ;

VARIABLE _RSUBEVID-E
VARIABLE _RSUBEVID-G
VARIABLE _RSUBEVID-O
VARIABLE _RSUBEVID-I

: _RSUB-EVIDENCE-HANDLE  ( entry generation owner -- entry status )
    _RSUBEVID-O ! _RSUBEVID-G ! _RSUBEVID-E !
    _RSUBEVID-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        0 RSUB-S-INVALID EXIT
    THEN
    _RSUBEVID-E @ _RSUBEVID-G @ _RSUBEVID-O @ _RSUB-HANDLE? 0= IF
        DROP 0 RSUB-S-NOT-FOUND EXIT
    THEN
    _RSUBEVID-I ! _RSUBEVID-E @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-STATE@
  ( entry generation owner -- state status )
    _RSUB-EVIDENCE-HANDLE DUP IF
        NIP RSUB-ENTRY-EMPTY SWAP EXIT
    THEN DROP RSUBE.STATE @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-TARGET$
  ( entry generation owner -- address length status )
    _RSUB-EVIDENCE-HANDLE DUP IF
        >R DROP 0 0 R> EXIT
    THEN
    DROP DUP RSUBE.TARGET-U @ >R DROP
    _RSUBEVID-I @ _RSUBEVID-O @ _RSUB-TARGET@ R> RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-LANE@
  ( entry generation owner -- lane status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP 0 SWAP EXIT THEN
    DROP RSUBE.LANE @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-CURSOR@
  ( entry generation owner -- event-seq status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP 0 SWAP EXIT THEN
    DROP RSUBE.CURSOR @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-NEXT-EVENT@
  ( entry generation owner -- next-event-seq status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP 0 SWAP EXIT THEN
    DROP RSUBE.CURSOR @ DUP RABBIT-U64-MAX = IF
        DROP 0 RSUB-S-OVERFLOW EXIT
    THEN
    1+ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-LAST-LANE-SEQ@
  ( entry generation owner -- lane-seq status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP 0 SWAP EXIT THEN
    DROP RSUBE.LAST-LANE-SEQ @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-LAST-OBSERVED-EVENT-SEQ@
  ( entry generation owner -- event-seq status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP 0 SWAP EXIT THEN
    DROP RSUBE.LAST-OBSERVED-EVENT-SEQ @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-LAST-DELIVERY@
  ( entry generation owner -- delivery status )
    _RSUB-EVIDENCE-HANDLE DUP IF
        NIP RSUB-DELIVERY-NONE SWAP EXIT
    THEN
    DROP RSUBE.LAST-DELIVERY @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-EVENT-REQUIRED@
  ( entry generation owner -- bytes status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP 0 SWAP EXIT THEN
    DROP RSUBE.EVENT-REQUIRED @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-CLIENT-STATUS@
  ( entry generation owner -- client-status status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP RCLIENT-S-INVALID SWAP EXIT THEN
    DROP RSUBE.CLIENT-STATUS @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-BIND-OP@
  ( entry generation owner -- operation op-generation status )
    _RSUB-EVIDENCE-HANDLE DUP IF >R DROP 0 0 R> EXIT THEN
    DROP DUP RSUBE.STATE @ DUP RSUB-ENTRY-BINDING =
    SWAP RSUB-ENTRY-BIND-RESULT = OR 0= IF
        DROP 0 0 RSUB-S-STATE EXIT
    THEN
    DUP RSUBE.BIND-OP @ SWAP RSUBE.BIND-GENERATION @ RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-RELEASE
  ( entry generation owner -- status )
    _RSUBP-BUSY @ IF 2DROP DROP RSUB-S-STATE EXIT THEN
    _RSUBEVID-O ! _RSUBEVID-G ! _RSUBEVID-E !
    _RSUBEVID-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        RSUB-S-INVALID EXIT
    THEN
    _RSUBEVID-E @ _RSUBEVID-G @ _RSUBEVID-O @ _RSUB-HANDLE? 0= IF
        DROP RSUB-S-NOT-FOUND 0 _RSUBEVID-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBEVID-I !
    _RSUBEVID-E @ RSUBE.STATE @ DUP RSUB-ENTRY-CONFIGURED =
    SWAP RSUB-ENTRY-NEEDS-REBIND = OR 0= IF
        RSUB-S-STATE 0 _RSUBEVID-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBEVID-I @ _RSUBEVID-O @ _RSUB-TARGET@
        _RSUBEVID-O @ RSUB.TARGET-SLOT-BYTES @ 0 FILL
    _RSUBEVID-O @ RSUB.EVENT-SLOT-BYTES @ IF
        _RSUBEVID-I @ _RSUBEVID-O @ _RSUB-EVENT@
            _RSUBEVID-O @ RSUB.EVENT-SLOT-BYTES @ 0 FILL
    THEN
    _RSUBEVID-E @ RABBIT-SUBSCRIPTION-ENTRY-SIZE 0 FILL
    -1 _RSUBEVID-O @ RSUB.COUNT +!
    RSUB-S-OK 0 _RSUBEVID-O @ _RSUB-STATUS! ;

\ =====================================================================
\  Correlated SUBSCRIBE binding and caller-resolved terminal result
\ =====================================================================

VARIABLE _RSUBBD-B
VARIABLE _RSUBBD-O

: _RSUB-BUILDER-DISJOINT?  ( builder owner -- flag )
    _RSUBBD-O ! _RSUBBD-B !
    _RSUBBD-O @ RABBIT-SUBSCRIPTIONS-SIZE _RSUBBD-B @
        RMSGB-OWNED-SPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBBD-O @ RSUB.ENTRIES @ _RSUBBD-O @ RSUB.CAPACITY @
        RABBIT-SUBSCRIPTION-ENTRY-BYTES _RSUBBD-B @
        RMSGB-OWNED-SPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBBD-O @ RSUB.TARGET-A @ _RSUBBD-O @ RSUB.CAPACITY @
        _RSUBBD-O @ RSUB.TARGET-SLOT-BYTES @ * _RSUBBD-B @
        RMSGB-OWNED-SPAN-OVERLAP? IF 0 EXIT THEN
    _RSUBBD-O @ RSUB.EVENT-A @ _RSUBBD-O @ RSUB.CAPACITY @
        _RSUBBD-O @ RSUB.EVENT-SLOT-BYTES @ * _RSUBBD-B @
        RMSGB-OWNED-SPAN-OVERLAP? 0= ;

VARIABLE _RSUBB-E
VARIABLE _RSUBB-G
VARIABLE _RSUBB-XA
VARIABLE _RSUBB-XU
VARIABLE _RSUBB-B
VARIABLE _RSUBB-O
VARIABLE _RSUBB-I
VARIABLE _RSUBB-RS
VARIABLE _RSUBB-OP
VARIABLE _RSUBB-OPG

: RABBIT-SUBSCRIPTION-BIND
  ( entry generation txn-a txn-u empty-builder owner )
  ( -- operation op-generation status )
    _RSUBP-BUSY @ IF 2DROP 2DROP 2DROP 0 0 RSUB-S-STATE EXIT THEN
    _RSUBB-O ! _RSUBB-B ! _RSUBB-XU ! _RSUBB-XA !
    _RSUBB-G ! _RSUBB-E !
    _RSUBB-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        0 0 RSUB-S-INVALID EXIT
    THEN
    _RSUBB-O @ RSUB.STATE @ RSUB-ST-ATTACHED <> IF
        0 0 RSUB-S-DISCONNECTED 0 _RSUBB-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBB-E @ _RSUBB-G @ _RSUBB-O @ _RSUB-HANDLE? 0= IF
        DROP 0 0 RSUB-S-NOT-FOUND 0 _RSUBB-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBB-I !
    _RSUBB-E @ RSUBE.STATE @ DUP RSUB-ENTRY-CONFIGURED =
    SWAP RSUB-ENTRY-NEEDS-REBIND = OR 0= IF
        0 0 RSUB-S-STATE 0 _RSUBB-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBB-XA @ 0= _RSUBB-XU @ 0> 0= OR IF
        0 0 RSUB-S-INVALID 0 _RSUBB-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBB-XA @ _RSUBB-XU @ MSPAN-NONWRAPPING? 0= IF
        0 0 RSUB-S-INVALID 0 _RSUBB-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBB-B @ RMSGB-VALID? 0= IF
        0 0 RSUB-S-BUILDER RMSGB-S-INVALID _RSUBB-O @
            _RSUB-STATUS! EXIT
    THEN
    _RSUBB-B @ RMSGB-STATE@ RMSGB-STATE-EMPTY <> IF
        0 0 RSUB-S-BUILDER RMSGB-S-STATE _RSUBB-O @
            _RSUB-STATUS! EXIT
    THEN
    _RSUBB-B @ _RSUBB-O @ _RSUB-BUILDER-DISJOINT? 0= IF
        0 0 RSUB-S-ALIAS RMSGB-S-ALIAS _RSUBB-O @
            _RSUB-STATUS! EXIT
    THEN
    RMSG-KIND-SUBSCRIBE
        _RSUBB-I @ _RSUBB-O @ _RSUB-TARGET@
        _RSUBB-E @ RSUBE.TARGET-U @ _RSUBB-E @ RSUBE.LANE @
        _RSUBB-XA @ _RSUBB-XU @ _RSUBB-B @ RMSGB-BEGIN-REQUEST
        DUP _RSUBB-RS ! IF
        0 0 RSUB-S-BUILDER _RSUBB-RS @ _RSUBB-O @
            _RSUB-STATUS! EXIT
    THEN
    _RSUBB-E @ RSUBE.CURSOR @ ?DUP IF
        _RSUBB-B @ RMSGB-SINCE! DUP _RSUBB-RS ! IF
            0 0 RSUB-S-BUILDER _RSUBB-RS @ _RSUBB-O @
                _RSUB-STATUS! EXIT
        THEN
    THEN
    _RSUBB-B @ RMSGB-SEAL DUP _RSUBB-RS ! IF
        0 0 RSUB-S-BUILDER _RSUBB-RS @ _RSUBB-O @
            _RSUB-STATUS! EXIT
    THEN
    _RSUBB-B @ _RSUBB-O @ RSUB.CLIENT @ RABBIT-CLIENT-REQUEST
    _RSUBB-RS ! _RSUBB-OPG ! _RSUBB-OP !
    _RSUBB-RS @ IF
        0 0 RSUB-S-CLIENT _RSUBB-RS @ _RSUBB-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBB-OP @ _RSUBB-E @ RSUBE.BIND-OP !
    _RSUBB-OPG @ _RSUBB-E @ RSUBE.BIND-GENERATION !
    RCLIENT-S-PENDING _RSUBB-E @ RSUBE.CLIENT-STATUS !
    RSUB-ENTRY-BINDING _RSUBB-E @ RSUBE.STATE !
    _RSUBB-OP @ _RSUBB-OPG @ RSUB-S-OK 0 _RSUBB-O @
        _RSUB-STATUS! ;

: RABBIT-SUBSCRIPTION-BIND-RESULT@
  ( entry generation owner -- code address length status )
    _RSUB-EVIDENCE-HANDLE DUP IF
        >R DROP 0 0 0 R> EXIT
    THEN DROP
    DUP RSUBE.STATE @ RSUB-ENTRY-BIND-RESULT <> IF
        DROP 0 0 0 RSUB-S-STATE EXIT
    THEN
    RSUBE.BIND-OP @ _RSUBEVID-O @ RSUB.CLIENT @
        RABBIT-CLIENT-OP-RESULT@ DUP IF
        >R 2DROP DROP R> DROP 0 0 0 RSUB-S-CLIENT EXIT
    THEN
    DROP RSUB-S-OK ;

: RABBIT-SUBSCRIPTION-BIND-REQUIRED@
  ( entry generation owner -- bytes status )
    _RSUB-EVIDENCE-HANDLE DUP IF NIP 0 SWAP EXIT THEN
    DROP
    DUP RSUBE.STATE @ RSUB-ENTRY-BIND-RESULT <> IF
        DROP 0 RSUB-S-STATE EXIT
    THEN
    RSUBE.BIND-OP @ _RSUBEVID-O @ RSUB.CLIENT @
        RABBIT-CLIENT-OP-REQUIRED@ DUP IF
        2DROP 0 RSUB-S-CLIENT EXIT
    THEN DROP RSUB-S-OK ;

VARIABLE _RSUBR-E
VARIABLE _RSUBR-G
VARIABLE _RSUBR-ACCEPT
VARIABLE _RSUBR-O
VARIABLE _RSUBR-I
VARIABLE _RSUBR-OPSTATE
VARIABLE _RSUBR-RS

: RABBIT-SUBSCRIPTION-BIND-RESOLVE
  ( entry generation accepted owner -- status )
    _RSUBP-BUSY @ IF 2DROP 2DROP RSUB-S-STATE EXIT THEN
    _RSUBR-O ! _RSUBR-ACCEPT ! _RSUBR-G ! _RSUBR-E !
    _RSUBR-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        RSUB-S-INVALID EXIT
    THEN
    _RSUBR-O @ RSUB.STATE @ RSUB-ST-ATTACHED <> IF
        RSUB-S-DISCONNECTED 0 _RSUBR-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBR-ACCEPT @ DUP 0= SWAP -1 = OR 0= IF
        RSUB-S-INVALID 0 _RSUBR-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBR-E @ _RSUBR-G @ _RSUBR-O @ _RSUB-HANDLE? 0= IF
        DROP RSUB-S-NOT-FOUND 0 _RSUBR-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBR-I !
    _RSUBR-E @ RSUBE.STATE @ RSUB-ENTRY-BIND-RESULT <> IF
        RSUB-S-STATE 0 _RSUBR-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBR-E @ RSUBE.BIND-OP @ _RSUBR-O @ RSUB.CLIENT @
        RABBIT-CLIENT-OP-STATE@ _RSUBR-RS ! _RSUBR-OPSTATE !
    _RSUBR-RS @ IF
        RSUB-S-CLIENT _RSUBR-RS @ _RSUBR-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBR-ACCEPT @ IF
        _RSUBR-OPSTATE @ RCLIENT-OP-COMPLETE <> IF
            RSUB-S-STATE _RSUBR-OPSTATE @ _RSUBR-O @
                _RSUB-STATUS! EXIT
        THEN
        _RSUBR-E @ RSUBE.CLIENT-STATUS @ RCLIENT-S-OK <> IF
            RSUB-S-CLIENT _RSUBR-E @ RSUBE.CLIENT-STATUS @ _RSUBR-O @
                _RSUB-STATUS! EXIT
        THEN
    THEN
    _RSUBR-E @ RSUBE.BIND-OP @ _RSUBR-E @ RSUBE.BIND-GENERATION @
        _RSUBR-O @ RSUB.CLIENT @ RABBIT-CLIENT-OP-RELEASE
        DUP _RSUBR-RS ! IF
        RSUB-S-CLIENT _RSUBR-RS @ _RSUBR-O @ _RSUB-STATUS! EXIT
    THEN
    0 _RSUBR-E @ RSUBE.BIND-OP !
    0 _RSUBR-E @ RSUBE.BIND-GENERATION !
    RCLIENT-S-OK _RSUBR-E @ RSUBE.CLIENT-STATUS !
    _RSUBR-ACCEPT @ IF RSUB-ENTRY-BOUND ELSE RSUB-ENTRY-CONFIGURED THEN
        _RSUBR-E @ RSUBE.STATE !
    RSUB-S-OK 0 _RSUBR-O @ _RSUB-STATUS! ;

\ =====================================================================
\  Synchronous client callback adapter and POLL/DISPATCH wrappers
\ =====================================================================

VARIABLE _RSUBP-O
VARIABLE _RSUBP-FALLBACK-XT
VARIABLE _RSUBP-FALLBACK-CONTEXT
VARIABLE _RSUBP-F
VARIABLE _RSUBP-KIND
VARIABLE _RSUBP-LANE
VARIABLE _RSUBP-LANE-SEQ
VARIABLE _RSUBP-EXPECTED
VARIABLE _RSUBP-DISPOSITION
VARIABLE _RSUBP-CALL-CONTEXT
VARIABLE _RSUBP-TARGET-A
VARIABLE _RSUBP-TARGET-U
VARIABLE _RSUBP-BODY-A
VARIABLE _RSUBP-BODY-U
VARIABLE _RSUBP-EVENT-SEQ
VARIABLE _RSUBP-PRESENT
VARIABLE _RSUBP-MESSAGE-STATUS
VARIABLE _RSUBP-MATCH-E
VARIABLE _RSUBP-MATCH-I
VARIABLE _RSUBP-MATCH-G
VARIABLE _RSUBP-DELIVERY
VARIABLE _RSUBP-EVENT-STATUS
VARIABLE _RSUBP-DECISION
VARIABLE _RSUBP-THROW
VARIABLE _RSUBP-CLIENT-ITEM
VARIABLE _RSUBP-CLIENT-SUBJECT
VARIABLE _RSUBP-CLIENT-GENERATION
VARIABLE _RSUBP-CLIENT-STATUS
VARIABLE _RSUBP-OUT-ITEM
VARIABLE _RSUBP-OUT-SUBJECT
VARIABLE _RSUBP-OUT-GENERATION
VARIABLE _RSUBP-OUT-STATUS
VARIABLE _RSUBP-OUT-DETAIL

: _RSUBP-RESET  ( -- )
    0 _RSUBP-F ! 0 _RSUBP-TARGET-A ! 0 _RSUBP-TARGET-U !
    0 _RSUBP-BODY-A ! 0 _RSUBP-BODY-U ! 0 _RSUBP-EVENT-SEQ !
    0 _RSUBP-MATCH-E ! 0 _RSUBP-MATCH-I ! 0 _RSUBP-MATCH-G !
    RSUB-DELIVERY-NONE _RSUBP-DELIVERY !
    RSUB-S-OTHER _RSUBP-EVENT-STATUS !
    0 _RSUBP-MESSAGE-STATUS !
    RSUB-DISPATCH-DROP _RSUBP-DECISION !
    0 _RSUBP-THROW ! ;

: _RSUBP-FALLBACK-INNER  ( -- )
    _RSUBP-F @ _RSUBP-KIND @ _RSUBP-LANE @ _RSUBP-LANE-SEQ @
    _RSUBP-EXPECTED @ _RSUBP-DISPOSITION @
    _RSUBP-FALLBACK-CONTEXT @ _RSUBP-FALLBACK-XT @ EXECUTE
    _RSUBP-DECISION ! ;

: _RSUBP-FALLBACK  ( -- client-decision )
    0 _RSUBP-THROW !
    _RSUBP-FALLBACK-XT @ 0= IF
        _RSUBP-KIND @ RMSG-KIND-RESPONSE = IF
            RSUB-DISPATCH-COMMIT
        ELSE
            RSUB-DISPATCH-DROP
        THEN DUP _RSUBP-DECISION ! EXIT
    THEN
    ['] _RSUBP-FALLBACK-INNER CATCH DUP _RSUBP-THROW ! IF
        RSUB-DELIVERY-CALLBACK _RSUBP-DELIVERY !
        RSUB-S-CALLBACK _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-DECISION @ RSUB-DISPATCH-VALID? 0= IF
        _RSUBP-DECISION @ _RSUBP-THROW !
        RSUB-DELIVERY-CALLBACK _RSUBP-DELIVERY !
        RSUB-S-CALLBACK _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-DECISION @ ;

: _RSUBP-ENTRY-CALLBACK-INNER  ( -- )
    _RSUBP-MATCH-E @ _RSUBP-MATCH-G @
    _RSUBP-LANE-SEQ @ _RSUBP-EVENT-SEQ @ _RSUBP-DELIVERY @
    _RSUBP-MATCH-I @ _RSUBP-O @ _RSUB-TARGET@
    _RSUBP-MATCH-E @ RSUBE.TARGET-U @
    _RSUBP-MATCH-I @ _RSUBP-O @ _RSUB-EVENT@ _RSUBP-BODY-U @
    _RSUBP-MATCH-E @ RSUBE.CALLBACK-CONTEXT @
    _RSUBP-MATCH-E @ RSUBE.CALLBACK-XT @ EXECUTE
    _RSUBP-DECISION ! ;

: _RSUBP-ENTRY-CALLBACK  ( -- client-decision )
    0 _RSUBP-THROW !
    ['] _RSUBP-ENTRY-CALLBACK-INNER CATCH DUP _RSUBP-THROW ! IF
        RSUB-DELIVERY-CALLBACK _RSUBP-DELIVERY !
        RSUB-S-CALLBACK _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-DECISION @ RSUB-DISPATCH-VALID? 0= IF
        _RSUBP-DECISION @ _RSUBP-THROW !
        RSUB-DELIVERY-CALLBACK _RSUBP-DELIVERY !
        RSUB-S-CALLBACK _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-DECISION @ ;

: _RSUBP-ACTIVE-ENTRY?  ( entry -- flag )
    RSUBE.STATE @ RSUB-ENTRY-BOUND = ;

: _RSUBP-CLASSIFY-EVENT  ( -- )
    _RSUBP-MATCH-E @ RSUBE.CURSOR @
    _RSUBP-EVENT-SEQ @ OVER U> 0= IF
        DROP RSUB-DELIVERY-DUPLICATE _RSUBP-DELIVERY !
        RSUB-S-EVENT-DUPLICATE _RSUBP-EVENT-STATUS ! EXIT
    THEN
    1+ _RSUBP-EVENT-SEQ @ = IF
        RSUB-DELIVERY-NEW _RSUBP-DELIVERY !
        RSUB-S-EVENT _RSUBP-EVENT-STATUS ! EXIT
    THEN
    RSUB-DELIVERY-GAP _RSUBP-DELIVERY !
    RSUB-S-GAP _RSUBP-EVENT-STATUS ! ;

: _RSUBP-EVENT  ( -- client-decision )
    _RSUBP-F @ RBF-ARGS$ _RSUBP-TARGET-U ! _RSUBP-TARGET-A !
    _RSUBP-TARGET-A @ _RSUBP-TARGET-U @ _RSUBP-LANE @ _RSUBP-O @
        _RSUB-FIND 0= IF
        2DROP _RSUBP-FALLBACK EXIT
    THEN
    _RSUBP-MATCH-I ! _RSUBP-MATCH-E !
    _RSUBP-MATCH-E @ _RSUBP-ACTIVE-ENTRY? 0= IF
        0 _RSUBP-MATCH-E ! 0 _RSUBP-MATCH-I !
        _RSUBP-FALLBACK EXIT
    THEN
    _RSUBP-MATCH-E @ RSUBE.GENERATION @ _RSUBP-MATCH-G !
    _RSUBP-DISPOSITION @ RABBIT-INBOUND-GAP = IF
        RSUB-DELIVERY-PROTOCOL _RSUBP-DELIVERY !
        RSUB-S-PROTOCOL _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-F @ RMSG-EVENT-SEQ@
        _RSUBP-MESSAGE-STATUS ! _RSUBP-PRESENT ! _RSUBP-EVENT-SEQ !
    _RSUBP-MESSAGE-STATUS @ IF
        RSUB-DELIVERY-PROTOCOL _RSUBP-DELIVERY !
        RSUB-S-MESSAGE _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-PRESENT @ 0= IF
        RSUB-DELIVERY-PROTOCOL _RSUBP-DELIVERY !
        RSUB-S-PROTOCOL _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-EVENT-SEQ @ _RSUBP-MATCH-E @
        RSUBE.LAST-OBSERVED-EVENT-SEQ !
    _RSUBP-F @ RMSG-BODY$
        _RSUBP-MESSAGE-STATUS ! _RSUBP-BODY-U ! _RSUBP-BODY-A !
    _RSUBP-MESSAGE-STATUS @ IF
        RSUB-DELIVERY-PROTOCOL _RSUBP-DELIVERY !
        RSUB-S-MESSAGE _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-BODY-U @ _RSUBP-MATCH-E @ RSUBE.EVENT-REQUIRED !
    _RSUBP-CLASSIFY-EVENT
    _RSUBP-EVENT-STATUS @ DUP RSUB-S-GAP =
    OVER RSUB-S-OVERFLOW = OR IF
        DROP RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN DROP
    _RSUBP-BODY-U @ _RSUBP-O @ RSUB.EVENT-SLOT-BYTES @ U> IF
        RSUB-DELIVERY-CAPACITY _RSUBP-DELIVERY !
        RSUB-S-CAPACITY _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-BODY-U @ IF
        _RSUBP-BODY-A @ _RSUBP-MATCH-I @ _RSUBP-O @ _RSUB-EVENT@
            _RSUBP-BODY-U @ MOVE
    THEN
    _RSUBP-BODY-U @ _RSUBP-MATCH-E @ RSUBE.EVENT-U !
    _RSUBP-ENTRY-CALLBACK
    0 _RSUBP-MATCH-E @ RSUBE.EVENT-U ! ;

: _RSUBP-CLIENT-CALLBACK
  ( frame kind lane seq expected disposition context -- client-decision )
    _RSUBP-CALL-CONTEXT ! _RSUBP-DISPOSITION ! _RSUBP-EXPECTED !
    _RSUBP-LANE-SEQ ! _RSUBP-LANE ! _RSUBP-KIND ! _RSUBP-F !
    _RSUBP-CALL-CONTEXT @ _RSUBP-O @ <> IF
        RSUB-DELIVERY-PROTOCOL _RSUBP-DELIVERY !
        RSUB-S-PROTOCOL _RSUBP-EVENT-STATUS !
        RSUB-DISPATCH-DROP DUP _RSUBP-DECISION ! EXIT
    THEN
    _RSUBP-KIND @ RMSG-KIND-EVENT = IF
        _RSUBP-EVENT
    ELSE
        _RSUBP-FALLBACK
    THEN ;

VARIABLE _RSUBP-BO
VARIABLE _RSUBP-BG
VARIABLE _RSUBP-BOwner

: _RSUBP-FIND-BIND  ( operation generation owner -- entry index flag )
    _RSUBP-BOwner ! _RSUBP-BG ! _RSUBP-BO !
    _RSUBP-BOwner @ RSUB.CAPACITY @ 0 ?DO
        I _RSUBP-BOwner @ _RSUB-ENTRY@ DUP RSUBE.STATE @
            RSUB-ENTRY-BINDING = IF
            DUP RSUBE.BIND-OP @ _RSUBP-BO @ =
            OVER RSUBE.BIND-GENERATION @ _RSUBP-BG @ = AND IF
                I -1 UNLOOP EXIT
            THEN
        THEN
        DROP
    LOOP
    0 0 0 ;

: _RSUBP-SET-OUTPUT  ( item subject generation status detail -- )
    _RSUBP-OUT-DETAIL ! _RSUBP-OUT-STATUS !
    _RSUBP-OUT-GENERATION ! _RSUBP-OUT-SUBJECT ! _RSUBP-OUT-ITEM ! ;

: _RSUBP-FINALIZE-OPERATION  ( -- )
    _RSUBP-CLIENT-SUBJECT @ _RSUBP-CLIENT-GENERATION @ _RSUBP-O @
        _RSUBP-FIND-BIND IF
        DROP DUP _RSUBP-MATCH-E !
        DUP RSUBE.GENERATION @ _RSUBP-MATCH-G !
        _RSUBP-CLIENT-STATUS @ OVER RSUBE.CLIENT-STATUS !
        RSUB-ENTRY-BIND-RESULT SWAP RSUBE.STATE !
        RSUB-ITEM-BIND _RSUBP-MATCH-E @ _RSUBP-MATCH-G @
            RSUB-S-BIND-RESULT _RSUBP-CLIENT-STATUS @
            _RSUBP-SET-OUTPUT EXIT
    THEN
    2DROP
    RSUB-ITEM-CLIENT-OP _RSUBP-CLIENT-SUBJECT @
        _RSUBP-CLIENT-GENERATION @ RSUB-S-OTHER
        _RSUBP-CLIENT-STATUS @ _RSUBP-SET-OUTPUT ;

: _RSUBP-FINALIZE-EVENT  ( -- )
    _RSUBP-MATCH-E @ 0= IF
        _RSUBP-EVENT-STATUS @ RSUB-S-CALLBACK = IF
            RSUB-ITEM-OTHER 0 0 RSUB-S-CALLBACK _RSUBP-THROW @
        ELSE
            RSUB-ITEM-OTHER 0 0 RSUB-S-OTHER _RSUBP-CLIENT-STATUS @
        THEN _RSUBP-SET-OUTPUT EXIT
    THEN
    _RSUBP-CLIENT-STATUS @ _RSUBP-MATCH-E @ RSUBE.CLIENT-STATUS !
    _RSUBP-DELIVERY @ _RSUBP-MATCH-E @ RSUBE.LAST-DELIVERY !
    _RSUBP-CLIENT-STATUS @ RCLIENT-S-EVENT <> IF
        RSUB-ITEM-EVENT _RSUBP-MATCH-E @ _RSUBP-MATCH-G @
            RSUB-S-CLIENT _RSUBP-CLIENT-STATUS @
            _RSUBP-SET-OUTPUT EXIT
    THEN
    _RSUBP-DECISION @ RSUB-DISPATCH-COMMIT = IF
        _RSUBP-EVENT-STATUS @ RSUB-S-EVENT = IF
            _RSUBP-EVENT-SEQ @ _RSUBP-MATCH-E @ RSUBE.CURSOR !
        THEN
        _RSUBP-EVENT-STATUS @ DUP RSUB-S-EVENT =
        SWAP RSUB-S-EVENT-DUPLICATE = OR IF
            _RSUBP-LANE-SEQ @ _RSUBP-MATCH-E @ RSUBE.LAST-LANE-SEQ !
        THEN
    ELSE
        _RSUBP-EVENT-STATUS @ DUP RSUB-S-EVENT =
        SWAP RSUB-S-EVENT-DUPLICATE = OR IF
            RSUB-DELIVERY-DROPPED _RSUBP-MATCH-E @
                RSUBE.LAST-DELIVERY !
            RSUB-S-DROPPED _RSUBP-EVENT-STATUS !
        THEN
    THEN
    RSUB-ITEM-EVENT _RSUBP-MATCH-E @ _RSUBP-MATCH-G @
        _RSUBP-EVENT-STATUS @
        _RSUBP-EVENT-STATUS @ RSUB-S-CALLBACK = IF
            _RSUBP-THROW @
        ELSE
            _RSUBP-MESSAGE-STATUS @
        THEN
        _RSUBP-SET-OUTPUT ;

: _RSUBP-WIPE-STAGE  ( -- )
    _RSUBP-MATCH-E @ IF
        _RSUBP-O @ RSUB.EVENT-SLOT-BYTES @ IF
            _RSUBP-MATCH-I @ _RSUBP-O @ _RSUB-EVENT@
                _RSUBP-O @ RSUB.EVENT-SLOT-BYTES @ 0 FILL
        THEN
        0 _RSUBP-MATCH-E @ RSUBE.EVENT-U !
    THEN ;

: _RSUBP-CLEAR-BORROWED  ( -- )
    0 _RSUBP-F ! 0 _RSUBP-TARGET-A ! 0 _RSUBP-BODY-A !
    0 _RSUBP-FALLBACK-XT ! 0 _RSUBP-FALLBACK-CONTEXT !
    0 _RSUBP-CALL-CONTEXT ! ;

VARIABLE _RSUBD-O
VARIABLE _RSUBD-C
VARIABLE _RSUBD-E
VARIABLE _RSUBD-RS
VARIABLE _RSUBD-STATE

: _RSUB-TERMINAL-OP-STATE?  ( state -- flag )
    DUP RCLIENT-OP-COMPLETE = OVER RCLIENT-OP-CANCELLED = OR
    SWAP RCLIENT-OP-FAILED = OR ;

: _RSUB-BIND-OPS-RELEASABLE?  ( owner -- client-status )
    DUP _RSUBD-O ! RSUB.CLIENT @ _RSUBD-C !
    _RSUBD-O @ RSUB.CAPACITY @ 0 ?DO
        I _RSUBD-O @ _RSUB-ENTRY@ _RSUBD-E !
        _RSUBD-E @ RSUBE.STATE @ RSUB-ENTRY-EMPTY <> IF
            _RSUBD-E @ RSUBE.BIND-OP @ IF
                _RSUBD-E @ RSUBE.BIND-OP @
                    _RSUBD-E @ RSUBE.BIND-GENERATION @ _RSUBD-C @
                    RABBIT-CLIENT-OP-MATCH? _RSUBD-RS !
                _RSUBD-RS @ IF DROP _RSUBD-RS @ UNLOOP EXIT THEN
                0= IF RCLIENT-S-NOT-FOUND UNLOOP EXIT THEN
                _RSUBD-E @ RSUBE.BIND-OP @ _RSUBD-C @
                    RABBIT-CLIENT-OP-STATE@
                    _RSUBD-RS ! _RSUBD-STATE !
                _RSUBD-RS @ IF _RSUBD-RS @ UNLOOP EXIT THEN
                _RSUBD-STATE @ _RSUB-TERMINAL-OP-STATE? 0= IF
                    RCLIENT-S-STATE UNLOOP EXIT
                THEN
            THEN
        THEN
    LOOP
    RCLIENT-S-OK ;

\ Preflight and release are distinct passes.  Under the serialized ownership
\ contract, successful preflight makes each release below infallible; a
\ refusal can therefore never erase the only handle for a pending bind.
: _RSUB-RELEASE-BIND-OPS  ( owner -- client-status )
    DUP _RSUBD-O ! RSUB.CLIENT @ _RSUBD-C !
    _RSUBD-O @ RSUB.CAPACITY @ 0 ?DO
        I _RSUBD-O @ _RSUB-ENTRY@ _RSUBD-E !
        _RSUBD-E @ RSUBE.STATE @ RSUB-ENTRY-EMPTY <> IF
            _RSUBD-E @ RSUBE.BIND-OP @ IF
                _RSUBD-E @ RSUBE.BIND-OP @
                    _RSUBD-E @ RSUBE.BIND-GENERATION @ _RSUBD-C @
                    RABBIT-CLIENT-OP-RELEASE DUP IF UNLOOP EXIT THEN DROP
            THEN
        THEN
    LOOP
    RCLIENT-S-OK ;

: _RSUB-MARK-DETACHED  ( owner -- client-status )
    DUP _RSUBD-O ! RSUB.CLIENT @ _RSUBD-C !
    _RSUBD-O @ _RSUB-BIND-OPS-RELEASABLE? DUP IF EXIT THEN DROP
    _RSUBD-O @ _RSUB-RELEASE-BIND-OPS DUP IF EXIT THEN DROP
    _RSUBD-O @ RSUB.CAPACITY @ 0 ?DO
        I _RSUBD-O @ _RSUB-ENTRY@ _RSUBD-E !
        _RSUBD-E @ RSUBE.STATE @ RSUB-ENTRY-EMPTY <> IF
            _RSUBD-O @ RSUB.EVENT-SLOT-BYTES @ IF
                I _RSUBD-O @ _RSUB-EVENT@
                    _RSUBD-O @ RSUB.EVENT-SLOT-BYTES @ 0 FILL
            THEN
            RSUB-ENTRY-NEEDS-REBIND _RSUBD-E @ RSUBE.STATE !
            0 _RSUBD-E @ RSUBE.LAST-LANE-SEQ !
            0 _RSUBD-E @ RSUBE.LAST-OBSERVED-EVENT-SEQ !
            0 _RSUBD-E @ RSUBE.EVENT-U !
            0 _RSUBD-E @ RSUBE.EVENT-REQUIRED !
            0 _RSUBD-E @ RSUBE.BIND-OP !
            0 _RSUBD-E @ RSUBE.BIND-GENERATION !
            RSUB-DELIVERY-NONE _RSUBD-E @ RSUBE.LAST-DELIVERY !
            RCLIENT-S-CANCELLED _RSUBD-E @ RSUBE.CLIENT-STATUS !
        THEN
    LOOP
    0 _RSUBD-O @ RSUB.CLIENT !
    RSUB-ST-DETACHED _RSUBD-O @ RSUB.STATE !
    RCLIENT-S-OK ;

: _RSUBP-FINALIZE  ( -- item subject generation status )
    _RSUBP-CLIENT-ITEM @ CASE
        RCLIENT-ITEM-OPERATION OF _RSUBP-FINALIZE-OPERATION ENDOF
        RCLIENT-ITEM-EVENT OF _RSUBP-FINALIZE-EVENT ENDOF
        RCLIENT-ITEM-OTHER OF
            _RSUBP-EVENT-STATUS @ RSUB-S-CALLBACK = IF
                RSUB-ITEM-OTHER 0 0 RSUB-S-CALLBACK _RSUBP-THROW @
            ELSE
                RSUB-ITEM-OTHER 0 0 RSUB-S-OTHER _RSUBP-CLIENT-STATUS @
            THEN _RSUBP-SET-OUTPUT
        ENDOF
        RSUB-ITEM-NONE 0 0
        _RSUBP-EVENT-STATUS @ RSUB-S-CALLBACK = IF
            RSUB-S-CALLBACK _RSUBP-THROW @
        ELSE
            _RSUBP-CLIENT-STATUS @ RCLIENT-S-PENDING = IF
                RSUB-S-PENDING
            ELSE
                RSUB-S-CLIENT
            THEN _RSUBP-CLIENT-STATUS @
        THEN _RSUBP-SET-OUTPUT
    ENDCASE
    _RSUBP-CLIENT-ITEM @ RCLIENT-ITEM-NONE =
    _RSUBP-CLIENT-STATUS @ DUP RCLIENT-S-PENDING <>
    SWAP RCLIENT-S-OK <> AND AND IF
        _RSUBP-O @ _RSUB-MARK-DETACHED DUP IF
            >R RSUB-ITEM-NONE 0 0 RSUB-S-CLIENT R>
                _RSUBP-SET-OUTPUT
        ELSE
            DROP
        THEN
    THEN
    _RSUBP-OUT-STATUS @ _RSUBP-OUT-DETAIL @ _RSUBP-O @
        _RSUB-STATUS! DROP
    _RSUBP-WIPE-STAGE
    _RSUBP-CLEAR-BORROWED
    _RSUBP-OUT-ITEM @ _RSUBP-OUT-SUBJECT @
        _RSUBP-OUT-GENERATION @ _RSUBP-OUT-STATUS @
    0 _RSUBP-BUSY ! ;

: _RSUBP-PREPARE  ( fallback-xt fallback-context owner -- status )
    _RSUBP-O ! _RSUBP-FALLBACK-CONTEXT ! _RSUBP-FALLBACK-XT !
    _RSUBP-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        RSUB-S-INVALID EXIT
    THEN
    _RSUBP-O @ RSUB.STATE @ RSUB-ST-ATTACHED <> IF
        RSUB-S-DISCONNECTED EXIT
    THEN
    _RSUBP-RESET RSUB-S-OK ;

: RABBIT-SUBSCRIPTIONS-DISPATCH
  ( fallback-xt fallback-context owner -- item subject generation status )
    _RSUBP-BUSY @ IF
        2DROP DROP RSUB-ITEM-NONE 0 0 RSUB-S-STATE EXIT
    THEN
    -1 _RSUBP-BUSY !
    _RSUBP-PREPARE DUP IF
        >R _RSUBP-CLEAR-BORROWED 0 _RSUBP-O ! 0 _RSUBP-BUSY !
        RSUB-ITEM-NONE 0 0 R> EXIT
    THEN DROP
    ['] _RSUBP-CLIENT-CALLBACK _RSUBP-O @
        _RSUBP-O @ RSUB.CLIENT @ RABBIT-CLIENT-DISPATCH
    _RSUBP-CLIENT-STATUS ! _RSUBP-CLIENT-GENERATION !
    _RSUBP-CLIENT-SUBJECT ! _RSUBP-CLIENT-ITEM !
    _RSUBP-FINALIZE ;

: RABBIT-SUBSCRIPTIONS-POLL
  ( fallback-xt fallback-context owner -- item subject generation status )
    _RSUBP-BUSY @ IF
        2DROP DROP RSUB-ITEM-NONE 0 0 RSUB-S-STATE EXIT
    THEN
    -1 _RSUBP-BUSY !
    _RSUBP-PREPARE DUP IF
        >R _RSUBP-CLEAR-BORROWED 0 _RSUBP-O ! 0 _RSUBP-BUSY !
        RSUB-ITEM-NONE 0 0 R> EXIT
    THEN DROP
    ['] _RSUBP-CLIENT-CALLBACK _RSUBP-O @
        _RSUBP-O @ RSUB.CLIENT @ RABBIT-CLIENT-POLL
    _RSUBP-CLIENT-STATUS ! _RSUBP-CLIENT-GENERATION !
    _RSUBP-CLIENT-SUBJECT ! _RSUBP-CLIENT-ITEM !
    _RSUBP-FINALIZE ;

\ =====================================================================
\  Disconnect/rebind lifecycle and complete caller-storage finalization
\ =====================================================================

VARIABLE _RSUBLC-O
VARIABLE _RSUBLC-C
VARIABLE _RSUBLC-RS
VARIABLE _RSUBLC-CS
VARIABLE _RSUBLC-MS

: RABBIT-SUBSCRIPTIONS-DISCONNECT  ( owner -- status )
    _RSUBP-BUSY @ IF DROP RSUB-S-STATE EXIT THEN
    DUP _RSUBLC-O ! RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        RSUB-S-INVALID EXIT
    THEN
    _RSUBLC-O @ RSUB.STATE @ RSUB-ST-DETACHED = IF
        RSUB-S-OK 0 _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-O @ RSUB.CLIENT @ DUP _RSUBLC-C !
        RABBIT-CLIENT-CANCEL DUP _RSUBLC-RS ! DROP
    _RSUBLC-O @ _RSUB-MARK-DETACHED DUP _RSUBLC-MS ! IF
        RSUB-S-CLIENT _RSUBLC-MS @ _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-RS @ DUP RCLIENT-S-OK =
    SWAP RCLIENT-S-CANCELLED = OR IF
        RSUB-S-OK _RSUBLC-RS @ _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    RSUB-S-CLIENT _RSUBLC-RS @ _RSUBLC-O @ _RSUB-STATUS! ;

: RABBIT-SUBSCRIPTIONS-ATTACH  ( client owner -- status )
    _RSUBP-BUSY @ IF 2DROP RSUB-S-STATE EXIT THEN
    _RSUBLC-O ! _RSUBLC-C !
    _RSUBLC-O @ RABBIT-SUBSCRIPTIONS-VALID? 0= IF
        RSUB-S-INVALID EXIT
    THEN
    _RSUBLC-O @ RSUB.STATE @ RSUB-ST-DETACHED <> IF
        RSUB-S-STATE 0 _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-C @ RABBIT-CLIENT-VALID? 0= IF
        RSUB-S-CLIENT RCLIENT-S-INVALID _RSUBLC-O @
            _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-C @ RABBIT-CLIENT-STATE@
        _RSUBLC-RS ! _RSUBLC-CS !
    _RSUBLC-RS @ IF
        RSUB-S-CLIENT _RSUBLC-RS @ _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-CS @ DUP RCLIENT-ST-READY =
    SWAP RCLIENT-ST-ACTIVE = OR 0= IF
        RSUB-S-CLIENT RCLIENT-S-STATE _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-O @ _RSUB-OWN-GEOMETRY? 0= IF
        RSUB-S-INVALID 0 _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-C @ _RSUBLC-O @ _RSUB-CLIENT-GEOMETRY-DISJOINT? 0= IF
        RSUB-S-ALIAS 0 _RSUBLC-O @ _RSUB-STATUS! EXIT
    THEN
    _RSUBLC-C @ _RSUBLC-O @ RSUB.CLIENT !
    RSUB-ST-ATTACHED _RSUBLC-O @ RSUB.STATE !
    RSUB-S-OK 0 _RSUBLC-O @ _RSUB-STATUS! ;

: RABBIT-SUBSCRIPTIONS-BINDING-VALID?  ( owner -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _RSUB-CELL-ALIGNED? 0= IF DROP 0 EXIT THEN
    DUP RABBIT-SUBSCRIPTIONS-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    DUP RSUB.MAGIC @ _RSUB-MAGIC-VALUE <> IF DROP 0 EXIT THEN
    DUP RSUB.ABI @ _RSUB-ABI-VERSION <> IF DROP 0 EXIT THEN
    DUP RSUB.BYTES @ RABBIT-SUBSCRIPTIONS-SIZE <> IF DROP 0 EXIT THEN
    DUP RSUB.STATE @ RSUB-STATE-VALID? 0= IF DROP 0 EXIT THEN
    DUP _RSUB-OWN-GEOMETRY? 0= IF DROP 0 EXIT THEN
    DUP RSUB.STATE @ RSUB-ST-DETACHED <> IF DROP 0 EXIT THEN
    RSUB.CLIENT @ 0= ;

: _RSUB-CLEAR-SCRATCH  ( -- )
    0 _RSUBCG-C !
    0 _RSUBG-O ! 0 _RSUBG-EU ! 0 _RSUBG-TU ! 0 _RSUBG-VU !
    0 _RSUBSG-A ! 0 _RSUBSG-U ! 0 _RSUBSG-PREV-SPACE !
    0 _RSUBV-O ! 0 _RSUBV-E ! 0 _RSUBV-I ! 0 _RSUBV-N !
    0 _RSUBV-LIVE ! 0 _RSUBV-OPSTATE ! 0 _RSUBV-OPVALUE !
    0 _RSUBV-OPSTATUS !
    0 _RSUBI-ENTRIES ! 0 _RSUBI-CAP ! 0 _RSUBI-TA ! 0 _RSUBI-TS !
    0 _RSUBI-EA ! 0 _RSUBI-ES ! 0 _RSUBI-C ! 0 _RSUBI-O !
    0 _RSUBI-EU ! 0 _RSUBI-TU ! 0 _RSUBI-VU !
    0 _RSUBI-CS ! 0 _RSUBI-RS !
    0 _RSUBS-O ! 0 _RSUBS-DETAIL ! 0 _RSUBS-GENERATION !
    0 _RSUBH-E ! 0 _RSUBH-G ! 0 _RSUBH-O ! 0 _RSUBH-I !
    0 _RSUBSO-A ! 0 _RSUBSO-U ! 0 _RSUBSO-O !
    0 _RSUBF-A ! 0 _RSUBF-U ! 0 _RSUBF-LANE ! 0 _RSUBF-O !
    0 _RSUBF-E !
    0 _RSUBA-A ! 0 _RSUBA-U ! 0 _RSUBA-LANE ! 0 _RSUBA-CURSOR !
    0 _RSUBA-XT !
    0 _RSUBA-CONTEXT ! 0 _RSUBA-O ! 0 _RSUBA-I ! 0 _RSUBA-E !
    0 _RSUBA-G !
    0 _RSUBEVID-E ! 0 _RSUBEVID-G ! 0 _RSUBEVID-O !
    0 _RSUBEVID-I !
    0 _RSUBBD-B ! 0 _RSUBBD-O !
    0 _RSUBB-E ! 0 _RSUBB-G ! 0 _RSUBB-XA ! 0 _RSUBB-XU !
    0 _RSUBB-B ! 0 _RSUBB-O ! 0 _RSUBB-I ! 0 _RSUBB-RS !
    0 _RSUBB-OP ! 0 _RSUBB-OPG !
    0 _RSUBR-E ! 0 _RSUBR-G ! 0 _RSUBR-ACCEPT ! 0 _RSUBR-O !
    0 _RSUBR-I ! 0 _RSUBR-OPSTATE ! 0 _RSUBR-RS !
    0 _RSUBP-O ! 0 _RSUBP-FALLBACK-XT ! 0 _RSUBP-FALLBACK-CONTEXT !
    0 _RSUBP-F ! 0 _RSUBP-KIND ! 0 _RSUBP-LANE !
    0 _RSUBP-LANE-SEQ ! 0 _RSUBP-EXPECTED ! 0 _RSUBP-DISPOSITION !
    0 _RSUBP-CALL-CONTEXT ! 0 _RSUBP-TARGET-A ! 0 _RSUBP-TARGET-U !
    0 _RSUBP-BODY-A ! 0 _RSUBP-BODY-U ! 0 _RSUBP-EVENT-SEQ !
    0 _RSUBP-PRESENT ! 0 _RSUBP-MESSAGE-STATUS !
    0 _RSUBP-MATCH-E ! 0 _RSUBP-MATCH-I ! 0 _RSUBP-MATCH-G !
    0 _RSUBP-DELIVERY ! 0 _RSUBP-EVENT-STATUS !
    0 _RSUBP-DECISION ! 0 _RSUBP-THROW !
    0 _RSUBP-CLIENT-ITEM ! 0 _RSUBP-CLIENT-SUBJECT !
    0 _RSUBP-CLIENT-GENERATION ! 0 _RSUBP-CLIENT-STATUS !
    0 _RSUBP-OUT-ITEM ! 0 _RSUBP-OUT-SUBJECT !
    0 _RSUBP-OUT-GENERATION ! 0 _RSUBP-OUT-STATUS !
    0 _RSUBP-OUT-DETAIL ! 0 _RSUBP-BUSY !
    0 _RSUBP-BO ! 0 _RSUBP-BG ! 0 _RSUBP-BOwner !
    0 _RSUBD-O ! 0 _RSUBD-C ! 0 _RSUBD-E ! 0 _RSUBD-RS !
    0 _RSUBD-STATE !
    0 _RSUBLC-O ! 0 _RSUBLC-C ! 0 _RSUBLC-RS ! 0 _RSUBLC-CS !
    0 _RSUBLC-MS ! ;

VARIABLE _RSUBFIN-O
VARIABLE _RSUBFIN-EA
VARIABLE _RSUBFIN-EU
VARIABLE _RSUBFIN-TA
VARIABLE _RSUBFIN-TU
VARIABLE _RSUBFIN-VA
VARIABLE _RSUBFIN-VU

: RABBIT-SUBSCRIPTIONS-FINI  ( owner -- status )
    _RSUBP-BUSY @ IF DROP RSUB-S-STATE EXIT THEN
    DUP _RSUBFIN-O ! RABBIT-SUBSCRIPTIONS-BINDING-VALID? 0= IF
        0 _RSUBFIN-O ! RSUB-S-INVALID EXIT
    THEN
    _RSUBFIN-O @ RSUB.ENTRIES @ _RSUBFIN-EA !
    _RSUBFIN-O @ RSUB.CAPACITY @ RABBIT-SUBSCRIPTION-ENTRY-BYTES
        _RSUBFIN-EU !
    _RSUBFIN-O @ RSUB.TARGET-A @ _RSUBFIN-TA !
    _RSUBFIN-O @ RSUB.CAPACITY @
        _RSUBFIN-O @ RSUB.TARGET-SLOT-BYTES @ * _RSUBFIN-TU !
    _RSUBFIN-O @ RSUB.EVENT-A @ _RSUBFIN-VA !
    _RSUBFIN-O @ RSUB.CAPACITY @
        _RSUBFIN-O @ RSUB.EVENT-SLOT-BYTES @ * _RSUBFIN-VU !
    _RSUBFIN-EU @ IF _RSUBFIN-EA @ _RSUBFIN-EU @ 0 FILL THEN
    _RSUBFIN-TU @ IF _RSUBFIN-TA @ _RSUBFIN-TU @ 0 FILL THEN
    _RSUBFIN-VU @ IF _RSUBFIN-VA @ _RSUBFIN-VU @ 0 FILL THEN
    _RSUBFIN-O @ RABBIT-SUBSCRIPTIONS-SIZE 0 FILL
    0 _RSUBFIN-O ! 0 _RSUBFIN-EA ! 0 _RSUBFIN-EU !
    0 _RSUBFIN-TA ! 0 _RSUBFIN-TU ! 0 _RSUBFIN-VA ! 0 _RSUBFIN-VU !
    _RSUB-CLEAR-SCRATCH
    RSUB-S-OK ;
