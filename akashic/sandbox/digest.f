\ =====================================================================
\  digest.f - Caller-owned sandbox SHA3-256 identity publication
\ =====================================================================
\  Raw hashing and every sandbox identity domain share this one mechanical
\  seam.  The module owns no mutable hash engine, scratch buffer, allocator,
\  Context, registry, host service, or authority.  Source and destination
\  bytes and the complete workspace remain caller-owned.
\
\  Domain-separated identities hash:
\
\      UTF-8 domain bytes || 0x00 || exact source bytes
\
\  The separator makes the construction unambiguous without length-prefix
\  state.  RAW hashes only the exact source bytes.
\
\  Ordinary preflight rejection leaves workspace and destination untouched.
\  Every admitted returned failure wipes the complete workspace.  Success
\  computes into the private workspace stage, publishes exactly 32 bytes,
\  then wipes the workspace.  A native publication or mandatory-wipe fault
\  is rethrown after the best possible wipe; a higher owner must invalidate
\  its semantic result and finish its own cleanup.
\ =====================================================================

REQUIRE ../utils/memory-span.f
REQUIRE ../math/sha3-context.f

0 CONSTANT SBOX-DIGEST-S-OK
1 CONSTANT SBOX-DIGEST-S-INVALID
2 CONSTANT SBOX-DIGEST-S-CAPACITY
3 CONSTANT SBOX-DIGEST-S-ALIAS
4 CONSTANT SBOX-DIGEST-S-FAULT

32  CONSTANT SBOX-DIGEST-SIZE
720 CONSTANT SBOX-DIGEST-WORKSPACE-SIZE

-1 1 RSHIFT CONSTANT _SDIG-LENGTH-MAX

  0 CONSTANT _SDW-SOURCE-OFF
  8 CONSTANT _SDW-SOURCE-U-OFF
 16 CONSTANT _SDW-DIGEST-OFF
 24 CONSTANT _SDW-PREFIX-OFF
 32 CONSTANT _SDW-PREFIX-U-OFF
 40 CONSTANT _SDW-CONTEXT-OFF
688 CONSTANT _SDW-STAGE-OFF

: _SDW.SOURCE    ( workspace -- address ) _SDW-SOURCE-OFF + ;
: _SDW.SOURCE-U  ( workspace -- address ) _SDW-SOURCE-U-OFF + ;
: _SDW.DIGEST    ( workspace -- address ) _SDW-DIGEST-OFF + ;
: _SDW.PREFIX    ( workspace -- address ) _SDW-PREFIX-OFF + ;
: _SDW.PREFIX-U  ( workspace -- address ) _SDW-PREFIX-U-OFF + ;
: _SDW.CONTEXT   ( workspace -- address ) _SDW-CONTEXT-OFF + ;
: _SDW.STAGE     ( workspace -- address ) _SDW-STAGE-OFF + ;

: _SDIG-PROFILE$  ( -- address length )
    S" akashic.sandbox.profile" ;

: _SDIG-ARTIFACT$  ( -- address length )
    S" akashic.sandbox.artifact" ;

: _SDIG-SCHEMA$  ( -- address length )
    S" akashic.sandbox.schema" ;

: _SDIG-DECLARATION$  ( -- address length )
    S" akashic.sandbox.declaration" ;

: _SDIG-INPUT$  ( -- address length )
    S" akashic.sandbox.value.input" ;

: _SDIG-OUTPUT$  ( -- address length )
    S" akashic.sandbox.value.output" ;

: _SDIG-GEOMETRY-ABORT  ( -- )
    ." sandbox digest geometry mismatch" CR ABORT ;

\ Fail before registering a layout incompatible with the caller-owned SHA3
\ context or the normative domain strings.
1 CELLS 8 <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDW-CONTEXT-OFF SHA3-256-CONTEXT-SIZE +
    _SDW-STAGE-OFF <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDW-STAGE-OFF SBOX-DIGEST-SIZE +
    SBOX-DIGEST-WORKSPACE-SIZE <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

SBOX-DIGEST-SIZE SHA3-256-CONTEXT-DIGEST-SIZE <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDIG-PROFILE$ NIP 23 <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDIG-ARTIFACT$ NIP 24 <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDIG-SCHEMA$ NIP 22 <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDIG-DECLARATION$ NIP 27 <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDIG-INPUT$ NIP 27 <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

_SDIG-OUTPUT$ NIP 28 <> [IF]
    _SDIG-GEOMETRY-ABORT
[THEN]

PROVIDED akashic-sbx-digest

: SBOX-DIGEST-STATUS-VALID?  ( status -- flag )
    DUP SBOX-DIGEST-S-OK >=
    SWAP SBOX-DIGEST-S-FAULT <= AND ;

