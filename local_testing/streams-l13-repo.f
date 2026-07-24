\ Focused RAM-VFS contracts for the L13 Streams repository owner.

PROVIDED akashic-streams-l13-repository-contracts

VARIABLE _SL13R-checks
VARIABLE _SL13R-fails
VARIABLE _SL13R-depth
VARIABLE _SL13R-arena
VARIABLE _SL13R-vfs
VARIABLE _SL13R-ior
VARIABLE _SL13R-old-vfs
VARIABLE _SL13R-owner-calls
VARIABLE _SL13R-expected-generation
VARIABLE _SL13R-stage-sink-bytes
VARIABLE _SL13R-stage-sink-errors

CREATE _SL13R-ops VFS-OPS-SIZE ALLOT
CREATE _SL13R-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _SL13R-cache0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _SL13R-cache1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13R-cache0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13R-cache1-memory
GUARD _SL13R-guard

STREAMS-REPOSITORY-SIZE XBUF _SL13R-repository
STREAMS-REPOSITORY-WORK-SIZE XBUF _SL13R-work
STREAMS-REPOSITORY-RECORD-BUFFER-MIN XBUF _SL13R-record-buffer
CREATE _SL13R-authority RID-SIZE ALLOT
CREATE _SL13R-other-authority RID-SIZE ALLOT
CREATE _SL13R-source-rid RID-SIZE ALLOT
STREAMS-SOURCE-SIZE XBUF _SL13R-source
STREAMS-SOURCE-SIZE XBUF _SL13R-source-out
STREAMS-SOURCE-AUTHORITY-WORK-SIZE XBUF _SL13R-source-work
STREAMS-OBSERVATION-CHECKPOINT-SIZE XBUF _SL13R-checkpoint
SPREC-ATTEMPT-SIZE XBUF _SL13R-attempt
SPREC-SOURCE-SIZE XBUF _SL13R-stage-record
SPREC-SOURCE-SIZE XBUF _SL13R-stage-record-out
CREATE _SL13R-namespace SHA3-256-LEN ALLOT
CREATE _SL13R-key STREAMS-PI-KEY-MAX ALLOT
CREATE _SL13R-ref PERSIST-REF-SIZE ALLOT
CREATE _SL13R-blob PBLOB-SIZE ALLOT
STREAMS-PA-RANGE-ROW-SIZE XBUF _SL13R-query-rows
STREAMS-QUERY-PAGE-SIZE XBUF _SL13R-query-page
STREAMS-QUERY-WORK-SIZE XBUF _SL13R-query-work

: _SL13R-assert  ( flag -- )
    1 _SL13R-checks +!
    0= IF
        1 _SL13R-fails +!
        ." STREAMS L13 REPOSITORY ASSERT " _SL13R-checks @ . CR
    THEN ;

: _SL13R-stack  ( -- )
    DEPTH DUP _SL13R-depth @ <> IF
        ." STREAMS L13 REPOSITORY STACK "
        _SL13R-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13R-depth @ = _SL13R-assert ;

: _SL13R-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 REPOSITORY STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13R-assert _SL13R-stack ;

: _SL13R-fault  ( point ordinal context -- status )
    2DROP DROP PERSIST-S-OK ;

: _SL13R-owner-ok  ( context repository work -- status )
    2DROP DROP
    1 _SL13R-owner-calls +!
    STREAMS-REPOSITORY-S-OK ;

: _SL13R-owner-bad-status  ( context repository work -- status )
    2DROP DROP 99 ;

: _SL13R-owner-throw  ( context repository work -- status )
    2DROP DROP -713 THROW ;

: _SL13R-owner-reenter  ( context repository work -- status )
    ROT DROP STREAMS-REPOSITORY-LOAD
    STREAMS-REPOSITORY-S-BUSY =
    IF STREAMS-REPOSITORY-S-OK
    ELSE STREAMS-REPOSITORY-S-CONFLICT THEN ;

