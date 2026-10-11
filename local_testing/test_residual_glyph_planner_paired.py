"""Execute the production residual planner against bounded paired CELL planes.

The screen borrow is isolated with a deterministic Forth authority fixture.
The planner, plan accessors, CELL codec, palette conversion, Unicode projection,
and KDOS exception boundary are their production sources, not Python models.
No desktop, renderer, worker, or filesystem workload is started.
"""

from __future__ import annotations

from dataclasses import dataclass
import os
import random
from pathlib import Path
import re
import struct
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", ROOT.parent / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from simulator.runtime import MegaForthRuntime  # noqa: E402
from tests.simulator.test_kdos_exceptions import _load_exceptions  # noqa: E402

PLANNER = ROOT / "akashic/tui/rich-terminal/residual-glyph-planner.f"
STEP_BUDGET = 3_000_000
MASK64 = (1 << 64) - 1
SENTINEL = 0xA173C2495E60B82D


def _without_loader(source: str) -> str:
    # Dependency composition belongs to this fixture; every definition and
    # data-table byte in the selected production source is retained verbatim.
    return re.sub(r"(?m)^(?:PROVIDED|REQUIRE) [^\n]*$", "", source)


def _source(relative: str) -> str:
    return (ROOT / "akashic" / relative).read_text()


def _dependency_source(planner: str) -> str:
    declarations = {}
    for relative in (
        "tui/rich-terminal/engine.f", "tui/rich-terminal/uidl-claim-ledger.f",
        "utils/memory-span.f", "utils/uint-range.f",
    ):
        source = _source(relative)
        for match in re.finditer(r"(?ms)^: (\S+)(?=\s).*?;\s*$", source):
            declarations[match[1]] = match[0]
        for match in re.finditer(r"(?m)^VARIABLE (\S+)\s*$", source):
            declarations[match[1]] = match[0]
        for match in re.finditer(
            r"(?m)^\s*(-?(?:0x[0-9A-Fa-f]+|[0-9]+))\s+CONSTANT\s+(\S+)", source
        ):
            declarations[match[2]] = match[0]
    chunks, emitted = [], set()

    def include(name):
        if name in emitted:
            return
        emitted.add(name)
        declaration = declarations[name]
        code = re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration)
        for token in code.split():
            if token != name and token in declarations:
                include(token)
        chunks.append(declaration)

    code = re.sub(r"\\[^\n]*|\([^)]*\)", "", planner)
    for token in code.split():
        if token in declarations:
            include(token)
    return "\n".join(chunks)


SCREEN_FIXTURE = r"""
VARIABLE TP-BACK
VARIABLE TP-RESIDUE
VARIABLE TP-COLS
VARIABLE TP-ROWS
VARIABLE TP-XT
VARIABLE TP-BORROWED
VARIABLE TP-BORROWS
VARIABLE TP-CHECKS
VARIABLE TP-REJECT
VARIABLE TP-THROW
: TP-PLANE-BYTES TP-COLS @ TP-ROWS @ * 8 * ;
: SCR-STORAGE-DISJOINT? ( a u -- flag )
    1 TP-CHECKS +!
    TP-THROW @ IF -88 THROW THEN
    TP-REJECT @ IF 2DROP 0 EXIT THEN
    2DUP TP-BACK @ TP-PLANE-BYTES MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    TP-RESIDUE @ TP-PLANE-BYTES MSPAN-OVERLAP? 0= ;
: TP-BACK-CALL ( -- ... )
    TP-BACK @ TP-COLS @ TP-ROWS @ TP-XT @ EXECUTE ;
: TP-PAIRED-CALL ( -- ... )
    TP-BACK @ TP-RESIDUE @ TP-COLS @ TP-ROWS @ 19 -1 TP-XT @ EXECUTE ;
: TP-END-BORROW ( exception -- )
    0 TP-BORROWED ! 0 TP-XT ! ?DUP IF THROW THEN ;
: SCR-WITH-BACK-PLANE ( xt -- ... )
    TP-XT ! -1 TP-BORROWED ! 1 TP-BORROWS +!
    ['] TP-BACK-CALL CATCH TP-END-BORROW ;
: SCR-WITH-PROJECTION-PLANES ( xt -- ... )
    TP-XT ! -1 TP-BORROWED ! 1 TP-BORROWS +!
    ['] TP-PAIRED-CALL CATCH TP-END-BORROW ;
\ Every cluster cell of a case names the one cluster held here.
CREATE TP-CLUSTER 64 ALLOT
VARIABLE TP-CLUSTER-N
: SCR-CLUSTER@ ( cell -- a n ) DROP TP-CLUSTER TP-CLUSTER-N @ ;
"""


