\ template.f — HTML builder DSL / micro-templates for KDOS
\
\ Two approaches over html.f:
\   A — Compositional words: TPL-PAGE, TPL-LINK, TPL-LIST, etc.
\   B — Micro-templates: TPL-VAR!, TPL-EXPAND with {{ name }}
\
\ All compositional words emit into the html.f builder output
\ (set up by the caller via HTML-SET-OUTPUT).
\
\ Prefix: TPL-   (public API)
\         _TPL-  (internal helpers)
\
\ Load with:   REQUIRE template.f

REQUIRE ../markup/html.f
REQUIRE ../utils/string.f

PROVIDED akashic-web-template

\ =====================================================================
\  Internal State
\ =====================================================================

VARIABLE _TPL-A1  VARIABLE _TPL-U1
VARIABLE _TPL-A2  VARIABLE _TPL-U2
VARIABLE _TPL-XT

\ =====================================================================
\  Approach A — Compositional Words
\ =====================================================================

\ TPL-PAGE ( title-a title-u body-xt -- )
\   Emit full HTML5 page: DOCTYPE + html + head + meta + title + body.
\   body-xt is EXECUTEd to produce body content.
: TPL-PAGE  ( title-a title-u body-xt -- )
    _TPL-XT !
    HTML-DOCTYPE
    S" html" HTML-<  HTML->
    S" head" HTML-<  HTML->
    S" meta" HTML-<  S" charset" S" utf-8" HTML-ATTR!  HTML-/>
    S" title" HTML-<  HTML->  HTML-TEXT!  S" title" HTML-</
    S" head" HTML-</
    S" body" HTML-<  HTML->
    _TPL-XT @ EXECUTE
    S" body" HTML-</
    S" html" HTML-</ ;

\ TPL-LINK ( href-a href-u text-a text-u -- )
\   Emit <a href="href">text</a>.
: TPL-LINK  ( href-a href-u text-a text-u -- )
    _TPL-U2 !  _TPL-A2 !
    _TPL-U1 !  _TPL-A1 !
    S" a" HTML-<
    S" href" _TPL-A1 @ _TPL-U1 @ HTML-ATTR!
    HTML->
    _TPL-A2 @ _TPL-U2 @ HTML-TEXT!
    S" a" HTML-</ ;

\ TPL-LIST ( n xt -- )
\   Emit <ul> with n <li> items.  xt receives index ( I -- ).
: TPL-LIST  ( n xt -- )
    _TPL-XT !
    S" ul" HTML-<  HTML->
    0 ?DO
        S" li" HTML-<  HTML->
        I _TPL-XT @ EXECUTE
        S" li" HTML-</
    LOOP
    S" ul" HTML-</ ;

\ TPL-TABLE-ROW ( n-cols xt -- )
\   Emit <tr> with n <td> cells.  xt receives column index ( I -- ).
: TPL-TABLE-ROW  ( n-cols xt -- )
    _TPL-XT !
    S" tr" HTML-<  HTML->
    0 ?DO
        S" td" HTML-<  HTML->
        I _TPL-XT @ EXECUTE
        S" td" HTML-</
    LOOP
    S" tr" HTML-</ ;

\ TPL-FORM ( action-a action-u method-a method-u body-xt -- )
\   Emit <form action="..." method="..."> body </form>.
: TPL-FORM  ( action-a action-u method-a method-u body-xt -- )
    _TPL-XT !
    _TPL-U2 !  _TPL-A2 !
    _TPL-U1 !  _TPL-A1 !
    S" form" HTML-<
    S" action" _TPL-A1 @ _TPL-U1 @ HTML-ATTR!
    S" method" _TPL-A2 @ _TPL-U2 @ HTML-ATTR!
    HTML->
    _TPL-XT @ EXECUTE
    S" form" HTML-</ ;

\ TPL-INPUT ( type-a type-u name-a name-u -- )
\   Emit <input type="..." name="...">.
: TPL-INPUT  ( type-a type-u name-a name-u -- )
    _TPL-U2 !  _TPL-A2 !
    _TPL-U1 !  _TPL-A1 !
    S" input" HTML-<
    S" type" _TPL-A1 @ _TPL-U1 @ HTML-ATTR!
    S" name" _TPL-A2 @ _TPL-U2 @ HTML-ATTR!
    HTML-/> ;

\ =====================================================================
\  Approach B — Micro-Template Expansion
\ =====================================================================

16 CONSTANT _TPL-MAX-VARS
160 CONSTANT _TPL-VSLOT-SZ

\ Slot layout (160 bytes each):
\   +0   name length   (1 cell = 8 bytes)
\   +8   name chars    (24 bytes)
\   +32  value length  (1 cell = 8 bytes)
\   +40  value chars   (120 bytes)

