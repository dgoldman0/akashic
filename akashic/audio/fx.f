\ fx.f — Audio effects collection (Phase 2a: delay + distortion)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Each effect has a CREATE word (heap descriptor), a PROCESS word
\ ( buf desc -- ) that transforms a PCM buffer in-place, and a
\ FREE word.  Effects are designed to plug into chain.f slots.
\
\ This file contains:
\   - Internal circular delay line  (_DL- prefix)
\   - FX-DELAY  — Delay / Echo effect
\   - FX-DIST   — Distortion / Bitcrusher
\
\ Future subphases will add reverb, chorus, EQ, compressor.
\
\ All audio values are FP16 bit patterns in 16-bit PCM buffers.
\ Non-reentrant (uses VARIABLE scratch).
\
\ Prefix: FX-     (public API)
\         _DL-    (delay line internals)
\         _FXD-   (FX-DELAY internals)
\         _FXS-   (FX-DIST internals)
\
\ Load with:   REQUIRE audio/fx.f
\
\ === Public API ===
\   FX-DELAY-CREATE   ( delay-ms rate -- desc )
\   FX-DELAY-FREE     ( desc -- )
\   FX-DELAY!         ( ms desc -- )
\   FX-DELAY-FB!      ( fb desc -- )
\   FX-DELAY-WET!     ( wet desc -- )
\   FX-DELAY-PROCESS  ( buf desc -- )
\
\   FX-DIST-CREATE    ( drive mode -- desc )
\   FX-DIST-FREE      ( desc -- )
\   FX-DIST-DRIVE!    ( drive desc -- )
\   FX-DIST-PROCESS   ( buf desc -- )

REQUIRE audio/pcm.f

PROVIDED akashic-audio-fx

\ #####################################################################
\  SECTION 1 — Internal Circular Delay Line
\ #####################################################################
\
\  A heap-allocated circular buffer of FP16 samples.  Supports
\  write-at-head and read-at-arbitrary-offset (tap).  Used
\  internally by delay, reverb, and chorus effects.
\
\  NOT a KDOS RING — no spinlock, no CMOVE overhead, direct
\  W@ / W! access for per-sample DSP performance.

\ =====================================================================
\  Delay line descriptor layout  (3 cells = 24 bytes)
\ =====================================================================
\
\  +0   capacity   integer (max samples)
\  +8   wptr       integer (write position, 0 .. capacity-1)
\  +16  data       pointer to sample buffer (2 bytes per sample)

24 CONSTANT _DL-DESC-SIZE

: DL.CAP   ( dl -- addr )  ;           \ capacity at +0
: DL.WPTR  ( dl -- addr )  8 + ;       \ write pointer at +8
: DL.DATA  ( dl -- addr )  16 + ;      \ data pointer at +16

VARIABLE _DL-TMP     \ general scratch
VARIABLE _DL-PTR     \ descriptor during create

\ =====================================================================
\  _DL-CREATE — Allocate delay line
\ =====================================================================
\  ( capacity -- dl )

: _DL-CREATE  ( capacity -- dl )
    1 MAX _DL-TMP !

    _DL-DESC-SIZE ALLOCATE
    0<> ABORT" _DL-CREATE: desc alloc failed"
    _DL-PTR !

    _DL-TMP @ _DL-PTR @ DL.CAP !
    0          _DL-PTR @ DL.WPTR !

    \ Allocate sample buffer (2 bytes per FP16 sample)
    _DL-TMP @ 2* ALLOCATE
    0<> ABORT" _DL-CREATE: data alloc failed"
    _DL-PTR @ DL.DATA !

    \ Zero the buffer (silence)
    _DL-PTR @ DL.DATA @
    _DL-TMP @ 2*
    0 FILL

    _DL-PTR @ ;

\ =====================================================================
\  _DL-FREE — Free delay line
\ =====================================================================

: _DL-FREE  ( dl -- )
    DUP DL.DATA @ FREE
    FREE ;

\ =====================================================================
\  _DL-WRITE — Write sample at head and advance
\ =====================================================================
\  ( sample dl -- )

