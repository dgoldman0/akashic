\ =====================================================================
\  session.f - Caller-owned transport-neutral Rabbit session mechanics
\ =====================================================================
\  This module owns protocol session state, not a transport abstraction.
\  The caller injects one NET-IO-PORT and retains its callback/context
\  ownership.  Session open, cancel, and close go through NIO directly.
\
\  The caller also supplies two distinct writable arrays:
\
\    * RLANE-SIZE records for application lanes; and
\    * RTXN-SIZE records for pending request transactions.
\
\  Their capacities are caller choices.  Zero capacity is valid, and this
\  module has no fallback allocation, product maximum, or default credit.
\  Lane 0 is an inline control lane; application lane IDs are u16 values
\  1..65535.  Every new application lane starts with zero send credit and
\  zero receive credit granted to its peer.
\
\  RTXN records borrow the transaction-token slice.  The token bytes must
\  remain stable and readable from successful TXN-BEGIN until matching
\  TXN-COMPLETE, session cleanup, or close.  They must not alias the session
\  header or either mutable record array.  Cleanup clears the borrowed
\  pointer; it never frees or modifies the token bytes.
\
\  Seq here is only lane-local transport sequence.  Topic/application
\  Event-Seq does not appear in this module and must remain separate in the
\  Streams/application layer.
\
\  State is activation-local and caller-owned; there are no mutable module
\  globals.  One cooperative owner must serialize access to a session.
\  Frame parsing/encoding supplies decoded fields to these words later.
\ =====================================================================

PROVIDED akashic-rabbit-session

REQUIRE profile.f
REQUIRE ../io-port.f
REQUIRE ../../utils/memory-span.f

\ =====================================================================
\  Public statuses, roles, states, capabilities, and dispositions
\ =====================================================================

0  CONSTANT RABBIT-S-OK
1  CONSTANT RABBIT-S-INVALID
2  CONSTANT RABBIT-S-STATE
3  CONSTANT RABBIT-S-CAPABILITY
4  CONSTANT RABBIT-S-CAPACITY
5  CONSTANT RABBIT-S-NOT-FOUND
6  CONSTANT RABBIT-S-DUPLICATE
7  CONSTANT RABBIT-S-CREDIT
8  CONSTANT RABBIT-S-SEQUENCE
9  CONSTANT RABBIT-S-OVERFLOW
10 CONSTANT RABBIT-S-IO
11 CONSTANT RABBIT-S-PENDING
12 CONSTANT RABBIT-S-CANCELLED

1 CONSTANT RABBIT-ROLE-CLIENT
2 CONSTANT RABBIT-ROLE-SERVER

0 CONSTANT RABBIT-ST-READY
1 CONSTANT RABBIT-ST-OPENING
2 CONSTANT RABBIT-ST-HELLO
3 CONSTANT RABBIT-ST-HELLO-SENT
4 CONSTANT RABBIT-ST-ESTABLISHED
5 CONSTANT RABBIT-ST-CLOSING
6 CONSTANT RABBIT-ST-CLOSED
7 CONSTANT RABBIT-ST-FAILED

0 CONSTANT RABBIT-INBOUND-NONE
1 CONSTANT RABBIT-INBOUND-NEW
2 CONSTANT RABBIT-INBOUND-DUPLICATE
3 CONSTANT RABBIT-INBOUND-GAP

\ Rabbit's reference lane credit scalar is u32.  This is a wire scalar
\ bound, not a number of lanes, clients, queued frames, or product objects.
-1 1 RSHIFT  CONSTANT _RABBIT-CELL-MAX

\ =====================================================================
\  Exact application-lane record
\ =====================================================================
\  ID is stored in one native cell but is admitted only when it is a u16.
\  ID zero marks an unused application record.  The remaining fields are
\  lane transport state only; there is deliberately no Event-Seq field.
\  For NEXT-SEND and EXPECTED-RECV only, zero is the terminal sentinel after
\  sequence 2^64-1 has been consumed; it is never emitted as a wire Seq.

 0 CONSTANT _RLANE-ID
 8 CONSTANT _RLANE-NEXT-SEND
16 CONSTANT _RLANE-EXPECTED-RECV
24 CONSTANT _RLANE-ACKED
32 CONSTANT _RLANE-SEND-CREDIT
40 CONSTANT _RLANE-RECV-CREDIT
48 CONSTANT RLANE-SIZE

: RLANE.ID            ( lane-record -- a ) _RLANE-ID + ;
: RLANE.NEXT-SEND     ( lane-record -- a ) _RLANE-NEXT-SEND + ;
: RLANE.EXPECTED-RECV ( lane-record -- a ) _RLANE-EXPECTED-RECV + ;
: RLANE.ACKED         ( lane-record -- a ) _RLANE-ACKED + ;
: RLANE.SEND-CREDIT   ( lane-record -- a ) _RLANE-SEND-CREDIT + ;
: RLANE.RECV-CREDIT   ( lane-record -- a ) _RLANE-RECV-CREDIT + ;

: _RLANE-INIT  ( lane-id lane-record -- )
    >R
    R@ RLANE-SIZE 0 FILL
    DUP R@ RLANE.ID !
    1 R@ RLANE.NEXT-SEND !
    1 R@ RLANE.EXPECTED-RECV !
    DROP R> DROP ;

\ =====================================================================
\  Exact pending-transaction record
\ =====================================================================
\  TOKEN-A/U is a borrowed stable slice.  TOKEN-A zero marks a free entry.
\  Matching is byte-exact and keyed by both lane and token.

 0 CONSTANT _RTXN-LANE
 8 CONSTANT _RTXN-TOKEN-A
16 CONSTANT _RTXN-TOKEN-U
24 CONSTANT RTXN-SIZE

: RTXN.LANE    ( txn-entry -- a ) _RTXN-LANE + ;
: RTXN.TOKEN-A ( txn-entry -- a ) _RTXN-TOKEN-A + ;
: RTXN.TOKEN-U ( txn-entry -- a ) _RTXN-TOKEN-U + ;

