\ bridge.f — HTML↔CSS bridge
\
\ Connects akashic-html and akashic-css for element-level
\ style computation.  Extracts tag, id, class from HTML
\ cursors and feeds them into CSS selector matching.
\
\ Prefix: CSSB-   (public API)
\         _CSSB-  (internal helpers)
\
\ Load with:   REQUIRE bridge.f

PROVIDED akashic-css-bridge
REQUIRE ../markup/html.f
REQUIRE css.f

\ =====================================================================
\  Element Setup
\ =====================================================================
\
\ Extracts tag name, id, and class attribute from an HTML element
\ cursor and configures CSS-MATCH-SET for selector matching.

VARIABLE _CSSB-TA   VARIABLE _CSSB-TL
VARIABLE _CSSB-IA   VARIABLE _CSSB-IL
VARIABLE _CSSB-CA   VARIABLE _CSSB-CL

\ "id" literal — 2 bytes packed in a cell
VARIABLE _CSSB-ID-LIT
25705 _CSSB-ID-LIT !

\ "class" literal — 5 bytes
CREATE _CSSB-CLS-LIT  99 C, 108 C, 97 C, 115 C, 115 C,

\ "style" literal — 5 bytes
CREATE _CSSB-STY-LIT  115 C, 116 C, 121 C, 108 C, 101 C,

\ _CSSB-SETUP ( html-a html-u -- )
\   Extract tag, id, class from HTML element and set CSS match state.
: _CSSB-SETUP  ( html-a html-u -- )
    2DUP MU-GET-TAG-NAME
    _CSSB-TL !  _CSSB-TA !  2DROP
    2DUP _CSSB-ID-LIT 2 HTML-ATTR?
    IF   _CSSB-IL !  _CSSB-IA !
    ELSE 2DROP 0 _CSSB-IL !  0 _CSSB-IA !  THEN
    _CSSB-CLS-LIT 5 HTML-ATTR?
    IF   _CSSB-CL !  _CSSB-CA !
    ELSE 2DROP 0 _CSSB-CL !  0 _CSSB-CA !  THEN
    _CSSB-TA @ _CSSB-TL @
    _CSSB-IA @ _CSSB-IL @
    _CSSB-CA @ _CSSB-CL @
    CSS-MATCH-SET ;

\ =====================================================================
\  Selector Matching
\ =====================================================================

VARIABLE _CBME-SA   VARIABLE _CBME-SL
VARIABLE _CBMC-F

\ _CSSB-MATCH-COMPOUND ( sel-a sel-u -- sel-a' sel-u' flag )
\   Match all simple selectors in one compound selector.
\   Stops at combinator or end of selector.
\   All simple selectors must match the current element.
: _CSSB-MATCH-COMPOUND  ( sel-a sel-u -- sel-a' sel-u' flag )
    -1 _CBMC-F !
    BEGIN
        CSS-SEL-NEXT-SIMPLE
    WHILE
        CSS-MATCH-SIMPLE
        0= IF 0 _CBMC-F ! THEN
    REPEAT
    2DROP DROP
    _CBMC-F @ ;

\ CSSB-MATCH-SELECTOR ( sel-a sel-u -- flag )
\   Match one selector (one group, no commas) against the element
\   set by _CSSB-SETUP / CSS-MATCH-SET.
\   Only checks the last compound selector (ignores ancestors).
: CSSB-MATCH-SELECTOR  ( sel-a sel-u -- flag )
    BEGIN
        _CSSB-MATCH-COMPOUND
        >R CSS-SEL-COMBINATOR
    WHILE
        DROP R> DROP
    REPEAT
    DROP 2DROP R> ;

\ _CSSB-MATCH-GROUPS ( sel-a sel-u -- flag )
\   Check if any comma-separated selector group matches.
: _CSSB-MATCH-GROUPS  ( sel-a sel-u -- flag )
    BEGIN
        CSS-SEL-GROUP-NEXT
    WHILE
        CSSB-MATCH-SELECTOR
        IF 2DROP -1 EXIT THEN
    REPEAT
    2DROP 2DROP 0 ;

\ CSSB-MATCH-ELEMENT ( sel-a sel-u html-a html-u -- flag )
\   Does any selector group match this HTML element?
\   Extracts tag/id/class from the element, then checks
\   each comma-separated selector group.
: CSSB-MATCH-ELEMENT  ( sel-a sel-u html-a html-u -- flag )
    2SWAP _CBME-SL !  _CBME-SA !
    _CSSB-SETUP
    _CBME-SA @ _CBME-SL @ _CSSB-MATCH-GROUPS ;

\ =====================================================================
\  Style Collection
\ =====================================================================