: _DL-WRITE  ( sample dl -- )
    _DL-PTR !
    \ Write sample at current wptr position
    _DL-PTR @ DL.WPTR @ 2*
    _DL-PTR @ DL.DATA @ +
    W!
    \ Advance wptr: (wptr + 1) mod capacity
    _DL-PTR @ DL.WPTR @
    1+
    _DL-PTR @ DL.CAP @ MOD
    _DL-PTR @ DL.WPTR ! ;

\ =====================================================================
\  _DL-TAP — Read sample at offset behind write head
\ =====================================================================
\  ( offset dl -- sample )
\  offset = 0 → sample just written (current wptr - 1)
\  offset = N → sample written N+1 steps ago
\
\  Clamps offset to [0, capacity-1].

: _DL-TAP  ( offset dl -- sample )
    _DL-PTR !
    \ Clamp offset to capacity - 1
    _DL-PTR @ DL.CAP @ 1- MIN 0 MAX
    \ Compute read position: (wptr - 1 - offset + capacity) mod capacity
    _DL-PTR @ DL.WPTR @ 1-
    SWAP -
    _DL-PTR @ DL.CAP @ +
    _DL-PTR @ DL.CAP @ MOD
    \ Read sample
    2* _DL-PTR @ DL.DATA @ + W@ ;

\ #####################################################################
\  SECTION 2 — FX-DELAY (Delay / Echo)
\ #####################################################################
\
\  Simple feedback delay.  A circular delay line stores past samples.
\  For each input sample:
\    delayed = _DL-TAP(delay_frames - 1)
\    output  = LERP(input, delayed, wet)
\    _DL-WRITE(input + feedback * delayed)
\
\  Parameters:
\    delay-ms  — delay time in milliseconds
\    feedback  — 0.0 = single echo, 0.9 = long trails (FP16)
\    wet       — 0.0 = dry, 1.0 = fully wet (FP16)

\ =====================================================================
\  FX-DELAY descriptor layout  (5 cells = 40 bytes)
\ =====================================================================
\
\  +0   dl        pointer to delay line
\  +8   delay     delay in frames (integer)
\  +16  feedback  FP16
\  +24  wet       FP16
\  +32  rate      sample rate (integer, for ms conversion)

40 CONSTANT FXD-DESC-SIZE

: FXD.DL    ( desc -- addr )  ;         \ delay line at +0
: FXD.DLY   ( desc -- addr )  8 + ;     \ delay frames at +8
: FXD.FB    ( desc -- addr )  16 + ;    \ feedback at +16
: FXD.WET   ( desc -- addr )  24 + ;    \ wet/dry mix at +24
: FXD.RATE  ( desc -- addr )  32 + ;    \ sample rate at +32

VARIABLE _FXD-BUF     \ PCM buffer during process
VARIABLE _FXD-DESC    \ descriptor during process
VARIABLE _FXD-X       \ current input sample
VARIABLE _FXD-D       \ delayed sample

\ =====================================================================
\  FX-DELAY-CREATE — Allocate delay effect
\ =====================================================================
\  ( delay-ms rate -- desc )
\  Creates a delay line sized for the given delay time.

: FX-DELAY-CREATE  ( delay-ms rate -- desc )
    _FXD-DESC !                        \ save rate temporarily

    \ Convert ms to frames: frames = ms * rate / 1000
    _FXD-DESC @ * 1000 /              ( delay-frames )
    1 MAX                             ( at least 1 frame )
    _FXD-X !                          \ save delay-frames

    \ Allocate descriptor
    FXD-DESC-SIZE ALLOCATE
    0<> ABORT" FX-DELAY-CREATE: alloc failed"
    _FXD-BUF !                        \ reuse var for desc addr

    \ Create delay line
    _FXD-X @ _DL-CREATE
    _FXD-BUF @ FXD.DL !

    \ Store parameters
    _FXD-X @       _FXD-BUF @ FXD.DLY  !
    FP16-POS-HALF  _FXD-BUF @ FXD.FB   !   \ default feedback = 0.5
    FP16-POS-HALF  _FXD-BUF @ FXD.WET  !   \ default wet = 0.5
    _FXD-DESC @    _FXD-BUF @ FXD.RATE !   \ restore rate from desc

    _FXD-BUF @ ;

