\ core.f — SML parser core for KDOS / Megapad-64
\
\ Element classification, validation, and attribute extraction
\ for the Sequential Markup Language (SML) — the modality-neutral
\ document format for 1D user interfaces.
\
\ SML uses angle-bracket XML syntax.  This module builds on
\ markup/core.f for low-level tag scanning, attribute parsing,
\ and entity decoding, adding SML-specific element types,
\ content-model validation, and convenience accessors.
\
\ Prefix: SML-   (public API)
\         _SML-  (internal helpers)
\
\ Load with:   REQUIRE core.f

REQUIRE ../markup/core.f
REQUIRE ../text/utf8.f

PROVIDED akashic-sml-core

\ =====================================================================
\  Error Handling
\ =====================================================================

VARIABLE SML-ERR
0 SML-ERR !

1  CONSTANT SML-E-BAD-ROOT       \ root element is not <sml>
2  CONSTANT SML-E-BAD-ELEMENT    \ unknown element name
3  CONSTANT SML-E-BAD-NEST       \ element in wrong parent context
4  CONSTANT SML-E-MISSING-ATTR   \ required attribute missing
5  CONSTANT SML-E-EMPTY-DOC      \ no content found
6  CONSTANT SML-E-TOO-DEEP       \ nesting exceeds max depth
7  CONSTANT SML-E-DUPLICATE-ID   \ duplicate id attribute
8  CONSTANT SML-E-BAD-KIND       \ invalid kind= attribute value

: SML-FAIL      ( code -- )   SML-ERR ! ;
: SML-OK?       ( -- flag )   SML-ERR @ 0= ;
: SML-CLEAR-ERR ( -- )        0 SML-ERR ! ;

\ =====================================================================
\  Element Type Constants  (SML spec §9 — 6 categories, 25 elements)
\ =====================================================================

0 CONSTANT SML-T-ENVELOPE    \ sml, head
1 CONSTANT SML-T-META        \ title, meta, link, style, cue-def
2 CONSTANT SML-T-SCOPE       \ seq, ring, gate, trap
3 CONSTANT SML-T-POSITION    \ item, act, val, pick, ind, tick, alert
4 CONSTANT SML-T-STRUCT      \ announce, shortcut, hint, gap, lane
5 CONSTANT SML-T-COMPOSE     \ frag, slot
6 CONSTANT SML-T-UNKNOWN     \ not a recognised SML element

\ =====================================================================
\  Element Name Table
\ =====================================================================
\
\ A counted-string table mapping element names to their type.
\ Each entry: 1-byte name-length, N bytes name, 1-byte type.
\ Sentinel: 0-length entry.
\
\ 25 elements grouped by type:

CREATE _SML-ELEMS

\ Envelope (type 0)
3 C, 115 C, 109 C, 108 C,         0 C,   \ sml
4 C, 104 C, 101 C,  97 C, 100 C,  0 C,   \ head

\ Meta (type 1)
5 C, 116 C, 105 C, 116 C, 108 C, 101 C,  1 C,   \ title
4 C, 109 C, 101 C, 116 C,  97 C,          1 C,   \ meta
4 C, 108 C, 105 C, 110 C, 107 C,          1 C,   \ link
5 C, 115 C, 116 C, 121 C, 108 C, 101 C,  1 C,   \ style
7 C,  99 C, 117 C, 101 C,  45 C, 100 C, 101 C, 102 C,  1 C,  \ cue-def

\ Scope (type 2)
3 C, 115 C, 101 C, 113 C,          2 C,   \ seq
4 C, 114 C, 105 C, 110 C, 103 C,  2 C,   \ ring
4 C, 103 C,  97 C, 116 C, 101 C,  2 C,   \ gate
4 C, 116 C, 114 C,  97 C, 112 C,  2 C,   \ trap

