\ Focused contracts for the sealed L13 Streams root and canonical keys.

PROVIDED akashic-streams-l13-core-contracts

VARIABLE _SL13C-fails
VARIABLE _SL13C-checks
VARIABLE _SL13C-depth

CREATE _SL13C-root STREAMS-AUTHORITY-ROOT-SIZE ALLOT
CREATE _SL13C-rid-a RID-SIZE ALLOT
CREATE _SL13C-rid-b RID-SIZE ALLOT
CREATE _SL13C-digest-a STREAMS-PI-DIGEST-SIZE ALLOT
CREATE _SL13C-digest-b STREAMS-PI-DIGEST-SIZE ALLOT
CREATE _SL13C-key-a STREAMS-PI-KEY-MAX ALLOT
CREATE _SL13C-key-b STREAMS-PI-KEY-MAX ALLOT

STREAMS-SOURCE-SIZE XBUF _SL13C-source
STREAMS-OBSERVATION-CHECKPOINT-SIZE XBUF _SL13C-checkpoint
OCHK-CANDIDATE-SIZE XBUF _SL13C-candidate
SPREC-SOURCE-SIZE XBUF _SL13C-source-record
SPREC-SOURCE-SIZE XBUF _SL13C-source-copy
SPREC-SOURCE-TOMBSTONE-SIZE XBUF _SL13C-tombstone
SPREC-ATTEMPT-SIZE XBUF _SL13C-attempt-record
SPREC-NATIVE-HEAD-SIZE XBUF _SL13C-native-record
SPREC-OBSERVATION-SIZE XBUF _SL13C-observation-record
SPREC-OBSERVATION-SIZE XBUF _SL13C-observation-copy
PBLOB-SIZE XBUF _SL13C-empty-blob

: _SL13C-assert  ( flag -- )
    1 _SL13C-checks +!
    0= IF
        1 _SL13C-fails +!
        ." STREAMS L13 CORE ASSERT " _SL13C-checks @ . CR
    THEN ;

: _SL13C-stack  ( -- )
    DEPTH DUP _SL13C-depth @ <> IF
        ." STREAMS L13 CORE STACK "
        _SL13C-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13C-depth @ = _SL13C-assert ;

: _SL13C-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 CORE STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13C-assert _SL13C-stack ;

: _SL13C-setup  ( -- )
    _SL13C-rid-a RID-SIZE 0x11 FILL
    _SL13C-rid-b RID-SIZE 0x22 FILL
    _SL13C-digest-a STREAMS-PI-DIGEST-SIZE 0x33 FILL
    _SL13C-digest-b STREAMS-PI-DIGEST-SIZE 0x44 FILL
    _SL13C-key-a STREAMS-PI-KEY-MAX 0 FILL
    _SL13C-key-b STREAMS-PI-KEY-MAX 0 FILL ;

: _SL13C-root-init  ( -- )
    _SL13C-rid-a _SL13C-root
        STREAMS-AUTHORITY-ROOT-TEMPLATE-INIT
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status ;

: _SL13C-authority-basic  ( -- )
    STREAMS-AUTHORITY-ROOT-SIZE PERSIST-PAGE-PAYLOAD-SIZE =
        _SL13C-assert
    STREAMS-AUTHORITY-ROOT-TREE-COUNT 4 = _SL13C-assert
    _SL13C-root-init
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13C-assert
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root SAR.AUTHORITY-ID _SL13C-rid-a RID= _SL13C-assert
    _SL13C-root SAR.SOURCE-COUNT @ 0= _SL13C-assert
    _SL13C-root SAR.REMOVED-SOURCE-COUNT @ 0= _SL13C-assert
    _SL13C-root SAR.ATTEMPT-COUNT @ 0= _SL13C-assert
    _SL13C-root SAR.OBSERVATION-COUNT @ 0= _SL13C-assert
    _SL13C-root SAR.NATIVE-COUNT @ 0= _SL13C-assert
    _SL13C-root SAR.ACTIVE-COUNT @ 0= _SL13C-assert
    _SL13C-root SAR.RECLAIM-STATE RECLAIM-STATE-SIZE
        RECLAIM-STATE-VALID? _SL13C-assert
    0 _SL13C-root STREAMS-AUTHORITY-ROOT-TREE
        DUP 0<> _SL13C-assert
    1 _SL13C-root STREAMS-AUTHORITY-ROOT-TREE
        SWAP - PBTREE-ROOT-SIZE = _SL13C-assert
    -1 _SL13C-root STREAMS-AUTHORITY-ROOT-TREE 0= _SL13C-assert
    4 _SL13C-root STREAMS-AUTHORITY-ROOT-TREE 0= _SL13C-assert
    0 _SL13C-root STREAMS-AUTHORITY-ROOT-TEMPLATE-INIT
        STREAMS-AUTHORITY-ROOT-S-INVALID _SL13C-status
    _SL13C-rid-a _SL13C-rid-a
        STREAMS-AUTHORITY-ROOT-TEMPLATE-INIT
        STREAMS-AUTHORITY-ROOT-S-INVALID _SL13C-status ;