\ =====================================================================
\  Caller-owned session header
\ =====================================================================

0x53534552 CONSTANT RSESS-MAGIC       \ "RESS"
2          CONSTANT RSESS-ABI-VERSION

  0 CONSTANT _RSESS-MAGIC
  8 CONSTANT _RSESS-ABI
 16 CONSTANT _RSESS-SIZE
 24 CONSTANT _RSESS-ROLE
 32 CONSTANT _RSESS-STATE
 40 CONSTANT _RSESS-LOCAL-CAPS
 48 CONSTANT _RSESS-PEER-CAPS
 56 CONSTANT _RSESS-AGREED-CAPS
 64 CONSTANT _RSESS-PORT
 72 CONSTANT _RSESS-LANES
 80 CONSTANT _RSESS-LANE-CAP
 88 CONSTANT _RSESS-TXNS
 96 CONSTANT _RSESS-TXN-CAP
104 CONSTANT _RSESS-FLAGS
112 CONSTANT _RSESS-CLOSE-STATUS
120 CONSTANT _RSESS-CONTROL-LANE      \ inline RLANE-SIZE
168 CONSTANT RABBIT-SESSION-SIZE

1 CONSTANT RSESS-F-CONFIGURED
2 CONSTANT RSESS-F-STORAGE-CLEANED

: RSESS.MAGIC        ( session -- a ) _RSESS-MAGIC + ;
: RSESS.ABI          ( session -- a ) _RSESS-ABI + ;
: RSESS.SIZE         ( session -- a ) _RSESS-SIZE + ;
: RSESS.ROLE         ( session -- a ) _RSESS-ROLE + ;
: RSESS.STATE        ( session -- a ) _RSESS-STATE + ;
: RSESS.LOCAL-CAPS   ( session -- a ) _RSESS-LOCAL-CAPS + ;
: RSESS.PEER-CAPS    ( session -- a ) _RSESS-PEER-CAPS + ;
: RSESS.AGREED-CAPS  ( session -- a ) _RSESS-AGREED-CAPS + ;
: RSESS.PORT         ( session -- a ) _RSESS-PORT + ;
: RSESS.LANES        ( session -- a ) _RSESS-LANES + ;
: RSESS.LANE-CAP     ( session -- a ) _RSESS-LANE-CAP + ;
: RSESS.TXNS         ( session -- a ) _RSESS-TXNS + ;
: RSESS.TXN-CAP      ( session -- a ) _RSESS-TXN-CAP + ;
: RSESS.FLAGS        ( session -- a ) _RSESS-FLAGS + ;
: RSESS.CLOSE-STATUS ( session -- a ) _RSESS-CLOSE-STATUS + ;
: RSESS.CONTROL      ( session -- lane-record ) _RSESS-CONTROL-LANE + ;

\ =====================================================================
\  Span and header validation
\ =====================================================================

: _RABBIT-ROLE?  ( role -- flag )
    DUP RABBIT-ROLE-CLIENT = SWAP RABBIT-ROLE-SERVER = OR ;

