\ =====================================================================
\  practice-activation.f - Generic validated Practice activation
\ =====================================================================
\  PACT owns activation-local state around a durable Practice head.  It
\  selects a semantically accepted generation of the head, which lives in
\  the home of the place set it is given, creates a fresh epoch and root
\  Context, and fails closed into a read-only recovery Context.
\
\  The set is what the activation's components see of storage.  Recovery,
\  a read-only Practice and a home that cannot be written narrow every
\  place of it to read-only.  A set with no usable home starts in
\  recovery: nothing falls back to another place.  PACT-PLACES answers
\  the set a component instance works in: the part of the activation's
\  set its descriptor says it needs (COMP.PLACE-NEEDS, PLSET-DERIVE),
\  made once for the instance and freed by PACT-PLACES-RELEASE or when
\  the activation ends.  A component's home in it is a folder of its own
\  inside the activation's home, named by the component's id, where that
\  home stands apart from the documents place.  PACT-STORE-PLACES answers
\  a set with that same home for stores that keep a component's records
\  on its behalf, as Desk's own stores do.  Ownership of a file
\  follows from these grants
\  (docs/utils/fs/places.md, "Who may write a file"), and a Practice's
\  own choice of places per component belongs in the same word.
\
\  The validator declares its trust level explicitly.  The built-in
\  validator is structural only: CRC plus PHEAD-VALID? is not authentication.
\  PACT-TRUST-AUTHENTICATED is meaningful only when the caller supplies a
\  validator backed by an external trust anchor and authenticated objects.
\
\  PACT never restores grants, invocation handles, queues, execution tokens,
\  leases, or runtime pointers from the durable head.
\ =====================================================================

PROVIDED akashic-runtime-pact

REQUIRE context.f
REQUIRE instance.f
REQUIRE vfs-practice-head.f
REQUIRE ../utils/fs/places.f

1414548289 CONSTANT PACT-MAGIC       \ "AKPT"
1          CONSTANT PACT-ABI-VERSION

0 CONSTANT PACT-S-OK
1 CONSTANT PACT-S-INVALID
2 CONSTANT PACT-S-NOMEM
3 CONSTANT PACT-S-RECOVERY

0 CONSTANT PACT-M-INACTIVE
1 CONSTANT PACT-M-ACTIVE
2 CONSTANT PACT-M-FALLBACK
3 CONSTANT PACT-M-RECOVERY

1 CONSTANT PACT-TRUST-STRUCTURAL
2 CONSTANT PACT-TRUST-AUTHENTICATED

1 CONSTANT PACT-F-PLACES-READONLY

  0 CONSTANT _PACT-MAGIC
  8 CONSTANT _PACT-ABI
 16 CONSTANT _PACT-SIZE
 24 CONSTANT _PACT-MODE
 32 CONSTANT _PACT-STATUS
 40 CONSTANT _PACT-TRUST
 48 CONSTANT _PACT-PLACES
 56 CONSTANT _PACT-EPOCH
 64 CONSTANT _PACT-OWNER-CORE
 72 CONSTANT _PACT-OWNER-TOKEN
 80 CONSTANT _PACT-VALIDATOR-XT
 88 CONSTANT _PACT-VALIDATOR-DATA
 96 CONSTANT _PACT-CONTEXT
104 CONSTANT _PACT-HEAD-GENERATION
112 CONSTANT _PACT-REJECTED-GENERATION
120 CONSTANT _PACT-FLAGS
128 CONSTANT _PACT-GRANTS
136 CONSTANT _PACT-HEAD
_PACT-HEAD PHEAD-SIZE + CONSTANT _PACT-REJECTED-HEAD
_PACT-REJECTED-HEAD PHEAD-SIZE + CONSTANT _PACT-STORE
_PACT-STORE PHEADVFS-SIZE + CONSTANT PACT-SIZE

