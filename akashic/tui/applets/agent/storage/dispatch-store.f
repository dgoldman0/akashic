\ =====================================================================
\  dispatch-store.f - The Agent's record of scheduled runs
\ =====================================================================
\  The Agent records each scheduled run that Desk's broker hands it.  A
\  run is recorded, accepted, before its provider starts, and its dispatch
\  key then names it for good: handing the same occurrence over again
\  finds the same run, and a run that may have started is never
\  forgotten.  When the run ends, the record says how, with the transcript
\  of what was said.
\
\  A run's RID is SHA3-256 of a domain, the store's identity, the Practice
\  and the dispatch key, so one occurrence always has one run.  A request
\  digest tells whether a later hand-over with the same key asks for
\  exactly the same run, or for another: a conflict.
\
\  The newest ended runs, as many as the store's KEEP setting (32 at
\  first), keep the request they ran and their transcript.  Older ones
\  keep only their row: when they ran, how they ended, and the run's
\  identity.  A run still in flight is never trimmed.
\
\  Runs live in one file, replaced whole and atomically through
\  vfs-replace.f.  The file is a CRC-checked record (checked-record.f,
\  magic AKAGDISP, format 1) whose tag is its generation: a header, the
\  runs in serial order, their keys in key order, then a blob region
\  (blob-slot.f) holding each kept run's request and then each one's
\  transcript.  OPEN finishes or undoes an interrupted replacement, then
\  reads the file.  A missing file is an empty store.  A file that fails
\  its checks, or that cannot be read, blocks the store with the reason:
\  nothing loads and nothing is written.  A write checks its file as OPEN
\  would, and one that fails reloads the last committed file.
\
\  The store is caller-serialized.  A run a word returns stays put until
\  the next operation.
\
\  Public API:
\    ADST-INIT         ( vfs path path-u store -- status )
\    ADST-OPEN         ( store -- status )
\    ADST-CLOSE        ( store -- status )
\    ADST-STATE@       ( store -- state )
\    ADST-REASON@      ( store -- reason )
\    ADST-GENERATION@  ( store -- n )
\    ADST-HEADER       ( store -- header )
\    ADST-COUNT@       ( store -- n )
\    ADST-NTH          ( index store -- run )
\    ADST-FIND         ( key store -- run|0 )
\    ADST-KEPT?        ( run -- flag )
\    ADST-REQUEST$     ( run -- address length )
\    ADST-TRANSCRIPT$  ( run -- address length )
\    ADST-DIGEST       ( request dest -- )
\    ADST-ACCEPT       ( request now store -- run status )
\    ADST-TRANSCRIPT!  ( address length run store -- status )
\    ADST-FINISH       ( outcome reason reply-u now run store -- status )
\    ADST-RECONCILE    ( now store -- n status )
\    ADST-KEEP!        ( n store -- status )
\ =====================================================================

PROVIDED akashic-agent-dispatch-store

REQUIRE ../../../../runtime/identity.f
REQUIRE ../../../../math/sha3.f
REQUIRE ../../../../math/entropy.f
REQUIRE ../../../../utils/checked-record.f
REQUIRE ../../../../utils/fs/vfs.f
REQUIRE ../../../../utils/fs/vfs-replace.f
REQUIRE ../../../../utils/record-table.f
REQUIRE ../../../../utils/blob-slot.f
REQUIRE ../../../../interop/scheduled-dispatch.f

0 CONSTANT ADST-S-OK
1 CONSTANT ADST-S-INVALID
2 CONSTANT ADST-S-NOMEM
3 CONSTANT ADST-S-IO
4 CONSTANT ADST-S-BLOCKED
5 CONSTANT ADST-S-STATE
6 CONSTANT ADST-S-ENTROPY
7 CONSTANT ADST-S-EXISTING     \ a run with the key asks for the same
8 CONSTANT ADST-S-CONFLICT     \ a run with the key asks for something else
9 CONSTANT ADST-S-NOT-FOUND

\ Store states.
0 CONSTANT ADST-CLOSED
1 CONSTANT ADST-READY
2 CONSTANT ADST-BLOCKED

\ Why a store is blocked.
1 CONSTANT ADST-R-CORRUPT      \ the file failed its checks
2 CONSTANT ADST-R-FUTURE       \ a newer format than this code reads
3 CONSTANT ADST-R-UNCERTAIN    \ a replacement's outcome is unknown
4 CONSTANT ADST-R-IO           \ the file could not be read into memory

\ A run's phase.
1 CONSTANT ADST-ACCEPTED       \ recorded; its provider may have started
2 CONSTANT ADST-ENDED

32 CONSTANT ADST-DEFAULT-KEEP

\ =====================================================================
\  Records
\ =====================================================================

\ A run:
\    +0 serial   +8 phase   +16 outcome   +24 reason   +32 run RID
\   +64 dispatch key   +96 request digest   +128 Practice
\  +160 permission   +192 its revision   +200 accepted (wall ms, 0 when
\       unknown)   +208 ended (likewise)   +216 reply bytes kept
\  +224 the request's blob slot   +240 the transcript's   +256 zero to 264
264 CONSTANT ADST-RUN-SIZE
: ADST-R.SERIAL      ( run -- a ) ;
: ADST-R.PHASE       ( run -- a ) 8 + ;
: ADST-R.OUTCOME     ( run -- a ) 16 + ;
: ADST-R.REASON      ( run -- a ) 24 + ;
: ADST-R.RID         ( run -- rid ) 32 + ;
: ADST-R.KEY         ( run -- key ) 64 + ;
: ADST-R.DIGEST      ( run -- digest ) 96 + ;
: ADST-R.PRACTICE    ( run -- rid ) 128 + ;
: ADST-R.PERMISSION  ( run -- rid ) 160 + ;
: ADST-R.REVISION    ( run -- a ) 192 + ;
: ADST-R.ACCEPTED    ( run -- a ) 200 + ;
: ADST-R.ENDED       ( run -- a ) 208 + ;
: ADST-R.REPLY-U     ( run -- a ) 216 + ;
224 CONSTANT _ADST-R-REQUEST
240 CONSTANT _ADST-R-TRANSCRIPT
: ADST-R.REQUEST     ( run -- slot ) _ADST-R-REQUEST + ;
: ADST-R.TRANSCRIPT  ( run -- slot ) _ADST-R-TRANSCRIPT + ;
: _ADST-R.RESERVED   ( run -- a ) 256 + ;

