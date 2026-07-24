\ Bounded RAM-VFS contracts for the L13 Streams acquisition authority.

PROVIDED akashic-streams-l13-acquisition-contracts

VARIABLE _SL13A-checks
VARIABLE _SL13A-fails
VARIABLE _SL13A-depth
VARIABLE _SL13A-arena
VARIABLE _SL13A-vfs
VARIABLE _SL13A-ior
VARIABLE _SL13A-old-vfs
VARIABLE _SL13A-expected-sequence
VARIABLE _SL13A-expected-attempt-count
VARIABLE _SL13A-check-attempt
VARIABLE _SL13A-check-state
VARIABLE _SL13A-check-active
VARIABLE _SL13A-build-rid
VARIABLE _SL13A-request-rid
VARIABLE _SL13A-request-revision
VARIABLE _SL13A-request-namespace
VARIABLE _SL13A-request-uri-a
VARIABLE _SL13A-request-uri-u
VARIABLE _SL13A-terminal-attempt
VARIABLE _SL13A-terminal-state
VARIABLE _SL13A-terminal-outcome

CREATE _SL13A-ops VFS-OPS-SIZE ALLOT
CREATE _SL13A-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _SL13A-cache0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _SL13A-cache1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13A-cache0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13A-cache1-memory
GUARD _SL13A-guard

STREAMS-REPOSITORY-SIZE XBUF _SL13A-repository
STREAMS-REPOSITORY-WORK-SIZE XBUF _SL13A-repo-work
STREAMS-REPOSITORY-RECORD-BUFFER-MIN XBUF _SL13A-record-buffer
STREAMS-SOURCE-AUTHORITY-WORK-SIZE XBUF _SL13A-source-work
STREAMS-ACQUISITION-WORK-SIZE XBUF _SL13A-acquisition-work

CREATE _SL13A-authority RID-SIZE ALLOT
CREATE _SL13A-source-a-rid RID-SIZE ALLOT
CREATE _SL13A-source-b-rid RID-SIZE ALLOT
CREATE _SL13A-source-c-rid RID-SIZE ALLOT
CREATE _SL13A-namespace-a SHA3-256-LEN ALLOT
CREATE _SL13A-namespace-b SHA3-256-LEN ALLOT
CREATE _SL13A-namespace-c SHA3-256-LEN ALLOT

STREAMS-SOURCE-SIZE XBUF _SL13A-source
STREAMS-SOURCE-SIZE XBUF _SL13A-source-out
STREAMS-ACQUISITION-BEGIN-REQUEST-SIZE XBUF _SL13A-begin-request
STREAMS-ACQUISITION-TERMINAL-REQUEST-SIZE XBUF _SL13A-terminal-request
OCHK-SOURCE-SIZE XBUF _SL13A-accepted-a
OCHK-SOURCE-SIZE XBUF _SL13A-accepted-b
OCHK-SOURCE-SIZE XBUF _SL13A-accepted-c
OCHK-SOURCE-SIZE XBUF _SL13A-terminal-out
OCHK-SOURCE-SIZE XBUF _SL13A-scratch-out
OCHK-SOURCE-SIZE XBUF _SL13A-next-out
OCHK-SOURCE-SIZE 2 * XBUF _SL13A-recovered

SPREC-ATTEMPT-SIZE XBUF _SL13A-history-record
SPREC-ATTEMPT-SIZE XBUF _SL13A-active-record
CREATE _SL13A-key STREAMS-PI-KEY-MAX ALLOT

: _SL13A-assert  ( flag -- )
    1 _SL13A-checks +!
    0= IF
        1 _SL13A-fails +!
        ." STREAMS L13 ACQUISITION ASSERT " _SL13A-checks @ . CR
    THEN ;

: _SL13A-stack  ( -- )
    DEPTH DUP _SL13A-depth @ <> IF
        ." STREAMS L13 ACQUISITION STACK "
        _SL13A-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13A-depth @ = _SL13A-assert ;

: _SL13A-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 ACQUISITION STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13A-assert _SL13A-stack ;

: _SL13A-fault  ( point ordinal context -- status )
    2DROP DROP PERSIST-S-OK ;

: _SL13A-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _SL13A-status ;

: _SL13A-adapter  ( -- adapter )
    _SL13A-repository STREAMS-REPOSITORY-ADAPTER@ ;

