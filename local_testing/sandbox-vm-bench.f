\ Guest cycles per sandbox VM instruction for a few loop motifs.
\
\ Each motif loops far longer than one measured slice, so a slice of
\ _VB-STEPS steps executes exactly that many VM instructions.  The core's
\ PERF-CYCLES counter brackets the slice.  This is a measurement, not a
\ contract: it reports and never fails on a number.  It reuses the golden
\ corpus's build and run helpers.

PROVIDED sbox-vm-bench

20000 CONSTANT _VB-STEPS
VARIABLE _VB-START

: _VB-REPORT  ( cycles name name-u -- )
    ." SBOX BENCH " TYPE SPACE
    _VB-STEPS . ." steps " DUP . ." cycles "
    _VB-STEPS / . ." per-step" CR TX-FLUSH ;

: _VB-SCALAR  ( source source-u memory-u name name-u -- )
    2>R
    _GC-MEM ! _GC-SRC-U ! _GC-SRC !
    _GC-LIMITS-DEFAULT
    0 _GC-INPUTS!
    _GC-SCALAR-BUILD 0= IF
        2R> TYPE ."  BUILD-FAILED" CR TX-FLUSH EXIT
    THEN
    100000000 _GC-SCALAR-INIT IF
        2R> TYPE ."  INIT-FAILED" CR TX-FLUSH _GC-SCALAR-RELEASE EXIT
    THEN
    PERF-CYCLES _VB-START !
    _VB-STEPS _GC-INSTANCE SBOX-VM-RUN-SLICE DROP
    PERF-CYCLES _VB-START @ -
    2R> _VB-REPORT
    _GC-INSTANCE SBOX-VM-RELEASE DROP
    _GC-SCALAR-RELEASE ;

: _VB-VALUE  ( source source-u memory-u name name-u -- )
    2>R
    _GC-MEM ! _GC-SRC-U ! _GC-SRC !
    _GC-LIMITS-DEFAULT
    100000000 _GC-VALUE-OPS !
    _GC-VALUE-BUILD 0= IF
        2R> TYPE ."  BUILD-FAILED" CR TX-FLUSH EXIT
    THEN
    100000000 _GC-VALUE-INIT IF
        2R> TYPE ."  INIT-FAILED" CR TX-FLUSH _GC-VALUE-RELEASE EXIT
    THEN
    PERF-CYCLES _VB-START !
    _VB-STEPS _GC-HOST SBOX-HOST-RUN-SLICE DROP
    PERF-CYCLES _VB-START @ -
    2R> _VB-REPORT
    _GC-HOST SBOX-HOST-RELEASE DROP
    _GC-VALUE-RELEASE ;

: _VB-ARITH  ( -- a u )
    S" FUNCTION a PARAMS 0 RESULTS 1 LOCALS 1 0 LOCAL.SET 0 1000000 0 DO R LOCAL.GET 0 I64.ADD LOCAL.SET 0 LOOP LOCAL.GET 0 RETURN END ENTRY main a" ;
: _VB-STACK  ( -- a u )
    S" FUNCTION s PARAMS 0 RESULTS 1 LOCALS 0 1 2 1000000 0 DO SWAP OVER I64.ADD DUP DROP TUCK NIP LOOP I64.ADD RETURN END ENTRY main s" ;
: _VB-MEMORY  ( -- a u )
    S" FUNCTION m PARAMS 0 RESULTS 1 LOCALS 0 0 1000000 0 DO R 8 MEM.STORE64 8 MEM.LOAD64 I64.ADD LOOP RETURN END ENTRY main m" ;
: _VB-CALLS  ( -- a u )
    S" FUNCTION c PARAMS 0 RESULTS 1 LOCALS 0 0 1000000 0 DO R CALL f I64.ADD LOOP RETURN END FUNCTION f PARAMS 1 RESULTS 1 LOCALS 0 1 I64.ADD RETURN END ENTRY main c" ;
: _VB-VALUES  ( -- a u )
    S" FUNCTION v PARAMS 1 RESULTS 1 LOCALS 0 1000000 0 DO DUP V.I64.GET DROP LOOP RETURN END ENTRY SIGNATURE 1 main v" ;

: SBOX-VM-BENCH  ( -- )
    ." SBOX BENCH START" CR TX-FLUSH
    _GC-GROUP-BEGIN
    PERF-RESET
    _VB-ARITH 64 S" arith-loop" _VB-SCALAR
    _VB-STACK 64 S" stack-loop" _VB-SCALAR
    _VB-MEMORY 64 S" memory-loop" _VB-SCALAR
    _VB-CALLS 64 S" call-loop" _VB-SCALAR
    _GC-PARENT-INIT
    _GC-W-RESET 41 _GC-W-I64
    _VB-VALUES 64 S" value-loop" _VB-VALUE
    _GC-PARENT-RELEASE
    ." SBOX BENCH DONE" CR TX-FLUSH ;
