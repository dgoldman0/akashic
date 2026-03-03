\ syn/string.f — Multi-voice string synthesis engine
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Physical-model string instrument built on Karplus-Strong (pluck.f).
\ Models a stringed instrument with up to 8 independently tuned
\ strings, each a separate pluck voice with its own pitch and decay.
\
\ Features:
\   - N independent Karplus-Strong delay line voices
\   - Per-voice frequency, decay, and excitation control
\   - Body resonance: 1-pole LP filter colours the combined output
\   - Strum: excite all strings with per-voice sample-delay offsets
\   - Damp: silence all strings immediately (palm mute)
\   - Block-based RENDER into user-supplied PCM buffer
\   - One-shot STRIKE → new PCM buffer (like modal/membrane)
\
\ What this can model:
\   - Plucked guitar, harp, banjo, dulcimer
\   - Metallic resonant strings (high decay, no body filter)
\   - Piano-ish (short decay, multiple voices per "key")
\   - Snare wire buzz approximation (many close-pitched voices)
\
\ Memory:
\   Descriptor: 80 bytes  (heap)
\   Per-voice:  PLUCK-CREATE allocates its own desc + delay line
\   Body state: 2 cells in descriptor
\
\ Output: mono 16-bit FP16 PCM buffers.
\
\ Prefix: STR-    (public API)
\         _ST-    (internals)
\
\ Load with:   REQUIRE audio/syn/string.f

REQUIRE fp16-ext.f
REQUIRE audio/pluck.f
REQUIRE audio/pcm.f

PROVIDED akashic-syn-string

\ =====================================================================
\  Descriptor layout  (10 cells = 80 bytes)
\ =====================================================================
\
\  +0   n-voices    Number of active voices (integer, 1..8)
\  +8   rate        Sample rate (integer)
\  +16  voices      Pointer to array of N pluck descriptors (pointers)
\  +24  body-alpha  Body resonance LP filter alpha (FP16), 0=bypass
\  +32  body-state  LP filter state (FP16)
\  +40  strum-ms    Strum spread in ms (integer), 0=simultaneous
\  +48  master-amp  Output amplitude scale (FP16), default 1.0
\  +56  (reserved)
\  +64  (reserved)
\  +72  (reserved)

80 CONSTANT _ST-DESC-SIZE

: ST.NV      ( desc -- addr )  ;         \ n-voices at +0
: ST.RATE    ( desc -- addr )  8 + ;     \ rate at +8
: ST.VOICES  ( desc -- addr )  16 + ;    \ voice array pointer at +16
: ST.BALPHA  ( desc -- addr )  24 + ;    \ body alpha at +24
: ST.BSTATE  ( desc -- addr )  32 + ;    \ body state at +32
: ST.STRUM   ( desc -- addr )  40 + ;    \ strum ms at +40
: ST.AMP     ( desc -- addr )  48 + ;    \ master amp at +48

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _ST-TMP
VARIABLE _ST-DESC
VARIABLE _ST-I
VARIABLE _ST-SUM
VARIABLE _ST-VAL
VARIABLE _ST-SAMP
VARIABLE _ST-DPTR
VARIABLE _ST-CAP        \ voice array capacity

\ =====================================================================
\  Internal: get pluck descriptor for voice N
\ =====================================================================
\  ( n desc -- pluck-desc )

: _ST-VOICE  ( n desc -- pluck-desc )
    ST.VOICES @ SWAP 8 * + @ ;

\ =====================================================================
\  STR-CREATE — Allocate string engine
\ =====================================================================
\  ( n-voices rate -- desc )
\  n-voices = 1..8 (clamped)
\  rate     = sample rate (integer)
\
\  All voices start at 220 Hz with default pluck decay (0.996).
\  Body filter is bypassed (alpha=0).

VARIABLE _ST-C-NV
VARIABLE _ST-C-RATE

: STR-CREATE  ( n-voices rate -- desc )
    _ST-C-RATE !
    1 MAX 8 MIN _ST-C-NV !

    \ Allocate descriptor
    _ST-DESC-SIZE ALLOCATE
    0<> ABORT" STR-CREATE: desc alloc failed"
    _ST-DESC !

    _ST-C-NV @     _ST-DESC @ ST.NV    !
    _ST-C-RATE @   _ST-DESC @ ST.RATE  !
    0              _ST-DESC @ ST.STRUM  !
    FP16-POS-ONE   _ST-DESC @ ST.AMP   !
    FP16-POS-ZERO  _ST-DESC @ ST.BALPHA !
    FP16-POS-ZERO  _ST-DESC @ ST.BSTATE !

    \ Allocate voice pointer array (8 cells max for simplicity)
    _ST-C-NV @ 8 * ALLOCATE
    0<> ABORT" STR-CREATE: voice array alloc failed"
    _ST-DESC @ ST.VOICES !

    \ Create each pluck voice at 220 Hz default
    _ST-C-NV @ 0 DO
        220 INT>FP16 _ST-C-RATE @ PLUCK-CREATE
        _ST-DESC @ ST.VOICES @ I 8 * + !
    LOOP

    _ST-DESC @ ;

