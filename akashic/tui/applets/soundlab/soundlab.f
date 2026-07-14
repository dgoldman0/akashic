\ =====================================================================
\  soundlab.f - Signal renderer, analyzer, playback, and WAV workbench
\ =====================================================================
\  Sound Lab renders a bounded mono FP16 signal, analyzes the exact PCM,
\  visualizes it in the TUI, atomically publishes /soundlab.wav, and can
\  submit the current render through Akashic's public AudioOut boundary.
\
\  Entry: SOUNDLAB-ENTRY ( desc -- )  for Desk
\         SOUNDLAB-RUN   ( -- )       standalone
\ =====================================================================

PROVIDED akashic-tui-soundlab

REQUIRE ../../widgets/prompt.f
REQUIRE ../../widgets/dialog.f
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widget.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/fs/vfs-replace.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/capability.f
REQUIRE ../../../interop/endpoint.f
REQUIRE ../../../interop/intent.f
REQUIRE ../../../interop/resource.f
REQUIRE ../../../audio/osc.f
REQUIRE ../../../audio/wav.f
REQUIRE ../../../audio/analysis/metrics.f
REQUIRE ../../../audio/analysis/spectral.f
REQUIRE ../../../audio/output.f

\ ---------------------------------------------------------------------
\ Bounded signal contract
\ ---------------------------------------------------------------------

8000 CONSTANT _SL-RATE
40   CONSTANT _SL-FREQ-MIN
2000 CONSTANT _SL-FREQ-MAX
100  CONSTANT _SL-DURATION-MIN
2000 CONSTANT _SL-DURATION-MAX
0    CONSTANT _SL-AMP-MIN
100  CONSTANT _SL-AMP-MAX
16000 CONSTANT _SL-MAX-FRAMES
32044 CONSTANT _SL-WAV-CAP       \ 44-byte header + 16,000 mono s16 frames
5000 CONSTANT _SL-PLAY-TIMEOUT-MS
768  CONSTANT _SL-SUMMARY-CAP
256  CONSTANT _SL-LINE-CAP
64   CONSTANT _SL-PROMPT-CAP

-1 CONSTANT _SL-PLAY-S-NEVER

0 CONSTANT _SL-PM-NONE
1 CONSTANT _SL-PM-FREQUENCY
2 CONSTANT _SL-PM-AMPLITUDE
3 CONSTANT _SL-PM-DURATION

0 CONSTANT _SL-SEL-SHAPE
1 CONSTANT _SL-SEL-FREQUENCY
2 CONSTANT _SL-SEL-AMPLITUDE
3 CONSTANT _SL-SEL-DURATION
4 CONSTANT _SL-SEL-COUNT

\ ---------------------------------------------------------------------
\ Per-instance state
\ ---------------------------------------------------------------------

VARIABLE _SL-CURRENT-STATE
VARIABLE _SL-CURRENT-INSTANCE
0 _SL-CURRENT-STATE !
0 _SL-CURRENT-INSTANCE !
CMP-LAYOUT-BEGIN

_SL-CURRENT-STATE CMP-CELL: _SL-E-BODY
_SL-CURRENT-STATE CMP-CELL: _SL-E-SBAR
_SL-CURRENT-STATE CMP-CELL: _SL-E-SBAR-SIGNAL
_SL-CURRENT-STATE CMP-CELL: _SL-E-SBAR-STATE
_SL-CURRENT-STATE CMP-CELL: _SL-E-SBAR-PLAYBACK

_SL-CURRENT-STATE 40 CMP-FIELD: _SL-PANEL
_SL-CURRENT-STATE CMP-CELL: _SL-PANEL-RGN
_SL-CURRENT-STATE CMP-CELL: _SL-PROMPT
_SL-CURRENT-STATE CMP-CELL: _SL-PROMPT-RGN
_SL-CURRENT-STATE CMP-CELL: _SL-PROMPT-MODE
_SL-CURRENT-STATE _SL-PROMPT-CAP CMP-FIELD: _SL-PROMPT-BUF

_SL-CURRENT-STATE CMP-CELL: _SL-SHAPE
_SL-CURRENT-STATE CMP-CELL: _SL-FREQUENCY
_SL-CURRENT-STATE CMP-CELL: _SL-AMPLITUDE
_SL-CURRENT-STATE CMP-CELL: _SL-DURATION
_SL-CURRENT-STATE CMP-CELL: _SL-SELECTED

_SL-CURRENT-STATE CMP-CELL: _SL-PCM
_SL-CURRENT-STATE CMP-CELL: _SL-RENDER-VALID
_SL-CURRENT-STATE CMP-CELL: _SL-UNSAVED
_SL-CURRENT-STATE CMP-CELL: _SL-LAST-ERROR
_SL-CURRENT-STATE CMP-CELL: _SL-LAST-PLAY-STATUS
_SL-CURRENT-STATE CMP-CELL: _SL-LAST-PLAY-ERROR
_SL-CURRENT-STATE CMP-CELL: _SL-LAST-PLAY-GENERATION
_SL-CURRENT-STATE CMP-CELL: _SL-PLAY-GEN-BEFORE
_SL-CURRENT-STATE CMP-CELL: _SL-PLAY-OWNED
_SL-CURRENT-STATE CMP-CELL: _SL-OWNED-GENERATION

_SL-CURRENT-STATE CMP-CELL: _SL-M-PEAK
_SL-CURRENT-STATE CMP-CELL: _SL-M-PEAK-FRAME
_SL-CURRENT-STATE CMP-CELL: _SL-M-RMS
_SL-CURRENT-STATE CMP-CELL: _SL-M-DC
_SL-CURRENT-STATE CMP-CELL: _SL-M-ZC
_SL-CURRENT-STATE CMP-CELL: _SL-M-CLIPS
_SL-CURRENT-STATE CMP-CELL: _SL-M-PITCH
_SL-CURRENT-STATE CMP-CELL: _SL-M-CENTROID

_SL-CURRENT-STATE CMP-CELL: _SL-VFS
_SL-CURRENT-STATE VREPL-SIZE CMP-FIELD: _SL-REPLACE
_SL-CURRENT-STATE CMP-CELL: _SL-OUTPUT-BLOCKED
_SL-CURRENT-STATE CMP-CELL: _SL-SAVED-ONCE
_SL-CURRENT-STATE CMP-CELL: _SL-WAV-BUF

_SL-CURRENT-STATE _SL-SUMMARY-CAP CMP-FIELD: _SL-SUMMARY-BUF
_SL-CURRENT-STATE CMP-CELL: _SL-SUMMARY-U
_SL-CURRENT-STATE _SL-LINE-CAP CMP-FIELD: _SL-LINE-BUF
_SL-CURRENT-STATE CMP-CELL: _SL-LINE-U
_SL-CURRENT-STATE 128 CMP-FIELD: _SL-STATUS-BUF
_SL-CURRENT-STATE CMP-CELL: _SL-STATUS-U

CMP-LAYOUT-SIZE CONSTANT _SL-STATE-SIZE

: _SL-ACTIVATE  ( instance -- )
    DUP _SL-CURRENT-INSTANCE !
    CINST-STATE _SL-CURRENT-STATE ! ;

\ ---------------------------------------------------------------------
\ Small bounded text builders
\ ---------------------------------------------------------------------

VARIABLE _SL-TA
VARIABLE _SL-TU
VARIABLE _SL-TN

: _SL-SUMMARY-RESET  ( -- ) 0 _SL-SUMMARY-U ! ;

: _SL-SUMMARY+  ( addr len -- )
    _SL-TU ! _SL-TA !
    _SL-SUMMARY-CAP _SL-SUMMARY-U @ - 0 MAX _SL-TU @ MIN _SL-TN !
    _SL-TA @ _SL-SUMMARY-BUF _SL-SUMMARY-U @ + _SL-TN @ CMOVE
    _SL-TN @ _SL-SUMMARY-U +! ;

: _SL-SUMMARY-N  ( n -- ) NUM>STR _SL-SUMMARY+ ;
: _SL-SUMMARY-NL ( -- ) 10 _SL-SUMMARY-BUF _SL-SUMMARY-U @ + C! 1 _SL-SUMMARY-U +! ;

: _SL-LINE-RESET  ( -- ) 0 _SL-LINE-U ! ;

: _SL-LINE+  ( addr len -- )
    _SL-TU ! _SL-TA !
    _SL-LINE-CAP _SL-LINE-U @ - 0 MAX _SL-TU @ MIN _SL-TN !
    _SL-TA @ _SL-LINE-BUF _SL-LINE-U @ + _SL-TN @ CMOVE
    _SL-TN @ _SL-LINE-U +! ;

: _SL-LINE-N  ( n -- ) NUM>STR _SL-LINE+ ;

\ ---------------------------------------------------------------------
\ Parameter and state descriptions
\ ---------------------------------------------------------------------

: _SL-SHAPE-NAME  ( shape -- addr len )
    CASE
        OSC-SINE OF S" sine" ENDOF
        OSC-SQUARE OF S" square" ENDOF
        OSC-SAW OF S" saw" ENDOF
        OSC-TRI OF S" triangle" ENDOF
        OSC-PULSE OF S" pulse" ENDOF
        DROP S" unknown"
    ENDCASE ;

: _SL-SHAPE-FROM-NAME  ( addr len -- shape flag )
    2DUP S" sine" STR-STR= IF 2DROP OSC-SINE -1 EXIT THEN
    2DUP S" square" STR-STR= IF 2DROP OSC-SQUARE -1 EXIT THEN
    2DUP S" saw" STR-STR= IF 2DROP OSC-SAW -1 EXIT THEN
    2DUP S" triangle" STR-STR= IF 2DROP OSC-TRI -1 EXIT THEN
    S" pulse" STR-STR= IF OSC-PULSE -1 ELSE 0 0 THEN ;

