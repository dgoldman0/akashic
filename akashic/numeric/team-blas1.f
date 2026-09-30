\ =====================================================================
\  numeric/team-blas1.f - Level-1 kernels on a team of cores
\ =====================================================================
\  The kernels of numeric/blas1.f, split across a team (numeric/team.f).
\  They give exactly the same bits as the one-core kernels.
\
\  Element-wise kernels split the array's tiles: each member works on a
\  one-row view of its share of the tiles.  The kernels compute whole
\  tiles, padding included, so a split at any tile boundary is exact.
\
\  Reductions split the blocks: each member computes the values of its
\  share of the blocks (NV-BLOCK-VALUES) into member 0's workspace, and
\  the owner then combines them all (NV-COMBINE).  The order is fixed by
\  the blocks, not by the members, so the result is the same on any
\  number of cores.
\
\  Each member's workspace needs NV-WS-BYTES of the array for reductions,
\  and 64 bytes for NT-SCALE and NT-AXPY.  Arrays must not overlap the
\  team's memory (NUM-E-OVERLAP).  A call is checked whole before any
\  member starts, so a refused call writes nothing.
\
\  Prefix: NT-    public API
\          _NTB-  internal helpers
\
\  Load with:   REQUIRE numeric/team-blas1.f
\ =====================================================================

PROVIDED akashic-numeric-team-blas1

REQUIRE team.f
REQUIRE blas1.f

\ =====================================================================
\  Element-wise kernels
\ =====================================================================

\ Plan fields (NTEAM-PLAN).
 0 CONSTANT _NTB-X
 8 CONSTANT _NTB-Y          \ 0 when unused
16 CONSTANT _NTB-Z          \ 0 when unused
24 CONSTANT _NTB-W          \ the array written
32 CONSTANT _NTB-BITS
40 CONSTANT _NTB-KERNEL     \ the one-core kernel
48 CONSTANT _NTB-TASK       \ the task xt

\ Task arguments (NTASK.ARGS).
 0 CONSTANT _NTA-KERNEL
 8 CONSTANT _NTA-BITS
16 CONSTANT _NTA-A          \ view of x
48 CONSTANT _NTA-B          \ view of y
80 CONSTANT _NTA-C          \ view of z

\ Describe tiles t0 up to t1 of arr, t0 < t1, as a one-row array at view.
: _NTB-VIEW  ( arr t0 t1 view -- )
    >R OVER - >R
    64 * OVER NARR-ADDR +
    R> 2 PICK NARR-FMT NUM-LANES *
    1 3 PICK NARR-FMT R> NARR-INIT
    2DROP ;

: _NTB-PLAN-MEMBER  ( k team -- )
    2DUP NTEAM-TASK >R
    DUP NTEAM-PLAN _NTB-X + @ NARR-TILES ROT 2 PICK NTEAM-SHARE
    2DUP = IF 2DROP DROP 0 R> NTASK.XT ! EXIT THEN
    ROT NTEAM-PLAN
    DUP _NTB-TASK + @ R@ NTASK.XT !
    DUP _NTB-KERNEL + @ R@ NTASK.ARGS _NTA-KERNEL + !
    DUP _NTB-BITS + @ R@ NTASK.ARGS _NTA-BITS + !
    DUP _NTB-X + @ 3 PICK 3 PICK R@ NTASK.ARGS _NTA-A + _NTB-VIEW
    DUP _NTB-Y + @ ?DUP IF 3 PICK 3 PICK R@ NTASK.ARGS _NTA-B + _NTB-VIEW THEN
    DUP _NTB-Z + @ ?DUP IF 3 PICK 3 PICK R@ NTASK.ARGS _NTA-C + _NTB-VIEW THEN
    _NTB-W + @ NARR-ADDR 2 PICK 64 * + R@ NTASK.OUT-A !
    SWAP - 64 * R> NTASK.OUT-U ! ;

\ z = x op y
: _NTB-TASK-XYZ  ( task -- status )
    NTASK.ARGS >R
    R@ _NTA-A + R@ _NTA-B + R@ _NTA-C + R> _NTA-KERNEL + @ EXECUTE ;

\ y = x
: _NTB-TASK-XY  ( task -- status )
    NTASK.ARGS >R R@ _NTA-A + R@ _NTA-B + R> _NTA-KERNEL + @ EXECUTE ;

\ fill x
: _NTB-TASK-SX  ( task -- status )
    NTASK.ARGS >R R@ _NTA-BITS + @ R@ _NTA-A + R> _NTA-KERNEL + @ EXECUTE ;