@dataclass(frozen=True)
class Run:
    row: int
    col: int
    width: int
    text: bytes
    foreground: int
    background: int
    attrs: int


@dataclass
class Case:
    back: int
    residue: int
    cols: int
    rows: int
    request: int
    buffers: dict[str, tuple[int, int]]
    original_planes: tuple[bytes, bytes]
    original_claims: bytes
    menu_count: int


def cell(character: str | int, *, fg=7, bg=0, attrs=0) -> int:
    cp = ord(character) if isinstance(character, str) else character
    return cp | (fg << 32) | (bg << 40) | (attrs << 48)


def cells(*rows: str):
    return [[cell(character) for character in row] for row in rows]


class PairedPlannerHarness:
    def __init__(self):
        self.source = PLANNER.read_text()
        self.runtime = _load_exceptions(MegaForthRuntime(execution_backend="native"))
        self.serial = 0
        self.guards = []
        sources = [
            _dependency_source(self.source),
            _without_loader(_source("tui/cell.f")),
            _without_loader(_source("text/utf8.f").split("[DEFINED] GUARDED", 1)[0]),
            _without_loader(_source("text/unicode-tables.f")),
            _without_loader(_source("text/unicode-props.f")),
            _without_loader(_source("text/grapheme.f").split("[DEFINED] GUARDED", 1)[0]),
            _without_loader(_source("text/cell-width.f")),
        ]
        color = _source("tui/color.f")
        sources.append(color[color.index("CREATE _TC-CUBE-LEVELS"):color.index("VARIABLE _TPC-R")])
        sources.extend((SCREEN_FIXTURE, _without_loader(self.source)))
        for index, source in enumerate(sources):
            self.runtime.evaluate(source.encode(), source_name=f"paired-production-{index}.f",
                                  step_budget=STEP_BUDGET)
        assert self.runtime.main_context.data.snapshot() == ()

    def address(self, name):
        word = self.runtime.dictionary.find(name.encode())
        assert word is not None, name
        return word.body_address

    def set_variable(self, name, value):
        self.runtime.memory.write64(self.address(name), value & MASK64)

    def variable(self, name):
        return self.runtime.memory.read64(self.address(name))

    def allocate(self, size):
        if not size:
            return 0
        self.serial += 1
        word = self.runtime.define_created(f"TP-BUFFER-{self.serial}", initial_body=bytes(size + 23))
        start = (word.body_address + 7) & -8
        self.runtime.memory.write64(start, SENTINEL)
        self.runtime.memory.write64(start + 8 + size, SENTINEL)
        self.guards.extend((start, start + 8 + size))
        return start + 8

    def make_case(self, back, residue, claims=(), *, menu_count=0, clip=None,
                  region=None, max_run=1024, diff_bytes=None, overrides=None,
                  planes_of=None, text_bytes=None):
        rows, cols = len(back), len(back[0])
        assert rows and cols
        assert len(residue) == rows
        assert all(len(row) == cols for plane in (back, residue) for row in plane)
        memory = self.runtime.memory
        planes = []
        raw_planes = []
        if planes_of is not None:
            # Another request over the very planes an earlier case holds.
            planes = [planes_of.back, planes_of.residue]
            raw_planes = list(planes_of.original_planes)
        for plane in (back, residue) if planes_of is None else ():
            raw = struct.pack(f"<{cols * rows}Q", *(value for row in plane for value in row))
            address = self.allocate(len(raw))
            memory.write_bytes(address, raw)
            planes.append(address)
            raw_planes.append(raw)
        count = len(claims)
        capacities = {
            "claims": count * 80,
            "heads": (rows + 1) * 8,
            "events": count * 2 * 24,
            "diff": (cols + 1) * 16 if diff_bytes is None else diff_bytes,
            "plan": 144, "items": cols * rows * 120,
            "refs": cols * rows * 16,
            "text": cols * rows * 4 if text_bytes is None else text_bytes,
        }
        buffers = {name: (self.allocate(size), size) for name, size in capacities.items()}
        claim_bytes = b"".join(struct.pack("<10Q", 1, 1, 1, index, 0, 0, *rectangle)
                               for index, rectangle in enumerate(claims))
        if claim_bytes:
            memory.write_bytes(buffers["claims"][0], claim_bytes)
        request = self.allocate(280)
        x, y, width, height = region or (0, 0, cols, rows)
        cx, cy, cw, ch = clip or (0, 0, 0, 0)
        values = [1, 1, cols, rows, 10, x, y, width, height, cx, cy, cw, ch, 0,
                  3 if clip is not None else 1, 0, 101, max_run]
        for name in ("claims", "heads", "events", "diff", "plan", "items", "refs", "text"):
            values.extend(buffers[name])
        values.append(0)
        assert len(values) == 35
        memory.write_bytes(request, struct.pack("<35Q", *(value & MASK64 for value in values)))
        case = Case(*planes, cols, rows, request, buffers, tuple(raw_planes), claim_bytes, menu_count)
        for offset, value in (overrides or {}).items():
            memory.write64(request + offset, value & MASK64)
        for name, value in (("TP-BACK", case.back), ("TP-RESIDUE", case.residue),
                            ("TP-COLS", cols), ("TP-ROWS", rows)):
            self.set_variable(name, value)
        return case

    def reference(self, case, count, text_used, *, max_run=1024):
        """A reference descriptor naming CASE's output banks."""
        address = self.allocate(48)
        self.runtime.memory.write_bytes(address, struct.pack(
            "<6Q", case.buffers["items"][0], count, case.buffers["refs"][0],
            case.buffers["text"][0], text_used, max_run))
        return address

    def run(self, case, *, api="paired", back=None, residue=None, menu_count=None,
            reference=0):
        memory = self.runtime.memory
        prefix = case.menu_count if menu_count is None else menu_count
        supplied_back = case.back if back is None else back
        supplied_residue = case.residue if residue is None else residue
        if api == "paired":
            name, args = "RGRP-BUILD-PAIRED", (prefix, case.request)
        elif api == "single":
            name, args = "RGRP-BUILD", (case.request,)
        elif api == "single-from":
            name = "RGRP-BUILD-FROM-PLANE"
            args = (supplied_back, case.cols, case.rows, case.request)
        elif api == "referenced":
            name = "_RGRP-BUILD-PAIRED-WITH-REFERENCE"
            args = (supplied_back, supplied_residue, case.cols, case.rows, prefix,
                    reference, case.request)
        else:
            name = ("_RGRP-BUILD-PAIRED-FROM-AUTHORIZED-PLANES" if api == "authorized"
                    else "RGRP-BUILD-PAIRED-FROM-PLANES")
            args = (supplied_back, supplied_residue, case.cols, case.rows, prefix, case.request)
        for value in args:
            self.runtime.main_context.data.push(value & MASK64)
        self.last_steps = self.runtime.execute(name, step_budget=STEP_BUDGET).semantic_steps
        assert self.runtime.main_context.data.depth() == 6
        result = tuple(reversed([self.runtime.main_context.data.pop() for _ in range(6)]))
        assert self.runtime.main_context.returns.snapshot() == ()
        assert self.variable("TP-BORROWED") == 0
        assert self.variable("TP-XT") == 0
        for name in re.findall(r"(?m)^VARIABLE (_RGRP-\S+)", self.source):
            if name != "_RGRP-OWNED-LIMIT":
                assert self.variable(name) == 0, f"planner retained {name}"
        assert memory.read_bytes(self.address("_RGRP-UTF8"), 8) == bytes(8)
        assert tuple(memory.read_bytes(address, case.cols * case.rows * 8)
                     for address in (case.back, case.residue)) == case.original_planes
        if case.original_claims:
            assert memory.read_bytes(case.buffers["claims"][0], len(case.original_claims)) == case.original_claims
        for guard in self.guards:
            assert memory.read64(guard) == SENTINEL, "caller-boundary write"
        runs = []
        count, _, _, _, _, status = result
        if status == 0:
            for index in range(count):
                item = struct.unpack("<15Q", memory.read_bytes(case.buffers["items"][0] + index * 120, 120))
                offset, length = struct.unpack("<2Q", memory.read_bytes(case.buffers["refs"][0] + index * 16, 16))
                text = memory.read_bytes(case.buffers["text"][0] + offset, length)
                assert item[0] == 101 + index
                assert item[4] == 1 and item[13] == length
                runs.append(Run(item[2], item[3], item[5], text, item[10], item[11], item[12]))
        else:
            assert result[:5] == (0, 0, 0, 0, 0)
        return result, runs