\ Whether RUN keeps its request and transcript.
: ADST-KEPT?  ( run -- flag ) ADST-R.REQUEST 8 + @ 0<> ;

\ A key: +0 the dispatch key   +32 its run's serial
40 CONSTANT _ADST-KEY-SIZE

\ The header:
\    +0 the store's identity (32 bytes)   +32 next serial   +40 keep
\   +48 run count   +56 blob bytes
64 CONSTANT ADST-HEADER-SIZE
: ADST-H.STORE-ID  ( h -- id ) ;
: ADST-H.SERIAL    ( h -- a ) 32 + ;
: ADST-H.KEEP      ( h -- a ) 40 + ;
: _ADST-H.COUNT    ( h -- a ) 48 + ;
: _ADST-H.BLOB     ( h -- a ) 56 + ;

\ A run and its key take this much of a payload.
ADST-RUN-SIZE _ADST-KEY-SIZE + CONSTANT _ADST-ROW-U

: _ADST-MAGIC$  ( -- address length ) S" AKAGDISP" ;
1 CONSTANT _ADST-FORMAT

: _ADST-ZERO?  ( address length -- flag )
    BEGIN DUP WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _ADST-RID-DOMAIN$  ( -- address length ) S" akashic.agent.dispatch-run.v1" ;
: _ADST-DIGEST-DOMAIN$  ( -- address length )
    S" akashic.agent.dispatch-request.v1" ;

\ The RID of the run with dispatch KEY, in PRACTICE, in the store with
\ identity ID, into DEST.
: _ADST-RID!  ( id practice key dest -- )
    >R SHA3-256-BEGIN
    _ADST-RID-DOMAIN$ SHA3-256-ADD
    ROT 32 SHA3-256-ADD SWAP 32 SHA3-256-ADD 32 SHA3-256-ADD
    R> SHA3-256-END ;

\ The digest of REQUEST's bytes, into DEST: the same digest is the same
\ request.
: ADST-DIGEST  ( request dest -- )
    >R SHA3-256-BEGIN
    _ADST-DIGEST-DOMAIN$ SHA3-256-ADD
    DUP SDSP-REQUEST-U SHA3-256-ADD
    R> SHA3-256-END ;

\ =====================================================================
\  The store descriptor
\ =====================================================================

0x5254534450534441 CONSTANT _ADST-MAGIC  \ "ADSPDSTR"

  0 CONSTANT _ADST-MAGIC-OFF
  8 CONSTANT _ADST-SELF
 16 CONSTANT _ADST-VFS
 24 CONSTANT _ADST-STATE
 32 CONSTANT _ADST-REASON
 40 CONSTANT _ADST-GENERATION
 48 CONSTANT _ADST-RUNS        \ RTAB-SIZE bytes
 72 CONSTANT _ADST-KEYS        \ RTAB-SIZE bytes
 96 CONSTANT _ADST-HEADER
\ Scratch: a digest, the payload a check reads, and its blob's cursor.
_ADST-HEADER ADST-HEADER-SIZE + CONSTANT _ADST-SCRATCH
_ADST-SCRATCH 32 + CONSTANT _ADST-PAYLOAD
_ADST-PAYLOAD 8 + CONSTANT _ADST-CURSOR
\ The checked-record callbacks see the store up to here.
_ADST-CURSOR BSLOT-CURSOR-SIZE + CONSTANT _ADST-CONTEXT-U
_ADST-CONTEXT-U CONSTANT _ADST-REPL
_ADST-REPL VREPL-SIZE + 7 + -8 AND CONSTANT _ADST-SPEC
_ADST-SPEC CREC-SPEC-SIZE + 7 + -8 AND CONSTANT _ADST-WORK
_ADST-WORK CREC-WORK-SIZE + 7 + -8 AND CONSTANT ADST-SIZE

: _ADST.MAGIC       ( store -- a ) _ADST-MAGIC-OFF + ;
: _ADST.SELF        ( store -- a ) _ADST-SELF + ;
: _ADST.VFS         ( store -- a ) _ADST-VFS + ;
: _ADST.STATE       ( store -- a ) _ADST-STATE + ;
: _ADST.REASON      ( store -- a ) _ADST-REASON + ;
: _ADST.GENERATION  ( store -- a ) _ADST-GENERATION + ;
: _ADST.RUNS        ( store -- table ) _ADST-RUNS + ;
: _ADST.KEYS        ( store -- table ) _ADST-KEYS + ;
: ADST-HEADER       ( store -- header ) _ADST-HEADER + ;
: _ADST.SCRATCH     ( store -- a ) _ADST-SCRATCH + ;
: _ADST.PAYLOAD     ( store -- a ) _ADST-PAYLOAD + ;
: _ADST.CURSOR      ( store -- cursor ) _ADST-CURSOR + ;
: _ADST.REPL        ( store -- replacement ) _ADST-REPL + ;
: _ADST.SPEC        ( store -- spec ) _ADST-SPEC + ;
: _ADST.WORK        ( store -- work ) _ADST-WORK + ;

: ADST-VALID?  ( store -- flag )
    DUP 0= IF EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _ADST.MAGIC @ _ADST-MAGIC <> IF DROP 0 EXIT THEN
    DUP _ADST.SELF @ = ;

: ADST-STATE@  ( store -- state ) _ADST.STATE @ ;
\ Why a blocked store is blocked; 0 otherwise.
: ADST-REASON@  ( store -- reason ) _ADST.REASON @ ;
\ The generation of the file the runs came from; 0 before the first.
: ADST-GENERATION@  ( store -- n ) _ADST.GENERATION @ ;

: ADST-COUNT@  ( store -- n ) _ADST.RUNS RTAB-COUNT@ ;
\ Run INDEX, oldest first.
: ADST-NTH  ( index store -- run ) _ADST.RUNS ADST-RUN-SIZE RTAB-NTH ;

