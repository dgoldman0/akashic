\ wav.f — WAV/RIFF encoder and decoder (PCM format)
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ Read and write Microsoft WAV files (RIFF container, PCM payload).
\ The BMP of audio — simplest useful container format.
\
\ Encoding converts a 16-bit-storage FP16 PCM buffer (samples in [-1, 1])
\ to signed 16-bit WAV PCM.  Decoding accepts 8-, 16-, and 32-bit integer
\ WAV PCM and always produces 16-bit-storage FP16 PCM.
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
\   WAV-ENCODE-PCM16 ( buf out-addr max-bytes -- len | 0 )
\     Explicit name for the same signed-16-bit encoder.
\
\   WAV-DECODE     ( in-addr in-len -- pcm-buf | 0 )
\     Decode WAV bytes into a new PCM buffer.  Returns 0 on error.
\
\   WAV-INFO       ( in-addr in-len -- rate bits chans frames | 0 )
\     Read WAV header fields without decoding sample data.

REQUIRE ../math/fp16-ext.f
REQUIRE pcm.f
REQUIRE pcm-fp16.f

PROVIDED akashic-audio-wav

\ =====================================================================
\  Constants
\ =====================================================================

44 CONSTANT WAV-HDR-SIZE       \ Standard RIFF + fmt + data header
0xFFFF CONSTANT _WAV-U16-MAX
0xFFFFFFFF CONSTANT _WAV-U32-MAX

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
VARIABLE _WAV-IN-LEN    \ input buffer length

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
VARIABLE _WAV-OUT       \ output buffer address
VARIABLE _WAV-CAP       \ output buffer capacity
VARIABLE _WAV-RIFF-SIZE
VARIABLE _WAV-FMT-SIZE
VARIABLE _WAV-BRATE
VARIABLE _WAV-BALIGN
VARIABLE _WAV-FBYTES
VARIABLE _WAV-MUL-A
VARIABLE _WAV-MUL-B
VARIABLE _WAV-MUL-LIMIT

\ Multiply non-negative header/size fields without ever forming a wrapped
\ product.  The caller supplies the actual destination field limit.
: _WAV-LIMITED*  ( a b limit -- product )
    _WAV-MUL-LIMIT ! _WAV-MUL-B ! _WAV-MUL-A !
    _WAV-MUL-A @ 0< _WAV-MUL-B @ 0< OR
        ABORT" WAV: size factors must not be negative"
    _WAV-MUL-B @ 0= IF 0 EXIT THEN
    _WAV-MUL-A @ _WAV-MUL-LIMIT @ _WAV-MUL-B @ / >
        ABORT" WAV: encoded field overflow"
    _WAV-MUL-A @ _WAV-MUL-B @ * ;

\ Validate the source and derive every encoded size once.  All values written
\ by _WAV-W!/D! are proven to fit their u16/u32 fields before output begins.
: _WAV-SET-ENCODE-FIELDS  ( buf -- )
    DUP _WAV-SRC !
    DUP PCM-FP16? 0=
        ABORT" WAV: source must use FP16 16-bit storage"
    DUP PCM-LEN _WAV-FRAMES !
    DUP PCM-RATE _WAV-RATE !
    PCM-CHANS _WAV-CHANS !
    16 _WAV-BITS !

    _WAV-FRAMES @ 1 < ABORT" WAV: source must contain samples"
    _WAV-RATE @ 1 < ABORT" WAV: sample rate must be positive"
    _WAV-RATE @ _WAV-U32-MAX > ABORT" WAV: sample rate exceeds u32"
    _WAV-CHANS @ 1 < ABORT" WAV: channels must be positive"
    _WAV-CHANS @ _WAV-U16-MAX > ABORT" WAV: channels exceed u16"

    _WAV-CHANS @ 2 _WAV-U16-MAX _WAV-LIMITED*
    DUP _WAV-FBYTES ! _WAV-BALIGN !
    _WAV-RATE @ _WAV-FBYTES @ _WAV-U32-MAX _WAV-LIMITED*
    _WAV-BRATE !
    _WAV-FRAMES @ _WAV-FBYTES @ _WAV-U32-MAX _WAV-LIMITED*
    _WAV-DSIZ !
    _WAV-DSIZ @ _WAV-U32-MAX 36 - >
        ABORT" WAV: RIFF payload exceeds u32"
    _WAV-DSIZ @ WAV-HDR-SIZE + _WAV-FSIZ ! ;

