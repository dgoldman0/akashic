\ fft.f — Radix-2 Cooley-Tukey FFT for FP16
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ In-place radix-2 DIT (decimation-in-time) FFT on paired
\ real / imaginary arrays of N FP16 values (N must be power of 2).
\
\ Twiddle factors computed on-the-fly via TRIG-SINCOS to avoid
\ accumulation error in FP16's 10-bit mantissa.  Precomputed-twiddle
\ variants (*-TW) replace per-butterfly TRIG-SINCOS with table
\ lookups for a ~3-5× speedup on repeated transforms.
\
\ Prefix: FFT-   (public API)
\         _FFT-  (internal helpers)
\
\ Depends on: fp16.f, fp16-ext.f, trig.f, simd-ext.f
\
\ Load with:   REQUIRE fft.f
\
\ === Public API ===
\   FFT-FORWARD    ( re im n -- )              in-place radix-2 FFT
\   FFT-INVERSE    ( re im n -- )              in-place inverse FFT
\   FFT-MAGNITUDE  ( re im mag n -- )          |X[k]| = sqrt(re²+im²)
\   FFT-POWER      ( re im pwr n -- )          power spectrum: re²+im²
\   FFT-CONVOLVE   ( a b dst n -- )            convolution via FFT
\   FFT-CORRELATE  ( a b dst n -- )            cross-correlation via FFT
\
\ === Precomputed-Twiddle API (Tier 3.1) ===
\   FFT-TWIDDLE-ALLOC  ( n -- addr )           allocate twiddle table
\   FFT-TWIDDLE-FILL   ( n addr -- )           fill twiddle table (one-time)
\   FFT-FORWARD-TW     ( re im n tw -- )       FFT with precomputed twiddle
\   FFT-INVERSE-TW     ( re im n tw -- )       IFFT with precomputed twiddle
\   FFT-CONVOLVE-TW    ( a b dst n tw -- )     convolution with twiddle
\   FFT-CORRELATE-TW   ( a b dst n tw -- )     correlation with twiddle

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE simd-ext.f

PROVIDED akashic-fft

\ =====================================================================
\  Constants
\ =====================================================================

0x0000 CONSTANT _FFT-ZERO            \ 0.0
0x3C00 CONSTANT _FFT-ONE             \ 1.0
0xBC00 CONSTANT _FFT-NEG1            \ -1.0
0x4000 CONSTANT _FFT-TWO             \ 2.0

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _FFT-RE                     \ real array pointer
VARIABLE _FFT-IM                     \ imaginary array pointer
VARIABLE _FFT-N                      \ array length
VARIABLE _FFT-DIR                    \ direction: -1.0 fwd, +1.0 inv

\ Bit-reversal
VARIABLE _FFT-J                      \ reversed index
VARIABLE _FFT-TMP                    \ swap temp

\ Butterfly stage
VARIABLE _FFT-STAGE                  \ current stage (1, 2, 4, ... N)
VARIABLE _FFT-HALF                   \ half = stage / 2
VARIABLE _FFT-AINC                   \ angle increment per butterfly
VARIABLE _FFT-WR                     \ twiddle real (cos)
VARIABLE _FFT-WI                     \ twiddle imag (sin)
VARIABLE _FFT-TR                     \ butterfly temp real
VARIABLE _FFT-TI                     \ butterfly temp imag

\ =====================================================================
\  _FFT-LOG2 — integer log2 of N (N must be power of 2)
\ =====================================================================
\  Returns number of bits: 4→2, 8→3, 16→4, etc.

VARIABLE _FFT-LOG2-V

: _FFT-LOG2  ( n -- log2 )
    0 _FFT-LOG2-V !
    1 RSHIFT                          \ n / 2
    BEGIN DUP 0 > WHILE
        _FFT-LOG2-V @ 1+ _FFT-LOG2-V !
        1 RSHIFT
    REPEAT
    DROP _FFT-LOG2-V @ ;

\ =====================================================================
\  _FFT-BITREV — bit-reverse index i for nbits-wide field
\ =====================================================================

VARIABLE _FFT-BRV
VARIABLE _FFT-BRI
VARIABLE _FFT-BRBITS

: _FFT-BITREV  ( i nbits -- reversed )
    _FFT-BRBITS !
    0 _FFT-BRV !
    _FFT-BRBITS @ 0 DO
        _FFT-BRV @ 1 LSHIFT           ( i rev<<1 )
        OVER 1 AND OR _FFT-BRV !      ( i )
        1 RSHIFT                       ( i>>1 )
    LOOP
    DROP _FFT-BRV @ ;

\ =====================================================================
\  _FFT-PERMUTE — bit-reversal permutation of re[] and im[]
\ =====================================================================
\  Swap re[i]↔re[j] and im[i]↔im[j] for all i < j where j is
\  the bit-reverse of i.

VARIABLE _FFT-PERM-NBITS

: _FFT-PERMUTE  ( -- )
    _FFT-N @ _FFT-LOG2 _FFT-PERM-NBITS !
    _FFT-N @ 0 DO
        I _FFT-PERM-NBITS @ _FFT-BITREV  ( j )
        I OVER < IF                        \ only swap when i < j
            _FFT-J !                       \ save j
            \ Swap re[i] ↔ re[j]
            _FFT-RE @ I 2 * + W@ _FFT-TMP !
            _FFT-RE @ _FFT-J @ 2 * + W@
            _FFT-RE @ I 2 * + W!
            _FFT-TMP @ _FFT-RE @ _FFT-J @ 2 * + W!
            \ Swap im[i] ↔ im[j]
            _FFT-IM @ I 2 * + W@ _FFT-TMP !
            _FFT-IM @ _FFT-J @ 2 * + W@
            _FFT-IM @ I 2 * + W!
            _FFT-TMP @ _FFT-IM @ _FFT-J @ 2 * + W!
        ELSE
            DROP
        THEN
    LOOP ;

