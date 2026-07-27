\ =====================================================================
\  token-set.f - Caller-owned opaque OAuth 2 token ownership
\ =====================================================================
\  A token set owns bounded access, refresh, and optional identity-token
\  bytes.  Tokens are opaque: this module does not decode JWTs or impose
\  provider policy.
\
\  Every published object contains its own spin guard and replacement
\  staging area.  Independent objects can therefore operate concurrently
\  without module-owned mutable state.  Mutations qualify every complete
\  caller span and reject source/object aliases before acquiring the guard.
\
\  Refresh launch is a generation-bound, caller-owned lease transaction:
\    O2TOK-REFRESH-LEASE-INIT
\    O2TOK-REFRESH-BEGIN
\    O2TOK-WITH-REFRESH-LEASE
\    O2TOK-REFRESH-COMMIT
\    O2TOK-REFRESH-ABORT
\  A descriptor binds the owner object, generation, and per-object nonce.
\  Only one lease may be active, and its refresh token may be borrowed once.
\  A callback THROW releases the guard but deliberately leaves that lease
\  active and consumed; only explicit COMMIT, ABORT, or CLEAR resolves it.
\ =====================================================================

PROVIDED akashic-oauth2-tokens

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../../concurrency/guard.f

\ =====================================================================
\  Public capacities and status vocabulary
\ =====================================================================

0  CONSTANT O2TOK-S-OK
1  CONSTANT O2TOK-S-INVALID
2  CONSTANT O2TOK-S-CAPACITY
3  CONSTANT O2TOK-S-ABSENT
4  CONSTANT O2TOK-S-BUSY
5  CONSTANT O2TOK-S-CALLBACK
6  CONSTANT O2TOK-S-ALIAS
7  CONSTANT O2TOK-S-STALE
8  CONSTANT O2TOK-S-RANGE
9  CONSTANT O2TOK-S-PROTECTED
10 CONSTANT O2TOK-S-PLATFORM

: O2TOK-STATUS-VALID?  ( status -- flag )
    DUP O2TOK-S-OK >= SWAP O2TOK-S-PLATFORM <= AND ;

8192 CONSTANT O2TOK-ACCESS-CAPACITY
4096 CONSTANT O2TOK-REFRESH-CAPACITY
8192 CONSTANT O2TOK-ID-CAPACITY
32   CONSTANT OAUTH2-REFRESH-LEASE-SIZE

\ =====================================================================
\  Caller-owned object layout
\ =====================================================================

0x4F32544F4B534554 CONSTANT _O2TOK-MAGIC-VALUE

  0 CONSTANT _O2T-MAGIC
  8 CONSTANT _O2T-GUARD
 40 CONSTANT _O2T-ACCESS-U
 48 CONSTANT _O2T-REFRESH-U
 56 CONSTANT _O2T-ID-U
 64 CONSTANT _O2T-EXPIRES-MS
 72 CONSTANT _O2T-GENERATION
 80 CONSTANT _O2T-USES
 88 CONSTANT _O2T-BORROWED
 96 CONSTANT _O2T-LEASE-SEQUENCE
104 CONSTANT _O2T-LEASE-ID
112 CONSTANT _O2T-LEASE-GENERATION
120 CONSTANT _O2T-LEASE-USED

\ Transient operation geometry is stored in the guarded caller object, not
\ in module variables.  It is cleared after every completed mutation.
128 CONSTANT _O2T-OP-ID-A
136 CONSTANT _O2T-OP-ID-U
144 CONSTANT _O2T-OP-ACCESS-A
152 CONSTANT _O2T-OP-ACCESS-U
160 CONSTANT _O2T-OP-REFRESH-A
168 CONSTANT _O2T-OP-REFRESH-U
176 CONSTANT _O2T-OP-EXPIRES
184 CONSTANT _O2T-OP-LEASE
192 CONSTANT _O2T-OP-MODE

200 CONSTANT _O2T-STAGE-ID-U
208 CONSTANT _O2T-STAGE-ACCESS-U
216 CONSTANT _O2T-STAGE-REFRESH-U
224 CONSTANT _O2T-STAGE-EXPIRES
232 CONSTANT _O2T-LEASE-DESC

256 CONSTANT _O2T-ACCESS
_O2T-ACCESS O2TOK-ACCESS-CAPACITY + CONSTANT _O2T-REFRESH
_O2T-REFRESH O2TOK-REFRESH-CAPACITY + CONSTANT _O2T-ID
_O2T-ID O2TOK-ID-CAPACITY + CONSTANT _O2T-STAGE-ACCESS
_O2T-STAGE-ACCESS O2TOK-ACCESS-CAPACITY + CONSTANT _O2T-STAGE-REFRESH
_O2T-STAGE-REFRESH O2TOK-REFRESH-CAPACITY + CONSTANT _O2T-STAGE-ID
_O2T-STAGE-ID O2TOK-ID-CAPACITY + CONSTANT OAUTH2-TOKEN-SET-SIZE

1 CONSTANT _O2TOK-MODE-SET
2 CONSTANT _O2TOK-MODE-COMMIT

0x4F324C4541534531 CONSTANT _O2LEASE-MAGIC-VALUE

 0 CONSTANT _O2L-MAGIC
 8 CONSTANT _O2L-OWNER
