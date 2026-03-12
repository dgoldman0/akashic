\ =================================================================
\  ntt.f  —  NTT Polynomial Arithmetic (hardware NTT engine)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: NTT-
\  Depends on: (none — uses KDOS NTT words at MMIO 0x08C0)
\
\  The NTT engine performs 256-point Number Theoretic Transforms
\  with 32-bit coefficients.  The modulus q must satisfy
\  (q - 1) mod 256 == 0 for the primitive root to exist.
\
\  Public API — modulus selection:
\   NTT-SET-MOD      ( q -- )            set NTT modulus
\   NTT-Q-KYBER      ( -- 3329 )         ML-KEM modulus
\   NTT-Q-DILITHIUM  ( -- 8380417 )      ML-DSA modulus
\   NTT-Q-STARK      ( -- 2013265921 )   Baby Bear prime for STARKs
\
\  Public API — polynomial buffers:
\   NTT-POLY         ( "name" -- )        create named polynomial buffer
\   NTT-POLY-ZERO    ( addr -- )          zero all 256 coefficients
\   NTT-POLY-COPY    ( src dst -- )       copy polynomial
\
\  Public API — transforms:
\   NTT-FORWARD      ( addr -- )          in-place forward NTT
\   NTT-INVERSE      ( addr -- )          in-place inverse NTT
\
\  Public API — polynomial multiply:
\   NTT-POLY-MUL     ( a b r -- )         r = a * b mod q
\
\  Public API — pointwise operations (NTT domain):
\   NTT-POINTWISE-MUL  ( a b r -- )       r[i] = a[i]*b[i] mod q
\   NTT-POINTWISE-ADD  ( a b r -- )       r[i] = (a[i]+b[i]) mod q
\
\  Public API — coefficient access:
\   NTT-COEFF@       ( idx addr -- val )  read coefficient at index
\   NTT-COEFF!       ( val idx addr -- )  write coefficient at index
\
\  Public API — display:
\   NTT-POLY.        ( addr n -- )        print first n coefficients
\
\  Constants:
\   NTT-N            ( -- 256 )           polynomial degree
\   NTT-BYTES        ( -- 1024 )          buffer size in bytes
\
\  KDOS/BIOS primitives used:
\   NTT-SETQ NTT-IDX! NTT-LOAD NTT-STORE
\   NTT-FWD NTT-INV NTT-PMUL NTT-PADD
\   NTT-STATUS@ NTT-WAIT
\   NTT-BUF-A NTT-BUF-B NTT-POLYMUL
\
\  Not reentrant.  One NTT computation at a time.
\ =================================================================

PROVIDED akashic-ntt

\ =====================================================================
\  Constants
\ =====================================================================

256  CONSTANT NTT-N        \ fixed polynomial degree
1024 CONSTANT NTT-BYTES    \ 256 coefficients x 4 bytes each

\ Modulus constants
3329       CONSTANT NTT-Q-KYBER       \ ML-KEM -- Kyber
8380417    CONSTANT NTT-Q-DILITHIUM   \ ML-DSA -- Dilithium
2013265921 CONSTANT NTT-Q-STARK       \ Baby Bear prime for STARKs
\ (q-1) mod 256 == 0 required for all moduli.

\ =====================================================================
\  Modulus selection
\ =====================================================================

\ NTT-SET-MOD ( q -- )  Set the NTT modulus.
: NTT-SET-MOD  ( q -- )
    NTT-SETQ ;

\ =====================================================================
\  Polynomial buffer management
\ =====================================================================

\ NTT-POLY ( "name" -- )  Create a named polynomial buffer.
\   Allocates 256 x 4 = 1024 bytes.
: NTT-POLY  ( "name" -- )
    CREATE NTT-BYTES ALLOT ;

\ NTT-POLY-ZERO ( addr -- )  Zero all 256 coefficients.
: NTT-POLY-ZERO  ( addr -- )
    NTT-BYTES 0 FILL ;

\ NTT-POLY-COPY ( src dst -- )  Copy 1024-byte polynomial buffer.
: NTT-POLY-COPY  ( src dst -- )
    NTT-BYTES CMOVE ;

\ =====================================================================
\  Coefficient access
\ =====================================================================

\ Internal: write one byte and advance to next position.
: _NTT-C!+  ( val addr -- val' addr' )
    2DUP C! 1+ SWAP 8 RSHIFT SWAP ;

\ NTT-COEFF@ ( idx addr -- val )  Read 32-bit coefficient at index.
\   Reads 8 bytes and masks to lower 32 bits.
: NTT-COEFF@  ( idx addr -- val )
    SWAP 4 * + @ 0xFFFFFFFF AND ;

\ NTT-COEFF! ( val idx addr -- )  Write 32-bit coefficient at index.
\   Writes exactly 4 bytes little-endian, preserving adjacent data.
: NTT-COEFF!  ( val idx addr -- )
    SWAP 4 * +
    _NTT-C!+ _NTT-C!+ _NTT-C!+
    C! ;