\ Position (type 3)
4 C, 105 C, 116 C, 101 C, 109 C,  3 C,   \ item
3 C,  97 C,  99 C, 116 C,          3 C,   \ act
3 C, 118 C,  97 C, 108 C,          3 C,   \ val
4 C, 112 C, 105 C,  99 C, 107 C,  3 C,   \ pick
3 C, 105 C, 110 C, 100 C,          3 C,   \ ind
4 C, 116 C, 105 C,  99 C, 107 C,  3 C,   \ tick
5 C,  97 C, 108 C, 101 C, 114 C, 116 C,  3 C,   \ alert

\ Struct (type 4)
8 C,  97 C, 110 C, 110 C, 111 C, 117 C, 110 C,  99 C, 101 C,  4 C,   \ announce
8 C, 115 C, 104 C, 111 C, 114 C, 116 C,  99 C, 117 C, 116 C,  4 C,   \ shortcut
4 C, 104 C, 105 C, 110 C, 116 C,  4 C,   \ hint
3 C, 103 C,  97 C, 112 C,          4 C,   \ gap
4 C, 108 C,  97 C, 110 C, 101 C,  4 C,   \ lane

\ Compose (type 5)
4 C, 102 C, 114 C,  97 C, 103 C,  5 C,   \ frag
4 C, 115 C, 108 C, 111 C, 116 C,  5 C,   \ slot

\ Sentinel
0 C,

\ =====================================================================
\  SML-TYPE?  — Classify element name
\ =====================================================================

\ _SML-TBL-PTR walks the table.
VARIABLE _STQ-P          \ table pointer
VARIABLE _STQ-NL         \ current entry name length

: SML-TYPE?  ( name-a name-u -- type )
    \ Search the element table for a matching name
    _SML-ELEMS _STQ-P !
    BEGIN
        _STQ-P @ C@  DUP 0= IF
            \ sentinel — not found
            DROP 2DROP SML-T-UNKNOWN EXIT
        THEN
        _STQ-NL !
        \ compare: entry name at _STQ-P+1 for _STQ-NL bytes
        OVER OVER                    \ ( name-a name-u name-a name-u )
        _STQ-P @ 1+  _STQ-NL @      \ ( name-a name-u name-a name-u entry-a entry-l )
        STR-STR=                     \ ( name-a name-u flag )
        IF
            \ match — type byte follows name
            2DROP
            _STQ-P @ 1+ _STQ-NL @ + C@  EXIT
        THEN
        \ advance past: 1(len) + name-len + 1(type)
        _STQ-P @  1+  _STQ-NL @ +  1+  _STQ-P !
    AGAIN ;

\ =====================================================================
\  Predicates for element categories
\ =====================================================================

: SML-ENVELOPE? ( type -- flag )   SML-T-ENVELOPE = ;
: SML-META?     ( type -- flag )   SML-T-META     = ;
: SML-SCOPE?    ( type -- flag )   SML-T-SCOPE    = ;
: SML-POSITION? ( type -- flag )   SML-T-POSITION = ;
: SML-STRUCT?   ( type -- flag )   SML-T-STRUCT   = ;
: SML-COMPOSE?  ( type -- flag )   SML-T-COMPOSE  = ;

\ SML-NAVIGABLE? ( type -- flag )
\   True if the element type participates in cursor navigation.
\   Scope and position elements are navigable.
: SML-NAVIGABLE?  ( type -- flag )
    DUP SML-T-SCOPE = SWAP SML-T-POSITION = OR ;

\ SML-CONTAINER? ( type -- flag )
\   True if the element can have children.
\   Envelope, scope, compose are containers.
: SML-CONTAINER?  ( type -- flag )
    DUP SML-T-ENVELOPE = OVER SML-T-SCOPE = OR SWAP SML-T-COMPOSE = OR ;

\ =====================================================================
\  SML-ATTR  — Read element attribute from tag body
\ =====================================================================