: _SL13A-adapter-work  ( -- work )
    _SL13A-repo-work STREAMS-REPOSITORY-ADAPTER-WORK@ ;

: _SL13A-root  ( -- root )
    _SL13A-repo-work STREAMS-REPOSITORY-AUTHORITY-ROOT@ ;

: _SL13A-sentinel!  ( address length -- )
    0xA5 FILL ;

: _SL13A-sentinel?  ( address length -- flag )
    0 ?DO
        DUP I + C@ 0xA5 <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _SL13A-output-sentinel!  ( output -- )
    OCHK-SOURCE-SIZE _SL13A-sentinel! ;

: _SL13A-output-sentinel?  ( output -- flag )
    OCHK-SOURCE-SIZE _SL13A-sentinel? ;

: _SL13A-recovered-nth  ( index -- attempt )
    OCHK-SOURCE-SIZE * _SL13A-recovered + ;

: _SL13A-runtime-init  ( -- )
    VFS-CUR _SL13A-old-vfs !
    VFS-RAM-OPS _SL13A-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _SL13A-binding VFS-BINDING-DESC-SIZE MOVE
    _SL13A-ops _SL13A-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW
    DUP 0= _SL13A-assert DROP _SL13A-arena !
    _SL13A-arena @ _SL13A-binding 0 VFS-NEW
    _SL13A-ior ! _SL13A-vfs !
    _SL13A-ior @ 0= _SL13A-assert
    _SL13A-vfs @ 0<> _SL13A-assert
    _SL13A-cache0-memory _SL13A-cache0 _SL13A-cache-init
    _SL13A-cache1-memory _SL13A-cache1 _SL13A-cache-init
    _SL13A-authority RID-SIZE 0x51 FILL
    _SL13A-source-a-rid RID-SIZE 0x61 FILL
    _SL13A-source-b-rid RID-SIZE 0x62 FILL
    _SL13A-source-c-rid RID-SIZE 0x63 FILL
    _SL13A-namespace-a SHA3-256-LEN 0x71 FILL
    _SL13A-namespace-b SHA3-256-LEN 0x72 FILL
    _SL13A-namespace-c SHA3-256-LEN 0x73 FILL
    _SL13A-key STREAMS-PI-KEY-MAX 0 FILL
    _SL13A-stack ;