@pytest.fixture
def harness():
    pytest.importorskip("_megaforth_native")
    return PairedPlannerHarness()


def projection(runs):
    return [(run.row, run.col, run.width, run.text) for run in runs]


@pytest.mark.parametrize("api", ["paired", "from", "authorized"])
def test_paired_reads_residue_for_menu_prefix_and_opaque_claims_win(harness, api):
    case = harness.make_case(cells("ABCDE", "FGHIJ"), cells("abcde", "fghij"),
                             [(0, 1, 2, 4), (0, 2, 1, 3)], menu_count=1)
    result, runs = harness.run(case, api=api)
    assert result == (3, 9, 24, 5, 103, 0)
    assert projection(runs) == [(0, 0, 2, b"Ab"), (0, 3, 2, b"dE"), (1, 0, 5, b"FghiJ")]
    assert harness.variable("TP-BORROWS") == (1 if api == "paired" else 0)
    assert (harness.variable("TP-CHECKS") == 0) == (api == "authorized")


def test_paired_overlapping_menu_union_ends_at_correct_row_and_column(harness):
    case = harness.make_case(cells("AAAAAA", "BBBBBB", "CCCCCC"),
                             cells("aaaaaa", "bbbbbb", "cccccc"),
                             [(0, 0, 2, 4), (1, 2, 3, 6)], menu_count=2)
    _, runs = harness.run(case)
    assert projection(runs) == [(0, 0, 6, b"aaaaAA"), (1, 0, 6, b"bbbbbb"), (2, 0, 6, b"CCcccc")]


