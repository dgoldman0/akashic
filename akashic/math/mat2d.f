\ mat2d.f — 2×3 affine transform matrices (FP16)
\
\ A 2×3 matrix stored as 6 consecutive FP16 values in memory,
\ row-major order: a b tx c d ty.
\
\   ┌            ┐
\   │ a   b   tx │     x' = a·x + b·y + tx
\   │ c   d   ty │     y' = c·x + d·y + ty
\   └            ┘
\
\ Each FP16 value occupies one 64-bit cell in memory (low 16 bits
\ used; stored via ! and fetched via @, masked to 0xFFFF).
\
\ Prefix: M2D-   (public API)
\         _M2D-  (internal helpers)
\
\ Load with:   REQUIRE mat2d.f
\   (auto-loads fp16.f, fp16-ext.f, trig.f via REQUIRE)
\
\ === Public API ===
\   M2D-IDENTITY    ( addr -- )                   store identity
\   M2D-TRANSLATE   ( addr tx ty -- )             set translation only
\   M2D-SCALE       ( addr sx sy -- )             set scale (no rotation)
\   M2D-ROTATE      ( addr angle -- )             set rotation (no scale/translate)
\   M2D-MULTIPLY    ( a b dst -- )                dst = a × b
\   M2D-TRANSFORM   ( addr x y -- x' y' )        transform one point
\   M2D-TRANSFORM-N ( mat src dst n -- )          batch transform n points
\   M2D-INVERT      ( src dst -- flag )           invert; flag = success
\   M2D-COMPOSE     ( addr tx ty sx sy angle -- ) build TRS in one call
\   M2D-COPY        ( src dst -- )                copy 6 cells

REQUIRE fp16-ext.f
REQUIRE trig.f

PROVIDED akashic-mat2d

\ =====================================================================
\  Memory layout: 6 consecutive cells (one FP16 per cell)
\ =====================================================================
\  Offset +0*CELL  a    (0,0)
\  Offset +1*CELL  b    (0,1)
\  Offset +2*CELL  tx   (0,2)
\  Offset +3*CELL  c    (1,0)
\  Offset +4*CELL  d    (1,1)
\  Offset +5*CELL  ty   (1,2)
\
\  Access helpers — addr of each element:

: _M2D-A   ( base -- addr )  ;                        \ +0 cells
: _M2D-B   ( base -- addr )  CELL+ ;                  \ +1 cell
: _M2D-TX  ( base -- addr )  CELL+ CELL+ ;            \ +2 cells
: _M2D-C   ( base -- addr )  3 CELLS + ;              \ +3 cells
: _M2D-D   ( base -- addr )  4 CELLS + ;              \ +4 cells
: _M2D-TY  ( base -- addr )  5 CELLS + ;              \ +5 cells

\ Fetch element as masked FP16
: _M2D@  ( elem-addr -- fp16 )  @ 0xFFFF AND ;

\ Store element (only low 16 bits matter)
: _M2D!  ( fp16 elem-addr -- )  SWAP 0xFFFF AND SWAP ! ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _M-A
VARIABLE _M-B
VARIABLE _M-C
VARIABLE _M-D
VARIABLE _M-TX
VARIABLE _M-TY

\ =====================================================================
\  M2D-IDENTITY — store identity matrix at addr
\ =====================================================================
\  Identity: a=1 b=0 tx=0 c=0 d=1 ty=0

: M2D-IDENTITY  ( addr -- )
    DUP FP16-POS-ONE  SWAP _M2D-A  _M2D!
    DUP FP16-POS-ZERO SWAP _M2D-B  _M2D!
    DUP FP16-POS-ZERO SWAP _M2D-TX _M2D!
    DUP FP16-POS-ZERO SWAP _M2D-C  _M2D!
    DUP FP16-POS-ONE  SWAP _M2D-D  _M2D!
        FP16-POS-ZERO SWAP _M2D-TY _M2D!
    ;

\ =====================================================================
\  M2D-COPY — copy 6 cells from src to dst
\ =====================================================================

: M2D-COPY  ( src dst -- )
    OVER _M2D-A  _M2D@  OVER _M2D-A  _M2D!
    OVER _M2D-B  _M2D@  OVER _M2D-B  _M2D!
    OVER _M2D-TX _M2D@  OVER _M2D-TX _M2D!
    OVER _M2D-C  _M2D@  OVER _M2D-C  _M2D!
    OVER _M2D-D  _M2D@  OVER _M2D-D  _M2D!
    OVER _M2D-TY _M2D@  OVER _M2D-TY _M2D!
    2DROP ;

