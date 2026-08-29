\ =====================================================================
\  cold-source-loader.f - bounded AKSRC001 checked source loader
\ =====================================================================
\  Public API:
\    COLD-SOURCE-LOAD  ( i*x "filename" -- j*x status )
\
\  The filename is parsed by OPEN, so this leaf is for short files in the
\  current MegaPad directory.  It is synchronous, non-reentrant, and must
\  run on core 0 because ALLOCATE/FREE are core-0 services.  Like REQUIRE,
\  successful source may leave data-stack effects for a following chunk.
\  Success commits its definitions.  Every evaluation failure or throw
\  restores HERE, LATEST, and evaluator depth; packaged boot source is
\  trusted, so callers abort rather than rely on failure stack restoration.
\
\  Stored payloads are read directly into the evaluation buffer.  LZSS
\  payloads retain the bounded decoder for explicitly compressed profiles.
\
\  Required resident words are OPEN/FSIZE/FREAD/(FCLOSE-NOFS),
\  ALLOCATE/FREE,
\  CRC32-IEEE-BUF, and SOURCE-EVALUATE-CHECKED.  FREE is void.
\ =====================================================================

PROVIDED akashic-cold-source-loader

   0 CONSTANT CSL-S-OK
   1 CONSTANT CSL-S-OPEN
   2 CONSTANT CSL-S-SIZE
   3 CONSTANT CSL-S-HEADER
   4 CONSTANT CSL-S-ALLOC
   5 CONSTANT CSL-S-READ
   6 CONSTANT CSL-S-TRUNCATED
   7 CONSTANT CSL-S-DISTANCE
   8 CONSTANT CSL-S-OUTPUT
   9 CONSTANT CSL-S-CANONICAL
  10 CONSTANT CSL-S-TRAILING
  11 CONSTANT CSL-S-CHECKSUM
  12 CONSTANT CSL-S-EVALUATE
  13 CONSTANT CSL-S-THROW
  14 CONSTANT CSL-S-CLEANUP
  15 CONSTANT CSL-S-BUSY
  16 CONSTANT CSL-S-STATE

40 CONSTANT _CSL-HEADER-U
122880 CONSTANT _CSL-RAW-MAX
0 CONSTANT _CSL-CODEC-LZSS
1 CONSTANT _CSL-CODEC-STORED

-28001 CONSTANT _CSL-X-EVAL
-28003 CONSTANT _CSL-X-ROLLBACK

CREATE _CSL-HEADER _CSL-HEADER-U ALLOT

VARIABLE _CSL-FD
VARIABLE _CSL-FILE-U
VARIABLE _CSL-PAYLOAD-A
VARIABLE _CSL-PAYLOAD-U
VARIABLE _CSL-RAW-A
VARIABLE _CSL-RAW-U
VARIABLE _CSL-CRC
VARIABLE _CSL-CODEC
VARIABLE _CSL-PRIMARY
VARIABLE _CSL-BUSY

VARIABLE _CSL-LAST-EVAL
VARIABLE _CSL-LAST-THROW
VARIABLE _CSL-CLEAN-THROW

VARIABLE _CSL-MARKED
VARIABLE _CSL-SAVED-HERE
VARIABLE _CSL-SAVED-LATEST
VARIABLE _CSL-SAVED-EDEPTH

VARIABLE _CSL-READ-A
VARIABLE _CSL-READ-U

\ Decoder state is explicit.  In particular, it never borrows the return
\ stack inside a loop: R is reserved for DO-loop state in this system.
VARIABLE _CSL-ZI
VARIABLE _CSL-ZIU
VARIABLE _CSL-ZIP
VARIABLE _CSL-ZO
VARIABLE _CSL-ZOU
VARIABLE _CSL-ZOP
VARIABLE _CSL-ZCTL
VARIABLE _CSL-ZBIT
VARIABLE _CSL-ZCODE
VARIABLE _CSL-ZDIST
VARIABLE _CSL-ZLEN
VARIABLE _CSL-ZN

: CSL-LAST-EVAL@  ( -- source-status ) _CSL-LAST-EVAL @ ;
: CSL-LAST-THROW@  ( -- throw-code ) _CSL-LAST-THROW @ ;
: CSL-LAST-CLEANUP@  ( -- throw-code ) _CSL-CLEAN-THROW @ ;

\ =====================================================================
\ Exact I/O and audited AKSRC001 header
\ =====================================================================

