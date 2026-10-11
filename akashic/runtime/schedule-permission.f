\ =====================================================================
\  schedule-permission.f - Durable permissions for scheduled actions
\ =====================================================================
\  A schedule permission lets Desk's broker start scheduled work on its
\  own: an automatic action from the catalog (interop/scheduled-action.f)
\  for one schedule of one store, in one Practice.  It binds exactly what
\  the user approved: the action and schema, the digest of its operands
\  (the model, limits and prompt), the digest of when it runs, and the
\  limits themselves.  A request matches it only when all of these are
\  the same, at the revision the request names.
\
\  The store keeps no content: no title, prompt or model text.  Whoever
\  shows a permission reads those from the schedule it names, and the
\  operand digest says whether they are still what was approved.
\
\  Permissions live in one file, replaced whole and atomically through
\  vfs-replace.f.  The file is a CRC-checked record (checked-record.f,
\  magic AKSCHPRM, format 1) whose tag is its generation: a header, then
\  a 272-byte record per permission, sorted by RID.  A permission's RID
\  is SHA3-256 of a domain, the store's identity and the permission's
\  serial, so a RID is never granted again once revoked.  A Practice has
\  at most one permission per schedule: approving a schedule again after
\  it changed replaces that permission's grant and moves its revision on.
\  Revoking deletes it.
\
\  OPEN finishes or undoes an interrupted replacement, then reads the
\  file.  A missing file is an empty store.  A file that fails its checks,
\  or that cannot be read, blocks the store with the reason: nothing loads
\  and nothing is written, so damage never reads as no permissions.  A
\  write checks its file as OPEN would, and one that fails reloads the
\  last committed file.
\
\  The store is caller-serialized.  Desk's broker is its only writer, so
\  what it holds in memory is what the file holds.
\
\  Public API:
\    SPERM-INIT         ( vfs path path-u store -- status )
\    SPERM-OPEN         ( store -- status )
\    SPERM-CLOSE        ( store -- status )
\    SPERM-STATE@       ( store -- state )
\    SPERM-REASON@      ( store -- reason )
\    SPERM-GENERATION@  ( store -- n )
\    SPERM-HEADER       ( store -- header )
\    SPERM-COUNT@       ( store -- n )
\    SPERM-NTH          ( index store -- permission )
\    SPERM-FIND         ( rid store -- permission|0 )
\    SPERM-GRANTABLE?   ( request practice -- flag )
\    SPERM-GRANT        ( request practice now store -- permission status )
\    SPERM-REVOKE       ( rid store -- status )
\    SPERM-MATCH        ( request practice store -- standing )
\ =====================================================================

PROVIDED akashic-sched-permission

REQUIRE identity.f
REQUIRE ../math/sha3.f
REQUIRE ../math/entropy.f
REQUIRE ../utils/checked-record.f
REQUIRE ../utils/fs/vfs.f
REQUIRE ../utils/fs/vfs-replace.f
REQUIRE ../utils/record-table.f
REQUIRE ../interop/scheduled-dispatch.f

0 CONSTANT SPERM-S-OK
1 CONSTANT SPERM-S-INVALID
2 CONSTANT SPERM-S-NOMEM
3 CONSTANT SPERM-S-IO
4 CONSTANT SPERM-S-BLOCKED
5 CONSTANT SPERM-S-STATE
6 CONSTANT SPERM-S-ENTROPY
7 CONSTANT SPERM-S-NOT-FOUND

\ Store states.
0 CONSTANT SPERM-CLOSED
1 CONSTANT SPERM-READY
2 CONSTANT SPERM-BLOCKED

\ Why a store is blocked.
1 CONSTANT SPERM-R-CORRUPT      \ the file failed its checks
2 CONSTANT SPERM-R-FUTURE       \ a newer format than this code reads
3 CONSTANT SPERM-R-UNCERTAIN    \ a replacement's outcome is unknown
4 CONSTANT SPERM-R-IO           \ the file could not be read into memory

\ =====================================================================
\  Records
\ =====================================================================

