"""Focused pure checks for the physical Desktop acceptance runner."""

from __future__ import annotations

import json
import inspect
import re
import time
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest

import akashic_tui  # noqa: F401  Ensures the selected MegaPad tree is importable.
import rich_terminal_desktop_acceptance as acceptance_runner
from rich_terminal.pygame_view import (
    ControlHitTarget,
    ControlIdentity,
    PixelRect,
)
from rich_terminal.retained_scene import (
    ControlKind,
    ControlState,
    ObjectBounds,
    RGBA,
)
from rich_terminal.retained_view import (
    DisplayScope,
    GlyphRunDraw,
    MenuBarDraw,
    MenuDraw,
    MenuItemDraw,
    MenuSeparatorDraw,
    RetainedDrawPlane,
    RetainedRegionDraw,
)
from session import (
    TerminalCell,
    TerminalDisplayOffer,
    TerminalSnapshot,
)

from rich_terminal_desktop_acceptance import (
    AcceptedInputEvidence,
    DAYBOOK_ACCEPTANCE_TASK,
    DAYBOOK_FOCUS_MARKER,
    DAYBOOK_PROMPT_MARKER,
    DesktopAcceptanceJourney,
    PAD_ACCEPTANCE_TEXT,
    PAD_FOCUS_MARKER,
    PhysicalDesktopAcceptanceError,
    PresentedFrameEvidence,
    RichScreenProjection,
    reconstruct_retained_screen,
    write_acceptance_manifest,
)


UINT32_MAX = 0xFFFFFFFF
UINT64_MAX = 0xFFFFFFFFFFFFFFFF


def _performance_status_fixture() -> dict:
    return {
        "generation": 3,
        "steps": 12_345,
        "batches": 17,
        "revision": 9,
        "rich_terminal": {
            "machine_publications": 7,
            "machine_publication_bytes": 700,
            "frames": 5,
            "frame_bytes": 500,
            "frames_by_type": {"0x0101": 4, "0x0110": 1},
            "frame_bytes_by_type": {"0x0101": 444, "0x0110": 56},
            "decoder_buffered_bytes": 0,
        },
    }


def test_performance_status_snapshot_copies_exact_transport_counters() -> None:
    status = _performance_status_fixture()

    snapshot = acceptance_runner._performance_status_snapshot(status)

    assert snapshot == status
    status["rich_terminal"]["frames_by_type"]["0x0101"] = 99
    status["rich_terminal"]["frame_bytes_by_type"] = {}
    assert snapshot["rich_terminal"]["frames_by_type"]["0x0101"] == 4
    assert snapshot["rich_terminal"]["frame_bytes_by_type"] == {
        "0x0101": 444,
        "0x0110": 56,
    }

    missing_optional = _performance_status_fixture()
    del missing_optional["rich_terminal"]["frame_bytes_by_type"]
    assert acceptance_runner._performance_status_snapshot(missing_optional)[
        "rich_terminal"
    ]["frame_bytes_by_type"] is None


def test_performance_trace_writes_ordered_relative_events(tmp_path) -> None:
    now = [10_000]
    trace = acceptance_runner._PerformanceTrace(
        tmp_path,
        clock_ns=lambda: now[0],
    )
    now[0] = 10_025
    trace.mark("offer_observed", status=_performance_status_fixture(), offer_id=4)
    started_ns = trace.now()
    now[0] = 10_065
    trace.mark(
        "offer_acknowledged",
        started_ns=started_ns,
        offer_id=4,
        compose_duration_ns=11,
    )

    path = trace.write("pass")

    assert path == tmp_path / "performance-trace.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["schema"] == "akashic-rich-terminal-performance-v1"
    assert payload["normative"] is False
    assert payload["clock"] == "time.monotonic_ns"
    assert payload["origin_ns"] == 10_000
    assert payload["outcome"] == "pass"
    assert [event["sequence"] for event in payload["events"]] == [0, 1]
    assert [event["elapsed_ns"] for event in payload["events"]] == [25, 65]
    assert payload["events"][0]["counters"]["steps"] == 12_345
    assert payload["events"][1]["duration_ns"] == 40
    assert payload["events"][1]["compose_duration_ns"] == 11
    assert path.read_bytes().endswith(b"\n")


def test_performance_trace_write_failure_is_non_normative(tmp_path) -> None:
    missing_root = tmp_path / "missing"
    trace = acceptance_runner._PerformanceTrace(
        missing_root,
        clock_ns=lambda: 1,
    )
    trace.mark("acceptance_started")

    assert trace.write("failure") is None
    missing_root.mkdir()
    assert trace.write("failure") == missing_root / "performance-trace.json"


def test_hybrid_producer_diagnostic_schema_matches_the_forth_layout() -> None:
    source = (
        Path(acceptance_runner.__file__).resolve().parents[1]
        / "akashic/tui/rich-terminal/hybrid-screen-producer.f"
    ).read_text(encoding="utf-8")
    _pointer, cell_count, fields = acceptance_runner._GUEST_FAILURE_RECORDS[
        "hybrid_producer"
    ]

    assert re.search(r"(?m)^2088 CONSTANT RTHP-SIZE$", source)
    assert cell_count == 2088 // 8
    expected_offsets = {
        "phase": 120,
        "surface_generation": 152,
        "candidate_attempt": 160,
        "source_draw": 176,
        "source_record_bytes": 200,
        "source_text_bytes": 224,
        "claim_bytes": 328,
        "glyph_text_bytes": 432,
        "control_count": 440,
        "glyph_count": 448,
        "target_active_address": 1904,
        "target_pending_address": 1912,
        "active_draw": 1936,
        "source_directory_bytes": 1968,
        "document_count": 1976,
        "row_damage_address": 1984,
        "row_damage_bytes": 1992,
        "glyph_id_map_address": 2000,
        "glyph_id_map_bytes": 2008,
        "delta_plan_valid": 2016,
        "delta_plan_active_address": 2024,
        "delta_plan_pending_address": 2032,
        "delta_plan_active_draw": 2040,
        "delta_plan_pending_draw": 2048,
        "delta_plan_control_count": 2056,
        "delta_plan_glyph_count": 2064,
        "delta_plan_attempt": 2072,
        "delta_plan_source_generation": 2080,
    }
    assert {name: fields[name] * 8 for name in expected_offsets} == expected_offsets


def _low(index: int, extent: int) -> int:
    return (index * UINT32_MAX + extent - 1) // extent


def _high(index: int, extent: int) -> int:
    return ((index + 1) * UINT32_MAX) // extent


def _glyph_run(
    object_id: int,
    row: int,
    col: int,
    text: str,
    *,
    cols: int,
    rows: int,
) -> GlyphRunDraw:
    assert text
    return GlyphRunDraw(
        object_id,
        0,
        ObjectBounds(
            _low(col, cols),
            _low(row, rows),
            _high(col + len(text) - 1, cols),
            _high(row, rows),
        ),
        RGBA(255, 255, 255, 255),
        RGBA(0, 0, 0, 255),
        0,
        text,
    )


def _glyph_draws_outside(
    cols: int,
    rows: int,
    gaps: set[tuple[int, int]],
) -> tuple[GlyphRunDraw, ...]:
    """Build coalesced full-screen fixture glyphs outside exact claim gaps."""

    draws: list[GlyphRunDraw] = []
    object_id = 1
    for row in range(rows):
        col = 0
        while col < cols:
            while col < cols and (col, row) in gaps:
                col += 1
            start = col
            while col < cols and (col, row) not in gaps:
                col += 1
            if start < col:
                text = "." * (col - start)
                draws.append(
                    _glyph_run(
                        object_id,
                        row,
                        start,
                        text,
                        cols=cols,
                        rows=rows,
                    )
                )
                object_id += 1
    return tuple(draws)


def _canonical_pad_file_entries() -> tuple[
    MenuItemDraw | MenuSeparatorDraw,
    ...,
]:
    ordinary = ControlState.VISIBLE | ControlState.ENABLED
    selected = ordinary | ControlState.SELECTED
    visible = ControlState.VISIBLE
    return (
        MenuItemDraw(10_100, selected, 0, "New File", "Ctrl+N"),
        MenuItemDraw(10_101, ordinary, 1, "Open File", "Ctrl+O"),
        MenuSeparatorDraw(10_102, visible, 2),
        MenuItemDraw(10_103, ordinary, 3, "Save", "Ctrl+S"),
        MenuItemDraw(10_104, ordinary, 4, "Save As", "Ctrl+Shift+S"),
        MenuItemDraw(10_105, ordinary, 5, "Save All", ""),
        MenuSeparatorDraw(10_106, visible, 6),
        MenuItemDraw(10_107, ordinary, 7, "Close Tab", "Ctrl+W"),
        MenuItemDraw(10_108, ordinary, 8, "Close All", ""),
        MenuSeparatorDraw(10_109, visible, 9),
        MenuItemDraw(10_110, ordinary, 10, "Quit", "Ctrl+Q"),
    )


