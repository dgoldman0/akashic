\ =====================================================================
\  agent-cap-catalog.f - Desk-trusted Agent capability candidates
\ =====================================================================
\  This table is policy input, not capability discovery or authority.  Desk
\  still resolves each component ID through its exact built-in descriptor
\  list, requires a live CINST/generation and exact descriptor effects, and
\  attenuates every row through the selected access profile and Mandate.
\
\  Component packages do not register rows here.  Adding or changing a row
\  is a Desk policy change that must update the closed authority-matrix tests.
\ =====================================================================

PROVIDED akashic-desk-agent-caps

REQUIRE ../agent/access-profile.f
REQUIRE ../../../interop/capability-facet.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../utils/memory-span.f

1 CONSTANT DACAND-P-READ
2 CONSTANT DACAND-P-ASSIST
4 CONSTANT DACAND-P-LIBRARY-BURROW
DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
    CONSTANT DACAND-PRESET-MASK

CFENTRY-F-VISIBLE CFENTRY-F-INVOKE OR CFENTRY-F-AUTO-OBSERVE OR
CFENTRY-F-DISCLOSE-RESULT OR CONSTANT DACAND-OBSERVE-FLAGS

CFENTRY-F-VISIBLE CFENTRY-F-INVOKE OR CFENTRY-F-REVIEW-COMMIT OR
CFENTRY-F-DISCLOSE-RESULT OR CONSTANT DACAND-REVIEW-FLAGS

\ Existing bounded text projections use this exact compact-JSON allowance.
\ It is a result bound, not a canonical argument or durable value limit.
4096 CONSTANT DACAND-TEXT-RESULT-MAX
4 CONSTANT DACAND-RESULT-FALLBACK-MIN

 0 CONSTANT _DAC-COMPONENT-A
 8 CONSTANT _DAC-COMPONENT-U
16 CONSTANT _DAC-OP-A
24 CONSTANT _DAC-OP-U
32 CONSTANT _DAC-EFFECTS
40 CONSTANT _DAC-FLAGS
48 CONSTANT _DAC-MAX-RESULT
56 CONSTANT _DAC-PRESETS
64 CONSTANT DACAND-SIZE

: DACAND.COMPONENT-A  ( candidate -- a ) _DAC-COMPONENT-A + ;
: DACAND.COMPONENT-U  ( candidate -- a ) _DAC-COMPONENT-U + ;
: DACAND.OP-A         ( candidate -- a ) _DAC-OP-A + ;
: DACAND.OP-U         ( candidate -- a ) _DAC-OP-U + ;
: DACAND.EFFECTS      ( candidate -- a ) _DAC-EFFECTS + ;
: DACAND.FLAGS        ( candidate -- a ) _DAC-FLAGS + ;
: DACAND.MAX-RESULT   ( candidate -- a ) _DAC-MAX-RESULT + ;
: DACAND.PRESETS      ( candidate -- a ) _DAC-PRESETS + ;

: DACAND-COMPONENT$  ( candidate -- a u )
    DUP DACAND.COMPONENT-A @ SWAP DACAND.COMPONENT-U @ ;

: DACAND-OP$  ( candidate -- a u )
    DUP DACAND.OP-A @ SWAP DACAND.OP-U @ ;

23 CONSTANT DESK-AGENT-CANDIDATE-N
CREATE DESK-AGENT-CANDIDATES
    DESK-AGENT-CANDIDATE-N DACAND-SIZE * ALLOT

: DESK-AGENT-CANDIDATE-NTH  ( index -- candidate|0 )
    DUP 0< OVER DESK-AGENT-CANDIDATE-N >= OR IF DROP 0 EXIT THEN
    DACAND-SIZE * DESK-AGENT-CANDIDATES + ;

: DACAND-PRESET-BIT  ( preset -- bit|0 )
    CASE
        AAP-PRESET-PRACTICE-READ OF DACAND-P-READ ENDOF
        AAP-PRESET-PRACTICE-ASSIST OF DACAND-P-ASSIST ENDOF
        AAP-PRESET-PRACTICE-LIBRARY-BURROW OF
            DACAND-P-LIBRARY-BURROW
        ENDOF
        0 SWAP
    ENDCASE ;

: DACAND-ALLOWED?  ( candidate preset -- flag )
    DACAND-PRESET-BIT DUP 0= IF 2DROP 0 EXIT THEN
    SWAP DACAND.PRESETS @ AND 0<> ;