: _SL13C-authority-classification  ( -- )
    _SL13C-root-init
    STREAMS-AUTHORITY-ROOT-ABI 1+ _SL13C-root SAR.ABI !
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-UNSUPPORTED _SL13C-status

    _SL13C-root-init
    1 _SL13C-root SAR.ATTEMPT-COUNT !
    1 _SL13C-root SAR.ACQUISITION-SEQUENCE !
    1 _SL13C-root SAR.SOURCE-COUNT !
    1 _SL13C-root SAR.ACTIVE-COUNT !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13C-assert
    2 _SL13C-root SAR.ACTIVE-COUNT !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status

    _SL13C-root-init
    1 _SL13C-root SAR.OBSERVATION-COUNT !
    2 _SL13C-root SAR.NATIVE-COUNT !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status

    _SL13C-root-init
    -1 _SL13C-root SAR.REMOVED-SOURCE-COUNT !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status

    _SL13C-root-init
    1 _SL13C-root SAR.RESERVED C!
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status

    _SL13C-root-init
    0 _SL13C-root SAR.MAGIC !
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status ;

: _SL13C-authority-legacy-evidence  ( -- )
    _SL13C-root-init
    STREAMS-AUTHORITY-PROVENANCE-LEGACY-SOURCES
        _SL13C-root SAR.PROVENANCE !
    -1 _SL13C-root SAR.LEGACY-SOURCE-PRESENT !
    17 _SL13C-root SAR.LEGACY-SOURCE-BYTES !
    _SL13C-root SAR.LEGACY-SOURCE-DIGEST
        SHA3-256-LEN 0x55 FILL
    STREAMS-AUTHORITY-UNKNOWN-LEGACY-ABSENT
        _SL13C-root SAR.OBSERVATION-COMPLETENESS !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13C-assert

    0 _SL13C-root SAR.LEGACY-SOURCE-BYTES !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status

    _SL13C-root-init
    STREAMS-AUTHORITY-PROVENANCE-LEGACY-OBSERVATIONS
        _SL13C-root SAR.PROVENANCE !
    -1 _SL13C-root SAR.LEGACY-OBSERVATION-PRESENT !
    19 _SL13C-root SAR.LEGACY-OBSERVATION-BYTES !
    _SL13C-root SAR.LEGACY-OBSERVATION-DIGEST
        SHA3-256-LEN 0x66 FILL
    STREAMS-AUTHORITY-UNKNOWN-LEGACY-ABSENT
        _SL13C-root SAR.SOURCE-COMPLETENESS !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13C-assert ;

: _SL13C-authority-complete-empty  ( -- )
    _SL13C-root-init
    STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY
        _SL13C-root SAR.PROVENANCE !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13C-assert

    -1 _SL13C-root SAR.LEGACY-SOURCE-PRESENT !
    17 _SL13C-root SAR.LEGACY-SOURCE-BYTES !
    _SL13C-root SAR.LEGACY-SOURCE-DIGEST SHA3-256-LEN 0x77 FILL
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status

    _SL13C-root-init
    STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY
        _SL13C-root SAR.PROVENANCE !
    STREAMS-AUTHORITY-UNKNOWN-LEGACY-ABSENT
        _SL13C-root SAR.OBSERVATION-COMPLETENESS !
    _SL13C-root STREAMS-AUTHORITY-ROOT-SEAL
        STREAMS-AUTHORITY-ROOT-S-OK _SL13C-status
    _SL13C-root STREAMS-AUTHORITY-ROOT-HEADER-CLASSIFY
        STREAMS-AUTHORITY-ROOT-S-CORRUPT _SL13C-status ;

: _SL13C-u64  ( -- )
    1 _SL13C-key-a STREAMS-PI-POSITIVE-U64-BE!
        STREAMS-PI-S-OK _SL13C-status
    2 _SL13C-key-b STREAMS-PI-POSITIVE-U64-BE!
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-U64-SIZE
        _SL13C-key-b STREAMS-PI-U64-SIZE COMPARE 0< _SL13C-assert
    _SL13C-key-a STREAMS-PI-POSITIVE-U64-BE@
        _SL13C-assert 1 = _SL13C-assert
    0 _SL13C-key-a STREAMS-PI-POSITIVE-U64-BE!
        STREAMS-PI-S-INVALID _SL13C-status ;

: _SL13C-directory-keys  ( -- )
    _SL13C-rid-a _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        STREAMS-PI-SOURCE-RID-KEY-VALID? _SL13C-assert
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        STREAMS-PI-KEY-VALID? _SL13C-assert
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        STREAMS-PI-KEY-FAMILY@
        STREAMS-PI-F-SOURCE-RID = _SL13C-assert
    STREAMS-PI-F-SOURCE-RID STREAMS-PI-FAMILY-TREE
        STREAMS-PI-TREE-DIRECTORY = _SL13C-assert

    7 _SL13C-rid-a _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13C-status
    8 _SL13C-rid-a _SL13C-key-b STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13C-key-b STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        COMPARE 0< _SL13C-assert
    _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        STREAMS-PI-SOURCE-ORDER-KEY-VALID? _SL13C-assert

    _SL13C-rid-a _SL13C-key-a STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        STREAMS-PI-ACTIVE-ATTEMPT-KEY-VALID? _SL13C-assert ;

