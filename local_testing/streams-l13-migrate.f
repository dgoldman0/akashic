\ Focused, single-process RAM-VFS contracts for the L13 cold migration.
\
\ Each matrix row receives a fresh VFS and repository.  The full-import row
\ independently reads every imported semantic kind and the content PBLOB
\ through the repository owner gate.  No fixture operation writes legacy
\ state after migration begins.

PROVIDED akashic-streams-l13-migration-contracts

VARIABLE _SL13M-checks
VARIABLE _SL13M-fails
VARIABLE _SL13M-depth
VARIABLE _SL13M-old-vfs
VARIABLE _SL13M-vfs
VARIABLE _SL13M-arena
VARIABLE _SL13M-ior
VARIABLE _SL13M-fd
VARIABLE _SL13M-record-u
VARIABLE _SL13M-generation
VARIABLE _SL13M-evidence-status
VARIABLE _SL13M-get-u
VARIABLE _SL13M-get-status
VARIABLE _SL13M-observation
VARIABLE _SL13M-blob-expected-a
VARIABLE _SL13M-blob-expected-u
VARIABLE _SL13M-blob-offset
VARIABLE _SL13M-blob-errors
VARIABLE _SL13M-sink-a
VARIABLE _SL13M-sink-u
VARIABLE _SL13M-sink-offset

CREATE _SL13M-ops VFS-OPS-SIZE ALLOT
CREATE _SL13M-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _SL13M-cache0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _SL13M-cache1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13M-cache0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13M-cache1-memory
GUARD _SL13M-guard

CREATE _SL13M-authority RID-SIZE ALLOT
CREATE _SL13M-source-rid RID-SIZE ALLOT
CREATE _SL13M-namespace SHA3-256-LEN ALLOT
CREATE _SL13M-source-digest SHA3-256-LEN ALLOT
CREATE _SL13M-observation-digest SHA3-256-LEN ALLOT
CREATE _SL13M-key STREAMS-PI-KEY-MAX ALLOT

STREAMS-SOURCE-STORE-SIZE XBUF _SL13M-source-store
STREAMS-OBSERVATION-STORE-SIZE XBUF _SL13M-observation-store
STREAMS-SOURCE-REGISTRY-SIZE XBUF _SL13M-registry
STREAMS-OBSERVATION-CHECKPOINT-SIZE XBUF _SL13M-checkpoint
STREAMS-OBSERVATION-CHECKPOINT-SIZE XBUF _SL13M-checkpoint-work
STREAMS-SOURCE-SIZE XBUF _SL13M-source
OCHK-CANDIDATE-SIZE XBUF _SL13M-candidate

STREAMS-REPOSITORY-SIZE XBUF _SL13M-repository
STREAMS-REPOSITORY-WORK-SIZE XBUF _SL13M-repository-work
STREAMS-REPOSITORY-RECORD-BUFFER-MIN XBUF _SL13M-record-buffer
STREAMS-MIGRATION-WORK-SIZE XBUF _SL13M-migration-work

STREAMS-PERSISTENCE-RECORD-MAX XBUF _SL13M-expected-record
STREAMS-PERSISTENCE-RECORD-MAX XBUF _SL13M-readback
STREAMS-SOURCE-STORE-RECORD-MAX XBUF _SL13M-source-raw

: _SL13M-assert  ( flag -- )
    1 _SL13M-checks +!
    0= IF
        1 _SL13M-fails +!
        ." STREAMS L13 MIGRATION ASSERT " _SL13M-checks @ . CR
    THEN ;

: _SL13M-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 MIGRATION STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13M-assert ;

: _SL13M-stack  ( -- )
    DEPTH DUP _SL13M-depth @ <> IF
        ." STREAMS L13 MIGRATION STACK "
        _SL13M-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13M-depth @ = _SL13M-assert ;