VARIABLE _DACV-C

: DACAND-VALID?  ( candidate -- flag )
    DUP 0= IF DROP 0 EXIT THEN DUP _DACV-C !
    DUP DACAND-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN DROP
    _DACV-C @ DACAND-COMPONENT$ DUP 1 < IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    UTF8-VALID? 0= IF 0 EXIT THEN
    _DACV-C @ DACAND-OP$ DUP 1 < OVER CFENTRY-OP-ID-MAX > OR IF
        2DROP 0 EXIT
    THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    UTF8-VALID? 0= IF 0 EXIT THEN
    _DACV-C @ DACAND.EFFECTS @ DUP 0< IF DROP 0 EXIT THEN
    CAP-E-OBSERVE CAP-E-NAVIGATE OR CAP-E-MUTATE OR CAP-E-PERSIST OR
        CAP-E-DESTRUCTIVE OR CAP-E-EXTERNAL OR INVERT AND IF 0 EXIT THEN
    _DACV-C @ DACAND.EFFECTS @
        CAP-E-DESTRUCTIVE CAP-E-EXTERNAL OR AND IF 0 EXIT THEN
    _DACV-C @ DACAND.FLAGS @ DUP 0< IF DROP 0 EXIT THEN
    CFENTRY-FLAGS-MASK INVERT AND IF 0 EXIT THEN
    _DACV-C @ DACAND.FLAGS @ DACAND-OBSERVE-FLAGS = IF
        _DACV-C @ DACAND.EFFECTS @ CAP-E-OBSERVE <> IF 0 EXIT THEN
    ELSE
        _DACV-C @ DACAND.FLAGS @ DACAND-REVIEW-FLAGS <> IF 0 EXIT THEN
        _DACV-C @ DACAND.EFFECTS @
            CAP-E-NAVIGATE CAP-E-MUTATE OR CAP-E-PERSIST OR AND
            0= IF 0 EXIT THEN
    THEN
    _DACV-C @ DACAND.MAX-RESULT @
        DACAND-RESULT-FALLBACK-MIN < IF 0 EXIT THEN
    _DACV-C @ DACAND.PRESETS @ DUP 0> 0= IF DROP 0 EXIT THEN
    DACAND-PRESET-MASK INVERT AND 0= ;

VARIABLE _DACS-B

: DACAND-SAME-OP?  ( candidate-a candidate-b -- flag )
    _DACS-B !
    DUP DACAND-COMPONENT$ _DACS-B @ DACAND-COMPONENT$ STR-STR=
    SWAP DACAND-OP$ _DACS-B @ DACAND-OP$ STR-STR= AND ;

VARIABLE _DACCV-C

: DESK-AGENT-CANDIDATES-VALID?  ( -- flag )
    DESK-AGENT-CANDIDATE-N CFACET-MAX-ENTRIES > IF 0 EXIT THEN
    DESK-AGENT-CANDIDATE-N 0 ?DO
        I DESK-AGENT-CANDIDATE-NTH DUP DACAND-VALID? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        _DACCV-C !
        DESK-AGENT-CANDIDATE-N I 1+ ?DO
            _DACCV-C @ I DESK-AGENT-CANDIDATE-NTH DACAND-SAME-OP? IF
                0 UNLOOP UNLOOP EXIT
            THEN
        LOOP
    LOOP
    -1 ;

VARIABLE _DACI-C

: _DACAND!  ( component-a component-u op-a op-u effects flags max presets index -- )
    DESK-AGENT-CANDIDATE-NTH DUP 0= IF -4910 THROW THEN
    DUP _DACI-C ! DACAND-SIZE 0 FILL
    _DACI-C @ DACAND.PRESETS !
    _DACI-C @ DACAND.MAX-RESULT !
    _DACI-C @ DACAND.FLAGS !
    _DACI-C @ DACAND.EFFECTS !
    _DACI-C @ DACAND.OP-U !
    _DACI-C @ DACAND.OP-A !
    _DACI-C @ DACAND.COMPONENT-U !
    _DACI-C @ DACAND.COMPONENT-A ! ;