\ =====================================================================
\  _FFT-BUTTERFLY — one butterfly pass at current stage
\ =====================================================================
\  For each group of _FFT-STAGE elements, combine pairs separated
\  by _FFT-HALF using twiddle factors.
\
\  For butterfly index k in [0, half):
\    angle = dir * 2π * k / stage
\    w = cos(angle) + i*sin(angle)
\    t = w * (re[j+half], im[j+half])    — complex multiply
\    (re[j], im[j])       += t
\    (re[j+half], im[j+half]) = old(j) - t

VARIABLE _FFT-GRP                    \ group start index
VARIABLE _FFT-U                      \ upper index
VARIABLE _FFT-L                      \ lower index
VARIABLE _FFT-UR                     \ saved upper re
VARIABLE _FFT-UI                     \ saved upper im
VARIABLE _FFT-K                      \ butterfly index within group
VARIABLE _FFT-ANGLE                  \ computed angle for twiddle

: _FFT-BUTTERFLY  ( -- )
    \ Compute angle increment: dir * 2π / stage
    _FFT-DIR @ TRIG-2PI FP16-MUL
    _FFT-STAGE @ INT>FP16 FP16-DIV
    _FFT-AINC !

    \ Iterate over groups using BEGIN...WHILE (avoids nested DO/J)
    0 _FFT-GRP !
    BEGIN _FFT-GRP @ _FFT-N @ < WHILE
        \ For each butterfly in this group
        0 _FFT-K !
        BEGIN _FFT-K @ _FFT-HALF @ < WHILE
            \ Compute indices
            _FFT-GRP @ _FFT-K @ + _FFT-U !
            _FFT-U @ _FFT-HALF @ + _FFT-L !

            \ Compute twiddle: angle = ainc * k
            _FFT-K @ 0= IF
                \ k=0: twiddle is always (1, 0)
                _FFT-ONE _FFT-WR !
                _FFT-ZERO _FFT-WI !
            ELSE
                _FFT-AINC @ _FFT-K @ INT>FP16 FP16-MUL
                _FFT-ANGLE !
                \ Workaround: _TR-REDUCE has a bug with negative angles.
                \ Use identity: cos(-x)=cos(x), sin(-x)=-sin(x)
                _FFT-ANGLE @ FP16-SIGN IF
                    _FFT-ANGLE @ FP16-NEG TRIG-SINCOS  ( sin cos )
                    _FFT-WR !                   \ cos → wr
                    FP16-NEG _FFT-WI !           \ -sin → wi
                ELSE
                    _FFT-ANGLE @ TRIG-SINCOS    ( sin cos )
                    _FFT-WR !                   \ cos → wr
                    _FFT-WI !                   \ sin → wi
                THEN
            THEN

            \ Load lower element
            _FFT-L @ 2 * _FFT-RE @ + W@   ( re_lo )
            _FFT-L @ 2 * _FFT-IM @ + W@   ( re_lo im_lo )

            \ Complex multiply: t = w * lower
            \ tr = wr*re_lo - wi*im_lo
            OVER _FFT-WR @ FP16-MUL       ( re_lo im_lo wr*re )
            OVER _FFT-WI @ FP16-MUL       ( re_lo im_lo wr*re wi*im )
            FP16-SUB _FFT-TR !             ( re_lo im_lo )
            \ ti = wr*im_lo + wi*re_lo
            _FFT-WR @ FP16-MUL            ( re_lo wr*im )
            SWAP _FFT-WI @ FP16-MUL       ( wr*im wi*re )
            FP16-ADD _FFT-TI !             ( )

            \ Save upper element
            _FFT-U @ 2 * _FFT-RE @ + W@ _FFT-UR !
            _FFT-U @ 2 * _FFT-IM @ + W@ _FFT-UI !

            \ upper = old_upper + t
            _FFT-UR @ _FFT-TR @ FP16-ADD
            _FFT-U @ 2 * _FFT-RE @ + W!
            _FFT-UI @ _FFT-TI @ FP16-ADD
            _FFT-U @ 2 * _FFT-IM @ + W!

            \ lower = old_upper - t
            _FFT-UR @ _FFT-TR @ FP16-SUB
            _FFT-L @ 2 * _FFT-RE @ + W!
            _FFT-UI @ _FFT-TI @ FP16-SUB
            _FFT-L @ 2 * _FFT-IM @ + W!

            _FFT-K @ 1+ _FFT-K !
        REPEAT
        _FFT-GRP @ _FFT-STAGE @ + _FFT-GRP !
    REPEAT ;

\ =====================================================================
\  FFT-FORWARD — in-place radix-2 forward FFT
\ =====================================================================

: FFT-FORWARD  ( re im n -- )
    _FFT-N !  _FFT-IM !  _FFT-RE !
    _FFT-NEG1 _FFT-DIR !             \ forward: -1

    _FFT-PERMUTE

    \ Butterfly stages: stage = 2, 4, 8, ... N
    2 _FFT-STAGE !
    BEGIN _FFT-STAGE @ _FFT-N @ <= WHILE
        _FFT-STAGE @ 2/ _FFT-HALF !
        _FFT-BUTTERFLY
        _FFT-STAGE @ 2* _FFT-STAGE !
    REPEAT ;