16 CONSTANT _O2L-GENERATION
24 CONSTANT _O2L-ID

: _O2TOK.MAGIC             ( tokens -- a ) _O2T-MAGIC + ;
: _O2TOK.GUARD             ( tokens -- guard ) _O2T-GUARD + ;
: O2TOK.ACCESS-U           ( tokens -- a ) _O2T-ACCESS-U + ;
: _O2TOK.REFRESH-U         ( tokens -- a ) _O2T-REFRESH-U + ;
: O2TOK.ID-U               ( tokens -- a ) _O2T-ID-U + ;
: O2TOK.EXPIRES-MS         ( tokens -- a ) _O2T-EXPIRES-MS + ;
: O2TOK.GENERATION         ( tokens -- a ) _O2T-GENERATION + ;
: O2TOK.USES               ( tokens -- a ) _O2T-USES + ;
: O2TOK.BORROWED           ( tokens -- a ) _O2T-BORROWED + ;
: _O2TOK.LEASE-SEQUENCE    ( tokens -- a ) _O2T-LEASE-SEQUENCE + ;
: _O2TOK.LEASE-ID          ( tokens -- a ) _O2T-LEASE-ID + ;
: _O2TOK.LEASE-GENERATION  ( tokens -- a ) _O2T-LEASE-GENERATION + ;
: _O2TOK.LEASE-USED        ( tokens -- a ) _O2T-LEASE-USED + ;

: _O2TOK.OP-ID-A           ( tokens -- a ) _O2T-OP-ID-A + ;
: _O2TOK.OP-ID-U           ( tokens -- a ) _O2T-OP-ID-U + ;
: _O2TOK.OP-ACCESS-A       ( tokens -- a ) _O2T-OP-ACCESS-A + ;
: _O2TOK.OP-ACCESS-U       ( tokens -- a ) _O2T-OP-ACCESS-U + ;
: _O2TOK.OP-REFRESH-A      ( tokens -- a ) _O2T-OP-REFRESH-A + ;
: _O2TOK.OP-REFRESH-U      ( tokens -- a ) _O2T-OP-REFRESH-U + ;
: _O2TOK.OP-EXPIRES        ( tokens -- a ) _O2T-OP-EXPIRES + ;
: _O2TOK.OP-LEASE          ( tokens -- a ) _O2T-OP-LEASE + ;
: _O2TOK.OP-MODE           ( tokens -- a ) _O2T-OP-MODE + ;

: _O2TOK.STAGE-ID-U        ( tokens -- a ) _O2T-STAGE-ID-U + ;
: _O2TOK.STAGE-ACCESS-U    ( tokens -- a ) _O2T-STAGE-ACCESS-U + ;
: _O2TOK.STAGE-REFRESH-U   ( tokens -- a ) _O2T-STAGE-REFRESH-U + ;
: _O2TOK.STAGE-EXPIRES     ( tokens -- a ) _O2T-STAGE-EXPIRES + ;
: _O2TOK.LEASE-DESC        ( tokens -- a ) _O2T-LEASE-DESC + ;

: O2TOK.ACCESS             ( tokens -- a ) _O2T-ACCESS + ;
: _O2TOK.REFRESH           ( tokens -- a ) _O2T-REFRESH + ;
: O2TOK.ID                 ( tokens -- a ) _O2T-ID + ;
: _O2TOK.STAGE-ACCESS      ( tokens -- a ) _O2T-STAGE-ACCESS + ;
: _O2TOK.STAGE-REFRESH     ( tokens -- a ) _O2T-STAGE-REFRESH + ;
: _O2TOK.STAGE-ID          ( tokens -- a ) _O2T-STAGE-ID + ;

: _O2LEASE.MAGIC           ( lease -- a ) _O2L-MAGIC + ;
: _O2LEASE.OWNER           ( lease -- a ) _O2L-OWNER + ;
: _O2LEASE.GENERATION      ( lease -- a ) _O2L-GENERATION + ;
: _O2LEASE.ID              ( lease -- a ) _O2L-ID + ;

\ =====================================================================
\  Caller admission, initialization, and locking
\ =====================================================================

: _O2TOK-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP O2TOK-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP O2TOK-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP O2TOK-S-PROTECTED EXIT
    THEN
    DROP O2TOK-S-PLATFORM ;

: _O2TOK-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _O2TOK-CALLER>STATUS ;

: _O2LEASE-INITIALIZED?  ( lease -- flag )
    _O2LEASE.MAGIC @ _O2LEASE-MAGIC-VALUE = ;

: _O2LEASE-FREE?  ( lease -- flag )
    DUP _O2LEASE-INITIALIZED? 0= IF DROP 0 EXIT THEN
    DUP _O2LEASE.OWNER @ 0=
    OVER _O2LEASE.GENERATION @ 0= AND
    SWAP _O2LEASE.ID @ 0= AND ;

: _O2LEASE-CLEAR  ( lease -- )
    0 OVER _O2LEASE.OWNER !
    0 OVER _O2LEASE.GENERATION !
    0 SWAP _O2LEASE.ID ! ;

