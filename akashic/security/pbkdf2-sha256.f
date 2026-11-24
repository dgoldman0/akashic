\ =====================================================================
\  pbkdf2-sha256.f - Resumable PBKDF2-HMAC-SHA-256 (RFC 8018, 5.2)
\ =====================================================================
\  Derives a key from a password and a salt with HMAC-SHA-256 as the
\  pseudorandom function.  The iterations run in steps of a size the
\  caller chooses, so an interactive owner such as Desk can draw between
\  steps; no hardware transaction stays open between them.  BEGIN makes
\  the two HMAC key blocks into SHA-256 keyed states once, and each
\  iteration resumes from them: four compressions on today's engine, two
\  once the engine loads a saved chaining state, with no change here (see
\  sha256.f).  Each step takes the SHA-256 transaction once for its whole
\  run, and a hardware iteration mode would replace that run behind the
\  same words.
\
\  All state lives in a caller-owned workspace sized from the derived
\  key's length.  BEGIN reads the password and salt and keeps neither: the
\  workspace holds the HMAC keyed states, the running values and the
\  progress.  FINISH publishes the key and ABANDON gives the derivation
\  up; both wipe the whole workspace, as does every failure once BEGIN has
\  admitted its arguments.  The caller keeps the workspace at one address
\  for the whole derivation and does not change it between calls.
\
\  Public API:
\    PBKDF2-SHA256-WORKSPACE-SIZE ( dk-u -- u|0 )
\    PBKDF2-SHA256-STATUS-VALID?  ( status -- flag )
\    PBKDF2-SHA256-BEGIN   ( password password-u salt salt-u iterations
\                            dk-u workspace -- status )
\    PBKDF2-SHA256-STEP    ( budget workspace -- remaining status )
\    PBKDF2-SHA256-FINISH  ( dk workspace -- status )
\    PBKDF2-SHA256-ABANDON ( workspace -- status )
\    PBKDF2-SHA256         ( password password-u salt salt-u iterations
\                            dk dk-u workspace -- status )
\
\  Status: 0 OK, 1 INVALID, 2 ALIAS, 3 STATE, 4 CRYPTO.
\ =====================================================================

PROVIDED akashic-pbkdf2-sha256

REQUIRE ../math/sha256.f
REQUIRE ../utils/memory-span.f

0 CONSTANT PBKDF2-SHA256-S-OK
1 CONSTANT PBKDF2-SHA256-S-INVALID
2 CONSTANT PBKDF2-SHA256-S-ALIAS
3 CONSTANT PBKDF2-SHA256-S-STATE
4 CONSTANT PBKDF2-SHA256-S-CRYPTO

: PBKDF2-SHA256-STATUS-VALID?  ( status -- flag )
    DUP PBKDF2-SHA256-S-OK >=
    SWAP PBKDF2-SHA256-S-CRYPTO <= AND ;

\ =====================================================================
\  Workspace layout
\ =====================================================================
\  Header cells come first, then the key block BEGIN builds each pad in.
\  Each keyed state sits directly before the value hashed after it, so on
\  today's engine an iteration's two hashes each read one span: the inner
\  state and U give V, the outer state and V give the next U.  One 32-byte
\  running block T per output block follows.

  0 CONSTANT _PBK-MAGIC        \ _PBK-LIVE while a derivation runs
  8 CONSTANT _PBK-SIZE         \ the whole workspace's size
 16 CONSTANT _PBK-ITERATIONS   \ c
 24 CONSTANT _PBK-DK-U         \ the derived key's length
 32 CONSTANT _PBK-BLOCKS       \ l, the number of 32-byte blocks
 40 CONSTANT _PBK-BLOCK        \ the block being iterated, from zero
 48 CONSTANT _PBK-DONE         \ iterations finished in that block
 56 CONSTANT _PBK-COUNTER      \ INT(i), big-endian, while beginning
 64 CONSTANT _PBK-PAD          \ a key block while beginning, 64 bytes
128 CONSTANT _PBK-INNER        \ the keyed state of key XOR 0x36
_PBK-INNER SHA256-KEYED-SIZE + CONSTANT _PBK-U       \ the newest U
_PBK-U 32 + CONSTANT _PBK-OUTER                      \ key XOR 0x5C's
_PBK-OUTER SHA256-KEYED-SIZE + CONSTANT _PBK-V       \ the inner hash
_PBK-V 32 + CONSTANT _PBK-T                          \ the running blocks

0x31533246444B4250 CONSTANT _PBK-LIVE   \ "PBKDF2S1" in memory

