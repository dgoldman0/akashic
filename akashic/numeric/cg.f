\ =====================================================================
\  numeric/cg.f - Conjugate gradient on a team of cores
\ =====================================================================
\  Solves A x = b for a symmetric positive definite operator A, given as
\  an execution token that applies it to an array without forming a
\  matrix:
\
\      op  ( v out team ctx -- status )      out = A v
\
\  The vectors are numeric arrays (numeric/array.f), and the vector work
\  runs on a team (numeric/team-blas1.f).  The solver keeps three arrays
\  of its own, carved from caller scratch: the residual R, and two work
\  arrays P and Q.  The caller puts b in NCG-R before a solve; the solve
\  overwrites it.  Every step is fixed, so a solve gives the same bits on
\  any number of cores:
\
\      bb = b.b;  Q = A x;  R = RN(b - Q);  P = R;  rr = R.R
\      thr = RN(RN(tol * tol) * bb);  k = 0
\      until rr <= thr:
\          stop with NUM-E-CONVERGE when k = limit
\          Q = A P;  pq = P.Q;  stop with NUM-E-CONVERGE unless pq > 0
\          alpha = RN(rr / pq)
\          x = RN(P * alpha + x);  R = RN(Q * -alpha + R)
\          rr' = R.R;  k = k + 1
\          unless rr' <= thr:  P = RN(P * RN(rr' / rr) + R)
\          rr = rr'
\
\  The dot products are the fixed-order reductions of numeric/blas1.f.
\  The scalar steps are binary64 and round to nearest even whatever
\  FPCSR's rounding mode is; the solve leaves that mode as it found it,
\  and the flags its steps raise stay set.  For an FP32 array, alpha and
\  the P coefficient are rounded to binary32 before use.
\
\  The solver's state lives in its caller-owned descriptor.
\
\  Prefix: NCG-   public API
\          _NCG-  internal helpers
\
\  Load with:   REQUIRE numeric/cg.f
\ =====================================================================

PROVIDED akashic-numeric-cg

REQUIRE team-blas1.f

\ =====================================================================
\  Descriptor
\ =====================================================================

  0 CONSTANT _NCG-OP
  8 CONSTANT _NCG-CTX
 16 CONSTANT _NCG-TOL        \ binary64 bits
 24 CONSTANT _NCG-LIMIT      \ iteration limit
 32 CONSTANT _NCG-ITERS      \ iterations of the last solve
 40 CONSTANT _NCG-RR         \ R.R, binary64 bits
 48 CONSTANT _NCG-THR        \ stopping threshold, binary64 bits
 56 CONSTANT _NCG-P          \ the descriptor now serving as P
 64 CONSTANT _NCG-Q          \ the descriptor now serving as Q
 72 CONSTANT _NCG-X
 80 CONSTANT _NCG-TEAM
 88 CONSTANT _NCG-STATUS
 96 CONSTANT _NCG-FPCSR      \ the caller's FPCSR
104 CONSTANT _NCG-SCRATCH-A
112 CONSTANT _NCG-SCRATCH-U
128 CONSTANT _NCG-RDESC      \ R, then two work descriptors
160 CONSTANT _NCG-ADESC
192 CONSTANT _NCG-BDESC
224 CONSTANT NCG-SIZE

\ The residual array; put b here before a solve.
: NCG-R  ( ncg -- arr )  _NCG-RDESC + ;

\ The work arrays, free for the caller's use outside a solve.
: NCG-P  ( ncg -- arr )  _NCG-P + @ ;
: NCG-Q  ( ncg -- arr )  _NCG-Q + @ ;

\ Iterations of the last solve, and its final R.R in binary64 bits.
: NCG-ITERATIONS  ( ncg -- n )     _NCG-ITERS + @ ;
: NCG-RESIDUAL    ( ncg -- bits )  _NCG-RR + @ ;

\ Scratch bytes for arrays shaped like like: three of them.
: NCG-SCRATCH-BYTES  ( like -- bytes )
    DUP NARR-NX OVER NARR-NY ROT NARR-FMT NARR-BYTES
    DUP -1 1 RSHIFT 3 / > IF DROP 0 EXIT THEN
    3 * ;