def _offer(
    text: str,
    *,
    offer_id: int = 1,
    pad_menu: bool = False,
    file_open: bool = False,
) -> TerminalDisplayOffer:
    lines = text.split("\n")
    rows = len(lines)
    cols = len(lines[0])
    assert rows > 0 and cols > 0
    assert all(len(line) == cols for line in lines)
    cells = tuple(
        tuple(TerminalCell(char, (255, 255, 255), (0, 0, 0), 0) for char in line)
        for line in lines
    )
    snapshot = TerminalSnapshot(cols, rows, cells, 0, 0, True, True)
    draws = []
    object_id = 1
    for row, line in enumerate(lines):
        draws.append(
            _glyph_run(
                object_id,
                row,
                0,
                line,
                cols=cols,
                rows=rows,
            )
        )
        object_id += 1
    if pad_menu:
        file_state = ControlState.VISIBLE | ControlState.ENABLED
        file_entries = ()
        if file_open:
            file_state |= ControlState.OPEN | ControlState.SELECTED
            file_entries = _canonical_pad_file_entries()
        menus = tuple(
            MenuDraw(
                10_001 + order,
                file_state
                if label == "File"
                else ControlState.VISIBLE | ControlState.ENABLED,
                order,
                label,
                file_entries if label == "File" else (),
            )
            for order, label in enumerate(acceptance_runner.PAD_MENU_SIGNATURE)
        )
    else:
        menus = (
            MenuDraw(
                10_001,
                ControlState.VISIBLE | ControlState.ENABLED,
                0,
                "File",
                (),
            ),
        )
    draws.append(
        MenuBarDraw(
            10_000,
            ControlState.VISIBLE | ControlState.ENABLED,
            0,
            0,
            ObjectBounds(
                _low(0, cols),
                _low(0, rows),
                _high(cols - 1, cols),
                _high(0, rows),
            ),
            menus,
        )
    )
    plane = RetainedDrawPlane(
        True,
        True,
        (
            RetainedRegionDraw(
                1,
                1,
                1,
                0,
                0,
                cols,
                rows,
                0,
                False,
                tuple(draws),
            ),
        ),
    )
    scope = DisplayScope(1, 1, 0, offer_id, 0, offer_id, offer_id)
    return TerminalDisplayOffer(offer_id, scope, snapshot, plane)


def _projection(text: str) -> RichScreenProjection:
    lines = tuple(text.split("\n"))
    return RichScreenProjection(
        max(map(len, lines)),
        len(lines),
        lines,
        sum(map(len, lines)),
        menu_bar_count=len(acceptance_runner.DESKTOP_MENU_SIGNATURES),
        menu_signatures=acceptance_runner.DESKTOP_MENU_SIGNATURES,
    )


def _desktop_projection(
    *placements: tuple[int, int, str],
) -> RichScreenProjection:
    lines = [
        " " * acceptance_runner.CANONICAL_DESKTOP_COLS
        for _ in range(acceptance_runner.CANONICAL_DESKTOP_ROWS)
    ]
    for row, col, value in placements:
        line = lines[row]
        lines[row] = line[:col] + value + line[col + len(value) :]
    return _projection("\n".join(lines))


def _daybook_projection(*, task_visible: bool) -> RichScreenProjection:
    placements = [(0, 190, DAYBOOK_FOCUS_MARKER)]
    if task_visible:
        placements.append((5, 190, DAYBOOK_ACCEPTANCE_TASK))
    return _desktop_projection(*placements)


def _handoff_projection(*, pad_tile: bool) -> RichScreenProjection:
    placements = [(0, 1, PAD_FOCUS_MARKER)]
    if pad_tile:
        placements.extend(
            (
                (4, 4, acceptance_runner.DAYBOOK_SHARED_SOURCE_MARKER),
                (5, 4, DAYBOOK_ACCEPTANCE_TASK),
            )
        )
    else:
        placements.extend(
            (
                (50, 190, acceptance_runner.DAYBOOK_SHARED_SOURCE_MARKER),
                (51, 190, DAYBOOK_ACCEPTANCE_TASK),
            )
        )
    return _desktop_projection(*placements)


def _uidl_attribute(source: str, name: str) -> str:
    match = re.search(
        rf"\b{re.escape(name)}=(?:\"([^\"]*)\"|([^\s/>]+))",
        source,
    )
    assert match is not None, (name, source)
    return next(value for value in match.groups() if value is not None)


def _pad_file_target(offer: TerminalDisplayOffer) -> ControlHitTarget:
    region = offer.retained.regions[0]
    return ControlHitTarget(
        ControlIdentity(region.owner_id, region.owner_generation, 10_001),
        ControlKind.MENU,
        PixelRect(2, 2, 42, 20),
    )


def _acknowledged_hit_state(
    offer: TerminalDisplayOffer,
    *targets: ControlHitTarget,
    generation: int = 9,
):
    state = acceptance_runner._RetainedDisplayState()
    state.stage(offer, generation)
    state.stage_frame_hit_map(offer, targets)
    assert state.finish_presentation(
        {
            "status": "presented",
            "presented": True,
            "revision": offer.scope.model_revision,
        }
    ) == offer.scope.model_revision
    return state, (offer.offer_id, offer.scope)


def test_full_screen_projection_reconstructs_coalesced_glyphs_and_menus() -> None:
    offer = _offer("AB\nCD")
    projection = reconstruct_retained_screen(offer)
    assert projection.cols == 2
    assert projection.rows == 2
    assert projection.draw_count == 3
    assert projection.glyph_cell_count == 4
    assert projection.menu_bar_count == 1
    assert projection.lines == ("AB", "CD")
    assert projection.semantic_lines == ("File",)
    assert projection.text == "AB\nCD\nFile"

    missing = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    offer.retained.regions[0],
                    draws=(
                        offer.retained.regions[0].draws[0],
                        offer.retained.regions[0].draws[-1],
                    ),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="uncovered"):
        reconstruct_retained_screen(missing)

    hidden = replace(
        offer,
        retained=RetainedDrawPlane(True, False, ()),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="visible initialized"):
        reconstruct_retained_screen(hidden)


def test_projection_rejects_invalid_run_coverage_and_requires_semantics() -> None:
    offer = _offer("AB\nCD")
    region = offer.retained.regions[0]
    first, second, menu = region.draws

    mismatch = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(replace(first, text="A"), second, menu)),),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="geometry"):
        reconstruct_retained_screen(mismatch)

    overlap = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(first, second, replace(second, object_id=99), menu),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="overlaps"):
        reconstruct_retained_screen(overlap)

    crossing = replace(
        first,
        bounds=ObjectBounds(
            first.bounds.left,
            first.bounds.top,
            first.bounds.right,
            second.bounds.bottom,
        ),
    )
    crossed = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(crossing, second, menu)),),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="geometry"):
        reconstruct_retained_screen(crossed)

    no_menu = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(first, second)),),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="semantic menu"):
        reconstruct_retained_screen(no_menu)


def test_semantic_menu_bounds_may_complete_glyph_coverage() -> None:
    offer = _offer("AB\nCD")
    region = offer.retained.regions[0]
    _first, second, menu = region.draws
    semantic_first_row = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(second, menu)),),
        ),
    )
    projection = reconstruct_retained_screen(semantic_first_row)
    assert projection.lines == ("  ", "CD")
    assert projection.semantic_lines == ("File",)
    assert projection.glyph_cell_count == 2


