"""Native complete-source tests for the optional immutable shell candidate."""

import re

from test_field_model import PRELUDE, ROOT, field_runtime, run_field

MODULES = ("tui/rich-terminal/shell-screen-producer.f",)
MODULES_ROOT = ROOT / "akashic"


def run(program, minimum=1):
    run_field(program, minimum=minimum, extra_sources=MODULES)


def test_the_shell_record_s_fields_lie_apart_and_inside_it():
    """Every field of the shell's record is a cell of its own, except the
    extension record the screen producer calls, which lies whole inside the
    record at its own offset; no field overlaps another, and the record ends
    where its last field does."""
    root = MODULES_ROOT / "tui/rich-terminal"
    source = (root / "shell-screen-producer.f").read_text()
    producer = (root / "hybrid-screen-producer.f").read_text()
    size = int(re.search(r"(?m)^(\d+) CONSTANT RSHSP-SIZE$", source)[1])
    extension = int(re.search(r"(?m)^(\d+) CONSTANT RTHP-EXTENSION-SIZE$", producer)[1])
    spans = []
    for name, offset in re.findall(
        r"(?m)^: _RSHSP\.([A-Z-]+) \( s -- a \)\s*(?:(\d+) \+ )?;", source
    ):
        start = int(offset or 0)
        spans.append((start, start + (extension if name == "EXTENSION" else 8), name))
    spans.sort()
    assert len(spans) >= 9
    for (_start, end, name), (next_start, _end, next_name) in zip(spans, spans[1:]):
        assert end <= next_start, (name, next_name)
    assert spans[-1][1] == size


def test_shell_producer_actual_dependency_closure_and_header_contract():
    run(PRELUDE + r'''
RSHSP-BYTES RSHSP-SIZE = _FM-A RSHSP-SIZE 104 = _FM-A
RSHSP-PART-HEADER-SIZE 96 = _FM-A
0 RSHSP-PART.PROMPT 88 = _FM-A
0 _RSHSP.PRODUCER 24 = _FM-A 0 _RSHSP.SOURCE 32 = _FM-A
0 _RSHSP.PART-BYTES 48 = _FM-A 0 _RSHSP.SCRATCH-USED 56 = _FM-A
0 _RSHSP.EXTENSION 64 = _FM-A
0 RSHSP-PART.BATCH 0= _FM-A 0 RSHSP-PART.MODEL 8 = _FM-A
0 RSHSP-PART.CORRELATIONS 24 = _FM-A 0 RSHSP-PART.ACTIONS 40 = _FM-A
0 RSHSP-PART.MEMBERSHIP 56 = _FM-A 0 RSHSP-PART.NEXT-REGION 72 = _FM-A
0 RSHSP-PART.NEXT-OBJECT 80 = _FM-A
\ The bank of the frame names the part and the bytes it uses.
0 _RTHP-TB.XBLOCK 368 = _FM-A 0 _RTHP-TB.XBLOCK-BYTES 376 = _FM-A
_RTHP-TARGET-BANK-HEADER-SIZE 384 = _FM-A
_FM-DONE
''', minimum=19)


from test_shell_snapshot import PRELUDE as SHELL_MODEL