: _CSL-READ-EXACT  ( address length -- status )
    _CSL-READ-U ! _CSL-READ-A !
    _CSL-READ-A @ _CSL-READ-U @ _CSL-FD @ FREAD
    _CSL-READ-U @ = IF CSL-S-OK ELSE CSL-S-READ THEN ;

: _CSL-MAGIC?  ( -- flag )
    S" AKSRC001" _CSL-HEADER 8 COMPARE 0= ;

: _CSL-PAYLOAD-MAX  ( raw-length -- max-packed-length )
    DUP 7 + 8 / + ;

: _CSL-HEADER?  ( -- flag )
    _CSL-MAGIC? 0= IF 0 EXIT THEN
    _CSL-HEADER 8 + W@ 1 <> IF 0 EXIT THEN
    _CSL-HEADER 10 + W@ DUP _CSL-CODEC !
    DUP _CSL-CODEC-LZSS = SWAP _CSL-CODEC-STORED = OR
    0= IF 0 EXIT THEN
    _CSL-HEADER 12 + L@ _CSL-HEADER-U <> IF 0 EXIT THEN
    _CSL-HEADER 36 + L@ 0<> IF 0 EXIT THEN

    _CSL-HEADER 16 + @ DUP _CSL-RAW-U !
    DUP 0= SWAP _CSL-RAW-MAX U> OR IF 0 EXIT THEN
    _CSL-HEADER 24 + @ DUP _CSL-PAYLOAD-U !
    DUP 0= IF DROP 0 EXIT THEN
    _CSL-CODEC @ _CSL-CODEC-STORED = IF
        _CSL-PAYLOAD-U @ _CSL-RAW-U @ <> IF 0 EXIT THEN
    ELSE
        _CSL-PAYLOAD-U @ _CSL-RAW-U @ _CSL-PAYLOAD-MAX U> IF
            0 EXIT
        THEN
    THEN
    _CSL-FILE-U @ _CSL-HEADER-U - _CSL-PAYLOAD-U @ <> IF
        0 EXIT
    THEN
    _CSL-HEADER 32 + L@ _CSL-CRC ! -1 ;

: _CSL-ALLOC-PAYLOAD  ( -- status )
    _CSL-PAYLOAD-U @ ALLOCATE DUP IF
        2DROP CSL-S-ALLOC EXIT
    THEN
    DROP _CSL-PAYLOAD-A ! CSL-S-OK ;

: _CSL-ALLOC-RAW  ( -- status )
    _CSL-RAW-U @ ALLOCATE DUP IF
        2DROP CSL-S-ALLOC EXIT
    THEN
    DROP _CSL-RAW-A ! CSL-S-OK ;

\ =====================================================================
\ Canonical LSB-first LZSS decoder
\ =====================================================================

: _CSL-ZIN?  ( count -- flag )
    _CSL-ZIU @ _CSL-ZIP @ - U> 0= ;

: _CSL-ZOUT?  ( count -- flag )
    _CSL-ZOU @ _CSL-ZOP @ - U> 0= ;

: _CSL-ZGET  ( -- byte )
    _CSL-ZI @ _CSL-ZIP @ + C@
    1 _CSL-ZIP +! ;

: _CSL-ZPUT  ( byte -- )
    _CSL-ZO @ _CSL-ZOP @ + C!
    1 _CSL-ZOP +! ;

: _CSL-ZLITERAL  ( -- status )
    1 _CSL-ZIN? 0= IF CSL-S-TRUNCATED EXIT THEN
    1 _CSL-ZOUT? 0= IF CSL-S-OUTPUT EXIT THEN
    _CSL-ZGET _CSL-ZPUT CSL-S-OK ;

: _CSL-ZMATCH  ( -- status )
    2 _CSL-ZIN? 0= IF CSL-S-TRUNCATED EXIT THEN
    _CSL-ZGET _CSL-ZCODE !
    _CSL-ZGET 8 LSHIFT _CSL-ZCODE +!
    _CSL-ZCODE @ 4 RSHIFT 1+ DUP _CSL-ZDIST !
    DUP 4096 U> SWAP _CSL-ZOP @ U> OR IF
        CSL-S-DISTANCE EXIT
    THEN
    _CSL-ZCODE @ 15 AND 3 + DUP _CSL-ZLEN !
    _CSL-ZOUT? 0= IF CSL-S-OUTPUT EXIT THEN
    0 _CSL-ZN !
    BEGIN _CSL-ZN @ _CSL-ZLEN @ U< WHILE
        _CSL-ZO @ _CSL-ZOP @ _CSL-ZDIST @ - + C@
        _CSL-ZPUT
        1 _CSL-ZN +!
    REPEAT
    CSL-S-OK ;