\ A permission:
\    +0 RID   +32 Practice RID   +64 revision   +72 serial
\   +80 the subject store's identity   +112 schedule RID
\  +144 action   +152 schema   +160 operand digest   +192 trigger digest
\  +224 effects   +232 time ms   +240 disclosure bytes   +248 output bytes
\  +256 granted (wall ms, 0 when unknown)   +264 zero to 272
272 CONSTANT SPERM-PERMISSION-SIZE
: SPERM-P.RID              ( p -- rid ) ;
: SPERM-P.PRACTICE         ( p -- rid ) 32 + ;
: SPERM-P.REVISION         ( p -- a ) 64 + ;
: SPERM-P.SERIAL           ( p -- a ) 72 + ;
: SPERM-P.STORE            ( p -- id ) 80 + ;
: SPERM-P.SCHEDULE         ( p -- rid ) 112 + ;
: SPERM-P.ACTION           ( p -- a ) 144 + ;
: SPERM-P.SCHEMA           ( p -- a ) 152 + ;
: SPERM-P.OPERANDS-DIGEST  ( p -- digest ) 160 + ;
: SPERM-P.TRIGGER-DIGEST   ( p -- digest ) 192 + ;
: SPERM-P.EFFECTS          ( p -- a ) 224 + ;
: SPERM-P.TIME             ( p -- a ) 232 + ;
: SPERM-P.DISCLOSURE       ( p -- a ) 240 + ;
: SPERM-P.OUTPUT           ( p -- a ) 248 + ;
: SPERM-P.GRANTED          ( p -- a ) 256 + ;
: _SPERM-P.RESERVED        ( p -- a ) 264 + ;

\ The header:
\    +0 the store's identity (32 bytes)   +32 next serial
\   +40 permission count   +48 zero to 64
64 CONSTANT SPERM-HEADER-SIZE
: SPERM-H.STORE-ID    ( h -- id ) ;
: SPERM-H.SERIAL      ( h -- a ) 32 + ;
: _SPERM-H.COUNT      ( h -- a ) 40 + ;
: _SPERM-H.RESERVED   ( h -- a ) 48 + ;

: _SPERM-MAGIC$  ( -- address length ) S" AKSCHPRM" ;
1 CONSTANT _SPERM-FORMAT

: _SPERM-ZERO?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _SPERM-DOMAIN$  ( -- address length ) S" akashic.sched.permission.v1" ;

\ The RID of permission SERIAL in the store with identity ID, into DEST.
\ DEST holds the serial's bytes while they are hashed.
: _SPERM-RID!  ( id serial dest -- )
    TUCK !
    SHA3-256-BEGIN
    _SPERM-DOMAIN$ SHA3-256-ADD
    SWAP 32 SHA3-256-ADD
    DUP 8 SHA3-256-ADD
    SHA3-256-END ;

\ =====================================================================
\  The store descriptor
\ =====================================================================

0x5254534D52455053 CONSTANT _SPERM-MAGIC  \ "SPERMSTR"

  0 CONSTANT _SPERM-MAGIC-OFF
  8 CONSTANT _SPERM-SELF
 16 CONSTANT _SPERM-VFS
 24 CONSTANT _SPERM-STATE
 32 CONSTANT _SPERM-REASON
 40 CONSTANT _SPERM-GENERATION
 48 CONSTANT _SPERM-TABLE       \ RTAB-SIZE bytes
 72 CONSTANT _SPERM-HEADER
\ Scratch: a RID, and the payload a check reads.
_SPERM-HEADER SPERM-HEADER-SIZE + CONSTANT _SPERM-RID
_SPERM-RID 32 + CONSTANT _SPERM-PAYLOAD
\ The checked-record callbacks see the store up to here.
_SPERM-PAYLOAD 8 + CONSTANT _SPERM-CONTEXT-U
_SPERM-CONTEXT-U CONSTANT _SPERM-REPL
_SPERM-REPL VREPL-SIZE + 7 + -8 AND CONSTANT _SPERM-SPEC
_SPERM-SPEC CREC-SPEC-SIZE + 7 + -8 AND CONSTANT _SPERM-WORK
_SPERM-WORK CREC-WORK-SIZE + 7 + -8 AND CONSTANT SPERM-SIZE

: _SPERM.MAGIC       ( store -- a ) _SPERM-MAGIC-OFF + ;
: _SPERM.SELF        ( store -- a ) _SPERM-SELF + ;
: _SPERM.VFS         ( store -- a ) _SPERM-VFS + ;
: _SPERM.STATE       ( store -- a ) _SPERM-STATE + ;
: _SPERM.REASON      ( store -- a ) _SPERM-REASON + ;
: _SPERM.GENERATION  ( store -- a ) _SPERM-GENERATION + ;
: _SPERM.TABLE       ( store -- table ) _SPERM-TABLE + ;
: SPERM-HEADER       ( store -- header ) _SPERM-HEADER + ;
: _SPERM.RID         ( store -- rid ) _SPERM-RID + ;
: _SPERM.PAYLOAD     ( store -- a ) _SPERM-PAYLOAD + ;
: _SPERM.REPL        ( store -- replacement ) _SPERM-REPL + ;
: _SPERM.SPEC        ( store -- spec ) _SPERM-SPEC + ;
: _SPERM.WORK        ( store -- work ) _SPERM-WORK + ;