# The source is produced by genuine completed root/host observation. The legacy
# candidate is a caller-built neutral fixture; all shape/semantic validators run.
STAGED = SHELL_MODEL + r'''
CREATE _SX-CS 167 ALLOT CREATE _SX-AS 4103 ALLOT CREATE _SX-BS 4103 ALLOT
CREATE _SX-HS AHOST-SIZE 7 + ALLOT CREATE _SX-DS COMP-DESC 7 + ALLOT
CREATE _SX-SLOTS AHS-SIZE 7 + ALLOT
CREATE _SX-PS RTHP-SIZE 7 + ALLOT CREATE _SX-SS RSHSP-SIZE 7 + ALLOT
CREATE _SX-FS RTE-FACADE-SIZE 7 + ALLOT CREATE _SX-FXS RTE-SHELL-FACADE-SIZE 7 + ALLOT
CREATE _SX-WS 262151 ALLOT CREATE _SX-KAS 131079 ALLOT CREATE _SX-KBS 131079 ALLOT
CREATE _SX-CIS 207 ALLOT CREATE _SX-SIS 183 ALLOT CREATE _SX-DIRS 247 ALLOT
CREATE _SX-CXS 63 ALLOT CREATE _SX-SXS 47 ALLOT CREATE _SX-CTS 15 ALLOT
\ Target banks with room for the candidate's items, an instrument
\ fixture's 128,000 sample bytes among them.
CREATE _SX-TARGETS 140007 ALLOT CREATE _SX-TARGET2S 140007 ALLOT
\ The screen producer's glyph banks, for every cell of the 32 by 12 surface.
CREATE _SX-GIS 46087 ALLOT CREATE _SX-GRS 6151 ALLOT CREATE _SX-GTS 4103 ALLOT
: _SX-C _SX-CS 7 + -8 AND ; : _SX-A _SX-AS 7 + -8 AND ; : _SX-B _SX-BS 7 + -8 AND ;
: _SX-H _SX-HS 7 + -8 AND ; : _SX-D _SX-DS 7 + -8 AND ;
: _SX-SLOT _SX-SLOTS 7 + -8 AND ; : _SX-P _SX-PS 7 + -8 AND ;
: _SX-S _SX-SS 7 + -8 AND ; : _SX-F _SX-FS 7 + -8 AND ; : _SX-FX _SX-FXS 7 + -8 AND ;
: _SX-W _SX-WS 7 + -8 AND ; : _SX-KA _SX-KAS 7 + -8 AND ; : _SX-KB _SX-KBS 7 + -8 AND ;
: _SX-CI _SX-CIS 7 + -8 AND ; : _SX-SI _SX-SIS 7 + -8 AND ; : _SX-DIR _SX-DIRS 7 + -8 AND ;
: _SX-CX _SX-CXS 7 + -8 AND ; : _SX-SX _SX-SXS 7 + -8 AND ; : _SX-CT _SX-CTS 7 + -8 AND ;
: _SX-TARGET _SX-TARGETS 7 + -8 AND ; : _SX-TARGET2 _SX-TARGET2S 7 + -8 AND ;
: _SX-GI _SX-GIS 7 + -8 AND ; : _SX-GR _SX-GRS 7 + -8 AND ; : _SX-GT _SX-GTS 7 + -8 AND ;
VARIABLE _SX-I VARIABLE _SX-CHILD VARIABLE _SX-RGN VARIABLE _SX-SCREEN
VARIABLE _SX-M VARIABLE _SX-MU VARIABLE _SX-STATUS VARIABLE _SX-ADMISSIONS
VARIABLE _SX-EMITS VARIABLE _SX-REGIONS VARIABLE _SX-TASK-ID VARIABLE _SX-LAUNCH-ID
VARIABLE _SX-SAVED-U VARIABLE _SX-TASK-CORR VARIABLE _SX-LAUNCH-CORR
: _SX-DISJOINT DROP 2DROP -1 ;
: _SX-CALLBACK 2DROP 1 _SX-EMITS +! RTE-S-OK ;
: _SX-REGION 7 0 DO 2DROP LOOP 1 _SX-REGIONS +! RTE-S-OK ;
: _SX-PREFLIGHT 2DROP 1 _SX-ADMISSIONS +! RTE-S-OK ;
: _SX-FACADE
    _SX-F RTE-FACADE-SIZE 0 FILL
    _RTE-MAGIC _SX-F ! RTE-FACADE-SIZE _SX-F _RTE-F.SIZE !
    _SX-F _SX-F _RTE-F.SELF ! 1 _SX-F _RTE-F.CONTEXT !
    RTE-FACADE-SIZE 48 DO ['] _SX-CALLBACK _SX-F I + ! 8 +LOOP
    ['] _SX-DISJOINT _SX-F _RTE-F.DISJOINT-XT !
    ['] _SX-REGION _SX-F _RTE-F.REGION-DEF-XT !
    _SX-FX RTE-SHELL-FACADE-SIZE 0 FILL
    _RTE-SHELL-MAGIC _SX-FX ! RTE-SHELL-FACADE-SIZE _SX-FX _RTE-SH.SIZE !
    _SX-FX _SX-FX _RTE-SH.SELF ! _SX-F _SX-FX _RTE-SH.BASE !
    ['] _SX-PREFLIGHT _SX-FX _RTE-SH.PREFLIGHT-XT !
    ['] _SX-CALLBACK _SX-FX _RTE-SH.PANE-DEFINE-XT !
    ['] _SX-CALLBACK _SX-FX _RTE-SH.PANE-REPLACE-XT ! ;
: _SX-OBSERVE
    ASHELL-DRAW-BEGIN _ASHELL-DRAW-OBSERVE _SS-OK
    _SX-H AHOST-SHELL-DRAW-COMPLETE _SS-OK
    SCR-DRAW-COMPLETE ASHELL-DRAW-COMPLETE _ASHELL-DRAW-OBSERVE _SS-OK
    SCR-DRAW-GENERATION@ _SX-C SHSN-SNAPSHOT-FOR@ _SS-OK _SX-MU ! _SX-M ! ;
: _SX-SOURCE
    32 12 SCR-NEW DUP _SX-SCREEN ! SCR-USE
    _SX-D COMP-DESC-INIT 64 _SX-D COMP.STATE-SIZE !
    _SX-D CINST-NEW _SS-OK DUP _SX-I ! _ASHELL-INST !
    _SX-D CINST-NEW _SS-OK _SX-CHILD !
    _SX-H AHOST-INIT _SX-I @ _SX-H AHOST-CONTEXT!
    0 0 9 19 RGN-NEW _SX-RGN !
    _SX-SLOT AHS-SIZE 0 FILL _SX-CHILD @ _SX-SLOT AHS.INST !
    _SX-RGN @ _SX-SLOT AHS.RGN ! 11 _SX-SLOT AHS.ID !
    AHS-S-FOCUSED _SX-SLOT AHS.STATE ! _SX-SLOT _SX-H AHOST.HEAD !
    _SX-SLOT _SX-H AHOST.FOCUS !
    _SS-BUILD 0 2 _SS-M SHM-ENTRY SHME.FLAGS ! 6 2 _SS-M SHM-ENTRY SHME.COL ! 10 _SS-M SHM.END-COL !
    _SX-I @ CINST.ID @ DUP _SS-M SHM.OWNER-ID ! 2 _SS-M SHM-ENTRY SHME.OWNER-ID !
    _SX-I @ CINST.GENERATION @ DUP _SS-M SHM.OWNER-GEN ! 2 _SS-M SHM-ENTRY SHME.OWNER-GEN !
    _SX-CHILD @ CINST.ID @ DUP 0 _SS-M SHM-ENTRY SHME.OWNER-ID ! 1 _SS-M SHM-ENTRY SHME.OWNER-ID !
    _SX-CHILD @ CINST.GENERATION @ DUP 0 _SS-M SHM-ENTRY SHME.OWNER-GEN ! 1 _SS-M SHM-ENTRY SHME.OWNER-GEN !
    _SS-M _SX-H AHOST-SHELL-MODEL!
    _SX-A 4096 _SX-B 4096 _SX-C SHSN-INIT _SS-OK _SX-C SHSN-INSTALL _SS-OK
    _SX-OBSERVE ;
\ A bank as the screen producer packs it for the candidate now drawn: the
\ header the shell reads, its draw, owner and counts, and the candidate's
\ controls, statics, instruments and series with their correlations, laid
\ out where the producer lays them, each reference an address into the
\ bank's own copy and the texts of each kind in item order.
VARIABLE _SX-PK-AT VARIABLE _SX-PK-S VARIABLE _SX-PK-O
\ The bytes of the references at OFFSET in N records STRIDE apart.
: _SX-PK-SUM ( a n stride offset -- u )
    _SX-PK-O ! _SX-PK-S ! 0 -ROT 0 ?DO
        DUP _SX-PK-O @ + 8 + @ ROT + SWAP _SX-PK-S @ +
    LOOP DROP ;
\ The text the reference at FIELD names goes to the copy's cursor, and the
\ reference points there; an empty one keeps the zero pair.
: _SX-PK-TEXT ( field -- )
    DUP 8 + @ 0= IF 0 SWAP ! EXIT THEN
    DUP @ _SX-PK-AT @ 2 PICK 8 + @ MOVE
    _SX-PK-AT @ OVER ! 8 + @ _SX-PK-AT +! ;
: _SX-PK-MOVE ( src bank-a bytes -- ) ROT ?DUP IF -ROT MOVE ELSE 0 FILL THEN ;
: _SX-PK-CONTROLS ( offset -- u )
    >R _SX-P _RTHP.CONTROLS-A @ _SX-P _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE R> _SX-PK-SUM ;
: _SX-PK-STATICS ( offset -- u )
    >R _SX-P _RTHP.STATICS-A @ _SX-P _RTHP.STATIC-COUNT @ RTE-STATIC-SIZE R> _SX-PK-SUM ;
: _SX-BANK ( bank -- )
    DUP _RTHP-TARGET-BANK-HEADER-SIZE 0 FILL
    88 OVER _RTHP-TB.OWNER ! 99 OVER _RTHP-TB.GENERATION !
    _SX-P _RTHP.SOURCE-DRAW @ OVER _RTHP-TB.DRAW !
    _SX-P _RTHP.REGION @ OVER _RTHP-TB.REGION !
    _SX-P _RTHP.FIRST-OBJECT @ OVER _RTHP-TB.FIRST-OBJECT !
    _SX-P _RTHP.FIRST-SERIES @ OVER _RTHP-TB.FIRST-SERIES !
    _SX-P _RTHP.CONTROL-COUNT @ OVER _RTHP-TB.CONTROL-COUNT !
    _SX-P _RTHP.STATIC-COUNT @ OVER _RTHP-TB.STATIC-COUNT !
    _SX-P _RTHP.INSTRUMENT-REGION-COUNT @ OVER _RTHP-TB.INSTRUMENT-REGION-COUNT !
    _SX-P _RTHP.INSTRUMENT-COUNT @ OVER _RTHP-TB.INSTRUMENT-COUNT !
    _SX-P _RTHP.SERIES-COUNT @ OVER _RTHP-TB.SERIES-COUNT !
    0 _RTE-CONTROL.LABEL-A _SX-PK-CONTROLS 0 _RTE-CONTROL.SHORTCUT-A _SX-PK-CONTROLS +
        0 _RTE-CONTROL.CONTENT-A _SX-PK-CONTROLS + OVER _RTHP-TB.SOURCE-TEXT-USED !
    0 _RTE-STATIC.LABEL-A _SX-PK-STATICS 0 _RTE-STATIC.VALUE-A _SX-PK-STATICS +
        OVER _RTHP-TB.STATIC-TEXT-BYTES !
    _SX-P _RTHP.INSTRUMENTS-A @ _SX-P _RTHP.INSTRUMENT-COUNT @ RTE-INSTRUMENT-SIZE
        0 _RTE-INSTRUMENT.UNIT-A _SX-PK-SUM OVER _RTHP-TB.INSTRUMENT-UNIT-BYTES !
    _SX-P _RTHP.SERIES-A @ _SX-P _RTHP.SERIES-COUNT @ RTE-SERIES-SIZE
        0 _RTE-SERIES.SAMPLES-A _SX-PK-SUM OVER _RTHP-TB.SERIES-SAMPLE-BYTES !
    _SX-P _RTHP.CONTROLS-A @ OVER _RTHP-PACK-CONTROLS-A
        _SX-P _RTHP.CONTROL-COUNT @ RTE-CONTROL-SIZE * _SX-PK-MOVE
    _SX-P _RTHP.CORR-A @ OVER _RTHP-PACK-CORR-A
        _SX-P _RTHP.CONTROL-COUNT @ RUCP-CORRELATION-SIZE * _SX-PK-MOVE
    DUP _RTHP-PACK-SOURCE-A _SX-PK-AT !
    _SX-P _RTHP.CONTROL-COUNT @ 0 ?DO
        DUP _RTHP-PACK-CONTROLS-A I RTE-CONTROL-SIZE * +
        DUP _RTE-CONTROL.LABEL-A _SX-PK-TEXT DUP _RTE-CONTROL.SHORTCUT-A _SX-PK-TEXT
        _RTE-CONTROL.CONTENT-A _SX-PK-TEXT
    LOOP
    _SX-P _RTHP.INSTRUMENT-REGIONS-A @ OVER _RTHP-PACK-INSTRUMENT-REGIONS-A
        _SX-P _RTHP.INSTRUMENT-REGION-COUNT @ RTE-INSTRUMENT-REGION-SIZE * _SX-PK-MOVE
    _SX-P _RTHP.INSTRUMENTS-A @ OVER _RTHP-PACK-INSTRUMENTS-A
        _SX-P _RTHP.INSTRUMENT-COUNT @ RTE-INSTRUMENT-SIZE * _SX-PK-MOVE
    _SX-P _RTHP.INSTRUMENT-CORR-A @ OVER _RTHP-PACK-INSTRUMENT-CORR-A
        _SX-P _RTHP.INSTRUMENT-COUNT @ RUIP-CORRELATION-SIZE * _SX-PK-MOVE
    DUP _RTHP-PACK-INSTRUMENT-UNITS-A _SX-PK-AT !
    _SX-P _RTHP.INSTRUMENT-COUNT @ 0 ?DO
        DUP _RTHP-PACK-INSTRUMENTS-A I RTE-INSTRUMENT-SIZE * + _RTE-INSTRUMENT.UNIT-A _SX-PK-TEXT
    LOOP
    _SX-P _RTHP.STATICS-A @ OVER _RTHP-PACK-STATICS-A
        _SX-P _RTHP.STATIC-COUNT @ RTE-STATIC-SIZE * _SX-PK-MOVE
    _SX-P _RTHP.STATIC-CORR-A @ OVER _RTHP-PACK-STATIC-CORR-A
        _SX-P _RTHP.STATIC-COUNT @ _RTHP-STATIC-CORR-SIZE * _SX-PK-MOVE
    DUP _RTHP-PACK-STATIC-TEXT-A _SX-PK-AT !
    _SX-P _RTHP.STATIC-COUNT @ 0 ?DO
        DUP _RTHP-PACK-STATICS-A I RTE-STATIC-SIZE * +
        DUP _RTE-STATIC.LABEL-A _SX-PK-TEXT _RTE-STATIC.VALUE-A _SX-PK-TEXT
    LOOP
    _SX-P _RTHP.SERIES-A @ OVER _RTHP-PACK-SERIES-A
        _SX-P _RTHP.SERIES-COUNT @ RTE-SERIES-SIZE * _SX-PK-MOVE
    _SX-P _RTHP.SERIES-CORR-A @ OVER _RTHP-PACK-SERIES-CORR-A
        _SX-P _RTHP.SERIES-COUNT @ _RTHP-SERIES-CORR-SIZE * _SX-PK-MOVE
    DUP _RTHP-PACK-SERIES-SAMPLES-A _SX-PK-AT !
    _SX-P _RTHP.SERIES-COUNT @ 0 ?DO
        DUP _RTHP-PACK-SERIES-A I RTE-SERIES-SIZE * + _RTE-SERIES.SAMPLES-A _SX-PK-TEXT
    LOOP
    DUP _RTHP-PACK-SERIES-SAMPLES-A OVER _RTHP-TB.SERIES-SAMPLE-BYTES @ +
        OVER _RTHP-PACK-A - SWAP _RTHP-TB.PACKED-BYTES ! ;
\ The screen producer publishes its pending bank, and retires the frame.
: _SX-PUBLISH
    _SX-P _RTHP.TARGET-PENDING @ DUP _SX-P _RTHP.TARGET-ACTIVE !
    _RTHP-TB.DRAW @ _SX-P _RTHP.ACTIVE-DRAW ! 0 _SX-P _RTHP.TARGET-PENDING !
    _RSHSP-PUBLISH ;
: _SX-RETIRE 0 _SX-P _RTHP.TARGET-ACTIVE ! 0 _SX-P _RTHP.ACTIVE-DRAW ! ;
\ The bank that names PART, the pending one or the one on screen, finds the
\ part whole; a part no bank names is not.
: _SX-NAMES? ( part bank -- flag ) DUP IF _RTHP-TB.XBLOCK @ = ELSE 2DROP 0 THEN ;
: _SX-PART-VALID? ( part -- flag )
    DUP _SX-P _RTHP.TARGET-PENDING @ _SX-NAMES? IF
        DROP _SX-P _RTHP.TARGET-PENDING @ _RSHSP-PART-VALID? EXIT
    THEN
    _SX-P _RTHP.TARGET-ACTIVE @ _SX-NAMES? IF
        _SX-P _RTHP.TARGET-ACTIVE @ _RSHSP-PART-VALID? EXIT
    THEN 0 ;
: _SX-CANDIDATE
    _SX-P RTHP-SIZE 0 FILL _SX-FACADE _SX-F _SX-P _RTHP.FACADE !
    32 _SX-P _RTHP.COLS ! 12 _SX-P _RTHP.ROWS !
    88 _SX-P _RTHP.OWNER ! 99 _SX-P _RTHP.OWNER-GEN !
    10 _SX-P _RTHP.REGION ! 100 _SX-P _RTHP.FIRST-OBJECT !
    1 _SX-P _RTHP.ATTEMPT ! 1 _SX-P _RTHP.SOURCE-GEN !
    SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN !
    _SX-TARGET _SX-P _RTHP.TARGET-PENDING !
    4096 _SX-P _RTHP.GLYPH-TEXT-U ! 256 _SX-P _RTHP.LIMITS _RTE-L.GLYPH-RUN-BYTES !
    0 _SX-P _RTHP.BASE-Z !
    _SX-DIR RUHA-DOCUMENT-SIZE 0 FILL
    77 _SX-DIR _RUHA-D.TOKEN ! 11 _SX-DIR _RUHA-D.SLOT-ID !
    9 _SX-DIR _RUHA-D.HEIGHT ! 19 _SX-DIR _RUHA-D.WIDTH !
    _SX-CHILD @ CINST.ID @ _SX-DIR _RUHA-D.OWNER-ID !
    _SX-CHILD @ CINST.GENERATION @ _SX-DIR _RUHA-D.OWNER-GEN !
    _SX-DIR _SX-P _RTHP.SOURCE-DIR-A ! RUHA-DOCUMENT-SIZE _SX-P _RTHP.SOURCE-DIR-USED !
    _SX-CI RTE-CONTROL-SIZE 0 FILL
    88 _SX-CI _RTE-CONTROL.OWNER ! 99 _SX-CI _RTE-CONTROL.GENERATION !
    100 _SX-CI _RTE-CONTROL.ID ! 1 _SX-CI _RTE-CONTROL.KIND ! 3 _SX-CI _RTE-CONTROL.STATE !
    10 _SX-CI _RTE-CONTROL.REGION ! 1 _SX-CI _RTE-CONTROL.ROW ! 1 _SX-CI _RTE-CONTROL.COL !
    1 _SX-CI _RTE-CONTROL.HEIGHT ! 10 _SX-CI _RTE-CONTROL.WIDTH !
    12 _SX-CI _RTE-CONTROL.ROOT-HEIGHT ! 32 _SX-CI _RTE-CONTROL.ROOT-WIDTH !
    _SX-CI _SX-P _RTHP.CONTROLS-A ! 1 _SX-P _RTHP.CONTROL-COUNT !
    _SX-CX RUCP-CORRELATION-SIZE 0 FILL 77 _SX-CX ! _SX-CX _SX-P _RTHP.CORR-A !
    _SX-SI RTE-STATIC-SIZE 0 FILL
    88 _SX-SI _RTE-STATIC.OWNER ! 99 _SX-SI _RTE-STATIC.GENERATION !
    101 _SX-SI _RTE-STATIC.ID ! 1 _SX-SI _RTE-STATIC.KIND ! -1 _SX-SI _RTE-STATIC.VISIBLE !
    10 _SX-SI _RTE-STATIC.REGION ! 2 _SX-SI _RTE-STATIC.ROW ! 2 _SX-SI _RTE-STATIC.COL !
    1 _SX-SI _RTE-STATIC.HEIGHT ! 8 _SX-SI _RTE-STATIC.WIDTH !
    12 _SX-SI _RTE-STATIC.ROOT-HEIGHT ! 32 _SX-SI _RTE-STATIC.ROOT-WIDTH !
    79 _SX-CT C! 75 _SX-CT 1+ C! _SX-CT _SX-SI _RTE-STATIC.VALUE-A ! 2 _SX-SI _RTE-STATIC.VALUE-U !
    _SX-SI _SX-P _RTHP.STATICS-A ! 1 _SX-P _RTHP.STATIC-COUNT ! 101 _SX-P _RTHP.STATIC-LAST !
    _SX-SX 40 0 FILL 77 _SX-SX ! _SX-SX _SX-P _RTHP.STATIC-CORR-A ! ;
\ What the screen producer does once it has lowered the applications'
\ controls: the shell counts the controls it adds after them
\ (RTHPX-PLAN), and the instruments and statics are numbered past those.
: _SX-NUMBER ( -- )
    _RSHSP-COUNT-CONTROLS _SS-OK
    _SX-P _RTHP-OBJECTS-FIRST? _SS-A
    _SX-P _RTHP.INSTRUMENT-COUNT @ 0 ?DO
        DUP _SX-P _RTHP.INSTRUMENTS-A @ I RTE-INSTRUMENT-SIZE * + _RTE-INSTRUMENT.ID !
        DUP _SX-P _RTHP.INSTRUMENT-LAST ! 1+
    LOOP
    _SX-P _RTHP.STATIC-COUNT @ 0 ?DO
        DUP _SX-P _RTHP.STATICS-A @ I RTE-STATIC-SIZE * + _RTE-STATIC.ID !
        DUP _SX-P _RTHP.STATIC-LAST ! 1+
    LOOP DROP
    \ Then the producer packs its pending bank from the candidate.
    _SX-P _RTHP.TARGET-PENDING @ ?DUP IF _SX-BANK THEN ;
\ A complete preparation as the producer runs it: the count comes in the
\ build, after the draw and the features it read.
: _SX-PREPARE ( -- status ) _SX-NUMBER _RSHSP-PREPARE ;
\ The preparation the producer runs once it has packed its pending bank
\ from the candidate as now built.
: _SX-PACK-PREPARE ( -- status )
    _SX-P _RTHP.TARGET-PENDING @ ?DUP IF _SX-BANK THEN _RSHSP-PREPARE ;
: _SX-SETUP
    _SX-SOURCE _SX-CANDIDATE _SX-S RSHSP-SIZE 0 FILL
    _SX-C _SX-S _RSHSP.SOURCE ! _SX-FX _SX-S _RSHSP.SHELL ! _SX-P _SX-S _RSHSP.PRODUCER !
    _SX-W _SX-P _RTHP.XSCRATCH-A ! 262144 _SX-P _RTHP.XSCRATCH-U !
    _SX-GI _SX-P _RTHP.GLYPH-ITEMS-A ! 46080 _SX-P _RTHP.GLYPH-ITEMS-U !
    _SX-GR _SX-P _RTHP.GLYPH-REFS-A ! 6144 _SX-P _RTHP.GLYPH-REFS-U !
    _SX-GT _SX-P _RTHP.GLYPH-TEXT-A !
    _SX-KA _SX-P _RTHP.XBLOCK0-A ! 131072 _SX-P _RTHP.XBLOCK0-U !
    _SX-KB _SX-P _RTHP.XBLOCK1-A ! 131072 _SX-P _RTHP.XBLOCK1-U !
    _SX-P _RSHSP-P ! _SX-S _RSHSP-S ! _SX-NUMBER ;
'''


