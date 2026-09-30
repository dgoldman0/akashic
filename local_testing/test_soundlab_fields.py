"""Execute Sound Lab's real parameter model, paint and event closure.

Audio/summary/status notifications are out of this focused closure. The
widgets, region layout, per-instance state, parameter handlers, prompts and
builder words are production Forth, with no terminal-facing substitute.
"""

import re

from test_field_model import ROOT, field_runtime
from test_rich_terminal_control_map import _definitions


def _soundlab_runtime(extra_sources=(), extra_targets=(), external=b"",
                      runtime_factory=field_runtime):
    runtime = runtime_factory(("utils/string.f", "tui/widgets/field.f", "tui/widgets/prompt.f",
                             "tui/data-graphics-model.f", "runtime/state-layout.f",
                             *extra_sources))
    source = (ROOT / "akashic/tui/applets/soundlab/soundlab.f").read_text()
    osc = (ROOT / "akashic/audio/osc.f").read_text()
    replace = (ROOT / "akashic/utils/fs/vfs-replace.f").read_text()
    constants = re.findall(r"(?m)^\d+ CONSTANT OSC-(?:SINE|SQUARE|SAW|TRI|PULSE)\s*$", osc)
    constants += re.findall(r"(?m)^\d+ CONSTANT VREPL-SIZE\s*$", replace)
    runtime.evaluate("\n".join(constants).encode(), source_name="production-layout-constants")
    start = source.index("8000 CONSTANT _SL-RATE")
    end = source.index("CMP-LAYOUT-SIZE CONSTANT _SL-STATE-SIZE")
    end += len("CMP-LAYOUT-SIZE CONSTANT _SL-STATE-SIZE")
    runtime.evaluate(source[start:end].encode(), source_name="production-soundlab-state")
    runtime.evaluate(b'''
: _SL-BUILD-SUMMARY ; : _SL-UPDATE-STATUS ; : ASHELL-DIRTY! ;
[UNDEFINED] UIDL-DIRTY! [IF] : UIDL-DIRTY! DROP ; [THEN]
: UTUI-FOCUS! DROP ;
: ASHELL-TOAST DROP 2DROP ;
: _SL-RENDER-ACTION ; : _SL-SAVE-ACTION ; : _SL-PLAYBACK-ACTION ;
DEFER _SL-DGRAPH-REBUILD-D
: _ST-DGRAPH-NOTIFY ;
' _ST-DGRAPH-NOTIFY IS _SL-DGRAPH-REBUILD-D
DEFER _SL-FIELDS-DRAW-D DEFER _SL-FIELD-ACTIVATE-D DEFER _SL-FIELD-ADJUST-D
''', source_name="external-notification-boundaries")
    if external:
        runtime.evaluate(external, source_name="external-test-boundaries")
    definitions = _definitions(source)
    seen = set()
    chunks = []

    def include(name):
        if name in seen or runtime.dictionary.find(name.encode()) is not None:
            return
        seen.add(name)
        declaration = definitions[name]
        code = re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration)
        for token in code.split():
            if token != name and token in definitions:
                include(token)
        chunks.append(declaration)

    for name in ("_SL-FIELDS-NEW", "_SL-FIELDS-FREE", "_SL-FIELDS-DRAW",
                 "_SL-NO-FIELDS", "_SL-DRAW-SETTINGS", "_SL-LAYOUT",
                 "_SL-FIELD-ACTIVATED", "_SL-FIELD-ADJUSTED", "_SL-PANEL-HANDLE",
                 "_SL-PROMPT-SUBMIT", "_SL-PROMPT-CANCEL", *extra_targets):
        include(name)
    runtime.evaluate("\n".join(chunks).encode(), source_name="production-soundlab-parameters",
                     step_budget=20_000_000)
    runtime.evaluate(b'''
' _SL-FIELDS-DRAW IS _SL-FIELDS-DRAW-D
' _SL-FIELD-ACTIVATED IS _SL-FIELD-ACTIVATE-D
' _SL-FIELD-ADJUSTED IS _SL-FIELD-ADJUST-D
''')
    runtime.drain_uart_output()
    return runtime