: _SL13C-attempt-and-observation-keys  ( -- )
    _SL13C-rid-a 3 _SL13C-rid-b _SL13C-key-a
        STREAMS-PI-ATTEMPT-BY-SOURCE-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-VALID? _SL13C-assert
    _SL13C-rid-a _SL13C-key-b
        STREAMS-PI-ATTEMPT-BY-SOURCE-LATEST-BOUNDARY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-b STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        STREAMS-PI-ATTEMPT-BY-SOURCE-LAST-BOUNDARY-VALID?
        _SL13C-assert
    _SL13C-key-b STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        STREAMS-PI-KEY-VALID? 0= _SL13C-assert
    _SL13C-key-a STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        _SL13C-key-b STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        COMPARE 0< _SL13C-assert

    _SL13C-rid-b 4 _SL13C-key-a
        STREAMS-PI-OBSERVATION-REVISION-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-OBSERVATION-REVISION-KEY-SIZE
        STREAMS-PI-OBSERVATION-REVISION-KEY-VALID? _SL13C-assert
    STREAMS-PI-F-OBSERVATION-REVISION STREAMS-PI-FAMILY-TREE
        STREAMS-PI-TREE-IDENTITIES = _SL13C-assert ;

: _SL13C-native-key  ( -- )
    _SL13C-rid-a _SL13C-digest-a 2 3 _SL13C-digest-b 1
        _SL13C-key-a STREAMS-PI-NATIVE-HEAD-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        STREAMS-PI-NATIVE-HEAD-KEY-VALID? _SL13C-assert
    _SL13C-rid-a _SL13C-digest-a 2 3 _SL13C-digest-b
        _SL13C-key-b STREAMS-PI-NATIVE-HEAD-LAST-BOUNDARY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-b STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        STREAMS-PI-NATIVE-HEAD-LAST-BOUNDARY-VALID? _SL13C-assert
    _SL13C-key-a STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        _SL13C-key-b STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        COMPARE 0< _SL13C-assert
    _SL13C-rid-a _SL13C-digest-a 2 3 _SL13C-digest-b 17
        _SL13C-key-a STREAMS-PI-NATIVE-HEAD-KEY
        STREAMS-PI-S-INVALID _SL13C-status ;

: _SL13C-ordering-keys  ( -- )
    9 _SL13C-rid-b 2 _SL13C-key-a STREAMS-PI-GLOBAL-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-GLOBAL-TIME-KEY-SIZE
        STREAMS-PI-GLOBAL-TIME-KEY-VALID? _SL13C-assert

    _SL13C-rid-a 9 _SL13C-rid-b 2 _SL13C-key-a
        STREAMS-PI-SOURCE-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-TIME-KEY-SIZE
        STREAMS-PI-SOURCE-TIME-KEY-VALID? _SL13C-assert

    _SL13C-rid-a _SL13C-digest-a _SL13C-digest-b
        9 _SL13C-rid-b 2 _SL13C-key-a
        STREAMS-PI-THREAD-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-THREAD-TIME-KEY-SIZE
        STREAMS-PI-THREAD-TIME-KEY-VALID? _SL13C-assert
    _SL13C-key-a STREAMS-PI-THREAD-TIME-KEY-SIZE
        STREAMS-PI-KEY-VALID? _SL13C-assert
    STREAMS-PI-F-THREAD-TIME STREAMS-PI-FAMILY-TREE
        STREAMS-PI-TREE-ORDERINGS = _SL13C-assert

    _SL13C-rid-a _SL13C-digest-a _SL13C-digest-b _SL13C-key-b
        STREAMS-PI-THREAD-TIME-LATEST-BOUNDARY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-b STREAMS-PI-THREAD-TIME-KEY-SIZE
        STREAMS-PI-THREAD-TIME-LAST-BOUNDARY-VALID? _SL13C-assert
    _SL13C-key-a STREAMS-PI-THREAD-TIME-KEY-SIZE
        _SL13C-key-b STREAMS-PI-THREAD-TIME-KEY-SIZE
        COMPARE 0< _SL13C-assert ;

: _SL13C-key-rejection-is-atomic  ( -- )
    _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY-SIZE 0xA5 FILL
    _SL13C-key-b STREAMS-PI-SOURCE-ORDER-KEY-SIZE 0xA5 FILL
    0 _SL13C-rid-a _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-INVALID _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13C-key-b STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        COMPARE 0= _SL13C-assert
    _SL13C-rid-a _SL13C-rid-a STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-INVALID _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-RID-PREFIX
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-RID-PREFIX-SIZE
        STREAMS-PI-KEY-FAMILY@ 0= _SL13C-assert
    0 STREAMS-PI-FAMILY-TREE -1 = _SL13C-assert ;

: _SL13C-source-value!  ( -- )
    _SL13C-source STREAMS-SOURCE-INIT
    _SL13C-rid-a _SL13C-source STREAMS-SOURCE-ID!
        SSREG-S-OK _SL13C-status
    1 _SL13C-source SSOURCE.REVISION !
    SSOURCE-KIND-SYNDICATION _SL13C-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _SL13C-source SSOURCE.FORMAT !
    S" L13 exact source" _SL13C-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13C-status
    S" https://example.test/l13.json"
        _SL13C-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13C-status
    _SL13C-source STREAMS-SOURCE-VALID? _SL13C-assert ;

