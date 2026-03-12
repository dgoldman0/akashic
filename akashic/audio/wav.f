\ wav.f — WAV/RIFF encoder and decoder (PCM format)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Read and write Microsoft WAV files (RIFF container, PCM payload).
\ The BMP of audio — simplest useful container format.
\
\ Encoding converts PCM buffer (FP16 samples in [-1, 1]) to the
\ WAV's target bit depth (8 unsigned, 16 signed, or 32 signed).
\ Decoding reverses the process: raw samples → FP16 PCM buffer.
\
\ In-memory only — WAV-ENCODE / WAV-DECODE work on byte buffers.
\ No file I/O dependency; the caller uses FWRITE / FREAD if desired.
\
\ Follows the bmp.f cursor-based writer pattern:
\   VARIABLE _WAV-BUF / _WAV-POS  +  _WAV-B! / _WAV-W! / _WAV-D!
\
\ Prefix: WAV-   (public API)
\         _WAV-  (internals)
\
\ Load with:   REQUIRE audio/wav.f
\
\ === Public API ===
\   WAV-FILE-SIZE  ( buf -- bytes )
\     Compute output WAV size for a PCM buffer.
\
\   WAV-ENCODE     ( buf out-addr max-bytes -- len | 0 )
\     Encode PCM buffer to WAV bytes.  Returns byte count or 0.
\
\   WAV-DECODE     ( in-addr in-len -- pcm-buf | 0 )
\     Decode WAV bytes into a new PCM buffer.  Returns 0 on error.
\
\   WAV-INFO       ( in-addr in-len -- rate bits chans frames | 0 )
\     Read WAV header fields without decoding sample data.

REQUIRE fp16-ext.f
REQUIRE audio/pcm.f

PROVIDED akashic-audio-wav

\ =====================================================================
\  Constants
\ =====================================================================

44 CONSTANT WAV-HDR-SIZE       \ Standard RIFF + fmt + data header

\ =====================================================================
\  Internal cursor-based writers (little-endian, BMP pattern)
\ =====================================================================

VARIABLE _WAV-BUF       \ output buffer address
VARIABLE _WAV-POS       \ write cursor byte offset

: _WAV-B!  ( byte -- )
    _WAV-BUF @ _WAV-POS @ + C!
    1 _WAV-POS +! ;

: _WAV-W!  ( u16 -- )
    DUP           255 AND _WAV-B!
        8 RSHIFT  255 AND _WAV-B! ;

: _WAV-D!  ( u32 -- )
    DUP              255 AND _WAV-B!
    DUP  8 RSHIFT    255 AND _WAV-B!
    DUP 16 RSHIFT    255 AND _WAV-B!
        24 RSHIFT    255 AND _WAV-B! ;

\ =====================================================================
\  Internal cursor-based readers (little-endian)
\ =====================================================================

VARIABLE _WAV-IN        \ input buffer address
VARIABLE _WAV-RPOS      \ read cursor byte offset

: _WAV-RB@  ( -- byte )
    _WAV-IN @ _WAV-RPOS @ + C@
    1 _WAV-RPOS +! ;

: _WAV-RW@  ( -- u16 )
    _WAV-RB@
    _WAV-RB@ 8 LSHIFT OR ;

: _WAV-RD@  ( -- u32 )
    _WAV-RB@
    _WAV-RB@  8 LSHIFT OR
    _WAV-RB@ 16 LSHIFT OR
    _WAV-RB@ 24 LSHIFT OR ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _WAV-SRC       \ source PCM buffer
VARIABLE _WAV-RATE
VARIABLE _WAV-BITS
VARIABLE _WAV-CHANS
VARIABLE _WAV-FRAMES
VARIABLE _WAV-DSIZ      \ data chunk size in bytes
VARIABLE _WAV-FSIZ      \ total file size
VARIABLE _WAV-VAL       \ temp value
VARIABLE _WAV-I         \ loop counter
VARIABLE _WAV-J         \ inner loop counter

\ =====================================================================
\  WAV-FILE-SIZE — Compute total output size for a PCM buffer
\ =====================================================================
\  ( buf -- bytes )

: WAV-FILE-SIZE  ( buf -- bytes )
    DUP PCM-DATA-BYTES          ( buf data-bytes )
    NIP                         ( data-bytes )
    WAV-HDR-SIZE + ;

\ =====================================================================
\  Internal: convert FP16 sample to target format
\ =====================================================================
\  FP16 audio range: [-1.0, +1.0]
\  8-bit WAV:  unsigned 0–255,   center = 128
\  16-bit WAV: signed -32768 to +32767
\  32-bit WAV: signed -2147483648 to +2147483647
\
\  Strategy: multiply by max positive value, clamp, truncate.

: _WAV-FP16>8  ( fp16 -- u8 )
    \ u8 = clamp(sample * 127 + 128, 0, 255)
    127 INT>FP16 FP16-MUL FP16>INT
    128 +
    DUP 0   < IF DROP 0   THEN
    DUP 255 > IF DROP 255 THEN ;

