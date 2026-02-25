\ fft.f — Radix-2 Cooley-Tukey FFT for FP16
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ In-place radix-2 DIT (decimation-in-time) FFT on paired
\ real / imaginary arrays of N FP16 values (N must be power of 2).
\
\ Twiddle factors computed on-the-fly via TRIG-SINCOS to avoid
\ accumulation error in FP16's 10-bit mantissa.
\
\ Prefix: FFT-   (public API)
\         _FFT-  (internal helpers)
\
\ Depends on: fp16.f, fp16-ext.f, trig.f
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

REQUIRE fp16-ext.f
REQUIRE trig.f

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