def test_open_pad_popup_requires_its_exact_source_claim_gap() -> None:
    cols = 20
    rows = 15
    offer = _offer(
        "\n".join("." * cols for _ in range(rows)),
        pad_menu=True,
        file_open=True,
    )
    region = offer.retained.regions[0]
    menu = region.draws[-1]
    exact_draws = [_glyph_run(1, 0, 0, "." * cols, cols=cols, rows=rows)]
    object_id = 2
    for row in range(1, 14):
        exact_draws.append(
            _glyph_run(object_id, row, 0, ".", cols=cols, rows=rows)
        )
        object_id += 1
        exact_draws.append(
            _glyph_run(
                object_id,
                row,
                14,
                "." * 6,
                cols=cols,
                rows=rows,
            )
        )
        object_id += 1
    exact_draws.append(
        _glyph_run(object_id, 14, 0, "." * cols, cols=cols, rows=rows)
    )
    exact_draws.append(menu)
    exact_gap = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=tuple(exact_draws)),),
        ),
    )
    projection = reconstruct_retained_screen(exact_gap)
    assert projection.renderer_owned_gap_cells == 13 * 13
    assert projection.menu_signatures == (acceptance_runner.PAD_MENU_SIGNATURE,)

    first_gap_row = exact_draws[1]
    extra_gap = replace(
        exact_gap,
        retained=replace(
            exact_gap.retained,
            regions=(
                replace(
                    region,
                    draws=tuple(
                        draw for draw in exact_draws if draw is not first_gap_row
                    ),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exact semantic popup"):
        reconstruct_retained_screen(extra_gap)

    closed_menu = replace(
        menu,
        menus=tuple(
            replace(
                item,
                state=item.state & ~ControlState.OPEN,
                entries=(),
            )
            if item.label == "File"
            else item
            for item in menu.menus
        ),
    )
    closed_gap = replace(
        exact_gap,
        retained=replace(
            exact_gap.retained,
            regions=(
                replace(
                    region,
                    draws=tuple(exact_draws[:-1]) + (closed_menu,),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exact semantic popup"):
        reconstruct_retained_screen(closed_gap)

    undersized = _offer(
        "\n".join("." * 14 for _ in range(13)),
        pad_menu=True,
        file_open=True,
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="does not fit"):
        reconstruct_retained_screen(undersized)


def test_open_nonfirst_menu_uses_uidl_title_offset_and_byte_width() -> None:
    cols = 32
    rows = 10
    ordinary = ControlState.VISIBLE | ControlState.ENABLED
    opened = ordinary | ControlState.OPEN | ControlState.SELECTED
    entries = (
        MenuItemDraw(10_200, ordinary | ControlState.SELECTED, 0, "É", ""),
        MenuSeparatorDraw(10_201, ControlState.VISIBLE, 1),
    )
    menu_bar = MenuBarDraw(
        10_000,
        ordinary,
        0,
        0,
        ObjectBounds(
            _low(0, cols),
            _low(0, rows),
            _high(cols - 1, cols),
            _high(0, rows),
        ),
        (
            MenuDraw(10_001, ordinary, 0, "Fïle", ()),
            MenuDraw(10_002, opened, 1, "Edit", entries),
        ),
    )
    # UIDL-TUI advances by the five UTF-8 bytes in "Fïle", then two
    # padding cells.  The two-byte item label makes a six-cell popup.
    expected_gap = {
        (col, row)
        for row in range(1, 5)
        for col in range(8, 14)
    }
    offer = _offer("\n".join("." * cols for _ in range(rows)))
    region = offer.retained.regions[0]
    exact = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=_glyph_draws_outside(cols, rows, expected_gap)
                    + (menu_bar,),
                ),
            ),
        ),
    )
    projection = reconstruct_retained_screen(exact)
    assert projection.renderer_owned_gap_cells == 6 * 4

    shifted_gap = {(col + 1, row) for col, row in expected_gap}
    shifted = replace(
        exact,
        retained=replace(
            exact.retained,
            regions=(
                replace(
                    region,
                    draws=_glyph_draws_outside(cols, rows, shifted_gap)
                    + (menu_bar,),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exact semantic popup"):
        reconstruct_retained_screen(shifted)


def test_source_claim_gate_accepts_two_simultaneously_open_menu_bars() -> None:
    cols = 40
    rows = 15
    ordinary = ControlState.VISIBLE | ControlState.ENABLED
    opened = ordinary | ControlState.OPEN | ControlState.SELECTED
    bar_one = MenuBarDraw(
        20_000,
        ordinary,
        0,
        0,
        ObjectBounds(
            _low(0, cols),
            _low(0, rows),
            _high(19, cols),
            _high(0, rows),
        ),
        (
            MenuDraw(
                20_001,
                opened,
                0,
                "File",
                (MenuItemDraw(20_100, ordinary, 0, "One", ""),),
            ),
        ),
    )
    bar_two = MenuBarDraw(
        30_000,
        ordinary,
        0,
        0,
        ObjectBounds(
            _low(20, cols),
            _low(7, rows),
            _high(39, cols),
            _high(7, rows),
        ),
        (
            MenuDraw(30_001, ordinary, 0, "A", ()),
            MenuDraw(
                30_002,
                opened,
                1,
                "Tools",
                (MenuItemDraw(30_100, ordinary, 0, "Inspect", ""),),
            ),
        ),
    )
    first_gap = {
        (col, row)
        for row in range(1, 4)
        for col in range(1, 8)
    }
    second_gap = {
        (col, row)
        for row in range(8, 11)
        for col in range(24, 35)
    }
    all_gaps = first_gap | second_gap
    offer = _offer("\n".join("." * cols for _ in range(rows)))
    region = offer.retained.regions[0]
    exact = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=_glyph_draws_outside(cols, rows, all_gaps)
                    + (bar_one, bar_two),
                ),
            ),
        ),
    )
    projection = reconstruct_retained_screen(exact)
    assert projection.renderer_owned_gap_cells == len(all_gaps)
    assert projection.menu_bar_count == 2


@pytest.mark.parametrize("missing", ("menu", "row"))
def test_popup_source_claim_refuses_detectably_incomplete_visible_order(
    missing: str,
) -> None:
    ordinary = ControlState.VISIBLE | ControlState.ENABLED
    opened = ordinary | ControlState.OPEN
    row_order = 1 if missing == "row" else 0
    menu_order = 1 if missing == "menu" else 0
    menu = MenuDraw(
        40_001,
        opened,
        menu_order,
        "File",
        (MenuItemDraw(40_100, ordinary, row_order, "Open", ""),),
    )
    menu_bar = MenuBarDraw(
        40_000,
        ordinary,
        0,
        0,
        ObjectBounds(_low(0, 20), _low(0, 8), _high(19, 20), _high(0, 8)),
        (menu,),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="source-order"):
        acceptance_runner._menu_popup_source_claim(
            menu_bar,
            menu,
            bar_left=0,
            bar_right=20,
            bar_top=0,
            screen_rows=8,
        )


def test_canonical_menu_aggregate_requires_each_visible_applet_once() -> None:
    projection = _projection("READY")
    acceptance_runner._require_canonical_menu_aggregate(projection)

    missing = replace(
        projection,
        menu_signatures=projection.menu_signatures[:-1],
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="every canonical"):
        acceptance_runner._require_canonical_menu_aggregate(missing)

    duplicate = replace(
        projection,
        menu_signatures=projection.menu_signatures
        + (acceptance_runner.PAD_MENU_SIGNATURE,),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="every canonical"):
        acceptance_runner._require_canonical_menu_aggregate(duplicate)

    unexpected = replace(
        projection,
        menu_bar_count=projection.menu_bar_count + 1,
        menu_signatures=projection.menu_signatures
        + (("Unexpected",),),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="unexpected applet"):
        acceptance_runner._require_canonical_menu_aggregate(unexpected)

    journey = DesktopAcceptanceJourney(("READY",))
    journey.after_present(
        _offer("X", offer_id=1, pad_menu=True),
        1,
        projection,
        lambda *_args: "progress",
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="every canonical"):
        journey.after_present(
            _offer("X", offer_id=2, pad_menu=True),
            1,
            missing,
            lambda *_args: "progress",
        )


def test_open_pad_file_requires_normal_uidl_selection_state() -> None:
    offer = _offer("READY", offer_id=3, pad_menu=True, file_open=True)
    assert acceptance_runner._pad_file_menu_is_open(offer)
    region = offer.retained.regions[0]
    *glyphs, menu_bar = region.draws
    file_menu, *other_menus = menu_bar.menus

    unselected_menu = replace(
        file_menu,
        state=file_menu.state & ~ControlState.SELECTED,
    )
    wrong_menu_state = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(
                        *glyphs,
                        replace(
                            menu_bar,
                            menus=(unselected_menu, *other_menus),
                        ),
                    ),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="selected state"):
        acceptance_runner._pad_file_menu_is_open(wrong_menu_state)

    first, *remaining = file_menu.entries
    unselected_first = replace(
        first,
        state=first.state & ~ControlState.SELECTED,
    )
    wrong_item_state = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(
                        *glyphs,
                        replace(
                            menu_bar,
                            menus=(
                                replace(
                                    file_menu,
                                    entries=(unselected_first, *remaining),
                                ),
                                *other_menus,
                            ),
                        ),
                    ),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="order and state"):
        acceptance_runner._pad_file_menu_is_open(wrong_item_state)


def test_pad_file_acceptance_signature_matches_the_ordinary_uidl_source() -> None:
    uidl = (
        Path(acceptance_runner.__file__).resolve().parents[1]
        / "akashic/tui/applets/pad/pad.uidl"
    ).read_text(encoding="utf-8")
    file_menu = uidl.split("<menu label=File>", 1)[1].split("</menu>", 1)[0]
    signature = []
    for kind, attributes in re.findall(
        r"<(item|separator)\b([^>]*)/>",
        file_menu,
    ):
        if kind == "separator":
            signature.append(("SEPARATOR", "", ""))
            continue
        shortcut = (
            _uidl_attribute(attributes, "key")
            if re.search(r"\bkey=", attributes)
            else ""
        )
        signature.append(
            ("ITEM", _uidl_attribute(attributes, "text"), shortcut)
        )

    assert tuple(signature) == acceptance_runner.PAD_FILE_ENTRY_SIGNATURE


def test_open_pad_file_signature_failure_reports_the_actual_source_values() -> None:
    offer = _offer("READY", offer_id=3, pad_menu=True, file_open=True)
    region = offer.retained.regions[0]
    *glyphs, menu_bar = region.draws
    file_menu, *other_menus = menu_bar.menus
    first, *remaining = file_menu.entries
    wrong_label = replace(first, label="New_File")
    mismatched = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(
                        *glyphs,
                        replace(
                            menu_bar,
                            menus=(
                                replace(
                                    file_menu,
                                    entries=(wrong_label, *remaining),
                                ),
                                *other_menus,
                            ),
                        ),
                    ),
                ),
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match=r"actual=.*New_File",
    ):
        acceptance_runner._pad_file_menu_is_open(mismatched)