: _SDIG-DROP6  ( x1 x2 x3 x4 x5 x6 -- )
    2DROP 2DROP 2DROP ;

: _SDIG-6DUP
  ( x1 x2 x3 x4 x5 x6 -- x1 x2 x3 x4 x5 x6 x1 x2 x3 x4 x5 x6 )
    5 PICK 5 PICK 5 PICK 5 PICK 5 PICK 5 PICK ;

: _SDIG-READ-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SDIG-FIXED-SPAN?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SDIG-PREFIX-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

\ Raw hashing has no prefix or separator.  A separated operation must also
\ fit its one separator byte before any SHA3 state is initialized.
: _SDIG-LENGTH-STATUS  ( source-u prefix-u -- status )
    DUP 0= IF 2DROP SBOX-DIGEST-S-OK EXIT THEN
    DUP _SDIG-LENGTH-MAX 1- U> IF
        2DROP SBOX-DIGEST-S-CAPACITY EXIT
    THEN
    1+ >R
    DUP _SDIG-LENGTH-MAX R@ - U> IF
        DROP R> DROP SBOX-DIGEST-S-CAPACITY EXIT
    THEN
    DROP R> DROP SBOX-DIGEST-S-OK ;

: _SDIG-PREFLIGHT
  ( source source-u digest workspace prefix prefix-u -- status )
    2 PICK SBOX-DIGEST-WORKSPACE-SIZE _SDIG-FIXED-SPAN? 0= IF
        _SDIG-DROP6 SBOX-DIGEST-S-INVALID EXIT
    THEN
    2 PICK 7 AND IF
        _SDIG-DROP6 SBOX-DIGEST-S-INVALID EXIT
    THEN
    3 PICK SBOX-DIGEST-SIZE _SDIG-FIXED-SPAN? 0= IF
        _SDIG-DROP6 SBOX-DIGEST-S-INVALID EXIT
    THEN
    5 PICK 5 PICK _SDIG-READ-SPAN? 0= IF
        _SDIG-DROP6 SBOX-DIGEST-S-INVALID EXIT
    THEN
    1 PICK 1 PICK _SDIG-PREFIX-SPAN? 0= IF
        _SDIG-DROP6 SBOX-DIGEST-S-INVALID EXIT
    THEN
    4 PICK OVER _SDIG-LENGTH-STATUS ?DUP IF
        >R _SDIG-DROP6 R> EXIT
    THEN

    5 PICK 5 PICK 4 PICK SBOX-DIGEST-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        _SDIG-DROP6 SBOX-DIGEST-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK 5 PICK SBOX-DIGEST-SIZE
        MSPAN-OVERLAP? IF
        _SDIG-DROP6 SBOX-DIGEST-S-ALIAS EXIT
    THEN
    3 PICK SBOX-DIGEST-SIZE
        4 PICK SBOX-DIGEST-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _SDIG-DROP6 SBOX-DIGEST-S-ALIAS EXIT
    THEN
    1 PICK 1 PICK 4 PICK SBOX-DIGEST-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        _SDIG-DROP6 SBOX-DIGEST-S-ALIAS EXIT
    THEN
    1 PICK 1 PICK 5 PICK SBOX-DIGEST-SIZE
        MSPAN-OVERLAP? IF
        _SDIG-DROP6 SBOX-DIGEST-S-ALIAS EXIT
    THEN
    _SDIG-DROP6 SBOX-DIGEST-S-OK ;

: _SDIG-BIND
  ( source source-u digest workspace prefix prefix-u -- workspace )
    2 PICK >R
    R@ SBOX-DIGEST-WORKSPACE-SIZE 0 FILL
    5 PICK R@ _SDW.SOURCE !
    4 PICK R@ _SDW.SOURCE-U !
    3 PICK R@ _SDW.DIGEST !
    1 PICK R@ _SDW.PREFIX !
    DUP R@ _SDW.PREFIX-U !
    _SDIG-DROP6 R> ;

: _SDIG-CONTEXT>STATUS  ( sha3-status -- status )
    DUP SHA3-CONTEXT-S-OK = IF
        DROP SBOX-DIGEST-S-OK EXIT
    THEN
    DUP SHA3-CONTEXT-S-CAPACITY = IF
        DROP SBOX-DIGEST-S-CAPACITY EXIT
    THEN
    DROP SBOX-DIGEST-S-FAULT ;