\ SML-ATTR ( body-a body-u attr-a attr-u -- val-a val-u flag )
\   Read an attribute value from a tag body string.
\   The body string is everything between '<' and '>'.
\   First skip past the tag name, then search attributes.
\   Returns ( val-a val-u -1 ) if found, ( 0 0 0 ) if not.
VARIABLE _SA-BA  VARIABLE _SA-BL

: SML-ATTR  ( body-a body-u attr-a attr-u -- val-a val-u flag )
    2>R
    \ Skip past tag name in body
    MU-SKIP-WS                       \ skip leading ws
    \ skip '/' if close tag
    DUP 0> IF
        OVER C@ 47 = IF 1 /STRING THEN
    THEN
    MU-SKIP-NAME                     \ skip tag name
    \ Now cursor is in attribute area
    2R>
    MU-ATTR-FIND ;

\ SML-ATTR-ID ( body-a body-u -- val-a val-u flag )
\   Convenience: read "id" attribute.
: SML-ATTR-ID  ( body-a body-u -- val-a val-u flag )
    S" id" MU-ATTR-FIND ;

\ SML-ATTR-LABEL ( body-a body-u -- val-a val-u flag )
\   Convenience: read "label" attribute.
: SML-ATTR-LABEL  ( body-a body-u -- val-a val-u flag )
    S" label" MU-ATTR-FIND ;

\ SML-ATTR-KIND ( body-a body-u -- val-a val-u flag )
\   Convenience: read "kind" attribute.
: SML-ATTR-KIND  ( body-a body-u -- val-a val-u flag )
    S" kind" MU-ATTR-FIND ;

\ =====================================================================
\  Content Model Validation Helpers
\ =====================================================================

\ These encode the SML content model rules (SML spec §9):
\
\ - <sml> must be root, may contain <head> + one scope
\ - <head> may contain only meta elements
\ - Scope elements may contain scope, position, struct, compose
\ - Position elements are leaf or may contain struct/compose
\ - Meta elements are leaf (self-closing or text content only)
\ - Struct elements are leaf
\ - Compose elements may contain scope, position, struct, compose

\ SML-VALID-CHILD? ( parent-type child-type -- flag )
\   Can an element of child-type appear inside parent-type?
: SML-VALID-CHILD?  ( parent-type child-type -- flag )
    SWAP
    DUP SML-T-ENVELOPE = IF
        DROP
        \ envelope (sml, head) can contain: envelope, meta, scope, compose
        DUP SML-T-ENVELOPE = OVER SML-T-META     = OR
        OVER SML-T-SCOPE   = OR SWAP SML-T-COMPOSE = OR EXIT
    THEN
    DUP SML-T-SCOPE = IF
        DROP
        \ scope can contain: scope, position, struct, compose
        DUP SML-T-SCOPE    = OVER SML-T-POSITION = OR
        OVER SML-T-STRUCT  = OR SWAP SML-T-COMPOSE = OR EXIT
    THEN
    DUP SML-T-POSITION = IF
        DROP
        \ position can contain: struct, compose
        DUP SML-T-STRUCT = SWAP SML-T-COMPOSE = OR EXIT
    THEN
    DUP SML-T-COMPOSE = IF
        DROP
        \ compose can contain: scope, position, struct, compose
        DUP SML-T-SCOPE    = OVER SML-T-POSITION = OR
        OVER SML-T-STRUCT  = OR SWAP SML-T-COMPOSE = OR EXIT
    THEN
    \ meta and struct are leaf — no children allowed
    2DROP 0 ;

\ =====================================================================
\  Element Name → Type Quick Lookup (count + enumeration)
\ =====================================================================

\ SML-ELEM-COUNT ( -- 25 )
\   Number of defined SML elements.
25 CONSTANT SML-ELEM-COUNT

\ SML-ELEM-NTH ( n -- name-a name-u type )
\   Return the nth element's name and type (0-based).
\   Returns ( 0 0 SML-T-UNKNOWN ) if out of range.
VARIABLE _SEN-I
VARIABLE _SEN-P