: _SL13A-repository-init  ( -- )
    _SL13A-vfs @ _SL13A-cache0 _SL13A-cache1 _SL13A-guard
    ['] _SL13A-fault 0 _SL13A-repository
        STREAMS-REPOSITORY-INIT
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-repository STREAMS-REPOSITORY-VALID? _SL13A-assert
    _SL13A-record-buffer STREAMS-REPOSITORY-RECORD-BUFFER-MIN
    _SL13A-repository _SL13A-repo-work
        STREAMS-REPOSITORY-WORK-INIT
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-repo-work STREAMS-REPOSITORY-WORK-VALID? _SL13A-assert
    _SL13A-repository _SL13A-repo-work
        STREAMS-REPOSITORY-WORK-BOUND? _SL13A-assert
    _SL13A-stack ;

: _SL13A-staging-owner  ( context repository work -- status )
    2DROP DROP
    _SL13A-authority _SL13A-adapter _SL13A-adapter-work
        STREAMS-PA-FIRST-STAGE-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-adapter-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13A-assert
    STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY
        SWAP SAR.PROVENANCE !
    _SL13A-adapter _SL13A-adapter-work
        STREAMS-PA-FIRST-STAGE-COMMIT
        STREAMS-PA-S-OK _SL13A-status
    STREAMS-REPOSITORY-S-OK ;

: _SL13A-provision  ( -- )
    _SL13A-repository _SL13A-repo-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-ABSENT _SL13A-status
    _SL13A-repository _SL13A-repo-work
        STREAMS-REPOSITORY-STAGING-PREPARE
        STREAMS-REPOSITORY-S-OK _SL13A-status
    0 ['] _SL13A-staging-owner
        _SL13A-repository _SL13A-repo-work
        STREAMS-REPOSITORY-WITH-STAGING-OWNER
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-repository _SL13A-repo-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-authority _SL13A-repository _SL13A-repo-work
        STREAMS-REPOSITORY-PROVISION
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-repository STREAMS-REPOSITORY-PROVISIONED?
        _SL13A-assert
    _SL13A-root SAR.AUTHORITY-ID _SL13A-authority RID=
        _SL13A-assert
    _SL13A-stack ;

: _SL13A-work-init  ( -- )
    _SL13A-source-work STREAMS-SOURCE-AUTHORITY-WORK-INIT
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status
    _SL13A-acquisition-work STREAMS-ACQUISITION-WORK-INIT
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-source-work STREAMS-SOURCE-AUTHORITY-WORK-VALID?
        _SL13A-assert
    _SL13A-acquisition-work STREAMS-ACQUISITION-WORK-VALID?
        _SL13A-assert
    _SL13A-stack ;

: _SL13A-source-base  ( rid -- )
    _SL13A-build-rid !
    _SL13A-source STREAMS-SOURCE-INIT
    _SL13A-build-rid @ _SL13A-source STREAMS-SOURCE-ID!
        SSREG-S-OK _SL13A-status
    SSOURCE-KIND-SYNDICATION _SL13A-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _SL13A-source SSOURCE.FORMAT ! ;

: _SL13A-create-source-a  ( -- )
    _SL13A-source-a-rid _SL13A-source-base
    S" Acquisition source A"
        _SL13A-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13A-status
    S" https://example.test/a.json"
        _SL13A-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13A-status
    _SL13A-source _SL13A-repository _SL13A-repo-work
        _SL13A-source-work STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status ;

: _SL13A-create-source-b  ( -- )
    _SL13A-source-b-rid _SL13A-source-base
    S" Acquisition source B"
        _SL13A-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13A-status
    S" https://example.test/b.json"
        _SL13A-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13A-status
    _SL13A-source _SL13A-repository _SL13A-repo-work
        _SL13A-source-work STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status ;

: _SL13A-create-source-c  ( -- )
    _SL13A-source-c-rid _SL13A-source-base
    S" Acquisition source C"
        _SL13A-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13A-status
    S" https://example.test/c.json"
        _SL13A-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13A-status
    _SL13A-source _SL13A-repository _SL13A-repo-work
        _SL13A-source-work STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status ;

: _SL13A-create-sources  ( -- )
    \ Keep creation order opposite active-key RID order for A/B.  Recovery
    \ must enumerate the bounded ACTIVE-ATTEMPT family, not SOURCE-ORDER.
    _SL13A-create-source-b
    _SL13A-create-source-a
    _SL13A-create-source-c
    _SL13A-root SAR.SOURCE-COUNT @ 3 = _SL13A-assert
    _SL13A-stack ;

: _SL13A-begin-request!  ( rid revision namespace uri-a uri-u -- )
    _SL13A-request-uri-u !
    _SL13A-request-uri-a !
    _SL13A-request-namespace !
    _SL13A-request-revision !
    _SL13A-request-rid !
    _SL13A-begin-request
        STREAMS-ACQUISITION-BEGIN-REQUEST-INIT
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-request-rid @
        _SL13A-begin-request SABR.SOURCE-ID
        RID-COPY
    _SL13A-request-revision @
        _SL13A-begin-request SABR.SOURCE-REVISION !
    _SL13A-request-namespace @
        _SL13A-begin-request SABR.NAMESPACE
        RID-COPY
    OCHK-NATIVE-PROVIDER-ID
        _SL13A-begin-request SABR.PROVIDER-KIND !
    _SL13A-request-uri-a @
        _SL13A-begin-request SABR.REQUESTED-A !
    _SL13A-request-uri-u @
        _SL13A-begin-request SABR.REQUESTED-U !
    _SL13A-begin-request
        STREAMS-ACQUISITION-BEGIN-REQUEST-VALID?
        _SL13A-assert
    _SL13A-stack ;

: _SL13A-terminal-request!  ( attempt state outcome -- )
    _SL13A-terminal-outcome !
    _SL13A-terminal-state !
    _SL13A-terminal-attempt !
    _SL13A-terminal-request
        STREAMS-ACQUISITION-TERMINAL-REQUEST-INIT
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-terminal-request SATR.FACTS
        STREAMS-ACQUISITION-TERMINAL-FACTS-INIT
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-terminal-attempt @ OCS.SOURCE-ID
        _SL13A-terminal-request SATR.SOURCE-ID RID-COPY
    _SL13A-terminal-attempt @ OCS.SOURCE-REVISION @
        _SL13A-terminal-request SATR.SOURCE-REVISION !
    _SL13A-terminal-attempt @ OCS.ATTEMPT-ID
        _SL13A-terminal-request SATR.ATTEMPT-ID RID-COPY
    _SL13A-terminal-attempt @ OCS.REQUEST-SEAL
        _SL13A-terminal-request SATR.REQUEST-SEAL RID-COPY
    _SL13A-terminal-state @
        _SL13A-terminal-request SATR.FACTS SACQF.STATE !
    _SL13A-terminal-outcome @
        _SL13A-terminal-request SATR.FACTS SACQF.OUTCOME !
    _SL13A-terminal-attempt @ OCS.STARTED-MS @
        _SL13A-terminal-request SATR.FACTS SACQF.FINISHED-MS !
    _SL13A-terminal-request
        STREAMS-ACQUISITION-TERMINAL-REQUEST-VALID?
        _SL13A-assert
    _SL13A-stack ;

: _SL13A-history-key!  ( attempt -- )
    DUP OCS.SOURCE-ID
    OVER OCS.ATTEMPT-SEQUENCE @
    ROT OCS.ATTEMPT-ID
    _SL13A-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY
        STREAMS-PI-S-OK _SL13A-status ;

: _SL13A-check-owner  ( context repository work -- status )
    2DROP DROP
    _SL13A-check-attempt @ _SL13A-history-key!
    _SL13A-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        _SL13A-history-record SPREC-ATTEMPT-SIZE
        _SL13A-adapter _SL13A-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP SPREC-ATTEMPT-SIZE = _SL13A-assert
    DROP
    _SL13A-history-record SPREC-ATTEMPT-SIZE
        SPREC-ATTEMPT-VALID? _SL13A-assert
    _SL13A-history-record SPRA.STATE @
        _SL13A-check-state @ = _SL13A-assert
    _SL13A-history-record SPRA.ATTEMPT
        OCHK-SOURCE-SIZE
        _SL13A-check-attempt @ OCHK-SOURCE-SIZE
        COMPARE 0= _SL13A-assert

    _SL13A-check-attempt @ OCS.SOURCE-ID
        _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        _SL13A-active-record SPREC-ATTEMPT-SIZE
        _SL13A-adapter _SL13A-adapter-work STREAMS-PA-GET
    _SL13A-check-active @ IF
        DUP STREAMS-PA-S-OK = _SL13A-assert
        SWAP SPREC-ATTEMPT-SIZE = _SL13A-assert
        DROP
        _SL13A-active-record SPREC-ATTEMPT-SIZE
            SPREC-ATTEMPT-VALID? _SL13A-assert
        _SL13A-active-record SPRA.ATTEMPT
            OCHK-SOURCE-SIZE
            _SL13A-check-attempt @ OCHK-SOURCE-SIZE
            COMPARE 0= _SL13A-assert
    ELSE
        DUP STREAMS-PA-S-NOT-FOUND = _SL13A-assert
        SWAP 0= _SL13A-assert
        DROP
    THEN
    STREAMS-REPOSITORY-S-OK ;

: _SL13A-check-persisted  ( attempt state active? -- )
    _SL13A-check-active !
    _SL13A-check-state !
    _SL13A-check-attempt !
    0 ['] _SL13A-check-owner
        _SL13A-repository _SL13A-repo-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-stack ;

: _SL13A-check-counters  ( sequence attempts active -- )
    >R >R >R
    _SL13A-root
    DUP SAR.ACQUISITION-SEQUENCE @ R> = _SL13A-assert
    DUP SAR.ATTEMPT-COUNT @ R> = _SL13A-assert
    SAR.ACTIVE-COUNT @ R> = _SL13A-assert
    _SL13A-stack ;

: _SL13A-policy-contracts  ( -- )
    _SL13A-source-b-rid 1 0
        _SL13A-repository _SL13A-repo-work _SL13A-source-work
        STREAMS-SOURCE-AUTHORITY-ENABLE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status

    _SL13A-source-b-rid 1 _SL13A-namespace-b
        S" https://example.test/b.json" _SL13A-begin-request!
    _SL13A-scratch-out _SL13A-output-sentinel!
    _SL13A-begin-request _SL13A-scratch-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-STALE _SL13A-status
    _SL13A-scratch-out _SL13A-output-sentinel? _SL13A-assert

    _SL13A-source-b-rid 2 _SL13A-namespace-b
        S" https://example.test/b.json" _SL13A-begin-request!
    _SL13A-begin-request _SL13A-scratch-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-DISABLED _SL13A-status
    _SL13A-scratch-out _SL13A-output-sentinel? _SL13A-assert

    _SL13A-source-b-rid 2 -1
        _SL13A-repository _SL13A-repo-work _SL13A-source-work
        STREAMS-SOURCE-AUTHORITY-ENABLE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status
    0 0 0 _SL13A-check-counters
    _SL13A-stack ;

: _SL13A-failed-contract  ( -- )
    _SL13A-source-a-rid 1 _SL13A-namespace-a
        S" https://example.test/a.json" _SL13A-begin-request!
    _SL13A-begin-request _SL13A-accepted-a
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-accepted-a OCS.STATE @
        OCHK-ATTEMPT-ACCEPTED = _SL13A-assert
    _SL13A-accepted-a OCS.ATTEMPT-SEQUENCE @ 1 =
        _SL13A-assert
    _SL13A-accepted-a OCS.SOURCE-REVISION @ 1 =
        _SL13A-assert
    _SL13A-accepted-a OCS.SOURCE-ID
        _SL13A-source-a-rid RID= _SL13A-assert
    _SL13A-accepted-a OCS.NAMESPACE
        _SL13A-namespace-a RID= _SL13A-assert
    _SL13A-accepted-a OCS.PROVIDER-KIND @
        OCHK-NATIVE-PROVIDER-ID = _SL13A-assert
    1 1 1 _SL13A-check-counters
    _SL13A-accepted-a OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted

    _SL13A-scratch-out _SL13A-output-sentinel!
    _SL13A-begin-request _SL13A-scratch-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-BUSY _SL13A-status
    _SL13A-scratch-out _SL13A-output-sentinel? _SL13A-assert
    1 1 1 _SL13A-check-counters

    _SL13A-accepted-a OCHK-ATTEMPT-FAILED OCHK-O-TRANSPORT
        _SL13A-terminal-request!
    _SL13A-terminal-request SATR.ATTEMPT-ID
    DUP C@ 1 XOR SWAP C!
    _SL13A-scratch-out _SL13A-output-sentinel!
    _SL13A-terminal-request _SL13A-scratch-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-TERMINAL
        STREAMS-ACQUISITION-S-MISMATCH _SL13A-status
    _SL13A-scratch-out _SL13A-output-sentinel? _SL13A-assert
    _SL13A-accepted-a OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted

    _SL13A-accepted-a OCHK-ATTEMPT-FAILED OCHK-O-TRANSPORT
        _SL13A-terminal-request!
    OCHK-O-OK
        _SL13A-terminal-request SATR.FACTS SACQF.OUTCOME !
    _SL13A-terminal-request
        STREAMS-ACQUISITION-TERMINAL-REQUEST-VALID?
        0= _SL13A-assert
    _SL13A-terminal-request _SL13A-scratch-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-TERMINAL
        STREAMS-ACQUISITION-S-INVALID _SL13A-status
    _SL13A-scratch-out _SL13A-output-sentinel? _SL13A-assert
    _SL13A-accepted-a OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted

    _SL13A-accepted-a OCHK-ATTEMPT-FAILED OCHK-O-TRANSPORT
        _SL13A-terminal-request!
    _SL13A-terminal-request _SL13A-terminal-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-TERMINAL
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-terminal-out OCS.STATE @
        OCHK-ATTEMPT-FAILED = _SL13A-assert
    _SL13A-terminal-out OCS.OUTCOME @
        OCHK-O-TRANSPORT = _SL13A-assert
    _SL13A-terminal-out OCHK-ATTEMPT-FAILED 0
        _SL13A-check-persisted
    1 1 0 _SL13A-check-counters
    _SL13A-stack ;

: _SL13A-replace-a  ( -- )
    _SL13A-source-a-rid _SL13A-source-out
        _SL13A-repository _SL13A-repo-work _SL13A-source-work
        STREAMS-SOURCE-AUTHORITY-READ
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status
    _SL13A-source-out SSOURCE.REVISION @ 1 = _SL13A-assert
    S" Acquisition source A revision two"
        _SL13A-source-out STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13A-status
    _SL13A-source-out 1
        _SL13A-repository _SL13A-repo-work _SL13A-source-work
        STREAMS-SOURCE-AUTHORITY-REPLACE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13A-status
    _SL13A-stack ;

: _SL13A-cancelled-contract  ( -- )
    _SL13A-source-a-rid 1 _SL13A-namespace-a
        S" https://example.test/a.json" _SL13A-begin-request!
    _SL13A-begin-request _SL13A-accepted-a
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-accepted-a OCS.ATTEMPT-SEQUENCE @ 2 =
        _SL13A-assert
    _SL13A-replace-a
    _SL13A-accepted-a OCHK-ATTEMPT-CANCELLED OCHK-O-CANCELLED
        _SL13A-terminal-request!
    _SL13A-terminal-request _SL13A-terminal-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-TERMINAL
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-terminal-out OCS.SOURCE-REVISION @ 1 =
        _SL13A-assert
    _SL13A-terminal-out OCS.STATE @
        OCHK-ATTEMPT-CANCELLED = _SL13A-assert
    _SL13A-terminal-out OCS.OUTCOME @
        OCHK-O-CANCELLED = _SL13A-assert
    _SL13A-terminal-out OCHK-ATTEMPT-CANCELLED 0
        _SL13A-check-persisted
    2 2 0 _SL13A-check-counters
    _SL13A-stack ;

: _SL13A-indeterminate-contract  ( -- )
    _SL13A-source-a-rid 2 _SL13A-namespace-a
        S" https://example.test/a.json" _SL13A-begin-request!
    _SL13A-begin-request _SL13A-accepted-a
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-accepted-a OCS.ATTEMPT-SEQUENCE @ 3 =
        _SL13A-assert
    _SL13A-accepted-a
        OCHK-ATTEMPT-INDETERMINATE OCHK-O-INDETERMINATE
        _SL13A-terminal-request!
    _SL13A-terminal-request _SL13A-terminal-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-TERMINAL
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-terminal-out OCS.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13A-assert
    _SL13A-terminal-out OCS.OUTCOME @
        OCHK-O-INDETERMINATE = _SL13A-assert
    _SL13A-terminal-out OCHK-ATTEMPT-INDETERMINATE 0
        _SL13A-check-persisted
    3 3 0 _SL13A-check-counters
    _SL13A-stack ;

: _SL13A-terminal-contracts  ( -- )
    _SL13A-failed-contract
    _SL13A-cancelled-contract
    _SL13A-indeterminate-contract
    _SL13A-stack ;

: _SL13A-cold-reopen  ( -- )
    _SL13A-repository _SL13A-repo-work STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-cache0-memory _SL13A-cache0 _SL13A-cache-init
    _SL13A-cache1-memory _SL13A-cache1 _SL13A-cache-init
    _SL13A-repository-init
    _SL13A-repository _SL13A-repo-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-OK _SL13A-status
    _SL13A-root SAR.AUTHORITY-ID _SL13A-authority RID=
        _SL13A-assert
    _SL13A-work-init
    _SL13A-stack ;

: _SL13A-recovery-all-contract  ( -- )
    _SL13A-source-a-rid 2 _SL13A-namespace-a
        S" https://example.test/a.json" _SL13A-begin-request!
    _SL13A-begin-request _SL13A-accepted-a
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-source-b-rid 3 _SL13A-namespace-b
        S" https://example.test/b.json" _SL13A-begin-request!
    _SL13A-begin-request _SL13A-accepted-b
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-accepted-a OCS.ATTEMPT-SEQUENCE @ 4 =
        _SL13A-assert
    _SL13A-accepted-b OCS.ATTEMPT-SEQUENCE @ 5 =
        _SL13A-assert
    5 5 2 _SL13A-check-counters
    _SL13A-accepted-a OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted
    _SL13A-accepted-b OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted
    _SL13A-root
    DUP SAR.ACQUISITION-SEQUENCE @ _SL13A-expected-sequence !
    SAR.ATTEMPT-COUNT @ _SL13A-expected-attempt-count !

    _SL13A-cold-reopen
    _SL13A-accepted-a OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted
    _SL13A-accepted-b OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted
    _SL13A-recovered OCHK-SOURCE-SIZE 2 * _SL13A-sentinel!
    _SL13A-recovered 1
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-RECOVER-ALL
    DUP STREAMS-ACQUISITION-S-CAPACITY = _SL13A-assert
    SWAP 0= _SL13A-assert
    DROP
    _SL13A-recovered OCHK-SOURCE-SIZE 2 *
        _SL13A-sentinel? _SL13A-assert
    5 5 2 _SL13A-check-counters

    _SL13A-recovered 2
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-RECOVER-ALL
    DUP STREAMS-ACQUISITION-S-OK = _SL13A-assert
    SWAP 2 = _SL13A-assert
    DROP
    0 _SL13A-recovered-nth OCS.SOURCE-ID
        _SL13A-source-a-rid RID= _SL13A-assert
    1 _SL13A-recovered-nth OCS.SOURCE-ID
        _SL13A-source-b-rid RID= _SL13A-assert
    0 _SL13A-recovered-nth OCS.ATTEMPT-SEQUENCE @ 4 =
        _SL13A-assert
    1 _SL13A-recovered-nth OCS.ATTEMPT-SEQUENCE @ 5 =
        _SL13A-assert
    0 _SL13A-recovered-nth OCS.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13A-assert
    1 _SL13A-recovered-nth OCS.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13A-assert
    0 _SL13A-recovered-nth OCHK-ATTEMPT-INDETERMINATE 0
        _SL13A-check-persisted
    1 _SL13A-recovered-nth OCHK-ATTEMPT-INDETERMINATE 0
        _SL13A-check-persisted
    _SL13A-expected-sequence @
        _SL13A-expected-attempt-count @ 0 _SL13A-check-counters
    _SL13A-stack ;

: _SL13A-recovery-next-contract  ( -- )
    _SL13A-source-c-rid 1 _SL13A-namespace-c
        S" https://example.test/c.json" _SL13A-begin-request!
    _SL13A-begin-request _SL13A-accepted-c
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-root
    DUP SAR.ACQUISITION-SEQUENCE @ _SL13A-expected-sequence !
    SAR.ATTEMPT-COUNT @ _SL13A-expected-attempt-count !
    _SL13A-accepted-c OCHK-ATTEMPT-ACCEPTED -1
        _SL13A-check-persisted

    _SL13A-cold-reopen
    _SL13A-next-out _SL13A-output-sentinel!
    _SL13A-next-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-RECOVER-NEXT
        STREAMS-ACQUISITION-S-OK _SL13A-status
    _SL13A-next-out OCS.SOURCE-ID
        _SL13A-source-c-rid RID= _SL13A-assert
    _SL13A-next-out OCS.ATTEMPT-SEQUENCE @
        _SL13A-expected-sequence @ = _SL13A-assert
    _SL13A-next-out OCS.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13A-assert
    _SL13A-next-out OCHK-ATTEMPT-INDETERMINATE 0
        _SL13A-check-persisted
    _SL13A-expected-sequence @
        _SL13A-expected-attempt-count @ 0 _SL13A-check-counters

    _SL13A-scratch-out _SL13A-output-sentinel!
    _SL13A-scratch-out
        _SL13A-repository _SL13A-repo-work _SL13A-acquisition-work
        STREAMS-ACQUISITION-RECOVER-NEXT
        STREAMS-ACQUISITION-S-NOT-FOUND _SL13A-status
    _SL13A-scratch-out _SL13A-output-sentinel? _SL13A-assert
    _SL13A-stack ;

: _SL13A-finish  ( -- )
    _SL13A-repository _SL13A-repo-work STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13A-status
    0 _SL13A-vfs @ VFS-UNMOUNT 0= _SL13A-assert
    _SL13A-vfs @ VFS-DESTROY
    _SL13A-old-vfs @ VFS-USE
    _SL13A-arena @ ARENA-DESTROY
    _SL13A-stack ;

: _SL13A-RUN  ( -- )
    0 _SL13A-checks ! 0 _SL13A-fails !
    DEPTH _SL13A-depth !
    _SL13A-runtime-init
    _SL13A-repository-init
    _SL13A-provision
    _SL13A-work-init
    _SL13A-create-sources
    _SL13A-policy-contracts
    _SL13A-terminal-contracts
    _SL13A-recovery-all-contract
    _SL13A-recovery-next-contract
    _SL13A-finish
    _SL13A-fails @ IF
        ." STREAMS L13 ACQUISITION FAIL "
            _SL13A-fails @ . ." / " _SL13A-checks @ . CR
    ELSE
        ." STREAMS L13 ACQUISITION PASS "
            _SL13A-checks @ . CR
    THEN ;