: _CSL-ZTOKEN  ( -- status )
    _CSL-ZCTL @ 1 AND IF _CSL-ZLITERAL ELSE _CSL-ZMATCH THEN ;

: _CSL-ZGROUP  ( -- status )
    1 _CSL-ZIN? 0= IF CSL-S-TRUNCATED EXIT THEN
    _CSL-ZGET _CSL-ZCTL ! 0 _CSL-ZBIT !
    BEGIN
        _CSL-ZBIT @ 8 U< _CSL-ZOP @ _CSL-ZOU @ U< AND
    WHILE
        _CSL-ZTOKEN DUP IF EXIT THEN DROP
        _CSL-ZCTL @ 1 RSHIFT _CSL-ZCTL !
        1 _CSL-ZBIT +!
    REPEAT
    _CSL-ZOP @ _CSL-ZOU @ = IF
        _CSL-ZCTL @ 0<> IF CSL-S-CANONICAL EXIT THEN
    THEN
    CSL-S-OK ;

: _CSL-DECODE  ( input input-u output output-u -- status )
    _CSL-ZOU ! _CSL-ZO ! _CSL-ZIU ! _CSL-ZI !
    0 _CSL-ZIP ! 0 _CSL-ZOP !
    BEGIN _CSL-ZOP @ _CSL-ZOU @ U< WHILE
        _CSL-ZGROUP DUP IF EXIT THEN DROP
    REPEAT
    _CSL-ZIP @ _CSL-ZIU @ <> IF
        CSL-S-TRAILING
    ELSE
        CSL-S-OK
    THEN ;

\ =====================================================================
\ Failure-atomic checked evaluation
\ =====================================================================

: _CSL-EVAL-BODY  ( i*x -- j*x )
    _CSL-RAW-A @ _CSL-RAW-U @ SOURCE-EVALUATE-CHECKED
    DUP _CSL-LAST-EVAL !
    ?DUP IF DROP _CSL-X-EVAL THROW THEN ;