: _SL-FP16-PERCENT  ( fp16 -- n )
    100 INT>FP16 FP16-MUL FP16>INT ;

: _SL-FP16-PERMILLE  ( fp16 -- n )
    1000 INT>FP16 FP16-MUL FP16>INT ;

: _SL-AUDIO-DEVICE-NAME  ( -- addr len )
    AUDIO-OUT-PRESENT? 0= IF S" absent" EXIT THEN
    AUDIO-OUT-SINK? IF
        S" audible-sink"
    ELSE
        S" deterministic-capture-only"
    THEN ;

: _SL-PLAY-STATUS-NAME  ( status -- addr len )
    DUP _SL-PLAY-S-NEVER = IF DROP S" never" EXIT THEN
    CASE
        AUDIO-OUT-S-OK OF S" ok" ENDOF
        AUDIO-OUT-S-ABSENT OF S" absent" ENDOF
        AUDIO-OUT-S-INVALID OF S" invalid" ENDOF
        AUDIO-OUT-S-TOO-LARGE OF S" too-large" ENDOF
        AUDIO-OUT-S-BUSY OF S" busy" ENDOF
        AUDIO-OUT-S-ALLOC OF S" allocation-failed" ENDOF
        AUDIO-OUT-S-DEVICE OF S" device-failed" ENDOF
        AUDIO-OUT-S-TIMEOUT OF S" timeout" ENDOF
        AUDIO-OUT-S-UNSUPPORTED OF S" unsupported" ENDOF
        AUDIO-OUT-S-IO OF S" io-failed" ENDOF
        AUDIO-OUT-S-CORE OF S" core-rejected" ENDOF
        DROP S" unknown"
    ENDCASE ;

: _SL-PLAY-ERROR-TEXT  ( status -- addr len )
    CASE
        AUDIO-OUT-S-ABSENT OF S" Audio output device is absent" ENDOF
        AUDIO-OUT-S-INVALID OF S" Current render is invalid for audio output" ENDOF
        AUDIO-OUT-S-TOO-LARGE OF S" Current render exceeds the audio output limit" ENDOF
        AUDIO-OUT-S-BUSY OF S" Audio output is busy" ENDOF
        AUDIO-OUT-S-ALLOC OF S" Audio output could not allocate staging memory" ENDOF
        AUDIO-OUT-S-DEVICE OF
            S" Audio device failed; inspect playback status for its error code"
        ENDOF
        AUDIO-OUT-S-TIMEOUT OF S" Audio output timed out and was stopped" ENDOF
        AUDIO-OUT-S-UNSUPPORTED OF S" Audio device cannot capture PCM16" ENDOF
        AUDIO-OUT-S-IO OF S" Audio output I/O failed" ENDOF
        AUDIO-OUT-S-CORE OF S" Audio output mutation requires the owner core" ENDOF
        DROP S" Audio output request failed"
    ENDCASE ;

: _SL-OWNED-ACTIVE?  ( -- flag )
    _SL-PLAY-OWNED @ 0= IF 0 EXIT THEN
    AUDIO-OUT-PLAYING? 0= IF 0 EXIT THEN
    AUDIO-OUT-GENERATION _SL-OWNED-GENERATION @ = ;

: _SL-BUILD-SUMMARY  ( -- )
    _SL-SUMMARY-RESET
    S" shape=" _SL-SUMMARY+ _SL-SHAPE @ _SL-SHAPE-NAME _SL-SUMMARY+ _SL-SUMMARY-NL
    S" frequency_hz=" _SL-SUMMARY+ _SL-FREQUENCY @ _SL-SUMMARY-N _SL-SUMMARY-NL
    S" amplitude_percent=" _SL-SUMMARY+ _SL-AMPLITUDE @ _SL-SUMMARY-N _SL-SUMMARY-NL
    S" duration_ms=" _SL-SUMMARY+ _SL-DURATION @ _SL-SUMMARY-N _SL-SUMMARY-NL
    S" sample_rate_hz=" _SL-SUMMARY+ _SL-RATE _SL-SUMMARY-N _SL-SUMMARY-NL
    S" render=" _SL-SUMMARY+
    _SL-LAST-ERROR @ IF
        S" failed" _SL-SUMMARY+
    ELSE _SL-RENDER-VALID @ IF
        S" ready" _SL-SUMMARY+
    ELSE _SL-PCM @ IF
        S" stale" _SL-SUMMARY+
    ELSE
        S" absent" _SL-SUMMARY+
    THEN THEN THEN _SL-SUMMARY-NL
    S" unsaved_render=" _SL-SUMMARY+
    _SL-UNSAVED @ IF S" true" ELSE S" false" THEN _SL-SUMMARY+ _SL-SUMMARY-NL
    _SL-RENDER-VALID @ IF
        S" peak_percent=" _SL-SUMMARY+ _SL-M-PEAK @ _SL-FP16-PERCENT _SL-SUMMARY-N _SL-SUMMARY-NL
        S" peak_frame=" _SL-SUMMARY+ _SL-M-PEAK-FRAME @ _SL-SUMMARY-N _SL-SUMMARY-NL
        S" rms_percent=" _SL-SUMMARY+ _SL-M-RMS @ _SL-FP16-PERCENT _SL-SUMMARY-N _SL-SUMMARY-NL
        S" dc_permille=" _SL-SUMMARY+ _SL-M-DC @ _SL-FP16-PERMILLE _SL-SUMMARY-N _SL-SUMMARY-NL
        S" zero_crossings=" _SL-SUMMARY+ _SL-M-ZC @ _SL-SUMMARY-N _SL-SUMMARY-NL
        S" clipped_samples=" _SL-SUMMARY+ _SL-M-CLIPS @ _SL-SUMMARY-N _SL-SUMMARY-NL
        S" pitch_estimate_hz=" _SL-SUMMARY+ _SL-M-PITCH @ FP16>INT _SL-SUMMARY-N _SL-SUMMARY-NL
        S" spectral_centroid_hz=" _SL-SUMMARY+ _SL-M-CENTROID @ FP16>INT _SL-SUMMARY-N _SL-SUMMARY-NL
    THEN
    S" audio_device=" _SL-SUMMARY+ _SL-AUDIO-DEVICE-NAME _SL-SUMMARY+ _SL-SUMMARY-NL
    S" audio_status_bits=" _SL-SUMMARY+ AUDIO-OUT-STATUS _SL-SUMMARY-N _SL-SUMMARY-NL
    S" audio_generation=" _SL-SUMMARY+ AUDIO-OUT-GENERATION _SL-SUMMARY-N _SL-SUMMARY-NL
    S" last_play_status=" _SL-SUMMARY+
    _SL-LAST-PLAY-STATUS @ _SL-PLAY-STATUS-NAME _SL-SUMMARY+ _SL-SUMMARY-NL
    S" last_play_generation=" _SL-SUMMARY+
    _SL-LAST-PLAY-GENERATION @ _SL-SUMMARY-N _SL-SUMMARY-NL
    S" last_play_device_error=" _SL-SUMMARY+
    _SL-LAST-PLAY-ERROR @ _SL-SUMMARY-N _SL-SUMMARY-NL
    S" owned_active_voice=" _SL-SUMMARY+
    _SL-OWNED-ACTIVE? IF S" true" ELSE S" false" THEN
    _SL-SUMMARY+ _SL-SUMMARY-NL
    S" output=vfs:/soundlab.wav" _SL-SUMMARY+ ;

\ ---------------------------------------------------------------------
\ Status and invalidation
\ ---------------------------------------------------------------------

: _SL-STATUS-RESET  ( -- ) 0 _SL-STATUS-U ! ;

: _SL-STATUS+  ( addr len -- )
    _SL-TU ! _SL-TA !
    128 _SL-STATUS-U @ - 0 MAX _SL-TU @ MIN _SL-TN !
    _SL-TA @ _SL-STATUS-BUF _SL-STATUS-U @ + _SL-TN @ CMOVE
    _SL-TN @ _SL-STATUS-U +! ;

: _SL-STATUS-N  ( n -- ) NUM>STR _SL-STATUS+ ;

: _SL-UPDATE-STATUS  ( -- )
    _SL-E-SBAR-SIGNAL @ ?DUP IF
        _SL-STATUS-RESET
        _SL-SHAPE @ _SL-SHAPE-NAME _SL-STATUS+
        S"  " _SL-STATUS+ _SL-FREQUENCY @ _SL-STATUS-N S" Hz  " _SL-STATUS+
        _SL-AMPLITUDE @ _SL-STATUS-N S" %  " _SL-STATUS+
        _SL-DURATION @ _SL-STATUS-N S" ms" _SL-STATUS+
        S" text" _SL-STATUS-BUF _SL-STATUS-U @ UTUI-SET-ATTR
    THEN
    _SL-E-SBAR-STATE @ ?DUP IF
        _SL-OUTPUT-BLOCKED @ IF
            S" Output recovery blocked"
        ELSE _SL-LAST-ERROR @ IF
            S" Render failed"
        ELSE _SL-RENDER-VALID @ 0= IF
            S" Render required"
        ELSE _SL-UNSAVED @ IF
            S" Rendered / unsaved"
        ELSE
            S" Rendered / saved"
        THEN THEN THEN THEN
        S" text" 2SWAP UTUI-SET-ATTR
    THEN
    _SL-E-SBAR-PLAYBACK @ ?DUP IF
        AUDIO-OUT-PRESENT? 0= IF
            S" Audio absent"
        ELSE AUDIO-OUT-SINK? IF
            S" Audible sink"
        ELSE
            S" Capture only"
        THEN THEN
        S" text" 2SWAP UTUI-SET-ATTR
    THEN ;