\ Describe the k-th array of the scratch at addr, shaped like like, at desc.
: _NCG-CARVE  ( addr like k desc -- )
    >R OVER NARR-STORAGE NIP * ROT +
    SWAP DUP NARR-NX OVER NARR-NY ROT NARR-FMT
    R> NARR-INIT DROP ;

\ Carve the solver's arrays, shaped like like, from the aligned scratch.
: NCG-INIT  ( addr bytes like ncg -- status )
    >R
    DUP NARR-FMT NUM-FORMAT? 0= IF 2DROP DROP R> DROP NUM-E-FORMAT EXIT THEN
    2 PICK 63 AND IF 2DROP DROP R> DROP NUM-E-ALIGN EXIT THEN
    DUP NCG-SCRATCH-BYTES ?DUP 0= IF 2DROP DROP R> DROP NUM-E-SPACE EXIT THEN
    2 PICK > IF 2DROP DROP R> DROP NUM-E-SPACE EXIT THEN
    2 PICK 2 PICK MSPAN-NONWRAPPING? 0= IF 2DROP DROP R> DROP NUM-E-SPACE EXIT THEN
    R@ NCG-SIZE 0 FILL
    NIP
    DUP NCG-SCRATCH-BYTES R@ _NCG-SCRATCH-U + !
    OVER R@ _NCG-SCRATCH-A + !
    2DUP 0 R@ _NCG-RDESC + _NCG-CARVE
    2DUP 1 R@ _NCG-ADESC + _NCG-CARVE
    2 R@ _NCG-BDESC + _NCG-CARVE
    R@ _NCG-ADESC + R@ _NCG-P + !
    R> DUP _NCG-BDESC + SWAP _NCG-Q + !
    NUM-OK ;

\ The operator and its context, passed back to it as ctx.
: NCG-OPERATOR!  ( xt ctx ncg -- )
    TUCK _NCG-CTX + !  _NCG-OP + ! ;

\ Stop when R.R <= tol^2 * b.b, or after limit iterations.  tol is binary64
\ bits, nonnegative and finite.
: NCG-LIMITS!  ( tol limit ncg -- status )
    OVER 0< IF DROP 2DROP NUM-E-RANGE EXIT THEN
    2 PICK 0x7FF0000000000000 U< 0= IF DROP 2DROP NUM-E-RANGE EXIT THEN
    TUCK _NCG-LIMIT + !  _NCG-TOL + !
    NUM-OK ;

\ =====================================================================
\  Solving
\ =====================================================================

: _NCG-FMT  ( ncg -- fmt )  NCG-R NARR-FMT ;