def test_physical_event_pump_routes_mouse_without_discarding_action_delay_input(
) -> None:
    class Events:
        @staticmethod
        def get():
            return [
                SimpleNamespace(type=2, pos=(12, 8)),
                SimpleNamespace(type=3, button=1, pos=(12, 8)),
                SimpleNamespace(type=4, button=1, pos=(12, 8), mod=0x10),
                SimpleNamespace(type=5),
            ]

    class Pygame:
        QUIT = 1
        MOUSEMOTION = 2
        MOUSEBUTTONDOWN = 3
        MOUSEBUTTONUP = 4
        WINDOWFOCUSLOST = 5
        WINDOWFOCUSGAINED = 6
        KMOD_SHIFT = 0x10
        KMOD_CTRL = 0x20
        KMOD_ALT = 0x40
        KMOD_GUI = 0x80
        KMOD_CAPS = 0x100
        KMOD_NUM = 0x200
        event = Events()

    class Pointer:
        def __init__(self):
            self.calls = []

        def move(self, position, extent):
            self.calls.append(("move", position, extent))

        def left_down(self, position, extent):
            self.calls.append(("down", position, extent))

        def left_up(self, position, extent, *, modifiers):
            self.calls.append(("up", position, extent, modifiers))

        def clear(self):
            self.calls.append(("clear",))

    class Keyboard:
        resets = 0
        flushes = 0

        def reset(self):
            self.resets += 1

        def flush_pending(self):
            self.flushes += 1

    pointer = Pointer()
    keyboard = Keyboard()
    extent = (2800, 1680)

    assert acceptance_runner._pump_physical_viewer_events(
        Pygame,
        pointer,
        keyboard,
        extent,
        closing_is_error=True,
    )
    assert pointer.calls == [
        ("move", (12, 8), extent),
        ("down", (12, 8), extent),
        ("up", (12, 8), extent, 1),
        ("clear",),
    ]
    assert keyboard.resets == 1
    assert keyboard.flushes == 1


def test_manual_pointer_trace_records_exact_target_and_backpressure_result(
    tmp_path,
) -> None:
    class Events:
        items = []

        @classmethod
        def get(cls):
            return list(cls.items)

    class Pygame:
        QUIT = 1
        MOUSEMOTION = 2
        MOUSEBUTTONDOWN = 3
        MOUSEBUTTONUP = 4
        WINDOWFOCUSLOST = 5
        WINDOWFOCUSGAINED = 6
        KMOD_SHIFT = 0x10
        KMOD_CTRL = 0x20
        KMOD_ALT = 0x40
        KMOD_GUI = 0x80
        KMOD_CAPS = 0x100
        KMOD_NUM = 0x200
        event = Events

    class Client:
        def __init__(self):
            self.statuses = ["backpressured", "progress"]

        def request(self, method, **params):
            assert method == "send_control_event"
            return {"status": self.statuses.pop(0)}

    now = [1_000]
    trace = acceptance_runner._PerformanceTrace(
        tmp_path,
        clock_ns=lambda: now.__setitem__(0, now[0] + 1) or now[0],
    )
    traced_client = acceptance_runner._ManualInputTraceClient(Client(), trace)
    offer = _offer("READY", offer_id=7, pad_menu=True)
    target = _pad_file_target(offer)
    display_state, display_ack = _acknowledged_hit_state(offer, target)
    keyboard = acceptance_runner._GuestKeyboardForwarder(
        Pygame,
        traced_client,
        generation=9,
        display_required=True,
    )
    keyboard.acknowledge_display_offer(*display_ack)
    pointer = acceptance_runner._SemanticPointerInteractor(
        display_state,
        keyboard,
    )
    Events.items = [
        SimpleNamespace(type=Pygame.MOUSEBUTTONDOWN, button=1, pos=(12, 8)),
        SimpleNamespace(
            type=Pygame.MOUSEBUTTONUP,
            button=1,
            pos=(12, 8),
            mod=Pygame.KMOD_SHIFT,
        ),
    ]

    assert acceptance_runner._pump_physical_viewer_events(
        Pygame,
        pointer,
        keyboard,
        (100, 80),
        closing_is_error=True,
        trace=trace,
    )

    events = trace.events
    assert [item["event"] for item in events] == [
        "manual_pointer_down",
        "manual_input_rpc",
        "manual_pointer_up",
        "manual_input_rpc",
    ]
    expected_identity = {
        "owner_id": target.identity.owner_id,
        "owner_generation": target.identity.owner_generation,
        "control_id": target.identity.control_id,
    }
    assert events[0]["semantic_target"] == expected_identity
    assert events[0]["result"] == "targeted"
    assert events[1]["semantic_target"] == expected_identity
    assert events[1]["result"] == "backpressured"
    assert events[2]["pressed_target"] == expected_identity
    assert events[2]["semantic_target"] == expected_identity
    assert events[2]["result"] == "rpc_submitted"
    assert events[2]["pending_events"] == 1
    assert events[3]["result"] == "progress"
    assert keyboard.pending_events == 0


def test_manual_pointer_trace_names_offer_supersession_drop_reason(
    tmp_path,
) -> None:
    class Pygame:
        KMOD_SHIFT = 0x10
        KMOD_CTRL = 0x20
        KMOD_ALT = 0x40
        KMOD_GUI = 0x80
        KMOD_CAPS = 0x100
        KMOD_NUM = 0x200

    class Client:
        @staticmethod
        def request(method, **params):
            return {"status": "backpressured"}

    trace = acceptance_runner._PerformanceTrace(tmp_path)
    traced_client = acceptance_runner._ManualInputTraceClient(Client(), trace)
    offer = _offer("READY", offer_id=7, pad_menu=True)
    target = _pad_file_target(offer)
    display_state, display_ack = _acknowledged_hit_state(offer, target)
    keyboard = acceptance_runner._GuestKeyboardForwarder(
        Pygame,
        traced_client,
        generation=9,
        display_required=True,
    )
    keyboard.acknowledge_display_offer(*display_ack)
    pointer = acceptance_runner._SemanticPointerInteractor(
        display_state,
        keyboard,
    )
    down = SimpleNamespace(type=3, button=1, pos=(12, 8))
    up = SimpleNamespace(type=4, button=1, pos=(12, 8), mod=0)
    Pygame.MOUSEMOTION = 2
    Pygame.MOUSEBUTTONDOWN = 3
    Pygame.MOUSEBUTTONUP = 4
    Pygame.WINDOWFOCUSLOST = 5
    Pygame.WINDOWFOCUSGAINED = 6

    assert acceptance_runner._dispatch_semantic_pointer_event(
        Pygame,
        pointer,
        keyboard,
        down,
        (100, 80),
        trace=trace,
    )
    assert acceptance_runner._dispatch_semantic_pointer_event(
        Pygame,
        pointer,
        keyboard,
        up,
        (100, 80),
        trace=trace,
    )
    assert keyboard.pending_events == 1

    pending_before = keyboard.pending_events
    keyboard.begin_display_offer()
    acceptance_runner._trace_pending_input_drop(
        trace,
        keyboard,
        pending_before,
        reason="new_display_offer",
        offer_id=8,
    )

    dropped = trace.events[-1]
    assert dropped["event"] == "manual_input_dropped"
    assert dropped["reason"] == "new_display_offer"
    assert dropped["dropped_events"] == 1
    assert dropped["pending_before"] == 1
    assert dropped["pending_after"] == 0
    assert dropped["offer_id"] == 8


def test_pad_file_activation_uses_exact_acknowledged_hit_identity() -> None:
    offer = _offer("READY", offer_id=7, pad_menu=True)
    target = _pad_file_target(offer)
    display_state, display_ack = _acknowledged_hit_state(offer, target)
    requests = []

    class Client:
        def request(self, method, **params):
            requests.append((method, params))
            return {"status": "progress", "accepted_events": 1}

    status, evidence = acceptance_runner._request_acceptance_input(
        Client(),
        "activate_pad_file_menu",
        acceptance_runner.PAD_FILE_MENU_EVIDENCE,
        offer,
        9,
        display_state=display_state,
        display_ack=display_ack,
    )
    assert status == "progress"
    assert requests == [
        (
            "send_control_event",
            {
                "generation": 9,
                "display_offer_id": offer.offer_id,
                "display_scope": acceptance_runner.display_scope_to_wire(
                    offer.scope
                ),
                "owner_id": target.identity.owner_id,
                "owner_generation": target.identity.owner_generation,
                "control_id": target.identity.control_id,
                "modifiers": 0,
            },
        )
    ]
    assert evidence is not None
    assert evidence.method == "send_control_event"
    assert evidence.semantic_target == {
        "owner_id": target.identity.owner_id,
        "owner_generation": target.identity.owner_generation,
        "control_id": target.identity.control_id,
        "kind": "MENU",
        "label": acceptance_runner.PAD_FILE_MENU_EVIDENCE,
        "pixel_rect": {
            "left": target.rect.left,
            "top": target.rect.top,
            "right": target.rect.right,
            "bottom": target.rect.bottom,
        },
    }
    assert evidence.to_dict()["semantic_target"] == evidence.semantic_target


def test_pad_file_activation_preserves_zero_acceptance_backpressure() -> None:
    offer = _offer("READY", offer_id=8, pad_menu=True)
    target = _pad_file_target(offer)
    display_state, display_ack = _acknowledged_hit_state(offer, target)

    class Client:
        def request(self, method, **params):
            assert method == "send_control_event"
            return {"status": "backpressured", "accepted_events": 0}

    status, evidence = acceptance_runner._request_acceptance_input(
        Client(),
        "activate_pad_file_menu",
        acceptance_runner.PAD_FILE_MENU_EVIDENCE,
        offer,
        9,
        display_state=display_state,
        display_ack=display_ack,
    )
    assert status == "backpressured"
    assert evidence is None