CREATE _TPL-VARS 2560 ALLOT
VARIABLE _TPL-NVAR
0 _TPL-NVAR !

CREATE _TPL-OUT-BUF 4096 ALLOT
VARIABLE _TPL-OUT-POS
4096 CONSTANT _TPL-OUT-MAX

: _TPL-SLOT  ( idx -- addr )  _TPL-VSLOT-SZ * _TPL-VARS + ;

\ ── Variable Lookup ──

VARIABLE _TVF-NA  VARIABLE _TVF-NU

: _TPL-VAR-FIND  ( name-a name-u -- slot-addr | 0 )
    _TVF-NU !  _TVF-NA !
    _TPL-NVAR @ 0 ?DO
        I _TPL-SLOT DUP
        DUP @ SWAP 8 +
        SWAP
        _TVF-NA @ _TVF-NU @
        STR-STR= IF UNLOOP EXIT THEN
        DROP
    LOOP
    0 ;

\ ── Variable Set / Clear ──

VARIABLE _TV-VA  VARIABLE _TV-VU
VARIABLE _TV-NA  VARIABLE _TV-NU

\ TPL-VAR! ( val-a val-u name-a name-u -- )
\   Set a template variable.  Updates existing or allocates new.
: TPL-VAR!  ( val-a val-u name-a name-u -- )
    _TV-NU !  _TV-NA !  _TV-VU !  _TV-VA !
    _TV-NA @ _TV-NU @ _TPL-VAR-FIND
    DUP IF
        DUP 32 + _TV-VU @ SWAP !
        40 + _TV-VA @ SWAP _TV-VU @ CMOVE
        EXIT
    THEN
    DROP
    _TPL-NVAR @ _TPL-MAX-VARS >= IF EXIT THEN
    _TPL-NVAR @ _TPL-SLOT
    DUP _TV-NU @ SWAP !
    DUP 8 + _TV-NA @ SWAP _TV-NU @ CMOVE
    DUP 32 + _TV-VU @ SWAP !
    40 + _TV-VA @ SWAP _TV-VU @ CMOVE
    1 _TPL-NVAR +! ;

\ TPL-VAR-CLEAR ( -- )
\   Reset all template variables.
: TPL-VAR-CLEAR  ( -- )  0 _TPL-NVAR ! ;

\ ── Output Helpers ──

: _TPL-OUT-CH  ( c -- )
    _TPL-OUT-POS @ _TPL-OUT-MAX < IF
        _TPL-OUT-BUF _TPL-OUT-POS @ + C!
        1 _TPL-OUT-POS +!
    ELSE DROP THEN ;

: _TPL-OUT-STR  ( a u -- )
    0 ?DO DUP I + C@ _TPL-OUT-CH LOOP DROP ;

\ ── Pattern Scanning ──

\ _TPL-FIND-OPEN ( a u -- offset | -1 )
\   Find first {{ in string.  Returns byte offset or -1.
: _TPL-FIND-OPEN  ( a u -- offset | -1 )
    DUP 2 < IF 2DROP -1 EXIT THEN
    1- 0 ?DO
        DUP I + C@ 123 =
        OVER I + 1+ C@ 123 = AND IF
            DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ _TPL-FIND-CLOSE ( a u -- offset | -1 )
\   Find first }} in string.  Returns byte offset or -1.
: _TPL-FIND-CLOSE  ( a u -- offset | -1 )
    DUP 2 < IF 2DROP -1 EXIT THEN
    1- 0 ?DO
        DUP I + C@ 125 =
        OVER I + 1+ C@ 125 = AND IF
            DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ ── Template Expansion ──

\ TPL-EXPAND ( tmpl-a tmpl-u -- result-a result-u )
\   Replace {{ name }} placeholders with variable values.
\   Unknown variables produce empty output.  Result is in
\   _TPL-OUT-BUF (static — not re-entrant).
: TPL-EXPAND  ( tmpl-a tmpl-u -- result-a result-u )
    0 _TPL-OUT-POS !
    BEGIN DUP 0> WHILE
        2DUP _TPL-FIND-OPEN
        DUP 0< IF
            DROP _TPL-OUT-STR  0 0
        ELSE
            >R
            OVER R@ _TPL-OUT-STR
            R> 2 + /STRING
            2DUP _TPL-FIND-CLOSE
            DUP 0< IF
                DROP
                123 _TPL-OUT-CH 123 _TPL-OUT-CH
                _TPL-OUT-STR  0 0
            ELSE
                >R
                OVER R@ STR-TRIM
                _TPL-VAR-FIND DUP IF
                    DUP 32 + @ SWAP 40 + SWAP _TPL-OUT-STR
                ELSE DROP THEN
                R> 2 + /STRING
            THEN
        THEN
    REPEAT
    2DROP
    _TPL-OUT-BUF _TPL-OUT-POS @ ;