: SML-ELEM-NTH  ( n -- name-a name-u type )
    DUP 0< IF DROP 0 0 SML-T-UNKNOWN EXIT THEN
    DUP SML-ELEM-COUNT >= IF DROP 0 0 SML-T-UNKNOWN EXIT THEN
    _SEN-I !
    _SML-ELEMS _SEN-P !
    \ skip _SEN-I entries
    BEGIN
        _SEN-I @ 0> WHILE
        _SEN-P @ C@  DUP 0= IF
            DROP 0 0 SML-T-UNKNOWN EXIT   \ shouldn't happen
        THEN
        1+ 1+  _SEN-P @ + _SEN-P !       \ skip len + name + type
        _SEN-I @ 1- _SEN-I !
    REPEAT
    \ now at the target entry
    _SEN-P @ C@  DUP 0= IF
        DROP 0 0 SML-T-UNKNOWN EXIT
    THEN
    \ name-a = _SEN-P+1, name-u = len, type = byte after name
    _SEN-P @ 1+            \ name-a
    OVER                   \ name-u (= len byte value)
    ROT                    \ ( name-a name-u len )
    _SEN-P @ 1+ + C@       \ type byte at _SEN-P+1+len
    ;

\ =====================================================================
\  Scope-kind check for ring, gate, trap
\ =====================================================================

\ The four scope elements have distinct traversal behaviour:
\   seq  — linear sequence (default)
\   ring — circular wrap
\   gate — locked until condition met
\   trap — sticky until explicit exit

: SML-SEQ?  ( name-a name-u -- flag )  S" seq"  STR-STR= ;
: SML-RING? ( name-a name-u -- flag )  S" ring" STR-STR= ;
: SML-GATE? ( name-a name-u -- flag )  S" gate" STR-STR= ;
: SML-TRAP? ( name-a name-u -- flag )  S" trap" STR-STR= ;

\ =====================================================================
\  val kind= validation
\ =====================================================================

\ Valid kind= values for <val>: text, range, toggle, display
\ Stored as counted strings with sentinel.

CREATE _SML-VAL-KINDS
4 C, 116 C, 101 C, 120 C, 116 C,                  \ text
5 C, 114 C,  97 C, 110 C, 103 C, 101 C,           \ range
6 C, 116 C, 111 C, 103 C, 103 C, 108 C, 101 C,    \ toggle
7 C, 100 C, 105 C, 115 C, 112 C, 108 C,  97 C, 121 C,  \ display
0 C,  \ sentinel

VARIABLE _SVK-P

: SML-VALID-VAL-KIND?  ( str-a str-u -- flag )
    _SML-VAL-KINDS  _SVK-P !
    BEGIN
        _SVK-P @ C@  DUP 0= IF
            DROP 2DROP 0 EXIT        \ sentinel — not found
        THEN
        >R                           \ R: entry-len
        OVER OVER
        _SVK-P @ 1+  R@  STR-STR=
        IF  2DROP R> DROP -1 EXIT  THEN
        R> 1+  _SVK-P @ +  _SVK-P !
    AGAIN ;

\ =====================================================================
\  pick choice= count
\ =====================================================================

\ SML-PICK-COUNT ( body-a body-u -- n )
\   Count the number of "|"-separated choices in the choices= attribute.
\   If no choices= attribute, returns 0.
VARIABLE _SPC-N
VARIABLE _SPC-A
VARIABLE _SPC-L

: SML-PICK-COUNT  ( body-a body-u -- n )
    S" choices" MU-ATTR-FIND
    0= IF 2DROP 0 EXIT THEN
    \ val-a val-u on stack — count '|' separators + 1
    _SPC-L ! _SPC-A !
    _SPC-L @ 0= IF 0 EXIT THEN
    1 _SPC-N !
    _SPC-L @ 0 DO
        _SPC-A @ I + C@ 124 = IF    \ '|'
            1 _SPC-N +!
        THEN
    LOOP
    _SPC-N @ ;

