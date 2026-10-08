"""Native canonical SERIES/WAVEFORM ownership, timestamp and extent proofs."""

import re

from test_field_model import ROOT
from forth_dependencies import dependency_order
from test_textarea import MEGAPAD_ROOT
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime


def series_runtime(extra_sources=()):
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=128 << 20, hbw_size=1 << 20),
        execution_backend="native",
    )
    runtime.evaluate((MEGAPAD_ROOT / "kdos.f").read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="series-init")
    for module in dependency_order(ROOT / "akashic", ("tui/data-graphics-model.f", *extra_sources)):
        source = (ROOT / "akashic" / module).read_text()
        source = "\n".join(line for line in source.splitlines()
                           if not line.strip().startswith(("REQUIRE ", "PROVIDED ")))
        runtime.evaluate(source.encode(), source_name=module, step_budget=20_000_000)
    runtime.drain_uart_output()
    return runtime


def run_series(program, minimum=1, extra_sources=(), marker="SERIES MODEL"):
    runtime = series_runtime(extra_sources)
    try:
        runtime.evaluate(program.encode(), source_name="series-proof", step_budget=40_000_000)
    except Exception as error:
        raise AssertionError(runtime.uart_output.decode(errors="replace")[-16000:]) from error
    output = runtime.drain_uart_output().decode(errors="replace")
    summary = re.search(rf"{marker} PASS\s+(\d+)\s+0", output)
    assert summary, (output, runtime.main_context.data.snapshot())
    assert int(summary.group(1)) >= minimum
    assert runtime.main_context.data.snapshot() == ()
    assert runtime.main_context.returns.snapshot() == ()
    return runtime


PRELUDE = r'''
VARIABLE _GS-N VARIABLE _GS-FAIL VARIABLE _GS-U VARIABLE _GS-R VARIABLE _GS-W
CREATE _GS-MS 130183 ALLOT CREATE _GS-OS 130183 ALLOT
CREATE _GS-BS 87 ALLOT CREATE _GS-SS 55 ALLOT CREATE _GS-DS 128007 ALLOT
: _GS-M _GS-MS 7 + -8 AND ; : _GS-O _GS-OS 7 + -8 AND ;
: _GS-B _GS-BS 7 + -8 AND ; : _GS-S _GS-SS 7 + -8 AND ;
: _GS-D _GS-DS 7 + -8 AND ;
: _GS-A 1 _GS-N +! 0= IF 1 _GS-FAIL +! ." SERIES ASSERT " _GS-N @ . CR THEN ;
: _GS-OK 0= _GS-A ;
: _GS-BEGIN _GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
    1 0 0 5 17 3 _GS-B UDG-BEGIN _GS-OK ;
: _GS-WAVE 3 0 0 5 17 0 1 2 -32768 32767
    0x00FFFFFF 0x777777FF 0 1 _GS-B UDG-WAVEFORM _GS-OK ;
: _GS-END _GS-B UDG-END _GS-OK
    _GS-B UDG-BUILDER-FINISH _GS-OK _GS-U !
    _GS-M _GS-U @ _GS-S UDG-ENTRY-VALIDATE _GS-OK
    _GS-M UDG-FIRST-RECORD DUP _GS-R ! UDG-RECORD-NEXT _GS-W ! ;
: _GS-UNIFORM _GS-BEGIN 2 16 1 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
    _GS-WAVE _GS-END ;
: _GS-INVALID _GS-M _GS-U @ _GS-S UDG-ENTRY-VALIDATE UDG-S-INVALID = _GS-A ;
: _GS-MUTATE ( value offset -- )
    _GS-R @ + DUP @ >R DUP >R ! _GS-INVALID R> R> SWAP ! ;
: _GS-WMUTATE ( value offset -- )
    _GS-W @ + DUP @ >R DUP >R ! _GS-INVALID R> R> SWAP ! ;
: _GS-DONE _GS-FAIL @ 0= IF ." SERIES MODEL PASS " ELSE ." SERIES MODEL FAIL " THEN
    _GS-N @ . _GS-FAIL @ . CR ;
-32768 _GS-D ! 0 _GS-D 8 + ! 32767 _GS-D 16 + !
'''