: _WAV-FP16>16  ( fp16 -- s16 )
    \ s16 = clamp(sample * 32767, -32768, 32767)
    32767 INT>FP16 FP16-MUL FP16>INT
    DUP -32768 < IF DROP -32768 THEN
    DUP  32767 > IF DROP  32767 THEN ;

: _WAV-FP16>32  ( fp16 -- s32 )
    \ s32 = clamp(sample * 32767, -32768, 32767) << 16
    \ (We scale to 16-bit then shift — FP16 doesn't have enough
    \  precision for full 32-bit anyway.)
    32767 INT>FP16 FP16-MUL FP16>INT
    DUP -32768 < IF DROP -32768 THEN
    DUP  32767 > IF DROP  32767 THEN
    16 LSHIFT ;

\ =====================================================================
\  Internal: write the 44-byte WAV header
\ =====================================================================

: _WAV-WRITE-HDR  ( -- )
    \ --- RIFF chunk (12 bytes) ---
    82 _WAV-B!  73 _WAV-B!  70 _WAV-B!  70 _WAV-B!   \ "RIFF"
    _WAV-FSIZ @ 8 - _WAV-D!                           \ file size - 8
    87 _WAV-B!  65 _WAV-B!  86 _WAV-B!  69 _WAV-B!   \ "WAVE"

    \ --- fmt sub-chunk (24 bytes) ---
    102 _WAV-B! 109 _WAV-B! 116 _WAV-B!  32 _WAV-B!  \ "fmt "
    16 _WAV-D!                                         \ chunk size (PCM=16)
    1 _WAV-W!                                          \ format tag (1=PCM)
    _WAV-CHANS @ _WAV-W!                               \ channels
    _WAV-RATE @ _WAV-D!                                \ sample rate
    \ byte rate = rate × channels × (bits/8)
    _WAV-RATE @ _WAV-CHANS @ * _WAV-BITS @ 8 / * _WAV-D!
    \ block align = channels × (bits/8)
    _WAV-CHANS @ _WAV-BITS @ 8 / * _WAV-W!
    _WAV-BITS @ _WAV-W!                                \ bits per sample

    \ --- data sub-chunk header (8 bytes) ---
    100 _WAV-B!  97 _WAV-B! 116 _WAV-B!  97 _WAV-B!  \ "data"
    _WAV-DSIZ @ _WAV-D! ;                              \ data size

\ =====================================================================
\  Internal: write sample data (FP16 → target bit depth)
\ =====================================================================

: _WAV-WRITE-SAMPLES  ( -- )
    _WAV-FRAMES @ 0 DO
        _WAV-CHANS @ 0 DO
            \ Read one FP16 sample from source PCM buffer
            J I _WAV-SRC @ PCM-SAMPLE@
            \ Convert and write based on bit depth
            _WAV-BITS @ DUP 8 = IF
                DROP _WAV-FP16>8 _WAV-B!
            ELSE DUP 16 = IF
                DROP _WAV-FP16>16 _WAV-W!
            ELSE
                DROP _WAV-FP16>32 _WAV-D!
            THEN THEN
        LOOP
    LOOP ;

\ =====================================================================
\  WAV-ENCODE — Encode PCM buffer to WAV bytes
\ =====================================================================
\  ( buf out-addr max-bytes -- len | 0 )
\  Returns byte count written, or 0 if max-bytes too small.

: WAV-ENCODE  ( buf out-addr max-bytes -- len | 0 )
    >R >R                              \ R: max out
    _WAV-SRC !

    \ Extract PCM properties
    _WAV-SRC @ PCM-RATE   _WAV-RATE !
    _WAV-SRC @ PCM-BITS   _WAV-BITS !
    _WAV-SRC @ PCM-CHANS  _WAV-CHANS !
    _WAV-SRC @ PCM-LEN    _WAV-FRAMES !

    \ Compute data size and file size
    _WAV-FRAMES @ _WAV-CHANS @ * _WAV-BITS @ 8 / *
    _WAV-DSIZ !
    _WAV-DSIZ @ WAV-HDR-SIZE +
    _WAV-FSIZ !

    \ Check buffer capacity
    R> R>                              ( out-addr max-bytes )
    DUP _WAV-FSIZ @ < IF              \ max < fsiz → too small
        2DROP 0 EXIT
    THEN
    DROP                               ( out-addr )
    _WAV-BUF !
    0 _WAV-POS !

    \ Write header + samples
    _WAV-WRITE-HDR
    _WAV-WRITE-SAMPLES

    \ Return bytes written
    _WAV-FSIZ @ ;

\ =====================================================================
\  Internal: convert raw sample to FP16
\ =====================================================================

: _WAV-8>FP16  ( u8 -- fp16 )
    128 -                    \ center to signed
    INT>FP16
    127 INT>FP16 FP16-DIV ;

: _WAV-16>FP16  ( s16 -- fp16 )
    \ Sign-extend from 16-bit
    DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN
    \ Halve first to keep FP16 exponents in safe range for FP16-DIV
    2 /
    INT>FP16
    16384 INT>FP16 FP16-DIV ;