def test_paired_physical_clip_keeps_signed_root_item_coordinates(harness):
    case = harness.make_case(cells("ABCDE", "FGHIJ", "KLMNO"), cells("abcde", "fghij", "klmno"),
                             [(0, 0, 3, 3), (0, 2, 3, 3)], menu_count=1,
                             region=(-1, -1, 7, 5), clip=(1, 1, 3, 1))
    _, runs = harness.run(case)
    assert projection(runs) == [(2, 2, 1, b"g"), (2, 4, 1, b"I")]


def test_paired_uses_selected_plane_styles_and_utf8_run_boundaries(harness):
    back = [[cell("A"), cell("B"), cell("C"), cell("D")]]
    residue = [[cell("x"), cell("é", fg=1, attrs=1), cell("é", fg=1, attrs=1), cell("y")]]
    case = harness.make_case(back, residue, [(0, 1, 1, 3)], menu_count=1, max_run=3)
    result, runs = harness.run(case)
    assert result == (4, 6, 32, 2, 104, 0)
    assert projection(runs) == [(0, 0, 1, b"A"), (0, 1, 1, "é".encode()),
                                (0, 2, 1, "é".encode()), (0, 3, 1, b"D")]
    assert [(run.foreground, run.attrs) for run in runs] == [
        (0xAAAAAAFF, 0), (0xAA0000FF, 1), (0xAA0000FF, 1), (0xAAAAAAFF, 0)]


