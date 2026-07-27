\ =====================================================================
\  hmac-sha256.f - Caller-owned, zeroizing HMAC-SHA-256
\ =====================================================================
\  This module provides the generic message-authentication primitive used
\  by deterministic ECDSA and OAuth protocol machinery.  It owns no mutable
\  storage and has no protocol policy.  Every operation stages keys, pads,
\  and the result in a caller-provided workspace, publishes the digest only
\  after both SHA-256 passes complete, and clears the entire workspace before
\  returning from every admitted computation.
\
\  Rejected calls do not modify either the destination or workspace.
\  Returned success and lower-layer crypto failure statuses prove that the
\  workspace was cleared.  A publication or cleanup THROW is propagated
\  rather than normalized; depending on its phase, destination publication
\  and/or workspace containment may then be ambiguous.
\  Key and message spans may overlap each other, but neither may overlap the
\  destination or workspace.
\
\  Public API:
\    HMAC-SHA256-DIGEST-SIZE     ( -- 32 )
\    HMAC-SHA256-WORKSPACE-SIZE  ( -- 192 )
\    HMAC-SHA256-STATUS-VALID?   ( status -- flag )
\    HMAC-SHA256-WORKSPACE-CLEAR ( workspace -- status )
\    HMAC-SHA256                 ( key key-u message message-u
\                                  digest workspace -- status )
\ =====================================================================

PROVIDED akashic-hmac-sha256

REQUIRE sha256.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Public constants and status vocabulary
\ =====================================================================

0 CONSTANT HMAC-SHA256-S-OK
1 CONSTANT HMAC-SHA256-S-INVALID
2 CONSTANT HMAC-SHA256-S-ALIAS
3 CONSTANT HMAC-SHA256-S-CRYPTO

32  CONSTANT HMAC-SHA256-DIGEST-SIZE
192 CONSTANT HMAC-SHA256-WORKSPACE-SIZE

: HMAC-SHA256-STATUS-VALID?  ( status -- flag )
    DUP HMAC-SHA256-S-OK >=
    SWAP HMAC-SHA256-S-CRYPTO <= AND ;

\ =====================================================================
\  Workspace layout
\ =====================================================================
\  Pointers and lengths are transient operation metadata.  They are kept
\  only inside the workspace so nested helpers need no module globals, and
\  are scrubbed with the key material before the public word returns.

  0 CONSTANT _H256-KEY-OFF
  8 CONSTANT _H256-KEY-U-OFF
 16 CONSTANT _H256-MESSAGE-OFF
 24 CONSTANT _H256-MESSAGE-U-OFF
 32 CONSTANT _H256-DIGEST-OFF
 40 CONSTANT _H256-RESERVED-OFF
 64 CONSTANT _H256-BLOCK-OFF
128 CONSTANT _H256-INNER-OFF
160 CONSTANT _H256-RESULT-OFF

: _H256.KEY       ( workspace -- address ) _H256-KEY-OFF + ;
: _H256.KEY-U     ( workspace -- address ) _H256-KEY-U-OFF + ;
: _H256.MESSAGE   ( workspace -- address ) _H256-MESSAGE-OFF + ;
: _H256.MESSAGE-U ( workspace -- address ) _H256-MESSAGE-U-OFF + ;
: _H256.DIGEST    ( workspace -- address ) _H256-DIGEST-OFF + ;
: _H256.BLOCK     ( workspace -- address ) _H256-BLOCK-OFF + ;
: _H256.INNER     ( workspace -- address ) _H256-INNER-OFF + ;
: _H256.RESULT    ( workspace -- address ) _H256-RESULT-OFF + ;

: _H256-DROP6  ( x1 x2 x3 x4 x5 x6 -- )
    2DROP 2DROP 2DROP ;

: _H256-6DUP  ( six values -- the same six values twice )
    5 PICK 5 PICK 5 PICK 5 PICK 5 PICK 5 PICK ;

: _H256-READ-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _H256-FIXED-SPAN?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

\ Map the complete lower SHA caller-span vocabulary before any HMAC-owned
\ byte can be changed.  Public geometry and reserved aliases retain their
\ HMAC meaning; a physical-window or checked-boundary failure is CRYPTO.
: _H256-SHA-SPAN>STATUS  ( address length -- status )
    SHA256-CALLER-SPAN-STATUS
    DUP SHA256-S-OK = IF
        DROP HMAC-SHA256-S-OK EXIT
    THEN
    DUP SHA256-S-INVALID = IF
        DROP HMAC-SHA256-S-INVALID EXIT
    THEN
    DUP SHA256-S-ALIAS = IF
        DROP HMAC-SHA256-S-ALIAS EXIT
    THEN
    DROP HMAC-SHA256-S-CRYPTO ;

