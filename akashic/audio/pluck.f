\ pluck.f — Karplus-Strong plucked-string synthesis
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Physical model: fill a delay line with noise, then repeatedly
\ average adjacent samples in a feedback loop.  High frequencies
\ decay faster than low, producing realistic plucked-string and
\ metallic timbres.
\
\ Delay line length = rate / freq samples.  The two-point average
\ filter in the feedback path acts as a first-order low-pass that
\ naturally produces spectral decay.  A loss factor controls the
\ overall decay rate.
\
\ Memory: descriptor (56 bytes) + delay buffer (2 bytes/sample).
\ At 44100 Hz, A1 (55 Hz) = 802 samples × 2 bytes ≈ 1.6 KiB.
\
\ Prefix: PLUCK-   (public API)
\         _PL-     (internals)
\
\ Load with:   REQUIRE audio/pluck.f
\
\ === Public API ===
\   PLUCK-CREATE   ( freq rate -- desc )    create pluck voice
\   PLUCK-FREE     ( desc -- )              free voice
\   PLUCK-EXCITE   ( desc -- )              fill delay with noise
\   PLUCK-RENDER   ( desc -- buf )          render one block
\   PLUCK          ( freq decay buf -- )    one-shot: fill buf
\   PLUCK-DECAY!   ( decay desc -- )        set decay factor
\   PLUCK-FREQ     ( desc -- freq )         get frequency
\   PLUCK-LEN      ( desc -- len )          get delay line length

REQUIRE fp16-ext.f
REQUIRE audio/pcm.f
REQUIRE audio/noise.f

PROVIDED akashic-audio-pluck

\ =====================================================================
\  Pluck descriptor layout  (7 cells = 56 bytes)
\ =====================================================================
\
\  +0   dl-data    Pointer to delay buffer (heap, 2 bytes/sample)
\  +8   dl-len     Delay line length (integer, = rate/freq)
\  +16  dl-wptr    Write pointer (0 .. dl-len-1)
\  +24  rate       Sample rate (integer)
\  +32  freq       Frequency (FP16)
\  +40  decay      Loss factor 0.0–1.0 (FP16), default 0.996
\  +48  work-buf   Work PCM buffer (for PLUCK-RENDER output)

56 CONSTANT _PL-DESC-SIZE

: PL.DATA   ( desc -- addr )  ;
: PL.LEN    ( desc -- addr )  8 + ;
: PL.WPTR   ( desc -- addr )  16 + ;
: PL.RATE   ( desc -- addr )  24 + ;
: PL.FREQ   ( desc -- addr )  32 + ;
: PL.DECAY  ( desc -- addr )  40 + ;
: PL.BUF    ( desc -- addr )  48 + ;

\ =====================================================================
\  FP16 constants
\ =====================================================================

\ 0.996 ≈ FP16 0x3FF0  (default decay)
\ Computed: 996/1000 via runtime division for accuracy
\ 0.5 = 0x3800 (for two-point average)

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _PL-TMP       \ descriptor pointer
VARIABLE _PL-VAL       \ temp value
VARIABLE _PL-PREV      \ previous sample for averaging
VARIABLE _PL-BUF       \ PCM buffer pointer
VARIABLE _PL-I         \ loop index
VARIABLE _PL-NOISE     \ noise generator

\ =====================================================================
\  Internal: read sample from delay line at position
\ =====================================================================
\  ( pos desc -- sample )

: _PL-DL@  ( pos desc -- sample )
    PL.DATA @ SWAP 2* + W@ ;

\ =====================================================================
\  Internal: write sample to delay line at position
\ =====================================================================
\  ( sample pos desc -- )

: _PL-DL!  ( sample pos desc -- )
    PL.DATA @ SWAP 2* + W! ;

\ =====================================================================
\  Internal: read sample at offset behind write pointer
\ =====================================================================
\  ( offset desc -- sample )
\  offset=0 → most recently written sample

: _PL-TAP  ( offset desc -- sample )
    _PL-TMP !
    _PL-TMP @ PL.WPTR @ 1-
    SWAP -
    _PL-TMP @ PL.LEN @ +
    _PL-TMP @ PL.LEN @ MOD
    _PL-TMP @ _PL-DL@ ;

\ =====================================================================
\  PLUCK-CREATE — Allocate pluck voice
\ =====================================================================
\  ( freq rate -- desc )
\  freq = FP16 Hz (e.g. 440 INT>FP16)
\  rate = integer sample rate (e.g. 44100)
\
\  Delay line length = rate / freq (integer division).

VARIABLE _PL-DLEN
VARIABLE _PL-RVAL

: PLUCK-CREATE  ( freq rate -- desc )
    _PL-RVAL !
    >R                                \ R: freq

    \ Compute delay length = rate / freq
    \ Convert both to FP16, divide, convert back to int
    _PL-RVAL @ INT>FP16
    R@ FP16-DIV
    FP16>INT
    2 MAX                             \ minimum 2 samples
    _PL-DLEN !

    \ Allocate descriptor
    _PL-DESC-SIZE ALLOCATE
    0<> ABORT" PLUCK-CREATE: desc alloc failed"
    _PL-TMP !

    \ Allocate delay buffer
    _PL-DLEN @ 2* ALLOCATE
    0<> ABORT" PLUCK-CREATE: delay alloc failed"
    _PL-TMP @ PL.DATA !

    \ Zero delay buffer
    _PL-TMP @ PL.DATA @
    _PL-DLEN @ 2*
    0 FILL

    _PL-DLEN @      _PL-TMP @ PL.LEN  !
    0                _PL-TMP @ PL.WPTR !
    _PL-RVAL @       _PL-TMP @ PL.RATE !
    R>               _PL-TMP @ PL.FREQ !

    \ Default decay = 0.996 ≈ 996/1000
    996 INT>FP16 1000 INT>FP16 FP16-DIV
    _PL-TMP @ PL.DECAY !

    \ Allocate work buffer: 256 frames, same rate, 16-bit mono
    256 _PL-RVAL @ 16 1 PCM-ALLOC
    _PL-TMP @ PL.BUF !

    _PL-TMP @ ;