def test_clusters_wide_pairs_and_joining_cells_make_whole_characters(harness):
    """A cluster's text is whole, a continuation adds a column but no text, a
    wide character a claim cuts shows a space, and a cell whose character
    would join the run's last one starts a new run (APT-1-TEXT)."""

    cluster = [0x65, 0x301]
    harness.runtime.memory.write_bytes(
        harness.address("TP-CLUSTER"), struct.pack(f"<{len(cluster)}I", *cluster))
    harness.set_variable("TP-CLUSTER-N", len(cluster))
    wide = 128
    cont = 256
    row = [cell("x"), cell(0x80000001), cell(0x4E2D, attrs=wide), cell(0, attrs=cont),
           cell("y"), cell(0x6587, attrs=wide), cell(0, attrs=cont)]
    case = harness.make_case([row], [row])
    result, runs = harness.run(case, api="single")
    assert result[5] == 0
    assert projection(runs) == [
        (0, 0, 7, "xe\u0301\u4e2dy\u6587".encode())]

    case = harness.make_case([row], [row], [(0, 3, 1, 4), (0, 6, 1, 7)])
    result, runs = harness.run(case, api="single")
    assert projection(runs) == [
        (0, 0, 3, "xe\u0301 ".encode()), (0, 4, 2, b"y ")]

    joining = [cell("x"), cell(0x301), cell("z")]
    case = harness.make_case([joining], [joining])
    result, runs = harness.run(case, api="single")
    assert projection(runs) == [(0, 0, 1, b"x"), (0, 1, 2, "\u0301z".encode())]


@pytest.mark.parametrize("api", ["single", "paired"])
@pytest.mark.parametrize("text_bytes", [9, 10])
def test_mixed_ascii_utf8_copy_preserves_exact_bytes_and_capacity(harness, api, text_bytes):
    claims = [(0, 1, 1, 6)] if api == "paired" else []
    case = harness.make_case(cells("AéB€C\x00D"), cells("ZéY€X\x00W"), claims,
                             menu_count=len(claims), max_run=4,
                             overrides={264: text_bytes})
    text_address, allocated_bytes = case.buffers["text"]
    memory = harness.runtime.memory
    memory.write_bytes(text_address, bytes([0xA5]) * allocated_bytes)
    result, runs = harness.run(case, api=api)
    # Every byte outside the declared output span must remain untouched,
    # including the first byte that a short-capacity append would overwrite.
    assert memory.read_bytes(text_address + text_bytes, allocated_bytes - text_bytes) == (
        bytes([0xA5]) * (allocated_bytes - text_bytes))
    if text_bytes == 9:
        assert result == (0, 0, 0, 0, 0, 1)
        assert memory.read_bytes(text_address, text_bytes) == bytes(text_bytes)
        return
    expected = (b"A\xc3\xa9Y\xe2\x82\xacX D" if api == "paired"
                else b"A\xc3\xa9B\xe2\x82\xacC D")
    assert result == (3, 10, 24, 4, 103, 0)
    assert projection(runs) == [(0, 0, 3, expected[:4]),
                                (0, 3, 2, expected[4:8]), (0, 5, 2, expected[8:])]
    assert memory.read_bytes(text_address, text_bytes) == expected


def test_paired_zero_menu_prefix_preserves_single_plane_result(harness):
    claims = [(0, 1, 1, 3)]
    paired = harness.make_case(cells("ABCDE"), cells("abcde"), claims)
    paired_result, paired_runs = harness.run(paired)
    single = harness.make_case(cells("ABCDE"), cells("abcde"), claims, diff_bytes=6 * 8)
    single_result, single_runs = harness.run(single, api="single")
    assert (paired_result, paired_runs) == (single_result, single_runs)
    assert projection(single_runs) == [(0, 0, 1, b"A"), (0, 3, 2, b"DE")]


@pytest.mark.parametrize("prefix", [-1, 2, 1 << 63])
def test_paired_rejects_invalid_menu_prefix_and_scrubs(harness, prefix):
    case = harness.make_case(cells("AB"), cells("ab"), [(0, 0, 1, 1)])
    result, _ = harness.run(case, menu_count=prefix)
    assert result[-1] == 3


@pytest.mark.parametrize("api", ["paired", "from", "authorized"])
def test_paired_requires_two_full_difference_channels(harness, api):
    case = harness.make_case(cells("ABCD"), cells("abcd"), [(0, 0, 1, 2)],
                             menu_count=1, diff_bytes=5 * 16 - 8)
    result, _ = harness.run(case, api=api)
    assert result[-1] == 1
    for name in ("heads", "events", "diff", "plan", "items", "refs", "text"):
        address, length = case.buffers[name]
        assert harness.runtime.memory.read_bytes(address, length) == bytes(length)