\ RFC 8018 numbers the blocks with a 32-bit counter, so a key has at most
\ 2^32-1 blocks.  That is the standard's bound, not a policy choice.
0xFFFFFFFF CONSTANT _PBK-BLOCKS-MAX

: PBKDF2-SHA256-WORKSPACE-SIZE  ( dk-u -- u|0 )
    DUP 1 < IF DROP 0 EXIT THEN
    31 + 5 RSHIFT
    DUP _PBK-BLOCKS-MAX > IF DROP 0 EXIT THEN
    5 LSHIFT _PBK-T + ;

: _PBK-DROP8  ( x1 x2 x3 x4 x5 x6 x7 x8 -- )
    2DROP 2DROP 2DROP 2DROP ;

: _PBK-DROP4  ( x1 x2 x3 x4 -- )  2DROP 2DROP ;

: _PBK-WIPE  ( workspace -- )
    DUP _PBK-SIZE + @ 0 FILL ;

\ SHA-256's caller qualification decides which spans the engine may read
\ and write; its answers map onto this module's vocabulary.
: _PBK-SPAN-STATUS  ( address length -- status )
    SHA256-CALLER-SPAN-STATUS
    DUP SHA256-S-OK = IF EXIT THEN
    DUP SHA256-S-ALIAS = IF DROP PBKDF2-SHA256-S-ALIAS EXIT THEN
    SHA256-S-CRYPTO = IF PBKDF2-SHA256-S-CRYPTO EXIT THEN
    PBKDF2-SHA256-S-INVALID ;

\ The remaining work, counted in iterations.  BEGIN already ran every
\ later block's first iteration, so each of those has c-1 left.
: _PBK-REMAINING  ( workspace -- n )
    DUP _PBK-BLOCKS + @ OVER _PBK-BLOCK + @ - 1-
    OVER _PBK-ITERATIONS + @ 1- *
    OVER _PBK-ITERATIONS + @ ROT _PBK-DONE + @ - + ;

