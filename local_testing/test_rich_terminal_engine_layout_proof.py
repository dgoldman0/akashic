"""The APT1 engine keeps one geometry proof per exact input.

Complete, unchanged PT and engine sources run on the simulator, as in the
CELL-feed fixture.  The engine's geometry is proved once and accepted again
only while every field the proof read, and the session's PT layout serial, is
unchanged; the stack-only authority query accepts a kept proof but never
keeps one.
"""

from __future__ import annotations

import pytest

from test_rich_terminal_cell_feed import SOURCE, _FeedHarness


FIXTURE = b"""
CREATE LP-EXTRA 16 ALLOT
: LP-STORAGE  ( -- flag )  CF-ENGINE _RTAPT-ENGINE-STORAGE? ;
: LP-QUERY  ( a u -- flag )  CF-ENGINE RTAPT-STORAGE-DISJOINT? ;
: LP-KEPT  ( -- engine )  _RTAPT-LP-E @ ;
: LP-FORGET  ( -- )  0 _RTAPT-LP-E ! ;
: LP-SERIAL  ( -- serial )  CF-SESSION PT-LAYOUT-SERIAL@ ;
: LP-OPS-U  ( -- address )  CF-ENGINE _RTAPT-E.OPS-U ;
\\ Initialize the session again, once with its receive span laid over the
\\ engine's operation bank and once with its own spans.  PT-INIT alone cannot
\\ see the engine, so only the engine's geometry proof can refuse the first.
: LP-REINIT-OVER-OPS  ( -- status )
  CF-OPS CF-RX-U CF-TX CF-TX-U CF-EVENT PT-EVENT-SIZE CF-SESSION PT-INIT ;
: LP-REINIT  ( -- status )
  CF-RX CF-RX-U CF-TX CF-TX-U CF-EVENT PT-EVENT-SIZE CF-SESSION PT-INIT ;
"""


@pytest.fixture(scope="module")
def harness():
    feed = _FeedHarness(SOURCE.read_bytes())
    feed.runtime.evaluate(FIXTURE, source_name="engine-layout-proof-fixture.f")
    return feed


def _value(harness, word: str, *inputs: int) -> int:
    values, _ = harness.call(word, *inputs)
    assert len(values) == 1
    return values[0]


def _true(harness, word: str, *inputs: int) -> bool:
    return _value(harness, word, *inputs) != 0


def test_engine_keeps_one_geometry_proof_per_exact_input(harness) -> None:
    engine = harness.engine
    extra = _value(harness, "LP-EXTRA")
    ops = _value(harness, "CF-OPS")

    # The authority query proves the geometry itself and keeps nothing.
    harness.call("LP-FORGET")
    assert _true(harness, "LP-QUERY", extra, 16)
    assert _value(harness, "LP-KEPT") == 0
    assert not _true(harness, "LP-QUERY", ops, 8)

    # The engine's own check proves the geometry once and keeps the proof.
    assert _true(harness, "LP-STORAGE")
    assert _value(harness, "LP-KEPT") == engine
    assert _true(harness, "LP-STORAGE")
    assert _true(harness, "LP-QUERY", extra, 16)

    # A changed field is proved again, so the kept proof cannot vouch for it.
    ops_u = _value(harness, "LP-OPS-U")
    saved = harness.runtime.memory.read64(ops_u)
    harness.runtime.memory.write64(ops_u, saved + 1)
    assert not _true(harness, "LP-STORAGE")
    assert not _true(harness, "LP-QUERY", extra, 16)
    harness.runtime.memory.write64(ops_u, saved)
    assert _true(harness, "LP-STORAGE")
    assert _true(harness, "LP-QUERY", extra, 16)

    # A session initialized again gets a new serial, so the engine proves its
    # geometry against the new spans and refuses one laid over its bank.
    serial = _value(harness, "LP-SERIAL")
    assert serial != 0
    assert _value(harness, "LP-REINIT-OVER-OPS") == 0
    assert _value(harness, "LP-SERIAL") not in (0, serial)
    assert not _true(harness, "LP-STORAGE")
    assert not _true(harness, "LP-QUERY", extra, 16)
    assert _value(harness, "LP-REINIT") == 0
    assert _true(harness, "LP-STORAGE")
    assert _true(harness, "LP-QUERY", extra, 16)
    assert _value(harness, "LP-KEPT") == engine