\ Frees the runs, their blobs and their keys.
: _ADST-FREE-TABLES  ( store -- )
    DUP _ADST.RUNS ADST-RUN-SIZE _ADST-R-REQUEST BSLOT-TABLE-FREE
    DUP _ADST.RUNS ADST-RUN-SIZE _ADST-R-TRANSCRIPT BSLOT-TABLE-FREE
    DUP _ADST.RUNS ADST-RUN-SIZE RTAB-FREE
    _ADST.KEYS _ADST-KEY-SIZE RTAB-FREE ;

\ Blocking frees the tables: a blocked store holds nothing to trust.
: _ADST-BLOCK!  ( reason store -- )
    DUP _ADST-FREE-TABLES
    DUP ADST-HEADER ADST-HEADER-SIZE 0 FILL
    ADST-BLOCKED OVER _ADST.STATE !
    _ADST.REASON ! ;

\ OK when the store can take an operation.
: _ADST-READY  ( store -- status )
    DUP ADST-VALID? 0= IF DROP ADST-S-INVALID EXIT THEN
    ADST-STATE@ DUP ADST-READY = IF DROP ADST-S-OK EXIT THEN
    ADST-BLOCKED = IF ADST-S-BLOCKED ELSE ADST-S-STATE THEN ;

\ The store's 32-byte identity, drawn from the entropy source when its
\ first run needs it for a RID.  The next commit saves it.
: _ADST-IDENTITY  ( store -- status )
    ADST-HEADER ADST-H.STORE-ID
    DUP RID-ZERO? 0= IF DROP ADST-S-OK EXIT THEN
    DUP RID-SIZE ENTROPY-FILL ENTROPY-S-OK <> IF
        RID-CLEAR ADST-S-ENTROPY EXIT
    THEN
    RID-ZERO? IF ADST-S-ENTROPY ELSE ADST-S-OK THEN ;

\ =====================================================================
\  Validation
\ =====================================================================
\  OPEN checks every file it reads and every write the file it writes.
\  While a check runs, the store holds the payload it reads.

: _ADST-P-RUNS  ( payload -- runs ) ADST-HEADER-SIZE + ;
: _ADST-P-COUNT  ( payload -- n ) _ADST-H.COUNT @ ;
: _ADST-P-KEYS  ( payload -- keys )
    DUP _ADST-P-RUNS SWAP _ADST-P-COUNT ADST-RUN-SIZE * + ;
: _ADST-P-BLOB  ( payload -- blob )
    DUP _ADST-P-KEYS SWAP _ADST-P-COUNT _ADST-KEY-SIZE * + ;
\ The payload's INDEX-th run.
: _ADST-P-NTH  ( index payload -- run )
    _ADST-P-RUNS SWAP ADST-RUN-SIZE * + ;

\ The count and the blob's size describe the payload exactly: after the
\ header and the blob, the bytes are that many runs and keys and nothing
\ more.  Dividing, not multiplying, so no count can wrap.  The record's
\ framing guarantees the header.
: _ADST-GEOMETRY-OK?  ( payload payload-u -- flag )
    ADST-HEADER-SIZE - OVER _ADST-H.BLOB @            ( payload rest blob )
    DUP 0< IF 2DROP DROP 0 EXIT THEN
    2DUP < IF 2DROP DROP 0 EXIT THEN
    - _ADST-ROW-U /MOD                                 ( payload rem n )
    ROT _ADST-P-COUNT = SWAP 0= AND ;

\ An identity and a serial counter past zero.  The runs' check bounds the
\ setting.
: _ADST-HEADER-OK?  ( payload -- flag )
    DUP ADST-H.STORE-ID RID-ZERO? IF DROP 0 EXIT THEN
    ADST-H.SERIAL @ 0> ;

\ How a recorded run may end: any end the catalog pairs, except not
\ started, which only Daybook records for runs it never handed over.  A
\ run its provider refused to start ends blocked.
: _ADST-END-OK?  ( outcome reason -- flag )
    OVER SACT-O-NOT-STARTED = IF 2DROP 0 EXIT THEN
    SACT-OUTCOME-OK? ;

\ A run: a serial below the counter, the RID its Practice and key give, a
\ request digest, a permission and its revision, times and a reply size
\ not below zero, and zero reserved bytes.  In flight it has no end and
\ keeps its request, and may hold its transcript so far; ended, its end
\ is one a recorded run can have, and it keeps its request or nothing.
: _ADST-RUN-OK?  ( run store -- flag )
    OVER ADST-R.SERIAL @ DUP 1 < SWAP
    2 PICK _ADST.PAYLOAD @ ADST-H.SERIAL @ < 0= OR IF 2DROP 0 EXIT THEN
    DUP _ADST.PAYLOAD @ ADST-H.STORE-ID 2 PICK ADST-R.PRACTICE
    3 PICK ADST-R.KEY 3 PICK _ADST.SCRATCH _ADST-RID!
    _ADST.SCRATCH OVER ADST-R.RID RID= 0= IF DROP 0 EXIT THEN
    DUP ADST-R.KEY 32 _ADST-ZERO?
    OVER ADST-R.DIGEST 32 _ADST-ZERO? OR
    OVER ADST-R.PRACTICE RID-ZERO? OR
    OVER ADST-R.PERMISSION RID-ZERO? OR
    OVER ADST-R.REVISION @ 1 < OR
    OVER ADST-R.ACCEPTED @ 0< OR
    OVER ADST-R.ENDED @ 0< OR
    OVER ADST-R.REPLY-U @ 0< OR
    OVER _ADST-R.RESERVED 8 _ADST-ZERO? 0= OR
    IF DROP 0 EXIT THEN
    DUP ADST-R.PHASE @ ADST-ACCEPTED = IF
        DUP ADST-R.OUTCOME 16 _ADST-ZERO?
        OVER ADST-R.ENDED @ 0= AND
        OVER ADST-R.REPLY-U @ 0= AND
        SWAP ADST-KEPT? AND EXIT
    THEN
    DUP ADST-R.PHASE @ ADST-ENDED <> IF DROP 0 EXIT THEN
    DUP ADST-R.OUTCOME @ OVER ADST-R.REASON @ _ADST-END-OK? 0= IF DROP 0 EXIT THEN
    DUP ADST-KEPT? IF DROP -1 EXIT THEN
    ADST-R.TRANSCRIPT 8 + @ 0= ;