\ =====================================================================
\  SML-VALID?  — Structural document validation
\ =====================================================================

\ SML-VALID? ( a u -- flag )
\   Validate an SML document string:
\   1. Must start with <sml> root
\   2. All elements must be known SML elements
\   3. Nesting depth ≤ 16
\   4. Content model rules respected
\
\   This is a streaming validator — it walks the markup once,
\   tracking a parent-type stack.  Returns TRUE if valid.

16 CONSTANT SML-MAX-DEPTH

CREATE _SVD-STACK 16 ALLOT          \ parent-type stack (byte per level)
VARIABLE _SVD-DEPTH
VARIABLE _SVD-NA   VARIABLE _SVD-NL  \ tag name
VARIABLE _SVD-TY                     \ element type
VARIABLE _SVD-TT                     \ tag type (MU-T-*)

: _SML-PUSH-TYPE  ( type -- ok? )
    _SVD-DEPTH @ SML-MAX-DEPTH >= IF
        DROP SML-E-TOO-DEEP SML-FAIL 0 EXIT
    THEN
    _SVD-STACK _SVD-DEPTH @ + C!
    1 _SVD-DEPTH +!  -1 ;

: _SML-POP-TYPE  ( -- )
    _SVD-DEPTH @ 0> IF -1 _SVD-DEPTH +! THEN ;

: _SML-PARENT-TYPE  ( -- type )
    _SVD-DEPTH @ 0= IF SML-T-UNKNOWN EXIT THEN
    _SVD-STACK _SVD-DEPTH @ 1- + C@ ;

: SML-VALID?  ( a u -- flag )
    SML-CLEAR-ERR
    0 _SVD-DEPTH !
    MU-SKIP-WS
    \ must start with a tag
    DUP 0= IF 2DROP SML-E-EMPTY-DOC SML-FAIL 0 EXIT THEN
    2DUP MU-AT-TAG? 0= IF 2DROP SML-E-EMPTY-DOC SML-FAIL 0 EXIT THEN
    \ check root is <sml>
    2DUP MU-GET-TAG-NAME _SVD-NL ! _SVD-NA ! 2DROP
    _SVD-NA @ _SVD-NL @  S" sml" STR-STR= 0= IF
        2DROP SML-E-BAD-ROOT SML-FAIL 0 EXIT
    THEN
    \ push root type
    SML-T-ENVELOPE _SML-PUSH-TYPE DROP
    MU-SKIP-TAG                      \ skip <sml ...>
    \ walk remaining content
    BEGIN
        DUP 0> WHILE
        MU-SKIP-WS
        DUP 0= IF 2DROP -1 EXIT THEN
        2DUP MU-AT-TAG? 0= IF
            \ text content — skip it
            MU-SKIP-TO-TAG
        ELSE
            2DUP MU-TAG-TYPE
            DUP MU-T-CLOSE = IF
                DROP
                _SML-POP-TYPE
                MU-SKIP-TAG
            ELSE DUP MU-T-COMMENT = IF
                DROP MU-SKIP-COMMENT
            ELSE DUP MU-T-PI = IF
                DROP MU-SKIP-PI
            ELSE DUP MU-T-OPEN = OVER MU-T-SELF-CLOSE = OR IF
                _SVD-TT !            \ save tag type, clean stack
                \ extract tag name, classify
                2DUP MU-GET-TAG-NAME _SVD-NL ! _SVD-NA ! 2DROP
                _SVD-NA @ _SVD-NL @  SML-TYPE?  _SVD-TY !
                \ unknown element?
                _SVD-TY @ SML-T-UNKNOWN = IF
                    2DROP SML-E-BAD-ELEMENT SML-FAIL 0 EXIT
                THEN
                \ check content model
                _SML-PARENT-TYPE _SVD-TY @  SML-VALID-CHILD? 0= IF
                    2DROP SML-E-BAD-NEST SML-FAIL 0 EXIT
                THEN
                \ if open tag, push onto stack
                _SVD-TT @ MU-T-OPEN = IF
                    _SVD-TY @ _SML-PUSH-TYPE 0= IF
                        2DROP 0 EXIT
                    THEN
                THEN
                MU-SKIP-TAG
            ELSE
                DROP MU-SKIP-TAG
            THEN THEN THEN THEN
        THEN
    REPEAT
    2DROP
    SML-OK? ;

