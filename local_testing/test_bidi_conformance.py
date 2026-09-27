#!/usr/bin/env python3
"""Run Akashic's Forth bidi module against Unicode's conformance files.

APT-1-TEXT.md Section 7.2 requires every case in BidiTest.txt and
BidiCharacterTest.txt to pass.  The production sources (unicode-tables.f,
unicode-props.f, bidi.f) are evaluated unmodified on the native hosted
MegaForth runtime; the test cases are written into its memory as compact
records and a small Forth driver checks each one, so only a failure count
and the first failing record cross back.

By default the test runs every case.  Set BIDI_CONFORMANCE_SAMPLE=N to run
every Nth case of BidiTest.txt instead, for a quicker check while editing.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

import pytest

import generate_unicode_text_tables as generator

ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", ROOT.parent / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from simulator.runtime import MegaForthRuntime  # noqa: E402


BIDI_NAMES = (
    "L", "R", "AL", "EN", "ES", "ET", "AN", "CS", "NSM", "BN", "B", "S", "WS",
    "ON", "LRE", "LRO", "RLE", "RLO", "PDF", "LRI", "RLI", "FSI", "PDI",
)
DIRECTIONS = {"auto": 0, "ltr": 1, "rtl": 2}
REMOVED = 255
UNCHECKED = 255
CHUNK_BYTES = 1 << 17
MAX_CHARACTERS = 255

DRIVER = r"""
VARIABLE BT-P  VARIABLE BT-N  VARIABLE BT-FAILS  VARIABLE BT-FIRST
VARIABLE BT-CASE  VARIABLE BT-CLASSES  VARIABLE BT-SCALARS  VARIABLE BT-OK
VARIABLE BT-LEVELS  VARIABLE BT-M
CREATE BT-DATA 131072 ALLOT
CREATE BT-CLASS-BUF 256 ALLOT
CREATE BT-WORK 255 BIDI-WORK-BYTES 8 + ALLOT
CREATE BT-ORDER 1024 ALLOT
: BT-WORK-A  BT-WORK 7 + -8 AND ;
\ Record: n dir para has-scalars, classes[n], levels[n], m, order[m],
\ then scalars[4n] when has-scalars is set.
: BT-CLASSES-FROM-SCALARS  ( -- )
    BT-N @ 0 ?DO
        I 4 * BT-SCALARS @ + L@ UP-PROPS UP-BIDI BT-CLASS-BUF I + C!
    LOOP
    BT-CLASS-BUF BT-CLASSES ! ;
: BT-ONE  ( -- )
    -1 BT-OK !
    BT-P @ C@ BT-N !
    BT-P @ 4 + BT-CLASSES !
    BT-P @ 4 + BT-N @ 2* + DUP C@ BT-M !      ( m-addr )
    1+ BT-M @ +                                ( scalars-addr )
    BT-P @ 3 + C@ IF
        DUP BT-SCALARS ! BT-CLASSES-FROM-SCALARS BT-N @ 4 * +
    ELSE
        0 BT-SCALARS !
    THEN
    >R
    BT-CLASSES @ BT-SCALARS @ BT-N @ BT-P @ 1+ C@ BT-WORK-A BIDI-RESOLVE
    BT-P @ 2 + C@ DUP 255 <> IF <> IF 0 BT-OK ! THEN ELSE 2DROP THEN
    BT-WORK-A BIDI-LEVELS BT-LEVELS !
    BT-LEVELS @ BT-N @ BT-P @ 4 + BT-N @ + BT-N @ COMPARE IF 0 BT-OK ! THEN
    BT-LEVELS @ BT-N @ BT-ORDER BIDI-REORDER BT-M @ <> IF 0 BT-OK ! THEN
    BT-OK @ IF
        BT-M @ 0 ?DO
            I 4 * BT-ORDER + L@
            BT-P @ 4 + BT-N @ 2* + 1+ I + C@ <> IF 0 BT-OK ! LEAVE THEN
        LOOP
    THEN
    BT-OK @ 0= IF
        1 BT-FAILS +!
        BT-FIRST @ 0< IF BT-CASE @ BT-FIRST ! THEN
    THEN
    R> BT-P ! ;
: BT-RUN  ( count -- )
    0 BT-FAILS ! -1 BT-FIRST ! BT-DATA BT-P !
    0 ?DO I BT-CASE ! BT-ONE LOOP ;