def staged_run(program, minimum=1, **kwargs):
    runtime = field_runtime(MODULES)
    try:
        runtime.evaluate(program.encode(), source_name="shell-candidate-proof", step_budget=40_000_000)
    except Exception:
        print(runtime.uart_output.decode(errors="replace")[-18000:])
        raise
    output = runtime.drain_uart_output().decode(errors="replace")
    print(output)
    summary = re.search(r"SHELL SNAP PASS\s+(\d+)\s+0", output)
    assert summary and int(summary[1]) >= minimum, output
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
    return runtime


def test_staged_complete_shell_candidate_owns_graph_and_is_the_pending_bank_s_part():
    staged_run(STAGED + r'''
: _SX-BATCH _SX-KA DUP RSHSP-PART.BATCH @ + ;
: _SX-FIND ( kind -- control|0 )
    _SX-BATCH DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ 64 / 0 ?DO
        DUP I 64 * + DUP _RTE-FE.KIND @ RTE-FAMILY-CONTROL = IF
            RTE-FAMILY-ITEMS@ RTE-CONTROL-SIZE / 0 ?DO
                DUP I RTE-CONTROL-SIZE * + DUP _RTE-CONTROL.KIND @ 4 PICK = IF
                    >R DROP 2DROP R> UNLOOP UNLOOP EXIT THEN DROP
            LOOP DROP
        ELSE DROP THEN
    LOOP 2DROP 0 ;
: _SX-HIT ( id -- )
    _RSHSP-INPUT-ID ! RTE-INTENT-ACTIVATE _RSHSP-INPUT-INTENT !
    _RSHSP-CONTROL-FIND DUP 0<> _SS-A _RSHSP-INPUT-CONTROL !
    _RSHSP-SHELL-TARGET? _SS-A ;
: _SX-REFUSED-HIT ( id -- )
    _RSHSP-INPUT-ID ! RTE-INTENT-ACTIVATE _RSHSP-INPUT-INTENT !
    _RSHSP-CONTROL-FIND DUP 0<> _SS-A _RSHSP-INPUT-CONTROL !
    _RSHSP-SHELL-TARGET? 0= _SS-A ;
_SX-SETUP _SX-PACK-PREPARE _SS-OK
\ The pending bank names the part, frozen into the first extension block.
_SX-TARGET _RTHP-TB.XBLOCK @ _SX-KA = _SS-A _RSHSP-PENDING-PART _SX-KA = _SS-A
_SX-P _RTHP.TARGET-ACTIVE @ 0= _SS-A
_SX-TARGET _RSHSP-PART-VALID? _SS-A
_SX-ADMISSIONS @ 1 = _SS-A _SX-BATCH RTE-FAMILY-BATCH-VALID? _SS-A
." SHELL METRICS " _SX-S RSHSP-SCRATCH-USED@ . _SX-S RSHSP-PART-BYTES@ . CR
_SX-S RSHSP-SCRATCH-USED@ 262144 U< _SS-A
_SX-S RSHSP-PART-BYTES@ _SX-TARGET _RTHP-TB.XBLOCK-BYTES @ = _SS-A
_SX-KA RSHSP-PART.CORRELATIONS-U @ 960 = _SS-A
_SX-KA RSHSP-PART.MEMBERSHIP-U @ 112 = _SS-A
1 _SX-FIND _RTE-CONTROL.ID @ 100 = _SS-A
11 _SX-FIND DUP _RTE-CONTROL.ID @ _SX-TASK-ID ! _RTE-CONTROL.PARENT @ 101 = _SS-A
12 _SX-FIND DUP _RTE-CONTROL.ID @ _SX-LAUNCH-ID ! _RTE-CONTROL.PARENT @ 103 = _SS-A
\ The part is the pending bank's own: another bank names none.
_SX-TARGET2 _SX-BANK _SX-TARGET2 _SX-P _RTHP.TARGET-PENDING ! _RSHSP-PENDING-PART 0= _SS-A
_SX-TARGET _SX-P _RTHP.TARGET-PENDING ! _RSHSP-PENDING-PART _SX-KA = _SS-A
_SX-BATCH _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-REGIONS @ 4 = _SS-A _SX-EMITS @ 7 > _SS-A
_SX-W 262144 165 FILL _SX-TARGET _RSHSP-PART-VALID? _SS-A
_SX-PUBLISH
_RSHSP-ACTIVE-PART _SX-KA = _SS-A _RSHSP-PENDING-PART 0= _SS-A
_RSHSP-CURRENT? _SS-A
_SX-TASK-ID @ _SX-HIT
_RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ROW @ 11 = _SS-A
_RSHSP-INPUT-CORR @ RSHPL-CORRELATION.COL @ 0= _SS-A
_SX-LAUNCH-ID @ _SX-HIT
_RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ROW @ 11 = _SS-A
_RSHSP-INPUT-CORR @ RSHPL-CORRELATION.COL @ 6 = _SS-A
\ Correlation identity swaps cannot redirect a valid control to another slot.
: _SX-SWAP-CORR _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.KEY DUP @ >R 999 SWAP !
_RSHSP-SHELL-TARGET? 0= _SS-A
R> _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.KEY !
_RSHSP-SHELL-TARGET? _SS-A ; _SX-SWAP-CORR
\ Swap valid copied correlation identities without changing either source row.
_SX-TASK-ID @ _RSHSP-INPUT-ID ! _RSHSP-CORRELATION-FIND _SX-TASK-CORR !
_SX-LAUNCH-ID @ _RSHSP-INPUT-ID ! _RSHSP-CORRELATION-FIND _SX-LAUNCH-CORR !
_SX-LAUNCH-ID @ _SX-TASK-CORR @ RSHPL-CORRELATION.ID !
_SX-TASK-ID @ _SX-LAUNCH-CORR @ RSHPL-CORRELATION.ID !
_SX-TASK-ID @ _SX-REFUSED-HIT _SX-LAUNCH-ID @ _SX-REFUSED-HIT
_SX-TASK-ID @ _SX-TASK-CORR @ RSHPL-CORRELATION.ID !
_SX-LAUNCH-ID @ _SX-LAUNCH-CORR @ RSHPL-CORRELATION.ID !
_SX-TASK-ID @ _SX-HIT _SX-LAUNCH-ID @ _SX-HIT
\ Keep source/correlation valid; redirect only CONTROL.ORDER to another real index.
: _SX-WRONG-ORDER
    11 _SX-FIND _RTE-CONTROL.ORDER DUP @ >R DUP >R 2 SWAP !
    _SX-TASK-ID @ _SX-REFUSED-HIT R> R> SWAP ! ;
_SX-WRONG-ORDER _SX-TASK-ID @ _SX-HIT
\ A later ordinary source invalidation, a new root draw beginning, revokes
\ current input authority.
ASHELL-DRAW-BEGIN _ASHELL-DRAW-OBSERVE _SS-OK
_RSHSP-CURRENT? 0= _SS-A
_SS-DONE
''', minimum=62)


