\ par.f — Parallel Combinators for KDOS / Megapad-64
\
\ Structured parallel operations over arrays and ranges.
\ Automatically divides work across available cores.
\
\ On multicore systems, work is dispatched to secondary cores via
\ CORE-RUN and synchronized with BARRIER.  On single-core (or
\ when _PAR-NCORES = 1), all work executes sequentially on core 0 —
\ same semantics, same results, just no speedup.
\
\ Core-type awareness:
\   Megapad-64 has two core flavors:
\     - Full cores (IDs 0..N-FULL-1): have tile engine, full ISA
\     - Micro-cores (IDs N-FULL..NCORES-1): no tile engine, limited
\       stack depth, cluster scratchpad (SPAD) instead of local mem
\
\   By default, par.f distributes work only to FULL cores (safe).
\   This is controlled by _PAR-NCORES, which defaults to N-FULL.
\   Use PAR-USE-ALL to opt in to micro-cores when you know your
\   xt uses only scalar ops (no tile engine, no heap, no ALLOT).
\   Use PAR-USE-FULL to restore the safe full-cores-only default.
\
\ Core strategy:
\   _PAR-NCORES @ determines the parallelism.  Work is divided
\   into that many chunks.  Core 0 processes chunk 0 directly;
\   cores 1..N-1 receive their chunks via CORE-RUN.  BARRIER
\   waits for all cores, then core 0 collects results.
\
\ Per-core result storage:
\   A static array _PAR-RESULTS holds one cell per core (up to
\   NCORES_MAX = 16).  Each core writes its local result there.
\   No contention — each core writes a different cell.
\
\ Dependencies: event.f (via REQUIRE)
\
\ Prefix: PAR-  (public API)
\         _PAR- (internal helpers)
\
\ Load with:   REQUIRE par.f

REQUIRE ../concurrency/event.f

PROVIDED akashic-par

\ =====================================================================
\  Constants & Core-Type Configuration
\ =====================================================================

16 CONSTANT _PAR-MAX-CORES         \ max cores (matches NCORES_MAX)

\ _PAR-NCORES — number of cores used for parallel dispatch.
\ Defaults to N-FULL (full cores only).  Micro-cores are excluded
\ by default because they lack the tile engine and have limited
\ resources.  Use PAR-USE-ALL / PAR-USE-FULL to change.
VARIABLE _PAR-NCORES
N-FULL _PAR-NCORES !               \ safe default: full cores only

\ PAR-USE-FULL ( -- )  restrict to full cores only (default, safe)
: PAR-USE-FULL  ( -- )  N-FULL _PAR-NCORES ! ;

\ PAR-USE-ALL ( -- )  include micro-cores in parallel dispatch
\   Only safe when xt uses scalar ops only — no tile engine, no
\   heap allocation, no ALLOT.  Micro-cores have limited stacks
\   and no tile engine.
: PAR-USE-ALL   ( -- )  NCORES _PAR-NCORES ! ;

\ PAR-CORES ( -- n )  query current core count used by par
: PAR-CORES     ( -- n )  _PAR-NCORES @ ;

\ =====================================================================
\  Per-Core Result & Parameter Storage
\ =====================================================================

\ One result cell per core — each core writes only its own slot.
CREATE _PAR-RESULTS  _PAR-MAX-CORES CELLS ALLOT

\ Per-core parameters for dispatched work.
\ Each core needs: xt, base-addr, start-index, count.
CREATE _PAR-XT       _PAR-MAX-CORES CELLS ALLOT
CREATE _PAR-ADDR     _PAR-MAX-CORES CELLS ALLOT
CREATE _PAR-START    _PAR-MAX-CORES CELLS ALLOT
CREATE _PAR-CNT      _PAR-MAX-CORES CELLS ALLOT
CREATE _PAR-IDENT    _PAR-MAX-CORES CELLS ALLOT

\ Accessor helpers
: _PAR-RESULTS@  ( core -- val )   CELLS _PAR-RESULTS + @ ;
: _PAR-RESULTS!  ( val core -- )   CELLS _PAR-RESULTS + ! ;
: _PAR-XT@       ( core -- xt )    CELLS _PAR-XT + @ ;
: _PAR-XT!       ( xt core -- )    CELLS _PAR-XT + ! ;
: _PAR-ADDR@     ( core -- addr )  CELLS _PAR-ADDR + @ ;
: _PAR-ADDR!     ( addr core -- )  CELLS _PAR-ADDR + ! ;
: _PAR-START@    ( core -- n )     CELLS _PAR-START + @ ;
: _PAR-START!    ( n core -- )     CELLS _PAR-START + ! ;
: _PAR-CNT@      ( core -- n )     CELLS _PAR-CNT + @ ;
: _PAR-CNT!      ( n core -- )     CELLS _PAR-CNT + ! ;
: _PAR-IDENT@    ( core -- v )     CELLS _PAR-IDENT + @ ;
: _PAR-IDENT!    ( v core -- )     CELLS _PAR-IDENT + ! ;

