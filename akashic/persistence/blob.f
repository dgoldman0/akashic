\ =====================================================================
\  blob.f - Immutable chunked blobs over the transactional record store
\ =====================================================================
\  Blob content is split into exact 32 KiB logical chunks.  Chunks and the
\  immutable manifest nodes which name them are checked PSTORE records.
\  A fixed descriptor names the manifest root; no path, applet vocabulary,
\  publication policy, or mutable module state is owned here.
\
\  Construction is streaming and must be enclosed by a caller's existing
\  PSTORE transaction.  This layer never begins, commits, aborts, or changes
\  the application root.  Reads are current-authority scoped PSTORE reads
\  and do not require a transaction.  One caller-owned workspace contains
\  one chunk buffer and the bounded manifest frontier.
\ =====================================================================

PROVIDED akashic-persist-blob

REQUIRE store.f

32768 CONSTANT PBLOB-CHUNK-SIZE
64    CONSTANT PBLOB-MANIFEST-FANOUT
7     CONSTANT PBLOB-MAX-LEVEL
9     CONSTANT _PBLOB-BUCKETS
32    CONSTANT _PBLOB-NODE-HEADER-SIZE
_PBLOB-NODE-HEADER-SIZE
    PBLOB-MANIFEST-FANOUT PERSIST-REF-SIZE * +
    CONSTANT PBLOB-MAX-MANIFEST-SIZE

0x50424C4F424D4554 CONSTANT _PBLOB-MAGIC       \ "PBLOBMET"
0x50424C4F424E4F44 CONSTANT _PBLOB-NODE-MAGIC  \ "PLOBNOD"

: _PBLOB-DROP6  ( x1 .. x6 -- ) 2DROP 2DROP 2DROP ;
: _PBLOB-DROP7  ( x1 .. x7 -- ) 2DROP 2DROP 2DROP DROP ;

: _PBLOB-CEIL/  ( nonnegative-n positive-d -- quotient )
    /MOD SWAP 0<> IF 1+ THEN ;

: _PBLOB-CHUNKS  ( total-bytes -- chunk-count )
    PBLOB-CHUNK-SIZE _PBLOB-CEIL/ ;

: _PBLOB-LEVEL-CAPACITY  ( level -- chunks status )
    DUP 0< OVER PBLOB-MAX-LEVEL > OR IF
        DROP 0 PERSIST-S-INVALID EXIT
    THEN
    1 SWAP 1+ 0 ?DO PBLOB-MANIFEST-FANOUT * LOOP
    PERSIST-S-OK ;

: _PBLOB-CHILD-CAPACITY  ( level -- chunks status )
    DUP 0< OVER PBLOB-MAX-LEVEL > OR IF
        DROP 0 PERSIST-S-INVALID EXIT
    THEN
    1 SWAP 0 ?DO PBLOB-MANIFEST-FANOUT * LOOP
    PERSIST-S-OK ;

: _PBLOB-STATUS?  ( status -- flag )
    DUP PERSIST-S-OK >= SWAP PERSIST-S-FAULT <= AND ;

\ =====================================================================
\ Immutable, copyable blob descriptor
\ =====================================================================

 0 CONSTANT _PBL-MAGIC
 8 CONSTANT _PBL-TOTAL
16 CONSTANT _PBL-CHUNKS
24 CONSTANT _PBL-LEVEL
32 CONSTANT _PBL-ROOT
56 CONSTANT _PBL-FLAGS
64 CONSTANT _PBL-RESERVED
72 CONSTANT PBLOB-SIZE

: _PBL.MAGIC     ( blob -- a ) _PBL-MAGIC + ;
: _PBL.TOTAL     ( blob -- a ) _PBL-TOTAL + ;
: _PBL.CHUNKS    ( blob -- a ) _PBL-CHUNKS + ;
: _PBL.LEVEL     ( blob -- a ) _PBL-LEVEL + ;
: _PBL.ROOT      ( blob -- ref ) _PBL-ROOT + ;
: _PBL.FLAGS     ( blob -- a ) _PBL-FLAGS + ;
: _PBL.RESERVED  ( blob -- a ) _PBL-RESERVED + ;