def test_series_native_modes_owned_samples_reference_and_deep_validation():
    program = PRELUDE + r'''
_GS-UNIFORM
_GS-U @ 352 = _GS-A
_GS-M UDG-RECORD-COUNT@ 2 = _GS-A _GS-M UDG-OBJECT-COUNT@ 1 = _GS-A
_GS-M UDG-SERIES-COUNT@ 1 = _GS-A _GS-M UDG-SAMPLE-SLOTS@ 16 = _GS-A
_GS-S UDG-SUMMARY-SERIES-COUNT@ 1 = _GS-A
_GS-S UDG-SUMMARY-SAMPLE-SLOTS@ 16 = _GS-A
_GS-R @ UDG-SERIES-CAPACITY@ 16 = _GS-A
_GS-R @ UDG-SERIES-SAMPLE-COUNT@ 3 = _GS-A
_GS-M 2 UDG-SERIES-FIND _GS-R @ = _GS-A
_GS-M 3 UDG-SERIES-FIND 0= _GS-A _GS-M 99 UDG-SERIES-FIND 0= _GS-A
0 _GS-R @ UDG-SERIES-SAMPLE@ -32768 = _GS-A 0= _GS-A
2 _GS-R @ UDG-SERIES-SAMPLE@ 32767 = _GS-A 250 = _GS-A
42 _GS-D ! 0 _GS-R @ UDG-SERIES-SAMPLE@ -32768 = _GS-A DROP
_GS-W @ UDG-WAVEFORM-SERIES-KEY@ 2 = _GS-A
0 24 _GS-MUTATE 2 24 _GS-MUTATE 0x100000000 24 _GS-MUTATE
2 32 _GS-MUTATE 0 40 _GS-MUTATE -1 40 _GS-MUTATE
17 48 _GS-MUTATE -1 56 _GS-MUTATE 1 64 _GS-MUTATE
184 0 _GS-MUTATE 1 16 _GS-MUTATE
1 80 _GS-WMUTATE 3 80 _GS-WMUTATE 99 80 _GS-WMUTATE
32767 88 _GS-WMUTATE -32768 96 _GS-WMUTATE
0x100000000 104 _GS-WMUTATE 0x100000000 112 _GS-WMUTATE
32768 120 _GS-WMUTATE 2 128 _GS-WMUTATE 1 136 _GS-WMUTATE
2 16 _GS-WMUTATE
2 _GS-M UDG-SERIES-COUNT-OFFSET + ! _GS-INVALID
1 _GS-M UDG-SERIES-COUNT-OFFSET + !
3 _GS-M UDG-SAMPLE-SLOTS-OFFSET + ! _GS-INVALID
16 _GS-M UDG-SAMPLE-SLOTS-OFFSET + !
_GS-M _GS-U @ 8 + _GS-S UDG-ENTRY-VALIDATE UDG-S-INVALID = _GS-A
99 _GS-R @ UDG-RECORD-KIND-OFFSET + !
_GS-M _GS-U @ _GS-S UDG-ENTRY-VALIDATE UDG-S-UNSUPPORTED = _GS-A
\ Full u64 timestamp range and full signed i64 values remain exact.
0 _GS-D ! 0x8000000000000000 _GS-D 8 + !
0x8000000000000000 _GS-D 16 + ! 0x7FFFFFFFFFFFFFFF _GS-D 24 + !
-1 _GS-D 32 + ! -1 _GS-D 40 + !
_GS-BEGIN 2 3 0 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END
_GS-U @ 376 = _GS-A
1 _GS-R @ UDG-SERIES-SAMPLE@ 0x7FFFFFFFFFFFFFFF = _GS-A 0x8000000000000000 = _GS-A
2 _GS-R @ UDG-SERIES-SAMPLE@ -1 = _GS-A -1 = _GS-A
1 40 _GS-MUTATE 1 56 _GS-MUTATE
0 88 _GS-MUTATE 0x7FFFFFFFFFFFFFFF 104 _GS-MUTATE
\ Empty definitions have no body; waveform remains valid and owns no samples.
_GS-BEGIN 2 16000 1 125 0 0 0 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END
_GS-U @ 328 = _GS-A _GS-M UDG-SAMPLE-SLOTS@ 16000 = _GS-A
1 56 _GS-MUTATE
\ Exact last timestamp UINT64_MAX is legal; one extra interval is not.
_GS-BEGIN 2 2 1 -1 0 _GS-D 2 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END
1 _GS-R @ UDG-SERIES-SAMPLE@ DROP -1 = _GS-A
_GS-DONE
'''
    run_series(program, minimum=85)


