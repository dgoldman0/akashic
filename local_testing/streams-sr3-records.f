\ streams-sr3-records.f - deterministic SR3 record and ordered-index contracts

PROVIDED akashic-streams-sr3-record-contracts

VARIABLE _sr3q-fails
VARIABLE _sr3q-checks
VARIABLE _sr3q-depth

: _sr3q-assert  ( flag -- )
    1 _sr3q-checks +!
    0= IF
        1 _sr3q-fails +!
        ." STREAMS SR3 RECORDS ASSERT " _sr3q-checks @ . CR
    THEN ;

: _sr3q-stack  ( -- )
    DEPTH DUP _sr3q-depth @ <> IF
        ." STREAMS SR3 RECORDS STACK "
        _sr3q-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr3q-depth @ = _sr3q-assert ;

: _sr3q-filled?  ( address length byte -- flag )
    SWAP
    0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

CREATE _sr3q-rid-a RID-SIZE ALLOT
CREATE _sr3q-rid-b RID-SIZE ALLOT
CREATE _sr3q-rid-c RID-SIZE ALLOT
CREATE _sr3q-rid-d RID-SIZE ALLOT
CREATE _sr3q-rid-e RID-SIZE ALLOT
CREATE _sr3q-rid-f RID-SIZE ALLOT
CREATE _sr3q-rid-g RID-SIZE ALLOT
CREATE _sr3q-rid-h RID-SIZE ALLOT
CREATE _sr3q-rid-zero RID-SIZE ALLOT
CREATE _sr3q-seal-a STREAMS-OI-REQUEST-SEAL-SIZE ALLOT
CREATE _sr3q-seal-b STREAMS-OI-REQUEST-SEAL-SIZE ALLOT
CREATE _sr3q-digest-a SHA3-256-LEN ALLOT

CREATE _sr3q-be-a STREAMS-OI-ORDER-SIZE ALLOT
CREATE _sr3q-be-b STREAMS-OI-ORDER-SIZE ALLOT
CREATE _sr3q-key-a PBTREE-KEY-MAX ALLOT
CREATE _sr3q-key-b PBTREE-KEY-MAX ALLOT
CREATE _sr3q-key-snapshot PBTREE-KEY-MAX ALLOT
CREATE _sr3q-alias-key PBTREE-KEY-MAX ALLOT
CREATE _sr3q-row STREAMS-OI-ROW-VALUE-SIZE ALLOT
CREATE _sr3q-ref PERSIST-REF-SIZE ALLOT
CREATE _sr3q-ref-snapshot PERSIST-REF-SIZE ALLOT
CREATE _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE ALLOT
CREATE _sr3q-connector-usage PBTREE-VALUE-MAX ALLOT
CREATE _sr3q-flow-usage PBTREE-VALUE-MAX ALLOT
CREATE _sr3q-value-snapshot PBTREE-VALUE-MAX ALLOT
CREATE _sr3q-alias-value PBTREE-VALUE-MAX ALLOT

CREATE _sr3q-attempt-a STREAMS-OPATT-SIZE ALLOT
CREATE _sr3q-attempt-b STREAMS-OPATT-SIZE ALLOT
CREATE _sr3q-attempt-c STREAMS-OPATT-SIZE ALLOT
CREATE _sr3q-receipt-a STREAMS-OPRECEIPT-SIZE ALLOT
CREATE _sr3q-receipt-b STREAMS-OPRECEIPT-SIZE ALLOT
CREATE _sr3q-receipt-c STREAMS-OPRECEIPT-SIZE ALLOT
CREATE _sr3q-root-a STREAMS-OPROOT-SIZE ALLOT
CREATE _sr3q-root-b STREAMS-OPROOT-SIZE 16 + ALLOT
CREATE _sr3q-root-c STREAMS-OPROOT-SIZE ALLOT

: _sr3q-setup-identities  ( -- )
    _sr3q-rid-a RID-SIZE 0x11 FILL
    _sr3q-rid-b RID-SIZE 0x22 FILL
    _sr3q-rid-c RID-SIZE 0x33 FILL
    _sr3q-rid-d RID-SIZE 0x44 FILL
    _sr3q-rid-e RID-SIZE 0x55 FILL
    _sr3q-rid-f RID-SIZE 0x66 FILL
    _sr3q-rid-g RID-SIZE 0x77 FILL
    _sr3q-rid-h RID-SIZE 0x88 FILL
    _sr3q-rid-zero RID-CLEAR
    _sr3q-seal-a STREAMS-OI-REQUEST-SEAL-SIZE 0xA1 FILL
    _sr3q-seal-b STREAMS-OI-REQUEST-SEAL-SIZE 0xB2 FILL
    _sr3q-digest-a SHA3-256-LEN 0xC3 FILL ;

: _sr3q-setup-ref  ( -- )
    _sr3q-ref PERSIST-REF-INIT
    128 _sr3q-ref PREF.OFFSET !
    96 _sr3q-ref PREF.SPAN !
    3 _sr3q-ref PREF.ORDINAL ! ;

: _sr3q-empty-blob!  ( blob -- )
    DUP PBLOB-SIZE 0 FILL
    _PBLOB-MAGIC OVER _PBL.MAGIC !
    -1 SWAP _PBL.LEVEL ! ;

: _sr3q-small-blob!  ( total-bytes blob -- )
    >R
    R@ PBLOB-SIZE 0 FILL
    _PBLOB-MAGIC R@ _PBL.MAGIC !
    DUP R@ _PBL.TOTAL !
    DUP _PBLOB-CHUNKS R@ _PBL.CHUNKS !
    0 R@ _PBL.LEVEL !
    _sr3q-setup-ref
    _sr3q-ref R@ _PBL.ROOT PERSIST-REF-COPY
    DROP R> DROP ;

: _sr3q-valid-attempt!  ( attempt -- )
    >R
    R@ STREAMS-OPATT-INIT
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-rid-a R@ SOPATT.ATTEMPT-ID RID-COPY
    _sr3q-rid-b R@ SOPATT.EVENT-ID RID-COPY
    _sr3q-rid-c R@ SOPATT.CONNECTOR-ID RID-COPY
    _sr3q-rid-d R@ SOPATT.FLOW-ID RID-COPY
    _sr3q-rid-e R@ SOPATT.CORRELATION-ID RID-COPY
    _sr3q-rid-f R@ SOPATT.IDEMPOTENCY-ID RID-COPY
    _sr3q-rid-g R@ SOPATT.ORIGIN-ID RID-COPY
    _sr3q-rid-h R@ SOPATT.DESTINATION-ID RID-COPY
    _sr3q-seal-a R@ SOPATT.REQUEST-SEAL RID-COPY
    _sr3q-seal-b R@ SOPATT.ENDPOINT-SEAL RID-COPY
    _sr3q-digest-a R@ SOPATT.PAYLOAD-DIGEST RID-COPY
    1 R@ SOPATT.CONNECTOR-REVISION !
    2 R@ SOPATT.FLOW-REVISION !
    3 R@ SOPATT.RECORD-REVISION !
    7 R@ SOPATT.ACCEPTED-SEQUENCE !
    8 R@ SOPATT.READY-SEQUENCE !
    101 R@ SOPATT.PROTOCOL !
    102 R@ SOPATT.PROFILE !
    202 R@ SOPATT.MEDIA !
    1000 R@ SOPATT.RECEIVED-MS !
    1001 R@ SOPATT.ACCEPTED-MS !
    STREAMS-OPATT-IDEMPOTENCY-EXACT
        R@ SOPATT.IDEMPOTENCY-POLICY !
    STREAMS-OPATT-RECEIPT-BOUNDED R@ SOPATT.RECEIPT-POLICY !
    512 R@ SOPATT.RECEIPT-BYTE-LIMIT !
    R@ SOPATT.PAYLOAD-BLOB _sr3q-empty-blob!
    R@ STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    R> DROP ;