\ =====================================================================
\  FFT-INVERSE — in-place radix-2 inverse FFT
\ =====================================================================
\  Same butterfly with direction = +1, then divide by N.

VARIABLE _FFT-INV-I
VARIABLE _FFT-INV-N16                \ N as FP16

: FFT-INVERSE  ( re im n -- )
    _FFT-N !  _FFT-IM !  _FFT-RE !
    _FFT-ONE _FFT-DIR !              \ inverse: +1

    _FFT-PERMUTE

    2 _FFT-STAGE !
    BEGIN _FFT-STAGE @ _FFT-N @ <= WHILE
        _FFT-STAGE @ 2/ _FFT-HALF !
        _FFT-BUTTERFLY
        _FFT-STAGE @ 2* _FFT-STAGE !
    REPEAT

    \ Scale by 1/N
    _FFT-N @ INT>FP16 _FFT-INV-N16 !
    0 _FFT-INV-I !
    BEGIN _FFT-INV-I @ _FFT-N @ < WHILE
        \ re[i] /= N
        _FFT-RE @ _FFT-INV-I @ 2 * +    ( addr )
        DUP W@                           ( addr val )
        _FFT-INV-N16 @ FP16-DIV          ( addr val/N )
        SWAP W!                          ( )
        \ im[i] /= N
        _FFT-IM @ _FFT-INV-I @ 2 * +    ( addr )
        DUP W@                           ( addr val )
        _FFT-INV-N16 @ FP16-DIV          ( addr val/N )
        SWAP W!                          ( )
        _FFT-INV-I @ 1+ _FFT-INV-I !
    REPEAT ;

\ =====================================================================
\  FFT-MAGNITUDE — |X[k]| = sqrt(re² + im²)
\ =====================================================================
\  Writes result into mag[] array (caller must allocate n*2 bytes).

VARIABLE _FFT-MAG-I
VARIABLE _FFT-MAG-N

: FFT-MAGNITUDE  ( re im mag n -- )
    _FFT-MAG-N !
    ROT ROT                          ( mag re im )
    _FFT-IM !  _FFT-RE !             ( mag )
    0 _FFT-MAG-I !
    BEGIN _FFT-MAG-I @ _FFT-MAG-N @ < WHILE
        _FFT-RE @ _FFT-MAG-I @ 2 * + W@   ( mag re_i )
        DUP FP16-MUL                       ( mag re² )
        _FFT-IM @ _FFT-MAG-I @ 2 * + W@   ( mag re² im_i )
        DUP FP16-MUL                       ( mag re² im² )
        FP16-ADD                           ( mag re²+im² )
        FP16-SQRT                          ( mag sqrt )
        OVER _FFT-MAG-I @ 2 * + W!        ( mag )
        _FFT-MAG-I @ 1+ _FFT-MAG-I !
    REPEAT
    DROP ;

\ =====================================================================
\  FFT-POWER — power spectrum: re² + im²
\ =====================================================================
\  Writes result into pwr[] array (caller must allocate n*2 bytes).

VARIABLE _FFT-PWR-I
VARIABLE _FFT-PWR-N

: FFT-POWER  ( re im pwr n -- )
    _FFT-PWR-N !
    ROT ROT                          ( pwr re im )
    _FFT-IM !  _FFT-RE !             ( pwr )
    0 _FFT-PWR-I !
    BEGIN _FFT-PWR-I @ _FFT-PWR-N @ < WHILE
        _FFT-RE @ _FFT-PWR-I @ 2 * + W@   ( pwr re_i )
        DUP FP16-MUL                       ( pwr re² )
        _FFT-IM @ _FFT-PWR-I @ 2 * + W@   ( pwr re² im_i )
        DUP FP16-MUL                       ( pwr re² im² )
        FP16-ADD                           ( pwr re²+im² )
        OVER _FFT-PWR-I @ 2 * + W!        ( pwr )
        _FFT-PWR-I @ 1+ _FFT-PWR-I !
    REPEAT
    DROP ;

\ =====================================================================
\  FFT-CONVOLVE — convolution via FFT
\ =====================================================================
\  Computes circular convolution of real signals a[] and b[],
\  stores result in dst[].  All arrays must be N FP16 values.
\  Allocates temporary arrays internally.

VARIABLE _FFT-CONV-N
VARIABLE _FFT-CONV-RA
VARIABLE _FFT-CONV-IA
VARIABLE _FFT-CONV-RB
VARIABLE _FFT-CONV-IB
VARIABLE _FFT-CONV-I
VARIABLE _FFT-CONV-A
VARIABLE _FFT-CONV-B
VARIABLE _FFT-CONV-DST

