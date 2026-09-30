\ =====================================================================
\  numeric/team.f - Running numeric work on several full cores
\ =====================================================================
\  A team is the calling core, the owner, plus worker cores 1 up to
\  NTEAM-CORES - 1.  Each member has its own workspace, so the numeric
\  kernels, which hold no module state, run on all members at once.
\
\  A team kernel (numeric/team-blas1.f, numeric/team-stencil2d.f) gives
\  each member a task: an execution token, the member's share of the
\  work, and the output span the share writes.  NTEAM-DISPATCH submits the
\  workers' tasks as worker jobs (concurrency/worker-job.f), runs the
\  owner's task, and waits for the rest.  When a worker core cannot take
\  its job, because it is busy, or because the caller is not core 0, the
\  owner runs that share itself, with that member's workspace.  Every
\  kernel fixes its order of operations without regard to which core runs
\  a share, so the results are the same bits either way.
\
\  Workers read the caller's input arrays, which must not change during a
\  call, and write only their share's output span and their workspace.
\  One team serves one owner at a time.
\
\  Team memory is one aligned caller span, carved for each member into a
\  workspace (the workspace size rounded up to whole tiles), a record
\  holding the member's workspace descriptor and task (256 bytes), and a
\  worker-job descriptor (192 bytes).
\
\  Prefix: NTEAM-  public API
\          NTASK.  task fields
\          _NTM-   internal helpers
\
\  Load with:   REQUIRE numeric/team.f
\ =====================================================================

PROVIDED akashic-numeric-team

REQUIRE array.f
REQUIRE ../concurrency/worker-job.f

\ =====================================================================
\  Team descriptor
\ =====================================================================

  0 CONSTANT _NTM-CORES
  8 CONSTANT _NTM-WSB        \ workspace bytes per member, whole tiles
 16 CONSTANT _NTM-BASE       \ team memory
 24 CONSTANT _NTM-GEN        \ worker-job generation of the last dispatch
 32 CONSTANT _NTM-JOBS       \ shares worker cores have run
 40 CONSTANT _NTM-OWNED      \ worker shares the owner ran instead
 48 CONSTANT _NTM-STRIDE     \ team-memory bytes per member
 64 CONSTANT _NTM-PLAN       \ 64 bytes of planning scratch for team kernels
128 CONSTANT NTEAM-SIZE

256 CONSTANT _NTM-RECORD-BYTES
192 CONSTANT _NTM-JOB-BYTES   \ WJOB-SIZE rounded up to a whole tile

: NTEAM-CORES  ( team -- n )     _NTM-CORES + @ ;
: NTEAM-JOBS   ( team -- n )     _NTM-JOBS + @ ;
: NTEAM-OWNED  ( team -- n )     _NTM-OWNED + @ ;
: NTEAM-PLAN   ( team -- addr )  _NTM-PLAN + ;