def test_pending_exact_ack_survives_source_invalidation_without_restoring_input():
    staged_run(STAGED + r'''
_SX-SETUP _SX-PACK-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KA = _SS-A
_SX-P _RTHP.TARGET-ACTIVE @ 0= _SS-A
ASHELL-DRAW-BEGIN _ASHELL-DRAW-OBSERVE _SS-OK
SCR-DRAW-GENERATION@ _SX-C SHSN-SNAPSHOT-FOR@ SHSN-S-UNAVAILABLE = _SS-A 2DROP
\ The part stays with its bank, which the exact ACK publishes.
_RSHSP-PENDING-PART _SX-KA = _SS-A
_SX-PUBLISH
_RSHSP-ACTIVE-PART _SX-KA = _SS-A
_SX-P _RTHP.TARGET-ACTIVE @ _SX-TARGET = _SS-A
_RSHSP-PENDING-PART 0= _SS-A
_SX-TARGET _RSHSP-PART-VALID? _SS-A
_RSHSP-CURRENT? 0= _SS-A
_SX-RETIRE
_RSHSP-ACTIVE-PART 0= _SS-A
_SS-DONE
''', minimum=27)


def test_final_block_capacity_and_stale_membership_preserve_the_prior_parts():
    staged_run(STAGED + r'''
CREATE _SX-BACKAS 131079 ALLOT CREATE _SX-BACKBS 131079 ALLOT
: _SX-BACKA _SX-BACKAS 7 + -8 AND ; : _SX-BACKB _SX-BACKBS 7 + -8 AND ;
: _SX-UNCHANGED
    _SX-KA 131072 _SX-BACKA 131072 COMPARE 0= _SS-A
    _SX-KB 131072 _SX-BACKB 131072 COMPARE 0= _SS-A
    _RSHSP-ACTIVE-PART _SX-KA = _SS-A
    _RSHSP-PENDING-PART 0= _SS-A ;
_SX-SETUP _SX-PACK-PREPARE _SS-OK
_SX-PUBLISH
_SX-KB 131072 165 FILL
_SX-KA _SX-BACKA 131072 MOVE _SX-KB _SX-BACKB 131072 MOVE
2 _SS-M SHM.EPOCH ! _SX-OBSERVE
SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN !
2 _SX-P _RTHP.SOURCE-GEN !
_SX-TARGET2 _SX-BANK _SX-TARGET2 _SX-P _RTHP.TARGET-PENDING !
1024 _SX-P _RTHP.XSCRATCH-U !
_SX-PACK-PREPARE RTE-S-CAPACITY = _SS-A _SX-UNCHANGED
262144 _SX-P _RTHP.XSCRATCH-U !
128 _SX-P _RTHP.XBLOCK1-U !
_SX-PACK-PREPARE RTE-S-CAPACITY = _SS-A _SX-UNCHANGED
_SX-S RSHSP-PART-BYTES@ 128 U> _SS-A
\ The batch it could not freeze had given the bank's control and static
\ the regions of its pane; the bank holds the producer's region again.
_SX-TARGET2 _RTHP-PACK-CONTROLS-A _RTE-CONTROL.REGION @ 10 = _SS-A
_SX-TARGET2 _RTHP-PACK-STATICS-A _RTE-STATIC.REGION @ 10 = _SS-A
131072 _SX-P _RTHP.XBLOCK1-U !
1 _SX-DIR _RUHA-D.OWNER-GEN +!
_SX-PACK-PREPARE RTE-S-UNAVAILABLE = _SS-A _SX-UNCHANGED
-1 _SX-DIR _RUHA-D.OWNER-GEN +!
_SX-PACK-PREPARE _SS-OK _RSHSP-PENDING-PART _SX-KB = _SS-A
_SX-TARGET2 _RSHSP-PART-VALID? _SS-A
_SX-TARGET2 _RTHP-PACK-CONTROLS-A _RTE-CONTROL.REGION @ 10 <> _SS-A
_SX-KA 131072 _SX-BACKA 131072 COMPARE 0= _SS-A
_SX-P _RTHP-XBLOCK-DROP
_RSHSP-PENDING-PART 0= _SS-A _RSHSP-ACTIVE-PART _SX-KA = _SS-A
_SS-DONE
''', minimum=45)