\ =====================================================================
\  PLUCK-FREE — Free voice and all resources
\ =====================================================================

: PLUCK-FREE  ( desc -- )
    DUP PL.BUF @ PCM-FREE
    DUP PL.DATA @ FREE
    FREE ;

\ =====================================================================
\  PLUCK-EXCITE — Fill delay line with white noise
\ =====================================================================
\  Seeds the delay line for a new pluck event.  Uses a temporary
\  white noise generator.

: PLUCK-EXCITE  ( desc -- )
    _PL-TMP !

    \ Create white noise generator
    NOISE-WHITE NOISE-CREATE _PL-NOISE !

    \ Fill delay line with noise samples
    _PL-TMP @ PL.LEN @ 0 DO
        _PL-NOISE @ NOISE-SAMPLE
        I _PL-TMP @ _PL-DL!
    LOOP

    \ Reset write pointer
    0 _PL-TMP @ PL.WPTR !

    \ Free noise generator
    _PL-NOISE @ NOISE-FREE ;

\ =====================================================================
\  PLUCK-DECAY! — Set decay/loss factor
\ =====================================================================
\  ( decay desc -- )
\  decay is FP16 in [0.0, 1.0].  Higher = longer sustain.

: PLUCK-DECAY!  ( decay desc -- ) PL.DECAY ! ;

\ =====================================================================
\  Getters
\ =====================================================================

: PLUCK-FREQ  ( desc -- freq ) PL.FREQ @ ;
: PLUCK-LEN   ( desc -- len )  PL.LEN  @ ;

\ =====================================================================
\  Internal: generate one sample via Karplus-Strong
\ =====================================================================
\  Read current sample and next from delay line, average them,
\  multiply by decay, write back, return the output sample.
\
\  output = dl[wptr]
\  new = (dl[wptr] + dl[(wptr+1) mod len]) / 2  ×  decay
\  dl[wptr] = new
\  advance wptr

: _PL-SAMPLE  ( desc -- sample )
    _PL-TMP !

    \ Read current sample at wptr
    _PL-TMP @ PL.WPTR @
    _PL-TMP @ _PL-DL@
    _PL-VAL !

    \ Read next sample at (wptr+1) mod len
    _PL-TMP @ PL.WPTR @ 1+
    _PL-TMP @ PL.LEN @ MOD
    _PL-TMP @ _PL-DL@

    \ Average: (current + next) / 2
    _PL-VAL @ FP16-ADD
    FP16-POS-HALF FP16-MUL

    \ Apply decay factor
    _PL-TMP @ PL.DECAY @ FP16-MUL

    \ Write averaged value back into delay line at wptr
    _PL-TMP @ PL.WPTR @
    _PL-TMP @ _PL-DL!

    \ Advance write pointer
    _PL-TMP @ PL.WPTR @ 1+
    _PL-TMP @ PL.LEN @ MOD
    _PL-TMP @ PL.WPTR !

    \ Return original sample (before averaging) as output
    _PL-VAL @ ;

\ =====================================================================
\  PLUCK-RENDER — Render one block of output
\ =====================================================================
\  ( desc -- buf )
\  Generates buf-length samples into the internal work buffer.
\  Returns the work buffer pointer.

: PLUCK-RENDER  ( desc -- buf )
    _PL-TMP !

    _PL-TMP @ PL.BUF @ _PL-BUF !

    _PL-BUF @ PCM-LEN 0 DO
        _PL-TMP @ _PL-SAMPLE
        I _PL-BUF @ PCM-FRAME!
    LOOP

    _PL-BUF @ ;

\ =====================================================================
\  PLUCK — One-shot: fill a PCM buffer with plucked string
\ =====================================================================
\  ( freq decay buf -- )
\  freq  = FP16 Hz
\  decay = FP16 loss factor (e.g. 0.996)
\  buf   = pre-allocated PCM buffer
\
\  Creates a temporary pluck voice, excites it, renders into buf,
\  then frees the voice.

VARIABLE _PL-ONE-DESC

: PLUCK  ( freq decay buf -- )
    _PL-BUF !
    _PL-VAL !                         \ decay
    \ freq is on stack
    _PL-BUF @ PCM-RATE
    PLUCK-CREATE
    _PL-ONE-DESC !

    \ Set decay
    _PL-VAL @ _PL-ONE-DESC @ PLUCK-DECAY!

    \ Excite delay line
    _PL-ONE-DESC @ PLUCK-EXCITE

    \ Render samples into user's buffer
    _PL-BUF @ PCM-LEN 0 DO
        _PL-ONE-DESC @ _PL-SAMPLE
        I _PL-BUF @ PCM-FRAME!
    LOOP

    \ Free voice
    _PL-ONE-DESC @ PLUCK-FREE ;
