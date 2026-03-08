\ =================================================================
\  stark.f  —  STARK Prover / Verifier  v2.5 (Multi-Column)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: STARK-
\  Depends on: sha3.f ntt.f baby-bear.f merkle.f stark-air.f
\
\  STARK prover & verifier over Baby Bear (q = 2013265921),
\  256-point trace, coefficient-space FRI with Merkle commitments.
\  Supports up to 8 trace columns for multi-column AIR.
\
\  Public API:
\   STARK-INIT        ( -- )               compute domain parameters
\   STARK-SET-COLS    ( n -- )             set active column count (1..8)
\   STARK-SET-AIR     ( air -- )           set AIR descriptor
\   STARK-TRACE!      ( val col idx -- )   write trace entry
\   STARK-TRACE@      ( col idx -- val )   read trace entry
\   STARK-TRACE-ZERO  ( -- )              zero all active trace columns
\   STARK-PROVE       ( -- )              generate proof
\   STARK-VERIFY      ( -- f )            verify proof (TRUE/FALSE)
\   STARK-FRI-FINAL@  ( -- val )          read FRI final constant
\
\  Uses baby-bear.f for field arithmetic, merkle.f for commitments,
\  stark-air.f for generic AIR constraint evaluation.
\  Not reentrant.
\ =================================================================

REQUIRE sha3.f
REQUIRE ntt.f
REQUIRE baby-bear.f
REQUIRE merkle.f
REQUIRE stark-air.f

PROVIDED akashic-stark

\ =====================================================================
\  Constants
\ =====================================================================

8 CONSTANT STARK-MAX-COLS

\ =====================================================================
\  Domain parameters (computed by STARK-INIT)
\ =====================================================================

VARIABLE _SK-OMEGA
VARIABLE _SK-OMEGA-INV
VARIABLE _SK-K
VARIABLE _SK-K-INV
VARIABLE _SK-K256
VARIABLE _SK-ZINV

\ =====================================================================
\  AIR descriptor pointer + column count
\ =====================================================================

VARIABLE _SK-AIR
VARIABLE _SK-NCOLS

\ =====================================================================
\  Per-column polynomial buffers (8 columns max)
\ =====================================================================
\  Trace:  8 x 1024 bytes (NTT-POLY each)
\  Coeff:  8 x 1024 bytes (NTT-POLY each)
\  Ceval:  8 x 1040 bytes (260 entries x 4)

CREATE _SK-TRACES   8192 ALLOT
CREATE _SK-TCOEFFS  8192 ALLOT
CREATE _SK-CEVALS   8320 ALLOT

\ Cols array for AIR-EVAL-TRANS (8 cells = 64 bytes)
CREATE _SK-COLS  64 ALLOT

\ =====================================================================
\  Per-column address helpers
\ =====================================================================

: _SK-TRACE-ADDR   ( col -- addr )  NTT-BYTES * _SK-TRACES + ;
: _SK-TCOEFF-ADDR  ( col -- addr )  NTT-BYTES * _SK-TCOEFFS + ;
: _SK-CEVAL-ADDR   ( col -- addr )  1040 * _SK-CEVALS + ;

\ =====================================================================
\  Per-column Merkle trees (8 x 16360 bytes)
\ =====================================================================
\  Each tree: 1 cell (n=256) + (2*256-1)*32 = 8 + 16352 = 16360 bytes.
\  Must init each tree's first cell to 256 before use.

16360 CONSTANT _SK-MTREE-SZ

CREATE _SK-MTREES  _SK-MTREE-SZ 8 * ALLOT

: _SK-MTREE-ADDR  ( col -- tree-addr )  _SK-MTREE-SZ * _SK-MTREES + ;

\ Per-column roots (8 x 32 = 256 bytes)
CREATE _SK-TROOTS  256 ALLOT

\ Combined trace root (32 bytes)
CREATE _SK-TROOT  32 ALLOT

\ =====================================================================
\  Shared scratch / single-use buffers
\ =====================================================================

NTT-POLY _SK-TMP1
NTT-POLY _SK-TMP2
NTT-POLY _SK-QCOEFF

\ Quotient Merkle tree (single, 256-leaf)
256 MERKLE-TREE _SK-MQUO

\ Scratch for leaf hashing
CREATE _SK-LBUF 4 ALLOT
CREATE _SK-LHASH 32 ALLOT