@pytest.mark.parametrize("defect", ["same-plane", "overlap-plane", "zero-residue", "unaligned-residue",
                                    "wrapped-residue", "output-alias", "request-alias", "claims-alias"])
@pytest.mark.parametrize("api", ["from", "authorized"])
def test_paired_plane_authority_rejects_aliases_before_any_mutation(harness, defect, api):
    case = harness.make_case(cells("ABCDE"), cells("abcde"), [(0, 0, 1, 1)], menu_count=1)
    options = {}
    if defect == "same-plane": options["residue"] = case.back
    elif defect == "overlap-plane": options["residue"] = case.back + 8
    elif defect == "zero-residue": options["residue"] = 0
    elif defect == "unaligned-residue": options["residue"] = case.residue + 1
    elif defect == "wrapped-residue": options["residue"] = MASK64 - 7
    elif defect == "output-alias": harness.runtime.memory.write64(case.request + 256, case.residue)
    elif defect == "request-alias": options["residue"] = case.request
    elif defect == "claims-alias": options["residue"] = case.buffers["claims"][0]
    # Authority must be proven before failure cleanup can touch any output.
    # Nonzero contents distinguish preservation from an erroneous zero-fill.
    for name, (address, length) in case.buffers.items():
        if name != "claims" and length:
            harness.runtime.memory.write_bytes(address, bytes([0xA5]) * length)
    before_outputs = {name: harness.runtime.memory.read_bytes(address, length)
                      for name, (address, length) in case.buffers.items()}
    result, _ = harness.run(case, api=api, **options)
    assert result[-1] == 3
    assert before_outputs == {name: harness.runtime.memory.read_bytes(address, length)
                              for name, (address, length) in case.buffers.items()}


def test_paired_authorized_peer_skips_only_prevalidated_screen_checks(harness):
    case = harness.make_case(cells("AB"), cells("ab"), [(0, 0, 1, 1)], menu_count=1)
    harness.set_variable("TP-REJECT", 1)
    result, _ = harness.run(case, api="from")
    assert result[-1] == 3
    before = harness.variable("TP-CHECKS")
    result, runs = harness.run(case, api="authorized")
    assert result[-1] == 0 and projection(runs) == [(0, 0, 2, b"aB")]
    assert harness.variable("TP-CHECKS") == before


def test_paired_throw_releases_borrow_and_clears_mode_before_single_build(harness):
    case = harness.make_case(cells("ABCD"), cells("abcd"), [(0, 0, 1, 2)], menu_count=1)
    harness.set_variable("TP-THROW", 1)
    result, _ = harness.run(case)
    assert result[-1] == 3
    harness.set_variable("TP-THROW", 0)
    result, runs = harness.run(case, api="single")
    assert result[-1] == 0 and projection(runs) == [(0, 2, 2, b"CD")]
    result, runs = harness.run(case)
    assert result[-1] == 0 and projection(runs) == [(0, 0, 4, b"abCD")]


def test_paired_no_claims_reads_back_and_keeps_two_channel_bound(harness):
    case = harness.make_case(cells("ABC"), cells("xyz"))
    result, runs = harness.run(case)
    assert result == (1, 3, 8, 3, 101, 0)
    assert projection(runs) == [(0, 0, 3, b"ABC")]
    short = harness.make_case(cells("ABC"), cells("xyz"), diff_bytes=4 * 8)
    result, _ = harness.run(short)
    assert result[-1] == 1


@pytest.mark.parametrize("api", ["from", "authorized"])
def test_paired_rejects_planner_owned_plane(harness, api):
    case = harness.make_case(cells("ABC"), cells("abc"))
    result, _ = harness.run(case, api=api, residue=harness.address("_RGRP-UTF8"))
    assert result[-1] == 3


# ---------------------------------------------------------------------------
# Reference plans
# ---------------------------------------------------------------------------

WIDE, CONT = 128, 256
CLUSTER = (0x65, 0x301)