\ =====================================================================
\  Internal — Chunk Distribution Helper
\ =====================================================================

\ _PAR-DISTRIBUTE ( count running-start -- )
\   Divide `count` items into PAR-CORES chunks and store
\   start/count for each core.  `running-start` is the base
\   index (0 for array operations, `lo` for PAR-FOR).
\
\   Writes: _PAR-START[i], _PAR-CNT[i] for i in [0, PAR-CORES).
\
\   NOTE: uses _PAR-RS variable for running-start instead of
\   the return stack, because R@ inside DO..LOOP accesses the
\   loop index, not values pushed before DO.

VARIABLE _PAR-RS                        \ running-start temp

: _PAR-DISTRIBUTE  ( count running-start -- )
    _PAR-RS !                           \ save running-start
    DUP PAR-CORES / SWAP PAR-CORES MOD  \ ( base remainder )
    PAR-CORES 0 DO
        OVER                            \ ( base rem base )
        I 2 PICK < IF 1+ THEN          \ +1 if I < remainder → chunk
        _PAR-RS @ I _PAR-START!         \ start[i] = running-start
        DUP I _PAR-CNT!                 \ cnt[i] = chunk
        DUP _PAR-RS +!                  \ running-start += chunk
        DROP                            \ drop chunk
    LOOP
    2DROP ;                             \ drop base, remainder

\ =====================================================================
\  PAR-DO — Run Two XTs in Parallel
\ =====================================================================

\ PAR-DO ( xt1 xt2 -- )
\   Run xt1 and xt2 in parallel.  On multicore (PAR-CORES >= 2),
\   xt2 is dispatched to core 1 while xt1 runs on core 0, then
\   BARRIER synchronizes.  On single-core, xt1 then xt2 run
\   sequentially.
\
\   Both XTs must have signature ( -- ).  They share no stack.
\
\   Example:   ['] compute-a ['] compute-b PAR-DO

: PAR-DO  ( xt1 xt2 -- )
    PAR-CORES 1 > IF
        1 CORE-RUN        \ dispatch xt2 to core 1
        EXECUTE            \ run xt1 on core 0
        BARRIER            \ wait for core 1
    ELSE
        SWAP EXECUTE       \ run xt1
        EXECUTE            \ run xt2
    THEN ;

\ =====================================================================
\  Internal — Map Workers
\ =====================================================================

