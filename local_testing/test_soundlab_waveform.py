"""Execute Sound Lab's complete PCM-to-ordinary-waveform production closure."""

import re

from test_data_graphics_series import series_runtime
from test_soundlab_fields import _soundlab_runtime


def test_soundlab_full_pcm_series_geometry_copy_and_cell_projection():
    runtime = _soundlab_runtime(
        extra_sources=("tui/widgets/data-graphics.f", "audio/pcm.f", "audio/pcm-fp16.f"),
        extra_targets=("_SL-DGRAPH-REBUILD", "_SL-DRAW-WAVEFORM"),
        external=b": _SL-OWNED-ACTIVE? 0 ; : AUDIO-OUT-PRESENT? 0 ;",
        runtime_factory=series_runtime,
    )
    program = r'''
VARIABLE _SW-N VARIABLE _SW-FAIL VARIABLE _SW-D VARIABLE _SW-G
VARIABLE _SW-S VARIABLE _SW-W VARIABLE _SW-OLD VARIABLE _SW-U
CREATE _SW-SS 55 ALLOT
: _SW-SUMMARY _SW-SS 7 + -8 AND ;
: _SW-A 1 _SW-N +! 0= IF 1 _SW-FAIL +! ." SOUND WAVE ASSERT " _SW-N @ . CR THEN ;
: _SW-OK 0= _SW-A ;
: _SW-SAMPLE ( index -- fp16 )
    5 MOD CASE 0 OF 0xBC00 ENDOF 1 OF 0x3800 ENDOF 2 OF 0 ENDOF
        3 OF 0xB800 ENDOF 4 OF 0x3C00 ENDOF ENDCASE ;
: _SW-VALUE ( index -- signed )
    5 MOD CASE 0 OF -32768 ENDOF 1 OF 16384 ENDOF 2 OF 0 ENDOF
        3 OF -16384 ENDOF 4 OF 32767 ENDOF ENDCASE ;
: _SW-ALL-SAMPLES
    16000 0 DO
        I _SW-S @ UDG-SERIES-SAMPLE@ I _SW-VALUE = _SW-A
        I 125 * = _SW-A
    LOOP ;
: _SW-CELL-COUNT ( -- count )
    0 12 0 DO 86 0 DO
        J 12 + I 4 + SCR-GET CELL-CP@ 8226 = IF 1+ THEN
    LOOP LOOP ;
0 _SW-N ! 0 _SW-FAIL ! DEPTH _SW-D !
_SL-DGRAPH-CAP 130176 = _SW-A
_SL-DGRAPH-SAMPLE-BYTES 128000 = _SW-A
_SL-DGRAPH-CAP 2* _SL-DGRAPH-SAMPLE-BYTES + 388352 = _SW-A
_SL-STATE-SIZE ALLOCATE 0<> ABORT" sound wave state allocation"
DUP _SL-CURRENT-STATE ! _SL-STATE-SIZE 0 FILL
96 36 SCR-NEW SCR-USE
1 2 30 90 RGN-NEW DUP _SL-PANEL-RGN ! DGRAPH-NEW _SL-DGRAPH-WIDGET !
16000 8000 16 1 PCM-ALLOC _SL-PCM !
: _SW-FILL-PCM 16000 0 DO I _SW-SAMPLE I 0 _SL-PCM @ PCM-SAMPLE! LOOP ;
_SW-FILL-PCM -1 _SL-RENDER-VALID !
_SL-DGRAPH-REBUILD _SW-OK
_SL-DGRAPH-ACTIVE-A @ DUP _SW-G ! _SL-DGRAPH-BANK-A = _SW-A
_SL-DGRAPH-ACTIVE-U @ DUP _SW-U ! 130176 = _SW-A
_SW-G @ _SW-U @ _SW-SUMMARY UDG-ENTRY-VALIDATE _SW-OK
_SW-G @ UDG-OBJECT-COUNT@ 14 = _SW-A
_SW-G @ UDG-SERIES-COUNT@ 1 = _SW-A
_SW-G @ UDG-RECORD-COUNT@ 15 = _SW-A
_SW-G @ UDG-SAMPLE-SLOTS@ 16000 = _SW-A
_SW-G @ 40 UDG-SERIES-FIND DUP _SW-S ! 0<> _SW-A
_SW-S @ UDG-SERIES-CAPACITY@ 16000 = _SW-A
_SW-S @ UDG-SERIES-MODE@ UDG-SERIES-UNIFORM = _SW-A
_SW-S @ UDG-SERIES-INTERVAL@ 125 = _SW-A
_SW-S @ UDG-SERIES-SAMPLE-COUNT@ 16000 = _SW-A
_SW-S @ UDG-SERIES-FIRST-TIMESTAMP@ 0= _SW-A
_SW-ALL-SAMPLES
_SW-S @ UDG-RECORD-NEXT DUP _SW-W ! UDG-RECORD-KEY@ 41 = _SW-A
_SW-W @ UDG-OBJECT-ROW@ 11 = _SW-A
_SW-W @ UDG-OBJECT-COLUMN@ 2 = _SW-A
_SW-W @ UDG-OBJECT-HEIGHT@ 12 = _SW-A
_SW-W @ UDG-OBJECT-WIDTH@ 86 = _SW-A
_SW-W @ UDG-WAVEFORM-SERIES-KEY@ 40 = _SW-A
_SW-W @ UDG-WAVEFORM-MINIMUM@ -32768 = _SW-A
_SW-W @ UDG-WAVEFORM-MAXIMUM@ 32767 = _SW-A
_SW-W @ UDG-WAVEFORM-ZERO-VALUE@ 0= _SW-A
_SL-DGRAPH-SAMPLES _SL-DGRAPH-SAMPLE-BYTES 0 FILL
_SL-PCM @ PCM-CLEAR
_SW-ALL-SAMPLES
SCR-CLEAR _SL-DGRAPH-WIDGET @ WDG-DRAW
_SW-CELL-COUNT 0> _SW-A
12 3 SCR-GET CELL-CP@ 32 = _SW-A
12 90 SCR-GET CELL-CP@ 32 = _SW-A
11 4 SCR-GET CELL-CP@ 32 = _SW-A
24 4 SCR-GET CELL-CP@ 32 = _SW-A
\ Source refusal preserves the prior active graph and its ordinary binding.
7999 _SL-PCM @ P.RATE !
_SL-DGRAPH-REBUILD DGRAPH-S-INVALID = _SW-A
_SL-DGRAPH-ACTIVE-A @ _SW-G @ = _SW-A
_SL-DGRAPH-ACTIVE-U @ _SW-U @ = _SW-A
_SL-DGRAPH-WIDGET @ _DGRAPH-BOUND? _SW-A
0 _SW-S @ UDG-SERIES-SAMPLE@ -32768 = _SW-A 0= _SW-A
8000 _SL-PCM @ P.RATE !
16001 _SL-PCM @ P.LEN !
_SL-DGRAPH-REBUILD DGRAPH-S-INVALID = _SW-A
_SL-DGRAPH-ACTIVE-A @ _SW-G @ = _SW-A
16000 _SL-PCM @ P.LEN !
\ A shorter panel contains metrics only, with no invented waveform slot.
17 _SL-PANEL-RGN @ _RGN-O-H + !
_SL-DGRAPH-REBUILD _SW-OK
_SL-DGRAPH-ACTIVE-A @ DUP _SW-OLD ! _SW-G @ <> _SW-A
_SL-DGRAPH-ACTIVE-U @ 1960 = _SW-A
_SW-OLD @ UDG-OBJECT-COUNT@ 13 = _SW-A
_SW-OLD @ UDG-SERIES-COUNT@ 0= _SW-A
_SW-OLD @ UDG-SAMPLE-SLOTS@ 0= _SW-A
0 _SW-S @ UDG-SERIES-SAMPLE@ -32768 = _SW-A DROP
\ Restore the original narrow geometry exactly and copy the current PCM.
18 _SL-PANEL-RGN @ _RGN-O-H + ! 20 _SL-PANEL-RGN @ _RGN-O-W + !
_SL-DGRAPH-REBUILD _SW-OK
_SL-DGRAPH-ACTIVE-A @ 40 UDG-SERIES-FIND DUP _SW-S !
UDG-RECORD-NEXT DUP _SW-W ! UDG-OBJECT-HEIGHT@ 3 = _SW-A
_SW-W @ UDG-OBJECT-WIDTH@ 16 = _SW-A
0 _SW-S @ UDG-SERIES-SAMPLE@ 0= _SW-A 0= _SW-A
\ Parameter invalidation removes stale samples while retaining metrics.
0 _SL-RENDER-VALID ! _SL-DGRAPH-REBUILD _SW-OK
_SL-DGRAPH-ACTIVE-U @ 1960 = _SW-A
_SL-DGRAPH-ACTIVE-A @ UDG-SERIES-COUNT@ 0= _SW-A
_SL-DGRAPH-WIDGET @ DGRAPH-FREE _SL-PANEL-RGN @ RGN-FREE
_SL-PCM @ PCM-FREE _SL-CURRENT-STATE @ FREE
DEPTH _SW-D @ = _SW-A
_SW-FAIL @ 0= IF ." SOUND WAVE PASS " ELSE ." SOUND WAVE FAIL " THEN
_SW-N @ . _SW-FAIL @ . CR
'''
    try:
        runtime.evaluate(program.encode(), source_name="soundlab-waveform-checks",
                         step_budget=80_000_000)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-16000:]) from error
    output = runtime.drain_uart_output().decode(errors="replace")
    result = re.search(r"SOUND WAVE PASS\s+(\d+)\s+0", output)
    assert result, (output, runtime.main_context.data.snapshot())
    assert int(result.group(1)) >= 64050
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