\ =====================================================================
\  WAV-FILE-SIZE — Compute total output size for a PCM buffer
\ =====================================================================
\  ( buf -- bytes )

: WAV-FILE-SIZE  ( buf -- bytes )
    _WAV-SET-ENCODE-FIELDS
    _WAV-FSIZ @ ;

\ =====================================================================
\  Internal: convert FP16 sample to target format
\ =====================================================================
\  FP16 audio range: [-1.0, +1.0]
\  8-bit WAV:  unsigned 0–255,   center = 128
\  16-bit WAV: signed -32768 to +32767
\  32-bit WAV: signed -2147483648 to +2147483647
\
\  Strategy: multiply by max positive value, clamp, truncate.

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
    _WAV-BRATE @ _WAV-D!                               \ byte rate
    _WAV-BALIGN @ _WAV-W!                              \ block align
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
            PCM-FP16>S16 _WAV-W!
        LOOP
    LOOP ;

\ =====================================================================
\  WAV-ENCODE — Encode PCM buffer to WAV bytes
\ =====================================================================
\  ( buf out-addr max-bytes -- len | 0 )
\  Returns byte count written, or 0 if max-bytes too small.

: WAV-ENCODE  ( buf out-addr max-bytes -- len | 0 )
    _WAV-CAP !
    _WAV-OUT !
    _WAV-SRC !

    _WAV-SRC @ _WAV-SET-ENCODE-FIELDS
    _WAV-OUT @ 0= IF 0 EXIT THEN

    \ Check buffer capacity
    _WAV-CAP @ _WAV-FSIZ @ < IF 0 EXIT THEN
    _WAV-OUT @ _WAV-BUF !
    0 _WAV-POS !

    \ Write header + samples
    _WAV-WRITE-HDR
    _WAV-WRITE-SAMPLES

    \ Return bytes written
    _WAV-FSIZ @ ;

: WAV-ENCODE-PCM16  ( buf out-addr max-bytes -- len | 0 )
    WAV-ENCODE ;

\ =====================================================================
\  Internal: convert raw sample to FP16
\ =====================================================================

: _WAV-8>FP16  ( u8 -- fp16 )
    \ PCM8 is asymmetric around 128.  Separate denominators make all three
    \ landmarks exact: byte 0 -> -1, 128 -> 0, and 255 -> +1.
    DUP 128 < IF
        128 - INT>FP16 128 INT>FP16 FP16-DIV
    ELSE
        128 - INT>FP16 127 INT>FP16 FP16-DIV
    THEN ;

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
\  Returns 0 on error.  This parser intentionally accepts only the
\  canonical 44-byte PCM layout emitted by WAV-ENCODE; it rejects malformed
\  sizes and headers rather than reading beyond the supplied input buffer.

: _WAV-VALID-BITS?  ( bits -- flag )
    DUP 8 = IF DROP -1 EXIT THEN
    DUP 16 = IF DROP -1 EXIT THEN
    32 = ;