: _CSL-EVALUATE  ( i*x -- j*x status )
    HERE _CSL-SAVED-HERE !
    LATEST _CSL-SAVED-LATEST !
    EVAL-DEPTH @ _CSL-SAVED-EDEPTH !
    -1 _CSL-MARKED !
    ['] _CSL-EVAL-BODY CATCH
    DUP 0= IF
        DROP 0 _CSL-MARKED ! CSL-S-OK EXIT
    THEN
    DUP _CSL-X-EVAL = IF DROP CSL-S-EVALUATE EXIT THEN
    THROW ;

\ =====================================================================
\ Independent cleanup owners
\ =====================================================================

: _CSL-CLOSE-OWNER  ( -- )
    _CSL-FD @ ?DUP IF (FCLOSE-NOFS) 0 _CSL-FD ! THEN ;

: _CSL-FREE-RAW  ( -- )
    _CSL-RAW-A @ ?DUP IF FREE 0 _CSL-RAW-A ! THEN ;

: _CSL-FREE-PAYLOAD  ( -- )
    _CSL-PAYLOAD-A @ ?DUP IF FREE 0 _CSL-PAYLOAD-A ! THEN ;

: _CSL-ROLLBACK  ( -- )
    _CSL-MARKED @ 0= IF EXIT THEN
    HERE _CSL-SAVED-HERE @ U< IF _CSL-X-ROLLBACK THROW THEN
    _CSL-SAVED-HERE @ _CSL-SAVED-LATEST @ DICT-ROLLBACK
    EVALUATOR-RESET
    _CSL-SAVED-EDEPTH @ EVAL-DEPTH !
    0 _CSL-MARKED ! ;

: _CSL-CLEAN-ONE  ( xt -- )
    CATCH ?DUP IF
        _CSL-CLEAN-THROW @ 0= IF
            _CSL-CLEAN-THROW !
        ELSE
            DROP
        THEN
    THEN ;

: _CSL-CLEANUP  ( -- )
    ['] _CSL-CLOSE-OWNER _CSL-CLEAN-ONE
    ['] _CSL-ROLLBACK _CSL-CLEAN-ONE
    ['] _CSL-FREE-RAW _CSL-CLEAN-ONE
    ['] _CSL-FREE-PAYLOAD _CSL-CLEAN-ONE ;

: _CSL-OWNED?  ( -- flag )
    _CSL-FD @ 0<>
    _CSL-PAYLOAD-A @ 0<> OR
    _CSL-RAW-A @ 0<> OR
    _CSL-MARKED @ 0<> OR ;

: _CSL-RESET  ( -- )
    0 _CSL-FD ! 0 _CSL-FILE-U !
    0 _CSL-PAYLOAD-A ! 0 _CSL-PAYLOAD-U !
    0 _CSL-RAW-A ! 0 _CSL-RAW-U ! 0 _CSL-CRC ! 0 _CSL-CODEC !
    0 _CSL-PRIMARY ! 0 _CSL-MARKED !
    0 _CSL-SAVED-HERE ! 0 _CSL-SAVED-LATEST !
    0 _CSL-SAVED-EDEPTH !
    0 _CSL-LAST-EVAL ! 0 _CSL-LAST-THROW !
    0 _CSL-CLEAN-THROW ! ;

_CSL-RESET 0 _CSL-BUSY !

\ =====================================================================
\ Operation owner and public parsing entry
\ =====================================================================

: _CSL-RUN  ( i*x -- j*x status )
    OPEN DUP 0= IF DROP CSL-S-OPEN EXIT THEN _CSL-FD !
    \ FREAD follows only the primary MP64FS extent.  Qualification media
    \ enforces this at build time; reject a mismatched file here as well.
    _CSL-FD @ 48 + @ IF CSL-S-SIZE EXIT THEN
    _CSL-FD @ FSIZE DUP _CSL-FILE-U !
    _CSL-HEADER-U U< IF CSL-S-SIZE EXIT THEN
    _CSL-HEADER _CSL-HEADER-U _CSL-READ-EXACT
    DUP IF EXIT THEN DROP
    _CSL-HEADER? 0= IF CSL-S-HEADER EXIT THEN

    _CSL-ALLOC-RAW DUP IF EXIT THEN DROP
    _CSL-CODEC @ _CSL-CODEC-STORED = IF
        _CSL-RAW-A @ _CSL-RAW-U @ _CSL-READ-EXACT
        DUP IF EXIT THEN DROP
        _CSL-CLOSE-OWNER
    ELSE
        _CSL-ALLOC-PAYLOAD DUP IF EXIT THEN DROP
        _CSL-PAYLOAD-A @ _CSL-PAYLOAD-U @ _CSL-READ-EXACT
        DUP IF EXIT THEN DROP
        _CSL-CLOSE-OWNER
        _CSL-PAYLOAD-A @ _CSL-PAYLOAD-U @
        _CSL-RAW-A @ _CSL-RAW-U @ _CSL-DECODE
        DUP IF EXIT THEN DROP
    THEN
    _CSL-RAW-A @ _CSL-RAW-U @ CRC32-IEEE-BUF
    _CSL-CRC @ <> IF CSL-S-CHECKSUM EXIT THEN
    _CSL-EVALUATE ;

: _CSL-DROP-NAME  ( -- ) PARSE-NAME 2DROP ;

: COLD-SOURCE-LOAD  ( i*x "filename" -- j*x status )
    _CSL-BUSY @ IF _CSL-DROP-NAME CSL-S-BUSY EXIT THEN
    _CSL-OWNED? IF
        0 _CSL-CLEAN-THROW ! _CSL-CLEANUP
        _CSL-CLEAN-THROW @ IF
            _CSL-DROP-NAME CSL-S-CLEANUP EXIT
        THEN
        _CSL-OWNED? IF _CSL-DROP-NAME CSL-S-STATE EXIT THEN
    THEN
    _CSL-RESET -1 _CSL-BUSY !
    ['] _CSL-RUN CATCH
    DUP IF
        _CSL-LAST-THROW ! CSL-S-THROW
    ELSE
        DROP
    THEN
    _CSL-PRIMARY !
    _CSL-CLEANUP 0 _CSL-BUSY !
    _CSL-PRIMARY @ DUP IF EXIT THEN DROP
    _CSL-CLEAN-THROW @ IF CSL-S-CLEANUP ELSE CSL-S-OK THEN ;