\ Whether the U bytes at REQUEST are the request RUN was accepted for: a
\ hand-over SDSP-REQUEST-OK? accepts, exactly that long, with the run's
\ digest, key, Practice and permission.  Its header is read only once the
\ bytes hold one.
: _ADST-REQUEST-OK?  ( run request u store -- flag )
    >R
    DUP SDSP-REQUEST-HEAD < IF 2DROP DROP R> DROP 0 EXIT THEN
    OVER SDSP-R.SIZE @ <> IF 2DROP R> DROP 0 EXIT THEN
    DUP -1 SDSP-REQUEST-OK? IF 2DROP R> DROP 0 EXIT THEN
    DUP R@ _ADST.SCRATCH ADST-DIGEST
    OVER ADST-R.DIGEST R> _ADST.SCRATCH 32 SWAP 32 COMPARE IF 2DROP 0 EXIT THEN
    OVER ADST-R.KEY OVER SDSP-R.KEY 32 TUCK COMPARE IF 2DROP 0 EXIT THEN
    OVER ADST-R.PRACTICE OVER SDSP-R.PRACTICE RID= 0= IF 2DROP 0 EXIT THEN
    OVER ADST-R.PERMISSION OVER SDSP-R.PERMISSION RID= 0= IF 2DROP 0 EXIT THEN
    SDSP-R.PERMISSION-REVISION @ SWAP ADST-R.REVISION @ = ;

\ Every kept run's request is its own, and the parts fill the blob
\ exactly: each kept run's request, then each one's transcript.
: _ADST-BLOBS-OK?  ( store -- flag )
    DUP _ADST.PAYLOAD @ DUP _ADST-P-BLOB SWAP _ADST-H.BLOB @
    2 PICK _ADST.CURSOR BSLOT-CURSOR-INIT
    DUP _ADST.PAYLOAD @ _ADST-P-COUNT 0 ?DO           ( store )
        I OVER _ADST.PAYLOAD @ _ADST-P-NTH            ( store run )
        DUP ADST-R.REQUEST 2 PICK _ADST.CURSOR BSLOT-NEXT   ( store run a u )
        DUP IF
            3 PICK _ADST-REQUEST-OK? 0= IF DROP 0 UNLOOP EXIT THEN
        ELSE
            2DROP DROP
        THEN
    LOOP
    DUP _ADST.PAYLOAD @ _ADST-P-COUNT 0 ?DO
        I OVER _ADST.PAYLOAD @ _ADST-P-NTH ADST-R.TRANSCRIPT
        OVER _ADST.CURSOR BSLOT-NEXT 2DROP
    LOOP
    DUP _ADST.CURSOR BSLOT-AT@ SWAP _ADST.PAYLOAD @ _ADST-H.BLOB @ = ;

\ The runs, ascending by serial, are each sound, and no more of the ended
\ ones keep their request than the setting says, which is therefore not
\ below zero.
: _ADST-RUNS-OK?  ( store -- flag )
    DUP _ADST.PAYLOAD @ DUP _ADST-P-RUNS SWAP _ADST-P-COUNT
    ADST-RUN-SIZE RTAB-IDS-ASCENDING? 0= IF DROP 0 EXIT THEN
    0 OVER _ADST.PAYLOAD @ _ADST-P-COUNT 0 ?DO        ( store kept )
        I 2 PICK _ADST.PAYLOAD @ _ADST-P-NTH          ( store kept run )
        DUP 3 PICK _ADST-RUN-OK? 0= IF DROP 2DROP 0 UNLOOP EXIT THEN
        DUP ADST-R.PHASE @ ADST-ENDED = SWAP ADST-KEPT? AND IF 1+ THEN
    LOOP
    SWAP _ADST.PAYLOAD @ ADST-H.KEEP @ > 0= ;

\ The keys, ascending, each name a run with that key.  With one key per
\ run and none repeated, every run has its key.
: _ADST-KEYS-OK?  ( store -- flag )
    _ADST.PAYLOAD @
    DUP _ADST-P-KEYS OVER _ADST-P-COUNT _ADST-KEY-SIZE RTAB-ASCENDING? 0= IF
        DROP 0 EXIT
    THEN
    DUP _ADST-P-COUNT 0 ?DO                           ( payload )
        DUP _ADST-P-KEYS I _ADST-KEY-SIZE * +         ( payload key )
        DUP 32 + @ 2 PICK _ADST-P-RUNS 3 PICK _ADST-P-COUNT ADST-RUN-SIZE
        RTAB-SEARCH-ID 0= IF 2DROP DROP 0 UNLOOP EXIT THEN   ( payload key index )
        2 PICK _ADST-P-NTH ADST-R.KEY 32 ROT 32 COMPARE IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ The checked-record callbacks.  The context is the store's head.
: _ADST-VALIDATE  ( store store-u payload payload-u tag -- status )
    DROP 2SWAP DROP >R                       ( payload payload-u ; R: store )
    OVER R@ _ADST.PAYLOAD !
    _ADST-GEOMETRY-OK? 0= IF R> DROP CREC-S-SEMANTIC EXIT THEN
    R@ _ADST.PAYLOAD @ _ADST-HEADER-OK? 0= IF R> DROP CREC-S-SEMANTIC EXIT THEN
    R@ _ADST-RUNS-OK? 0= IF R> DROP CREC-S-SEMANTIC EXIT THEN
    R@ _ADST-KEYS-OK? 0= IF R> DROP CREC-S-SEMANTIC EXIT THEN
    R> _ADST-BLOBS-OK? IF CREC-S-OK ELSE CREC-S-SEMANTIC THEN ;

: _ADST-BLOB-SIZE  ( store -- bytes )
    DUP _ADST.RUNS ADST-RUN-SIZE _ADST-R-REQUEST BSLOT-TABLE-U
    SWAP _ADST.RUNS ADST-RUN-SIZE _ADST-R-TRANSCRIPT BSLOT-TABLE-U + ;