\ =====================================================================
\  Convenience: element count in a scope
\ =====================================================================

\ SML-COUNT-CHILDREN ( a u -- n )
\   Count direct child elements inside a container element.
\   Cursor must be at the opening tag of the container.
\   Uses MU-INNER + sibling iteration.
VARIABLE _SCC-N

: SML-COUNT-CHILDREN  ( a u -- n )
    MU-INNER
    0 _SCC-N !
    BEGIN
        MU-SKIP-WS
        DUP 0> WHILE
        2DUP MU-AT-TAG? IF
            2DUP MU-TAG-TYPE
            DUP MU-T-OPEN = OVER MU-T-SELF-CLOSE = OR IF
                DROP
                1 _SCC-N +!
                MU-SKIP-ELEMENT
            ELSE DUP MU-T-CLOSE = IF
                \ closing tag of parent — stop
                DROP 2DROP _SCC-N @ EXIT
            ELSE DUP MU-T-COMMENT = IF
                DROP MU-SKIP-COMMENT
            ELSE
                DROP MU-SKIP-TAG
            THEN THEN THEN
        ELSE
            MU-SKIP-TO-TAG
        THEN
    REPEAT
    2DROP _SCC-N @ ;

\ =====================================================================
\  Tag body extraction shortcut
\ =====================================================================

\ SML-TAG-BODY ( a u -- body-a body-u name-a name-u )
\   From cursor at a tag, extract both the tag body and the tag name.
\   Useful for getting attributes + name in one pass.
VARIABLE _STB-BA  VARIABLE _STB-BL
VARIABLE _STB-NA  VARIABLE _STB-NL

: SML-TAG-BODY  ( a u -- body-a body-u name-a name-u )
    2DUP MU-GET-TAG-BODY _STB-BL ! _STB-BA !
    MU-GET-TAG-NAME _STB-NL ! _STB-NA !
    2DROP
    _STB-BA @ _STB-BL @  _STB-NA @ _STB-NL @ ;

\ =====================================================================
\  SML-PARSE — Forward Declaration
\ =====================================================================
\
\ Full tree construction (SML string → SOM tree) is implemented in
\ sml/tree.f.  core.f provides the element vocabulary, classification,
\ validation, and attribute extraction that tree.f builds upon.
\
\ See: REQUIRE sml/tree.f   for SML-PARSE, SML-TREE-CREATE, etc.

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _smlcore-guard

