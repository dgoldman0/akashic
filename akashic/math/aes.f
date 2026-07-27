\ =====================================================================
\  aes.f - Caller-owned AES-128/256-GCM authenticated encryption
\ =====================================================================
\  This is the generic Akashic boundary for the Megapad AES-GCM engine.
\  It owns no key, selected mode, current tag, streaming lifecycle, or
\  operation scratch.  Each call receives a caller-owned descriptor and
\  workspace; key size is selected from that descriptor for the one call.
\
\  The public contract admits only 96-bit IVs and 128-bit tags.  AAD and
\  data lengths must fit the engine's unsigned 32-bit length registers.
\  Exact input/output in-place operation is supported.  Every other
\  input/output overlap, and every overlap involving mutable tag output,
\  descriptor, or workspace storage, is rejected before caller memory is
\  changed.
\
\  SEAL stages the tag until encryption and engine cleanup both succeed.
\  Any admitted SEAL failure wipes the complete ciphertext destination.
\  OPEN authenticates once without reading DOUT, clears the engine, then
\  repeats the operation to publish plaintext while rechecking the tag.
\  Authentication failure, timeout, hardware rejection, cleanup failure, or
\  caught THROW wipes the full plaintext destination.  The complete workspace
\  is cleared on every admitted return path.
\
\  Public API:
\    AES-GCM-DESCRIPTOR-SIZE       ( -- 88 )
\    AES-GCM-WORKSPACE-SIZE        ( -- 240 )
\    AES-GCM-DESCRIPTOR-CLEAR      ( descriptor -- status )
\    AES-GCM-WORKSPACE-CLEAR       ( workspace -- status )
\    AES-GCM-DESCRIPTOR-VALID?     ( descriptor -- flag )
\    AES-GCM-STATUS-VALID?         ( status -- flag )
\    AES-GCM-SEAL                  ( descriptor workspace -- status )
\    AES-GCM-OPEN                  ( descriptor workspace -- status )
\
\  Descriptor field accessors return the address of one cell:
\    AES-GCM-D.KEY       AES-GCM-D.KEY-U
\    AES-GCM-D.IV        AES-GCM-D.IV-U
\    AES-GCM-D.AAD       AES-GCM-D.AAD-U
\    AES-GCM-D.INPUT     AES-GCM-D.OUTPUT
\    AES-GCM-D.DATA-U
\    AES-GCM-D.TAG       AES-GCM-D.TAG-U
\ =====================================================================

PROVIDED akashic-aes

REQUIRE ../utils/memory-span.f
REQUIRE ../concurrency/guard.f

\ =====================================================================
\  Public geometry and status vocabulary
\ =====================================================================

16 CONSTANT AES-GCM-KEY128-SIZE
32 CONSTANT AES-GCM-KEY256-SIZE
12 CONSTANT AES-GCM-IV-SIZE
16 CONSTANT AES-GCM-TAG-SIZE
16 CONSTANT AES-GCM-BLOCK-SIZE

88  CONSTANT AES-GCM-DESCRIPTOR-SIZE
240 CONSTANT AES-GCM-WORKSPACE-SIZE

0 CONSTANT AES-GCM-S-OK
1 CONSTANT AES-GCM-S-INVALID
2 CONSTANT AES-GCM-S-ALIAS
3 CONSTANT AES-GCM-S-TIMEOUT
4 CONSTANT AES-GCM-S-HARDWARE
5 CONSTANT AES-GCM-S-AUTH
6 CONSTANT AES-GCM-S-INTERNAL

: AES-GCM-STATUS-VALID?  ( status -- flag )
    DUP AES-GCM-S-OK >=
    SWAP AES-GCM-S-INTERNAL <= AND ;

\ The MMIO length registers are exactly 32 bits.  Rejecting rather than
\ truncating larger cells keeps the declared feed geometry unambiguous.
0xFFFFFFFF CONSTANT AES-GCM-LENGTH-MAX
4096 CONSTANT AES-GCM-HARDWARE-POLL-LIMIT

\ =====================================================================
\  Caller-owned descriptor
\ =====================================================================

 0 CONSTANT _AGCM-D-KEY
 8 CONSTANT _AGCM-D-KEY-U
16 CONSTANT _AGCM-D-IV
24 CONSTANT _AGCM-D-IV-U
32 CONSTANT _AGCM-D-AAD
40 CONSTANT _AGCM-D-AAD-U
48 CONSTANT _AGCM-D-INPUT
56 CONSTANT _AGCM-D-OUTPUT
64 CONSTANT _AGCM-D-DATA-U
72 CONSTANT _AGCM-D-TAG
80 CONSTANT _AGCM-D-TAG-U

