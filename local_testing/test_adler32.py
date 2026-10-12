#!/usr/bin/env python3
"""Akashic math/adler32.f against Python's zlib.adler32.

The sum of fixed and random data, whole and continued a piece at a time,
and of a run of 0xFF bytes long enough to cross the module's reduction
block, the case that grows the sums fastest.
"""

from __future__ import annotations

import random
import zlib

import pytest

from forth_dependencies import dependency_order
from test_uidl_collection_snapshot import AK, KDOS_PATH, _load_forth_lines
from simulator.platform import create_one_core_address_space
from simulator.runtime import MegaForthRuntime

BUFFER = 3 << 20


@pytest.fixture(scope="module")
def runtime():
    runtime = MegaForthRuntime(
        memory=create_one_core_address_space(external_size=16 << 20, hbw_size=1 << 20),
        execution_backend="native",
    )
    runtime.evaluate(KDOS_PATH.read_bytes(), source_name="kdos.f")
    runtime.evaluate(b"ENTER-USERLAND", source_name="userland")
    source = []
    for module in dependency_order(AK, ("math/adler32.f",)):
        source.extend(_load_forth_lines(AK / module))
    runtime.evaluate(("\n".join(source) + f"\n{BUFFER} XBUF AT-BUF\n").encode(),
                     source_name="adler32", step_budget=10_000_000)
    runtime.drain_uart_output()
    return runtime


def _pop(runtime) -> int:
    value = runtime.main_context.data.pop()
    assert runtime.main_context.data.depth() == 0
    return value


def _buffer(runtime) -> int:
    runtime.execute("AT-BUF")
    return _pop(runtime)


def _sum(runtime, data: bytes, cuts=()) -> int:
    """The module's sum of DATA, continued at each of CUTS."""

    base = _buffer(runtime)
    runtime.memory.write_bytes(base, data)
    stack = runtime.main_context.data
    runtime.execute("ADLER32-INIT")
    start = 0
    for end in (*sorted(cuts), len(data)):
        stack.push(base + start)
        stack.push(end - start)
        runtime.execute("ADLER32-UPDATE", step_budget=200_000_000)
        start = end
    return _pop(runtime)


@pytest.mark.parametrize("data, expected", (
    (b"", 0x00000001),
    (b"a", 0x00620062),
    (b"abc", 0x024D0127),
    (b"Wikipedia", 0x11E60398),
    (b"123456789", 0x091E01DE),
))
def test_known_sums(runtime, data, expected):
    assert _sum(runtime, data) == expected == zlib.adler32(data)


@pytest.mark.parametrize("size", (1, 255, 5551, 5552, 5553, 65521, 100_000))
def test_random_data_whole_and_in_pieces(runtime, size):
    rng = random.Random(size)
    data = rng.randbytes(size)
    assert _sum(runtime, data) == zlib.adler32(data)
    cuts = sorted(rng.sample(range(size + 1), min(size, 5)))
    assert _sum(runtime, data, cuts) == zlib.adler32(data)


def test_a_long_run_of_ff_crosses_the_reduction_block(runtime):
    data = b"\xff" * (2_500_000)
    assert _sum(runtime, data) == zlib.adler32(data)
    assert _sum(runtime, data, (1, 1_048_576, 1_048_577)) == zlib.adler32(data)


def test_one_call_matches_the_continued_sum(runtime):
    data = random.Random(7).randbytes(3000)
    base = _buffer(runtime)
    runtime.memory.write_bytes(base, data)
    stack = runtime.main_context.data
    stack.push(base)
    stack.push(len(data))
    runtime.execute("ADLER32")
    assert _pop(runtime) == zlib.adler32(data)