: O2TOK-REFRESH-LEASE-INIT?  ( lease -- status )
    DUP OAUTH2-REFRESH-LEASE-SIZE _O2TOK-ADMIT-SPAN
    DUP IF NIP EXIT THEN
    DROP
    DUP _O2LEASE-INITIALIZED? IF
        DUP _O2LEASE-FREE? 0= IF
            DROP O2TOK-S-BUSY EXIT
        THEN
    THEN
    DUP OAUTH2-REFRESH-LEASE-SIZE 0 FILL
    _O2LEASE-MAGIC-VALUE SWAP _O2LEASE.MAGIC !
    O2TOK-S-OK ;

\ Initialization requires exclusive descriptor ownership.
: O2TOK-REFRESH-LEASE-INIT  ( lease -- )
    O2TOK-REFRESH-LEASE-INIT? DROP ;

: _O2TOK-INITIALIZED?  ( tokens -- flag )
    DUP _O2TOK.MAGIC @ _O2TOK-MAGIC-VALUE =
    SWAP _O2TOK.GUARD GUARD-SPIN? AND ;

: _O2TOK-OBJECT-STATUS  ( tokens -- status )
    DUP OAUTH2-TOKEN-SET-SIZE _O2TOK-ADMIT-SPAN
    DUP IF NIP EXIT THEN
    DROP
    _O2TOK-INITIALIZED? IF O2TOK-S-OK ELSE O2TOK-S-INVALID THEN ;

: _O2TOK-LEASE-DESC-STATUS  ( lease tokens -- status )
    >R
    DUP OAUTH2-REFRESH-LEASE-SIZE _O2TOK-ADMIT-SPAN
    ?DUP IF
        NIP R> DROP EXIT
    THEN
    DUP OAUTH2-REFRESH-LEASE-SIZE
    R@ OAUTH2-TOKEN-SET-SIZE MSPAN-OVERLAP? IF
        DROP R> DROP O2TOK-S-ALIAS EXIT
    THEN
    DUP _O2LEASE-INITIALIZED? 0= IF
        DROP R> DROP O2TOK-S-INVALID EXIT
    THEN
    DROP R> DROP O2TOK-S-OK ;

: _O2TOK-BOUNDED-LENGTH?  ( length capacity -- flag )
    OVER 0< IF 2DROP 0 EXIT THEN
    U> 0= ;

: _O2TOK-LEASE-FLAG?  ( value -- flag )
    DUP 0= SWAP -1 = OR ;

: _O2TOK-STATE-VALID?  ( tokens -- flag )
    DUP O2TOK.ACCESS-U @ O2TOK-ACCESS-CAPACITY
        _O2TOK-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP _O2TOK.REFRESH-U @ O2TOK-REFRESH-CAPACITY
        _O2TOK-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP O2TOK.ID-U @ O2TOK-ID-CAPACITY
        _O2TOK-BOUNDED-LENGTH? 0= IF DROP 0 EXIT THEN
    DUP O2TOK.GENERATION @ 0= IF DROP 0 EXIT THEN
    DUP O2TOK.BORROWED @ _O2TOK-LEASE-FLAG? 0= IF DROP 0 EXIT THEN
    DUP _O2TOK.LEASE-USED @ _O2TOK-LEASE-FLAG? 0= IF DROP 0 EXIT THEN
    DUP _O2TOK.LEASE-ID @ 0= IF
        DUP _O2TOK.LEASE-GENERATION @ 0=
        OVER _O2TOK.LEASE-USED @ 0= AND
        SWAP _O2TOK.LEASE-DESC @ 0= AND EXIT
    THEN
    DUP _O2TOK.LEASE-DESC @ 0= IF DROP 0 EXIT THEN
    DUP _O2TOK.LEASE-GENERATION @
    SWAP O2TOK.GENERATION @ = ;

: _O2TOK-UNLOCK  ( tokens -- )
    _O2TOK.GUARD GUARD-RELEASE ;

\ A successful result leaves the object's guard held.
: _O2TOK-LOCK  ( tokens -- status )
    DUP _O2TOK.GUARD GUARD-TRY-ACQUIRE 0= IF
        DROP O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK-STATE-VALID? 0= IF
        DUP _O2TOK-UNLOCK
        DROP O2TOK-S-INVALID EXIT
    THEN
    DROP O2TOK-S-OK ;

: O2TOK-INIT?  ( tokens -- status )
    DUP OAUTH2-TOKEN-SET-SIZE _O2TOK-ADMIT-SPAN
    DUP IF NIP EXIT THEN
    DROP
    DUP _O2TOK-INITIALIZED? IF
        DUP _O2TOK.LEASE-ID @ IF
            DROP O2TOK-S-BUSY EXIT
        THEN
    THEN
    DUP OAUTH2-TOKEN-SET-SIZE 0 FILL
    _O2TOK-MAGIC-VALUE OVER _O2TOK.MAGIC !
    1 OVER O2TOK.GENERATION !
    DROP O2TOK-S-OK ;

\ Initialization requires exclusive, unpublished storage.  O2TOK-INIT keeps
\ the established no-result surface; use O2TOK-INIT? when status reporting is
\ required.
: O2TOK-INIT  ( tokens -- )
    O2TOK-INIT? DROP ;