: _ADST-ENCODE  ( store store-u payload payload-u tag -- status )
    2DROP NIP                                ( store payload )
    OVER ADST-HEADER OVER ADST-HEADER-SIZE MOVE
    OVER ADST-COUNT@ OVER _ADST-H.COUNT !
    OVER _ADST-BLOB-SIZE OVER _ADST-H.BLOB !
    DUP ADST-HEADER-SIZE +
    2 PICK _ADST.RUNS ADST-RUN-SIZE RTAB-PUT
    2 PICK _ADST.KEYS _ADST-KEY-SIZE RTAB-PUT ( store payload blob )
    OVER _ADST-H.BLOB @ 3 PICK _ADST.CURSOR BSLOT-CURSOR-INIT   ( store payload )
    \ The written runs' slots: every request, then every transcript.
    DUP _ADST-P-RUNS OVER _ADST-P-COUNT ADST-RUN-SIZE _ADST-R-REQUEST
        5 PICK _ADST.CURSOR BSLOT-PUT-RECORDS
    DUP _ADST-P-RUNS SWAP _ADST-P-COUNT ADST-RUN-SIZE _ADST-R-TRANSCRIPT
        4 PICK _ADST.CURSOR BSLOT-PUT-RECORDS
    DROP CREC-S-OK ;

: _ADST-PAYLOAD-U  ( store -- payload-u )
    DUP ADST-COUNT@ _ADST-ROW-U * SWAP _ADST-BLOB-SIZE + ADST-HEADER-SIZE + ;

\ =====================================================================
\  Reading the file
\ =====================================================================

\ An empty store: the serial counter at one, the default setting, no
\ identity yet.
: _ADST-FRESH  ( store -- )
    0 OVER _ADST.GENERATION !
    ADST-HEADER DUP ADST-HEADER-SIZE 0 FILL
    1 OVER ADST-H.SERIAL !
    ADST-DEFAULT-KEEP SWAP ADST-H.KEEP ! ;

\ The file open for reading, or 0 when it does not exist.
: _ADST-OPEN-READ  ( store -- fd|0 status )
    >R R@ _ADST.REPL VREPL-TARGET$ VFS-FF-READ R> _ADST.VFS @ VFS-OPEN?
    ?DUP IF
        NIP VFS-IOR-REASON VFS-R-NOENT = IF 0 ADST-S-OK ELSE 0 ADST-S-IO THEN
        EXIT
    THEN
    ADST-S-OK ;

\ Copies the payload's runs and keys into the store's empty tables, and
\ gives the runs' blobs their own copies.
: _ADST-TAKE-TABLES  ( payload store -- status )
    OVER _ADST-P-RUNS 2 PICK _ADST-P-COUNT 2 PICK _ADST.RUNS ADST-RUN-SIZE
    RTAB-TAKE IF 2DROP ADST-S-NOMEM EXIT THEN
    OVER _ADST-P-KEYS 2 PICK _ADST-P-COUNT 2 PICK _ADST.KEYS _ADST-KEY-SIZE
    RTAB-TAKE IF
        0 OVER _ADST.RUNS ADST-RUN-SIZE _ADST-R-REQUEST BSLOT-TABLE-FORGET
        0 OVER _ADST.RUNS ADST-RUN-SIZE _ADST-R-TRANSCRIPT BSLOT-TABLE-FORGET
        2DROP ADST-S-NOMEM EXIT
    THEN
    OVER _ADST-P-BLOB OVER _ADST.RUNS ADST-RUN-SIZE _ADST-R-REQUEST
    BSLOT-TABLE-OWN IF
        0 OVER _ADST.RUNS ADST-RUN-SIZE _ADST-R-TRANSCRIPT BSLOT-TABLE-FORGET
        2DROP ADST-S-NOMEM EXIT
    THEN
    SWAP _ADST-P-BLOB SWAP _ADST.RUNS ADST-RUN-SIZE _ADST-R-TRANSCRIPT
    BSLOT-TABLE-OWN IF ADST-S-NOMEM ELSE ADST-S-OK THEN ;

\ Validates the file's bytes and takes their runs and generation.  A file
\ that fails its checks blocks the store.
: _ADST-TAKE-FILE  ( record record-u store -- status )
    >R R@ _ADST-CONTEXT-U 2SWAP R@ _ADST.SPEC R@ _ADST.WORK CREC-VALIDATE
    ?DUP IF
        CREC-S-UNSUPPORTED = IF ADST-R-FUTURE ELSE ADST-R-CORRUPT THEN
        R> _ADST-BLOCK! ADST-S-OK EXIT
    THEN
    R@ _ADST.WORK CREC-TAG@ R@ _ADST.GENERATION !
    R@ _ADST.WORK CREC-PAYLOAD$ DROP                    ( payload )
    DUP R@ ADST-HEADER ADST-HEADER-SIZE MOVE
    \ In memory the tables keep their own count, and the blobs are theirs.
    0 R@ ADST-HEADER _ADST-H.COUNT !
    0 R@ ADST-HEADER _ADST-H.BLOB !
    R> _ADST-TAKE-TABLES ;

\ Reads the file into the empty tables.  A missing file leaves an empty
\ store; one that is too short to be a record, unreadable, or refused
\ blocks it.  Fails only for want of memory to hold it.
: _ADST-LOAD  ( store -- status )
    DUP _ADST-OPEN-READ ?DUP IF
        NIP DROP ADST-R-IO SWAP _ADST-BLOCK! ADST-S-OK EXIT
    THEN                                                ( store fd|0 )
    ?DUP 0= IF _ADST-FRESH ADST-S-OK EXIT THEN          ( store fd )
    DUP VFS-SIZE                                        ( store fd size )
    DUP CREC-HEADER-SIZE < IF
        DROP VFS-CLOSE? DROP ADST-R-CORRUPT SWAP _ADST-BLOCK! ADST-S-OK EXIT
    THEN
    DUP ALLOCATE IF
        2DROP VFS-CLOSE? DROP DROP ADST-S-NOMEM EXIT
    THEN                                                ( store fd size buffer )
    2DUP SWAP 4 PICK VFS-READ-EXACT                     ( store fd size buffer ior )
    3 PICK VFS-CLOSE? DROP
    >R ROT DROP SWAP R>                                 ( store buffer size ior )
    IF DROP FREE ADST-R-IO SWAP _ADST-BLOCK! ADST-S-OK EXIT THEN
    OVER SWAP 3 PICK _ADST-TAKE-FILE                    ( store buffer status )
    SWAP FREE NIP ;