: _NTM-ROUND  ( u -- u' )  63 + -64 AND ;

: _NTM-STRIDE-FOR  ( ws-bytes -- stride )
    _NTM-ROUND _NTM-RECORD-BYTES + _NTM-JOB-BYTES + ;

-1 1 RSHIFT 1024 - CONSTANT _NTM-MAX-WS

\ Team memory bytes for cores members with ws-bytes of workspace each, or
\ 0 when cores < 1, ws-bytes is negative, or the size cannot be a cell.
: NTEAM-BYTES  ( cores ws-bytes -- bytes|0 )
    DUP 0< OVER _NTM-MAX-WS > OR IF 2DROP 0 EXIT THEN
    OVER 1 < IF 2DROP 0 EXIT THEN
    _NTM-STRIDE-FOR
    -1 1 RSHIFT OVER / 2 PICK < IF 2DROP 0 EXIT THEN
    * ;

\ =====================================================================
\  Members
\ =====================================================================

: _NTM-MEMBER  ( k team -- addr )
    DUP _NTM-STRIDE + @ ROT * SWAP _NTM-BASE + @ + ;

: _NTM-RECORD  ( k team -- addr )
    DUP _NTM-WSB + @ >R _NTM-MEMBER R> + ;

\ Member k's workspace descriptor.
: NTEAM-WS  ( k team -- ws )  _NTM-RECORD ;

\ Member k's task.
: NTEAM-TASK  ( k team -- task )  _NTM-RECORD 16 + ;

: _NTM-JOB  ( k team -- job )  _NTM-RECORD _NTM-RECORD-BYTES + ;

\ Task fields.  A task whose xt is 0 has no share.
240 CONSTANT NTEAM-TASK-BYTES
: NTASK.XT      ( task -- a )  ;
: NTASK.OUT-A   ( task -- a )  8 + ;
: NTASK.OUT-U   ( task -- a )  16 + ;
: NTASK.WS      ( task -- a )  24 + ;     \ set by NTEAM-DISPATCH
: NTASK.STATE   ( task -- a )  32 + ;     \ 0 not submitted, 1 submitted
: NTASK.STATUS  ( task -- a )  40 + ;
: NTASK.ARGS    ( task -- a )  48 + ;     \ 192 bytes for the kernel

: _NTM-MEMBER-INIT  ( k team -- )
    2DUP _NTM-MEMBER OVER _NTM-WSB + @ 2OVER NTEAM-WS NWS-INIT DROP
    2DUP NTEAM-TASK NTEAM-TASK-BYTES 0 FILL
    _NTM-JOB WJOB-INIT ;

\ Carve a team of cores members, each with ws-bytes of workspace, from the
\ aligned caller span at addr.  cores may not exceed N-FULL-CORES.
: NTEAM-INIT  ( addr bytes cores ws-bytes team -- status )
    >R
    OVER 1 < IF 2DROP 2DROP R> DROP NUM-E-RANGE EXIT THEN
    OVER N-FULL-CORES > IF 2DROP 2DROP R> DROP NUM-E-RANGE EXIT THEN
    2DUP NTEAM-BYTES ?DUP 0= IF 2DROP 2DROP R> DROP NUM-E-RANGE EXIT THEN
    3 PICK > IF 2DROP 2DROP R> DROP NUM-E-SPACE EXIT THEN
    3 PICK 63 AND IF 2DROP 2DROP R> DROP NUM-E-ALIGN EXIT THEN
    3 PICK 3 PICK MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP R> DROP NUM-E-SPACE EXIT THEN
    _NTM-ROUND R@ _NTM-WSB + !
    R@ _NTM-CORES + !
    DROP R@ _NTM-BASE + !
    R@ _NTM-WSB + @ _NTM-STRIDE-FOR R@ _NTM-STRIDE + !
    0 R@ _NTM-GEN + !  0 R@ _NTM-JOBS + !  0 R@ _NTM-OWNED + !
    R> DUP NTEAM-CORES 0 ?DO I OVER _NTM-MEMBER-INIT LOOP
    DROP NUM-OK ;

\ The span of team memory the members use.
: NTEAM-SPAN  ( team -- addr bytes )
    DUP _NTM-BASE + @ SWAP DUP NTEAM-CORES SWAP _NTM-STRIDE + @ * ;

\ Does the span a u stay clear of the team's memory?
: NTEAM-APART?  ( a u team -- flag )
    NTEAM-SPAN MSPAN-OVERLAP? 0= ;

\ Member k's share of total items: from k*total/n up to (k+1)*total/n.
: NTEAM-SHARE  ( total k team -- start end )
    NTEAM-CORES >R
    2DUP * R@ /  -ROT 1+ * R> / ;

\ =====================================================================
\  Dispatch
\ =====================================================================

\ Worker-job entry: run the task the job carries.
: _NTM-JOB-XT  ( job -- result )
    WJOB.IN-A @ DUP NTASK.XT @ EXECUTE ;

: _NTM-RESET  ( k team -- )
    2DUP NTEAM-WS -ROT NTEAM-TASK
    TUCK NTASK.WS !
    0 OVER NTASK.STATE !  0 SWAP NTASK.STATUS ! ;

: _NTM-PREPARE  ( k team -- status )
    2DUP NTEAM-TASK >R
    ['] _NTM-JOB-XT
    R@ NTEAM-TASK-BYTES
    R@ NTASK.OUT-A @ R@ NTASK.OUT-U @
    R> NTASK.WS @ DUP NWS-ADDR SWAP NWS-BYTES
    CCLASS-EXCLUSIVE-BUFFER
    8 PICK _NTM-GEN + @
    10 PICK
    11 PICK 11 PICK _NTM-JOB
    WJOB-PREPARE
    NIP NIP ;

\ Submit member k's task to core k.  A task the core cannot take stays
\ unsubmitted, for the owner to run.
: _NTM-SUBMIT  ( k team -- )
    2DUP NTEAM-TASK NTASK.XT @ 0= IF 2DROP EXIT THEN
    2DUP _NTM-PREPARE IF 2DROP EXIT THEN
    2DUP _NTM-JOB 2 PICK SWAP WJOB-SUBMIT IF
        _NTM-JOB DUP WJOB-CANCEL DROP WJOB-REAP DROP EXIT
    THEN
    1 OVER _NTM-JOBS + +!
    NTEAM-TASK NTASK.STATE 1 SWAP ! ;

: _NTM-RUN-HERE  ( k team -- )
    NTEAM-TASK DUP DUP NTASK.XT @ EXECUTE SWAP NTASK.STATUS ! ;

\ Wait for member k's job, reap it, and keep its status.
: _NTM-WAIT  ( k team -- )
    2DUP _NTM-JOB
    BEGIN DUP WJOB-POLL OVER WJOB-TERMINAL? 0= WHILE 2DROP REPEAT
    SWAP WJOB-S-SUCCEEDED <> OVER 0= AND IF DROP -1 THEN
    >R BEGIN DUP WJOB-REAP WJOB-E-BUSY <> UNTIL DROP R>
    -ROT NTEAM-TASK NTASK.STATUS ! ;

: _NTM-STATUS  ( team -- status )
    0 SWAP DUP NTEAM-CORES 0 ?DO
        OVER 0= IF I OVER NTEAM-TASK NTASK.STATUS @ ROT DROP SWAP THEN
    LOOP
    DROP ;

\ Run every member's task: the workers' as worker jobs, the owner's here,
\ and here too any share a worker core could not take.  Returns the first
\ nonzero task status in member order, or NUM-OK.
: NTEAM-DISPATCH  ( team -- status )
    DUP _NTM-GEN + 1 SWAP +!
    DUP NTEAM-CORES 0 ?DO I OVER _NTM-RESET LOOP
    COREID 0= IF
        DUP NTEAM-CORES 1 ?DO I OVER _NTM-SUBMIT LOOP
    THEN
    DUP NTEAM-CORES 0 ?DO
        I OVER NTEAM-TASK DUP NTASK.XT @ SWAP NTASK.STATE @ 0= AND IF
            I IF 1 OVER _NTM-OWNED + +! THEN
            I OVER _NTM-RUN-HERE
        THEN
    LOOP
    DUP NTEAM-CORES 1 ?DO
        I OVER NTEAM-TASK NTASK.STATE @ IF I OVER _NTM-WAIT THEN
    LOOP
    _NTM-STATUS ;
