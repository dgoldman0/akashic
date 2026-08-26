"""Seconds-scale structural and byte oracles for the final-screen producer."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic" / "tui" / "rich-terminal" / "screen-plane.f"

U32_MAX = 0xFFFFFFFF
PLAN_ITEM_BYTES = 120
RUN_COPY_FIXED = 120
RUN_FRAME_FIXED = 120
REGION_COPY_BYTES = 72
REGION_FRAME_BYTES = 88
UPDATE_ENVELOPE_BYTES = 160
TEXT_CAPACITY = 4


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$", source
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def _align8(value: int) -> int:
    return (value + 7) & ~7


def _palette_rgba(index: int) -> int:
    assert 0 <= index <= 255
    base = (
        0x000000FF,
        0xAA0000FF,
        0x00AA00FF,
        0xAA5500FF,
        0x0000AAFF,
        0xAA00AAFF,
        0x00AAAAFF,
        0xAAAAAAFF,
        0x555555FF,
        0xFF5555FF,
        0x55FF55FF,
        0xFFFF55FF,
        0x5555FFFF,
        0xFF55FFFF,
        0x55FFFFFF,
        0xFFFFFFFF,
    )
    if index < 16:
        return base[index]
    if index < 232:
        levels = (0, 95, 135, 175, 215, 255)
        cube = index - 16
        red, remainder = divmod(cube, 36)
        green, blue = divmod(remainder, 6)
        return (
            levels[red] << 24
            | levels[green] << 16
            | levels[blue] << 8
            | 0xFF
        )
    gray = 8 + 10 * (index - 232)
    return gray << 24 | gray << 16 | gray << 8 | 0xFF


def _cell_codepoint(codepoint: int) -> int:
    """Independent samples of the screen's isolated one-cell projection."""

    if codepoint == 0:
        return 0x20
    if codepoint in {0x0A, 0x0301, 0x1F642}:
        return 0xFFFD
    assert 0 <= codepoint <= 0x10FFFF
    return codepoint


def _unorm32(boundary: int, root: int) -> int:
    return boundary * U32_MAX // root


@dataclass(frozen=True)
class Cell:
    codepoint: int
    foreground: int
    background: int
    attrs: int


@dataclass(frozen=True)
class Run:
    owner: int
    generation: int
    object_id: int
    region: int
    row: int
    col: int
    root_rows: int
    root_cols: int
    foreground: int
    background: int
    attrs: int
    text: bytes


def _project_plane(
    cells: list[Cell],
    *,
    rows: int,
    cols: int,
    owner: int,
    generation: int,
    region: int,
    first_object: int,
) -> list[Run]:
    assert len(cells) == rows * cols
    runs = []
    for index, cell in enumerate(cells):
        assert cell.attrs & ~0x01FF == 0
        assert cell.attrs & 0x10 == 0  # GLYPH_RUN cannot express blink.
        codepoint = _cell_codepoint(cell.codepoint)
        runs.append(
            Run(
                owner=owner,
                generation=generation,
                object_id=first_object + index,
                region=region,
                row=index // cols,
                col=index % cols,
                root_rows=rows,
                root_cols=cols,
                foreground=_palette_rgba(cell.foreground),
                background=_palette_rgba(cell.background),
                attrs=cell.attrs & 0x006F,
                text=chr(codepoint).encode("utf-8"),
            )
        )
    return runs


def _wire_payload(run: Run) -> bytes:
    left = _unorm32(run.col, run.root_cols)
    top = _unorm32(run.row, run.root_rows)
    right = _unorm32(run.col + 1, run.root_cols)
    bottom = _unorm32(run.row + 1, run.root_rows)
    fg = run.foreground.to_bytes(4, "big")
    bg = run.background.to_bytes(4, "big")
    fixed = struct.pack(
        "<QQQHHiQQIIII8BHHI",
        run.owner,
        run.generation,
        run.object_id,
        4,  # GLYPH_RUN object kind
        1,  # visible
        0,  # z
        run.region,
        0,  # root parent
        left,
        top,
        right,
        bottom,
        *fg,
        *bg,
        run.attrs,
        0,
        len(run.text),
    )
    assert len(fixed) == 80
    return fixed + run.text