\ =====================================================================
\  Transforms
\ =====================================================================

\ NTT-FORWARD ( addr -- )  In-place forward NTT.
\   Loads polynomial from addr into device buffer A,
\   runs forward NTT, stores result back to addr.
: NTT-FORWARD  ( addr -- )
    DUP NTT-BUF-A NTT-LOAD
    NTT-FWD NTT-WAIT
    NTT-STORE ;

\ NTT-INVERSE ( addr -- )  In-place inverse NTT.
\   Loads polynomial from addr into device buffer A,
\   runs inverse NTT, stores result back to addr.
: NTT-INVERSE  ( addr -- )
    DUP NTT-BUF-A NTT-LOAD
    NTT-INV NTT-WAIT
    NTT-STORE ;

\ =====================================================================
\  Polynomial multiply
\ =====================================================================

\ NTT-POLY-MUL ( a b r -- )  r = a * b mod q.
\   Full NTT pipeline: NTT both inputs, pointwise multiply,
\   inverse NTT, store.  Modulus must be set via NTT-SET-MOD first.
: NTT-POLY-MUL  ( a b r -- )
    NTT-POLYMUL ;

\ =====================================================================
\  Pointwise operations (NTT domain)
\ =====================================================================

\ NTT-POINTWISE-MUL ( a b r -- )  r[i] = a[i] * b[i] mod q.
\   All three buffers should be in NTT domain.
: NTT-POINTWISE-MUL  ( a b r -- )
    >R SWAP
    NTT-BUF-A NTT-LOAD
    NTT-BUF-B NTT-LOAD
    NTT-PMUL NTT-WAIT
    R> NTT-STORE ;

\ NTT-POINTWISE-ADD ( a b r -- )  r[i] = (a[i] + b[i]) mod q.
\   All three buffers should be in NTT domain.
: NTT-POINTWISE-ADD  ( a b r -- )
    >R SWAP
    NTT-BUF-A NTT-LOAD
    NTT-BUF-B NTT-LOAD
    NTT-PADD NTT-WAIT
    R> NTT-STORE ;

\ =====================================================================
\  Display
\ =====================================================================

\ NTT-POLY. ( addr n -- )  Print first n coefficients, space-separated.
: NTT-POLY.  ( addr n -- )
    DUP 0= IF 2DROP EXIT THEN
    0 DO
        DUP I 4 * + @ 0xFFFFFFFF AND .
    LOOP
    DROP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ntt-guard

' NTT-SET-MOD     CONSTANT _ntt-set-mod-xt
' NTT-POLY        CONSTANT _ntt-poly-xt
' NTT-POLY-ZERO   CONSTANT _ntt-poly-zero-xt
' NTT-POLY-COPY   CONSTANT _ntt-poly-copy-xt
' NTT-COEFF@      CONSTANT _ntt-coeff-at-xt
' NTT-COEFF!      CONSTANT _ntt-coeff-s-xt
' NTT-FORWARD     CONSTANT _ntt-forward-xt
' NTT-INVERSE     CONSTANT _ntt-inverse-xt
' NTT-POLY-MUL    CONSTANT _ntt-poly-mul-xt
' NTT-POINTWISE-MUL CONSTANT _ntt-pointwise-mul-xt
' NTT-POINTWISE-ADD CONSTANT _ntt-pointwise-add-xt
' NTT-POLY.       CONSTANT _ntt-poly-dot-xt

: NTT-SET-MOD     _ntt-set-mod-xt _ntt-guard WITH-GUARD ;
: NTT-POLY        _ntt-poly-xt _ntt-guard WITH-GUARD ;
: NTT-POLY-ZERO   _ntt-poly-zero-xt _ntt-guard WITH-GUARD ;
: NTT-POLY-COPY   _ntt-poly-copy-xt _ntt-guard WITH-GUARD ;
: NTT-COEFF@      _ntt-coeff-at-xt _ntt-guard WITH-GUARD ;
: NTT-COEFF!      _ntt-coeff-s-xt _ntt-guard WITH-GUARD ;
: NTT-FORWARD     _ntt-forward-xt _ntt-guard WITH-GUARD ;
: NTT-INVERSE     _ntt-inverse-xt _ntt-guard WITH-GUARD ;
: NTT-POLY-MUL    _ntt-poly-mul-xt _ntt-guard WITH-GUARD ;
: NTT-POINTWISE-MUL _ntt-pointwise-mul-xt _ntt-guard WITH-GUARD ;
: NTT-POINTWISE-ADD _ntt-pointwise-add-xt _ntt-guard WITH-GUARD ;
: NTT-POLY.       _ntt-poly-dot-xt _ntt-guard WITH-GUARD ;
[THEN] [THEN]