def _set_cluster(harness):
    harness.runtime.memory.write_bytes(
        harness.address("TP-CLUSTER"), struct.pack(f"<{len(CLUSTER)}I", *CLUSTER))
    harness.set_variable("TP-CLUSTER-N", len(CLUSTER))


def _random_rows(rng, cols, rows):
    """Cells of every kind a scan decides on: styles, wide characters with
    and without their halves, joining marks and a cluster."""

    styles = [(7, 0, 0), (3, 0, 0), (7, 1, 0), (2, 0, 1)]
    plane = []
    for _ in range(rows):
        row, style = [], rng.choice(styles)
        while len(row) < cols:
            if rng.random() < 0.12:
                style = rng.choice(styles)
            fg, bg, attrs = style
            kind = rng.random()
            if kind < 0.06:
                row.append(cell(0x4E2D, fg=fg, bg=bg, attrs=attrs | WIDE))
                row.append(cell(0, fg=fg, bg=bg, attrs=attrs | CONT))
            elif kind < 0.08:
                row.append(cell(0, fg=fg, bg=bg, attrs=attrs | CONT))
            elif kind < 0.10:
                row.append(cell(0x4E2D, fg=fg, bg=bg, attrs=attrs | WIDE))
            elif kind < 0.12:
                row.append(cell(0x301, fg=fg, bg=bg, attrs=attrs))
            elif kind < 0.13:
                row.append(cell(0x80000001, fg=fg, bg=bg, attrs=attrs))
            else:
                row.append(cell(rng.choice("abcdefgh ijk"), fg=fg, bg=bg, attrs=attrs))
        plane.append(row[:cols])
    return plane


def _random_rect(rng, cols, rows):
    row0 = rng.randrange(rows)
    col0 = rng.randrange(cols)
    return (row0, col0, rng.randrange(row0 + 1, rows + 1), rng.randrange(col0 + 1, cols + 1))


def _outputs(harness, case, result):
    """Every byte a build wrote: its results, plan header and used banks."""

    memory = harness.runtime.memory
    count, text_used = result[0], result[1]
    return (result,
            memory.read_bytes(case.buffers["plan"][0], 144),
            memory.read_bytes(case.buffers["items"][0], count * 120),
            memory.read_bytes(case.buffers["refs"][0], count * 16),
            memory.read_bytes(case.buffers["text"][0], text_used))


def _base_and_reference(harness, back, residue, claims, menu_count, max_run):
    base = harness.make_case(back, residue, claims, menu_count=menu_count, max_run=max_run)
    result, _ = harness.run(base, api="authorized")
    assert result[5] == 0
    return base, harness.reference(base, result[0], result[1], max_run=max_run)


@pytest.mark.parametrize("seed", range(12))
def test_reference_runs_give_exactly_the_plan_reading_every_cell_gives(harness, seed):
    """A build that takes runs from the plan of the whole surface writes the
    very bytes, and fails the very way, a build reading every cell does:
    under its own clip, its own extra claims and any text capacity."""

    rng = random.Random(seed)
    _set_cluster(harness)
    cols, rows = 24, 6
    max_run = rng.choice((4, 7, 64))
    back, residue = _random_rows(rng, cols, rows), _random_rows(rng, cols, rows)
    menus = [_random_rect(rng, cols, rows) for _ in range(rng.randrange(3))]
    opaque = [_random_rect(rng, cols, rows) for _ in range(rng.randrange(3))]
    base, reference = _base_and_reference(
        harness, back, residue, menus + opaque, len(menus), max_run)
    for _ in range(2):
        extra = [_random_rect(rng, cols, rows) for _ in range(rng.randrange(3))]
        x, y = rng.randrange(cols), rng.randrange(rows)
        clip = rng.choice((None, (x, y, rng.randrange(1, cols - x + 1),
                                  rng.randrange(1, rows - y + 1))))
        case = harness.make_case(back, residue, menus + opaque + extra, menu_count=len(menus),
                                 clip=clip, planes_of=base, max_run=max_run)
        plain, _ = harness.run(case, api="authorized")
        assert plain[5] == 0
        expected = _outputs(harness, case, plain)
        taken, _ = harness.run(case, api="referenced", reference=reference)
        assert _outputs(harness, case, taken) == expected
        # The text capacity just under, at and just over what the plan uses.
        for text_bytes in (plain[1] - 1, plain[1], plain[1] + 1):
            if text_bytes <= 0:
                continue
            tight = harness.make_case(back, residue, menus + opaque + extra,
                                      menu_count=len(menus), clip=clip, planes_of=base,
                                      max_run=max_run, text_bytes=text_bytes)
            plain_tight, _ = harness.run(tight, api="authorized")
            expected = _outputs(harness, tight, plain_tight)
            taken, _ = harness.run(tight, api="referenced", reference=reference)
            assert _outputs(harness, tight, taken) == expected