: HMAC-SHA256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP HMAC-SHA256-WORKSPACE-SIZE
        _H256-FIXED-SPAN? 0= IF
        DROP HMAC-SHA256-S-INVALID EXIT
    THEN
    DUP HMAC-SHA256-WORKSPACE-SIZE
        _H256-SHA-SPAN>STATUS ?DUP IF
        NIP EXIT
    THEN
    HMAC-SHA256-WORKSPACE-SIZE 0 FILL
    HMAC-SHA256-S-OK ;

\ Validate every span and alias relationship before the workspace or output
\ is touched.  The two borrowed inputs may overlap one another.
: _H256-PREFLIGHT
  ( key key-u message message-u digest workspace -- status )
    DUP HMAC-SHA256-WORKSPACE-SIZE _H256-FIXED-SPAN? 0= IF
        _H256-DROP6 HMAC-SHA256-S-INVALID EXIT
    THEN
    OVER HMAC-SHA256-DIGEST-SIZE _H256-FIXED-SPAN? 0= IF
        _H256-DROP6 HMAC-SHA256-S-INVALID EXIT
    THEN
    5 PICK 5 PICK _H256-READ-SPAN? 0= IF
        _H256-DROP6 HMAC-SHA256-S-INVALID EXIT
    THEN
    3 PICK 3 PICK _H256-READ-SPAN? 0= IF
        _H256-DROP6 HMAC-SHA256-S-INVALID EXIT
    THEN

    \ The SHA transaction mutates both its algorithm guard and the shared
    \ CRYPTO-ACC footprint.  Reject every caller span against that complete
    \ footprint before the workspace is initialized or the digest is staged.
    5 PICK 5 PICK _H256-SHA-SPAN>STATUS ?DUP IF
        >R _H256-DROP6 R> EXIT
    THEN
    3 PICK 3 PICK _H256-SHA-SPAN>STATUS ?DUP IF
        >R _H256-DROP6 R> EXIT
    THEN
    OVER HMAC-SHA256-DIGEST-SIZE _H256-SHA-SPAN>STATUS ?DUP IF
        >R _H256-DROP6 R> EXIT
    THEN
    DUP HMAC-SHA256-WORKSPACE-SIZE _H256-SHA-SPAN>STATUS ?DUP IF
        >R _H256-DROP6 R> EXIT
    THEN

    OVER HMAC-SHA256-DIGEST-SIZE
    2 PICK HMAC-SHA256-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _H256-DROP6 HMAC-SHA256-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK
    2 PICK HMAC-SHA256-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _H256-DROP6 HMAC-SHA256-S-ALIAS EXIT
    THEN
    3 PICK 3 PICK
    2 PICK HMAC-SHA256-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _H256-DROP6 HMAC-SHA256-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK
    3 PICK HMAC-SHA256-DIGEST-SIZE MSPAN-OVERLAP? IF
        _H256-DROP6 HMAC-SHA256-S-ALIAS EXIT
    THEN
    3 PICK 3 PICK
    3 PICK HMAC-SHA256-DIGEST-SIZE MSPAN-OVERLAP? IF
        _H256-DROP6 HMAC-SHA256-S-ALIAS EXIT
    THEN
    _H256-DROP6 HMAC-SHA256-S-OK ;

\ =====================================================================
\  HMAC construction
\ =====================================================================

: _H256-XOR-BLOCK  ( workspace mask -- )
    64 0 DO
        OVER _H256.BLOCK I +
        DUP C@ 2 PICK XOR SWAP C!
    LOOP
    2DROP ;

: _H256-NORMALIZE-KEY  ( workspace -- status )
    DUP _H256.KEY-U @ 64 > IF
        DUP _H256.KEY @
        OVER _H256.KEY-U @
        2 PICK _H256.BLOCK
        SHA256-HASH
        DUP IF
            2DROP HMAC-SHA256-S-CRYPTO EXIT
        THEN
        DROP
    ELSE
        DUP _H256.KEY @
        OVER _H256.KEY-U @
        2 PICK _H256.BLOCK
        SWAP MOVE
    THEN
    DROP HMAC-SHA256-S-OK ;