: FFT-CONVOLVE  ( a b dst n -- )
    _FFT-CONV-N !
    _FFT-CONV-DST !
    _FFT-CONV-B !
    _FFT-CONV-A !

    \ Allocate temporaries: re_a, im_a, re_b, im_b (each n*2 bytes)
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-RA !
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-IA !
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-RB !
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-IB !

    \ Copy a→re_a, zero im_a; copy b→re_b, zero im_b
    0 _FFT-CONV-I !
    BEGIN _FFT-CONV-I @ _FFT-CONV-N @ < WHILE
        _FFT-CONV-A @ _FFT-CONV-I @ 2 * + W@
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W!
        _FFT-ZERO _FFT-CONV-IA @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-B @ _FFT-CONV-I @ 2 * + W@
        _FFT-CONV-RB @ _FFT-CONV-I @ 2 * + W!
        _FFT-ZERO _FFT-CONV-IB @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-I @ 1+ _FFT-CONV-I !
    REPEAT

    \ FFT both
    _FFT-CONV-RA @ _FFT-CONV-IA @ _FFT-CONV-N @ FFT-FORWARD
    _FFT-CONV-RB @ _FFT-CONV-IB @ _FFT-CONV-N @ FFT-FORWARD

    \ Pointwise complex multiply: (ra+i*ia)*(rb+i*ib)
    \ Result back into ra+i*ia.  Uses _FFT-UR/UI/WR/WI as scratch.
    0 _FFT-CONV-I !
    BEGIN _FFT-CONV-I @ _FFT-CONV-N @ < WHILE
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W@ _FFT-UR !
        _FFT-CONV-IA @ _FFT-CONV-I @ 2 * + W@ _FFT-UI !
        _FFT-CONV-RB @ _FFT-CONV-I @ 2 * + W@ _FFT-WR !
        _FFT-CONV-IB @ _FFT-CONV-I @ 2 * + W@ _FFT-WI !
        \ re_out = ra*rb - ia*ib
        _FFT-UR @ _FFT-WR @ FP16-MUL
        _FFT-UI @ _FFT-WI @ FP16-MUL
        FP16-SUB
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W!
        \ im_out = ra*ib + ia*rb
        _FFT-UR @ _FFT-WI @ FP16-MUL
        _FFT-UI @ _FFT-WR @ FP16-MUL
        FP16-ADD
        _FFT-CONV-IA @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-I @ 1+ _FFT-CONV-I !
    REPEAT

    \ IFFT
    _FFT-CONV-RA @ _FFT-CONV-IA @ _FFT-CONV-N @ FFT-INVERSE

    \ Copy real part to dst
    0 _FFT-CONV-I !
    BEGIN _FFT-CONV-I @ _FFT-CONV-N @ < WHILE
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W@
        _FFT-CONV-DST @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-I @ 1+ _FFT-CONV-I !
    REPEAT ;

\ =====================================================================
\  FFT-CORRELATE — cross-correlation via FFT
\ =====================================================================
\  Same as convolution but conjugates B's FFT before multiplication.
\  corr(a,b)[k] = IFFT( FFT(a) * conj(FFT(b)) )

VARIABLE _FFT-CORR-N
VARIABLE _FFT-CORR-RA
VARIABLE _FFT-CORR-IA
VARIABLE _FFT-CORR-RB
VARIABLE _FFT-CORR-IB
VARIABLE _FFT-CORR-I
VARIABLE _FFT-CORR-A
VARIABLE _FFT-CORR-B
VARIABLE _FFT-CORR-DST

: FFT-CORRELATE  ( a b dst n -- )
    _FFT-CORR-N !
    _FFT-CORR-DST !
    _FFT-CORR-B !
    _FFT-CORR-A !

    \ Allocate temporaries
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-RA !
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-IA !
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-RB !
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-IB !

    \ Copy a→re_a, zero im_a; copy b→re_b, zero im_b
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-A @ _FFT-CORR-I @ 2 * + W@
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W!
        _FFT-ZERO _FFT-CORR-IA @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-B @ _FFT-CORR-I @ 2 * + W@
        _FFT-CORR-RB @ _FFT-CORR-I @ 2 * + W!
        _FFT-ZERO _FFT-CORR-IB @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT

    \ FFT both
    _FFT-CORR-RA @ _FFT-CORR-IA @ _FFT-CORR-N @ FFT-FORWARD
    _FFT-CORR-RB @ _FFT-CORR-IB @ _FFT-CORR-N @ FFT-FORWARD

    \ Conjugate B: negate im_b
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-IB @ _FFT-CORR-I @ 2 * + DUP W@
        FP16-NEG SWAP W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT

    \ Pointwise complex multiply: (ra+i*ia)*(rb+i*ib)  [ib already negated]
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W@ _FFT-UR !
        _FFT-CORR-IA @ _FFT-CORR-I @ 2 * + W@ _FFT-UI !
        _FFT-CORR-RB @ _FFT-CORR-I @ 2 * + W@ _FFT-WR !
        _FFT-CORR-IB @ _FFT-CORR-I @ 2 * + W@ _FFT-WI !
        \ re_out = ra*rb - ia*ib
        _FFT-UR @ _FFT-WR @ FP16-MUL
        _FFT-UI @ _FFT-WI @ FP16-MUL
        FP16-SUB
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W!
        \ im_out = ra*ib + ia*rb
        _FFT-UR @ _FFT-WI @ FP16-MUL
        _FFT-UI @ _FFT-WR @ FP16-MUL
        FP16-ADD
        _FFT-CORR-IA @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT

    \ IFFT
    _FFT-CORR-RA @ _FFT-CORR-IA @ _FFT-CORR-N @ FFT-INVERSE

    \ Copy real part to dst
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W@
        _FFT-CORR-DST @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT ;