: _sr3q-valid-receipt!  ( receipt -- )
    >R
    R@ STREAMS-OPRECEIPT-INIT
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-rid-b R@ SOPRECEIPT.RECEIPT-ID RID-COPY
    _sr3q-rid-a R@ SOPRECEIPT.ATTEMPT-ID RID-COPY
    _sr3q-seal-a R@ SOPRECEIPT.REQUEST-SEAL RID-COPY
    _sr3q-digest-a R@ SOPRECEIPT.PAYLOAD-DIGEST RID-COPY
    _sr3q-rid-c R@ SOPRECEIPT.CONNECTOR-ID RID-COPY
    _sr3q-rid-d R@ SOPRECEIPT.FLOW-ID RID-COPY
    _sr3q-rid-e R@ SOPRECEIPT.ACKNOWLEDGEMENT-ID RID-COPY
    1 R@ SOPRECEIPT.CONNECTOR-REVISION !
    2 R@ SOPRECEIPT.FLOW-REVISION !
    101 R@ SOPRECEIPT.PROTOCOL !
    102 R@ SOPRECEIPT.PROFILE !
    1002 R@ SOPRECEIPT.ACKNOWLEDGED-MS !
    200 R@ SOPRECEIPT.RESULT !
    R@ STREAMS-OPRECEIPT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    R> DROP ;

: _sr3q-root-trees!  ( root -- )
    STREAMS-OPROOT-TREE-COUNT 0 ?DO
        I OVER STREAMS-OPROOT-TREE
        PBTREE-ROOT-SIZE I 1+ FILL
    LOOP
    DROP ;

: _sr3q-valid-root!  ( root -- )
    >R
    _sr3q-rid-h 8 1024 4 60000 R@
        STREAMS-OPROOT-TEMPLATE-INIT
        STREAMS-OPREC-S-OK = _sr3q-assert
    1 R@ SOPROOT.LOGICAL-GENERATION !
    R@ _sr3q-root-trees!
    R@ STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    R> DROP ;

: _sr3q-tree-roundtrip  ( tree-index -- )
    DUP STREAMS-OI-TREE-VALID? _sr3q-assert
    DUP STREAMS-OI-TREE-SCOPE
    DUP 0<> _sr3q-assert
    STREAMS-OI-SCOPE-TREE = _sr3q-assert ;