\ scale x, with the member's workspace
: _NTB-TASK-SXW  ( task -- status )
    DUP NTASK.WS @ SWAP NTASK.ARGS >R
    R@ _NTA-BITS + @ R@ _NTA-A + ROT R> _NTA-KERNEL + @ EXECUTE ;

\ y = x * a + y, with the member's workspace
: _NTB-TASK-SXYW  ( task -- status )
    DUP NTASK.WS @ SWAP NTASK.ARGS >R
    R@ _NTA-BITS + @ R@ _NTA-A + R@ _NTA-B + 3 ROLL R> _NTA-KERNEL + @ EXECUTE ;

: _NTB-RUN  ( x y z w bits kernel task-xt team -- status )
    >R
    R@ NTEAM-PLAN _NTB-TASK + !  R@ NTEAM-PLAN _NTB-KERNEL + !
    R@ NTEAM-PLAN _NTB-BITS + !  R@ NTEAM-PLAN _NTB-W + !
    R@ NTEAM-PLAN _NTB-Z + !     R@ NTEAM-PLAN _NTB-Y + !
    R@ NTEAM-PLAN _NTB-X + !
    R> DUP NTEAM-CORES 0 ?DO I OVER _NTB-PLAN-MEMBER LOOP
    NTEAM-DISPATCH ;

: _NTB-APART?  ( arr team -- flag )  >R NARR-STORAGE R> NTEAM-APART? ;

: _NTB-SPACE?  ( bytes team -- flag )  0 SWAP NTEAM-WS NWS-BYTES <= ;

\ Checks shared by the binary kernels: status for x y z on team.
: _NTB-CHECK3  ( x y z team -- status )
    >R 2 PICK 2 PICK 2 PICK NV-CHECK3 ?DUP IF >R 2DROP DROP R> R> DROP EXIT THEN
    R@ _NTB-APART? SWAP R@ _NTB-APART? AND SWAP R> _NTB-APART? AND
    IF NUM-OK ELSE NUM-E-OVERLAP THEN ;

: _NTB-CHECK2  ( x y team -- status )
    >R 2DUP NV-CHECK2 ?DUP IF >R 2DROP R> R> DROP EXIT THEN
    R@ _NTB-APART? SWAP R> _NTB-APART? AND
    IF NUM-OK ELSE NUM-E-OVERLAP THEN ;

: _NTB-CHECK1  ( x team -- status )
    OVER NARR-FMT NUM-FORMAT? 0= IF 2DROP NUM-E-FORMAT EXIT THEN
    _NTB-APART? IF NUM-OK ELSE NUM-E-OVERLAP THEN ;