: AES-GCM-D.KEY     ( descriptor -- field ) _AGCM-D-KEY + ;
: AES-GCM-D.KEY-U   ( descriptor -- field ) _AGCM-D-KEY-U + ;
: AES-GCM-D.IV      ( descriptor -- field ) _AGCM-D-IV + ;
: AES-GCM-D.IV-U    ( descriptor -- field ) _AGCM-D-IV-U + ;
: AES-GCM-D.AAD     ( descriptor -- field ) _AGCM-D-AAD + ;
: AES-GCM-D.AAD-U   ( descriptor -- field ) _AGCM-D-AAD-U + ;
: AES-GCM-D.INPUT   ( descriptor -- field ) _AGCM-D-INPUT + ;
: AES-GCM-D.OUTPUT  ( descriptor -- field ) _AGCM-D-OUTPUT + ;
: AES-GCM-D.DATA-U  ( descriptor -- field ) _AGCM-D-DATA-U + ;
: AES-GCM-D.TAG     ( descriptor -- field ) _AGCM-D-TAG + ;
: AES-GCM-D.TAG-U   ( descriptor -- field ) _AGCM-D-TAG-U + ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================
\  All borrowed descriptor values are snapshotted before the engine is
\  touched.  KEY-STAGE prevents the BIOS's fixed 32-byte KEY write from
\  reading beyond a 16-byte AES-128 key.  The base pointers and lengths let
\  OPEN replay the exact operation only after its authentication pass has
\  succeeded.  ZERO supplies a known-zero key, IV, tag, and lengths for the
\  scoped engine-clearing transaction.

  0 CONSTANT _AGCM-W-KEY
  8 CONSTANT _AGCM-W-KEY-U
 16 CONSTANT _AGCM-W-IV
 24 CONSTANT _AGCM-W-AAD
 32 CONSTANT _AGCM-W-AAD-LEFT
 40 CONSTANT _AGCM-W-SOURCE
 48 CONSTANT _AGCM-W-DEST
 56 CONSTANT _AGCM-W-DATA-LEFT
 64 CONSTANT _AGCM-W-OUTPUT-BASE
 72 CONSTANT _AGCM-W-DATA-U
 80 CONSTANT _AGCM-W-TAG
 88 CONSTANT _AGCM-W-OP
 96 CONSTANT _AGCM-W-TAKE
104 CONSTANT _AGCM-W-STATE
112 CONSTANT _AGCM-W-AAD-BASE
120 CONSTANT _AGCM-W-AAD-U
128 CONSTANT _AGCM-W-INPUT-BASE
136 CONSTANT _AGCM-W-REQUEST
144 CONSTANT _AGCM-W-BLOCK
160 CONSTANT _AGCM-W-TAG-STAGE
176 CONSTANT _AGCM-W-KEY-STAGE
208 CONSTANT _AGCM-W-ZERO

: _AGCM-W.KEY         ( workspace -- field ) _AGCM-W-KEY + ;
: _AGCM-W.KEY-U       ( workspace -- field ) _AGCM-W-KEY-U + ;
: _AGCM-W.IV          ( workspace -- field ) _AGCM-W-IV + ;
: _AGCM-W.AAD         ( workspace -- field ) _AGCM-W-AAD + ;
: _AGCM-W.AAD-LEFT    ( workspace -- field ) _AGCM-W-AAD-LEFT + ;
: _AGCM-W.SOURCE      ( workspace -- field ) _AGCM-W-SOURCE + ;
: _AGCM-W.DEST        ( workspace -- field ) _AGCM-W-DEST + ;
: _AGCM-W.DATA-LEFT   ( workspace -- field ) _AGCM-W-DATA-LEFT + ;
: _AGCM-W.OUTPUT-BASE ( workspace -- field ) _AGCM-W-OUTPUT-BASE + ;
: _AGCM-W.DATA-U      ( workspace -- field ) _AGCM-W-DATA-U + ;
: _AGCM-W.TAG         ( workspace -- field ) _AGCM-W-TAG + ;
: _AGCM-W.OP          ( workspace -- field ) _AGCM-W-OP + ;
: _AGCM-W.TAKE        ( workspace -- field ) _AGCM-W-TAKE + ;
: _AGCM-W.STATE       ( workspace -- field ) _AGCM-W-STATE + ;
: _AGCM-W.AAD-BASE    ( workspace -- field ) _AGCM-W-AAD-BASE + ;
: _AGCM-W.AAD-U       ( workspace -- field ) _AGCM-W-AAD-U + ;
: _AGCM-W.INPUT-BASE  ( workspace -- field ) _AGCM-W-INPUT-BASE + ;
: _AGCM-W.REQUEST     ( workspace -- field ) _AGCM-W-REQUEST + ;
: _AGCM-W.BLOCK       ( workspace -- address ) _AGCM-W-BLOCK + ;
: _AGCM-W.TAG-STAGE   ( workspace -- address ) _AGCM-W-TAG-STAGE + ;
: _AGCM-W.KEY-STAGE   ( workspace -- address ) _AGCM-W-KEY-STAGE + ;
: _AGCM-W.ZERO        ( workspace -- address ) _AGCM-W-ZERO + ;