def _pane_screen(cols, rows):
    """A window: border cells around text lines of a few styles."""

    plane = []
    for row in range(rows):
        line = [cell("|", fg=6)]
        words = "the quick brown fox jumps over a lazy dog " * 4
        for col in range(1, cols - 1):
            style = dict(fg=3) if (col // 9 + row) % 3 == 0 else dict(fg=7)
            line.append(cell(words[(col + row) % len(words)], **style))
        plane.append(line + [cell("|", fg=6)])
    return plane


def test_a_pane_takes_the_surface_plans_runs_instead_of_reading_its_cells(harness):
    """A pane inside a window border, with a claim of its own, plans the
    same bytes from the surface plan in well under half the steps."""

    cols, rows = 40, 6
    back = _pane_screen(cols, rows)
    base_claims = [(2, 12, 4, 20)]
    base, reference = _base_and_reference(harness, back, back, base_claims, 0, 64)
    pane = harness.make_case(back, back, base_claims + [(0, 30, 1, 36)],
                             clip=(1, 0, cols - 2, rows), planes_of=base, max_run=64)
    plain, _ = harness.run(pane, api="authorized")
    plain_steps = harness.last_steps
    expected = _outputs(harness, pane, plain)
    taken, _ = harness.run(pane, api="referenced", reference=reference)
    assert _outputs(harness, pane, taken) == expected
    assert harness.last_steps * 2 < plain_steps


@pytest.mark.parametrize("defect", ["limit", "items-alias", "refs-alias", "text-alias",
                                    "unaligned-items", "wrapped-text"])
def test_a_malformed_reference_is_refused_before_any_write(harness, defect):
    back = _pane_screen(12, 3)
    base, reference = _base_and_reference(harness, back, back, [], 0, 64)
    case = harness.make_case(back, back, [(1, 2, 2, 5)], planes_of=base, max_run=64)
    memory = harness.runtime.memory
    fields = list(struct.unpack("<6Q", memory.read_bytes(reference, 48)))
    if defect == "limit":
        fields[5] = 63
    elif defect == "items-alias":
        fields[0] = case.buffers["items"][0]
    elif defect == "refs-alias":
        fields[2] = case.buffers["text"][0]
    elif defect == "text-alias":
        fields[3] = case.buffers["refs"][0]
    elif defect == "unaligned-items":
        fields[0] += 1
    elif defect == "wrapped-text":
        fields[3], fields[4] = MASK64 - 7, 64
    memory.write_bytes(reference, struct.pack("<6Q", *fields))
    for name, (address, length) in case.buffers.items():
        if name != "claims" and length:
            memory.write_bytes(address, bytes([0xA5]) * length)
    before = {name: memory.read_bytes(address, length)
              for name, (address, length) in case.buffers.items()}
    result, _ = harness.run(case, api="referenced", reference=reference)
    assert result == (0, 0, 0, 0, 0, 3)
    assert before == {name: memory.read_bytes(address, length)
                      for name, (address, length) in case.buffers.items()}


def test_a_reference_run_of_the_wrong_shape_is_invalid(harness):
    back = _pane_screen(12, 3)
    base, reference = _base_and_reference(harness, back, back, [], 0, 64)
    case = harness.make_case(back, back, [], planes_of=base, max_run=64)
    # The surface plan's first run of several cells, after the border's
    # single cell, claims a height of two rows.
    harness.runtime.memory.write64(base.buffers["items"][0] + 120 + 32, 2)
    result, _ = harness.run(case, api="referenced", reference=reference)
    assert result == (0, 0, 0, 0, 0, 3)
