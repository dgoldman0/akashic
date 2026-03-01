\ fx.f — Audio effects collection
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Each effect has a CREATE word (heap descriptor), a PROCESS word
\ ( buf desc -- ) that transforms a PCM buffer in-place, and a
\ FREE word.  Effects are designed to plug into chain.f slots.
\
\ This file contains:
\   - Internal circular delay line  (_DL- prefix)
\   - FX-DELAY   — Delay / Echo effect
\   - FX-DIST    — Distortion / Bitcrusher
\   - FX-REVERB  — Schroeder reverb (4 comb + 2 allpass)
\   - FX-CHORUS  — LFO-modulated delay chorus
\   - FX-EQ      — Parametric EQ (up to 4 IIR biquad bands)
\
\ All audio values are FP16 bit patterns in 16-bit PCM buffers.
\ Non-reentrant (uses VARIABLE scratch).
\
\ Prefix: FX-     (public API)
\         _DL-    (delay line internals)
\         _FXD-   (FX-DELAY internals)
\         _FXS-   (FX-DIST internals)
\         _FXR-   (FX-REVERB internals)
\         _FXC-   (FX-CHORUS internals)
\         _FXQ-   (FX-EQ internals)
\
\ Load with:   REQUIRE audio/fx.f
\
\ === Public API ===
\   FX-DELAY-CREATE    ( delay-ms rate -- desc )
\   FX-DELAY-FREE      ( desc -- )
\   FX-DELAY!          ( ms desc -- )
\   FX-DELAY-FB!       ( fb desc -- )
\   FX-DELAY-WET!      ( wet desc -- )
\   FX-DELAY-PROCESS   ( buf desc -- )
\
\   FX-DIST-CREATE     ( drive mode -- desc )
\   FX-DIST-FREE       ( desc -- )
\   FX-DIST-DRIVE!     ( drive desc -- )
\   FX-DIST-PROCESS    ( buf desc -- )
\
\   FX-REVERB-CREATE   ( room damp wet rate -- desc )
\   FX-REVERB-FREE     ( desc -- )
\   FX-REVERB-PROCESS  ( buf desc -- )
\   FX-REVERB-ROOM!    ( room desc -- )
\   FX-REVERB-DAMP!    ( damp desc -- )
\
\   FX-CHORUS-CREATE   ( depth-ms rate-hz mix rate -- desc )
\   FX-CHORUS-FREE     ( desc -- )
\   FX-CHORUS-PROCESS  ( buf desc -- )
\
\   FX-EQ-CREATE       ( nbands rate -- desc )
\   FX-EQ-FREE         ( desc -- )
\   FX-EQ-BAND!        ( freq gain-db Q band# desc -- )
\   FX-EQ-PROCESS      ( buf desc -- )
\
\   FX-COMP-CREATE     ( thresh ratio attack release rate -- desc )
\   FX-COMP-FREE       ( desc -- )
\   FX-COMP-PROCESS    ( buf desc -- )
\   FX-COMP-LIMIT!     ( desc -- )

REQUIRE audio/pcm.f
REQUIRE audio/lfo.f
REQUIRE ../math/trig.f
REQUIRE ../math/exp.f

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

\ #####################################################################
\  SECTION 4 — FX-REVERB (Schroeder Reverb)
\ #####################################################################
\
\  Classic Schroeder topology:
\    4 parallel comb filters  →  sum  →  2 series allpass filters
\
\  Each comb has a one-pole LP in its feedback path (damping).
\  Comb delay times (Freeverb classic, at 44100 Hz):
\    1116, 1188, 1277, 1356 samples — scaled to actual rate.
\  Allpass delay times: 556, 441 samples.  Gain = 0.5.
\
\  Parameters:
\    room  — FP16 0.0–1.0 (comb feedback amount, longer tail)
\    damp  — FP16 0.0–1.0 (LP cutoff: 0=bright, 1=dark)
\    wet   — FP16 0.0–1.0 (wet/dry mix)
\
\  Memory: ~13.4 KiB at 44100 Hz, much less at lower rates.

\ =====================================================================
\  FX-REVERB descriptor layout  (13 cells = 104 bytes)
\ =====================================================================
\
\  +0    comb DL 0     (pointer)
\  +8    comb DL 1     (pointer)
\  +16   comb DL 2     (pointer)
\  +24   comb DL 3     (pointer)
\  +32   allpass DL 0  (pointer)
\  +40   allpass DL 1  (pointer)
\  +48   filt state 0  (FP16 — comb 0 one-pole LP state)
\  +56   filt state 1  (FP16 — comb 1)
\  +64   filt state 2  (FP16 — comb 2)
\  +72   filt state 3  (FP16 — comb 3)
\  +80   room          (FP16)
\  +88   damp          (FP16)
\  +96   wet           (FP16)

104 CONSTANT FXR-DESC-SIZE

: FXR.C0   ( d -- addr )  ;
: FXR.C1   ( d -- addr )  8 + ;
: FXR.C2   ( d -- addr )  16 + ;
: FXR.C3   ( d -- addr )  24 + ;
: FXR.A0   ( d -- addr )  32 + ;
: FXR.A1   ( d -- addr )  40 + ;
: FXR.F0   ( d -- addr )  48 + ;
: FXR.F1   ( d -- addr )  56 + ;
: FXR.F2   ( d -- addr )  64 + ;
: FXR.F3   ( d -- addr )  72 + ;
: FXR.ROOM ( d -- addr )  80 + ;
: FXR.DAMP ( d -- addr )  88 + ;
: FXR.WET  ( d -- addr )  96 + ;

VARIABLE _FXR-RATE    \ saved rate for delay scaling
VARIABLE _FXR-PTR     \ descriptor under construction
VARIABLE _FXR-BUF     \ PCM buffer during process
VARIABLE _FXR-DESC    \ descriptor during process
VARIABLE _FXR-X       \ current input sample
VARIABLE _FXR-DL      \ current delay line
VARIABLE _FXR-D       \ delayed sample
VARIABLE _FXR-SUM     \ accumulator / allpass input
VARIABLE _FXR-FA      \ filter state address
VARIABLE _FXR-DAMP1   \ precomputed 1 - damp

\ =====================================================================
\  _FXR-SCALE — Scale Freeverb delay time to actual rate
\ =====================================================================
\  ( base -- scaled )   at least 1

: _FXR-SCALE  ( base -- scaled )
    _FXR-RATE @ * 44100 / 1 MAX ;

\ =====================================================================
\  FX-REVERB-CREATE — Allocate Schroeder reverb
\ =====================================================================
\  ( room damp wet rate -- desc )

: FX-REVERB-CREATE  ( room damp wet rate -- desc )
    _FXR-RATE !                        ( room damp wet )

    FXR-DESC-SIZE ALLOCATE
    0<> ABORT" FX-REVERB-CREATE: alloc failed"
    _FXR-PTR !                         ( room damp wet )

    _FXR-PTR @ FXR.WET !              ( room damp )
    _FXR-PTR @ FXR.DAMP !             ( room )
    _FXR-PTR @ FXR.ROOM !             ( )

    \ Zero filter states
    0 _FXR-PTR @ FXR.F0 !
    0 _FXR-PTR @ FXR.F1 !
    0 _FXR-PTR @ FXR.F2 !
    0 _FXR-PTR @ FXR.F3 !

    \ Create comb delay lines (Freeverb classic delay times)
    1116 _FXR-SCALE _DL-CREATE _FXR-PTR @ FXR.C0 !
    1188 _FXR-SCALE _DL-CREATE _FXR-PTR @ FXR.C1 !
    1277 _FXR-SCALE _DL-CREATE _FXR-PTR @ FXR.C2 !
    1356 _FXR-SCALE _DL-CREATE _FXR-PTR @ FXR.C3 !

    \ Create allpass delay lines
     556 _FXR-SCALE _DL-CREATE _FXR-PTR @ FXR.A0 !
     441 _FXR-SCALE _DL-CREATE _FXR-PTR @ FXR.A1 !

    _FXR-PTR @ ;

\ =====================================================================
\  FX-REVERB-FREE — Free reverb and all delay lines
\ =====================================================================

: FX-REVERB-FREE  ( desc -- )
    DUP FXR.C0 @ _DL-FREE
    DUP FXR.C1 @ _DL-FREE
    DUP FXR.C2 @ _DL-FREE
    DUP FXR.C3 @ _DL-FREE
    DUP FXR.A0 @ _DL-FREE
    DUP FXR.A1 @ _DL-FREE
    FREE ;

\ =====================================================================
\  FX-REVERB-ROOM! / FX-REVERB-DAMP! — Adjust parameters
\ =====================================================================

: FX-REVERB-ROOM!  ( room desc -- )  FXR.ROOM ! ;
: FX-REVERB-DAMP!  ( damp desc -- )  FXR.DAMP ! ;

\ =====================================================================
\  _FXR-COMB1 — Process one comb filter for current sample
\ =====================================================================
\  ( dl filt-addr -- contribution )
\  Reads _FXR-X, _FXR-DESC (room, damp), _FXR-DAMP1.

: _FXR-COMB1  ( dl filt-addr -- contribution )
    _FXR-FA !
    _FXR-DL !

    \ Read delayed sample (oldest in buffer)
    _FXR-DL @ DL.CAP @ 1-
    _FXR-DL @ _DL-TAP                 ( delayed )
    _FXR-D !

    \ One-pole LP: filtered = (1-damp)*delayed + damp*prev_filt
    _FXR-DAMP1 @ _FXR-D @ FP16-MUL   ( (1-d)*del )
    _FXR-DESC @ FXR.DAMP @
    _FXR-FA @ @ FP16-MUL              ( (1-d)*del d*prev )
    FP16-ADD                           ( filtered )
    DUP _FXR-FA @ !                    \ update state

    \ Write to delay: input + room * filtered
    DUP
    _FXR-DESC @ FXR.ROOM @ SWAP FP16-MUL  ( filtered room*filt )
    _FXR-X @ FP16-ADD                 ( filtered write_val )
    _FXR-DL @ _DL-WRITE               ( filtered )
    ;

\ =====================================================================
\  _FXR-AP1 — Process one allpass filter for current sample
\ =====================================================================
\  ( input dl -- output )
\  Freeverb allpass: output = bufout - input
\                    write(input + 0.5 * bufout)

: _FXR-AP1  ( input dl -- output )
    _FXR-DL !
    _FXR-SUM !                         \ save input

    \ Read delayed
    _FXR-DL @ DL.CAP @ 1-
    _FXR-DL @ _DL-TAP                 ( bufout )
    _FXR-D !

    \ output = bufout - input
    _FXR-D @ _FXR-SUM @ FP16-SUB      ( output )

    \ write = input + 0.5 * bufout
    _FXR-SUM @
    0x3800 _FXR-D @ FP16-MUL
    FP16-ADD                           ( output write_val )
    _FXR-DL @ _DL-WRITE               ( output )
    ;

\ =====================================================================
\  FX-REVERB-PROCESS — Apply reverb in-place
\ =====================================================================
\  ( buf desc -- )

: FX-REVERB-PROCESS  ( buf desc -- )
    _FXR-DESC !
    _FXR-BUF !

    \ Precompute (1 - damp)
    0x3C00 _FXR-DESC @ FXR.DAMP @ FP16-SUB
    _FXR-DAMP1 !

    _FXR-BUF @ PCM-LEN 0 DO
        \ Read input sample
        I _FXR-BUF @ PCM-FRAME@
        _FXR-X !

        \ Sum 4 parallel comb filters
        _FXR-DESC @ FXR.C0 @  _FXR-DESC @ FXR.F0  _FXR-COMB1
        _FXR-DESC @ FXR.C1 @  _FXR-DESC @ FXR.F1  _FXR-COMB1
        FP16-ADD
        _FXR-DESC @ FXR.C2 @  _FXR-DESC @ FXR.F2  _FXR-COMB1
        FP16-ADD
        _FXR-DESC @ FXR.C3 @  _FXR-DESC @ FXR.F3  _FXR-COMB1
        FP16-ADD

        \ Scale by 0.25 to prevent overflow
        0x3400 FP16-MUL                ( scaled_sum )

        \ Series allpass chain
        _FXR-DESC @ FXR.A0 @ _FXR-AP1 ( ap0_out )
        _FXR-DESC @ FXR.A1 @ _FXR-AP1 ( ap1_out )

        \ Wet/dry mix: LERP(dry, reverb, wet)
        _FXR-X @ SWAP
        _FXR-DESC @ FXR.WET @
        FP16-LERP                      ( mixed )

        I _FXR-BUF @ PCM-FRAME!
    LOOP ;

\ #####################################################################
\  SECTION 5 — FX-CHORUS (LFO-Modulated Delay)
\ #####################################################################
\
\  A short delay line whose tap position is swept by an LFO.
\  Linear interpolation between adjacent delay samples for
\  sub-sample precision.  Produces the classic chorus thickening.
\
\  Parameters:
\    depth-ms  — integer, modulation range in ms (typ. 2–10)
\    rate-hz   — FP16, LFO frequency (typ. 0.3–3.0 Hz)
\    mix       — FP16, wet/dry (0.0–1.0)
\    rate      — integer, sample rate
\
\  Center delay fixed at 25 ms.

\ =====================================================================
\  FX-CHORUS descriptor layout  (4 cells = 32 bytes)
\ =====================================================================
\
\  +0   dl        pointer to delay line
\  +8   lfo       pointer to LFO descriptor
\  +16  mix       FP16 wet/dry
\  +24  center    integer center delay in samples

32 CONSTANT FXC-DESC-SIZE

: FXC.DL     ( d -- addr )  ;
: FXC.LFO    ( d -- addr )  8 + ;
: FXC.MIX    ( d -- addr )  16 + ;
: FXC.CTR    ( d -- addr )  24 + ;

VARIABLE _FXC-PTR     \ descriptor under construction
VARIABLE _FXC-BUF     \ PCM buffer during process
VARIABLE _FXC-DESC    \ descriptor during process
VARIABLE _FXC-X       \ current input
VARIABLE _FXC-TAP     \ FP16 modulated tap position
VARIABLE _FXC-IOFF    \ integer part of tap offset
VARIABLE _FXC-FRAC    \ FP16 fractional part
VARIABLE _FXC-TMP1    \ scratch
VARIABLE _FXC-TMP2    \ scratch

\ =====================================================================
\  FX-CHORUS-CREATE — Allocate chorus effect
\ =====================================================================
\  ( depth-ms rate-hz mix rate -- desc )
\  depth-ms: integer, modulation depth in ms
\  rate-hz:  FP16, LFO frequency
\  mix:      FP16, wet/dry
\  rate:     integer, sample rate

: FX-CHORUS-CREATE  ( depth-ms rate-hz mix rate -- desc )
    _FXC-TMP1 !                        \ save rate
    _FXC-TMP2 !                        \ save mix temporarily

    FXC-DESC-SIZE ALLOCATE
    0<> ABORT" FX-CHORUS-CREATE: alloc failed"
    _FXC-PTR !                         ( depth-ms rate-hz )

    _FXC-TMP2 @  _FXC-PTR @ FXC.MIX !

    \ center = 25 * rate / 1000
    25 _FXC-TMP1 @ * 1000 /
    DUP _FXC-PTR @ FXC.CTR !          ( depth-ms rate-hz center )
    DROP                               ( depth-ms rate-hz )

    \ depth_samples = depth-ms * rate / 1000
    SWAP _FXC-TMP1 @ * 1000 /         ( rate-hz depth_samples )
    1 MAX

    \ DL capacity = center + depth + 2 (safety margin)
    _FXC-PTR @ FXC.CTR @ OVER + 2 +
    _DL-CREATE _FXC-PTR @ FXC.DL !    ( rate-hz depth_samples )

    \ Create LFO: ( freq shape depth center rate -- lfo )
    \   shape = 0 (sine)
    \   depth = depth_samples as FP16 (half-range of modulation)
    \   center = center_samples as FP16
    SWAP                               ( depth_samples rate-hz )
    0                                  ( depth_samples rate-hz shape=sine )
    ROT INT>FP16                       ( rate-hz shape depth_fp16 )
    _FXC-PTR @ FXC.CTR @ INT>FP16     ( rate-hz shape depth center_fp16 )
    _FXC-TMP1 @                        ( rate-hz shape depth center rate )
    LFO-CREATE
    _FXC-PTR @ FXC.LFO !

    _FXC-PTR @ ;

\ =====================================================================
\  FX-CHORUS-FREE — Free chorus, delay line, and LFO
\ =====================================================================

: FX-CHORUS-FREE  ( desc -- )
    DUP FXC.DL @  _DL-FREE
    DUP FXC.LFO @ LFO-FREE
    FREE ;

\ =====================================================================
\  FX-CHORUS-PROCESS — Apply chorus in-place
\ =====================================================================
\  For each sample:
\    1. Write input into delay line
\    2. LFO-TICK → FP16 tap offset
\    3. Integer/fractional split for linear interpolation
\    4. Read two adjacent taps, interpolate
\    5. Mix with dry input
\  ( buf desc -- )

: FX-CHORUS-PROCESS  ( buf desc -- )
    _FXC-DESC !
    _FXC-BUF !

    _FXC-BUF @ PCM-LEN 0 DO
        \ Read input
        I _FXC-BUF @ PCM-FRAME@
        _FXC-X !

        \ Write input into delay line (before read, so we read past)
        _FXC-X @
        _FXC-DESC @ FXC.DL @
        _DL-WRITE

        \ Get modulated tap position from LFO
        _FXC-DESC @ FXC.LFO @
        LFO-TICK                       ( tap_fp16 )
        \ Clamp to positive range
        0 FP16-MAX
        _FXC-TAP !

        \ Split into integer and fractional parts
        _FXC-TAP @ FP16>INT
        _FXC-IOFF !
        _FXC-TAP @
        _FXC-IOFF @ INT>FP16 FP16-SUB
        _FXC-FRAC !

        \ Read two adjacent delay taps
        _FXC-IOFF @     _FXC-DESC @ FXC.DL @ _DL-TAP  ( s0 )
        _FXC-IOFF @ 1+  _FXC-DESC @ FXC.DL @ _DL-TAP  ( s0 s1 )

        \ Linear interpolation: lerp(s0, s1, frac)
        _FXC-FRAC @ FP16-LERP         ( delayed )

        \ Wet/dry mix: lerp(dry, delayed, mix)
        _FXC-X @ SWAP
        _FXC-DESC @ FXC.MIX @
        FP16-LERP                      ( mixed )

        I _FXC-BUF @ PCM-FRAME!
    LOOP ;

\ #####################################################################
\  SECTION 6 — FX-EQ (Parametric Equalizer)
\ #####################################################################
\
\  Up to 4 bands of IIR biquad filtering.  Each band has its own
\  coefficients (b0, b1, b2, a1, a2) and persistent delay state
\  (s1, s2) for Direct Form II Transposed.
\
\  FX-EQ-BAND! recomputes biquad coefficients from frequency,
\  gain-dB, and Q.  Band type auto-selected:
\    freq < 200 Hz      → low shelf
\    freq > rate/4      → high shelf
\    otherwise           → peaking EQ
\
\  Coefficients computed using standard Audio EQ Cookbook formulas
\  (Robert Bristow-Johnson).

\ =====================================================================
\  Per-band layout  (7 FP16 values = 7 cells = 56 bytes)
\ =====================================================================
\
\  +0   b0   FP16
\  +8   b1   FP16
\  +16  b2   FP16
\  +24  a1   FP16
\  +32  a2   FP16
\  +40  s1   FP16 (state register 1)
\  +48  s2   FP16 (state register 2)

56 CONSTANT _FXQ-BAND-SIZE

: _QB.B0  ( band -- addr )  ;
: _QB.B1  ( band -- addr )  8 + ;
: _QB.B2  ( band -- addr )  16 + ;
: _QB.A1  ( band -- addr )  24 + ;
: _QB.A2  ( band -- addr )  32 + ;
: _QB.S1  ( band -- addr )  40 + ;
: _QB.S2  ( band -- addr )  48 + ;

\ =====================================================================
\  FX-EQ descriptor layout  (3 cells + band array)
\ =====================================================================
\
\  +0   nbands   integer (1–4)
\  +8   rate     integer (sample rate)
\  +16  bands    pointer to array of nbands band descriptors

24 CONSTANT FXQ-DESC-SIZE

: FXQ.N    ( d -- addr )  ;
: FXQ.RATE ( d -- addr )  8 + ;
: FXQ.BANDS ( d -- addr ) 16 + ;

VARIABLE _FXQ-PTR     \ descriptor under construction
VARIABLE _FXQ-BUF     \ PCM buffer during process
VARIABLE _FXQ-DESC    \ descriptor during process
VARIABLE _FXQ-X       \ current sample
VARIABLE _FXQ-Y       \ output sample
VARIABLE _FXQ-BP      \ current band pointer
VARIABLE _FXQ-TMP1    \ scratch
VARIABLE _FXQ-TMP2    \ scratch
VARIABLE _FXQ-TMP3    \ scratch

\ =====================================================================
\  FX-EQ-CREATE — Allocate parametric EQ
\ =====================================================================
\  ( nbands rate -- desc )

: FX-EQ-CREATE  ( nbands rate -- desc )
    _FXQ-TMP1 !                        \ save rate

    \ Clamp nbands to 1–4
    1 MAX 4 MIN
    _FXQ-TMP2 !                        \ save clamped nbands

    FXQ-DESC-SIZE ALLOCATE
    0<> ABORT" FX-EQ-CREATE: alloc failed"
    _FXQ-PTR !

    _FXQ-TMP2 @ _FXQ-PTR @ FXQ.N !
    _FXQ-TMP1 @ _FXQ-PTR @ FXQ.RATE !

    \ Allocate band array
    _FXQ-TMP2 @ _FXQ-BAND-SIZE *
    ALLOCATE
    0<> ABORT" FX-EQ-CREATE: band alloc failed"
    DUP _FXQ-PTR @ FXQ.BANDS !

    \ Zero all band data (unity passthrough: b0=1, rest=0)
    _FXQ-TMP2 @ _FXQ-BAND-SIZE * 0 FILL

    \ Set each band to unity passthrough (b0=1.0)
    _FXQ-TMP2 @ 0 DO
        0x3C00
        _FXQ-PTR @ FXQ.BANDS @
        I _FXQ-BAND-SIZE * +
        _QB.B0 !
    LOOP

    _FXQ-PTR @ ;

\ =====================================================================
\  FX-EQ-FREE — Free EQ and band array
\ =====================================================================

: FX-EQ-FREE  ( desc -- )
    DUP FXQ.BANDS @ FREE
    FREE ;

\ =====================================================================
\  FX-EQ-BAND! — Configure a band
\ =====================================================================
\  ( freq gain-db Q band# desc -- )
\  freq:    integer Hz
\  gain-db: FP16 (positive = boost, negative = cut)
\  Q:       FP16 (quality factor, 0.1–10, typ. 0.707)
\  band#:   integer 0-based
\
\  Auto-selects filter type based on frequency:
\    freq < 200      → low shelf
\    freq > rate/4   → high shelf
\    otherwise        → peaking EQ
\
\  Uses Audio EQ Cookbook (RBJ) biquad formulas.

VARIABLE _FXQ-FREQ    \ integer Hz
VARIABLE _FXQ-GAIN    \ FP16 gain-dB
VARIABLE _FXQ-Q       \ FP16 Q
VARIABLE _FXQ-W0      \ FP16 omega0 = 2*pi*freq/rate
VARIABLE _FXQ-SN      \ FP16 sin(w0)
VARIABLE _FXQ-CS      \ FP16 cos(w0)
VARIABLE _FXQ-ALPHA   \ FP16 alpha = sin(w0)/(2*Q)
VARIABLE _FXQ-A       \ FP16 A = 10^(dBgain/40) ≈ 1 + gain/6.02
VARIABLE _FXQ-NORM    \ FP16 1/a0 for normalization

\ _FXQ-BAND-ADDR — Get address of band# in desc
\  ( band# desc -- band-addr )
: _FXQ-BAND-ADDR  ( band# desc -- band-addr )
    FXQ.BANDS @
    SWAP _FXQ-BAND-SIZE * + ;

\ _FXQ-COMPUTE-COMMON — Compute w0, sin, cos, alpha from freq, rate, Q
\  Assumes _FXQ-FREQ, _FXQ-Q, and rate are set.
\  ( rate -- )

: _FXQ-COMPUTE-COMMON  ( rate -- )
    \ w0 = 2*pi*freq/rate
    \ = TRIG-2PI * freq / rate   (all FP16 arithmetic)
    _FXQ-FREQ @ INT>FP16             ( rate freq_fp16 )
    TRIG-2PI FP16-MUL                ( rate 2pi*freq )
    SWAP INT>FP16 FP16-DIV           ( w0 )
    _FXQ-W0 !

    \ sin(w0), cos(w0)
    _FXQ-W0 @ TRIG-SINCOS            ( sin cos )
    _FXQ-CS !
    _FXQ-SN !

    \ alpha = sin(w0) / (2*Q)
    _FXQ-SN @
    0x4000 _FXQ-Q @ FP16-MUL         ( sin 2*Q )
    FP16-DIV
    _FXQ-ALPHA ! ;

\ =====================================================================
\  _FXQ-COMPUTE-A — Compute amplitude from gain-dB
\ =====================================================================
\  A ≈ 1 + ln(10)/20 * dB ≈ 1 + 0.1151 * dB
\  0.1151 in FP16 ≈ 0x2F60.  Adequate for ±12 dB range.
\  Clamped to [0.25, 4.0] for FP16 safety.

: _FXQ-COMPUTE-A  ( -- )
    0x2F60 _FXQ-GAIN @ FP16-MUL      ( 0.1151*dB )
    0x3C00 FP16-ADD                   ( 1 + 0.1151*dB )
    0x3400 0x4400 FP16-CLAMP
    _FXQ-A ! ;

\ =====================================================================
\  _FXQ-SET-PEAKING — Compute peaking EQ coefficients
\ =====================================================================
\  Standard RBJ peaking EQ:
\    b0 =  1 + alpha*A
\    b1 = -2*cos(w0)
\    b2 =  1 - alpha*A
\    a0 =  1 + alpha/A
\    a1 = -2*cos(w0)
\    a2 =  1 - alpha/A
\  Normalize all by 1/a0.

: _FXQ-SET-PEAKING  ( band-addr -- )
    _FXQ-BP !

    \ b0 = 1 + alpha*A
    _FXQ-ALPHA @ _FXQ-A @ FP16-MUL   ( alpha*A )
    0x3C00 FP16-ADD                   ( 1 + alpha*A )
    _FXQ-TMP1 !

    \ b2 = 1 - alpha*A
    0x3C00
    _FXQ-ALPHA @ _FXQ-A @ FP16-MUL
    FP16-SUB
    _FXQ-TMP2 !

    \ b1 = a1 = -2*cos(w0)
    0x4000 _FXQ-CS @ FP16-MUL FP16-NEG
    _FXQ-TMP3 !

    \ a0 = 1 + alpha/A
    _FXQ-ALPHA @ _FXQ-A @ FP16-DIV   ( alpha/A )
    0x3C00 FP16-ADD                   ( a0 )
    _FXQ-NORM !

    \ a2 = 1 - alpha/A
    0x3C00
    _FXQ-ALPHA @ _FXQ-A @ FP16-DIV
    FP16-SUB

    \ Normalize: divide all by a0
    _FXQ-NORM @ FP16-RECIP _FXQ-NORM !  \ 1/a0

    _FXQ-TMP1 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B0 !
    _FXQ-TMP3 @ _FXQ-NORM @ FP16-MUL  DUP _FXQ-BP @ _QB.B1 !
                                        _FXQ-BP @ _QB.A1 !
    _FXQ-TMP2 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B2 !
    _FXQ-NORM @ FP16-MUL               _FXQ-BP @ _QB.A2 !

    \ Zero state registers
    0 _FXQ-BP @ _QB.S1 !
    0 _FXQ-BP @ _QB.S2 ! ;

\ =====================================================================
\  _FXQ-SET-LOWSHELF — Compute low shelf coefficients
\ =====================================================================
\  RBJ low shelf:
\    b0 =    A*[ (A+1) - (A-1)*cos + 2*sqrt(A)*alpha ]
\    b1 =  2*A*[ (A-1) - (A+1)*cos                   ]
\    b2 =    A*[ (A+1) - (A-1)*cos - 2*sqrt(A)*alpha ]
\    a0 =        (A+1) + (A-1)*cos + 2*sqrt(A)*alpha
\    a1 =   -2*[ (A-1) + (A+1)*cos                   ]
\    a2 =        (A+1) + (A-1)*cos - 2*sqrt(A)*alpha
\  Simplified for FP16: use moderate precision.

VARIABLE _FXQ-AP1V    \ A+1
VARIABLE _FXQ-AM1V    \ A-1
VARIABLE _FXQ-SQAV    \ 2*sqrt(A)*alpha

: _FXQ-SET-LOWSHELF  ( band-addr -- )
    _FXQ-BP !

    _FXQ-A @ 0x3C00 FP16-ADD _FXQ-AP1V !     \ A+1
    _FXQ-A @ 0x3C00 FP16-SUB _FXQ-AM1V !     \ A-1
    _FXQ-A @ FP16-SQRT
    0x4000 FP16-MUL _FXQ-ALPHA @ FP16-MUL
    _FXQ-SQAV !                                \ 2*sqrt(A)*alpha

    \ b0 = A * [(A+1) - (A-1)*cos + 2*sqrt(A)*alpha]
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-SUB
    _FXQ-SQAV @ FP16-ADD
    _FXQ-A @ FP16-MUL
    _FXQ-TMP1 !

    \ b1 = 2*A * [(A-1) - (A+1)*cos]
    _FXQ-AM1V @
    _FXQ-AP1V @ _FXQ-CS @ FP16-MUL FP16-SUB
    0x4000 FP16-MUL _FXQ-A @ FP16-MUL
    _FXQ-TMP2 !

    \ b2 = A * [(A+1) - (A-1)*cos - 2*sqrt(A)*alpha]
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-SUB
    _FXQ-SQAV @ FP16-SUB
    _FXQ-A @ FP16-MUL
    _FXQ-TMP3 !

    \ a0 = (A+1) + (A-1)*cos + 2*sqrt(A)*alpha
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-ADD
    _FXQ-SQAV @ FP16-ADD
    _FXQ-NORM !

    \ a1 = -2 * [(A-1) + (A+1)*cos]
    _FXQ-AM1V @
    _FXQ-AP1V @ _FXQ-CS @ FP16-MUL FP16-ADD
    0x4000 FP16-MUL FP16-NEG

    \ a2 = (A+1) + (A-1)*cos - 2*sqrt(A)*alpha
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-ADD
    _FXQ-SQAV @ FP16-SUB

    \ Normalize by 1/a0
    _FXQ-NORM @ FP16-RECIP _FXQ-NORM !

    _FXQ-TMP1 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B0 !
    _FXQ-TMP2 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B1 !
    _FXQ-TMP3 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B2 !
    \ a1 is on the stack from above
    SWAP
    _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.A1 !
    _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.A2 !

    0 _FXQ-BP @ _QB.S1 !
    0 _FXQ-BP @ _QB.S2 ! ;

\ =====================================================================
\  _FXQ-SET-HIGHSHELF — Compute high shelf coefficients
\ =====================================================================
\  RBJ high shelf:
\    b0 =    A*[ (A+1) + (A-1)*cos + 2*sqrt(A)*alpha ]
\    b1 = -2*A*[ (A-1) + (A+1)*cos                   ]
\    b2 =    A*[ (A+1) + (A-1)*cos - 2*sqrt(A)*alpha ]
\    a0 =        (A+1) - (A-1)*cos + 2*sqrt(A)*alpha
\    a1 =    2*[ (A-1) - (A+1)*cos                   ]
\    a2 =        (A+1) - (A-1)*cos - 2*sqrt(A)*alpha

: _FXQ-SET-HIGHSHELF  ( band-addr -- )
    _FXQ-BP !

    _FXQ-A @ 0x3C00 FP16-ADD _FXQ-AP1V !
    _FXQ-A @ 0x3C00 FP16-SUB _FXQ-AM1V !
    _FXQ-A @ FP16-SQRT
    0x4000 FP16-MUL _FXQ-ALPHA @ FP16-MUL
    _FXQ-SQAV !

    \ b0 = A * [(A+1) + (A-1)*cos + 2*sqrt(A)*alpha]
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-ADD
    _FXQ-SQAV @ FP16-ADD
    _FXQ-A @ FP16-MUL
    _FXQ-TMP1 !

    \ b1 = -2*A * [(A-1) + (A+1)*cos]
    _FXQ-AM1V @
    _FXQ-AP1V @ _FXQ-CS @ FP16-MUL FP16-ADD
    0x4000 FP16-MUL _FXQ-A @ FP16-MUL FP16-NEG
    _FXQ-TMP2 !

    \ b2 = A * [(A+1) + (A-1)*cos - 2*sqrt(A)*alpha]
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-ADD
    _FXQ-SQAV @ FP16-SUB
    _FXQ-A @ FP16-MUL
    _FXQ-TMP3 !

    \ a0 = (A+1) - (A-1)*cos + 2*sqrt(A)*alpha
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-SUB
    _FXQ-SQAV @ FP16-ADD
    _FXQ-NORM !

    \ a1 = 2 * [(A-1) - (A+1)*cos]
    _FXQ-AM1V @
    _FXQ-AP1V @ _FXQ-CS @ FP16-MUL FP16-SUB
    0x4000 FP16-MUL

    \ a2 = (A+1) - (A-1)*cos - 2*sqrt(A)*alpha
    _FXQ-AP1V @
    _FXQ-AM1V @ _FXQ-CS @ FP16-MUL FP16-SUB
    _FXQ-SQAV @ FP16-SUB

    \ Normalize
    _FXQ-NORM @ FP16-RECIP _FXQ-NORM !

    _FXQ-TMP1 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B0 !
    _FXQ-TMP2 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B1 !
    _FXQ-TMP3 @ _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.B2 !
    SWAP
    _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.A1 !
    _FXQ-NORM @ FP16-MUL  _FXQ-BP @ _QB.A2 !

    0 _FXQ-BP @ _QB.S1 !
    0 _FXQ-BP @ _QB.S2 ! ;

\ =====================================================================
\  FX-EQ-BAND! — Configure band coefficients
\ =====================================================================
\  ( freq gain-db Q band# desc -- )

: FX-EQ-BAND!  ( freq gain-db Q band# desc -- )
    SWAP                               ( freq gain-db Q desc band# )
    OVER _FXQ-BAND-ADDR               ( freq gain-db Q desc band-addr )
    _FXQ-BP !
    FXQ.RATE @                         ( freq gain-db Q rate )
    _FXQ-TMP1 !                        \ rate now in _FXQ-TMP1
    _FXQ-Q !                           ( freq gain-db )
    _FXQ-GAIN !                        ( freq )
    _FXQ-FREQ !                        ( )

    \ Compute common intermediates
    _FXQ-TMP1 @ _FXQ-COMPUTE-COMMON
    _FXQ-COMPUTE-A

    \ Auto-select band type by frequency
    _FXQ-FREQ @ 200 < IF
        _FXQ-BP @ _FXQ-SET-LOWSHELF
    ELSE
        _FXQ-FREQ @ _FXQ-TMP1 @ 4 / > IF
            _FXQ-BP @ _FXQ-SET-HIGHSHELF
        ELSE
            _FXQ-BP @ _FXQ-SET-PEAKING
        THEN
    THEN ;

\ =====================================================================
\  _FXQ-PROCESS-BAND — Process one biquad band (DFII-T) in-place
\ =====================================================================
\  For each sample in the PCM buffer, apply:
\    y = b0*x + s1
\    s1 = b1*x - a1*y + s2
\    s2 = b2*x - a2*y
\  With persistent state per band.
\  ( buf band-addr -- )

VARIABLE _FXQ-BN      \ band address during inner loop

: _FXQ-PROCESS-BAND  ( buf band-addr -- )
    _FXQ-BN !
    _FXQ-BUF !

    _FXQ-BUF @ PCM-LEN 0 DO
        I _FXQ-BUF @ PCM-FRAME@       ( x )
        _FXQ-X !

        \ y = b0*x + s1
        _FXQ-BN @ _QB.B0 @ _FXQ-X @ FP16-MUL
        _FXQ-BN @ _QB.S1 @ FP16-ADD
        _FXQ-Y !

        \ s1 = b1*x - a1*y + s2
        _FXQ-BN @ _QB.B1 @ _FXQ-X @ FP16-MUL
        _FXQ-BN @ _QB.A1 @ _FXQ-Y @ FP16-MUL FP16-SUB
        _FXQ-BN @ _QB.S2 @ FP16-ADD
        _FXQ-BN @ _QB.S1 !

        \ s2 = b2*x - a2*y
        _FXQ-BN @ _QB.B2 @ _FXQ-X @ FP16-MUL
        _FXQ-BN @ _QB.A2 @ _FXQ-Y @ FP16-MUL FP16-SUB
        _FXQ-BN @ _QB.S2 !

        \ Store output
        _FXQ-Y @
        I _FXQ-BUF @ PCM-FRAME!
    LOOP ;

\ =====================================================================
\  FX-EQ-PROCESS — Apply parametric EQ in-place (cascaded biquads)
\ =====================================================================
\  ( buf desc -- )

: FX-EQ-PROCESS  ( buf desc -- )
    _FXQ-DESC !
    _FXQ-BUF !

    _FXQ-DESC @ FXQ.N @ 0 DO
        _FXQ-BUF @
        I _FXQ-DESC @ _FXQ-BAND-ADDR
        _FXQ-PROCESS-BAND
    LOOP ;

\ #####################################################################
\  SECTION 7 — FX-COMP (Compressor / Limiter)
\ #####################################################################
\
\  Dynamics processor with envelope follower.
\
\  Envelope detection: one-pole LP on |sample|, with separate
\  attack and release coefficients for fast transient response
\  and smooth recovery.
\
\    if |x| > level: level ← atk × |x| + (1-atk) × level   (attack)
\    else:           level ← rel × |x| + (1-rel) × level   (release)
\
\  Smoothing coefficient computed from time constant:
\    α = 1 − e^(−1/N)   where N = time_ms × rate / 1000
\  Uses EXP-EXP from exp.f.  Falls back to α ≈ 1/N for
\  long time constants where FP16 cancellation would occur.
\
\  Gain reduction (exact power formula via EXP-POW from exp.f):
\    if level < threshold:  G = 1.0
\    if ratio = 0 (limiter): G = threshold / level
\    else: G = (threshold / level) ^ (1 − 1/ratio)
\
\  Parameters:
\    threshold — FP16, 0.0–1.0 (above this level, gain reduced)
\    ratio     — FP16, 1.0 → no compression, higher → more compression
\                0 = limiter mode (infinite ratio)
\    attack    — integer, attack time in milliseconds
\    release   — integer, release time in milliseconds
\    rate      — integer, sample rate

\ =====================================================================
\  FX-COMP descriptor layout  (7 cells = 56 bytes)
\ =====================================================================
\
\  +0   threshold  FP16
\  +8   slope      FP16  precomputed: 1 - 1/ratio  (1.0 for limiter)
\  +16  atk_coeff  FP16  attack smoothing coefficient
\  +24  rel_coeff  FP16  release smoothing coefficient
\  +32  level      FP16  current envelope level (state)
\  +40  gain       FP16  current applied gain (state)
\  +48  limiter    integer  1 = limiter mode, 0 = compressor

56 CONSTANT FXK-DESC-SIZE

: FXK.THRESH ( d -- addr )  ;
: FXK.SLOPE  ( d -- addr )  8 + ;
: FXK.ATK    ( d -- addr )  16 + ;
: FXK.REL    ( d -- addr )  24 + ;
: FXK.LEVEL  ( d -- addr )  32 + ;
: FXK.GAIN   ( d -- addr )  40 + ;
: FXK.LIM    ( d -- addr )  48 + ;

VARIABLE _FXK-PTR
VARIABLE _FXK-BUF
VARIABLE _FXK-DESC
VARIABLE _FXK-X
VARIABLE _FXK-ABS
VARIABLE _FXK-LVL
VARIABLE _FXK-G
VARIABLE _FXK-TMP1
VARIABLE _FXK-TMP2

\ =====================================================================
\  _FXK-TIME>COEFF — Convert time in ms + rate to one-pole coefficient
\ =====================================================================
\  Exact formula: α = 1 − e^(−1/N) where N = time_ms × rate / 1000.
\  Uses EXP-EXP from exp.f for short/medium time constants.
\  Falls back to α ≈ 1/N for N > 500 (long times) to avoid
\  FP16 catastrophic cancellation in (1.0 − near-1.0).
\  ( time-ms rate -- coeff )

: _FXK-TIME>COEFF  ( time-ms rate -- coeff )
    * 1000 /                           ( samples = N )
    1 MAX
    DUP 500 > IF
        \ Long time: α ≈ 1/N (Taylor approx, <0.1% error)
        INT>FP16 FP16-RECIP
    ELSE
        \ Short/medium: exact α = 1 − e^(−1/N)
        INT>FP16 FP16-RECIP            ( 1/N )
        FP16-NEG EXP-EXP               ( e^(-1/N) )
        0x3C00 SWAP FP16-SUB           ( 1 − e^(-1/N) )
    THEN ;

\ =====================================================================
\  FX-COMP-CREATE — Allocate compressor
\ =====================================================================
\  ( thresh ratio attack release rate -- desc )

: FX-COMP-CREATE  ( thresh ratio attack release rate -- desc )
    _FXK-TMP1 !                        \ save rate

    FXK-DESC-SIZE ALLOCATE
    0<> ABORT" FX-COMP-CREATE: alloc failed"
    _FXK-PTR !                         ( thresh ratio attack release )

    \ Compute release coefficient
    _FXK-TMP1 @ _FXK-TIME>COEFF       ( thresh ratio attack rel_coeff )
    _FXK-PTR @ FXK.REL !              ( thresh ratio attack )

    \ Compute attack coefficient
    _FXK-TMP1 @ _FXK-TIME>COEFF       ( thresh ratio atk_coeff )
    _FXK-PTR @ FXK.ATK !              ( thresh ratio )

    \ Compute slope = 1 - 1/ratio
    \ If ratio = 0 → limiter mode → slope = 1.0
    DUP 0= IF
        DROP
        0x3C00 _FXK-PTR @ FXK.SLOPE !
        1 _FXK-PTR @ FXK.LIM !
    ELSE
        0x3C00 SWAP FP16-DIV          ( 1/ratio )
        0x3C00 SWAP FP16-SUB          ( 1 - 1/ratio )
        _FXK-PTR @ FXK.SLOPE !
        0 _FXK-PTR @ FXK.LIM !
    THEN                               ( thresh )

    _FXK-PTR @ FXK.THRESH !

    \ Init state
    0 _FXK-PTR @ FXK.LEVEL !
    0x3C00 _FXK-PTR @ FXK.GAIN !      \ gain starts at 1.0

    _FXK-PTR @ ;

\ =====================================================================
\  FX-COMP-FREE — Free compressor
\ =====================================================================

: FX-COMP-FREE  ( desc -- )  FREE ;

\ =====================================================================
\  FX-COMP-LIMIT! — Set to limiter mode (ratio = infinity)
\ =====================================================================

: FX-COMP-LIMIT!  ( desc -- )
    DUP 0x3C00 SWAP FXK.SLOPE !       \ slope = 1.0
    1 SWAP FXK.LIM ! ;

\ =====================================================================
\  FX-COMP-PROCESS — Apply compression in-place
\ =====================================================================
\  ( buf desc -- )

: FX-COMP-PROCESS  ( buf desc -- )
    _FXK-DESC !
    _FXK-BUF !

    _FXK-BUF @ PCM-LEN 0 DO
        \ Read input
        I _FXK-BUF @ PCM-FRAME@
        _FXK-X !
        _FXK-X @ FP16-ABS _FXK-ABS !

        \ Envelope follower: one-pole LP on |sample|
        _FXK-DESC @ FXK.LEVEL @ _FXK-LVL !

        _FXK-ABS @  _FXK-LVL @  FP16-GT IF
            \ Attack: level rising
            _FXK-DESC @ FXK.ATK @          ( atk )
            DUP _FXK-ABS @ FP16-MUL       ( atk  atk*|x| )
            SWAP 0x3C00 SWAP FP16-SUB     ( atk*|x|  1-atk )
            _FXK-LVL @ FP16-MUL           ( atk*|x|  (1-a)*lvl )
            FP16-ADD
        ELSE
            \ Release: level falling
            _FXK-DESC @ FXK.REL @          ( rel )
            DUP _FXK-ABS @ FP16-MUL       ( rel  rel*|x| )
            SWAP 0x3C00 SWAP FP16-SUB     ( rel*|x|  1-rel )
            _FXK-LVL @ FP16-MUL           ( rel*|x|  (1-r)*lvl )
            FP16-ADD
        THEN
        DUP _FXK-DESC @ FXK.LEVEL !
        _FXK-LVL !                         \ updated level

        \ Compute gain
        _FXK-LVL @ _FXK-DESC @ FXK.THRESH @ FP16-GT IF
            \ Level exceeds threshold — reduce gain
            _FXK-DESC @ FXK.LIM @ IF
                \ Limiter: G = threshold / level
                _FXK-DESC @ FXK.THRESH @
                _FXK-LVL @ FP16-DIV
            ELSE
                \ Compressor: G = (thresh/level) ^ slope
                \ where slope = 1 − 1/ratio (precomputed)
                _FXK-DESC @ FXK.THRESH @
                _FXK-LVL @ FP16-DIV       ( thresh/level )
                _FXK-DESC @ FXK.SLOPE @   ( thresh/level slope )
                EXP-POW                    ( (t/l)^slope )
            THEN
            \ Clamp gain to [0, 1]
            0 0x3C00 FP16-CLAMP
        ELSE
            0x3C00                          \ below threshold: G = 1.0
        THEN
        _FXK-G !

        \ Apply gain
        _FXK-X @ _FXK-G @ FP16-MUL

        I _FXK-BUF @ PCM-FRAME!
    LOOP ;