def test_soundlab_fields_preserve_geometry_prompts_and_bounded_adjustments():
    runtime = _soundlab_runtime()
    program = r'''
VARIABLE _ST-N VARIABLE _ST-FAIL VARIABLE _ST-D VARIABLE _ST-REV
CREATE _ST-EVENT 24 ALLOT CREATE _ST-LEGACY 1680 ALLOT
: _ST-A 1 _ST-N +! 0= IF 1 _ST-FAIL +! ." SOUND FIELD ASSERT " _ST-N @ . CR THEN ;
: _ST-MOUSE ( code row col -- consumed? )
    SWAP 16 LSHIFT OR _ST-EVENT 16 + ! _ST-EVENT 8 + ! KEY-T-MOUSE _ST-EVENT !
    _ST-EVENT _SL-PANEL _SL-PANEL-HANDLE ;
: _ST-SPECIAL ( key -- consumed? )
    _ST-EVENT 8 + ! KEY-T-SPECIAL _ST-EVENT ! 0 _ST-EVENT 16 + !
    _ST-EVENT _SL-PANEL _SL-PANEL-HANDLE ;
: _ST-PROMPT-LABEL ( -- a u )
    _SL-PROMPT @ DUP _PRM-O-LABEL-A + @ SWAP _PRM-O-LABEL-U + @ ;
: _ST-SUBMIT ( a u -- )
    _SL-PROMPT @ _PRM-O-INPUT + @ INP-SET-TEXT
    KEY-T-SPECIAL _ST-EVENT ! KEY-ENTER _ST-EVENT 8 + ! 0 _ST-EVENT 16 + !
    _ST-EVENT _SL-PROMPT @ WDG-HANDLE _ST-A ;
: _ST-SAVE-ROWS
    3 0 DO 70 0 DO
        J 5 + I 3 + SCR-GET _ST-LEGACY J 70 * I + 8 * + !
    LOOP LOOP ;
: _ST-COMPARE-ROWS
    3 0 DO 70 0 DO
        J 5 + I 3 + SCR-GET _ST-LEGACY J 70 * I + 8 * + @ = _ST-A
    LOOP LOOP ;
0 _ST-N ! 0 _ST-FAIL ! DEPTH _ST-D !
_SL-STATE-SIZE ALLOCATE 0<> ABORT" test state allocation"
DUP _SL-CURRENT-STATE ! _SL-STATE-SIZE 0 FILL
90 30 SCR-NEW SCR-USE
1 3 20 70 RGN-NEW _SL-PANEL-RGN !
_SL-PANEL-RGN @ _SL-PANEL 8 + ! 5 _SL-PANEL 32 + !
25 3 1 70 RGN-NEW _SL-PROMPT-RGN !
_SL-PROMPT-RGN @ _SL-PROMPT-BUF _SL-PROMPT-CAP PRM-NEW _SL-PROMPT !
' _SL-PROMPT-SUBMIT _SL-PROMPT @ PRM-ON-SUBMIT
' _SL-PROMPT-CANCEL _SL-PROMPT @ PRM-ON-CANCEL
OSC-SINE _SL-SHAPE ! 440 _SL-FREQUENCY ! 75 _SL-AMPLITUDE ! 500 _SL-DURATION !
1 _SL-SELECTED ! 1 _SL-FIELD-REVISION ! -1 _SL-FIELD-DIRTY !
_SL-FIELDS-NEW _SL-LAYOUT
' _SL-NO-FIELDS IS _SL-FIELDS-DRAW-D
SCR-CLEAR _SL-PANEL-RGN @ RGN-USE _SL-DRAW-SETTINGS _ST-SAVE-ROWS
' _SL-FIELDS-DRAW IS _SL-FIELDS-DRAW-D
SCR-CLEAR _SL-PANEL-RGN @ RGN-USE _SL-DRAW-SETTINGS _ST-COMPARE-ROWS
_SL-FIELD-READY @ _ST-A
0 _SL-FIELD-WIDGET FLD-MODEL@ DROP
DUP UFLD-KIND@ UFLD-K-CHOICE = _ST-A
DUP UFLD-CHOICE-COUNT@ 5 = _ST-A
DUP UFLD-VALUE-COLUMN@ 54 = _ST-A
DUP UFLD-VALUE-WIDTH@ 14 = _ST-A
DUP UFLD-LABEL-COLUMN@ 2 = _ST-A
UFLD-LABEL-WIDTH@ 52 = _ST-A
4 57 SCR-GET CELL-CP@ 115 = _ST-A
1 _SL-FIELD-WIDGET FLD-MODEL@ DROP
DUP UFLD-MINIMUM@ 40 = _ST-A DUP UFLD-MAXIMUM@ 2000 = _ST-A
DUP UFLD-STEP@ 10 = _ST-A UFLD-STATE@ 7 = _ST-A
KEY-MOUSE-LEFT 5 5 _ST-MOUSE 0= _ST-A
_SL-PROMPT @ PRM-ACTIVE? 0= _ST-A
KEY-MOUSE-LEFT 5 57 _ST-MOUSE _ST-A
_ST-PROMPT-LABEL S" Frequency (40-2000 Hz):" STR-STR= _ST-A
_SL-PROMPT @ PRM-GET-TEXT S" 440" STR-STR= _ST-A
S" 2001" _ST-SUBMIT _SL-FREQUENCY @ 440 = _ST-A
KEY-F2 _ST-SPECIAL _ST-A S" 850" _ST-SUBMIT _SL-FREQUENCY @ 850 = _ST-A
KEY-MOUSE-LEFT 6 57 _ST-MOUSE _ST-A
_ST-PROMPT-LABEL S" Amplitude (0-100 percent):" STR-STR= _ST-A
_SL-PROMPT @ PRM-GET-TEXT S" 75" STR-STR= _ST-A
_SL-PROMPT @ PRM-HIDE
KEY-MOUSE-LEFT 7 57 _ST-MOUSE _ST-A
_ST-PROMPT-LABEL S" Duration (100-2000 ms):" STR-STR= _ST-A
_SL-PROMPT @ PRM-GET-TEXT S" 500" STR-STR= _ST-A
_SL-PROMPT @ PRM-HIDE
_SL-FIELD-REVISION @ _ST-REV !
_SL-FIELD-REVISION @ KEY-MOUSE-FIELD-REVISION !
0x7FFFFFFFFFFFFFFF KEY-MOUSE-FIELD-ADJUSTMENT !
KEY-MOUSE-FIELD-ADJUST 5 57 _ST-MOUSE _ST-A
_SL-FREQUENCY @ 2000 = _ST-A _SL-SELECTED @ 1 = _ST-A
_SL-FIELD-REVISION @ _ST-REV @ 1+ = _ST-A
\ The next dispatch refreshes the dirty binding before checking revision.
\ An old intent must not act on the newly authoritative value, even when
\ no repaint has happened between the two events.
0x8000000000000000 KEY-MOUSE-FIELD-ADJUSTMENT !
KEY-MOUSE-FIELD-ADJUST 5 57 _ST-MOUSE 0= _ST-A
_SL-FREQUENCY @ 2000 = _ST-A
_SL-FIELD-REVISION @ _ST-REV @ 1+ = _ST-A
_SL-FIELD-REVISION @ KEY-MOUSE-FIELD-REVISION !
0x8000000000000000 KEY-MOUSE-FIELD-ADJUSTMENT !
KEY-MOUSE-FIELD-ADJUST 5 57 _ST-MOUSE _ST-A _SL-FREQUENCY @ 40 = _ST-A
_SL-FIELD-REVISION @ KEY-MOUSE-FIELD-REVISION !
0x7FFFFFFFFFFFFFFF KEY-MOUSE-FIELD-ADJUSTMENT !
KEY-MOUSE-FIELD-ADJUST 6 57 _ST-MOUSE _ST-A _SL-AMPLITUDE @ 100 = _ST-A
_SL-FIELD-REVISION @ KEY-MOUSE-FIELD-REVISION !
0x8000000000000000 KEY-MOUSE-FIELD-ADJUSTMENT !
KEY-MOUSE-FIELD-ADJUST 6 57 _ST-MOUSE _ST-A _SL-AMPLITUDE @ 0= _ST-A
_SL-FIELD-REVISION @ KEY-MOUSE-FIELD-REVISION !
0x7FFFFFFFFFFFFFFF KEY-MOUSE-FIELD-ADJUSTMENT !
KEY-MOUSE-FIELD-ADJUST 7 57 _ST-MOUSE _ST-A _SL-DURATION @ 2000 = _ST-A
_SL-FIELD-REVISION @ KEY-MOUSE-FIELD-REVISION !
0x8000000000000000 KEY-MOUSE-FIELD-ADJUSTMENT !
KEY-MOUSE-FIELD-ADJUST 7 57 _ST-MOUSE _ST-A _SL-DURATION @ 100 = _ST-A
_SL-FIELD-REVISION @ KEY-MOUSE-FIELD-REVISION !
KEY-MOUSE-FIELD-ADJUST 4 57 _ST-MOUSE _ST-A _SL-SHAPE @ OSC-SAW = _ST-A
_SL-FIELD-REVISION @ _ST-REV !
KEY-DOWN _ST-SPECIAL _ST-A
_SL-FIELD-REVISION @ _ST-REV @ = _ST-A
_SL-PANEL-RGN @ RGN-USE _SL-DRAW-SETTINGS
1 _SL-FIELD-WIDGET FLD-MODEL@ DROP UFLD-STATE@ 7 = _ST-A
10 _SL-PANEL-RGN @ _RGN-O-W + ! _SL-LAYOUT
_SL-PANEL-RGN @ RGN-USE _SL-DRAW-SETTINGS
_SL-FIELD-READY @ 0= _ST-A
0 _SL-FIELD-WIDGET FLD-FIELD-MEASURE FLD-S-INVALID = _ST-A 0= _ST-A
70 _SL-PANEL-RGN @ _RGN-O-W + ! _SL-LAYOUT
_SL-PANEL-RGN @ RGN-USE _SL-DRAW-SETTINGS _SL-FIELD-READY @ _ST-A
_SL-FIELDS-FREE
_SL-PROMPT @ PRM-FREE _SL-PROMPT-RGN @ RGN-FREE
_SL-PANEL-RGN @ RGN-FREE _SL-CURRENT-STATE @ FREE
DEPTH _ST-D @ = _ST-A
_ST-FAIL @ 0= IF ." SOUND FIELD PASS " ELSE ." SOUND FIELD FAIL " THEN
_ST-N @ . _ST-FAIL @ . CR
'''
    try:
        runtime.evaluate(program.encode(), source_name="soundlab-field-checks",
                         step_budget=20_000_000)
    except Exception as error:
        deferred = {}
        for name in (b"_SL-DGRAPH-REBUILD-D", b"_SL-FIELDS-DRAW-D",
                     b"_SL-FIELD-ACTIVATE-D", b"_SL-FIELD-ADJUST-D"):
            word = runtime.dictionary.find(name)
            deferred[name] = runtime.memory.read64(word.body_address)
        raise AssertionError((runtime.uart_output.decode(errors="replace")[-16000:],
                              runtime.main_context.data.snapshot(),
                              runtime.main_context.returns.snapshot(), deferred)) from error
    output = runtime.drain_uart_output().decode(errors="replace")
    result = re.search(r"SOUND FIELD PASS\s+(\d+)\s+0", output)
    assert result, (output, runtime.main_context.data.snapshot())
    assert int(result.group(1)) >= 260
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
