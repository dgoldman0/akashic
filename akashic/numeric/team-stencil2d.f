\ =====================================================================
\  numeric/team-stencil2d.f - Grid stencils on a team of cores
\ =====================================================================
\  NST-LAPLACE and NST-UPDATE (numeric/stencil2d.f) split across a team
\  (numeric/team.f) by rows: each member computes its share of the output
\  rows, reading whatever grid rows and ghost values those rows need.
\  Every output value depends only on its own inputs, so the results are
\  the same bits as on one core.
\
\  Each member's workspace needs NST-WS-BYTES of the grid.  The grid, the
\  output, and any Dirichlet ghost vector must not overlap the team's
\  memory (NUM-E-OVERLAP).  A call is checked whole before any member
\  starts, so a refused call writes nothing.
\
\  Prefix: NT-    public API
\          _NTS-  internal helpers
\
\  Load with:   REQUIRE numeric/team-stencil2d.f
\ =====================================================================

PROVIDED akashic-numeric-team-stencil2d

REQUIRE team.f
REQUIRE stencil2d.f

\ Plan fields (NTEAM-PLAN) and task arguments (NTASK.ARGS) share this
\ layout; the plan's first 40 bytes are copied into each task.
 0 CONSTANT _NTS-C          \ update coefficient
 8 CONSTANT _NTS-U
16 CONSTANT _NTS-BC
24 CONSTANT _NTS-OUT
32 CONSTANT _NTS-UPDATE     \ nonzero: NST-UPDATE-ROWS, else NST-LAPLACE-ROWS
40 CONSTANT _NTS-I0
48 CONSTANT _NTS-I1

: _NTS-TASK  ( task -- status )
    DUP NTASK.WS @ SWAP NTASK.ARGS >R
    R@ _NTS-UPDATE + @ IF
        R@ _NTS-C + @ R@ _NTS-U + @ R@ _NTS-BC + @ R@ _NTS-OUT + @ 4 ROLL
        R@ _NTS-I0 + @ R> _NTS-I1 + @ NST-UPDATE-ROWS
    ELSE
        R@ _NTS-U + @ R@ _NTS-BC + @ R@ _NTS-OUT + @ 3 ROLL
        R@ _NTS-I0 + @ R> _NTS-I1 + @ NST-LAPLACE-ROWS
    THEN ;

: _NTS-PLAN-MEMBER  ( k team -- )
    2DUP NTEAM-TASK >R
    DUP NTEAM-PLAN _NTS-U + @ NARR-NY ROT 2 PICK NTEAM-SHARE
    2DUP = IF 2DROP DROP 0 R> NTASK.XT ! EXIT THEN
    ['] _NTS-TASK R@ NTASK.XT !
    ROT NTEAM-PLAN R@ NTASK.ARGS _NTS-I0 CMOVE
    OVER R@ NTASK.ARGS _NTS-I0 + !
    DUP R@ NTASK.ARGS _NTS-I1 + !
    R@ NTASK.ARGS _NTS-OUT + @ NARR-PITCH
    ROT OVER * R@ NTASK.ARGS _NTS-OUT + @ NARR-ADDR + R@ NTASK.OUT-A !
    SWAP R@ NTASK.ARGS _NTS-I0 + @ - * R> NTASK.OUT-U ! ;

\ Do the grid, the output, and every Dirichlet vector stay clear of the
\ team's memory?
: _NTS-APART?  ( u bc out team -- flag )
    >R
    NARR-STORAGE R@ NTEAM-APART?
    ROT NARR-STORAGE R@ NTEAM-APART? AND
    SWAP R>
    4 0 DO
        I 2 PICK NBC-KIND NBC-DIRICHLET = IF
            I 2 PICK NBC-GHOST NARR-STORAGE 2 PICK NTEAM-APART?
            3 ROLL AND -ROT
        THEN
    LOOP
    2DROP ;

\ Check the whole call on member 0's workspace, then plan and dispatch.
: _NTS-RUN  ( c u bc out update team -- status )
    >R
    3 PICK 3 PICK 3 PICK 0 R@ NTEAM-WS NST-CHECK ?DUP IF
        R> DROP >R 2DROP 2DROP DROP R> EXIT
    THEN
    3 PICK 3 PICK 3 PICK R@ _NTS-APART? 0= IF
        R> DROP 2DROP 2DROP DROP NUM-E-OVERLAP EXIT
    THEN
    R@ NTEAM-PLAN _NTS-UPDATE + !
    R@ NTEAM-PLAN _NTS-OUT + !
    R@ NTEAM-PLAN _NTS-BC + !
    R@ NTEAM-PLAN _NTS-U + !
    R@ NTEAM-PLAN _NTS-C + !
    R> DUP NTEAM-CORES 0 ?DO I OVER _NTS-PLAN-MEMBER LOOP
    NTEAM-DISPATCH ;

\ out = L(u) on the team.
: NT-LAPLACE  ( u bc out team -- status )
    >R 0 3 ROLL 3 ROLL 3 ROLL 0 R> _NTS-RUN ;

\ out = RN(L(u) * c + u) on the team, where c is scalar bits in u's format.
: NT-UPDATE  ( c u bc out team -- status )
    -1 SWAP _NTS-RUN ;