: _SL-INVALIDATE  ( -- )
    _SL-BUILD-SUMMARY
    _SL-PANEL WDG-DIRTY
    _SL-E-BODY @ ?DUP IF UIDL-DIRTY! THEN
    _SL-UPDATE-STATUS
    ASHELL-DIRTY! ;

: _SL-PARAM-CHANGED  ( -- )
    0 _SL-RENDER-VALID !
    0 _SL-LAST-ERROR !
    _SL-INVALIDATE ;

\ ---------------------------------------------------------------------
\ Rendering and native analysis
\ ---------------------------------------------------------------------

VARIABLE _SL-R-CANDIDATE
VARIABLE _SL-R-OSC
VARIABLE _SL-R-DATA
VARIABLE _SL-R-AMP
VARIABLE _SL-R-PEAK
VARIABLE _SL-R-PEAK-FRAME
VARIABLE _SL-R-RMS
VARIABLE _SL-R-DC
VARIABLE _SL-R-ZC
VARIABLE _SL-R-CLIPS
VARIABLE _SL-R-PITCH
VARIABLE _SL-R-CENTROID

: _SL-RENDER-CLEANUP  ( -- )
    _SL-R-OSC @ ?DUP IF OSC-FREE 0 _SL-R-OSC ! THEN
    _SL-R-CANDIDATE @ ?DUP IF PCM-FREE 0 _SL-R-CANDIDATE ! THEN ;

: _SL-RENDER-BODY  ( -- )
    _SL-DURATION @ _SL-RATE * 1000 /
    DUP 1 MAX _SL-MAX-FRAMES MIN
    _SL-RATE 16 1 PCM-ALLOC DUP _SL-R-CANDIDATE !
    _SL-FREQUENCY @ INT>FP16 _SL-SHAPE @ _SL-RATE OSC-CREATE
    DUP _SL-R-OSC !
    _SL-R-CANDIDATE @ SWAP OSC-FILL
    _SL-R-OSC @ OSC-FREE 0 _SL-R-OSC !

    _SL-AMPLITUDE @ INT>FP16 100 INT>FP16 FP16-DIV _SL-R-AMP !
    _SL-R-CANDIDATE @ PCM-DATA _SL-R-DATA !
    _SL-R-CANDIDATE @ PCM-LEN 0 DO
        _SL-R-DATA @ I 2* + DUP W@
        _SL-R-AMP @ FP16-MUL SWAP W!
    LOOP

    _SL-R-CANDIDATE @ PCM-FP16-PEAK
    _SL-R-PEAK-FRAME ! _SL-R-PEAK !
    _SL-R-CANDIDATE @ PCM-RMS _SL-R-RMS !
    _SL-R-CANDIDATE @ PCM-DC-OFFSET _SL-R-DC !
    _SL-R-CANDIDATE @ PCM-ZERO-CROSSINGS _SL-R-ZC !
    _SL-R-CANDIDATE @ PCM-CLIP-COUNT _SL-R-CLIPS !
    _SL-R-CANDIDATE @ PCM-PITCH-ESTIMATE _SL-R-PITCH !
    _SL-R-CANDIDATE @ PCM-SPECTRAL-CENTROID _SL-R-CENTROID ! ;

: _SL-COMMIT-RENDER  ( -- )
    _SL-PCM @ ?DUP IF PCM-FREE THEN
    _SL-R-CANDIDATE @ _SL-PCM ! 0 _SL-R-CANDIDATE !
    _SL-R-PEAK @ _SL-M-PEAK !
    _SL-R-PEAK-FRAME @ _SL-M-PEAK-FRAME !
    _SL-R-RMS @ _SL-M-RMS !
    _SL-R-DC @ _SL-M-DC !
    _SL-R-ZC @ _SL-M-ZC !
    _SL-R-CLIPS @ _SL-M-CLIPS !
    _SL-R-PITCH @ _SL-M-PITCH !
    _SL-R-CENTROID @ _SL-M-CENTROID !
    -1 _SL-RENDER-VALID !
    -1 _SL-UNSAVED !
    0 _SL-LAST-ERROR ! ;

