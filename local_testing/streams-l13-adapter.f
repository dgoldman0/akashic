\ Focused transactional contracts for the L13 four-tree Streams adapter.

PROVIDED akashic-streams-l13-adapter-contracts

VARIABLE _SL13A-checks
VARIABLE _SL13A-fails
VARIABLE _SL13A-depth
VARIABLE _SL13A-arena
VARIABLE _SL13A-vfs
VARIABLE _SL13A-ior

CREATE _SL13A-ops VFS-OPS-SIZE ALLOT
CREATE _SL13A-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _SL13A-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _SL13A-authority RID-SIZE ALLOT
CREATE _SL13A-rid-a RID-SIZE ALLOT
CREATE _SL13A-rid-b RID-SIZE ALLOT
CREATE _SL13A-store PSTORE-SIZE ALLOT
CREATE _SL13A-pwork PSTORE-WORK-SIZE ALLOT
CREATE _SL13A-adapter STREAMS-PA-SIZE ALLOT
STREAMS-PA-WORK-SIZE XBUF _SL13A-work

STREAMS-PERSISTENCE-RECORD-MAX PBLOB-CHUNK-SIZE MAX
    CONSTANT _SL13A-record-max
_SL13A-record-max PERSIST-RECORD-HEADER-SIZE +
    CONSTANT _SL13A-buffer-u
_SL13A-buffer-u XBUF _SL13A-buffer

STREAMS-SOURCE-SIZE XBUF _SL13A-source
SPREC-SOURCE-SIZE XBUF _SL13A-source-record
SPREC-SOURCE-SIZE XBUF _SL13A-source-out
SPREC-SOURCE-TOMBSTONE-SIZE XBUF _SL13A-tombstone
SPREC-SOURCE-TOMBSTONE-SIZE XBUF _SL13A-tombstone-out
STREAMS-OBSERVATION-CHECKPOINT-SIZE XBUF _SL13A-checkpoint
OCHK-CANDIDATE-SIZE XBUF _SL13A-candidate
SPREC-ATTEMPT-SIZE XBUF _SL13A-attempt
SPREC-NATIVE-HEAD-SIZE XBUF _SL13A-native
SPREC-OBSERVATION-SIZE XBUF _SL13A-observation
SPREC-OBSERVATION-SIZE XBUF _SL13A-observation-out
STREAMS-OC-WORK-SIZE XBUF _SL13A-oc-work
CREATE _SL13A-key STREAMS-PI-KEY-MAX ALLOT
CREATE _SL13A-key2 STREAMS-PI-KEY-MAX ALLOT
CREATE _SL13A-ref PERSIST-REF-SIZE ALLOT
CREATE _SL13A-blob PBLOB-SIZE ALLOT
CREATE _SL13A-namespace SHA3-256-LEN ALLOT
STREAMS-PA-RANGE-ROW-SIZE 2 * XBUF _SL13A-rows
STREAMS-QUERY-PAGE-SIZE XBUF _SL13A-query-page
STREAMS-QUERY-WORK-SIZE XBUF _SL13A-query-work
STREAMS-QUERY-CONTINUATION-SIZE XBUF _SL13A-query-after
STREAMS-QUERY-CONTINUATION-SIZE XBUF _SL13A-query-before
GUARD _SL13A-guard

VARIABLE _SL13A-sink-bytes
VARIABLE _SL13A-sink-calls
VARIABLE _SL13A-sink-errors

PBLOB-CHUNK-SIZE 37 + CONSTANT _SL13A-blob-total
0x5A CONSTANT _SL13A-blob-seed

: _SL13A-assert  ( flag -- )
    1 _SL13A-checks +!
    0= IF
        1 _SL13A-fails +!
        ." STREAMS L13 ADAPTER ASSERT " _SL13A-checks @ . CR
    THEN ;

: _SL13A-stack  ( -- )
    DEPTH DUP _SL13A-depth @ <> IF
        ." STREAMS L13 ADAPTER STACK "
        _SL13A-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13A-depth @ = _SL13A-assert ;

: _SL13A-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 ADAPTER STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13A-assert _SL13A-stack ;