\ =====================================================================
\  Precomputed Twiddle Table (Tier 3.1)
\ =====================================================================
\  For a fixed FFT size N, precompute cos(2π·k/N) and sin(2π·k/N)
\  for k = 0 .. N/2−1.  Eliminates per-butterfly TRIG-SINCOS calls.
\
\  Memory layout at address tw:
\    tw + 0   : cos[0..N/2−1]    N bytes  (twiddle cos)
\    tw + N   : sin[0..N/2−1]    N bytes  (twiddle sin)
\    tw + 2N  : wr_expanded      N bytes  (SIMD workspace)
\    tw + 3N  : wi_expanded      N bytes  (SIMD workspace)
\    tw + 4N  : temp1            N bytes  (SIMD workspace)
\    tw + 5N  : temp2            N bytes  (SIMD workspace)
\  Total: 6·N bytes.  For N=2048 this is 12 KB.
\
\  Twiddle reuse across stages:
\    For stage S with half = S/2, stride = N/S.
\    twiddle[k] = ( cos[k·stride], sin[k·stride] )
\    All stages index the same table at different strides.

VARIABLE _FFT-TW                     \ twiddle table pointer
VARIABLE _FFT-TW-STRIDE              \ stride into twiddle table
VARIABLE _FFT-TW-SIGN                \ 1=forward (negate sin), 0=inverse

\ ── FFT-TWIDDLE-ALLOC ────────────────────────────────────────────────
\  Allocate twiddle table + SIMD workspace for N-point FFT.
\  Size = 6·N bytes: 2N twiddle + 4N SIMD workspace.

: FFT-TWIDDLE-ALLOC  ( n -- addr )
    6 * HBW-ALLOT ;

\ ── FFT-TWIDDLE-FILL ─────────────────────────────────────────────────
\  Populate twiddle table with cos/sin factors.
\  cos[k] = cos(2π·k/N), sin[k] = sin(2π·k/N)  for k = 0 .. N/2−1.

VARIABLE _FFT-TWF-N
VARIABLE _FFT-TWF-ADDR

: FFT-TWIDDLE-FILL  ( n addr -- )
    _FFT-TWF-ADDR !  _FFT-TWF-N !
    _FFT-TWF-N @ 2/ 0 DO
        \ angle = 2π · i / N
        I INT>FP16 TRIG-2PI FP16-MUL
        _FFT-TWF-N @ INT>FP16 FP16-DIV   ( angle )
        TRIG-SINCOS                        ( sin cos )
        \ cos → addr + i·2
        _FFT-TWF-ADDR @ I 2 * + W!        ( sin )
        \ sin → addr + N + i·2
        _FFT-TWF-ADDR @ _FFT-TWF-N @ + I 2 * + W!  ( )
    LOOP ;

\ ── _FFT-BFT-SCALAR ───────────────────────────────────────────────────
\  Scalar butterfly pass using precomputed twiddle table.
\  Used for small stages (half < 32) where SIMD isn't beneficial.

: _FFT-BFT-SCALAR  ( -- )
    \ Compute stride and sign for this stage
    _FFT-N @ _FFT-STAGE @ / _FFT-TW-STRIDE !
    _FFT-DIR @ FP16-SIGN _FFT-TW-SIGN !

    \ Iterate over groups
    0 _FFT-GRP !
    BEGIN _FFT-GRP @ _FFT-N @ < WHILE
        0 _FFT-K !
        BEGIN _FFT-K @ _FFT-HALF @ < WHILE
            _FFT-GRP @ _FFT-K @ + _FFT-U !
            _FFT-U @ _FFT-HALF @ + _FFT-L !

            \ Look up twiddle: byte offset = k × stride × 2
            _FFT-K @ _FFT-TW-STRIDE @ * 2 *   ( boff )
            DUP _FFT-TW @ + W@ _FFT-WR !      ( boff )
            _FFT-TW @ _FFT-N @ + + W@          ( raw-sin )
            _FFT-TW-SIGN @ IF FP16-NEG THEN
            _FFT-WI !

            \ Load lower element
            _FFT-L @ 2 * _FFT-RE @ + W@
            _FFT-L @ 2 * _FFT-IM @ + W@

            \ Complex multiply: t = w × lower
            \ tr = wr·re_lo − wi·im_lo
            OVER _FFT-WR @ FP16-MUL
            OVER _FFT-WI @ FP16-MUL
            FP16-SUB _FFT-TR !
            \ ti = wr·im_lo + wi·re_lo
            _FFT-WR @ FP16-MUL
            SWAP _FFT-WI @ FP16-MUL
            FP16-ADD _FFT-TI !

            \ Save upper element
            _FFT-U @ 2 * _FFT-RE @ + W@ _FFT-UR !
            _FFT-U @ 2 * _FFT-IM @ + W@ _FFT-UI !

            \ upper = old_upper + t
            _FFT-UR @ _FFT-TR @ FP16-ADD
            _FFT-U @ 2 * _FFT-RE @ + W!
            _FFT-UI @ _FFT-TI @ FP16-ADD
            _FFT-U @ 2 * _FFT-IM @ + W!

            \ lower = old_upper − t
            _FFT-UR @ _FFT-TR @ FP16-SUB
            _FFT-L @ 2 * _FFT-RE @ + W!
            _FFT-UI @ _FFT-TI @ FP16-SUB
            _FFT-L @ 2 * _FFT-IM @ + W!

            _FFT-K @ 1+ _FFT-K !
        REPEAT
        _FFT-GRP @ _FFT-STAGE @ + _FFT-GRP !
    REPEAT ;