: _SL13C-record-source  ( -- )
    _SL13C-source-value!
    _SL13C-source 7 _SL13C-source-record SPREC-SOURCE-CONSTRUCT
        SPREC-S-OK _SL13C-status
    _SL13C-source-record SPREC-SOURCE-SIZE
        SPREC-SOURCE-VALID? _SL13C-assert
    _SL13C-source-record SPREC-SOURCE-SIZE
        SPREC-VALID? _SL13C-assert
    _SL13C-source-record SPRS.CREATION-SEQUENCE @ 7 =
        _SL13C-assert
    _SL13C-source-record SPRS.OBSERVATION-COUNT @ 0=
        _SL13C-assert
    _SL13C-source-record SPRS.SOURCE STREAMS-SOURCE-SIZE
        _SL13C-source STREAMS-SOURCE-SIZE COMPARE 0= _SL13C-assert
    3 _SL13C-source-record SPRS.OBSERVATION-COUNT !
    _SL13C-source-record SPREC-SOURCE-SIZE
        SPREC-SOURCE-VALID? 0= _SL13C-assert
    _SL13C-source-record SPREC-SOURCE-SEAL!
        SPREC-S-OK _SL13C-status
    _SL13C-source-record SPRS.OBSERVATION-COUNT @ 3 =
        _SL13C-assert
    _SL13C-source-record SPREC-SOURCE-SIZE
        SPREC-SOURCE-VALID? _SL13C-assert
    _SL13C-source-record _SL13C-source-copy SPREC-SOURCE-COPY
        SPREC-S-OK _SL13C-status
    _SL13C-source-record SPREC-SOURCE-SIZE
        _SL13C-source-copy SPREC-SOURCE-SIZE COMPARE 0= _SL13C-assert
    8 _SL13C-source-copy SPRS.CREATION-SEQUENCE !
    _SL13C-source-copy SPREC-SOURCE-SIZE
        SPREC-SOURCE-VALID? 0= _SL13C-assert ;

: _SL13C-record-tombstone  ( -- )
    _SL13C-source-record 9 _SL13C-tombstone
        SPREC-SOURCE-TOMBSTONE-CONSTRUCT
        SPREC-S-OK _SL13C-status
    _SL13C-tombstone SPREC-SOURCE-TOMBSTONE-SIZE
        SPREC-SOURCE-TOMBSTONE-VALID? _SL13C-assert
    _SL13C-tombstone SPREC-SOURCE-TOMBSTONE-SIZE
        SPREC-VALID? _SL13C-assert
    _SL13C-tombstone SPRT.SOURCE-ID
        _SL13C-source-record SPRS.ID RID= _SL13C-assert
    _SL13C-tombstone SPRT.CREATION-SEQUENCE @ 7 =
        _SL13C-assert
    _SL13C-tombstone SPRT.SOURCE-REVISION @ 1 =
        _SL13C-assert
    _SL13C-tombstone SPRT.REMOVAL-SEQUENCE @ 9 =
        _SL13C-assert
    _SL13C-tombstone SPRT.SOURCE-SEAL
        _SL13C-source-record SPREC.SEAL RID= _SL13C-assert
    _SL13C-tombstone _SL13C-key-a
        SPREC-SOURCE-TOMBSTONE-SIZE MOVE
    _SL13C-source-record 7 _SL13C-tombstone
        SPREC-SOURCE-TOMBSTONE-CONSTRUCT
        SPREC-S-INVALID _SL13C-status
    _SL13C-tombstone SPREC-SOURCE-TOMBSTONE-SIZE
        _SL13C-key-a SPREC-SOURCE-TOMBSTONE-SIZE
        COMPARE 0= _SL13C-assert ;

: _SL13C-candidate!  ( -- )
    _SL13C-candidate OCHK-CANDIDATE-INIT
    SSOURCE-FORMAT-JSON-FEED _SL13C-candidate OCC.FORMAT !
    OCHK-NATIVE-PROVIDER-ID _SL13C-candidate OCC.NATIVE-KIND !
    S" l13-native"
        _SL13C-candidate OCC.NATIVE-U !
        _SL13C-candidate OCC.NATIVE-A !
    S" L13 observation"
        _SL13C-candidate OCC.TITLE-U !
        _SL13C-candidate OCC.TITLE-A !
    S" https://example.test/item/l13"
        _SL13C-candidate OCC.URL-U !
        _SL13C-candidate OCC.URL-A !
    S" Bounded stream summary"
        _SL13C-candidate OCC.SUMMARY-U !
        _SL13C-candidate OCC.SUMMARY-A !
    0 _SL13C-candidate OCC.CONTENT-U !
    0 _SL13C-candidate OCC.CONTENT-A !
    S" 2026-07-24T12:00:00Z"
        _SL13C-candidate OCC.PUBLISHED-U !
        _SL13C-candidate OCC.PUBLISHED-A !
    _SL13C-candidate SPREC-CANDIDATE-VALID? _SL13C-assert ;