\ =====================================================================
\  Zeroization and coherent state helpers
\ =====================================================================

: _O2TOK-WIPE-LIVE  ( tokens -- )
    DUP O2TOK.ACCESS O2TOK-ACCESS-CAPACITY 0 FILL
    DUP _O2TOK.REFRESH O2TOK-REFRESH-CAPACITY 0 FILL
    DUP O2TOK.ID O2TOK-ID-CAPACITY 0 FILL
    0 OVER O2TOK.ACCESS-U !
    0 OVER _O2TOK.REFRESH-U !
    0 OVER O2TOK.ID-U !
    0 SWAP O2TOK.EXPIRES-MS ! ;

: _O2TOK-WIPE-STAGE  ( tokens -- )
    DUP _O2TOK.STAGE-ACCESS O2TOK-ACCESS-CAPACITY 0 FILL
    DUP _O2TOK.STAGE-REFRESH O2TOK-REFRESH-CAPACITY 0 FILL
    DUP _O2TOK.STAGE-ID O2TOK-ID-CAPACITY 0 FILL
    0 OVER _O2TOK.STAGE-ACCESS-U !
    0 OVER _O2TOK.STAGE-REFRESH-U !
    0 OVER _O2TOK.STAGE-ID-U !
    0 SWAP _O2TOK.STAGE-EXPIRES ! ;

: _O2TOK-CLEAR-OP  ( tokens -- )
    _O2T-OP-ID-A + 72 0 FILL ;

: _O2TOK-INVALIDATE-DESC  ( lease tokens -- )
    >R
    DUP OAUTH2-REFRESH-LEASE-SIZE _O2TOK-ADMIT-SPAN 0= IF
        DUP _O2LEASE-INITIALIZED? IF
            DUP _O2LEASE.OWNER @ R@ = IF
                DUP _O2LEASE-CLEAR
            THEN
        THEN
    THEN
    DROP R> DROP ;

: _O2TOK-CLEAR-LEASE  ( tokens -- )
    DUP _O2TOK.LEASE-DESC @ ?DUP IF
        OVER _O2TOK-INVALIDATE-DESC
    THEN
    0 OVER _O2TOK.LEASE-ID !
    0 OVER _O2TOK.LEASE-GENERATION !
    0 OVER _O2TOK.LEASE-USED !
    0 SWAP _O2TOK.LEASE-DESC ! ;

: _O2TOK-NEXT-NONZERO  ( cell-address -- value )
    DUP @ 1+ DUP 0= IF DROP 1 THEN
    DUP ROT ! ;

: _O2TOK-PRESENT-LOCKED?  ( tokens -- flag )
    O2TOK.ACCESS-U @ 0> ;

: O2TOK-CLEAR?  ( tokens -- status )
    DUP _O2TOK-OBJECT-STATUS ?DUP IF NIP EXIT THEN
    DUP _O2TOK-LOCK ?DUP IF NIP EXIT THEN
    DUP O2TOK.BORROWED @ IF
        DUP _O2TOK-UNLOCK
        DROP O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK-WIPE-LIVE
    DUP _O2TOK-WIPE-STAGE
    DUP _O2TOK-CLEAR-OP
    DUP _O2TOK-CLEAR-LEASE
    DUP O2TOK.GENERATION _O2TOK-NEXT-NONZERO DROP
    DUP _O2TOK-UNLOCK
    DROP O2TOK-S-OK ;

: O2TOK-CLEAR  ( tokens -- )
    O2TOK-CLEAR? DROP ;

: O2TOK-PRESENCE  ( tokens -- present? status )
    DUP _O2TOK-OBJECT-STATUS ?DUP IF
        NIP 0 SWAP EXIT
    THEN
    DUP _O2TOK-LOCK ?DUP IF
        NIP 0 SWAP EXIT
    THEN
    DUP _O2TOK-PRESENT-LOCKED?
    SWAP _O2TOK-UNLOCK
    O2TOK-S-OK ;

\ =====================================================================
\  Mutation geometry
\ =====================================================================

: _O2TOK-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _O2TOK-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _O2TOK-DROP8  ( eight-values -- )
    2DROP 2DROP 2DROP 2DROP ;

: _O2TOK-DROP9  ( nine-values -- )
    _O2TOK-DROP8 DROP ;

: _O2TOK-8DUP  ( eight-values -- the-same-eight-values twice )
    7 PICK 7 PICK 7 PICK 7 PICK
    7 PICK 7 PICK 7 PICK 7 PICK ;

: _O2TOK-9DUP  ( nine-values -- the-same-nine-values twice )
    8 PICK 8 PICK 8 PICK 8 PICK 8 PICK
    8 PICK 8 PICK 8 PICK 8 PICK ;

\ Validate the complete source span, its capacity, its required presence,
\ and its alias against the complete mutable token object.
: _O2TOK-SOURCE-STATUS
  ( address length capacity required? tokens -- status )
    >R >R >R
    2DUP _O2TOK-ADMIT-SPAN ?DUP IF
        R> DROP R> DROP R> DROP
        >R 2DROP R> EXIT
    THEN
    R>
    1 PICK SWAP U> IF
        2DROP R> DROP R> DROP O2TOK-S-CAPACITY EXIT
    THEN
    R> IF
        DUP 0= IF
            2DROP R> DROP O2TOK-S-ABSENT EXIT
        THEN
    THEN
    R> OAUTH2-TOKEN-SET-SIZE MSPAN-OVERLAP? IF
        O2TOK-S-ALIAS
    ELSE
        O2TOK-S-OK
    THEN ;