def test_module_is_isolated_fixed_shape_and_caller_bounded() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    assert "PROVIDED akashic-tui-rich-screen-plane" in source
    assert re.findall(r"(?m)^REQUIRE (.+)$", source) == [
        "engine.f",
        "../screen.f",
        "../color.f",
    ]
    for forbidden in ("UIDL", "DESK", "APPLET", "RTAPT"):
        assert forbidden not in source.upper()
    assert not re.search(r"(?m)(?:^|\s)PT-", source.upper())
    assert not re.search(r"\b(?:CREATE|ALLOT|XBUF)\b", source)
    assert not re.search(r"\b(?:VERSION|REVISION|SCHEMA|ABI)\b", source, re.I)
    assert not re.search(r"\b80\s+CONSTANT|\b24\s+CONSTANT", source)

    assert "568 CONSTANT RTSCREEN-SIZE" in source
    for field, offset in {
        "FACADE": 24,
        "ITEMS-A": 32,
        "ITEMS-U": 40,
        "OWNER": 48,
        "OWNER-GEN": 56,
        "REGION": 64,
        "FIRST-OBJECT": 72,
        "PLAN": 136,
        "RUN": 248,
        "LIMITS": 400,
        "UTF8": 560,
    }.items():
        assert f": _RTSCREEN.{field}" in source
        assert f"{offset} + ;" in source

    init = _definition(source, "RTSCREEN-INIT")
    assert "_RTSCREEN-I-ITEMS-A" in init
    assert "_RTSCREEN-I-ITEMS-U" in init
    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE MOD" in init
    assert init.count("RTE-STORAGE-DISJOINT?") == 2
    assert "MSPAN-OVERLAP?" in init

    capacity = _definition(source, "_RTSCREEN-CALL-CAPACITY?")
    assert "_RTSCREEN-S-COLS @ _RTSCREEN-S-ROWS @" in capacity
    assert "_RTSCREEN-UMUL?" in capacity
    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE" in capacity
    assert "_RTSCREEN.ITEMS-U @ U>" in capacity
    assert "_RTSCREEN-CELL-TEXT-CAPACITY" in capacity
    assert "_RTSCREEN-UADD?" in capacity

    admit = _definition(source, "_RTSCREEN-LIMITS-ADMIT?")
    for accessor in (
        "RTE-LIMITS-GLYPH-RUN-BYTES@",
        "RTE-LIMITS-REGIONS@",
        "RTE-LIMITS-OBJECTS@",
        "RTE-LIMITS-OPS@",
        "RTE-LIMITS-UTF8-BYTES@",
    ):
        assert accessor in admit


def test_projection_is_final_screen_row_major_and_renderer_neutral() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    load = _definition(source, "_RTSCREEN-CELL-LOAD?")
    plan_item = _definition(source, "_RTSCREEN-PLAN-ITEM?")
    run = _definition(source, "_RTSCREEN-RUN?")

    assert "SCR-GET" in load
    assert "CELL-CP@ DUP 0= IF DROP 32 THEN" in load
    assert "CW-CELL-CP" in load
    assert "UTF8-ENCODE" in load
    assert "CELL-A-BLINK AND 0=" in _definition(source, "_RTSCREEN-CELL-ATTRS?")
    for body in (plan_item, run):
        assert "_RTSCREEN.FIRST-OBJECT @" in body
        assert "_RTSCREEN-C-ROW @" in body
        assert "_RTSCREEN-C-COL @" in body
        assert "TUI-PALETTE>RGBA" in body
        assert "_RTSCREEN-RICH-ATTRS AND" in body
    assert "1 _RTSCREEN-PI-ITEM @ _RTE-LPI.HEIGHT !" in plan_item
    assert "1 _RTSCREEN-PI-ITEM @ _RTE-LPI.WIDTH !" in plan_item
    assert "_RTSCREEN-CELL-TEXT-CAPACITY" in plan_item
    assert "1 _RTSCREEN-R-RUN @ _RTE-GLYPH-RUN.HEIGHT !" in run
    assert "1 _RTSCREEN-R-RUN @ _RTE-GLYPH-RUN.WIDTH !" in run