\ ── SIMD FFT Butterfly (Tier 3.2) ────────────────────────────────────
\  When half ≥ 32, the butterfly inner loop is vectorized using
\  SIMD-MUL-N, SIMD-ADD-N, SIMD-SUB-N operating on 32-element tiles.
\
\  SIMD workspace within twiddle allocation (set up once per FFT call):
\    _FFT-SIMD-WR  : expanded twiddle cos for current stage (N bytes)
\    _FFT-SIMD-WI  : expanded twiddle sin (possibly negated)  (N bytes)
\    _FFT-SIMD-T1  : temp buffer 1                            (N bytes)
\    _FFT-SIMD-T2  : temp buffer 2                            (N bytes)
\
\  Complex butterfly for 'half' consecutive elements:
\    1. Save upper: t1=re_up, t2=im_up
\    2. tr = wr*re_lo - wi*im_lo      (4 SIMD-*-N ops)
\    3. ti = wr*im_lo + wi*re_lo      (3 SIMD-*-N ops)
\    4. re_up = t1 + tr, re_lo = t1 - tr  (2 ops)
\    5. im_up = t2 + ti, im_lo = t2 - ti  (2 ops)
\  Total: 12 SIMD-*-N per group + 1 twiddle expansion per stage.

VARIABLE _FFT-SIMD-WR                \ expanded twiddle cos workspace
VARIABLE _FFT-SIMD-WI                \ expanded twiddle sin workspace
VARIABLE _FFT-SIMD-T1                \ temp buffer 1
VARIABLE _FFT-SIMD-T2                \ temp buffer 2
VARIABLE _FFT-EXP-K                  \ loop counter for twiddle expand

\ Pointers into re/im arrays for current group
VARIABLE _FFT-SIMD-REU               \ re[upper] for group
VARIABLE _FFT-SIMD-REL               \ re[lower] for group
VARIABLE _FFT-SIMD-IMU               \ im[upper] for group
VARIABLE _FFT-SIMD-IML               \ im[lower] for group

\ _FFT-TW-EXPAND — expand twiddle table to contiguous workspace
\  Gathers cos[k*stride] → wr_buf, sin[k*stride] → wi_buf
\  for k = 0..half-1.  Negates sin for forward direction.

: _FFT-TW-EXPAND  ( -- )
    _FFT-N @ _FFT-STAGE @ / _FFT-TW-STRIDE !
    0 _FFT-EXP-K !
    BEGIN _FFT-EXP-K @ _FFT-HALF @ < WHILE
        _FFT-EXP-K @ _FFT-TW-STRIDE @ * 2 *   ( boff )
        DUP _FFT-TW @ + W@
        _FFT-SIMD-WR @ _FFT-EXP-K @ 2 * + W!  ( boff )
        _FFT-TW @ _FFT-N @ + + W@
        _FFT-DIR @ FP16-SIGN IF FP16-NEG THEN
        _FFT-SIMD-WI @ _FFT-EXP-K @ 2 * + W!
        _FFT-EXP-K @ 1+ _FFT-EXP-K !
    REPEAT ;

\ _FFT-BFT-SIMD — SIMD butterfly pass for stages with half ≥ 32

: _FFT-BFT-SIMD  ( -- )
    _FFT-TW-EXPAND                     \ expand twiddle for this stage

    0 _FFT-GRP !
    BEGIN _FFT-GRP @ _FFT-N @ < WHILE
        \ Set up pointers for this group
        _FFT-RE @ _FFT-GRP @ 2 * +               _FFT-SIMD-REU !
        _FFT-RE @ _FFT-GRP @ _FFT-HALF @ + 2 * + _FFT-SIMD-REL !
        _FFT-IM @ _FFT-GRP @ 2 * +               _FFT-SIMD-IMU !
        _FFT-IM @ _FFT-GRP @ _FFT-HALF @ + 2 * + _FFT-SIMD-IML !

        \ 1. Save upper elements: t1 = re_up, t2 = im_up
        _FFT-SIMD-REU @ _FFT-SIMD-T1 @ _FFT-HALF @ SIMD-COPY-N
        _FFT-SIMD-IMU @ _FFT-SIMD-T2 @ _FFT-HALF @ SIMD-COPY-N

        \ 2. tr = wr*re_lo - wi*im_lo → stored in re_up
        \    re_up = wr * re_lo
        _FFT-SIMD-WR @ _FFT-SIMD-REL @ _FFT-SIMD-REU @ _FFT-HALF @ SIMD-MUL-N
        \    im_up = wi * im_lo  (temp)
        _FFT-SIMD-WI @ _FFT-SIMD-IML @ _FFT-SIMD-IMU @ _FFT-HALF @ SIMD-MUL-N
        \    re_up = re_up - im_up = tr
        _FFT-SIMD-REU @ _FFT-SIMD-IMU @ _FFT-SIMD-REU @ _FFT-HALF @ SIMD-SUB-N

        \ 3. ti = wr*im_lo + wi*re_lo → stored in im_up
        \    im_up = wr * im_lo
        _FFT-SIMD-WR @ _FFT-SIMD-IML @ _FFT-SIMD-IMU @ _FFT-HALF @ SIMD-MUL-N
        \    im_lo = wi * re_lo  (overwrite im_lo — original already consumed)
        _FFT-SIMD-WI @ _FFT-SIMD-REL @ _FFT-SIMD-IML @ _FFT-HALF @ SIMD-MUL-N
        \    im_up = im_up + im_lo = ti
        _FFT-SIMD-IMU @ _FFT-SIMD-IML @ _FFT-SIMD-IMU @ _FFT-HALF @ SIMD-ADD-N

        \ 4. re_lo = t1 - tr, re_up = t1 + tr
        \    (must compute SUB before ADD since ADD overwrites re_up)
        _FFT-SIMD-T1 @ _FFT-SIMD-REU @ _FFT-SIMD-REL @ _FFT-HALF @ SIMD-SUB-N
        _FFT-SIMD-T1 @ _FFT-SIMD-REU @ _FFT-SIMD-REU @ _FFT-HALF @ SIMD-ADD-N

        \ 5. im_lo = t2 - ti, im_up = t2 + ti
        _FFT-SIMD-T2 @ _FFT-SIMD-IMU @ _FFT-SIMD-IML @ _FFT-HALF @ SIMD-SUB-N
        _FFT-SIMD-T2 @ _FFT-SIMD-IMU @ _FFT-SIMD-IMU @ _FFT-HALF @ SIMD-ADD-N

        _FFT-GRP @ _FFT-STAGE @ + _FFT-GRP !
    REPEAT ;