: SPERM-VALID?  ( store -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SPERM.MAGIC @ _SPERM-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SPERM.SELF @ = ;

: SPERM-STATE@  ( store -- state ) _SPERM.STATE @ ;
\ Why a blocked store is blocked; 0 otherwise.
: SPERM-REASON@  ( store -- reason ) _SPERM.REASON @ ;
\ The generation of the file the table came from; 0 before the first.
: SPERM-GENERATION@  ( store -- n ) _SPERM.GENERATION @ ;

: SPERM-COUNT@  ( store -- n ) _SPERM.TABLE RTAB-COUNT@ ;
: SPERM-NTH  ( index store -- permission )
    _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-NTH ;

\ Where the permission RID names is or belongs.
: _SPERM-SEARCH  ( rid store -- index found? )
    DUP _SPERM.TABLE @ SWAP SPERM-COUNT@ SPERM-PERMISSION-SIZE RTAB-SEARCH ;

\ Blocking frees the table: a blocked store holds nothing to trust.
: _SPERM-BLOCK!  ( reason store -- )
    DUP _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-FREE
    DUP SPERM-HEADER SPERM-HEADER-SIZE 0 FILL
    SPERM-BLOCKED OVER _SPERM.STATE !
    _SPERM.REASON ! ;

\ OK when the store can take an operation.
: _SPERM-READY  ( store -- status )
    DUP SPERM-VALID? 0= IF DROP SPERM-S-INVALID EXIT THEN
    SPERM-STATE@ DUP SPERM-READY = IF DROP SPERM-S-OK EXIT THEN
    SPERM-BLOCKED = IF SPERM-S-BLOCKED ELSE SPERM-S-STATE THEN ;

\ The store's 32-byte identity, drawn from the entropy source when its
\ first permission needs it for a RID.  The next commit saves it.
: _SPERM-IDENTITY  ( store -- status )
    SPERM-HEADER SPERM-H.STORE-ID
    DUP RID-ZERO? 0= IF DROP SPERM-S-OK EXIT THEN
    DUP RID-SIZE ENTROPY-FILL ENTROPY-S-OK <> IF
        RID-CLEAR SPERM-S-ENTROPY EXIT
    THEN
    RID-ZERO? IF SPERM-S-ENTROPY ELSE SPERM-S-OK THEN ;

\ =====================================================================
\  Validation
\ =====================================================================
\  OPEN checks every file it reads and every write the file it writes.
\  While a check runs, the store holds the payload it reads.

: _SPERM-RECORDS  ( payload -- records ) SPERM-HEADER-SIZE + ;
\ The payload's INDEX-th permission.
: _SPERM-P-NTH  ( index store -- permission )
    _SPERM.PAYLOAD @ _SPERM-RECORDS SWAP SPERM-PERMISSION-SIZE * + ;
: _SPERM-P-COUNT  ( store -- n ) _SPERM.PAYLOAD @ _SPERM-H.COUNT @ ;

\ The count describes the payload exactly: the bytes after the header are
\ that many permissions and nothing more.  Dividing, not multiplying, so
\ no count can wrap.  The record's framing guarantees the header.
: _SPERM-GEOMETRY-OK?  ( payload payload-u -- flag )
    SPERM-HEADER-SIZE - SPERM-PERMISSION-SIZE /MOD      ( payload rem n )
    ROT _SPERM-H.COUNT @ = SWAP 0= AND ;

\ An identity, a serial counter past zero, and zero reserved bytes.
: _SPERM-HEADER-OK?  ( payload -- flag )
    DUP SPERM-H.STORE-ID RID-ZERO? IF DROP 0 EXIT THEN
    DUP SPERM-H.SERIAL @ 1 < IF DROP 0 EXIT THEN
    _SPERM-H.RESERVED 16 _SPERM-ZERO? ;

\ A permission: the RID its serial gives, below the serial counter; a
\ Practice; a schedule of a store; an automatic action at its schema;
\ both digests; positive limits and no effects, which the catalog does
\ not take yet; and zero reserved bytes.
: _SPERM-PERMISSION-OK?  ( permission store -- flag )
    OVER SPERM-P.SERIAL @ DUP 1 < SWAP
    2 PICK _SPERM.PAYLOAD @ SPERM-H.SERIAL @ < 0= OR IF 2DROP 0 EXIT THEN
    DUP _SPERM.PAYLOAD @ SPERM-H.STORE-ID 2 PICK SPERM-P.SERIAL @
        2 PICK _SPERM.RID _SPERM-RID!
    _SPERM.RID OVER RID= 0= IF DROP 0 EXIT THEN
    DUP SPERM-P.PRACTICE RID-ZERO?
    OVER SPERM-P.STORE RID-ZERO? OR
    OVER SPERM-P.SCHEDULE RID-ZERO? OR
    OVER SPERM-P.REVISION @ 1 < OR
    OVER SPERM-P.OPERANDS-DIGEST 32 _SPERM-ZERO? OR
    OVER SPERM-P.TRIGGER-DIGEST 32 _SPERM-ZERO? OR
    OVER SPERM-P.GRANTED @ 0< OR
    OVER _SPERM-P.RESERVED 8 _SPERM-ZERO? 0= OR
    IF DROP 0 EXIT THEN
    DUP SPERM-P.ACTION @ OVER SPERM-P.SCHEMA @ SACT-CLASS SACT-AUTOMATIC <> IF
        DROP 0 EXIT
    THEN
    DUP SPERM-P.EFFECTS @ IF DROP 0 EXIT THEN
    DUP SPERM-P.TIME @ 0>
    OVER SPERM-P.DISCLOSURE @ 0> AND
    SWAP SPERM-P.OUTPUT @ 0> AND ;

\ Whether two permissions are for one schedule of one store in one
\ Practice.
: _SPERM-SAME-SUBJECT?  ( a b -- flag )
    OVER SPERM-P.PRACTICE OVER SPERM-P.PRACTICE RID=
    2 PICK SPERM-P.STORE 2 PICK SPERM-P.STORE RID= AND
    ROT SPERM-P.SCHEDULE ROT SPERM-P.SCHEDULE RID= AND ;

\ Whether any permission after the I-th has its subject.
: _SPERM-CLASH?  ( i store -- flag )
    DUP _SPERM-P-COUNT 2 PICK 1+ ?DO          ( i store )
        2DUP _SPERM-P-NTH I 2 PICK _SPERM-P-NTH _SPERM-SAME-SUBJECT? IF
            2DROP -1 UNLOOP EXIT
        THEN
    LOOP
    2DROP 0 ;

\ The permissions are ascending by RID, each sound, no two the same
\ subject's.
: _SPERM-TABLE-OK?  ( store -- flag )
    DUP _SPERM.PAYLOAD @ _SPERM-RECORDS OVER _SPERM-P-COUNT
    SPERM-PERMISSION-SIZE RTAB-ASCENDING? 0= IF DROP 0 EXIT THEN
    DUP _SPERM-P-COUNT 0 ?DO
        I OVER _SPERM-P-NTH OVER _SPERM-PERMISSION-OK? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        I OVER _SPERM-CLASH? IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ The checked-record callbacks.  The context is the store's head.
: _SPERM-VALIDATE  ( store store-u payload payload-u tag -- status )
    DROP 2SWAP DROP >R                       ( payload payload-u ; R: store )
    OVER R@ _SPERM.PAYLOAD !
    _SPERM-GEOMETRY-OK? 0= IF R> DROP CREC-S-SEMANTIC EXIT THEN
    R@ _SPERM.PAYLOAD @ _SPERM-HEADER-OK? 0= IF R> DROP CREC-S-SEMANTIC EXIT THEN
    R> _SPERM-TABLE-OK? IF CREC-S-OK ELSE CREC-S-SEMANTIC THEN ;

: _SPERM-ENCODE  ( store store-u payload payload-u tag -- status )
    2DROP NIP                                ( store payload )
    OVER SPERM-HEADER OVER SPERM-HEADER-SIZE MOVE
    OVER SPERM-COUNT@ OVER _SPERM-H.COUNT !
    SPERM-HEADER-SIZE +
    SWAP _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-PUT DROP
    CREC-S-OK ;

: _SPERM-PAYLOAD-U  ( store -- payload-u )
    SPERM-COUNT@ SPERM-PERMISSION-SIZE * SPERM-HEADER-SIZE + ;

\ =====================================================================
\  Reading the file
\ =====================================================================

\ An empty store: the serial counter at one, no identity yet.
: _SPERM-FRESH  ( store -- )
    0 OVER _SPERM.GENERATION !
    SPERM-HEADER DUP SPERM-HEADER-SIZE 0 FILL
    1 SWAP SPERM-H.SERIAL ! ;

\ The file open for reading, or 0 when it does not exist.
: _SPERM-OPEN-READ  ( store -- fd|0 status )
    >R R@ _SPERM.REPL VREPL-TARGET$ VFS-FF-READ R> _SPERM.VFS @ VFS-OPEN?
    ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF 0 SPERM-S-OK ELSE 0 SPERM-S-IO THEN
        EXIT
    THEN
    SPERM-S-OK ;

\ Validates the file's bytes and takes their permissions and generation.
\ A file that fails its checks blocks the store.
: _SPERM-TAKE-FILE  ( record record-u store -- status )
    >R R@ _SPERM-CONTEXT-U 2SWAP R@ _SPERM.SPEC R@ _SPERM.WORK CREC-VALIDATE
    ?DUP IF
        CREC-S-UNSUPPORTED = IF SPERM-R-FUTURE ELSE SPERM-R-CORRUPT THEN
        R> _SPERM-BLOCK! SPERM-S-OK EXIT
    THEN
    R@ _SPERM.WORK CREC-TAG@ R@ _SPERM.GENERATION !
    R@ _SPERM.WORK CREC-PAYLOAD$ DROP                   ( payload )
    DUP R@ SPERM-HEADER SPERM-HEADER-SIZE MOVE
    \ In memory the table keeps its own count.
    0 R@ SPERM-HEADER _SPERM-H.COUNT !
    DUP _SPERM-RECORDS SWAP _SPERM-H.COUNT @
    R> _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-TAKE
    IF SPERM-S-NOMEM ELSE SPERM-S-OK THEN ;

\ Reads the file into the empty table.  A missing file leaves an empty
\ store; one that is too short to be a record, unreadable, or refused
\ blocks it.  Fails only for want of memory to hold it.
: _SPERM-LOAD  ( store -- status )
    DUP _SPERM-OPEN-READ ?DUP IF
        NIP DROP SPERM-R-IO SWAP _SPERM-BLOCK! SPERM-S-OK EXIT
    THEN                                                ( store fd|0 )
    ?DUP 0= IF _SPERM-FRESH SPERM-S-OK EXIT THEN        ( store fd )
    DUP VFS-SIZE                                        ( store fd size )
    DUP CREC-HEADER-SIZE < IF
        DROP VFS-CLOSE? DROP SPERM-R-CORRUPT SWAP _SPERM-BLOCK! SPERM-S-OK EXIT
    THEN
    DUP ALLOCATE IF
        2DROP VFS-CLOSE? DROP DROP SPERM-S-NOMEM EXIT
    THEN                                                ( store fd size buffer )
    2DUP SWAP 4 PICK VFS-READ-EXACT                     ( store fd size buffer ior )
    3 PICK VFS-CLOSE? DROP
    >R ROT DROP SWAP R>                                 ( store buffer size ior )
    IF DROP FREE SPERM-R-IO SWAP _SPERM-BLOCK! SPERM-S-OK EXIT THEN
    OVER SWAP 3 PICK _SPERM-TAKE-FILE                   ( store buffer status )
    SWAP FREE NIP ;

\ Drops what memory holds and reads the file again, returning STATUS.  A
\ file that can no longer be read blocks the store.
: _SPERM-RELOAD  ( status store -- status )
    DUP _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-FREE
    DUP ['] _SPERM-LOAD CATCH IF DROP SPERM-S-NOMEM THEN  ( status store load )
    IF SPERM-R-IO SWAP _SPERM-BLOCK! DROP SPERM-S-BLOCKED EXIT THEN
    SPERM-STATE@ SPERM-BLOCKED = IF DROP SPERM-S-BLOCKED THEN ;

\ Finishes or undoes an interrupted replacement.  One nobody can resolve
\ blocks the store.
: _SPERM-RECOVER  ( store -- )
    DUP _SPERM.REPL ['] VREPL-RECOVER CATCH IF DROP VREPL-S-RECOVERY THEN
    DUP VREPL-S-OK = OVER VREPL-S-ROLLED-BACK = OR
    SWAP VREPL-S-COMMITTED-CLEANUP = OR
    IF DROP ELSE SPERM-R-UNCERTAIN SWAP _SPERM-BLOCK! THEN ;

\ =====================================================================
\  Writing the file
\ =====================================================================

\ The file's bytes for the table, one generation on, checked as OPEN
\ would check them.  The caller frees the record.
: _SPERM-ENCODE-FILE  ( store -- record record-u status )
    DUP _SPERM-PAYLOAD-U OVER _SPERM.SPEC CREC-MEASURE IF
        2DROP 0 0 SPERM-S-INVALID EXIT
    THEN                                     ( store capacity )
    DUP ALLOCATE IF 2DROP DROP 0 0 SPERM-S-NOMEM EXIT THEN
    SWAP                                     ( store record capacity )
    2 PICK _SPERM-CONTEXT-U
    4 PICK _SPERM-PAYLOAD-U
    5 PICK _SPERM.GENERATION @ 1+
    5 PICK 5 PICK
    8 PICK _SPERM.SPEC 9 PICK _SPERM.WORK CREC-ENCODE
                                             ( store record capacity record-u status )
    IF 2DROP FREE DROP 0 0 SPERM-S-INVALID EXIT THEN
    NIP                                      ( store record record-u )
    2 PICK _SPERM-CONTEXT-U 2OVER 6 PICK _SPERM.SPEC 7 PICK _SPERM.WORK
        CREC-VALIDATE
    IF DROP FREE DROP 0 0 SPERM-S-INVALID EXIT THEN
    ROT DROP SPERM-S-OK ;

\ The store after a replacement: one generation on, unchanged and
\ reloaded, or blocked when nobody can tell which.
: _SPERM-REPLACED  ( vrepl-status store -- status )
    OVER VREPL-S-OK = 2 PICK VREPL-S-COMMITTED-CLEANUP = OR IF
        NIP 1 SWAP _SPERM.GENERATION +! SPERM-S-OK EXIT
    THEN
    OVER VREPL-S-IO = 2 PICK VREPL-S-CONFLICT = OR
    2 PICK VREPL-S-BUSY = OR 2 PICK VREPL-S-INVALID = OR IF
        NIP SPERM-S-IO SWAP _SPERM-RELOAD EXIT
    THEN
    NIP SPERM-R-UNCERTAIN SWAP _SPERM-BLOCK! SPERM-S-BLOCKED ;

\ Writes the table as the next generation.  Any failure reloads the last
\ committed file, undoing the edits; one whose outcome is unknown blocks
\ the store instead.  The store has its identity: its first permission
\ drew it.
: _SPERM-COMMIT  ( store -- status )
    DUP _SPERM-ENCODE-FILE ?DUP IF NIP NIP SWAP _SPERM-RELOAD EXIT THEN
                                             ( store record record-u )
    2DUP 4 PICK _SPERM.REPL ['] VREPL-REPLACE CATCH IF
        2DROP DROP VREPL-S-UNCERTAIN
    THEN                                     ( store record record-u vstatus )
    NIP SWAP FREE
    SWAP _SPERM-REPLACED ;

\ =====================================================================
\  Lifecycle
\ =====================================================================

\ Configures STORE, SPERM-SIZE cell-aligned bytes, to keep its file at
\ PATH, an absolute path, in VFS.  The store starts closed.
: SPERM-INIT  ( vfs path path-u store -- status )
    DUP 0= OVER 7 AND OR IF 2DROP 2DROP SPERM-S-INVALID EXIT THEN
    DUP SPERM-VALID? IF 2DROP 2DROP SPERM-S-STATE EXIT THEN
    3 PICK 0= IF 2DROP 2DROP SPERM-S-INVALID EXIT THEN
    DUP SPERM-SIZE 0 FILL
    >R
    2 PICK R@ _SPERM.VFS !
    2 PICK R@ _SPERM.REPL VREPL-INIT IF
        2DROP DROP R> SPERM-SIZE 0 FILL SPERM-S-INVALID EXIT
    THEN
    R@ _SPERM.REPL VREPL-DERIVE-PATHS! IF
        DROP R> SPERM-SIZE 0 FILL SPERM-S-INVALID EXIT
    THEN
    DROP
    _SPERM-MAGIC$ _SPERM-FORMAT CREC-TAG-POSITIVE ['] _SPERM-ENCODE
        ['] _SPERM-VALIDATE R@ _SPERM.SPEC CREC-SPEC-INIT
    \ The file grows with the table; memory, not the format, bounds it.
    SPERM-HEADER-SIZE 1 62 LSHIFT 8 R@ _SPERM.SPEC CREC-SPEC-FRAMED! OR
    R@ _SPERM.SPEC CREC-SPEC-SEAL OR
    R@ _SPERM.WORK CREC-WORK-INIT OR IF
        R> SPERM-SIZE 0 FILL SPERM-S-INVALID EXIT
    THEN
    R@ DUP _SPERM.SELF !
    _SPERM-MAGIC R@ _SPERM.MAGIC !
    SPERM-CLOSED R> _SPERM.STATE !
    SPERM-S-OK ;

\ Frees what OPEN read.  The store stays configured.
: SPERM-CLOSE  ( store -- status )
    DUP SPERM-VALID? 0= IF DROP SPERM-S-INVALID EXIT THEN
    DUP _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-FREE
    DUP SPERM-HEADER SPERM-HEADER-SIZE 0 FILL
    0 OVER _SPERM.GENERATION !
    0 OVER _SPERM.REASON !
    SPERM-CLOSED SWAP _SPERM.STATE !
    SPERM-S-OK ;

\ Recovers the file and reads it.  Returns OK when the store is READY, or
\ BLOCKED with SPERM-REASON@ saying why it cannot be used.
: SPERM-OPEN  ( store -- status )
    DUP SPERM-VALID? 0= IF DROP SPERM-S-INVALID EXIT THEN
    DUP SPERM-STATE@ SPERM-CLOSED <> IF DROP SPERM-S-STATE EXIT THEN
    SPERM-READY OVER _SPERM.STATE !
    0 OVER _SPERM.REASON !
    DUP _SPERM-RECOVER
    DUP SPERM-STATE@ SPERM-READY <> IF DROP SPERM-S-BLOCKED EXIT THEN
    SPERM-S-OK SWAP _SPERM-RELOAD ;

\ =====================================================================
\  Operations
\ =====================================================================

\ The permission RID names, or 0.  It stays put until the next
\ operation.
: SPERM-FIND  ( rid store -- permission|0 )
    DUP _SPERM-READY IF 2DROP 0 EXIT THEN
    DUP _SPERM.TABLE @ SWAP SPERM-COUNT@ SPERM-PERMISSION-SIZE RTAB-RECORD ;

\ The permission in PRACTICE for REQUEST's schedule of its store, or 0.
: _SPERM-SUBJECT  ( request practice store -- permission|0 )
    DUP SPERM-COUNT@ 0 ?DO
        I OVER SPERM-NTH                     ( request practice store p )
        DUP SPERM-P.PRACTICE 3 PICK RID=
        OVER SPERM-P.STORE 5 PICK SDSP-R.STORE RID= AND
        OVER SPERM-P.SCHEDULE 5 PICK SDSP-R.SCHEDULE RID= AND
        IF NIP NIP NIP UNLOOP EXIT THEN
        DROP
    LOOP
    DROP 2DROP 0 ;

\ Whether REQUEST asks for exactly what PERMISSION grants: its action and
\ schema, and both digests.  The operand digest covers the limits.
: _SPERM-SAME-GRANT?  ( request permission -- flag )
    OVER SDSP-R.ACTION @ OVER SPERM-P.ACTION @ =
    2 PICK SDSP-R.SCHEMA @ 2 PICK SPERM-P.SCHEMA @ = AND
    2 PICK SDSP-R.OPERANDS-DIGEST 32 3 PICK SPERM-P.OPERANDS-DIGEST 32 COMPARE
    0= AND
    2 PICK SDSP-R.TRIGGER-DIGEST 32 3 PICK SPERM-P.TRIGGER-DIGEST 32 COMPARE
    0= AND
    NIP NIP ;

\ Whether PRACTICE may grant REQUEST: a request SDSP-REQUEST-OK? accepts
\ that names no occurrence, has its trigger digest, and names no other
\ Practice.
: SPERM-GRANTABLE?  ( request practice -- flag )
    DUP RID-ZERO? IF 2DROP 0 EXIT THEN
    OVER 0 SDSP-REQUEST-OK? IF 2DROP 0 EXIT THEN
    OVER SDSP-R.TRIGGER-DIGEST 32 _SPERM-ZERO? IF 2DROP 0 EXIT THEN
    OVER SDSP-R.PRACTICE RID-ZERO? IF 2DROP -1 EXIT THEN
    SWAP SDSP-R.PRACTICE RID= ;

\ A new permission in the table: its serial, the RID that gives, and
\ revision 1.
: _SPERM-NEW  ( store -- permission status )
    DUP _SPERM-IDENTITY ?DUP IF NIP 0 SWAP EXIT THEN
    DUP SPERM-HEADER DUP SPERM-H.SERIAL @          ( store header serial )
    SWAP SPERM-H.STORE-ID SWAP 2 PICK _SPERM.RID _SPERM-RID!
    DUP _SPERM.RID OVER _SPERM-SEARCH IF DROP 0 SPERM-S-INVALID EXIT THEN
    OVER _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-RESERVE IF
        2DROP 0 SPERM-S-NOMEM EXIT
    THEN                                           ( store index )
    OVER _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-INSERT     ( store p )
    OVER _SPERM.RID OVER RID-SIZE MOVE
    OVER SPERM-HEADER SPERM-H.SERIAL DUP @ 2 PICK SPERM-P.SERIAL ! 1 SWAP +!
    1 OVER SPERM-P.REVISION !
    NIP SPERM-S-OK ;

\ The limits in REQUEST's operands, into PERMISSION.
: _SPERM-LIMITS!  ( request permission -- )
    SWAP SDSP-OPERANDS$ DROP                       ( p operands )
    DUP SACT-O.EFFECTS @ 2 PICK SPERM-P.EFFECTS !
    DUP SACT-O.TIME @ 2 PICK SPERM-P.TIME !
    DUP SACT-O.DISCLOSURE @ 2 PICK SPERM-P.DISCLOSURE !
    SACT-O.OUTPUT @ SWAP SPERM-P.OUTPUT ! ;

\ Writes the subject and grant REQUEST asks for into PERMISSION, in
\ PRACTICE, granted at NOW.
: _SPERM-FILL  ( request practice now permission -- )
    SWAP 0 MAX OVER SPERM-P.GRANTED !              ( request practice p )
    SWAP OVER SPERM-P.PRACTICE RID-SIZE MOVE       ( request p )
    OVER SDSP-R.STORE OVER SPERM-P.STORE RID-SIZE MOVE
    OVER SDSP-R.SCHEDULE OVER SPERM-P.SCHEDULE RID-SIZE MOVE
    OVER SDSP-R.ACTION @ OVER SPERM-P.ACTION !
    OVER SDSP-R.SCHEMA @ OVER SPERM-P.SCHEMA !
    OVER SDSP-R.OPERANDS-DIGEST OVER SPERM-P.OPERANDS-DIGEST 32 MOVE
    OVER SDSP-R.TRIGGER-DIGEST OVER SPERM-P.TRIGGER-DIGEST 32 MOVE
    _SPERM-LIMITS! ;

\ Grants REQUEST in PRACTICE at NOW, the wall clock in milliseconds or -1
\ when it is not set: an approval Desk's user gave for one schedule.  A
\ schedule with no permission in PRACTICE gets a new one at revision 1.
\ One whose permission grants exactly this keeps it, unwritten.  One
\ whose permission grants something else has its grant replaced and its
\ revision moved on.  Returns the permission, which stays put until the
\ next operation.
: SPERM-GRANT  ( request practice now store -- permission status )
    DUP _SPERM-READY ?DUP IF >R 2DROP 2DROP 0 R> EXIT THEN
    >R                                             ( request practice now ; R: store )
    2 PICK 2 PICK SPERM-GRANTABLE? 0= IF
        2DROP DROP R> DROP 0 SPERM-S-INVALID EXIT
    THEN
    2 PICK 2 PICK R@ _SPERM-SUBJECT ?DUP IF        ( request practice now p )
        3 PICK OVER _SPERM-SAME-GRANT? IF
            NIP NIP NIP R> DROP SPERM-S-OK EXIT
        THEN
        1 OVER SPERM-P.REVISION +!
    ELSE
        R@ _SPERM-NEW ?DUP IF
            NIP >R 2DROP DROP R> R> _SPERM-RELOAD 0 SWAP EXIT
        THEN
    THEN
    DUP >R _SPERM-FILL R>                          ( p ; R: store )
    R> _SPERM-COMMIT ?DUP IF NIP 0 SWAP EXIT THEN
    SPERM-S-OK ;

\ Revokes the permission RID names: it is deleted, and its RID is never
\ granted again.
: SPERM-REVOKE  ( rid store -- status )
    DUP _SPERM-READY ?DUP IF NIP NIP EXIT THEN
    TUCK _SPERM-SEARCH 0= IF 2DROP SPERM-S-NOT-FOUND EXIT THEN   ( store index )
    OVER _SPERM.TABLE SPERM-PERMISSION-SIZE RTAB-DELETE
    _SPERM-COMMIT ;

\ How REQUEST, one SDSP-REQUEST-OK? accepts, stands in PRACTICE: approved
\ only when the permission it names exists at the revision it names, in
\ PRACTICE, for its schedule of its store, granting exactly its action,
\ schema, operands and trigger.  A store that cannot answer is
\ unavailable.
: SPERM-MATCH  ( request practice store -- standing )
    DUP _SPERM-READY IF 2DROP DROP SDSP-A-UNAVAILABLE EXIT THEN
    2 PICK SDSP-R.PERMISSION RID-ZERO? IF 2DROP DROP SDSP-A-NONE EXIT THEN
    2 PICK SDSP-R.PERMISSION SWAP SPERM-FIND       ( request practice p|0 )
    ?DUP 0= IF 2DROP SDSP-A-WITHDRAWN EXIT THEN
    DUP SPERM-P.PRACTICE ROT RID= 0= IF 2DROP SDSP-A-PRACTICE EXIT THEN
    OVER SDSP-R.PRACTICE RID-ZERO? 0= IF           ( request p )
        OVER SDSP-R.PRACTICE OVER SPERM-P.PRACTICE RID= 0= IF
            2DROP SDSP-A-PRACTICE EXIT
        THEN
    THEN
    OVER SDSP-R.PERMISSION-REVISION @ OVER SPERM-P.REVISION @ <> IF
        2DROP SDSP-A-CHANGED EXIT
    THEN
    OVER SDSP-R.STORE OVER SPERM-P.STORE RID=
    2 PICK SDSP-R.SCHEDULE 2 PICK SPERM-P.SCHEDULE RID= AND 0= IF
        2DROP SDSP-A-CHANGED EXIT
    THEN
    _SPERM-SAME-GRANT? IF SDSP-A-APPROVED ELSE SDSP-A-CHANGED THEN ;