\ =====================================================================
\  M2D-TRANSLATE — set to translation matrix
\ =====================================================================
\  a=1 b=0 tx=tx c=0 d=1 ty=ty

: M2D-TRANSLATE  ( addr tx ty -- )
    ROT                                ( tx ty addr )
    DUP M2D-IDENTITY                   \ start from identity
    DUP >R                             ( tx ty addr ) ( R: addr )
    _M2D-TY _M2D!                      ( tx )
    R> _M2D-TX _M2D!                   ( )
    ;

\ =====================================================================
\  M2D-SCALE — set to scale matrix
\ =====================================================================
\  a=sx b=0 tx=0 c=0 d=sy ty=0

: M2D-SCALE  ( addr sx sy -- )
    ROT                                ( sx sy addr )
    DUP M2D-IDENTITY                   \ start from identity
    DUP >R                             ( sx sy addr ) ( R: addr )
    _M2D-D  _M2D!                      ( sx )
    R> _M2D-A  _M2D!                   ( )
    ;

\ =====================================================================
\  M2D-ROTATE — set to rotation matrix
\ =====================================================================
\  a=cos(θ)  b=-sin(θ)  tx=0
\  c=sin(θ)  d= cos(θ)  ty=0

VARIABLE _MR-SIN
VARIABLE _MR-COS

: M2D-ROTATE  ( addr angle -- )
    TRIG-SINCOS                        ( addr sin cos )
    _MR-COS !  _MR-SIN !              ( addr )
    DUP FP16-POS-ZERO SWAP _M2D-TX _M2D!
    DUP FP16-POS-ZERO SWAP _M2D-TY _M2D!
    DUP _MR-COS @ SWAP _M2D-A  _M2D!
    DUP _MR-SIN @ FP16-NEG SWAP _M2D-B  _M2D!
    DUP _MR-SIN @ SWAP _M2D-C  _M2D!
        _MR-COS @ SWAP _M2D-D  _M2D!
    ;

\ =====================================================================
\  M2D-TRANSFORM — transform one point
\ =====================================================================
\  x' = a*x + b*y + tx
\  y' = c*x + d*y + ty

VARIABLE _MT-X
VARIABLE _MT-Y