\ A live workspace holds a consistent derivation in admitted memory.
: _PBK-LIVE?  ( workspace -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _PBK-T SHA256-CALLER-SPAN-STATUS IF DROP 0 EXIT THEN
    DUP _PBK-MAGIC + @ _PBK-LIVE <> IF DROP 0 EXIT THEN
    DUP _PBK-DK-U + @ PBKDF2-SHA256-WORKSPACE-SIZE
    OVER _PBK-SIZE + @ <> IF DROP 0 EXIT THEN
    DUP DUP _PBK-SIZE + @ SHA256-CALLER-SPAN-STATUS IF DROP 0 EXIT THEN
    DUP _PBK-BLOCK + @ OVER _PBK-BLOCKS + @ U< 0= IF DROP 0 EXIT THEN
    DUP _PBK-DONE + @ 1 < IF DROP 0 EXIT THEN
    DUP _PBK-DONE + @ SWAP _PBK-ITERATIONS + @ > 0= ;

\ =====================================================================
\  Admission
\ =====================================================================
\  Every argument is checked before the workspace changes.  The stack
\  holds ( p pu s su c dku ws size ): size 0, ws 1, dku 2, c 3, su 4,
\  s 5, pu 6, p 7.

: _PBK-ADMIT  ( p pu s su c dku ws size -- p pu s su c dku ws size status )
    DUP 0= IF PBKDF2-SHA256-S-INVALID EXIT THEN
    3 PICK 1 < IF PBKDF2-SHA256-S-INVALID EXIT THEN
    \ The remaining count must stay a positive cell for every block.
    3 PICK  3 PICK 31 + 5 RSHIFT
    -1 1 RSHIFT SWAP / > IF PBKDF2-SHA256-S-INVALID EXIT THEN
    1 PICK 1 PICK _PBK-SPAN-STATUS ?DUP IF EXIT THEN
    7 PICK 7 PICK _PBK-SPAN-STATUS ?DUP IF EXIT THEN
    5 PICK 5 PICK _PBK-SPAN-STATUS ?DUP IF EXIT THEN
    7 PICK 7 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        PBKDF2-SHA256-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        PBKDF2-SHA256-S-ALIAS EXIT
    THEN
    PBKDF2-SHA256-S-OK ;

\ =====================================================================
\  Beginning: key blocks and each block's first U
\ =====================================================================

\ The key block key XOR mask in the workspace's pad.
: _PBK-PAD!  ( key key-u mask workspace -- )
    _PBK-PAD + DUP 64 3 PICK FILL NIP
    SWAP 0 ?DO
        OVER I + C@ OVER I + DUP C@ ROT XOR SWAP C!
    LOOP
    2DROP ;

\ The inner and outer keyed states of a key of at most 64 bytes.
: _PBK-KEYED  ( key key-u workspace -- status )
    >R
    2DUP 0x36 R@ _PBK-PAD!
    R@ _PBK-PAD + R@ _PBK-INNER + SHA256-HELD-KEY ?DUP IF
        NIP NIP R> DROP EXIT
    THEN
    0x5C R@ _PBK-PAD!
    R@ _PBK-PAD + R@ _PBK-OUTER + SHA256-HELD-KEY
    R> _PBK-PAD + 64 0 FILL ;

\ A password longer than the 64-byte block is first hashed to 32 bytes,
\ which the U slot holds until the keyed states are made.
: _PBK-KEY  ( password password-u workspace -- status )
    OVER 64 > IF
        >R R@ _PBK-U + SHA256-HELD-HASH
        ?DUP IF R> DROP EXIT THEN
        R@ _PBK-U + 32 R@ _PBK-KEYED
        R> _PBK-U + 32 0 FILL EXIT
    THEN
    _PBK-KEYED ;

: _PBK-BE32!  ( u address -- )
    OVER 24 RSHIFT 255 AND OVER C!
    OVER 16 RSHIFT 255 AND OVER 1+ C!
    OVER 8 RSHIFT 255 AND OVER 2 + C!
    SWAP 255 AND SWAP 3 + C! ;

\ U1 = HMAC(P, S || INT(i)) for every block i.  Each becomes its block's
\ running value T, so the salt is not needed again.
: _PBK-FIRST  ( salt salt-u workspace -- status )
    DUP _PBK-BLOCKS + @ 0 ?DO
        I 1+ OVER _PBK-COUNTER + _PBK-BE32!
        DUP _PBK-INNER +
        3 PICK 3 PICK
        3 PICK _PBK-COUNTER + 4
        5 PICK _PBK-V + SHA256-HELD-RESUME-2
        ?DUP IF NIP NIP NIP UNLOOP EXIT THEN
        DUP _PBK-OUTER + OVER _PBK-V + 32
        3 PICK _PBK-T + I 5 LSHIFT + SHA256-HELD-RESUME
        ?DUP IF NIP NIP NIP UNLOOP EXIT THEN
    LOOP
    2DROP DROP 0 ;

\ The keyed states and every block's first U, in one held transaction.
: _PBK-PREPARE  ( password password-u salt salt-u workspace -- status )
    >R 2SWAP R@ _PBK-KEY ?DUP IF NIP NIP R> DROP EXIT THEN
    R> _PBK-FIRST ;

: _PBK-PREPARE-HELD  ( password password-u salt salt-u workspace -- status )
    ['] _PBK-PREPARE SHA256-WITH-TRANSACTION ;

: PBKDF2-SHA256-BEGIN
  ( password password-u salt salt-u iterations dk-u workspace -- status )
    OVER PBKDF2-SHA256-WORKSPACE-SIZE
    _PBK-ADMIT ?DUP IF >R _PBK-DROP8 R> EXIT THEN
    \ Admitted: the workspace belongs to this derivation from here on.
    2DUP 0 FILL
    OVER _PBK-SIZE + !
    TUCK _PBK-DK-U + !
    TUCK _PBK-ITERATIONS + !
    DUP _PBK-DK-U + @ 31 + 5 RSHIFT OVER _PBK-BLOCKS + !
    >R R@ ['] _PBK-PREPARE-HELD CATCH ?DUP IF
        >R _PBK-DROP4 DROP R> R> _PBK-WIPE THROW
    THEN
    IF R> _PBK-WIPE PBKDF2-SHA256-S-CRYPTO EXIT THEN
    R@ _PBK-T + R@ _PBK-U + 32 MOVE
    0 R@ _PBK-BLOCK + !
    1 R@ _PBK-DONE + !
    _PBK-LIVE R> _PBK-MAGIC + !
    PBKDF2-SHA256-S-OK ;

\ =====================================================================
\  Stepping: the iterations
\ =====================================================================

: _PBK-XOR-INTO-T  ( workspace -- )
    DUP _PBK-BLOCK + @ 5 LSHIFT _PBK-T + OVER +
    SWAP _PBK-U +
    4 0 DO
        OVER I CELLS + @ OVER I CELLS + @ XOR
        2 PICK I CELLS + !
    LOOP
    2DROP ;

\ One iteration: U = HMAC(P, U), then T ^= U.  Both hashes resume from a
\ keyed state inside the step's held SHA-256 transaction.
: _PBK-ITERATE  ( workspace -- status )
    DUP _PBK-INNER + OVER _PBK-U + 32 3 PICK _PBK-V + SHA256-HELD-RESUME
    ?DUP IF NIP EXIT THEN
    DUP _PBK-OUTER + OVER _PBK-V + 32 3 PICK _PBK-U + SHA256-HELD-RESUME
    ?DUP IF NIP EXIT THEN
    DUP _PBK-XOR-INTO-T
    1 SWAP _PBK-DONE + +!
    0 ;

\ After a block's last iteration, start the next block from its U1, or
\ report that every block is done.
: _PBK-NEXT-BLOCK  ( workspace -- more? )
    DUP _PBK-BLOCK + @ 1+
    DUP 2 PICK _PBK-BLOCKS + @ < 0= IF 2DROP 0 EXIT THEN
    OVER _PBK-BLOCK + !
    DUP _PBK-BLOCK + @ 5 LSHIFT _PBK-T + OVER +
    OVER _PBK-U + 32 MOVE
    1 SWAP _PBK-DONE + !
    -1 ;

: _PBK-RUN  ( budget workspace -- status )
    BEGIN
        OVER 0>
    WHILE
        DUP _PBK-DONE + @ OVER _PBK-ITERATIONS + @ < IF
            DUP _PBK-ITERATE ?DUP IF NIP NIP EXIT THEN
            SWAP 1- SWAP
        ELSE
            DUP _PBK-NEXT-BLOCK 0= IF 2DROP 0 EXIT THEN
        THEN
    REPEAT
    2DROP 0 ;

: _PBK-RUN-HELD  ( budget workspace -- status )
    ['] _PBK-RUN SHA256-WITH-TRANSACTION ;

\ Run at most budget iterations and answer how many remain.  A hash
\ failure wipes the workspace; a THROW wipes it and propagates.
: PBKDF2-SHA256-STEP  ( budget workspace -- remaining status )
    DUP _PBK-LIVE? 0= IF 2DROP 0 PBKDF2-SHA256-S-STATE EXIT THEN
    OVER 1 < IF 2DROP 0 PBKDF2-SHA256-S-INVALID EXIT THEN
    DUP >R
    ['] _PBK-RUN-HELD CATCH
    ?DUP IF
        >R 2DROP R> R> _PBK-WIPE THROW
    THEN
    IF
        R> _PBK-WIPE 0 PBKDF2-SHA256-S-CRYPTO EXIT
    THEN
    R> _PBK-REMAINING PBKDF2-SHA256-S-OK ;

\ =====================================================================
\  Finishing
\ =====================================================================

\ Publish the key once every iteration has run, then wipe the workspace.
\ A rejected destination leaves the finished derivation in place, so the
\ caller can finish into a proper one or abandon it.
: PBKDF2-SHA256-FINISH  ( dk workspace -- status )
    DUP _PBK-LIVE? 0= IF 2DROP PBKDF2-SHA256-S-STATE EXIT THEN
    DUP _PBK-REMAINING IF 2DROP PBKDF2-SHA256-S-STATE EXIT THEN
    OVER 0= IF 2DROP PBKDF2-SHA256-S-INVALID EXIT THEN
    OVER OVER _PBK-DK-U + @ _PBK-SPAN-STATUS ?DUP IF
        NIP NIP EXIT
    THEN
    2DUP SWAP OVER _PBK-DK-U + @
    ROT DUP _PBK-SIZE + @ MSPAN-OVERLAP? IF
        2DROP PBKDF2-SHA256-S-ALIAS EXIT
    THEN
    DUP _PBK-T + ROT 2 PICK _PBK-DK-U + @ MOVE
    _PBK-WIPE PBKDF2-SHA256-S-OK ;

: PBKDF2-SHA256-ABANDON  ( workspace -- status )
    DUP _PBK-LIVE? 0= IF DROP PBKDF2-SHA256-S-STATE EXIT THEN
    _PBK-WIPE PBKDF2-SHA256-S-OK ;

\ The whole derivation in one call, for callers that need not draw.
: PBKDF2-SHA256
  ( password password-u salt salt-u iterations dk dk-u workspace -- status )
    ROT >R DUP >R
    PBKDF2-SHA256-BEGIN ?DUP IF R> R> 2DROP EXIT THEN
    -1 1 RSHIFT R@ PBKDF2-SHA256-STEP NIP
    ?DUP IF R> R> 2DROP EXIT THEN
    R> R> SWAP DUP >R
    PBKDF2-SHA256-FINISH
    DUP IF R@ PBKDF2-SHA256-ABANDON DROP THEN
    R> DROP ;