: _sr3q-test-constants  ( -- )
    RID-SIZE 32 = _sr3q-assert
    STREAMS-OPREC-SHAPE-CURRENT 1 = _sr3q-assert
    STREAMS-OPATT-SIZE 800 = _sr3q-assert
    STREAMS-OPRECEIPT-SIZE 512 = _sr3q-assert
    STREAMS-OPATT-F-RECEIPT-PRESENT 1 = _sr3q-assert
    STREAMS-OPROOT-SIZE PERSIST-PAGE-PAYLOAD-SIZE =
        _sr3q-assert
    STREAMS-OPROOT-SIZE 4032 = _sr3q-assert
    STREAMS-OPROOT-TREE-COUNT 8 = _sr3q-assert
    STREAMS-OI-TREE-COUNT STREAMS-OPROOT-TREE-COUNT =
        _sr3q-assert

    STREAMS-OI-CONNECTOR-CONFIG-KEY-SIZE 33 = _sr3q-assert
    STREAMS-OI-CONNECTOR-CONFIG-PREFIX-SIZE 1 = _sr3q-assert
    STREAMS-OI-FLOW-CONFIG-KEY-SIZE 33 = _sr3q-assert
    STREAMS-OI-FLOW-CONFIG-PREFIX-SIZE 1 = _sr3q-assert
    STREAMS-OI-CHECKPOINT-KEY-SIZE 65 = _sr3q-assert
    STREAMS-OI-CHECKPOINT-CONNECTOR-PREFIX-SIZE 33 =
        _sr3q-assert
    STREAMS-OI-CHECKPOINT-FAMILY-PREFIX-SIZE 1 = _sr3q-assert
    STREAMS-OI-ATTEMPT-KEY-SIZE 33 = _sr3q-assert
    STREAMS-OI-ATTEMPT-PREFIX-SIZE 1 = _sr3q-assert
    STREAMS-OI-DISPATCH-READY-KEY-SIZE 41 = _sr3q-assert
    STREAMS-OI-DISPATCH-READY-ORDER-PREFIX-SIZE 9 =
        _sr3q-assert
    STREAMS-OI-DISPATCH-READY-PREFIX-SIZE 1 = _sr3q-assert
    STREAMS-OI-DISPATCH-ACTIVE-KEY-SIZE 41 = _sr3q-assert
    STREAMS-OI-DISPATCH-ACTIVE-TIME-PREFIX-SIZE 9 =
        _sr3q-assert
    STREAMS-OI-DISPATCH-ACTIVE-PREFIX-SIZE 1 = _sr3q-assert
    STREAMS-OI-TERMINAL-RETENTION-KEY-SIZE 41 =
        _sr3q-assert
    STREAMS-OI-TERMINAL-RETENTION-TIME-PREFIX-SIZE 9 =
        _sr3q-assert
    STREAMS-OI-TERMINAL-RETENTION-PREFIX-SIZE 1 =
        _sr3q-assert
    STREAMS-OI-IDEMPOTENCY-KEY-SIZE 65 = _sr3q-assert
    STREAMS-OI-IDEMPOTENCY-CONNECTOR-PREFIX-SIZE 33 =
        _sr3q-assert
    STREAMS-OI-IDEMPOTENCY-FAMILY-PREFIX-SIZE 1 =
        _sr3q-assert
    STREAMS-OI-ROW-VALUE-SIZE PERSIST-REF-SIZE =
        _sr3q-assert
    STREAMS-OI-ROW-VALUE-SIZE 24 = _sr3q-assert
    STREAMS-OI-IDEMPOTENCY-VALUE-SIZE 64 = _sr3q-assert
    STREAMS-OI-IDEMPOTENCY-VALUE-SIZE PBTREE-VALUE-MAX =
        _sr3q-assert
    STREAMS-OI-CONNECTOR-USAGE-KEY-SIZE 33 = _sr3q-assert
    STREAMS-OI-FLOW-USAGE-KEY-SIZE 33 = _sr3q-assert
    STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE 16 = _sr3q-assert
    STREAMS-OI-FLOW-USAGE-VALUE-SIZE 8 = _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-tree-mapping  ( -- )
    STREAMS-OI-TREE-CONNECTOR-CONFIG
        STREAMS-OPROOT-TREE-CONNECTORS = _sr3q-assert
    STREAMS-OI-TREE-FLOW-CONFIG
        STREAMS-OPROOT-TREE-FLOWS = _sr3q-assert
    STREAMS-OI-TREE-CHECKPOINT
        STREAMS-OPROOT-TREE-CHECKPOINTS = _sr3q-assert
    STREAMS-OI-TREE-ATTEMPT-DIRECTORY
        STREAMS-OPROOT-TREE-ATTEMPTS = _sr3q-assert
    STREAMS-OI-TREE-DISPATCH
        STREAMS-OPROOT-TREE-DISPATCH = _sr3q-assert
    STREAMS-OI-TREE-TERMINAL-RETENTION
        STREAMS-OPROOT-TREE-TERMINAL = _sr3q-assert
    STREAMS-OI-TREE-IDEMPOTENCY
        STREAMS-OPROOT-TREE-IDEMPOTENCY = _sr3q-assert
    STREAMS-OI-TREE-OPERATIONAL-USAGE
        STREAMS-OPROOT-TREE-USAGE = _sr3q-assert

    STREAMS-OI-TREE-CONNECTOR-CONFIG _sr3q-tree-roundtrip
    STREAMS-OI-TREE-FLOW-CONFIG _sr3q-tree-roundtrip
    STREAMS-OI-TREE-CHECKPOINT _sr3q-tree-roundtrip
    STREAMS-OI-TREE-ATTEMPT-DIRECTORY _sr3q-tree-roundtrip
    STREAMS-OI-TREE-DISPATCH _sr3q-tree-roundtrip
    STREAMS-OI-TREE-TERMINAL-RETENTION _sr3q-tree-roundtrip
    STREAMS-OI-TREE-IDEMPOTENCY _sr3q-tree-roundtrip
    STREAMS-OI-TREE-OPERATIONAL-USAGE _sr3q-tree-roundtrip
    -1 STREAMS-OI-TREE-VALID? 0= _sr3q-assert
    STREAMS-OI-TREE-COUNT STREAMS-OI-TREE-VALID? 0=
        _sr3q-assert
    -1 STREAMS-OI-TREE-SCOPE 0= _sr3q-assert
    0 STREAMS-OI-SCOPE-TREE -1 = _sr3q-assert

    STREAMS-OI-F-CONNECTOR-CONFIG STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-CONNECTOR-CONFIG = _sr3q-assert
    STREAMS-OI-F-FLOW-CONFIG STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-FLOW-CONFIG = _sr3q-assert
    STREAMS-OI-F-CHECKPOINT STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-CHECKPOINT = _sr3q-assert
    STREAMS-OI-F-ATTEMPT-DIRECTORY STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-ATTEMPT-DIRECTORY = _sr3q-assert
    STREAMS-OI-F-DISPATCH-READY STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-DISPATCH = _sr3q-assert
    STREAMS-OI-F-DISPATCH-ACTIVE STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-DISPATCH = _sr3q-assert
    STREAMS-OI-F-TERMINAL-RETENTION STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-TERMINAL-RETENTION = _sr3q-assert
    STREAMS-OI-F-IDEMPOTENCY STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-IDEMPOTENCY = _sr3q-assert
    STREAMS-OI-F-CONNECTOR-USAGE STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-OPERATIONAL-USAGE = _sr3q-assert
    STREAMS-OI-F-FLOW-USAGE STREAMS-OI-FAMILY-TREE
        STREAMS-OI-TREE-OPERATIONAL-USAGE = _sr3q-assert
    0 STREAMS-OI-FAMILY-TREE -1 = _sr3q-assert

    STREAMS-OI-F-CONNECTOR-CONFIG STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-FLOW-CONFIG STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-CHECKPOINT STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-ATTEMPT-DIRECTORY STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-DISPATCH-READY STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-DISPATCH-ACTIVE STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-TERMINAL-RETENTION STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-IDEMPOTENCY STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-CONNECTOR-USAGE STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    STREAMS-OI-F-FLOW-USAGE STREAMS-OI-FAMILY-VALID?
        _sr3q-assert
    0 STREAMS-OI-FAMILY-VALID? 0= _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-big-endian  ( -- )
    0x0102030405060708 _sr3q-be-a
        STREAMS-OI-NONNEGATIVE-U64-BE!
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-be-a     C@ 0x01 = _sr3q-assert
    _sr3q-be-a 1 + C@ 0x02 = _sr3q-assert
    _sr3q-be-a 2 + C@ 0x03 = _sr3q-assert
    _sr3q-be-a 3 + C@ 0x04 = _sr3q-assert
    _sr3q-be-a 4 + C@ 0x05 = _sr3q-assert
    _sr3q-be-a 5 + C@ 0x06 = _sr3q-assert
    _sr3q-be-a 6 + C@ 0x07 = _sr3q-assert
    _sr3q-be-a 7 + C@ 0x08 = _sr3q-assert
    _sr3q-be-a STREAMS-OI-NONNEGATIVE-U64-BE@
        _sr3q-assert
    0x0102030405060708 = _sr3q-assert

    _sr3q-be-b STREAMS-OI-ORDER-SIZE 0xA5 FILL
    -1 _sr3q-be-b STREAMS-OI-NONNEGATIVE-U64-BE!
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-be-b STREAMS-OI-ORDER-SIZE 0xA5
        _sr3q-filled? _sr3q-assert
    _sr3q-be-b STREAMS-OI-ORDER-SIZE 0 FILL
    0x80 _sr3q-be-b C!
    _sr3q-be-b STREAMS-OI-NONNEGATIVE-U64-BE@
        0= _sr3q-assert
    0= _sr3q-assert

    2 _sr3q-rid-a _sr3q-key-a
        STREAMS-OI-DISPATCH-READY-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    256 _sr3q-rid-a _sr3q-key-b
        STREAMS-OI-DISPATCH-READY-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
    _sr3q-key-b STREAMS-OI-DISPATCH-READY-KEY-SIZE
        COMPARE 0< _sr3q-assert
    _sr3q-key-a 1+ STREAMS-OI-NONNEGATIVE-U64-BE@
        _sr3q-assert
    2 = _sr3q-assert
    _sr3q-key-b 1+ STREAMS-OI-NONNEGATIVE-U64-BE@
        _sr3q-assert
    256 = _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-values  ( -- )
    _sr3q-setup-ref
    _sr3q-ref PERSIST-REF-VALID? _sr3q-assert
    _sr3q-ref _sr3q-row STREAMS-OI-ROW-VALUE
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-ROW-VALUE-VALID? _sr3q-assert
    _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-ROW-VALUE-REF@ _sr3q-row = _sr3q-assert
    _sr3q-ref PERSIST-REF-SIZE
    _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        COMPARE 0= _sr3q-assert
    _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-F-CONNECTOR-CONFIG
        STREAMS-OI-FAMILY-VALUE-VALID? _sr3q-assert
    _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-F-IDEMPOTENCY
        STREAMS-OI-FAMILY-VALUE-VALID? 0= _sr3q-assert

    _sr3q-ref _sr3q-ref-snapshot PERSIST-REF-COPY
    _sr3q-ref _sr3q-ref STREAMS-OI-ROW-VALUE
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-ref PERSIST-REF-SIZE
    _sr3q-ref-snapshot PERSIST-REF-SIZE
        COMPARE 0= _sr3q-assert

    _sr3q-rid-a _sr3q-seal-a _sr3q-idempotency-value
        STREAMS-OI-IDEMPOTENCY-VALUE
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        STREAMS-OI-IDEMPOTENCY-VALUE-VALID? _sr3q-assert
    _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        STREAMS-OI-IDEMPOTENCY-VALUE-ATTEMPT@
        _sr3q-rid-a RID= _sr3q-assert
    _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        STREAMS-OI-IDEMPOTENCY-VALUE-SEAL@
        _sr3q-seal-a STREAMS-OI-REQUEST-SEAL-SIZE
        _SOI-BYTES= _sr3q-assert
    _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        _sr3q-rid-a _sr3q-seal-a
        STREAMS-OI-IDEMPOTENCY-VALUE-MATCH? _sr3q-assert
    _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        _sr3q-rid-b _sr3q-seal-a
        STREAMS-OI-IDEMPOTENCY-VALUE-MATCH? 0= _sr3q-assert
    _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        _sr3q-rid-a _sr3q-seal-b
        STREAMS-OI-IDEMPOTENCY-VALUE-MATCH? 0= _sr3q-assert
    _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        STREAMS-OI-F-IDEMPOTENCY
        STREAMS-OI-FAMILY-VALUE-VALID? _sr3q-assert

    _sr3q-idempotency-value PBTREE-VALUE-MAX 0xA5 FILL
    _sr3q-idempotency-value _sr3q-value-snapshot
        PBTREE-VALUE-MAX MOVE
    _sr3q-rid-a _sr3q-rid-zero _sr3q-idempotency-value
        STREAMS-OI-IDEMPOTENCY-VALUE
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-idempotency-value PBTREE-VALUE-MAX
    _sr3q-value-snapshot PBTREE-VALUE-MAX
        COMPARE 0= _sr3q-assert

    _sr3q-alias-value PBTREE-VALUE-MAX 0x19 FILL
    _sr3q-alias-value _sr3q-value-snapshot
        PBTREE-VALUE-MAX MOVE
    _sr3q-alias-value
    _sr3q-alias-value RID-SIZE +
    _sr3q-alias-value STREAMS-OI-IDEMPOTENCY-VALUE
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-alias-value PBTREE-VALUE-MAX
    _sr3q-value-snapshot PBTREE-VALUE-MAX
        COMPARE 0= _sr3q-assert
    _sr3q-rid-a _sr3q-seal-a _sr3q-idempotency-value
        STREAMS-OI-IDEMPOTENCY-VALUE
        STREAMS-OI-S-OK = _sr3q-assert

    3 4096 _sr3q-connector-usage
        STREAMS-OI-CONNECTOR-USAGE-VALUE
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-VALID? _sr3q-assert
    _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-ITEM-COUNT@
        _sr3q-assert
    3 = _sr3q-assert
    _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-PAYLOAD-BYTES@
        _sr3q-assert
    4096 = _sr3q-assert
    _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-F-CONNECTOR-USAGE
        STREAMS-OI-FAMILY-VALUE-VALID? _sr3q-assert
    _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE 1-
        STREAMS-OI-CONNECTOR-USAGE-VALUE-VALID? 0= _sr3q-assert

    2 _sr3q-flow-usage STREAMS-OI-FLOW-USAGE-VALUE
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-FLOW-USAGE-VALUE-VALID? _sr3q-assert
    _sr3q-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-FLOW-USAGE-VALUE-ACTIVE-COUNT@
        _sr3q-assert
    2 = _sr3q-assert
    _sr3q-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-F-FLOW-USAGE
        STREAMS-OI-FAMILY-VALUE-VALID? _sr3q-assert

    _sr3q-connector-usage PBTREE-VALUE-MAX 0xA5 FILL
    _sr3q-connector-usage _sr3q-value-snapshot
        PBTREE-VALUE-MAX MOVE
    -1 1 _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-connector-usage PBTREE-VALUE-MAX
    _sr3q-value-snapshot PBTREE-VALUE-MAX
        COMPARE 0= _sr3q-assert
    0 1 _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-connector-usage PBTREE-VALUE-MAX
    _sr3q-value-snapshot PBTREE-VALUE-MAX
        COMPARE 0= _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-config-and-checkpoint-keys  ( -- )
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-PREFIX-SIZE
        STREAMS-OI-CONNECTOR-CONFIG-PREFIX-VALID? _sr3q-assert
    _sr3q-key-a C@ STREAMS-OI-F-CONNECTOR-CONFIG =
        _sr3q-assert
    _sr3q-rid-c _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-KEY-SIZE
        STREAMS-OI-CONNECTOR-CONFIG-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-KEY-SIZE
        STREAMS-OI-CONNECTOR-CONFIG-KEY-ID@
        _sr3q-rid-c RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-KEY-SIZE
        STREAMS-OI-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-CONNECTOR-CONFIG =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-CONNECTOR-CONFIG =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-CONFIG-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert

    _sr3q-key-a STREAMS-OI-FLOW-CONFIG-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-FLOW-CONFIG-PREFIX-SIZE
        STREAMS-OI-FLOW-CONFIG-PREFIX-VALID? _sr3q-assert
    _sr3q-rid-d _sr3q-key-a STREAMS-OI-FLOW-CONFIG-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-FLOW-CONFIG-KEY-SIZE
        STREAMS-OI-FLOW-CONFIG-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-FLOW-CONFIG-KEY-SIZE
        STREAMS-OI-FLOW-CONFIG-KEY-ID@
        _sr3q-rid-d RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-FLOW-CONFIG-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-FLOW-CONFIG =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-FLOW-CONFIG-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-FLOW-CONFIG =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-FLOW-CONFIG-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert

    _sr3q-key-a STREAMS-OI-CHECKPOINT-FAMILY-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-FAMILY-PREFIX-SIZE
        STREAMS-OI-CHECKPOINT-FAMILY-PREFIX-VALID? _sr3q-assert
    _sr3q-rid-c _sr3q-key-a
        STREAMS-OI-CHECKPOINT-CONNECTOR-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-CONNECTOR-PREFIX-SIZE
        STREAMS-OI-CHECKPOINT-CONNECTOR-PREFIX-VALID?
        _sr3q-assert
    _sr3q-rid-c _sr3q-rid-d _sr3q-key-a
        STREAMS-OI-CHECKPOINT-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-KEY-SIZE
        STREAMS-OI-CHECKPOINT-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-KEY-SIZE
        STREAMS-OI-CHECKPOINT-KEY-CONNECTOR@
        _sr3q-rid-c RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-KEY-SIZE
        STREAMS-OI-CHECKPOINT-KEY-FLOW@
        _sr3q-rid-d RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-CHECKPOINT =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-CHECKPOINT =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-CHECKPOINT-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-attempt-and-order-keys  ( -- )
    _sr3q-key-a STREAMS-OI-ATTEMPT-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-ATTEMPT-PREFIX-SIZE
        STREAMS-OI-ATTEMPT-PREFIX-VALID? _sr3q-assert
    _sr3q-rid-a _sr3q-key-a STREAMS-OI-ATTEMPT-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-ATTEMPT-KEY-SIZE
        STREAMS-OI-ATTEMPT-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-ATTEMPT-KEY-SIZE
        STREAMS-OI-ATTEMPT-KEY-ID@
        _sr3q-rid-a RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-ATTEMPT-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-ATTEMPT-DIRECTORY =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-ATTEMPT-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-ATTEMPT-DIRECTORY =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-ATTEMPT-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert

    _sr3q-key-a STREAMS-OI-DISPATCH-READY-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-PREFIX-SIZE
        STREAMS-OI-DISPATCH-READY-PREFIX-VALID? _sr3q-assert
    7 _sr3q-key-a STREAMS-OI-DISPATCH-READY-ORDER-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-ORDER-PREFIX-SIZE
        STREAMS-OI-DISPATCH-READY-ORDER-PREFIX-VALID?
        _sr3q-assert
    7 _sr3q-rid-a _sr3q-key-a
        STREAMS-OI-DISPATCH-READY-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
        STREAMS-OI-DISPATCH-READY-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
        STREAMS-OI-DISPATCH-READY-KEY-SEQUENCE@
        _sr3q-assert
    7 = _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
        STREAMS-OI-DISPATCH-READY-KEY-ATTEMPT@
        _sr3q-rid-a RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-DISPATCH =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-DISPATCH =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert

    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-PREFIX-SIZE
        STREAMS-OI-DISPATCH-ACTIVE-PREFIX-VALID? _sr3q-assert
    _sr3q-key-a C@ _sr3q-key-b C@ <> _sr3q-assert
    1002 _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-TIME-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-TIME-PREFIX-SIZE
        STREAMS-OI-DISPATCH-ACTIVE-TIME-PREFIX-VALID?
        _sr3q-assert
    1002 _sr3q-rid-a _sr3q-key-b
        STREAMS-OI-DISPATCH-ACTIVE-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-KEY-SIZE
        STREAMS-OI-DISPATCH-ACTIVE-KEY-VALID? _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-KEY-SIZE
        STREAMS-OI-DISPATCH-ACTIVE-KEY-TIME@
        _sr3q-assert
    1002 = _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-KEY-SIZE
        STREAMS-OI-DISPATCH-ACTIVE-KEY-ATTEMPT@
        _sr3q-rid-a RID= _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-DISPATCH =
        _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-DISPATCH =
        _sr3q-assert
    _sr3q-key-b STREAMS-OI-DISPATCH-ACTIVE-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert

    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-PREFIX-SIZE
        STREAMS-OI-TERMINAL-RETENTION-PREFIX-VALID?
        _sr3q-assert
    2000 _sr3q-key-a
        STREAMS-OI-TERMINAL-RETENTION-TIME-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-TIME-PREFIX-SIZE
        STREAMS-OI-TERMINAL-RETENTION-TIME-PREFIX-VALID?
        _sr3q-assert
    2000 _sr3q-rid-a _sr3q-key-a
        STREAMS-OI-TERMINAL-RETENTION-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-KEY-SIZE
        STREAMS-OI-TERMINAL-RETENTION-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-KEY-SIZE
        STREAMS-OI-TERMINAL-RETENTION-KEY-TIME@
        _sr3q-assert
    2000 = _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-KEY-SIZE
        STREAMS-OI-TERMINAL-RETENTION-KEY-ATTEMPT@
        _sr3q-rid-a RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-TERMINAL-RETENTION =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-TERMINAL-RETENTION =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-TERMINAL-RETENTION-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-idempotency-keys  ( -- )
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-FAMILY-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-FAMILY-PREFIX-SIZE
        STREAMS-OI-IDEMPOTENCY-FAMILY-PREFIX-VALID?
        _sr3q-assert
    _sr3q-rid-c _sr3q-key-a
        STREAMS-OI-IDEMPOTENCY-CONNECTOR-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-CONNECTOR-PREFIX-SIZE
        STREAMS-OI-IDEMPOTENCY-CONNECTOR-PREFIX-VALID?
        _sr3q-assert
    _sr3q-rid-c _sr3q-rid-f _sr3q-key-a
        STREAMS-OI-IDEMPOTENCY-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        STREAMS-OI-IDEMPOTENCY-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        STREAMS-OI-IDEMPOTENCY-KEY-CONNECTOR@
        _sr3q-rid-c RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        STREAMS-OI-IDEMPOTENCY-KEY-ID@
        _sr3q-rid-f RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        STREAMS-OI-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-IDEMPOTENCY =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-IDEMPOTENCY =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        _sr3q-idempotency-value STREAMS-OI-IDEMPOTENCY-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE 1-
        STREAMS-OI-IDEMPOTENCY-KEY-VALID? 0= _sr3q-assert
    _sr3q-key-a STREAMS-OI-IDEMPOTENCY-KEY-SIZE
        _sr3q-row STREAMS-OI-ROW-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? 0= _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-usage-keys  ( -- )
    3 4096 _sr3q-connector-usage
        STREAMS-OI-CONNECTOR-USAGE-VALUE
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-PREFIX-SIZE
        STREAMS-OI-CONNECTOR-USAGE-PREFIX-VALID? _sr3q-assert
    _sr3q-rid-c _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-KEY-SIZE
        STREAMS-OI-CONNECTOR-USAGE-KEY-VALID? _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-KEY-SIZE
        STREAMS-OI-CONNECTOR-USAGE-KEY-ID@
        _sr3q-rid-c RID= _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-OPERATIONAL-USAGE =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-OPERATIONAL-USAGE =
        _sr3q-assert
    _sr3q-key-a STREAMS-OI-CONNECTOR-USAGE-KEY-SIZE
        _sr3q-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert

    2 _sr3q-flow-usage STREAMS-OI-FLOW-USAGE-VALUE
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-b STREAMS-OI-FLOW-USAGE-PREFIX
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-b STREAMS-OI-FLOW-USAGE-PREFIX-SIZE
        STREAMS-OI-FLOW-USAGE-PREFIX-VALID? _sr3q-assert
    _sr3q-rid-d _sr3q-key-b STREAMS-OI-FLOW-USAGE-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-b STREAMS-OI-FLOW-USAGE-KEY-SIZE
        STREAMS-OI-FLOW-USAGE-KEY-VALID? _sr3q-assert
    _sr3q-key-b STREAMS-OI-FLOW-USAGE-KEY-SIZE
        STREAMS-OI-FLOW-USAGE-KEY-ID@
        _sr3q-rid-d RID= _sr3q-assert
    _sr3q-key-b STREAMS-OI-FLOW-USAGE-KEY-SIZE
        STREAMS-OI-KEY-TREE STREAMS-OI-TREE-OPERATIONAL-USAGE =
        _sr3q-assert
    _sr3q-key-b STREAMS-OI-FLOW-USAGE-KEY-SIZE
        STREAMS-OI-KEY-SCOPE STREAMS-OI-SCOPE-OPERATIONAL-USAGE =
        _sr3q-assert
    _sr3q-key-b STREAMS-OI-FLOW-USAGE-KEY-SIZE
        _sr3q-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-KEY-VALUE-VALID? _sr3q-assert
    _sr3q-key-a C@ _sr3q-key-b C@ <> _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-index-nonmutation  ( -- )
    _sr3q-key-a PBTREE-KEY-MAX 0xA5 FILL
    _sr3q-key-a _sr3q-key-snapshot PBTREE-KEY-MAX MOVE
    _sr3q-rid-zero _sr3q-key-a
        STREAMS-OI-CONNECTOR-CONFIG-KEY
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-key-a PBTREE-KEY-MAX
    _sr3q-key-snapshot PBTREE-KEY-MAX
        COMPARE 0= _sr3q-assert

    _sr3q-key-a PBTREE-KEY-MAX 0x3C FILL
    _sr3q-key-a _sr3q-key-snapshot PBTREE-KEY-MAX MOVE
    0 _sr3q-rid-a _sr3q-key-a
        STREAMS-OI-DISPATCH-READY-KEY
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-key-a PBTREE-KEY-MAX
    _sr3q-key-snapshot PBTREE-KEY-MAX
        COMPARE 0= _sr3q-assert

    1 _sr3q-rid-a _sr3q-key-a
        STREAMS-OI-DISPATCH-READY-KEY
        STREAMS-OI-S-OK = _sr3q-assert
    _sr3q-key-a 1+ STREAMS-OI-ORDER-SIZE 0 FILL
    _sr3q-key-a STREAMS-OI-DISPATCH-READY-KEY-SIZE
        STREAMS-OI-DISPATCH-READY-KEY-VALID? 0= _sr3q-assert

    _sr3q-key-a PBTREE-KEY-MAX 0x5A FILL
    _sr3q-key-a _sr3q-key-snapshot PBTREE-KEY-MAX MOVE
    -1 _sr3q-rid-a _sr3q-key-a
        STREAMS-OI-DISPATCH-READY-KEY
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-key-a PBTREE-KEY-MAX
    _sr3q-key-snapshot PBTREE-KEY-MAX
        COMPARE 0= _sr3q-assert

    _sr3q-alias-key PBTREE-KEY-MAX 0x17 FILL
    _sr3q-alias-key _sr3q-key-snapshot PBTREE-KEY-MAX MOVE
    _sr3q-alias-key _sr3q-alias-key
        STREAMS-OI-CONNECTOR-CONFIG-KEY
        STREAMS-OI-S-INVALID = _sr3q-assert
    _sr3q-alias-key PBTREE-KEY-MAX
    _sr3q-key-snapshot PBTREE-KEY-MAX
        COMPARE 0= _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-attempt-record  ( -- )
    0 STREAMS-OPATT-SIZE STREAMS-OPATT-VALID? 0= _sr3q-assert
    -1 STREAMS-OPATT-SIZE STREAMS-OPATT-VALID? 0= _sr3q-assert
    0 STREAMS-OPATT-INIT STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-c STREAMS-OPATT-INIT
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-attempt-c SOPATT.RECEIPT-POLICY @
        STREAMS-OPATT-RECEIPT-NONE = _sr3q-assert
    _sr3q-attempt-c SOPATT.RECEIPT-BYTE-LIMIT @ 0=
        _sr3q-assert
    _sr3q-attempt-c SOPATT.DISPATCH-COUNT @ 0= _sr3q-assert
    _sr3q-attempt-a _sr3q-valid-attempt!
    _sr3q-attempt-a STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3q-assert
    _sr3q-attempt-a STREAMS-OPATT-SIZE
        STREAMS-OPATT-HEADER-CLASSIFY
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-attempt-a STREAMS-OPATT-SIZE 1-
        STREAMS-OPATT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3q-assert
    _sr3q-attempt-a SOPATT.PAYLOAD-U @ 0= _sr3q-assert
    _sr3q-attempt-a SOPATT.PAYLOAD-BLOB PBLOB-VALID?
        _sr3q-assert
    _sr3q-attempt-a SOPATT.PAYLOAD-BLOB PBLOB-TOTAL@
        0= _sr3q-assert
    _sr3q-attempt-a SOPATT.RECEIPT-ID RID-ZERO? _sr3q-assert
    _sr3q-attempt-a SOPATT.RECEIPT-REF PERSIST-REF-SIZE
        _SOPREC-ZERO? _sr3q-assert
    _sr3q-attempt-a SOPATT.STATE @
        STREAMS-OPATT-STATE-ACCEPTED = _sr3q-assert
    _sr3q-attempt-a SOPATT.EFFECT @
        STREAMS-OPATT-EFFECT-NOT-APPLIED = _sr3q-assert
    _sr3q-attempt-a SOPATT.IDEMPOTENCY-POLICY @
        STREAMS-OPATT-IDEMPOTENCY-EXACT = _sr3q-assert
    _sr3q-attempt-a SOPATT.REQUEST-SEAL
        _sr3q-seal-a RID= _sr3q-assert
    _sr3q-attempt-a SOPATT.ENDPOINT-SEAL
        _sr3q-seal-b RID= _sr3q-assert
    _sr3q-attempt-a SOPATT.ACCEPTED-SEQUENCE @ 7 =
        _sr3q-assert
    _sr3q-attempt-a SOPATT.READY-SEQUENCE @ 8 =
        _sr3q-assert
    _sr3q-attempt-a SOPATT.DISPATCH-COUNT @ 0= _sr3q-assert
    _sr3q-attempt-a SOPATT.PROFILE @ 102 = _sr3q-assert
    _sr3q-attempt-a SOPATT.RECEIPT-POLICY @
        STREAMS-OPATT-RECEIPT-BOUNDED = _sr3q-assert
    _sr3q-attempt-a SOPATT.RECEIPT-BYTE-LIMIT @ 512 =
        _sr3q-assert

    _sr3q-attempt-a _sr3q-attempt-b STREAMS-OPATT-COPY
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-attempt-a STREAMS-OPATT-SIZE
    _sr3q-attempt-b STREAMS-OPATT-SIZE
        COMPARE 0= _sr3q-assert
    _sr3q-attempt-b STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3q-assert

    _sr3q-attempt-a _sr3q-attempt-a STREAMS-OPATT-COPY
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-a STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3q-assert
    _sr3q-attempt-a _sr3q-attempt-a 1+ STREAMS-OPATT-COPY
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-a STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3q-assert

    _sr3q-attempt-b SOPATT.PAYLOAD-DIGEST
        DUP C@ 1 XOR SWAP C!
    _sr3q-attempt-b STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? 0= _sr3q-assert

    _sr3q-attempt-a _sr3q-attempt-b STREAMS-OPATT-SIZE MOVE
    STREAMS-OPREC-SHAPE-CURRENT 1+
        _sr3q-attempt-b SOPREC.SHAPE !
    _sr3q-attempt-b STREAMS-OPATT-SIZE
        STREAMS-OPATT-HEADER-CLASSIFY
        STREAMS-OPREC-S-UNKNOWN = _sr3q-assert
    0 _sr3q-attempt-b SOPREC.SHAPE !
    _sr3q-attempt-b STREAMS-OPATT-SIZE
        STREAMS-OPATT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3q-assert

    _sr3q-attempt-a _sr3q-attempt-b STREAMS-OPATT-SIZE MOVE
    STREAMS-OPATT-STATE-ACTIVE
        _sr3q-attempt-b SOPATT.STATE !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-b SOPREC.SEAL SHA3-256-LEN
        _SOPREC-ZERO? _sr3q-assert

    _sr3q-attempt-b _sr3q-valid-attempt!
    _sr3q-attempt-b SOPATT.ENDPOINT-SEAL RID-CLEAR
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-b _sr3q-valid-attempt!
    0 _sr3q-attempt-b SOPATT.READY-SEQUENCE !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-b _sr3q-valid-attempt!
    0 _sr3q-attempt-b SOPATT.PROFILE !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-b _sr3q-valid-attempt!
    1 _sr3q-attempt-b SOPATT.RETRY-COUNT !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-RECEIPT-NONE _sr3q-attempt-b SOPATT.RECEIPT-POLICY !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-attempt-states  ( -- )
    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-STATE-ACTIVE _sr3q-attempt-b SOPATT.STATE !
    STREAMS-OPATT-EFFECT-UNCERTAIN _sr3q-attempt-b SOPATT.EFFECT !
    1 _sr3q-attempt-b SOPATT.DISPATCH-COUNT !
    1002 _sr3q-attempt-b SOPATT.STARTED-MS !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-attempt-b STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3q-assert

    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-STATE-FAILED-BEFORE
        _sr3q-attempt-b SOPATT.STATE !
    1002 _sr3q-attempt-b SOPATT.FINISHED-MS !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert

    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-STATE-INDETERMINATE
        _sr3q-attempt-b SOPATT.STATE !
    STREAMS-OPATT-EFFECT-UNCERTAIN _sr3q-attempt-b SOPATT.EFFECT !
    1 _sr3q-attempt-b SOPATT.DISPATCH-COUNT !
    1002 _sr3q-attempt-b SOPATT.STARTED-MS !
    1003 _sr3q-attempt-b SOPATT.FINISHED-MS !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert

    \ A local receipt with empty remote evidence is present rather than
    \ absent.  Cancellation retains the stronger known-applied effect and
    \ its exact receipt facts.
    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-STATE-CANCELLED _sr3q-attempt-b SOPATT.STATE !
    STREAMS-OPATT-EFFECT-APPLIED _sr3q-attempt-b SOPATT.EFFECT !
    STREAMS-OPATT-F-RECEIPT-PRESENT _sr3q-attempt-b SOPATT.FLAGS !
    _sr3q-rid-b _sr3q-attempt-b SOPATT.RECEIPT-ID RID-COPY
    _sr3q-setup-ref
    _sr3q-ref _sr3q-attempt-b SOPATT.RECEIPT-REF PERSIST-REF-COPY
    1 _sr3q-attempt-b SOPATT.DISPATCH-COUNT !
    1002 _sr3q-attempt-b SOPATT.STARTED-MS !
    1003 _sr3q-attempt-b SOPATT.FINISHED-MS !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-attempt-b SOPATT.RECEIPT-ID
        _sr3q-rid-b RID= _sr3q-assert
    _sr3q-attempt-b SOPATT.RECEIPT-REF
        PERSIST-REF-VALID? _sr3q-assert
    _sr3q-attempt-b SOPATT.FLAGS @
        STREAMS-OPATT-F-RECEIPT-PRESENT AND 0<>
        _sr3q-assert
    _sr3q-attempt-b SOPATT.EFFECT @
        STREAMS-OPATT-EFFECT-APPLIED = _sr3q-assert
    STREAMS-OPATT-RECEIPT-NONE
        _sr3q-attempt-b SOPATT.RECEIPT-POLICY !
    0 _sr3q-attempt-b SOPATT.RECEIPT-BYTE-LIMIT !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert

    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-STATE-FAILED-BEFORE
        _sr3q-attempt-b SOPATT.STATE !
    1002 _sr3q-attempt-b SOPATT.FINISHED-MS !
    STREAMS-OPATT-F-RECEIPT-PRESENT _sr3q-attempt-b SOPATT.FLAGS !
    _sr3q-rid-b _sr3q-attempt-b SOPATT.RECEIPT-ID RID-COPY
    _sr3q-setup-ref
    _sr3q-ref _sr3q-attempt-b SOPATT.RECEIPT-REF PERSIST-REF-COPY
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    \ Known acknowledgement cannot be represented as receipt-free success.
    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-STATE-ACKNOWLEDGED
        _sr3q-attempt-b SOPATT.STATE !
    STREAMS-OPATT-EFFECT-APPLIED _sr3q-attempt-b SOPATT.EFFECT !
    1 _sr3q-attempt-b SOPATT.DISPATCH-COUNT !
    1002 _sr3q-attempt-b SOPATT.STARTED-MS !
    1003 _sr3q-attempt-b SOPATT.FINISHED-MS !
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    \ A present receipt must carry both its identity and checked record
    \ reference; an absent receipt must carry neither.
    _sr3q-attempt-b _sr3q-valid-attempt!
    _sr3q-rid-b _sr3q-attempt-b SOPATT.RECEIPT-ID RID-COPY
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-attempt-b _sr3q-valid-attempt!
    STREAMS-OPATT-F-RECEIPT-PRESENT _sr3q-attempt-b SOPATT.FLAGS !
    _sr3q-rid-b _sr3q-attempt-b SOPATT.RECEIPT-ID RID-COPY
    _sr3q-attempt-b STREAMS-OPATT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-receipt-record  ( -- )
    0 STREAMS-OPRECEIPT-SIZE STREAMS-OPRECEIPT-VALID?
        0= _sr3q-assert
    _sr3q-receipt-a _sr3q-valid-receipt!
    _sr3q-receipt-a STREAMS-OPRECEIPT-SIZE
        STREAMS-OPRECEIPT-VALID? _sr3q-assert
    _sr3q-receipt-a STREAMS-OPRECEIPT-SIZE
        STREAMS-OPRECEIPT-HEADER-CLASSIFY
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-receipt-a STREAMS-OPRECEIPT-SIZE 1-
        STREAMS-OPRECEIPT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3q-assert
    _sr3q-receipt-a SOPRECEIPT.RECEIPT-ID
        _sr3q-rid-b RID= _sr3q-assert
    _sr3q-receipt-a SOPRECEIPT.ATTEMPT-ID
        _sr3q-rid-a RID= _sr3q-assert
    _sr3q-receipt-a SOPRECEIPT.ACKNOWLEDGEMENT-ID
        _sr3q-rid-e RID= _sr3q-assert
    _sr3q-receipt-a SOPRECEIPT.DELIVERY-ID
        RID-ZERO? _sr3q-assert
    _sr3q-receipt-a SOPRECEIPT.DELIVERED-MS @ -1 =
        _sr3q-assert
    _sr3q-receipt-a SOPRECEIPT.REMOTE-DIGEST
        SHA3-256-LEN _SOPREC-ZERO? _sr3q-assert
    _sr3q-receipt-a SOPRECEIPT.REMOTE-BLOB
        PBLOB-SIZE _SOPREC-ZERO? _sr3q-assert

    _sr3q-receipt-a _sr3q-receipt-b STREAMS-OPRECEIPT-COPY
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-receipt-a STREAMS-OPRECEIPT-SIZE
    _sr3q-receipt-b STREAMS-OPRECEIPT-SIZE
        COMPARE 0= _sr3q-assert
    _sr3q-receipt-a _sr3q-receipt-a STREAMS-OPRECEIPT-COPY
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    \ Both optional remote fields share one PBLOB.  Their exact lengths bind
    \ the receipt-then-correlation split and the digest binds all 12 bytes.
    _sr3q-receipt-b _sr3q-valid-receipt!
    _sr3q-rid-f _sr3q-receipt-b SOPRECEIPT.DELIVERY-ID RID-COPY
    1003 _sr3q-receipt-b SOPRECEIPT.DELIVERED-MS !
    _sr3q-seal-b _sr3q-receipt-b SOPRECEIPT.REMOTE-DIGEST RID-COPY
    5 _sr3q-receipt-b SOPRECEIPT.REMOTE-RECEIPT-U !
    7 _sr3q-receipt-b SOPRECEIPT.REMOTE-CORRELATION-U !
    12 _sr3q-receipt-b SOPRECEIPT.REMOTE-BLOB _sr3q-small-blob!
    _sr3q-receipt-b STREAMS-OPRECEIPT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-receipt-b STREAMS-OPRECEIPT-SIZE
        STREAMS-OPRECEIPT-VALID? _sr3q-assert
    _sr3q-receipt-b SOPRECEIPT.REMOTE-BLOB PBLOB-TOTAL@
        12 = _sr3q-assert

    _sr3q-receipt-c _sr3q-valid-receipt!
    _sr3q-receipt-c SOPRECEIPT.ACKNOWLEDGEMENT-ID RID-CLEAR
    -1 _sr3q-receipt-c SOPRECEIPT.ACKNOWLEDGED-MS !
    _sr3q-receipt-c STREAMS-OPRECEIPT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-receipt-c _sr3q-valid-receipt!
    1 _sr3q-receipt-c SOPRECEIPT.REMOTE-RECEIPT-U !
    _sr3q-receipt-c STREAMS-OPRECEIPT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-receipt-c _sr3q-valid-receipt!
    STREAMS-OPRECEIPT-RESULT-MAX 1+
        _sr3q-receipt-c SOPRECEIPT.RESULT !
    _sr3q-receipt-c STREAMS-OPRECEIPT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-receipt-c _sr3q-valid-receipt!
    1 _sr3q-receipt-c SOPRECEIPT.RESERVED C!
    _sr3q-receipt-c STREAMS-OPRECEIPT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-receipt-a _sr3q-receipt-c STREAMS-OPRECEIPT-SIZE MOVE
    STREAMS-OPREC-SHAPE-CURRENT 1+
        _sr3q-receipt-c SOPREC.SHAPE !
    _sr3q-receipt-c STREAMS-OPRECEIPT-SIZE
        STREAMS-OPRECEIPT-HEADER-CLASSIFY
        STREAMS-OPREC-S-UNKNOWN = _sr3q-assert

    _sr3q-receipt-a _sr3q-receipt-c STREAMS-OPRECEIPT-SIZE MOVE
    _sr3q-receipt-c SOPRECEIPT.PAYLOAD-DIGEST
        DUP C@ 1 XOR SWAP C!
    _sr3q-receipt-c STREAMS-OPRECEIPT-SIZE
        STREAMS-OPRECEIPT-VALID? 0= _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-root-record  ( -- )
    0 STREAMS-OPROOT-STRUCTURE-VALID? 0= _sr3q-assert
    -1 STREAMS-OPROOT-STRUCTURE-VALID? 0= _sr3q-assert
    _sr3q-rid-h 8 1024 4 60000 _sr3q-root-a
        STREAMS-OPROOT-TEMPLATE-INIT
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SIZE
        STREAMS-OPROOT-HEADER-CLASSIFY
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SIZE 1-
        STREAMS-OPROOT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3q-assert
    _sr3q-root-a SOPROOT.ITEM-LIMIT @ 8 = _sr3q-assert
    _sr3q-root-a SOPROOT.PAYLOAD-BYTE-LIMIT @ 1024 =
        _sr3q-assert
    _sr3q-root-a SOPROOT.TERMINAL-LIMIT @ 4 = _sr3q-assert
    _sr3q-root-a SOPROOT.TERMINAL-AGE-MS @ 60000 =
        _sr3q-assert
    _sr3q-root-a SOPROOT.NEXT-ACCEPTED-SEQUENCE @ 1 =
        _sr3q-assert
    _sr3q-root-a SOPROOT.NEXT-READY-SEQUENCE @ 1 =
        _sr3q-assert
    _sr3q-root-a SOPROOT.NEXT-READY-SEQUENCE
    _sr3q-root-a SOPROOT.NEXT-ACCEPTED-SEQUENCE <> _sr3q-assert
    _sr3q-root-a SOPROOT.RECLAIM-STATE RECLAIM-STATE-SIZE
        RECLAIM-STATE-VALID? _sr3q-assert
    _sr3q-root-a _SOPROOT-ROOTS-PRESENT? 0= _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-STRUCTURE-VALID? 0=
        _sr3q-assert
    1 _sr3q-root-a SOPROOT.LOGICAL-GENERATION !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-root-a _sr3q-root-trees!
    _sr3q-root-a _SOPROOT-ROOTS-PRESENT? _sr3q-assert
    -1 _sr3q-root-a STREAMS-OPROOT-TREE 0= _sr3q-assert
    STREAMS-OPROOT-TREE-COUNT _sr3q-root-a
        STREAMS-OPROOT-TREE 0= _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-STRUCTURE-VALID?
        _sr3q-assert

    4 _sr3q-root-a SOPROOT.ITEM-COUNT !
    100 _sr3q-root-a SOPROOT.PAYLOAD-BYTES !
    1 _sr3q-root-a SOPROOT.READY-COUNT !
    1 _sr3q-root-a SOPROOT.ACTIVE-COUNT !
    2 _sr3q-root-a SOPROOT.TERMINAL-COUNT !
    1 _sr3q-root-a SOPROOT.INDETERMINATE-COUNT !
    1 _sr3q-root-a SOPROOT.CLEANUP-BACKLOG !
    2 _sr3q-root-a SOPROOT.CONNECTOR-COUNT !
    3 _sr3q-root-a SOPROOT.FLOW-COUNT !
    4 _sr3q-root-a SOPROOT.CHECKPOINT-COUNT !
    5 _sr3q-root-a SOPROOT.PHYSICAL-RETIREMENT !
    2 _sr3q-root-a SOPROOT.RECEIPT-COUNT !
    20 _sr3q-root-a SOPROOT.RECEIPT-BYTES !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-STRUCTURE-VALID?
        _sr3q-assert

    _sr3q-root-a _sr3q-root-b STREAMS-OPROOT-COPY
        STREAMS-OPREC-S-OK = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SIZE
    _sr3q-root-b STREAMS-OPROOT-SIZE
        COMPARE 0= _sr3q-assert
    _sr3q-root-a _sr3q-root-a STREAMS-OPROOT-COPY
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-STRUCTURE-VALID?
        _sr3q-assert

    3 _sr3q-root-a SOPROOT.TERMINAL-COUNT !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-root-a SOPROOT.SEAL SHA3-256-LEN
        _SOPREC-ZERO? _sr3q-assert

    _sr3q-root-a _sr3q-valid-root!
    8 _sr3q-root-a SOPROOT.ITEM-COUNT !
    1024 _sr3q-root-a SOPROOT.PAYLOAD-BYTES !
    4 _sr3q-root-a SOPROOT.READY-COUNT !
    0 _sr3q-root-a SOPROOT.ACTIVE-COUNT !
    4 _sr3q-root-a SOPROOT.TERMINAL-COUNT !
    4 _sr3q-root-a SOPROOT.INDETERMINATE-COUNT !
    4 _sr3q-root-a SOPROOT.CLEANUP-BACKLOG !
    4 _sr3q-root-a SOPROOT.RECEIPT-COUNT !
    100 _sr3q-root-a SOPROOT.RECEIPT-BYTES !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-OK = _sr3q-assert
    9 _sr3q-root-a SOPROOT.ITEM-COUNT !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-root-a _sr3q-valid-root!
    5 _sr3q-root-a SOPROOT.ITEM-COUNT !
    2 _sr3q-root-a SOPROOT.ACTIVE-COUNT !
    3 _sr3q-root-a SOPROOT.TERMINAL-COUNT !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-root-a _sr3q-valid-root!
    1 _sr3q-root-a SOPROOT.ITEM-COUNT !
    1 _sr3q-root-a SOPROOT.TERMINAL-COUNT !
    2 _sr3q-root-a SOPROOT.RECEIPT-COUNT !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-root-a _sr3q-valid-root!
    1 _sr3q-root-a SOPROOT.RECEIPT-BYTES !
    _sr3q-root-a STREAMS-OPROOT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3q-assert

    _sr3q-root-b _sr3q-valid-root!
    _sr3q-root-b SOPROOT.PAYLOAD-BYTES
        DUP C@ 1 XOR SWAP C!
    _sr3q-root-b STREAMS-OPROOT-STRUCTURE-VALID? 0=
        _sr3q-assert

    _sr3q-root-c _sr3q-valid-root!
    _sr3q-root-c _sr3q-root-b STREAMS-OPROOT-SIZE MOVE
    STREAMS-OPREC-SHAPE-CURRENT 1+
        _sr3q-root-b SOPROOT.SHAPE !
    STREAMS-OPROOT-SIZE 8 + _sr3q-root-b SOPROOT.SIZE !
    _sr3q-root-b STREAMS-OPROOT-SIZE 8 +
        STREAMS-OPROOT-HEADER-CLASSIFY
        STREAMS-OPREC-S-UNKNOWN = _sr3q-assert
    STREAMS-OPREC-SHAPE-CURRENT _sr3q-root-b SOPROOT.SHAPE !
    _sr3q-root-b STREAMS-OPROOT-SIZE 8 +
        STREAMS-OPROOT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3q-assert
    0 _sr3q-root-b SOPROOT.SIZE !
    _sr3q-root-b STREAMS-OPROOT-SIZE
        STREAMS-OPROOT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3q-assert
    STREAMS-OPROOT-SIZE _sr3q-root-b SOPROOT.SIZE !
    0 _sr3q-root-b SOPROOT.SHAPE !
    _sr3q-root-b STREAMS-OPROOT-SIZE
        STREAMS-OPROOT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3q-assert
    _sr3q-stack ;

