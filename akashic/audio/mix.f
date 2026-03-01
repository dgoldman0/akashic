\ mix.f — N-channel audio mixer
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Mixes up to 16 mono input channels to a stereo master output
\ buffer.  Each channel has gain, pan, and mute controls.
\ Uses equal-power panning via TRIG-SINCOS.
\
\ Data is FP16 bit patterns in 16-bit PCM buffers.
\ Non-reentrant (uses VARIABLE scratch).
\
\ Prefix: MIX-     (public API)
\         _MIX-    (internal helpers)
\
\ Load with:   REQUIRE audio/mix.f
\
\ === Public API ===
\   MIX-CREATE        ( n-chans frames rate -- mix )
\   MIX-FREE          ( mix -- )
\   MIX-GAIN!         ( gain chan# mix -- )
\   MIX-PAN!          ( pan chan# mix -- )
\   MIX-MUTE!         ( flag chan# mix -- )
\   MIX-MASTER-GAIN!  ( gain mix -- )
\   MIX-INPUT!        ( buf chan# mix -- )
\   MIX-RENDER        ( mix -- )
\   MIX-MASTER        ( mix -- buf )

REQUIRE audio/pcm.f
REQUIRE ../math/trig.f

PROVIDED akashic-audio-mix

\ #####################################################################
\  Mixer descriptor layout  (4 cells = 32 bytes)
\ #####################################################################
\
\  +0   n-chans      integer  (1–16)
\  +8   master-gain  FP16
\  +16  master-buf   pointer to stereo PCM buffer
\  +24  chans        pointer to channel descriptor array

32 CONSTANT MIX-DESC-SIZE

: MIX.NCHANS     ( m -- addr )  ;
: MIX.MGAIN      ( m -- addr )  8 + ;
: MIX.MBUF       ( m -- addr )  16 + ;
: MIX.CHANS      ( m -- addr )  24 + ;

\ #####################################################################
\  Channel descriptor layout  (4 cells = 32 bytes per channel)
\ #####################################################################
\
\  +0   gain    FP16  channel gain (0.0–1.0)
\  +8   pan     FP16  pan position (−1.0 left, 0.0 center, +1.0 right)
\  +16  mute    integer (0 = active, 1 = muted)
\  +24  buf     pointer to input PCM buffer (mono)

32 CONSTANT MIX-CHAN-SIZE

: _MIX-CHAN-ADDR  ( chan# mix -- addr )
    MIX.CHANS @ SWAP MIX-CHAN-SIZE * + ;

: MIXC.GAIN  ( ch -- addr )  ;
: MIXC.PAN   ( ch -- addr )  8 + ;
: MIXC.MUTE  ( ch -- addr )  16 + ;
: MIXC.BUF   ( ch -- addr )  24 + ;

\ #####################################################################
\  Scratch variables
\ #####################################################################

VARIABLE _MIX-PTR
VARIABLE _MIX-TMP
VARIABLE _MIX-MIX
VARIABLE _MIX-I
VARIABLE _MIX-CH
VARIABLE _MIX-LGAIN
VARIABLE _MIX-RGAIN
VARIABLE _MIX-SAMP
VARIABLE _MIX-L
VARIABLE _MIX-R

\ #####################################################################
\  MIX-CREATE — Allocate mixer
\ #####################################################################
\  ( n-chans frames rate -- mix )
\
\  Allocates: mixer descriptor (32 bytes), channel array
\  (n-chans * 32 bytes), and a stereo master PCM buffer.

: MIX-CREATE  ( n-chans frames rate -- mix )
    _MIX-TMP !                         \ save rate
    SWAP _MIX-I !                      \ save n-chans  ( frames )

    \ Allocate master buffer: stereo, 16-bit
    _MIX-TMP @ 16 2                    ( frames rate 16 2 )
    PCM-ALLOC                          ( master-buf )

    \ Allocate mixer descriptor
    MIX-DESC-SIZE ALLOCATE
    0<> ABORT" MIX-CREATE: alloc failed"
    _MIX-PTR !                         ( master-buf )

    _MIX-I @ _MIX-PTR @ MIX.NCHANS !  \ store n-chans
    0x3C00 _MIX-PTR @ MIX.MGAIN !     \ default master gain = 1.0

    _MIX-PTR @ MIX.MBUF !             \ store master buf ptr

    \ Allocate channel array: n-chans * 32 bytes
    _MIX-I @ MIX-CHAN-SIZE * ALLOCATE
    0<> ABORT" MIX-CREATE: chan alloc failed"
    _MIX-PTR @ MIX.CHANS !

    \ Initialize each channel: gain=1.0, pan=0.0 (center), mute=0, buf=0
    _MIX-I @ 0 DO
        I _MIX-PTR @ _MIX-CHAN-ADDR   ( chan-addr )
        DUP 0x3C00 SWAP MIXC.GAIN !   \ gain = 1.0
        DUP 0      SWAP MIXC.PAN !    \ pan = 0.0 (center)
        DUP 0      SWAP MIXC.MUTE !   \ active
        0          SWAP MIXC.BUF !     \ no input assigned
    LOOP

    _MIX-PTR @ ;

\ #####################################################################
\  MIX-FREE — Free mixer + master buffer
\ #####################################################################

: MIX-FREE  ( mix -- )
    DUP MIX.CHANS @ FREE               \ free channel array
    DUP MIX.MBUF @ PCM-FREE            \ free master buffer
    FREE ;                             \ free descriptor

\ #####################################################################
\  Channel setters
\ #####################################################################

: MIX-GAIN!  ( gain chan# mix -- )
    _MIX-CHAN-ADDR MIXC.GAIN ! ;

: MIX-PAN!  ( pan chan# mix -- )
    _MIX-CHAN-ADDR MIXC.PAN ! ;

: MIX-MUTE!  ( flag chan# mix -- )
    _MIX-CHAN-ADDR MIXC.MUTE ! ;

: MIX-INPUT!  ( buf chan# mix -- )
    _MIX-CHAN-ADDR MIXC.BUF ! ;

: MIX-MASTER-GAIN!  ( gain mix -- )
    MIX.MGAIN ! ;

: MIX-MASTER  ( mix -- buf )
    MIX.MBUF @ ;

\ #####################################################################
\  _MIX-PAN-GAINS — Compute equal-power L/R gains from pan
\ #####################################################################
\  Pan law: L = cos(π/4 × (1 + pan)), R = sin(π/4 × (1 + pan))
\  pan = −1.0 → angle=0     → L=1, R=0  (hard left)
\  pan =  0.0 → angle=π/4   → L≈0.707, R≈0.707  (center)
\  pan = +1.0 → angle=π/2   → L=0, R=1  (hard right)
\
\  ( pan -- L-gain R-gain )

: _MIX-PAN-GAINS  ( pan -- L R )
    0x3C00 FP16-ADD                    ( 1 + pan )
    0x3A48 FP16-MUL                    ( π/4 × (1+pan) )
    TRIG-SINCOS                        ( sin cos )
    SWAP ;                             ( cos sin → L R )

\ #####################################################################
\  MIX-RENDER — Sum all active channels to stereo master
\ #####################################################################
\  For each non-muted channel with a non-NULL input buffer:
\    1. Compute pan L/R gains
\    2. Multiply gain × pan_gain to get effective L/R gains
\    3. For each frame: read mono sample, scale, accumulate to stereo master
\
\  The master buffer is cleared first.

: MIX-RENDER  ( mix -- )
    _MIX-MIX !

    \ Clear master buffer
    _MIX-MIX @ MIX.MBUF @ PCM-CLEAR

    \ For each channel
    _MIX-MIX @ MIX.NCHANS @ 0 DO
        I _MIX-MIX @ _MIX-CHAN-ADDR _MIX-CH !

        \ Skip muted channels and channels with no input buffer
        _MIX-CH @ MIXC.MUTE @ 0= IF
        _MIX-CH @ MIXC.BUF @ 0<> IF
                \ Compute effective L/R gains
                _MIX-CH @ MIXC.PAN @
                _MIX-PAN-GAINS              ( L R )
                _MIX-CH @ MIXC.GAIN @       ( L R gain )
                DUP ROT FP16-MUL            ( L gain R*gain )
                _MIX-RGAIN !                ( L gain )
                FP16-MUL                    ( L*gain )
                _MIX-LGAIN !

                \ Determine frame count: min of input len and master len
                _MIX-CH @ MIXC.BUF @ PCM-LEN
                _MIX-MIX @ MIX.MBUF @ PCM-LEN
                MIN                          ( frames )

                \ Accumulate samples
                0 DO
                    \ Read mono input sample
                    I _MIX-CH @ MIXC.BUF @ PCM-FRAME@
                    _MIX-SAMP !

                    \ Left channel: master[i,0] += sample * L-gain
                    I 0 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE@
                    _MIX-SAMP @ _MIX-LGAIN @ FP16-MUL
                    FP16-ADD
                    I 0 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE!

                    \ Right channel: master[i,1] += sample * R-gain
                    I 1 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE@
                    _MIX-SAMP @ _MIX-RGAIN @ FP16-MUL
                    FP16-ADD
                    I 1 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE!
                LOOP
        THEN THEN
    LOOP

    \ Apply master gain
    _MIX-MIX @ MIX.MGAIN @             ( mgain )
    DUP 0x3C00 = IF
        \ Master gain is 1.0 — nothing to do
        DROP
    ELSE
        \ Scale all stereo samples by master gain
        _MIX-MIX @ MIX.MBUF @ PCM-LEN 0 DO
            \ Left
            I 0 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE@
            OVER FP16-MUL
            I 0 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE!
            \ Right
            I 1 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE@
            OVER FP16-MUL
            I 1 _MIX-MIX @ MIX.MBUF @ PCM-SAMPLE!
        LOOP
        DROP
    THEN ;
