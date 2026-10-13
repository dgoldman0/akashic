\ =====================================================================
\  akashic/utils/fs/link-path.f — the path a document's link names
\ =====================================================================
\
\  A link in a document names a file by a path from the folder of the
\  file that holds the link, or from the root when it starts with "/".
\  LPATH-RESOLVE turns such a target into the path it names: empty and
\  "." steps add nothing, ".." goes back one folder, and a #fragment or
\  ?query is left out.  A target that begins with a URI scheme (RFC 3986:
\  a letter, then letters, digits, "+", "-" or ".", then ":") is no path
\  at all, such as https: or mailto:.
\
\  The path is absolute when the target or the base is, and ".." never
\  goes above the root; a link to the root gives "/".  From a relative
\  base it stays relative, for a file system to take from its current
\  folder: ".." steps it cannot undo stay at its start, and a link to
\  that folder gives ".".
\
\  The path goes into the caller's buffer, and is never longer than
\  LPATH-BOUND, the base's length and the target's and one byte more, so
\  a caller can size the buffer exactly.
\
\  Public API:
\    LPATH-BOUND    ( target-u base-u -- bytes )
\    LPATH-RESOLVE  ( target-a target-u base-a base-u buf cap -- u status )
\        BASE is the path of the file that holds the link, or 0 0 for
\        none, which starts a relative target at the root.
\
\  Prefix: LPATH- (public), _LP- (internal)
\  Provider: akashic-link-path
\  Dependencies: ../string.f

PROVIDED akashic-link-path

REQUIRE ../string.f

0 CONSTANT LPATH-S-OK
1 CONSTANT LPATH-S-EMPTY     \ no path: empty, or only a #fragment or ?query
2 CONSTANT LPATH-S-SCHEME    \ a scheme, such as https:, so no file
3 CONSTANT LPATH-S-ROOM      \ the path does not fit the caller's buffer

: LPATH-BOUND  ( target-u base-u -- bytes )  + 1+ ;

VARIABLE _LP-BUF
VARIABLE _LP-CAP
VARIABLE _LP-U

\ The target up to its first # or ?.
: _LP-CUT  ( a u -- a u' )
    DUP 0 ?DO
        OVER I + C@ DUP 35 = SWAP 63 = OR IF DROP I UNLOOP EXIT THEN
    LOOP ;

: _LP-ALPHA?  ( c -- flag )  32 OR 97 123 WITHIN ;

: _LP-SCHEME-CHAR?  ( c -- flag )
    DUP _LP-ALPHA? OVER 48 58 WITHIN OR OVER 43 = OR OVER 45 = OR SWAP 46 = OR ;

\ Whether the target begins with a scheme and its colon.
: _LP-SCHEME?  ( a u -- flag )
    DUP 0= IF NIP EXIT THEN
    OVER C@ _LP-ALPHA? 0= IF 2DROP 0 EXIT THEN
    1 ?DO
        DUP I + C@
        DUP 58 = IF 2DROP -1 UNLOOP EXIT THEN
        _LP-SCHEME-CHAR? 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP 0 ;

VARIABLE _LP-ABS      \ the path starts at the root
VARIABLE _LP-STEPS    \ its steps
VARIABLE _LP-UPS      \ the ".." steps at the start of a relative path

\ Add a step after a "/", or alone at the start of a relative path.
\ False when it does not fit.
: _LP-PUT  ( a u -- ok? )
    _LP-U @ 0> _LP-ABS @ OR IF
        _LP-U @ OVER + 1+ _LP-CAP @ > IF 2DROP 0 EXIT THEN
        47 _LP-BUF @ _LP-U @ + C!  1 _LP-U +!
    ELSE
        _LP-U @ OVER + _LP-CAP @ > IF 2DROP 0 EXIT THEN
    THEN
    TUCK _LP-BUF @ _LP-U @ + SWAP MOVE _LP-U +!
    1 _LP-STEPS +! -1 ;

\ Leave out the last step and the "/" before it.
: _LP-DROP-STEP  ( -- )
    BEGIN _LP-U @ 0> WHILE
        -1 _LP-U +!
        _LP-BUF @ _LP-U @ + C@ 47 = IF -1 _LP-STEPS +! EXIT THEN
    REPEAT
    -1 _LP-STEPS +! ;

\ Add one step: nothing for an empty step or ".", and for ".." back one
\ folder, or another ".." at the start of a relative path.
: _LP-STEP  ( a u -- ok? )
    DUP 0= IF 2DROP -1 EXIT THEN
    2DUP S" ." STR-STR= IF 2DROP -1 EXIT THEN
    2DUP S" .." STR-STR= IF
        _LP-STEPS @ _LP-UPS @ > IF 2DROP _LP-DROP-STEP -1 EXIT THEN
        _LP-ABS @ IF 2DROP -1 EXIT THEN
        _LP-PUT DUP IF 1 _LP-UPS +! THEN EXIT
    THEN
    _LP-PUT ;

VARIABLE _LP-A
VARIABLE _LP-N

\ Add each /-separated step of a path.
: _LP-PATH  ( a u -- ok? )
    _LP-N ! _LP-A !
    BEGIN _LP-N @ 0> WHILE
        _LP-A @ _LP-N @ 47 STR-INDEX DUP 0< IF DROP _LP-N @ THEN
        _LP-A @ OVER _LP-STEP 0= IF DROP 0 EXIT THEN
        1+ _LP-N @ MIN DUP _LP-A +! NEGATE _LP-N +!
    REPEAT
    -1 ;

\ The folder a path's file lies in: the path up to its last /.
: _LP-FOLDER  ( a u -- a u' )
    2DUP 47 STR-RINDEX DUP 0< IF 2DROP 0 ELSE NIP THEN ;

: LPATH-RESOLVE  ( target-a target-u base-a base-u buf cap -- u status )
    _LP-CAP ! _LP-BUF ! 0 _LP-U ! 0 _LP-STEPS ! 0 _LP-UPS !
    2SWAP _LP-CUT                                   ( base-a base-u t-a t-u )
    DUP 0= IF 2DROP 2DROP 0 LPATH-S-EMPTY EXIT THEN
    2DUP _LP-SCHEME? IF 2DROP 2DROP 0 LPATH-S-SCHEME EXIT THEN
    OVER C@ 47 = IF
        -1 _LP-ABS ! 2SWAP 2DROP
    ELSE
        2SWAP DUP 0= IF -1 ELSE OVER C@ 47 = THEN _LP-ABS !
        _LP-FOLDER _LP-PATH 0= IF 2DROP 0 LPATH-S-ROOM EXIT THEN
    THEN
    _LP-PATH 0= IF 0 LPATH-S-ROOM EXIT THEN
    _LP-U @ 0= IF
        _LP-CAP @ 0= IF 0 LPATH-S-ROOM EXIT THEN
        _LP-ABS @ IF 47 ELSE 46 THEN _LP-BUF @ C! 1 _LP-U !
    THEN
    _LP-U @ LPATH-S-OK ;

\ =====================================================================
\  Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _lpath-guard

' LPATH-RESOLVE CONSTANT _lpath-resolve-xt

: LPATH-RESOLVE  _lpath-resolve-xt _lpath-guard WITH-GUARD ;
[THEN] [THEN]
