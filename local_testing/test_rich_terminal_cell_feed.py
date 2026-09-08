"""Real CELL-feed boundary checks and an optional two-row semantic benchmark.

The executable fixture uses complete, unchanged PT and Akashic engine sources,
the existing one-core exception/UART fixtures, and the real terminal driver.
It does not boot Desktop. The benchmark uses actual 280x2 geometry within
280x84 caller bounds; compilation, initial snapshot, retained discovery, and
host presentation are outside its timed CELL-span/write kernel.
"""

from __future__ import annotations

import argparse
from dataclasses import replace
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

import pytest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/rich-terminal/apt1-engine.f"
_paired = ROOT.parent / ROOT.name.replace("akashic-", "megapad-", 1)
MEGAPAD_ROOT = Path(os.environ.get(
    "MEGAPAD_ROOT", _paired if _paired != ROOT and _paired.is_dir()
    else ROOT.parent / "megapad"
))
sys.path.insert(0, str(MEGAPAD_ROOT))

from rich_terminal.apt1 import MessageType, snapshot_wire_bytes  # noqa: E402
from rich_terminal.driver import DriverLimits, RichTerminalDriver  # noqa: E402
from rich_terminal.server import TerminalConfig, TerminalState  # noqa: E402
from rich_terminal.transport import EgressWatermarks, HostPortLimits  # noqa: E402
from simulator.bootstrap_loader import BootstrapModule, BootstrapSourceLoader  # noqa: E402
from simulator.rich_terminal_host import SemanticBatchStop, SimulatorSessionBackend  # noqa: E402
from tests.simulator.test_kdos_exceptions import _load_exceptions  # noqa: E402
from tests.test_rich_terminal_driver import _retained_policy  # noqa: E402
from tests.test_rich_terminal_dual_backend import (  # noqa: E402
    ONE_CORE_UART_LOCK_SHIMS,
    RICH_TERMINAL_SOURCE,
    SIMULATOR_SOURCE_MAX_STEPS,
)


SESSION_ID = 0x43454C4C46454544
SENTINEL = 0x12345678
# The observed baseline costs about 8,463 semantic operations per cell.
# This watchdog bounds one 280-cell row, not a Desktop dispatch.
ROW_STEP_BUDGET = 3_000_000


def _engine_source(ref: str | None) -> bytes:
    if ref is None:
        return SOURCE.read_bytes()
    return subprocess.check_output(
        ["git", "--no-optional-locks", "show",
         f"{ref}:akashic/tui/rich-terminal/apt1-engine.f"],
        cwd=ROOT,
    )