\ ── _FFT-BUTTERFLY-TW ────────────────────────────────────────────────
\  Dispatcher: SIMD path for half ≥ 32, scalar for smaller stages.

: _FFT-BUTTERFLY-TW  ( -- )
    _FFT-HALF @ 32 >= IF
        _FFT-BFT-SIMD
    ELSE
        _FFT-BFT-SCALAR
    THEN ;

\ ── FFT-FORWARD-TW ───────────────────────────────────────────────────
\  In-place forward FFT using precomputed twiddle table.
\  The twiddle table must have been allocated and filled for the same N.

: FFT-FORWARD-TW  ( re im n tw -- )
    _FFT-TW !
    _FFT-N !  _FFT-IM !  _FFT-RE !
    _FFT-NEG1 _FFT-DIR !

    \ Set up SIMD workspace pointers (within twiddle allocation)
    _FFT-TW @ _FFT-N @ 2 * + _FFT-SIMD-WR !
    _FFT-TW @ _FFT-N @ 3 * + _FFT-SIMD-WI !
    _FFT-TW @ _FFT-N @ 4 * + _FFT-SIMD-T1 !
    _FFT-TW @ _FFT-N @ 5 * + _FFT-SIMD-T2 !

    _FFT-PERMUTE

    2 _FFT-STAGE !
    BEGIN _FFT-STAGE @ _FFT-N @ <= WHILE
        _FFT-STAGE @ 2/ _FFT-HALF !
        _FFT-BUTTERFLY-TW
        _FFT-STAGE @ 2* _FFT-STAGE !
    REPEAT ;

\ ── FFT-INVERSE-TW ───────────────────────────────────────────────────
\  In-place inverse FFT using precomputed twiddle table.
\  Includes 1/N scaling.

: FFT-INVERSE-TW  ( re im n tw -- )
    _FFT-TW !
    _FFT-N !  _FFT-IM !  _FFT-RE !
    _FFT-ONE _FFT-DIR !

    \ Set up SIMD workspace pointers (within twiddle allocation)
    _FFT-TW @ _FFT-N @ 2 * + _FFT-SIMD-WR !
    _FFT-TW @ _FFT-N @ 3 * + _FFT-SIMD-WI !
    _FFT-TW @ _FFT-N @ 4 * + _FFT-SIMD-T1 !
    _FFT-TW @ _FFT-N @ 5 * + _FFT-SIMD-T2 !

    _FFT-PERMUTE

    2 _FFT-STAGE !
    BEGIN _FFT-STAGE @ _FFT-N @ <= WHILE
        _FFT-STAGE @ 2/ _FFT-HALF !
        _FFT-BUTTERFLY-TW
        _FFT-STAGE @ 2* _FFT-STAGE !
    REPEAT

    \ Scale by 1/N
    _FFT-N @ INT>FP16 _FFT-INV-N16 !
    0 _FFT-INV-I !
    BEGIN _FFT-INV-I @ _FFT-N @ < WHILE
        _FFT-RE @ _FFT-INV-I @ 2 * +
        DUP W@ _FFT-INV-N16 @ FP16-DIV SWAP W!
        _FFT-IM @ _FFT-INV-I @ 2 * +
        DUP W@ _FFT-INV-N16 @ FP16-DIV SWAP W!
        _FFT-INV-I @ 1+ _FFT-INV-I !
    REPEAT ;

\ ── FFT-CONVOLVE-TW ──────────────────────────────────────────────────
\  Convolution via FFT using precomputed twiddle table.
\  Same algorithm as FFT-CONVOLVE but uses *-TW transforms.

VARIABLE _FFTC-TW                    \ twiddle for convolve-TW