: WAV-INFO  ( in-addr in-len -- rate bits chans frames | 0 )
    DUP _WAV-IN-LEN !
    \ Need at least 44 bytes
    WAV-HDR-SIZE < IF DROP 0 EXIT THEN

    _WAV-IN !
    0 _WAV-RPOS !

    \ Check "RIFF" magic (bytes 0–3)
    _WAV-RD@                           \ read 4 bytes as u32-LE
    0x46464952 <> IF 0 EXIT THEN       \ 'R','I','F','F' in LE

    \ RIFF payload size (file size minus the first 8 bytes)
    _WAV-RD@ _WAV-RIFF-SIZE !
    _WAV-RIFF-SIZE @ 36 < IF 0 EXIT THEN
    _WAV-RIFF-SIZE @ 8 + _WAV-IN-LEN @ > IF 0 EXIT THEN

    \ Check "WAVE" (bytes 8–11)
    _WAV-RD@
    0x45564157 <> IF 0 EXIT THEN       \ 'W','A','V','E' in LE

    \ Check "fmt " (bytes 12–15)
    _WAV-RD@
    0x20746D66 <> IF 0 EXIT THEN       \ 'f','m','t',' ' in LE

    \ Canonical PCM fmt chunk is exactly 16 bytes
    _WAV-RD@ _WAV-FMT-SIZE !
    _WAV-FMT-SIZE @ 16 <> IF 0 EXIT THEN

    \ format tag (bytes 20–21), must be 1 (PCM)
    _WAV-RW@ 1 <> IF 0 EXIT THEN

    \ channels (bytes 22–23)
    _WAV-RW@ _WAV-CHANS !
    _WAV-CHANS @ 1 < IF 0 EXIT THEN

    \ sample rate (bytes 24–27)
    _WAV-RD@ _WAV-RATE !
    _WAV-RATE @ 1 < IF 0 EXIT THEN

    \ byte rate + block align (bytes 28–33)
    _WAV-RD@ _WAV-BRATE !
    _WAV-RW@ _WAV-BALIGN !

    \ bits per sample (bytes 34–35)
    _WAV-RW@ _WAV-BITS !
    _WAV-BITS @ _WAV-VALID-BITS? 0= IF 0 EXIT THEN

    \ Cross-check the redundant format fields before reading payload.
    _WAV-CHANS @ _WAV-BITS @ 8 / * _WAV-FBYTES !
    _WAV-FBYTES @ 1 < IF 0 EXIT THEN
    _WAV-FBYTES @ _WAV-U16-MAX > IF 0 EXIT THEN
    _WAV-BALIGN @ _WAV-FBYTES @ <> IF 0 EXIT THEN
    _WAV-RATE @ _WAV-U32-MAX _WAV-FBYTES @ / > IF 0 EXIT THEN
    _WAV-BRATE @ _WAV-RATE @ _WAV-FBYTES @ * <> IF 0 EXIT THEN

    \ Check "data" (bytes 36–39)
    _WAV-RD@
    0x61746164 <> IF 0 EXIT THEN       \ 'd','a','t','a' in LE

    \ data size (bytes 40–43)
    _WAV-RD@ _WAV-DSIZ !

    \ A zero-frame file is indistinguishable from this word's scalar error
    \ return, so reject it explicitly.  Validate every declared byte before
    \ deriving a frame count or letting WAV-DECODE advance its reader.
    _WAV-DSIZ @ 1 < IF 0 EXIT THEN
    _WAV-DSIZ @ _WAV-IN-LEN @ WAV-HDR-SIZE - > IF 0 EXIT THEN
    _WAV-DSIZ @ _WAV-U32-MAX 36 - > IF 0 EXIT THEN
    _WAV-RIFF-SIZE @ _WAV-DSIZ @ 36 + < IF 0 EXIT THEN
    _WAV-DSIZ @ _WAV-FBYTES @ MOD 0<> IF 0 EXIT THEN

    \ Compute frame count = data_size / (channels × (bits/8))
    _WAV-DSIZ @ _WAV-FBYTES @ / _WAV-FRAMES !

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
                DROP _WAV-RW@ PCM-S16>FP16
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
' WAV-ENCODE-PCM16 CONSTANT _wav-encode-pcm16-xt
' WAV-INFO        CONSTANT _wav-info-xt
' WAV-DECODE      CONSTANT _wav-decode-xt

: WAV-FILE-SIZE   _wav-file-size-xt _wav-guard WITH-GUARD ;
: WAV-ENCODE      _wav-encode-xt _wav-guard WITH-GUARD ;
: WAV-ENCODE-PCM16 _wav-encode-pcm16-xt _wav-guard WITH-GUARD ;
: WAV-INFO        _wav-info-xt _wav-guard WITH-GUARD ;
: WAV-DECODE      _wav-decode-xt _wav-guard WITH-GUARD ;
[THEN] [THEN]