: _SDIG-RUN  ( workspace -- status )
    DUP _SDW.CONTEXT SHA3-256-CONTEXT-INIT
        _SDIG-CONTEXT>STATUS
    DUP IF NIP EXIT THEN DROP

    DUP _SDW.PREFIX-U @ ?DUP IF
        OVER _SDW.PREFIX @ SWAP
        2 PICK _SDW.CONTEXT
        SHA3-256-CONTEXT-UPDATE _SDIG-CONTEXT>STATUS
        DUP IF NIP EXIT THEN DROP

        \ _SDW.STAGE is still zero from _SDIG-BIND.
        DUP _SDW.STAGE 1
        2 PICK _SDW.CONTEXT
        SHA3-256-CONTEXT-UPDATE _SDIG-CONTEXT>STATUS
        DUP IF NIP EXIT THEN DROP
    THEN

    DUP _SDW.SOURCE @
    OVER _SDW.SOURCE-U @
    2 PICK _SDW.CONTEXT
    SHA3-256-CONTEXT-UPDATE _SDIG-CONTEXT>STATUS
    DUP IF NIP EXIT THEN DROP

    DUP _SDW.STAGE
    OVER _SDW.CONTEXT
    SHA3-256-CONTEXT-FINAL _SDIG-CONTEXT>STATUS
    NIP ;

: _SDIG-ADMITTED
  ( source source-u digest workspace prefix prefix-u -- workspace status )
    _SDIG-BIND DUP _SDIG-RUN ;

: _SDIG-COMPUTE-CALL
  ( source source-u digest workspace prefix prefix-u xt -- workspace status )
    3 PICK >R
    CATCH
    ?DUP IF
        >R _SDIG-DROP6 R> DROP
        R> SBOX-DIGEST-S-FAULT EXIT
    THEN
    R> DROP ;

: _SDIG-CLEAR-RETURN  ( workspace status -- status | throws )
    >R
    SBOX-DIGEST-WORKSPACE-SIZE 0 FILL
    R> ;

: _SDIG-PUBLISH  ( workspace -- workspace | throws )
    DUP _SDW.STAGE
    OVER _SDW.DIGEST @
    SBOX-DIGEST-SIZE MOVE ;

: _SDIG-PUBLISH-CLEAR  ( workspace -- status | throws )
    ['] _SDIG-PUBLISH CATCH
    ?DUP IF
        >R
        SBOX-DIGEST-WORKSPACE-SIZE 0 FILL
        R> THROW
    THEN
    SBOX-DIGEST-WORKSPACE-SIZE 0 FILL
    SBOX-DIGEST-S-OK ;

: _SBOX-DIGEST
  ( source source-u digest workspace prefix prefix-u -- status | throws )
    _SDIG-6DUP _SDIG-PREFLIGHT DUP IF
        >R _SDIG-DROP6 R> EXIT
    THEN
    DROP
    ['] _SDIG-ADMITTED _SDIG-COMPUTE-CALL
    DUP IF
        _SDIG-CLEAR-RETURN EXIT
    THEN
    DROP
    _SDIG-PUBLISH-CLEAR ;

: SBOX-DIGEST-WORKSPACE-CLEAR  ( workspace -- status | throws )
    DUP SBOX-DIGEST-WORKSPACE-SIZE _SDIG-FIXED-SPAN? 0= IF
        DROP SBOX-DIGEST-S-INVALID EXIT
    THEN
    DUP 7 AND IF DROP SBOX-DIGEST-S-INVALID EXIT THEN
    SBOX-DIGEST-WORKSPACE-SIZE 0 FILL
    SBOX-DIGEST-S-OK ;

: SBOX-DIGEST-RAW
  ( source source-u digest workspace -- status | throws )
    0 0 _SBOX-DIGEST ;

: SBOX-DIGEST-PROFILE
  ( source source-u digest workspace -- status | throws )
    _SDIG-PROFILE$ _SBOX-DIGEST ;

: SBOX-DIGEST-ARTIFACT
  ( source source-u digest workspace -- status | throws )
    _SDIG-ARTIFACT$ _SBOX-DIGEST ;

: SBOX-DIGEST-SCHEMA
  ( source source-u digest workspace -- status | throws )
    _SDIG-SCHEMA$ _SBOX-DIGEST ;

: SBOX-DIGEST-DECLARATION
  ( source source-u digest workspace -- status | throws )
    _SDIG-DECLARATION$ _SBOX-DIGEST ;

: SBOX-DIGEST-VALUE-INPUT
  ( source source-u digest workspace -- status | throws )
    _SDIG-INPUT$ _SBOX-DIGEST ;

: SBOX-DIGEST-VALUE-OUTPUT
  ( source source-u digest workspace -- status | throws )
    _SDIG-OUTPUT$ _SBOX-DIGEST ;