# The system heap behind a memory source that counts what it hands out.
GROWING = STAGED + r"""
VARIABLE _SG-ALLOCS VARIABLE _SG-FREES VARIABLE _SG-FREED
: _SG-ALLOC ( bytes ctx -- addr|0 ) DROP ALLOCATE IF DROP 0 ELSE 1 _SG-ALLOCS +! THEN ;
: _SG-FREE ( addr bytes ctx -- ) DROP 1 _SG-FREES +! _SG-FREED +! FREE ;
CREATE _SG-SRCS MSRC-SIZE 7 + ALLOT : _SG-SRC _SG-SRCS 7 + -8 AND ;
: _SG-HELD ( -- u )
    _SX-P _RTHP.XSCRATCH-U @ _SX-P _RTHP.XBLOCK0-U @ + _SX-P _RTHP.XBLOCK1-U @ + ;
\ The smallest storage, from one memory source, as Desk sets it up: no
\ scratch or extension block of the producer's yet.
: _SG-SETUP
    _SX-SETUP
    ['] _SG-ALLOC ['] _SG-FREE 0 0 _SG-SRC MSRC-INIT
    0 _SX-P _RTHP.XSCRATCH-A ! 0 _SX-P _RTHP.XSCRATCH-U !
    0 _SX-P _RTHP.XBLOCK0-A ! 0 _SX-P _RTHP.XBLOCK0-U !
    0 _SX-P _RTHP.XBLOCK1-A ! 0 _SX-P _RTHP.XBLOCK1-U !
    _SG-SRC _SX-P _RTHP.MEMORY !
    \ As the constructor leaves it.
    _RSHSP-MAGIC _SX-S _RSHSP.MAGIC ! RSHSP-SIZE _SX-S _RSHSP.SIZE !
    _SX-S _SX-S _RSHSP.SELF !
    0 _SG-ALLOCS ! 0 _SG-FREES ! 0 _SG-FREED ! 0 _RSHSP-DIAG-GROWTHS ! ;
"""


def test_storage_grows_from_its_memory_source_until_the_candidate_fits():
    staged_run(GROWING + r"""
VARIABLE _SG-GROWTHS
_SG-SETUP _SX-PACK-PREPARE _SS-OK
\ The scratch block and the extension block the part froze into grew until
\ the candidate fit.
_RSHSP-DIAG-GROWTHS @ 2 < 0= _SS-A
_SX-P _RTHP.XSCRATCH-U @ _SX-S RSHSP-SCRATCH-USED@ U< 0= _SS-A
_SX-P _RTHP.XBLOCK0-U @ _SX-S RSHSP-PART-BYTES@ U< 0= _SS-A
_RSHSP-PENDING-PART _SX-P _RTHP.XBLOCK0-A @ = _SS-A
_SX-TARGET _RSHSP-PART-VALID? _SS-A
_SX-P _RTHP.XBLOCK1-U @ 0= _SS-A
\ Each block it replaced went back, all but the first scratch and
\ extension blocks: the source holds what the producer holds.
_SG-SRC MSRC-HELD@ _SG-HELD = _SS-A
_SG-ALLOCS @ _RSHSP-DIAG-GROWTHS @ = _SS-A _SG-FREES @ 2 + _SG-ALLOCS @ = _SS-A
\ Preparing again into the same block takes nothing more.
_RSHSP-DIAG-GROWTHS @ _SG-GROWTHS !
_SX-PACK-PREPARE _SS-OK _RSHSP-DIAG-GROWTHS @ _SG-GROWTHS @ = _SS-A
\ With the first block's part on screen, the second grows the same way and
\ the first is untouched.
_SX-PUBLISH
_RSHSP-ACTIVE-PART _SX-P _RTHP.XBLOCK0-A @ = _SS-A
_SX-TARGET2 _SX-BANK _SX-TARGET2 _SX-P _RTHP.TARGET-PENDING !
_SX-PACK-PREPARE _SS-OK
_RSHSP-PENDING-PART _SX-P _RTHP.XBLOCK1-A @ = _SS-A
_SX-P _RTHP.XBLOCK1-U @ _SX-S RSHSP-PART-BYTES@ U< 0= _SS-A
_SX-TARGET2 _RSHSP-PART-VALID? _SS-A
_SX-TARGET _RSHSP-PART-VALID? _SS-A
_SG-SRC MSRC-HELD@ _SG-HELD = _SS-A
\ The shell holds nothing to give back; the producer keeps its blocks.
_SX-S RSHSP-FINI _SX-S _RSHSP.MAGIC @ 0= _SS-A
_SG-SRC MSRC-HELD@ _SG-HELD = _SS-A
_SS-DONE
""", minimum=20)


def test_a_refused_growth_leaves_the_blocks_and_records_the_bytes():
    staged_run(GROWING + r"""
_SG-SETUP
\ Room for no block.
_SG-SRC MSRC-HELD@ 64 + _SG-SRC MSRC.BUDGET !
0 _RTHP-W-MEMORY-ASKED ! 0 _RTHP-W-MEMORY-HELD !
_SX-PACK-PREPARE RTE-S-CAPACITY = _SS-A
_RSHSP-PENDING-PART 0= _SS-A
_SX-P _RTHP.XSCRATCH-U @ 0= _SS-A
_SX-P _RTHP.XBLOCK0-U @ 0= _SS-A
_SX-P _RTHP.XBLOCK1-U @ 0= _SS-A
_RTHP-W-MEMORY-ASKED @ 0<> _SS-A
_RTHP-W-MEMORY-HELD @ _SG-SRC MSRC-HELD@ = _SS-A
_SG-SRC MSRC-HELD@ _SG-HELD = _SS-A
_SS-DONE
""", minimum=9)


def test_a_grown_scratch_block_that_overlaps_the_producer_s_storage_is_an_anomaly():
    """The screen producer grows the scratch block the shell builds in.  A
    block from the memory source that overlaps the producer's own record
    means the source's records are wrong, which only a bug causes.  The
    producer gives it back unused, the preparation refuses, and safe mode
    turns on for the rest of the session, naming the source (check-mode.f)."""
    staged_run(GROWING + r"""
\ A source that hands out the producer's own record, and takes it back
\ without freeing it.
: _SG-BAD-ALLOC ( bytes ctx -- addr|0 ) 2DROP 1 _SG-ALLOCS +! _SX-P ;
: _SG-BAD-FREE ( addr bytes ctx -- ) DROP 2DROP 1 _SG-FREES +! ;
_SG-SETUP
' _SG-BAD-ALLOC _SG-SRC MSRC.ALLOC-XT ! ' _SG-BAD-FREE _SG-SRC MSRC.FREE-XT !
CHK-SAFE? 0= _SS-A
_SX-PACK-PREPARE RTE-S-INVALID = _SS-A
_SG-ALLOCS @ 1 = _SS-A _SG-FREES @ 1 = _SS-A
_SX-P _RTHP.XSCRATCH-A @ 0= _SS-A
CHK-SAFE-MODE @ CHK-WHY-ANOMALY = _SS-A
CHK-DAMAGE S" Desk's memory source" COMPARE 0= _SS-A
_SS-DONE
""", minimum=7)


def test_a_grown_extension_block_that_overlaps_the_producer_s_storage_is_an_anomaly():
    """The screen producer grows the extension block the shell's part goes
    into.  A block from the memory source that overlaps the producer's own
    record means the source's records are wrong: the producer gives it back
    unused, the free block stays as it was, the preparation refuses, and
    safe mode turns on, naming the source (check-mode.f)."""
    staged_run(GROWING + r"""
: _SG-BAD-ALLOC ( bytes ctx -- addr|0 ) 2DROP 1 _SG-ALLOCS +! _SX-P ;
: _SG-BAD-FREE ( addr bytes ctx -- ) DROP 2DROP 1 _SG-FREES +! ;
_SG-SETUP
\ A scratch block that already holds the build, so the extension block is
\ the first block to grow.
_SX-W _SX-P _RTHP.XSCRATCH-A ! 262144 _SX-P _RTHP.XSCRATCH-U !
' _SG-BAD-ALLOC _SG-SRC MSRC.ALLOC-XT ! ' _SG-BAD-FREE _SG-SRC MSRC.FREE-XT !
CHK-SAFE? 0= _SS-A
_SX-PACK-PREPARE RTE-S-INVALID = _SS-A
_SG-ALLOCS @ 1 = _SS-A _SG-FREES @ 1 = _SS-A
_SX-P _RTHP.XBLOCK0-A @ 0= _SS-A _RSHSP-PENDING-PART 0= _SS-A
CHK-SAFE-MODE @ CHK-WHY-ANOMALY = _SS-A
CHK-DAMAGE S" Desk's memory source" COMPARE 0= _SS-A
_SS-DONE
""", minimum=8)


