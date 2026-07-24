\ =====================================================================
\  semantic-record-agreement.f - Streams semantic lineage agreement
\ =====================================================================
\  These pure predicates join complete checked Streams records across the
\  stable semantic IDs retained in them.  Every public predicate validates
\  every supplied record completely before it reads fields for agreement.
\  Invalid, corrupt, wrong-kind, or wrong-size records fail closed.
\
\  Observation publication requires the referenced attempt to be exactly
\  OCHK-ATTEMPT-SUCCEEDED.  ACCEPTED is durable in-flight evidence only;
\  FAILED, CANCELLED, and INDETERMINATE attempts do not authorize a visible
\  observation revision.
\
\  Historical observation/native-head agreement admits any positive
\  observation revision at or below the head's latest revision.  Current-head
\  agreement is stricter and requires equality with the latest revision.
\  Publication additionally requires the head's last-seen sequence to equal
\  the observation/attempt acquisition sequence.  A later unchanged attempt
\  may advance last-seen without invalidating an ordinary current-head read.
\
\  These predicates make no claim that a PBLOB descriptor names bytes whose
\  digest equals SPRO.CONTENT-DIGEST.  That proof requires storage authority
\  and bounded blob readback, and remains the responsibility of construction,
\  migration verification, and compaction before publication.
\
\  Public API:
\    STREAMS-SRA-OBSERVATION-ATTEMPT-AGREES?
\      ( observation attempt -- flag )
\    STREAMS-SRA-OBSERVATION-NATIVE-HEAD-AGREES?
\      ( observation native-head -- flag )
\    STREAMS-SRA-OBSERVATION-CURRENT-HEAD-AGREES?
\      ( observation native-head -- flag )
\    STREAMS-SRA-OBSERVATION-PUBLICATION-AGREES?
\      ( observation attempt native-head -- flag )
\
\  This module owns no mutable state and performs no I/O.
\ =====================================================================

PROVIDED akashic-tui-streams-semantic-record-agreement

REQUIRE persistence-records.f

: _SSRA-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;

\ Inputs to the private field predicates have already passed their complete
\ current-record validators.
: _SSRA-OBSERVATION-ATTEMPT-FIELDS?
  ( observation attempt -- flag )
    >R
    R@ SPRA.STATE @ OCHK-ATTEMPT-SUCCEEDED <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.ATTEMPT-ID R@ SPRA.ATTEMPT-ID RID= 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.SOURCE-ID R@ SPRA.SOURCE-ID RID= 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.NAMESPACE R@ SPRA.NAMESPACE SHA3-256-COMPARE 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.ACQUISITION-SEQUENCE @
    R@ SPRA.ATTEMPT-SEQUENCE @ =
    NIP R> DROP ;

: _SSRA-OBSERVATION-NATIVE-HEAD-FIELDS?
  ( observation native-head -- flag )
    >R
    DUP SPRO.OBSERVATION-ID R@ SPRH.OBSERVATION-ID RID= 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.SOURCE-ID R@ SPRH.SOURCE-ID RID= 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.NAMESPACE R@ SPRH.NAMESPACE SHA3-256-COMPARE 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.OBSERVATION-FORMAT @
    R@ SPRH.OBSERVATION-FORMAT @ <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.REVISION @ R@ SPRH.LATEST-REVISION @ > IF
        DROP R> DROP 0 EXIT
    THEN
    DUP SPRO.ACQUISITION-SEQUENCE @
    R@ SPRH.LAST-SEEN-SEQUENCE @ <=
    NIP R> DROP ;

: _SSRA-OBSERVATION-CURRENT-HEAD-FIELDS?
  ( observation native-head -- flag )
    2DUP _SSRA-OBSERVATION-NATIVE-HEAD-FIELDS? 0= IF
        2DROP 0 EXIT
    THEN
    >R SPRO.REVISION @ R> SPRH.LATEST-REVISION @ = ;

: _SSRA-OBSERVATION-PUBLICATION-HEAD-FIELDS?
  ( observation native-head -- flag )
    2DUP _SSRA-OBSERVATION-CURRENT-HEAD-FIELDS? 0= IF
        2DROP 0 EXIT
    THEN
    >R SPRO.ACQUISITION-SEQUENCE @
    R> SPRH.LAST-SEEN-SEQUENCE @ = ;

: STREAMS-SRA-OBSERVATION-ATTEMPT-AGREES?
  ( observation attempt -- flag )
    OVER SPREC-OBSERVATION-SIZE SPREC-OBSERVATION-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    DUP SPREC-ATTEMPT-SIZE SPREC-ATTEMPT-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    _SSRA-OBSERVATION-ATTEMPT-FIELDS? ;

: STREAMS-SRA-OBSERVATION-NATIVE-HEAD-AGREES?
  ( observation native-head -- flag )
    OVER SPREC-OBSERVATION-SIZE SPREC-OBSERVATION-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    DUP SPREC-NATIVE-HEAD-SIZE SPREC-NATIVE-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    _SSRA-OBSERVATION-NATIVE-HEAD-FIELDS? ;

: STREAMS-SRA-OBSERVATION-CURRENT-HEAD-AGREES?
  ( observation native-head -- flag )
    OVER SPREC-OBSERVATION-SIZE SPREC-OBSERVATION-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    DUP SPREC-NATIVE-HEAD-SIZE SPREC-NATIVE-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    _SSRA-OBSERVATION-CURRENT-HEAD-FIELDS? ;

: STREAMS-SRA-OBSERVATION-PUBLICATION-AGREES?
  ( observation attempt native-head -- flag )
    2 PICK SPREC-OBSERVATION-SIZE SPREC-OBSERVATION-VALID? 0= IF
        _SSRA-DROP3 0 EXIT
    THEN
    OVER SPREC-ATTEMPT-SIZE SPREC-ATTEMPT-VALID? 0= IF
        _SSRA-DROP3 0 EXIT
    THEN
    DUP SPREC-NATIVE-HEAD-SIZE SPREC-NATIVE-VALID? 0= IF
        _SSRA-DROP3 0 EXIT
    THEN
    >R
    2DUP _SSRA-OBSERVATION-ATTEMPT-FIELDS? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DROP R> _SSRA-OBSERVATION-PUBLICATION-HEAD-FIELDS? ;
