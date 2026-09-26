\ =================================================================
\  unicode-props.f — Unicode 15.1.0 text properties of one scalar
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: UP- / _UP-
\  Depends on: unicode-tables.f (generated from the pinned UCD)
\
\  One lookup returns every property the shared text contract
\  (docs/rich-terminal/APT-1-TEXT.md) uses, packed into one value;
\  the field words below take that value apart.  Scalars in the Basic
\  Multilingual Plane use a 64 KiB byte table filled once at load time;
\  supplementary scalars use a binary search over the generated runs.
\
\  Public API:
\    UP-PROPS        ( cp -- props )     packed properties
\    UP-GCB          ( props -- n )      Grapheme_Cluster_Break (UP-GCB-*)
\    UP-EXTPICT?     ( props -- flag )   Extended_Pictographic
\    UP-INCB         ( props -- n )      Indic_Conjunct_Break (UP-INCB-*)
\    UP-WIDTH        ( props -- w )      scalar width 0, 1, or 2
\    UP-EMOJI?       ( props -- flag )   Emoji
\    UP-EMOJI-MODIFIER? ( props -- flag ) Emoji_Modifier
\    UP-IGNORABLE?   ( props -- flag )   Default_Ignorable_Code_Point
\    UP-INVALID?     ( props -- flag )   Cc, Zl, or Zp
\    UP-BIDI         ( props -- n )      Bidi_Class (UP-BC-*)
\    UP-JOINING      ( props -- n )      Joining_Type (UP-JT-*)
\    UP-MIRROR       ( cp -- cp' )       Bidi_Mirroring_Glyph, or cp
\    UP-BRACKET      ( cp -- pair type ) paired bracket; type 0, 1 open,
\                                        2 close
\    UP-ARABIC-FORM  ( cp form -- cp' | 0 )  presentation form scalar
\                                        (UP-FORM-*), 0 when none
\
\  Every word is pure: it reads only the immutable tables and the
\  stack, so it is reentrant and needs no guard.
\ =================================================================

PROVIDED akashic-unicode-props

REQUIRE unicode-tables.f

\ =====================================================================
\  §1 — Property values (must match generate_unicode_text_tables.py)
\ =====================================================================

 0 CONSTANT UP-GCB-OTHER
 1 CONSTANT UP-GCB-CR
 2 CONSTANT UP-GCB-LF
 3 CONSTANT UP-GCB-CONTROL
 4 CONSTANT UP-GCB-EXTEND
 5 CONSTANT UP-GCB-ZWJ
 6 CONSTANT UP-GCB-RI
 7 CONSTANT UP-GCB-PREPEND
 8 CONSTANT UP-GCB-SPACINGMARK
 9 CONSTANT UP-GCB-L
10 CONSTANT UP-GCB-V
11 CONSTANT UP-GCB-T
12 CONSTANT UP-GCB-LV
13 CONSTANT UP-GCB-LVT

0 CONSTANT UP-INCB-NONE
1 CONSTANT UP-INCB-CONSONANT
2 CONSTANT UP-INCB-EXTEND
3 CONSTANT UP-INCB-LINKER

 0 CONSTANT UP-BC-L
 1 CONSTANT UP-BC-R
 2 CONSTANT UP-BC-AL
 3 CONSTANT UP-BC-EN
 4 CONSTANT UP-BC-ES
 5 CONSTANT UP-BC-ET
 6 CONSTANT UP-BC-AN
 7 CONSTANT UP-BC-CS
 8 CONSTANT UP-BC-NSM
 9 CONSTANT UP-BC-BN
10 CONSTANT UP-BC-B
11 CONSTANT UP-BC-S
12 CONSTANT UP-BC-WS
13 CONSTANT UP-BC-ON
14 CONSTANT UP-BC-LRE
15 CONSTANT UP-BC-LRO
16 CONSTANT UP-BC-RLE
17 CONSTANT UP-BC-RLO
18 CONSTANT UP-BC-PDF
19 CONSTANT UP-BC-LRI
20 CONSTANT UP-BC-RLI
21 CONSTANT UP-BC-FSI
22 CONSTANT UP-BC-PDI

0 CONSTANT UP-JT-U
1 CONSTANT UP-JT-D
2 CONSTANT UP-JT-R
3 CONSTANT UP-JT-L
4 CONSTANT UP-JT-C
5 CONSTANT UP-JT-T

0 CONSTANT UP-FORM-ISOLATED
1 CONSTANT UP-FORM-FINAL
2 CONSTANT UP-FORM-INITIAL
3 CONSTANT UP-FORM-MEDIAL

\ =====================================================================
\  §2 — Field words
\ =====================================================================

: UP-GCB             ( props -- n )     15 AND ;
: UP-EXTPICT?        ( props -- flag )  16 AND 0<> ;
: UP-INCB            ( props -- n )     5 RSHIFT 3 AND ;
: UP-WIDTH           ( props -- w )     7 RSHIFT 3 AND ;
: UP-EMOJI?          ( props -- flag )  512 AND 0<> ;
: UP-EMOJI-MODIFIER? ( props -- flag )  1024 AND 0<> ;
: UP-IGNORABLE?      ( props -- flag )  2048 AND 0<> ;
: UP-INVALID?        ( props -- flag )  4096 AND 0<> ;
: UP-BIDI            ( props -- n )     13 RSHIFT 31 AND ;
: UP-JOINING         ( props -- n )     18 RSHIFT 7 AND ;
: UP-MIRRORED?       ( props -- flag )  2097152 AND 0<> ;
: UP-BRACKET?        ( props -- flag )  4194304 AND 0<> ;
: UP-ARABIC-FORMS?   ( props -- flag )  8388608 AND 0<> ;

\ =====================================================================
\  §3 — Lookup
\ =====================================================================

0xFFFFFFFF CONSTANT _UP-LOW32

: _UP-RUN-FIRST  ( i -- first )  CELLS UT-RANGES + @ _UP-LOW32 AND ;
: _UP-RUN-VALUE  ( i -- index )  CELLS UT-RANGES + @ 32 RSHIFT ;

\ _UP-RUN ( cp lo -- i )
\   The run containing cp, searching from run LO.  Invariant:
\   first(lo) <= cp < first(hi), with hi = count meaning past the end.
: _UP-RUN  ( cp lo -- i )
    UT-RANGE-COUNT                           ( cp lo hi )
    BEGIN 2DUP SWAP - 1 > WHILE
        2DUP + 2/                            ( cp lo hi mid )
        DUP _UP-RUN-FIRST 4 PICK > IF NIP ELSE ROT DROP SWAP THEN
    REPEAT
    DROP NIP ;

\ Every Basic Multilingual Plane scalar has its value index in one byte,
\ filled once at load time run by run.  Only supplementary scalars, such
\ as most emoji, search the runs.
0x10000 CONSTANT _UP-DIRECT-LIMIT
CREATE _UP-DIRECT _UP-DIRECT-LIMIT ALLOT

: _UP-BUILD-DIRECT  ( -- )
    UT-RANGE-COUNT 0 DO
        I _UP-RUN-FIRST DUP _UP-DIRECT-LIMIT >= IF DROP LEAVE THEN
        I 1+ UT-RANGE-COUNT < IF
            I 1+ _UP-RUN-FIRST _UP-DIRECT-LIMIT MIN
        ELSE
            _UP-DIRECT-LIMIT
        THEN                                 ( first end )
        OVER - SWAP _UP-DIRECT + SWAP I _UP-RUN-VALUE FILL
    LOOP ;
_UP-BUILD-DIRECT

_UP-DIRECT-LIMIT 0 _UP-RUN CONSTANT _UP-SUPPLEMENTARY-RUN

: UP-PROPS  ( cp -- props )
    DUP _UP-DIRECT-LIMIT U< IF
        _UP-DIRECT + C@
    ELSE
        DUP 0x10FFFF U> IF
            DROP 0xFFFD _UP-DIRECT + C@
        ELSE
            _UP-SUPPLEMENTARY-RUN _UP-RUN _UP-RUN-VALUE
        THEN
    THEN
    CELLS UT-VALUES + @ ;

\ _UP-FIND ( key table count stride -- entry | 0 )
\   Binary search entries of STRIDE cells whose first cell holds the
\   scalar in its upper 32 bits.
: _UP-FIND  ( key table count stride -- entry | 0 )
    CELLS >R                                 ( key table count  R: bytes )
    0 SWAP                                   ( key table lo hi )
    BEGIN 2DUP < WHILE
        2DUP + 2/                            ( key table lo hi mid )
        DUP R@ * 4 PICK + @ 32 RSHIFT        ( key table lo hi mid scalar )
        5 PICK 2DUP = IF
            2DROP NIP NIP R> * + NIP EXIT
        THEN
        < IF                                 \ scalar < key: lo = mid+1
            1+ ROT DROP SWAP
        ELSE                                 \ scalar > key: hi = mid
            NIP
        THEN
    REPEAT
    R> DROP 2DROP 2DROP 0 ;

: UP-MIRROR  ( cp -- cp' )
    DUP UT-MIRRORS UT-MIRROR-COUNT 1 _UP-FIND
    ?DUP IF NIP @ _UP-LOW32 AND THEN ;

: UP-BRACKET  ( cp -- pair type )
    UT-BRACKETS UT-BRACKET-COUNT 1 _UP-FIND
    ?DUP 0= IF 0 0 EXIT THEN
    @ _UP-LOW32 AND DUP 2 RSHIFT SWAP 3 AND ;

: UP-ARABIC-FORM  ( cp form -- cp' | 0 )
    SWAP UT-ARABIC UT-ARABIC-COUNT 2 _UP-FIND
    ?DUP 0= IF DROP 0 EXIT THEN
    CELL+ @ SWAP 16 * RSHIFT 0xFFFF AND ;

\ =====================================================================
\  §4 — Concurrency classification
\ =====================================================================
\
\ The tables are immutable after load and every word keeps its state on
\ the data stack, so concurrent callers need no guard.