: _DACANDIDATES-SETUP  ( -- )
    DESK-AGENT-CANDIDATES
        DESK-AGENT-CANDIDATE-N DACAND-SIZE * 0 FILL

    S" org.akashic.daybook" S" daybook.agenda.markdown"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS DACAND-TEXT-RESULT-MAX
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        0 _DACAND!
    S" org.akashic.daybook" S" daybook.source"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS 516
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        1 _DACAND!
    S" org.akashic.pad" S" pad.document.active"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS 516
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        2 _DACAND!
    S" org.akashic.pad" S" pad.document.text"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS DACAND-TEXT-RESULT-MAX
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        3 _DACAND!
    S" org.akashic.fexplorer" S" fexplorer.resource.selected"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS 516
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        4 _DACAND!
    S" org.akashic.fexplorer" S" fexplorer.preview.text"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS DACAND-TEXT-RESULT-MAX
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        5 _DACAND!
    S" org.akashic.grid" S" grid.cell.selected"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS 40
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        6 _DACAND!
    S" org.akashic.grid" S" grid.workbook.csv"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS DACAND-TEXT-RESULT-MAX
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        7 _DACAND!
    S" org.akashic.grid" S" grid.source"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS 516
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        8 _DACAND!
    S" org.akashic.streams" S" streams.source.query"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS DACAND-TEXT-RESULT-MAX
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        9 _DACAND!
    S" org.akashic.streams" S" streams.source.read"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS DACAND-TEXT-RESULT-MAX
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        10 _DACAND!

    S" org.akashic.daybook" S" daybook.task.capture"
        CAP-E-MUTATE CAP-E-PERSIST OR DACAND-REVIEW-FLAGS 8
        DACAND-P-ASSIST DACAND-P-LIBRARY-BURROW OR 11 _DACAND!
    S" org.akashic.pad" S" pad.document.open"
        CAP-E-NAVIGATE DACAND-REVIEW-FLAGS 516
        DACAND-P-ASSIST DACAND-P-LIBRARY-BURROW OR 12 _DACAND!
    S" org.akashic.fexplorer" S" fexplorer.resource.reveal"
        CAP-E-NAVIGATE DACAND-REVIEW-FLAGS 516
        DACAND-P-ASSIST DACAND-P-LIBRARY-BURROW OR 13 _DACAND!
    S" org.akashic.grid" S" grid.cell.set-selected"
        CAP-E-MUTATE DACAND-REVIEW-FLAGS 40
        DACAND-P-ASSIST DACAND-P-LIBRARY-BURROW OR 14 _DACAND!
    S" org.akashic.grid" S" grid.workbook.save"
        CAP-E-PERSIST DACAND-REVIEW-FLAGS 8
        DACAND-P-ASSIST DACAND-P-LIBRARY-BURROW OR 15 _DACAND!

    S" org.akashic.library.applet" S" library.status"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS 56
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        16 _DACAND!
    S" org.akashic.library.applet" S" library.document.create"
        CAP-E-MUTATE CAP-E-PERSIST OR DACAND-REVIEW-FLAGS 357
        DACAND-P-ASSIST DACAND-P-LIBRARY-BURROW OR 17 _DACAND!
    S" org.akashic.library.applet" S" library.collection.create"
        CAP-E-MUTATE CAP-E-PERSIST OR DACAND-REVIEW-FLAGS 270
        DACAND-P-ASSIST DACAND-P-LIBRARY-BURROW OR 18 _DACAND!
    S" org.akashic.streams" S" streams.burrow.create"
        CAP-E-MUTATE DACAND-REVIEW-FLAGS 806
        DACAND-P-LIBRARY-BURROW 19 _DACAND!
    S" org.akashic.streams" S" streams.burrow.status"
        CAP-E-OBSERVE DACAND-OBSERVE-FLAGS 744
        DACAND-P-READ DACAND-P-ASSIST OR DACAND-P-LIBRARY-BURROW OR
        20 _DACAND!
    S" org.akashic.streams" S" streams.burrow.start"
        CAP-E-MUTATE DACAND-REVIEW-FLAGS 806
        DACAND-P-LIBRARY-BURROW 21 _DACAND!
    S" org.akashic.streams" S" streams.burrow.stop"
        CAP-E-MUTATE DACAND-REVIEW-FLAGS 806
        DACAND-P-LIBRARY-BURROW 22 _DACAND!

    DESK-AGENT-CANDIDATES-VALID? 0= IF -4911 THROW THEN ;

_DACANDIDATES-SETUP