: _AGCM-WIPE-WORKSPACE  ( workspace -- )
    AES-GCM-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Span and descriptor validation
\ =====================================================================

: _AGCM-REQUIRED-SPAN?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _AGCM-OPTIONAL-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _AGCM-U32?  ( length -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    AES-GCM-LENGTH-MAX <= ;

: AES-GCM-DESCRIPTOR-VALID?  ( descriptor -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP AES-GCM-DESCRIPTOR-SIZE
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN

    DUP AES-GCM-D.KEY-U @
        DUP AES-GCM-KEY128-SIZE =
        SWAP AES-GCM-KEY256-SIZE = OR 0= IF DROP 0 EXIT THEN
    DUP AES-GCM-D.KEY @
        OVER AES-GCM-D.KEY-U @
        _AGCM-REQUIRED-SPAN? 0= IF DROP 0 EXIT THEN

    DUP AES-GCM-D.IV-U @ AES-GCM-IV-SIZE <> IF DROP 0 EXIT THEN
    DUP AES-GCM-D.IV @ AES-GCM-IV-SIZE
        _AGCM-REQUIRED-SPAN? 0= IF DROP 0 EXIT THEN

    DUP AES-GCM-D.AAD-U @ _AGCM-U32? 0= IF DROP 0 EXIT THEN
    DUP AES-GCM-D.AAD @ OVER AES-GCM-D.AAD-U @
        _AGCM-OPTIONAL-SPAN? 0= IF DROP 0 EXIT THEN

    DUP AES-GCM-D.DATA-U @ _AGCM-U32? 0= IF DROP 0 EXIT THEN
    DUP AES-GCM-D.INPUT @ OVER AES-GCM-D.DATA-U @
        _AGCM-OPTIONAL-SPAN? 0= IF DROP 0 EXIT THEN
    DUP AES-GCM-D.OUTPUT @ OVER AES-GCM-D.DATA-U @
        _AGCM-OPTIONAL-SPAN? 0= IF DROP 0 EXIT THEN

    DUP AES-GCM-D.TAG-U @ AES-GCM-TAG-SIZE <> IF DROP 0 EXIT THEN
    AES-GCM-D.TAG @ AES-GCM-TAG-SIZE _AGCM-REQUIRED-SPAN? ;

: AES-GCM-DESCRIPTOR-CLEAR  ( descriptor -- status )
    DUP AES-GCM-DESCRIPTOR-SIZE _AGCM-REQUIRED-SPAN? 0= IF
        DROP AES-GCM-S-INVALID EXIT
    THEN
    AES-GCM-DESCRIPTOR-SIZE 0 FILL AES-GCM-S-OK ;

: AES-GCM-WORKSPACE-CLEAR  ( workspace -- status )
    DUP AES-GCM-WORKSPACE-SIZE _AGCM-REQUIRED-SPAN? 0= IF
        DROP AES-GCM-S-INVALID EXIT
    THEN
    _AGCM-WIPE-WORKSPACE AES-GCM-S-OK ;

\ ( descriptor workspace span-a span-u -- flag )
\ Test one external span against both caller-owned control objects.
: _AGCM-ONE-CONTAINER-ALIASED?  ( descriptor workspace a u -- flag )
    2DUP 5 PICK AES-GCM-DESCRIPTOR-SIZE MSPAN-OVERLAP? IF
        2DROP 2DROP -1 EXIT
    THEN
    2DUP 4 PICK AES-GCM-WORKSPACE-SIZE MSPAN-OVERLAP?
    >R 2DROP 2DROP R> ;

: _AGCM-CONTAINERS-ALIASED?  ( descriptor workspace -- flag )
    \ Descriptor and workspace must first be disjoint from one another.
    OVER AES-GCM-DESCRIPTOR-SIZE
        2 PICK AES-GCM-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN

    2DUP OVER AES-GCM-D.KEY @
        2 PICK AES-GCM-D.KEY-U @
        _AGCM-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER AES-GCM-D.IV @ AES-GCM-IV-SIZE
        _AGCM-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER AES-GCM-D.AAD @
        2 PICK AES-GCM-D.AAD-U @
        _AGCM-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER AES-GCM-D.INPUT @
        2 PICK AES-GCM-D.DATA-U @
        _AGCM-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER AES-GCM-D.OUTPUT @
        2 PICK AES-GCM-D.DATA-U @
        _AGCM-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DUP OVER AES-GCM-D.TAG @ AES-GCM-TAG-SIZE
        _AGCM-ONE-CONTAINER-ALIASED? IF 2DROP -1 EXIT THEN
    2DROP 0 ;

: _AGCM-DATA-PARTIAL-OVERLAP?  ( descriptor -- flag )
    DUP AES-GCM-D.DATA-U @ 0= IF DROP 0 EXIT THEN
    DUP AES-GCM-D.INPUT @
        OVER AES-GCM-D.OUTPUT @ = IF DROP 0 EXIT THEN
    DUP AES-GCM-D.INPUT @ OVER AES-GCM-D.DATA-U @
        2 PICK AES-GCM-D.OUTPUT @ 3 PICK AES-GCM-D.DATA-U @
        MSPAN-OVERLAP? NIP ;

: _AGCM-OUTPUT-OVERLAPS?  ( descriptor a u -- flag )
    2 PICK AES-GCM-D.OUTPUT @
        3 PICK AES-GCM-D.DATA-U @
        MSPAN-OVERLAP? NIP ;

: _AGCM-TAG-OVERLAPS?  ( descriptor a u -- flag )
    2 PICK AES-GCM-D.TAG @ AES-GCM-TAG-SIZE
        MSPAN-OVERLAP? NIP ;

: _AGCM-MUTABLE-ALIASED?  ( descriptor -- flag )
    DUP _AGCM-DATA-PARTIAL-OVERLAP? IF DROP -1 EXIT THEN
    DUP >R

    R@ R@ AES-GCM-D.KEY @ R@ AES-GCM-D.KEY-U @
        _AGCM-OUTPUT-OVERLAPS? IF DROP R> DROP -1 EXIT THEN
    R@ R@ AES-GCM-D.IV @ AES-GCM-IV-SIZE
        _AGCM-OUTPUT-OVERLAPS? IF DROP R> DROP -1 EXIT THEN
    R@ R@ AES-GCM-D.AAD @ R@ AES-GCM-D.AAD-U @
        _AGCM-OUTPUT-OVERLAPS? IF DROP R> DROP -1 EXIT THEN
    R@ R@ AES-GCM-D.TAG @ AES-GCM-TAG-SIZE
        _AGCM-OUTPUT-OVERLAPS? IF DROP R> DROP -1 EXIT THEN

    R@ R@ AES-GCM-D.KEY @ R@ AES-GCM-D.KEY-U @
        _AGCM-TAG-OVERLAPS? IF DROP R> DROP -1 EXIT THEN
    R@ R@ AES-GCM-D.IV @ AES-GCM-IV-SIZE
        _AGCM-TAG-OVERLAPS? IF DROP R> DROP -1 EXIT THEN
    R@ R@ AES-GCM-D.AAD @ R@ AES-GCM-D.AAD-U @
        _AGCM-TAG-OVERLAPS? IF DROP R> DROP -1 EXIT THEN
    R@ R@ AES-GCM-D.INPUT @ R@ AES-GCM-D.DATA-U @
        _AGCM-TAG-OVERLAPS? IF DROP R> DROP -1 EXIT THEN

    DROP R> DROP 0 ;

: _AGCM-GEOMETRY  ( descriptor workspace -- status )
    OVER AES-GCM-DESCRIPTOR-VALID? 0= IF
        2DROP AES-GCM-S-INVALID EXIT
    THEN
    DUP AES-GCM-WORKSPACE-SIZE _AGCM-REQUIRED-SPAN? 0= IF
        2DROP AES-GCM-S-INVALID EXIT
    THEN
    2DUP _AGCM-CONTAINERS-ALIASED? IF
        2DROP AES-GCM-S-ALIAS EXIT
    THEN
    OVER _AGCM-MUTABLE-ALIASED? IF
        2DROP AES-GCM-S-ALIAS EXIT
    THEN
    2DROP AES-GCM-S-OK ;

\ =====================================================================
\  Bounded engine state polling
\ =====================================================================

-1 CONSTANT _AGCM-POLL-TIMEOUT
-2 CONSTANT _AGCM-POLL-INVALID

\ Return 1, 2, or 3 once CMD has visibly started.  Status zero is allowed
\ only during the bounded transition window.
: _AGCM-POLL-STARTED  ( -- machine-status )
    AES-GCM-HARDWARE-POLL-LIMIT 0 DO
        AES-STATUS@ DUP 0= IF
            DROP YIELD?
        ELSE
            DUP 3 <= IF UNLOOP EXIT THEN
            DROP _AGCM-POLL-INVALID UNLOOP EXIT
        THEN
    LOOP
    _AGCM-POLL-TIMEOUT ;

\ Return only terminal status 2 or 3.  Both idle and busy are bounded so
\ a wedged or incoherent device can never hold the Akashic guard forever.
: _AGCM-POLL-FINAL  ( -- machine-status )
    AES-GCM-HARDWARE-POLL-LIMIT 0 DO
        AES-STATUS@ DUP 2 = OVER 3 = OR IF UNLOOP EXIT THEN
        DUP 0= OVER 1 = OR IF
            DROP YIELD?
        ELSE
            DROP _AGCM-POLL-INVALID UNLOOP EXIT
        THEN
    LOOP
    _AGCM-POLL-TIMEOUT ;

\ =====================================================================
\  Operation setup and exact feeds
\ =====================================================================

0 CONSTANT _AGCM-OP-SEAL
1 CONSTANT _AGCM-OP-OPEN-AUTH
2 CONSTANT _AGCM-OP-OPEN-PUBLISH

: _AGCM-RESET-PASS  ( workspace -- )
    DUP _AGCM-W.AAD-BASE @ OVER _AGCM-W.AAD !
    DUP _AGCM-W.AAD-U @ OVER _AGCM-W.AAD-LEFT !
    DUP _AGCM-W.INPUT-BASE @ OVER _AGCM-W.SOURCE !
    DUP _AGCM-W.OUTPUT-BASE @ OVER _AGCM-W.DEST !
    DUP _AGCM-W.DATA-U @ OVER _AGCM-W.DATA-LEFT !
    DROP ;

: _AGCM-BIND  ( descriptor workspace operation -- workspace )
    >R
    DUP AES-GCM-WORKSPACE-SIZE 0 FILL
    OVER AES-GCM-D.KEY @ OVER _AGCM-W.KEY !
    OVER AES-GCM-D.KEY-U @ OVER _AGCM-W.KEY-U !
    OVER AES-GCM-D.IV @ OVER _AGCM-W.IV !
    OVER AES-GCM-D.AAD @ OVER _AGCM-W.AAD-BASE !
    OVER AES-GCM-D.AAD-U @ OVER _AGCM-W.AAD-U !
    OVER AES-GCM-D.INPUT @ OVER _AGCM-W.INPUT-BASE !
    OVER AES-GCM-D.OUTPUT @ OVER _AGCM-W.OUTPUT-BASE !
    OVER AES-GCM-D.DATA-U @ OVER _AGCM-W.DATA-U !
    OVER AES-GCM-D.TAG @ OVER _AGCM-W.TAG !
    R@ OVER _AGCM-W.OP !
    R@ OVER _AGCM-W.REQUEST !
    DUP _AGCM-RESET-PASS
    R> DROP NIP ;

: _AGCM-FEEDS-DONE?  ( workspace -- flag )
    DUP _AGCM-W.AAD-LEFT @ 0=
    SWAP _AGCM-W.DATA-LEFT @ 0= AND ;

\ Validate the synchronous native state after each complete 16-byte DIN
\ window.  Terminal state is coherent only after the exact declared feed.
: _AGCM-CHECK-PROGRESS  ( workspace machine-status -- status )
    DUP _AGCM-POLL-TIMEOUT = IF
        2DROP AES-GCM-S-TIMEOUT EXIT
    THEN
    DUP _AGCM-POLL-INVALID = IF
        2DROP AES-GCM-S-HARDWARE EXIT
    THEN
    DUP 1 = IF
        DROP DUP _AGCM-FEEDS-DONE? IF
            DROP AES-GCM-S-HARDWARE
        ELSE
            DROP AES-GCM-S-OK
        THEN
        EXIT
    THEN
    DUP 2 = OVER 3 = OR IF
        DROP DUP _AGCM-FEEDS-DONE? IF
            DROP AES-GCM-S-OK
        ELSE
            DROP AES-GCM-S-HARDWARE
        THEN
        EXIT
    THEN
    2DROP AES-GCM-S-HARDWARE ;

: _AGCM-START  ( workspace -- machine-status )
    DUP _AGCM-W.KEY-STAGE AES-GCM-KEY256-SIZE 0 FILL
    DUP _AGCM-W.KEY @ OVER _AGCM-W.KEY-STAGE
        2 PICK _AGCM-W.KEY-U @ MOVE
    DUP _AGCM-W.KEY-STAGE AES-KEY!
    DUP _AGCM-W.IV @ AES-IV!
    DUP _AGCM-W.KEY-U @ AES-GCM-KEY128-SIZE =
        IF 1 ELSE 0 THEN AES-KEY-MODE!
    DUP _AGCM-W.AAD-LEFT @ AES-AAD-LEN!
    DUP _AGCM-W.DATA-LEFT @ AES-DATA-LEN!
    DUP _AGCM-W.OP @ _AGCM-OP-SEAL <> IF
        DUP _AGCM-W.TAG @ AES-TAG!
    THEN
    _AGCM-W.OP @ _AGCM-OP-SEAL =
        IF 0 ELSE 1 THEN AES-CMD!
    _AGCM-POLL-STARTED ;

: _AGCM-FEED-AAD  ( workspace -- status )
    BEGIN DUP _AGCM-W.AAD-LEFT @ 0> WHILE
        DUP _AGCM-W.BLOCK AES-GCM-BLOCK-SIZE 0 FILL
        DUP _AGCM-W.AAD-LEFT @ AES-GCM-BLOCK-SIZE MIN
            OVER _AGCM-W.TAKE !
        DUP _AGCM-W.AAD @ OVER _AGCM-W.BLOCK
            2 PICK _AGCM-W.TAKE @ MOVE
        DUP _AGCM-W.BLOCK AES-DIN!
        DUP _AGCM-W.TAKE @ OVER _AGCM-W.AAD +!
        DUP _AGCM-W.TAKE @ NEGATE OVER _AGCM-W.AAD-LEFT +!
        _AGCM-POLL-STARTED OVER _AGCM-W.STATE !
        DUP DUP _AGCM-W.STATE @ _AGCM-CHECK-PROGRESS
        DUP IF NIP EXIT THEN DROP
    REPEAT
    DROP AES-GCM-S-OK ;

: _AGCM-FEED-DATA  ( workspace -- status )
    BEGIN DUP _AGCM-W.DATA-LEFT @ 0> WHILE
        DUP _AGCM-W.BLOCK AES-GCM-BLOCK-SIZE 0 FILL
        DUP _AGCM-W.DATA-LEFT @ AES-GCM-BLOCK-SIZE MIN
            OVER _AGCM-W.TAKE !
        DUP _AGCM-W.SOURCE @ OVER _AGCM-W.BLOCK
            2 PICK _AGCM-W.TAKE @ MOVE
        DUP _AGCM-W.BLOCK AES-DIN!
        DUP _AGCM-W.TAKE @ OVER _AGCM-W.SOURCE +!
        DUP _AGCM-W.TAKE @ NEGATE OVER _AGCM-W.DATA-LEFT +!
        _AGCM-POLL-STARTED OVER _AGCM-W.STATE !
        DUP DUP _AGCM-W.STATE @ _AGCM-CHECK-PROGRESS
        DUP IF NIP EXIT THEN DROP

        \ The first OPEN pass authenticates the complete input without ever
        \ reading DOUT.  SEAL and the second OPEN pass publish only coherent
        \ blocks; any terminal failure still causes the wrapper to wipe the
        \ complete destination before returning.
        DUP _AGCM-W.OP @ _AGCM-OP-OPEN-AUTH <> IF
            DUP _AGCM-W.STATE @ 3 <> IF
                DUP _AGCM-W.BLOCK AES-DOUT@
                DUP _AGCM-W.BLOCK OVER _AGCM-W.DEST @
                    2 PICK _AGCM-W.TAKE @ MOVE
                DUP _AGCM-W.TAKE @ OVER _AGCM-W.DEST +!
            THEN
        THEN
    REPEAT
    DROP AES-GCM-S-OK ;

: _AGCM-FINAL>STATUS  ( workspace machine-status -- status )
    DUP _AGCM-POLL-TIMEOUT = IF
        2DROP AES-GCM-S-TIMEOUT EXIT
    THEN
    DUP _AGCM-POLL-INVALID = IF
        2DROP AES-GCM-S-HARDWARE EXIT
    THEN
    DUP 2 = IF 2DROP AES-GCM-S-OK EXIT THEN
    3 = IF
        _AGCM-W.OP @ _AGCM-OP-SEAL <>
            IF AES-GCM-S-AUTH ELSE AES-GCM-S-HARDWARE THEN
        EXIT
    THEN
    DROP AES-GCM-S-HARDWARE ;

: _AGCM-RUN  ( workspace -- status )
    DUP _AGCM-START OVER _AGCM-W.STATE !
    DUP DUP _AGCM-W.STATE @ _AGCM-CHECK-PROGRESS
    DUP IF NIP EXIT THEN DROP

    DUP _AGCM-FEED-AAD DUP IF NIP EXIT THEN DROP
    DUP _AGCM-FEED-DATA DUP IF NIP EXIT THEN DROP

    _AGCM-POLL-FINAL OVER _AGCM-W.STATE !
    DUP DUP _AGCM-W.STATE @ _AGCM-FINAL>STATUS
    DUP IF NIP EXIT THEN DROP

    DUP _AGCM-W.OP @ _AGCM-OP-SEAL = IF
        DUP _AGCM-W.TAG-STAGE AES-TAG@
    THEN
    DROP AES-GCM-S-OK ;

\ =====================================================================
\  CATCH-safe pass, cleanup, publication, and guarded public entry
\ =====================================================================

-3001 CONSTANT _AGCM-E-CLEANUP

\ The register contract has no reset/abort word.  A zero-key, zero-length
\ transaction is therefore the scoped reset: it overwrites the key schedule,
\ finalizes immediately, and is followed by clearing the visible tag window.
: _AGCM-CLEAR-ENGINE  ( workspace -- )
    DUP _AGCM-W.ZERO AES-GCM-KEY256-SIZE 0 FILL
    DUP _AGCM-W.ZERO AES-KEY!
    DUP _AGCM-W.ZERO AES-IV!
    DUP _AGCM-W.ZERO AES-TAG!
    0 AES-KEY-MODE!
    0 AES-AAD-LEN!
    0 AES-DATA-LEN!
    0 AES-CMD!
    _AGCM-POLL-FINAL 2 <> IF
        DROP _AGCM-E-CLEANUP THROW
    THEN
    DUP _AGCM-W.ZERO AES-TAG!
    DROP ;

: _AGCM-CLEAR-ENGINE-SAFE  ( workspace -- failed? )
    ['] _AGCM-CLEAR-ENGINE CATCH
    DUP IF 2DROP -1 ELSE DROP 0 THEN ;

: _AGCM-RUN-SAFE  ( workspace -- status )
    ['] _AGCM-RUN CATCH
    DUP IF
        2DROP AES-GCM-S-INTERNAL
    ELSE
        DROP
    THEN ;

: _AGCM-WIPE-OUTPUT  ( workspace -- )
    DUP _AGCM-W.DATA-U @ 0> IF
        DUP _AGCM-W.OUTPUT-BASE @
        OVER _AGCM-W.DATA-U @ 0 FILL
    THEN
    DROP ;

: _AGCM-PUBLISH-TAG  ( workspace -- )
    DUP _AGCM-W.TAG-STAGE
    SWAP _AGCM-W.TAG @
    AES-GCM-TAG-SIZE MOVE ;

: _AGCM-WIPE-WORKSPACE-SAFE  ( workspace -- failed? )
    ['] _AGCM-WIPE-WORKSPACE CATCH
    DUP IF 2DROP -1 ELSE DROP 0 THEN ;

: _AGCM-WIPE-OUTPUT-SAFE  ( workspace -- failed? )
    ['] _AGCM-WIPE-OUTPUT CATCH
    DUP IF 2DROP -1 ELSE DROP 0 THEN ;

: _AGCM-PUBLISH-TAG-SAFE  ( workspace -- failed? )
    ['] _AGCM-PUBLISH-TAG CATCH
    DUP IF 2DROP -1 ELSE DROP 0 THEN ;

: _AGCM-WIPE-DESCRIPTOR-OUTPUT  ( descriptor -- )
    DUP AES-GCM-D.DATA-U @ 0> IF
        DUP AES-GCM-D.OUTPUT @
        OVER AES-GCM-D.DATA-U @ 0 FILL
    THEN
    DROP ;

: _AGCM-WIPE-DESCRIPTOR-OUTPUT-SAFE  ( descriptor -- failed? )
    ['] _AGCM-WIPE-DESCRIPTOR-OUTPUT CATCH
    DUP IF 2DROP -1 ELSE DROP 0 THEN ;

: _AGCM-BIND-SAFE  ( descriptor workspace operation -- status )
    ['] _AGCM-BIND CATCH
    DUP IF
        2DROP 2DROP AES-GCM-S-INTERNAL
    ELSE
        DROP DROP AES-GCM-S-OK
    THEN ;

\ One engine pass always performs engine cleanup before returning.  OPEN uses
\ this boundary between its authenticate-only and publication passes.
: _AGCM-PASS-SAFE  ( workspace -- status )
    DUP _AGCM-RUN-SAFE >R
    DUP _AGCM-CLEAR-ENGINE-SAFE IF
        DROP R> DROP AES-GCM-S-INTERNAL EXIT
    THEN
    DROP R> ;

: _AGCM-PREPARE-OPEN-PUBLISH  ( workspace -- )
    _AGCM-OP-OPEN-PUBLISH OVER _AGCM-W.OP !
    _AGCM-RESET-PASS ;

: _AGCM-PREPARE-OPEN-PUBLISH-SAFE  ( workspace -- status )
    ['] _AGCM-PREPARE-OPEN-PUBLISH CATCH
    DUP IF
        2DROP AES-GCM-S-INTERNAL
    ELSE
        DROP AES-GCM-S-OK
    THEN ;

: _AGCM-BODY  ( workspace -- status )
    DUP _AGCM-W.OP @ _AGCM-OP-SEAL = IF
        _AGCM-PASS-SAFE EXIT
    THEN

    \ Authenticate the whole input without observing DOUT.
    DUP _AGCM-PASS-SAFE
    DUP IF NIP EXIT THEN DROP

    \ Replay only after successful authentication.  This pass rechecks the
    \ exact bytes it observes while publishing.  Exclusive caller ownership
    \ remains normative; reauthentication is not a general race detector.
    DUP _AGCM-PREPARE-OPEN-PUBLISH-SAFE
    DUP IF NIP EXIT THEN DROP
    _AGCM-PASS-SAFE ;

: _AGCM-BODY-SAFE  ( workspace -- status )
    ['] _AGCM-BODY CATCH
    DUP IF
        2DROP AES-GCM-S-INTERNAL
    ELSE
        DROP
    THEN ;

: _AGCM-ADMITTED  ( workspace -- status )
    DUP _AGCM-BODY-SAFE >R

    \ This outer cleanup is intentional even though each ordinary pass also
    \ clears: it covers an unexpected body THROW before pass cleanup starts.
    \ Engine cleanup is always attempted before any caller-output cleanup.
    DUP _AGCM-CLEAR-ENGINE-SAFE IF
        R> DROP AES-GCM-S-INTERNAL >R
    THEN

    \ SEAL never exposes its staged tag until body and engine cleanup succeed.
    R@ AES-GCM-S-OK = IF
        DUP _AGCM-W.REQUEST @ _AGCM-OP-SEAL = IF
            DUP _AGCM-PUBLISH-TAG-SAFE IF
                R> DROP AES-GCM-S-INTERNAL >R
            THEN
        THEN
    THEN

    \ A failed publication is a failed operation, so ciphertext/plaintext is
    \ removed.  A wipe fault cannot suppress the already-attempted engine
    \ cleanup or the workspace wipe that follows.
    R@ IF
        DUP _AGCM-WIPE-OUTPUT-SAFE IF
            R> DROP AES-GCM-S-INTERNAL >R
        THEN
    THEN

    DUP _AGCM-WIPE-WORKSPACE-SAFE IF
        DROP R> DROP AES-GCM-S-INTERNAL EXIT
    THEN
    DROP R> ;

GUARD _aes-gcm-guard

: _AGCM-CALL-LOCKED  ( descriptor workspace operation -- status )
    >R
    2DUP _AGCM-GEOMETRY DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    2DUP R@ _AGCM-BIND-SAFE
    DUP IF
        DROP
        \ Geometry admitted the operation.  Keep every recovery stage
        \ independent even when workspace binding itself throws.
        DUP _AGCM-CLEAR-ENGINE-SAFE DROP
        OVER _AGCM-WIPE-DESCRIPTOR-OUTPUT-SAFE DROP
        DUP _AGCM-WIPE-WORKSPACE-SAFE DROP
        2DROP R> DROP AES-GCM-S-INTERNAL EXIT
    THEN
    DROP NIP R> DROP _AGCM-ADMITTED ;

\ Catch the complete locked call, including geometry and the final admitted
\ bookkeeping.  On an unexpected THROW, CATCH restores descriptor/workspace/
\ operation.  Recovery is then best-effort and independently contained: the
\ engine is cleared first, caller output second, and workspace last.
: _AGCM-CALL-SAFE  ( descriptor workspace operation -- status )
    ['] _AGCM-CALL-LOCKED CATCH
    DUP IF
        2DROP
        DUP _AGCM-CLEAR-ENGINE-SAFE DROP
        OVER _AGCM-WIPE-DESCRIPTOR-OUTPUT-SAFE DROP
        DUP _AGCM-WIPE-WORKSPACE-SAFE DROP
        2DROP AES-GCM-S-INTERNAL EXIT
    THEN
    DROP ;

: _AGCM-SEAL-LOCKED  ( descriptor workspace -- status )
    _AGCM-OP-SEAL _AGCM-CALL-SAFE ;

: _AGCM-OPEN-LOCKED  ( descriptor workspace -- status )
    _AGCM-OP-OPEN-AUTH _AGCM-CALL-SAFE ;

: AES-GCM-SEAL  ( descriptor workspace -- status )
    ['] _AGCM-SEAL-LOCKED _aes-gcm-guard WITH-GUARD ;

: AES-GCM-OPEN  ( descriptor workspace -- status )
    ['] _AGCM-OPEN-LOCKED _aes-gcm-guard WITH-GUARD ;

\ Compile-time geometry checks make workspace alias regressions fail at
\ image construction instead of silently overlapping key or tag material.
: _AGCM-GEOMETRY-ABORT  ( -- )
    ." AES-GCM workspace geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]

_AGCM-D-TAG-U 8 + AES-GCM-DESCRIPTOR-SIZE <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]

_AGCM-W-INPUT-BASE 8 + _AGCM-W-REQUEST <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]

_AGCM-W-REQUEST 8 + _AGCM-W-BLOCK <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]

_AGCM-W-BLOCK AES-GCM-BLOCK-SIZE +
    _AGCM-W-TAG-STAGE <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]

_AGCM-W-TAG-STAGE AES-GCM-TAG-SIZE +
    _AGCM-W-KEY-STAGE <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]

_AGCM-W-KEY-STAGE AES-GCM-KEY256-SIZE +
    _AGCM-W-ZERO <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]

_AGCM-W-ZERO AES-GCM-KEY256-SIZE +
    AES-GCM-WORKSPACE-SIZE <> [IF]
    _AGCM-GEOMETRY-ABORT
[THEN]