: _O2TOK-SET-GEOMETRY
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires tokens
  \   -- status )
    DUP _O2TOK-OBJECT-STATUS ?DUP IF
        >R _O2TOK-DROP8 R> EXIT
    THEN
    1 PICK 0< IF
        _O2TOK-DROP8 O2TOK-S-INVALID EXIT
    THEN
    7 PICK 7 PICK O2TOK-ID-CAPACITY 0 4 PICK
        _O2TOK-SOURCE-STATUS ?DUP IF
        >R _O2TOK-DROP8 R> EXIT
    THEN
    5 PICK 5 PICK O2TOK-ACCESS-CAPACITY -1 4 PICK
        _O2TOK-SOURCE-STATUS ?DUP IF
        >R _O2TOK-DROP8 R> EXIT
    THEN
    3 PICK 3 PICK O2TOK-REFRESH-CAPACITY 0 4 PICK
        _O2TOK-SOURCE-STATUS ?DUP IF
        >R _O2TOK-DROP8 R> EXIT
    THEN
    _O2TOK-DROP8 O2TOK-S-OK ;

: _O2TOK-LEASE-SOURCE-OVERLAP?
  ( address length lease -- flag )
    OAUTH2-REFRESH-LEASE-SIZE MSPAN-OVERLAP? ;

: _O2TOK-COMMIT-GEOMETRY
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires lease tokens
  \   -- status )
    DUP _O2TOK-OBJECT-STATUS ?DUP IF
        >R _O2TOK-DROP9 R> EXIT
    THEN
    1 PICK OVER _O2TOK-LEASE-DESC-STATUS ?DUP IF
        >R _O2TOK-DROP9 R> EXIT
    THEN
    2 PICK 0< IF
        _O2TOK-DROP9 O2TOK-S-INVALID EXIT
    THEN
    8 PICK 8 PICK O2TOK-ID-CAPACITY 0 4 PICK
        _O2TOK-SOURCE-STATUS ?DUP IF
        >R _O2TOK-DROP9 R> EXIT
    THEN
    8 PICK 8 PICK 3 PICK _O2TOK-LEASE-SOURCE-OVERLAP? IF
        _O2TOK-DROP9 O2TOK-S-ALIAS EXIT
    THEN
    6 PICK 6 PICK O2TOK-ACCESS-CAPACITY -1 4 PICK
        _O2TOK-SOURCE-STATUS ?DUP IF
        >R _O2TOK-DROP9 R> EXIT
    THEN
    6 PICK 6 PICK 3 PICK _O2TOK-LEASE-SOURCE-OVERLAP? IF
        _O2TOK-DROP9 O2TOK-S-ALIAS EXIT
    THEN
    4 PICK 4 PICK O2TOK-REFRESH-CAPACITY 0 4 PICK
        _O2TOK-SOURCE-STATUS ?DUP IF
        >R _O2TOK-DROP9 R> EXIT
    THEN
    4 PICK 4 PICK 3 PICK _O2TOK-LEASE-SOURCE-OVERLAP? IF
        _O2TOK-DROP9 O2TOK-S-ALIAS EXIT
    THEN
    _O2TOK-DROP9 O2TOK-S-OK ;

\ =====================================================================
\  Guarded staging and publication
\ =====================================================================

: _O2TOK-LOAD-OP8
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires tokens
  \   -- tokens )
    >R
    R@ _O2TOK.OP-EXPIRES !
    R@ _O2TOK.OP-REFRESH-U !
    R@ _O2TOK.OP-REFRESH-A !
    R@ _O2TOK.OP-ACCESS-U !
    R@ _O2TOK.OP-ACCESS-A !
    R@ _O2TOK.OP-ID-U !
    R@ _O2TOK.OP-ID-A !
    R> ;

: _O2TOK-LOAD-OP9
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires lease tokens
  \   -- tokens )
    >R
    R@ _O2TOK.OP-LEASE !
    R@ _O2TOK.OP-EXPIRES !
    R@ _O2TOK.OP-REFRESH-U !
    R@ _O2TOK.OP-REFRESH-A !
    R@ _O2TOK.OP-ACCESS-U !
    R@ _O2TOK.OP-ACCESS-A !
    R@ _O2TOK.OP-ID-U !
    R@ _O2TOK.OP-ID-A !
    R> ;

: _O2TOK-STAGE-ID  ( tokens -- )
    >R
    R@ _O2TOK.OP-ID-U @ IF
        R@ _O2TOK.OP-ID-A @ R@ _O2TOK.STAGE-ID
        R@ _O2TOK.OP-ID-U @ MOVE
        R@ _O2TOK.OP-ID-U @ R@ _O2TOK.STAGE-ID-U !
    ELSE
        R@ _O2TOK.OP-MODE @ _O2TOK-MODE-SET <> IF
            R@ O2TOK.ID R@ _O2TOK.STAGE-ID
            R@ O2TOK.ID-U @ MOVE
            R@ O2TOK.ID-U @ R@ _O2TOK.STAGE-ID-U !
        THEN
    THEN
    R> DROP ;