: _SL13R-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _SL13R-status ;

: _SL13R-runtime-init  ( -- )
    VFS-CUR _SL13R-old-vfs !
    VFS-RAM-OPS _SL13R-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _SL13R-binding VFS-BINDING-DESC-SIZE MOVE
    _SL13R-ops _SL13R-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW
    DUP 0= _SL13R-assert DROP _SL13R-arena !
    _SL13R-arena @ _SL13R-binding 0 VFS-NEW
    _SL13R-ior ! _SL13R-vfs !
    _SL13R-ior @ 0= _SL13R-assert
    _SL13R-vfs @ 0<> _SL13R-assert
    _SL13R-cache0-memory _SL13R-cache0 _SL13R-cache-init
    _SL13R-cache1-memory _SL13R-cache1 _SL13R-cache-init
    _SL13R-authority RID-SIZE 0x61 FILL
    _SL13R-other-authority RID-SIZE 0x62 FILL
    _SL13R-source-rid RID-SIZE 0x63 FILL
    _SL13R-namespace SHA3-256-LEN 0x64 FILL
    _SL13R-key STREAMS-PI-KEY-MAX 0 FILL
    _SL13R-ref PERSIST-REF-SIZE 0 FILL
    0 _SL13R-owner-calls !
    0 _SL13R-expected-generation !
    0 _SL13R-stage-sink-bytes !
    0 _SL13R-stage-sink-errors !
    _SL13R-stack ;