\ Drops what memory holds and reads the file again, returning STATUS.  A
\ file that can no longer be read blocks the store.
: _ADST-RELOAD  ( status store -- status )
    DUP _ADST-FREE-TABLES
    DUP ['] _ADST-LOAD CATCH IF DROP ADST-S-NOMEM THEN  ( status store load )
    IF ADST-R-IO SWAP _ADST-BLOCK! DROP ADST-S-BLOCKED EXIT THEN
    ADST-STATE@ ADST-BLOCKED = IF DROP ADST-S-BLOCKED THEN ;

\ Finishes or undoes an interrupted replacement.  One nobody can resolve
\ blocks the store.
: _ADST-RECOVER  ( store -- )
    DUP _ADST.REPL ['] VREPL-RECOVER CATCH IF DROP VREPL-S-RECOVERY THEN
    DUP VREPL-S-OK = OVER VREPL-S-ROLLED-BACK = OR
    SWAP VREPL-S-COMMITTED-CLEANUP = OR
    IF DROP ELSE ADST-R-UNCERTAIN SWAP _ADST-BLOCK! THEN ;

\ =====================================================================
\  Writing the file
\ =====================================================================

\ The file's bytes for the tables, one generation on, checked as OPEN
\ would check them.  The caller frees the record.
: _ADST-ENCODE-FILE  ( store -- record record-u status )
    DUP _ADST-PAYLOAD-U OVER _ADST.SPEC CREC-MEASURE IF
        2DROP 0 0 ADST-S-INVALID EXIT
    THEN                                     ( store capacity )
    DUP ALLOCATE IF 2DROP DROP 0 0 ADST-S-NOMEM EXIT THEN
    SWAP                                     ( store record capacity )
    2 PICK _ADST-CONTEXT-U
    4 PICK _ADST-PAYLOAD-U
    5 PICK _ADST.GENERATION @ 1+
    5 PICK 5 PICK
    8 PICK _ADST.SPEC 9 PICK _ADST.WORK CREC-ENCODE
                                             ( store record capacity record-u status )
    IF 2DROP FREE DROP 0 0 ADST-S-INVALID EXIT THEN
    NIP                                      ( store record record-u )
    2 PICK _ADST-CONTEXT-U 2OVER 6 PICK _ADST.SPEC 7 PICK _ADST.WORK
        CREC-VALIDATE
    IF DROP FREE DROP 0 0 ADST-S-INVALID EXIT THEN
    ROT DROP ADST-S-OK ;

\ The store after a replacement: one generation on, unchanged and
\ reloaded, or blocked when nobody can tell which.
: _ADST-REPLACED  ( vrepl-status store -- status )
    OVER VREPL-S-OK = 2 PICK VREPL-S-COMMITTED-CLEANUP = OR IF
        NIP 1 SWAP _ADST.GENERATION +! ADST-S-OK EXIT
    THEN
    OVER VREPL-S-IO = 2 PICK VREPL-S-CONFLICT = OR
    2 PICK VREPL-S-BUSY = OR 2 PICK VREPL-S-INVALID = OR IF
        NIP ADST-S-IO SWAP _ADST-RELOAD EXIT
    THEN
    NIP ADST-R-UNCERTAIN SWAP _ADST-BLOCK! ADST-S-BLOCKED ;

\ Writes the tables as the next generation.  Any failure reloads the last
\ committed file, undoing the edits; one whose outcome is unknown blocks
\ the store instead.
: _ADST-COMMIT  ( store -- status )
    DUP _ADST-ENCODE-FILE ?DUP IF NIP NIP SWAP _ADST-RELOAD EXIT THEN
                                             ( store record record-u )
    2DUP 4 PICK _ADST.REPL ['] VREPL-REPLACE CATCH IF
        2DROP DROP VREPL-S-UNCERTAIN
    THEN                                     ( store record record-u vstatus )
    NIP SWAP FREE
    SWAP _ADST-REPLACED ;

\ =====================================================================
\  Lifecycle
\ =====================================================================

\ Configures STORE, ADST-SIZE cell-aligned bytes, to keep its file at
\ PATH, an absolute path, in VFS.  The store starts closed.
: ADST-INIT  ( vfs path path-u store -- status )
    DUP 0= OVER 7 AND OR IF 2DROP 2DROP ADST-S-INVALID EXIT THEN
    DUP ADST-VALID? IF 2DROP 2DROP ADST-S-STATE EXIT THEN
    3 PICK 0= IF 2DROP 2DROP ADST-S-INVALID EXIT THEN
    DUP ADST-SIZE 0 FILL
    >R
    2 PICK R@ _ADST.VFS !
    2 PICK R@ _ADST.REPL VREPL-INIT IF
        2DROP DROP R> ADST-SIZE 0 FILL ADST-S-INVALID EXIT
    THEN
    R@ _ADST.REPL VREPL-DERIVE-PATHS! IF
        DROP R> ADST-SIZE 0 FILL ADST-S-INVALID EXIT
    THEN
    DROP
    _ADST-MAGIC$ _ADST-FORMAT CREC-TAG-POSITIVE ['] _ADST-ENCODE
        ['] _ADST-VALIDATE R@ _ADST.SPEC CREC-SPEC-INIT
    \ The file grows with the runs; memory, not the format, bounds it.
    ADST-HEADER-SIZE 1 62 LSHIFT 8 R@ _ADST.SPEC CREC-SPEC-FRAMED! OR
    R@ _ADST.SPEC CREC-SPEC-SEAL OR
    R@ _ADST.WORK CREC-WORK-INIT OR IF
        R> ADST-SIZE 0 FILL ADST-S-INVALID EXIT
    THEN
    R@ DUP _ADST.SELF !
    _ADST-MAGIC R@ _ADST.MAGIC !
    ADST-CLOSED R> _ADST.STATE !
    ADST-S-OK ;

\ Frees what OPEN read.  The store stays configured.
: ADST-CLOSE  ( store -- status )
    DUP ADST-VALID? 0= IF DROP ADST-S-INVALID EXIT THEN
    DUP _ADST-FREE-TABLES
    DUP ADST-HEADER ADST-HEADER-SIZE 0 FILL
    0 OVER _ADST.GENERATION !
    0 OVER _ADST.REASON !
    ADST-CLOSED SWAP _ADST.STATE !
    ADST-S-OK ;

\ Recovers the file and reads it.  Returns OK when the store is READY, or
\ BLOCKED with ADST-REASON@ saying why it cannot be used.
: ADST-OPEN  ( store -- status )
    DUP ADST-VALID? 0= IF DROP ADST-S-INVALID EXIT THEN
    DUP ADST-STATE@ ADST-CLOSED <> IF DROP ADST-S-STATE EXIT THEN
    ADST-READY OVER _ADST.STATE !
    0 OVER _ADST.REASON !
    DUP _ADST-RECOVER
    DUP ADST-STATE@ ADST-READY <> IF DROP ADST-S-BLOCKED EXIT THEN
    ADST-S-OK SWAP _ADST-RELOAD ;


\ =====================================================================
\  Operations
\ =====================================================================

\ The request RUN ran and its transcript, ATHREAD-ENCODE bytes the store
\ keeps opaque; each is 0 0 once the run is trimmed.
: ADST-REQUEST$     ( run -- address length ) ADST-R.REQUEST BSLOT$ ;
: ADST-TRANSCRIPT$  ( run -- address length ) ADST-R.TRANSCRIPT BSLOT$ ;

\ Whether RUN is one of the store's runs.
: _ADST-RUN?  ( run store -- flag )
    DUP _ADST.RUNS @ ROT SWAP -                       ( store offset )
    DUP 0< IF 2DROP 0 EXIT THEN
    ADST-RUN-SIZE /MOD SWAP IF 2DROP 0 EXIT THEN      ( store index )
    SWAP ADST-COUNT@ < ;

\ The run with dispatch KEY, or 0.
: ADST-FIND  ( key store -- run|0 )
    DUP _ADST-READY IF 2DROP 0 EXIT THEN
    >R R@ _ADST.KEYS @ R@ _ADST.KEYS RTAB-COUNT@ _ADST-KEY-SIZE RTAB-RECORD
    ?DUP 0= IF R> DROP 0 EXIT THEN
    32 + @ R@ _ADST.RUNS @ R@ ADST-COUNT@ ADST-RUN-SIZE RTAB-SEARCH-ID
    IF R> ADST-NTH ELSE DROP R> DROP 0 THEN ;

\ Trims the oldest ended runs that keep their request and transcript
\ until no more than the setting do.  Runs in flight are never trimmed.
: _ADST-TRIM  ( store -- )
    0 OVER ADST-COUNT@ 0 ?DO                          ( store kept )
        I 2 PICK ADST-NTH
        DUP ADST-R.PHASE @ ADST-ENDED = SWAP ADST-KEPT? AND IF 1+ THEN
    LOOP
    OVER ADST-HEADER ADST-H.KEEP @ - 0 MAX            ( store excess )
    OVER ADST-COUNT@ 0 ?DO
        DUP IF
            I 2 PICK ADST-NTH
            DUP ADST-R.PHASE @ ADST-ENDED = OVER ADST-KEPT? AND IF
                DUP ADST-R.REQUEST BSLOT-FREE ADST-R.TRANSCRIPT BSLOT-FREE 1-
            ELSE
                DROP
            THEN
        THEN
    LOOP
    2DROP ;

\ Whether REQUEST can be accepted: an occurrence's hand-over
\ (SDSP-REQUEST-OK?) naming a permission at a revision.
: _ADST-ACCEPTABLE?  ( request -- flag )
    DUP -1 SDSP-REQUEST-OK? IF DROP 0 EXIT THEN
    DUP SDSP-R.PERMISSION RID-ZERO? IF DROP 0 EXIT THEN
    SDSP-R.PERMISSION-REVISION @ 0> ;

\ RUN, recorded under REQUEST's key: EXISTING when it was accepted for
\ exactly REQUEST, byte for byte, and CONFLICT when not.
: _ADST-AGAIN  ( request run store -- run status )
    ROT OVER _ADST.SCRATCH ADST-DIGEST                ( run store )
    _ADST.SCRATCH 32 2 PICK ADST-R.DIGEST 32 COMPARE
    IF ADST-S-CONFLICT ELSE ADST-S-EXISTING THEN ;

\ A new run for REQUEST, accepted at NOW, at the end of the table: the
\ next serial, a copy of the request and its digest, the RID its
\ Practice and key give, and its key among the keys.
: _ADST-NEW  ( request now store -- run status )
    DUP _ADST-IDENTITY ?DUP IF NIP NIP NIP 0 SWAP EXIT THEN
    DUP _ADST.RUNS ADST-RUN-SIZE RTAB-RESERVE
    OVER _ADST.KEYS _ADST-KEY-SIZE RTAB-RESERVE OR IF
        DROP 2DROP 0 ADST-S-NOMEM EXIT
    THEN
    >R                                                ( request now ; R: store )
    R@ ADST-COUNT@ R@ _ADST.RUNS ADST-RUN-SIZE RTAB-INSERT   ( request now run )
    SWAP 0 MAX OVER ADST-R.ACCEPTED !                 ( request run )
    OVER DUP SDSP-REQUEST-U 2 PICK ADST-R.REQUEST BSLOT! IF
        2DROP R@ ADST-COUNT@ 1- R> _ADST.RUNS ADST-RUN-SIZE RTAB-DELETE
        0 ADST-S-NOMEM EXIT
    THEN
    ADST-ACCEPTED OVER ADST-R.PHASE !
    R@ ADST-HEADER ADST-H.SERIAL DUP @ 2 PICK ADST-R.SERIAL ! 1 SWAP +!
    OVER SDSP-R.KEY OVER ADST-R.KEY 32 MOVE
    OVER SDSP-R.PRACTICE OVER ADST-R.PRACTICE RID-SIZE MOVE
    OVER SDSP-R.PERMISSION OVER ADST-R.PERMISSION RID-SIZE MOVE
    OVER SDSP-R.PERMISSION-REVISION @ OVER ADST-R.REVISION !
    OVER OVER ADST-R.DIGEST ADST-DIGEST
    R@ ADST-HEADER ADST-H.STORE-ID OVER ADST-R.PRACTICE 2 PICK ADST-R.KEY
        3 PICK ADST-R.RID _ADST-RID!
    NIP                                               ( run )
    DUP ADST-R.KEY R@ _ADST.KEYS @ R@ _ADST.KEYS RTAB-COUNT@ _ADST-KEY-SIZE
    RTAB-SEARCH DROP                                  ( run index )
    R> _ADST.KEYS _ADST-KEY-SIZE RTAB-INSERT          ( run key )
    OVER ADST-R.KEY OVER 32 MOVE
    OVER ADST-R.SERIAL @ SWAP 32 + !
    ADST-S-OK ;

\ Records the run REQUEST asks for, accepted at NOW, the wall clock in
\ milliseconds or -1 when it is not set, before its provider starts.
\ REQUEST is an occurrence's hand-over naming its permission.  A run with
\ its dispatch key already recorded is returned instead, unchanged:
\ EXISTING when it was accepted for exactly this request, CONFLICT when
\ not.  Returns the run, which stays put until the next operation.
: ADST-ACCEPT  ( request now store -- run status )
    DUP _ADST-READY ?DUP IF NIP NIP NIP 0 SWAP EXIT THEN
    2 PICK _ADST-ACCEPTABLE? 0= IF DROP 2DROP 0 ADST-S-INVALID EXIT THEN
    2 PICK SDSP-R.KEY OVER ADST-FIND ?DUP IF          ( request now store run )
        ROT DROP SWAP _ADST-AGAIN EXIT
    THEN
    DUP >R _ADST-NEW ?DUP IF R> DROP EXIT THEN        ( run ; R: store )
    R> _ADST-COMMIT ?DUP IF NIP 0 SWAP EXIT THEN
    ADST-S-OK ;

\ Sets the transcript of RUN, a run in flight, to its own copy of LENGTH
\ bytes at ADDRESS: the run's conversation so far.  It is written with
\ the next write, normally ADST-FINISH's.  A write that fails reloads the
\ run without it, so whoever retries the write sets it again.
: ADST-TRANSCRIPT!  ( address length run store -- status )
    DUP _ADST-READY ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    2DUP _ADST-RUN? 0= IF 2DROP 2DROP ADST-S-INVALID EXIT THEN
    DROP DUP ADST-R.PHASE @ ADST-ACCEPTED <> IF DROP 2DROP ADST-S-STATE EXIT THEN
    OVER 0< IF DROP 2DROP ADST-S-INVALID EXIT THEN
    ADST-R.TRANSCRIPT BSLOT! IF ADST-S-NOMEM ELSE ADST-S-OK THEN ;

\ Ends RUN, a run in flight, at NOW with OUTCOME for REASON, a pair the
\ catalog allows (scheduled-action.f), having kept REPLY-U bytes of
\ reply.  A run its provider refused to start ends blocked; none ends as
\ not started.  The newest ended runs keep their request and transcript,
\ as many as the setting says, and older ones are trimmed to their row.
\ A write that fails reloads the run as it was, still in flight.
: ADST-FINISH  ( outcome reason reply-u now run store -- status )
    DUP _ADST-READY ?DUP IF >R 2DROP 2DROP 2DROP R> EXIT THEN
    2DUP _ADST-RUN? 0= IF 2DROP 2DROP 2DROP ADST-S-INVALID EXIT THEN
    OVER ADST-R.PHASE @ ADST-ACCEPTED <> IF 2DROP 2DROP 2DROP ADST-S-STATE EXIT THEN
    5 PICK 5 PICK _ADST-END-OK? 0= 4 PICK 0< OR IF
        2DROP 2DROP 2DROP ADST-S-INVALID EXIT
    THEN
    >R                                ( outcome reason reply-u now run ; R: store )
    SWAP 0 MAX OVER ADST-R.ENDED !
    TUCK ADST-R.REPLY-U !
    TUCK ADST-R.REASON !
    TUCK ADST-R.OUTCOME !
    ADST-ENDED SWAP ADST-R.PHASE !
    R@ _ADST-TRIM R> _ADST-COMMIT ;

\ Ends every run in flight as indeterminate, interrupted, at NOW: runs the
\ Agent was running when it last stopped, which may or may not have
\ reached their provider.  Returns how many.  The Agent calls it once
\ when it opens the store, before it runs anything.
: ADST-RECONCILE  ( now store -- n status )
    DUP _ADST-READY ?DUP IF NIP NIP 0 SWAP EXIT THEN
    0 OVER ADST-COUNT@ 0 ?DO                          ( now store n )
        I 2 PICK ADST-NTH DUP ADST-R.PHASE @ ADST-ACCEPTED = IF
            ADST-ENDED OVER ADST-R.PHASE !
            SACT-O-INDETERMINATE OVER ADST-R.OUTCOME !
            SACT-R-INTERRUPTED OVER ADST-R.REASON !
            3 PICK 0 MAX SWAP ADST-R.ENDED !
            1+
        ELSE
            DROP
        THEN
    LOOP
    ROT DROP                                          ( store n )
    DUP 0= IF NIP ADST-S-OK EXIT THEN
    OVER _ADST-TRIM
    SWAP _ADST-COMMIT ?DUP IF NIP 0 SWAP EXIT THEN
    ADST-S-OK ;

\ Sets how many ended runs keep their request and transcript, N not below
\ zero; older ones keep only their row.  Lowering it trims at once, and
\ raising it brings nothing back.
: ADST-KEEP!  ( n store -- status )
    DUP _ADST-READY ?DUP IF NIP NIP EXIT THEN
    OVER 0< IF 2DROP ADST-S-INVALID EXIT THEN
    2DUP ADST-HEADER ADST-H.KEEP @ = IF 2DROP ADST-S-OK EXIT THEN
    DUP _ADST-IDENTITY ?DUP IF NIP NIP EXIT THEN
    TUCK ADST-HEADER ADST-H.KEEP !
    DUP _ADST-TRIM _ADST-COMMIT ;