: _O2TOK-STAGE-ACCESS  ( tokens -- )
    >R
    R@ _O2TOK.OP-ACCESS-U @ IF
        R@ _O2TOK.OP-ACCESS-A @ R@ _O2TOK.STAGE-ACCESS
        R@ _O2TOK.OP-ACCESS-U @ MOVE
        R@ _O2TOK.OP-ACCESS-U @ R@ _O2TOK.STAGE-ACCESS-U !
    ELSE
        R@ _O2TOK.OP-MODE @ _O2TOK-MODE-SET <> IF
            R@ O2TOK.ACCESS R@ _O2TOK.STAGE-ACCESS
            R@ O2TOK.ACCESS-U @ MOVE
            R@ O2TOK.ACCESS-U @ R@ _O2TOK.STAGE-ACCESS-U !
        THEN
    THEN
    R> DROP ;

: _O2TOK-STAGE-REFRESH  ( tokens -- )
    >R
    R@ _O2TOK.OP-REFRESH-U @ IF
        R@ _O2TOK.OP-REFRESH-A @ R@ _O2TOK.STAGE-REFRESH
        R@ _O2TOK.OP-REFRESH-U @ MOVE
        R@ _O2TOK.OP-REFRESH-U @ R@ _O2TOK.STAGE-REFRESH-U !
    ELSE
        R@ _O2TOK.OP-MODE @ _O2TOK-MODE-SET <> IF
            R@ _O2TOK.REFRESH R@ _O2TOK.STAGE-REFRESH
            R@ _O2TOK.REFRESH-U @ MOVE
            R@ _O2TOK.REFRESH-U @ R@ _O2TOK.STAGE-REFRESH-U !
        THEN
    THEN
    R> DROP ;

: _O2TOK-STAGE-EXPIRY  ( tokens -- )
    DUP _O2TOK.OP-MODE @ _O2TOK-MODE-SET = IF
        DUP _O2TOK.OP-EXPIRES @
    ELSE
        DUP _O2TOK.OP-EXPIRES @ ?DUP 0= IF
            DUP O2TOK.EXPIRES-MS @
        THEN
    THEN
    SWAP _O2TOK.STAGE-EXPIRES ! ;

: _O2TOK-STAGE-ALL  ( tokens -- )
    DUP _O2TOK-WIPE-STAGE
    DUP _O2TOK-STAGE-ID
    DUP _O2TOK-STAGE-ACCESS
    DUP _O2TOK-STAGE-REFRESH
    _O2TOK-STAGE-EXPIRY ;

: _O2TOK-PUBLISH-STAGE  ( tokens -- )
    >R
    R@ _O2TOK-WIPE-LIVE

    R@ _O2TOK.STAGE-ACCESS R@ O2TOK.ACCESS
    R@ _O2TOK.STAGE-ACCESS-U @ MOVE
    R@ _O2TOK.STAGE-REFRESH R@ _O2TOK.REFRESH
    R@ _O2TOK.STAGE-REFRESH-U @ MOVE
    R@ _O2TOK.STAGE-ID R@ O2TOK.ID
    R@ _O2TOK.STAGE-ID-U @ MOVE

    R@ _O2TOK.STAGE-ACCESS-U @ R@ O2TOK.ACCESS-U !
    R@ _O2TOK.STAGE-REFRESH-U @ R@ _O2TOK.REFRESH-U !
    R@ _O2TOK.STAGE-ID-U @ R@ O2TOK.ID-U !
    R@ _O2TOK.STAGE-EXPIRES @ R@ O2TOK.EXPIRES-MS !
    R@ O2TOK.GENERATION _O2TOK-NEXT-NONZERO DROP

    R@ _O2TOK.OP-MODE @ _O2TOK-MODE-COMMIT = IF
        R@ _O2TOK-CLEAR-LEASE
    THEN
    R@ _O2TOK-WIPE-STAGE
    R@ _O2TOK-CLEAR-OP
    R> DROP ;

: _O2TOK-MUTATE-FAIL  ( tokens status -- status )
    >R
    DUP _O2TOK-WIPE-STAGE
    DUP _O2TOK-CLEAR-OP
    DROP R> ;

: _O2TOK-LEASE-MATCH?  ( lease tokens -- flag )
    >R
    DUP R@ _O2TOK.LEASE-DESC @ =
    OVER _O2LEASE.MAGIC @ _O2LEASE-MAGIC-VALUE = AND
    OVER _O2LEASE.OWNER @ R@ = AND
    OVER _O2LEASE.GENERATION @ R@ _O2TOK.LEASE-GENERATION @ = AND
    OVER _O2LEASE.ID @ R@ _O2TOK.LEASE-ID @ = AND
    R@ _O2TOK.LEASE-ID @ 0<> AND
    R@ _O2TOK.LEASE-GENERATION @ R@ O2TOK.GENERATION @ = AND
    SWAP DROP
    R> DROP ;