def _fixture_source(cols: int) -> bytes:
    return f"""
{cols} CONSTANT CF-COLS
2 CONSTANT CF-ROWS
12 CF-COLS 8 * + 256 MAX CONSTANT CF-MAX-PAY
_PT-CONTROL-RESERVE _PT-HDR + CF-MAX-PAY + CONSTANT CF-RX-U
_PT-OPEN-BYTES _PT-HDR CF-MAX-PAY + MAX CONSTANT CF-TX-U
CREATE CF-RX CF-RX-U ALLOT
CREATE CF-TX CF-TX-U ALLOT
CREATE CF-EVENT PT-EVENT-SIZE ALLOT
CREATE CF-SESSION-MEM PT-SESSION-SIZE 7 + ALLOT
: CF-SESSION CF-SESSION-MEM 7 + -8 AND ;
CREATE CF-CONFIG-MEM RTAPT-CONFIG-SIZE 7 + ALLOT
: CF-CONFIG CF-CONFIG-MEM 7 + -8 AND ;
CREATE CF-ENGINE-MEM RTAPT-ENGINE-SIZE 7 + ALLOT
: CF-ENGINE CF-ENGINE-MEM 7 + -8 AND ;
CREATE CF-OWNERS-MEM RTAPT-OWNER-SIZE 7 + ALLOT
: CF-OWNERS CF-OWNERS-MEM 7 + -8 AND ;
CREATE CF-OPS-MEM RTAPT-OP-SIZE 7 + ALLOT
: CF-OPS CF-OPS-MEM 7 + -8 AND ;
CREATE CF-COPY-MEM 15 ALLOT
: CF-COPY CF-COPY-MEM 7 + -8 AND ;
CREATE CF-LEDGER-MEM RTAPT-CONTROL-LEDGER-SIZE 7 + ALLOT
: CF-LEDGER CF-LEDGER-MEM 7 + -8 AND ;
VARIABLE CF-ACTIVE
VARIABLE CF-RETAINED
VARIABLE CF-ROW
: CF-INIT
  CF-RX CF-RX-U CF-TX CF-TX-U CF-EVENT PT-EVENT-SIZE
  CF-SESSION PT-INIT THROW
  CF-SESSION CF-OWNERS RTAPT-OWNER-SIZE CF-OPS RTAPT-OP-SIZE
  CF-COPY 8 CF-LEDGER RTAPT-CONTROL-LEDGER-SIZE
  CF-CONFIG RTAPT-CONFIG-INIT THROW
  CF-CONFIG CF-ENGINE RTAPT-INIT THROW ;
: CF-START CF-SESSION PT-START THROW ;
: CF-SERVICE
  CF-SESSION PT-SERVICE DUP PT-S-WOULD-BLOCK = IF DROP ELSE THROW THEN
  CF-SESSION PT-ACTIVE? CF-ACTIVE !
  CF-SESSION PT-RETAINED-STATE@ CF-RETAINED ! ;
: CF-INITIAL-BEGIN
  CF-COLS CF-ROWS CF-ROWS CF-COLS CF-ROWS * CF-SESSION
  PT-SNAPSHOT-BEGIN THROW ;
: CF-INITIAL-ROW
  CF-ROW ! CF-ROW @ 0 CF-COLS CF-SESSION PT-SPAN-BEGIN THROW
  CF-COLS 0 DO 32 7 0 0 CF-SESSION PT-CELL THROW LOOP ;
: CF-INITIAL-COMMIT
  0 0 0 CF-SESSION PT-CURSOR THROW
  CF-SESSION PT-TX-COMMIT THROW ;
: CF-BEGIN
  CF-COLS CF-ROWS CF-ROWS CF-COLS CF-ROWS * PT-CELL-DELTA
  CF-ENGINE RTAPT-CELL-BEGIN THROW ;
: CF-ROW-WRITE
  CF-ROW ! CF-ROW @ 0 CF-COLS CF-ENGINE RTAPT-CELL-SPAN-BEGIN THROW
  CF-COLS 0 DO
    65 CF-ROW @ + 7 CF-ROW @ 1 CF-ENGINE RTAPT-CELL-WRITE THROW
  LOOP ;
: CF-CURSOR 1 CF-COLS 1- 1 CF-ENGINE RTAPT-CELL-CURSOR ;
: CF-COMMIT CF-ENGINE RTAPT-CELL-COMMIT THROW ;
""".encode("ascii")