: _RABBIT-LANE-ID?  ( lane -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    RABBIT-LANE-MAX U> 0= ;

: _RABBIT-APP-LANE-ID?  ( lane -- flag )
    DUP 0> SWAP _RABBIT-LANE-ID? AND ;

: _RABBIT-CELL-ALIGNED?  ( address -- flag )
    7 AND 0= ;

: _RABBIT-ARRAY?  ( address count stride -- flag )
    >R
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    DUP _RABBIT-CELL-MAX R@ / U> IF 2DROP R> DROP 0 EXIT THEN
    DUP IF
        OVER 0= IF 2DROP R> DROP 0 EXIT THEN
        OVER _RABBIT-CELL-ALIGNED? 0= IF 2DROP R> DROP 0 EXIT THEN
    THEN
    R> *
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _RABBIT-SLICE?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

\ Inputs to these overlap helpers have already passed _RABBIT-ARRAY?.
: _RABBIT-ARRAY-FIXED-OVERLAP?
  ( array-a array-cap stride fixed-a fixed-u -- flag )
    >R >R * R> R> MSPAN-OVERLAP? ;

: _RABBIT-ARRAYS-OVERLAP?
  ( a1 cap1 stride1 a2 cap2 stride2 -- flag )
    * >R >R * R> R> MSPAN-OVERLAP? ;

: RABBIT-SESSION-VALID?  ( session -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _RABBIT-CELL-ALIGNED? 0= IF DROP 0 EXIT THEN
    DUP RABBIT-SESSION-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    >R
    R@ RSESS.MAGIC @ RSESS-MAGIC <> IF R> DROP 0 EXIT THEN
    R@ RSESS.ABI @ RSESS-ABI-VERSION <> IF R> DROP 0 EXIT THEN
    R@ RSESS.SIZE @ RABBIT-SESSION-SIZE <> IF R> DROP 0 EXIT THEN
    R@ RSESS.ROLE @ _RABBIT-ROLE? 0= IF R> DROP 0 EXIT THEN
    R@ RSESS.PORT @ DUP 0= IF DROP R> DROP 0 EXIT THEN
    DUP _RABBIT-CELL-ALIGNED? 0= IF DROP R> DROP 0 EXIT THEN
    DUP NET-IO-PORT-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    NET-IO-PORT-SIZE R@ RABBIT-SESSION-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R> DROP -1 ;

: RABBIT-SESSION-STATE@  ( session -- state|-1 )
    DUP RABBIT-SESSION-VALID? 0= IF DROP -1 EXIT THEN
    RSESS.STATE @ ;

: RABBIT-SESSION-ESTABLISHED?  ( session -- flag )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 0 EXIT THEN
    RSESS.STATE @ RABBIT-ST-ESTABLISHED = ;

: RABBIT-SESSION-AGREED-CAPS@  ( session -- flags )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 0 EXIT THEN
    RSESS.AGREED-CAPS @ ;

: RABBIT-SESSION-PORT@  ( session -- port|0 )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 0 EXIT THEN
    RSESS.PORT @ ;

: _RSESS-CAP?  ( mask session -- flag )
    >R DUP R> RSESS.AGREED-CAPS @ AND = ;

\ =====================================================================
\  Initialization and caller storage binding
\ =====================================================================
\  INIT publishes nothing on refusal.  The supplied NET-IO-PORT must already
\  have been initialized/configured by its owner; INIT does not NIO-INIT it.
\  A live session must be closed before the same header is reinitialized.

: RABBIT-SESSION-INIT  ( port role local-cap-flags session -- status )
    DUP 0= IF 2DROP 2DROP RABBIT-S-INVALID EXIT THEN
    DUP _RABBIT-CELL-ALIGNED? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    DUP RABBIT-SESSION-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    3 PICK DUP 0= SWAP NET-IO-PORT-SIZE MSPAN-NONWRAPPING? 0= OR IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    3 PICK _RABBIT-CELL-ALIGNED? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK _RABBIT-ROLE? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    1 PICK RABBIT-CAPS-KNOWN INVERT AND IF
        2DROP 2DROP RABBIT-S-CAPABILITY EXIT
    THEN
    3 PICK NET-IO-PORT-SIZE 2 PICK RABBIT-SESSION-SIZE
        MSPAN-OVERLAP? IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN

    >R
    R@ RABBIT-SESSION-SIZE 0 FILL
    RSESS-MAGIC R@ RSESS.MAGIC !
    RSESS-ABI-VERSION R@ RSESS.ABI !
    RABBIT-SESSION-SIZE R@ RSESS.SIZE !
    RABBIT-ST-READY R@ RSESS.STATE !
    RABBIT-S-OK R@ RSESS.CLOSE-STATUS !
    DUP R@ RSESS.LOCAL-CAPS ! DROP
    DUP R@ RSESS.ROLE ! DROP
    R@ RSESS.PORT !
    0 R@ RSESS.CONTROL _RLANE-INIT
    R> DROP RABBIT-S-OK ;

\ CONFIGURE binds and clears both arrays atomically after complete geometry
\ validation.  The arrays must be mutually disjoint and disjoint from the
\ session header and NET-IO-PORT.  A refused configuration changes neither
\ session nor arrays.  Configuration is allowed exactly once before OPEN.
: RABBIT-SESSION-CONFIGURE
  ( lane-a lane-cap txn-a txn-cap session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF
        DROP 2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    DUP RSESS.STATE @ RABBIT-ST-READY <> IF
        DROP 2DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    DUP RSESS.FLAGS @ RSESS-F-CONFIGURED AND IF
        DROP 2DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    >R

    3 PICK 3 PICK RLANE-SIZE _RABBIT-ARRAY? 0= IF
        2DROP 2DROP R> DROP RABBIT-S-INVALID EXIT
    THEN
    1 PICK 1 PICK RTXN-SIZE _RABBIT-ARRAY? 0= IF
        2DROP 2DROP R> DROP RABBIT-S-INVALID EXIT
    THEN
    3 PICK 3 PICK RLANE-SIZE 4 PICK 4 PICK RTXN-SIZE
        _RABBIT-ARRAYS-OVERLAP? IF
        2DROP 2DROP R> DROP RABBIT-S-INVALID EXIT
    THEN
    3 PICK 3 PICK RLANE-SIZE R@ RABBIT-SESSION-SIZE
        _RABBIT-ARRAY-FIXED-OVERLAP? IF
        2DROP 2DROP R> DROP RABBIT-S-INVALID EXIT
    THEN
    1 PICK 1 PICK RTXN-SIZE R@ RABBIT-SESSION-SIZE
        _RABBIT-ARRAY-FIXED-OVERLAP? IF
        2DROP 2DROP R> DROP RABBIT-S-INVALID EXIT
    THEN
    3 PICK 3 PICK RLANE-SIZE R@ RSESS.PORT @ NET-IO-PORT-SIZE
        _RABBIT-ARRAY-FIXED-OVERLAP? IF
        2DROP 2DROP R> DROP RABBIT-S-INVALID EXIT
    THEN
    1 PICK 1 PICK RTXN-SIZE R@ RSESS.PORT @ NET-IO-PORT-SIZE
        _RABBIT-ARRAY-FIXED-OVERLAP? IF
        2DROP 2DROP R> DROP RABBIT-S-INVALID EXIT
    THEN

    3 PICK 3 PICK RLANE-SIZE * 0 FILL
    1 PICK 1 PICK RTXN-SIZE * 0 FILL
    3 PICK R@ RSESS.LANES !
    2 PICK R@ RSESS.LANE-CAP !
    1 PICK R@ RSESS.TXNS !
    DUP R@ RSESS.TXN-CAP !
    RSESS-F-CONFIGURED R@ RSESS.FLAGS !
    2DROP 2DROP R> DROP RABBIT-S-OK ;

\ =====================================================================
\  Idempotent storage cleanup and NIO close/cancel
\ =====================================================================

: _RSESS-CLEAR-STORAGE  ( session -- )
    DUP RSESS.FLAGS @ RSESS-F-STORAGE-CLEANED AND IF DROP EXIT THEN
    DUP RSESS.FLAGS DUP @ RSESS-F-STORAGE-CLEANED OR SWAP !
    DUP RSESS.LANES @ OVER RSESS.LANE-CAP @ RLANE-SIZE * 0 FILL
    DUP RSESS.TXNS @ OVER RSESS.TXN-CAP @ RTXN-SIZE * 0 FILL
    DUP 0 SWAP RSESS.PEER-CAPS !
    DUP 0 SWAP RSESS.AGREED-CAPS !
    0 SWAP RSESS.CONTROL _RLANE-INIT ;

: _RSESS-CLOSE-PUBLISH  ( nio-status session -- status )
    >R
    DUP NIO-S-PENDING = IF
        DROP RABBIT-ST-CLOSING R@ RSESS.STATE !
        RABBIT-S-PENDING DUP R@ RSESS.CLOSE-STATUS !
        R> DROP EXIT
    THEN
    DUP NIO-S-OK = IF
        DROP RABBIT-ST-CLOSED R@ RSESS.STATE !
        RABBIT-S-OK DUP R@ RSESS.CLOSE-STATUS !
        R> DROP EXIT
    THEN
    DUP NIO-S-CANCELLED = IF
        DROP RABBIT-ST-CLOSED R@ RSESS.STATE !
        RABBIT-S-CANCELLED DUP R@ RSESS.CLOSE-STATUS !
        R> DROP EXIT
    THEN
    DROP RABBIT-ST-FAILED R@ RSESS.STATE !
    RABBIT-S-IO DUP R@ RSESS.CLOSE-STATUS !
    R> DROP ;

\ CLOSE invalidates all lane/transaction loans before asking NIO to close.
\ Repeated calls never clear twice and NIO itself guarantees callback-attempt
\ idempotence.  If an asynchronous close is pending, another CLOSE (or the
\ explicit CLOSE-POLL alias) polls it instead of starting a second close.
: RABBIT-SESSION-CLOSE  ( session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-CLOSED = IF
        RSESS.CLOSE-STATUS @ EXIT
    THEN
    DUP _RSESS-CLEAR-STORAGE
    DUP RSESS.STATE @ RABBIT-ST-CLOSING = IF
        DUP RSESS.PORT @ NIO-CLOSE-POLL SWAP _RSESS-CLOSE-PUBLISH EXIT
    THEN
    DUP RSESS.PORT @ NIO-CLOSE-START SWAP _RSESS-CLOSE-PUBLISH ;

: RABBIT-SESSION-CLOSE-POLL  ( session -- status )
    RABBIT-SESSION-CLOSE ;

\ CANCEL is the parse-failure/timeout/backpressure teardown path.  It uses
\ NIO-CANCEL directly, clears caller records once, and is idempotent through
\ both the session terminal state and NIO cleanup flags.
: RABBIT-SESSION-CANCEL  ( session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-CLOSED = IF
        RSESS.CLOSE-STATUS @ EXIT
    THEN
    DUP _RSESS-CLEAR-STORAGE
    DUP RSESS.PORT @ NIO-CANCEL SWAP _RSESS-CLOSE-PUBLISH ;

\ =====================================================================
\  NIO open and minimal fixture HELLO negotiation
\ =====================================================================

: _RSESS-OPEN-PUBLISH  ( nio-status session -- status )
    >R
    DUP NIO-S-OK = IF
        DROP RABBIT-ST-HELLO R@ RSESS.STATE !
        R> DROP RABBIT-S-OK EXIT
    THEN
    DUP NIO-S-PENDING = IF
        DROP RABBIT-ST-OPENING R@ RSESS.STATE !
        R> DROP RABBIT-S-PENDING EXIT
    THEN
    DUP NIO-S-CANCELLED = IF
        DROP R@ _RSESS-CLEAR-STORAGE
        RABBIT-ST-CLOSED R@ RSESS.STATE !
        RABBIT-S-CANCELLED R@ RSESS.CLOSE-STATUS !
        R> DROP RABBIT-S-CANCELLED EXIT
    THEN
    DROP RABBIT-ST-FAILED R@ RSESS.STATE !
    RABBIT-S-IO R@ RSESS.CLOSE-STATUS !
    R> DROP RABBIT-S-IO ;

: RABBIT-SESSION-OPEN  ( session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.FLAGS @ RSESS-F-CONFIGURED AND 0= IF
        DROP RABBIT-S-STATE EXIT
    THEN
    DUP RSESS.STATE @ DUP RABBIT-ST-HELLO =
        OVER RABBIT-ST-HELLO-SENT = OR
        OVER RABBIT-ST-ESTABLISHED = OR IF
        2DROP RABBIT-S-OK EXIT
    THEN
    RABBIT-ST-OPENING = IF
        DUP RSESS.PORT @ NIO-OPEN-POLL SWAP _RSESS-OPEN-PUBLISH EXIT
    THEN
    DUP RSESS.STATE @ RABBIT-ST-READY <> IF
        DROP RABBIT-S-STATE EXIT
    THEN
    DUP RSESS.PORT @ NIO-OPEN-START SWAP _RSESS-OPEN-PUBLISH ;

: RABBIT-SESSION-OPEN-POLL  ( session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-OPENING <> IF
        DROP RABBIT-S-STATE EXIT
    THEN
    DUP RSESS.PORT @ NIO-OPEN-POLL SWAP _RSESS-OPEN-PUBLISH ;

\ The client calls HELLO-BEGIN when it publishes its HELLO frame.  It returns
\ the exact local flags to encode.  A repeated begin is refused, preventing
\ an accidental second state transition or duplicate fixture HELLO.
: RABBIT-SESSION-HELLO-BEGIN  ( session -- offered-flags status )
    DUP RABBIT-SESSION-VALID? 0= IF
        DROP 0 RABBIT-S-INVALID EXIT
    THEN
    DUP RSESS.ROLE @ RABBIT-ROLE-CLIENT <> IF
        DROP 0 RABBIT-S-STATE EXIT
    THEN
    DUP RSESS.STATE @ RABBIT-ST-HELLO <> IF
        DROP 0 RABBIT-S-STATE EXIT
    THEN
    RABBIT-ST-HELLO-SENT OVER RSESS.STATE !
    RSESS.LOCAL-CAPS @ RABBIT-S-OK ;

\ HELLO-ACCEPT is deliberately the minimal anonymous fixture transition.
\ A server accepts a decoded client HELLO from HELLO state; a client accepts
\ a decoded 200 HELLO only after HELLO-BEGIN.  It stores known peer flags and
\ their exact intersection with local flags, then becomes ESTABLISHED.
\ Authentication/challenge and channel-binding state belong in later profile
\ work; this word must not be presented as a production security handshake.
: RABBIT-SESSION-HELLO-ACCEPT
  ( peer-cap-flags session -- agreed-flags status )
    DUP RABBIT-SESSION-VALID? 0= IF
        2DROP 0 RABBIT-S-INVALID EXIT
    THEN
    DUP RSESS.ROLE @ RABBIT-ROLE-CLIENT = IF
        DUP RSESS.STATE @ RABBIT-ST-HELLO-SENT <>
    ELSE
        DUP RSESS.ROLE @ RABBIT-ROLE-SERVER <>
        OVER RSESS.STATE @ RABBIT-ST-HELLO <> OR
    THEN IF
        2DROP 0 RABBIT-S-STATE EXIT
    THEN
    >R
    RABBIT-CAPS-KNOWN AND DUP R@ RSESS.PEER-CAPS !
    R@ RSESS.LOCAL-CAPS @ AND DUP R@ RSESS.AGREED-CAPS !
    RABBIT-ST-ESTABLISHED R@ RSESS.STATE !
    R> DROP RABBIT-S-OK ;

\ =====================================================================
\  Lane lookup and opening
\ =====================================================================

: _RSESS-APP-LANE@  ( lane-id session -- lane-record|0 )
    >R
    R@ RSESS.LANES @ R> RSESS.LANE-CAP @
    BEGIN DUP 0> WHILE
        OVER RLANE.ID @ 3 PICK = IF
            DROP NIP EXIT
        THEN
        1- SWAP RLANE-SIZE + SWAP
    REPEAT
    2DROP DROP 0 ;

: _RSESS-EMPTY-LANE@  ( session -- lane-record|0 )
    DUP RSESS.LANES @ SWAP RSESS.LANE-CAP @
    BEGIN DUP 0> WHILE
        OVER RLANE.ID @ 0= IF DROP EXIT THEN
        1- SWAP RLANE-SIZE + SWAP
    REPEAT
    2DROP 0 ;

: _RSESS-LANE@  ( lane-id session -- lane-record|0 )
    OVER 0= IF NIP RSESS.CONTROL EXIT THEN
    _RSESS-APP-LANE@ ;

: RABBIT-SESSION-LANE@  ( lane-id session -- lane-record|0 )
    DUP RABBIT-SESSION-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER _RABBIT-LANE-ID? 0= IF 2DROP 0 EXIT THEN
    _RSESS-LANE@ ;

\ Application lane opening is transactional: duplicate, capacity, state,
\ and capability refusals do not alter any record.  Success initializes only
\ the chosen free record, with Seq counters at one, ACK at zero, and credit
\ at zero.  No fixture default can leak into product behavior.
: RABBIT-SESSION-APP-LANE-OPEN  ( lane-id session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF 2DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        2DROP RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
        2DROP RABBIT-S-CAPABILITY EXIT
    THEN
    OVER _RABBIT-APP-LANE-ID? 0= IF 2DROP RABBIT-S-INVALID EXIT THEN
    2DUP _RSESS-APP-LANE@ ?DUP IF
        DROP 2DROP RABBIT-S-DUPLICATE EXIT
    THEN
    DUP _RSESS-EMPTY-LANE@ ?DUP 0= IF
        2DROP RABBIT-S-CAPACITY EXIT
    THEN
    SWAP DROP _RLANE-INIT RABBIT-S-OK ;

\ =====================================================================
\  Credit, outbound reservation, cumulative ACK, and inbound disposition
\ =====================================================================

: _RLANE-CREDIT+  ( amount lane-record -- status )
    >R
    DUP 0= IF DROP R> DROP RABBIT-S-INVALID EXIT THEN
    DUP RABBIT-CREDIT-MAX U> IF DROP R> DROP RABBIT-S-OVERFLOW EXIT THEN
    R@ RLANE.SEND-CREDIT @
    RABBIT-CREDIT-MAX OVER - 2 PICK SWAP U> IF
        2DROP R> DROP RABBIT-S-OVERFLOW EXIT
    THEN
    + R@ RLANE.SEND-CREDIT !
    R> DROP RABBIT-S-OK ;

: _RLANE-RECV-CREDIT+  ( amount lane-record -- status )
    >R
    DUP 0= IF DROP R> DROP RABBIT-S-INVALID EXIT THEN
    DUP RABBIT-CREDIT-MAX U> IF DROP R> DROP RABBIT-S-OVERFLOW EXIT THEN
    R@ RLANE.RECV-CREDIT @
    RABBIT-CREDIT-MAX OVER - 2 PICK SWAP U> IF
        2DROP R> DROP RABBIT-S-OVERFLOW EXIT
    THEN
    + R@ RLANE.RECV-CREDIT !
    R> DROP RABBIT-S-OK ;

\ CREDIT+ is application-lane-only.  The entire add is checked before the
\ stored counter changes; zero, scalar overflow, and unknown lanes refuse
\ without mutation.
: RABBIT-SESSION-CREDIT+  ( lane-id amount session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 2DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
        DROP 2DROP RABBIT-S-CAPABILITY EXIT
    THEN
    2 PICK _RABBIT-APP-LANE-ID? 0= IF
        DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK 1 PICK _RSESS-APP-LANE@ ?DUP 0= IF
        DROP 2DROP RABBIT-S-NOT-FOUND EXIT
    THEN
    >R DROP NIP R> _RLANE-CREDIT+ ;

\ GRANT-CREDIT records credit that this endpoint has staged for its peer.
\ A later NEW inbound delivery consumes exactly one grant at COMMIT; staging
\ failure must occur before this mutation so unsent credit is never recorded.
: RABBIT-SESSION-GRANT-CREDIT  ( lane-id amount session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 2DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
        DROP 2DROP RABBIT-S-CAPABILITY EXIT
    THEN
    2 PICK _RABBIT-APP-LANE-ID? 0= IF
        DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK 1 PICK _RSESS-APP-LANE@ ?DUP 0= IF
        DROP 2DROP RABBIT-S-NOT-FOUND EXIT
    THEN
    >R DROP NIP R> _RLANE-RECV-CREDIT+ ;

: _RLANE-NEXT-SEND@  ( lane-record -- seq status )
    >R
    R@ RLANE.NEXT-SEND @ DUP 0= IF
        DROP R> DROP 0 RABBIT-S-OVERFLOW EXIT
    THEN
    R@ RLANE.SEND-CREDIT @ 0= IF
        DROP R> DROP 0 RABBIT-S-CREDIT EXIT
    THEN
    R> DROP RABBIT-S-OK ;

: _RLANE-RESERVE-SEND-EXACT  ( seq lane-record -- status )
    >R
    DUP 0= IF DROP R> DROP RABBIT-S-SEQUENCE EXIT THEN
    R@ RLANE.NEXT-SEND @ DUP 0= IF
        2DROP R> DROP RABBIT-S-OVERFLOW EXIT
    THEN
    2DUP <> IF
        2DROP R> DROP RABBIT-S-SEQUENCE EXIT
    THEN
    R@ RLANE.SEND-CREDIT @ 0= IF
        2DROP R> DROP RABBIT-S-CREDIT EXIT
    THEN
    NIP
    DUP RABBIT-U64-MAX = IF
        DROP 0 R@ RLANE.NEXT-SEND !
    ELSE
        1+ R@ RLANE.NEXT-SEND !
    THEN
    R@ RLANE.SEND-CREDIT DUP @ 1- SWAP !
    R> DROP RABBIT-S-OK ;

: _RLANE-RESERVE-SEND  ( lane-record -- seq status )
    DUP _RLANE-NEXT-SEND@ DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    DROP DUP >R SWAP _RLANE-RESERVE-SEND-EXACT
    R> SWAP ;

\ NEXT-SEND@ is a read-only admission decision.  A connection can encode the
\ returned sequence into caller-owned staging storage before it commits the
\ exact reservation; neither this word nor any refusal changes lane state.
: RABBIT-SESSION-NEXT-SEND@  ( lane-id session -- seq status )
    DUP RABBIT-SESSION-VALID? 0= IF 2DROP 0 RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        2DROP 0 RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
        2DROP 0 RABBIT-S-CAPABILITY EXIT
    THEN
    OVER _RABBIT-APP-LANE-ID? 0= IF
        2DROP 0 RABBIT-S-INVALID EXIT
    THEN
    2DUP _RSESS-APP-LANE@ ?DUP 0= IF
        2DROP 0 RABBIT-S-NOT-FOUND EXIT
    THEN
    >R 2DROP R> _RLANE-NEXT-SEND@ ;

\ RESERVE-SEND-EXACT is the mutation half of NEXT-SEND@.  It succeeds only
\ while expected-seq is still the lane's next sequence and send credit is
\ still available.  Every refusal leaves both fields unchanged.
: RABBIT-SESSION-RESERVE-SEND-EXACT
  ( lane-id expected-seq session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 2DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
        DROP 2DROP RABBIT-S-CAPABILITY EXIT
    THEN
    2 PICK _RABBIT-APP-LANE-ID? 0= IF
        DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK 1 PICK _RSESS-APP-LANE@ ?DUP 0= IF
        DROP 2DROP RABBIT-S-NOT-FOUND EXIT
    THEN
    >R DROP NIP R> _RLANE-RESERVE-SEND-EXACT ;

\ RESERVE-SEND is atomic with respect to refusal: it consumes exactly one
\ previously granted credit and advances Seq exactly once, or changes neither.
: RABBIT-SESSION-RESERVE-SEND  ( lane-id session -- seq status )
    DUP RABBIT-SESSION-VALID? 0= IF 2DROP 0 RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        2DROP 0 RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
        2DROP 0 RABBIT-S-CAPABILITY EXIT
    THEN
    OVER _RABBIT-APP-LANE-ID? 0= IF
        2DROP 0 RABBIT-S-INVALID EXIT
    THEN
    2DUP _RSESS-APP-LANE@ ?DUP 0= IF
        2DROP 0 RABBIT-S-NOT-FOUND EXIT
    THEN
    >R 2DROP R> _RLANE-RESERVE-SEND ;

: _RLANE-RESERVE-CONTROL  ( lane-record -- seq status )
    >R
    R@ RLANE.NEXT-SEND @ DUP 0= IF
        DROP R> DROP 0 RABBIT-S-OVERFLOW EXIT
    THEN
    DUP RABBIT-U64-MAX = IF
        0 R@ RLANE.NEXT-SEND !
    ELSE
        DUP 1+ R@ RLANE.NEXT-SEND !
    THEN
    R> DROP RABBIT-S-OK ;

\ Control traffic must be able to carry ACK/CREDIT/PING when every app lane
\ is credit-starved.  Its inline lane therefore has an explicit no-app-credit
\ reservation path; it does not manufacture credit for an application lane.
: RABBIT-SESSION-RESERVE-CONTROL  ( session -- seq status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 0 RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 0 RABBIT-S-STATE EXIT
    THEN
    RSESS.CONTROL _RLANE-RESERVE-CONTROL ;

: _RLANE-ACK  ( ack-seq lane-record -- status )
    >R
    DUP 0= IF DROP R> DROP RABBIT-S-SEQUENCE EXIT THEN
    R@ RLANE.NEXT-SEND @ DUP IF
        OVER SWAP U< 0= IF
            DROP R> DROP RABBIT-S-SEQUENCE EXIT
        THEN
    ELSE
        DROP
    THEN
    DUP R@ RLANE.ACKED @ U> IF
        R@ RLANE.ACKED !
    ELSE
        DROP
    THEN
    R> DROP RABBIT-S-OK ;

\ ACK is cumulative and monotonic, may acknowledge only an actually reserved
\ Seq, and never changes send credit.  Stale ACKs are successful no-ops.
: RABBIT-SESSION-ACK  ( lane-id ack-seq session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 2DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    2 PICK _RABBIT-LANE-ID? 0= IF DROP 2DROP RABBIT-S-INVALID EXIT THEN
    2 PICK 0<> IF
        RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
            DROP 2DROP RABBIT-S-CAPABILITY EXIT
        THEN
    THEN
    2 PICK 1 PICK _RSESS-LANE@ ?DUP 0= IF
        DROP 2DROP RABBIT-S-NOT-FOUND EXIT
    THEN
    >R DROP NIP R> _RLANE-ACK ;

: _RLANE-INBOUND-CLASSIFY
  ( seq lane-record -- expected disposition status )
    >R
    R@ RLANE.EXPECTED-RECV @
    DUP 0= IF
        NIP RABBIT-INBOUND-DUPLICATE RABBIT-S-OK
        R> DROP EXIT
    THEN
    2DUP = IF
        R@ RLANE.ID @ 0<> IF
            R@ RLANE.RECV-CREDIT @ 0= IF
                NIP RABBIT-INBOUND-NEW RABBIT-S-CREDIT
                R> DROP EXIT
            THEN
        THEN
        NIP RABBIT-INBOUND-NEW RABBIT-S-OK
        R> DROP EXIT
    THEN
    2DUP U< IF
        NIP RABBIT-INBOUND-DUPLICATE RABBIT-S-OK
        R> DROP EXIT
    THEN
    NIP RABBIT-INBOUND-GAP RABBIT-S-OK
    R> DROP ;

: _RLANE-INBOUND-COMMIT  ( seq lane-record -- status )
    >R
    DUP 0= IF DROP R> DROP RABBIT-S-SEQUENCE EXIT THEN
    R@ RLANE.EXPECTED-RECV @ DUP 0= IF
        2DROP R> DROP RABBIT-S-OVERFLOW EXIT
    THEN
    2DUP <> IF
        2DROP R> DROP RABBIT-S-SEQUENCE EXIT
    THEN
    R@ RLANE.ID @ 0<> IF
        R@ RLANE.RECV-CREDIT @ 0= IF
            2DROP R> DROP RABBIT-S-CREDIT EXIT
        THEN
    THEN
    NIP
    DUP RABBIT-U64-MAX = IF
        DROP 0 R@ RLANE.EXPECTED-RECV !
    ELSE
        1+ R@ RLANE.EXPECTED-RECV !
    THEN
    R@ RLANE.ID @ 0<> IF
        R@ RLANE.RECV-CREDIT DUP @ 1- SWAP !
    THEN
    R> DROP RABBIT-S-OK ;

: _RLANE-INBOUND  ( seq lane-record -- expected disposition status )
    OVER >R
    DUP >R
    _RLANE-INBOUND-CLASSIFY
    DUP IF
        R> DROP R> DROP EXIT
    THEN
    DROP
    DUP RABBIT-INBOUND-NEW <> IF
        R> DROP R> DROP RABBIT-S-OK EXIT
    THEN
    R> R> SWAP _RLANE-INBOUND-COMMIT ;

\ INBOUND-CLASSIFY is read-only.  NEW/OK means that payload admission may run;
\ NEW/CREDIT means that the peer has no unconsumed receive grant.  Terminal
\ lanes classify all representable retransmissions as duplicates.
: RABBIT-SESSION-INBOUND-CLASSIFY
  ( lane-id seq session -- expected disposition status )
    DUP RABBIT-SESSION-VALID? 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-INVALID EXIT
    THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-STATE EXIT
    THEN
    2 PICK _RABBIT-LANE-ID? 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-INVALID EXIT
    THEN
    OVER 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-SEQUENCE EXIT
    THEN
    2 PICK 0<> IF
        RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
            DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-CAPABILITY EXIT
        THEN
    THEN
    2 PICK 1 PICK _RSESS-LANE@ ?DUP 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-NOT-FOUND EXIT
    THEN
    >R DROP NIP R> _RLANE-INBOUND-CLASSIFY ;

\ INBOUND-COMMIT is the exact mutation half.  A connection invokes it only
\ after accepting a NEW payload; a stale decision, missing grant, or terminal
\ lane refuses without advancing expected Seq or consuming receive credit.
: RABBIT-SESSION-INBOUND-COMMIT  ( lane-id seq session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF DROP 2DROP RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    2 PICK _RABBIT-LANE-ID? 0= IF DROP 2DROP RABBIT-S-INVALID EXIT THEN
    OVER 0= IF DROP 2DROP RABBIT-S-SEQUENCE EXIT THEN
    2 PICK 0<> IF
        RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
            DROP 2DROP RABBIT-S-CAPABILITY EXIT
        THEN
    THEN
    2 PICK 1 PICK _RSESS-LANE@ ?DUP 0= IF
        DROP 2DROP RABBIT-S-NOT-FOUND EXIT
    THEN
    >R DROP NIP R> _RLANE-INBOUND-COMMIT ;

\ Convenience admission retains the original combined surface, but it is now
\ implemented through the same read-only decision and exact mutation core.
\ DUPLICATE and GAP remain successful no-ops; only NEW/OK commits state.
: RABBIT-SESSION-INBOUND
  ( lane-id seq session -- expected disposition status )
    DUP RABBIT-SESSION-VALID? 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-INVALID EXIT
    THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-STATE EXIT
    THEN
    2 PICK _RABBIT-LANE-ID? 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-INVALID EXIT
    THEN
    OVER 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-SEQUENCE EXIT
    THEN
    2 PICK 0<> IF
        RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
            DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-CAPABILITY EXIT
        THEN
    THEN
    2 PICK 1 PICK _RSESS-LANE@ ?DUP 0= IF
        DROP 2DROP 0 RABBIT-INBOUND-NONE RABBIT-S-NOT-FOUND EXIT
    THEN
    >R DROP NIP R> _RLANE-INBOUND ;

\ Receive-credit inspection is read-only and application-lane-only.  It lets
\ the connection verify grant publication and refusal atomicity without
\ exposing a second source of truth.
: RABBIT-SESSION-RECV-CREDIT@
  ( lane-id session -- amount status )
    DUP RABBIT-SESSION-VALID? 0= IF 2DROP 0 RABBIT-S-INVALID EXIT THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        2DROP 0 RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-LANES OVER _RSESS-CAP? 0= IF
        2DROP 0 RABBIT-S-CAPABILITY EXIT
    THEN
    OVER _RABBIT-APP-LANE-ID? 0= IF
        2DROP 0 RABBIT-S-INVALID EXIT
    THEN
    2DUP _RSESS-APP-LANE@ ?DUP 0= IF
        2DROP 0 RABBIT-S-NOT-FOUND EXIT
    THEN
    >R 2DROP R> RLANE.RECV-CREDIT @ RABBIT-S-OK ;

\ =====================================================================
\  Exact (lane, transaction-token) pending transaction table
\ =====================================================================

: _RTXN-MATCH?  ( lane-id token-a token-u txn-entry -- flag )
    >R
    2 PICK R@ RTXN.LANE @ <> IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DUP R@ RTXN.TOKEN-U @ <> IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    ROT DROP R@ RTXN.TOKEN-A @ R> RTXN.TOKEN-U @ COMPARE 0= ;

: _RSESS-TXN-FIND
  ( lane-id token-a token-u session -- txn-entry|0 )
    >R
    R@ RSESS.TXNS @ R> RSESS.TXN-CAP @
    BEGIN DUP 0> WHILE
        1 PICK >R
        4 PICK 4 PICK 4 PICK R@ _RTXN-MATCH? IF
            2DROP 2DROP DROP R> EXIT
        THEN
        R> DROP
        1- SWAP RTXN-SIZE + SWAP
    REPEAT
    2DROP 2DROP DROP 0 ;

: _RSESS-EMPTY-TXN@  ( session -- txn-entry|0 )
    DUP RSESS.TXNS @ SWAP RSESS.TXN-CAP @
    BEGIN DUP 0> WHILE
        OVER RTXN.TOKEN-A @ 0= IF DROP EXIT THEN
        1- SWAP RTXN-SIZE + SWAP
    REPEAT
    2DROP 0 ;

: _RSESS-TOKEN-DISJOINT?  ( token-a token-u session -- flag )
    >R
    2DUP R@ RABBIT-SESSION-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DUP R@ RSESS.LANES @ R@ RSESS.LANE-CAP @ RLANE-SIZE *
        MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DUP R@ RSESS.TXNS @ R@ RSESS.TXN-CAP @ RTXN-SIZE *
        MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DUP R@ RSESS.PORT @ NET-IO-PORT-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 EXIT
    THEN
    2DROP R> DROP -1 ;

\ TXN-BEGIN validates state, async negotiation, lane existence, exact-key
\ uniqueness, and capacity before publishing the borrowed token pointer.
\ Every refusal leaves the complete transaction table unchanged.
: RABBIT-SESSION-TXN-BEGIN
  ( lane-id token-a token-u session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        2DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-ASYNC OVER _RSESS-CAP? 0= IF
        2DROP 2DROP RABBIT-S-CAPABILITY EXIT
    THEN
    3 PICK _RABBIT-LANE-ID? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK 2 PICK _RABBIT-SLICE? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK 2 PICK 2 PICK _RSESS-TOKEN-DISJOINT? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    3 PICK 1 PICK _RSESS-LANE@ 0= IF
        2DROP 2DROP RABBIT-S-NOT-FOUND EXIT
    THEN
    3 PICK 3 PICK 3 PICK 3 PICK _RSESS-TXN-FIND ?DUP IF
        DROP 2DROP 2DROP RABBIT-S-DUPLICATE EXIT
    THEN
    DUP _RSESS-EMPTY-TXN@ ?DUP 0= IF
        2DROP 2DROP RABBIT-S-CAPACITY EXIT
    THEN
    >R DROP
    2 PICK R@ RTXN.LANE !
    1 PICK R@ RTXN.TOKEN-A !
    DUP R@ RTXN.TOKEN-U !
    2DROP DROP R> DROP RABBIT-S-OK ;

: RABBIT-SESSION-TXN-PENDING?
  ( lane-id token-a token-u session -- flag )
    DUP RABBIT-SESSION-VALID? 0= IF 2DROP 2DROP 0 EXIT THEN
    2 PICK 2 PICK _RABBIT-SLICE? 0= IF 2DROP 2DROP 0 EXIT THEN
    2 PICK 2 PICK 2 PICK _RSESS-TOKEN-DISJOINT? 0= IF
        2DROP 2DROP 0 EXIT
    THEN
    _RSESS-TXN-FIND 0<> ;

\ TXN-COMPLETE removes only the exact (lane, token-bytes) entry.  Wrong-lane,
\ wrong-token, and missing completions are refusal/no-op outcomes; no other
\ pending transaction can be consumed accidentally.
: RABBIT-SESSION-TXN-COMPLETE
  ( lane-id token-a token-u session -- status )
    DUP RABBIT-SESSION-VALID? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    DUP RSESS.STATE @ RABBIT-ST-ESTABLISHED <> IF
        2DROP 2DROP RABBIT-S-STATE EXIT
    THEN
    RABBIT-CAP-F-ASYNC OVER _RSESS-CAP? 0= IF
        2DROP 2DROP RABBIT-S-CAPABILITY EXIT
    THEN
    3 PICK _RABBIT-LANE-ID? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK 2 PICK _RABBIT-SLICE? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    2 PICK 2 PICK 2 PICK _RSESS-TOKEN-DISJOINT? 0= IF
        2DROP 2DROP RABBIT-S-INVALID EXIT
    THEN
    _RSESS-TXN-FIND ?DUP 0= IF
        RABBIT-S-NOT-FOUND EXIT
    THEN
    RTXN-SIZE 0 FILL RABBIT-S-OK ;
