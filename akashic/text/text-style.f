\ =================================================================
\  text-style.f — what the parts of a text mean
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TSTY- / _TSTY-
\  Depends on: utf8.f
\
\  A style says what a stretch of text means, never how it looks:
\  each display chooses its own look.  The ten meanings below are
\  the shared list of the rich terminal's semantic text
\  (SEMANTIC-CONTENT-1, style runs), with the same values, so a
\  producer passes them through unchanged.
\
\  A style map holds one meaning per byte of a line, 0 for plain
\  text.  A highlighter (syntax.f) fills one.  A character takes the
\  meaning of its first scalar, and TSTY-RUNS turns a map into runs
\  of scalars, which is how semantic text carries styles.  A scalar is
\  what UTF8-DECODE reads: one character, or one ill-formed part of a
\  sequence, which a display shows as U+FFFD.
\
\  Public API:
\    TSTY-PLAIN .. TSTY-ERROR   meanings 0-10
\    TSTY-COUNT   ( -- n )       meanings including plain
\    TSTY-VALID?  ( meaning -- flag )   one of the ten, not plain
\    TSTY-RUNS    ( text-a text-u map xt -- ok? )
\        Call XT ( start length meaning -- ok? ) for each run of
\        scalars that share one meaning other than plain, in order.
\        Stops and returns false when XT does.
\ =================================================================

PROVIDED akashic-text-style

REQUIRE utf8.f

 0 CONSTANT TSTY-PLAIN
 1 CONSTANT TSTY-KEYWORD      \ a keyword of a programming language
 2 CONSTANT TSTY-COMMENT
 3 CONSTANT TSTY-STRING       \ a string or character literal
 4 CONSTANT TSTY-NUMBER       \ a numeric literal
 5 CONSTANT TSTY-HEADING
 6 CONSTANT TSTY-EMPHASIS
 7 CONSTANT TSTY-STRONG
 8 CONSTANT TSTY-CODE         \ code set within prose
 9 CONSTANT TSTY-LINK         \ a link the reader can follow
10 CONSTANT TSTY-ERROR        \ text the application reports as wrong
11 CONSTANT TSTY-COUNT

: TSTY-VALID?  ( meaning -- flag )  1 TSTY-COUNT WITHIN ;

\ =================================================================
\  Runs of scalars
\ =================================================================
\
\  Each scalar takes the meaning in the map at its first byte; the
\  entries of its other bytes are never read.  A meaning outside the
\  list counts as plain.  Neighbouring scalars that share a meaning
\  form one run, so two runs with the same meaning never touch.

VARIABLE _TSTY-A      \ text
VARIABLE _TSTY-U
VARIABLE _TSTY-MAP
VARIABLE _TSTY-XT
VARIABLE _TSTY-I      \ byte index
VARIABLE _TSTY-N      \ scalars before it
VARIABLE _TSTY-M      \ meaning of the open run, 0 when none
VARIABLE _TSTY-S      \ its first scalar

\ _TSTY-UNIT ( -- bytes )   The bytes of the scalar at _TSTY-I.
: _TSTY-UNIT  ( -- bytes )
    _TSTY-A @ _TSTY-I @ + DUP C@ 0x80 < IF DROP 1 EXIT THEN
    _TSTY-U @ _TSTY-I @ - UTF8-UNIT-BYTES ;

: _TSTY-CLOSE  ( -- ok? )
    _TSTY-M @ 0= IF -1 EXIT THEN
    _TSTY-S @ _TSTY-N @ OVER - _TSTY-M @ _TSTY-XT @ EXECUTE ;

: TSTY-RUNS  ( text-a text-u map xt -- ok? )
    _TSTY-XT ! _TSTY-MAP ! _TSTY-U ! _TSTY-A !
    0 _TSTY-I ! 0 _TSTY-N ! 0 _TSTY-M ! 0 _TSTY-S !
    BEGIN _TSTY-I @ _TSTY-U @ < WHILE
        _TSTY-MAP @ _TSTY-I @ + C@
        DUP TSTY-VALID? 0= IF DROP TSTY-PLAIN THEN
        DUP _TSTY-M @ <> IF
            _TSTY-CLOSE 0= IF DROP 0 EXIT THEN
            _TSTY-M ! _TSTY-N @ _TSTY-S !
        ELSE DROP THEN
        1 _TSTY-N +!
        _TSTY-UNIT _TSTY-I +!
    REPEAT
    _TSTY-CLOSE ;

\ =================================================================
\  Guard
\ =================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _tsty-guard

' TSTY-RUNS CONSTANT _tsty-runs-xt

: TSTY-RUNS  _tsty-runs-xt _tsty-guard WITH-GUARD ;
[THEN] [THEN]