: PBLOB-VALID?  ( blob -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP PBLOB-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _PBL.MAGIC @ _PBLOB-MAGIC <> IF DROP 0 EXIT THEN
    DUP _PBL.TOTAL @ DUP 0< IF 2DROP 0 EXIT THEN
    DUP _PBLOB-CHUNKS 2 PICK _PBL.CHUNKS @ <> IF 2DROP 0 EXIT THEN
    DROP
    DUP _PBL.FLAGS @ IF DROP 0 EXIT THEN
    DUP _PBL.RESERVED @ IF DROP 0 EXIT THEN
    DUP _PBL.TOTAL @ 0= IF
        DUP _PBL.CHUNKS @ IF DROP 0 EXIT THEN
        DUP _PBL.LEVEL @ -1 <> IF DROP 0 EXIT THEN
        _PBL.ROOT PERSIST-REF-SIZE _PERSIST-ZERO?
        EXIT
    THEN
    DUP _PBL.CHUNKS @ 0> 0= IF DROP 0 EXIT THEN
    DUP _PBL.LEVEL @ DUP 0< SWAP PBLOB-MAX-LEVEL > OR IF
        DROP 0 EXIT
    THEN
    DUP _PBL.LEVEL @ _PBLOB-LEVEL-CAPACITY
    DUP IF 2DROP DROP 0 EXIT THEN DROP
    OVER _PBL.CHUNKS @ < IF DROP 0 EXIT THEN
    DUP _PBL.LEVEL @ 0> IF
        DUP _PBL.LEVEL @ 1- _PBLOB-LEVEL-CAPACITY
        DUP IF 2DROP DROP 0 EXIT THEN DROP
        OVER _PBL.CHUNKS @ >= IF DROP 0 EXIT THEN
    THEN
    _PBL.ROOT PERSIST-REF-VALID? ;

: PBLOB-TOTAL@  ( blob -- total-bytes|-1 )
    DUP PBLOB-VALID? IF _PBL.TOTAL @ ELSE DROP -1 THEN ;

: PBLOB-CHUNK-COUNT@  ( blob -- chunk-count|-1 )
    DUP PBLOB-VALID? IF _PBL.CHUNKS @ ELSE DROP -1 THEN ;

: PBLOB-LEVEL@  ( blob -- level|-1 )
    DUP PBLOB-VALID? IF _PBL.LEVEL @ ELSE DROP -1 THEN ;

: PBLOB-ROOT@  ( blob -- root-ref|0 )
    DUP PBLOB-VALID? 0= IF DROP 0 EXIT THEN
    DUP _PBL.TOTAL @ 0= IF DROP 0 ELSE _PBL.ROOT THEN ;

: PBLOB-COPY  ( source destination -- status )
    OVER PBLOB-VALID? 0= IF 2DROP PERSIST-S-INVALID EXIT THEN
    DUP 0= IF 2DROP PERSIST-S-INVALID EXIT THEN
    DUP PBLOB-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP PERSIST-S-INVALID EXIT
    THEN
    PBLOB-SIZE MOVE PERSIST-S-OK ;

\ =====================================================================
\ Caller-owned bounded workspace
\ =====================================================================

0x50424C4F4257524B CONSTANT _PBLOB-WORK-MAGIC  \ "PBLOBWRK"

  0 CONSTANT _PBW-MAGIC
  8 CONSTANT _PBW-SELF
 16 CONSTANT _PBW-BUSY
 24 CONSTANT _PBW-STATUS
 32 CONSTANT _PBW-STORE
 40 CONSTANT _PBW-STORE-WORK
 48 CONSTANT _PBW-BLOB
 56 CONSTANT _PBW-CALLBACK-XT
 64 CONSTANT _PBW-CALLBACK-CONTEXT
 72 CONSTANT _PBW-TOTAL
 80 CONSTANT _PBW-POSITION
 88 CONSTANT _PBW-REQUESTED
 96 CONSTANT _PBW-ACTUAL
104 CONSTANT _PBW-CALLBACK-STATUS
112 CONSTANT _PBW-RETURNED
120 CONSTANT _PBW-LOCAL-INDEX
128 CONSTANT _PBW-EXPECTED-COVERED
136 CONSTANT _PBW-EXPECTED-LEVEL
144 CONSTANT _PBW-SLOT
152 CONSTANT _PBW-PAYLOAD-A
160 CONSTANT _PBW-PAYLOAD-U
168 CONSTANT _PBW-CHUNK-WRITES
176 CONSTANT _PBW-CHUNK-READS
184 CONSTANT _PBW-MANIFEST-WRITES
192 CONSTANT _PBW-MANIFEST-READS
200 CONSTANT _PBW-BYTES
208 CONSTANT _PBW-CALLBACKS
216 CONSTANT _PBW-PEAK
224 CONSTANT _PBW-SELECTED-REF
248 CONSTANT _PBW-TEMP-REF
272 CONSTANT _PBW-COUNTS
344 CONSTANT _PBW-FRONTIER
_PBW-FRONTIER
    _PBLOB-BUCKETS PBLOB-MANIFEST-FANOUT * PERSIST-REF-SIZE * +
    CONSTANT _PBW-CHUNK
_PBW-CHUNK PBLOB-CHUNK-SIZE + CONSTANT PBLOB-WORK-SIZE

: _PBW.MAGIC              ( work -- a ) _PBW-MAGIC + ;
: _PBW.SELF               ( work -- a ) _PBW-SELF + ;
: _PBW.BUSY               ( work -- a ) _PBW-BUSY + ;
: _PBW.STATUS             ( work -- a ) _PBW-STATUS + ;
: _PBW.STORE              ( work -- a ) _PBW-STORE + ;
: _PBW.STORE-WORK         ( work -- a ) _PBW-STORE-WORK + ;
: _PBW.BLOB               ( work -- a ) _PBW-BLOB + ;
: _PBW.CALLBACK-XT        ( work -- a ) _PBW-CALLBACK-XT + ;
: _PBW.CALLBACK-CONTEXT   ( work -- a ) _PBW-CALLBACK-CONTEXT + ;
: _PBW.TOTAL              ( work -- a ) _PBW-TOTAL + ;
: _PBW.POSITION           ( work -- a ) _PBW-POSITION + ;
: _PBW.REQUESTED          ( work -- a ) _PBW-REQUESTED + ;
: _PBW.ACTUAL             ( work -- a ) _PBW-ACTUAL + ;
: _PBW.CALLBACK-STATUS    ( work -- a ) _PBW-CALLBACK-STATUS + ;
: _PBW.RETURNED           ( work -- a ) _PBW-RETURNED + ;
: _PBW.LOCAL-INDEX        ( work -- a ) _PBW-LOCAL-INDEX + ;
: _PBW.EXPECTED-COVERED   ( work -- a ) _PBW-EXPECTED-COVERED + ;
: _PBW.EXPECTED-LEVEL     ( work -- a ) _PBW-EXPECTED-LEVEL + ;
: _PBW.SLOT               ( work -- a ) _PBW-SLOT + ;
: _PBW.PAYLOAD-A          ( work -- a ) _PBW-PAYLOAD-A + ;
: _PBW.PAYLOAD-U          ( work -- a ) _PBW-PAYLOAD-U + ;
: _PBW.CHUNK-WRITES       ( work -- a ) _PBW-CHUNK-WRITES + ;
: _PBW.CHUNK-READS        ( work -- a ) _PBW-CHUNK-READS + ;
: _PBW.MANIFEST-WRITES    ( work -- a ) _PBW-MANIFEST-WRITES + ;
: _PBW.MANIFEST-READS     ( work -- a ) _PBW-MANIFEST-READS + ;
: _PBW.BYTES              ( work -- a ) _PBW-BYTES + ;
: _PBW.CALLBACKS          ( work -- a ) _PBW-CALLBACKS + ;
: _PBW.PEAK               ( work -- a ) _PBW-PEAK + ;
: _PBW.SELECTED-REF       ( work -- ref ) _PBW-SELECTED-REF + ;
: _PBW.TEMP-REF           ( work -- ref ) _PBW-TEMP-REF + ;
: _PBW.COUNTS             ( work -- a ) _PBW-COUNTS + ;
: _PBW.FRONTIER           ( work -- a ) _PBW-FRONTIER + ;
: _PBW.CHUNK              ( work -- a ) _PBW-CHUNK + ;

: _PBW-COUNT  ( bucket work -- a )
    _PBW.COUNTS SWAP CELLS + ;

: _PBW-FRONTIER-REF  ( bucket index work -- ref )
    >R SWAP PBLOB-MANIFEST-FANOUT * + PERSIST-REF-SIZE *
    R> _PBW.FRONTIER + ;

: PBLOB-WORK-VALID?  ( work -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP PBLOB-WORK-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _PBW.MAGIC @ _PBLOB-WORK-MAGIC <> IF DROP 0 EXIT THEN
    DUP _PBW.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _PBW.BUSY @ DUP 0= SWAP -1 = OR 0= IF DROP 0 EXIT THEN
    _PBW.STATUS @ _PBLOB-STATUS? ;

: PBLOB-WORK-INIT  ( work -- status )
    DUP 0= IF DROP PERSIST-S-INVALID EXIT THEN
    DUP PBLOB-WORK-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP PERSIST-S-INVALID EXIT
    THEN
    DUP PBLOB-WORK-SIZE 0 FILL
    _PBLOB-WORK-MAGIC OVER _PBW.MAGIC !
    DUP OVER _PBW.SELF !
    PERSIST-S-INVALID OVER _PBW.STATUS !
    PBLOB-WORK-SIZE OVER _PBW.PEAK !
    DROP PERSIST-S-OK ;

: PBLOB-WORK-STATUS@  ( work -- status )
    DUP PBLOB-WORK-VALID? IF _PBW.STATUS @ ELSE DROP PERSIST-S-INVALID THEN ;

: PBLOB-CHUNK-WRITES@  ( work -- u )
    DUP PBLOB-WORK-VALID? IF _PBW.CHUNK-WRITES @ ELSE DROP 0 THEN ;
: PBLOB-CHUNK-READS@  ( work -- u )
    DUP PBLOB-WORK-VALID? IF _PBW.CHUNK-READS @ ELSE DROP 0 THEN ;
: PBLOB-MANIFEST-WRITES@  ( work -- u )
    DUP PBLOB-WORK-VALID? IF _PBW.MANIFEST-WRITES @ ELSE DROP 0 THEN ;
: PBLOB-MANIFEST-READS@  ( work -- u )
    DUP PBLOB-WORK-VALID? IF _PBW.MANIFEST-READS @ ELSE DROP 0 THEN ;
: PBLOB-BYTES@  ( work -- u )
    DUP PBLOB-WORK-VALID? IF _PBW.BYTES @ ELSE DROP 0 THEN ;
: PBLOB-CALLBACKS@  ( work -- u )
    DUP PBLOB-WORK-VALID? IF _PBW.CALLBACKS @ ELSE DROP 0 THEN ;
: PBLOB-WORKING-PEAK@  ( work -- u )
    DUP PBLOB-WORK-VALID? IF _PBW.PEAK @ ELSE DROP 0 THEN ;

: _PBLOB-WORK-RESET  ( work -- )
    >R
    R@ _PBW-STORE + PBLOB-WORK-SIZE _PBW-STORE - 0 FILL
    PBLOB-WORK-SIZE R@ _PBW.PEAK !
    PERSIST-S-OK R@ _PBW.STATUS !
    R> DROP ;

: _PBLOB-BOUND?  ( work -- flag )
    >R
    R@ _PBW.STORE @ DUP PSTORE-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    DUP PSTORE-SEGMENT-FILE@ PSEG-MAX-PAYLOAD@
        PBLOB-CHUNK-SIZE < IF DROP R> DROP 0 EXIT THEN
    DROP
    R@ _PBW.STORE-WORK @ PSTORE-WORK-VALID? 0= IF R> DROP 0 EXIT THEN
    R@ _PBW.BLOB @ DUP 0= IF DROP R> DROP 0 EXIT THEN
    DUP PBLOB-SIZE MSPAN-NONWRAPPING? 0= IF DROP R> DROP 0 EXIT THEN
    DUP PBLOB-SIZE R@ PBLOB-WORK-SIZE MSPAN-OVERLAP? IF
        DROP R> DROP 0 EXIT
    THEN
    DUP PBLOB-SIZE R@ _PBW.STORE-WORK @ PSTORE-WORK-SIZE
        MSPAN-OVERLAP? IF DROP R> DROP 0 EXIT THEN
    DUP PBLOB-SIZE R@ _PBW.STORE-WORK @
        PSTORE-WORK-SPAN-DISJOINT? 0= IF DROP R> DROP 0 EXIT THEN
    DUP PBLOB-SIZE R@ _PBW.STORE @ PSTORE-SPAN-DISJOINT? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ PBLOB-WORK-SIZE R@ _PBW.STORE-WORK @ PSTORE-WORK-SIZE
        MSPAN-OVERLAP? IF R> DROP 0 EXIT THEN
    R@ PBLOB-WORK-SIZE R@ _PBW.STORE-WORK @
        PSTORE-WORK-SPAN-DISJOINT? 0= IF R> DROP 0 EXIT THEN
    R@ PBLOB-WORK-SIZE R@ _PBW.STORE @ PSTORE-SPAN-DISJOINT?
    R> DROP ;

: _PBLOB-RUN-CATCH  ( work body-xt -- status )
    CATCH DUP IF
        2DROP PERSIST-S-FAULT
    ELSE
        DROP
    THEN ;

: _PBLOB-OP-END  ( status work -- status )
    >R
    DUP _PBLOB-STATUS? 0= IF DROP PERSIST-S-FAULT THEN
    DUP R@ _PBW.STATUS !
    0 R@ _PBW.BUSY !
    R> DROP ;

\ A local source, frontier, capacity, or descriptor failure after at least one
\ successful record emission invalidates the surrounding PSTORE proposal.
\ Pure preflight failures and failures before the first emission remain
\ no-effect and leave an otherwise ready transaction usable.
: _PBLOB-WRITE-END  ( status work -- status )
    >R
    DUP _PBLOB-STATUS? 0= IF DROP PERSIST-S-FAULT THEN
    DUP IF
        R@ _PBW.CHUNK-WRITES @ R@ _PBW.MANIFEST-WRITES @ OR IF
            DUP R@ _PBW.STORE @ R@ _PBW.STORE-WORK @
                PSTORE-TX-POISON DROP
        THEN
    THEN
    R> _PBLOB-OP-END ;

\ =====================================================================
\ Callback containment
\ =====================================================================

: _PBLOB-SOURCE-BODY  ( work -- )
    >R
    R@ _PBW.POSITION @
    R@ _PBW.CHUNK
    R@ _PBW.REQUESTED @
    R@ _PBW.CALLBACK-CONTEXT @
    R@ _PBW.CALLBACK-XT @ EXECUTE
    R@ _PBW.CALLBACK-STATUS !
    R@ _PBW.ACTUAL !
    R> DROP ;

: _PBLOB-CALL-SOURCE  ( work -- status )
    >R
    -1 R@ _PBW.ACTUAL !
    PERSIST-S-FAULT R@ _PBW.CALLBACK-STATUS !
    R@ ['] _PBLOB-SOURCE-BODY CATCH
    DUP IF
        2DROP R> DROP PERSIST-S-FAULT EXIT
    THEN DROP
    1 R@ _PBW.CALLBACKS +!
    R@ _PBW.CALLBACK-STATUS @ DUP _PBLOB-STATUS? 0= IF
        DROP R> DROP PERSIST-S-FAULT EXIT
    THEN
    DUP IF R> DROP EXIT THEN DROP
    R@ _PBW.ACTUAL @ R@ _PBW.REQUESTED @ = IF
        R> DROP PERSIST-S-OK
    ELSE
        R> DROP PERSIST-S-CORRUPT
    THEN ;

: _PBLOB-SINK-BODY  ( work -- )
    >R
    R@ _PBW.POSITION @
    R@ _PBW.PAYLOAD-A @
    R@ _PBW.PAYLOAD-U @
    R@ _PBW.CALLBACK-CONTEXT @
    R@ _PBW.CALLBACK-XT @ EXECUTE
    R@ _PBW.CALLBACK-STATUS !
    R> DROP ;

: _PBLOB-CALL-SINK  ( work -- status )
    >R
    PERSIST-S-FAULT R@ _PBW.CALLBACK-STATUS !
    R@ ['] _PBLOB-SINK-BODY CATCH
    DUP IF
        2DROP R> DROP PERSIST-S-FAULT EXIT
    THEN DROP
    1 R@ _PBW.CALLBACKS +!
    R@ _PBW.CALLBACK-STATUS @ DUP _PBLOB-STATUS? 0= IF
        DROP R> DROP PERSIST-S-FAULT
    ELSE
        R> DROP
    THEN ;

\ =====================================================================
\ Streaming manifest construction
\ =====================================================================

: _PBLOB-NODE-COVERED  ( level count work -- chunks status )
    >R
    DUP 0> 0= OVER PBLOB-MANIFEST-FANOUT > OR IF
        2DROP R> DROP 0 PERSIST-S-CORRUPT EXIT
    THEN
    DUP R@ _PBW.SLOT !
    SWAP DUP R@ _PBW.EXPECTED-LEVEL !
    _PBLOB-LEVEL-CAPACITY
    DUP IF >R 2DROP R> R> DROP 0 SWAP EXIT THEN DROP
    NIP
    DUP R@ _PBW.ACTUAL !
    R@ _PBW.SLOT @ PBLOB-MANIFEST-FANOUT = IF
        DROP R@ _PBW.ACTUAL @
    ELSE
        DROP
        R@ _PBW.EXPECTED-COVERED @ R@ _PBW.ACTUAL @ /MOD DROP
        DUP 0= IF DROP R@ _PBW.ACTUAL @ THEN
    THEN
    DUP R@ _PBW.LOCAL-INDEX !
    R@ _PBW.EXPECTED-LEVEL @ _PBLOB-CHILD-CAPACITY
    DUP IF >R 2DROP R> R> DROP 0 SWAP EXIT THEN DROP
    R@ _PBW.LOCAL-INDEX @ SWAP _PBLOB-CEIL/
    R@ _PBW.SLOT @ <> IF
        DROP R> DROP 0 PERSIST-S-CORRUPT EXIT
    THEN
    PERSIST-S-OK R> DROP ;

: _PBLOB-ENCODE-NODE  ( bucket work -- status )
    >R
    DUP R@ _PBW-COUNT @ DUP 0> 0= OVER PBLOB-MANIFEST-FANOUT > OR IF
        2DROP R> DROP PERSIST-S-CORRUPT EXIT
    THEN
    DUP R@ _PBW.SLOT !
    2DUP R@ _PBLOB-NODE-COVERED
    DUP IF >R 2DROP DROP R> R> DROP EXIT THEN DROP
    R@ _PBW.ACTUAL !
    R@ _PBW.CHUNK
    R@ _PBW.SLOT @ PERSIST-REF-SIZE * _PBLOB-NODE-HEADER-SIZE +
    2DUP 0 FILL
    _PBLOB-NODE-MAGIC 2 PICK !
    3 PICK 2 PICK 8 + !
    R@ _PBW.SLOT @ 2 PICK 16 + !
    R@ _PBW.ACTUAL @ 2 PICK 24 + !
    3 PICK 0 R@ _PBW-FRONTIER-REF
    2 PICK _PBLOB-NODE-HEADER-SIZE +
    R@ _PBW.SLOT @ PERSIST-REF-SIZE * MOVE
    R@ _PBW.TEMP-REF
    R@ _PBW.STORE @ R@ _PBW.STORE-WORK @ PSTORE-APPEND-RECORD
    DUP IF >R 2DROP R> R> DROP EXIT THEN DROP
    1 R@ _PBW.MANIFEST-WRITES +!
    0 2 PICK R@ _PBW-COUNT !
    2DROP R> DROP PERSIST-S-OK ;

: _PBLOB-ADD-TEMP  ( bucket work -- status )
    >R
    BEGIN
        DUP 0< OVER _PBLOB-BUCKETS >= OR IF
            DROP R> DROP PERSIST-S-CAPACITY EXIT
        THEN
        DUP _PBLOB-BUCKETS 1- = IF
            DUP R@ _PBW-COUNT @ IF
                DROP R> DROP PERSIST-S-CAPACITY EXIT
            THEN
        THEN
        DUP R@ _PBW-COUNT @ DUP PBLOB-MANIFEST-FANOUT >= IF
            2DROP R> DROP PERSIST-S-CORRUPT EXIT
        THEN
        2DUP R@ _PBW-FRONTIER-REF
        R@ _PBW.TEMP-REF SWAP PERSIST-REF-COPY
        1+ DUP 2 PICK R@ _PBW-COUNT !
        PBLOB-MANIFEST-FANOUT = IF
            DUP _PBLOB-BUCKETS 1- = IF
                DROP R> DROP PERSIST-S-CAPACITY EXIT
            THEN
            DUP R@ _PBLOB-ENCODE-NODE
            DUP IF NIP R> DROP EXIT THEN DROP
            1+
        ELSE
            DROP R> DROP PERSIST-S-OK EXIT
        THEN
    AGAIN ;

: _PBLOB-HIGHER?  ( bucket work -- flag )
    SWAP 1+
    _PBLOB-BUCKETS SWAP ?DO
        I OVER _PBW-COUNT @ IF DROP -1 UNLOOP EXIT THEN
    LOOP
    DROP 0 ;

: _PBLOB-FINALIZE-MANIFEST  ( work -- root-bucket status )
    >R
    0
    BEGIN DUP _PBLOB-BUCKETS 1- < WHILE
        DUP R@ _PBW-COUNT @ DUP IF
            OVER 0= OVER 1 <> OR
            2 PICK R@ _PBLOB-HIGHER? OR IF
                DROP
                DUP R@ _PBLOB-ENCODE-NODE
                DUP IF >R DROP R> R> DROP -1 SWAP EXIT THEN DROP
                DUP 1+ R@ _PBLOB-ADD-TEMP
                DUP IF >R DROP R> R> DROP -1 SWAP EXIT THEN DROP
            ELSE
                DROP
            THEN
        ELSE
            DROP
        THEN
        1+
    REPEAT
    DROP
    R>
    _PBLOB-BUCKETS 0 ?DO
        I OVER _PBW-COUNT @ IF
            I OVER _PBW-COUNT @ 1 = IF
                DROP I PERSIST-S-OK UNLOOP EXIT
            THEN
            DROP -1 PERSIST-S-CORRUPT UNLOOP EXIT
        THEN
    LOOP
    DROP -1 PERSIST-S-CORRUPT ;

: _PBLOB-INSTALL-DESCRIPTOR  ( root-bucket work -- status )
    >R
    R@ _PBW.BLOB @ DUP PBLOB-SIZE 0 FILL
    _PBLOB-MAGIC OVER _PBL.MAGIC !
    R@ _PBW.TOTAL @ OVER _PBL.TOTAL !
    R@ _PBW.EXPECTED-COVERED @ OVER _PBL.CHUNKS !
    OVER 1- OVER _PBL.LEVEL !
    OVER 0 R@ _PBW-FRONTIER-REF OVER _PBL.ROOT PERSIST-REF-COPY
    NIP DUP PBLOB-VALID? IF
        DROP R> DROP PERSIST-S-OK
    ELSE
        DROP R> DROP PERSIST-S-CORRUPT
    THEN ;

: _PBLOB-INSTALL-EMPTY  ( work -- status )
    >R
    R@ _PBW.BLOB @ DUP PBLOB-SIZE 0 FILL
    _PBLOB-MAGIC OVER _PBL.MAGIC !
    -1 OVER _PBL.LEVEL !
    DUP PBLOB-VALID? IF
        DROP R> DROP PERSIST-S-OK
    ELSE
        DROP R> DROP PERSIST-S-CORRUPT
    THEN ;

: _PBLOB-WRITE-RUN  ( work -- status )
    >R
    R@ _PBW.STORE @ R@ _PBW.STORE-WORK @ PSTORE-TX-READY? 0= IF
        R> DROP PERSIST-S-BUSY EXIT
    THEN
    R@ _PBW.BLOB @ PBLOB-SIZE 0 FILL
    R@ _PBW.TOTAL @ DUP 0< IF DROP R> DROP PERSIST-S-INVALID EXIT THEN
    DUP _PBLOB-CHUNKS R@ _PBW.EXPECTED-COVERED !
    0= IF R> _PBLOB-INSTALL-EMPTY EXIT THEN
    R@ _PBW.CALLBACK-XT @ 0= IF R> DROP PERSIST-S-INVALID EXIT THEN
    BEGIN R@ _PBW.POSITION @ R@ _PBW.TOTAL @ < WHILE
        R@ _PBW.TOTAL @ R@ _PBW.POSITION @ -
        PBLOB-CHUNK-SIZE MIN R@ _PBW.REQUESTED !
        R@ _PBLOB-CALL-SOURCE DUP IF R> DROP EXIT THEN DROP
        R@ _PBW.CHUNK R@ _PBW.REQUESTED @ R@ _PBW.TEMP-REF
        R@ _PBW.STORE @ R@ _PBW.STORE-WORK @ PSTORE-APPEND-RECORD
        DUP IF R> DROP EXIT THEN DROP
        1 R@ _PBW.CHUNK-WRITES +!
        R@ _PBW.REQUESTED @ R@ _PBW.BYTES +!
        R@ _PBW.REQUESTED @ R@ _PBW.POSITION +!
        0 R@ _PBLOB-ADD-TEMP DUP IF R> DROP EXIT THEN DROP
    REPEAT
    R@ _PBLOB-FINALIZE-MANIFEST
    DUP IF >R DROP R> R> DROP EXIT THEN DROP
    R> _PBLOB-INSTALL-DESCRIPTOR ;

: PBLOB-WRITE  ( total-u source-xt source-context output-blob store store-work blob-work -- status )
    >R
    R@ PBLOB-WORK-VALID? 0= IF
        _PBLOB-DROP6 R> DROP PERSIST-S-INVALID EXIT
    THEN
    R@ _PBW.BUSY @ IF _PBLOB-DROP6 R> DROP PERSIST-S-BUSY EXIT THEN
    R@ _PBLOB-WORK-RESET
    5 PICK R@ _PBW.TOTAL !
    4 PICK R@ _PBW.CALLBACK-XT !
    3 PICK R@ _PBW.CALLBACK-CONTEXT !
    2 PICK R@ _PBW.BLOB !
    1 PICK R@ _PBW.STORE !
    DUP R@ _PBW.STORE-WORK !
    R@ _PBLOB-BOUND? 0= IF
        _PBLOB-DROP6 PERSIST-S-INVALID R@ _PBLOB-OP-END R> DROP EXIT
    THEN
    -1 R@ _PBW.BUSY !
    _PBLOB-DROP6
    R@ ['] _PBLOB-WRITE-RUN _PBLOB-RUN-CATCH
    R@ _PBLOB-WRITE-END R> DROP ;

\ =====================================================================
\ Manifest traversal and bounded ranged reads
\ =====================================================================

: _PBLOB-NODE-VALID?  ( work -- flag )
    >R
    R@ _PBW.PAYLOAD-U @ _PBLOB-NODE-HEADER-SIZE < IF R> DROP 0 EXIT THEN
    R@ _PBW.PAYLOAD-A @ DUP _PBLOB-NODE-MAGIC SWAP @ <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP 8 + @ R@ _PBW.EXPECTED-LEVEL @ <> IF DROP R> DROP 0 EXIT THEN
    DUP 16 + @ DUP 0> 0= OVER PBLOB-MANIFEST-FANOUT > OR IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP R@ _PBW.SLOT !
    PERSIST-REF-SIZE * _PBLOB-NODE-HEADER-SIZE +
    R@ _PBW.PAYLOAD-U @ <> IF DROP R> DROP 0 EXIT THEN
    DUP 24 + @ R@ _PBW.EXPECTED-COVERED @ <> IF DROP R> DROP 0 EXIT THEN
    DROP
    R@ _PBW.EXPECTED-LEVEL @ _PBLOB-CHILD-CAPACITY
    DUP IF 2DROP R> DROP 0 EXIT THEN DROP
    DUP R@ _PBW.ACTUAL !
    R@ _PBW.EXPECTED-COVERED @ SWAP _PBLOB-CEIL/
    R@ _PBW.SLOT @ <> IF R> DROP 0 EXIT THEN
    0
    BEGIN DUP R@ _PBW.SLOT @ < WHILE
        R@ _PBW.PAYLOAD-A @ _PBLOB-NODE-HEADER-SIZE +
        OVER PERSIST-REF-SIZE * + PERSIST-REF-VALID? 0= IF
            DROP R> DROP 0 EXIT
        THEN
        1+
    REPEAT
    DROP
    R> DROP -1 ;

: _PBLOB-LOCATE-CHUNK  ( chunk-index work -- status )
    >R
    DUP 0< OVER R@ _PBW.BLOB @ _PBL.CHUNKS @ >= OR IF
        DROP R> DROP PERSIST-S-NOT-FOUND EXIT
    THEN
    R@ _PBW.LOCAL-INDEX !
    R@ _PBW.BLOB @ _PBL.CHUNKS @ R@ _PBW.EXPECTED-COVERED !
    R@ _PBW.BLOB @ _PBL.LEVEL @ R@ _PBW.EXPECTED-LEVEL !
    R@ _PBW.BLOB @ _PBL.ROOT R@ _PBW.SELECTED-REF PERSIST-REF-COPY
    BEGIN
        R@ _PBW.SELECTED-REF
        R@ _PBW.STORE @ R@ _PBW.STORE-WORK @ PSTORE-READ-RECORD
        DUP IF R> DROP EXIT THEN DROP
        1 R@ _PBW.MANIFEST-READS +!
        R@ _PBW.STORE-WORK @ PSTORE-RECORD-PAYLOAD$
        DUP R@ _PBW.PAYLOAD-U ! SWAP R@ _PBW.PAYLOAD-A ! DROP
        R@ _PBLOB-NODE-VALID? 0= IF R> DROP PERSIST-S-CORRUPT EXIT THEN
        R@ _PBW.LOCAL-INDEX @ R@ _PBW.ACTUAL @ /MOD
        SWAP R@ _PBW.LOCAL-INDEX !
        DUP R@ _PBW.PAYLOAD-U !
        R@ _PBW.SLOT @ >= IF R> DROP PERSIST-S-CORRUPT EXIT THEN
        R@ _PBW.PAYLOAD-A @ _PBLOB-NODE-HEADER-SIZE +
        R@ _PBW.PAYLOAD-U @ PERSIST-REF-SIZE * +
        R@ _PBW.SELECTED-REF PERSIST-REF-COPY
        R@ _PBW.EXPECTED-LEVEL @ 0= IF R> DROP PERSIST-S-OK EXIT THEN
        R@ _PBW.EXPECTED-COVERED @
        R@ _PBW.PAYLOAD-U @ R@ _PBW.ACTUAL @ * -
        R@ _PBW.ACTUAL @ MIN R@ _PBW.EXPECTED-COVERED !
        -1 R@ _PBW.EXPECTED-LEVEL +!
    AGAIN ;

: _PBLOB-EXPECTED-CHUNK-U  ( chunk-index work -- u )
    >R
    1+ R@ _PBW.BLOB @ _PBL.CHUNKS @ < IF
        R> DROP PBLOB-CHUNK-SIZE EXIT
    THEN
    R@ _PBW.BLOB @ _PBL.TOTAL @
    R@ _PBW.BLOB @ _PBL.CHUNKS @ 1- PBLOB-CHUNK-SIZE * -
    R> DROP ;

: _PBLOB-READ-RANGE-RUN  ( work -- status )
    >R
    R@ _PBW.BLOB @ PBLOB-VALID? 0= IF R> DROP PERSIST-S-INVALID EXIT THEN
    R@ _PBW.POSITION @ DUP 0< IF
        DROP R> DROP PERSIST-S-INVALID EXIT
    THEN
    R@ _PBW.BLOB @ _PBL.TOTAL @ > IF R> DROP PERSIST-S-NOT-FOUND EXIT THEN
    R@ _PBW.REQUESTED @ DUP 0< IF
        DROP R> DROP PERSIST-S-INVALID EXIT
    THEN
    R@ _PBW.BLOB @ _PBL.TOTAL @ R@ _PBW.POSITION @ - MIN
    DUP R@ _PBW.RETURNED !
    0 R@ _PBW.REQUESTED !
    0= IF R> DROP PERSIST-S-OK EXIT THEN
    R@ _PBW.CALLBACK-XT @ 0= IF R> DROP PERSIST-S-INVALID EXIT THEN
    BEGIN R@ _PBW.REQUESTED @ R@ _PBW.RETURNED @ < WHILE
        R@ _PBW.POSITION @ PBLOB-CHUNK-SIZE /MOD
        OVER R@ _PBW.CALLBACK-STATUS !
        R@ _PBW.SLOT ! DROP
        R@ _PBW.SLOT @ DUP R@ _PBLOB-LOCATE-CHUNK DUP IF
            >R DROP R> R> DROP EXIT
        THEN DROP
        R@ _PBLOB-EXPECTED-CHUNK-U R@ _PBW.ACTUAL !
        R@ _PBW.SELECTED-REF
        R@ _PBW.STORE @ R@ _PBW.STORE-WORK @ PSTORE-READ-RECORD
        DUP IF R> DROP EXIT THEN DROP
        1 R@ _PBW.CHUNK-READS +!
        R@ _PBW.STORE-WORK @ PSTORE-RECORD-PAYLOAD$
        DUP R@ _PBW.ACTUAL @ <> IF
            2DROP R> DROP PERSIST-S-CORRUPT EXIT
        THEN
        DROP R@ _PBW.CALLBACK-STATUS @ + R@ _PBW.PAYLOAD-A !
        R@ _PBW.ACTUAL @ R@ _PBW.CALLBACK-STATUS @ -
        R@ _PBW.RETURNED @ R@ _PBW.REQUESTED @ - MIN
        R@ _PBW.PAYLOAD-U !
        R@ _PBLOB-CALL-SINK DUP IF
            R> DROP EXIT
        THEN DROP
        R@ _PBW.PAYLOAD-U @ DUP R@ _PBW.BYTES +!
        DUP R@ _PBW.POSITION +!
        R@ _PBW.REQUESTED +!
    REPEAT
    R> DROP PERSIST-S-OK ;

: PBLOB-READ-RANGE  ( blob offset requested-u sink-xt sink-context store store-work blob-work -- status )
    >R
    R@ PBLOB-WORK-VALID? 0= IF
        _PBLOB-DROP7 R> DROP PERSIST-S-INVALID EXIT
    THEN
    R@ _PBW.BUSY @ IF _PBLOB-DROP7 R> DROP PERSIST-S-BUSY EXIT THEN
    R@ _PBLOB-WORK-RESET
    6 PICK R@ _PBW.BLOB !
    5 PICK R@ _PBW.POSITION !
    4 PICK R@ _PBW.REQUESTED !
    3 PICK R@ _PBW.CALLBACK-XT !
    2 PICK R@ _PBW.CALLBACK-CONTEXT !
    1 PICK R@ _PBW.STORE !
    DUP R@ _PBW.STORE-WORK !
    R@ _PBLOB-BOUND? 0= IF
        _PBLOB-DROP7 PERSIST-S-INVALID R@ _PBLOB-OP-END R> DROP EXIT
    THEN
    -1 R@ _PBW.BUSY !
    _PBLOB-DROP7
    R@ ['] _PBLOB-READ-RANGE-RUN _PBLOB-RUN-CATCH
    R@ _PBLOB-OP-END R> DROP ;

: PBLOB-STREAM
  ( blob offset sink-xt sink-context store store-work blob-work -- status )
    >R
    PERSIST-MAX-SIGNED
    6 PICK 6 PICK ROT 6 PICK 6 PICK 6 PICK 6 PICK R>
    PBLOB-READ-RANGE
    >R _PBLOB-DROP6 R> ;