\ =====================================================================
\  FX-DELAY-FREE — Free delay effect
\ =====================================================================

: FX-DELAY-FREE  ( desc -- )
    DUP FXD.DL @ _DL-FREE
    FREE ;

\ =====================================================================
\  FX-DELAY! — Change delay time (clamped to buffer capacity)
\ =====================================================================
\  ( ms desc -- )

: FX-DELAY!  ( ms desc -- )
    _FXD-DESC !
    _FXD-DESC @ FXD.RATE @ * 1000 /   ( frames )
    1 MAX
    _FXD-DESC @ FXD.DL @ DL.CAP @ 1-  ( frames max )
    MIN
    _FXD-DESC @ FXD.DLY ! ;

\ =====================================================================
\  FX-DELAY-FB! / FX-DELAY-WET! — Parameter setters
\ =====================================================================

: FX-DELAY-FB!   ( fb  desc -- )  FXD.FB  ! ;
: FX-DELAY-WET!  ( wet desc -- )  FXD.WET ! ;

\ =====================================================================
\  FX-DELAY-PROCESS — Apply delay effect in-place
\ =====================================================================
\  ( buf desc -- )

: FX-DELAY-PROCESS  ( buf desc -- )
    _FXD-DESC !
    _FXD-BUF !

    _FXD-BUF @ PCM-LEN 0 DO
        \ Read current input sample from buffer
        I _FXD-BUF @ PCM-FRAME@
        _FXD-X !

        \ Read delayed sample from delay line
        _FXD-DESC @ FXD.DLY @ 1-
        _FXD-DESC @ FXD.DL @
        _DL-TAP
        _FXD-D !

        \ Compute output: lerp(dry, delayed, wet)
        \   FP16-LERP ( a b t -- r ) = a + t*(b-a)
        \   wet=0 -> input, wet=1 -> delayed
        _FXD-X @
        _FXD-D @
        _FXD-DESC @ FXD.WET @
        FP16-LERP
        I _FXD-BUF @ PCM-FRAME!

        \ Write to delay line: input + feedback * delayed
        _FXD-D @
        _FXD-DESC @ FXD.FB @
        FP16-MUL                        ( fb*delayed )
        _FXD-X @ FP16-ADD              ( input + fb*delayed )
        _FXD-DESC @ FXD.DL @
        _DL-WRITE
    LOOP ;

\ #####################################################################
\  SECTION 3 — FX-DIST (Distortion / Bitcrusher)
\ #####################################################################
\
\  Three modes:
\   0 = soft clip:  out = t / (1 + |t|)    where t = x * drive
\   1 = hard clip:  out = CLAMP(x * drive, -1.0, +1.0)
\   2 = bitcrush:   zero lower N mantissa bits + sample-and-hold
\
\  drive is FP16 for modes 0/1, integer-as-FP16 for mode 2.

\ =====================================================================
\  FX-DIST descriptor layout  (4 cells = 32 bytes)
\ =====================================================================
\
\  +0   drive     FP16 (gain for soft/hard; crush amount for bitcrush)
\  +8   mode      integer (0=soft, 1=hard, 2=bitcrush)
\  +16  hold      FP16 last held sample (bitcrush state)
\  +24  cnt       integer hold counter (bitcrush state)

32 CONSTANT FXS-DESC-SIZE

: FXS.DRV   ( desc -- addr )  ;         \ drive at +0
: FXS.MODE  ( desc -- addr )  8 + ;     \ mode at +8
: FXS.HOLD  ( desc -- addr )  16 + ;    \ held sample at +16
: FXS.CNT   ( desc -- addr )  24 + ;    \ hold counter at +24

VARIABLE _FXS-BUF
VARIABLE _FXS-DESC
VARIABLE _FXS-X
VARIABLE _FXS-N       \ integer crush amount for bitcrush

\ =====================================================================
\  FX-DIST-CREATE — Allocate distortion effect
\ =====================================================================
\  ( drive mode -- desc )
\  drive: FP16 gain for modes 0/1; FP16 crush amount for mode 2
\  mode:  0=soft clip, 1=hard clip, 2=bitcrush