: _NTB-BINARY  ( x y z team kernel -- status )
    >R 3 PICK 3 PICK 3 PICK 3 PICK _NTB-CHECK3 ?DUP IF
        R> DROP >R 2DROP 2DROP R> EXIT
    THEN
    >R DUP 0 R> R> SWAP ['] _NTB-TASK-XYZ SWAP _NTB-RUN ;

\ z = x + y, x - y, or x * y on the team.
: NT-ADD  ( x y z team -- status )  ['] NV-ADD _NTB-BINARY ;
: NT-SUB  ( x y z team -- status )  ['] NV-SUB _NTB-BINARY ;
: NT-MUL  ( x y z team -- status )  ['] NV-MUL _NTB-BINARY ;

\ y = x on the team.
: NT-COPY  ( x y team -- status )
    >R 2DUP R@ _NTB-CHECK2 ?DUP IF R> DROP >R 2DROP R> EXIT THEN
    0 OVER 0 ['] NV-COPY ['] _NTB-TASK-XY R> _NTB-RUN ;

\ Every lane of x becomes the scalar bits, on the team.
: NT-FILL  ( bits x team -- status )
    2DUP _NTB-CHECK1 ?DUP IF >R DROP 2DROP R> EXIT THEN
    >R SWAP >R 0 0 2 PICK R> ['] NV-FILL ['] _NTB-TASK-SX R> _NTB-RUN ;

\ x = RN(x * a) on the team.
: NT-SCALE  ( bits x team -- status )
    2DUP _NTB-CHECK1 ?DUP IF >R DROP 2DROP R> EXIT THEN
    64 OVER _NTB-SPACE? 0= IF DROP 2DROP NUM-E-SPACE EXIT THEN
    >R SWAP >R 0 0 2 PICK R> ['] NV-SCALE ['] _NTB-TASK-SXW R> _NTB-RUN ;

\ y = RN(x * a + y) on the team.
: NT-AXPY  ( bits x y team -- status )
    >R 2DUP R@ _NTB-CHECK2 ?DUP IF R> DROP >R 2DROP DROP R> EXIT THEN
    64 R@ _NTB-SPACE? 0= IF R> DROP 2DROP DROP NUM-E-SPACE EXIT THEN
    ROT >R 0 OVER R> ['] NV-AXPY ['] _NTB-TASK-SXYW R> _NTB-RUN ;

\ =====================================================================
\  Reductions
\ =====================================================================

\ Plan fields (NTEAM-PLAN).
 0 CONSTANT _NTR-PX
 8 CONSTANT _NTR-PY
16 CONSTANT _NTR-POP
24 CONSTANT _NTR-PDST      \ member 0's NV-PARTIALS

\ Task arguments (NTASK.ARGS).
 0 CONSTANT _NTR-X
 8 CONSTANT _NTR-Y
16 CONSTANT _NTR-OP
24 CONSTANT _NTR-DST
32 CONSTANT _NTR-B0
40 CONSTANT _NTR-B1

: _NTB-TASK-BLOCKS  ( task -- status )
    DUP NTASK.WS @ SWAP NTASK.ARGS >R
    R@ _NTR-X + @ R@ _NTR-Y + @ R@ _NTR-OP + @ 3 ROLL
    R@ _NTR-DST + @ R@ _NTR-B0 + @ R> _NTR-B1 + @
    NV-BLOCK-VALUES ;

: _NTB-PLAN-BLOCKS  ( k team -- )
    2DUP NTEAM-TASK >R
    DUP NTEAM-PLAN _NTR-PX + @ NV-BLOCKS ROT 2 PICK NTEAM-SHARE
    2DUP = IF 2DROP DROP 0 R> NTASK.XT ! EXIT THEN
    ['] _NTB-TASK-BLOCKS R@ NTASK.XT !
    ROT NTEAM-PLAN
    DUP _NTR-PX + @ R@ NTASK.ARGS _NTR-X + !
    DUP _NTR-PY + @ R@ NTASK.ARGS _NTR-Y + !
    DUP _NTR-POP + @ R@ NTASK.ARGS _NTR-OP + !
    _NTR-PDST + @
    DUP R@ NTASK.ARGS _NTR-DST + !
    2 PICK 8 * + R@ NTASK.OUT-A !
    2DUP SWAP - 8 * R@ NTASK.OUT-U !
    R@ NTASK.ARGS _NTR-B1 + !  R> NTASK.ARGS _NTR-B0 + ! ;

: _NTB-REDUCE  ( x y op team -- bits status )
    3 PICK NARR-FMT NUM-FORMAT? 0= IF 2DROP 2DROP 0 NUM-E-FORMAT EXIT THEN
    OVER NV-OP-DOT = IF
        3 PICK 3 PICK NARR-SAME-SHAPE? 0= IF 2DROP 2DROP 0 NUM-E-SHAPE EXIT THEN
        2 PICK OVER _NTB-APART? 0= IF 2DROP 2DROP 0 NUM-E-OVERLAP EXIT THEN
    THEN
    3 PICK OVER _NTB-APART? 0= IF 2DROP 2DROP 0 NUM-E-OVERLAP EXIT THEN
    3 PICK NV-WS-BYTES OVER _NTB-SPACE? 0= IF 2DROP 2DROP 0 NUM-E-SPACE EXIT THEN
    >R
    R@ NTEAM-PLAN _NTR-POP + !  R@ NTEAM-PLAN _NTR-PY + !
    DUP R@ NTEAM-PLAN _NTR-PX + !
    0 R@ NTEAM-WS NV-PARTIALS R@ NTEAM-PLAN _NTR-PDST + !
    NV-BLOCKS R> SWAP >R
    DUP NTEAM-CORES 0 ?DO I OVER _NTB-PLAN-BLOCKS LOOP
    DUP NTEAM-DISPATCH ?DUP IF NIP R> DROP 0 SWAP EXIT THEN
    R> OVER NTEAM-PLAN _NTR-POP + @ ROT 0 SWAP NTEAM-WS NV-COMBINE ;

: NT-SUM    ( x team -- bits status )  0 NV-OP-SUM ROT _NTB-REDUCE ;
: NT-SUMSQ  ( x team -- bits status )  0 NV-OP-SUMSQ ROT _NTB-REDUCE ;
: NT-ASUM   ( x team -- bits status )  0 NV-OP-ASUM ROT _NTB-REDUCE ;
: NT-MAX    ( x team -- bits status )  0 NV-OP-MAX ROT _NTB-REDUCE ;
: NT-MIN    ( x team -- bits status )  0 NV-OP-MIN ROT _NTB-REDUCE ;
: NT-DOT    ( x y team -- bits status )  NV-OP-DOT SWAP _NTB-REDUCE ;