: _O2TOK-SET-BODY
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires tokens
  \   -- status )
    DUP O2TOK.BORROWED @ IF
        _O2TOK-DROP8 O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK.LEASE-ID @ IF
        _O2TOK-DROP8 O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK-PRESENT-LOCKED? IF
        _O2TOK-DROP8 O2TOK-S-BUSY EXIT
    THEN
    _O2TOK-LOAD-OP8
    _O2TOK-MODE-SET OVER _O2TOK.OP-MODE !
    DUP _O2TOK-STAGE-ALL
    DUP _O2TOK.STAGE-ACCESS-U @ 0= IF
        O2TOK-S-ABSENT _O2TOK-MUTATE-FAIL EXIT
    THEN
    DUP _O2TOK-PUBLISH-STAGE
    DROP O2TOK-S-OK ;

: _O2TOK-COMMIT-BODY
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires lease tokens
  \   -- status )
    DUP O2TOK.BORROWED @ IF
        _O2TOK-DROP9 O2TOK-S-BUSY EXIT
    THEN
    1 PICK OVER _O2TOK-LEASE-MATCH? 0= IF
        _O2TOK-DROP9 O2TOK-S-STALE EXIT
    THEN
    DUP _O2TOK.LEASE-USED @ 0= IF
        _O2TOK-DROP9 O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK-PRESENT-LOCKED? 0= IF
        _O2TOK-DROP9 O2TOK-S-ABSENT EXIT
    THEN
    _O2TOK-LOAD-OP9
    _O2TOK-MODE-COMMIT OVER _O2TOK.OP-MODE !
    DUP _O2TOK-STAGE-ALL
    DUP _O2TOK.STAGE-ACCESS-U @ 0= IF
        O2TOK-S-ABSENT _O2TOK-MUTATE-FAIL EXIT
    THEN
    DUP _O2TOK-PUBLISH-STAGE
    DROP O2TOK-S-OK ;

\ These wrappers release the object guard on normal return and on THROW.
\ Unexpected mutation faults propagate after staging/control cleanup.
: _O2TOK-CALL8
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires tokens xt
  \   -- status )
    1 PICK >R
    CATCH
    DUP IF
        >R
        DUP _O2TOK-WIPE-STAGE
        DUP _O2TOK-CLEAR-OP
        DUP _O2TOK-UNLOCK
        _O2TOK-DROP8
        R> R> DROP THROW
    THEN
    DROP
    R@ _O2TOK-UNLOCK
    R> DROP ;

: _O2TOK-CALL9
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires lease tokens xt
  \   -- status )
    1 PICK >R
    CATCH
    DUP IF
        >R
        DUP _O2TOK-WIPE-STAGE
        DUP _O2TOK-CLEAR-OP
        DUP _O2TOK-UNLOCK
        _O2TOK-DROP9
        R> R> DROP THROW
    THEN
    DROP
    R@ _O2TOK-UNLOCK
    R> DROP ;

\ =====================================================================
\  Initial token publication
\ =====================================================================