VARIABLE _CGS-BA    VARIABLE _CGS-BL
VARIABLE _CGS-MX
VARIABLE _CGS-CSA   VARIABLE _CGS-CSL
VARIABLE _CGS-SA    VARIABLE _CGS-SL
VARIABLE _CGS-BOA   VARIABLE _CGS-BOL

\ _CSSB-APPEND-SEP ( -- )
\   Append "; " separator to buffer if non-empty.
: _CSSB-APPEND-SEP  ( -- )
    _CGS-BL @ 0= IF EXIT THEN
    _CGS-BL @ 2 + _CGS-MX @ > IF EXIT THEN
    59 _CGS-BA @ _CGS-BL @ + C!  1 _CGS-BL +!
    32 _CGS-BA @ _CGS-BL @ + C!  1 _CGS-BL +! ;

\ _CSSB-APPEND ( src-a src-u -- )
\   Append string to buffer, checking bounds.
: _CSSB-APPEND  ( src-a src-u -- )
    DUP _CGS-BL @ + _CGS-MX @ > IF
        2DROP EXIT
    THEN
    DUP >R
    _CGS-BA @ _CGS-BL @ + SWAP CMOVE
    R> _CGS-BL +! ;

\ _CSSB-COLLECT ( css-a css-u -- )
\   Internal: iterate CSS rules, match selectors, append bodies.
\   Assumes element match state and buffer are configured.
: _CSSB-COLLECT  ( css-a css-u -- )
    BEGIN
        CSS-RULE-NEXT
    WHILE
        _CGS-BOL ! _CGS-BOA !
        _CGS-SL !  _CGS-SA !
        _CGS-SA @ _CGS-SL @ _CSSB-MATCH-GROUPS
        IF
            _CSSB-APPEND-SEP
            _CGS-BOA @ _CGS-BOL @
            CSS-SKIP-WS _CSS-TRIM-END
            _CSSB-APPEND
        THEN
    REPEAT
    2DROP 2DROP 2DROP ;

\ CSSB-GET-STYLES ( css-a css-u html-a html-u buf max -- n )
\   Collect matching CSS declarations for an HTML element.
\   Iterates rules in document order.  For each matching rule,
\   appends its declaration body to buf separated by "; ".
\   Returns number of bytes written.
: CSSB-GET-STYLES  ( css-a css-u html-a html-u buf max -- n )
    _CGS-MX !  _CGS-BA !
    0 _CGS-BL !
    2SWAP _CGS-CSL !  _CGS-CSA !
    _CSSB-SETUP
    _CGS-CSA @ _CGS-CSL @ _CSSB-COLLECT
    _CGS-BL @ ;

\ CSSB-APPLY-INLINE ( css-a css-u html-a html-u buf max -- n )
\   Like CSSB-GET-STYLES but also merges inline style="" attribute.
\   Inline styles appear last (highest effective specificity).
\   Returns number of bytes written.
VARIABLE _CAI-HA   VARIABLE _CAI-HL

: CSSB-APPLY-INLINE  ( css-a css-u html-a html-u buf max -- n )
    _CGS-MX !  _CGS-BA !
    0 _CGS-BL !
    2DUP _CAI-HL !  _CAI-HA !
    2SWAP _CGS-CSL !  _CGS-CSA !
    _CSSB-SETUP
    _CGS-CSA @ _CGS-CSL @ _CSSB-COLLECT
    \ Append inline style="" if present
    _CAI-HA @ _CAI-HL @ _CSSB-STY-LIT 5 HTML-ATTR?
    IF
        DUP 0> IF
            _CSSB-APPEND-SEP
            _CSSB-APPEND
        ELSE 2DROP THEN
    ELSE 2DROP THEN
    _CGS-BL @ ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _cssbr-guard

' CSSB-MATCH-SELECTOR CONSTANT _cssb-match-selector-xt
' CSSB-MATCH-ELEMENT CONSTANT _cssb-match-element-xt
' CSSB-GET-STYLES CONSTANT _cssb-get-styles-xt
' CSSB-APPLY-INLINE CONSTANT _cssb-apply-inline-xt

: CSSB-MATCH-SELECTOR _cssb-match-selector-xt _cssbr-guard WITH-GUARD ;
: CSSB-MATCH-ELEMENT _cssb-match-element-xt _cssbr-guard WITH-GUARD ;
: CSSB-GET-STYLES _cssb-get-styles-xt _cssbr-guard WITH-GUARD ;
: CSSB-APPLY-INLINE _cssb-apply-inline-xt _cssbr-guard WITH-GUARD ;
[THEN] [THEN]