: _WAV-32>FP16  ( s32 -- fp16 )
    \ Shift down to 16-bit range then convert
    16 RSHIFT
    DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN
    2 /
    INT>FP16
    16384 INT>FP16 FP16-DIV ;

\ =====================================================================
\  WAV-INFO — Read header fields without loading data
\ =====================================================================
\  ( in-addr in-len -- rate bits chans frames | 0 )
\  Returns 0 on error (too short, bad magic, bad format tag).

: WAV-INFO  ( in-addr in-len -- rate bits chans frames | 0 )
    \ Need at least 44 bytes
    WAV-HDR-SIZE < IF DROP 0 EXIT THEN

    _WAV-IN !
    0 _WAV-RPOS !

    \ Check "RIFF" magic (bytes 0–3)
    _WAV-RD@                           \ read 4 bytes as u32-LE
    0x46464952 <> IF 0 EXIT THEN       \ 'R','I','F','F' in LE

    \ Skip file size (4 bytes)
    _WAV-RPOS @ 4 + _WAV-RPOS !

    \ Check "WAVE" (bytes 8–11)
    _WAV-RD@
    0x45564157 <> IF 0 EXIT THEN       \ 'W','A','V','E' in LE

    \ Check "fmt " (bytes 12–15)
    _WAV-RD@
    0x20746D66 <> IF 0 EXIT THEN       \ 'f','m','t',' ' in LE

    \ Skip fmt chunk size (bytes 16–19)
    _WAV-RPOS @ 4 + _WAV-RPOS !

    \ format tag (bytes 20–21), must be 1 (PCM)
    _WAV-RW@ 1 <> IF 0 EXIT THEN

    \ channels (bytes 22–23)
    _WAV-RW@ _WAV-CHANS !

    \ sample rate (bytes 24–27)
    _WAV-RD@ _WAV-RATE !

    \ skip byte rate + block align (bytes 28–33)
    _WAV-RPOS @ 6 + _WAV-RPOS !

    \ bits per sample (bytes 34–35)
    _WAV-RW@ _WAV-BITS !

    \ Check "data" (bytes 36–39)
    _WAV-RD@
    0x61746164 <> IF 0 EXIT THEN       \ 'd','a','t','a' in LE

    \ data size (bytes 40–43)
    _WAV-RD@ _WAV-DSIZ !

    \ Compute frame count = data_size / (channels × (bits/8))
    _WAV-DSIZ @
    _WAV-CHANS @ _WAV-BITS @ 8 / * /
    _WAV-FRAMES !

    \ Return results
    _WAV-RATE @
    _WAV-BITS @
    _WAV-CHANS @
    _WAV-FRAMES @ ;

\ =====================================================================
\  WAV-DECODE — Decode WAV bytes into a new PCM buffer
\ =====================================================================
\  ( in-addr in-len -- pcm-buf | 0 )
\  Allocates a new FP16 PCM buffer (16-bit, regardless of source depth).
\  Samples are converted to FP16 [-1, 1].  Returns 0 on error.

: WAV-DECODE  ( in-addr in-len -- pcm-buf | 0 )
    2DUP WAV-INFO                  ( in-addr in-len rate bits chans frames | in-addr in-len 0 )
    DUP 0= IF
        DROP 2DROP 0 EXIT          \ header parse failed
    THEN

    _WAV-FRAMES !
    _WAV-CHANS !
    _WAV-BITS !
    _WAV-RATE !

    \ Set up read cursor at byte 44 (start of sample data)
    DROP                           \ drop in-len
    _WAV-IN !                      \ in-addr already set by WAV-INFO, but reset
    WAV-HDR-SIZE _WAV-RPOS !

    \ Allocate output PCM buffer (FP16 = 16-bit)
    _WAV-FRAMES @ _WAV-RATE @ 16 _WAV-CHANS @ PCM-ALLOC
    _WAV-SRC !                     \ reuse _WAV-SRC as output buf

    \ Read and convert samples
    _WAV-FRAMES @ 0 DO
        _WAV-CHANS @ 0 DO
            \ Read one raw sample
            _WAV-BITS @ DUP 8 = IF
                DROP _WAV-RB@ _WAV-8>FP16
            ELSE DUP 16 = IF
                DROP _WAV-RW@ _WAV-16>FP16
            ELSE
                DROP _WAV-RD@ _WAV-32>FP16
            THEN THEN

            \ Write FP16 sample to output buffer
            J I _WAV-SRC @ PCM-SAMPLE!
        LOOP
    LOOP

    _WAV-SRC @ ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _wav-guard

' WAV-FILE-SIZE   CONSTANT _wav-file-size-xt
' WAV-ENCODE      CONSTANT _wav-encode-xt
' WAV-INFO        CONSTANT _wav-info-xt
' WAV-DECODE      CONSTANT _wav-decode-xt

: WAV-FILE-SIZE   _wav-file-size-xt _wav-guard WITH-GUARD ;
: WAV-ENCODE      _wav-encode-xt _wav-guard WITH-GUARD ;
: WAV-INFO        _wav-info-xt _wav-guard WITH-GUARD ;
: WAV-DECODE      _wav-decode-xt _wav-guard WITH-GUARD ;
[THEN] [THEN]