def test_series_builder_refusals_capacity_copy_bounds_and_pcm_conversion():
    program = PRELUDE + r'''
: _GS-SAVE _GS-M _GS-O 130176 MOVE ;
: _GS-SAME _GS-M 130176 _GS-O 130176 COMPARE 0= _GS-A ;
: _GS-REFUSE UDG-S-INVALID = _GS-A _GS-SAME ;
_GS-BEGIN _GS-SAVE 2 3 1 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 -1 1 _GS-D 2 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 -1 0 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 0 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 0 0 1 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 2 1 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 125 0 _GS-D 1+ 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 125 0 _GS-M 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 125 0 _GS-B 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 125 0 _UDG-SR-A 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 125 0 0 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 125 0 -8 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 1 125 0 _GS-D 0 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN _GS-SAVE 2 3 2 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
\ A forged builder prefix cannot escape its bounded destination.
_GS-BEGIN 2 3 1 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
130177 _GS-B _UDG-B.USED + ! _GS-SAVE
3 3 1 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN 2 3 1 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
104 _GS-M UDG-FIRST-RECORD ! _GS-SAVE
3 3 1 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-REFUSE
_GS-M 207 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 5 17 3 _GS-B UDG-BEGIN _GS-OK _GS-SAVE
2 3 1 125 0 _GS-D 3 _GS-B UDG-SERIES UDG-S-CAPACITY = _GS-A _GS-SAME
\ Missing, object, forward and duplicate keys cannot form a reference.
_GS-BEGIN _GS-SAVE
3 0 0 5 17 0 1 2 -1 1 0 0 0 0 _GS-B UDG-WAVEFORM _GS-REFUSE
_GS-BEGIN 2 1 1 125 0 _GS-D 1 _GS-B UDG-SERIES _GS-OK _GS-SAVE
2 1 1 125 0 _GS-D 1 _GS-B UDG-SERIES _GS-REFUSE
_GS-BEGIN 2 0 0 1 1 0 1 0 0 1 0 _GS-B UDG-STATUS _GS-OK _GS-SAVE
3 0 0 5 17 0 1 2 -1 1 0 0 0 0 _GS-B UDG-WAVEFORM _GS-REFUSE
\ Declared capacities, including empty histories, must fit aggregate u32.
_GS-BEGIN 2 0xFFFFFFFF 1 125 0 0 0 _GS-B UDG-SERIES _GS-OK _GS-SAVE
3 1 1 125 0 0 0 _GS-B UDG-SERIES _GS-REFUSE
\ Native values use the existing audio conversion policy, not raw FP16 bits.
0x3C00 PCM-FP16>S16 32767 = _GS-A 0xBC00 PCM-FP16>S16 -32768 = _GS-A
0x3800 PCM-FP16>S16 16384 = _GS-A 0xB800 PCM-FP16>S16 -16384 = _GS-A
0x7C00 PCM-FP16>S16 32767 = _GS-A 0xFC00 PCM-FP16>S16 -32768 = _GS-A
0x7E00 PCM-FP16>S16 0= _GS-A
\ Measurement preserves the builder ABI and returns the same exact extent.
0 0 _GS-B UDG-BUILDER-INIT _GS-OK 1 0 0 5 17 3 _GS-B UDG-BEGIN _GS-OK
2 16 1 125 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK _GS-WAVE
_GS-B UDG-END _GS-OK _GS-B UDG-BUILDER-FINISH _GS-OK 352 = _GS-A
\ Full Sound Lab history is bounded by the caller's 16000-frame capacity.
: _GS-FILL 16000 0 DO I 8000 - _GS-D I 8 * + ! LOOP ; _GS-FILL
_GS-BEGIN 2 16000 1 125 0 _GS-D 16000 _GS-B UDG-SERIES _GS-OK _GS-WAVE _GS-END
_GS-U @ 128328 = _GS-A _GS-M UDG-SAMPLE-SLOTS@ 16000 = _GS-A
15999 _GS-R @ UDG-SERIES-SAMPLE@ 7999 = _GS-A 1999875 = _GS-A
_GS-D 128000 0 FILL
15999 _GS-R @ UDG-SERIES-SAMPLE@ 7999 = _GS-A DROP
\ Validator cannot use model or summary spans in its own mutable storage.
_GS-SAVE _GS-M _GS-U @ _UDG-V-G UDG-ENTRY-VALIDATE UDG-S-INVALID = _GS-A _GS-SAME
_UDG-V-G 112 _GS-S UDG-ENTRY-VALIDATE UDG-S-INVALID = _GS-A
_GS-DONE
'''
    run_series(program, minimum=90, extra_sources=("audio/pcm-fp16.f",))