def test_lifecycle_is_hidden_start_exact_reveal_then_stable_replacement() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    step_cold = _definition(source, "_RTSCREEN-STEP-COLD")
    preflight = _definition(source, "_RTSCREEN-STEP-PREFLIGHT")
    owner_open = _definition(source, "_RTSCREEN-STEP-OWNER-OPEN")
    prepare = _definition(source, "RTSCREEN-PREPARE")

    assert "RTE-LIMITS@" in step_cold
    assert "RTE-GLYPH-RUN-PREFLIGHT" in preflight
    assert "RTE-OWNER-OPEN" in owner_open
    assert all(
        token not in prepare
        for token in ("RTE-LIMITS@", "RTE-GLYPH-RUN-PREFLIGHT", "RTE-OWNER-OPEN")
    )
    assert prepare.rstrip().endswith("SCB-S-OK ;")

    accept_gate = prepare.index("DUP _RTSCREEN-ACCEPT-PHASE?")
    live_gate = prepare.index("DUP _RTSCREEN-PH-LIVE =", accept_gate)
    ready_delta_gate = prepare.index("DUP _RTSCREEN-PH-READY-DELTA =", live_gate)
    assert accept_gate < live_gate < ready_delta_gate
    assert (
        prepare.index("SCB-S-WOULD-BLOCK EXIT", accept_gate) < live_gate
    )
    assert (
        prepare.index("_RTSCREEN-PREPARE-DELTA EXIT", live_gate)
        < ready_delta_gate
    )
    accept_phases = _definition(source, "_RTSCREEN-ACCEPT-PHASE?")
    for phase in (
        "_RTSCREEN-PH-ACCEPT-START",
        "_RTSCREEN-PH-ACCEPT-REVEAL",
        "_RTSCREEN-PH-ACCEPT-DELTA",
    ):
        assert phase in accept_phases

    start = _definition(source, "_RTSCREEN-PREPARE-START")
    reveal = _definition(source, "_RTSCREEN-PREPARE-REVEAL")
    delta = _definition(source, "_RTSCREEN-PREPARE-DELTA")
    assert "RTE-RETAINED-REPLACE-START RTE-COMMIT -1" in start
    assert (
        "RTE-RETAINED-REPLACE-CONTINUE RTE-COMMIT-AND-REVEAL 0"
        in reveal
    )
    assert "RTE-RETAINED-DELTA RTE-COMMIT 0" in delta

    start_body = _definition(source, "_RTSCREEN-CAPTURE-START-BODY")
    replacements = _definition(source, "_RTSCREEN-CAPTURE-REPLACEMENTS")
    assert "RTE-REGION-DEFINE" in _definition(source, "_RTSCREEN-CAPTURE-REGION")
    assert "RTE-GLYPH-RUN-DEFINE" in start_body
    assert "RTE-GLYPH-RUN-REPLACE" not in start_body
    assert "RTE-GLYPH-RUN-REPLACE" in replacements
    assert "RTE-GLYPH-RUN-DEFINE" not in replacements
    assert "_RTSCREEN.FIRST-OBJECT @" in _definition(source, "_RTSCREEN-RUN?")

    capture = _definition(source, "_RTSCREEN-CAPTURE")
    assert "RTE-RETAINED-CANCEL" in capture
    assert capture.index("RTE-RETAINED-BEGIN") < capture.index("RTE-RETAINED-SEAL")
    assert "RTE-RETAINED-DELTA =" in capture
    assert "_RTSCREEN-P-COUNT @ 0= AND" in capture