def test_pad_file_activation_rejects_unacknowledged_ambiguous_or_occluded_hits(
) -> None:
    offer = _offer("READY", offer_id=4, pad_menu=True)
    target = _pad_file_target(offer)

    region = offer.retained.regions[0]
    *glyphs, menu_bar = region.draws
    file_menu, *other_menus = menu_bar.menus
    selected_closed = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(
                        *glyphs,
                        replace(
                            menu_bar,
                            menus=(
                                replace(
                                    file_menu,
                                    state=(
                                        file_menu.state
                                        | ControlState.SELECTED
                                    ),
                                ),
                                *other_menus,
                            ),
                        ),
                    ),
                ),
            ),
        ),
    )
    selected_target = _pad_file_target(selected_closed)
    selected_state, selected_ack = _acknowledged_hit_state(
        selected_closed,
        selected_target,
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exact closed"):
        acceptance_runner._pad_file_hit_target(
            selected_closed,
            selected_state,
            selected_ack,
        )

    unacknowledged = acceptance_runner._RetainedDisplayState()
    unacknowledged.stage(offer, 3)
    unacknowledged.stage_frame_hit_map(offer, (target,))
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exact acknowledged"):
        acceptance_runner._pad_file_hit_target(
            offer,
            unacknowledged,
            (offer.offer_id, offer.scope),
        )

    acknowledged, _ack = _acknowledged_hit_state(offer, target)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exact acknowledged"):
        acceptance_runner._pad_file_hit_target(
            offer,
            acknowledged,
            (offer.offer_id - 1, offer.scope),
        )

    ambiguous, ambiguous_ack = _acknowledged_hit_state(offer, target, target)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="one Pad File"):
        acceptance_runner._pad_file_hit_target(
            offer,
            ambiguous,
            ambiguous_ack,
        )

    occluding = ControlHitTarget(
        ControlIdentity(1, 1, 99_999),
        ControlKind.MENU,
        target.rect,
    )
    occluded, occluded_ack = _acknowledged_hit_state(
        offer,
        target,
        occluding,
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="painter-order"):
        acceptance_runner._pad_file_hit_target(
            offer,
            occluded,
            occluded_ack,
        )


