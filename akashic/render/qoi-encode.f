\ qoi-encode.f — encode a surface as a QOI picture
\
\ Encodes a surface (RGBA8888) as a QOI file ("Quite OK Image") through
\ qoi-rows.f, the encoder that takes pixels a row at a time.  The format's
\ constants and the decoder are qoi.f; neither they nor the encoder by
\ rows load the surface renderer.
\
\ Load with:   REQUIRE qoi-encode.f
\
\ Public API:
\   QOI-FILE-SIZE  ( w h -- max-bytes )          Worst-case output size
\   QOI-ENCODE     ( surf buf max -- len | 0 )   Encode surface → QOI
\
\ Returns 0 from QOI-ENCODE if the buffer is too small.
\ =====================================================================

REQUIRE qoi-rows.f
REQUIRE surface.f

PROVIDED akashic-qoi-encode

\ =====================================================================
\  QOI-FILE-SIZE  ( w h -- max-bytes )
\ =====================================================================
\  Worst case: every pixel needs 5 bytes (RGBA tag + 4 channel bytes),
\  plus header and end marker.

: QOI-FILE-SIZE  ( w h -- max-bytes )
    * 5 *                     \ w*h*5  worst case pixel data
    QOI-HDR-SIZE +
    QOI-END-SIZE +
;

VARIABLE _QOI-SURF
VARIABLE _QOI-W
VARIABLE _QOI-H

\ The record QOI-ENCODE encodes a surface with.
CREATE _QOI-SURF-ENC-S QOI-ENC-SIZE 7 + ALLOT
: _QOI-SURF-ENC  ( -- enc )  _QOI-SURF-ENC-S 7 + -8 AND ;

\ =====================================================================
\  QOI-ENCODE  ( surf buf max -- len | 0 )
\ =====================================================================

: QOI-ENCODE  ( surf buf max -- len | 0 )
    ROT DUP SURF-W _QOI-W !  DUP SURF-H _QOI-H !  _QOI-SURF !
    _QOI-W @ _QOI-H @ QOI-FILE-SIZE < IF DROP 0 EXIT THEN
    DUP >R  _QOI-W @ _QOI-H @ 4 R> QOI-ENC-HEADER
    _QOI-SURF-ENC QOI-ENC-START
    _QOI-SURF @ SURF-BUF  _QOI-W @ _QOI-H @ *  ROT _QOI-SURF-ENC QOI-ENC-PIXELS
    _QOI-SURF-ENC QOI-ENC-END SWAP - ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _qoi-encode-guard

' QOI-FILE-SIZE   CONSTANT _qoi-file-size-xt
' QOI-ENCODE      CONSTANT _qoi-encode-xt

: QOI-FILE-SIZE   _qoi-file-size-xt _qoi-encode-guard WITH-GUARD ;
: QOI-ENCODE      _qoi-encode-xt _qoi-encode-guard WITH-GUARD ;
[THEN] [THEN]