\ A binary64 scalar in the arrays' format.
: _NCG-SCALAR  ( bits ncg -- bits' )
    _NCG-FMT NUM-FP64 = IF EXIT THEN
    F64>F32 ;

: _NCG-NEGATE  ( bits ncg -- bits' )
    _NCG-FMT NUM-NEG-ZERO XOR ;

\ Q = A v.
: _NCG-APPLY  ( v ncg -- status )
    >R R@ NCG-Q R@ _NCG-TEAM + @ R@ _NCG-CTX + @ R> _NCG-OP + @ EXECUTE ;

\ Round the scalar steps to nearest even; keep the caller's mode to restore.
: _NCG-ENTER  ( ncg -- )
    FPCSR@ DUP ROT _NCG-FPCSR + !  -8 AND FPCSR! ;

\ Restore the caller's rounding mode, keeping the flags raised meanwhile.
: _NCG-LEAVE  ( ncg -- )
    _NCG-FPCSR + @ 7 AND  FPCSR@ -8 AND OR FPCSR! ;

\ bb, Q = A x, R = RN(b - Q), P = R, rr, and the threshold.
: _NCG-START  ( ncg -- status )
    >R
    R@ NCG-R R@ _NCG-TEAM + @ NT-SUMSQ ?DUP IF NIP R> DROP EXIT THEN
    R@ _NCG-TOL + @ DUP F64* F64* R@ _NCG-THR + !
    R@ _NCG-X + @ R@ _NCG-APPLY ?DUP IF R> DROP EXIT THEN
    R@ NCG-R R@ NCG-Q R@ NCG-R R@ _NCG-TEAM + @ NT-SUB ?DUP IF R> DROP EXIT THEN
    R@ NCG-R R@ NCG-P R@ _NCG-TEAM + @ NT-COPY ?DUP IF R> DROP EXIT THEN
    R@ NCG-R R@ _NCG-TEAM + @ NT-SUMSQ ?DUP IF NIP R> DROP EXIT THEN
    R@ _NCG-RR + !
    0 R> _NCG-ITERS + !
    NUM-OK ;

\ One step.  Leaves true when the solve is over, with its status kept.
: _NCG-STEP  ( ncg -- over? )
    >R
    R@ _NCG-RR + @ R@ _NCG-THR + @ F64<= IF
        NUM-OK R> _NCG-STATUS + ! -1 EXIT
    THEN
    R@ _NCG-ITERS + @ R@ _NCG-LIMIT + @ >= IF
        NUM-E-CONVERGE R> _NCG-STATUS + ! -1 EXIT
    THEN
    R@ NCG-P R@ _NCG-APPLY ?DUP IF R> _NCG-STATUS + ! -1 EXIT THEN
    R@ NCG-P R@ NCG-Q R@ _NCG-TEAM + @ NT-DOT ?DUP IF
        NIP R> _NCG-STATUS + ! -1 EXIT
    THEN
    0 OVER F64< 0= IF DROP NUM-E-CONVERGE R> _NCG-STATUS + ! -1 EXIT THEN
    R@ _NCG-RR + @ SWAP F64/ R@ _NCG-SCALAR
    DUP R@ NCG-P R@ _NCG-X + @ R@ _NCG-TEAM + @ NT-AXPY ?DUP IF
        NIP R> _NCG-STATUS + ! -1 EXIT
    THEN
    R@ _NCG-NEGATE R@ NCG-Q R@ NCG-R R@ _NCG-TEAM + @ NT-AXPY ?DUP IF
        R> _NCG-STATUS + ! -1 EXIT
    THEN
    R@ NCG-R R@ _NCG-TEAM + @ NT-SUMSQ ?DUP IF NIP R> _NCG-STATUS + ! -1 EXIT THEN
    1 R@ _NCG-ITERS + +!
    DUP R@ _NCG-THR + @ F64<= IF R> _NCG-RR + ! 0 EXIT THEN
    DUP R@ _NCG-RR + @ F64/ R@ _NCG-SCALAR
    R@ NCG-R R@ NCG-Q R@ _NCG-TEAM + @ NT-COPY ?DUP IF
        NIP NIP R> _NCG-STATUS + ! -1 EXIT
    THEN
    R@ NCG-P R@ NCG-Q R@ _NCG-TEAM + @ NT-AXPY ?DUP IF
        NIP R> _NCG-STATUS + ! -1 EXIT
    THEN
    R@ _NCG-P + @ R@ _NCG-Q + @ R@ _NCG-P + ! R@ _NCG-Q + !
    R> _NCG-RR + ! 0 ;

\ Does the span a u stay clear of the solver's scratch?
: _NCG-APART?  ( a u ncg -- flag )
    DUP _NCG-SCRATCH-A + @ SWAP _NCG-SCRATCH-U + @ MSPAN-OVERLAP? 0= ;

\ Solve A x = b, starting from x, with b in NCG-R.  x becomes the
\ solution; NCG-ITERATIONS and NCG-RESIDUAL report the solve.
: NCG-SOLVE  ( x team ncg -- status )
    >R
    OVER R@ NCG-R NARR-SAME-SHAPE? 0= IF 2DROP R> DROP NUM-E-SHAPE EXIT THEN
    R@ _NCG-OP + @ 0= IF 2DROP R> DROP NUM-E-RANGE EXIT THEN
    OVER NARR-STORAGE R@ _NCG-APART? 0= IF 2DROP R> DROP NUM-E-OVERLAP EXIT THEN
    R@ _NCG-TEAM + !  R@ _NCG-X + !
    R@ _NCG-ENTER
    R@ _NCG-START ?DUP IF R@ _NCG-LEAVE R> DROP EXIT THEN
    BEGIN R@ _NCG-STEP UNTIL
    R@ _NCG-LEAVE
    R> _NCG-STATUS + @ ;