\ Quotient root
CREATE _SK-QROOT 32 ALLOT

\ FRI storage: 8 rounds, 2048 bytes
CREATE _SK-FRI-BUF  2048 ALLOT

\ FRI round commitments: 8 x 32 = 256 bytes
CREATE _SK-FRI-HASH  256 ALLOT

VARIABLE _SK-FRI-FINAL

\ Denominator + inverse buffers
\ Layout: 0..1023 = transition denoms (256 x 4)
\         1024+   = boundary denoms (up to 16 boundaries x 256 x 4)
CREATE _SK-DENOM  18432 ALLOT
CREATE _SK-DINV   18432 ALLOT

\ Per-boundary Fiat-Shamir challenges (up to 16 boundaries)
CREATE _SK-BCHAL  128 ALLOT

\ Scratch for combined root hashing
CREATE _SK-RBUF  256 ALLOT

\ =====================================================================
\  FRI round offset table
\ =====================================================================

CREATE _SK-FRI-OFF  64 ALLOT

: _SK-INIT-FRI-TBL  ( -- )
    0    _SK-FRI-OFF !
    1024 _SK-FRI-OFF 8 + !
    1536 _SK-FRI-OFF 16 + !
    1792 _SK-FRI-OFF 24 + !
    1920 _SK-FRI-OFF 32 + !
    1984 _SK-FRI-OFF 40 + !
    2016 _SK-FRI-OFF 48 + !
    2032 _SK-FRI-OFF 56 + ! ;

: _SK-FRI-ROUND-ADDR  ( round -- addr )
    8 * _SK-FRI-OFF + @ _SK-FRI-BUF + ;

: _SK-FRI-ROUND-N  ( round -- n )
    256 SWAP RSHIFT ;

\ =====================================================================
\  Fiat-Shamir transcript
\ =====================================================================

CREATE _SK-FS  32 ALLOT
CREATE _SK-FS2 64 ALLOT

: _SK-FS-INIT  ( -- )  _SK-FS 32 0 FILL ;

: _SK-FS-ABSORB32  ( addr -- )
    _SK-FS _SK-FS2 32 CMOVE
    _SK-FS2 32 + 32 CMOVE
    _SK-FS2 64 _SK-FS SHA3-256-HASH ;

: _SK-FS-CHALLENGE  ( -- val )
    _SK-FS 32 _SK-FS SHA3-256-HASH
    _SK-FS @ BB-Q MOD ;

\ =====================================================================
\  STARK-INIT
\ =====================================================================

VARIABLE _SK-INIT-I

: _SK-INIT-MTREES  ( -- )
    0 _SK-INIT-I !
    BEGIN _SK-INIT-I @ STARK-MAX-COLS < WHILE
        256 _SK-INIT-I @ _SK-MTREE-ADDR !
        _SK-INIT-I @ 1 + _SK-INIT-I !
    REPEAT ;

: STARK-INIT  ( -- )
    _SK-INIT-FRI-TBL
    NTT-Q-STARK NTT-SET-MOD
    \ Extract omega: evaluate f(x)=x via NTT
    _SK-TMP1 NTT-POLY-ZERO
    1 1 _SK-TMP1 NTT-COEFF!
    _SK-TMP1 NTT-FORWARD
    1 _SK-TMP1 NTT-COEFF@ _SK-OMEGA !
    _SK-OMEGA @ BB-INV _SK-OMEGA-INV !
    \ Coset generator
    3 _SK-K !
    _SK-K @ 256 BB-POW _SK-K256 !
    _SK-K256 @ 1 = IF
        5 _SK-K !
        _SK-K @ 256 BB-POW _SK-K256 !
    THEN
    _SK-K @ BB-INV _SK-K-INV !
    _SK-K256 @ 1 BB- BB-INV _SK-ZINV !
    \ Init column count
    1 _SK-NCOLS !
    \ Init per-column Merkle tree headers
    _SK-INIT-MTREES
    \ Set default cols pointer (col 0 ceval)
    _SK-CEVALS _SK-COLS ! ;

\ =====================================================================
\  Column management
\ =====================================================================

: STARK-SET-COLS  ( n -- )
    DUP 1 < IF DROP 1 THEN
    DUP STARK-MAX-COLS > IF DROP STARK-MAX-COLS THEN
    _SK-NCOLS ! ;

\ =====================================================================
\  AIR management
\ =====================================================================