: FX-DIST-CREATE  ( drive mode -- desc )
    _FXS-N !                           \ save mode
    _FXS-X !                           \ save drive

    FXS-DESC-SIZE ALLOCATE
    0<> ABORT" FX-DIST-CREATE: alloc failed"
    _FXS-DESC !

    _FXS-X @          _FXS-DESC @ FXS.DRV  !
    _FXS-N @          _FXS-DESC @ FXS.MODE !
    FP16-POS-ZERO     _FXS-DESC @ FXS.HOLD !
    0                  _FXS-DESC @ FXS.CNT  !

    _FXS-DESC @ ;

\ =====================================================================
\  FX-DIST-FREE — Free distortion effect
\ =====================================================================

: FX-DIST-FREE  ( desc -- )  FREE ;

\ =====================================================================
\  FX-DIST-DRIVE! — Set drive amount
\ =====================================================================

: FX-DIST-DRIVE!  ( drive desc -- )  FXS.DRV ! ;

\ =====================================================================
\  Internal: soft clip one sample
\ =====================================================================
\  ( x desc -- out )
\  out = t / (1 + |t|)  where t = x * drive

: _FXS-SOFT  ( x desc -- out )
    FXS.DRV @
    FP16-MUL                            ( t = x*drive )
    DUP FP16-ABS                        ( t |t| )
    FP16-POS-ONE FP16-ADD              ( t 1+|t| )
    FP16-DIV ;                          ( t / (1+|t|) )

\ =====================================================================
\  Internal: hard clip one sample
\ =====================================================================
\  ( x desc -- out )
\  out = CLAMP(x * drive, -1.0, +1.0)

: _FXS-HARD  ( x desc -- out )
    FXS.DRV @
    FP16-MUL                            ( x*drive )
    FP16-NEG-ONE FP16-POS-ONE
    FP16-CLAMP ;                        ( clamped )

\ =====================================================================
\  Internal: bitcrush one sample
\ =====================================================================
\  ( x desc -- out )
\  Zeroes lower N mantissa bits of the FP16 value, where N
\  is the integer part of drive (clamped 0-10).
\  Also implements sample-and-hold: hold every Nth sample.

: _FXS-CRUSH  ( x desc -- out )
    _FXS-DESC !
    _FXS-X !

    \ Get integer crush amount from drive
    _FXS-DESC @ FXS.DRV @ FP16>INT
    0 MAX 10 MIN
    _FXS-N !

    \ Sample-and-hold with down-counting:
    \   cnt=0  -> capture new sample, reset cnt to (N-1)
    \   cnt>0  -> decrement, output held sample
    \ Initialized to cnt=0 so first sample is always captured.

    _FXS-DESC @ FXS.CNT @ 0= IF
        \ Capture: reset counter and quantize
        _FXS-N @ 1 MAX 1-
        _FXS-DESC @ FXS.CNT !

        \ Quantize: zero lower N mantissa bits via shift
        _FXS-X @ 0xFFFF AND
        _FXS-N @ RSHIFT
        _FXS-N @ LSHIFT
        0xFFFF AND

        DUP _FXS-DESC @ FXS.HOLD !
    ELSE
        \ Hold: decrement counter, output held value
        _FXS-DESC @ FXS.CNT @ 1-
        _FXS-DESC @ FXS.CNT !
        _FXS-DESC @ FXS.HOLD @
    THEN ;

\ =====================================================================
\  FX-DIST-PROCESS — Apply distortion in-place
\ =====================================================================
\  ( buf desc -- )

: FX-DIST-PROCESS  ( buf desc -- )
    _FXS-DESC !
    _FXS-BUF !

    _FXS-BUF @ PCM-LEN 0 DO
        I _FXS-BUF @ PCM-FRAME@        ( x )

        _FXS-DESC @                     ( x desc )
        _FXS-DESC @ FXS.MODE @
        CASE
            0 OF _FXS-SOFT ENDOF
            1 OF _FXS-HARD ENDOF
            2 OF _FXS-CRUSH ENDOF
            \ default: pass through
            DROP
        ENDCASE

        I _FXS-BUF @ PCM-FRAME!
    LOOP ;
