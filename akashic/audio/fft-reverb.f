\ fft-reverb.f — FFT-based partitioned convolution reverb
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Overlap-save partitioned convolution replaces the O(N×L)
\ sample-by-sample Schroeder reverb with an O(N×log N) FFT approach.
\ For a 512-sample block and 2-second impulse response at 44.1 kHz,
\ this yields ~64× speedup over time-domain convolution.
\
\ Algorithm:
\   1. Pre-FFT the impulse response into P partitions of B samples
\      (zero-padded to N=2B), stored in frequency domain.
\   2. Each PROCESS call:
\      a. Prepend B saved input samples to B new samples → N samples
\      b. FFT the N-point input block
\      c. Complex multiply with each IR partition, accumulate
\      d. IFFT the accumulated result
\      e. Take the last B samples as output (overlap-save)
\      f. Wet/dry mix with original input
\
\ Memory per instance (B=block, P=partitions):
\   - IR partitions: P × 2N bytes (re+im for each)
\   - Twiddle table: 6N bytes
\   - Input history: N × 2 bytes
\   - Work buffers: 6N bytes (acc_re, acc_im, blk_re, blk_im, tmp_re, tmp_im)
\   Total ≈ (2P+8)×N bytes
\
\ Non-reentrant (uses VARIABLE scratch).
\
\ Prefix: FFTREV-   (public API)
\         _FFTREV-  (internal helpers)
\
\ Depends on: pcm.f, math/fft.f, math/simd-ext.f
\
\ Load with:   REQUIRE audio/fft-reverb.f
\
\ === Public API ===
\   FFTREV-CREATE   ( ir-addr ir-len block-size -- desc )
\   FFTREV-FREE     ( desc -- )
\   FFTREV-PROCESS  ( buf desc -- )
\   FFTREV-WET!     ( wet desc -- )

REQUIRE pcm.f
REQUIRE math/fft.f
REQUIRE math/simd-ext.f

PROVIDED akashic-audio-fft-reverb