def test_unmodeled_final_writer_omits_both_bands_and_preserves_pane_membership():
    staged_run(STAGED + r'''
: _SX-LATER 88 11 9 DRW-CHAR ;
\ The producer builds after the overlay, which covers the taskbar.
_SX-SETUP ' _SX-LATER DRW-OVERLAY _SX-NUMBER
_SX-PACK-PREPARE _SS-OK
_SX-TARGET _RSHSP-PART-VALID? _SS-A
_SX-KA RSHSP-PART.CORRELATIONS-U @ RSHPL-CORRELATION-SIZE = _SS-A
_SX-KA RSHSP-PART.MEMBERSHIP-U @ RSHMM-ENTRY-SIZE = _SS-A
_SX-KA DUP RSHSP-PART.CORRELATIONS @ + RSHPL-CORRELATION.KIND @ SHM-K-PANE = _SS-A
_SX-KA DUP RSHSP-PART.BATCH @ + RTE-FAMILY-BATCH-VALID? _SS-A
_SS-DONE
''', minimum=21)


def test_the_shell_plans_its_runs_in_the_producer_s_glyph_banks():
    """While the shell is installed the screen producer plans no runs of its
    own, and the shell plans each region's runs in the producer's glyph
    banks, which are sized for every cell of the surface, then copies only
    the runs planned into its batch.  The producer then holds no plan of
    its own for any draw, so it takes none of what the banks hold for one;
    the shell plans with no reference to it, with every check on as well."""
    staged_run(STAGED + r'''
_SX-SETUP
\ A plan the producer held for this draw, before the shell's.
_SX-P _RTHP.SOURCE-DRAW @ _SX-P _RTHP.GLYPH-DRAW !
_SX-GI 46080 165 FILL
-1 CHK-EVERY-FRAME !
_SX-PREPARE _SS-OK CHK-DAMAGE-COUNT @ 0= _SS-A
0 CHK-EVERY-FRAME !
_SX-P _RTHP.GLYPH-DRAW @ 0= _SS-A
_SX-TARGET _RSHSP-PART-VALID? _SS-A
\ The banks held the slots: the runs the batch keeps are copies.
_SX-GI C@ 165 <> _SS-A
_SS-DONE
''', minimum=4)


def test_the_frozen_part_gives_the_bank_s_items_the_regions_of_its_panes():
    """Once the shell's part is frozen and named by the pending bank, the
    bank's application controls and statics carry the regions the batch
    placed them in, the panes' regions, so the bank records the frame its
    part holds.  The screen producer packed them in its own region."""
    staged_run(STAGED + r'''
\ The first item of the part's first family of KIND.
VARIABLE _SX-FI
: _SX-FIRST ( kind -- item )
    _SX-FI ! _SX-KA DUP RSHSP-PART.BATCH @ + DUP _RTE-FB.FAMILIES-A @
    SWAP _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        DUP I RTE-FAMILY-ENTRY-SIZE * + DUP _RTE-FE.KIND @ _SX-FI @ = IF
            NIP RTE-FAMILY-ITEMS@ DROP UNLOOP EXIT
        THEN DROP
    LOOP DROP 0 ;
_SX-SETUP
\ The pending bank as the producer packs it, its control and static in the
\ producer's own region.
_SX-TARGET _RTHP-PACK-CONTROLS-A _RTE-CONTROL.REGION @ 10 = _SS-A
_SX-PREPARE _SS-OK _SX-TARGET _RTHP-TB.XBLOCK @ _SX-KA = _SS-A
_SX-TARGET _RTHP-PACK-CONTROLS-A _RTE-CONTROL.REGION @
    DUP 10 <> _SS-A RTE-FAMILY-CONTROL _SX-FIRST _RTE-CONTROL.REGION @ = _SS-A
_SX-TARGET _RTHP-PACK-STATICS-A _RTE-STATIC.REGION @
    DUP 10 <> _SS-A RTE-FAMILY-STATIC _SX-FIRST _RTE-STATIC.REGION @ = _SS-A
\ The producer's own candidate keeps its region.
_SX-CI _RTE-CONTROL.REGION @ 10 = _SS-A _SX-SI _RTE-STATIC.REGION @ 10 = _SS-A
_SS-DONE
''', minimum=7)


def test_nonzero_menu_claim_keeps_residue_underlay_and_excludes_opaque_status():
    staged_run(STAGED + r'''
CREATE _SM-CLAIMS-S RUCL-CLAIM-SIZE 2 * 7 + ALLOT
CREATE _SM-COVER 384 ALLOT CREATE _SM-CPS-S 3079 ALLOT
: _SM-CLAIMS _SM-CLAIMS-S 7 + -8 AND ; : _SM-CPS _SM-CPS-S 7 + -8 AND ;
VARIABLE _SM-BACK VARIABLE _SM-RESIDUE VARIABLE _SM-BATCH VARIABLE _SM-FAMILY
VARIABLE _SM-ITEM VARIABLE _SM-TEXT VARIABLE _SM-U VARIABLE _SM-ROW VARIABLE _SM-COL
: _SM-MENU 10 0 DO 77 1 I 1+ DRW-CHAR LOOP ;
: _SM-PAINT
    10 0 DO 65 I + 1 I 1+ DRW-CHAR LOOP
    8 0 DO 90 2 I 2 + DRW-CHAR LOOP
    ['] _SM-MENU DRW-REPLACEMENT ;
: _SM-PLANES ( back residue cols rows draw dirty -- )
    2DROP 2DROP _SM-RESIDUE ! _SM-BACK !
    10 0 DO
        _SM-BACK @ 33 I + 8 * + @ CELL-CP@ 77 = _SS-A
        _SM-RESIDUE @ 33 I + 8 * + @ CELL-CP@ 65 I + = _SS-A
    LOOP 0 _SM-BACK ! 0 _SM-RESIDUE ! ;
: _SM-DRAW
    ASHELL-DRAW-BEGIN _ASHELL-DRAW-OBSERVE _SS-OK
    _SM-PAINT _SX-H AHOST-SHELL-DRAW-COMPLETE _SS-OK
    SCR-DRAW-COMPLETE ASHELL-DRAW-COMPLETE _ASHELL-DRAW-OBSERVE _SS-OK
    SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN !
    _SX-TARGET _SX-BANK ;
: _SM-CLAIM-SETUP
    77 1 1 0 100 0 1 1 2 11 _SM-CLAIMS RUCL-ADMITTED-RECTANGLE! _SS-OK
    77 1 1 1 101 0 2 2 3 10 _SM-CLAIMS RUCL-CLAIM-SIZE + RUCL-ADMITTED-RECTANGLE! _SS-OK
    _SM-CLAIMS _SX-P _RTHP.CLAIMS-A !
    RUCL-CLAIM-SIZE 2 * _SX-P _RTHP.CLAIMS-USED !
    1 _SX-P _RTHP.MENU-CLAIMS ! ;
: _SM-GLYPHS ( family -- )
    _SM-FAMILY !
    _SM-FAMILY @ RTE-FAMILY-ITEMS@ RTE-GLYPH-RUN-PLAN-ITEM-SIZE / 0 ?DO
        DUP I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _SM-ITEM !
        _SM-ITEM @ _RTE-LPI.ROW @ _SM-ROW ! _SM-ITEM @ _RTE-LPI.COL @ _SM-COL !
        _SM-ITEM @ _RTE-LPI.HEIGHT @ 1 = _SS-A
        _SM-FAMILY @ _RTE-FE.REFS-A @ I 16 * + DUP 8 + @ _SM-U !
        @ _SM-FAMILY @ _RTE-FE.BYTES-A @ + _SM-TEXT !
        _SM-U @ _SM-ITEM @ _RTE-LPI.WIDTH @ = _SS-A
        _SM-U @ 0 ?DO
            _SM-ROW @ 32 * _SM-COL @ + I + DUP
            _SM-COVER + DUP C@ 1+ SWAP C!
            8 * _SM-CPS + _SM-TEXT @ I + C@ SWAP !
        LOOP
    LOOP DROP ;
: _SM-REPLAY
    _SM-COVER 384 0 FILL _SM-CPS 3072 0 FILL
    _SX-KA DUP RSHSP-PART.BATCH @ + _SM-BATCH !
    _SM-BATCH @ _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        _SM-BATCH @ _RTE-FB.FAMILIES-A @ I RTE-FAMILY-ENTRY-SIZE * +
        DUP _RTE-FE.KIND @ RTE-FAMILY-GLYPH = IF _SM-GLYPHS ELSE DROP THEN
    LOOP ;
: _SM-COVERAGE
    10 0 DO
        _SM-COVER 33 I + + C@ 1 = _SS-A
        _SM-CPS 33 I + 8 * + @ 65 I + = _SS-A
    LOOP
    8 0 DO _SM-COVER 66 I + + C@ 0= _SS-A LOOP
    _SM-COVER 65 + C@ 1 = _SS-A _SM-COVER 74 + C@ 1 = _SS-A ;
_SX-SETUP _SM-DRAW _SM-CLAIM-SETUP
' _SM-PLANES SCR-WITH-PROJECTION-PLANES
_SX-P _RTHP.MENU-CLAIMS @ 1 = _SS-A
_SX-PACK-PREPARE _SS-OK
_SX-TARGET _RSHSP-PART-VALID? _SS-A
_SM-REPLAY _SM-COVERAGE
\ Frozen replay is independent of transient work and current CELL planes.
_SX-W 262144 165 FILL _SM-MENU
_SM-REPLAY _SM-COVERAGE
_SS-DONE
''', minimum=120)