def test_open_pad_file_popup_requires_exact_enabled_item_hit_map() -> None:
    offer = _offer("READY", offer_id=5, pad_menu=True, file_open=True)
    region = offer.retained.regions[0]
    menu_bar = region.draws[-1]
    file_menu = menu_bar.menus[0]
    item_entries = tuple(
        entry
        for entry in file_menu.entries
        if isinstance(entry, MenuItemDraw)
    )
    title_target = _pad_file_target(offer)
    item_targets = tuple(
        ControlHitTarget(
            ControlIdentity(
                region.owner_id,
                region.owner_generation,
                entry.control_id,
            ),
            ControlKind.MENU_ITEM,
            PixelRect(4, 24 + index * 20, 94, 42 + index * 20),
        )
        for index, entry in enumerate(item_entries)
    )
    state, display_ack = _acknowledged_hit_state(
        offer,
        title_target,
        *item_targets,
    )
    validated = acceptance_runner._require_pad_file_popup_hits(
        offer,
        state,
        display_ack,
    )
    assert validated == (title_target, *item_targets)

    class Client:
        def request(self, method, **params):
            assert method == "send_key"
            assert params["key"] == "escape"
            return {"status": "progress", "accepted_events": 1}

    status, evidence = acceptance_runner._request_acceptance_input(
        Client(),
        "send_key",
        "escape",
        offer,
        9,
        display_state=state,
        display_ack=display_ack,
    )
    assert status == "progress"
    assert evidence is not None
    assert evidence.method == "send_key"
    assert evidence.semantic_target is not None
    assert evidence.semantic_target["kind"] == "MENU_POPUP"
    assert evidence.semantic_target["label"] == (
        acceptance_runner.PAD_FILE_MENU_EVIDENCE
    )
    semantic_targets = evidence.semantic_target["targets"]
    assert isinstance(semantic_targets, list)
    assert [target["label"] for target in semantic_targets] == [
        "File",
        *(entry.label for entry in item_entries),
    ]
    assert [target["control_id"] for target in semantic_targets] == [
        title_target.identity.control_id,
        *(target.identity.control_id for target in item_targets),
    ]

    missing, missing_ack = _acknowledged_hit_state(
        offer,
        title_target,
        *item_targets[:-1],
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exactly match"):
        acceptance_runner._require_pad_file_popup_hits(
            offer,
            missing,
            missing_ack,
        )

    duplicate, duplicate_ack = _acknowledged_hit_state(
        offer,
        title_target,
        item_targets[0],
        *item_targets,
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exactly match"):
        acceptance_runner._require_pad_file_popup_hits(
            offer,
            duplicate,
            duplicate_ack,
        )

    swapped, swapped_ack = _acknowledged_hit_state(
        offer,
        title_target,
        item_targets[1],
        item_targets[0],
        *item_targets[2:],
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="semantic painter"):
        acceptance_runner._require_pad_file_popup_hits(
            offer,
            swapped,
            swapped_ack,
        )

    with pytest.raises(PhysicalDesktopAcceptanceError, match="exact acknowledged"):
        acceptance_runner._require_pad_file_popup_hits(
            offer,
            state,
            (offer.offer_id - 1, offer.scope),
        )

    occluding = ControlHitTarget(
        ControlIdentity(region.owner_id, region.owner_generation, 99_999),
        ControlKind.MENU,
        item_targets[0].rect,
    )
    occluded, occluded_ack = _acknowledged_hit_state(
        offer,
        title_target,
        *item_targets,
        occluding,
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="painter-order"):
        acceptance_runner._require_pad_file_popup_hits(
            offer,
            occluded,
            occluded_ack,
        )


def test_physical_runner_stages_hits_from_the_exact_composited_frame() -> None:
    source = inspect.getsource(acceptance_runner.run_physical_desktop_acceptance)
    geometry_index = source.index("_require_canonical_desktop_geometry(")
    draw_index = source.index("def draw_frame()")
    compose_index = source.index("compose_terminal_frame_result(", draw_index)
    stage_index = source.index("display_state.stage_frame_hit_map(", compose_index)
    present_index = source.index("presentation = draw_flip_and_present(", stage_index)
    finish_index = source.index("display_state.finish_presentation(", present_index)
    ack_index = source.index("keyboard.acknowledge_display_offer(", finish_index)
    journey_index = source.index("journey.after_present(", ack_index)

    assert "control_font=chrome_font" in source[compose_index:stage_index]
    assert "frame_result.hit_targets" in source[stage_index:present_index]
    assert (
        geometry_index
        < compose_index
        < stage_index
        < present_index
        < finish_index
        < ack_index
        < journey_index
    )


def test_physical_runner_rejects_noncanonical_terminal_geometry(
    tmp_path: Path,
) -> None:
    assert acceptance_runner.CANONICAL_DESKTOP_COLS == (
        akashic_tui.DESKTOP_ACCEPTANCE_COLS
    )
    assert acceptance_runner.CANONICAL_DESKTOP_ROWS == (
        akashic_tui.DESKTOP_ACCEPTANCE_ROWS
    )
    with pytest.raises(ValueError, match="canonical 280x84 geometry"):
        acceptance_runner.run_physical_desktop_acceptance(
            "/tmp/not-opened.sock",
            tmp_path,
            expected_server_pid=1,
            cols=100,
            rows=32,
            ready_markers=("READY",),
            timeout=1.0,
        )

    canonical = RichScreenProjection(
        acceptance_runner.CANONICAL_DESKTOP_COLS,
        acceptance_runner.CANONICAL_DESKTOP_ROWS,
        (),
        0,
    )
    acceptance_runner._require_canonical_desktop_geometry(canonical)
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="observed retained frame geometry 279x84",
    ):
        acceptance_runner._require_canonical_desktop_geometry(
            replace(canonical, cols=279)
        )


def test_journey_advances_only_across_new_physically_presented_frames() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    actions: list[tuple[str, str, int, int]] = []

    def sender(method, value, offer, generation):
        actions.append((method, value, offer.offer_id, generation))
        return "progress"

    first = _offer("X", offer_id=1, pad_menu=True)
    progress = journey.after_present(
        first, 9, _projection("READY"), sender
    )
    assert progress.milestone == "desk-complete"
    assert actions == [("send_key", "alt+1", 1, 9)]

    journey.after_present(first, 9, _projection(PAD_FOCUS_MARKER), sender)
    assert len(actions) == 1
    second = _offer("X", offer_id=2, pad_menu=True)
    progress = journey.after_present(
        second,
        9,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    assert progress.milestone == "pad-file-menu-activation-source"
    third = _offer("X", offer_id=3, pad_menu=True, file_open=True)
    progress = journey.after_present(
        third, 9, _projection(PAD_FOCUS_MARKER), sender
    )
    assert progress.milestone == "pad-file-menu-open"
    fourth = _offer("X", offer_id=4, pad_menu=True)
    progress = journey.after_present(
        fourth,
        9,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    assert progress.milestone == "pad-file-menu-closed"
    fifth = _offer("X", offer_id=5, pad_menu=True)
    progress = journey.after_present(
        fifth,
        9,
        _projection(PAD_FOCUS_MARKER + PAD_ACCEPTANCE_TEXT),
        sender,
    )
    assert progress.milestone == "pad-edited"
    sixth = _offer("X", offer_id=6, pad_menu=True)
    journey.after_present(sixth, 9, _projection(DAYBOOK_FOCUS_MARKER), sender)
    seventh = _offer("X", offer_id=7, pad_menu=True)
    journey.after_present(
        seventh,
        9,
        _projection(DAYBOOK_FOCUS_MARKER + DAYBOOK_PROMPT_MARKER),
        sender,
    )
    eighth = _offer("X", offer_id=8, pad_menu=True)
    journey.after_present(
        eighth,
        9,
        _projection(
            DAYBOOK_FOCUS_MARKER
            + DAYBOOK_PROMPT_MARKER
            + DAYBOOK_ACCEPTANCE_TASK
        ),
        sender,
    )
    ninth = _offer("X", offer_id=9, pad_menu=True)
    progress = journey.after_present(
        ninth,
        9,
        _daybook_projection(task_visible=True),
        sender,
    )
    assert progress.milestone == "daybook-task-added"
    assert not progress.complete
    navigated = _offer("X", offer_id=10, pad_menu=True)
    progress = journey.after_present(
        navigated,
        9,
        _daybook_projection(task_visible=False),
        sender,
    )
    assert progress.milestone == "daybook-date-advanced"
    assert not progress.complete
    outside_pad = _offer("X", offer_id=11, pad_menu=True)
    progress = journey.after_present(
        outside_pad,
        9,
        _handoff_projection(pad_tile=False),
        sender,
    )
    assert progress.milestone is None
    assert not progress.complete
    assert journey.stage == 10
    handoff = _offer("X", offer_id=12, pad_menu=True)
    progress = journey.after_present(
        handoff,
        9,
        _handoff_projection(pad_tile=True),
        sender,
    )
    assert progress.milestone == "daybook-source-opened-in-pad"
    assert progress.complete
    assert actions == [
        ("send_key", "alt+1", 1, 9),
        (
            "activate_pad_file_menu",
            acceptance_runner.PAD_FILE_MENU_EVIDENCE,
            2,
            9,
        ),
        ("send_key", "escape", 3, 9),
        ("send_text", PAD_ACCEPTANCE_TEXT, 4, 9),
        ("send_key", "alt+3", 5, 9),
        ("send_key", "ctrl+n", 6, 9),
        ("send_text", DAYBOOK_ACCEPTANCE_TASK, 7, 9),
        ("send_key", "enter", 8, 9),
        ("send_key", "right", 9, 9),
        ("send_key", "ctrl+o", 10, 9),
    ]


def test_journey_mutation_markers_are_distinct_single_scalars() -> None:
    assert len(PAD_ACCEPTANCE_TEXT) == 1
    assert len(DAYBOOK_ACCEPTANCE_TASK) == 1
    assert PAD_ACCEPTANCE_TEXT != DAYBOOK_ACCEPTANCE_TASK
    assert PAD_ACCEPTANCE_TEXT.isprintable()
    assert DAYBOOK_ACCEPTANCE_TASK.isprintable()


def test_journey_never_routes_input_from_background_popup_or_prompt() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    calls = []

    def sender(method, value, offer, generation):
        calls.append((method, value, offer.offer_id, generation))
        return "progress"

    journey.after_present(
        _offer("X", offer_id=1, pad_menu=True),
        4,
        _projection("READY"),
        sender,
    )
    journey.after_present(
        _offer("X", offer_id=2, pad_menu=True),
        4,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    background_popup = _offer(
        "X",
        offer_id=3,
        pad_menu=True,
        file_open=True,
    )
    journey.after_present(
        background_popup,
        4,
        _projection("Pad popup without Desk focus"),
        sender,
    )
    assert journey.stage == 2
    assert len(calls) == 2

    journey.after_present(
        _offer("X", offer_id=4, pad_menu=True, file_open=True),
        4,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    journey.after_present(
        _offer("X", offer_id=5, pad_menu=True),
        4,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    journey.after_present(
        _offer("X", offer_id=6, pad_menu=True),
        4,
        _projection(PAD_FOCUS_MARKER + PAD_ACCEPTANCE_TEXT),
        sender,
    )
    journey.after_present(
        _offer("X", offer_id=7, pad_menu=True),
        4,
        _projection(DAYBOOK_FOCUS_MARKER),
        sender,
    )
    assert journey.stage == 6

    journey.after_present(
        _offer("X", offer_id=8, pad_menu=True),
        4,
        _projection(DAYBOOK_PROMPT_MARKER),
        sender,
    )
    assert journey.stage == 6
    assert len(calls) == 6
    journey.after_present(
        _offer("X", offer_id=9, pad_menu=True),
        4,
        _projection(DAYBOOK_FOCUS_MARKER + DAYBOOK_PROMPT_MARKER),
        sender,
    )
    assert journey.stage == 7
    assert calls[-1][:3] == ("send_text", DAYBOOK_ACCEPTANCE_TASK, 9)


def test_journey_cannot_cross_session_lineage() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    calls = []

    def sender(method, value, offer, generation):
        calls.append((method, value, offer.offer_id, generation))
        return "progress"

    initial = _offer("X", offer_id=1, pad_menu=True)
    journey.after_present(initial, 4, _projection("READY"), sender)
    next_offer = _offer("X", offer_id=2, pad_menu=True)
    drifted = replace(
        next_offer,
        scope=replace(next_offer.scope, session_id=2),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="session lineage"):
        journey.after_present(
            drifted,
            4,
            _projection(PAD_FOCUS_MARKER),
            sender,
        )
    assert calls == [("send_key", "alt+1", 1, 4)]


def test_journey_rejects_preexisting_mutation_markers() -> None:
    def sender(_method, _value, _offer, _generation):
        return "progress"

    pad = DesktopAcceptanceJourney(("READY",))
    pad.after_present(
        _offer("X", offer_id=1, pad_menu=True),
        1,
        _projection("READY"),
        sender,
    )
    pad.after_present(
        _offer("X", offer_id=2, pad_menu=True),
        1,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    pad.after_present(
        _offer("X", offer_id=3, pad_menu=True, file_open=True),
        1,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="Pad acceptance"):
        pad.after_present(
            _offer("X", offer_id=4, pad_menu=True),
            1,
            _projection(PAD_FOCUS_MARKER + PAD_ACCEPTANCE_TEXT),
            sender,
        )

    daybook = DesktopAcceptanceJourney(("READY",))
    daybook.after_present(
        _offer("X", offer_id=1, pad_menu=True),
        1,
        _projection("READY"),
        sender,
    )
    daybook.after_present(
        _offer("X", offer_id=2, pad_menu=True),
        1,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    daybook.after_present(
        _offer("X", offer_id=3, pad_menu=True, file_open=True),
        1,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    daybook.after_present(
        _offer("X", offer_id=4, pad_menu=True),
        1,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    daybook.after_present(
        _offer("X", offer_id=5, pad_menu=True),
        1,
        _projection(PAD_FOCUS_MARKER + PAD_ACCEPTANCE_TEXT),
        sender,
    )
    daybook.after_present(
        _offer("X", offer_id=6, pad_menu=True),
        1,
        _projection(DAYBOOK_FOCUS_MARKER),
        sender,
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError, match="Daybook acceptance"
    ):
        daybook.after_present(
            _offer("X", offer_id=7, pad_menu=True),
            1,
            _projection(
                DAYBOOK_FOCUS_MARKER
                + DAYBOOK_PROMPT_MARKER
                + DAYBOOK_ACCEPTANCE_TASK
            ),
            sender,
        )


def test_backpressured_action_retries_against_same_acknowledged_frame() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    statuses = iter(("backpressured", "progress", "progress"))
    calls = []

    def sender(method, value, offer, generation):
        calls.append((method, value, offer.offer_id))
        return next(statuses)

    first = _offer("X", offer_id=1, pad_menu=True)
    journey.after_present(first, 4, _projection("READY"), sender)
    assert journey.stage == 0
    journey.after_present(first, 4, _projection("READY"), sender)
    assert calls == [("send_key", "alt+1", 1)]

    assert journey.has_pending_input
    newer = _offer("X", offer_id=2, pad_menu=True)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="cannot leave"):
        journey.retry_pending_current(newer, 4, sender)
    assert calls == [("send_key", "alt+1", 1)]
    assert journey.retry_pending_current(first, 4, sender)
    assert journey.stage == 1
    assert not journey.has_pending_input
    assert calls[-1] == ("send_key", "alt+1", 1)

    second = _offer("X", offer_id=2, pad_menu=True)
    journey.after_present(second, 4, _projection(PAD_FOCUS_MARKER), sender)
    assert journey.stage == 2
    assert calls[-1] == (
        "activate_pad_file_menu",
        acceptance_runner.PAD_FILE_MENU_EVIDENCE,
        2,
    )


def test_backpressured_file_activation_reauthorizes_from_qualifying_new_frame(
) -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    activation_statuses = iter(("backpressured", "progress"))
    calls = []
    requests = []
    accepted = []

    def sender(method, value, offer, generation):
        calls.append((method, value, offer.offer_id, generation))
        if method == "activate_pad_file_menu":
            response_status = next(activation_statuses)
            target = _pad_file_target(offer)
            display_state, display_ack = _acknowledged_hit_state(
                offer,
                target,
                generation=generation,
            )

            class Client:
                def request(self, rpc_method, **params):
                    requests.append((offer.offer_id, rpc_method, params))
                    return {
                        "status": response_status,
                        "accepted_events": (
                            1 if response_status == "progress" else 0
                        ),
                    }

            status, evidence = acceptance_runner._request_acceptance_input(
                Client(),
                method,
                value,
                offer,
                generation,
                display_state=display_state,
                display_ack=display_ack,
            )
            if evidence is not None:
                accepted.append(evidence)
            return status
        return "progress"

    initial = _offer("X", offer_id=1, pad_menu=True)
    journey.after_present(initial, 4, _projection("READY"), sender)
    source = _offer("X", offer_id=2, pad_menu=True)
    progress = journey.after_present(
        source,
        4,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    assert progress.milestone == "pad-file-menu-activation-source"
    assert journey.has_pending_input

    drifted = _offer("X", offer_id=3, pad_menu=True)
    progress = journey.after_present(
        drifted,
        4,
        _projection("Pad no longer focused"),
        sender,
    )
    assert progress.milestone is None
    assert journey.stage == 1
    assert not journey.has_pending_input
    assert not journey.retry_pending_current(source, 4, sender)

    replacement_source = _offer("X", offer_id=4, pad_menu=True)
    progress = journey.after_present(
        replacement_source,
        4,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    assert progress.milestone == "pad-file-menu-activation-source"
    assert journey.stage == 2
    assert [call[2] for call in calls if call[0].startswith("activate")] == [
        source.offer_id,
        replacement_source.offer_id,
    ]
    assert [request[0] for request in requests] == [
        source.offer_id,
        replacement_source.offer_id,
    ]
    assert [request[1] for request in requests] == [
        "send_control_event",
        "send_control_event",
    ]
    assert len(accepted) == 1
    assert accepted[0].offer_id == replacement_source.offer_id
    assert accepted[0].generation == 4
    assert accepted[0].scope == acceptance_runner.display_scope_to_wire(
        replacement_source.scope
    )
    assert accepted[0].semantic_target is not None
    assert accepted[0].semantic_target["control_id"] == (
        _pad_file_target(replacement_source).identity.control_id
    )


def test_connect_rejects_a_socket_owned_by_another_server_process(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    clients = []

    class Client:
        def __init__(self, socket_path, timeout):
            self.socket_path = socket_path
            self.timeout = timeout
            self.closed = False
            clients.append(self)

        def connect(self):
            return None

        def close(self):
            self.closed = True

    monkeypatch.setattr(acceptance_runner, "SessionClient", Client)
    monkeypatch.setattr(
        acceptance_runner,
        "_connected_peer_pid",
        lambda _client: 111,
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="process 111, not the launched server process 222",
    ):
        acceptance_runner._connect(
            "/tmp/stale-session.sock",
            time.monotonic() + 1.0,
            222,
        )
    assert len(clients) == 1
    assert clients[0].timeout == acceptance_runner.SESSION_REQUEST_TIMEOUT_SECONDS
    assert clients[0].closed


def test_guest_boot_failures_are_reported_from_the_cell_screen() -> None:
    normal = "KDOS loaded\nRunning autoexec.f...\n"
    assert acceptance_runner._guest_boot_failure(normal) is None

    failure = (
        normal
        + "  line 66: _UTUI-RGN ? (not found)\n"
        + "COLD SOURCE LOAD FAIL status=12 eval=1 line=488 token=_UTUI-RGN\n"
    )
    excerpt = acceptance_runner._guest_boot_failure(failure)
    assert excerpt is not None
    assert "_UTUI-RGN ? (not found)" in excerpt
    assert "COLD SOURCE LOAD FAIL" in excerpt

    depth_failure = normal + " ok\nEVALUATE depth limit exceeded\n>\n"
    excerpt = acceptance_runner._guest_boot_failure(depth_failure)
    assert excerpt is not None
    assert "Running autoexec.f..." in excerpt
    assert "EVALUATE depth limit exceeded" in excerpt


def test_guest_failure_diagnostics_capture_existing_service_records(
    tmp_path: Path,
) -> None:
    values = {
        "_A1D-FAILURE-VALID": (0x0FD0, UINT64_MAX),
        "_A1D-FAILURE-IOR": (0x0FD8, (-3203) & UINT64_MAX),
        "_A1D-FAILURE-PHASE": (0x0FE0, 6),
        "_A1D-FAILURE-PUBLISHER-A": (0x0FE8, 0x2000),
        "_A1D-FAILURE-SCREEN-A": (0x0FF0, 0x3000),
        "_A1D-FAILURE-ENGINE-A": (0x0FF8, 0x4000),
        "_ASHELL-TERM-STATUS": (0x1000, 3),
        "_APTSCB-STATUS": (0x1008, 0),
    }
    record_cells = {
        0x2000: list(range(26)),
        0x3000: list(range(261)),
        0x4000: list(range(62)),
    }

    class Client:
        def request(self, method, **params):
            if method == "status":
                assert params == {"detailed": True}
                return {"state": "running", "forth": {"word": None}}
            if method == "forth":
                assert set(values) <= set(params["names"])
                return {
                    "here": 0x9000,
                    "words": {
                        name: {
                            "data_address": address,
                            "value": value,
                        }
                        for name, (address, value) in values.items()
                    },
                }
            if method == "peek":
                cells = record_cells[params["address"]]
                assert params["count"] == len(cells)
                return {"values": cells}
            raise AssertionError(method)

    path = acceptance_runner._write_guest_failure_diagnostics(
        Client(),
        tmp_path,
        "[akashic] desktop exception -3203",
    )
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["failure"].endswith("-3203")
    assert payload["record_source"] == "failure_snapshot"
    assert payload["variables"]["_A1D-FAILURE-VALID"]["value"] == UINT64_MAX
    assert payload["variables"]["_ASHELL-TERM-STATUS"]["value"] == 3
    assert payload["records"]["publisher"]["fields"] == {
        "adapter": 18,
        "base_magic": 10,
        "context": 1,
        "engine": 11,
        "fault_status": 24,
        "more_work": 22,
        "output_needed": 23,
        "phase": 25,
        "producer_budget": 15,
        "producer_bytes": 14,
        "producer_context": 13,
        "rich_magic": 12,
        "session": 0,
        "surface_cols": 19,
        "surface_generation": 21,
        "surface_rows": 20,
    }
    producer = payload["records"]["hybrid_producer"]["fields"]
    assert producer["phase"] == 15
    assert producer["candidate_attempt"] == 20
    assert producer["source_draw"] == 22
    assert producer["source_record_bytes"] == 25
    assert producer["source_text_bytes"] == 28
    assert producer["claim_bytes"] == 41
    assert producer["glyph_text_bytes"] == 54
    assert producer["control_count"] == 55
    assert producer["glyph_count"] == 56
    assert producer["target_active_address"] == 238
    assert producer["target_pending_address"] == 239
    assert producer["next_region"] == 240
    assert producer["next_object"] == 241
    assert producer["active_draw"] == 242
    assert producer["source_directory_bytes"] == 246
    assert producer["document_count"] == 247
    assert producer["row_damage_address"] == 248
    assert producer["row_damage_bytes"] == 249
    assert producer["glyph_id_map_address"] == 250
    assert producer["glyph_id_map_bytes"] == 251
    assert payload["records"]["engine"]["fields"]["last_status"] == 28


def test_guest_failure_message_preserves_failure_when_capture_breaks(
    tmp_path: Path,
) -> None:
    class Client:
        def request(self, method, **params):
            raise KeyError("missing diagnostic field")

    message = acceptance_runner._guest_failure_message(
        Client(),
        tmp_path,
        "[akashic] desktop exception -3203",
    )
    assert "desktop exception -3203" in message
    assert "diagnostic capture failed" in message


def test_timeout_state_pauses_reads_live_records_and_resumes(
    tmp_path: Path,
) -> None:
    calls = []
    words = {
        "_A1D-FAILURE-VALID": {
            "data_address": 0x1000,
            "value": 0,
        },
        "_A1D-FAILURE-IOR": {
            "data_address": 0x1008,
            "value": 0,
        },
        "_RTAPTSCBOP-PUBLISHER": {
            "data_address": 0x1020,
            "value": 0x2000,
        },
        "_RTAPTSCBOP-CONTEXT": {
            "data_address": 0x1028,
            "value": 0x3000,
        },
        "_RTAPTSCBI-ENGINE": {
            "data_address": 0x1030,
            "value": 0x4000,
        },
    }
    record_cells = {
        0x2000: list(range(26)),
        0x3000: list(range(261)),
        0x4000: list(range(62)),
    }

    class Client:
        def request(self, method, **params):
            calls.append((method, params))
            if method == "status":
                assert params == {"detailed": False}
                return {"paused": False}
            if method == "pause":
                assert params == {}
                return {
                    "state": "paused",
                    "paused": True,
                    "error": None,
                    "rich_terminal": {"failure": None, "lost": False},
                    "forth": {
                        "word": {"name": "_RTHP-BUILD-CANDIDATE"}
                    },
                }
            if method == "forth":
                assert set(words) <= set(params["names"])
                return {"here": 0x9000, "words": words}
            if method == "peek":
                cells = record_cells[params["address"]]
                assert params["count"] == len(cells)
                return {"values": cells}
            if method == "resume":
                assert params == {}
                return {"paused": False}
            raise AssertionError(method)

    path = acceptance_runner._write_timeout_state_diagnostics(
        Client(),
        tmp_path,
        "stage=0 offers-seen=0",
    )
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert [method for method, _params in calls] == [
        "status",
        "pause",
        "forth",
        "peek",
        "peek",
        "peek",
        "resume",
    ]
    assert [
        (params["address"], params["count"])
        for method, params in calls
        if method == "peek"
    ] == [(0x2000, 26), (0x3000, 261), (0x4000, 62)]
    assert payload["timeout"] == "stage=0 offers-seen=0"
    assert payload["record_source"] == "live_composition"
    assert payload["machine"]["forth"]["word"]["name"] == (
        "_RTHP-BUILD-CANDIDATE"
    )
    assert payload["records"]["publisher"]["fields"]["phase"] == 25
    producer = payload["records"]["hybrid_producer"]["fields"]
    assert producer["phase"] == 15
    assert producer["candidate_attempt"] == 20
    assert producer["source_draw"] == 22
    assert producer["source_record_bytes"] == 25
    assert producer["source_text_bytes"] == 28
    assert producer["claim_bytes"] == 41
    assert producer["glyph_text_bytes"] == 54
    assert producer["control_count"] == 55
    assert producer["glyph_count"] == 56
    assert producer["target_active_address"] == 238
    assert producer["target_pending_address"] == 239
    assert producer["source_directory_bytes"] == 246
    assert producer["active_draw"] == 242
    assert producer["row_damage_address"] == 248
    assert producer["row_damage_bytes"] == 249
    assert producer["glyph_id_map_address"] == 250
    assert producer["glyph_id_map_bytes"] == 251
    assert payload["records"]["engine"]["fields"]["operation_count"] == 24
    assert payload["records"]["engine"]["fields"]["send_index"] == 27
    assert payload["resume_attempted"] is True
    assert "resume_error" not in payload


def test_timeout_state_message_preserves_timeout_and_resumes_after_failure(
    tmp_path: Path,
) -> None:
    calls = []

    class Client:
        def request(self, method, **params):
            calls.append(method)
            if method == "status":
                return {"paused": False}
            if method == "pause":
                return {
                    "paused": True,
                    "error": None,
                    "rich_terminal": {"failure": None, "lost": False},
                }
            if method == "forth":
                raise KeyError("capture broke")
            if method == "resume":
                return {"paused": False}
            raise AssertionError(method)

    message = acceptance_runner._timeout_state_message(
        Client(),
        tmp_path,
        "stage=0",
    )
    assert message == "diagnostic capture failed: 'capture broke'"
    assert calls == ["status", "pause", "forth", "resume"]


def test_timeout_state_keeps_capture_when_best_effort_resume_fails(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    calls = []

    class Client:
        def request(self, method, **params):
            calls.append(method)
            if method == "status":
                return {"paused": False}
            if method == "pause":
                return {
                    "paused": True,
                    "error": None,
                    "rich_terminal": {"failure": None, "lost": False},
                }
            if method == "resume":
                raise RuntimeError("resume broke")
            raise AssertionError(method)

    monkeypatch.setattr(
        acceptance_runner,
        "_guest_state_payload",
        lambda *_args, **_kwargs: {"timeout": "stage=0"},
    )
    path = acceptance_runner._write_timeout_state_diagnostics(
        Client(),
        tmp_path,
        "stage=0",
    )
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert calls == ["status", "pause", "resume"]
    assert payload["resume_attempted"] is True
    assert payload["resume_error"] == "RuntimeError: resume broke"


def test_acceptance_diagnostic_state_reports_exact_display_boundary() -> None:
    ready, missing = acceptance_runner._marker_status(
        "Desk Selection and Tools",
        ("Selection", "Tools", "Daybook"),
    )
    assert not ready
    assert missing == ("Daybook",)

    state = acceptance_runner.AcceptanceDiagnosticState(
        acceptance_runner.RETAINED_PENDING_MODE,
        True,
        offer_id=9,
        scope={"model_revision": 12},
        draw_count=3_200,
        retained_text_sha256="a" * 64,
        missing_ready_markers=missing,
    )
    summary = state.summary()
    assert acceptance_runner.RETAINED_PENDING_MODE in summary
    assert "CELL-ready=True" in summary
    assert "offer=9" in summary
    assert "draws=3200" in summary
    assert 'scope={"model_revision": 12}' in summary
    assert f"retained-text={'a' * 64}" in summary
    assert "missing=Daybook" in summary


def test_timeout_diagnostics_persist_cell_and_latest_retained_text(
    tmp_path: Path,
) -> None:
    detail = acceptance_runner._write_timeout_diagnostics(
        tmp_path,
        cell_text="CELL Desk",
        retained_text="retained Desk",
        stage=0,
        cell_ready=True,
        offers_seen=2,
        since_offer=7,
        cell_missing_markers=(),
        retained_missing_markers=("Daybook",),
        frame_barrier=0,
        pending_input=False,
    )
    assert (tmp_path / "timeout-cell.txt").read_text() == "CELL Desk"
    assert (tmp_path / "timeout-retained.txt").read_text() == "retained Desk"
    assert detail == (
        "stage=0 CELL-ready=True offers-seen=2 since-offer=7 "
        "cell-missing=none retained-missing=Daybook "
        "frame-barrier=0 pending-input=False"
    )

    acceptance_runner._write_timeout_diagnostics(
        tmp_path,
        cell_text="new CELL",
        retained_text=None,
        stage=0,
        cell_ready=False,
        offers_seen=0,
        since_offer=0,
        cell_missing_markers=("Selection",),
        retained_missing_markers=None,
        frame_barrier=0,
        pending_input=False,
    )
    assert (tmp_path / "timeout-cell.txt").read_text() == "new CELL"
    assert not (tmp_path / "timeout-retained.txt").exists()


def test_manifest_records_physical_pixels_scopes_and_bound_inputs(
    tmp_path: Path,
) -> None:
    scope = {
        "attachment_epoch": 1,
        "session_id": 2,
        "presentation_epoch": 0,
        "model_revision": 7,
        "geometry_generation": 0,
        "cell_revision": 7,
        "retained_revision": 7,
    }
    frame = PresentedFrameEvidence(
        milestone="pad-file-menu-open",
        offer_id=7,
        generation=0,
        scope=scope,
        logical_cols=acceptance_runner.CANONICAL_DESKTOP_COLS,
        logical_rows=acceptance_runner.CANONICAL_DESKTOP_ROWS,
        draw_count=3200,
        pixel_sha256="a" * 64,
        retained_text_sha256="b" * 64,
        retained_only_sha256="c" * 64,
        retained_only_nonblack_pixels=900,
        png_path=tmp_path / "desk.png",
        retained_png_path=tmp_path / "desk-retained.png",
        retained_text_path=tmp_path / "desk-retained.txt",
        menu_signatures=(acceptance_runner.PAD_MENU_SIGNATURE,),
        renderer_owned_gap_cells=12,
    )
    replacement = replace(frame, offer_id=8, pixel_sha256="d" * 64)
    stored_frames = [frame]
    acceptance_runner._store_milestone_frame(stored_frames, replacement)
    assert stored_frames == [replacement]
    with pytest.raises(PhysicalDesktopAcceptanceError, match="duplicated milestone"):
        acceptance_runner._store_milestone_frame(
            [frame, replacement],
            replace(frame, offer_id=9),
        )

    event = AcceptedInputEvidence("send_key", "alt+1", 7, 0, scope)
    semantic_target = {
        "owner_id": 1,
        "owner_generation": 1,
        "control_id": 10_001,
        "kind": "MENU",
        "label": acceptance_runner.PAD_FILE_MENU_EVIDENCE,
        "pixel_rect": {
            "left": 2,
            "top": 2,
            "right": 42,
            "bottom": 20,
        },
    }
    control = AcceptedInputEvidence(
        "send_control_event",
        acceptance_runner.PAD_FILE_MENU_EVIDENCE,
        7,
        0,
        scope,
        semantic_target,
    )
    manifest = write_acceptance_manifest(
        tmp_path,
        "x11",
        (frame,),
        (event, control),
    )
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    assert payload["video_driver"] == "x11"
    assert payload["physical_boundary"] == "pygame.display.flip"
    assert payload["acknowledged_evidence_viewport"] == {
        "origin": [0, 0],
        "extent": "recorded frame PNG dimensions",
        "host_mode_bar": "excluded",
    }
    assert payload["frames"] == [frame.to_dict()]
    assert payload["inputs"] == [event.to_dict(), control.to_dict()]
    assert payload["frames"][0]["renderer_owned_gap_cells"] == 12
    assert payload["frames"][0]["logical_cols"] == 280
    assert payload["frames"][0]["logical_rows"] == 84
    assert payload["inputs"][1]["semantic_target"] == semantic_target