: M2D-TRANSFORM  ( addr x y -- x' y' )
    _MT-Y !  _MT-X !                  ( addr )
    \ Read matrix elements into scratch
    DUP _M2D-A  _M2D@  _M-A  !
    DUP _M2D-B  _M2D@  _M-B  !
    DUP _M2D-TX _M2D@  _M-TX !
    DUP _M2D-C  _M2D@  _M-C  !
    DUP _M2D-D  _M2D@  _M-D  !
        _M2D-TY _M2D@  _M-TY !
    \ x' = a*x + b*y + tx
    _M-A @  _MT-X @ FP16-MUL          ( a*x )
    _M-B @  _MT-Y @ FP16-MUL          ( a*x b*y )
    FP16-ADD _M-TX @ FP16-ADD         ( x' )
    \ y' = c*x + d*y + ty
    _M-C @  _MT-X @ FP16-MUL          ( x' c*x )
    _M-D @  _MT-Y @ FP16-MUL          ( x' c*x d*y )
    FP16-ADD _M-TY @ FP16-ADD         ( x' y' )
    ;

\ =====================================================================
\  M2D-TRANSFORM-N — batch transform n points
\ =====================================================================
\  Points at src/dst are stored as pairs of FP16 values (2 cells each).
\  src and dst may be the same address (in-place transform).

VARIABLE _MN-MAT
VARIABLE _MN-SRC
VARIABLE _MN-DST

: M2D-TRANSFORM-N  ( mat src dst n -- )
    >R                                 ( mat src dst ) ( R: n )
    _MN-DST !  _MN-SRC !  _MN-MAT !  ( )
    \ Read matrix once
    _MN-MAT @ _M2D-A  _M2D@  _M-A  !
    _MN-MAT @ _M2D-B  _M2D@  _M-B  !
    _MN-MAT @ _M2D-TX _M2D@  _M-TX !
    _MN-MAT @ _M2D-C  _M2D@  _M-C  !
    _MN-MAT @ _M2D-D  _M2D@  _M-D  !
    _MN-MAT @ _M2D-TY _M2D@  _M-TY !
    R>                                 ( n )
    0 DO
        \ Read source point
        _MN-SRC @ _M2D@  _MT-X !      \ x
        _MN-SRC @ CELL+ _M2D@  _MT-Y !  \ y
        \ x' = a*x + b*y + tx
        _M-A @  _MT-X @ FP16-MUL
        _M-B @  _MT-Y @ FP16-MUL
        FP16-ADD _M-TX @ FP16-ADD     ( x' )
        \ y' = c*x + d*y + ty
        _M-C @  _MT-X @ FP16-MUL
        _M-D @  _MT-Y @ FP16-MUL
        FP16-ADD _M-TY @ FP16-ADD     ( x' y' )
        \ Write dest point
        _MN-DST @ CELL+ _M2D!         \ store y'
        _MN-DST @ _M2D!               \ store x'
        \ Advance pointers
        _MN-SRC @ 2 CELLS + _MN-SRC !
        _MN-DST @ 2 CELLS + _MN-DST !
    LOOP ;

\ =====================================================================
\  M2D-MULTIPLY — matrix multiply: dst = a × b
\ =====================================================================
\  dst.a  = a.a*b.a  + a.b*b.c
\  dst.b  = a.a*b.b  + a.b*b.d
\  dst.tx = a.a*b.tx + a.b*b.ty + a.tx
\  dst.c  = a.c*b.a  + a.d*b.c
\  dst.d  = a.c*b.b  + a.d*b.d
\  dst.ty = a.c*b.tx + a.d*b.ty + a.ty
\
\  Uses separate variables so src and dst can safely be the same
\  address (but a or b must not alias dst — use a temp if needed).

VARIABLE _MM-AA   VARIABLE _MM-AB   VARIABLE _MM-ATX
VARIABLE _MM-AC   VARIABLE _MM-AD   VARIABLE _MM-ATY
VARIABLE _MM-BA   VARIABLE _MM-BB   VARIABLE _MM-BTX
VARIABLE _MM-BC   VARIABLE _MM-BD   VARIABLE _MM-BTY
VARIABLE _MM-DST

: M2D-MULTIPLY  ( a b dst -- )
    _MM-DST !
    \ Read matrix B
    DUP _M2D-A  _M2D@  _MM-BA  !
    DUP _M2D-B  _M2D@  _MM-BB  !
    DUP _M2D-TX _M2D@  _MM-BTX !
    DUP _M2D-C  _M2D@  _MM-BC  !
    DUP _M2D-D  _M2D@  _MM-BD  !
        _M2D-TY _M2D@  _MM-BTY !
    \ Read matrix A
    DUP _M2D-A  _M2D@  _MM-AA  !
    DUP _M2D-B  _M2D@  _MM-AB  !
    DUP _M2D-TX _M2D@  _MM-ATX !
    DUP _M2D-C  _M2D@  _MM-AC  !
    DUP _M2D-D  _M2D@  _MM-AD  !
        _M2D-TY _M2D@  _MM-ATY !
    \ dst.a = aa*ba + ab*bc
    _MM-AA @ _MM-BA @ FP16-MUL
    _MM-AB @ _MM-BC @ FP16-MUL  FP16-ADD
    _MM-DST @ _M2D-A _M2D!
    \ dst.b = aa*bb + ab*bd
    _MM-AA @ _MM-BB @ FP16-MUL
    _MM-AB @ _MM-BD @ FP16-MUL  FP16-ADD
    _MM-DST @ _M2D-B _M2D!
    \ dst.tx = aa*btx + ab*bty + atx
    _MM-AA @ _MM-BTX @ FP16-MUL
    _MM-AB @ _MM-BTY @ FP16-MUL  FP16-ADD
    _MM-ATX @ FP16-ADD
    _MM-DST @ _M2D-TX _M2D!
    \ dst.c = ac*ba + ad*bc
    _MM-AC @ _MM-BA @ FP16-MUL
    _MM-AD @ _MM-BC @ FP16-MUL  FP16-ADD
    _MM-DST @ _M2D-C _M2D!
    \ dst.d = ac*bb + ad*bd
    _MM-AC @ _MM-BB @ FP16-MUL
    _MM-AD @ _MM-BD @ FP16-MUL  FP16-ADD
    _MM-DST @ _M2D-D _M2D!
    \ dst.ty = ac*btx + ad*bty + aty
    _MM-AC @ _MM-BTX @ FP16-MUL
    _MM-AD @ _MM-BTY @ FP16-MUL  FP16-ADD
    _MM-ATY @ FP16-ADD
    _MM-DST @ _M2D-TY _M2D!
    ;

\ =====================================================================
\  M2D-INVERT — invert affine matrix
\ =====================================================================
\  For a 2×2 block [a b; c d], det = a*d - b*c.
\  Inverse 2×2 = (1/det) * [d -b; -c a].
\  New translation: tx' = -(inv_a * tx + inv_b * ty)
\                   ty' = -(inv_c * tx + inv_d * ty)
\  Returns flag: TRUE if invertible, FALSE if det ≈ 0.

VARIABLE _MI-DET
VARIABLE _MI-IA
VARIABLE _MI-IB
VARIABLE _MI-IC
VARIABLE _MI-ID

: M2D-INVERT  ( src dst -- flag )
    SWAP                               ( dst src )
    \ Read source matrix
    DUP _M2D-A  _M2D@  _M-A  !
    DUP _M2D-B  _M2D@  _M-B  !
    DUP _M2D-TX _M2D@  _M-TX !
    DUP _M2D-C  _M2D@  _M-C  !
    DUP _M2D-D  _M2D@  _M-D  !
        _M2D-TY _M2D@  _M-TY !
    \ det = a*d - b*c
    _M-A @ _M-D @ FP16-MUL
    _M-B @ _M-C @ FP16-MUL
    FP16-SUB                           ( dst det )
    DUP FP16-POS-ZERO FP16-EQ IF
        DROP DROP 0 EXIT               \ singular → fail
    THEN
    FP16-RECIP _MI-DET !               \ inv_det saved ( dst )
    \ Inverse 2×2: ia=d/det, ib=-b/det, ic=-c/det, id=a/det
    _M-D  @ _MI-DET @ FP16-MUL  _MI-IA !
    _M-B  @ FP16-NEG _MI-DET @ FP16-MUL  _MI-IB !
    _M-C  @ FP16-NEG _MI-DET @ FP16-MUL  _MI-IC !
    _M-A  @ _MI-DET @ FP16-MUL  _MI-ID !
    \ Write 2×2 block
    DUP _MI-IA @ SWAP _M2D-A  _M2D!
    DUP _MI-IB @ SWAP _M2D-B  _M2D!
    DUP _MI-IC @ SWAP _M2D-C  _M2D!
    DUP _MI-ID @ SWAP _M2D-D  _M2D!
    \ tx' = -(ia*tx + ib*ty)
    _MI-IA @ _M-TX @ FP16-MUL
    _MI-IB @ _M-TY @ FP16-MUL  FP16-ADD
    FP16-NEG
    OVER _M2D-TX _M2D!
    \ ty' = -(ic*tx + id*ty)
    _MI-IC @ _M-TX @ FP16-MUL
    _MI-ID @ _M-TY @ FP16-MUL  FP16-ADD
    FP16-NEG
    OVER _M2D-TY _M2D!
    DROP -1 ;                          ( flag=true )

\ =====================================================================
\  M2D-COMPOSE — build TRS (translate-rotate-scale) in one call
\ =====================================================================
\  Equivalent to: Scale(sx,sy) × Rotate(θ) applied first, then
\  Translate(tx,ty).
\
\  a = sx * cos(θ)    b = -sy * sin(θ)    tx = tx
\  c = sx * sin(θ)    d =  sy * cos(θ)    ty = ty

VARIABLE _MC-SIN
VARIABLE _MC-COS

: M2D-COMPOSE  ( addr tx ty sx sy angle -- )
    TRIG-SINCOS                        ( addr tx ty sx sy sin cos )
    _MC-COS !  _MC-SIN !              ( addr tx ty sx sy )
    \ sy → _M-D, sx → _M-A (temporary re-use)
    _M-D !  _M-A !                    ( addr tx ty )
    \ ty, tx → scratch
    _M-TY !  _M-TX !                  ( addr )
    \ a = sx * cos
    DUP  _M-A @ _MC-COS @ FP16-MUL  SWAP _M2D-A _M2D!
    \ b = -(sy * sin)
    DUP  _M-D @ _MC-SIN @ FP16-MUL FP16-NEG  SWAP _M2D-B _M2D!
    \ tx
    DUP  _M-TX @  SWAP _M2D-TX _M2D!
    \ c = sx * sin
    DUP  _M-A @ _MC-SIN @ FP16-MUL  SWAP _M2D-C _M2D!
    \ d = sy * cos
    DUP  _M-D @ _MC-COS @ FP16-MUL  SWAP _M2D-D _M2D!
    \ ty
         _M-TY @  SWAP _M2D-TY _M2D!
    ;

\ ── Concurrency ──────────────────────────────────────────
\ Mat2D words are NOT reentrant.  They use shared VARIABLE
\ scratch for intermediate results.  Callers must ensure
\ single-task access via WITH-GUARD, WITH-CRITICAL, or by
\ running with preemption disabled.