INSTRUMENTS = STAGED + r'''
CREATE _SI-SLOTS AHS-SIZE 7 + ALLOT CREATE _SI-DIRS RUHA-DOCUMENT-SIZE 2 * 7 + ALLOT
CREATE _SI-IRS 103 ALLOT CREATE _SI-IR-BACKS 103 ALLOT
CREATE _SI-IS RTE-INSTRUMENT-SIZE 2 * 7 + ALLOT
CREATE _SI-CS RUIP-CORRELATION-SIZE 2 * 7 + ALLOT
CREATE _SI-YS 95 ALLOT CREATE _SI-SAMPLES-S 128007 ALLOT
CREATE _SI-WS 524295 ALLOT CREATE _SI-AS 524295 ALLOT CREATE _SI-BS 524295 ALLOT
: _SI-SLOT _SI-SLOTS 7 + -8 AND ; : _SI-DIR _SI-DIRS 7 + -8 AND ;
: _SI-IR _SI-IRS 7 + -8 AND ; : _SI-IR-BACK _SI-IR-BACKS 7 + -8 AND ;
: _SI-I _SI-IS 7 + -8 AND ; : _SI-C _SI-CS 7 + -8 AND ;
: _SI-Y _SI-YS 7 + -8 AND ; : _SI-SAMPLES _SI-SAMPLES-S 7 + -8 AND ;
: _SI-W _SI-WS 7 + -8 AND ; : _SI-A _SI-AS 7 + -8 AND ; : _SI-B _SI-BS 7 + -8 AND ;
VARIABLE _SI-CHILD VARIABLE _SI-RGN VARIABLE _SI-E VARIABLE _SI-BATCH
VARIABLE _SI-CATALOG VARIABLE _SI-FAMILY VARIABLE _SI-PLAN VARIABLE _SI-FROZEN-Y
VARIABLE _SI-FROZEN-IR VARIABLE _SI-MEMBER VARIABLE _SI-EMIT-I VARIABLE _SI-EMIT-Y
: _SI-INSTRUMENT-CALLBACK ( instrument context -- status )
    DROP DUP _RTE-INSTRUMENT.REGION @ 11 = _SS-A
    DUP _RTE-INSTRUMENT.ROOT-WIDTH @ 8 = _SS-A
    _RTE-INSTRUMENT.ROOT-HEIGHT @ 6 = _SS-A
    1 _SI-EMIT-I +! RTE-S-OK ;
: _SI-SERIES-CALLBACK ( series context -- status )
    DROP DUP _RTE-SERIES.CAPACITY @ 16000 = _SS-A
    DUP _RTE-SERIES.SAMPLES-U @ 128000 = _SS-A
    _RTE-SERIES.INTERVAL-US @ 125 = _SS-A
    1 _SI-EMIT-Y +! RTE-S-OK ;
: _SI-SECOND-PANE
    _SX-D CINST-NEW _SS-OK _SI-CHILD !
    1 21 8 10 RGN-NEW _SI-RGN !
    _SI-SLOT AHS-SIZE 0 FILL _SI-CHILD @ _SI-SLOT AHS.INST !
    _SI-RGN @ _SI-SLOT AHS.RGN ! 12 _SI-SLOT AHS.ID !
    AHS-S-RUNNING _SI-SLOT AHS.STATE ! _SI-SLOT _SX-SLOT AHS.NEXT !
    0 _SS-M SHM.READY ! _SS-M SHM-APPEND DUP 0<> _SS-A _SI-E !
    12 _SI-E @ SHME.KEY ! SHM-K-PANE _SI-E @ SHME.KIND !
    1 _SI-E @ SHME.ROW ! 21 _SI-E @ SHME.COL !
    9 _SI-E @ SHME.HEIGHT ! 11 _SI-E @ SHME.WIDTH !
    1 _SI-E @ SHME.CONTENT-ROW ! 21 _SI-E @ SHME.CONTENT-COL !
    8 _SI-E @ SHME.CONTENT-H ! 10 _SI-E @ SHME.CONTENT-W !
    _SI-CHILD @ CINST.ID @ _SI-E @ SHME.OWNER-ID !
    _SI-CHILD @ CINST.GENERATION @ _SI-E @ SHME.OWNER-GEN !
    12 _SI-E @ SHME.IDENTITY ! 12 _SI-E @ SHME.ACTION !
    \ Canonical SHM groups panes before tasks/launchers and stores text densely
    \ in that same order, so inserting the pane also rebuilds its text bank.
    3 _SS-M SHM-ENTRY _SS-O SHM-ENTRY-SIZE MOVE
    1 _SS-M SHM-ENTRY 2 _SS-M SHM-ENTRY SHM-ENTRY-SIZE 2 * MOVE
    _SS-O 1 _SS-M SHM-ENTRY SHM-ENTRY-SIZE MOVE
    4 0 DO I _SS-M SHM-ENTRY SHME.LABEL-OFF 48 0 FILL LOOP
    SHM-HEADER-SIZE SHM-ENTRY-SIZE 4 * + _SS-M SHM.USED !
    S" Editor" _SS-M SHM-COPY$ _SS-A 0 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    6 0 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" Sound" _SS-M SHM-COPY$ _SS-A 1 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    5 1 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" Edit" _SS-M SHM-COPY$ _SS-A 2 _SS-M SHM-ENTRY SHME.LABEL-OFF !
    4 2 _SS-M SHM-ENTRY SHME.LABEL-U !
    S" Editor" _SS-M SHM-COPY$ _SS-A 2 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    6 2 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" Run" _SS-M SHM-COPY$ _SS-A 3 _SS-M SHM-ENTRY SHME.LABEL-OFF !
    3 3 _SS-M SHM-ENTRY SHME.LABEL-U !
    S" Launch" _SS-M SHM-COPY$ _SS-A 3 _SS-M SHM-ENTRY SHME.TITLE-OFF !
    6 3 _SS-M SHM-ENTRY SHME.TITLE-U !
    S" start" _SS-M SHM-COPY$ _SS-A 3 _SS-M SHM-ENTRY SHME.ACTION-OFF !
    5 3 _SS-M SHM-ENTRY SHME.ACTION-U !
    2 _SS-M SHM.EPOCH ! _SS-M SHM-SEAL
    _SX-OBSERVE
    SCR-DRAW-GENERATION@ DUP _SX-P _RTHP.SOURCE-DRAW ! _SX-P _RTHP.SURFACE-GEN !
    _SX-TARGET _SX-BANK
    _SX-DIR _SI-DIR RUHA-DOCUMENT-SIZE MOVE
    _SI-DIR RUHA-DOCUMENT-SIZE + DUP RUHA-DOCUMENT-SIZE 0 FILL _SI-E !
    78 _SI-E @ _RUHA-D.TOKEN ! 12 _SI-E @ _RUHA-D.SLOT-ID !
    1 _SI-E @ _RUHA-D.ROW ! 21 _SI-E @ _RUHA-D.COL !
    8 _SI-E @ _RUHA-D.HEIGHT ! 10 _SI-E @ _RUHA-D.WIDTH !
    _SI-CHILD @ CINST.ID @ _SI-E @ _RUHA-D.OWNER-ID !
    _SI-CHILD @ CINST.GENERATION @ _SI-E @ _RUHA-D.OWNER-GEN !
    _SI-DIR _SX-P _RTHP.SOURCE-DIR-A !
    RUHA-DOCUMENT-SIZE 2 * _SX-P _RTHP.SOURCE-DIR-USED ! ;
: _SI-LEGACY
    _SI-IR 96 0 FILL 11 _SI-IR _RTE-IR.ID !
    22 _SI-IR _RTE-IR.X ! 2 _SI-IR _RTE-IR.Y !
    8 _SI-IR _RTE-IR.COLS ! 6 _SI-IR _RTE-IR.ROWS !
    -1 _SI-IR _RTE-IR.Z ! RTE-REGION-VISIBLE _SI-IR _RTE-IR.FLAGS !
    _SI-IR _SX-P _RTHP.INSTRUMENT-REGIONS-A ! 1 _SX-P _RTHP.INSTRUMENT-REGION-COUNT !
    _SI-I RTE-INSTRUMENT-SIZE 2 * 0 FILL _SI-C RUIP-CORRELATION-SIZE 2 * 0 FILL
    2 0 DO
        _SI-I I RTE-INSTRUMENT-SIZE * + _SI-E !
        88 _SI-E @ _RTE-INSTRUMENT.OWNER ! 99 _SI-E @ _RTE-INSTRUMENT.GENERATION !
        101 I + _SI-E @ _RTE-INSTRUMENT.ID ! -1 _SI-E @ _RTE-INSTRUMENT.VISIBLE !
        11 _SI-E @ _RTE-INSTRUMENT.REGION ! 8 _SI-E @ _RTE-INSTRUMENT.ROOT-WIDTH !
        6 _SI-E @ _RTE-INSTRUMENT.ROOT-HEIGHT ! 8 _SI-E @ _RTE-INSTRUMENT.WIDTH !
        78 _SI-C I RUIP-CORRELATION-SIZE * + !
    LOOP
    RTE-INSTRUMENT-WAVEFORM _SI-I _RTE-INSTRUMENT.KIND !
    4 _SI-I _RTE-INSTRUMENT.HEIGHT ! -32768 _SI-I _RTE-INSTRUMENT.MINIMUM !
    32767 _SI-I _RTE-INSTRUMENT.MAXIMUM ! 7 _SI-I _RTE-INSTRUMENT.SERIES-ID !
    _SI-I RTE-INSTRUMENT-SIZE + _SI-E !
    RTE-INSTRUMENT-METER _SI-E @ _RTE-INSTRUMENT.KIND !
    4 _SI-E @ _RTE-INSTRUMENT.ROW ! 1 _SI-E @ _RTE-INSTRUMENT.HEIGHT !
    100 _SI-E @ _RTE-INSTRUMENT.MAXIMUM ! 50 _SI-E @ _RTE-INSTRUMENT.VALUE !
    _SI-I _SX-P _RTHP.INSTRUMENTS-A ! 2 _SX-P _RTHP.INSTRUMENT-COUNT !
    102 _SX-P _RTHP.INSTRUMENT-LAST ! _SI-C _SX-P _RTHP.INSTRUMENT-CORR-A !
    103 _SX-SI _RTE-STATIC.ID ! 103 _SX-P _RTHP.STATIC-LAST !
    _SX-P _RTHP.INSTRUMENT-PLAN _SI-PLAN !
    88 _SI-PLAN @ _RTE-IP.OWNER ! 99 _SI-PLAN @ _RTE-IP.GENERATION !
    32 _SI-PLAN @ _RTE-IP.SURFACE-COLS ! 12 _SI-PLAN @ _RTE-IP.SURFACE-ROWS !
    _SI-IR _SI-PLAN @ _RTE-IP.REGIONS-A ! 96 _SI-PLAN @ _RTE-IP.REGIONS-U !
    _SI-I _SI-PLAN @ _RTE-IP.ITEMS-A ! RTE-INSTRUMENT-SIZE 2 * _SI-PLAN @ _RTE-IP.ITEMS-U !
    16000 0 DO I 4 * 32768 - _SI-SAMPLES I 8 * + ! LOOP
    _SI-Y 88 0 FILL 88 _SI-Y _RTE-SERIES.OWNER ! 99 _SI-Y _RTE-SERIES.GENERATION !
    7 _SI-Y _RTE-SERIES.ID ! 16000 _SI-Y _RTE-SERIES.CAPACITY !
    RTE-SERIES-UNIFORM _SI-Y _RTE-SERIES.MODE ! 125 _SI-Y _RTE-SERIES.INTERVAL-US !
    _SI-SAMPLES _SI-Y _RTE-SERIES.SAMPLES-A ! 128000 _SI-Y _RTE-SERIES.SAMPLES-U !
    1000 _SI-Y _RTE-SERIES.CHUNK-SAMPLES !
    _SI-Y _SX-P _RTHP.SERIES-A ! 1 _SX-P _RTHP.SERIES-COUNT !
    _SI-SAMPLES _SX-P _RTHP.SERIES-SAMPLES-A ! 128000 _SX-P _RTHP.SERIES-SAMPLES-USED !
    _SX-P _RTHP.SERIES-PLAN _SI-PLAN !
    88 _SI-PLAN @ _RTE-SRP.OWNER ! 99 _SI-PLAN @ _RTE-SRP.GENERATION !
    32 _SI-PLAN @ _RTE-SRP.SURFACE-COLS ! 12 _SI-PLAN @ _RTE-SRP.SURFACE-ROWS !
    _SI-Y _SI-PLAN @ _RTE-SRP.ITEMS-A ! 88 _SI-PLAN @ _RTE-SRP.ITEMS-U ! ;
: _SI-SETUP
    _SX-SETUP _SI-SECOND-PANE _SI-LEGACY
    _SI-W _SX-P _RTHP.XSCRATCH-A ! 524288 _SX-P _RTHP.XSCRATCH-U !
    _SI-A _SX-P _RTHP.XBLOCK0-A ! 524288 _SX-P _RTHP.XBLOCK0-U !
    _SI-B _SX-P _RTHP.XBLOCK1-A ! 524288 _SX-P _RTHP.XBLOCK1-U !
    ['] _SI-INSTRUMENT-CALLBACK _SX-F _RTE-F.INSTRUMENT-DEF-XT !
    ['] _SI-SERIES-CALLBACK _SX-F _RTE-F.SERIES-DEFINE-XT ! _SX-NUMBER ;
: _SI-FIND ( kind -- family )
    _SI-BATCH @ _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        _SI-BATCH @ _RTE-FB.FAMILIES-A @ I RTE-FAMILY-ENTRY-SIZE * +
        DUP _RTE-FE.KIND @ 2 PICK = IF NIP UNLOOP EXIT THEN DROP
    LOOP DROP 0 ;
: _SI-FROZEN
    _SI-A DUP RSHSP-PART.BATCH @ + _SI-BATCH !
    _SI-BATCH @ _RTE-FB.CATALOG-A @ _SI-CATALOG !
    11 _SI-CATALOG @ RTE-REGION-CATALOG-FIND DUP 0<> _SS-A _SI-FROZEN-IR !
    RTE-FAMILY-SERIES _SI-FIND DUP 0<> _SS-A RTE-FAMILY-ITEMS@ 88 = _SS-A _SI-FROZEN-Y ! ;
: _SI-SAMPLES-EXACT
    _SI-FROZEN-Y @ _RTE-SERIES.SAMPLES-U @ 128000 = _SS-A
    _SI-FROZEN-Y @ _RTE-SERIES.CAPACITY @ 16000 = _SS-A
    _SI-FROZEN-Y @ _RTE-SERIES.MODE @ RTE-SERIES-UNIFORM = _SS-A
    _SI-FROZEN-Y @ _RTE-SERIES.INTERVAL-US @ 125 = _SS-A
    _SI-FROZEN-Y @ _RTE-SERIES.FIRST-US @ 0= _SS-A
    16000 0 DO _SI-FROZEN-Y @ _RTE-SERIES.SAMPLES-A @ I 8 * + @
        I 4 * 32768 - = _SS-A LOOP ;
'''