: _SL-RENDER  ( -- ior )
    0 _SL-R-CANDIDATE ! 0 _SL-R-OSC !
    ['] _SL-RENDER-BODY CATCH DUP IF
        DUP _SL-LAST-ERROR !
        0 _SL-RENDER-VALID !
        _SL-RENDER-CLEANUP
        _SL-INVALIDATE EXIT
    THEN
    DROP _SL-COMMIT-RENDER _SL-INVALIDATE 0 ;

\ ---------------------------------------------------------------------
\ Atomic WAV publication
\ ---------------------------------------------------------------------

: _SL-RECOVER-OUTPUT  ( -- status )
    _SL-REPLACE VREPL-RECOVER
    DUP VREPL-S-OK = IF DROP 0 EXIT THEN
    DUP VREPL-S-ROLLED-BACK = IF DROP 0 EXIT THEN
    VREPL-S-COMMITTED-CLEANUP = IF 0 ELSE -1 THEN ;

: _SL-SAVE  ( -- ior )
    _SL-RENDER-VALID @ 0= IF -1 EXIT THEN
    _SL-OUTPUT-BLOCKED @ IF
        _SL-RECOVER-OUTPUT IF -2 EXIT THEN
        0 _SL-OUTPUT-BLOCKED !
    THEN
    _SL-PCM @ _SL-WAV-BUF @ _SL-WAV-CAP WAV-ENCODE
    DUP 0= IF DROP -3 EXIT THEN
    _SL-WAV-BUF @ SWAP _SL-REPLACE VREPL-REPLACE
    DUP VREPL-S-OK = IF DROP 0 ELSE
        DUP VREPL-S-COMMITTED-CLEANUP = IF DROP 0 THEN
    THEN
    DUP 0= IF
        0 _SL-UNSAVED ! -1 _SL-SAVED-ONCE !
    THEN
    _SL-INVALIDATE ;

\ ---------------------------------------------------------------------
\ Bounded AudioOut submission
\ ---------------------------------------------------------------------

: _SL-PLAY  ( -- status )
    _SL-RENDER-VALID @ 0= IF
        AUDIO-OUT-S-INVALID DUP _SL-LAST-PLAY-STATUS !
        0 _SL-LAST-PLAY-ERROR !
        AUDIO-OUT-GENERATION _SL-LAST-PLAY-GENERATION !
        _SL-INVALIDATE EXIT
    THEN
    AUDIO-OUT-GENERATION _SL-PLAY-GEN-BEFORE !
    _SL-PCM @ _SL-PLAY-TIMEOUT-MS AUDIO-OUT-SUBMIT-FP16
    DUP _SL-LAST-PLAY-STATUS !
    AUDIO-OUT-ERROR _SL-LAST-PLAY-ERROR !
    AUDIO-OUT-GENERATION DUP _SL-LAST-PLAY-GENERATION !
    AUDIO-OUT-PLAYING? IF
        \ A capture generation created by this call belongs to Sound Lab
        \ even when the host callback failed after starting a voice.
        DUP _SL-PLAY-GEN-BEFORE @ <> IF
            -1 _SL-PLAY-OWNED !
            DUP _SL-OWNED-GENERATION !
        THEN
    ELSE
        0 _SL-PLAY-OWNED !
    THEN
    DROP
    _SL-INVALIDATE ;

: _SL-STOP-OWNED-VOICE  ( -- )
    _SL-OWNED-ACTIVE? IF AUDIO-OUT-STOP DROP THEN
    0 _SL-PLAY-OWNED ! ;

\ ---------------------------------------------------------------------
\ Exact-value prompt
\ ---------------------------------------------------------------------

VARIABLE _SL-SUB-A
VARIABLE _SL-SUB-U
VARIABLE _SL-SUB-N
VARIABLE _SL-SUB-MODE
VARIABLE _SL-SHOW-MODE
VARIABLE _SL-SHOW-LA
VARIABLE _SL-SHOW-LU
VARIABLE _SL-SHOW-IA
VARIABLE _SL-SHOW-IU

: _SL-SHOW-PROMPT  ( mode label-a label-u n -- )
    NUM>STR _SL-SHOW-IU ! _SL-SHOW-IA !
    _SL-SHOW-LU ! _SL-SHOW-LA ! _SL-SHOW-MODE !
    _SL-PROMPT @ 0= IF EXIT THEN
    _SL-SHOW-MODE @ _SL-PROMPT-MODE !
    _SL-SHOW-LA @ _SL-SHOW-LU @
    _SL-SHOW-IA @ _SL-SHOW-IU @ _SL-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _SL-CYCLE-SHAPE  ( delta -- )
    _SL-SHAPE @ +
    DUP 0< IF DROP OSC-PULSE THEN
    DUP OSC-PULSE > IF DROP OSC-SINE THEN
    DUP _SL-SHAPE @ <> IF _SL-SHAPE ! _SL-PARAM-CHANGED ELSE DROP THEN ;

: _SL-BEGIN-EDIT  ( -- )
    _SL-SELECTED @ CASE
        _SL-SEL-SHAPE OF 1 _SL-CYCLE-SHAPE ENDOF
        _SL-SEL-FREQUENCY OF
            _SL-PM-FREQUENCY S" Frequency (40-2000 Hz):" _SL-FREQUENCY @ _SL-SHOW-PROMPT
        ENDOF
        _SL-SEL-AMPLITUDE OF
            _SL-PM-AMPLITUDE S" Amplitude (0-100 percent):" _SL-AMPLITUDE @ _SL-SHOW-PROMPT
        ENDOF
        _SL-SEL-DURATION OF
            _SL-PM-DURATION S" Duration (100-2000 ms):" _SL-DURATION @ _SL-SHOW-PROMPT
        ENDOF
    ENDCASE ;

: _SL-PROMPT-SUBMIT  ( prompt -- )
    PRM-GET-TEXT STR-TRIM _SL-SUB-U ! _SL-SUB-A !
    _SL-PROMPT-MODE @ _SL-SUB-MODE !
    _SL-PM-NONE _SL-PROMPT-MODE !
    _SL-SUB-A @ _SL-SUB-U @ STR>NUM 0= IF
        DROP S" Enter a whole number" 1800 ASHELL-TOAST
    ELSE
        _SL-SUB-N !
        _SL-SUB-MODE @ CASE
            _SL-PM-FREQUENCY OF
                _SL-SUB-N @ DUP _SL-FREQ-MIN < SWAP _SL-FREQ-MAX > OR IF
                    S" Frequency must be 40-2000 Hz" 2200 ASHELL-TOAST
                ELSE _SL-SUB-N @ _SL-FREQUENCY ! _SL-PARAM-CHANGED THEN
            ENDOF
            _SL-PM-AMPLITUDE OF
                _SL-SUB-N @ DUP _SL-AMP-MIN < SWAP _SL-AMP-MAX > OR IF
                    S" Amplitude must be 0-100 percent" 2200 ASHELL-TOAST
                ELSE _SL-SUB-N @ _SL-AMPLITUDE ! _SL-PARAM-CHANGED THEN
            ENDOF
            _SL-PM-DURATION OF
                _SL-SUB-N @ DUP _SL-DURATION-MIN < SWAP _SL-DURATION-MAX > OR IF
                    S" Duration must be 100-2000 ms" 2200 ASHELL-TOAST
                ELSE _SL-SUB-N @ _SL-DURATION ! _SL-PARAM-CHANGED THEN
            ENDOF
        ENDCASE
    THEN
    _SL-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _SL-INVALIDATE ;

: _SL-PROMPT-CANCEL  ( prompt -- )
    DROP _SL-PM-NONE _SL-PROMPT-MODE !
    _SL-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _SL-INVALIDATE ;

\ ---------------------------------------------------------------------
\ Responsive direct-TUI drawing
\ ---------------------------------------------------------------------

VARIABLE _SL-DW
VARIABLE _SL-DH
VARIABLE _SL-DI
VARIABLE _SL-DR
VARIABLE _SL-DA
VARIABLE _SL-DU
VARIABLE _SL-DVA
VARIABLE _SL-DVU
VARIABLE _SL-VALUE-COL
VARIABLE _SL-VALUE-W

: _SL-DRAW-PARAM  ( index row label-a label-u value-a value-u -- )
    _SL-DVU ! _SL-DVA ! _SL-DU ! _SL-DA ! _SL-DR ! _SL-DI !
    _SL-DI @ _SL-SELECTED @ = IF
        15 24 CELL-A-BOLD
    ELSE
        253 234 0
    THEN DRW-STYLE!
    32 _SL-DR @ 0 1 _SL-DW @ DRW-FILL-RECT
    _SL-DA @ _SL-DU @ _SL-DR @ 2 DRW-TEXT
    _SL-DW @ 16 - 18 MAX _SL-VALUE-COL !
    _SL-DW @ _SL-VALUE-COL @ - 2 - 1 MAX _SL-VALUE-W !
    _SL-DVA @ _SL-DVU @ _SL-DR @ _SL-VALUE-COL @ _SL-VALUE-W @ DRW-TEXT-RIGHT ;

: _SL-DRAW-SETTINGS  ( -- )
    _SL-SEL-SHAPE 3 S" Waveform" _SL-SHAPE @ _SL-SHAPE-NAME _SL-DRAW-PARAM
    _SL-SEL-FREQUENCY 4 S" Frequency (Hz)" _SL-FREQUENCY @ NUM>STR _SL-DRAW-PARAM
    _SL-SEL-AMPLITUDE 5 S" Amplitude (%)" _SL-AMPLITUDE @ NUM>STR _SL-DRAW-PARAM
    _SL-SEL-DURATION 6 S" Duration (ms)" _SL-DURATION @ NUM>STR _SL-DRAW-PARAM ;

VARIABLE _SL-PLOT-ROW
VARIABLE _SL-PLOT-H
VARIABLE _SL-PLOT-W
VARIABLE _SL-PLOT-MID
VARIABLE _SL-PLOT-FRAME
VARIABLE _SL-PLOT-Y

: _SL-DRAW-WAVEFORM  ( -- )
    _SL-DH @ 18 < IF EXIT THEN
    11 _SL-PLOT-ROW !
    _SL-DH @ 17 - 3 MAX 12 MIN _SL-PLOT-H !
    _SL-DW @ 4 - 4 MAX _SL-PLOT-W !
    244 234 0 DRW-STYLE!
    S" Waveform (rendered PCM)" 10 2 DRW-TEXT
    _SL-PLOT-ROW @ _SL-PLOT-H @ 2 / + _SL-PLOT-MID !
    239 234 0 DRW-STYLE!
    9472 _SL-PLOT-MID @ 2 _SL-PLOT-W @ DRW-HLINE
    _SL-RENDER-VALID @ 0= IF
        220 234 CELL-A-DIM DRW-STYLE!
        S" Press F5 or R to render current settings"
        _SL-PLOT-MID @ 4 DRW-TEXT EXIT
    THEN
    81 234 CELL-A-BOLD DRW-STYLE!
    _SL-PLOT-W @ 0 DO
        I _SL-PCM @ PCM-LEN * _SL-PLOT-W @ / _SL-PLOT-FRAME !
        _SL-PLOT-FRAME @ 0 _SL-PCM @ PCM-SAMPLE@
        _SL-PLOT-H @ 2 / 1- 1 MAX INT>FP16 FP16-MUL FP16>INT
        _SL-PLOT-MID @ SWAP -
        _SL-PLOT-ROW @ MAX
        _SL-PLOT-ROW @ _SL-PLOT-H @ + 1- MIN _SL-PLOT-Y !
        8226 _SL-PLOT-Y @ I 2 + DRW-CHAR
    LOOP ;

VARIABLE _SL-ANALYSIS-ROW
VARIABLE _SL-LANDMARK-W
VARIABLE _SL-PITCH-X
VARIABLE _SL-CENTROID-X

: _SL-DRAW-ANALYSIS  ( -- )
    _SL-DH @ 18 >= IF
        _SL-PLOT-ROW @ _SL-PLOT-H @ + 1+
    ELSE 9 THEN _SL-ANALYSIS-ROW !
    _SL-RENDER-VALID @ 0= IF EXIT THEN
    250 234 0 DRW-STYLE!
    _SL-LINE-RESET
    S" Peak " _SL-LINE+ _SL-M-PEAK @ _SL-FP16-PERCENT _SL-LINE-N
    S" % @ " _SL-LINE+ _SL-M-PEAK-FRAME @ _SL-LINE-N
    S"   RMS " _SL-LINE+ _SL-M-RMS @ _SL-FP16-PERCENT _SL-LINE-N
    S" %   DC " _SL-LINE+ _SL-M-DC @ _SL-FP16-PERMILLE _SL-LINE-N
    S" ppt" _SL-LINE+
    _SL-LINE-BUF _SL-LINE-U @ _SL-DW @ 4 - 0 MAX MIN
    _SL-ANALYSIS-ROW @ 2 DRW-TEXT

    _SL-LINE-RESET
    S" Pitch " _SL-LINE+ _SL-M-PITCH @ FP16>INT _SL-LINE-N
    S" Hz   centroid " _SL-LINE+ _SL-M-CENTROID @ FP16>INT _SL-LINE-N
    S" Hz   crossings " _SL-LINE+ _SL-M-ZC @ _SL-LINE-N
    S"   clips " _SL-LINE+ _SL-M-CLIPS @ _SL-LINE-N
    _SL-LINE-BUF _SL-LINE-U @ _SL-DW @ 4 - 0 MAX MIN
    _SL-ANALYSIS-ROW @ 1+ 2 DRW-TEXT

    _SL-ANALYSIS-ROW @ 3 + _SL-DH @ < IF
        _SL-DW @ 6 - 4 MAX _SL-LANDMARK-W !
        244 234 CELL-A-DIM DRW-STYLE!
        S" Frequency landmarks: 0 Hz" _SL-ANALYSIS-ROW @ 2 + 2 DRW-TEXT
        S" 4 kHz" _SL-ANALYSIS-ROW @ 2 + 2 _SL-LANDMARK-W @ DRW-TEXT-RIGHT
        9472 _SL-ANALYSIS-ROW @ 3 + 2 _SL-LANDMARK-W @ DRW-HLINE
        _SL-M-PITCH @ FP16>INT 0 MAX 4000 MIN _SL-LANDMARK-W @ 1- * 4000 /
        2 + _SL-PITCH-X !
        _SL-M-CENTROID @ FP16>INT 0 MAX 4000 MIN _SL-LANDMARK-W @ 1- * 4000 /
        2 + _SL-CENTROID-X !
        81 234 CELL-A-BOLD DRW-STYLE!
        [CHAR] P _SL-ANALYSIS-ROW @ 3 + _SL-PITCH-X @ DRW-CHAR
        220 DRW-FG!
        _SL-CENTROID-X @ _SL-PITCH-X @ = IF [CHAR] * ELSE [CHAR] C THEN
        _SL-ANALYSIS-ROW @ 3 + _SL-CENTROID-X @ DRW-CHAR
    THEN ;

: _SL-PANEL-DRAW  ( widget -- )
    DUP WDG-REGION RGN-W _SL-DW !
    WDG-REGION RGN-H _SL-DH !
    253 234 0 DRW-STYLE!
    32 0 0 _SL-DH @ _SL-DW @ DRW-FILL-RECT
    255 24 CELL-A-BOLD DRW-STYLE!
    32 0 0 1 _SL-DW @ DRW-FILL-RECT
    S" SOUND LAB" 0 2 DRW-TEXT
    244 234 0 DRW-STYLE!
    S" FP16 renderer / analyzer  |  arrows edit  |  F5 render  |  P play"
    _SL-DW @ 4 - 0 MAX MIN 1 2 DRW-TEXT
    _SL-DRAW-SETTINGS
    239 234 0 DRW-STYLE!
    9472 7 1 _SL-DW @ 2 - 0 MAX DRW-HLINE
    220 234 0 DRW-STYLE!
    _SL-OUTPUT-BLOCKED @ IF
        S" Output: recovery blocked"
    ELSE _SL-RENDER-VALID @ IF
        _SL-UNSAVED @ IF S" Output: rendered, not saved"
        ELSE S" Output: /soundlab.wav" THEN
    ELSE
        S" Output: render current settings before saving"
    THEN THEN 8 2 DRW-TEXT
    203 234 CELL-A-DIM DRW-STYLE!
    AUDIO-OUT-PRESENT? 0= IF
        S" Playback: audio device absent"
    ELSE AUDIO-OUT-SINK? IF
        S" Playback: audible sink ready (P to play)"
    ELSE
        S" Playback: deterministic capture only (P captures; no sound)"
    THEN THEN
    _SL-DW @ 4 - 0 MAX MIN 9 2 DRW-TEXT
    _SL-DRAW-WAVEFORM
    _SL-DRAW-ANALYSIS
    DRW-STYLE-RESET ;

\ ---------------------------------------------------------------------
\ Input and menu actions
\ ---------------------------------------------------------------------

: _SL-MOVE-SELECTION  ( delta -- )
    _SL-SELECTED @ + 0 MAX _SL-SEL-COUNT 1- MIN _SL-SELECTED !
    _SL-INVALIDATE ;

: _SL-ADJUST  ( delta -- )
    _SL-SELECTED @ CASE
        _SL-SEL-SHAPE OF _SL-CYCLE-SHAPE ENDOF
        _SL-SEL-FREQUENCY OF
            10 * _SL-FREQUENCY @ + _SL-FREQ-MIN MAX _SL-FREQ-MAX MIN
            DUP _SL-FREQUENCY @ <> IF _SL-FREQUENCY ! _SL-PARAM-CHANGED ELSE DROP THEN
        ENDOF
        _SL-SEL-AMPLITUDE OF
            5 * _SL-AMPLITUDE @ + _SL-AMP-MIN MAX _SL-AMP-MAX MIN
            DUP _SL-AMPLITUDE @ <> IF _SL-AMPLITUDE ! _SL-PARAM-CHANGED ELSE DROP THEN
        ENDOF
        _SL-SEL-DURATION OF
            100 * _SL-DURATION @ + _SL-DURATION-MIN MAX _SL-DURATION-MAX MIN
            DUP _SL-DURATION @ <> IF _SL-DURATION ! _SL-PARAM-CHANGED ELSE DROP THEN
        ENDOF
    ENDCASE ;

: _SL-RENDER-ACTION  ( -- )
    _SL-RENDER IF
        S" Signal render failed; previous PCM was kept" 2800 ASHELL-TOAST
    ELSE
        S" Signal rendered and analyzed" 1600 ASHELL-TOAST
    THEN ;

: _SL-SAVE-ACTION  ( -- )
    _SL-SAVE IF
        _SL-RENDER-VALID @ IF
            S" WAV save failed; rendered PCM was kept"
        ELSE
            S" Render current settings before saving"
        THEN 2600 ASHELL-TOAST
    ELSE
        S" Saved /soundlab.wav" 1600 ASHELL-TOAST
    THEN ;

: _SL-PLAYBACK-ACTION  ( -- )
    _SL-RENDER-VALID @ 0= IF
        S" Render current settings before playback" 2200 ASHELL-TOAST EXIT
    THEN
    _SL-PLAY
    DUP AUDIO-OUT-S-OK = IF
        DROP AUDIO-OUT-SINK? IF
            S" Playing the current render through the audible sink"
        ELSE
            S" Captured the current render deterministically; no audible sink"
        THEN
        2800 ASHELL-TOAST EXIT
    THEN
    _SL-PLAY-ERROR-TEXT 3200 ASHELL-TOAST ;

VARIABLE _SL-H-WIDGET

: _SL-PANEL-HANDLE  ( event widget -- consumed? )
    _SL-H-WIDGET !
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-UP OF -1 _SL-MOVE-SELECTION -1 EXIT ENDOF
            KEY-DOWN OF 1 _SL-MOVE-SELECTION -1 EXIT ENDOF
            KEY-LEFT OF -1 _SL-ADJUST -1 EXIT ENDOF
            KEY-RIGHT OF 1 _SL-ADJUST -1 EXIT ENDOF
            KEY-ENTER OF _SL-BEGIN-EDIT -1 EXIT ENDOF
            KEY-F2 OF _SL-BEGIN-EDIT -1 EXIT ENDOF
            KEY-F5 OF _SL-RENDER-ACTION -1 EXIT ENDOF
        ENDCASE
        0 EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
        DUP 16 + @ 0= IF
            8 + @ CASE
                [CHAR] r OF _SL-RENDER-ACTION -1 EXIT ENDOF
                [CHAR] s OF _SL-SAVE-ACTION -1 EXIT ENDOF
                [CHAR] p OF _SL-PLAYBACK-ACTION -1 EXIT ENDOF
                BL OF _SL-RENDER-ACTION -1 EXIT ENDOF
            ENDCASE
        THEN
    THEN
    DROP 0 ;

: _SL-PANEL-INIT  ( rgn -- )
    DUP _SL-PANEL-RGN !
    _SL-PANEL
    33 OVER !
    SWAP OVER 8 + !
    ['] _SL-PANEL-DRAW OVER 16 + !
    ['] _SL-PANEL-HANDLE OVER 24 + !
    WDG-F-VISIBLE WDG-F-DIRTY OR SWAP 32 + ! ;

: _SL-DO-SAVE  ( elem -- ) DROP _SL-SAVE-ACTION ;
: _SL-DO-RENDER  ( elem -- ) DROP _SL-RENDER-ACTION ;
: _SL-DO-PLAY  ( elem -- ) DROP _SL-PLAYBACK-ACTION ;
: _SL-DO-EDIT  ( elem -- ) DROP _SL-BEGIN-EDIT ;
: _SL-DO-PREV-SHAPE  ( elem -- ) DROP -1 _SL-CYCLE-SHAPE ;
: _SL-DO-NEXT-SHAPE  ( elem -- ) DROP 1 _SL-CYCLE-SHAPE ;
: _SL-DO-QUIT  ( elem -- ) DROP ASHELL-QUIT ;

: _SL-DO-RESET  ( elem -- )
    DROP OSC-SINE _SL-SHAPE ! 440 _SL-FREQUENCY !
    75 _SL-AMPLITUDE ! 500 _SL-DURATION !
    _SL-PARAM-CHANGED S" Defaults restored; press F5 to render" 1800 ASHELL-TOAST ;

: _SL-DO-ABOUT  ( elem -- )
    DROP S" Sound Lab - deterministic synthesis, analysis, AudioOut, and WAV export"
    3200 ASHELL-TOAST ;

VARIABLE _SL-SOURCE-REQ

: _SL-REVEAL-COMPLETE  ( request -- )
    DUP CBR.STATUS @ CBUS-S-OK <> IF
        S" Could not reveal the Sound Lab output" 2000 ASHELL-TOAST
    THEN
    CBR-FREE ;

: _SL-DO-REVEAL-OUTPUT  ( elem -- )
    DROP
    _SL-SAVED-ONCE @ 0= IF
        S" Save a WAV before revealing the output" 1800 ASHELL-TOAST EXIT
    THEN
    CBR-NEW DUP IF
        2DROP S" Could not allocate reveal request" 1800 ASHELL-TOAST EXIT
    THEN
    DROP _SL-SOURCE-REQ !
    CPRINC-COMPONENT _SL-SOURCE-REQ @ CBR.PRINCIPAL !
    S" /soundlab.wav" _SL-SOURCE-REQ @ CBR.ARGS IRES-VFS! IF
        _SL-SOURCE-REQ @ CBR-FREE EXIT
    THEN
    ['] _SL-REVEAL-COMPLETE _SL-SOURCE-REQ @ CBR.COMPLETE-XT !
    _SL-SOURCE-REQ @ _SL-CURRENT-INSTANCE @ CINST-POST-INTENT
    DUP CBUS-S-OK <> IF
        DROP _SL-SOURCE-REQ @ CBR-FREE
        S" Output reveal is unavailable outside Desk" 1800 ASHELL-TOAST
    ELSE DROP THEN ;

\ ---------------------------------------------------------------------
\ App lifecycle
\ ---------------------------------------------------------------------

VARIABLE _SL-INIT-RENDER-IOR

: SOUNDLAB-INIT-CB  ( instance -- )
    _SL-ACTIVATE
    0 _SL-PROMPT ! 0 _SL-PROMPT-RGN ! 0 _SL-PANEL-RGN !
    _SL-PM-NONE _SL-PROMPT-MODE !
    OSC-SINE _SL-SHAPE ! 440 _SL-FREQUENCY !
    75 _SL-AMPLITUDE ! 500 _SL-DURATION !
    _SL-SEL-SHAPE _SL-SELECTED !
    0 _SL-PCM ! 0 _SL-RENDER-VALID ! 0 _SL-UNSAVED ! 0 _SL-LAST-ERROR !
    _SL-PLAY-S-NEVER _SL-LAST-PLAY-STATUS !
    0 _SL-LAST-PLAY-ERROR ! 0 _SL-LAST-PLAY-GENERATION !
    0 _SL-PLAY-OWNED ! 0 _SL-OWNED-GENERATION !
    0 _SL-OUTPUT-BLOCKED ! 0 _SL-SAVED-ONCE ! 0 _SL-WAV-BUF !

    VFS-CUR DUP 0= ABORT" soundlab: no VFS available" _SL-VFS !
    _SL-VFS @ _SL-REPLACE VREPL-INIT
    0<> ABORT" soundlab: replacement initialization failed"
    S" /soundlab.wav" _SL-REPLACE VREPL-DERIVE-PATHS!
    0<> ABORT" soundlab: replacement path setup failed"
    _SL-RECOVER-OUTPUT IF -1 _SL-OUTPUT-BLOCKED ! THEN
    S" /soundlab.wav" _SL-VFS @ VFS-RESOLVE 0<> IF -1 _SL-SAVED-ONCE ! THEN
    _SL-WAV-CAP ALLOCATE
    0<> ABORT" soundlab: WAV scratch allocation failed" _SL-WAV-BUF !

    S" soundlab-body" UTUI-BY-ID _SL-E-BODY !
    S" sbar" UTUI-BY-ID _SL-E-SBAR !
    S" sbar-signal" UTUI-BY-ID _SL-E-SBAR-SIGNAL !
    S" sbar-state" UTUI-BY-ID _SL-E-SBAR-STATE !
    S" sbar-playback" UTUI-BY-ID _SL-E-SBAR-PLAYBACK !

    _SL-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW DUP _SL-PROMPT-RGN !
        _SL-PROMPT-BUF _SL-PROMPT-CAP PRM-NEW DUP _SL-PROMPT !
        ['] _SL-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
        ['] _SL-PROMPT-CANCEL OVER PRM-ON-CANCEL
        15 23 ROT PRM-COLORS!
    THEN
    _SL-E-BODY @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW _SL-PANEL-INIT
        _SL-PANEL _SL-E-BODY @ UTUI-WIDGET-SET
    THEN
    S" save" ['] _SL-DO-SAVE UTUI-DO!
    S" reveal-output" ['] _SL-DO-REVEAL-OUTPUT UTUI-DO!
    S" render" ['] _SL-DO-RENDER UTUI-DO!
    S" play" ['] _SL-DO-PLAY UTUI-DO!
    S" edit" ['] _SL-DO-EDIT UTUI-DO!
    S" previous-shape" ['] _SL-DO-PREV-SHAPE UTUI-DO!
    S" next-shape" ['] _SL-DO-NEXT-SHAPE UTUI-DO!
    S" reset" ['] _SL-DO-RESET UTUI-DO!
    S" quit" ['] _SL-DO-QUIT UTUI-DO!
    S" about" ['] _SL-DO-ABOUT UTUI-DO!
    _SL-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _SL-RENDER _SL-INIT-RENDER-IOR !
    _SL-INIT-RENDER-IOR @ IF
        S" Initial signal render failed; controls remain available"
        3000 ASHELL-TOAST
    THEN ;

: SOUNDLAB-EVENT-CB  ( event instance -- consumed? )
    _SL-ACTIVATE
    _SL-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    _UTUI-MENU-OPEN @ IF DROP 0 EXIT THEN
    _SL-PANEL WDG-HANDLE ;

: SOUNDLAB-PAINT-CB  ( instance -- )
    _SL-ACTIVATE
    _SL-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN DROP
    _SL-E-SBAR @ ?DUP IF UTUI-ELEM-RGN _SL-PROMPT @ PRM-SET-BOUNDS THEN
    _SL-PROMPT @ WDG-DRAW ;

: SOUNDLAB-TICK-CB  ( instance -- ) _SL-ACTIVATE ;

: SOUNDLAB-REQUEST-CLOSE-CB  ( reason instance -- decision )
    SWAP DROP _SL-ACTIVATE
    _SL-PROMPT @ ?DUP IF
        PRM-ACTIVE? IF
            S" Finish or cancel the Sound Lab prompt before closing"
            2400 ASHELL-TOAST APP-CLOSE-D-CANCEL EXIT
        THEN
    THEN
    _SL-UNSAVED @ 0= IF APP-CLOSE-D-ALLOW EXIT THEN
    S" Close Sound Lab and discard the unsaved render?" DLG-CONFIRM IF
        APP-CLOSE-D-ALLOW
    ELSE
        APP-CLOSE-D-CANCEL
    THEN ;

: SOUNDLAB-SHUTDOWN-CB  ( instance -- )
    _SL-ACTIVATE
    _SL-STOP-OWNED-VOICE
    _SL-E-BODY @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _SL-PROMPT @ ?DUP IF PRM-FREE THEN
    _SL-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _SL-PANEL-RGN @ ?DUP IF RGN-FREE THEN
    _SL-PCM @ ?DUP IF PCM-FREE THEN
    _SL-WAV-BUF @ ?DUP IF FREE THEN
    0 _SL-PROMPT ! 0 _SL-PROMPT-RGN ! 0 _SL-PANEL-RGN !
    0 _SL-PCM ! 0 _SL-WAV-BUF ! ;

\ ---------------------------------------------------------------------
\ Agent-visible component capabilities
\ ---------------------------------------------------------------------

CREATE _SL-NULL-SCHEMA CS-SIZE ALLOT
CREATE _SL-BOOL-SCHEMA CS-SIZE ALLOT
CREATE _SL-SUMMARY-SCHEMA CS-SIZE ALLOT
CREATE _SL-SHAPE-SCHEMA CS-SIZE ALLOT
CREATE _SL-FREQUENCY-SCHEMA CS-SIZE ALLOT
CREATE _SL-AMPLITUDE-SCHEMA CS-SIZE ALLOT
CREATE _SL-DURATION-SCHEMA CS-SIZE ALLOT
CREATE _SL-RESOURCE-SCHEMA CS-SIZE ALLOT

10 CONSTANT _SL-CAP-COUNT
CREATE SOUNDLAB-CAPS _SL-CAP-COUNT CAP-DESC * ALLOT
: SOUNDLAB-CAP-SHAPE      SOUNDLAB-CAPS ;
: SOUNDLAB-CAP-FREQUENCY  SOUNDLAB-CAPS CAP-DESC + ;
: SOUNDLAB-CAP-AMPLITUDE  SOUNDLAB-CAPS CAP-DESC 2 * + ;
: SOUNDLAB-CAP-DURATION   SOUNDLAB-CAPS CAP-DESC 3 * + ;
: SOUNDLAB-CAP-RENDER     SOUNDLAB-CAPS CAP-DESC 4 * + ;
: SOUNDLAB-CAP-ANALYSIS   SOUNDLAB-CAPS CAP-DESC 5 * + ;
: SOUNDLAB-CAP-SAVE       SOUNDLAB-CAPS CAP-DESC 6 * + ;
: SOUNDLAB-CAP-OUTPUT     SOUNDLAB-CAPS CAP-DESC 7 * + ;
: SOUNDLAB-CAP-PLAYBACK   SOUNDLAB-CAPS CAP-DESC 8 * + ;
: SOUNDLAB-CAP-PLAY       SOUNDLAB-CAPS CAP-DESC 9 * + ;

VARIABLE _SL-CAP-REQ
VARIABLE _SL-CAP-N

: _SL-CAP-FAIL  ( addr len -- status )
    CBUS-S-FAILED _SL-CAP-REQ @ CBR-ERROR!
    CBUS-S-FAILED ;

: _SL-CAP-SUMMARY-RESULT  ( request -- status )
    _SL-BUILD-SUMMARY
    _SL-SUMMARY-BUF _SL-SUMMARY-U @ ROT CBR.RESULT CV-STRING!
    IF S" Could not allocate Sound Lab result" _SL-CAP-FAIL
    ELSE CBUS-S-OK THEN ;

: _SL-CAP-SHAPE-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ !
    DUP CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@ _SL-SHAPE-FROM-NAME
    0= IF 2DROP S" Shape must be sine, square, saw, triangle, or pulse" _SL-CAP-FAIL EXIT THEN
    DUP _SL-SHAPE @ <> IF _SL-SHAPE ! _SL-PARAM-CHANGED ELSE DROP THEN
    _SL-CAP-SUMMARY-RESULT ;

: _SL-CAP-FREQUENCY-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ !
    DUP CBR.ARGS CV-DATA@ DUP _SL-FREQ-MIN < OVER _SL-FREQ-MAX > OR IF
        DROP DROP S" Frequency is outside 40-2000 Hz" _SL-CAP-FAIL EXIT
    THEN
    DUP _SL-FREQUENCY @ <> IF _SL-FREQUENCY ! _SL-PARAM-CHANGED ELSE DROP THEN
    _SL-CAP-SUMMARY-RESULT ;

: _SL-CAP-AMPLITUDE-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ !
    DUP CBR.ARGS CV-DATA@ DUP _SL-AMP-MIN < OVER _SL-AMP-MAX > OR IF
        DROP DROP S" Amplitude is outside 0-100 percent" _SL-CAP-FAIL EXIT
    THEN
    DUP _SL-AMPLITUDE @ <> IF _SL-AMPLITUDE ! _SL-PARAM-CHANGED ELSE DROP THEN
    _SL-CAP-SUMMARY-RESULT ;

: _SL-CAP-DURATION-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ !
    DUP CBR.ARGS CV-DATA@ DUP _SL-DURATION-MIN < OVER _SL-DURATION-MAX > OR IF
        DROP DROP S" Duration is outside 100-2000 ms" _SL-CAP-FAIL EXIT
    THEN
    DUP _SL-DURATION @ <> IF _SL-DURATION ! _SL-PARAM-CHANGED ELSE DROP THEN
    _SL-CAP-SUMMARY-RESULT ;

: _SL-CAP-RENDER-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ !
    _SL-RENDER IF
        DROP S" Sound Lab render failed; previous PCM was kept" _SL-CAP-FAIL
    ELSE
        _SL-CAP-SUMMARY-RESULT
    THEN ;

: _SL-CAP-ANALYSIS-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ ! _SL-CAP-SUMMARY-RESULT ;

: _SL-CAP-SAVE-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ !
    _SL-SAVE 0= DUP ROT CBR.RESULT CV-BOOL!
    IF CBUS-S-OK ELSE
        S" Sound Lab WAV save failed" _SL-CAP-FAIL
    THEN ;

: _SL-CAP-OUTPUT-HANDLER  ( request instance -- status )
    _SL-ACTIVATE
    S" /soundlab.wav" ROT CBR.RESULT IRES-VFS!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _SL-CAP-PLAYBACK-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ ! _SL-CAP-SUMMARY-RESULT ;

: _SL-CAP-PLAY-HANDLER  ( request instance -- status )
    _SL-ACTIVATE DUP _SL-CAP-REQ !
    _SL-RENDER-VALID @ 0= IF
        DROP S" Render current settings before playback" _SL-CAP-FAIL EXIT
    THEN
    _SL-PLAY _SL-CAP-N !
    _SL-CAP-N @ AUDIO-OUT-S-OK = IF _SL-CAP-SUMMARY-RESULT EXIT THEN
    DROP _SL-CAP-N @ _SL-PLAY-ERROR-TEXT _SL-CAP-FAIL ;

: _SL-CAP-COMMON  ( cap -- )
    DUP CAP-DESC-INIT
    CAP-F-NEEDS-TARGET SWAP CAP.FLAGS ! ;

: _SL-CAP-SETUP  ( -- )
    _SL-NULL-SCHEMA CS-INIT CV-T-NULL _SL-NULL-SCHEMA CS-ALLOW!
    _SL-BOOL-SCHEMA CS-INIT CV-T-BOOL _SL-BOOL-SCHEMA CS-ALLOW!
    _SL-SUMMARY-SCHEMA CS-INIT CV-T-STRING _SL-SUMMARY-SCHEMA CS-ALLOW!
    _SL-SUMMARY-CAP _SL-SUMMARY-SCHEMA CS-MAX-LEN!
    _SL-SHAPE-SCHEMA CS-INIT CV-T-STRING _SL-SHAPE-SCHEMA CS-ALLOW!
    8 _SL-SHAPE-SCHEMA CS-MAX-LEN!
    _SL-FREQUENCY-SCHEMA CS-INIT CV-T-INT _SL-FREQUENCY-SCHEMA CS-ALLOW!
    _SL-FREQ-MIN _SL-FREQUENCY-SCHEMA CS-MIN!
    _SL-FREQ-MAX _SL-FREQUENCY-SCHEMA CS-MAX!
    _SL-AMPLITUDE-SCHEMA CS-INIT CV-T-INT _SL-AMPLITUDE-SCHEMA CS-ALLOW!
    _SL-AMP-MIN _SL-AMPLITUDE-SCHEMA CS-MIN!
    _SL-AMP-MAX _SL-AMPLITUDE-SCHEMA CS-MAX!
    _SL-DURATION-SCHEMA CS-INIT CV-T-INT _SL-DURATION-SCHEMA CS-ALLOW!
    _SL-DURATION-MIN _SL-DURATION-SCHEMA CS-MIN!
    _SL-DURATION-MAX _SL-DURATION-SCHEMA CS-MAX!
    _SL-RESOURCE-SCHEMA CS-INIT CV-T-RESOURCE _SL-RESOURCE-SCHEMA CS-ALLOW!
    516 _SL-RESOURCE-SCHEMA CS-MAX-LEN!

    SOUNDLAB-CAP-SHAPE _SL-CAP-COMMON
    CAP-K-COMMAND SOUNDLAB-CAP-SHAPE CAP.KIND !
    S" soundlab.shape.set" SOUNDLAB-CAP-SHAPE CAP.ID-U ! SOUNDLAB-CAP-SHAPE CAP.ID-A !
    S" Set waveform" SOUNDLAB-CAP-SHAPE CAP.TITLE-U ! SOUNDLAB-CAP-SHAPE CAP.TITLE-A !
    S" Select sine, square, saw, triangle, or pulse; render separately"
    SOUNDLAB-CAP-SHAPE CAP.DESC-U ! SOUNDLAB-CAP-SHAPE CAP.DESC-A !
    _SL-SHAPE-SCHEMA SOUNDLAB-CAP-SHAPE CAP.IN-SCHEMA !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-SHAPE CAP.OUT-SCHEMA !
    CAP-E-MUTATE SOUNDLAB-CAP-SHAPE CAP.EFFECTS !
    ['] _SL-CAP-SHAPE-HANDLER SOUNDLAB-CAP-SHAPE CAP.HANDLER-XT !

    SOUNDLAB-CAP-FREQUENCY _SL-CAP-COMMON
    CAP-K-COMMAND SOUNDLAB-CAP-FREQUENCY CAP.KIND !
    S" soundlab.frequency.set" SOUNDLAB-CAP-FREQUENCY CAP.ID-U ! SOUNDLAB-CAP-FREQUENCY CAP.ID-A !
    S" Set frequency" SOUNDLAB-CAP-FREQUENCY CAP.TITLE-U ! SOUNDLAB-CAP-FREQUENCY CAP.TITLE-A !
    S" Set oscillator frequency in Hz from 40 through 2000; render separately"
    SOUNDLAB-CAP-FREQUENCY CAP.DESC-U ! SOUNDLAB-CAP-FREQUENCY CAP.DESC-A !
    _SL-FREQUENCY-SCHEMA SOUNDLAB-CAP-FREQUENCY CAP.IN-SCHEMA !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-FREQUENCY CAP.OUT-SCHEMA !
    CAP-E-MUTATE SOUNDLAB-CAP-FREQUENCY CAP.EFFECTS !
    ['] _SL-CAP-FREQUENCY-HANDLER SOUNDLAB-CAP-FREQUENCY CAP.HANDLER-XT !

    SOUNDLAB-CAP-AMPLITUDE _SL-CAP-COMMON
    CAP-K-COMMAND SOUNDLAB-CAP-AMPLITUDE CAP.KIND !
    S" soundlab.amplitude.set" SOUNDLAB-CAP-AMPLITUDE CAP.ID-U ! SOUNDLAB-CAP-AMPLITUDE CAP.ID-A !
    S" Set amplitude" SOUNDLAB-CAP-AMPLITUDE CAP.TITLE-U ! SOUNDLAB-CAP-AMPLITUDE CAP.TITLE-A !
    S" Set render amplitude from 0 through 100 percent; render separately"
    SOUNDLAB-CAP-AMPLITUDE CAP.DESC-U ! SOUNDLAB-CAP-AMPLITUDE CAP.DESC-A !
    _SL-AMPLITUDE-SCHEMA SOUNDLAB-CAP-AMPLITUDE CAP.IN-SCHEMA !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-AMPLITUDE CAP.OUT-SCHEMA !
    CAP-E-MUTATE SOUNDLAB-CAP-AMPLITUDE CAP.EFFECTS !
    ['] _SL-CAP-AMPLITUDE-HANDLER SOUNDLAB-CAP-AMPLITUDE CAP.HANDLER-XT !

    SOUNDLAB-CAP-DURATION _SL-CAP-COMMON
    CAP-K-COMMAND SOUNDLAB-CAP-DURATION CAP.KIND !
    S" soundlab.duration.set" SOUNDLAB-CAP-DURATION CAP.ID-U ! SOUNDLAB-CAP-DURATION CAP.ID-A !
    S" Set duration" SOUNDLAB-CAP-DURATION CAP.TITLE-U ! SOUNDLAB-CAP-DURATION CAP.TITLE-A !
    S" Set render duration in milliseconds from 100 through 2000; render separately"
    SOUNDLAB-CAP-DURATION CAP.DESC-U ! SOUNDLAB-CAP-DURATION CAP.DESC-A !
    _SL-DURATION-SCHEMA SOUNDLAB-CAP-DURATION CAP.IN-SCHEMA !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-DURATION CAP.OUT-SCHEMA !
    CAP-E-MUTATE SOUNDLAB-CAP-DURATION CAP.EFFECTS !
    ['] _SL-CAP-DURATION-HANDLER SOUNDLAB-CAP-DURATION CAP.HANDLER-XT !

    SOUNDLAB-CAP-RENDER _SL-CAP-COMMON
    CAP-K-COMMAND SOUNDLAB-CAP-RENDER CAP.KIND !
    S" soundlab.render" SOUNDLAB-CAP-RENDER CAP.ID-U ! SOUNDLAB-CAP-RENDER CAP.ID-A !
    S" Render signal" SOUNDLAB-CAP-RENDER CAP.TITLE-U ! SOUNDLAB-CAP-RENDER CAP.TITLE-A !
    S" Render current settings and return native PCM analysis"
    SOUNDLAB-CAP-RENDER CAP.DESC-U ! SOUNDLAB-CAP-RENDER CAP.DESC-A !
    _SL-NULL-SCHEMA SOUNDLAB-CAP-RENDER CAP.IN-SCHEMA !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-RENDER CAP.OUT-SCHEMA !
    CAP-E-MUTATE SOUNDLAB-CAP-RENDER CAP.EFFECTS !
    15000 SOUNDLAB-CAP-RENDER CAP.MAX-MS !
    ['] _SL-CAP-RENDER-HANDLER SOUNDLAB-CAP-RENDER CAP.HANDLER-XT !

    SOUNDLAB-CAP-ANALYSIS _SL-CAP-COMMON
    CAP-K-RESOURCE SOUNDLAB-CAP-ANALYSIS CAP.KIND !
    S" soundlab.analysis" SOUNDLAB-CAP-ANALYSIS CAP.ID-U ! SOUNDLAB-CAP-ANALYSIS CAP.ID-A !
    S" Signal analysis" SOUNDLAB-CAP-ANALYSIS CAP.TITLE-U ! SOUNDLAB-CAP-ANALYSIS CAP.TITLE-A !
    S" Read settings, render state, native metrics, output, and playback state"
    SOUNDLAB-CAP-ANALYSIS CAP.DESC-U ! SOUNDLAB-CAP-ANALYSIS CAP.DESC-A !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-ANALYSIS CAP.OUT-SCHEMA !
    CAP-E-OBSERVE SOUNDLAB-CAP-ANALYSIS CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
    SOUNDLAB-CAP-ANALYSIS CAP.FLAGS !
    ['] _SL-CAP-ANALYSIS-HANDLER SOUNDLAB-CAP-ANALYSIS CAP.HANDLER-XT !

    SOUNDLAB-CAP-SAVE _SL-CAP-COMMON
    CAP-K-COMMAND SOUNDLAB-CAP-SAVE CAP.KIND !
    S" soundlab.wav.save" SOUNDLAB-CAP-SAVE CAP.ID-U ! SOUNDLAB-CAP-SAVE CAP.ID-A !
    S" Save WAV" SOUNDLAB-CAP-SAVE CAP.TITLE-U ! SOUNDLAB-CAP-SAVE CAP.TITLE-A !
    S" Atomically publish the current render to /soundlab.wav"
    SOUNDLAB-CAP-SAVE CAP.DESC-U ! SOUNDLAB-CAP-SAVE CAP.DESC-A !
    _SL-NULL-SCHEMA SOUNDLAB-CAP-SAVE CAP.IN-SCHEMA !
    _SL-BOOL-SCHEMA SOUNDLAB-CAP-SAVE CAP.OUT-SCHEMA !
    CAP-E-PERSIST SOUNDLAB-CAP-SAVE CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR SOUNDLAB-CAP-SAVE CAP.FLAGS !
    15000 SOUNDLAB-CAP-SAVE CAP.MAX-MS !
    ['] _SL-CAP-SAVE-HANDLER SOUNDLAB-CAP-SAVE CAP.HANDLER-XT !

    SOUNDLAB-CAP-OUTPUT _SL-CAP-COMMON
    CAP-K-RESOURCE SOUNDLAB-CAP-OUTPUT CAP.KIND !
    S" soundlab.output" SOUNDLAB-CAP-OUTPUT CAP.ID-U ! SOUNDLAB-CAP-OUTPUT CAP.ID-A !
    S" WAV output" SOUNDLAB-CAP-OUTPUT CAP.TITLE-U ! SOUNDLAB-CAP-OUTPUT CAP.TITLE-A !
    S" Return the durable VFS resource reserved for Sound Lab WAV output"
    SOUNDLAB-CAP-OUTPUT CAP.DESC-U ! SOUNDLAB-CAP-OUTPUT CAP.DESC-A !
    _SL-RESOURCE-SCHEMA SOUNDLAB-CAP-OUTPUT CAP.OUT-SCHEMA !
    CAP-E-OBSERVE SOUNDLAB-CAP-OUTPUT CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR SOUNDLAB-CAP-OUTPUT CAP.FLAGS !
    ['] _SL-CAP-OUTPUT-HANDLER SOUNDLAB-CAP-OUTPUT CAP.HANDLER-XT !

    SOUNDLAB-CAP-PLAYBACK _SL-CAP-COMMON
    CAP-K-RESOURCE SOUNDLAB-CAP-PLAYBACK CAP.KIND !
    S" soundlab.playback.status" SOUNDLAB-CAP-PLAYBACK CAP.ID-U ! SOUNDLAB-CAP-PLAYBACK CAP.ID-A !
    S" Playback status" SOUNDLAB-CAP-PLAYBACK CAP.TITLE-U ! SOUNDLAB-CAP-PLAYBACK CAP.TITLE-A !
    S" Observe AudioOut device mode, status bits, generation, and last play result"
    SOUNDLAB-CAP-PLAYBACK CAP.DESC-U ! SOUNDLAB-CAP-PLAYBACK CAP.DESC-A !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-PLAYBACK CAP.OUT-SCHEMA !
    CAP-E-OBSERVE SOUNDLAB-CAP-PLAYBACK CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR SOUNDLAB-CAP-PLAYBACK CAP.FLAGS !
    ['] _SL-CAP-PLAYBACK-HANDLER SOUNDLAB-CAP-PLAYBACK CAP.HANDLER-XT !

    SOUNDLAB-CAP-PLAY _SL-CAP-COMMON
    CAP-K-COMMAND SOUNDLAB-CAP-PLAY CAP.KIND !
    S" soundlab.play" SOUNDLAB-CAP-PLAY CAP.ID-U ! SOUNDLAB-CAP-PLAY CAP.ID-A !
    S" Play render" SOUNDLAB-CAP-PLAY CAP.TITLE-U ! SOUNDLAB-CAP-PLAY CAP.TITLE-A !
    S" Submit the current valid render to AudioOut; host dispatch is synchronous"
    SOUNDLAB-CAP-PLAY CAP.DESC-U ! SOUNDLAB-CAP-PLAY CAP.DESC-A !
    _SL-NULL-SCHEMA SOUNDLAB-CAP-PLAY CAP.IN-SCHEMA !
    _SL-SUMMARY-SCHEMA SOUNDLAB-CAP-PLAY CAP.OUT-SCHEMA !
    CAP-E-EXTERNAL SOUNDLAB-CAP-PLAY CAP.EFFECTS !
    \ No hard capability deadline is advertised: the driver's five-second
    \ guest wait cannot preempt a synchronous emulator host callback.
    ['] _SL-CAP-PLAY-HANDLER SOUNDLAB-CAP-PLAY CAP.HANDLER-XT ! ;

CREATE SOUNDLAB-COMP-DESC COMP-DESC ALLOT

: _SOUNDLAB-COMP-SETUP  ( -- )
    _SL-CAP-SETUP
    SOUNDLAB-COMP-DESC COMP-DESC-INIT
    S" org.akashic.soundlab"
    SOUNDLAB-COMP-DESC COMP.ID-U ! SOUNDLAB-COMP-DESC COMP.ID-A !
    S" 0.2.0"
    SOUNDLAB-COMP-DESC COMP.VERSION-U ! SOUNDLAB-COMP-DESC COMP.VERSION-A !
    _SL-STATE-SIZE SOUNDLAB-COMP-DESC COMP.STATE-SIZE !
    SOUNDLAB-CAPS SOUNDLAB-COMP-DESC COMP.CAPS-A !
    _SL-CAP-COUNT SOUNDLAB-COMP-DESC COMP.CAPS-N ! ;

: SOUNDLAB-ENTRY  ( desc -- )
    _SOUNDLAB-COMP-SETUP
    DUP APP-DESC-INIT
    SOUNDLAB-COMP-DESC       OVER APP.COMP-DESC !
    ['] SOUNDLAB-INIT-CB OVER APP.INIT-XT !
    ['] SOUNDLAB-EVENT-CB OVER APP.EVENT-XT !
    ['] SOUNDLAB-TICK-CB OVER APP.TICK-XT !
    ['] SOUNDLAB-PAINT-CB OVER APP.PAINT-XT !
    ['] SOUNDLAB-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _SL-ACTIVATE OVER APP.ACTIVATE-XT !
    ['] SOUNDLAB-REQUEST-CLOSE-CB OVER APP.REQUEST-CLOSE-XT !
    S" tui/applets/soundlab/soundlab.uidl"
    ROT DUP >R APP.UIDL-FILE-U ! R@ APP.UIDL-FILE-A !
    0 R@ APP.WIDTH ! 0 R@ APP.HEIGHT !
    S" Sound Lab" R@ APP.TITLE-U ! R> APP.TITLE-A ! ;

CREATE SOUNDLAB-DESC APP-DESC ALLOT

: SOUNDLAB-RUN  ( -- )
    SOUNDLAB-DESC SOUNDLAB-ENTRY
    SOUNDLAB-DESC ASHELL-RUN ;