: STARK-SET-AIR  ( air -- )  _SK-AIR ! ;

\ =====================================================================
\  Trace management (multi-column)
\ =====================================================================

: STARK-TRACE!  ( val col idx -- )
    SWAP _SK-TRACE-ADDR NTT-COEFF! ;

: STARK-TRACE@  ( col idx -- val )
    SWAP _SK-TRACE-ADDR NTT-COEFF@ ;

VARIABLE _SK-ZI

: STARK-TRACE-ZERO  ( -- )
    0 _SK-ZI !
    BEGIN _SK-ZI @ _SK-NCOLS @ < WHILE
        _SK-ZI @ _SK-TRACE-ADDR NTT-POLY-ZERO
        _SK-ZI @ 1 + _SK-ZI !
    REPEAT ;

\ =====================================================================
\  Coset evaluation
\ =====================================================================

VARIABLE _SK-KI

: _SK-COSET-EVAL  ( src dst -- )
    SWAP OVER NTT-POLY-COPY
    1 _SK-KI !
    256 0 DO
        I OVER NTT-COEFF@ _SK-KI @ BB*
        I 2 PICK NTT-COEFF!
        _SK-KI @ _SK-K @ BB* _SK-KI !
    LOOP
    NTT-FORWARD ;

: _SK-COSET-INV  ( buf -- )
    DUP NTT-INVERSE
    1 _SK-KI !
    256 0 DO
        I OVER NTT-COEFF@ _SK-KI @ BB*
        I 2 PICK NTT-COEFF!
        _SK-KI @ _SK-K-INV @ BB* _SK-KI !
    LOOP DROP ;

\ =====================================================================
\  Single-polynomial Merkle commitment (for quotient)
\ =====================================================================

VARIABLE _MC-POLY
VARIABLE _MC-TREE

: _SK-MERKLE-COMMIT  ( poly tree -- )
    _MC-TREE ! _MC-POLY !
    256 0 DO
        I _MC-POLY @ NTT-COEFF@
        _SK-LBUF BB-W32!
        _SK-LBUF 4 _SK-LHASH SHA3-256-HASH
        _SK-LHASH I _MC-TREE @ MERKLE-LEAF!
    LOOP
    _MC-TREE @ MERKLE-BUILD ;

\ =====================================================================
\  FRI fold
\ =====================================================================

VARIABLE _SK-FR-SRC
VARIABLE _SK-FR-DST
VARIABLE _SK-FR-CH

: _SK-FRI-FOLD  ( src n challenge dst -- )
    _SK-FR-DST ! _SK-FR-CH !
    2 / >R _SK-FR-SRC !
    R> 0 ?DO
        I 2 * 4 * _SK-FR-SRC @ + BB-W32@
        I 2 * 1 + 4 * _SK-FR-SRC @ + BB-W32@
        _SK-FR-CH @ BB* BB+
        I 4 * _SK-FR-DST @ + BB-W32!
    LOOP ;

\ =====================================================================
\  STARK-PROVE
\ =====================================================================

VARIABLE _SK-ALPHA
VARIABLE _SK-BETA
VARIABLE _SK-MAXOFF
VARIABLE _SK-CTRANS
VARIABLE _SK-QVAL
VARIABLE _SK-DVAL
VARIABLE _SK-BROW
VARIABLE _SK-BVAL
VARIABLE _SK-NB
VARIABLE _SK-PI
VARIABLE _SK-PJ
VARIABLE _SK-OMROW
VARIABLE _SK-FRICH
VARIABLE _SK-PC
VARIABLE _SK-BCOL

