\ pcm.f — PCM audio buffer abstraction
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ A PCM buffer is a descriptor + contiguous sample data, analogous to
\ surface.f for pixels.  Supports arbitrary sample rates (8000–96000),
\ bit depths (8 unsigned, 16 signed, 32 signed), and channel counts.
\ Suitable for earcons, music, voice, audio processing, streaming.
\
\ Memory: sample data via XMEM when available, descriptor on heap.
\ PCM-CREATE-FROM wraps existing data (no allocation).
\
\ Sample storage: interleaved channels.
\   Mono:   [s0] [s1] [s2] ...
\   Stereo: [L0 R0] [L1 R1] [L2 R2] ...
\
\ One "frame" = one sample per channel.
\ Frame size in bytes = (bits / 8) × channels.
\
\ Prefix: PCM-   (public API)
\         _PCM-  (internals)
\
\ Load with:   REQUIRE audio/pcm.f
\
\ === Public API ===
\   PCM-ALLOC       ( frames rate bits chans -- buf )
\   PCM-ALLOC-MS    ( ms rate bits chans -- buf )
\   PCM-FREE        ( buf -- )
\   PCM-CREATE-FROM ( addr frames rate bits chans -- buf )
\
\   PCM-DATA        ( buf -- addr )      sample data pointer
\   PCM-LEN         ( buf -- frames )    frame count
\   PCM-RATE        ( buf -- hz )        sample rate
\   PCM-BITS        ( buf -- n )         bits per sample
\   PCM-CHANS       ( buf -- n )         channel count
\   PCM-FLAGS       ( buf -- flags )     flag word
\   PCM-OFFSET      ( buf -- n )         cursor position
\   PCM-PEAK        ( buf -- n )         peak value seen
\   PCM-USER        ( buf -- x )         user payload
\   PCM-FRAME-BYTES ( buf -- n )         bytes per frame
\   PCM-DATA-BYTES  ( buf -- n )         total data bytes
\   PCM-DURATION-MS ( buf -- ms )        buffer duration in ms
\
\   PCM-SAMPLE!     ( value frame chan buf -- )
\   PCM-SAMPLE@     ( frame chan buf -- value )
\   PCM-FRAME!      ( value frame buf -- )   write mono (chan 0)
\   PCM-FRAME@      ( frame buf -- value )   read mono (chan 0)
\
\   PCM-CLEAR       ( buf -- )           zero all samples
\   PCM-FILL        ( value buf -- )     fill with constant
\   PCM-COPY        ( src dst -- )       copy samples
\   PCM-SLICE       ( start end buf -- buf' )  sub-buffer view
\   PCM-CLONE       ( buf -- buf' )      deep copy
\   PCM-REVERSE     ( buf -- )           reverse in place
\
\   PCM-MS>FRAMES   ( ms buf -- n )      ms to frame count
\   PCM-FRAMES>MS   ( n buf -- ms )      frame count to ms
\   PCM-RESAMPLE    ( new-rate buf -- buf' )  nearest-neighbor
\   PCM-TO-MONO     ( buf -- buf' )      mix down to mono
\   PCM-SCAN-PEAK   ( buf -- peak )      scan & update peak
\   PCM-NORMALIZE   ( target buf -- )    scale to target peak

PROVIDED akashic-audio-pcm

\ =====================================================================
\  PCM descriptor layout  (10 cells = 80 bytes)
\ =====================================================================
\
\  +0   data       pointer to sample data
\  +8   len        number of frames
\  +16  rate       sample rate in Hz
\  +24  bits       bits per sample (8, 16, or 32)
\  +32  channels   channel count
\  +40  flags      bit 0: owns buf, bit 1: XMEM buf
\  +48  offset     read/write cursor (frame index)
\  +56  peak       peak absolute sample value seen
\  +64  user       application-defined payload
\  +72  (reserved)

80 CONSTANT PCM-DESC-SIZE

: P.DATA    ( buf -- addr )  ;              \ +0
: P.LEN     ( buf -- addr )  8 + ;          \ +8
: P.RATE    ( buf -- addr )  16 + ;         \ +16
: P.BITS    ( buf -- addr )  24 + ;         \ +24
: P.CHANS   ( buf -- addr )  32 + ;         \ +32
: P.FLAGS   ( buf -- addr )  40 + ;         \ +40
: P.OFFSET  ( buf -- addr )  48 + ;         \ +48
: P.PEAK    ( buf -- addr )  56 + ;         \ +56
: P.USER    ( buf -- addr )  64 + ;         \ +64

\ Flag bits
1 CONSTANT _PCM-F-OWNS-BUF
2 CONSTANT _PCM-F-XMEM-BUF

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _PCM-TMP
VARIABLE _PCM-PTR
VARIABLE _PCM-CNT
VARIABLE _PCM-VAL
VARIABLE _PCM-SRC
VARIABLE _PCM-DST
VARIABLE _PCM-I
VARIABLE _PCM-FBYTES
VARIABLE _PCM-BYTES
VARIABLE _PCM-FRAMES
VARIABLE _PCM-RATE2
VARIABLE _PCM-BITS2
VARIABLE _PCM-CHANS2
VARIABLE _PCM-SA-BUF    \ buf for _PCM-SAMPLE-ADDR
VARIABLE _PCM-RW-BUF    \ buf for PCM-SAMPLE! / PCM-SAMPLE@

\ =====================================================================
\  Accessors — read fields
\ =====================================================================

: PCM-DATA   ( buf -- addr )    P.DATA  @ ;
: PCM-LEN    ( buf -- frames )  P.LEN   @ ;
: PCM-RATE   ( buf -- hz )      P.RATE  @ ;
: PCM-BITS   ( buf -- n )       P.BITS  @ ;
: PCM-CHANS  ( buf -- n )       P.CHANS @ ;
: PCM-FLAGS  ( buf -- flags )   P.FLAGS @ ;
: PCM-OFFSET ( buf -- n )       P.OFFSET @ ;
: PCM-PEAK   ( buf -- n )       P.PEAK  @ ;
: PCM-USER   ( buf -- x )       P.USER  @ ;

\ =====================================================================
\  Computed properties
\ =====================================================================

: PCM-FRAME-BYTES  ( buf -- n )
    DUP PCM-BITS 8 / SWAP PCM-CHANS * ;

: PCM-DATA-BYTES  ( buf -- n )
    DUP PCM-LEN SWAP PCM-FRAME-BYTES * ;

: PCM-DURATION-MS  ( buf -- ms )
    DUP PCM-LEN 1000 *
    SWAP PCM-RATE / ;

\ =====================================================================
\  Internal: validate bits per sample
\ =====================================================================

: _PCM-VALID-BITS?  ( bits -- flag )
    DUP 8 = IF DROP -1 EXIT THEN
    DUP 16 = IF DROP -1 EXIT THEN
    32 = IF -1 EXIT THEN
    0 ;

\ =====================================================================
\  PCM-ALLOC — Allocate new PCM buffer
\ =====================================================================
\  ( frames rate bits chans -- buf )

: PCM-ALLOC  ( frames rate bits chans -- buf )
    _PCM-CHANS2 !
    DUP _PCM-BITS2 !
    _PCM-VALID-BITS? 0= ABORT" PCM-ALLOC: bits must be 8, 16, or 32"
    _PCM-RATE2 !
    _PCM-FRAMES !

    \ Compute data size: frames × (bits/8) × channels
    _PCM-FRAMES @
    _PCM-BITS2 @ 8 / *
    _PCM-CHANS2 @ *
    _PCM-BYTES !

    \ Allocate descriptor (80 bytes, always heap)
    PCM-DESC-SIZE ALLOCATE
    0<> ABORT" PCM-ALLOC: descriptor alloc failed"
    _PCM-TMP !

    \ Allocate sample data
    _PCM-BYTES @
    XMEM? IF
        XMEM-ALLOT
        _PCM-PTR !
        _PCM-F-OWNS-BUF _PCM-F-XMEM-BUF OR
    ELSE
        ALLOCATE
        0<> IF
            _PCM-TMP @ FREE
            0 ABORT" PCM-ALLOC: data alloc failed"
        THEN
        _PCM-PTR !
        _PCM-F-OWNS-BUF
    THEN
    _PCM-VAL !   \ flags → _PCM-VAL

    \ Zero sample data
    _PCM-PTR @  _PCM-BYTES @  0 FILL

    \ Fill descriptor
    _PCM-PTR @       _PCM-TMP @ P.DATA   !
    _PCM-FRAMES @    _PCM-TMP @ P.LEN    !
    _PCM-RATE2 @     _PCM-TMP @ P.RATE   !
    _PCM-BITS2 @     _PCM-TMP @ P.BITS   !
    _PCM-CHANS2 @    _PCM-TMP @ P.CHANS  !
    _PCM-VAL @       _PCM-TMP @ P.FLAGS  !
    0                _PCM-TMP @ P.OFFSET !
    0                _PCM-TMP @ P.PEAK   !
    0                _PCM-TMP @ P.USER   !

    _PCM-TMP @ ;

\ =====================================================================
\  PCM-ALLOC-MS — Allocate by duration in milliseconds
\ =====================================================================
\  ( ms rate bits chans -- buf )

: PCM-ALLOC-MS  ( ms rate bits chans -- buf )
    _PCM-CHANS2 !
    _PCM-BITS2 !
    DUP _PCM-RATE2 !      \ save rate
    SWAP                   ( rate ms )
    OVER * 1000 /          ( rate frames )
    SWAP                   ( frames rate )
    _PCM-BITS2 @
    _PCM-CHANS2 @
    PCM-ALLOC ;

\ =====================================================================
\  PCM-FREE — Free PCM buffer
\ =====================================================================
\  ( buf -- )

: PCM-FREE  ( buf -- )
    DUP P.FLAGS @ _PCM-F-OWNS-BUF AND IF
        DUP P.FLAGS @ _PCM-F-XMEM-BUF AND IF
            DUP PCM-DATA-BYTES       ( buf bytes )
            OVER PCM-DATA            ( buf bytes addr )
            SWAP XMEM-FREE-BLOCK    ( buf )
        ELSE
            DUP PCM-DATA FREE
        THEN
    THEN
    FREE ;

\ =====================================================================
\  PCM-CREATE-FROM — Wrap existing sample data
\ =====================================================================
\  ( addr frames rate bits chans -- buf )
\  Does NOT own the data.  PCM-FREE will not free it.

: PCM-CREATE-FROM  ( addr frames rate bits chans -- buf )
    _PCM-CHANS2 !
    DUP _PCM-BITS2 !
    _PCM-VALID-BITS? 0= ABORT" PCM-CREATE-FROM: bits must be 8, 16, or 32"
    _PCM-RATE2 !
    _PCM-FRAMES !
    _PCM-PTR !

    PCM-DESC-SIZE ALLOCATE
    0<> ABORT" PCM-CREATE-FROM: descriptor alloc failed"
    _PCM-TMP !

    _PCM-PTR @       _PCM-TMP @ P.DATA   !
    _PCM-FRAMES @    _PCM-TMP @ P.LEN    !
    _PCM-RATE2 @     _PCM-TMP @ P.RATE   !
    _PCM-BITS2 @     _PCM-TMP @ P.BITS   !
    _PCM-CHANS2 @    _PCM-TMP @ P.CHANS  !
    0                _PCM-TMP @ P.FLAGS  !
    0                _PCM-TMP @ P.OFFSET !
    0                _PCM-TMP @ P.PEAK   !
    0                _PCM-TMP @ P.USER   !

    _PCM-TMP @ ;

\ =====================================================================
\  Internal: compute byte address for a sample
\ =====================================================================
\  _PCM-SAMPLE-ADDR ( frame chan buf -- addr )
\  addr = data + (frame × channels + chan) × (bits/8)

: _PCM-SAMPLE-ADDR  ( frame chan buf -- addr )
    _PCM-SA-BUF !                  \ save buf
    _PCM-SA-BUF @ PCM-CHANS       ( frame chan chans )
    ROT *                         ( chan frame*chans )
    +                             ( sample-index )
    _PCM-SA-BUF @ PCM-BITS 8 /    ( idx bytes-per-sample )
    *                             ( byte-offset )
    _PCM-SA-BUF @ PCM-DATA +      ( addr )
    ;

\ =====================================================================
\  PCM-SAMPLE! — Write one sample
\ =====================================================================
\  ( value frame chan buf -- )

: PCM-SAMPLE!  ( value frame chan buf -- )
    DUP _PCM-RW-BUF !               \ save buf
    _PCM-SAMPLE-ADDR                ( value addr )
    _PCM-RW-BUF @ PCM-BITS          ( value addr bits )
    DUP 8 = IF
        DROP C!                     \ 8-bit: byte store
    ELSE DUP 16 = IF
        DROP W!                     \ 16-bit: half-word store
    ELSE
        DROP L!                     \ 32-bit: long store
    THEN THEN ;

\ =====================================================================
\  PCM-SAMPLE@ — Read one sample
\ =====================================================================
\  ( frame chan buf -- value )

: PCM-SAMPLE@  ( frame chan buf -- value )
    DUP _PCM-RW-BUF !               \ save buf
    _PCM-SAMPLE-ADDR                ( addr )
    _PCM-RW-BUF @ PCM-BITS          ( addr bits )
    DUP 8 = IF
        DROP C@                     \ 8-bit
    ELSE DUP 16 = IF
        DROP W@                     \ 16-bit
    ELSE
        DROP L@                     \ 32-bit
    THEN THEN ;

\ =====================================================================
\  PCM-FRAME! / PCM-FRAME@ — Mono shortcuts (channel 0)
\ =====================================================================

: PCM-FRAME!  ( value frame buf -- )
    0 SWAP PCM-SAMPLE! ;

: PCM-FRAME@  ( frame buf -- value )
    0 SWAP PCM-SAMPLE@ ;

\ =====================================================================
\  PCM-CLEAR — Zero all samples
\ =====================================================================

: PCM-CLEAR  ( buf -- )
    DUP PCM-DATA              ( buf addr )
    SWAP PCM-DATA-BYTES       ( addr bytes )
    0 FILL ;

\ =====================================================================
\  PCM-FILL — Fill all samples with a constant value
\ =====================================================================
\  Writes value to every sample slot (every channel of every frame).

: PCM-FILL  ( value buf -- )
    _PCM-TMP !                   \ buf
    _PCM-VAL !                   \ value

    \ Total samples = frames × channels
    _PCM-TMP @ PCM-LEN
    _PCM-TMP @ PCM-CHANS *
    _PCM-CNT !

    _PCM-TMP @ PCM-DATA _PCM-PTR !
    _PCM-TMP @ PCM-BITS _PCM-BITS2 !

    _PCM-CNT @ 0 DO
        _PCM-BITS2 @ 8 = IF
            _PCM-VAL @ _PCM-PTR @ C!
            _PCM-PTR @ 1+ _PCM-PTR !
        ELSE _PCM-BITS2 @ 16 = IF
            _PCM-VAL @ _PCM-PTR @ W!
            _PCM-PTR @ 2 + _PCM-PTR !
        ELSE
            _PCM-VAL @ _PCM-PTR @ L!
            _PCM-PTR @ 4 + _PCM-PTR !
        THEN THEN
    LOOP ;

\ =====================================================================
\  PCM-COPY — Copy samples from src to dst
\ =====================================================================
\  Copies min(src-data-bytes, dst-data-bytes) bytes.

: PCM-COPY  ( src dst -- )
    _PCM-DST !  _PCM-SRC !

    _PCM-SRC @ PCM-DATA-BYTES
    _PCM-DST @ PCM-DATA-BYTES
    MIN _PCM-BYTES !

    _PCM-SRC @ PCM-DATA
    _PCM-DST @ PCM-DATA
    _PCM-BYTES @
    CMOVE ;

\ =====================================================================
\  PCM-SLICE — Sub-buffer view (shared data, no copy)
\ =====================================================================
\  ( start end buf -- buf' )
\  Creates a new descriptor pointing into the original data.
\  The new buffer does NOT own the data.

: PCM-SLICE  ( start end buf -- buf' )
    _PCM-TMP !                  \ buf
    _PCM-CNT !                  \ end
    _PCM-I !                    \ start

    \ Clamp
    _PCM-I @ 0 MAX _PCM-TMP @ PCM-LEN MIN  _PCM-I !
    _PCM-CNT @ _PCM-I @ MAX _PCM-TMP @ PCM-LEN MIN  _PCM-CNT !

    \ Compute new frame count
    _PCM-CNT @ _PCM-I @ -  _PCM-FRAMES !

    \ Compute data address for start frame
    _PCM-TMP @ PCM-DATA
    _PCM-I @ _PCM-TMP @ PCM-FRAME-BYTES * +
    _PCM-PTR !

    \ Create non-owning descriptor
    _PCM-PTR @
    _PCM-FRAMES @
    _PCM-TMP @ PCM-RATE
    _PCM-TMP @ PCM-BITS
    _PCM-TMP @ PCM-CHANS
    PCM-CREATE-FROM ;

\ =====================================================================
\  PCM-CLONE — Deep copy
\ =====================================================================
\  ( buf -- buf' )

: PCM-CLONE  ( buf -- buf' )
    _PCM-SRC !

    _PCM-SRC @ PCM-LEN
    _PCM-SRC @ PCM-RATE
    _PCM-SRC @ PCM-BITS
    _PCM-SRC @ PCM-CHANS
    PCM-ALLOC
    _PCM-DST !

    _PCM-SRC @ _PCM-DST @  PCM-COPY

    \ Copy metadata
    _PCM-SRC @ PCM-OFFSET  _PCM-DST @ P.OFFSET !
    _PCM-SRC @ PCM-PEAK    _PCM-DST @ P.PEAK   !
    _PCM-SRC @ PCM-USER    _PCM-DST @ P.USER   !

    _PCM-DST @ ;

\ =====================================================================
\  PCM-REVERSE — Reverse samples in place
\ =====================================================================
\  Swaps frames symmetrically: frame[0] ↔ frame[n-1], etc.

VARIABLE _PCM-REV-LO
VARIABLE _PCM-REV-HI
VARIABLE _PCM-REV-TMP
VARIABLE _PCM-NORM-TGT  \ target for PCM-NORMALIZE (survives SCAN-PEAK)

: PCM-REVERSE  ( buf -- )
    _PCM-TMP !

    _PCM-TMP @ PCM-LEN _PCM-CNT !

    0 _PCM-REV-LO !
    _PCM-CNT @ 1- _PCM-REV-HI !

    BEGIN
        _PCM-REV-LO @ _PCM-REV-HI @ <
    WHILE
        _PCM-TMP @ PCM-CHANS 0 DO
            \ Read lo sample
            _PCM-REV-LO @ I _PCM-TMP @ PCM-SAMPLE@
            _PCM-REV-TMP !
            \ Read hi sample, write to lo position
            _PCM-REV-HI @ I _PCM-TMP @ PCM-SAMPLE@
            _PCM-REV-LO @ I _PCM-TMP @ PCM-SAMPLE!
            \ Write saved lo sample to hi position
            _PCM-REV-TMP @
            _PCM-REV-HI @ I _PCM-TMP @ PCM-SAMPLE!
        LOOP
        _PCM-REV-LO @ 1+ _PCM-REV-LO !
        _PCM-REV-HI @ 1- _PCM-REV-HI !
    REPEAT ;

\ =====================================================================
\  PCM-MS>FRAMES — Convert milliseconds to frame count
\ =====================================================================

: PCM-MS>FRAMES  ( ms buf -- n )
    PCM-RATE  ( ms rate )
    * 1000 / ;

\ =====================================================================
\  PCM-FRAMES>MS — Convert frame count to milliseconds
\ =====================================================================

: PCM-FRAMES>MS  ( n buf -- ms )
    PCM-RATE  ( n rate )
    SWAP 1000 * SWAP / ;

\ =====================================================================
\  PCM-SCAN-PEAK — Scan all samples, update peak field
\ =====================================================================
\  Returns the peak absolute value.

: PCM-SCAN-PEAK  ( buf -- peak )
    _PCM-TMP !
    0 _PCM-VAL !                 \ running peak = 0

    _PCM-TMP @ PCM-LEN
    _PCM-TMP @ PCM-CHANS *
    _PCM-CNT !                   \ total samples

    _PCM-TMP @ PCM-DATA _PCM-PTR !
    _PCM-TMP @ PCM-BITS _PCM-BITS2 !

    _PCM-CNT @ 0 DO
        _PCM-BITS2 @ 8 = IF
            _PCM-PTR @ C@
            \ 8-bit unsigned, center is 128 — offset to signed
            128 -
            _PCM-PTR @ 1+ _PCM-PTR !
        ELSE _PCM-BITS2 @ 16 = IF
            _PCM-PTR @ W@
            \ Sign-extend 16-bit
            DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN
            _PCM-PTR @ 2 + _PCM-PTR !
        ELSE
            _PCM-PTR @ L@
            \ Sign-extend 32-bit
            DUP 0x80000000 AND IF 0xFFFFFFFF00000000 OR THEN
            _PCM-PTR @ 4 + _PCM-PTR !
        THEN THEN
        \ Absolute value
        DUP 0< IF NEGATE THEN
        \ Update peak
        DUP _PCM-VAL @ > IF
            _PCM-VAL !
        ELSE
            DROP
        THEN
    LOOP

    _PCM-VAL @ DUP _PCM-TMP @ P.PEAK !
    ;

\ =====================================================================
\  PCM-NORMALIZE — Scale all samples so peak = target
\ =====================================================================
\  ( target buf -- )
\  Integer scaling: each sample = sample × target / current-peak.
\  No-op if current peak is 0.

: PCM-NORMALIZE  ( target buf -- )
    _PCM-TMP !
    _PCM-NORM-TGT !              \ target in dedicated var

    _PCM-TMP @ PCM-SCAN-PEAK    ( current-peak )
    DUP 0= IF DROP EXIT THEN    \ silent buffer — nothing to do
    _PCM-CNT !                   \ reuse as current peak

    _PCM-TMP @ PCM-LEN
    _PCM-TMP @ PCM-CHANS *
    _PCM-I !                     \ total samples

    _PCM-TMP @ PCM-DATA _PCM-PTR !
    _PCM-TMP @ PCM-BITS _PCM-BITS2 !

    _PCM-I @ 0 DO
        \ Read sample
        _PCM-BITS2 @ 8 = IF
            _PCM-PTR @ C@        ( raw )
            128 -                 ( signed )
            _PCM-NORM-TGT @ * _PCM-CNT @ /   ( scaled )
            128 +                 ( unsigned )
            _PCM-PTR @ C!
            _PCM-PTR @ 1+ _PCM-PTR !
        ELSE _PCM-BITS2 @ 16 = IF
            _PCM-PTR @ W@        ( raw16 )
            DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN  ( signed )
            _PCM-NORM-TGT @ * _PCM-CNT @ /   ( scaled )
            0xFFFF AND           ( truncate to 16 bits )
            _PCM-PTR @ W!
            _PCM-PTR @ 2 + _PCM-PTR !
        ELSE
            _PCM-PTR @ L@        ( raw32 )
            DUP 0x80000000 AND IF 0xFFFFFFFF00000000 OR THEN
            _PCM-NORM-TGT @ * _PCM-CNT @ /
            0xFFFFFFFF AND
            _PCM-PTR @ L!
            _PCM-PTR @ 4 + _PCM-PTR !
        THEN THEN
    LOOP ;

\ =====================================================================
\  PCM-RESAMPLE — Nearest-neighbor resample to new rate
\ =====================================================================
\  ( new-rate buf -- buf' )
\  Allocates a new buffer at the target rate.

: PCM-RESAMPLE  ( new-rate buf -- buf' )
    _PCM-SRC !
    _PCM-RATE2 !

    \ new frames = src-len × new-rate / src-rate
    _PCM-SRC @ PCM-LEN
    _PCM-RATE2 @ *
    _PCM-SRC @ PCM-RATE /
    _PCM-FRAMES !

    _PCM-FRAMES @
    _PCM-RATE2 @
    _PCM-SRC @ PCM-BITS
    _PCM-SRC @ PCM-CHANS
    PCM-ALLOC
    _PCM-DST !

    _PCM-SRC @ PCM-CHANS _PCM-CHANS2 !

    _PCM-FRAMES @ 0 DO
        \ Source frame index = i × src-rate / new-rate
        I _PCM-SRC @ PCM-RATE *
        _PCM-RATE2 @ /
        _PCM-I !                  \ src frame index

        _PCM-CHANS2 @ 0 DO
            _PCM-I @ I _PCM-SRC @ PCM-SAMPLE@
            J I _PCM-DST @ PCM-SAMPLE!
        LOOP
    LOOP

    _PCM-DST @ ;

\ =====================================================================
\  PCM-TO-MONO — Mix down to mono by averaging channels
\ =====================================================================
\  ( buf -- buf' )
\  If already mono, returns a clone.

: PCM-TO-MONO  ( buf -- buf' )
    _PCM-SRC !

    _PCM-SRC @ PCM-CHANS 1 = IF
        _PCM-SRC @ PCM-CLONE EXIT
    THEN

    _PCM-SRC @ PCM-LEN
    _PCM-SRC @ PCM-RATE
    _PCM-SRC @ PCM-BITS
    1   \ mono
    PCM-ALLOC
    _PCM-DST !

    _PCM-SRC @ PCM-CHANS _PCM-CHANS2 !

    _PCM-SRC @ PCM-LEN 0 DO
        0 _PCM-VAL !             \ accumulator
        _PCM-CHANS2 @ 0 DO
            J I _PCM-SRC @ PCM-SAMPLE@   \ J=outer frame, I=channel
            _PCM-VAL +!
        LOOP
        _PCM-VAL @ _PCM-CHANS2 @ /
        I _PCM-DST @ PCM-FRAME!
    LOOP

    _PCM-DST @ ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _pcm-guard

' P.DATA          CONSTANT _p-dotdata-xt
' P.LEN           CONSTANT _p-dotlen-xt
' P.RATE          CONSTANT _p-dotrate-xt
' P.BITS          CONSTANT _p-dotbits-xt
' P.CHANS         CONSTANT _p-dotchans-xt
' P.FLAGS         CONSTANT _p-dotflags-xt
' P.OFFSET        CONSTANT _p-dotoffset-xt
' P.PEAK          CONSTANT _p-dotpeak-xt
' P.USER          CONSTANT _p-dotuser-xt
' PCM-DATA        CONSTANT _pcm-data-xt
' PCM-LEN         CONSTANT _pcm-len-xt
' PCM-RATE        CONSTANT _pcm-rate-xt
' PCM-BITS        CONSTANT _pcm-bits-xt
' PCM-CHANS       CONSTANT _pcm-chans-xt
' PCM-FLAGS       CONSTANT _pcm-flags-xt
' PCM-OFFSET      CONSTANT _pcm-offset-xt
' PCM-PEAK        CONSTANT _pcm-peak-xt
' PCM-USER        CONSTANT _pcm-user-xt
' PCM-FRAME-BYTES CONSTANT _pcm-frame-bytes-xt
' PCM-DATA-BYTES  CONSTANT _pcm-data-bytes-xt
' PCM-DURATION-MS CONSTANT _pcm-duration-ms-xt
' PCM-ALLOC       CONSTANT _pcm-alloc-xt
' PCM-ALLOC-MS    CONSTANT _pcm-alloc-ms-xt
' PCM-FREE        CONSTANT _pcm-free-xt
' PCM-CREATE-FROM CONSTANT _pcm-create-from-xt
' PCM-SAMPLE!     CONSTANT _pcm-sample-s-xt
' PCM-SAMPLE@     CONSTANT _pcm-sample-at-xt
' PCM-FRAME!      CONSTANT _pcm-frame-s-xt
' PCM-FRAME@      CONSTANT _pcm-frame-at-xt
' PCM-CLEAR       CONSTANT _pcm-clear-xt
' PCM-FILL        CONSTANT _pcm-fill-xt
' PCM-COPY        CONSTANT _pcm-copy-xt
' PCM-SLICE       CONSTANT _pcm-slice-xt
' PCM-CLONE       CONSTANT _pcm-clone-xt
' PCM-REVERSE     CONSTANT _pcm-reverse-xt
' PCM-MS>FRAMES   CONSTANT _pcm-ms-to-frames-xt
' PCM-FRAMES>MS   CONSTANT _pcm-frames-to-ms-xt
' PCM-SCAN-PEAK   CONSTANT _pcm-scan-peak-xt
' PCM-NORMALIZE   CONSTANT _pcm-normalize-xt
' PCM-RESAMPLE    CONSTANT _pcm-resample-xt
' PCM-TO-MONO     CONSTANT _pcm-to-mono-xt

: P.DATA          _p-dotdata-xt _pcm-guard WITH-GUARD ;
: P.LEN           _p-dotlen-xt _pcm-guard WITH-GUARD ;
: P.RATE          _p-dotrate-xt _pcm-guard WITH-GUARD ;
: P.BITS          _p-dotbits-xt _pcm-guard WITH-GUARD ;
: P.CHANS         _p-dotchans-xt _pcm-guard WITH-GUARD ;
: P.FLAGS         _p-dotflags-xt _pcm-guard WITH-GUARD ;
: P.OFFSET        _p-dotoffset-xt _pcm-guard WITH-GUARD ;
: P.PEAK          _p-dotpeak-xt _pcm-guard WITH-GUARD ;
: P.USER          _p-dotuser-xt _pcm-guard WITH-GUARD ;
: PCM-DATA        _pcm-data-xt _pcm-guard WITH-GUARD ;
: PCM-LEN         _pcm-len-xt _pcm-guard WITH-GUARD ;
: PCM-RATE        _pcm-rate-xt _pcm-guard WITH-GUARD ;
: PCM-BITS        _pcm-bits-xt _pcm-guard WITH-GUARD ;
: PCM-CHANS       _pcm-chans-xt _pcm-guard WITH-GUARD ;
: PCM-FLAGS       _pcm-flags-xt _pcm-guard WITH-GUARD ;
: PCM-OFFSET      _pcm-offset-xt _pcm-guard WITH-GUARD ;
: PCM-PEAK        _pcm-peak-xt _pcm-guard WITH-GUARD ;
: PCM-USER        _pcm-user-xt _pcm-guard WITH-GUARD ;
: PCM-FRAME-BYTES _pcm-frame-bytes-xt _pcm-guard WITH-GUARD ;
: PCM-DATA-BYTES  _pcm-data-bytes-xt _pcm-guard WITH-GUARD ;
: PCM-DURATION-MS _pcm-duration-ms-xt _pcm-guard WITH-GUARD ;
: PCM-ALLOC       _pcm-alloc-xt _pcm-guard WITH-GUARD ;
: PCM-ALLOC-MS    _pcm-alloc-ms-xt _pcm-guard WITH-GUARD ;
: PCM-FREE        _pcm-free-xt _pcm-guard WITH-GUARD ;
: PCM-CREATE-FROM _pcm-create-from-xt _pcm-guard WITH-GUARD ;
: PCM-SAMPLE!     _pcm-sample-s-xt _pcm-guard WITH-GUARD ;
: PCM-SAMPLE@     _pcm-sample-at-xt _pcm-guard WITH-GUARD ;
: PCM-FRAME!      _pcm-frame-s-xt _pcm-guard WITH-GUARD ;
: PCM-FRAME@      _pcm-frame-at-xt _pcm-guard WITH-GUARD ;
: PCM-CLEAR       _pcm-clear-xt _pcm-guard WITH-GUARD ;
: PCM-FILL        _pcm-fill-xt _pcm-guard WITH-GUARD ;
: PCM-COPY        _pcm-copy-xt _pcm-guard WITH-GUARD ;
: PCM-SLICE       _pcm-slice-xt _pcm-guard WITH-GUARD ;
: PCM-CLONE       _pcm-clone-xt _pcm-guard WITH-GUARD ;
: PCM-REVERSE     _pcm-reverse-xt _pcm-guard WITH-GUARD ;
: PCM-MS>FRAMES   _pcm-ms-to-frames-xt _pcm-guard WITH-GUARD ;
: PCM-FRAMES>MS   _pcm-frames-to-ms-xt _pcm-guard WITH-GUARD ;
: PCM-SCAN-PEAK   _pcm-scan-peak-xt _pcm-guard WITH-GUARD ;
: PCM-NORMALIZE   _pcm-normalize-xt _pcm-guard WITH-GUARD ;
: PCM-RESAMPLE    _pcm-resample-xt _pcm-guard WITH-GUARD ;
: PCM-TO-MONO     _pcm-to-mono-xt _pcm-guard WITH-GUARD ;
[THEN] [THEN]