: _SL13C-empty-blob!  ( -- )
    _SL13C-empty-blob PBLOB-SIZE 0 FILL
    _PBLOB-MAGIC _SL13C-empty-blob _PBL.MAGIC !
    -1 _SL13C-empty-blob _PBL.LEVEL !
    _SL13C-empty-blob PBLOB-VALID? _SL13C-assert ;

: _SL13C-attempt-head  ( -- head )
    _SL13C-rid-a _SL13C-checkpoint OCHK-SOURCE-FIND ;

: _SL13C-record-attempt  ( -- )
    _SL13C-checkpoint OCHK-INIT
    _SL13C-rid-a 1 _SL13C-digest-a 1
        S" https://example.test/l13.json" _SL13C-checkpoint
        OCHK-BEGIN OCHK-S-OK _SL13C-status
    _SL13C-attempt-head DUP 0<> _SL13C-assert
    _SL13C-attempt-record SPREC-ATTEMPT-CONSTRUCT
        SPREC-S-OK _SL13C-status
    _SL13C-attempt-record SPREC-ATTEMPT-SIZE
        SPREC-ATTEMPT-VALID? _SL13C-assert
    _SL13C-attempt-record SPRA.STATE @
        OCHK-ATTEMPT-ACCEPTED = _SL13C-assert
    _SL13C-attempt-record SPRA.ATTEMPT-ID
        _SL13C-attempt-head OCS.ATTEMPT-ID RID= _SL13C-assert
    _SL13C-attempt-record SPRA.REQUEST-SEAL
        _SL13C-attempt-head OCS.REQUEST-SEAL RID= _SL13C-assert

    1 _SL13C-attempt-record SPRA.DETAIL !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-INVALID _SL13C-status
    0 _SL13C-attempt-record SPRA.DETAIL !

    OCHK-ATTEMPT-FAILED _SL13C-attempt-record SPRA.STATE !
    OCHK-O-TRANSPORT _SL13C-attempt-record SPRA.OUTCOME !
    10 _SL13C-attempt-record SPRA.STARTED-MS !
    9 _SL13C-attempt-record SPRA.FINISHED-MS !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-INVALID _SL13C-status
    10 _SL13C-attempt-record SPRA.FINISHED-MS !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-OK _SL13C-status

    OCHK-ATTEMPT-CANCELLED _SL13C-attempt-record SPRA.STATE !
    OCHK-O-TRANSPORT _SL13C-attempt-record SPRA.OUTCOME !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-INVALID _SL13C-status
    OCHK-O-CANCELLED _SL13C-attempt-record SPRA.OUTCOME !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-OK _SL13C-status

    OCHK-ATTEMPT-ACCEPTED _SL13C-attempt-record SPRA.STATE !
    OCHK-O-NONE _SL13C-attempt-record SPRA.OUTCOME !
    0 _SL13C-attempt-record SPRA.STARTED-MS !
    0 _SL13C-attempt-record SPRA.FINISHED-MS !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-OK _SL13C-status ;

: _SL13C-record-native  ( -- )
    _SL13C-attempt-head _SL13C-candidate _SL13C-rid-b
        _OCHK-DERIVE-OBS-ID
    _SL13C-native-record SPREC-NATIVE-INIT
        SPREC-S-OK _SL13C-status
    _SL13C-rid-a _SL13C-native-record SPRH.SOURCE-ID RID-COPY
    _SL13C-digest-a _SL13C-native-record SPRH.NAMESPACE RID-COPY
    1 _SL13C-native-record SPRH.LATEST-REVISION !
    1 _SL13C-native-record SPRH.LAST-SEEN-SEQUENCE !
    1 _SL13C-native-record SPRH.COLLISION-ORDINAL !
    _SL13C-candidate _SL13C-native-record SPREC-NATIVE-CANDIDATE!
        SPREC-S-OK _SL13C-status
    _SL13C-native-record SPREC-NATIVE-HEAD-SIZE
        SPREC-NATIVE-VALID? _SL13C-assert
    _SL13C-native-record SPRH.OBSERVATION-ID
        _SL13C-rid-b RID= _SL13C-assert
    _SL13C-native-record SPRH-NATIVE$
        S" l13-native" STR-STR= _SL13C-assert
    17 _SL13C-native-record SPRH.COLLISION-ORDINAL !
    _SL13C-native-record SPREC-NATIVE-SEAL!
        SPREC-S-INVALID _SL13C-status
    1 _SL13C-native-record SPRH.COLLISION-ORDINAL !
    2 _SL13C-native-record SPRH.LATEST-REVISION !
    _SL13C-native-record SPREC-NATIVE-SEAL!
        SPREC-S-INVALID _SL13C-status
    1 _SL13C-native-record SPRH.LATEST-REVISION !
    _SL13C-native-record SPREC-NATIVE-SEAL!
        SPREC-S-OK _SL13C-status
    _SL13C-native-record _SL13C-observation-copy
        SPREC-NATIVE-HEAD-SIZE MOVE
    _SL13C-candidate _SL13C-native-record SPREC-NATIVE-CANDIDATE!
        SPREC-S-INVALID _SL13C-status
    _SL13C-native-record SPREC-NATIVE-HEAD-SIZE
        _SL13C-observation-copy SPREC-NATIVE-HEAD-SIZE
        COMPARE 0= _SL13C-assert ;