: PACT.MAGIC                ( pact -- a ) _PACT-MAGIC + ;
: PACT.ABI                  ( pact -- a ) _PACT-ABI + ;
: PACT.SIZE                 ( pact -- a ) _PACT-SIZE + ;
: PACT.MODE                 ( pact -- a ) _PACT-MODE + ;
: PACT.STATUS               ( pact -- a ) _PACT-STATUS + ;
: PACT.TRUST                ( pact -- a ) _PACT-TRUST + ;
: PACT.PLACES               ( pact -- a ) _PACT-PLACES + ;
: PACT.EPOCH                ( pact -- a ) _PACT-EPOCH + ;
: PACT.OWNER-CORE           ( pact -- a ) _PACT-OWNER-CORE + ;
: PACT.OWNER-TOKEN          ( pact -- a ) _PACT-OWNER-TOKEN + ;
: PACT.VALIDATOR-XT         ( pact -- a ) _PACT-VALIDATOR-XT + ;
: PACT.VALIDATOR-DATA       ( pact -- a ) _PACT-VALIDATOR-DATA + ;
: PACT.CONTEXT              ( pact -- a ) _PACT-CONTEXT + ;
: PACT.HEAD-GENERATION      ( pact -- a ) _PACT-HEAD-GENERATION + ;
: PACT.REJECTED-GENERATION  ( pact -- a ) _PACT-REJECTED-GENERATION + ;
: PACT.FLAGS                ( pact -- a ) _PACT-FLAGS + ;
: _PACT.GRANTS              ( pact -- a ) _PACT-GRANTS + ;
: PACT-HEAD                 ( pact -- head ) _PACT-HEAD + ;
: PACT-REJECTED-HEAD        ( pact -- head ) _PACT-REJECTED-HEAD + ;
: PACT-STORE                ( pact -- store ) _PACT-STORE + ;

: _PACT-STRUCTURAL-VALIDATOR  ( head data -- status )
    DROP DUP PHEAD-VALID? SWAP PHEAD.SIZE @ PHEAD-SIZE = AND IF
        PHEADVFS-S-OK
    ELSE
        PHEADVFS-S-INVALID
    THEN ;

: PACT-TRUST-VALID?  ( trust -- flag )
    DUP PACT-TRUST-STRUCTURAL = SWAP PACT-TRUST-AUTHENTICATED = OR ;