\ _PAR-MAP-CHUNK ( -- )
\   Worker executed on each core for PAR-MAP.  Reads parameters
\   from the per-core arrays indexed by COREID.  Applies xt to
\   each element (in-place) in its assigned chunk.
\
\   For each index i in [start, start+count):
\     addr[i] = xt( addr[i] )
\
\   xt must have signature ( val -- val' ).

: _PAR-MAP-CHUNK  ( -- )
    COREID _PAR-ADDR@                   \ base addr
    COREID _PAR-START@ CELLS +          \ start element addr
    COREID _PAR-CNT@                    \ count
    0 ?DO
        DUP @                           \ ( addr val )
        COREID _PAR-XT@ EXECUTE         \ ( addr val' )
        OVER !                          \ store back
        CELL+                           \ advance to next element
    LOOP
    DROP ;

\ =====================================================================
\  PAR-MAP — Parallel Map (In-Place)
\ =====================================================================

\ PAR-MAP ( xt addr count -- )
\   Apply xt to each element of the cell array at addr (count
\   elements).  Modifies the array in-place.
\
\   xt must have signature ( val -- val' ).
\
\   The array is divided into PAR-CORES chunks.  Each core processes
\   its chunk.  On single core, runs sequentially.
\
\   Example:   [: 2 * ;] data-array 1024 PAR-MAP

: PAR-MAP  ( xt addr count -- )
    DUP 0 <= IF  DROP 2DROP EXIT  THEN  \ nothing to do
    \ Store xt for all cores
    ROT                                 \ ( addr count xt )
    PAR-CORES 0 DO  DUP I _PAR-XT!  LOOP
    DROP                                \ ( addr count )
    \ Store addr for all cores
    SWAP                                \ ( count addr )
    PAR-CORES 0 DO  DUP I _PAR-ADDR!  LOOP
    DROP                                \ ( count )
    \ Distribute chunks (start from index 0)
    0 _PAR-DISTRIBUTE                   \ ( )
    \ Dispatch to secondary cores
    PAR-CORES 1 > IF
        PAR-CORES 1 DO
            I _PAR-CNT@ 0> IF
                ['] _PAR-MAP-CHUNK I CORE-RUN
            THEN
        LOOP
    THEN
    \ Core 0 processes its own chunk
    0 _PAR-CNT@ 0> IF
        _PAR-MAP-CHUNK
    THEN
    \ Synchronize
    PAR-CORES 1 > IF  BARRIER  THEN ;

\ =====================================================================
\  Internal — Reduce Workers
\ =====================================================================

\ _PAR-REDUCE-CHUNK ( -- )
\   Worker executed on each core for PAR-REDUCE.  Reads parameters
\   from per-core arrays.  Reduces its chunk with the given xt and
\   identity, stores the local result in _PAR-RESULTS[coreid].
\
\   xt must have signature ( a b -- c ).
\
\   Stack invariant in loop: ( addr acc ) with addr on bottom.

: _PAR-REDUCE-CHUNK  ( -- )
    COREID _PAR-ADDR@
    COREID _PAR-START@ CELLS +          \ start addr
    COREID _PAR-IDENT@                  \ acc = identity
    \ ( addr acc )
    COREID _PAR-CNT@                    \ count
    0 ?DO
        OVER @                          \ ( addr acc val )
        COREID _PAR-XT@ EXECUTE         \ ( addr acc' )
        SWAP CELL+ SWAP                 \ advance addr → ( addr' acc' )
    LOOP
    NIP                                 \ drop addr, keep acc
    COREID _PAR-RESULTS!               \ store local result
    ;

\ =====================================================================
\  PAR-REDUCE — Parallel Reduction (Fold)
\ =====================================================================

\ PAR-REDUCE ( xt identity addr count -- val )
\   Parallel reduction over a cell array.
\
\   xt must have signature ( a b -- c ) and be associative.
\   identity is the neutral element (0 for +, 1 for *, etc.).
\
\   Each core reduces its chunk locally, then core 0 does a
\   final sequential reduction of the per-core results.
\
\   Example:   ['] + 0 data-array 1024 PAR-REDUCE .

: PAR-REDUCE  ( xt identity addr count -- val )
    DUP 0 <= IF  2DROP NIP EXIT  THEN   \ return identity
    >R >R                               \ ( xt identity ) R: count addr
    \ Store xt for all cores
    SWAP                                \ ( identity xt )
    PAR-CORES 0 DO  DUP I _PAR-XT!  LOOP
    DROP                                \ ( identity )
    \ Store identity for all cores
    PAR-CORES 0 DO  DUP I _PAR-IDENT!  LOOP
    DROP                                \ ( )
    \ Store addr for all cores
    R>                                  \ ( addr ) R: count
    PAR-CORES 0 DO  DUP I _PAR-ADDR!  LOOP
    DROP                                \ ( )
    \ Distribute chunks (start from index 0)
    R>                                  \ ( count )
    0 _PAR-DISTRIBUTE                   \ ( )
    \ Initialize results to identity
    PAR-CORES 0 DO
        I _PAR-IDENT@ I _PAR-RESULTS!
    LOOP
    \ Dispatch to secondary cores
    PAR-CORES 1 > IF
        PAR-CORES 1 DO
            I _PAR-CNT@ 0> IF
                ['] _PAR-REDUCE-CHUNK I CORE-RUN
            THEN
        LOOP
    THEN
    \ Core 0 processes its own chunk
    0 _PAR-CNT@ 0> IF
        _PAR-REDUCE-CHUNK
    THEN
    \ Synchronize
    PAR-CORES 1 > IF  BARRIER  THEN
    \ Final reduction: combine per-core results on core 0
    0 _PAR-XT@                          \ ( xt )
    0 _PAR-RESULTS@                     \ ( xt acc )
    PAR-CORES 1 ?DO
        I _PAR-RESULTS@                 \ ( xt acc val )
        2 PICK EXECUTE                  \ ( xt acc' )
    LOOP
    NIP ;                               \ drop xt, leave result

\ =====================================================================
\  Internal — For Workers
\ =====================================================================

\ _PAR-FOR-CHUNK ( -- )
\   Worker for PAR-FOR.  Calls xt with each index in
\   [start, start+count).
\
\   xt must have signature ( i -- ).

: _PAR-FOR-CHUNK  ( -- )
    COREID _PAR-START@                  \ lo
    COREID _PAR-CNT@                    \ count
    OVER +                              \ hi = lo + count
    SWAP ?DO
        I COREID _PAR-XT@ EXECUTE
    LOOP ;

\ =====================================================================
\  PAR-FOR — Parallel FOR Loop
\ =====================================================================

\ PAR-FOR ( xt lo hi -- )
\   Execute xt for each index in [lo, hi).  The range is divided
\   across PAR-CORES cores.
\
\   xt must have signature ( i -- ).
\
\   Example:   [: ( i -- ) DUP CELLS data + @ process ;] 0 1000 PAR-FOR

: PAR-FOR  ( xt lo hi -- )
    2DUP >= IF  DROP 2DROP EXIT  THEN   \ empty range
    OVER -                              \ ( xt lo total-count )
    >R >R                               \ ( xt ) R: total-count lo
    \ Store xt for all cores
    PAR-CORES 0 DO  DUP I _PAR-XT!  LOOP
    DROP                                \ ( )
    \ Distribute chunks starting from lo
    R> R>                               \ ( lo total-count )
    SWAP _PAR-DISTRIBUTE                \ ( )
    \ Dispatch to secondary cores
    PAR-CORES 1 > IF
        PAR-CORES 1 DO
            I _PAR-CNT@ 0> IF
                ['] _PAR-FOR-CHUNK I CORE-RUN
            THEN
        LOOP
    THEN
    \ Core 0 processes its own chunk
    0 _PAR-CNT@ 0> IF
        _PAR-FOR-CHUNK
    THEN
    \ Synchronize
    PAR-CORES 1 > IF  BARRIER  THEN ;

\ =====================================================================
\  PAR-SCATTER — Distribute Data to Per-Core Arenas
\ =====================================================================

\ PAR-SCATTER ( src-addr elem-size count -- )
\   Distribute `count` elements of `elem-size` bytes from src-addr
\   into the per-core parameter tables.  Each core gets a contiguous
\   chunk.  After scatter, core I's data starts at
\   src-addr + (core_start × elem-size).
\
\   This is a setup helper — it fills _PAR-ADDR, _PAR-START,
\   and _PAR-CNT for subsequent per-core processing.

: PAR-SCATTER  ( src-addr elem-size count -- )
    DUP 0 <= IF  DROP 2DROP EXIT  THEN
    >R SWAP                             \ ( elem-size src-addr ) R: count
    PAR-CORES 0 DO  DUP I _PAR-ADDR!  LOOP
    DROP                                \ ( elem-size ) R: count
    R>                                  \ ( elem-size count )
    0 _PAR-DISTRIBUTE                   \ ( elem-size )
    DROP ;                              \ drop elem-size

\ =====================================================================
\  PAR-GATHER — Collect Per-Core Results
\ =====================================================================

\ PAR-GATHER ( dest-addr count -- )
\   Copy per-core results from _PAR-RESULTS into a destination
\   array.  Copies min(count, PAR-CORES) cells.

: PAR-GATHER  ( dest-addr count -- )
    PAR-CORES MIN
    0 ?DO
        I _PAR-RESULTS@ OVER !
        CELL+
    LOOP
    DROP ;

\ =====================================================================
\  PAR-INFO — Debug Display
\ =====================================================================

\ PAR-INFO ( -- )
\   Print parallel combinator state for debugging.

: PAR-INFO  ( -- )
    ." [par active=" PAR-CORES .
    ." full=" N-FULL .
    ." total=" NCORES .
    ." ]" CR
    PAR-CORES 0 DO
        ."   core " I .
        I FULL-CORE? IF ." (full)" ELSE ." (micro)" THEN
        ."  start=" I _PAR-START@ .
        ."  cnt=" I _PAR-CNT@ .
        ."  result=" I _PAR-RESULTS@ .
        CR
    LOOP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  PAR-USE-FULL ( -- )                    Use full cores only (default)
\  PAR-USE-ALL  ( -- )                    Use all cores incl. micro
\  PAR-CORES    ( -- n )                  Query active core count
\  PAR-DO       ( xt1 xt2 -- )           Run two XTs in parallel
\  PAR-MAP      ( xt addr count -- )     Parallel in-place map
\  PAR-REDUCE   ( xt id addr count -- v) Parallel reduction
\  PAR-FOR      ( xt lo hi -- )          Parallel FOR loop
\  PAR-SCATTER  ( src esize count -- )   Distribute to per-core params
\  PAR-GATHER   ( dest count -- )        Collect per-core results
\  PAR-INFO     ( -- )                   Debug display (shows core types)