\ =====================================================================
\  Descriptor layout  (11 cells = 88 bytes)
\ =====================================================================
\
\  +0   block-size   B (power-of-2, e.g. 256, 512)
\  +8   fft-size     N = 2×B
\  +16  n-parts      P = number of IR partitions
\  +24  twiddle      pointer to FFT twiddle table (N-point)
\  +32  ir-parts     pointer to array of P×2 pointers (re,im per partition)
\  +40  history      pointer to N-sample input history buffer
\  +48  acc-re       pointer to N-element accumulator (real)
\  +56  acc-im       pointer to N-element accumulator (imag)
\  +64  blk-re       pointer to N-element work buffer (real)
\  +72  blk-im       pointer to N-element work buffer (imag)
\  +80  wet          FP16 wet/dry mix (0x3C00 = 1.0 = full wet)
\  +88  ring-buf     pointer to array of P×2 pointers (FFT'd input history)
\  +96  ring-idx     current ring buffer write position

104 CONSTANT _FFTREV-DESC-SIZE

: _FFTREV.BS   ( d -- addr )  ;
: _FFTREV.N    ( d -- addr )  8  + ;
: _FFTREV.NP   ( d -- addr )  16 + ;
: _FFTREV.TW   ( d -- addr )  24 + ;
: _FFTREV.IRP  ( d -- addr )  32 + ;
: _FFTREV.HIST ( d -- addr )  40 + ;
: _FFTREV.ARE  ( d -- addr )  48 + ;
: _FFTREV.AIM  ( d -- addr )  56 + ;
: _FFTREV.BRE  ( d -- addr )  64 + ;
: _FFTREV.BIM  ( d -- addr )  72 + ;
: _FFTREV.WET  ( d -- addr )  80 + ;
: _FFTREV.RING ( d -- addr )  88 + ;
: _FFTREV.RIDX ( d -- addr )  96 + ;

\ =====================================================================
\  Scratch variables
\ =====================================================================

VARIABLE _FFTREV-DESC     \ current descriptor
VARIABLE _FFTREV-I        \ loop counter
VARIABLE _FFTREV-J        \ inner loop counter
VARIABLE _FFTREV-P        \ partition loop counter
VARIABLE _FFTREV-SRC      \ source pointer
VARIABLE _FFTREV-DST      \ dest pointer
VARIABLE _FFTREV-PTR      \ temp pointer
VARIABLE _FFTREV-N        \ cached FFT size
VARIABLE _FFTREV-BS       \ cached block size
VARIABLE _FFTREV-OBRE     \ saved BRE pointer
VARIABLE _FFTREV-OBIM     \ saved BIM pointer

\ =====================================================================
\  _FFTREV-ALLOC-BUF — Allocate n×2 byte buffer, zero-filled
\ =====================================================================

: _FFTREV-ALLOC-BUF  ( n -- addr )
    2 * DUP ALLOCATE
    0<> ABORT" FFTREV: alloc failed"
    DUP ROT 0 FILL ;

\ =====================================================================
\  FFTREV-CREATE — Build partitioned convolution reverb
\ =====================================================================
\  ( ir-addr ir-len block-size -- desc )
\
\  ir-addr: pointer to impulse response (FP16 samples, 2 bytes each)
\  ir-len:  number of impulse response samples
\  block-size: processing block size (must be power of 2)
\
\  The IR is split into ceil(ir-len / block-size) partitions.
\  Each partition is zero-padded to N=2×block-size and pre-FFT'd.

: FFTREV-CREATE  ( ir-addr ir-len block-size -- desc )
    \ Allocate descriptor
    _FFTREV-DESC-SIZE ALLOCATE
    0<> ABORT" FFTREV-CREATE: alloc failed"
    _FFTREV-DESC !

    \ Store block-size and compute FFT size
    _FFTREV-DESC @ _FFTREV.BS !       ( ir-addr ir-len )
    _FFTREV-DESC @ _FFTREV.BS @ 2 *
    _FFTREV-DESC @ _FFTREV.N !

    \ Compute number of partitions: ceil(ir-len / block-size)
    SWAP _FFTREV-SRC !                 ( ir-len )
    DUP _FFTREV-DESC @ _FFTREV.BS @ + 1-
    _FFTREV-DESC @ _FFTREV.BS @ /
    _FFTREV-DESC @ _FFTREV.NP !       ( ir-len )

    \ Cache values
    _FFTREV-DESC @ _FFTREV.N @ _FFTREV-N !
    _FFTREV-DESC @ _FFTREV.BS @ _FFTREV-BS !

    \ Allocate twiddle table
    _FFTREV-N @ FFT-TWIDDLE-ALLOC
    DUP _FFTREV-N @ SWAP FFT-TWIDDLE-FILL
    _FFTREV-DESC @ _FFTREV.TW !

    \ Allocate IR partition pointer array: n-parts × 2 pointers × 8 bytes
    _FFTREV-DESC @ _FFTREV.NP @ 16 * ALLOCATE
    0<> ABORT" FFTREV-CREATE: alloc IR ptrs failed"
    _FFTREV-DESC @ _FFTREV.IRP !

    \ Allocate and pre-FFT each partition
    _FFTREV-I !                        \ _FFTREV-I = ir-len remaining
    0 _FFTREV-P !
    BEGIN _FFTREV-P @ _FFTREV-DESC @ _FFTREV.NP @ < WHILE
        \ Allocate re and im buffers for this partition
        _FFTREV-N @ _FFTREV-ALLOC-BUF _FFTREV-PTR !     \ re
        _FFTREV-N @ _FFTREV-ALLOC-BUF _FFTREV-DST !     \ im

        \ Copy IR samples into re (first B slots), rest stays zero
        \ Remaining IR samples for this partition
        _FFTREV-I @ _FFTREV-BS @ MIN                     ( chunk )
        DUP 0> IF
            \ Copy chunk samples: src → re
            0 _FFTREV-J !
            BEGIN _FFTREV-J @ OVER < WHILE
                _FFTREV-SRC @ _FFTREV-J @ 2 * + W@
                _FFTREV-PTR @ _FFTREV-J @ 2 * + W!
                _FFTREV-J @ 1+ _FFTREV-J !
            REPEAT
            \ Advance source pointer and decrement remaining
            DUP 2 * _FFTREV-SRC @ + _FFTREV-SRC !
            _FFTREV-I @ SWAP - _FFTREV-I !
        ELSE
            DROP
        THEN

        \ FFT this partition in-place
        _FFTREV-PTR @  _FFTREV-DST @
        _FFTREV-N @  _FFTREV-DESC @ _FFTREV.TW @
        FFT-FORWARD-TW

        \ Store pointers: irp[p*2] = re, irp[p*2+1] = im
        _FFTREV-PTR @
        _FFTREV-DESC @ _FFTREV.IRP @  _FFTREV-P @ 16 * +  !
        _FFTREV-DST @
        _FFTREV-DESC @ _FFTREV.IRP @  _FFTREV-P @ 16 * + 8 +  !

        _FFTREV-P @ 1+ _FFTREV-P !
    REPEAT

    \ Allocate input history buffer (N samples, zero-filled)
    _FFTREV-N @ _FFTREV-ALLOC-BUF
    _FFTREV-DESC @ _FFTREV.HIST !

    \ Allocate accumulator and work buffers
    _FFTREV-N @ _FFTREV-ALLOC-BUF  _FFTREV-DESC @ _FFTREV.ARE !
    _FFTREV-N @ _FFTREV-ALLOC-BUF  _FFTREV-DESC @ _FFTREV.AIM !
    _FFTREV-N @ _FFTREV-ALLOC-BUF  _FFTREV-DESC @ _FFTREV.BRE !
    _FFTREV-N @ _FFTREV-ALLOC-BUF  _FFTREV-DESC @ _FFTREV.BIM !

    \ Default wet = 1.0 (full reverb)
    0x3C00 _FFTREV-DESC @ _FFTREV.WET !

    \ Allocate ring buffer for FFT'd input history (P entries × 2 pointers)
    _FFTREV-DESC @ _FFTREV.NP @ 16 * ALLOCATE
    0<> ABORT" FFTREV-CREATE: alloc ring failed"
    _FFTREV-DESC @ _FFTREV.RING !

    \ Allocate P pairs of (re, im) buffers for ring
    0 _FFTREV-P !
    BEGIN _FFTREV-P @ _FFTREV-DESC @ _FFTREV.NP @ < WHILE
        _FFTREV-N @ _FFTREV-ALLOC-BUF
        _FFTREV-DESC @ _FFTREV.RING @  _FFTREV-P @ 16 * +  !
        _FFTREV-N @ _FFTREV-ALLOC-BUF
        _FFTREV-DESC @ _FFTREV.RING @  _FFTREV-P @ 16 * + 8 +  !
        _FFTREV-P @ 1+ _FFTREV-P !
    REPEAT

    \ Ring write index starts at 0
    0 _FFTREV-DESC @ _FFTREV.RIDX !

    _FFTREV-DESC @ ;

\ =====================================================================
\  FFTREV-FREE — Release all partitioned reverb memory
\ =====================================================================

: FFTREV-FREE  ( desc -- )
    _FFTREV-DESC !

    \ Free IR partition buffers
    0 _FFTREV-P !
    BEGIN _FFTREV-P @ _FFTREV-DESC @ _FFTREV.NP @ < WHILE
        _FFTREV-DESC @ _FFTREV.IRP @  _FFTREV-P @ 16 * +  @ FREE
        _FFTREV-DESC @ _FFTREV.IRP @  _FFTREV-P @ 16 * + 8 +  @ FREE
        _FFTREV-P @ 1+ _FFTREV-P !
    REPEAT

    \ Free pointer array
    _FFTREV-DESC @ _FFTREV.IRP @ FREE

    \ Free twiddle table — it's HBW-ALLOT'd, not ALLOCATE'd
    \ HBW-ALLOT memory is stack-managed; we don't free it individually.
    \ (Twiddle table will be reclaimed on FFTREV-FREE caller's exit.)

    \ Free work buffers
    _FFTREV-DESC @ _FFTREV.HIST @ FREE
    _FFTREV-DESC @ _FFTREV.ARE  @ FREE
    _FFTREV-DESC @ _FFTREV.AIM  @ FREE
    _FFTREV-DESC @ _FFTREV.BRE  @ FREE
    _FFTREV-DESC @ _FFTREV.BIM  @ FREE

    \ Free ring buffer entries
    0 _FFTREV-P !
    BEGIN _FFTREV-P @ _FFTREV-DESC @ _FFTREV.NP @ < WHILE
        _FFTREV-DESC @ _FFTREV.RING @  _FFTREV-P @ 16 * +  @ FREE
        _FFTREV-DESC @ _FFTREV.RING @  _FFTREV-P @ 16 * + 8 +  @ FREE
        _FFTREV-P @ 1+ _FFTREV-P !
    REPEAT
    _FFTREV-DESC @ _FFTREV.RING @ FREE

    \ Free descriptor
    _FFTREV-DESC @ FREE ;

\ =====================================================================
\  FFTREV-WET! — Set wet/dry mix
\ =====================================================================

: FFTREV-WET!  ( wet desc -- )  _FFTREV.WET ! ;

\ =====================================================================
\  _FFTREV-CMUL-ACC — Complex multiply-accumulate
\ =====================================================================
\  Multiply (blk_re + i·blk_im) × (ir_re + i·ir_im)
\  and add to (acc_re + i·acc_im).
\  All arrays are N elements of FP16.
\
\  Uses SIMD-MUL-N and SIMD-ADD-N for bulk operations when available.
\  ( ir-re ir-im desc -- )

VARIABLE _FFTREV-IRRE
VARIABLE _FFTREV-IRIM
VARIABLE _FFTREV-TR       \ temp real product
VARIABLE _FFTREV-TI       \ temp imag product
VARIABLE _FFTREV-UR       \ scratch for element multiply
VARIABLE _FFTREV-UI
VARIABLE _FFTREV-WR
VARIABLE _FFTREV-WI

: _FFTREV-CMUL-ACC  ( ir-re ir-im desc -- )
    _FFTREV-DESC !
    _FFTREV-IRIM !
    _FFTREV-IRRE !

    _FFTREV-DESC @ _FFTREV.N @ _FFTREV-N !

    \ Element-wise: acc += blk × ir   (complex multiply)
    \ re_prod = blk_re × ir_re − blk_im × ir_im
    \ im_prod = blk_re × ir_im + blk_im × ir_re
    0 _FFTREV-I !
    BEGIN _FFTREV-I @ _FFTREV-N @ < WHILE
        _FFTREV-I @ 2 * _FFTREV-PTR !

        \ Load block values
        _FFTREV-DESC @ _FFTREV.BRE @ _FFTREV-PTR @ + W@  _FFTREV-UR !
        _FFTREV-DESC @ _FFTREV.BIM @ _FFTREV-PTR @ + W@  _FFTREV-UI !

        \ Load IR partition values
        _FFTREV-IRRE @ _FFTREV-PTR @ + W@  _FFTREV-WR !
        _FFTREV-IRIM @ _FFTREV-PTR @ + W@  _FFTREV-WI !

        \ re_prod = ur*wr - ui*wi
        _FFTREV-UR @ _FFTREV-WR @ FP16-MUL
        _FFTREV-UI @ _FFTREV-WI @ FP16-MUL
        FP16-SUB

        \ Accumulate into acc_re
        _FFTREV-DESC @ _FFTREV.ARE @ _FFTREV-PTR @ + DUP W@
        ROT FP16-ADD SWAP W!

        \ im_prod = ur*wi + ui*wr
        _FFTREV-UR @ _FFTREV-WI @ FP16-MUL
        _FFTREV-UI @ _FFTREV-WR @ FP16-MUL
        FP16-ADD

        \ Accumulate into acc_im
        _FFTREV-DESC @ _FFTREV.AIM @ _FFTREV-PTR @ + DUP W@
        ROT FP16-ADD SWAP W!

        _FFTREV-I @ 1+ _FFTREV-I !
    REPEAT ;

\ =====================================================================
\  FFTREV-PROCESS — Process one PCM buffer through FFT reverb
\ =====================================================================
\  ( buf desc -- )
\
\  The PCM buffer must have exactly block-size frames.
\  Processes mono channel 0.  Modifies buf in-place.

VARIABLE _FFTREV-BUF
VARIABLE _FFTREV-SAMP
VARIABLE _FFTREV-DRY

: FFTREV-PROCESS  ( buf desc -- )
    _FFTREV-DESC !
    _FFTREV-BUF !

    _FFTREV-DESC @ _FFTREV.N  @ _FFTREV-N !
    _FFTREV-DESC @ _FFTREV.BS @ _FFTREV-BS !

    \ ── Step 1: Shift history left by B, copy new input into right half ──
    \ history[0..B-1] ← history[B..N-1]   (slide old input left)
    _FFTREV-DESC @ _FFTREV.HIST @ _FFTREV-BS @ 2 * +    \ src = hist+B
    _FFTREV-DESC @ _FFTREV.HIST @                         \ dst = hist
    _FFTREV-BS @ SIMD-COPY-N

    \ Copy new PCM samples into history[B..N-1]
    0 _FFTREV-I !
    BEGIN _FFTREV-I @ _FFTREV-BS @ < WHILE
        _FFTREV-I @ _FFTREV-BUF @ PCM-FRAME@
        _FFTREV-DESC @ _FFTREV.HIST @
        _FFTREV-BS @ _FFTREV-I @ + 2 * + W!
        _FFTREV-I @ 1+ _FFTREV-I !
    REPEAT

    \ ── Step 2: Copy history into blk_re, zero blk_im ──
    _FFTREV-DESC @ _FFTREV.HIST @
    _FFTREV-DESC @ _FFTREV.BRE @
    _FFTREV-N @ SIMD-COPY-N

    _FFTREV-DESC @ _FFTREV.BIM @
    _FFTREV-N @ SIMD-ZERO-N

    \ ── Step 3: FFT the input block ──
    _FFTREV-DESC @ _FFTREV.BRE @
    _FFTREV-DESC @ _FFTREV.BIM @
    _FFTREV-N @
    _FFTREV-DESC @ _FFTREV.TW @
    FFT-FORWARD-TW

    \ ── Step 3.5: Save FFT'd block into ring buffer at ring_idx ──
    _FFTREV-DESC @ _FFTREV.BRE @
    _FFTREV-DESC @ _FFTREV.RIDX @ 16 *
    _FFTREV-DESC @ _FFTREV.RING @ + @
    _FFTREV-N @ SIMD-COPY-N

    _FFTREV-DESC @ _FFTREV.BIM @
    _FFTREV-DESC @ _FFTREV.RIDX @ 16 *
    _FFTREV-DESC @ _FFTREV.RING @ + 8 + @
    _FFTREV-N @ SIMD-COPY-N

    \ ── Step 4: Zero accumulator ──
    _FFTREV-DESC @ _FFTREV.ARE @  _FFTREV-N @ SIMD-ZERO-N
    _FFTREV-DESC @ _FFTREV.AIM @  _FFTREV-N @ SIMD-ZERO-N

    \ ── Step 5: Complex multiply-accumulate with each IR partition ──
    \  Partition p uses the FFT'd input from p blocks ago:
    \  ring slot = (ring_idx − p + P) mod P
    _FFTREV-DESC @ _FFTREV.BRE @ _FFTREV-OBRE !
    _FFTREV-DESC @ _FFTREV.BIM @ _FFTREV-OBIM !
    0 _FFTREV-P !
    BEGIN _FFTREV-P @ _FFTREV-DESC @ _FFTREV.NP @ < WHILE
        \ Compute ring slot for partition p
        _FFTREV-DESC @ _FFTREV.RIDX @
        _FFTREV-P @ -
        _FFTREV-DESC @ _FFTREV.NP @ +
        _FFTREV-DESC @ _FFTREV.NP @ MOD         ( slot )
        \ Point BRE/BIM at ring[slot] re/im
        16 *
        _FFTREV-DESC @ _FFTREV.RING @ +         ( &ring[slot] )
        DUP @
        _FFTREV-DESC @ _FFTREV.BRE !            \ BRE = ring[slot].re
        8 + @
        _FFTREV-DESC @ _FFTREV.BIM !            \ BIM = ring[slot].im
        \ Complex multiply-accumulate IR[p] × ring[slot]
        _FFTREV-DESC @ _FFTREV.IRP @  _FFTREV-P @ 16 * +  @     \ ir-re
        _FFTREV-DESC @ _FFTREV.IRP @  _FFTREV-P @ 16 * + 8 +  @ \ ir-im
        _FFTREV-DESC @ _FFTREV-CMUL-ACC

        _FFTREV-P @ 1+ _FFTREV-P !
    REPEAT
    \ Restore BRE/BIM pointers
    _FFTREV-OBRE @ _FFTREV-DESC @ _FFTREV.BRE !
    _FFTREV-OBIM @ _FFTREV-DESC @ _FFTREV.BIM !

    \ ── Step 6: IFFT the accumulated result ──
    _FFTREV-DESC @ _FFTREV.ARE @
    _FFTREV-DESC @ _FFTREV.AIM @
    _FFTREV-N @
    _FFTREV-DESC @ _FFTREV.TW @
    FFT-INVERSE-TW

    \ ── Step 7: Take last B samples from acc_re, wet/dry mix, write back ──
    0 _FFTREV-I !
    BEGIN _FFTREV-I @ _FFTREV-BS @ < WHILE
        \ Reverb output = acc_re[B + i]  (overlap-save: discard first B)
        _FFTREV-DESC @ _FFTREV.ARE @
        _FFTREV-BS @ _FFTREV-I @ + 2 * + W@
        _FFTREV-SAMP !

        \ Dry signal
        _FFTREV-I @ _FFTREV-BUF @ PCM-FRAME@
        _FFTREV-DRY !

        \ Mix: LERP(dry, wet_sample, wet_amount)
        _FFTREV-DRY @
        _FFTREV-SAMP @
        _FFTREV-DESC @ _FFTREV.WET @
        FP16-LERP

        _FFTREV-I @ _FFTREV-BUF @ PCM-FRAME!
        _FFTREV-I @ 1+ _FFTREV-I !
    REPEAT

    \ ── Step 8: Advance ring index ──
    _FFTREV-DESC @ _FFTREV.RIDX @ 1+
    _FFTREV-DESC @ _FFTREV.NP @ MOD
    _FFTREV-DESC @ _FFTREV.RIDX ! ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _fftrv-guard

' FFTREV-CREATE   CONSTANT _fftrev-create-xt
' FFTREV-FREE     CONSTANT _fftrev-free-xt
' FFTREV-WET!     CONSTANT _fftrev-wet-s-xt
' FFTREV-PROCESS  CONSTANT _fftrev-process-xt

: FFTREV-CREATE   _fftrev-create-xt _fftrv-guard WITH-GUARD ;
: FFTREV-FREE     _fftrev-free-xt _fftrv-guard WITH-GUARD ;
: FFTREV-WET!     _fftrev-wet-s-xt _fftrv-guard WITH-GUARD ;
: FFTREV-PROCESS  _fftrev-process-xt _fftrv-guard WITH-GUARD ;
[THEN] [THEN]