: _SK-PROVE-PER-COL  ( -- )
    \ For each column: interpolate, coset-eval, Merkle-commit
    0 _SK-PC !
    BEGIN _SK-PC @ _SK-NCOLS @ < WHILE
        \ Copy trace[c] -> tcoeff[c], inverse NTT
        _SK-PC @ _SK-TRACE-ADDR
        _SK-PC @ _SK-TCOEFF-ADDR
        NTT-POLY-COPY
        _SK-PC @ _SK-TCOEFF-ADDR NTT-INVERSE

        \ Coset-evaluate tcoeff[c] -> TMP1
        _SK-PC @ _SK-TCOEFF-ADDR _SK-TMP1 _SK-COSET-EVAL

        \ Copy coset evals to per-column extended buffer + wrap
        _SK-TMP1  _SK-PC @ _SK-CEVAL-ADDR  NTT-BYTES CMOVE
        _SK-PC @ _SK-CEVAL-ADDR
        _SK-PC @ _SK-CEVAL-ADDR 1024 +
        16 CMOVE

        \ Set cols pointer for this column
        _SK-PC @ _SK-CEVAL-ADDR
        _SK-PC @ 8 * _SK-COLS +  !

        \ Merkle-commit tcoeff[c]
        _SK-PC @ _SK-TCOEFF-ADDR
        _SK-PC @ _SK-MTREE-ADDR
        _SK-MERKLE-COMMIT

        \ Copy root to troots[c]
        _SK-PC @ _SK-MTREE-ADDR MERKLE-ROOT
        _SK-PC @ 32 * _SK-TROOTS +
        32 CMOVE

        _SK-PC @ 1 + _SK-PC !
    REPEAT ;

: _SK-COMBINE-TROOTS  ( -- )
    \ Combined trace root = SHA3( troots[0] || ... || troots[N-1] )
    _SK-TROOTS  _SK-NCOLS @ 32 *  _SK-TROOT  SHA3-256-HASH ;

: _SK-DERIVE-BCHAL  ( -- )
    \ Generate one Fiat-Shamir challenge per boundary constraint
    _SK-NB @ 0 ?DO
        _SK-FS-CHALLENGE
        I 8 * _SK-BCHAL + !
    LOOP ;