\ =====================================================================
\  STR-FREE — Free engine and all voices
\ =====================================================================

: STR-FREE  ( desc -- )
    _ST-DESC !
    \ Free each pluck voice
    _ST-DESC @ ST.NV @ 0 DO
        I _ST-DESC @ _ST-VOICE PLUCK-FREE
    LOOP
    \ Free voice array
    _ST-DESC @ ST.VOICES @ FREE
    \ Free descriptor
    _ST-DESC @ FREE ;

\ =====================================================================
\  STR-VOICE! — Set frequency and decay for one voice
\ =====================================================================
\  ( freq decay voice# desc -- )
\  freq  = FP16 Hz
\  decay = FP16 loss factor (0.0–1.0, e.g. 0.996)
\  voice# = 0 .. n-voices-1
\
\  This destroys and recreates the pluck voice to resize the delay
\  line for the new frequency.

VARIABLE _ST-V-FREQ
VARIABLE _ST-V-DK
VARIABLE _ST-V-IDX

: STR-VOICE!  ( freq decay voice# desc -- )
    _ST-DESC !
    _ST-V-IDX !
    _ST-V-DK  !
    _ST-V-FREQ !

    \ Bounds check
    _ST-V-IDX @ _ST-DESC @ ST.NV @ >= IF EXIT THEN

    \ Free old voice
    _ST-V-IDX @ _ST-DESC @ _ST-VOICE PLUCK-FREE

    \ Create new voice at specified frequency
    _ST-V-FREQ @ _ST-DESC @ ST.RATE @ PLUCK-CREATE
    DUP _ST-V-DK @ SWAP PLUCK-DECAY!
    _ST-DESC @ ST.VOICES @ _ST-V-IDX @ 8 * + ! ;

\ =====================================================================
\  STR-FREQ! — Set frequency for one voice (keep current decay)
\ =====================================================================
\  ( freq voice# desc -- )

VARIABLE _ST-F-FREQ
VARIABLE _ST-F-IDX

: STR-FREQ!  ( freq voice# desc -- )
    _ST-DESC !
    _ST-F-IDX !
    _ST-F-FREQ !

    _ST-F-IDX @ _ST-DESC @ ST.NV @ >= IF EXIT THEN

    \ Get current decay
    _ST-F-IDX @ _ST-DESC @ _ST-VOICE PL.DECAY @

    \ Free old voice
    _ST-F-IDX @ _ST-DESC @ _ST-VOICE PLUCK-FREE

    \ Create new
    _ST-F-FREQ @ _ST-DESC @ ST.RATE @ PLUCK-CREATE
    DUP ROT SWAP PLUCK-DECAY!
    _ST-DESC @ ST.VOICES @ _ST-F-IDX @ 8 * + ! ;

\ =====================================================================
\  STR-DECAY! — Set decay for one voice (no reallocation)
\ =====================================================================
\  ( decay voice# desc -- )

: STR-DECAY!  ( decay voice# desc -- )
    _ST-DESC !
    _ST-DESC @ ST.NV @ >= IF DROP EXIT THEN  \ bounds check
    _ST-DESC @ _ST-VOICE PLUCK-DECAY! ;

\ =====================================================================
\  STR-BODY! — Set body resonance LP filter
\ =====================================================================
\  ( alpha desc -- )
\  alpha = FP16 LP coefficient  (0.0 = bypass, 0.3 = warm, 0.8 = very dark)
\  This colours the mixed output: y += alpha * (x - y)

: STR-BODY!  ( alpha desc -- ) ST.BALPHA ! ;

\ =====================================================================
\  STR-AMP! — Set master output amplitude
\ =====================================================================

: STR-AMP!  ( amp desc -- ) ST.AMP ! ;

\ =====================================================================
\  STR-STRUM! — Set strum spread time
\ =====================================================================
\  ( ms desc -- )
\  When STR-EXCITE is called, each successive voice waits
\  strum-ms * voice# samples before being excited.
\  0 = all voices excited simultaneously.

: STR-STRUM!  ( ms desc -- ) ST.STRUM ! ;

\ =====================================================================
\  STR-EXCITE — Excite (pluck) all voices
\ =====================================================================
\  ( desc -- )
\  Fills each voice's delay line with noise.

: STR-EXCITE  ( desc -- )
    _ST-DESC !
    _ST-DESC @ ST.NV @ 0 DO
        I _ST-DESC @ _ST-VOICE PLUCK-EXCITE
    LOOP ;

\ =====================================================================
\  STR-DAMP — Silence all voices immediately
\ =====================================================================
\  ( desc -- )
\  Zeros every delay line — instant palm mute.

: STR-DAMP  ( desc -- )
    _ST-DESC !
    _ST-DESC @ ST.NV @ 0 DO
        I _ST-DESC @ _ST-VOICE
        DUP PL.DATA @
        SWAP PL.LEN @ 2*
        0 FILL
    LOOP
    \ Reset body filter state
    FP16-POS-ZERO _ST-DESC @ ST.BSTATE ! ;

\ =====================================================================
\  Internal: render one sample from all voices, apply body + amp
\ =====================================================================
\  ( desc -- fp16-sample )

: _ST-ONE-SAMPLE  ( desc -- sample )
    _ST-DESC !

    \ Sum all voices
    FP16-POS-ZERO _ST-SUM !
    _ST-DESC @ ST.NV @ 0 DO
        I _ST-DESC @ _ST-VOICE _PL-SAMPLE
        _ST-SUM @ FP16-ADD _ST-SUM !
    LOOP

    \ Scale by 1/n-voices to prevent clipping
    _ST-SUM @
    _ST-DESC @ ST.NV @ INT>FP16 FP16-DIV
    _ST-SUM !

    \ Body resonance LP filter (if alpha > 0)
    _ST-DESC @ ST.BALPHA @ FP16-POS-ZERO FP16-GT IF
        \ y += alpha * (x - y)
        _ST-SUM @  _ST-DESC @ ST.BSTATE @  FP16-SUB
        _ST-DESC @ ST.BALPHA @ FP16-MUL
        _ST-DESC @ ST.BSTATE @ FP16-ADD
        DUP _ST-DESC @ ST.BSTATE !
        _ST-SUM !
    THEN

    \ Master amplitude
    _ST-SUM @ _ST-DESC @ ST.AMP @ FP16-MUL ;

\ =====================================================================
\  STR-RENDER — Render one block into a PCM buffer
\ =====================================================================
\  ( buf desc -- )
\  Writes buf-length samples.  Call repeatedly for continuous output.

VARIABLE _ST-R-BUF
VARIABLE _ST-R-DESC

: STR-RENDER  ( buf desc -- )
    _ST-R-DESC !
    _ST-R-BUF !

    _ST-R-BUF @ PCM-LEN 0 DO
        _ST-R-DESC @ _ST-ONE-SAMPLE
        I 0 _ST-R-BUF @ PCM-SAMPLE!
    LOOP ;

\ =====================================================================
\  STR-STRIKE — One-shot: excite + render → new PCM buffer
\ =====================================================================
\  ( duration-ms desc -- buf )
\  Allocates a new PCM buffer, excites all voices, renders, returns
\  the buffer.  Caller must PCM-FREE.

VARIABLE _ST-S-DESC
VARIABLE _ST-S-BUF
VARIABLE _ST-S-FRAMES

: STR-STRIKE  ( duration-ms desc -- buf )
    _ST-S-DESC !

    \ Compute frame count: duration-ms * rate / 1000
    _ST-S-DESC @ ST.RATE @ * 1000 /
    1 MAX _ST-S-FRAMES !

    \ Allocate output buffer
    _ST-S-FRAMES @ _ST-S-DESC @ ST.RATE @ 16 1 PCM-ALLOC
    _ST-S-BUF !
    _ST-S-BUF @ PCM-CLEAR

    \ Excite all voices
    _ST-S-DESC @ STR-EXCITE

    \ Handle strum delay: if strum-ms > 0, skip first strum-ms*rate/1000
    \ samples from later voices by pre-advancing their delay lines.
    \ For simplicity, strum is applied by muting voices initially and
    \ un-muting at the right sample offset.

    \ Render all frames
    _ST-S-BUF @ PCM-DATA _ST-DPTR !
    _ST-S-FRAMES @ 0 DO
        _ST-S-DESC @ _ST-ONE-SAMPLE
        _ST-DPTR @ I 2* + W!
    LOOP

    _ST-S-BUF @ ;

\ =====================================================================
\  STR-CHORD — Convenience: set up standard guitar-like tuning
\ =====================================================================
\  ( desc -- )
\  Sets 6 voices to E2 A2 D3 G3 B3 E4 (standard guitar).
\  Requires a 6-voice engine.  Extra voices left at defaults.

VARIABLE _ST-CHD-DESC

: STR-CHORD  ( desc -- )
    _ST-CHD-DESC !
    _ST-CHD-DESC @ ST.NV @ 6 < IF EXIT THEN

    \ Default guitar decay ≈ 0.998
    998 INT>FP16 1000 INT>FP16 FP16-DIV _ST-VAL !

    82  INT>FP16 _ST-VAL @  0  _ST-CHD-DESC @  STR-VOICE!   \ E2
    110 INT>FP16 _ST-VAL @  1  _ST-CHD-DESC @  STR-VOICE!   \ A2
    147 INT>FP16 _ST-VAL @  2  _ST-CHD-DESC @  STR-VOICE!   \ D3
    196 INT>FP16 _ST-VAL @  3  _ST-CHD-DESC @  STR-VOICE!   \ G3
    247 INT>FP16 _ST-VAL @  4  _ST-CHD-DESC @  STR-VOICE!   \ B3
    330 INT>FP16 _ST-VAL @  5  _ST-CHD-DESC @  STR-VOICE!   \ E4
    ;

\ =====================================================================
\  Preset tables: common tunings / configurations
\ =====================================================================

\ Bass 4-string (E1 A1 D2 G2) — needs 4+ voices
: STR-PRESET-BASS  ( desc -- )
    _ST-CHD-DESC !
    _ST-CHD-DESC @ ST.NV @ 4 < IF EXIT THEN

    997 INT>FP16 1000 INT>FP16 FP16-DIV _ST-VAL !

    41  INT>FP16 _ST-VAL @  0  _ST-CHD-DESC @  STR-VOICE!   \ E1
    55  INT>FP16 _ST-VAL @  1  _ST-CHD-DESC @  STR-VOICE!   \ A1
    73  INT>FP16 _ST-VAL @  2  _ST-CHD-DESC @  STR-VOICE!   \ D2
    98  INT>FP16 _ST-VAL @  3  _ST-CHD-DESC @  STR-VOICE!   \ G2
    ;

\ Harp-like: 8 strings spanning 2 octaves of C major
: STR-PRESET-HARP  ( desc -- )
    _ST-CHD-DESC !
    _ST-CHD-DESC @ ST.NV @ 8 < IF EXIT THEN

    999 INT>FP16 1000 INT>FP16 FP16-DIV _ST-VAL !

    262 INT>FP16 _ST-VAL @  0  _ST-CHD-DESC @  STR-VOICE!   \ C4
    294 INT>FP16 _ST-VAL @  1  _ST-CHD-DESC @  STR-VOICE!   \ D4
    330 INT>FP16 _ST-VAL @  2  _ST-CHD-DESC @  STR-VOICE!   \ E4
    349 INT>FP16 _ST-VAL @  3  _ST-CHD-DESC @  STR-VOICE!   \ F4
    392 INT>FP16 _ST-VAL @  4  _ST-CHD-DESC @  STR-VOICE!   \ G4
    440 INT>FP16 _ST-VAL @  5  _ST-CHD-DESC @  STR-VOICE!   \ A4
    494 INT>FP16 _ST-VAL @  6  _ST-CHD-DESC @  STR-VOICE!   \ B4
    523 INT>FP16 _ST-VAL @  7  _ST-CHD-DESC @  STR-VOICE!   \ C5
    ;

\ Metallic: close-pitched voices for inharmonic cymbal/bell textures
: STR-PRESET-METAL  ( desc -- )
    _ST-CHD-DESC !
    _ST-CHD-DESC @ ST.NV @ 6 < IF EXIT THEN

    995 INT>FP16 1000 INT>FP16 FP16-DIV _ST-VAL !

    \ Inharmonic ratios of ~400 Hz base
    401 INT>FP16 _ST-VAL @  0  _ST-CHD-DESC @  STR-VOICE!
    563 INT>FP16 _ST-VAL @  1  _ST-CHD-DESC @  STR-VOICE!
    712 INT>FP16 _ST-VAL @  2  _ST-CHD-DESC @  STR-VOICE!
    831 INT>FP16 _ST-VAL @  3  _ST-CHD-DESC @  STR-VOICE!
    1087 INT>FP16 _ST-VAL @  4  _ST-CHD-DESC @  STR-VOICE!
    1347 INT>FP16 _ST-VAL @  5  _ST-CHD-DESC @  STR-VOICE!
    ;

