\ =====================================================================
\  context.f - Activation-local recursive runtime Context
\ =====================================================================
\  A Context is live activation state.  Its numeric identity is valid
\  only within EPOCH, and its service fields are borrowed runtime
\  pointers.  It is never a durable or portable representation.
\
\  Context allocation and mutation are owner-serialized in version 1.
\  CTX-CHILD-NEW intentionally does not inherit bindings, facets,
\  authority, queues, wordsets, or VFS reachability.
\ =====================================================================

PROVIDED akashic-runtime-context

REQUIRE identity.f

1095451480 CONSTANT CTX-MAGIC       \ "AKCX"
1          CONSTANT CTX-ABI-VERSION

1 CONSTANT CTX-E-BAD-CONTEXT
2 CONSTANT CTX-E-NOMEM

1 CONSTANT CTX-F-ACTIVE
2 CONSTANT CTX-F-READONLY
4 CONSTANT CTX-F-DISPOSABLE
8 CONSTANT CTX-F-RECOVERY

\ Live Context, 26 cells / 208 bytes.
  0 CONSTANT _CTX-MAGIC
  8 CONSTANT _CTX-ABI
 16 CONSTANT _CTX-SIZE
 24 CONSTANT _CTX-ID
 32 CONSTANT _CTX-GENERATION
 40 CONSTANT _CTX-REVISION
 48 CONSTANT _CTX-EPOCH
 56 CONSTANT _CTX-FLAGS
 64 CONSTANT _CTX-PARENT-ID
 72 CONSTANT _CTX-PARENT-GENERATION
 80 CONSTANT _CTX-PRACTICE
 88 CONSTANT _CTX-OWNER-CORE
 96 CONSTANT _CTX-OWNER-TOKEN
104 CONSTANT _CTX-BINDINGS
112 CONSTANT _CTX-FACETS
120 CONSTANT _CTX-AUTHORITY
128 CONSTANT _CTX-QUEUE
136 CONSTANT _CTX-POLICY
144 CONSTANT _CTX-WORDSET
152 CONSTANT _CTX-VFS
160 CONSTANT _CTX-MEMORY-LIMIT
168 CONSTANT _CTX-TIME-LIMIT-MS
176 CONSTANT _CTX-OUTPUT-LIMIT
184 CONSTANT _CTX-QUEUE-LIMIT
192 CONSTANT _CTX-RETENTION
200 CONSTANT _CTX-RESERVED
208 CONSTANT CTX-SIZE

: CTX.MAGIC              ( ctx -- a ) _CTX-MAGIC + ;
: CTX.ABI                ( ctx -- a ) _CTX-ABI + ;
: CTX.SIZE               ( ctx -- a ) _CTX-SIZE + ;
: CTX.ID                 ( ctx -- a ) _CTX-ID + ;
: CTX.GENERATION         ( ctx -- a ) _CTX-GENERATION + ;
: CTX.REVISION           ( ctx -- a ) _CTX-REVISION + ;
: CTX.EPOCH              ( ctx -- a ) _CTX-EPOCH + ;
: CTX.FLAGS              ( ctx -- a ) _CTX-FLAGS + ;
: CTX.PARENT-ID          ( ctx -- a ) _CTX-PARENT-ID + ;
: CTX.PARENT-GENERATION  ( ctx -- a ) _CTX-PARENT-GENERATION + ;
: CTX.PRACTICE           ( ctx -- a ) _CTX-PRACTICE + ;
: CTX.OWNER-CORE         ( ctx -- a ) _CTX-OWNER-CORE + ;
: CTX.OWNER-TOKEN        ( ctx -- a ) _CTX-OWNER-TOKEN + ;
: CTX.BINDINGS           ( ctx -- a ) _CTX-BINDINGS + ;
: CTX.FACETS             ( ctx -- a ) _CTX-FACETS + ;
: CTX.AUTHORITY          ( ctx -- a ) _CTX-AUTHORITY + ;
: CTX.QUEUE              ( ctx -- a ) _CTX-QUEUE + ;
: CTX.POLICY             ( ctx -- a ) _CTX-POLICY + ;
: CTX.WORDSET            ( ctx -- a ) _CTX-WORDSET + ;
: CTX.VFS                ( ctx -- a ) _CTX-VFS + ;
: CTX.MEMORY-LIMIT       ( ctx -- a ) _CTX-MEMORY-LIMIT + ;
: CTX.TIME-LIMIT-MS      ( ctx -- a ) _CTX-TIME-LIMIT-MS + ;
: CTX.OUTPUT-LIMIT       ( ctx -- a ) _CTX-OUTPUT-LIMIT + ;
: CTX.QUEUE-LIMIT        ( ctx -- a ) _CTX-QUEUE-LIMIT + ;
: CTX.RETENTION          ( ctx -- a ) _CTX-RETENTION + ;

