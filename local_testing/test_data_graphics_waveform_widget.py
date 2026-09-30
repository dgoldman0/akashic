"""CELL and capture consume the same owned canonical waveform history."""

from test_data_graphics_series import PRELUDE, run_series


def test_waveform_cell_uses_timestamps_values_zero_line_and_owned_capture():
    program = PRELUDE + r'''
VARIABLE _GW-W VARIABLE _GW-R VARIABLE _GW-S
: _GW-BIND _GS-M _GS-U @ _GS-S _GW-W @ DGRAPH-BIND _GS-OK ;
: _GW-RESET _GW-W @ DGRAPH-FREE _GW-R @ DGRAPH-NEW _GW-W ! ;
: _GW-DRAW SCR-CLEAR RGN-ROOT 7 0 0 DRW-STYLE! _GW-W @ WDG-DRAW ;
: _GW-CP ( expected row col -- ) SCR-GET CELL-CP@ = _GS-A ;
: _GW-EXPLICIT
    _GS-BEGIN 2 3 0 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END ;
25 9 SCR-NEW DUP _GW-S ! SCR-USE
1 2 5 17 RGN-NEW DUP _GW-R ! DGRAPH-NEW _GW-W !
_GS-UNIFORM _GW-BIND _GW-DRAW
8226 5 2 _GW-CP 8226 3 10 _GW-CP 8226 1 18 _GW-CP
9472 3 3 _GW-CP 32 0 2 _GW-CP 32 1 1 _GW-CP 32 1 19 _GW-CP
DRW-ATTR@ 0= _GS-A
\ Zero renderer scratch for waveform-only graphs; SERIES is never an object.
_GW-W @ _DGRAPH-O-SCRATCH-U + @ 0= _GS-A
_GS-B _GW-W @ DGRAPH-DATA-GRAPHICS-MEASURE _GS-OK _GS-U @ = _GS-A
_GS-O 130176 _GS-B _GW-W @ DGRAPH-DATA-GRAPHICS-CAPTURE _GS-OK _GS-U @ = _GS-A
_GS-O _GS-U @ _GS-S UDG-ENTRY-VALIDATE _GS-OK
_GS-M _GS-U @ _GS-O _GS-U @ COMPARE 0= _GS-A
\ A deep immutable copy outlives the source sample buffer.
_GS-D 24 0 FILL _GW-DRAW 8226 5 2 _GW-CP 8226 1 18 _GW-CP
_GS-M 130176 _GS-B _GW-W @ DGRAPH-DATA-GRAPHICS-CAPTURE
DGRAPH-S-INVALID = _GS-A 0= _GS-A
_GS-O _GS-U @ 1- _GS-B _GW-W @ DGRAPH-DATA-GRAPHICS-CAPTURE
DGRAPH-S-CAPACITY = _GS-A 0= _GS-A
\ Explicit irregular time positions must not become uniformly spaced indices.
0 _GS-D ! -32768 _GS-D 8 + !
10 _GS-D 16 + ! 0 _GS-D 24 + !
100 _GS-D 32 + ! 32767 _GS-D 40 + !
_GW-RESET _GW-EXPLICIT _GW-BIND _GW-DRAW
8226 3 3 _GW-CP 9472 3 10 _GW-CP
\ Unsigned timestamps cross bit63 and can end at UINT64_MAX.
_GW-RESET
0x8000000000000000 _GS-D 16 + ! -1 _GS-D 32 + !
_GW-EXPLICIT _GW-BIND _GW-DRAW 8226 3 10 _GW-CP 8226 1 18 _GW-CP
0x8000000000000000 -1 16 _DGRAPH-TIME-SCALE 8 = _GS-A
-2 -1 16 _DGRAPH-TIME-SCALE 15 = _GS-A
\ Single sample is centered; full signed values clip to the declared range.
_GW-RESET 0x7FFFFFFFFFFFFFFF _GS-D !
_GS-BEGIN 2 1 1 125 0 _GS-D 1 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END
_GW-BIND _GW-DRAW 8226 1 10 _GW-CP 9472 3 10 _GW-CP
_GW-RESET 0x8000000000000000 _GS-D !
_GS-BEGIN 2 1 1 125 0 _GS-D 1 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END
_GW-BIND _GW-DRAW 8226 5 10 _GW-CP
\ Empty SERIES draws only the optional zero line.
_GW-RESET
_GS-BEGIN 2 16000 1 125 0 0 0 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END
_GW-BIND _GW-DRAW 9472 3 2 _GW-CP 9472 3 18 _GW-CP 32 1 10 _GW-CP
_GW-W @ WDG-HIDE _GW-DRAW 32 3 2 _GW-CP _GW-W @ WDG-SHOW
_GW-W @ WDG-DISABLE _GW-DRAW CELL-A-DIM 3 2 SCR-GET CELL-HAS-ATTR? _GS-A
_GW-W @ WDG-ENABLE
\ Object-local edges remain clipped by the actual widget region.
_GW-RESET 32767 _GS-D !
_GS-BEGIN 2 1 1 125 0 _GS-D 1 _GS-B UDG-SERIES _GS-OK
3 -1 -3 5 17 0 1 2 -32768 32767 0x00FFFFFF 0x777777FF 0 1 _GS-B UDG-WAVEFORM _GS-OK
_GS-END _GW-BIND _GW-DRAW
32 0 7 _GW-CP 9472 2 2 _GW-CP 9472 2 15 _GW-CP 32 2 16 _GW-CP
_GW-W @ DGRAPH-FREE _GW-R @ RGN-FREE RGN-ROOT _GW-S @ SCR-FREE
_GS-DONE
'''
    run_series(program, minimum=95, extra_sources=("tui/widgets/data-graphics.f",))


def test_existing_instrument_model_and_widget_oracles_still_pass_in_native_source():
    from test_semantic_data_graphics import ORACLE_CASES
    from test_data_graphics_widget import ORACLE_SOURCE

    # Native source execution has no BIOS .S diagnostic. All assertions and
    # production words are unchanged; only its failure-only stack dump is omitted.
    program = ORACLE_CASES.replace(".S CR", "CR") + r'''
_udg-fails @ 0= IF ." SERIES REGRESSION PASS " _udg-checks @ . 0 . CR THEN
'''
    run_series(program, minimum=100, marker="SERIES REGRESSION")
    program = "\n".join(line for line in ORACLE_SOURCE.splitlines()
                        if not line.startswith(("PROVIDED ", "REQUIRE ")))
    program += r'''
_dg-fails @ 0= IF ." SERIES REGRESSION PASS " _dg-checks @ . 0 . CR THEN
'''
    run_series(program, minimum=100, marker="SERIES REGRESSION",
               extra_sources=("tui/widgets/data-graphics.f",))