' SML-FAIL        CONSTANT _sml-fail-xt
' SML-OK?         CONSTANT _sml-ok-q-xt
' SML-CLEAR-ERR   CONSTANT _sml-clear-err-xt
' SML-TYPE?       CONSTANT _sml-type-q-xt
' SML-ENVELOPE?   CONSTANT _sml-envelope-q-xt
' SML-META?       CONSTANT _sml-meta-q-xt
' SML-SCOPE?      CONSTANT _sml-scope-q-xt
' SML-POSITION?   CONSTANT _sml-position-q-xt
' SML-STRUCT?     CONSTANT _sml-struct-q-xt
' SML-COMPOSE?    CONSTANT _sml-compose-q-xt
' SML-NAVIGABLE?  CONSTANT _sml-navigable-q-xt
' SML-CONTAINER?  CONSTANT _sml-container-q-xt
' SML-ATTR        CONSTANT _sml-attr-xt
' SML-ATTR-ID     CONSTANT _sml-attr-id-xt
' SML-ATTR-LABEL  CONSTANT _sml-attr-label-xt
' SML-ATTR-KIND   CONSTANT _sml-attr-kind-xt
' SML-VALID-CHILD? CONSTANT _sml-valid-child-q-xt
' SML-ELEM-NTH    CONSTANT _sml-elem-nth-xt
' SML-SEQ?        CONSTANT _sml-seq-q-xt
' SML-RING?       CONSTANT _sml-ring-q-xt
' SML-GATE?       CONSTANT _sml-gate-q-xt
' SML-TRAP?       CONSTANT _sml-trap-q-xt
' SML-VALID-VAL-KIND? CONSTANT _sml-valid-val-kind-q-xt
' SML-PICK-COUNT  CONSTANT _sml-pick-count-xt
' SML-VALID?      CONSTANT _sml-valid-q-xt
' SML-COUNT-CHILDREN CONSTANT _sml-count-children-xt
' SML-TAG-BODY    CONSTANT _sml-tag-body-xt

: SML-FAIL        _sml-fail-xt _smlcore-guard WITH-GUARD ;
: SML-OK?         _sml-ok-q-xt _smlcore-guard WITH-GUARD ;
: SML-CLEAR-ERR   _sml-clear-err-xt _smlcore-guard WITH-GUARD ;
: SML-TYPE?       _sml-type-q-xt _smlcore-guard WITH-GUARD ;
: SML-ENVELOPE?   _sml-envelope-q-xt _smlcore-guard WITH-GUARD ;
: SML-META?       _sml-meta-q-xt _smlcore-guard WITH-GUARD ;
: SML-SCOPE?      _sml-scope-q-xt _smlcore-guard WITH-GUARD ;
: SML-POSITION?   _sml-position-q-xt _smlcore-guard WITH-GUARD ;
: SML-STRUCT?     _sml-struct-q-xt _smlcore-guard WITH-GUARD ;
: SML-COMPOSE?    _sml-compose-q-xt _smlcore-guard WITH-GUARD ;
: SML-NAVIGABLE?  _sml-navigable-q-xt _smlcore-guard WITH-GUARD ;
: SML-CONTAINER?  _sml-container-q-xt _smlcore-guard WITH-GUARD ;
: SML-ATTR        _sml-attr-xt _smlcore-guard WITH-GUARD ;
: SML-ATTR-ID     _sml-attr-id-xt _smlcore-guard WITH-GUARD ;
: SML-ATTR-LABEL  _sml-attr-label-xt _smlcore-guard WITH-GUARD ;
: SML-ATTR-KIND   _sml-attr-kind-xt _smlcore-guard WITH-GUARD ;
: SML-VALID-CHILD? _sml-valid-child-q-xt _smlcore-guard WITH-GUARD ;
: SML-ELEM-NTH    _sml-elem-nth-xt _smlcore-guard WITH-GUARD ;
: SML-SEQ?        _sml-seq-q-xt _smlcore-guard WITH-GUARD ;
: SML-RING?       _sml-ring-q-xt _smlcore-guard WITH-GUARD ;
: SML-GATE?       _sml-gate-q-xt _smlcore-guard WITH-GUARD ;
: SML-TRAP?       _sml-trap-q-xt _smlcore-guard WITH-GUARD ;
: SML-VALID-VAL-KIND? _sml-valid-val-kind-q-xt _smlcore-guard WITH-GUARD ;
: SML-PICK-COUNT  _sml-pick-count-xt _smlcore-guard WITH-GUARD ;
: SML-VALID?      _sml-valid-q-xt _smlcore-guard WITH-GUARD ;
: SML-COUNT-CHILDREN _sml-count-children-xt _smlcore-guard WITH-GUARD ;
: SML-TAG-BODY    _sml-tag-body-xt _smlcore-guard WITH-GUARD ;
[THEN] [THEN]