class _FeedHarness:
    def __init__(self, engine_source: bytes, *, cols: int = 2):
        self.cols = cols
        self.runtime = _load_exceptions()
        self.backend = None
        self.driver = None
        self.views = []
        self.legacy_output = []
        self.runtime.evaluate(
            ONE_CORE_UART_LOCK_SHIMS + RICH_TERMINAL_SOURCE.read_bytes(),
            source_name="one-core-uart-lock-shims+complete-rich-terminal.f",
            step_budget=SIMULATOR_SOURCE_MAX_STEPS,
        )
        records = (
            (b"uint-range.f", b"akashic-uint-range", "utils/uint-range.f"),
            (b"../../utils/memory-span.f", b"akashic-memory-span",
             "utils/memory-span.f"),
            (b"phase-profile.f", b"akashic-tui-rterm-phase-profile",
             "tui/rich-terminal/phase-profile.f"),
            (b"apt1-engine.f", b"akashic-tui-rtapt",
             "tui/rich-terminal/apt1-engine.f"),
        )
        loader = BootstrapSourceLoader(self.runtime, tuple(
            BootstrapModule(
                request_name=request,
                provided_id=provider,
                source_name=str(ROOT / "akashic" / path),
                source=(engine_source if request == b"apt1-engine.f"
                        else (ROOT / "akashic" / path).read_bytes()),
            )
            for request, provider, path in records
        ))
        loader.install()
        loader.load(b"apt1-engine.f", step_budget=SIMULATOR_SOURCE_MAX_STEPS)
        self.runtime.evaluate(_fixture_source(cols), source_name="cell-feed-fixture.f")
        self.call("CF-INIT")
        self.engine = self.call("CF-ENGINE")[0][0]

    def call(self, word: str, *inputs: int):
        data = self.runtime.main_context.data
        assert data.snapshot() == ()
        for value in inputs:
            data.push(value)
        if self.backend is None:
            result = self.runtime.execute(word, step_budget=ROW_STEP_BUDGET)
        else:
            result = self.backend.run_semantic_batch(
                entry=word, step_budget=ROW_STEP_BUDGET
            )
            assert result.stop_reason is SemanticBatchStop.COMPLETED
        values = data.snapshot()
        data.clear()
        assert self.runtime.main_context.returns.snapshot() == ()
        return values, result.semantic_steps

    def cell(self, name: str) -> int:
        word = self.runtime.find(name)
        assert word is not None
        return self.runtime.memory.read64(word.body_address)

    def service(self):
        assert self.driver is not None
        self.driver.service(max_batches=8)
        self.call("CF-SERVICE")
        self.driver.service(max_batches=8)
        assert self.driver.failure_reason is None
        assert self.backend.rich_terminal_host.failure_reason is None

    def until(self, predicate):
        for _ in range(24):
            self.service()
            if predicate():
                return
        raise AssertionError("bounded CELL fixture did not settle protocol state")

    def attach(self):
        # The actual two-row setup remains small; caller maxima retain the
        # ordinary Desktop width and height without constructing Desktop.
        maximum_payload = 12 + 280 * 8
        maximum_transaction = snapshot_wire_bytes(280, 84) + 256
        publication = maximum_transaction + 4096
        self.backend = SimulatorSessionBackend(
            self.runtime, legacy_output_sink=self.legacy_output.append
        )
        try:
            self.driver = RichTerminalDriver.attach(
                self.backend,
                HostPortLimits(
                    egress=EgressWatermarks(
                        high_bytes=publication * 2, low_bytes=publication,
                        high_batches=16, low_batches=2,
                    ),
                    retained_publication_bytes=publication,
                    ingress_bytes=8192, ingress_events=16,
                    ingress_control_bytes=4096, ingress_control_events=8,
                    geometry_events=2,
                ),
                TerminalConfig(
                    max_payload=maximum_payload,
                    max_transaction_bytes=maximum_transaction,
                    terminal_receive_credit=maximum_transaction,
                    max_cells=280 * 84, max_feed_bytes=publication,
                    max_cols=280, max_rows=84, cols=self.cols, rows=2,
                ),
                DriverLimits(4096, 8),
                retained_policy=replace(
                    _retained_policy(),
                    client_to_terminal_max_payload=maximum_payload,
                    max_retained_transaction_bytes=maximum_transaction,
                    base_max_transaction_bytes=maximum_transaction,
                ),
                view_sink=self.views.append,
                session_id_factory=lambda: SESSION_ID,
            )
            self.call("CF-START")
            self.until(lambda: bool(self.cell("CF-ACTIVE")))
            self.call("CF-INITIAL-BEGIN")
            for row in range(2):
                self.call("CF-INITIAL-ROW", row)
            self.call("CF-INITIAL-COMMIT")
            available = self.call("PT-RET-ST-AVAILABLE")[0][0]
            self.until(lambda: self.cell("CF-RETAINED") == available)
            assert self.driver.core.state is TerminalState.ACTIVE
            assert len(self.views) == 1
        except BaseException:
            self.close()
            raise

    def close(self):
        try:
            if self.driver is not None:
                self.driver.close()
        finally:
            if self.backend is not None:
                self.backend.close()


@pytest.fixture(scope="module")
def feed():
    fixture = _FeedHarness(SOURCE.read_bytes())
    fixture.attach()
    try:
        yield fixture
    finally:
        fixture.close()


