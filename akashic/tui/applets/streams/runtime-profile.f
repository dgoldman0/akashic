\ =====================================================================
\ runtime-profile.f - named storage-free Streams runtime profiles
\ =====================================================================
\ Profiles describe supported SR2 execution workspaces; they do not allocate
\ them.  A caller supplies every payload segment, segment table, connector
\ operation workspace, flow descriptor, and pool entry.
\
\ Compact and standard cells may coexist in one pool.  Selecting the standard
\ profile for one larger request therefore does not enlarge every cell.  These
\ are current prerelease runtime profiles, not durable formats; measurements
\ may replace their exact values before release.
\ =====================================================================

PROVIDED akashic-streams-profile

1 CONSTANT STREAMS-RUNTIME-PROFILE-COMPACT
2 CONSTANT STREAMS-RUNTIME-PROFILE-STANDARD

4096 CONSTANT STREAMS-RUNTIME-SEGMENT-BYTES
1    CONSTANT STREAMS-RUNTIME-COMPACT-SEGMENTS
4    CONSTANT STREAMS-RUNTIME-STANDARD-SEGMENTS
256  CONSTANT STREAMS-RUNTIME-COMPACT-OPERATION-BYTES
512  CONSTANT STREAMS-RUNTIME-STANDARD-OPERATION-BYTES

: STREAMS-RUNTIME-PROFILE-VALID?  ( profile -- flag )
    DUP STREAMS-RUNTIME-PROFILE-COMPACT =
    SWAP STREAMS-RUNTIME-PROFILE-STANDARD = OR ;

: STREAMS-RUNTIME-INGRESS-SEGMENTS  ( profile -- count )
    DUP STREAMS-RUNTIME-PROFILE-COMPACT = IF
        DROP STREAMS-RUNTIME-COMPACT-SEGMENTS EXIT
    THEN
    STREAMS-RUNTIME-PROFILE-STANDARD =
    IF STREAMS-RUNTIME-STANDARD-SEGMENTS ELSE 0 THEN ;

: STREAMS-RUNTIME-EGRESS-SEGMENTS  ( profile -- count )
    STREAMS-RUNTIME-INGRESS-SEGMENTS ;

: STREAMS-RUNTIME-INGRESS-CAPACITY  ( profile -- bytes )
    STREAMS-RUNTIME-INGRESS-SEGMENTS STREAMS-RUNTIME-SEGMENT-BYTES * ;

: STREAMS-RUNTIME-EGRESS-CAPACITY  ( profile -- bytes )
    STREAMS-RUNTIME-EGRESS-SEGMENTS STREAMS-RUNTIME-SEGMENT-BYTES * ;

: STREAMS-RUNTIME-OPERATION-CAPACITY  ( profile -- bytes )
    DUP STREAMS-RUNTIME-PROFILE-COMPACT = IF
        DROP STREAMS-RUNTIME-COMPACT-OPERATION-BYTES EXIT
    THEN
    STREAMS-RUNTIME-PROFILE-STANDARD =
    IF STREAMS-RUNTIME-STANDARD-OPERATION-BYTES ELSE 0 THEN ;

: STREAMS-RUNTIME-PAYLOAD-CAPACITY  ( profile -- bytes )
    DUP STREAMS-RUNTIME-INGRESS-CAPACITY
    SWAP STREAMS-RUNTIME-EGRESS-CAPACITY + ;

: STREAMS-RUNTIME-SEGMENT-TABLE-BYTES  ( profile segment-size -- bytes )
    >R
    DUP STREAMS-RUNTIME-INGRESS-SEGMENTS
    SWAP STREAMS-RUNTIME-EGRESS-SEGMENTS +
    R> * ;