: _SL13A-zero?  ( a u -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SL13A-blob-source
  ( logical-offset destination-a requested-u seed -- actual-u status )
    SWAP DUP >R
    0 ?DO
        1 PICK I +
        3 PICK I + 2 PICK + 255 AND
        SWAP C!
    LOOP
    2DROP DROP R> PERSIST-S-OK ;

: _SL13A-blob-sink
  ( logical-offset payload-a payload-u seed -- status )
    SWAP DUP >R
    0 ?DO
        1 PICK I + C@
        3 PICK I + 2 PICK + 255 AND
        <> IF 1 _SL13A-sink-errors +! THEN
    LOOP
    2DROP DROP
    R> DUP _SL13A-sink-bytes +! DROP
    1 _SL13A-sink-calls +!
    PERSIST-S-OK ;

: _SL13A-observation-sink
  ( logical-offset payload-a payload-u content-a -- status )
    SWAP DUP >R
    0 ?DO
        1 PICK I + C@
        3 PICK I + 2 PICK + C@
        <> IF 1 _SL13A-sink-errors +! THEN
    LOOP
    2DROP DROP
    R> DUP _SL13A-sink-bytes +! DROP
    1 _SL13A-sink-calls +!
    PERSIST-S-OK ;

: _SL13A-source!  ( revision -- )
    >R
    _SL13A-source STREAMS-SOURCE-INIT
    _SL13A-rid-a _SL13A-source STREAMS-SOURCE-ID!
        SSREG-S-OK _SL13A-status
    R@ _SL13A-source SSOURCE.REVISION !
    SSOURCE-KIND-SYNDICATION _SL13A-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _SL13A-source SSOURCE.FORMAT !
    R@ 1 = IF
        S" First persisted source"
    ELSE
        R@ 2 = IF S" Updated persisted source"
        ELSE S" Discarded persisted source" THEN
    THEN
    _SL13A-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13A-status
    S" https://example.test/adapter.json"
        _SL13A-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13A-status
    _SL13A-source STREAMS-SOURCE-VALID? _SL13A-assert
    _SL13A-source 1 _SL13A-source-record SPREC-SOURCE-CONSTRUCT
        SPREC-S-OK _SL13A-status
    R> DROP ;

: _SL13A-setup  ( -- )
    VFS-RAM-OPS _SL13A-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _SL13A-binding VFS-BINDING-DESC-SIZE MOVE
    _SL13A-ops _SL13A-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW
    DUP 0= _SL13A-assert DROP _SL13A-arena !
    _SL13A-arena @ _SL13A-binding 0 VFS-NEW
    _SL13A-ior ! _SL13A-vfs !
    _SL13A-ior @ 0= _SL13A-assert
    _SL13A-vfs @ 0<> _SL13A-assert

    _SL13A-identity PERSIST-IDENTITY-SIZE 0x73 FILL
    _SL13A-authority RID-SIZE 0xA0 FILL
    _SL13A-rid-a RID-SIZE 0xA1 FILL
    _SL13A-rid-b RID-SIZE 0xA2 FILL
    _SL13A-namespace SHA3-256-LEN 0xB3 FILL
    _SL13A-key STREAMS-PI-KEY-MAX 0 FILL
    _SL13A-key2 STREAMS-PI-KEY-MAX 0 FILL
    _SL13A-ref PERSIST-REF-SIZE 0 FILL
    _SL13A-oc-work STREAMS-OC-WORK-INIT
        STREAMS-OC-S-OK _SL13A-status

    S" /sl13a-pages" S" /sl13a-segments"
    S" /sl13a-root-a" S" /sl13a-root-b"
    _SL13A-identity _SL13A-record-max
    _SL13A-vfs @ 0 0 _SL13A-guard 0 0 _SL13A-store
        PSTORE-INIT PERSIST-S-OK _SL13A-status
    _SL13A-buffer _SL13A-buffer-u _SL13A-pwork
        PSTORE-WORK-INIT PERSIST-S-OK _SL13A-status
    _SL13A-store _SL13A-adapter STREAMS-PA-INIT
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-pwork _SL13A-adapter _SL13A-work
        STREAMS-PA-WORK-INIT STREAMS-PA-S-OK _SL13A-status
    _SL13A-source STREAMS-SOURCE-SIZE _SL13A-work
        STREAMS-PA-SPAN-DISJOINT? _SL13A-assert
    _SL13A-buffer _SL13A-buffer-u _SL13A-work
        STREAMS-PA-SPAN-DISJOINT? 0= _SL13A-assert
    _SL13A-source STREAMS-SOURCE-SIZE 0
        STREAMS-PA-SPAN-DISJOINT? 0= _SL13A-assert
    _SL13A-store _SL13A-pwork PSTORE-PROVISION
        PERSIST-S-OK _SL13A-status ;

: _SL13A-provision  ( -- )
    _SL13A-adapter _SL13A-work STREAMS-PA-OPEN
        STREAMS-PA-S-ABSENT _SL13A-status
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@ 0= _SL13A-assert
    _SL13A-authority _SL13A-adapter _SL13A-work
        STREAMS-PA-PROVISION STREAMS-PA-S-OK _SL13A-status
    _SL13A-adapter STREAMS-PA-PHYSICAL-GENERATION@ 1 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-LOGICAL-GENERATION@ 0 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-MUTATION-SEQUENCE@ 0 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13A-assert
    DUP SAR.AUTHORITY-ID _SL13A-authority RID= _SL13A-assert
    DUP SAR.SOURCE-COUNT @ 0= _SL13A-assert
    DUP SAR.ATTEMPT-COUNT @ 0= _SL13A-assert
    DUP SAR.OBSERVATION-COUNT @ 0= _SL13A-assert
    DROP
    _SL13A-authority _SL13A-adapter _SL13A-work
        STREAMS-PA-PROVISION STREAMS-PA-S-OK _SL13A-status
    _SL13A-rid-b _SL13A-adapter _SL13A-work
        STREAMS-PA-PROVISION STREAMS-PA-S-CONFLICT _SL13A-status ;

: _SL13A-source-keys-put  ( -- )
    _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status
    1 _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status ;

: _SL13A-source-keys-staged-put  ( -- )
    _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-STAGED-PUT STREAMS-PA-S-OK _SL13A-status
    1 _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-STAGED-PUT STREAMS-PA-S-OK _SL13A-status ;

: _SL13A-source-get  ( expected-revision -- )
    >R
    _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-source-out SPREC-SOURCE-SIZE 0xCC FILL
    _SL13A-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13A-source-out SPREC-SOURCE-SIZE
        _SL13A-adapter _SL13A-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP SPREC-SOURCE-SIZE = _SL13A-assert
    DROP
    _SL13A-source-out SPREC-SOURCE-SIZE
        SPREC-SOURCE-VALID? _SL13A-assert
    _SL13A-source-out SPRS.REVISION @ R> = _SL13A-assert
    _SL13A-stack ;

: _SL13A-visible-create  ( -- )
    1 _SL13A-source!
    _SL13A-adapter _SL13A-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-source-record SPREC-SOURCE-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-blob-total ['] _SL13A-blob-source _SL13A-blob-seed
        _SL13A-blob _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-WRITE STREAMS-PA-S-OK _SL13A-status
    _SL13A-blob 0 1 ['] _SL13A-blob-sink _SL13A-blob-seed
        _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-READ-RANGE STREAMS-PA-S-BUSY _SL13A-status
    _SL13A-source-keys-put
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13A-assert
    1 SWAP SAR.SOURCE-COUNT !
    _SL13A-adapter _SL13A-work STREAMS-PA-COMMIT
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-LOGICAL-GENERATION@ 1 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-MUTATION-SEQUENCE@ 1 =
        _SL13A-assert
    STREAMS-PI-TREE-DIRECTORY _SL13A-work STREAMS-PA-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 2 = _SL13A-assert
    1 _SL13A-source-get ;

: _SL13A-blob-reads  ( -- )
    0 _SL13A-sink-bytes !
    0 _SL13A-sink-calls !
    0 _SL13A-sink-errors !
    _SL13A-blob PBLOB-CHUNK-SIZE 8 -
        32 ['] _SL13A-blob-sink _SL13A-blob-seed
        _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-READ-RANGE STREAMS-PA-S-OK _SL13A-status
    _SL13A-sink-bytes @ 32 = _SL13A-assert
    _SL13A-sink-calls @ 2 = _SL13A-assert
    _SL13A-sink-errors @ 0= _SL13A-assert

    0 _SL13A-sink-bytes !
    0 _SL13A-sink-calls !
    _SL13A-blob _SL13A-blob-total 11 -
        ['] _SL13A-blob-sink _SL13A-blob-seed
        _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-STREAM STREAMS-PA-S-OK _SL13A-status
    _SL13A-sink-bytes @ 11 = _SL13A-assert
    _SL13A-sink-calls @ 1 = _SL13A-assert
    _SL13A-sink-errors @ 0= _SL13A-assert

    _SL13A-blob _SL13A-blob-total 1+
        1 ['] _SL13A-blob-sink _SL13A-blob-seed
        _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-READ-RANGE STREAMS-PA-S-NOT-FOUND _SL13A-status
    _SL13A-blob _SL13A-blob-total
        0 0 0 _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-READ-RANGE STREAMS-PA-S-OK _SL13A-status
    _SL13A-work 0 1 ['] _SL13A-blob-sink _SL13A-blob-seed
        _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-READ-RANGE STREAMS-PA-S-INVALID _SL13A-status
    _SL13A-stack ;

: _SL13A-attempt-head  ( -- head )
    _SL13A-rid-a _SL13A-checkpoint OCHK-SOURCE-FIND ;

: _SL13A-journal-inputs  ( -- )
    _SL13A-checkpoint OCHK-INIT
    _SL13A-rid-a 1 _SL13A-namespace 1
        S" https://example.test/adapter.json"
        _SL13A-checkpoint OCHK-BEGIN OCHK-S-OK _SL13A-status
    _SL13A-attempt-head DUP 0<> _SL13A-assert
    _SL13A-attempt SPREC-ATTEMPT-CONSTRUCT
        SPREC-S-OK _SL13A-status
    _SL13A-attempt SPREC-ATTEMPT-SIZE
        SPREC-ATTEMPT-VALID? _SL13A-assert
    _SL13A-attempt SPRA.STATE @
        OCHK-ATTEMPT-ACCEPTED = _SL13A-assert

    _SL13A-candidate OCHK-CANDIDATE-INIT
    SSOURCE-FORMAT-JSON-FEED _SL13A-candidate OCC.FORMAT !
    OCHK-NATIVE-PROVIDER-ID _SL13A-candidate OCC.NATIVE-KIND !
    S" l13-adapter-native"
        _SL13A-candidate OCC.NATIVE-U !
        _SL13A-candidate OCC.NATIVE-A !
    S" Adapter journal observation"
        _SL13A-candidate OCC.TITLE-U !
        _SL13A-candidate OCC.TITLE-A !
    S" https://example.test/item/adapter"
        _SL13A-candidate OCC.URL-U !
        _SL13A-candidate OCC.URL-A !
    S" Immutable streaming evidence"
        _SL13A-candidate OCC.SUMMARY-U !
        _SL13A-candidate OCC.SUMMARY-A !
    S" Exact L13 streamed content bytes"
        _SL13A-candidate OCC.CONTENT-U !
        _SL13A-candidate OCC.CONTENT-A !
    S" 2026-07-24T16:00:00Z"
        _SL13A-candidate OCC.PUBLISHED-U !
        _SL13A-candidate OCC.PUBLISHED-A !
    _SL13A-candidate SPREC-CANDIDATE-VALID? _SL13A-assert
    _SL13A-stack ;

: _SL13A-attempt-history-key  ( -- )
    _SL13A-rid-a
    _SL13A-attempt SPRA.ATTEMPT-SEQUENCE @
    _SL13A-attempt SPRA.ATTEMPT-ID
    _SL13A-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY
        STREAMS-PI-S-OK _SL13A-status ;

: _SL13A-active-range  ( -- )
    _SL13A-rid-a _SL13A-key2 STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP 1 = _SL13A-assert DROP
    _SL13A-rows STREAMS-PA-RANGE-ROW-VALID? _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-KEY$
        2DUP STREAMS-PI-ACTIVE-ATTEMPT-KEY-VALID? _SL13A-assert
        _SL13A-key2 STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        STR-STR= _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-RECORD$
        _SL13A-attempt SPREC-ATTEMPT-SIZE
        COMPARE 0= _SL13A-assert
    _SL13A-stack ;

: _SL13A-accepted-attempt  ( -- )
    _SL13A-adapter _SL13A-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-attempt SPREC-ATTEMPT-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-attempt-history-key
    _SL13A-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status
    _SL13A-rid-a _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13A-assert
    DUP 1 SWAP SAR.ACQUISITION-SEQUENCE !
    DUP 1 SWAP SAR.ATTEMPT-COUNT !
    1 SWAP SAR.ACTIVE-COUNT !
    _SL13A-adapter _SL13A-work STREAMS-PA-COMMIT
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-LOGICAL-GENERATION@ 2 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-MUTATION-SEQUENCE@ 2 =
        _SL13A-assert
    STREAMS-PI-TREE-DIRECTORY _SL13A-work STREAMS-PA-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 3 = _SL13A-assert
    STREAMS-PI-TREE-ATTEMPTS _SL13A-work STREAMS-PA-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 1 = _SL13A-assert
    _SL13A-active-range
    _SL13A-stack ;

: _SL13A-terminal-inputs  ( -- )
    OCHK-ATTEMPT-SUCCEEDED _SL13A-attempt SPRA.STATE !
    OCHK-O-OK _SL13A-attempt SPRA.OUTCOME !
    10 _SL13A-attempt SPRA.STARTED-MS !
    11 _SL13A-attempt SPRA.FINISHED-MS !
    S" https://example.test/adapter.json"
        DUP _SL13A-attempt SPRA.EFFECTIVE-U !
        _SL13A-attempt SPRA.EFFECTIVE SWAP MOVE
    1 _SL13A-attempt SPRA.NEW-COUNT !
    _SL13A-attempt SPREC-ATTEMPT-SEAL!
        SPREC-S-OK _SL13A-status

    _SL13A-native SPREC-NATIVE-INIT SPREC-S-OK _SL13A-status
    _SL13A-rid-a _SL13A-native SPRH.SOURCE-ID RID-COPY
    _SL13A-namespace _SL13A-native SPRH.NAMESPACE RID-COPY
    1 _SL13A-native SPRH.LATEST-REVISION !
    1 _SL13A-native SPRH.LAST-SEEN-SEQUENCE !
    1 _SL13A-native SPRH.COLLISION-ORDINAL !
    _SL13A-candidate _SL13A-native SPREC-NATIVE-CANDIDATE!
        SPREC-S-OK _SL13A-status
    _SL13A-native SPREC-NATIVE-HEAD-SIZE
        SPREC-NATIVE-VALID? _SL13A-assert

    _SL13A-observation SPREC-OBSERVATION-SIZE 0xCC FILL
    _SL13A-candidate _SL13A-attempt _SL13A-native
        _SL13A-observation _SL13A-adapter _SL13A-work _SL13A-oc-work
        STREAMS-OC-CONSTRUCT STREAMS-OC-S-BUSY _SL13A-status
    _SL13A-observation SPREC-OBSERVATION-SIZE _SL13A-zero?
        _SL13A-assert
    _SL13A-oc-work STREAMS-OC-ABORT-REQUIRED? 0=
        _SL13A-assert
    _SL13A-stack ;

: _SL13A-native-key  ( -- )
    _SL13A-native SPRH.SOURCE-ID
    _SL13A-native SPRH.NAMESPACE
    _SL13A-native SPRH.OBSERVATION-FORMAT @
    _SL13A-native SPRH.NATIVE-KIND @
    _SL13A-native SPRH.NATIVE-DIGEST
    _SL13A-native SPRH.COLLISION-ORDINAL @
    _SL13A-key STREAMS-PI-NATIVE-HEAD-KEY
        STREAMS-PI-S-OK _SL13A-status ;

: _SL13A-observation-keys-put  ( -- )
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-observation SPRO.REVISION @
    _SL13A-key STREAMS-PI-OBSERVATION-REVISION-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-OBSERVATION-REVISION-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status

    _SL13A-observation SPRO.ACQUISITION-SEQUENCE @
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-observation SPRO.REVISION @
    _SL13A-key STREAMS-PI-GLOBAL-TIME-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-GLOBAL-TIME-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status

    _SL13A-observation SPRO.SOURCE-ID
    _SL13A-observation SPRO.ACQUISITION-SEQUENCE @
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-observation SPRO.REVISION @
    _SL13A-key STREAMS-PI-SOURCE-TIME-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-TIME-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status ;

: _SL13A-journal-apply  ( -- )
    _SL13A-adapter _SL13A-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-candidate _SL13A-attempt _SL13A-native
        _SL13A-observation _SL13A-adapter _SL13A-work _SL13A-oc-work
        STREAMS-OC-CONSTRUCT STREAMS-OC-S-OK _SL13A-status
    _SL13A-observation SPREC-OBSERVATION-SIZE
        SPREC-OBSERVATION-VALID? _SL13A-assert
    _SL13A-observation _SL13A-attempt _SL13A-native
        STREAMS-SRA-OBSERVATION-PUBLICATION-AGREES?
        _SL13A-assert

    _SL13A-attempt SPREC-ATTEMPT-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-attempt-history-key
    _SL13A-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status
    _SL13A-rid-a _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        _SL13A-adapter _SL13A-work
        STREAMS-PA-DELETE STREAMS-PA-S-OK _SL13A-status

    _SL13A-native SPREC-NATIVE-HEAD-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-native-key
    _SL13A-key STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status

    _SL13A-observation SPREC-OBSERVATION-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-observation-keys-put

    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13A-assert
    DUP 0 SWAP SAR.ACTIVE-COUNT !
    DUP 1 SWAP SAR.OBSERVATION-COUNT !
    1 SWAP SAR.NATIVE-COUNT !
    _SL13A-adapter _SL13A-work STREAMS-PA-COMMIT
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-LOGICAL-GENERATION@ 3 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-MUTATION-SEQUENCE@ 3 =
        _SL13A-assert
    STREAMS-PI-TREE-DIRECTORY _SL13A-work STREAMS-PA-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 2 = _SL13A-assert
    STREAMS-PI-TREE-IDENTITIES _SL13A-work STREAMS-PA-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 2 = _SL13A-assert
    STREAMS-PI-TREE-ORDERINGS _SL13A-work STREAMS-PA-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 2 = _SL13A-assert
    _SL13A-stack ;

: _SL13A-journal-read  ( -- )
    _SL13A-candidate OCC.CONTENT-A @
    _SL13A-candidate OCC.CONTENT-U @
    _SL13A-observation SPRO.CONTENT-DIGEST
        SHA3-256-HASH-COMPARE _SL13A-assert
    _SL13A-observation SPRO.CONTENT PBLOB-TOTAL@
        _SL13A-candidate OCC.CONTENT-U @ = _SL13A-assert

    0 _SL13A-sink-bytes !
    0 _SL13A-sink-calls !
    0 _SL13A-sink-errors !
    _SL13A-observation SPRO.CONTENT 0
        ['] _SL13A-observation-sink
        _SL13A-candidate OCC.CONTENT-A @
        _SL13A-adapter _SL13A-work
        STREAMS-PA-BLOB-STREAM STREAMS-PA-S-OK _SL13A-status
    _SL13A-sink-bytes @
        _SL13A-candidate OCC.CONTENT-U @ = _SL13A-assert
    _SL13A-sink-calls @ 1 = _SL13A-assert
    _SL13A-sink-errors @ 0= _SL13A-assert

    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-observation SPRO.REVISION @
    _SL13A-key STREAMS-PI-OBSERVATION-REVISION-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-OBSERVATION-REVISION-KEY-SIZE
        _SL13A-observation-out SPREC-OBSERVATION-SIZE
        _SL13A-adapter _SL13A-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP SPREC-OBSERVATION-SIZE = _SL13A-assert DROP
    _SL13A-observation-out SPREC-OBSERVATION-SIZE
        _SL13A-observation SPREC-OBSERVATION-SIZE
        COMPARE 0= _SL13A-assert
    _SL13A-stack ;

: _SL13A-journal  ( -- )
    _SL13A-journal-inputs
    _SL13A-accepted-attempt
    _SL13A-terminal-inputs
    _SL13A-journal-apply
    _SL13A-journal-read ;

: _SL13A-query-init  ( -- )
    _SL13A-query-work STREAMS-QUERY-WORK-INIT
        STREAMS-QUERY-S-OK _SL13A-status
    _SL13A-rows 1 _SL13A-query-page STREAMS-QUERY-PAGE-INIT
        STREAMS-QUERY-S-OK _SL13A-status
    _SL13A-query-page STREAMS-QUERY-PAGE-VALID? _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-PUBLISHED? 0=
        _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-ID@
        _SL13A-authority RID= _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-PROVENANCE@
        STREAMS-AUTHORITY-PROVENANCE-NATIVE = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-SOURCE-COMPLETENESS@
        STREAMS-AUTHORITY-COMPLETE = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-OBSERVATION-COMPLETENESS@
        STREAMS-AUTHORITY-COMPLETE = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-LOGICAL-GENERATION@
        3 = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-MUTATION-SEQUENCE@
        3 = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-ACQUISITION-SEQUENCE@
        1 = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-SOURCE-COUNT@
        1 = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-REMOVED-SOURCE-COUNT@
        0= _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-ATTEMPT-COUNT@
        1 = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-OBSERVATION-COUNT@
        1 = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-NATIVE-COUNT@
        1 = _SL13A-assert
    _SL13A-work STREAMS-QUERY-AUTHORITY-ACTIVE-COUNT@
        0= _SL13A-assert
    _SL13A-stack ;

: _SL13A-query-page-metadata  ( family count -- )
    >R
    _SL13A-query-page STREAMS-QUERY-PAGE-VALID? _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-PUBLISHED? _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-FAMILY@ = _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-COUNT@ R> =
        _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-AUTHORITY-ID@
        _SL13A-authority RID= _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-PROVENANCE@
        STREAMS-AUTHORITY-PROVENANCE-NATIVE = _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-SOURCE-COMPLETENESS@
        STREAMS-AUTHORITY-COMPLETE = _SL13A-assert
    _SL13A-query-page
        STREAMS-QUERY-PAGE-OBSERVATION-COMPLETENESS@
        STREAMS-AUTHORITY-COMPLETE = _SL13A-assert
    _SL13A-query-page STREAMS-QUERY-PAGE-COMPLETE?
        _SL13A-assert
    _SL13A-stack ;

: _SL13A-query-copy-tokens  ( -- )
    _SL13A-query-page STREAMS-QUERY-PAGE-AFTER-CONTINUATION@
    DUP 0<> _SL13A-assert
    DUP STREAMS-QUERY-CONTINUATION-READY? _SL13A-assert
    DUP STREAMS-QUERY-CONTINUATION-DIRECTION@
        STREAMS-QUERY-DIRECTION-AFTER = _SL13A-assert
    _SL13A-query-after STREAMS-QUERY-CONTINUATION-COPY
        STREAMS-QUERY-S-OK _SL13A-status
    _SL13A-query-page STREAMS-QUERY-PAGE-BEFORE-CONTINUATION@
    DUP 0<> _SL13A-assert
    DUP STREAMS-QUERY-CONTINUATION-READY? _SL13A-assert
    DUP STREAMS-QUERY-CONTINUATION-DIRECTION@
        STREAMS-QUERY-DIRECTION-BEFORE = _SL13A-assert
    _SL13A-query-before STREAMS-QUERY-CONTINUATION-COPY
        STREAMS-QUERY-S-OK _SL13A-status
    _SL13A-stack ;

: _SL13A-query-sources  ( -- )
    _SL13A-query-page _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCES-FIRST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-SOURCES 1 _SL13A-query-page-metadata
    0 _SL13A-query-page STREAMS-QUERY-SOURCE-PAGE-ROW@
    DUP 0<> _SL13A-assert
    DUP SPRS.ID _SL13A-rid-a RID= _SL13A-assert
    SPRS.REVISION @ 1 = _SL13A-assert
    _SL13A-query-copy-tokens
    _SL13A-query-page _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCES-LAST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-SOURCES 1 _SL13A-query-page-metadata
    0 _SL13A-query-page STREAMS-QUERY-SOURCE-PAGE-ROW@
    DUP 0<> _SL13A-assert
    SPRS.ID _SL13A-rid-a RID= _SL13A-assert

    _SL13A-query-before _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCES-AFTER
        STREAMS-QUERY-S-INVALID _SL13A-status
    _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-GLOBAL-TIME-AFTER
        STREAMS-QUERY-S-INVALID _SL13A-status

    _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCES-AFTER
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-SOURCES 0 _SL13A-query-page-metadata
    _SL13A-query-page STREAMS-QUERY-PAGE-AFTER-CONTINUATION@
        STREAMS-QUERY-CONTINUATION-READY? 0= _SL13A-assert
    _SL13A-query-before _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCES-BEFORE
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-SOURCES 0 _SL13A-query-page-metadata
    _SL13A-stack ;

: _SL13A-query-attempts  ( -- )
    _SL13A-rid-a _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-ATTEMPTS-FIRST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-ATTEMPTS 1 _SL13A-query-page-metadata
    0 _SL13A-query-page STREAMS-QUERY-ATTEMPT-PAGE-ROW@
    DUP 0<> _SL13A-assert
    DUP SPREC-ATTEMPT-SIZE
        _SL13A-attempt SPREC-ATTEMPT-SIZE
        COMPARE 0= _SL13A-assert
    DROP
    _SL13A-query-copy-tokens

    _SL13A-rid-b _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-ATTEMPTS-AFTER
        STREAMS-QUERY-S-INVALID _SL13A-status
    _SL13A-rid-a _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-ATTEMPTS-AFTER
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-ATTEMPTS 0 _SL13A-query-page-metadata
    _SL13A-rid-a _SL13A-query-before _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-ATTEMPTS-BEFORE
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-ATTEMPTS 0 _SL13A-query-page-metadata

    _SL13A-rid-a _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-ATTEMPTS-LAST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-ATTEMPTS 1 _SL13A-query-page-metadata
    _SL13A-rid-a _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-ATTEMPT-LATEST@
    DUP STREAMS-QUERY-S-OK = _SL13A-assert
    DROP
    DUP 0<> _SL13A-assert
    DUP SPRA.SOURCE-ID _SL13A-rid-a RID= _SL13A-assert
    SPRA.ATTEMPT-SEQUENCE @ 1 = _SL13A-assert
    _SL13A-stack ;

: _SL13A-query-observation-revisions  ( -- )
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-query-page _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-OBSERVATION-REVISIONS-FIRST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-OBSERVATION-REVISIONS 1
        _SL13A-query-page-metadata
    0 _SL13A-query-page STREAMS-QUERY-OBSERVATION-PAGE-ROW@
    DUP 0<> _SL13A-assert
    DUP SPRO.OBSERVATION-ID
        _SL13A-observation SPRO.OBSERVATION-ID RID= _SL13A-assert
    SPRO.REVISION @ 1 = _SL13A-assert
    _SL13A-query-copy-tokens

    _SL13A-rid-b _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-OBSERVATION-REVISIONS-AFTER
        STREAMS-QUERY-S-INVALID _SL13A-status
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-OBSERVATION-REVISIONS-AFTER
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-OBSERVATION-REVISIONS 0
        _SL13A-query-page-metadata
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-query-before _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-OBSERVATION-REVISIONS-BEFORE
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-OBSERVATION-REVISIONS 0
        _SL13A-query-page-metadata

    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-query-page _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-OBSERVATION-REVISIONS-LAST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-OBSERVATION-REVISIONS 1
        _SL13A-query-page-metadata
    0 _SL13A-query-page STREAMS-QUERY-OBSERVATION-PAGE-ROW@
    DUP 0<> _SL13A-assert
    SPRO.REVISION @ 1 = _SL13A-assert
    _SL13A-stack ;

: _SL13A-query-global  ( -- )
    _SL13A-query-page _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-GLOBAL-TIME-FIRST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-GLOBAL-TIME 1 _SL13A-query-page-metadata
    0 _SL13A-query-page STREAMS-QUERY-OBSERVATION-PAGE-ROW@
    DUP 0<> _SL13A-assert
    DUP SPREC-OBSERVATION-SIZE
        _SL13A-observation SPREC-OBSERVATION-SIZE
        COMPARE 0= _SL13A-assert
    DROP
    _SL13A-query-copy-tokens
    _SL13A-query-page _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-GLOBAL-TIME-LAST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-GLOBAL-TIME 1 _SL13A-query-page-metadata
    0 _SL13A-query-page STREAMS-QUERY-OBSERVATION-PAGE-ROW@
    DUP 0<> _SL13A-assert
    SPRO.OBSERVATION-ID
        _SL13A-observation SPRO.OBSERVATION-ID RID= _SL13A-assert
    _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-GLOBAL-TIME-AFTER
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-GLOBAL-TIME 0 _SL13A-query-page-metadata
    _SL13A-query-before _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-GLOBAL-TIME-BEFORE
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-GLOBAL-TIME 0 _SL13A-query-page-metadata
    _SL13A-stack ;

: _SL13A-query-source-time  ( -- )
    _SL13A-rid-a _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCE-TIME-FIRST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-SOURCE-TIME 1 _SL13A-query-page-metadata
    _SL13A-query-copy-tokens
    _SL13A-rid-a _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCE-TIME-LAST
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-SOURCE-TIME 1 _SL13A-query-page-metadata
    _SL13A-rid-b _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCE-TIME-AFTER
        STREAMS-QUERY-S-INVALID _SL13A-status
    _SL13A-rid-a _SL13A-query-after _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCE-TIME-AFTER
        STREAMS-QUERY-S-OK _SL13A-status
    STREAMS-QUERY-FAMILY-SOURCE-TIME 0 _SL13A-query-page-metadata
    _SL13A-rid-a _SL13A-query-page
        _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-SOURCE-OBSERVATION-LATEST@
    DUP STREAMS-QUERY-S-OK = _SL13A-assert
    DROP
    DUP 0<> _SL13A-assert
    DUP SPRO.SOURCE-ID _SL13A-rid-a RID= _SL13A-assert
    SPRO.ACQUISITION-SEQUENCE @ 1 = _SL13A-assert
    _SL13A-stack ;

: _SL13A-query-exact-and-content  ( -- )
    _SL13A-observation-out SPREC-OBSERVATION-SIZE 0xD7 FILL
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-observation SPRO.REVISION @
    _SL13A-observation-out SPREC-OBSERVATION-SIZE
    _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-OBSERVATION-REVISION@
    DUP STREAMS-QUERY-S-OK = _SL13A-assert
    SWAP SPREC-OBSERVATION-SIZE = _SL13A-assert DROP
    _SL13A-observation-out SPREC-OBSERVATION-SIZE
        _SL13A-observation SPREC-OBSERVATION-SIZE
        COMPARE 0= _SL13A-assert
    _SL13A-observation-out
        STREAMS-QUERY-OBSERVATION-CONTENT-SIZE@
        _SL13A-candidate OCC.CONTENT-U @ = _SL13A-assert

    0 _SL13A-sink-bytes !
    0 _SL13A-sink-calls !
    0 _SL13A-sink-errors !
    _SL13A-observation-out 0 7
        ['] _SL13A-observation-sink
        _SL13A-candidate OCC.CONTENT-A @
        _SL13A-adapter _SL13A-work
        STREAMS-QUERY-OBSERVATION-CONTENT-READ-RANGE
        STREAMS-QUERY-S-OK _SL13A-status
    _SL13A-sink-bytes @ 7 = _SL13A-assert
    _SL13A-sink-calls @ 1 = _SL13A-assert
    _SL13A-sink-errors @ 0= _SL13A-assert

    0 _SL13A-sink-bytes !
    0 _SL13A-sink-calls !
    _SL13A-observation-out 7
        ['] _SL13A-observation-sink
        _SL13A-candidate OCC.CONTENT-A @
        _SL13A-adapter _SL13A-work
        STREAMS-QUERY-OBSERVATION-CONTENT-STREAM
        STREAMS-QUERY-S-OK _SL13A-status
    _SL13A-sink-bytes @
        _SL13A-candidate OCC.CONTENT-U @ 7 - = _SL13A-assert
    _SL13A-sink-calls @ 1 = _SL13A-assert
    _SL13A-sink-errors @ 0= _SL13A-assert

    _SL13A-observation-out SPREC-OBSERVATION-SIZE 0xD8 FILL
    _SL13A-observation SPRO.OBSERVATION-ID
    _SL13A-observation SPRO.REVISION @ 1+
    _SL13A-observation-out SPREC-OBSERVATION-SIZE
    _SL13A-adapter _SL13A-work _SL13A-query-work
        STREAMS-QUERY-OBSERVATION-REVISION@
    DUP STREAMS-QUERY-S-NOT-FOUND = _SL13A-assert
    SWAP 0= _SL13A-assert DROP
    _SL13A-observation-out SPREC-OBSERVATION-SIZE
        _SL13A-zero? _SL13A-assert
    _SL13A-stack ;

: _SL13A-query  ( -- )
    _SL13A-query-init
    _SL13A-query-sources
    _SL13A-query-attempts
    _SL13A-query-observation-revisions
    _SL13A-query-global
    _SL13A-query-source-time
    _SL13A-query-exact-and-content ;

: _SL13A-source-order-range  ( -- )
    STREAMS-PA-RANGE-MAX 32 = _SL13A-assert
    STREAMS-PA-RANGE-ROW-SIZE 2704 = _SL13A-assert
    1 _SL13A-rid-a _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP 1 = _SL13A-assert DROP
    _SL13A-rows STREAMS-PA-RANGE-ROW-VALID? _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-KEY$
        _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        STR-STR= _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-RECORD$
        SPREC-SOURCE-VALID? _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-RECORD$
        DROP SPRS.REVISION @ 1 = _SL13A-assert
    _SL13A-key STREAMS-PI-SOURCE-ORDER-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-LAST
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP 1 = _SL13A-assert DROP
    _SL13A-rows STREAMS-PA-RANGE-ROW-KEY$
        _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        STR-STR= _SL13A-assert

    _SL13A-key STREAMS-PI-SOURCE-ORDER-PREFIX-SIZE
        _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-AFTER
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP 0= _SL13A-assert DROP

    1 _SL13A-authority _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-PREFIX-SIZE
        _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-AFTER
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP 1 = _SL13A-assert DROP

    2 _SL13A-rid-a _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-PREFIX-SIZE
        _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-BEFORE
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP 1 = _SL13A-assert DROP
    _SL13A-rows STREAMS-PA-RANGE-ROW-KEY$
        1 _SL13A-rid-a _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK = _SL13A-assert
    _SL13A-key2 STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        STR-STR= _SL13A-assert

    _SL13A-key STREAMS-PI-SOURCE-RID-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-RID-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    STREAMS-PA-S-INVALID = _SL13A-assert
    0= _SL13A-assert

    _SL13A-rid-a _SL13A-key
        STREAMS-PI-ATTEMPT-BY-SOURCE-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-ATTEMPT-BY-SOURCE-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-VALID? _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-RECORD$
        SPREC-ATTEMPT-VALID? _SL13A-assert
    _SL13A-key STREAMS-PI-ATTEMPT-BY-SOURCE-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-LAST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert

    _SL13A-observation SPRO.OBSERVATION-ID _SL13A-key
        STREAMS-PI-OBSERVATION-REVISION-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-OBSERVATION-REVISION-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-RECORD$
        SPREC-OBSERVATION-VALID? _SL13A-assert
    _SL13A-key STREAMS-PI-OBSERVATION-REVISION-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-LAST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert

    _SL13A-key STREAMS-PI-GLOBAL-TIME-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-GLOBAL-TIME-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-RECORD$
        SPREC-OBSERVATION-VALID? _SL13A-assert
    _SL13A-key STREAMS-PI-GLOBAL-TIME-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-LAST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert

    _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-TIME-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-TIME-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert
    _SL13A-rows STREAMS-PA-RANGE-ROW-RECORD$
        SPREC-OBSERVATION-VALID? _SL13A-assert
    _SL13A-key STREAMS-PI-SOURCE-TIME-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-LAST
    STREAMS-PA-S-OK = _SL13A-assert
    1 = _SL13A-assert

    _SL13A-rid-a _SL13A-authority _SL13A-rid-b _SL13A-key
        STREAMS-PI-THREAD-TIME-PREFIX
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-THREAD-TIME-PREFIX-SIZE
        _SL13A-rows 2 _SL13A-adapter _SL13A-work
        STREAMS-PA-RANGE-FIRST
    STREAMS-PA-S-UNSUPPORTED = _SL13A-assert
    0= _SL13A-assert
    _SL13A-stack ;

: _SL13A-mismatch-rejected  ( -- )
    _SL13A-adapter _SL13A-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-rid-b _SL13A-key STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-CORRUPT _SL13A-status
    _SL13A-adapter _SL13A-work STREAMS-PA-ABORT
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-REOPEN-REQUIRED? _SL13A-assert
    _SL13A-adapter _SL13A-work STREAMS-PA-REBIND
        STREAMS-PA-S-OK _SL13A-status
    1 _SL13A-source-get ;

: _SL13A-staged-replace  ( -- )
    2 _SL13A-source!
    _SL13A-adapter _SL13A-work STREAMS-PA-STAGE-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-source-record SPREC-SOURCE-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-source-keys-staged-put
    _SL13A-adapter _SL13A-work STREAMS-PA-STAGE-COMMIT
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-LOGICAL-GENERATION@ 4 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-MUTATION-SEQUENCE@ 4 =
        _SL13A-assert
    2 _SL13A-source-get ;

: _SL13A-stage-discard  ( -- )
    3 _SL13A-source!
    _SL13A-adapter _SL13A-work STREAMS-PA-STAGE-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-source-record SPREC-SOURCE-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-source-keys-staged-put
    _SL13A-adapter _SL13A-work STREAMS-PA-STAGE-DISCARD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-LOGICAL-GENERATION@ 4 =
        _SL13A-assert
    2 _SL13A-source-get ;

: _SL13A-cardinality-rejected  ( -- )
    _SL13A-adapter _SL13A-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13A-assert
    2 SWAP SAR.SOURCE-COUNT !
    _SL13A-adapter _SL13A-work STREAMS-PA-MARK-MUTATED
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-adapter _SL13A-work STREAMS-PA-COMMIT
        STREAMS-PA-S-CORRUPT _SL13A-status
    _SL13A-work STREAMS-PA-REOPEN-REQUIRED? _SL13A-assert
    _SL13A-adapter _SL13A-work STREAMS-PA-REBIND
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
        SAR.SOURCE-COUNT @ 1 = _SL13A-assert
    2 _SL13A-source-get ;

: _SL13A-source-remove  ( -- )
    _SL13A-source-out 5 _SL13A-tombstone
        SPREC-SOURCE-TOMBSTONE-CONSTRUCT
        SPREC-S-OK _SL13A-status
    _SL13A-adapter _SL13A-work STREAMS-PA-BEGIN
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-tombstone SPREC-SOURCE-TOMBSTONE-SIZE _SL13A-ref
        _SL13A-adapter _SL13A-work STREAMS-PA-APPEND-RECORD
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13A-ref _SL13A-adapter _SL13A-work
        STREAMS-PA-PUT STREAMS-PA-S-OK _SL13A-status
    1 _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13A-adapter _SL13A-work
        STREAMS-PA-DELETE STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13A-assert
    0 OVER SAR.SOURCE-COUNT !
    1 SWAP SAR.REMOVED-SOURCE-COUNT !
    _SL13A-adapter _SL13A-work STREAMS-PA-COMMIT
        STREAMS-PA-S-OK _SL13A-status
    _SL13A-work STREAMS-PA-LOGICAL-GENERATION@ 5 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-MUTATION-SEQUENCE@ 5 =
        _SL13A-assert
    _SL13A-work STREAMS-PA-AUTHORITY-ROOT@
    DUP SAR.SOURCE-COUNT @ 0= _SL13A-assert
    DUP SAR.REMOVED-SOURCE-COUNT @ 1 = _SL13A-assert
    SAR.ACTIVE-COUNT @ 0= _SL13A-assert
    STREAMS-PI-TREE-DIRECTORY _SL13A-work STREAMS-PA-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 1 = _SL13A-assert

    _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13A-tombstone-out SPREC-SOURCE-TOMBSTONE-SIZE
        _SL13A-adapter _SL13A-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13A-assert
    SWAP SPREC-SOURCE-TOMBSTONE-SIZE = _SL13A-assert
    DROP
    _SL13A-tombstone-out SPREC-SOURCE-TOMBSTONE-SIZE
        SPREC-SOURCE-TOMBSTONE-VALID? _SL13A-assert
    _SL13A-tombstone-out SPRT.SOURCE-ID
        _SL13A-rid-a RID= _SL13A-assert

    1 _SL13A-rid-a _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13A-status
    _SL13A-key STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13A-source-out SPREC-SOURCE-SIZE
        _SL13A-adapter _SL13A-work STREAMS-PA-GET
    STREAMS-PA-S-NOT-FOUND = _SL13A-assert
    0= _SL13A-assert
    _SL13A-stack ;

: _SL13A-RUN  ( -- )
    0 _SL13A-checks ! 0 _SL13A-fails !
    DEPTH _SL13A-depth !
    _SL13A-setup
    _SL13A-provision
    _SL13A-visible-create
    _SL13A-blob-reads
    _SL13A-journal
    _SL13A-query
    _SL13A-source-order-range
    _SL13A-mismatch-rejected
    _SL13A-staged-replace
    _SL13A-stage-discard
    _SL13A-cardinality-rejected
    _SL13A-source-remove
    _SL13A-stack
    _SL13A-fails @ IF
        ." STREAMS L13 ADAPTER FAIL "
            _SL13A-fails @ . ." / " _SL13A-checks @ . CR
    ELSE
        ." STREAMS L13 ADAPTER PASS " _SL13A-checks @ . CR
    THEN ;