\ The digest is deliberately not published here.  Any returned SHA failure
\ is mapped to CRYPTO; a SHA THROW returns through the public CATCH while
\ the result remains private to the workspace.
: _H256-RUN  ( workspace -- status )
    DUP _H256-NORMALIZE-KEY
    DUP IF NIP EXIT THEN
    DROP
    DUP 0x36 _H256-XOR-BLOCK

    DUP _H256.MESSAGE @
    OVER _H256.MESSAGE-U @
    2 PICK _H256.BLOCK 64 2SWAP
    4 PICK _H256.INNER
    SHA256-HASH-2
    DUP IF
        2DROP HMAC-SHA256-S-CRYPTO EXIT
    THEN
    DROP

    \ ipad XOR 0x36 XOR 0x5c = opad.
    DUP 0x6A _H256-XOR-BLOCK
    DUP _H256.BLOCK 64
    2 PICK _H256.INNER HMAC-SHA256-DIGEST-SIZE
    4 PICK _H256.RESULT
    SHA256-HASH-2
    DUP IF
        2DROP HMAC-SHA256-S-CRYPTO EXIT
    THEN
    2DROP HMAC-SHA256-S-OK ;

: _H256-BIND
  ( key key-u message message-u digest workspace -- workspace )
    DUP HMAC-SHA256-WORKSPACE-SIZE 0 FILL
    5 PICK OVER _H256.KEY !
    4 PICK OVER _H256.KEY-U !
    3 PICK OVER _H256.MESSAGE !
    2 PICK OVER _H256.MESSAGE-U !
    OVER OVER _H256.DIGEST !
    >R 2DROP 2DROP DROP R> ;

: _H256-ADMITTED
  ( key key-u message message-u digest workspace -- workspace status )
    _H256-BIND
    DUP _H256-RUN ;

\ Digest publication is intentionally its own phase and retains the
\ workspace for the mandatory wipe.  It never executes inside the boundary
\ that converts pre-publication computation exceptions to CRYPTO.
: _H256-PUBLISH  ( workspace -- workspace )
    DUP _H256.RESULT
    OVER _H256.DIGEST @
    HMAC-SHA256-DIGEST-SIZE MOVE ;

\ Bind and both SHA passes are pre-publication computation.  CATCH restores
\ all six public arguments on THROW; retain the independently preflighted
\ workspace so the public word can wipe it before returning CRYPTO.
: _H256-COMPUTE-CALL
  ( key key-u message message-u digest workspace xt -- workspace status )
    1 PICK >R
    CATCH
    ?DUP IF
        >R _H256-DROP6 R> DROP
        R> HMAC-SHA256-S-CRYPTO EXIT
    THEN
    R> DROP ;

\ A returned computation failure is only publishable after the secret
\ workspace has actually been cleared.  A cleanup THROW escapes unchanged;
\ reporting CRYPTO in that case would falsely claim containment.
: _H256-CLEAR-RETURN  ( workspace status -- status )
    >R
    HMAC-SHA256-WORKSPACE-SIZE 0 FILL
    R> ;

\ Publication faults are intrinsically ambiguous: MOVE may have changed any
\ prefix of the caller's digest.  Attempt the secret wipe, then rethrow the
\ publication exception.  If that wipe itself throws, its exception escapes
\ instead; no returned status claims that either output is contained.
: _H256-PUBLISH-CLEAR  ( workspace -- status | throws )
    ['] _H256-PUBLISH CATCH
    ?DUP IF
        >R
        HMAC-SHA256-WORKSPACE-SIZE 0 FILL
        R> THROW
    THEN
    HMAC-SHA256-WORKSPACE-SIZE 0 FILL
    HMAC-SHA256-S-OK ;

: HMAC-SHA256
  ( key key-u message message-u digest workspace -- status )
    _H256-6DUP _H256-PREFLIGHT DUP IF
        >R _H256-DROP6 R> EXIT
    THEN
    DROP
    ['] _H256-ADMITTED _H256-COMPUTE-CALL
    DUP IF
        _H256-CLEAR-RETURN EXIT
    THEN
    DROP
    _H256-PUBLISH-CLEAR ;

\ Compile-time layout checks prevent a later edit from silently making
\ one secret region overlap another.
: _H256-GEOMETRY-ABORT  ( -- )
    ." HMAC-SHA256 workspace geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _H256-GEOMETRY-ABORT
[THEN]

_H256-RESERVED-OFF 24 + _H256-BLOCK-OFF <> [IF]
    _H256-GEOMETRY-ABORT
[THEN]

_H256-BLOCK-OFF 64 + _H256-INNER-OFF <> [IF]
    _H256-GEOMETRY-ABORT
[THEN]

_H256-INNER-OFF 32 + _H256-RESULT-OFF <> [IF]
    _H256-GEOMETRY-ABORT
[THEN]

_H256-RESULT-OFF 32 + HMAC-SHA256-WORKSPACE-SIZE <> [IF]
    _H256-GEOMETRY-ABORT
[THEN]
