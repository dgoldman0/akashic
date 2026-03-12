\ pcm-simd.f — SIMD bulk operations on PCM buffers
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Thin wrappers around simd-ext.f that operate directly on PCM
\ buffer descriptors.  For mono 16-bit buffers (the standard audio
\ pipeline format), PCM-DATA already points to a packed array of
\ 2-byte FP16 values — exactly the layout that SIMD-*-N expects.
\ No conversion is needed.
\
\ All SIMD words handle both mono and stereo: the element count
\ is frames × channels.  For stereo buffers this means the SIMD
\ operations are applied uniformly to all interleaved samples.
\
\ Requirements:
\   - PCM buffers must be 16-bit (storing FP16 bit patterns via W!).
\   - Two-buffer ops expect compatible format (same bits & channels).
\
\ Prefix: PCM-SIMD-  (public API)
\         _PSIMD-    (internals)
\
\ Load with:   REQUIRE audio/pcm-simd.f
\
\ === Public API ===
\   PCM-SIMD-ADD     ( src dst -- )         dst[i] += src[i]
\   PCM-SIMD-SCALE   ( scalar buf -- )      buf[i] *= scalar  (in-place)
\   PCM-SIMD-MIX     ( gain src dst -- )    dst[i] += gain × src[i]
\   PCM-SIMD-MUL     ( src dst -- )         dst[i] *= src[i]
\   PCM-SIMD-FILL    ( val buf -- )         fill every sample with val
\   PCM-SIMD-CLEAR   ( buf -- )             zero all samples

REQUIRE math/simd-ext.f
REQUIRE audio/pcm.f

PROVIDED akashic-audio-pcm-simd

\ =====================================================================
\  Internal scratch
\ =====================================================================

VARIABLE _PSIMD-BUF0
VARIABLE _PSIMD-BUF1
VARIABLE _PSIMD-N

\ =====================================================================
\  Helper: total sample count (frames × channels)
\ =====================================================================

: _PSIMD-SAMPLES  ( buf -- n )
    DUP PCM-LEN SWAP PCM-CHANS * ;

\ =====================================================================
\  PCM-SIMD-ADD — elementwise add: dst[i] += src[i]
\ =====================================================================
\  SIMD-ADD-N ( src0 src1 dst n -- )     dst[i] = src0[i] + src1[i]
\  We pass: src.data  dst.data  dst.data  n  → in-place dst += src.

: PCM-SIMD-ADD  ( src dst -- )
    _PSIMD-BUF1 !  _PSIMD-BUF0 !
    _PSIMD-BUF0 @ _PSIMD-SAMPLES
    _PSIMD-BUF1 @ _PSIMD-SAMPLES MIN _PSIMD-N !
    _PSIMD-N @ 0= IF EXIT THEN
    _PSIMD-BUF0 @ PCM-DATA
    _PSIMD-BUF1 @ PCM-DATA
    DUP
    _PSIMD-N @
    SIMD-ADD-N ;

\ =====================================================================
\  PCM-SIMD-SCALE — broadcast scalar multiply: buf[i] *= scalar
\ =====================================================================
\  SIMD-SCALE-N ( src scalar dst n -- )
\  In-place: src = dst = buf.data.

: PCM-SIMD-SCALE  ( scalar buf -- )
    _PSIMD-BUF0 !
    _PSIMD-BUF0 @ _PSIMD-SAMPLES DUP 0= IF 2DROP EXIT THEN
    _PSIMD-N !
    _PSIMD-BUF0 @ PCM-DATA
    SWAP
    _PSIMD-BUF0 @ PCM-DATA
    _PSIMD-N @
    SIMD-SCALE-N ;

\ =====================================================================
\  PCM-SIMD-MIX — scaled accumulation: dst[i] += gain × src[i]
\ =====================================================================
\  SIMD-SAXPY-N ( a x y dst n -- )   dst[i] = a*x[i] + y[i]
\  We pass:  gain  src.data  dst.data  dst.data  n   (y=dst for in-place).

: PCM-SIMD-MIX  ( gain src dst -- )
    _PSIMD-BUF1 !  _PSIMD-BUF0 !
    _PSIMD-BUF0 @ _PSIMD-SAMPLES
    _PSIMD-BUF1 @ _PSIMD-SAMPLES MIN _PSIMD-N !
    _PSIMD-N @ 0= IF DROP EXIT THEN
    \ Stack: gain
    _PSIMD-BUF0 @ PCM-DATA            \ x
    _PSIMD-BUF1 @ PCM-DATA            \ y
    DUP                                \ dst (= y, in-place)
    _PSIMD-N @
    SIMD-SAXPY-N ;

\ =====================================================================
\  PCM-SIMD-MUL — elementwise multiply: dst[i] *= src[i]
\ =====================================================================
\  SIMD-MUL-N ( src0 src1 dst n -- )

: PCM-SIMD-MUL  ( src dst -- )
    _PSIMD-BUF1 !  _PSIMD-BUF0 !
    _PSIMD-BUF0 @ _PSIMD-SAMPLES
    _PSIMD-BUF1 @ _PSIMD-SAMPLES MIN _PSIMD-N !
    _PSIMD-N @ 0= IF EXIT THEN
    _PSIMD-BUF0 @ PCM-DATA
    _PSIMD-BUF1 @ PCM-DATA
    DUP
    _PSIMD-N @
    SIMD-MUL-N ;

\ =====================================================================
\  PCM-SIMD-FILL — broadcast fill all samples with a constant
\ =====================================================================

: PCM-SIMD-FILL  ( val buf -- )
    DUP _PSIMD-SAMPLES DUP 0= IF 2DROP DROP EXIT THEN
    >R PCM-DATA SWAP R>
    SIMD-FILL-N ;

\ =====================================================================
\  PCM-SIMD-CLEAR — zero all sample data
\ =====================================================================

: PCM-SIMD-CLEAR  ( buf -- )
    DUP PCM-DATA SWAP _PSIMD-SAMPLES 2 * 0 FILL ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _pcmsimd-guard

' PCM-SIMD-ADD    CONSTANT _pcm-simd-add-xt
' PCM-SIMD-SCALE  CONSTANT _pcm-simd-scale-xt
' PCM-SIMD-MIX    CONSTANT _pcm-simd-mix-xt
' PCM-SIMD-MUL    CONSTANT _pcm-simd-mul-xt
' PCM-SIMD-FILL   CONSTANT _pcm-simd-fill-xt
' PCM-SIMD-CLEAR  CONSTANT _pcm-simd-clear-xt

: PCM-SIMD-ADD    _pcm-simd-add-xt _pcmsimd-guard WITH-GUARD ;
: PCM-SIMD-SCALE  _pcm-simd-scale-xt _pcmsimd-guard WITH-GUARD ;
: PCM-SIMD-MIX    _pcm-simd-mix-xt _pcmsimd-guard WITH-GUARD ;
: PCM-SIMD-MUL    _pcm-simd-mul-xt _pcmsimd-guard WITH-GUARD ;
: PCM-SIMD-FILL   _pcm-simd-fill-xt _pcmsimd-guard WITH-GUARD ;
: PCM-SIMD-CLEAR  _pcm-simd-clear-xt _pcmsimd-guard WITH-GUARD ;
[THEN] [THEN]