: _SL13C-record-observation  ( -- )
    _SL13C-empty-blob!
    _SL13C-observation-record SPREC-OBSERVATION-INIT
        SPREC-S-OK _SL13C-status
    _SL13C-rid-b _SL13C-observation-record
        SPRO.OBSERVATION-ID RID-COPY
    _SL13C-rid-a _SL13C-observation-record SPRO.SOURCE-ID RID-COPY
    _SL13C-digest-a _SL13C-observation-record SPRO.NAMESPACE RID-COPY
    _SL13C-attempt-head OCS.ATTEMPT-ID
        _SL13C-observation-record SPRO.ATTEMPT-ID RID-COPY
    1 _SL13C-observation-record SPRO.ACQUISITION-SEQUENCE !
    1 _SL13C-observation-record SPRO.REVISION !
    _SL13C-candidate _SL13C-empty-blob _SL13C-observation-record
        SPREC-OBSERVATION-CANDIDATE!
        SPREC-S-OK _SL13C-status
    _SL13C-observation-record SPREC-OBSERVATION-SIZE
        SPREC-OBSERVATION-VALID? _SL13C-assert
    _SL13C-observation-record SPRO.CONTENT PBLOB-VALID? _SL13C-assert
    _SL13C-observation-record SPRO.CONTENT-U @ 0= _SL13C-assert
    _SL13C-observation-record SPRO-TITLE$
        S" L13 observation" STR-STR= _SL13C-assert
    _SL13C-candidate _SL13C-digest-b _OCHK-SEMANTIC-DIGEST!
    _SL13C-observation-record SPRO.SEMANTIC-DIGEST
        _SL13C-digest-b RID= _SL13C-assert
    2 _SL13C-observation-record SPRO.REVISION !
    _SL13C-observation-record SPREC-OBSERVATION-SEAL!
        SPREC-S-INVALID _SL13C-status
    1 _SL13C-observation-record SPRO.REVISION !
    _SL13C-observation-record SPREC-OBSERVATION-SEAL!
        SPREC-S-OK _SL13C-status

    _SL13C-observation-record _SL13C-observation-copy
        SPREC-OBSERVATION-COPY SPREC-S-OK _SL13C-status
    _SL13C-observation-record SPRO.OBSERVATION-ID C@
        0xFF XOR _SL13C-observation-record SPRO.OBSERVATION-ID C!
    _SL13C-observation-record _SL13C-source-copy
        SPREC-OBSERVATION-SIZE MOVE
    _SL13C-candidate _SL13C-empty-blob _SL13C-observation-record
        SPREC-OBSERVATION-CANDIDATE!
        SPREC-S-INVALID _SL13C-status
    _SL13C-observation-record SPREC-OBSERVATION-SIZE
        _SL13C-source-copy SPREC-OBSERVATION-SIZE
        COMPARE 0= _SL13C-assert
    _SL13C-observation-copy _SL13C-observation-record
        SPREC-OBSERVATION-SIZE MOVE
    _SL13C-candidate _SL13C-empty-blob _SL13C-observation-record
        SPREC-OBSERVATION-CANDIDATE!
        SPREC-S-INVALID _SL13C-status
    _SL13C-observation-record SPREC-OBSERVATION-SIZE
        _SL13C-observation-copy SPREC-OBSERVATION-SIZE
        COMPARE 0= _SL13C-assert ;

: _SL13C-records  ( -- )
    STREAMS-PERSISTENCE-RECORD-MAX SPREC-OBSERVATION-SIZE =
        _SL13C-assert
    SPREC-OBSERVATION-SIZE PERSIST-PAGE-PAYLOAD-SIZE <=
        _SL13C-assert
    STREAMS-SOURCE-OBSERVATION-DEFAULT 16 = _SL13C-assert
    STREAMS-SOURCE-REVISION-DEFAULT 4 = _SL13C-assert
    STREAMS-SOURCE-OBSERVATION-MAX 10000000 = _SL13C-assert
    STREAMS-SOURCE-REVISION-MAX 10000000 = _SL13C-assert
    SPREC-NATIVE-COLLISION-MAX
        STREAMS-PI-NATIVE-COLLISION-MAX = _SL13C-assert
    _SL13C-record-source
    _SL13C-record-tombstone
    _SL13C-candidate!
    _SL13C-record-attempt
    _SL13C-record-native
    _SL13C-record-observation ;