"""


def _source(relative: str) -> bytes:
    text = (ROOT / "akashic" / relative).read_text(encoding="utf-8")
    return re.sub(r"(?m)^(?:PROVIDED|REQUIRE) [^\n]*$", "", text).encode()


def _runtime() -> MegaForthRuntime:
    runtime = MegaForthRuntime(execution_backend="native")
    for relative in ("text/unicode-tables.f", "text/unicode-props.f", "text/bidi.f"):
        runtime.evaluate(_source(relative), source_name=relative, step_budget=4_000_000_000)
    runtime.evaluate(DRIVER.encode(), source_name="bidi-driver", step_budget=100_000_000)
    assert runtime.main_context.data.snapshot() == ()
    return runtime


def _record(classes, direction, levels, order, paragraph=UNCHECKED, scalars=None) -> bytes:
    n = len(classes)
    assert n <= MAX_CHARACTERS
    body = bytes([n, direction, paragraph, 1 if scalars else 0])
    body += bytes(classes)
    body += bytes(REMOVED if level == "x" else int(level) for level in levels)
    body += bytes([len(order)]) + bytes(order)
    if scalars:
        body += b"".join(cp.to_bytes(4, "little") for cp in scalars)
    return body


def _ucd(name: str) -> Path:
    try:
        return generator.ucd_file(generator.DEFAULT_UCD, name)
    except generator.UcdError as exc:  # pragma: no cover - host data
        pytest.skip(f"pinned Unicode 15.1.0 data unavailable: {exc}")


def _bidi_test_records(sample: int):
    names = {name: index for index, name in enumerate(BIDI_NAMES)}
    levels = order = None
    index = 0
    for line in _ucd("BidiTest.txt").read_text(encoding="utf-8").splitlines():
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        if body.startswith("@Levels:"):
            levels = body.split(":", 1)[1].split()
            continue
        if body.startswith("@Reorder:"):
            order = [int(v) for v in body.split(":", 1)[1].split()]
            continue
        text, bits = body.split(";")
        classes = [names[name] for name in text.split()]
        bits = int(bits, 16)
        for bit, direction in ((1, "auto"), (2, "ltr"), (4, "rtl")):
            if bits & bit:
                if index % sample == 0:
                    yield (text, direction), _record(classes, DIRECTIONS[direction], levels, order)
                index += 1


def _bidi_character_records():
    directions = {"0": "ltr", "1": "rtl", "2": "auto"}
    for line in _ucd("BidiCharacterTest.txt").read_text(encoding="utf-8").splitlines():
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = body.split(";")
        scalars = [int(v, 16) for v in fields[0].split()]
        record = _record(
            [0] * len(scalars),
            DIRECTIONS[directions[fields[1]]],
            fields[3].split(),
            [int(v) for v in fields[4].split()],
            paragraph=int(fields[2]),
            scalars=scalars,
        )
        yield fields[0], record


def _run_records(runtime: MegaForthRuntime, records) -> tuple[int, int, list]:
    data = runtime.dictionary.find(b"BT-DATA").body_address
    fails_addr = runtime.dictionary.find(b"BT-FAILS").body_address
    first_addr = runtime.dictionary.find(b"BT-FIRST").body_address
    total = failures = 0
    examples: list = []
    chunk: list = []
    size = 0

    def flush():
        nonlocal total, failures, chunk, size
        if not chunk:
            return
        runtime.memory.write_bytes(data, b"".join(record for _, record in chunk))
        runtime.evaluate(f"{len(chunk)} BT-RUN".encode(), source_name="bidi-run",
                         step_budget=50_000_000_000)
        fails = runtime.memory.read64(fails_addr)
        if fails:
            failures += fails
            first = runtime.memory.read64(first_addr)
            if len(examples) < 5:
                examples.append(chunk[first][0])
        total += len(chunk)
        chunk = []
        size = 0

    for label, record in records:
        if size + len(record) > CHUNK_BYTES:
            flush()
        chunk.append((label, record))
        size += len(record)
    flush()
    return total, failures, examples


@pytest.fixture(scope="module")
def runtime() -> MegaForthRuntime:
    return _runtime()


def test_forth_bidi_passes_bidi_test(runtime: MegaForthRuntime) -> None:
    sample = int(os.environ.get("BIDI_CONFORMANCE_SAMPLE", "1"))
    total, failures, examples = _run_records(runtime, _bidi_test_records(sample))
    if sample == 1:
        assert total == 770_241
    assert (failures, examples) == (0, [])


def test_forth_bidi_passes_bidi_character_test(runtime: MegaForthRuntime) -> None:
    total, failures, examples = _run_records(runtime, _bidi_character_records())
    assert total == 91_707
    assert (failures, examples) == (0, [])