: STARK-PROVE  ( -- )
    \ Step 1-4: per-column interpolation, coset-eval, Merkle commit
    _SK-PROVE-PER-COL

    \ Step 5: combined trace root + Fiat-Shamir
    _SK-COMBINE-TROOTS
    _SK-FS-INIT
    _SK-TROOT _SK-FS-ABSORB32

    \ Get boundary count, derive per-boundary challenges
    _SK-AIR @ AIR-N-BOUND _SK-NB !
    _SK-DERIVE-BCHAL

    \ Step 6: build denominators
    _SK-AIR @ AIR-MAX-OFF _SK-MAXOFF !

    \ --- Transition zerofier denominators ---
    _SK-K @ _SK-KI !
    256 0 DO
        1 _SK-DVAL !
        _SK-MAXOFF @ 0 ?DO
            _SK-KI @
            256 I _SK-MAXOFF @ - +  _SK-OMEGA @ SWAP BB-POW
            BB-
            _SK-DVAL @ BB* _SK-DVAL !
        LOOP
        _SK-DVAL @ I 4 * _SK-DENOM + BB-W32!
        _SK-KI @ _SK-OMEGA @ BB* _SK-KI !
    LOOP

    \ Batch invert transition denominators
    _SK-DENOM _SK-DINV 256 BB-BATCH-INV

    \ --- Boundary zerofier denominators ---
    0 _SK-PJ !
    BEGIN _SK-PJ @ _SK-NB @ < WHILE
        \ Get boundary row
        _SK-AIR @ AIR-N-TRANS _SK-PJ @ + 8 * 8 +
        _SK-AIR @ + 2 + _AIR-W16@  _SK-BROW !
        _SK-BROW @ _SK-OMEGA @ SWAP BB-POW  _SK-OMROW !
        _SK-K @ _SK-KI !
        256 0 DO
            _SK-KI @ _SK-OMROW @ BB-
            _SK-PJ @ 256 * I + 4 * _SK-DENOM 1024 + + BB-W32!
            _SK-KI @ _SK-OMEGA @ BB* _SK-KI !
        LOOP
        \ Batch invert this boundary's denominators
        _SK-PJ @ 256 * 4 * _SK-DENOM 1024 + +
        _SK-PJ @ 256 * 4 * _SK-DINV  1024 + +
        256 BB-BATCH-INV
        _SK-PJ @ 1 + _SK-PJ !
    REPEAT

    \ --- Compute combined quotient on coset ---
    256 0 DO
        I _SK-PI !
        \ Transition quotient: C_trans(x_i) / Z_partial(x_i)
        _SK-AIR @ _SK-COLS _SK-PI @ AIR-EVAL-TRANS
        _SK-PI @ 4 * _SK-DINV + BB-W32@
        BB*
        _SK-ZINV @ BB*
        _SK-QVAL !

        \ Boundary quotients (per-boundary, column-aware)
        0 _SK-PJ !
        BEGIN _SK-PJ @ _SK-NB @ < WHILE
            \ Get boundary column index
            _SK-AIR @ AIR-N-TRANS _SK-PJ @ + 8 * 8 +
            _SK-AIR @ + C@  _SK-BCOL !

            \ Get boundary expected value
            _SK-AIR @ AIR-N-TRANS _SK-PJ @ + 8 * 8 +
            _SK-AIR @ + 4 + BB-W32@  _SK-BVAL !

            \ P_col(x_i) - val  (read from column's ceval buffer)
            _SK-PI @ 4 *  _SK-BCOL @ _SK-CEVAL-ADDR  + BB-W32@
            _SK-BVAL @ BB-

            \ / (x_i - omega^row)
            _SK-PJ @ 256 * _SK-PI @ + 4 * _SK-DINV 1024 + + BB-W32@
            BB*

            \ Scale by per-boundary challenge
            _SK-PJ @ 8 * _SK-BCHAL + @  BB*

            _SK-QVAL @ BB+ _SK-QVAL !
            _SK-PJ @ 1 + _SK-PJ !
        REPEAT

        _SK-QVAL @ _SK-PI @ _SK-TMP2 NTT-COEFF!
    LOOP

    \ Step 7: inverse coset -> quotient coefficients
    _SK-TMP2 _SK-QCOEFF NTT-POLY-COPY
    _SK-QCOEFF _SK-COSET-INV

    \ Step 8: commit quotient via Merkle
    _SK-QCOEFF _SK-MQUO _SK-MERKLE-COMMIT
    _SK-MQUO MERKLE-ROOT _SK-QROOT 32 CMOVE

    \ Step 9: FRI
    _SK-QROOT _SK-FS-ABSORB32

    \ Copy quotient coefficients to FRI round 0
    _SK-QCOEFF 0 _SK-FRI-ROUND-ADDR NTT-BYTES CMOVE

    \ FRI folding rounds
    8 0 DO
        \ Hash round I data
        I _SK-FRI-ROUND-ADDR
        I _SK-FRI-ROUND-N 4 *
        _SK-FRI-HASH I 32 * + SHA3-256-HASH

        \ Absorb commitment
        _SK-FRI-HASH I 32 * + _SK-FS-ABSORB32

        \ Get challenge
        _SK-FS-CHALLENGE _SK-FRICH !

        I 7 < IF
            I _SK-FRI-ROUND-ADDR
            I _SK-FRI-ROUND-N
            _SK-FRICH @
            I 1 + _SK-FRI-ROUND-ADDR
            _SK-FRI-FOLD
        ELSE
            7 _SK-FRI-ROUND-ADDR BB-W32@
            7 _SK-FRI-ROUND-ADDR 4 + BB-W32@
            _SK-FRICH @ BB* BB+
            _SK-FRI-FINAL !
        THEN
    LOOP ;

\ =====================================================================
\  STARK-VERIFY — exhaustive (multi-column)
\ =====================================================================

VARIABLE _SK-V-OK

: _SK-V-FAIL  0 _SK-V-OK ! ;

: _SK-CMP32  ( a b -- flag )
    32 0 DO
        OVER I + C@ OVER I + C@ <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP -1 ;

: _SK-VERIFY-PER-COL  ( -- )
    \ For each column: re-commit coefficients, verify Merkle root
    0 _SK-PC !
    BEGIN _SK-PC @ _SK-NCOLS @ < WHILE
        \ Re-commit tcoeff[c] -> mtree[c]
        _SK-PC @ _SK-TCOEFF-ADDR
        _SK-PC @ _SK-MTREE-ADDR
        _SK-MERKLE-COMMIT

        \ Compare root vs stored troots[c]
        _SK-PC @ _SK-MTREE-ADDR MERKLE-ROOT
        _SK-PC @ 32 * _SK-TROOTS +
        _SK-CMP32
        0= IF _SK-V-FAIL THEN

        _SK-PC @ 1 + _SK-PC !
    REPEAT ;

: _SK-VERIFY-COMBINED-ROOT  ( -- )
    \ Re-derive combined trace root, compare vs _SK-TROOT
    _SK-TROOTS _SK-NCOLS @ 32 * _SK-RBUF SHA3-256-HASH
    _SK-RBUF _SK-TROOT _SK-CMP32
    0= IF _SK-V-FAIL THEN ;

: _SK-VERIFY-TRACE-EVALS  ( -- )
    \ For each column: NTT-forward tcoeff[c] to get evals,
    \ copy to ceval[c] with wrap, set cols pointer
    0 _SK-PC !
    BEGIN _SK-PC @ _SK-NCOLS @ < WHILE
        _SK-PC @ _SK-TCOEFF-ADDR _SK-TMP1 NTT-POLY-COPY
        _SK-TMP1 NTT-FORWARD
        \ Copy evals to ceval[c] + wrap
        _SK-TMP1  _SK-PC @ _SK-CEVAL-ADDR  NTT-BYTES CMOVE
        _SK-PC @ _SK-CEVAL-ADDR
        _SK-PC @ _SK-CEVAL-ADDR 1024 +
        16 CMOVE
        \ Set cols pointer
        _SK-PC @ _SK-CEVAL-ADDR
        _SK-PC @ 8 * _SK-COLS +  !

        _SK-PC @ 1 + _SK-PC !
    REPEAT ;

: STARK-VERIFY  ( -- flag )
    -1 _SK-V-OK !

    \ 1. Verify per-column Merkle commitments
    _SK-VERIFY-PER-COL

    \ 2. Verify combined trace root
    _SK-VERIFY-COMBINED-ROOT

    \ 3. Re-derive Fiat-Shamir challenges
    _SK-FS-INIT
    _SK-TROOT _SK-FS-ABSORB32

    _SK-AIR @ AIR-N-BOUND _SK-NB !
    _SK-DERIVE-BCHAL

    \ 4. Get trace evals for AIR checking
    _SK-VERIFY-TRACE-EVALS

    \ 5. Check AIR boundaries
    _SK-AIR @ _SK-COLS AIR-CHECK-BOUND
    0= IF _SK-V-FAIL THEN

    \ 6. Check AIR transitions
    _SK-AIR @ AIR-MAX-OFF _SK-MAXOFF !
    256 _SK-MAXOFF @ - 0 DO
        _SK-AIR @ _SK-COLS I AIR-EVAL-TRANS
        0 <> IF _SK-V-FAIL THEN
    LOOP

    \ 7. Verify quotient Merkle commitment
    _SK-QCOEFF _SK-MQUO _SK-MERKLE-COMMIT
    _SK-MQUO MERKLE-ROOT _SK-QROOT _SK-CMP32
    0= IF _SK-V-FAIL THEN

    \ 8. FRI verification
    _SK-QROOT _SK-FS-ABSORB32

    \ Round 0 == quotient coefficients
    _SK-V-OK @ IF
        NTT-BYTES 0 DO
            _SK-QCOEFF I + C@
            0 _SK-FRI-ROUND-ADDR I + C@
            <> IF _SK-V-FAIL LEAVE THEN
        LOOP
    THEN

    \ Verify each FRI round
    8 0 DO
        I _SK-FRI-ROUND-ADDR
        I _SK-FRI-ROUND-N 4 *
        _SK-LHASH SHA3-256-HASH
        _SK-LHASH _SK-FRI-HASH I 32 * + _SK-CMP32
        0= IF _SK-V-FAIL THEN

        _SK-FRI-HASH I 32 * + _SK-FS-ABSORB32
        _SK-FS-CHALLENGE _SK-FRICH !

        I 7 < IF
            I _SK-FRI-ROUND-ADDR
            I _SK-FRI-ROUND-N
            _SK-FRICH @
            _SK-TMP1
            _SK-FRI-FOLD
            _SK-V-OK @ IF
                I 1 + _SK-FRI-ROUND-N 4 * 0 ?DO
                    _SK-TMP1 I + C@
                    J 1 + _SK-FRI-ROUND-ADDR I + C@
                    <> IF _SK-V-FAIL LEAVE THEN
                LOOP
            THEN
        ELSE
            7 _SK-FRI-ROUND-ADDR BB-W32@
            7 _SK-FRI-ROUND-ADDR 4 + BB-W32@
            _SK-FRICH @ BB* BB+
            _SK-FRI-FINAL @ <> IF _SK-V-FAIL THEN
        THEN
    LOOP

    _SK-V-OK @ ;

\ =====================================================================
\  Convenience
\ =====================================================================

: STARK-FRI-FINAL@  ( -- val )  _SK-FRI-FINAL @ ;