: _sr3q-test-root-init-nonmutation  ( -- )
    _sr3q-root-a STREAMS-OPROOT-SIZE 0xA5 FILL
    _sr3q-root-a _sr3q-root-c STREAMS-OPROOT-SIZE MOVE
    _sr3q-rid-zero 8 1024 4 60000 _sr3q-root-a
        STREAMS-OPROOT-TEMPLATE-INIT
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SIZE
    _sr3q-root-c STREAMS-OPROOT-SIZE
        COMPARE 0= _sr3q-assert

    _sr3q-root-a 8 1024 4 60000 _sr3q-root-a
        STREAMS-OPROOT-TEMPLATE-INIT
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SIZE
    _sr3q-root-c STREAMS-OPROOT-SIZE
        COMPARE 0= _sr3q-assert

    _sr3q-rid-h 8 1024 9 60000 _sr3q-root-a
        STREAMS-OPROOT-TEMPLATE-INIT
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SIZE
    _sr3q-root-c STREAMS-OPROOT-SIZE
        COMPARE 0= _sr3q-assert

    _sr3q-rid-h 8 0 4 60000 _sr3q-root-a
        STREAMS-OPROOT-TEMPLATE-INIT
        STREAMS-OPREC-S-INVALID = _sr3q-assert
    _sr3q-root-a STREAMS-OPROOT-SIZE
    _sr3q-root-c STREAMS-OPROOT-SIZE
        COMPARE 0= _sr3q-assert
    _sr3q-stack ;

: _SR3Q-RUN  ( -- )
    0 _sr3q-fails !
    0 _sr3q-checks !
    DEPTH _sr3q-depth !
    _sr3q-setup-identities
    _sr3q-stack
    _sr3q-test-constants
    _sr3q-test-tree-mapping
    _sr3q-test-big-endian
    _sr3q-test-values
    _sr3q-test-config-and-checkpoint-keys
    _sr3q-test-attempt-and-order-keys
    _sr3q-test-idempotency-keys
    _sr3q-test-usage-keys
    _sr3q-test-index-nonmutation
    _sr3q-test-attempt-record
    _sr3q-test-attempt-states
    _sr3q-test-receipt-record
    _sr3q-test-root-record
    _sr3q-test-root-init-nonmutation
    _sr3q-fails @ 0= IF
        ." STREAMS SR3 RECORDS PASS" CR
    ELSE
        ." STREAMS SR3 RECORDS FAIL " _sr3q-fails @ . CR
    THEN ;