def test_prepare_retry_preserves_sealed_phase_while_publication_is_in_flight() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    for name, ready_phase, sealed_phase in (
        (
            "_RTSCREEN-PREPARE-START",
            "_RTSCREEN-PH-READY-START",
            "_RTSCREEN-PH-START-SEALED",
        ),
        (
            "_RTSCREEN-PREPARE-REVEAL",
            "_RTSCREEN-PH-READY-REVEAL",
            "_RTSCREEN-PH-REVEAL-SEALED",
        ),
        (
            "_RTSCREEN-PREPARE-DELTA",
            "_RTSCREEN-PH-READY-DELTA",
            "_RTSCREEN-PH-DELTA-SEALED",
        ),
    ):
        prepare = _definition(source, name)
        capture = prepare.index("_RTSCREEN-CAPTURE")
        seal = prepare.index(sealed_phase, capture)
        would_block = prepare.index(
            "DUP SCB-S-WOULD-BLOCK = IF EXIT THEN",
            seal,
        )
        recover = prepare.index(ready_phase, would_block)

        assert capture < seal < would_block < recover
        assert ready_phase not in prepare[:would_block]


def test_committed_snapshot_closes_hidden_start_race() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    different = _definition(source, "_RTSCREEN-DIFFERENT?")
    pending = _definition(source, "_RTSCREEN-PENDING!")
    accept_one = _definition(source, "_RTSCREEN-SNAPSHOT-ACCEPT-ONE")
    replacements = _definition(source, "_RTSCREEN-CAPTURE-REPLACEMENTS")
    sealed = _definition(source, "_RTSCREEN-STEP-SEALED")
    accept = _definition(source, "_RTSCREEN-STEP-ACCEPT")

    assert "SCR-FRONT@" not in source
    assert "SCR-GET" in different
    assert "_RTSCREEN.ITEMS-A @" in different
    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + @" in different
    assert "8 + !" in pending
    assert "DUP 8 + @ SWAP !" in accept_one
    assert replacements.index("_RTSCREEN-DIFFERENT?") < replacements.index(
        "_RTSCREEN-PENDING!"
    )
    pending_store = replacements.index("_RTSCREEN-PENDING!")
    assert pending_store < replacements.index("\n        IF", pending_store)
    assert "_RTSCREEN-PENDING!" in _definition(
        source, "_RTSCREEN-CAPTURE-START-BODY"
    )

    idle = sealed.index("RTE-UPDATE-IDLE")
    accepted_status = sealed.index("RTE-S-OK", idle)
    phase_publish = sealed.index("_RTSCREEN.PHASE !", accepted_status)
    assert idle < accepted_status < phase_publish
    rejected_status = sealed.index("RTE-S-STALE", phase_publish)
    stale_clear = sealed.index("RTE-RETAINED-CANCEL", rejected_status)
    rejected_phase = sealed.index("NIP R@ _RTSCREEN.PHASE !", rejected_status)
    assert phase_publish < rejected_status < stale_clear < rejected_phase
    assert sealed.index("SCB-S-OK 0 -1 EXIT", rejected_phase) > rejected_phase
    sealed_retry = sealed.index("RTE-UPDATE-SEALED")
    assert sealed.index("SCB-S-OK 0 -1 EXIT", sealed_retry) < idle
    assert "_RTSCREEN-SNAPSHOT-ACCEPT-ONE" not in sealed
    assert "_RTSCREEN-SNAPSHOT-ACCEPT-ONE" in accept
    assert "_RTSCREEN-S-BUDGET" in accept

    step = _definition(source, "RTSCREEN-STEP")
    for accepted_phase, rejected_phase in (
        ("_RTSCREEN-PH-ACCEPT-START", "_RTSCREEN-PH-READY-START"),
        ("_RTSCREEN-PH-ACCEPT-REVEAL", "_RTSCREEN-PH-READY-REVEAL"),
        ("_RTSCREEN-PH-ACCEPT-DELTA", "_RTSCREEN-PH-READY-DELTA"),
    ):
        assert f"{accepted_phase} {rejected_phase}" in step

    # CELL/front is A, hidden START captures B, then the back becomes A again.
    # Comparing to CELL/front would miss the reveal replacement.  The committed
    # rich snapshot correctly retains B until the reveal is accepted.
    cell_a = 0x0000000700000041
    cell_b = 0x0000000700000042
    committed = [cell_a]
    pending_snapshot = [cell_b]
    assert committed == [cell_a]  # START not accepted yet.
    committed = pending_snapshot.copy()  # accepted START settlement only.
    back_at_reveal = [cell_a]
    changed = [
        index
        for index, (back, rich) in enumerate(zip(back_at_reveal, committed))
        if back != rich
    ]
    assert changed == [0]
    pending_snapshot = back_at_reveal.copy()
    assert committed == [cell_b]  # rejected reveal does not advance it.
    assert [i for i, v in enumerate(back_at_reveal) if v != committed[i]] == [0]
    committed = pending_snapshot.copy()  # accepted reveal settlement only.
    assert committed == [cell_a]