@pytest.mark.parametrize("word,inputs", [
    ("RTAPT-CELL-SPAN-BEGIN", (0, 0, 1)),
    ("RTAPT-CELL-WRITE", (65, 7, 0, 1)),
    ("RTAPT-CELL-CURSOR", (0, 0, 1)),
])
def test_public_cell_feed_rejects_before_wire_effects(feed, word, inputs):
    runtime = feed.runtime
    size = feed.call("RTAPT-ENGINE-SIZE")[0][0]
    original = runtime.memory.read_bytes(feed.engine, size)
    frames = feed.driver.core.frames_received
    pending = feed.backend.rich_terminal_host.accepted_egress_bytes
    active = feed.call("_RTAPT-E.ACTIVE-KIND", feed.engine)[0][0]
    status = feed.call("_RTAPT-E.LAST-STATUS", feed.engine)[0][0]
    ops = feed.call("_RTAPT-E.OPS-A", feed.engine)[0][0]
    owners = feed.call("CF-OWNERS")[0][0]
    quarantine = feed.call("_RTAPT-ACTIVE-QUARANTINED")[0][0]
    for mutation, expected in (
        ("storage", 3), ("overlap", 3), ("invalid-quarantine", 3),
        ("quarantine", 7), ("phase", 6),
    ):
        try:
            if mutation in ("storage", "invalid-quarantine"):
                runtime.memory.write64(feed.engine, 0)
            elif mutation == "overlap":
                runtime.memory.write64(ops, owners)
            if mutation in ("quarantine", "invalid-quarantine"):
                runtime.memory.write64(active, quarantine)
                runtime.memory.write64(status, 7)
            before = runtime.memory.read_bytes(feed.engine, size)
            values, _ = feed.call(word, SENTINEL, *inputs, feed.engine)
            assert values == (SENTINEL, expected)
            assert runtime.memory.read_bytes(feed.engine, size) == before
            assert feed.driver.core.frames_received == frames
            assert feed.backend.rich_terminal_host.accepted_egress_bytes == pending
        finally:
            runtime.memory.write_bytes(feed.engine, original)


def _exercise(feed: _FeedHarness) -> dict:
    feed.call("CF-BEGIN")
    seconds = 0.0
    steps = 0
    before_bytes = feed.driver.core.frame_bytes_received
    for row in range(2):
        started = time.perf_counter()
        values, row_steps = feed.call("CF-ROW-WRITE", SENTINEL, row)
        seconds += time.perf_counter() - started
        steps += row_steps
        assert values == (SENTINEL,)
    values, _ = feed.call("CF-CURSOR", SENTINEL)
    assert values == (SENTINEL, 0)
    feed.call("CF-COMMIT")
    feed.until(lambda: len(feed.views) == 2)
    composite = feed.views[-1]
    view = composite.cell
    assert view is not None
    cells = tuple(
        (cell.codepoint, cell.foreground, cell.background, cell.attributes)
        for row in view.cells for cell in row
    )
    expected = ((65, 7, 0, 1),) * feed.cols + ((66, 7, 1, 1),) * feed.cols
    assert cells == expected
    assert (view.cursor.row, view.cursor.column, view.cursor.visible) == (
        1, feed.cols - 1, True
    )
    assert view.revision == 2
    assert feed.driver.core.frames_received_by_type[int(MessageType.CELL_SPAN)] == 4
    count = feed.cols * 2
    return {
        "geometry": [feed.cols, 2], "caller_maxima": [280, 84],
        "cells": count, "semantic_steps": steps,
        "semantic_steps_per_cell": steps / count,
        "cell_feed_seconds": seconds, "cells_per_second": count / seconds,
        "committed_frame_bytes": feed.driver.core.frame_bytes_received - before_bytes,
        "cell_sha256": hashlib.sha256(json.dumps(cells).encode()).hexdigest(),
        "revision": view.revision,
    }


def test_public_cell_feed_commits_span_cell_and_cursor_through_real_host(feed):
    _exercise(feed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref", default="2f090ee")
    args = parser.parse_args()
    results = []
    # Intentionally sequential: never run a second runtime alongside the first.
    for label, ref in (("baseline", args.baseline_ref), ("current", None)):
        started = time.perf_counter()
        source = _engine_source(ref)
        fixture = _FeedHarness(source, cols=280)
        try:
            fixture.attach()
            result = _exercise(fixture)
        finally:
            fixture.close()
        result.update(
            label=label, engine_sha256=hashlib.sha256(source).hexdigest(),
            total_fixture_seconds=time.perf_counter() - started,
        )
        results.append(result)
    assert results[0]["cell_sha256"] == results[1]["cell_sha256"]
    assert results[0]["committed_frame_bytes"] == results[1]["committed_frame_bytes"]
    print(json.dumps({
        "scope": "two-row semantic CELL feed only; not Desktop throughput",
        "results": results,
        "speedup": results[1]["cells_per_second"] / results[0]["cells_per_second"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