: CTX-INIT  ( ctx -- )
    DUP CTX-SIZE 0 FILL
    CTX-MAGIC OVER CTX.MAGIC !
    CTX-ABI-VERSION OVER CTX.ABI !
    CTX-SIZE OVER CTX.SIZE !
    1 SWAP CTX.REVISION ! ;

: CTX-IDENTITY!  ( id generation epoch ctx -- )
    >R
    ROT R@ CTX.ID !
    SWAP R@ CTX.GENERATION !
    R> CTX.EPOCH ! ;

: CTX-VALID?  ( ctx -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CTX.MAGIC @ CTX-MAGIC =
    OVER CTX.ABI @ CTX-ABI-VERSION = AND
    OVER CTX.SIZE @ CTX-SIZE >= AND
    OVER CTX.ID @ 0> AND
    OVER CTX.GENERATION @ 0> AND
    OVER CTX.REVISION @ 0> AND
    SWAP CTX.EPOCH @ 0> AND ;

: CTX-TOUCH  ( ctx -- )
    1 SWAP CTX.REVISION +! ;

: CTX-READONLY?  ( ctx -- flag )
    CTX.FLAGS @ CTX-F-READONLY AND 0<> ;

: CTX-IDENTITY=  ( id generation epoch ctx -- flag )
    >R
    ROT R@ CTX.ID @ =
    ROT R@ CTX.GENERATION @ = AND
    SWAP R> CTX.EPOCH @ = AND ;

: CTX-OWNER?  ( core owner-token ctx -- flag )
    >R
    SWAP R@ CTX.OWNER-CORE @ =
    SWAP R> CTX.OWNER-TOKEN @ = AND ;

VARIABLE _CTX-NEXT-ID
1 _CTX-NEXT-ID !

: CTX-NEW  ( epoch -- ctx ior )
    DUP 0< OVER 0= OR IF DROP 0 CTX-E-BAD-CONTEXT EXIT THEN
    >R
    CTX-SIZE ALLOCATE
    DUP IF R> DROP SWAP DROP 0 SWAP EXIT THEN
    DROP DUP CTX-INIT
    _CTX-NEXT-ID @ DUP 1 _CTX-NEXT-ID +!
    R> 3 PICK CTX-IDENTITY!
    0 ;

: CTX-FREE  ( ctx -- )
    ?DUP IF DUP CTX-SIZE 0 FILL FREE THEN ;

VARIABLE _CTX-CHILD-PARENT
VARIABLE _CTX-CHILD

: CTX-CHILD-NEW  ( parent -- child ior )
    DUP CTX-VALID? 0= IF DROP 0 CTX-E-BAD-CONTEXT EXIT THEN
    _CTX-CHILD-PARENT !
    _CTX-CHILD-PARENT @ CTX.EPOCH @ CTX-NEW
    DUP IF EXIT THEN
    DROP DUP _CTX-CHILD ! DROP
    _CTX-CHILD-PARENT @ CTX.ID @
        _CTX-CHILD @ CTX.PARENT-ID !
    _CTX-CHILD-PARENT @ CTX.GENERATION @
        _CTX-CHILD @ CTX.PARENT-GENERATION !
    _CTX-CHILD-PARENT @ CTX.PRACTICE @
        _CTX-CHILD @ CTX.PRACTICE !
    _CTX-CHILD-PARENT @ CTX.OWNER-CORE @
        _CTX-CHILD @ CTX.OWNER-CORE !
    _CTX-CHILD-PARENT @ CTX.OWNER-TOKEN @
        _CTX-CHILD @ CTX.OWNER-TOKEN !
    _CTX-CHILD-PARENT @ CTX.POLICY @
        _CTX-CHILD @ CTX.POLICY !
    _CTX-CHILD-PARENT @ CTX.MEMORY-LIMIT @
        _CTX-CHILD @ CTX.MEMORY-LIMIT !
    _CTX-CHILD-PARENT @ CTX.TIME-LIMIT-MS @
        _CTX-CHILD @ CTX.TIME-LIMIT-MS !
    _CTX-CHILD-PARENT @ CTX.OUTPUT-LIMIT @
        _CTX-CHILD @ CTX.OUTPUT-LIMIT !
    _CTX-CHILD-PARENT @ CTX.QUEUE-LIMIT @
        _CTX-CHILD @ CTX.QUEUE-LIMIT !
    _CTX-CHILD-PARENT @ CTX.RETENTION @
        _CTX-CHILD @ CTX.RETENTION !
    _CTX-CHILD-PARENT @ CTX.FLAGS @
        CTX-F-READONLY CTX-F-RECOVERY OR AND
        CTX-F-DISPOSABLE OR _CTX-CHILD @ CTX.FLAGS !
    _CTX-CHILD @ 0 ;