: _SL13R-repository-init  ( -- )
    _SL13R-vfs @ _SL13R-cache0 _SL13R-cache1 _SL13R-guard
    ['] _SL13R-fault 0 _SL13R-repository
        STREAMS-REPOSITORY-INIT
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-VALID? _SL13R-assert
    _SL13R-record-buffer STREAMS-REPOSITORY-RECORD-BUFFER-MIN
    _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WORK-INIT
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-work STREAMS-REPOSITORY-WORK-VALID? _SL13R-assert
    _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WORK-BOUND? _SL13R-assert
    _SL13R-stack ;

: _SL13R-source-candidate  ( -- )
    _SL13R-source STREAMS-SOURCE-INIT
    _SL13R-source-rid _SL13R-source STREAMS-SOURCE-ID!
        SSREG-S-OK _SL13R-status
    SSOURCE-KIND-SYNDICATION _SL13R-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _SL13R-source SSOURCE.FORMAT !
    S" L13 configured feed" _SL13R-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13R-status
    S" https://example.test/feed.json"
        _SL13R-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13R-status
    _SL13R-source SSOURCE.REVISION @ 0= _SL13R-assert
    1 _SL13R-source SSOURCE.REVISION !
    _SL13R-source STREAMS-SOURCE-VALID? _SL13R-assert
    0 _SL13R-source SSOURCE.REVISION !
    _SL13R-stack ;

: _SL13R-adapter  ( -- adapter )
    _SL13R-repository STREAMS-REPOSITORY-ADAPTER@ ;

: _SL13R-adapter-work  ( -- work )
    _SL13R-work STREAMS-REPOSITORY-ADAPTER-WORK@ ;

: _SL13R-stage-source
  ( logical-offset destination-a requested-u seed -- actual-u status )
    SWAP DUP >R
    0 ?DO
        1 PICK I +
        3 PICK I + 2 PICK + 255 AND
        SWAP C!
    LOOP
    2DROP DROP R> PERSIST-S-OK ;

: _SL13R-stage-sink
  ( logical-offset payload-a payload-u seed -- status )
    SWAP DUP >R
    0 ?DO
        1 PICK I + C@
        3 PICK I + 2 PICK + 255 AND
        <> IF 1 _SL13R-stage-sink-errors +! THEN
    LOOP
    2DROP DROP
    R> _SL13R-stage-sink-bytes +!
    PERSIST-S-OK ;

: _SL13R-stage-source-record  ( -- )
    _SL13R-source-candidate
    1 _SL13R-source SSOURCE.REVISION !
    _SL13R-source 1 _SL13R-stage-record SPREC-SOURCE-CONSTRUCT
        SPREC-S-OK _SL13R-status
    0 _SL13R-source SSOURCE.REVISION ! ;

: _SL13R-staging-owner  ( context repository work -- status )
    2DROP DROP
    _SL13R-authority _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-FIRST-STAGE-BEGIN
        STREAMS-PA-S-OK _SL13R-status
    STREAMS-PI-TREE-DIRECTORY _SL13R-adapter-work
        STREAMS-PA-STAGED-TREE-CARDINALITY@ 0= _SL13R-assert

    _SL13R-stage-record SPREC-SOURCE-SIZE _SL13R-ref
        _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-APPEND-RECORD STREAMS-PA-S-OK _SL13R-status
    _SL13R-source-rid _SL13R-key STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13R-status
    _SL13R-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13R-ref _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-STAGED-PUT STREAMS-PA-S-OK _SL13R-status
    STREAMS-PI-TREE-DIRECTORY _SL13R-adapter-work
        STREAMS-PA-STAGED-TREE-CARDINALITY@ 1 = _SL13R-assert
    _SL13R-stage-record-out SPREC-SOURCE-SIZE 0xD8 FILL
    _SL13R-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13R-stage-record-out SPREC-SOURCE-SIZE
        _SL13R-adapter _SL13R-adapter-work STREAMS-PA-STAGED-GET
    DUP STREAMS-PA-S-OK = _SL13R-assert
    SWAP SPREC-SOURCE-SIZE = _SL13R-assert
    DROP
    _SL13R-stage-record-out SPREC-SOURCE-SIZE
        SPREC-SOURCE-VALID? _SL13R-assert
    _SL13R-stage-record-out SPRS.SOURCE SSOURCE.ID
        _SL13R-source-rid RID= _SL13R-assert

    37 ['] _SL13R-stage-source 0x71 _SL13R-blob
        _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-BLOB-WRITE STREAMS-PA-S-OK _SL13R-status
    0 _SL13R-stage-sink-bytes !
    0 _SL13R-stage-sink-errors !
    _SL13R-blob 0 37 ['] _SL13R-stage-sink 0x71
        _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-STAGED-BLOB-READ-RANGE
        STREAMS-PA-S-OK _SL13R-status
    _SL13R-stage-sink-bytes @ 37 = _SL13R-assert
    _SL13R-stage-sink-errors @ 0= _SL13R-assert

    _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-FIRST-STAGE-DISCARD
        STREAMS-PA-S-OK _SL13R-status
    _SL13R-adapter-work STREAMS-PA-AUTHORITY-ROOT@ 0=
        _SL13R-assert

    _SL13R-authority _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-FIRST-STAGE-BEGIN
        STREAMS-PA-S-OK _SL13R-status
    _SL13R-adapter-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13R-assert
    STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY
        SWAP SAR.PROVENANCE !
    STREAMS-PI-TREE-DIRECTORY _SL13R-adapter-work
        STREAMS-PA-STAGED-TREE-CARDINALITY@ 0= _SL13R-assert
    _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-FIRST-STAGE-COMMIT
        STREAMS-PA-S-OK _SL13R-status
    STREAMS-REPOSITORY-S-OK ;

: _SL13R-complete-empty-query  ( -- )
    _SL13R-query-work STREAMS-QUERY-WORK-INIT
        STREAMS-QUERY-S-OK _SL13R-status
    _SL13R-query-rows 1 _SL13R-query-page
        STREAMS-QUERY-PAGE-INIT
        STREAMS-QUERY-S-OK _SL13R-status
    _SL13R-query-page _SL13R-adapter _SL13R-adapter-work
        _SL13R-query-work STREAMS-QUERY-SOURCES-FIRST
        STREAMS-QUERY-S-OK _SL13R-status
    _SL13R-query-page STREAMS-QUERY-PAGE-VALID? _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-PUBLISHED? _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-COUNT@ 0=
        _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-PROVENANCE@
        STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY =
        _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-COMPLETE? _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-AFTER-CONTINUATION@
        STREAMS-QUERY-CONTINUATION-READY? 0= _SL13R-assert

    _SL13R-query-page _SL13R-adapter _SL13R-adapter-work
        _SL13R-query-work STREAMS-QUERY-GLOBAL-TIME-FIRST
        STREAMS-QUERY-S-OK _SL13R-status
    _SL13R-query-page STREAMS-QUERY-PAGE-VALID? _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-FAMILY@
        STREAMS-QUERY-FAMILY-GLOBAL-TIME = _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-COUNT@ 0=
        _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-PROVENANCE@
        STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY =
        _SL13R-assert
    _SL13R-query-page STREAMS-QUERY-PAGE-COMPLETE? _SL13R-assert
    _SL13R-stack ;

: _SL13R-provision  ( -- )
    _SL13R-repository _SL13R-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-ABSENT _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-LOADED? _SL13R-assert
    _SL13R-repository STREAMS-REPOSITORY-PROVISIONED?
        0= _SL13R-assert
    _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-STAGING-PREPARE
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-STAGING-PREPARED?
        _SL13R-assert
    _SL13R-repository STREAMS-REPOSITORY-PROVISIONED?
        0= _SL13R-assert
    77 ['] _SL13R-owner-ok _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-CONFLICT _SL13R-status
    _SL13R-stage-source-record
    77 ['] _SL13R-staging-owner _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-STAGING-OWNER
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-repository _SL13R-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-PROVISIONED? _SL13R-assert
    _SL13R-repository STREAMS-REPOSITORY-STAGING-PREPARED?
        0= _SL13R-assert
    _SL13R-repository STREAMS-REPOSITORY-BLOCKED? 0= _SL13R-assert
    _SL13R-repository STREAMS-REPOSITORY-GENERATION@ 1 =
        _SL13R-assert
    _SL13R-work STREAMS-REPOSITORY-LOGICAL-GENERATION@ 0=
        _SL13R-assert
    _SL13R-work STREAMS-REPOSITORY-MUTATION-SEQUENCE@ 0=
        _SL13R-assert
    _SL13R-work STREAMS-REPOSITORY-AUTHORITY-ROOT@
    DUP 0<> _SL13R-assert
    DUP SAR.AUTHORITY-ID _SL13R-authority RID= _SL13R-assert
    DUP SAR.PROVENANCE @
        STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY =
        _SL13R-assert
    SAR.SOURCE-COUNT @ 0= _SL13R-assert
    STREAMS-PI-TREE-DIRECTORY _SL13R-work
        STREAMS-REPOSITORY-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 0= _SL13R-assert
    S" /streams/root-0" _SL13R-vfs @ VFS-RESOLVE?
    DUP 0= _SL13R-assert DROP
    DUP 0<> _SL13R-assert
    IN.TYPE @ VFS-T-FILE = _SL13R-assert
    _SL13R-authority _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-PROVISION
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-complete-empty-query
    1 _SL13R-expected-generation ! ;

: _SL13R-source-root  ( -- root )
    _SL13R-work STREAMS-REPOSITORY-AUTHORITY-ROOT@ ;

: _SL13R-attempt-head  ( -- head )
    _SL13R-source-rid _SL13R-checkpoint OCHK-SOURCE-FIND ;

: _SL13R-attempt-history-key  ( -- )
    _SL13R-attempt SPRA.SOURCE-ID
    _SL13R-attempt SPRA.ATTEMPT-SEQUENCE @
    _SL13R-attempt SPRA.ATTEMPT-ID
    _SL13R-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY
        STREAMS-PI-S-OK _SL13R-status ;

: _SL13R-attempt-put  ( -- )
    _SL13R-attempt SPREC-ATTEMPT-SIZE _SL13R-ref
        _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-APPEND-RECORD STREAMS-PA-S-OK _SL13R-status
    _SL13R-attempt-history-key
    _SL13R-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        _SL13R-ref _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13R-status ;

: _SL13R-attempt-accepted  ( -- )
    _SL13R-checkpoint OCHK-INIT
    _SL13R-source-rid 3 _SL13R-namespace OCHK-NATIVE-PROVIDER-ID
        S" https://example.test/feed.json" _SL13R-checkpoint
        OCHK-BEGIN OCHK-S-OK _SL13R-status
    _SL13R-attempt-head DUP 0<> _SL13R-assert
    _SL13R-attempt SPREC-ATTEMPT-CONSTRUCT
        SPREC-S-OK _SL13R-status
    _SL13R-adapter _SL13R-adapter-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13R-status
    _SL13R-attempt-put
    _SL13R-source-rid _SL13R-key STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13R-status
    _SL13R-key STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        _SL13R-ref _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13R-status
    _SL13R-source-root
    DUP 1 SWAP SAR.ACQUISITION-SEQUENCE !
    DUP 1 SWAP SAR.ATTEMPT-COUNT +!
    1 SWAP SAR.ACTIVE-COUNT +!
    _SL13R-adapter _SL13R-adapter-work STREAMS-PA-COMMIT
        STREAMS-PA-S-OK _SL13R-status
    5 _SL13R-expected-generation !
    _SL13R-stack ;

: _SL13R-attempt-terminal  ( -- )
    _SL13R-source-rid 3
        OCHK-ATTEMPT-FAILED OCHK-O-TRANSPORT
        0 0 0 1 0 _SL13R-checkpoint
        OCHK-TERMINAL OCHK-S-OK _SL13R-status
    _SL13R-attempt-head _SL13R-attempt SPREC-ATTEMPT-CONSTRUCT
        SPREC-S-OK _SL13R-status
    _SL13R-adapter _SL13R-adapter-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13R-status
    _SL13R-attempt-put
    _SL13R-source-rid _SL13R-key STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13R-status
    _SL13R-key STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        _SL13R-adapter _SL13R-adapter-work
        STREAMS-PA-DELETE STREAMS-PA-S-OK _SL13R-status
    -1 _SL13R-source-root SAR.ACTIVE-COUNT +!
    _SL13R-adapter _SL13R-adapter-work STREAMS-PA-COMMIT
        STREAMS-PA-S-OK _SL13R-status
    6 _SL13R-expected-generation !
    _SL13R-stack ;

: _SL13R-source-read  ( expected-revision expected-enabled -- )
    >R >R
    _SL13R-source-out STREAMS-SOURCE-SIZE 0xA5 FILL
    _SL13R-source-rid _SL13R-source-out
        _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-READ
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13R-status
    _SL13R-source-out SSOURCE.REVISION @ R> = _SL13R-assert
    _SL13R-source-out SSOURCE.FLAGS @ SSOURCE-F-ENABLED AND 0<>
        R> 0<> = _SL13R-assert
    _SL13R-source-out SSOURCE.ID _SL13R-source-rid RID=
        _SL13R-assert
    _SL13R-source-out STREAMS-SOURCE-VALID? _SL13R-assert
    _SL13R-stack ;

: _SL13R-source-lifecycle  ( -- )
    _SL13R-source-work STREAMS-SOURCE-AUTHORITY-WORK-INIT
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13R-status
    _SL13R-source-work STREAMS-SOURCE-AUTHORITY-WORK-VALID?
        _SL13R-assert
    _SL13R-source-candidate

    _SL13R-source-out STREAMS-SOURCE-SIZE 0xA5 FILL
    _SL13R-source-rid _SL13R-source-out
        _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-READ
        STREAMS-SOURCE-AUTHORITY-S-NOT-FOUND _SL13R-status
    _SL13R-source-out C@ 0xA5 = _SL13R-assert

    _SL13R-source _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13R-status
    _SL13R-source SSOURCE.REVISION @ 0= _SL13R-assert
    2 _SL13R-expected-generation !
    _SL13R-repository STREAMS-REPOSITORY-GENERATION@ 2 =
        _SL13R-assert
    _SL13R-source-root
    DUP SAR.LOGICAL-GENERATION @ 1 = _SL13R-assert
    DUP SAR.MUTATION-SEQUENCE @ 1 = _SL13R-assert
    DUP SAR.SOURCE-COUNT @ 1 = _SL13R-assert
    DUP SAR.REMOVED-SOURCE-COUNT @ 0= _SL13R-assert
    DROP
    STREAMS-PI-TREE-DIRECTORY _SL13R-work
        STREAMS-REPOSITORY-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 2 = _SL13R-assert
    1 -1 _SL13R-source-read

    _SL13R-source _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-DUPLICATE _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-GENERATION@ 2 =
        _SL13R-assert

    _SL13R-source-out _SL13R-source STREAMS-SOURCE-SIZE MOVE
    S" L13 configured feed replacement"
        _SL13R-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13R-status
    _SL13R-source 1 _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-REPLACE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13R-status
    _SL13R-source SSOURCE.REVISION @ 1 = _SL13R-assert
    3 _SL13R-expected-generation !
    2 -1 _SL13R-source-read
    _SL13R-source 1 _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-REPLACE
        STREAMS-SOURCE-AUTHORITY-S-STALE _SL13R-status

    _SL13R-source-rid 2 -1
        _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-ENABLE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-GENERATION@ 3 =
        _SL13R-assert
    _SL13R-source-rid 2 0
        _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-ENABLE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13R-status
    4 _SL13R-expected-generation !
    3 0 _SL13R-source-read
    _SL13R-source-rid 2 -1
        _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-ENABLE
        STREAMS-SOURCE-AUTHORITY-S-STALE _SL13R-status

    _SL13R-attempt-accepted
    _SL13R-source-root
    DUP SAR.ACTIVE-COUNT @ 1 = _SL13R-assert
    DUP SAR.ATTEMPT-COUNT @ 1 = _SL13R-assert
    SAR.ACQUISITION-SEQUENCE @ 1 = _SL13R-assert
    _SL13R-source-rid 3 _SL13R-repository _SL13R-work
        _SL13R-source-work STREAMS-SOURCE-AUTHORITY-REMOVE
        STREAMS-SOURCE-AUTHORITY-S-BUSY _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-GENERATION@ 5 =
        _SL13R-assert
    _SL13R-attempt-terminal

    _SL13R-source-rid 2 _SL13R-repository _SL13R-work
        _SL13R-source-work STREAMS-SOURCE-AUTHORITY-REMOVE
        STREAMS-SOURCE-AUTHORITY-S-STALE _SL13R-status
    _SL13R-source-rid 3 _SL13R-repository _SL13R-work
        _SL13R-source-work STREAMS-SOURCE-AUTHORITY-REMOVE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13R-status
    7 _SL13R-expected-generation !
    _SL13R-source-root
    DUP SAR.LOGICAL-GENERATION @ 6 = _SL13R-assert
    DUP SAR.MUTATION-SEQUENCE @ 6 = _SL13R-assert
    DUP SAR.SOURCE-COUNT @ 0= _SL13R-assert
    DUP SAR.REMOVED-SOURCE-COUNT @ 1 = _SL13R-assert
    DUP SAR.ATTEMPT-COUNT @ 1 = _SL13R-assert
    DUP SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    DROP
    STREAMS-PI-TREE-DIRECTORY _SL13R-work
        STREAMS-REPOSITORY-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 1 = _SL13R-assert

    _SL13R-source-out STREAMS-SOURCE-SIZE 0xB6 FILL
    _SL13R-source-rid _SL13R-source-out
        _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-READ
        STREAMS-SOURCE-AUTHORITY-S-GONE _SL13R-status
    _SL13R-source-out C@ 0xB6 = _SL13R-assert
    0 _SL13R-source SSOURCE.REVISION !
    _SL13R-source _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-DUPLICATE _SL13R-status
    _SL13R-source-work STREAMS-SOURCE-AUTHORITY-WORK-STATUS@
        STREAMS-SOURCE-AUTHORITY-S-DUPLICATE = _SL13R-assert
    _SL13R-stack ;

: _SL13R-owner-contracts  ( -- )
    77 ['] _SL13R-owner-ok _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-owner-calls @ 1 = _SL13R-assert
    77 0 _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-INVALID _SL13R-status
    77 ['] _SL13R-owner-bad-status _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-INVALID _SL13R-status
    77 ['] _SL13R-owner-throw _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-FAULT _SL13R-status
    77 ['] _SL13R-owner-reenter _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-work STREAMS-REPOSITORY-WORK-BUSY? 0= _SL13R-assert
    _SL13R-guard GUARD-HELD? 0= _SL13R-assert
    _SL13R-stack ;

: _SL13R-conflict-fence  ( -- )
    _SL13R-other-authority _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-PROVISION
        STREAMS-REPOSITORY-S-CONFLICT _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-BLOCKED? _SL13R-assert
    77 ['] _SL13R-owner-ok _SL13R-repository _SL13R-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-CONFLICT _SL13R-status
    _SL13R-stack ;

: _SL13R-reopen  ( -- )
    _SL13R-repository _SL13R-work STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-cache0-memory _SL13R-cache0 _SL13R-cache-init
    _SL13R-cache1-memory _SL13R-cache1 _SL13R-cache-init
    _SL13R-repository-init
    _SL13R-repository _SL13R-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-OK _SL13R-status
    _SL13R-repository STREAMS-REPOSITORY-GENERATION@
        _SL13R-expected-generation @ =
        _SL13R-assert
    _SL13R-work STREAMS-REPOSITORY-AUTHORITY-ROOT@
        SAR.AUTHORITY-ID _SL13R-authority RID= _SL13R-assert
    _SL13R-source-out STREAMS-SOURCE-SIZE 0xC7 FILL
    _SL13R-source-rid _SL13R-source-out
        _SL13R-repository _SL13R-work _SL13R-source-work
        STREAMS-SOURCE-AUTHORITY-READ
        STREAMS-SOURCE-AUTHORITY-S-GONE _SL13R-status
    _SL13R-source-out C@ 0xC7 = _SL13R-assert
    _SL13R-stack ;

: _SL13R-finish  ( -- )
    _SL13R-repository _SL13R-work STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13R-status
    0 _SL13R-vfs @ VFS-UNMOUNT 0= _SL13R-assert
    _SL13R-vfs @ VFS-DESTROY
    _SL13R-old-vfs @ VFS-USE
    _SL13R-arena @ ARENA-DESTROY
    _SL13R-stack ;

: _SL13R-RUN  ( -- )
    0 _SL13R-checks ! 0 _SL13R-fails !
    DEPTH _SL13R-depth !
    _SL13R-runtime-init
    _SL13R-repository-init
    _SL13R-provision
    _SL13R-owner-contracts
    _SL13R-source-lifecycle
    _SL13R-conflict-fence
    _SL13R-reopen
    _SL13R-finish
    _SL13R-fails @ IF
        ." STREAMS L13 REPOSITORY FAIL "
            _SL13R-fails @ . ." / " _SL13R-checks @ . CR
    ELSE
        ." STREAMS L13 REPOSITORY PASS " _SL13R-checks @ . CR
    THEN ;