def test_two_panes_unclipped_local_instruments_preserve_full_owned_series():
    staged_run(INSTRUMENTS + r'''
_SI-SETUP _SI-IR _SI-IR-BACK 96 MOVE
_SX-PACK-PREPARE _SS-OK _SX-ADMISSIONS @ 1 = _SS-A
_SX-TARGET _RSHSP-PART-VALID? _SS-A _SI-FROZEN
_SI-BATCH @ RTE-FAMILY-BATCH-VALID? _SS-A
_SI-IR 96 _SI-IR-BACK 96 COMPARE 0= _SS-A
_SX-P _RTHP.INSTRUMENT-PLAN _RTE-IP.REGIONS-A @ _SI-IR = _SS-A
_SI-FROZEN-IR @ _RTE-IR.FLAGS @ 3 = _SS-A
_SI-FROZEN-IR @ _RTE-IR.CLIP-X @ 22 = _SS-A
_SI-FROZEN-IR @ _RTE-IR.CLIP-Y @ 2 = _SS-A
_SI-FROZEN-IR @ _RTE-IR.CLIP-COLS @ 8 = _SS-A
_SI-FROZEN-IR @ _RTE-IR.CLIP-ROWS @ 6 = _SS-A
RTE-FAMILY-INSTRUMENT _SI-FIND _RTE-FE.PLAN-A @ _RTE-IP.REGIONS-A @
96 _SI-FROZEN-IR @ 96 COMPARE 0= _SS-A
78 _SI-A DUP RSHSP-PART.MEMBERSHIP @ +
_SI-A RSHSP-PART.MEMBERSHIP-U @ RSHMM-FIND DUP 0<> _SS-A _SI-MEMBER !
_SI-MEMBER @ RSHMM.SLOT-ID @ 12 = _SS-A
_SI-MEMBER @ RSHMM.ROW @ 1 = _SS-A _SI-MEMBER @ RSHMM.COL @ 21 = _SS-A
RTE-FAMILY-PANE _SI-FIND RTE-FAMILY-ITEMS@ RTE-PANE-SIZE 2 * = _SS-A
RTE-PANE-SIZE + _RTE-PANE.CONTENT-REGION @ _SI-MEMBER @ RSHMM.CONTENT-REGION @ = _SS-A
_SI-SAMPLES-EXACT
_SI-BATCH @ _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SI-EMIT-I @ 2 = _SS-A _SI-EMIT-Y @ 1 = _SS-A _SX-REGIONS @ 6 = _SS-A
." SHELL INSTRUMENT METRICS " _SX-S RSHSP-SCRATCH-USED@ . _SX-S RSHSP-PART-BYTES@ . CR
_SI-W 524288 165 FILL _SI-SAMPLES 128000 0 FILL
_SI-SAMPLES-EXACT _SX-TARGET _RSHSP-PART-VALID? _SS-A
_SS-DONE
''', minimum=32060)


def test_local_instrument_refuses_wrong_pane_and_preserves_explicit_subclip():
    staged_run(INSTRUMENTS + r'''
_SI-SETUP
\ This root remains on the 32-column surface but escapes pane2's right edge31.
24 _SI-IR _RTE-IR.X ! _SX-PACK-PREPARE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-PENDING-PART 0= _SS-A _SX-ADMISSIONS @ 0= _SS-A
22 _SI-IR _RTE-IR.X ! 77 _SI-C !
_SX-PACK-PREPARE RTE-S-UNAVAILABLE = _SS-A
_RSHSP-PENDING-PART 0= _SS-A _SX-ADMISSIONS @ 0= _SS-A
78 _SI-C !
3 _SI-IR _RTE-IR.FLAGS ! 23 _SI-IR _RTE-IR.CLIP-X ! 3 _SI-IR _RTE-IR.CLIP-Y !
6 _SI-IR _RTE-IR.CLIP-COLS ! 4 _SI-IR _RTE-IR.CLIP-ROWS !
_SI-IR _SI-IR-BACK 96 MOVE
_SX-PACK-PREPARE _SS-OK _SI-FROZEN
_SI-FROZEN-IR @ 96 _SI-IR-BACK 96 COMPARE 0= _SS-A
_SI-IR 96 _SI-IR-BACK 96 COMPARE 0= _SS-A
_SI-BATCH @ _SX-FX RTE-FAMILY-BATCH-EMIT _SS-OK
_SX-TARGET _RSHSP-PART-VALID? _SS-A
_SS-DONE
''', minimum=45)