: PACT-INIT  ( pact -- )
    DUP PACT-SIZE 0 FILL
    PACT-MAGIC OVER PACT.MAGIC !
    PACT-ABI-VERSION OVER PACT.ABI !
    PACT-SIZE OVER PACT.SIZE !
    PACT-M-INACTIVE OVER PACT.MODE !
    PACT-TRUST-STRUCTURAL OVER PACT.TRUST !
    ['] _PACT-STRUCTURAL-VALIDATOR SWAP PACT.VALIDATOR-XT ! ;

: PACT-VALID?  ( pact -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP PACT.MAGIC @ PACT-MAGIC =
    OVER PACT.ABI @ PACT-ABI-VERSION = AND
    OVER PACT.SIZE @ PACT-SIZE >= AND
    OVER PACT.VALIDATOR-XT @ 0<> AND
    SWAP PACT.TRUST @ PACT-TRUST-VALID? AND ;

: PACT-ACTIVE?  ( pact -- flag )
    DUP PACT-VALID? 0= IF DROP 0 EXIT THEN
    PACT.CONTEXT @ ?DUP IF
        DUP CTX-VALID? SWAP CTX.FLAGS @ CTX-F-ACTIVE AND 0<> AND
    ELSE
        0
    THEN ;

: PACT-RECOVERY?  ( pact -- flag )
    PACT.MODE @ PACT-M-RECOVERY = ;

: PACT-FALLBACK?  ( pact -- flag )
    PACT.MODE @ PACT-M-FALLBACK = ;

: PACT-READONLY?  ( pact -- flag )
    DUP PACT.CONTEXT @ ?DUP IF CTX-READONLY? NIP ELSE DROP 0 THEN ;

: PACT-AUTHENTICATED?  ( pact -- flag )
    DUP PACT.TRUST @ PACT-TRUST-AUTHENTICATED =
    OVER PACT-ACTIVE? AND
    SWAP PACT-RECOVERY? 0= AND ;

VARIABLE _PACT-VS-XT
VARIABLE _PACT-VS-DATA
VARIABLE _PACT-VS-TRUST
VARIABLE _PACT-VS-PACT

: PACT-VALIDATOR!  ( xt data trust pact -- status )
    _PACT-VS-PACT ! _PACT-VS-TRUST ! _PACT-VS-DATA ! _PACT-VS-XT !
    _PACT-VS-PACT @ PACT-VALID? 0= IF PACT-S-INVALID EXIT THEN
    _PACT-VS-PACT @ PACT-ACTIVE? IF PACT-S-INVALID EXIT THEN
    _PACT-VS-XT @ 0= _PACT-VS-TRUST @ PACT-TRUST-VALID? 0= OR IF
        PACT-S-INVALID EXIT
    THEN
    _PACT-VS-XT @ _PACT-VS-PACT @ PACT.VALIDATOR-XT !
    _PACT-VS-DATA @ _PACT-VS-PACT @ PACT.VALIDATOR-DATA !
    _PACT-VS-TRUST @ _PACT-VS-PACT @ PACT.TRUST !
    PACT-S-OK ;

\ A grant: the place set one component instance works in, made from the
\ activation's set (PACT-PLACES).  Grants are heap records listed on the
\ activation and found by the instance's ID, which no later instance
\ repeats.
: _PAG.NEXT  ( grant -- a ) ;
: _PAG.ID    ( grant -- a )  8 + ;
: _PAG.SET   ( grant -- a ) 16 + ;
24 CONSTANT _PAG-SIZE

\ Free every grant of the activation, with its set.
: _PACT-GRANTS-FREE  ( pact -- )
    DUP _PACT.GRANTS @  0 ROT _PACT.GRANTS !
    BEGIN ?DUP WHILE
        DUP _PAG.NEXT @ SWAP
        DUP _PAG.SET @ PLSET-FREE  FREE
    REPEAT ;

: PACT-DEACTIVATE  ( pact -- )
    DUP 0= IF DROP EXIT THEN
    DUP _PACT-GRANTS-FREE
    DUP PACT.CONTEXT @ ?DUP IF CTX-FREE THEN
    0 OVER PACT.CONTEXT !
    0 OVER PACT.PLACES !
    0 OVER PACT.EPOCH !
    0 OVER PACT.OWNER-CORE !
    0 OVER PACT.OWNER-TOKEN !
    0 OVER PACT.HEAD-GENERATION !
    0 OVER PACT.REJECTED-GENERATION !
    0 OVER PACT.FLAGS !
    PACT-S-OK OVER PACT.STATUS !
    PACT-M-INACTIVE SWAP PACT.MODE ! ;

: _PACT-FRESH-EPOCH  ( -- epoch )
    RANDOM 0x7FFFFFFFFFFFFFFF AND 1 OR ;

: _PACT-FRESH-OWNER-TOKEN  ( -- token )
    RANDOM 1 OR ;

VARIABLE _PACT-A-SET
VARIABLE _PACT-A-HOME
VARIABLE _PACT-A-PACT
VARIABLE _PACT-A-LOAD-STATUS
VARIABLE _PACT-A-CONTEXT
VARIABLE _PACT-A-CTX-FLAGS

\ Narrow every place of the set to read-only.  The volumes under the
\ places stay as they are: the place words, a replacement bound in a
\ read-only place, and the persistence and snapshot stores marked from
\ their home's access each refuse changes themselves
\ (docs/utils/fs/places.md).
: _PACT-NARROW  ( -- )
    _PACT-A-SET @ PLSET-READ-ONLY!
    _PACT-A-PACT @ _PACT.GRANTS @
    BEGIN ?DUP WHILE
        DUP _PAG.SET @ PLSET-READ-ONLY!  _PAG.NEXT @
    REPEAT
    PACT-F-PLACES-READONLY _PACT-A-PACT @ PACT.FLAGS ! ;

: _PACT-ENTER-RECOVERY  ( -- )
    PACT-M-RECOVERY _PACT-A-PACT @ PACT.MODE !
    PACT-S-RECOVERY _PACT-A-PACT @ PACT.STATUS !
    CTX-F-ACTIVE CTX-F-READONLY OR CTX-F-RECOVERY OR
        _PACT-A-CTX-FLAGS !
    _PACT-NARROW ;

: _PACT-ENTER-ACCEPTED  ( -- )
    _PACT-A-PACT @ PACT-STORE PHEADVFS-FALLBACK? IF
        PACT-M-FALLBACK
    ELSE
        PACT-M-ACTIVE
    THEN _PACT-A-PACT @ PACT.MODE !
    PACT-S-OK _PACT-A-PACT @ PACT.STATUS !
    CTX-F-ACTIVE _PACT-A-CTX-FLAGS !
    _PACT-A-PACT @ PACT-HEAD PHEAD-READONLY?
    _PACT-A-HOME @ PLACE-WRITABLE? 0= OR IF
        _PACT-A-CTX-FLAGS @ CTX-F-READONLY OR _PACT-A-CTX-FLAGS !
        _PACT-NARROW
    THEN ;

\ The set's home when it can be used now, else 0.
: _PACT-USABLE-HOME  ( set -- place | 0 )
    PLSET-HOME DUP 0= IF EXIT THEN
    DUP PLACE-STATUS IF DROP 0 THEN ;

\ PACT-ACTIVATE ( set pact -- status )
\   Activate over the place set SET.  The Practice head is read from the
\   set's home.  A set whose home is absent or unavailable activates in
\   recovery without a head.
: PACT-ACTIVATE  ( set pact -- status )
    _PACT-A-PACT ! _PACT-A-SET !
    _PACT-A-PACT @ PACT-VALID? 0= _PACT-A-SET @ 0= OR IF
        PACT-S-INVALID EXIT
    THEN
    _PACT-A-PACT @ PACT-DEACTIVATE
    _PACT-A-SET @ _PACT-A-PACT @ PACT.PLACES !
    _PACT-A-SET @ _PACT-USABLE-HOME DUP _PACT-A-HOME ! IF
        _PACT-A-HOME @ _PACT-A-PACT @ PACT-STORE PHEADVFS-INIT
        PHEADVFS-S-OK <> IF
            PACT-S-INVALID _PACT-A-PACT @ PACT.STATUS !
            PACT-S-INVALID EXIT
        THEN
        _PACT-A-PACT @ PACT-HEAD
        _PACT-A-PACT @ PACT-REJECTED-HEAD
        _PACT-A-PACT @ PACT.VALIDATOR-XT @
        _PACT-A-PACT @ PACT.VALIDATOR-DATA @
        _PACT-A-PACT @ PACT-STORE PHEADVFS-LOAD-VALIDATED
        DUP _PACT-A-LOAD-STATUS !
        DUP PHEADVFS-S-OK <> SWAP PHEADVFS-S-RECOVERY <> AND IF
            PACT-S-INVALID _PACT-A-PACT @ PACT.STATUS !
            PACT-S-INVALID EXIT
        THEN
    ELSE
        PHEADVFS-S-RECOVERY _PACT-A-LOAD-STATUS !
    THEN

    _PACT-FRESH-EPOCH DUP _PACT-A-PACT @ PACT.EPOCH !
    CTX-NEW DUP IF
        2DROP PACT-S-NOMEM _PACT-A-PACT @ PACT.STATUS !
        PACT-S-NOMEM EXIT
    THEN
    DROP DUP _PACT-A-CONTEXT ! _PACT-A-PACT @ PACT.CONTEXT !
    COREID DUP _PACT-A-PACT @ PACT.OWNER-CORE !
        _PACT-A-CONTEXT @ CTX.OWNER-CORE !
    _PACT-FRESH-OWNER-TOKEN DUP _PACT-A-PACT @ PACT.OWNER-TOKEN !
        _PACT-A-CONTEXT @ CTX.OWNER-TOKEN !
    _PACT-A-PACT @ PACT-HEAD _PACT-A-CONTEXT @ CTX.PRACTICE !
    _PACT-A-SET @ _PACT-A-CONTEXT @ CTX.PLACES !
    _PACT-A-HOME @ IF
        _PACT-A-PACT @ PACT-STORE PHEADVFS.GENERATION @
            _PACT-A-PACT @ PACT.HEAD-GENERATION !
        _PACT-A-PACT @ PACT-STORE PHEADVFS.REJECTED-GENERATION @
            _PACT-A-PACT @ PACT.REJECTED-GENERATION !
    THEN

    _PACT-A-LOAD-STATUS @ PHEADVFS-S-RECOVERY = IF
        _PACT-ENTER-RECOVERY
    ELSE
        _PACT-ENTER-ACCEPTED
    THEN
    _PACT-A-CTX-FLAGS @ _PACT-A-CONTEXT @ CTX.FLAGS !
    _PACT-A-PACT @ PACT.STATUS @ ;

VARIABLE _PPL-INST
VARIABLE _PPL-PACT

\ The grant of the instance with ID on the activation, or 0.
: _PACT-GRANT-FIND  ( id pact -- grant | 0 )
    _PACT.GRANTS @
    BEGIN DUP WHILE
        2DUP _PAG.ID @ = IF NIP EXIT THEN
        _PAG.NEXT @
    REPEAT
    NIP ;

\ The places the instance's component says it needs.
: _PACT-NEEDS  ( instance -- needs )
    CINST-DESC DUP COMP-DESC-VALID? IF COMP.PLACE-NEEDS @ ELSE DROP 0 THEN ;

\ The folder of a component's own home in the activation's home: the
\ component's id ID, so each component keeps its records in a folder of
\ its own that no other component is given.  A home that is the documents
\ place too, as the linked build's one place is, stays shared, since a
\ folder per component there would sit among a person's documents.
: _PACT-ID-FOLDER  ( id-a id-u pact -- a u )
    PACT.PLACES @ DUP PLSET-HOME SWAP PLSET-DOCUMENTS = IF
        2DROP 0 0
    THEN ;

\ The folder of the instance's own home: its component's id.
: _PACT-HOME-FOLDER  ( instance pact -- a u )
    >R CINST-DESC DUP COMP-DESC-VALID? IF
        DUP COMP.ID-A @ SWAP COMP.ID-U @
    ELSE DROP 0 0 THEN
    R> _PACT-ID-FOLDER ;

\ PACT-PLACES ( instance pact -- set | 0 )
\   The place set the runtime instance INSTANCE works in under this
\   activation: the part of the activation's set its component's
\   descriptor says it needs, made the first time the instance asks and
\   kept for it until PACT-PLACES-RELEASE or the activation ends.  0
\   when the activation is not active, for no instance, or when the set
\   cannot be made.
: PACT-PLACES  ( instance pact -- set | 0 )
    DUP PACT-ACTIVE? 0= IF 2DROP 0 EXIT THEN
    _PPL-PACT ! DUP _PPL-INST ! 0= IF 0 EXIT THEN
    _PPL-INST @ CINST.ID @ _PPL-PACT @ _PACT-GRANT-FIND ?DUP IF
        _PAG.SET @ EXIT
    THEN
    _PPL-INST @ _PACT-NEEDS _PPL-INST @ _PPL-PACT @ _PACT-HOME-FOLDER
    _PPL-PACT @ PACT.PLACES @ PLSET-DERIVE
    IF DROP 0 EXIT THEN                                ( set )
    _PAG-SIZE ALLOCATE IF DROP PLSET-FREE 0 EXIT THEN  ( set grant )
    TUCK _PAG.SET !
    _PPL-INST @ CINST.ID @ OVER _PAG.ID !
    _PPL-PACT @ _PACT.GRANTS @ OVER _PAG.NEXT !
    DUP _PPL-PACT @ _PACT.GRANTS !
    _PAG.SET @ ;

\ PACT-STORE-PLACES ( id-a id-u pact -- set | 0 )
\   A set for stores that keep the records of the component with id ID
\   on its behalf, as Desk's own stores do.  Its home is the home
\   PACT-PLACES gives the component's instances, so a component's records
\   lie together whichever code writes them, and nothing else of the
\   activation's set is in it but the origin, read-only.  The set is the
\   caller's, freed with PLSET-FREE once its stores are closed.  0 when
\   the activation is not active, for an empty ID, or when the set cannot
\   be made.
: PACT-STORE-PLACES  ( id-a id-u pact -- set | 0 )
    DUP PACT-ACTIVE? 0= IF DROP 2DROP 0 EXIT THEN
    OVER 0= IF DROP 2DROP 0 EXIT THEN
    >R R@ _PACT-ID-FOLDER
    PLACES-NEED-HOME ROT ROT R> PACT.PLACES @ PLSET-DERIVE
    IF DROP 0 THEN ;

VARIABLE _PPR-ID

\ PACT-PLACES-RELEASE ( instance pact -- )
\   Free the set PACT-PLACES made for INSTANCE, once the instance has
\   ended and nothing of it uses its places.
: PACT-PLACES-RELEASE  ( instance pact -- )
    OVER 0= OVER PACT-VALID? 0= OR IF 2DROP EXIT THEN
    SWAP CINST.ID @ _PPR-ID !
    _PACT.GRANTS                                   ( link )
    BEGIN DUP @ WHILE
        DUP @ _PAG.ID @ _PPR-ID @ = IF
            DUP @ DUP _PAG.NEXT @ ROT !               ( grant )
            DUP _PAG.SET @ PLSET-FREE  FREE  EXIT
        THEN
        @ _PAG.NEXT
    REPEAT
    DROP ;