: FFT-CONVOLVE-TW  ( a b dst n tw -- )
    _FFTC-TW !
    _FFT-CONV-N !
    _FFT-CONV-DST !
    _FFT-CONV-B !
    _FFT-CONV-A !

    \ Allocate temporaries: re_a, im_a, re_b, im_b (each n×2 bytes)
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-RA !
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-IA !
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-RB !
    _FFT-CONV-N @ 2 * HBW-ALLOT _FFT-CONV-IB !

    \ Copy a→re_a, zero im_a; copy b→re_b, zero im_b
    0 _FFT-CONV-I !
    BEGIN _FFT-CONV-I @ _FFT-CONV-N @ < WHILE
        _FFT-CONV-A @ _FFT-CONV-I @ 2 * + W@
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W!
        _FFT-ZERO _FFT-CONV-IA @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-B @ _FFT-CONV-I @ 2 * + W@
        _FFT-CONV-RB @ _FFT-CONV-I @ 2 * + W!
        _FFT-ZERO _FFT-CONV-IB @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-I @ 1+ _FFT-CONV-I !
    REPEAT

    \ FFT both using twiddle table
    _FFT-CONV-RA @ _FFT-CONV-IA @ _FFT-CONV-N @ _FFTC-TW @ FFT-FORWARD-TW
    _FFT-CONV-RB @ _FFT-CONV-IB @ _FFT-CONV-N @ _FFTC-TW @ FFT-FORWARD-TW

    \ Pointwise complex multiply: (ra+i·ia)×(rb+i·ib)
    0 _FFT-CONV-I !
    BEGIN _FFT-CONV-I @ _FFT-CONV-N @ < WHILE
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W@ _FFT-UR !
        _FFT-CONV-IA @ _FFT-CONV-I @ 2 * + W@ _FFT-UI !
        _FFT-CONV-RB @ _FFT-CONV-I @ 2 * + W@ _FFT-WR !
        _FFT-CONV-IB @ _FFT-CONV-I @ 2 * + W@ _FFT-WI !
        \ re_out = ra·rb − ia·ib
        _FFT-UR @ _FFT-WR @ FP16-MUL
        _FFT-UI @ _FFT-WI @ FP16-MUL
        FP16-SUB
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W!
        \ im_out = ra·ib + ia·rb
        _FFT-UR @ _FFT-WI @ FP16-MUL
        _FFT-UI @ _FFT-WR @ FP16-MUL
        FP16-ADD
        _FFT-CONV-IA @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-I @ 1+ _FFT-CONV-I !
    REPEAT

    \ IFFT using twiddle table
    _FFT-CONV-RA @ _FFT-CONV-IA @ _FFT-CONV-N @ _FFTC-TW @ FFT-INVERSE-TW

    \ Copy real part to dst
    0 _FFT-CONV-I !
    BEGIN _FFT-CONV-I @ _FFT-CONV-N @ < WHILE
        _FFT-CONV-RA @ _FFT-CONV-I @ 2 * + W@
        _FFT-CONV-DST @ _FFT-CONV-I @ 2 * + W!
        _FFT-CONV-I @ 1+ _FFT-CONV-I !
    REPEAT ;

\ ── FFT-CORRELATE-TW ─────────────────────────────────────────────────
\  Cross-correlation via FFT using precomputed twiddle table.
\  Same as FFT-CONVOLVE-TW but conjugates B's FFT before multiply.

VARIABLE _FFTCR-TW                   \ twiddle for correlate-TW

: FFT-CORRELATE-TW  ( a b dst n tw -- )
    _FFTCR-TW !
    _FFT-CORR-N !
    _FFT-CORR-DST !
    _FFT-CORR-B !
    _FFT-CORR-A !

    \ Allocate temporaries
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-RA !
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-IA !
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-RB !
    _FFT-CORR-N @ 2 * HBW-ALLOT _FFT-CORR-IB !

    \ Copy a→re_a, zero im_a; copy b→re_b, zero im_b
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-A @ _FFT-CORR-I @ 2 * + W@
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W!
        _FFT-ZERO _FFT-CORR-IA @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-B @ _FFT-CORR-I @ 2 * + W@
        _FFT-CORR-RB @ _FFT-CORR-I @ 2 * + W!
        _FFT-ZERO _FFT-CORR-IB @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT

    \ FFT both using twiddle table
    _FFT-CORR-RA @ _FFT-CORR-IA @ _FFT-CORR-N @ _FFTCR-TW @ FFT-FORWARD-TW
    _FFT-CORR-RB @ _FFT-CORR-IB @ _FFT-CORR-N @ _FFTCR-TW @ FFT-FORWARD-TW

    \ Conjugate B: negate im_b
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-IB @ _FFT-CORR-I @ 2 * + DUP W@
        FP16-NEG SWAP W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT

    \ Pointwise complex multiply
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W@ _FFT-UR !
        _FFT-CORR-IA @ _FFT-CORR-I @ 2 * + W@ _FFT-UI !
        _FFT-CORR-RB @ _FFT-CORR-I @ 2 * + W@ _FFT-WR !
        _FFT-CORR-IB @ _FFT-CORR-I @ 2 * + W@ _FFT-WI !
        _FFT-UR @ _FFT-WR @ FP16-MUL
        _FFT-UI @ _FFT-WI @ FP16-MUL
        FP16-SUB
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W!
        _FFT-UR @ _FFT-WI @ FP16-MUL
        _FFT-UI @ _FFT-WR @ FP16-MUL
        FP16-ADD
        _FFT-CORR-IA @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT

    \ IFFT using twiddle table
    _FFT-CORR-RA @ _FFT-CORR-IA @ _FFT-CORR-N @ _FFTCR-TW @ FFT-INVERSE-TW

    \ Copy real part to dst
    0 _FFT-CORR-I !
    BEGIN _FFT-CORR-I @ _FFT-CORR-N @ < WHILE
        _FFT-CORR-RA @ _FFT-CORR-I @ 2 * + W@
        _FFT-CORR-DST @ _FFT-CORR-I @ 2 * + W!
        _FFT-CORR-I @ 1+ _FFT-CORR-I !
    REPEAT ;