: _SL13M-zero?  ( a u -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SL13M-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _SL13M-status ;

: _SL13M-fault  ( point ordinal context -- status )
    2DROP DROP PERSIST-S-OK ;

: _SL13M-adapter  ( -- adapter )
    _SL13M-repository STREAMS-REPOSITORY-ADAPTER@ ;

: _SL13M-adapter-work  ( -- work )
    _SL13M-repository-work STREAMS-REPOSITORY-ADAPTER-WORK@ ;

: _SL13M-root  ( -- root|0 )
    _SL13M-repository-work STREAMS-REPOSITORY-AUTHORITY-ROOT@ ;

: _SL13M-case-setup  ( -- )
    VFS-CUR _SL13M-old-vfs !
    VFS-RAM-OPS _SL13M-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _SL13M-binding VFS-BINDING-DESC-SIZE MOVE
    _SL13M-ops _SL13M-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW
    DUP 0= _SL13M-assert DROP _SL13M-arena !
    _SL13M-arena @ _SL13M-binding 0 VFS-NEW
    _SL13M-ior ! _SL13M-vfs !
    _SL13M-ior @ 0= _SL13M-assert
    _SL13M-vfs @ 0<> _SL13M-assert
    _SL13M-vfs @ VFS-USE

    _SL13M-cache0-memory _SL13M-cache0 _SL13M-cache-init
    _SL13M-cache1-memory _SL13M-cache1 _SL13M-cache-init
    _SL13M-authority RID-SIZE 0xA1 FILL
    _SL13M-source-rid RID-SIZE 0xB2 FILL
    _SL13M-namespace SHA3-256-LEN 0xC3 FILL
    _SL13M-source-digest SHA3-256-LEN 0 FILL
    _SL13M-observation-digest SHA3-256-LEN 0 FILL
    _SL13M-key STREAMS-PI-KEY-MAX 0 FILL

    _SL13M-vfs @ _SL13M-source-store STREAMS-SOURCE-STORE-INIT
        SSSTORE-S-OK _SL13M-status
    _SL13M-vfs @ _SL13M-observation-store
        STREAMS-OBSERVATION-STORE-INIT
        OSTORE-S-OK _SL13M-status

    _SL13M-vfs @ _SL13M-cache0 _SL13M-cache1 _SL13M-guard
    ['] _SL13M-fault 0 _SL13M-repository
        STREAMS-REPOSITORY-INIT
        STREAMS-REPOSITORY-S-OK _SL13M-status
    _SL13M-record-buffer STREAMS-REPOSITORY-RECORD-BUFFER-MIN
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-WORK-INIT
        STREAMS-REPOSITORY-S-OK _SL13M-status
    _SL13M-migration-work STREAMS-MIGRATION-WORK-INIT
        STREAMS-MIGRATION-S-OK _SL13M-status

    _SL13M-registry STREAMS-SOURCE-REGISTRY-INIT
    _SL13M-checkpoint OCHK-INIT
    _SL13M-candidate OCHK-CANDIDATE-INIT
    0 _SL13M-blob-offset !
    0 _SL13M-blob-errors !
    _SL13M-stack ;

: _SL13M-case-finish  ( -- )
    _SL13M-repository STREAMS-REPOSITORY-VALID? IF
        _SL13M-repository _SL13M-repository-work
            STREAMS-REPOSITORY-FINI
            STREAMS-REPOSITORY-S-OK _SL13M-status
    THEN
    _SL13M-source-store STREAMS-SOURCE-STORE-VALID? IF
        _SL13M-source-store STREAMS-SOURCE-STORE-FINI DROP
    THEN
    _SL13M-observation-store STREAMS-OBSERVATION-STORE-VALID? IF
        _SL13M-observation-store STREAMS-OBSERVATION-STORE-FINI DROP
    THEN
    0 _SL13M-vfs @ VFS-UNMOUNT 0= _SL13M-assert
    _SL13M-vfs @ VFS-DESTROY
    _SL13M-old-vfs @ VFS-USE
    _SL13M-arena @ ARENA-DESTROY
    0 _SL13M-vfs !
    0 _SL13M-arena !
    _SL13M-stack ;

\ ---------------------------------------------------------------------
\ Exact legacy setup
\ ---------------------------------------------------------------------

: _SL13M-source-legacy  ( -- )
    _SL13M-source STREAMS-SOURCE-INIT
    _SL13M-source-rid _SL13M-source STREAMS-SOURCE-ID!
        SSREG-S-OK _SL13M-status
    SSOURCE-KIND-SYNDICATION _SL13M-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _SL13M-source SSOURCE.FORMAT !
    S" Migrated configured feed"
        _SL13M-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13M-status
    S" https://example.test/migrated.json"
        _SL13M-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13M-status
    _SL13M-source _SL13M-registry STREAMS-SOURCE-CREATE
        SSREG-S-OK _SL13M-status
    _SL13M-registry SSREG.GENERATION @ 1 = _SL13M-assert
    _SL13M-registry 0 _SL13M-source-store
        STREAMS-SOURCE-STORE-SAVE
        SSSTORE-S-OK _SL13M-status ;

: _SL13M-observation-candidate  ( -- )
    _SL13M-candidate OCHK-CANDIDATE-INIT
    \ Observation candidates retain the syndication projection format
    \ domain (JSON Feed = 1), not the configured-source format domain.
    1 _SL13M-candidate OCC.FORMAT !
    OCHK-NATIVE-PROVIDER-ID _SL13M-candidate OCC.NATIVE-KIND !
    S" migrated-native-id"
        _SL13M-candidate OCC.NATIVE-U !
        _SL13M-candidate OCC.NATIVE-A !
    S" Migrated observation"
        _SL13M-candidate OCC.TITLE-U !
        _SL13M-candidate OCC.TITLE-A !
    S" https://example.test/items/1"
        _SL13M-candidate OCC.URL-U !
        _SL13M-candidate OCC.URL-A !
    S" Exact migrated summary"
        _SL13M-candidate OCC.SUMMARY-U !
        _SL13M-candidate OCC.SUMMARY-A !
    S" Exact migrated body"
        _SL13M-candidate OCC.CONTENT-U !
        _SL13M-candidate OCC.CONTENT-A !
    S" 2026-07-24T12:00:00Z"
        _SL13M-candidate OCC.PUBLISHED-U !
        _SL13M-candidate OCC.PUBLISHED-A !
    S" 2026-07-24T12:01:00Z"
        _SL13M-candidate OCC.MODIFIED-U !
        _SL13M-candidate OCC.MODIFIED-A !
    _SL13M-candidate SPREC-CANDIDATE-VALID? _SL13M-assert ;

: _SL13M-observation-legacy  ( -- )
    _SL13M-checkpoint OCHK-INIT
    _SL13M-observation-candidate

    _SL13M-source-rid 1 _SL13M-namespace 1
    S" https://example.test/migrated.json"
        _SL13M-checkpoint OCHK-BEGIN
        OCHK-S-OK _SL13M-status
    _SL13M-checkpoint 0 _SL13M-observation-store
        STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-OK _SL13M-status

    _SL13M-source-rid 1
    S" https://cdn.example.test/migrated.json"
    73 200 _SL13M-candidate 1 _SL13M-checkpoint OCHK-APPLY
        OCHK-S-OK _SL13M-status
    _SL13M-checkpoint 1 _SL13M-observation-store
        STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-OK _SL13M-status

    _SL13M-source-rid 1 _SL13M-namespace 1
    S" https://example.test/migrated.json"
        _SL13M-checkpoint OCHK-BEGIN
        OCHK-S-OK _SL13M-status
    _SL13M-checkpoint 2 _SL13M-observation-store
        STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-OK _SL13M-status

    _SL13M-checkpoint OCHK.GENERATION @ 3 = _SL13M-assert
    _SL13M-checkpoint OCHK.SEQUENCE @ 2 = _SL13M-assert
    _SL13M-checkpoint OCHK.OBSERVATION-COUNT @ 1 = _SL13M-assert
    _SL13M-checkpoint OCHK.KEY-COUNT @ 1 = _SL13M-assert
    _SL13M-source-rid _SL13M-checkpoint OCHK-SOURCE-FIND
    DUP 0<> _SL13M-assert
    OCS.STATE @ OCHK-ATTEMPT-ACCEPTED = _SL13M-assert ;

: _SL13M-capture-evidence  ( -- )
    _SL13M-registry STREAMS-SOURCE-REGISTRY-SIZE
    _SL13M-source-digest _SL13M-source-store
        STREAMS-SOURCE-STORE-LOAD-EVIDENCE
    _SL13M-evidence-status !
    _SL13M-generation !
    _SL13M-record-u !
    _SL13M-evidence-status @ SSSTORE-S-OK _SL13M-status
    _SL13M-record-u @ STREAMS-SOURCE-STORE-RECORD-MAX =
        _SL13M-assert
    _SL13M-generation @ 1 = _SL13M-assert

    _SL13M-checkpoint STREAMS-OBSERVATION-CHECKPOINT-SIZE
    _SL13M-observation-digest _SL13M-observation-store
        STREAMS-OBSERVATION-STORE-LOAD-EVIDENCE
    _SL13M-evidence-status !
    _SL13M-generation !
    _SL13M-record-u !
    _SL13M-evidence-status @ OSTORE-S-OK _SL13M-status
    _SL13M-record-u @ STREAMS-OBSERVATION-STORE-RECORD-MAX =
        _SL13M-assert
    _SL13M-generation @ 3 = _SL13M-assert ;

: _SL13M-migrate  ( -- status )
    _SL13M-authority
    _SL13M-source-store _SL13M-observation-store
    _SL13M-repository _SL13M-repository-work
    _SL13M-migration-work STREAMS-MIGRATION-RUN ;

\ ---------------------------------------------------------------------
\ Independent published readback for the both-valid row
\ ---------------------------------------------------------------------

: _SL13M-get!  ( key-u -- )
    _SL13M-key SWAP
    _SL13M-readback STREAMS-PERSISTENCE-RECORD-MAX
    _SL13M-adapter _SL13M-adapter-work STREAMS-PA-GET
    _SL13M-get-status !
    _SL13M-get-u ! ;

: _SL13M-verify-source  ( -- )
    0 _SL13M-registry STREAMS-SOURCE-NTH
    DUP 0<> _SL13M-assert
    1 _SL13M-expected-record SPREC-SOURCE-CONSTRUCT
        SPREC-S-OK _SL13M-status
    1 _SL13M-expected-record SPRS.OBSERVATION-COUNT !
    _SL13M-expected-record SPREC-SOURCE-SEAL!
        SPREC-S-OK _SL13M-status
    _SL13M-expected-record SPRS.OBSERVATION-COUNT @ 1 =
        _SL13M-assert
    _SL13M-expected-record SPRS.ID _SL13M-key
        STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13M-status
    STREAMS-PI-SOURCE-RID-KEY-SIZE _SL13M-get!
    _SL13M-get-status @ STREAMS-PA-S-OK _SL13M-status
    _SL13M-get-u @ SPREC-SOURCE-SIZE = _SL13M-assert
    _SL13M-readback SPRS.OBSERVATION-COUNT @ 1 =
        _SL13M-assert
    _SL13M-expected-record SPREC-SOURCE-SIZE
    _SL13M-readback SPREC-SOURCE-SIZE COMPARE 0= _SL13M-assert ;

: _SL13M-verify-attempt  ( -- )
    _SL13M-checkpoint _SL13M-checkpoint-work
        STREAMS-OBSERVATION-CHECKPOINT-SIZE MOVE
    _SL13M-source-rid _SL13M-checkpoint-work OCHK-SOURCE-FIND
    DUP 0<> _SL13M-assert
    DUP _SL13M-expected-record SPREC-ATTEMPT-CONSTRUCT
        SPREC-S-OK _SL13M-status
    DROP
    _SL13M-expected-record SPRA.STATE @
        OCHK-ATTEMPT-ACCEPTED = _SL13M-assert
    _SL13M-expected-record SPRA.SOURCE-ID
    _SL13M-expected-record SPRA.ATTEMPT-SEQUENCE @
    _SL13M-expected-record SPRA.ATTEMPT-ID
    _SL13M-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY
        STREAMS-PI-S-OK _SL13M-status
    STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE _SL13M-get!
    _SL13M-get-status @ STREAMS-PA-S-OK _SL13M-status
    _SL13M-get-u @ SPREC-ATTEMPT-SIZE = _SL13M-assert
    \ Recovery changes only these terminal fields.  FINISHED-MS is sampled
    \ during migration, so admit that published value before independently
    \ resealing the preserved accepted head for an exact byte comparison.
    OCHK-ATTEMPT-INDETERMINATE
        _SL13M-expected-record SPRA.STATE !
    OCHK-O-INDETERMINATE
        _SL13M-expected-record SPRA.OUTCOME !
    _SL13M-readback SPRA.FINISHED-MS @
        _SL13M-expected-record SPRA.FINISHED-MS !
    _SL13M-expected-record SPREC-ATTEMPT-SEAL!
        SPREC-S-OK _SL13M-status
    _SL13M-expected-record SPREC-ATTEMPT-SIZE
    _SL13M-readback SPREC-ATTEMPT-SIZE COMPARE 0= _SL13M-assert
    _SL13M-readback SPRA.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13M-assert
    _SL13M-readback SPRA.OUTCOME @
        OCHK-O-INDETERMINATE = _SL13M-assert ;

: _SL13M-candidate-from-key  ( key -- )
    _SL13M-candidate OCHK-CANDIDATE-INIT
    DUP OCK.FORMAT @ _SL13M-candidate OCC.FORMAT !
    DUP OCK.NATIVE-KIND @ _SL13M-candidate OCC.NATIVE-KIND !
    DUP _SL13M-checkpoint OCHK-KEY-NATIVE$
        _SL13M-candidate OCC.NATIVE-U !
        _SL13M-candidate OCC.NATIVE-A !
    DROP
    _SL13M-candidate SPREC-CANDIDATE-VALID? _SL13M-assert ;

: _SL13M-verify-native  ( -- )
    0 _SL13M-checkpoint OCHK-KEY-NTH
    DUP 0<> _SL13M-assert
    _SL13M-expected-record SPREC-NATIVE-INIT
        SPREC-S-OK _SL13M-status
    DUP OCK.SOURCE-ID
        _SL13M-expected-record SPRH.SOURCE-ID RID-COPY
    DUP OCK.NAMESPACE
        _SL13M-expected-record SPRH.NAMESPACE SHA3-256-LEN MOVE
    DUP OCK.LATEST-REVISION @
        _SL13M-expected-record SPRH.LATEST-REVISION !
    DUP OCK.LAST-SEEN-SEQUENCE @
        _SL13M-expected-record SPRH.LAST-SEEN-SEQUENCE !
    1 _SL13M-expected-record SPRH.COLLISION-ORDINAL !
    DUP _SL13M-candidate-from-key
    _SL13M-candidate _SL13M-expected-record
        SPREC-NATIVE-CANDIDATE!
        SPREC-S-OK _SL13M-status
    DROP
    _SL13M-expected-record SPREC-NATIVE-HEAD-SIZE
        SPREC-NATIVE-VALID? _SL13M-assert

    _SL13M-expected-record SPRH.SOURCE-ID
    _SL13M-expected-record SPRH.NAMESPACE
    _SL13M-expected-record SPRH.OBSERVATION-FORMAT @
    _SL13M-expected-record SPRH.NATIVE-KIND @
    _SL13M-expected-record SPRH.NATIVE-DIGEST
    _SL13M-expected-record SPRH.COLLISION-ORDINAL @
    _SL13M-key STREAMS-PI-NATIVE-HEAD-KEY
        STREAMS-PI-S-OK _SL13M-status
    STREAMS-PI-NATIVE-HEAD-KEY-SIZE _SL13M-get!
    _SL13M-get-status @ STREAMS-PA-S-OK _SL13M-status
    _SL13M-get-u @ SPREC-NATIVE-HEAD-SIZE = _SL13M-assert
    _SL13M-expected-record SPREC-NATIVE-HEAD-SIZE
    _SL13M-readback SPREC-NATIVE-HEAD-SIZE
        COMPARE 0= _SL13M-assert ;

: _SL13M-blob-sink
  ( logical-offset source-a offered-u context -- status )
    DROP
    _SL13M-sink-u !
    _SL13M-sink-a !
    _SL13M-sink-offset !
    _SL13M-sink-offset @ _SL13M-blob-offset @ <> IF
        1 _SL13M-blob-errors +!
    THEN
    _SL13M-sink-offset @ 0<
    _SL13M-sink-u @ 0< OR IF
        1 _SL13M-blob-errors +!
        PERSIST-S-OK EXIT
    THEN
    _SL13M-sink-offset @ _SL13M-sink-u @ +
        _SL13M-blob-expected-u @ > IF
        1 _SL13M-blob-errors +!
        PERSIST-S-OK EXIT
    THEN
    _SL13M-blob-expected-a @ _SL13M-sink-offset @ +
        _SL13M-sink-u @
    _SL13M-sink-a @ _SL13M-sink-u @
        COMPARE IF 1 _SL13M-blob-errors +! THEN
    _SL13M-sink-u @ _SL13M-blob-offset +!
    PERSIST-S-OK ;

: _SL13M-verify-observation  ( -- )
    0 _SL13M-checkpoint OCHK-OBSERVATION-NTH
    DUP _SL13M-observation ! 0<> _SL13M-assert
    _SL13M-observation @ OCO.ID
    _SL13M-observation @ OCO.REVISION @
    _SL13M-key STREAMS-PI-OBSERVATION-REVISION-KEY
        STREAMS-PI-S-OK _SL13M-status
    STREAMS-PI-OBSERVATION-REVISION-KEY-SIZE _SL13M-get!
    _SL13M-get-status @ STREAMS-PA-S-OK _SL13M-status
    _SL13M-get-u @ SPREC-OBSERVATION-SIZE = _SL13M-assert
    _SL13M-readback SPREC-OBSERVATION-SIZE
        SPREC-OBSERVATION-VALID? _SL13M-assert
    _SL13M-observation @ OCO.ID
        _SL13M-readback SPRO.OBSERVATION-ID RID= _SL13M-assert
    _SL13M-observation @ OCO.SOURCE-ID
        _SL13M-readback SPRO.SOURCE-ID RID= _SL13M-assert
    _SL13M-observation @ OCO.NAMESPACE SHA3-256-LEN
        _SL13M-readback SPRO.NAMESPACE SHA3-256-LEN
        COMPARE 0= _SL13M-assert
    _SL13M-observation @ OCO.ATTEMPT-ID
        _SL13M-readback SPRO.ATTEMPT-ID RID= _SL13M-assert
    _SL13M-observation @ OCO.SEMANTIC-DIGEST SHA3-256-LEN
        _SL13M-readback SPRO.SEMANTIC-DIGEST SHA3-256-LEN
        COMPARE 0= _SL13M-assert
    _SL13M-observation @ OCO.SEQUENCE @
        _SL13M-readback SPRO.ACQUISITION-SEQUENCE @ =
        _SL13M-assert
    _SL13M-observation @ OCO.REVISION @
        _SL13M-readback SPRO.REVISION @ = _SL13M-assert
    _SL13M-observation @ OCO.FORMAT @
        _SL13M-readback SPRO.OBSERVATION-FORMAT @ =
        _SL13M-assert

    _SL13M-observation @ _SL13M-checkpoint OCHK-OBSERVATION-TITLE$
        _SL13M-readback SPRO-TITLE$ STR-STR= _SL13M-assert
    _SL13M-observation @ _SL13M-checkpoint OCHK-OBSERVATION-URL$
        _SL13M-readback SPRO-URL$ STR-STR= _SL13M-assert
    _SL13M-observation @ _SL13M-checkpoint OCHK-OBSERVATION-SUMMARY$
        _SL13M-readback SPRO-SUMMARY$ STR-STR= _SL13M-assert
    _SL13M-observation @ _SL13M-checkpoint
        OCHK-OBSERVATION-PUBLISHED$
        _SL13M-readback SPRO-PUBLISHED$ STR-STR= _SL13M-assert
    _SL13M-observation @ _SL13M-checkpoint
        OCHK-OBSERVATION-MODIFIED$
        _SL13M-readback SPRO-MODIFIED$ STR-STR= _SL13M-assert

    _SL13M-observation @ _SL13M-checkpoint OCHK-OBSERVATION-CONTENT$
    DUP _SL13M-blob-expected-u !
    OVER _SL13M-blob-expected-a !
    DUP _SL13M-readback SPRO.CONTENT-U @ = _SL13M-assert
    _SL13M-readback SPRO.CONTENT-DIGEST
        SHA3-256-HASH-COMPARE _SL13M-assert

    0 _SL13M-blob-offset !
    0 _SL13M-blob-errors !
    _SL13M-readback SPRO.CONTENT
    0 _SL13M-blob-expected-u @
    ['] _SL13M-blob-sink 0
    _SL13M-adapter _SL13M-adapter-work
        STREAMS-PA-BLOB-READ-RANGE
        STREAMS-PA-S-OK _SL13M-status
    _SL13M-blob-errors @ 0= _SL13M-assert
    _SL13M-blob-offset @ _SL13M-blob-expected-u @ =
        _SL13M-assert ;

: _SL13M-verify-import-owner
  ( context repository repository-work -- repository-status )
    2DROP DROP
    _SL13M-verify-source
    _SL13M-verify-attempt
    _SL13M-verify-native
    _SL13M-verify-observation
    STREAMS-REPOSITORY-S-OK ;

: _SL13M-verify-import  ( -- )
    1 ['] _SL13M-verify-import-owner
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13M-status ;

\ ---------------------------------------------------------------------
\ Matrix rows and refusal
\ ---------------------------------------------------------------------

: _SL13M-assert-base-root  ( -- root )
    _SL13M-root DUP 0<> _SL13M-assert
    DUP STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13M-assert
    DUP SAR.AUTHORITY-ID _SL13M-authority RID= _SL13M-assert
    DUP SAR.LOGICAL-GENERATION @ 0= _SL13M-assert
    DUP SAR.ACTIVE-COUNT @ 0= _SL13M-assert
    DUP SAR.REMOVED-SOURCE-COUNT @ 0= _SL13M-assert ;

: _SL13M-both-absent  ( -- )
    ." STREAMS L13 MIGRATION CASE both-absent" CR
    _SL13M-case-setup
    _SL13M-migrate STREAMS-MIGRATION-S-OK _SL13M-status
    _SL13M-migration-work STREAMS-MIGRATION-COMMIT-ATTEMPTED?
        _SL13M-assert
    _SL13M-migration-work STREAMS-MIGRATION-FLIP-CONFIRMED?
        _SL13M-assert
    _SL13M-assert-base-root
    DUP SAR.PROVENANCE @
        STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY =
        _SL13M-assert
    DUP SAR.SOURCE-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13M-assert
    DUP SAR.OBSERVATION-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13M-assert
    DUP SAR.SOURCE-COUNT @ 0= _SL13M-assert
    DUP SAR.ATTEMPT-COUNT @ 0= _SL13M-assert
    DUP SAR.OBSERVATION-COUNT @ 0= _SL13M-assert
    DUP SAR.NATIVE-COUNT @ 0= _SL13M-assert
    DUP SAR.LEGACY-SOURCE-PRESENT @ 0= _SL13M-assert
    DUP SAR.LEGACY-OBSERVATION-PRESENT @ 0= _SL13M-assert
    DUP SAR.LEGACY-SOURCE-BYTES @ 0= _SL13M-assert
    DUP SAR.LEGACY-OBSERVATION-BYTES @ 0= _SL13M-assert
    DUP SAR.LEGACY-SOURCE-DIGEST SHA3-256-LEN
        _SL13M-zero? _SL13M-assert
    SAR.LEGACY-OBSERVATION-DIGEST SHA3-256-LEN
        _SL13M-zero? _SL13M-assert
    _SL13M-case-finish ;

: _SL13M-both-valid  ( -- )
    ." STREAMS L13 MIGRATION CASE both-valid" CR
    _SL13M-case-setup
    _SL13M-source-legacy
    _SL13M-observation-legacy
    _SL13M-capture-evidence
    _SL13M-migrate STREAMS-MIGRATION-S-OK _SL13M-status
    _SL13M-migration-work
        STREAMS-MIGRATION-RECOVERED-ATTEMPT-COUNT@ 1 =
        _SL13M-assert
    _SL13M-migration-work STREAMS-MIGRATION-COMMIT-ATTEMPTED?
        _SL13M-assert
    _SL13M-migration-work STREAMS-MIGRATION-FLIP-CONFIRMED?
        _SL13M-assert
    _SL13M-assert-base-root
    DUP SAR.PROVENANCE @
        STREAMS-AUTHORITY-PROVENANCE-LEGACY-BOTH =
        _SL13M-assert
    DUP SAR.SOURCE-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13M-assert
    DUP SAR.OBSERVATION-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13M-assert
    DUP SAR.MUTATION-SEQUENCE @ 1 = _SL13M-assert
    DUP SAR.ACQUISITION-SEQUENCE @ 2 = _SL13M-assert
    DUP SAR.SOURCE-COUNT @ 1 = _SL13M-assert
    DUP SAR.ATTEMPT-COUNT @ 1 = _SL13M-assert
    DUP SAR.OBSERVATION-COUNT @ 1 = _SL13M-assert
    DUP SAR.NATIVE-COUNT @ 1 = _SL13M-assert
    DUP SAR.LEGACY-SOURCE-PRESENT @ -1 = _SL13M-assert
    DUP SAR.LEGACY-OBSERVATION-PRESENT @ -1 = _SL13M-assert
    DUP SAR.LEGACY-SOURCE-BYTES @
        STREAMS-SOURCE-STORE-RECORD-MAX = _SL13M-assert
    DUP SAR.LEGACY-OBSERVATION-BYTES @
        STREAMS-OBSERVATION-STORE-RECORD-MAX = _SL13M-assert
    DUP SAR.LEGACY-SOURCE-DIGEST SHA3-256-LEN
        _SL13M-source-digest SHA3-256-LEN
        COMPARE 0= _SL13M-assert
    SAR.LEGACY-OBSERVATION-DIGEST SHA3-256-LEN
        _SL13M-observation-digest SHA3-256-LEN
        COMPARE 0= _SL13M-assert

    _SL13M-verify-import

    \ The migration's recovery copy must not rewrite legacy authority.
    _SL13M-checkpoint-work STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _SL13M-observation-store STREAMS-OBSERVATION-STORE-LOAD
        OSTORE-S-OK _SL13M-status
    _SL13M-source-rid _SL13M-checkpoint-work OCHK-SOURCE-FIND
    DUP 0<> _SL13M-assert
    OCS.STATE @ OCHK-ATTEMPT-ACCEPTED = _SL13M-assert

    _SL13M-migrate STREAMS-MIGRATION-S-ALREADY _SL13M-status
    _SL13M-migration-work STREAMS-MIGRATION-COMMIT-ATTEMPTED?
        0= _SL13M-assert
    _SL13M-migration-work STREAMS-MIGRATION-FLIP-CONFIRMED?
        _SL13M-assert
    _SL13M-case-finish ;

: _SL13M-source-only  ( -- )
    ." STREAMS L13 MIGRATION CASE source-only" CR
    _SL13M-case-setup
    _SL13M-source-legacy
    _SL13M-migrate STREAMS-MIGRATION-S-OK _SL13M-status
    _SL13M-assert-base-root
    DUP SAR.PROVENANCE @
        STREAMS-AUTHORITY-PROVENANCE-LEGACY-SOURCES =
        _SL13M-assert
    DUP SAR.SOURCE-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13M-assert
    DUP SAR.OBSERVATION-COMPLETENESS @
        STREAMS-AUTHORITY-UNKNOWN-LEGACY-ABSENT =
        _SL13M-assert
    DUP SAR.SOURCE-COUNT @ 1 = _SL13M-assert
    DUP SAR.ATTEMPT-COUNT @ 0= _SL13M-assert
    DUP SAR.OBSERVATION-COUNT @ 0= _SL13M-assert
    DUP SAR.NATIVE-COUNT @ 0= _SL13M-assert
    DUP SAR.LEGACY-SOURCE-PRESENT @ -1 = _SL13M-assert
    SAR.LEGACY-OBSERVATION-PRESENT @ 0= _SL13M-assert
    _SL13M-case-finish ;

: _SL13M-observation-only  ( -- )
    ." STREAMS L13 MIGRATION CASE observation-only" CR
    _SL13M-case-setup
    _SL13M-observation-legacy
    _SL13M-migrate STREAMS-MIGRATION-S-OK _SL13M-status
    _SL13M-migration-work
        STREAMS-MIGRATION-RECOVERED-ATTEMPT-COUNT@ 1 =
        _SL13M-assert
    _SL13M-assert-base-root
    DUP SAR.PROVENANCE @
        STREAMS-AUTHORITY-PROVENANCE-LEGACY-OBSERVATIONS =
        _SL13M-assert
    DUP SAR.SOURCE-COMPLETENESS @
        STREAMS-AUTHORITY-UNKNOWN-LEGACY-ABSENT =
        _SL13M-assert
    DUP SAR.OBSERVATION-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13M-assert
    DUP SAR.SOURCE-COUNT @ 0= _SL13M-assert
    DUP SAR.ATTEMPT-COUNT @ 1 = _SL13M-assert
    DUP SAR.OBSERVATION-COUNT @ 1 = _SL13M-assert
    DUP SAR.NATIVE-COUNT @ 1 = _SL13M-assert
    DUP SAR.LEGACY-SOURCE-PRESENT @ 0= _SL13M-assert
    SAR.LEGACY-OBSERVATION-PRESENT @ -1 = _SL13M-assert
    _SL13M-case-finish ;

: _SL13M-read-source-record  ( -- )
    STREAMS-SOURCE-STORE-TARGET$
        VFS-FF-READ VFS-CUR VFS-OPEN?
    _SL13M-ior ! _SL13M-fd !
    _SL13M-ior @ 0= _SL13M-assert
    _SL13M-fd @ 0<> _SL13M-assert
    _SL13M-fd @ VFS-SIZE STREAMS-SOURCE-STORE-RECORD-MAX =
        _SL13M-assert
    _SL13M-source-raw STREAMS-SOURCE-STORE-RECORD-MAX
        _SL13M-fd @ VFS-READ-EXACT 0= _SL13M-assert
    _SL13M-fd @ VFS-CLOSE? 0= _SL13M-assert
    0 _SL13M-fd ! ;

: _SL13M-write-source-record  ( -- )
    STREAMS-SOURCE-STORE-TARGET$
        VFS-FF-READ VFS-FF-WRITE OR VFS-CUR VFS-OPEN?
    _SL13M-ior ! _SL13M-fd !
    _SL13M-ior @ 0= _SL13M-assert
    _SL13M-fd @ 0<> _SL13M-assert
    _SL13M-fd @ VFS-REWIND
    _SL13M-source-raw STREAMS-SOURCE-STORE-RECORD-MAX
        _SL13M-fd @ VFS-WRITE-EXACT 0= _SL13M-assert
    _SL13M-fd @ VFS-CLOSE? 0= _SL13M-assert
    0 _SL13M-fd !
    _SL13M-vfs @ VFS-SYNC 0= _SL13M-assert ;

: _SL13M-corrupt-refusal  ( -- )
    ." STREAMS L13 MIGRATION CASE corrupt-refusal" CR
    _SL13M-case-setup
    _SL13M-source-legacy
    _SL13M-read-source-record
    _SL13M-source-raw STREAMS-SOURCE-STORE-HEADER-SIZE +
        DUP C@ 1 XOR SWAP C!
    _SL13M-write-source-record
    _SL13M-migrate STREAMS-MIGRATION-S-CORRUPT _SL13M-status
    _SL13M-migration-work STREAMS-MIGRATION-COMMIT-ATTEMPTED?
        0= _SL13M-assert
    _SL13M-migration-work STREAMS-MIGRATION-FLIP-CONFIRMED?
        0= _SL13M-assert
    _SL13M-root 0= _SL13M-assert
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-ABSENT _SL13M-status
    _SL13M-case-finish ;

: _SL13M-RUN  ( -- )
    0 _SL13M-checks !
    0 _SL13M-fails !
    DEPTH _SL13M-depth !
    _SL13M-both-absent
    _SL13M-both-valid
    _SL13M-source-only
    _SL13M-observation-only
    _SL13M-corrupt-refusal
    _SL13M-stack
    _SL13M-fails @ IF
        ." STREAMS L13 MIGRATION FAIL "
            _SL13M-fails @ . ." / " _SL13M-checks @ . CR
    ELSE
        ." STREAMS L13 MIGRATION PASS " _SL13M-checks @ . CR
    THEN ;