: _SL13C-record-safety  ( -- )
    0 STREAMS-SOURCE-VALID? 0= _SL13C-assert
    0 SPREC-SOURCE-INIT SPREC-S-INVALID _SL13C-status
    _SL13C-source 7 0 SPREC-SOURCE-CONSTRUCT
        SPREC-S-INVALID _SL13C-status
    _SL13C-candidate 0 SPREC-CANDIDATE-SEMANTIC-DIGEST!
        SPREC-S-INVALID _SL13C-status
    _SL13C-source-record SPREC-SOURCE-SIZE 0 SPREC-COPY
        SPREC-S-INVALID _SL13C-status
    0 _SL13C-empty-blob _SL13C-observation-record
        SPREC-OBSERVATION-CONTENT!
        SPREC-S-INVALID _SL13C-status
    _SL13C-digest-a _SL13C-observation-record SPRO.CONTENT
        _SL13C-observation-record SPREC-OBSERVATION-CONTENT!
        SPREC-S-INVALID _SL13C-status
    _SL13C-observation-record SPREC-OBSERVATION-SIZE
        SPREC-OBSERVATION-VALID? _SL13C-assert ;

: _SL13C-index-record-agreement  ( -- )
    _SL13C-rid-a _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13C-source-record SPREC-SOURCE-SIZE
        STREAMS-PI-SOURCE-RID-RECORD-AGREES? _SL13C-assert
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13C-source-record SPREC-SOURCE-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13C-tombstone SPREC-SOURCE-TOMBSTONE-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert

    7 _SL13C-rid-a _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13C-source-record SPREC-SOURCE-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert
    _SL13C-key-a STREAMS-PI-SOURCE-ORDER-KEY-SIZE
        _SL13C-tombstone SPREC-SOURCE-TOMBSTONE-SIZE
        STREAMS-PI-RECORD-AGREES? 0= _SL13C-assert

    _SL13C-rid-a _SL13C-key-a STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
        _SL13C-attempt-record SPREC-ATTEMPT-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert

    _SL13C-rid-a
        _SL13C-attempt-record SPRA.ATTEMPT-SEQUENCE @
        _SL13C-attempt-record SPRA.ATTEMPT-ID
        _SL13C-key-a STREAMS-PI-ATTEMPT-BY-SOURCE-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
        _SL13C-attempt-record SPREC-ATTEMPT-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert

    _SL13C-native-record SPRH.SOURCE-ID
        _SL13C-native-record SPRH.NAMESPACE
        _SL13C-native-record SPRH.OBSERVATION-FORMAT @
        _SL13C-native-record SPRH.NATIVE-KIND @
        _SL13C-native-record SPRH.NATIVE-DIGEST
        _SL13C-native-record SPRH.COLLISION-ORDINAL @
        _SL13C-key-a STREAMS-PI-NATIVE-HEAD-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        _SL13C-native-record SPREC-NATIVE-HEAD-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert

    _SL13C-observation-record SPRO.OBSERVATION-ID
        _SL13C-observation-record SPRO.REVISION @
        _SL13C-key-a STREAMS-PI-OBSERVATION-REVISION-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-OBSERVATION-REVISION-KEY-SIZE
        _SL13C-observation-record SPREC-OBSERVATION-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert

    _SL13C-observation-record SPRO.ACQUISITION-SEQUENCE @
        _SL13C-observation-record SPRO.OBSERVATION-ID
        _SL13C-observation-record SPRO.REVISION @
        _SL13C-key-a STREAMS-PI-GLOBAL-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-GLOBAL-TIME-KEY-SIZE
        _SL13C-observation-record SPREC-OBSERVATION-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert

    _SL13C-observation-record SPRO.SOURCE-ID
        _SL13C-observation-record SPRO.ACQUISITION-SEQUENCE @
        _SL13C-observation-record SPRO.OBSERVATION-ID
        _SL13C-observation-record SPRO.REVISION @
        _SL13C-key-a STREAMS-PI-SOURCE-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-TIME-KEY-SIZE
        _SL13C-observation-record SPREC-OBSERVATION-SIZE
        STREAMS-PI-RECORD-AGREES? _SL13C-assert

    _SL13C-rid-a _SL13C-digest-a _SL13C-digest-b
        1 _SL13C-rid-b 1 _SL13C-key-a
        STREAMS-PI-THREAD-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-THREAD-TIME-KEY-SIZE
        _SL13C-observation-record SPREC-OBSERVATION-SIZE
        STREAMS-PI-RECORD-AGREES? 0= _SL13C-assert

    _SL13C-rid-b _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13C-source-record SPREC-SOURCE-SIZE
        STREAMS-PI-RECORD-AGREES? 0= _SL13C-assert
    _SL13C-rid-a _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13C-status
    _SL13C-key-a STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13C-source-copy SPREC-SOURCE-SIZE
        STREAMS-PI-RECORD-AGREES? 0= _SL13C-assert ;