: O2TOK-SET
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires-ms tokens
  \   -- status )
    _O2TOK-8DUP _O2TOK-SET-GEOMETRY ?DUP IF
        >R _O2TOK-DROP8 R> EXIT
    THEN
    DUP _O2TOK-LOCK ?DUP IF
        >R _O2TOK-DROP8 R> EXIT
    THEN
    ['] _O2TOK-SET-BODY _O2TOK-CALL8 ;

\ =====================================================================
\  Callback borrows
\ =====================================================================

: _O2TOK-CALLBACK
  ( callback callback-context address length -- callback-status )
    2SWAP SWAP EXECUTE ;

\ The caller contract is one returned status cell.  THROW maps to CALLBACK;
\ the borrowed flag is cleared in both cases.
: _O2TOK-BORROW-RUN
  ( callback callback-context tokens address length -- status )
    2 PICK >R
    -1 R@ O2TOK.BORROWED !
    ROT DROP
    ['] _O2TOK-CALLBACK CATCH
    DUP IF
        DROP 2DROP 2DROP O2TOK-S-CALLBACK
    ELSE
        DROP
    THEN
    0 R@ O2TOK.BORROWED !
    1 R@ O2TOK.USES +!
    R> DROP ;

\ Preserve the three arguments and append a status.  OK means the guard is
\ held.  Same-owner recursion is rejected through BORROWED after acquisition.
: _O2TOK-BORROW-LOCK
  \ ( callback callback-context tokens
  \   -- callback callback-context tokens status )
    2 PICK 0= IF O2TOK-S-INVALID EXIT THEN
    DUP _O2TOK-OBJECT-STATUS ?DUP IF EXIT THEN
    DUP _O2TOK-LOCK ?DUP IF EXIT THEN
    DUP O2TOK.BORROWED @ IF
        DUP _O2TOK-UNLOCK
        O2TOK-S-BUSY EXIT
    THEN
    O2TOK-S-OK ;

: _O2TOK-WITH-AT
  ( callback callback-context tokens address length -- status )
    DUP 0= IF
        2DROP
        DUP _O2TOK-UNLOCK
        _O2TOK-DROP3 O2TOK-S-ABSENT EXIT
    THEN
    2 PICK >R
    _O2TOK-BORROW-RUN
    R> _O2TOK-UNLOCK ;

: O2TOK-WITH-ACCESS
  ( callback callback-context tokens -- status )
    _O2TOK-BORROW-LOCK ?DUP IF
        >R _O2TOK-DROP3 R> EXIT
    THEN
    DUP O2TOK.ACCESS
    OVER O2TOK.ACCESS-U @
    _O2TOK-WITH-AT ;

: O2TOK-WITH-ID
  ( callback callback-context tokens -- status )
    _O2TOK-BORROW-LOCK ?DUP IF
        >R _O2TOK-DROP3 R> EXIT
    THEN
    DUP O2TOK.ID
    OVER O2TOK.ID-U @
    _O2TOK-WITH-AT ;

\ =====================================================================
\  Generation-bound, single-use refresh lease
\ =====================================================================

: O2TOK-REFRESH-BEGIN  ( lease tokens -- status )
    DUP _O2TOK-OBJECT-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP _O2TOK-LEASE-DESC-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    OVER _O2LEASE-FREE? 0= IF
        2DROP O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK-LOCK ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP O2TOK.BORROWED @ IF
        DUP _O2TOK-UNLOCK
        2DROP O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK.LEASE-ID @ IF
        DUP _O2TOK-UNLOCK
        2DROP O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK.REFRESH-U @ 0= IF
        DUP _O2TOK-UNLOCK
        2DROP O2TOK-S-ABSENT EXIT
    THEN
    OVER _O2LEASE-FREE? 0= IF
        DUP _O2TOK-UNLOCK
        2DROP O2TOK-S-BUSY EXIT
    THEN

    DUP _O2TOK.LEASE-SEQUENCE _O2TOK-NEXT-NONZERO >R
    R@ OVER _O2TOK.LEASE-ID !
    DUP O2TOK.GENERATION @ OVER _O2TOK.LEASE-GENERATION !
    0 OVER _O2TOK.LEASE-USED !
    OVER OVER _O2TOK.LEASE-DESC !

    DUP 2 PICK _O2LEASE.OWNER !
    DUP O2TOK.GENERATION @ 2 PICK _O2LEASE.GENERATION !
    R@ 2 PICK _O2LEASE.ID !

    DUP _O2TOK-UNLOCK
    2DROP R> DROP O2TOK-S-OK ;

: O2TOK-WITH-REFRESH-LEASE
  ( callback callback-context lease tokens -- status )
    3 PICK 0= IF _O2TOK-DROP4 O2TOK-S-INVALID EXIT THEN
    DUP _O2TOK-OBJECT-STATUS ?DUP IF
        >R _O2TOK-DROP4 R> EXIT
    THEN
    OVER OVER _O2TOK-LEASE-DESC-STATUS ?DUP IF
        >R _O2TOK-DROP4 R> EXIT
    THEN
    DUP _O2TOK-LOCK ?DUP IF
        >R _O2TOK-DROP4 R> EXIT
    THEN
    DUP O2TOK.BORROWED @ IF
        DUP _O2TOK-UNLOCK
        _O2TOK-DROP4 O2TOK-S-BUSY EXIT
    THEN
    OVER OVER _O2TOK-LEASE-MATCH? 0= IF
        DUP _O2TOK-UNLOCK
        _O2TOK-DROP4 O2TOK-S-STALE EXIT
    THEN
    DUP _O2TOK.LEASE-USED @ IF
        DUP _O2TOK-UNLOCK
        _O2TOK-DROP4 O2TOK-S-BUSY EXIT
    THEN
    DUP _O2TOK.REFRESH-U @ 0= IF
        DUP _O2TOK-UNLOCK
        _O2TOK-DROP4 O2TOK-S-ABSENT EXIT
    THEN

    -1 OVER _O2TOK.LEASE-USED !
    DUP _O2TOK.REFRESH
    OVER _O2TOK.REFRESH-U @
    3 ROLL DROP
    2 PICK >R
    _O2TOK-BORROW-RUN
    R> _O2TOK-UNLOCK ;

: O2TOK-REFRESH-ABORT  ( lease tokens -- status )
    DUP _O2TOK-OBJECT-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP _O2TOK-LEASE-DESC-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP _O2TOK-LOCK ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP O2TOK.BORROWED @ IF
        DUP _O2TOK-UNLOCK
        2DROP O2TOK-S-BUSY EXIT
    THEN
    2DUP _O2TOK-LEASE-MATCH? 0= IF
        DUP _O2TOK-UNLOCK
        2DROP O2TOK-S-STALE EXIT
    THEN
    DUP _O2TOK-CLEAR-LEASE
    DUP _O2TOK-UNLOCK
    2DROP O2TOK-S-OK ;

: O2TOK-REFRESH-COMMIT
  \ ( id-a id-u access-a access-u refresh-a refresh-u expires-ms lease tokens
  \   -- status )
    _O2TOK-9DUP _O2TOK-COMMIT-GEOMETRY ?DUP IF
        >R _O2TOK-DROP9 R> EXIT
    THEN
    DUP _O2TOK-LOCK ?DUP IF
        >R _O2TOK-DROP9 R> EXIT
    THEN
    ['] _O2TOK-COMMIT-BODY _O2TOK-CALL9 ;