def test_small_plane_has_exact_capacity_and_byte_oracle() -> None:
    cells = [
        Cell(0, 7, 0, 0),
        Cell(ord("A"), 1, 4, 0x81),  # bold survives; WIDE is representation state.
        Cell(0x1F642, 15, 0, 0),  # isolated wide scalar becomes U+FFFD.
        Cell(0x03BB, 46, 232, 0x08),
        Cell(0x0A, 196, 16, 0),  # control becomes U+FFFD.
        Cell(ord("Z"), 255, 8, 0x28),
    ]
    runs = _project_plane(
        cells,
        rows=2,
        cols=3,
        owner=7,
        generation=9,
        region=11,
        first_object=100,
    )

    assert [run.object_id for run in runs] == [100, 101, 102, 103, 104, 105]
    assert [(run.row, run.col) for run in runs] == [
        (0, 0),
        (0, 1),
        (0, 2),
        (1, 0),
        (1, 1),
        (1, 2),
    ]
    assert [run.text for run in runs] == [
        b" ",
        b"A",
        b"\xef\xbf\xbd",
        b"\xce\xbb",
        b"\xef\xbf\xbd",
        b"Z",
    ]
    assert runs[1].attrs == 0x01
    assert runs[3].foreground == 0x00FF00FF
    assert runs[3].background == 0x080808FF

    count = len(runs)
    assert count * PLAN_ITEM_BYTES == 720
    assert count * TEXT_CAPACITY == 24
    assert 1 + count == 7
    assert REGION_COPY_BYTES + count * _align8(RUN_COPY_FIXED + 4) == 840
    assert (
        UPDATE_ENVELOPE_BYTES
        + REGION_FRAME_BYTES
        + count * (RUN_FRAME_FIXED + 4)
        == 992
    )

    payloads = [_wire_payload(run) for run in runs]
    assert [len(payload) for payload in payloads] == [81, 81, 83, 82, 83, 81]
    first = struct.unpack("<QQQHHiQQIIII8BHHI", payloads[0][:-1])
    assert first[:8] == (7, 9, 100, 4, 1, 0, 11, 0)
    assert first[8:12] == (0, 0, 0x55555555, 0x7FFFFFFF)
    assert first[12:20] == (0xAA, 0xAA, 0xAA, 0xFF, 0, 0, 0, 0xFF)
    assert first[20:] == (0, 0, 1)
    assert payloads[0][-1:] == b" "

    last = struct.unpack("<QQQHHiQQIIII8BHHI", payloads[-1][:-1])
    assert last[2] == 105
    assert last[8:12] == (0xAAAAAAAA, 0x7FFFFFFF, U32_MAX, U32_MAX)
    assert payloads[-1][-1:] == b"Z"