: _SL13C-semantic-record-agreement  ( -- )
    _SL13C-observation-record _SL13C-attempt-record
        STREAMS-SRA-OBSERVATION-ATTEMPT-AGREES?
        0= _SL13C-assert
    _SL13C-observation-record _SL13C-native-record
        STREAMS-SRA-OBSERVATION-NATIVE-HEAD-AGREES?
        _SL13C-assert
    _SL13C-observation-record _SL13C-native-record
        STREAMS-SRA-OBSERVATION-CURRENT-HEAD-AGREES?
        _SL13C-assert
    _SL13C-observation-record _SL13C-attempt-record
        _SL13C-native-record
        STREAMS-SRA-OBSERVATION-PUBLICATION-AGREES?
        0= _SL13C-assert

    OCHK-ATTEMPT-SUCCEEDED _SL13C-attempt-record SPRA.STATE !
    OCHK-O-OK _SL13C-attempt-record SPRA.OUTCOME !
    10 _SL13C-attempt-record SPRA.STARTED-MS !
    11 _SL13C-attempt-record SPRA.FINISHED-MS !
    1 _SL13C-attempt-record SPRA.UNCHANGED-COUNT !
    S" https://example.test/l13.json"
        DUP _SL13C-attempt-record SPRA.EFFECTIVE-U !
        _SL13C-attempt-record SPRA.EFFECTIVE SWAP MOVE
    1 _SL13C-attempt-record SPRA.REJECTED-COUNT !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-INVALID _SL13C-status
    0 _SL13C-attempt-record SPRA.REJECTED-COUNT !
    -701 _SL13C-attempt-record SPRA.CLEANUP-ERROR !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-INVALID _SL13C-status
    0 _SL13C-attempt-record SPRA.CLEANUP-ERROR !
    _SL13C-attempt-record SPREC-ATTEMPT-SEAL!
        SPREC-S-OK _SL13C-status
    _SL13C-observation-record _SL13C-attempt-record
        STREAMS-SRA-OBSERVATION-ATTEMPT-AGREES?
        _SL13C-assert
    _SL13C-observation-record _SL13C-attempt-record
        _SL13C-native-record
        STREAMS-SRA-OBSERVATION-PUBLICATION-AGREES?
        _SL13C-assert

    _SL13C-observation-record _SL13C-observation-copy
        SPREC-OBSERVATION-COPY SPREC-S-OK _SL13C-status
    2 _SL13C-observation-record SPRO.ACQUISITION-SEQUENCE !
    _SL13C-observation-record SPREC-OBSERVATION-SEAL!
        SPREC-S-OK _SL13C-status
    _SL13C-observation-record _SL13C-native-record
        STREAMS-SRA-OBSERVATION-NATIVE-HEAD-AGREES?
        0= _SL13C-assert
    _SL13C-observation-record _SL13C-attempt-record
        STREAMS-SRA-OBSERVATION-ATTEMPT-AGREES?
        0= _SL13C-assert
    _SL13C-observation-copy _SL13C-observation-record
        SPREC-OBSERVATION-SIZE MOVE

    2 _SL13C-native-record SPRH.LATEST-REVISION !
    2 _SL13C-native-record SPRH.LAST-SEEN-SEQUENCE !
    _SL13C-native-record SPREC-NATIVE-SEAL!
        SPREC-S-OK _SL13C-status
    _SL13C-observation-record _SL13C-native-record
        STREAMS-SRA-OBSERVATION-NATIVE-HEAD-AGREES?
        _SL13C-assert
    _SL13C-observation-record _SL13C-native-record
        STREAMS-SRA-OBSERVATION-CURRENT-HEAD-AGREES?
        0= _SL13C-assert
    _SL13C-observation-record _SL13C-attempt-record
        _SL13C-native-record
        STREAMS-SRA-OBSERVATION-PUBLICATION-AGREES?
        0= _SL13C-assert
    1 _SL13C-native-record SPRH.LATEST-REVISION !
    1 _SL13C-native-record SPRH.LAST-SEEN-SEQUENCE !
    _SL13C-native-record SPREC-NATIVE-SEAL!
        SPREC-S-OK _SL13C-status

    2 _SL13C-native-record SPRH.LAST-SEEN-SEQUENCE !
    _SL13C-native-record SPREC-NATIVE-SEAL!
        SPREC-S-OK _SL13C-status
    _SL13C-observation-record _SL13C-native-record
        STREAMS-SRA-OBSERVATION-CURRENT-HEAD-AGREES?
        _SL13C-assert
    _SL13C-observation-record _SL13C-attempt-record
        _SL13C-native-record
        STREAMS-SRA-OBSERVATION-PUBLICATION-AGREES?
        0= _SL13C-assert
    1 _SL13C-native-record SPRH.LAST-SEEN-SEQUENCE !
    _SL13C-native-record SPREC-NATIVE-SEAL!
        SPREC-S-OK _SL13C-status ;

: _SL13C-RUN  ( -- )
    0 _SL13C-fails ! 0 _SL13C-checks !
    DEPTH _SL13C-depth !
    _SL13C-setup
    _SL13C-authority-basic
    _SL13C-authority-classification
    _SL13C-authority-legacy-evidence
    _SL13C-authority-complete-empty
    _SL13C-u64
    _SL13C-directory-keys
    _SL13C-attempt-and-observation-keys
    _SL13C-native-key
    _SL13C-ordering-keys
    _SL13C-key-rejection-is-atomic
    _SL13C-records
    _SL13C-record-safety
    _SL13C-index-record-agreement
    _SL13C-semantic-record-agreement
    _SL13C-stack
    _SL13C-fails @ IF
        ." STREAMS L13 CORE FAIL "
            _SL13C-fails @ . ." / " _SL13C-checks @ . CR
    ELSE
        ." STREAMS L13 CORE PASS " _SL13C-checks @ . CR
    THEN ;
