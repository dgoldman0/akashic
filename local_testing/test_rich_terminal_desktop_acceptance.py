"""Focused pure checks for the physical Desktop acceptance runner."""

from __future__ import annotations

import hashlib
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
from rich_terminal.semantic_content import (
    SemanticContentFlag,
    SemanticTextContent,
    SemanticTextItem,
    SemanticTextRole,
    SemanticTextState,
)
from rich_terminal.retained_view import (
    DisplayScope,
    GlyphRunDraw,
    MeterDraw,
    MenuBarDraw,
    MenuDraw,
    MenuItemDraw,
    MenuSeparatorDraw,
    ReadoutDraw,
    RetainedDrawPlane,
    RetainedRegionDraw,
    StatusDraw,
    TabDraw,
    TabSetDraw,
    TextAreaDraw,
    TextGridDraw,
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


UINT64_MAX = 0xFFFFFFFFFFFFFFFF
TEST_DAYBOOK_INITIAL_DATE = "2026-09-02"
TEST_DAYBOOK_NEXT_DATE = "2026-09-03"


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


def _phase_event(sequence: int, phase: int) -> int:
    return (sequence << 8) | phase


def _phase_transition(
    previous_sequence: int,
    previous_phase: int,
    sequence: int,
    phase: int,
    lower: int,
    upper: int,
    *,
    sample_index: int,
    batch_index: int,
    generation: int = 23,
) -> dict:
    return {
        "machine_generation": generation,
        "sample_index": sample_index,
        "source": "batch",
        "batch_index": batch_index,
        "step_lower_bound": lower,
        "step_upper_bound": upper,
        "previous_event": _phase_event(previous_sequence, previous_phase),
        "previous_sequence": previous_sequence,
        "previous_phase": previous_phase,
        "event": _phase_event(sequence, phase),
        "sequence": sequence,
        "phase": phase,
        "coalesced_transitions": sequence - previous_sequence - 1,
    }


def _phase_observer(
    transitions: list[dict],
    *,
    status: str = "stopped",
    generation: int = 23,
    address: int = 0x100,
    started_steps: int = 100,
    started_batches: int = 10,
    current_steps: int = 220,
    current_batches: int = 22,
    initial_sequence: int = 10,
    initial_phase: int = 0,
) -> dict:
    if transitions:
        last_sequence = transitions[-1]["sequence"]
        last_phase = transitions[-1]["phase"]
        successful_samples = transitions[-1]["sample_index"] + 1
    else:
        last_sequence = initial_sequence
        last_phase = initial_phase
        successful_samples = 1
    observed_transitions = last_sequence - initial_sequence
    return {
        "schema": acceptance_runner.GUEST_PHASE_PROFILE_SCHEMA,
        "schema_version": acceptance_runner.GUEST_PHASE_PROFILE_SCHEMA_VERSION,
        "status": status,
        "machine_generation": generation,
        "address": address,
        "encoding": acceptance_runner.GUEST_PHASE_PROFILE_ENCODING,
        "batch_step_bound": 100,
        "max_events": 32,
        "started_steps": started_steps,
        "started_batches": started_batches,
        "current_steps": current_steps,
        "current_batches": current_batches,
        "last_sample_steps": current_steps,
        "last_sample_batches": current_batches,
        "stopped_steps": None if status == "active" else current_steps,
        "stopped_batches": None if status == "active" else current_batches,
        "initial": {
            "event": _phase_event(initial_sequence, initial_phase),
            "sequence": initial_sequence,
            "phase": initial_phase,
        },
        "last": {
            "event": _phase_event(last_sequence, last_phase),
            "sequence": last_sequence,
            "phase": last_phase,
        },
        "sample_attempts": successful_samples,
        "successful_samples": successful_samples,
        "observed_transitions": observed_transitions,
        "coalesced_transitions": observed_transitions - len(transitions),
        "dropped_records": 0,
        "dropped_transitions": 0,
        "error": None,
        "transitions": transitions,
    }


class _PhaseProfileClient:
    def __init__(
        self,
        observer: dict,
        *,
        address: int = 0x100,
        resolved_event: int | None = None,
    ):
        self.observer = observer
        self.address = address
        self.resolved_event = resolved_event
        self.calls: list[tuple[str, dict]] = []

    def request(self, method: str, **params):
        self.calls.append((method, params))
        if method == "forth":
            initial = self.observer["initial"]
            return {
                "words": {
                    acceptance_runner.GUEST_PHASE_PROFILE_WORD: {
                        "name": acceptance_runner.GUEST_PHASE_PROFILE_WORD,
                        "data_address": self.address,
                        "value": (
                            initial["event"]
                            if self.resolved_event is None
                            else self.resolved_event
                        ),
                    }
                }
            }
        if method in {"start_phase_profile", "stop_phase_profile"}:
            return self.observer
        raise AssertionError(f"unexpected request {method!r}")


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
    guest_profile = {
        "available": True,
        "summary_available": True,
        "phase_summary": {"lifecycle_complete": True},
    }
    trace.set_guest_phase_profile(guest_profile)

    path = trace.write("pass")

    assert path == tmp_path / "performance-trace.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["schema"] == "akashic-rich-terminal-performance-v2"
    assert payload["normative"] is False
    assert payload["clock"] == "time.monotonic_ns"
    assert payload["origin_ns"] == 10_000
    assert payload["outcome"] == "pass"
    assert [event["sequence"] for event in payload["events"]] == [0, 1]
    assert [event["elapsed_ns"] for event in payload["events"]] == [25, 65]
    assert payload["events"][0]["counters"]["steps"] == 12_345
    assert payload["events"][1]["duration_ns"] == 40
    assert payload["events"][1]["compose_duration_ns"] == 11
    assert payload["guest_phase_profile"] == guest_profile
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
    payload = json.loads(trace.path.read_text(encoding="utf-8"))
    assert payload["guest_phase_profile"] is None


def test_phase_profile_start_is_generation_and_first_offer_bound() -> None:
    observer = _phase_observer(
        [],
        status="active",
        address=0x103,
        started_steps=120,
        started_batches=12,
        current_steps=120,
        current_batches=12,
        initial_phase=3,
    )
    client = _PhaseProfileClient(
        observer,
        address=0x103,
        resolved_event=_phase_event(9, 0),
    )
    first_offer_status = {
        "generation": 23,
        "steps": 100,
        "batches": 10,
        "revision": 7,
    }

    capture = acceptance_runner._start_guest_phase_profile(
        client,
        max_events=32,
        machine_generation=23,
        first_offer_status=first_offer_status,
    )

    assert client.calls == [
        (
            "forth",
            {"names": [acceptance_runner.GUEST_PHASE_PROFILE_WORD]},
        ),
        (
            "start_phase_profile",
            {"generation": 23, "address": 0x103, "max_events": 32},
        ),
    ]
    assert capture["first_offer_status_identity"] == {
        "generation": 23,
        "steps": 100,
        "batches": 10,
    }
    assert capture["first_offer_status_revision"] == 7
    assert capture["observer_attach_lag_steps"] == 20
    assert capture["observer_attach_lag_batches"] == 2
    assert capture["resolved_word"]["event"] == _phase_event(9, 0)
    assert capture["observer_start"]["initial"]["event"] == _phase_event(10, 3)


@pytest.mark.parametrize(
    ("started_steps", "started_batches"),
    ((90, 10), (100, 9)),
)
def test_phase_profile_start_rejects_attachment_before_first_offer_status(
    started_steps: int,
    started_batches: int,
) -> None:
    observer = _phase_observer(
        [],
        status="active",
        started_steps=started_steps,
        started_batches=started_batches,
        current_steps=started_steps,
        current_batches=started_batches,
    )
    client = _PhaseProfileClient(observer)

    with pytest.raises(ValueError, match="precedes first-offer status"):
        acceptance_runner._start_guest_phase_profile(
            client,
            max_events=32,
            machine_generation=23,
            first_offer_status={
                "generation": 23,
                "steps": 100,
                "batches": 10,
                "revision": 7,
            },
        )

    assert client.calls[-1] == ("stop_phase_profile", {})


@pytest.mark.parametrize(
    ("resolved_event", "error"),
    (
        (_phase_event(11, 0), "sequence regressed"),
        (_phase_event(10, 1), "without advancing"),
    ),
)
def test_phase_profile_start_rejects_impossible_event_order(
    resolved_event: int,
    error: str,
) -> None:
    observer = _phase_observer([], status="active")
    client = _PhaseProfileClient(observer, resolved_event=resolved_event)

    with pytest.raises(ValueError, match=error):
        acceptance_runner._start_guest_phase_profile(
            client,
            max_events=32,
            machine_generation=23,
        )

    assert client.calls[-1] == ("stop_phase_profile", {})


def test_phase_profile_start_rejects_capacity_above_megapad_bound() -> None:
    client = _PhaseProfileClient(_phase_observer([], status="active"))

    with pytest.raises(ValueError, match="max_events"):
        acceptance_runner._start_guest_phase_profile(
            client,
            max_events=acceptance_runner.GUEST_PHASE_PROFILE_MAX_EVENTS + 1,
            machine_generation=23,
        )

    assert client.calls == []


def test_guest_phase_summary_computes_batch_bounded_residency() -> None:
    transitions = [
        _phase_transition(10, 0, 11, 1, 110, 120, sample_index=2, batch_index=11),
        _phase_transition(11, 1, 12, 0, 150, 170, sample_index=3, batch_index=12),
    ]
    observer = _phase_observer(
        transitions,
        address=0x103,
        current_steps=200,
        current_batches=20,
    )

    summary = acceptance_runner._guest_phase_summary(
        observer,
        expected_generation=23,
        window_end_steps=200,
    )

    assert summary["lifecycle_complete"] is True
    assert summary["attribution_complete"] is True
    assert summary["window_end_phase"] == 0
    assert summary["residencies"] == [
        {
            "phase": 1,
            "name": "uidl_aggregate",
            "kind": "closed",
            "start_step_lower_bound": 110,
            "start_step_upper_bound": 120,
            "end_step_lower_bound": 150,
            "end_step_upper_bound": 170,
            "retired_steps_lower_bound": 30,
            "retired_steps_upper_bound": 60,
            "start_coalesced_transitions": 0,
            "end_coalesced_transitions": 0,
        }
    ]
    assert summary["phases"]["1"]["visits"] == 1
    assert summary["phases"]["1"]["retired_steps_lower_bound"] == 30
    assert summary["phases"]["1"]["retired_steps_upper_bound"] == 60
    assert summary["phases"]["0"]["retired_steps_lower_bound"] == 40
    assert summary["phases"]["0"]["retired_steps_upper_bound"] == 70


def test_guest_phase_summary_bounds_phase_open_at_attachment() -> None:
    observer = _phase_observer(
        [
            _phase_transition(
                10,
                3,
                11,
                0,
                110,
                120,
                sample_index=2,
                batch_index=11,
            )
        ],
        initial_phase=3,
        current_steps=200,
        current_batches=20,
    )

    summary = acceptance_runner._guest_phase_summary(
        observer,
        expected_generation=23,
        window_end_steps=200,
    )

    assert summary["lifecycle_complete"] is True
    assert summary["attribution_complete"] is True
    assert summary["initial_phase"] == 3
    assert summary["initial_residency_truncated"] is True
    assert summary["residencies"] == [
        {
            "phase": 3,
            "name": "control_plan",
            "kind": "initial-window-open",
            "start_step_lower_bound": 100,
            "start_step_upper_bound": 100,
            "end_step_lower_bound": 110,
            "end_step_upper_bound": 120,
            "retired_steps_lower_bound": 10,
            "retired_steps_upper_bound": 20,
            "start_coalesced_transitions": 0,
            "end_coalesced_transitions": 0,
        }
    ]


def test_guest_phase_summary_rejects_malformed_events_and_intervals() -> None:
    transitions = [
        _phase_transition(10, 0, 11, 1, 110, 120, sample_index=2, batch_index=11),
        _phase_transition(11, 1, 12, 0, 150, 170, sample_index=3, batch_index=12),
    ]
    malformed = []

    packed_mismatch = _phase_observer(json.loads(json.dumps(transitions)))
    packed_mismatch["transitions"][0]["event"] += 1
    malformed.append(packed_mismatch)

    coalesced_mismatch = _phase_observer(json.loads(json.dumps(transitions)))
    coalesced_mismatch["transitions"][0]["coalesced_transitions"] = 1
    malformed.append(coalesced_mismatch)

    reversed_interval = _phase_observer(json.loads(json.dumps(transitions)))
    reversed_interval["transitions"][0]["step_lower_bound"] = 121
    malformed.append(reversed_interval)

    overlapping_interval = _phase_observer(json.loads(json.dumps(transitions)))
    overlapping_interval["transitions"][1]["step_lower_bound"] = 119
    malformed.append(overlapping_interval)

    for observer in malformed:
        with pytest.raises(ValueError):
            acceptance_runner._guest_phase_summary(
                observer,
                expected_generation=23,
                window_end_steps=200,
            )


def test_guest_phase_summary_marks_window_straddling_transition_ambiguous() -> None:
    transitions = [
        _phase_transition(10, 0, 11, 1, 110, 120, sample_index=2, batch_index=11),
        _phase_transition(11, 1, 12, 0, 190, 210, sample_index=3, batch_index=20),
    ]
    observer = _phase_observer(transitions)

    summary = acceptance_runner._guest_phase_summary(
        observer,
        expected_generation=23,
        window_end_steps=200,
    )

    assert summary["lifecycle_complete"] is False
    assert summary["attribution_complete"] is False
    assert summary["window_end_state_known"] is False
    assert summary["window_end_phase"] is None
    assert summary["straddling_transition"]["step_upper_bound"] == 210
    residency = summary["residencies"][0]
    assert residency["kind"] == "window-end-ambiguous"
    assert residency["end_step_lower_bound"] == 190
    assert residency["end_step_upper_bound"] == 200
    assert residency["retired_steps_lower_bound"] == 70
    assert residency["retired_steps_upper_bound"] == 90


def test_guest_phase_summary_bounds_phase_that_may_open_across_window_end() -> None:
    observer = _phase_observer(
        [
            _phase_transition(
                10,
                0,
                11,
                1,
                190,
                210,
                sample_index=2,
                batch_index=20,
            )
        ]
    )

    summary = acceptance_runner._guest_phase_summary(
        observer,
        expected_generation=23,
        window_end_steps=200,
    )

    assert summary["window_end_state_known"] is False
    assert summary["residencies"][0]["kind"] == "window-end-possible"
    assert summary["residencies"][0]["retired_steps_lower_bound"] == 0
    assert summary["residencies"][0]["retired_steps_upper_bound"] == 10
    assert summary["phases"]["1"]["visits"] == 0
    assert summary["phases"]["1"]["possible_visits"] == 1


def test_guest_phase_summary_closes_terminal_open_phase_at_exact_end() -> None:
    observer = _phase_observer(
        [
            _phase_transition(
                10,
                0,
                11,
                1,
                110,
                120,
                sample_index=2,
                batch_index=11,
            )
        ],
        current_steps=200,
        current_batches=20,
    )

    summary = acceptance_runner._guest_phase_summary(
        observer,
        expected_generation=23,
        window_end_steps=200,
    )

    assert summary["lifecycle_complete"] is False
    assert summary["attribution_complete"] is False
    assert summary["incomplete_open_phase"] == 1
    assert summary["window_end_phase"] == 1
    residency = summary["residencies"][0]
    assert residency["kind"] == "terminal-open"
    assert residency["end_step_lower_bound"] == 200
    assert residency["end_step_upper_bound"] == 200
    assert residency["retired_steps_lower_bound"] == 80
    assert residency["retired_steps_upper_bound"] == 90
    assert summary["phases"]["0"]["retired_steps_lower_bound"] == 10
    assert summary["phases"]["0"]["retired_steps_upper_bound"] == 20


def test_guest_phase_observer_error_remains_non_normative() -> None:
    observer = _phase_observer([], status="read_error")
    observer["error"] = {
        "kind": "MemoryError",
        "message": "diagnostic read failed",
    }

    summary = acceptance_runner._guest_phase_summary(
        observer,
        expected_generation=23,
        window_end_steps=200,
    )

    assert summary["observer_status"] == "read_error"
    assert summary["observer_error"] == observer["error"]
    assert summary["lifecycle_complete"] is False
    assert summary["attribution_complete"] is False


def test_phase_profile_finish_preserves_raw_snapshot_on_summary_failure() -> None:
    transition = _phase_transition(
        10,
        0,
        11,
        1,
        121,
        120,
        sample_index=2,
        batch_index=11,
    )
    raw_observer = _phase_observer([transition])
    client = _PhaseProfileClient(raw_observer)

    result = acceptance_runner._finish_guest_phase_profile(
        client,
        {
            "available": True,
            "expected_machine_generation": 23,
        },
        window_end_steps=200,
    )

    assert result["observer"] is raw_observer
    assert result["phase_summary"] is None
    assert result["summary_available"] is False
    assert result["profile_error"]["stage"] == "summarize"
    assert result["profile_error"]["kind"] == "ValueError"
    assert result["phase_names"]["1"] == "uidl_aggregate"


def test_hybrid_producer_diagnostic_schema_matches_the_forth_layout() -> None:
    source = (
        Path(acceptance_runner.__file__).resolve().parents[1]
        / "akashic/tui/rich-terminal/hybrid-screen-producer.f"
    ).read_text(encoding="utf-8")
    _pointer, cell_count, fields = acceptance_runner._GUEST_FAILURE_RECORDS[
        "hybrid_producer"
    ]

    assert re.search(r"(?m)^3008 CONSTANT RTHP-SIZE$", source)
    assert cell_count == 3008 // 8
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
        "target_active_address": 2200,
        "target_pending_address": 2208,
        "active_draw": 2232,
        "source_directory_bytes": 2264,
        "document_count": 2272,
        "row_damage_address": 2280,
        "row_damage_bytes": 2288,
        "glyph_id_map_address": 2296,
        "glyph_id_map_bytes": 2304,
        "delta_plan_valid": 2312,
        "delta_plan_active_address": 2320,
        "delta_plan_pending_address": 2328,
        "delta_plan_active_draw": 2336,
        "delta_plan_pending_draw": 2344,
        "delta_plan_control_count": 2352,
        "delta_plan_glyph_count": 2360,
        "delta_plan_attempt": 2368,
        "delta_plan_source_generation": 2376,
        "delta_plan_pending_content": 2384,
        "delta_plan_active_content": 2392,
        "source_content_epoch": 2400,
        "max_collection_native": 2408,
        "max_collections": 2416,
        "max_controls": 2424,
        "source_menu_text_bytes": 2432,
        "collection_descriptor_bytes": 2456,
        "collection_native_bytes": 2480,
        "source_collection_count": 2488,
        "menu_control_count": 2496,
        "collection_count": 2504,
        "collection_items": 2512,
        "collection_utf8": 2520,
        "max_collection_descriptors": 2528,
        "max_data_graphics_native": 2800,
        "max_data_graphics_descriptors": 2808,
        "max_instrument_regions": 2816,
        "max_instruments": 2824,
        "data_graphics_descriptor_bytes": 2848,
        "data_graphics_native_bytes": 2872,
        "source_data_graphics_count": 2880,
        "instrument_unit_bytes": 2936,
        "instrument_region_count": 2960,
        "instrument_count": 2968,
        "instrument_claim_count": 2992,
        "base_claim_bytes": 3000,
    }
    assert {name: fields[name] * 8 for name in expected_offsets} == expected_offsets


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
    assert 0 <= row < rows
    assert 0 <= col and col + len(text) <= cols
    return GlyphRunDraw(
        object_id,
        0,
        ObjectBounds(col, row, len(text), 1),
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
        if row == 0:
            # The semantic menu bar exclusively owns the first logical row.
            continue
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
            ObjectBounds(0, 0, cols, 1),
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
                0,
                0,
                0,
                0,
                False,
                tuple(draws),
            ),
        ),
    )
    scope = DisplayScope(1, 1, 0, offer_id, 0, offer_id, offer_id)
    return TerminalDisplayOffer(offer_id, scope, snapshot, plane)


def _offer_with_instruments() -> tuple[
    TerminalDisplayOffer,
    set[tuple[int, int]],
]:
    """Build one base plane plus clipped and unclipped instrument regions."""

    cols = 12
    rows = 7
    offer = _offer("\n".join("." * cols for _ in range(rows)))
    base_region = offer.retained.regions[0]
    menu = base_region.draws[-1]
    clipped_draws = (
        ReadoutDraw(
            100_000,
            0,
            ObjectBounds(-1, 0, 4, 1),
            RGBA(255, 255, 255, 255),
            RGBA(0, 0, 0, 255),
            "42%",
            (
                ObjectBounds(1, 1, 7, 4),
                ObjectBounds(0, -1, 7, 4),
            ),
        ),
        MeterDraw(
            100_001,
            1,
            ObjectBounds(2, 1, 4, 1),
            RGBA(0, 255, 0, 255),
            RGBA(0, 0, 0, 255),
            False,
            True,
            0,
            100,
            42,
        ),
        StatusDraw(
            100_002,
            2,
            ObjectBounds(5, 2, 2, 2),
            RGBA(64, 64, 64, 255),
            RGBA(0, 255, 0, 255),
            1,
            0,
        ),
    )
    clipped_region = RetainedRegionDraw(
        owner_id=base_region.owner_id,
        owner_generation=base_region.owner_generation,
        region_id=2,
        logical_x=2,
        logical_y=1,
        logical_cols=8,
        logical_rows=4,
        clip_x=4,
        clip_y=1,
        clip_cols=4,
        clip_rows=4,
        z_order=1,
        clipped=True,
        draws=clipped_draws,
    )
    full_readout = ReadoutDraw(
        100_003,
        0,
        ObjectBounds(0, 0, 2, 1),
        RGBA(255, 255, 255, 255),
        RGBA(0, 0, 0, 255),
        "OK",
    )
    full_region = RetainedRegionDraw(
        owner_id=base_region.owner_id,
        owner_generation=base_region.owner_generation,
        region_id=3,
        logical_x=8,
        logical_y=5,
        logical_cols=2,
        logical_rows=1,
        clip_x=0,
        clip_y=0,
        clip_cols=0,
        clip_rows=0,
        z_order=2,
        clipped=False,
        draws=(full_readout,),
    )
    instrument_cells = (
        {(column, 1) for column in range(4, 6)}
        | {(column, 2) for column in range(4, 8)}
        | {(7, row) for row in range(3, 5)}
        | {(column, 5) for column in range(8, 10)}
    )
    menu_cells = {(column, 0) for column in range(cols)}
    base_region = replace(
        base_region,
        draws=(
            _glyph_draws_outside(cols, rows, instrument_cells | menu_cells)
            + (menu,)
        ),
    )
    return (
        replace(
            offer,
            retained=replace(
                offer.retained,
                regions=(base_region, clipped_region, full_region),
            ),
        ),
        instrument_cells,
    )


def _synthetic_content_state(
    text: tuple[str, ...] = (),
    *,
    primary_key: int = 0,
    primary_offset: int = 0,
    anchor_key: int = 0,
    anchor_offset: int = 0,
) -> tuple[object, ...]:
    """Build one STX1 value without retained-wire ControlIdentity."""

    scalar_text = " ".join(part for part in text if part)
    columns = max(1, len(scalar_text))
    content = SemanticTextContent(
        1,
        2,
        columns,
        0,
        0,
        2,
        columns,
        SemanticContentFlag(0),
        primary_key,
        primary_offset,
        anchor_key,
        anchor_offset,
        (
            SemanticTextItem(
                1,
                0,
                0,
                1,
                columns,
                SemanticTextRole.CONTENT,
                SemanticTextState(0),
                scalar_text,
            ),
            SemanticTextItem(
                2,
                1,
                0,
                1,
                columns,
                SemanticTextRole.CONTENT,
                SemanticTextState(0),
                "",
            ),
        ),
    )
    return acceptance_runner._semantic_text_content_state(content)


def _projection(text: str) -> RichScreenProjection:
    source_lines = tuple(text.split("\n"))
    columns = max(
        acceptance_runner.CANONICAL_DESKTOP_COLS,
        *(len(line) for line in source_lines),
    )
    rows = max(acceptance_runner.CANONICAL_DESKTOP_ROWS, len(source_lines))
    lines = tuple(
        (
            source_lines[row]
            if row < len(source_lines)
            else ""
        ).ljust(columns)
        for row in range(rows)
    )
    projection = RichScreenProjection(
        columns,
        rows,
        lines,
        sum(map(len, lines)),
        menu_bar_count=len(acceptance_runner.DESKTOP_MENU_SIGNATURES),
        menu_signatures=acceptance_runner.DESKTOP_MENU_SIGNATURES,
    )
    pad_left, pad_top, pad_right, pad_bottom = (
        acceptance_runner._desktop_tile_bounds(
            projection,
            acceptance_runner.PAD_DESKTOP_TILE,
        )
    )
    daybook_left, daybook_top, daybook_right, daybook_bottom = (
        acceptance_runner._desktop_tile_bounds(
            projection,
            acceptance_runner.DAYBOOK_DESKTOP_TILE,
        )
    )
    pad_visible_text = tuple(
        line[pad_left:pad_right]
        for line in lines[pad_top:pad_bottom]
        if line[pad_left:pad_right].strip()
    )
    pad_height = pad_bottom - pad_top
    if pad_height >= 2:
        output_top = min(
            pad_bottom - 1,
            pad_top + max(1, pad_height * 4 // 5),
        )
        editor_bottom = output_top
    else:
        editor_bottom = pad_bottom
        output_top = pad_top
    pad_revision = 2 if any(
        PAD_ACCEPTANCE_TEXT in line for line in pad_visible_text
    ) else 1
    if any(PAD_ACCEPTANCE_TEXT in line for line in pad_visible_text):
        pad_content = (PAD_ACCEPTANCE_TEXT,)
    elif any(
        acceptance_runner.DAYBOOK_SHARED_SOURCE_MARKER in line
        for line in pad_visible_text
    ):
        pad_content = (
            acceptance_runner.DAYBOOK_SHARED_SOURCE_MARKER,
            DAYBOOK_ACCEPTANCE_TASK,
        )
    else:
        pad_content = ()
    pad_root_state = ControlState.VISIBLE | ControlState.ENABLED
    if PAD_FOCUS_MARKER in text:
        pad_root_state |= ControlState.SELECTED
    return replace(
        projection,
        semantic_collection_claims=(
            acceptance_runner._SemanticCollectionClaim(
                ControlKind.TEXT_AREA,
                ControlIdentity(1, 1, 20_000),
                pad_left,
                pad_top,
                pad_right,
                editor_bottom,
                visible_text=pad_visible_text,
                content_revision=pad_revision,
                content_state=_synthetic_content_state(pad_content),
                state=pad_root_state,
            ),
            acceptance_runner._SemanticCollectionClaim(
                ControlKind.TEXT_AREA,
                ControlIdentity(1, 1, 20_002),
                pad_left,
                output_top,
                pad_right,
                pad_bottom,
                visible_text=(),
                content_revision=1,
                content_state=_synthetic_content_state(),
            ),
            acceptance_runner._SemanticCollectionClaim(
                ControlKind.TEXT_GRID,
                ControlIdentity(1, 1, 20_001),
                daybook_left,
                daybook_top,
                daybook_right,
                daybook_bottom,
                content_revision=1,
                primary_key=1,
                content_state=_synthetic_content_state(primary_key=1),
            ),
        ),
        semantic_tabset_claims=(
            _pad_tabset_claim(projection),
        ),
    )


def _pad_tabset_claim(
    projection: RichScreenProjection,
    *,
    labels: tuple[str, ...] = ("Untitled",),
    selected: int = 0,
    identity_base: int = 30_000,
) -> acceptance_runner._SemanticTabSetClaim:
    left, top, right, bottom = acceptance_runner._desktop_tile_bounds(
        projection,
        acceptance_runner.PAD_DESKTOP_TILE,
    )
    return acceptance_runner._SemanticTabSetClaim(
        ControlIdentity(1, 1, identity_base),
        ControlState.VISIBLE | ControlState.ENABLED,
        left,
        top,
        right,
        bottom,
        tuple(
            acceptance_runner._SemanticTabClaim(
                ControlIdentity(1, 1, identity_base + 1 + order),
                ControlState.VISIBLE
                | ControlState.ENABLED
                | (
                    ControlState.SELECTED
                    if order == selected
                    else ControlState(0)
                ),
                order,
                label,
                "",
            )
            for order, label in enumerate(labels)
        ),
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


def _daybook_prompt_projection(
    *,
    task_visible: bool = False,
    focused: bool = True,
) -> RichScreenProjection:
    """Model RUHA's document-atomic fallback under Daybook's prompt."""

    seed = _projection("")
    daybook_left, _, _, daybook_bottom = acceptance_runner._desktop_tile_bounds(
        seed,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
    )
    prompt_text = DAYBOOK_PROMPT_MARKER
    if task_visible:
        prompt_text += DAYBOOK_ACCEPTANCE_TASK
    placements = [(daybook_bottom - 2, daybook_left + 1, prompt_text)]
    if focused:
        placements.append((83, 0, DAYBOOK_FOCUS_MARKER))
    projection = _desktop_projection(*placements)
    unaffected_menus = tuple(
        signature
        for signature in acceptance_runner.DESKTOP_MENU_SIGNATURES
        if signature != acceptance_runner.DAYBOOK_MENU_SIGNATURE
    )
    daybook_grids = acceptance_runner._collection_claims_in_tile(
        projection,
        ControlKind.TEXT_GRID,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
    )
    assert len(daybook_grids) == 1
    return replace(
        projection,
        menu_bar_count=len(unaffected_menus),
        menu_signatures=unaffected_menus,
        semantic_collection_claims=tuple(
            claim
            for claim in projection.semantic_collection_claims
            if claim not in daybook_grids
        ),
    )


def _daybook_projection(
    *,
    task_visible: bool,
    pad_tab_identity_base: int = 30_000,
    date: str | None = None,
) -> RichScreenProjection:
    if date is None:
        date = (
            TEST_DAYBOOK_INITIAL_DATE
            if task_visible
            else TEST_DAYBOOK_NEXT_DATE
        )
    placements = [
        (0, 190, DAYBOOK_FOCUS_MARKER),
        (1, 190, date),
    ]
    if task_visible:
        placements.append((5, 190, DAYBOOK_ACCEPTANCE_TASK))
    projection = _desktop_projection(*placements)
    projection = replace(
        projection,
        semantic_tabset_claims=(
            _pad_tabset_claim(
                projection,
                labels=("Untitled*",),
                identity_base=pad_tab_identity_base,
            ),
        ),
    )
    if task_visible:
        return projection
    return replace(
        projection,
        semantic_collection_claims=tuple(
            replace(
                claim,
                content_revision=2,
                primary_key=2,
                content_state=_synthetic_content_state(primary_key=2),
            )
            if claim.kind is ControlKind.TEXT_GRID
            else claim
            for claim in projection.semantic_collection_claims
        ),
    )


def _handoff_projection(
    *,
    pad_tile: bool,
    pad_tab_identity_base: int = 30_000,
) -> RichScreenProjection:
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
    projection = _desktop_projection(*placements)
    return replace(
        projection,
        semantic_collection_claims=tuple(
            replace(claim, content_revision=3)
            if (
                pad_tile
                and claim.kind is ControlKind.TEXT_AREA
                and claim.identity.control_id == 20_000
            )
            else claim
            for claim in projection.semantic_collection_claims
        ),
        semantic_tabset_claims=(
            _pad_tabset_claim(
                projection,
                labels=("Untitled*", "/daybook.md"),
                selected=1,
                identity_base=pad_tab_identity_base,
            ),
        ),
    )


def _activated_pad_tab_projection(
    *,
    pad_tab_identity_base: int = 30_000,
) -> RichScreenProjection:
    projection = _desktop_projection(
        (0, 1, PAD_FOCUS_MARKER),
        (4, 4, PAD_ACCEPTANCE_TEXT),
    )
    projection = replace(
        projection,
        semantic_collection_claims=tuple(
            replace(claim, content_revision=4)
            if (
                claim.kind is ControlKind.TEXT_AREA
                and claim.identity.control_id == 20_000
            )
            else replace(
                claim,
                content_revision=2,
                primary_key=2,
                content_state=_synthetic_content_state(primary_key=2),
            )
            if claim.kind is ControlKind.TEXT_GRID
            else claim
            for claim in projection.semantic_collection_claims
        ),
    )
    return replace(
        projection,
        semantic_tabset_claims=(
            _pad_tabset_claim(
                projection,
                labels=("Untitled*", "/daybook.md"),
                selected=0,
                identity_base=pad_tab_identity_base,
            ),
        ),
    )


def _desk_launcher_projection(selected_title: str) -> RichScreenProjection:
    assert selected_title in acceptance_runner.DESKTOP_LAUNCHER_TITLES
    entries = tuple(
        (
            acceptance_runner.DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index,
            acceptance_runner.DESKTOP_LAUNCHER_MARKER_COL,
            f"{'>' if title == selected_title else ' '} {title} ready",
        )
        for index, title in enumerate(
            acceptance_runner.DESKTOP_LAUNCHER_TITLES
        )
    )
    return _desktop_projection(
        (
            acceptance_runner.DESKTOP_LAUNCHER_TOP,
            acceptance_runner.DESKTOP_LAUNCHER_HEADER_COL,
            "Applets",
        ),
        (
            acceptance_runner.DESKTOP_LAUNCHER_TOP + 1,
            acceptance_runner.DESKTOP_LAUNCHER_HEADER_COL,
            "select an applet",
        ),
        *entries,
    )


def _soundlab_desktop_projection(
    *,
    pad_tab_identity_base: int = 30_000,
    daybook_date: str = TEST_DAYBOOK_NEXT_DATE,
) -> RichScreenProjection:
    projection = _desktop_projection(
        (4, 4, PAD_ACCEPTANCE_TEXT),
        (1, 190, daybook_date),
        (44, 190, "SOUND LAB"),
        (83, 0, acceptance_runner.SOUNDLAB_FOCUS_MARKER),
    )
    projection = replace(
        projection,
        semantic_collection_claims=tuple(
            replace(claim, content_revision=5)
            if (
                claim.kind is ControlKind.TEXT_AREA
                and claim.identity.control_id == 20_000
            )
            else replace(
                claim,
                content_revision=5,
                primary_key=2,
                content_state=_synthetic_content_state(primary_key=2),
            )
            if claim.kind is ControlKind.TEXT_GRID
            else claim
            for claim in projection.semantic_collection_claims
        ),
        semantic_tabset_claims=(
            _pad_tabset_claim(
                projection,
                labels=("Untitled*", "/daybook.md"),
                selected=0,
                identity_base=pad_tab_identity_base,
            ),
        ),
    )
    kinds = ("READOUT",) * 8 + ("METER",) * 2 + ("STATUS",) * 3
    claims = tuple(
        acceptance_runner._InstrumentClaim(
            kind,
            1,
            1,
            40_000 + index,
            190 + index,
            44,
            191 + index,
            45,
        )
        for index, kind in enumerate(kinds)
    )
    return replace(
        projection,
        menu_bar_count=len(acceptance_runner.DESKTOP_MENU_SIGNATURES) + 1,
        menu_signatures=(
            acceptance_runner.DESKTOP_MENU_SIGNATURES
            + (acceptance_runner.SOUNDLAB_MENU_SIGNATURE,)
        ),
        region_count=2,
        instrument_region_count=1,
        instrument_cell_count=len(claims),
        instrument_claims=claims,
    )


def _rebase_semantic_control_ids(
    projection: RichScreenProjection,
    offset: int,
) -> RichScreenProjection:
    """Model fresh graph IDs assigned by complete RET_REPLACE_START."""

    def rebased(identity: ControlIdentity) -> ControlIdentity:
        return ControlIdentity(
            identity.owner_id,
            identity.owner_generation,
            identity.control_id + offset,
        )

    return replace(
        projection,
        semantic_collection_claims=tuple(
            replace(claim, identity=rebased(claim.identity))
            for claim in projection.semantic_collection_claims
        ),
        semantic_tabset_claims=tuple(
            replace(
                tabset,
                identity=rebased(tabset.identity),
                tabs=tuple(
                    replace(tab, identity=rebased(tab.identity))
                    for tab in tabset.tabs
                ),
            )
            for tabset in projection.semantic_tabset_claims
        ),
    )


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


def _offer_with_pad_tabs(
    *,
    offer_id: int,
) -> tuple[TerminalDisplayOffer, tuple[ControlHitTarget, ...]]:
    cols = 12
    rows = 7
    offer = _offer(
        "\n".join("." * cols for _ in range(rows)),
        offer_id=offer_id,
        pad_menu=True,
    )
    region = offer.retained.regions[0]
    ordinary = ControlState.VISIBLE | ControlState.ENABLED
    tabset = TabSetDraw(
        30_000,
        ordinary,
        0,
        1,
        ObjectBounds(0, 1, 4, 2),
        (
            TabDraw(30_001, ordinary, 0, "Untitled*", ""),
            TabDraw(
                30_002,
                ordinary | ControlState.SELECTED,
                1,
                "/daybook.md",
                "",
            ),
        ),
    )
    offer = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(region, draws=region.draws + (tabset,)),
            ),
        ),
    )
    identities = tuple(
        ControlIdentity(
            region.owner_id,
            region.owner_generation,
            tab.control_id,
        )
        for tab in tabset.tabs
    )
    targets = (
        ControlHitTarget(
            identities[0],
            ControlKind.TAB,
            PixelRect(2, 20, 42, 40),
        ),
        ControlHitTarget(
            identities[1],
            ControlKind.TAB,
            PixelRect(44, 20, 90, 40),
        ),
    )
    return offer, targets


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
    assert projection.draw_count == 2
    assert projection.glyph_cell_count == 2
    assert projection.menu_bar_count == 1
    assert projection.lines == ("  ", "CD")
    assert projection.semantic_lines == ("File",)
    assert projection.text == "  \nCD\nFile"

    glyph, menu = offer.retained.regions[0].draws
    missing = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    offer.retained.regions[0],
                    draws=(
                        _glyph_run(99, 1, 0, "C", cols=2, rows=2),
                        menu,
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


def test_projection_accepts_cell_rect_instruments_across_clipped_regions() -> None:
    offer, instrument_cells = _offer_with_instruments()

    projection = reconstruct_retained_screen(offer)

    assert projection.region_count == 3
    assert projection.instrument_region_count == 2
    assert projection.clipped_region_count == 1
    assert projection.instrument_cell_count == len(instrument_cells) == 10
    assert projection.readout_count == 2
    assert projection.meter_count == 1
    assert projection.status_count == 1
    assert tuple(
        (
            claim.kind,
            claim.object_id,
            claim.left,
            claim.top,
            claim.right,
            claim.bottom,
        )
        for claim in projection.instrument_claims
    ) == (
        ("READOUT", 100_000, 4, 1, 6, 2),
        ("METER", 100_001, 4, 2, 8, 3),
        ("STATUS", 100_002, 7, 3, 8, 5),
        ("READOUT", 100_003, 8, 5, 10, 6),
    )
    assert projection.draw_count == sum(
        len(region.draws) for region in offer.retained.regions
    )
    assert "OK" not in projection.text
    assert "42%" not in projection.text
    assert DesktopAcceptanceJourney._offer_lineage(offer, 9)[-2:] == (1, 1)

    base_region, clipped_region, full_region = offer.retained.regions
    instrument_underlay = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(clipped_region, z_order=0),
                replace(base_region, z_order=1),
                full_region,
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="instrument region precedes",
    ):
        reconstruct_retained_screen(instrument_underlay)

    invalid_clip = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                base_region,
                replace(clipped_region, clip_x=1),
                full_region,
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="outside its logical/surface intersection",
    ):
        reconstruct_retained_screen(invalid_clip)


def test_projection_rejects_residual_glyphs_under_instrument_claims() -> None:
    offer, _instrument_cells = _offer_with_instruments()
    base_region, *instrument_regions = offer.retained.regions
    menu = base_region.draws[-1]
    overlap = _glyph_run(90_000, 1, 4, ".", cols=12, rows=7)
    base_region = replace(
        base_region,
        draws=base_region.draws[:-1] + (overlap, menu),
    )
    crossed = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(base_region, *instrument_regions),
        ),
    )

    with pytest.raises(PhysicalDesktopAcceptanceError, match="instrument claims"):
        reconstruct_retained_screen(crossed)


def test_projection_rejects_instrument_region_from_another_owner() -> None:
    offer, _instrument_cells = _offer_with_instruments()
    base_region, clipped_region, full_region = offer.retained.regions
    mixed_owner = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                base_region,
                replace(clipped_region, owner_id=2),
                full_region,
            ),
        ),
    )

    with pytest.raises(PhysicalDesktopAcceptanceError, match="one retained owner"):
        DesktopAcceptanceJourney._offer_lineage(mixed_owner, 9)
    with pytest.raises(PhysicalDesktopAcceptanceError, match="aggregate owner"):
        reconstruct_retained_screen(mixed_owner)


def test_projection_rejects_invalid_run_coverage_and_requires_semantics() -> None:
    offer = _offer("AB\nCD")
    region = offer.retained.regions[0]
    glyph, menu = region.draws

    mismatch = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(replace(glyph, text="C"), menu)),),
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
                    draws=(glyph, replace(glyph, object_id=99), menu),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="overlaps"):
        reconstruct_retained_screen(overlap)

    crossing = replace(
        glyph,
        bounds=ObjectBounds(
            glyph.bounds.cell_x,
            0,
            glyph.bounds.cell_cols,
            2,
        ),
    )
    crossed = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(crossing, menu)),),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="geometry"):
        reconstruct_retained_screen(crossed)

    partially_offscreen_glyph = replace(
        glyph,
        bounds=replace(glyph.bounds, cell_x=-1),
    )
    partial_glyph_offer = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(partially_offscreen_glyph, menu),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="wholly inside"):
        reconstruct_retained_screen(partial_glyph_offer)

    partially_offscreen_menu = replace(
        menu,
        bounds=replace(menu.bounds, cell_x=-1),
    )
    partial_menu_offer = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(glyph, partially_offscreen_menu),
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="wholly inside"):
        reconstruct_retained_screen(partial_menu_offer)

    no_menu = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(glyph,)),),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="semantic menu"):
        reconstruct_retained_screen(no_menu)


def test_semantic_menu_bounds_may_complete_glyph_coverage() -> None:
    offer = _offer("AB\nCD")
    region = offer.retained.regions[0]
    glyph, menu = region.draws
    semantic_first_row = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(replace(region, draws=(glyph, menu)),),
        ),
    )
    projection = reconstruct_retained_screen(semantic_first_row)
    assert projection.lines == ("  ", "CD")
    assert projection.semantic_lines == ("File",)
    assert projection.glyph_cell_count == 2


def test_semantic_text_claims_complete_coverage_and_feed_tile_text() -> None:
    cols = 12
    rows = 7
    offer = _offer("\n".join("." * cols for _ in range(rows)))
    region = offer.retained.regions[0]
    menu = region.draws[-1]
    visible_enabled = ControlState.VISIBLE | ControlState.ENABLED
    area_content = SemanticTextContent(
        1,
        2,
        4,
        0,
        0,
        2,
        4,
        SemanticContentFlag(0),
        1,
        4,
        0,
        0,
        (
            SemanticTextItem(
                1,
                0,
                0,
                1,
                4,
                SemanticTextRole.CONTENT,
                SemanticTextState(0),
                "~abc",
            ),
            SemanticTextItem(
                2,
                1,
                0,
                1,
                4,
                SemanticTextRole.CONTENT,
                SemanticTextState(0),
                "pad",
            ),
        ),
    )
    grid_content = SemanticTextContent(
        1,
        2,
        2,
        0,
        0,
        2,
        2,
        SemanticContentFlag(0),
        12,
        0,
        0,
        0,
        (
            SemanticTextItem(
                10,
                0,
                0,
                1,
                2,
                SemanticTextRole.COLUMN_HEADER,
                SemanticTextState(0),
                "Aug",
            ),
            SemanticTextItem(
                11,
                1,
                0,
                1,
                1,
                SemanticTextRole.CONTENT,
                SemanticTextState(0),
                "31",
            ),
            SemanticTextItem(
                12,
                1,
                1,
                1,
                1,
                SemanticTextRole.CONTENT,
                SemanticTextState.CURRENT,
                "^",
            ),
        ),
    )
    area = TextAreaDraw(
        20_000,
        visible_enabled | ControlState.SELECTED,
        0,
        1,
        ObjectBounds(0, 1, 4, 2),
        area_content,
    )
    grid = TextGridDraw(
        20_001,
        visible_enabled | ControlState.SELECTED,
        0,
        1,
        ObjectBounds(8, 1, 4, 2),
        grid_content,
    )
    claim_cells = {
        (col, row)
        for row in range(1, 3)
        for col in range(cols)
        if col < 4 or col >= 8
    } | {(col, 0) for col in range(cols)}
    claimed = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=(
                        *_glyph_draws_outside(cols, rows, claim_cells),
                        menu,
                        area,
                        grid,
                    ),
                ),
            ),
        ),
    )

    projection = reconstruct_retained_screen(claimed)
    assert projection.text_area_count == 1
    assert projection.text_grid_count == 1
    assert "~abc" in projection.text
    assert "Aug" not in projection.text
    assert "^" not in projection.text
    area_claim = next(
        claim
        for claim in projection.semantic_collection_claims
        if claim.kind is ControlKind.TEXT_AREA
    )
    grid_claim = next(
        claim
        for claim in projection.semantic_collection_claims
        if claim.kind is ControlKind.TEXT_GRID
    )
    assert area_claim.content_state == (
        2,
        4,
        0,
        0,
        2,
        4,
        0,
        1,
        4,
        0,
        0,
        (
            (
                1,
                0,
                0,
                1,
                4,
                int(SemanticTextRole.CONTENT),
                0,
                "~abc",
            ),
            (
                2,
                1,
                0,
                1,
                4,
                int(SemanticTextRole.CONTENT),
                0,
                "pad",
            ),
        ),
    )
    assert area_claim.state == visible_enabled | ControlState.SELECTED
    assert grid_claim.visible_text == ()
    assert grid_claim.content_revision == 1
    assert grid_claim.primary_key == 12
    assert grid_claim.current_item_keys == (12,)
    assert grid_claim.content_state == (
        2,
        2,
        0,
        0,
        2,
        2,
        0,
        12,
        0,
        0,
        0,
        (
            (
                10,
                0,
                0,
                1,
                2,
                int(SemanticTextRole.COLUMN_HEADER),
                0,
                "Aug",
            ),
            (
                11,
                1,
                0,
                1,
                1,
                int(SemanticTextRole.CONTENT),
                0,
                "31",
            ),
            (
                12,
                1,
                1,
                1,
                1,
                int(SemanticTextRole.CONTENT),
                int(SemanticTextState.CURRENT),
                "^",
            ),
        ),
    )
    assert grid_claim.state == visible_enabled | ControlState.SELECTED
    assert acceptance_runner._desktop_tile_contains(projection, "~", 0)
    assert not acceptance_runner._desktop_tile_contains(projection, "^", 2)
    assert not acceptance_runner._desktop_tile_contains(projection, "^", 0)

    instrument = ReadoutDraw(
        90_000,
        0,
        ObjectBounds(0, 0, 1, 1),
        RGBA(255, 255, 255, 255),
        RGBA(0, 0, 0, 255),
        "cover",
    )
    covering_region = RetainedRegionDraw(
        region.owner_id,
        region.owner_generation,
        2,
        0,
        1,
        1,
        1,
        0,
        0,
        0,
        0,
        1,
        False,
        (instrument,),
    )
    covered = replace(
        claimed,
        retained=replace(
            claimed.retained,
            regions=(claimed.retained.regions[0], covering_region),
        ),
    )
    covered_projection = reconstruct_retained_screen(covered)
    assert covered_projection.text_area_count == 0
    assert covered_projection.text_grid_count == 1
    assert "~abc" not in covered_projection.text
    assert "cover" not in covered_projection.text

    lower_region = replace(covering_region, z_order=-1)
    revealed = replace(
        claimed,
        retained=replace(
            claimed.retained,
            regions=(lower_region, claimed.retained.regions[0]),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="instrument region precedes",
    ):
        reconstruct_retained_screen(revealed)


def test_semantic_tabset_claims_complete_coverage_and_preserve_tab_state() -> None:
    cols = 12
    rows = 7
    offer = _offer("\n".join("." * cols for _ in range(rows)))
    region = offer.retained.regions[0]
    menu = region.draws[-1]
    ordinary = ControlState.VISIBLE | ControlState.ENABLED
    tabset = TabSetDraw(
        30_000,
        ordinary,
        0,
        1,
        ObjectBounds(0, 1, 4, 2),
        (
            TabDraw(30_001, ordinary, 0, "Untitled", ""),
            TabDraw(
                30_002,
                ordinary | ControlState.SELECTED,
                1,
                "/daybook.md",
                "Ctrl+2",
            ),
        ),
    )
    claim_cells = {
        (col, row)
        for row in range(1, 3)
        for col in range(4)
    } | {(col, 0) for col in range(cols)}
    claimed = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=_glyph_draws_outside(cols, rows, claim_cells)
                    + (menu, tabset),
                ),
            ),
        ),
    )

    projection = reconstruct_retained_screen(claimed)
    assert projection.tabset_count == 1
    assert projection.tab_signatures == (("Untitled", "/daybook.md"),)
    assert projection.selected_tab_labels == (("/daybook.md",),)
    assert projection.selected_tab_identities == (
        (ControlIdentity(region.owner_id, region.owner_generation, 30_002),),
    )
    assert "Untitled [/daybook.md] (Ctrl+2)" in projection.text
    claim = projection.semantic_tabset_claims[0]
    assert (claim.left, claim.top, claim.right, claim.bottom) == (0, 1, 4, 3)
    assert claim.selected_tabs[0].control_id == 30_002

    overlapped = replace(
        claimed,
        retained=replace(
            claimed.retained,
            regions=(
                replace(
                    claimed.retained.regions[0],
                    draws=(
                        claimed.retained.regions[0].draws[:-2]
                        + (
                            _glyph_run(
                                90_000,
                                1,
                                0,
                                ".",
                                cols=cols,
                                rows=rows,
                            ),
                        )
                        + claimed.retained.regions[0].draws[-2:]
                    ),
                ),
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="overlap semantic root claims",
    ):
        reconstruct_retained_screen(overlapped)


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
    exact_draws = []
    object_id = 1
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

    underlay_content = SemanticTextContent(
        1,
        13,
        13,
        0,
        0,
        13,
        13,
        SemanticContentFlag(0),
        1,
        0,
        0,
        0,
        (
            SemanticTextItem(
                1,
                0,
                0,
                1,
                13,
                SemanticTextRole.CONTENT,
                SemanticTextState(0),
                "underlay",
            ),
        ),
    )
    underlay = TextAreaDraw(
        9_000,
        ControlState.VISIBLE | ControlState.ENABLED,
        0,
        0,
        ObjectBounds(1, 1, 13, 13),
        underlay_content,
    )
    semantic_underlay = replace(
        exact_gap,
        retained=replace(
            exact_gap.retained,
            regions=(
                replace(
                    region,
                    draws=tuple(exact_draws[:-1]) + (underlay, menu),
                ),
            ),
        ),
    )
    underlay_projection = reconstruct_retained_screen(semantic_underlay)
    assert underlay_projection.renderer_owned_gap_cells == 13 * 13
    assert underlay_projection.text_area_count == 1
    assert "underlay" in underlay_projection.text

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
        ObjectBounds(0, 0, cols, 1),
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
    root_claim = {(col, 0) for col in range(cols)}
    offer = _offer("\n".join("." * cols for _ in range(rows)))
    region = offer.retained.regions[0]
    exact = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=_glyph_draws_outside(
                        cols,
                        rows,
                        expected_gap | root_claim,
                    )
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
                    draws=_glyph_draws_outside(
                        cols,
                        rows,
                        shifted_gap | root_claim,
                    )
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
        ObjectBounds(0, 0, 20, 1),
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
        ObjectBounds(20, 7, 20, 1),
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
    popup_gaps = first_gap | second_gap
    bar_claims = (
        {(col, 0) for col in range(20)}
        | {(col, 7) for col in range(20, 40)}
    )
    all_claims = popup_gaps | bar_claims
    offer = _offer("\n".join("." * cols for _ in range(rows)))
    region = offer.retained.regions[0]
    exact = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    region,
                    draws=_glyph_draws_outside(cols, rows, all_claims)
                    + (bar_one, bar_two),
                ),
            ),
        ),
    )
    projection = reconstruct_retained_screen(exact)
    assert projection.renderer_owned_gap_cells == len(popup_gaps)
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
        ObjectBounds(0, 0, 20, 1),
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
    acceptance_runner._require_canonical_desktop_semantics(projection)

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

    with pytest.raises(PhysicalDesktopAcceptanceError, match="TEXT_AREA"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_collection_claims=tuple(
                    claim
                    for claim in projection.semantic_collection_claims
                    if claim.kind is not ControlKind.TEXT_AREA
                ),
            )
        )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="TEXT_GRID"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_collection_claims=tuple(
                    claim
                    for claim in projection.semantic_collection_claims
                    if claim.kind is not ControlKind.TEXT_GRID
                ),
            )
        )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="visibly enabled"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_collection_claims=tuple(
                    replace(claim, state=claim.state & ~ControlState.ENABLED)
                    if claim.kind is ControlKind.TEXT_AREA
                    else claim
                    for claim in projection.semantic_collection_claims
                ),
            )
        )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="visibly enabled"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_collection_claims=tuple(
                    replace(claim, state=claim.state & ~ControlState.ENABLED)
                    if claim.kind is ControlKind.TEXT_GRID
                    else claim
                    for claim in projection.semantic_collection_claims
                ),
            )
        )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="TABSET"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(projection, semantic_tabset_claims=())
        )

    pad_tabset = projection.semantic_tabset_claims[0]
    with pytest.raises(PhysicalDesktopAcceptanceError, match="selected tab"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_tabset_claims=(
                    replace(
                        pad_tabset,
                        tabs=tuple(
                            replace(
                                tab,
                                state=tab.state & ~ControlState.SELECTED,
                            )
                            for tab in pad_tabset.tabs
                        ),
                    ),
                ),
            )
        )

    pad_claims = tuple(
        claim
        for claim in projection.semantic_collection_claims
        if claim.kind is ControlKind.TEXT_AREA
    )
    assert len(pad_claims) == 2
    pad_claim = next(
        claim for claim in pad_claims if claim.identity.control_id == 20_000
    )
    daybook_claim = next(
        claim
        for claim in projection.semantic_collection_claims
        if claim.kind is ControlKind.TEXT_GRID
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="exactly one TEXT_GRID",
    ):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_collection_claims=projection.semantic_collection_claims
                + (
                    replace(
                        daybook_claim,
                        identity=ControlIdentity(1, 1, 21_001),
                    ),
                ),
            )
        )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="Pad tile"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_collection_claims=tuple(
                    replace(
                        claim,
                        left=daybook_claim.left,
                        right=daybook_claim.right,
                    )
                    if claim.kind is ControlKind.TEXT_AREA
                    else claim
                    for claim in projection.semantic_collection_claims
                ),
            )
        )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="Daybook tile"):
        acceptance_runner._require_canonical_desktop_semantics(
            replace(
                projection,
                semantic_collection_claims=tuple(
                    replace(
                        claim,
                        left=pad_claim.left,
                        right=pad_claim.right,
                    )
                    if claim.kind is ControlKind.TEXT_GRID
                    else claim
                    for claim in projection.semantic_collection_claims
                ),
            )
        )

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


def test_daybook_prompt_gate_requires_exact_document_atomic_fallback() -> None:
    prompt = _daybook_prompt_projection()
    acceptance_runner._require_daybook_prompt_fallback_semantics(prompt)

    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="four unaffected canonical menu forests",
    ):
        acceptance_runner._require_daybook_prompt_fallback_semantics(
            replace(
                prompt,
                menu_bar_count=prompt.menu_bar_count + 1,
                menu_signatures=prompt.menu_signatures
                + (acceptance_runner.DAYBOOK_MENU_SIGNATURE,),
            )
        )

    complete = _projection("READY")
    daybook_grid = acceptance_runner._collection_claims_in_tile(
        complete,
        ControlKind.TEXT_GRID,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
    )
    assert len(daybook_grid) == 1
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="partial text collection",
    ):
        acceptance_runner._require_daybook_prompt_fallback_semantics(
            replace(
                prompt,
                semantic_collection_claims=(
                    prompt.semantic_collection_claims + daybook_grid
                ),
            )
        )

    with pytest.raises(PhysicalDesktopAcceptanceError, match="TEXT_AREA"):
        acceptance_runner._require_daybook_prompt_fallback_semantics(
            replace(
                prompt,
                semantic_collection_claims=tuple(
                    claim
                    for claim in prompt.semantic_collection_claims
                    if claim.kind is not ControlKind.TEXT_AREA
                ),
            )
        )

    daybook_left, daybook_top, daybook_right, daybook_bottom = (
        acceptance_runner._desktop_tile_bounds(
            prompt,
            acceptance_runner.DAYBOOK_DESKTOP_TILE,
        )
    )
    prompt_row = daybook_bottom - 2
    without_prompt = list(prompt.lines)
    without_prompt[prompt_row] = " " * prompt.cols
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="prompt is not visible inside its Desk tile",
    ):
        acceptance_runner._require_daybook_prompt_fallback_semantics(
            replace(prompt, lines=tuple(without_prompt))
        )

    pad_area = next(
        claim
        for claim in prompt.semantic_collection_claims
        if claim.kind is ControlKind.TEXT_AREA
    )
    semantic_prompt = replace(
        pad_area,
        identity=ControlIdentity(1, 1, 29_999),
        left=daybook_left,
        top=daybook_top,
        right=daybook_right,
        bottom=daybook_bottom,
        visible_text=(DAYBOOK_PROMPT_MARKER,),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="partial text collection",
    ):
        acceptance_runner._require_daybook_prompt_fallback_semantics(
            replace(
                prompt,
                lines=tuple(without_prompt),
                semantic_collection_claims=(
                    prompt.semantic_collection_claims + (semantic_prompt,)
                ),
            )
        )

    pad_tabset = prompt.semantic_tabset_claims[0]
    with pytest.raises(PhysicalDesktopAcceptanceError, match="partial TABSET"):
        acceptance_runner._require_daybook_prompt_fallback_semantics(
            replace(
                prompt,
                semantic_tabset_claims=prompt.semantic_tabset_claims
                + (
                    replace(
                        pad_tabset,
                        identity=ControlIdentity(1, 1, 39_999),
                        left=daybook_left,
                        top=daybook_top,
                        right=daybook_right,
                        bottom=daybook_bottom,
                    ),
                ),
            )
        )


def test_journey_selects_prompt_fallback_only_for_visible_modal_frames() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    journey.stage = 6
    actions: list[tuple[str, str, int]] = []
    rollover_initial = "2026-12-31"
    rollover_next = "2027-01-01"

    def sender(method, value, offer, _generation):
        actions.append((method, value, offer.offer_id))
        return "progress"

    journey.after_present(
        _offer("X", offer_id=1, pad_menu=True),
        9,
        _projection(DAYBOOK_FOCUS_MARKER),
        sender,
    )
    assert journey.stage == 6
    assert actions == []

    journey.after_present(
        _offer("X", offer_id=2, pad_menu=True),
        9,
        _daybook_prompt_projection(),
        sender,
    )
    assert journey.stage == 7
    assert actions == [("send_text", DAYBOOK_ACCEPTANCE_TASK, 2)]

    journey.after_present(
        _offer("X", offer_id=3, pad_menu=True),
        9,
        _daybook_prompt_projection(task_visible=True),
        sender,
    )
    assert journey.stage == 8
    assert actions[-1] == ("send_key", "enter", 3)

    journey.after_present(
        _offer("X", offer_id=4, pad_menu=True),
        9,
        _daybook_prompt_projection(task_visible=True),
        sender,
    )
    assert journey.stage == 8
    assert len(actions) == 2

    progress = journey.after_present(
        _offer("X", offer_id=5, pad_menu=True),
        9,
        _daybook_projection(task_visible=True, date=rollover_initial),
        sender,
    )
    assert progress.milestone == "daybook-task-added"
    assert journey.stage == 9
    assert actions[-1] == ("send_key", "right", 5)
    assert journey._daybook_initial_date == rollover_initial
    assert journey._daybook_next_date == rollover_next
    assert journey.final_cell_markers == (
        acceptance_runner.CELL_FINAL_STATIC_MARKERS + (rollover_next,)
    )

    progress = journey.after_present(
        _offer("X", offer_id=6, pad_menu=True),
        9,
        _daybook_projection(task_visible=False, date=rollover_next),
        sender,
    )
    assert progress.milestone == "daybook-date-advanced"
    assert journey.stage == 10
    assert actions[-1] == ("send_key", "ctrl+o", 6)

    outside = _daybook_prompt_projection()
    _, _, _, daybook_bottom = acceptance_runner._desktop_tile_bounds(
        outside,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
    )
    outside_lines = list(outside.lines)
    outside_lines[daybook_bottom - 2] = " " * outside.cols
    outside_lines[0] = DAYBOOK_PROMPT_MARKER.ljust(outside.cols)
    wrong_tile = DesktopAcceptanceJourney(("READY",))
    wrong_tile.stage = 6
    with pytest.raises(PhysicalDesktopAcceptanceError, match="every canonical"):
        wrong_tile.after_present(
            _offer("X", offer_id=1, pad_menu=True),
            9,
            replace(outside, lines=tuple(outside_lines)),
            sender,
        )


def test_collection_transition_matches_bounds_across_rebased_wire_ids() -> None:
    before = _projection(PAD_FOCUS_MARKER)
    prior = acceptance_runner._collection_states_in_tile(
        before,
        ControlKind.TEXT_AREA,
        acceptance_runner.PAD_DESKTOP_TILE,
    )
    assert len(prior) == 2

    edited = _rebase_semantic_control_ids(
        _projection(PAD_FOCUS_MARKER + PAD_ACCEPTANCE_TEXT),
        40_000,
    )
    matches = acceptance_runner._collection_claims_advanced_containing(
        edited,
        ControlKind.TEXT_AREA,
        acceptance_runner.PAD_DESKTOP_TILE,
        prior,
        PAD_ACCEPTANCE_TEXT,
        require_position_change=False,
    )

    assert len(matches) == 1
    assert matches[0].identity.control_id == 60_000


def test_collection_preservation_accepts_nonregressing_repacked_state() -> None:
    baseline = _daybook_projection(task_visible=False)
    prior = acceptance_runner._collection_states_in_tile(
        baseline,
        ControlKind.TEXT_GRID,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
    )
    assert len(prior) == 1

    equal_revision = _rebase_semantic_control_ids(baseline, 40_000)
    equal_matches = acceptance_runner._collection_claims_preserving_state(
        equal_revision,
        ControlKind.TEXT_GRID,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
        prior,
    )
    assert len(equal_matches) == 1
    assert equal_matches[0].identity.control_id == 60_001

    higher_rebase = _rebase_semantic_control_ids(baseline, 50_000)
    higher_revision = replace(
        higher_rebase,
        semantic_collection_claims=tuple(
            replace(claim, content_revision=5)
            if claim.kind is ControlKind.TEXT_GRID
            else claim
            for claim in higher_rebase.semantic_collection_claims
        ),
    )
    higher_matches = acceptance_runner._collection_claims_preserving_state(
        higher_revision,
        ControlKind.TEXT_GRID,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
        prior,
    )
    assert len(higher_matches) == 1
    assert higher_matches[0].content_revision == 5


def test_daybook_acceptance_dates_are_exact_tile_evidence() -> None:
    initial = _daybook_projection(task_visible=True)
    assert acceptance_runner._daybook_dates(initial) == (
        TEST_DAYBOOK_INITIAL_DATE,
    )
    assert (
        acceptance_runner._require_daybook_date(initial)
        == TEST_DAYBOOK_INITIAL_DATE
    )
    assert acceptance_runner._daybook_date_is(
        initial,
        TEST_DAYBOOK_INITIAL_DATE,
    )
    assert not acceptance_runner._daybook_date_is(
        initial,
        TEST_DAYBOOK_NEXT_DATE,
    )

    advanced = _daybook_projection(task_visible=False)
    assert acceptance_runner._daybook_date_is(
        advanced,
        TEST_DAYBOOK_NEXT_DATE,
    )
    assert not acceptance_runner._daybook_date_is(
        advanced,
        TEST_DAYBOOK_INITIAL_DATE,
    )

    wrong = _daybook_projection(task_visible=False, date="2026-09-04")
    assert not acceptance_runner._daybook_date_is(
        wrong,
        TEST_DAYBOOK_NEXT_DATE,
    )
    assert acceptance_runner._daybook_date_is(wrong, "2026-09-04")

    for malformed in ("2026-02-30", "2026-9-4"):
        with pytest.raises(ValueError, match="valid canonical ISO date"):
            acceptance_runner._daybook_date_is(advanced, malformed)
        malformed_header = _daybook_projection(
            task_visible=True,
            date=malformed,
        )
        assert acceptance_runner._daybook_dates(malformed_header) == ()
        assert not acceptance_runner._daybook_date_is(
            malformed_header,
            TEST_DAYBOOK_INITIAL_DATE,
        )
        with pytest.raises(
            PhysicalDesktopAcceptanceError,
            match="exactly one valid ISO calendar date",
        ):
            acceptance_runner._require_daybook_date(malformed_header)

    assert acceptance_runner._next_iso_date("2028-02-29") == "2028-03-01"
    assert acceptance_runner._next_iso_date("2026-12-31") == "2027-01-01"

    left, top, _, _ = acceptance_runner._desktop_tile_bounds(
        initial,
        acceptance_runner.DAYBOOK_DESKTOP_TILE,
    )
    extra_date = "2026-09-04"
    entry_lines = list(initial.lines)
    entry_row = top + 10
    entry_line = entry_lines[entry_row]
    entry_lines[entry_row] = (
        entry_line[: left + 1]
        + extra_date
        + entry_line[left + 1 + len(extra_date) :]
    )
    entry_date = replace(initial, lines=tuple(entry_lines))
    assert acceptance_runner._daybook_dates(entry_date) == (
        TEST_DAYBOOK_INITIAL_DATE,
    )

    ambiguous_lines = list(initial.lines)
    ambiguous_row = top + acceptance_runner.DAYBOOK_DATE_HEADER_ROW_OFFSET
    ambiguous_line = ambiguous_lines[ambiguous_row]
    extra_date_column = left + 20
    ambiguous_lines[ambiguous_row] = (
        ambiguous_line[:extra_date_column]
        + extra_date
        + ambiguous_line[extra_date_column + len(extra_date) :]
    )
    ambiguous = replace(initial, lines=tuple(ambiguous_lines))
    assert acceptance_runner._daybook_dates(ambiguous) == (
        TEST_DAYBOOK_INITIAL_DATE,
        extra_date,
    )
    assert not acceptance_runner._daybook_date_is(
        ambiguous,
        TEST_DAYBOOK_INITIAL_DATE,
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="exactly one valid ISO calendar date",
    ):
        acceptance_runner._require_daybook_date(ambiguous)


def test_final_cell_markers_require_the_acknowledged_daybook_date() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="no acknowledged Daybook navigation date",
    ):
        _ = journey.final_cell_markers


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


def test_scripted_event_pump_and_rpc_guard_fail_closed_on_manual_input(
    tmp_path: Path,
) -> None:
    class Events:
        @staticmethod
        def get():
            return [SimpleNamespace(type=2, pos=(12, 8))]

    class Pygame:
        QUIT = 1
        MOUSEMOTION = 2
        MOUSEBUTTONDOWN = 3
        MOUSEBUTTONUP = 4
        WINDOWFOCUSLOST = 5
        WINDOWFOCUSGAINED = 6
        event = Events()

    class Pointer:
        def move(self, *_args):
            raise AssertionError("rejected pointer event reached the interactor")

    class Keyboard:
        pending_events = 0
        last_error = None

        def flush_pending(self):
            raise AssertionError("rejected pointer event reached input flush")

    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="refuses manual pointer input",
    ):
        acceptance_runner._pump_physical_viewer_events(
            Pygame,
            Pointer(),
            Keyboard(),
            (2800, 1680),
            closing_is_error=True,
            reject_pointer_input=True,
        )

    class Client:
        @staticmethod
        def request(_method, **_params):
            return {"status": "progress"}

    trace = acceptance_runner._PerformanceTrace(tmp_path)
    traced = acceptance_runner._ManualInputTraceClient(Client(), trace)
    acceptance_runner._require_no_manual_scripted_input(traced)
    traced.request("send_key", generation=1, key="right")
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="manual viewer input.*rpc-count=1",
    ):
        acceptance_runner._require_no_manual_scripted_input(traced)


def test_scripted_pointer_input_is_blocked_and_startup_motion_is_cleared() -> None:
    class Events:
        calls = []

        @classmethod
        def set_blocked(cls, event_types):
            cls.calls.append(("blocked", tuple(event_types)))

        @classmethod
        def clear(cls, event_types):
            cls.calls.append(("cleared", tuple(event_types)))

    class Pygame:
        MOUSEMOTION = 2
        MOUSEBUTTONDOWN = 3
        MOUSEBUTTONUP = 4
        event = Events

    acceptance_runner._isolate_scripted_pointer_input(Pygame)
    assert Events.calls == [
        ("blocked", (2, 3, 4)),
        ("cleared", (2, 3, 4)),
    ]

    source = inspect.getsource(
        acceptance_runner.run_physical_desktop_acceptance
    )
    set_modes = [
        match.start()
        for match in re.finditer("pygame.display.set_mode\\(", source)
    ]
    isolates = [
        match.start()
        for match in re.finditer(
            "_isolate_scripted_pointer_input\\(pygame\\)", source
        )
    ]
    scripted_loop = source.index("while time.monotonic() < deadline:")
    assert len(set_modes) == len(isolates) == 2
    assert all(set_mode < isolate for set_mode, isolate in zip(set_modes, isolates))
    assert isolates[0] < scripted_loop < set_modes[1]


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


def test_pad_tab_activation_uses_exact_acknowledged_generic_tab_target() -> None:
    offer, targets = _offer_with_pad_tabs(offer_id=9)
    display_state, display_ack = _acknowledged_hit_state(offer, *targets)
    requests = []

    class Client:
        def request(self, method, **params):
            requests.append((method, params))
            return {"status": "progress", "accepted_events": 1}

    status, evidence = acceptance_runner._request_acceptance_input(
        Client(),
        "activate_pad_tab",
        str(targets[0].identity.control_id),
        offer,
        11,
        display_state=display_state,
        display_ack=display_ack,
    )

    assert status == "progress"
    assert requests == [
        (
            "send_control_event",
            {
                "generation": 11,
                "display_offer_id": offer.offer_id,
                "display_scope": acceptance_runner.display_scope_to_wire(
                    offer.scope
                ),
                "owner_id": targets[0].identity.owner_id,
                "owner_generation": targets[0].identity.owner_generation,
                "control_id": targets[0].identity.control_id,
                "modifiers": 0,
            },
        )
    ]
    assert evidence is not None
    assert evidence.method == "send_control_event"
    assert evidence.value == str(targets[0].identity.control_id)
    assert evidence.semantic_target == {
        "owner_id": targets[0].identity.owner_id,
        "owner_generation": targets[0].identity.owner_generation,
        "control_id": targets[0].identity.control_id,
        "kind": "TAB",
        "label": "Untitled*",
        "pixel_rect": {
            "left": targets[0].rect.left,
            "top": targets[0].rect.top,
            "right": targets[0].rect.right,
            "bottom": targets[0].rect.bottom,
        },
    }

    with pytest.raises(PhysicalDesktopAcceptanceError, match="unselected tab"):
        acceptance_runner._request_acceptance_input(
            Client(),
            "activate_pad_tab",
            str(targets[1].identity.control_id),
            offer,
            11,
            display_state=display_state,
            display_ack=display_ack,
        )

    missing_state, missing_ack = _acknowledged_hit_state(offer, targets[0])
    with pytest.raises(PhysicalDesktopAcceptanceError, match="exactly match"):
        acceptance_runner._request_acceptance_input(
            Client(),
            "activate_pad_tab",
            str(targets[0].identity.control_id),
            offer,
            11,
            display_state=missing_state,
            display_ack=missing_ack,
        )


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
    initial_cell_index = source.index(
        'initial_cell = _require_cell_fallback_evidence(', ack_index
    )
    journey_index = source.index("journey.after_present(", initial_cell_index)
    final_cell_index = source.index(
        'final_cell = _require_cell_fallback_evidence(', journey_index
    )
    manifest_index = source.index(
        "manifest = write_acceptance_manifest(", final_cell_index
    )

    assert "control_font=chrome_font" in source[compose_index:stage_index]
    assert "frame_result.hit_targets" in source[stage_index:present_index]
    assert "reject_pointer_input=closing_is_error" in source
    assert source.count("_require_no_manual_scripted_input(") >= 3
    assert "manual_input_rpc_count=manual_input_client.request_count" in source
    assert (
        "tuple(ready_markers) + journey.final_cell_markers"
        in source[final_cell_index:manifest_index]
    )
    assert source.index("keyboard.set_input_enabled(False)", manifest_index) > (
        manifest_index
    )
    assert (
        geometry_index
        < compose_index
        < stage_index
        < present_index
        < finish_index
        < ack_index
        < initial_cell_index
        < journey_index
        < final_cell_index
        < manifest_index
    )


def test_physical_runner_profiles_only_inside_exact_offer_backpressure() -> None:
    source = inspect.getsource(acceptance_runner.run_physical_desktop_acceptance)
    projection_index = source.index("_require_canonical_desktop_geometry(")
    profile_start_index = source.index(
        "phase_capture = _start_guest_phase_profile(", projection_index
    )
    present_index = source.index(
        "presentation = draw_flip_and_present(", profile_start_index
    )
    journey_index = source.index("progress = journey.after_present(", present_index)
    profile_stop_index = source.index(
        "profile_result = _finish_guest_phase_profile(", journey_index
    )
    artifact_index = source.index("recorded_frame = _record_frame(", profile_stop_index)
    manifest_index = source.index(
        "manifest = write_acceptance_manifest(", artifact_index
    )
    hold_index = source.index("_keep_window_visible(", manifest_index)

    assert "first_offer_status=status" in source[
        profile_start_index:present_index
    ]
    assert "last_status.get(\"steps\")" in source[
        journey_index:profile_stop_index
    ]
    assert (
        projection_index
        < profile_start_index
        < present_index
        < journey_index
        < profile_stop_index
        < artifact_index
        < manifest_index
        < hold_index
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

    with pytest.raises(TypeError, match="phase_profile must be a boolean"):
        acceptance_runner.run_physical_desktop_acceptance(
            "/tmp/not-opened.sock",
            tmp_path,
            expected_server_pid=1,
            cols=acceptance_runner.CANONICAL_DESKTOP_COLS,
            rows=acceptance_runner.CANONICAL_DESKTOP_ROWS,
            ready_markers=("READY",),
            timeout=1.0,
            phase_profile=1,
        )
    with pytest.raises(ValueError, match="phase_profile_max_events"):
        acceptance_runner.run_physical_desktop_acceptance(
            "/tmp/not-opened.sock",
            tmp_path,
            expected_server_pid=1,
            cols=acceptance_runner.CANONICAL_DESKTOP_COLS,
            rows=acceptance_runner.CANONICAL_DESKTOP_ROWS,
            ready_markers=("READY",),
            timeout=1.0,
            phase_profile=True,
            phase_profile_max_events=(
                acceptance_runner.GUEST_PHASE_PROFILE_MAX_EVENTS + 1
            ),
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
        _daybook_prompt_projection(),
        sender,
    )
    eighth = _offer("X", offer_id=8, pad_menu=True)
    journey.after_present(
        eighth,
        9,
        _daybook_prompt_projection(task_visible=True),
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
    assert journey._daybook_initial_date == TEST_DAYBOOK_INITIAL_DATE
    assert journey._daybook_next_date == TEST_DAYBOOK_NEXT_DATE
    assert journey.final_cell_markers[-1] == TEST_DAYBOOK_NEXT_DATE
    # A complete retained replacement necessarily assigns fresh retained-wire
    # IDs.  Make the pre-handoff graph differ from the initial frame and then
    # rebase every semantic control again at the successful handoff.
    handoff_tab_identity_base = 31_000
    wrong_date = _offer("X", offer_id=10, pad_menu=True)
    progress = journey.after_present(
        wrong_date,
        9,
        _daybook_projection(
            task_visible=False,
            pad_tab_identity_base=handoff_tab_identity_base,
            date=TEST_DAYBOOK_INITIAL_DATE,
        ),
        sender,
    )
    assert progress.milestone is None
    assert not progress.complete
    assert journey.stage == 9
    assert actions[-1] == ("send_key", "right", 9, 9)

    navigated = _offer("X", offer_id=11, pad_menu=True)
    progress = journey.after_present(
        navigated,
        9,
        _daybook_projection(
            task_visible=False,
            pad_tab_identity_base=handoff_tab_identity_base,
        ),
        sender,
    )
    assert progress.milestone == "daybook-date-advanced"
    assert not progress.complete
    outside_pad = _offer("X", offer_id=12, pad_menu=True)
    progress = journey.after_present(
        outside_pad,
        9,
        _handoff_projection(pad_tile=False),
        sender,
    )
    assert progress.milestone is None
    assert not progress.complete
    assert journey.stage == 10
    handoff_projection = _handoff_projection(
        pad_tile=True,
        pad_tab_identity_base=handoff_tab_identity_base,
    )
    moved_root_projection = replace(
        handoff_projection,
        semantic_tabset_claims=(
            replace(
                handoff_projection.semantic_tabset_claims[0],
                right=handoff_projection.semantic_tabset_claims[0].right - 1,
            ),
        ),
    )

    def next_owner(identity: ControlIdentity) -> ControlIdentity:
        return ControlIdentity(
            identity.owner_id,
            identity.owner_generation + 1,
            identity.control_id,
        )

    owner_replaced_projection = replace(
        handoff_projection,
        semantic_collection_claims=tuple(
            replace(claim, identity=next_owner(claim.identity))
            for claim in handoff_projection.semantic_collection_claims
        ),
        semantic_tabset_claims=tuple(
            replace(
                tabset,
                identity=next_owner(tabset.identity),
                tabs=tuple(
                    replace(tab, identity=next_owner(tab.identity))
                    for tab in tabset.tabs
                ),
            )
            for tabset in handoff_projection.semantic_tabset_claims
        ),
    )
    owner_replaced_offer = _offer("X", offer_id=12, pad_menu=True)
    owner_replaced_offer = replace(
        owner_replaced_offer,
        retained=replace(
            owner_replaced_offer.retained,
            regions=(
                replace(
                    owner_replaced_offer.retained.regions[0],
                    owner_generation=(
                        owner_replaced_offer.retained.regions[0].owner_generation
                        + 1
                    ),
                ),
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="left its original session lineage",
    ):
        journey.after_present(
            owner_replaced_offer,
            9,
            owner_replaced_projection,
            sender,
        )

    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="moved the canonical TABSET root",
    ):
        journey.after_present(
            _offer("X", offer_id=13, pad_menu=True),
            9,
            moved_root_projection,
            sender,
        )

    relabeled_tab_projection = replace(
        handoff_projection,
        semantic_tabset_claims=(
            replace(
                handoff_projection.semantic_tabset_claims[0],
                tabs=(
                    replace(
                        handoff_projection.semantic_tabset_claims[0].tabs[0],
                        label="Scratch*",
                    ),
                    handoff_projection.semantic_tabset_claims[0].tabs[1],
                ),
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="replaced, reordered, or relabeled an existing canonical tab",
    ):
        journey.after_present(
            _offer("X", offer_id=14, pad_menu=True),
            9,
            relabeled_tab_projection,
            sender,
        )

    editor_claim = next(
        claim
        for claim in handoff_projection.semantic_collection_claims
        if claim.identity.control_id == 20_000
    )
    wrong_handoff_root = replace(
        handoff_projection,
        semantic_collection_claims=tuple(
            replace(claim, visible_text=())
            if claim.identity.control_id == 20_000
            else replace(
                claim,
                visible_text=editor_claim.visible_text,
                content_revision=editor_claim.content_revision,
                primary_key=editor_claim.primary_key,
                current_item_keys=editor_claim.current_item_keys,
                content_state=editor_claim.content_state,
            )
            if claim.identity.control_id == 20_002
            else claim
            for claim in handoff_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="moved away from or did not advance",
    ):
        journey.after_present(
            _offer("X", offer_id=15, pad_menu=True),
            9,
            wrong_handoff_root,
            sender,
        )

    rebased_handoff_projection = _rebase_semantic_control_ids(
        handoff_projection,
        50_000,
    )
    handoff = _offer("X", offer_id=16, pad_menu=True)
    progress = journey.after_present(
        handoff,
        9,
        rebased_handoff_projection,
        sender,
    )
    assert progress.milestone == "daybook-source-opened-in-pad"
    assert not progress.complete
    assert journey.stage == acceptance_runner.DESKTOP_ACCEPTANCE_PAD_TAB_STAGE
    activated_projection = _rebase_semantic_control_ids(
        _activated_pad_tab_projection(
            pad_tab_identity_base=handoff_tab_identity_base,
        ),
        70_000,
    )
    activated_editor = next(
        claim
        for claim in activated_projection.semantic_collection_claims
        if claim.kind is ControlKind.TEXT_AREA
        and any(PAD_ACCEPTANCE_TEXT in line for line in claim.visible_text)
    )
    assert activated_editor.state & ControlState.SELECTED
    corrupted_target = replace(
        activated_projection,
        semantic_collection_claims=tuple(
            replace(
                claim,
                primary_key=1,
                content_state=_synthetic_content_state(
                    (PAD_ACCEPTANCE_TEXT,),
                    primary_key=1,
                    primary_offset=1,
                ),
            )
            if (
                claim.kind is ControlKind.TEXT_AREA
                and any(
                    PAD_ACCEPTANCE_TEXT in line
                    for line in claim.visible_text
                )
            )
            else claim
            for claim in activated_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="exact edited STX1 state",
    ):
        journey.after_present(
            _offer("X", offer_id=17, pad_menu=True),
            9,
            corrupted_target,
            sender,
        )
    activated = _offer("X", offer_id=18, pad_menu=True)
    progress = journey.after_present(
        activated,
        9,
        activated_projection,
        sender,
    )
    assert progress.milestone == "pad-tab-activated"
    assert not progress.complete
    assert journey.stage == acceptance_runner.DESKTOP_ACCEPTANCE_LAUNCHER_OPEN_STAGE
    intervening = _offer("X", offer_id=19, pad_menu=True)
    progress = journey.after_present(
        intervening,
        9,
        activated_projection,
        sender,
    )
    assert progress.milestone is None
    assert not progress.complete
    assert journey.stage == acceptance_runner.DESKTOP_ACCEPTANCE_LAUNCHER_OPEN_STAGE
    launcher = _offer("X", offer_id=20, pad_menu=True)
    progress = journey.after_present(
        launcher,
        9,
        _desk_launcher_projection("Akashic Pad"),
        sender,
    )
    assert progress.milestone == "desk-launcher-open"
    assert not progress.complete
    stale_launcher = _offer("X", offer_id=21, pad_menu=True)
    progress = journey.after_present(
        stale_launcher,
        9,
        _desk_launcher_projection("Akashic Pad"),
        sender,
    )
    assert progress.milestone is None
    assert not progress.complete
    launcher_end = _offer("X", offer_id=22, pad_menu=True)
    progress = journey.after_present(
        launcher_end,
        9,
        _desk_launcher_projection("Streams"),
        sender,
    )
    assert progress.milestone is None
    assert not progress.complete
    stale_end = _offer("X", offer_id=23, pad_menu=True)
    progress = journey.after_present(
        stale_end,
        9,
        _desk_launcher_projection("Streams"),
        sender,
    )
    assert progress.milestone is None
    assert not progress.complete
    soundlab_selected = _offer("X", offer_id=24, pad_menu=True)
    progress = journey.after_present(
        soundlab_selected,
        9,
        _desk_launcher_projection("Sound Lab"),
        sender,
    )
    assert progress.milestone == "soundlab-launch-source"
    assert not progress.complete
    soundlab_projection = _rebase_semantic_control_ids(
        _soundlab_desktop_projection(
            pad_tab_identity_base=handoff_tab_identity_base,
        ),
        90_000,
    )
    final_pad_editor = next(
        claim
        for claim in soundlab_projection.semantic_collection_claims
        if claim.kind is ControlKind.TEXT_AREA
        and any(PAD_ACCEPTANCE_TEXT in line for line in claim.visible_text)
    )
    assert not (final_pad_editor.state & ControlState.SELECTED)
    wrong_final_date = _rebase_semantic_control_ids(
        _soundlab_desktop_projection(
            pad_tab_identity_base=handoff_tab_identity_base,
            daybook_date=TEST_DAYBOOK_INITIAL_DATE,
        ),
        90_000,
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Daybook navigation state",
    ):
        journey.after_present(
            _offer("X", offer_id=25, pad_menu=True),
            9,
            wrong_final_date,
            sender,
        )

    reset_tabset = replace(
        soundlab_projection,
        semantic_tabset_claims=(
            _pad_tabset_claim(
                soundlab_projection,
                labels=("Untitled*",),
                identity_base=handoff_tab_identity_base + 90_000,
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="two-tab signature graph",
    ):
        journey.after_present(
            _offer("X", offer_id=25, pad_menu=True),
            9,
            reset_tabset,
            sender,
        )

    reset_daybook = replace(
        soundlab_projection,
        semantic_collection_claims=tuple(
            replace(
                claim,
                content_revision=6,
                primary_key=1,
                content_state=_synthetic_content_state(primary_key=1),
            )
            if claim.kind is ControlKind.TEXT_GRID
            else claim
            for claim in soundlab_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Daybook navigation state",
    ):
        journey.after_present(
            _offer("X", offer_id=26, pad_menu=True),
            9,
            reset_daybook,
            sender,
        )

    reset_pad = replace(
        soundlab_projection,
        semantic_collection_claims=tuple(
            replace(
                claim,
                content_revision=6,
                primary_key=1,
                content_state=_synthetic_content_state(
                    (PAD_ACCEPTANCE_TEXT,),
                    primary_key=1,
                    primary_offset=1,
                ),
            )
            if (
                claim.kind is ControlKind.TEXT_AREA
                and any(
                    PAD_ACCEPTANCE_TEXT in line
                    for line in claim.visible_text
                )
            )
            else claim
            for claim in soundlab_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Pad editor state and accepted text",
    ):
        journey.after_present(
            _offer("X", offer_id=27, pad_menu=True),
            9,
            reset_pad,
            sender,
        )

    rollback_pad = replace(
        soundlab_projection,
        semantic_collection_claims=tuple(
            replace(claim, content_revision=3)
            if (
                claim.kind is ControlKind.TEXT_AREA
                and any(
                    PAD_ACCEPTANCE_TEXT in line
                    for line in claim.visible_text
                )
            )
            else claim
            for claim in soundlab_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Pad editor state and accepted text",
    ):
        journey.after_present(
            _offer("X", offer_id=28, pad_menu=True),
            9,
            rollback_pad,
            sender,
        )

    wrong_selected_tab = replace(
        soundlab_projection,
        semantic_tabset_claims=(
            _pad_tabset_claim(
                soundlab_projection,
                labels=("Untitled*", "/daybook.md"),
                selected=1,
                identity_base=handoff_tab_identity_base + 90_000,
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="activated original tab",
    ):
        journey.after_present(
            _offer("X", offer_id=29, pad_menu=True),
            9,
            wrong_selected_tab,
            sender,
        )

    moved_final_tabset = replace(
        soundlab_projection,
        semantic_tabset_claims=(
            replace(
                soundlab_projection.semantic_tabset_claims[0],
                right=soundlab_projection.semantic_tabset_claims[0].right - 1,
            ),
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="root bounds",
    ):
        journey.after_present(
            _offer("X", offer_id=30, pad_menu=True),
            9,
            moved_final_tabset,
            sender,
        )

    moved_final_pad = replace(
        soundlab_projection,
        semantic_collection_claims=tuple(
            replace(claim, right=claim.right - 1)
            if (
                claim.kind is ControlKind.TEXT_AREA
                and any(
                    PAD_ACCEPTANCE_TEXT in line
                    for line in claim.visible_text
                )
            )
            else claim
            for claim in soundlab_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Pad editor state and accepted text",
    ):
        journey.after_present(
            _offer("X", offer_id=31, pad_menu=True),
            9,
            moved_final_pad,
            sender,
        )

    moved_final_daybook = replace(
        soundlab_projection,
        semantic_collection_claims=tuple(
            replace(claim, right=claim.right - 1)
            if claim.kind is ControlKind.TEXT_GRID
            else claim
            for claim in soundlab_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Daybook navigation state",
    ):
        journey.after_present(
            _offer("X", offer_id=32, pad_menu=True),
            9,
            moved_final_daybook,
            sender,
        )

    rollback_daybook = replace(
        soundlab_projection,
        semantic_collection_claims=tuple(
            replace(claim, content_revision=1)
            if claim.kind is ControlKind.TEXT_GRID
            else claim
            for claim in soundlab_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Daybook navigation state",
    ):
        journey.after_present(
            _offer("X", offer_id=33, pad_menu=True),
            9,
            rollback_daybook,
            sender,
        )

    disabled_final_pad = replace(
        soundlab_projection,
        semantic_collection_claims=tuple(
            replace(claim, state=claim.state & ~ControlState.ENABLED)
            if (
                claim.kind is ControlKind.TEXT_AREA
                and any(
                    PAD_ACCEPTANCE_TEXT in line
                    for line in claim.visible_text
                )
            )
            else claim
            for claim in soundlab_projection.semantic_collection_claims
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Pad editor state and accepted text",
    ):
        journey.after_present(
            _offer("X", offer_id=34, pad_menu=True),
            9,
            disabled_final_pad,
            sender,
        )

    soundlab = _offer("X", offer_id=35, pad_menu=True)
    progress = journey.after_present(
        soundlab,
        9,
        soundlab_projection,
        sender,
    )
    assert progress.milestone == "soundlab-instruments-live"
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
        ("send_key", "ctrl+o", 11, 9),
        ("activate_pad_tab", "81001", 16, 9),
        ("send_key", "alt+h", 18, 9),
        ("send_key", "end", 20, 9),
        ("send_key", "up", 22, 9),
        ("send_key", "enter", 24, 9),
    ]


def test_soundlab_product_gate_requires_exact_ordinary_instrument_family() -> None:
    launcher = _desk_launcher_projection("Sound Lab")
    acceptance_runner._require_desk_launcher_selection(launcher, "Sound Lab")
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="expected visible selection 'Streams'",
    ):
        acceptance_runner._require_desk_launcher_selection(launcher, "Streams")

    # A marker elsewhere on the physical row must not impersonate the
    # canonical launcher slot at row 42, column 107.  The underlying Agent
    # tile can leave unrelated content to the left of the centered modal.
    misleading_lines = list(launcher.lines)
    soundlab_row_index = (
        acceptance_runner.DESKTOP_LAUNCHER_FIRST_ENTRY_ROW
        + acceptance_runner.DESKTOP_LAUNCHER_TITLES.index("Sound Lab")
    )
    soundlab_row = misleading_lines[soundlab_row_index]
    marker_col = acceptance_runner.DESKTOP_LAUNCHER_MARKER_COL
    misleading_lines[soundlab_row_index] = (
        "> Sound Lab"
        + soundlab_row[len("> Sound Lab") : marker_col]
        + " "
        + soundlab_row[marker_col + 1 :]
    )
    misleading = replace(launcher, lines=tuple(misleading_lines))
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="expected visible selection 'Sound Lab'",
    ):
        acceptance_runner._require_desk_launcher_selection(
            misleading, "Sound Lab"
        )

    projection = _soundlab_desktop_projection()
    acceptance_runner._require_soundlab_desktop_semantics(projection)

    without_readout = replace(
        projection,
        instrument_claims=projection.instrument_claims[1:],
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="8 READOUT, 2 METER, and 3 STATUS",
    ):
        acceptance_runner._require_soundlab_desktop_semantics(without_readout)

    without_soundlab_menu = replace(
        projection,
        menu_bar_count=projection.menu_bar_count - 1,
        menu_signatures=projection.menu_signatures[:-1],
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="Sound Lab.*missing-or-duplicated",
    ):
        acceptance_runner._require_soundlab_desktop_semantics(
            without_soundlab_menu
        )

    first_claim = projection.instrument_claims[0]
    outside_soundlab = replace(
        projection,
        instrument_claims=(
            replace(first_claim, left=10, right=11),
            *projection.instrument_claims[1:],
        ),
    )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="outside-tile-5",
    ):
        acceptance_runner._require_soundlab_desktop_semantics(outside_soundlab)


def test_pad_edit_marker_and_revision_must_share_one_matched_text_area_root() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    actions = []

    def sender(method, value, offer, generation):
        actions.append((method, value, offer.offer_id, generation))
        return "progress"

    journey.after_present(
        _offer("X", offer_id=1, pad_menu=True),
        9,
        _projection("READY"),
        sender,
    )
    journey.after_present(
        _offer("X", offer_id=2, pad_menu=True),
        9,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    journey.after_present(
        _offer("X", offer_id=3, pad_menu=True, file_open=True),
        9,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    journey.after_present(
        _offer("X", offer_id=4, pad_menu=True),
        9,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    assert journey.stage == 4
    assert len(journey._pad_area_before_edit or ()) == 2

    split_evidence = _projection(PAD_FOCUS_MARKER + PAD_ACCEPTANCE_TEXT)
    split_evidence = replace(
        split_evidence,
        semantic_collection_claims=tuple(
            replace(claim, content_revision=1)
            if claim.identity.control_id == 20_000
            else replace(claim, content_revision=2)
            if claim.identity.control_id == 20_002
            else claim
            for claim in split_evidence.semantic_collection_claims
        ),
    )
    progress = journey.after_present(
        _offer("X", offer_id=5, pad_menu=True),
        9,
        split_evidence,
        sender,
    )

    assert progress.milestone is None
    assert not progress.complete
    assert journey.stage == 4
    assert actions[-1] == ("send_text", PAD_ACCEPTANCE_TEXT, 4, 9)


def test_journey_rejects_multiple_initial_pad_tabs() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    projection = _projection("READY")
    projection = replace(
        projection,
        semantic_tabset_claims=(
            _pad_tabset_claim(
                projection,
                labels=("Untitled", "Already open"),
                selected=0,
            ),
        ),
    )

    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="exactly one ordinary buffer tab",
    ):
        journey.after_present(
            _offer("X", offer_id=1, pad_menu=True),
            9,
            projection,
            lambda *_args: "progress",
        )


def test_journey_activates_pad_menu_when_initial_frame_is_already_focused(
) -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    actions = []

    def sender(method, value, offer, generation):
        actions.append((method, value, offer.offer_id, generation))
        return "progress"

    initial = _offer("X", offer_id=1, pad_menu=True)
    progress = journey.after_present(
        initial,
        9,
        _projection("READY" + PAD_FOCUS_MARKER),
        sender,
    )

    assert progress.milestone == "desk-complete"
    assert journey.stage == 2
    assert actions == [
        (
            "activate_pad_file_menu",
            acceptance_runner.PAD_FILE_MENU_EVIDENCE,
            1,
            9,
        )
    ]

    menu_open = _offer("X", offer_id=2, pad_menu=True, file_open=True)
    progress = journey.after_present(
        menu_open,
        9,
        _projection(PAD_FOCUS_MARKER),
        sender,
    )
    assert progress.milestone == "pad-file-menu-open"
    assert journey.stage == 3
    assert actions[-1] == ("send_key", "escape", 2, 9)


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
        _daybook_prompt_projection(focused=False),
        sender,
    )
    assert journey.stage == 6
    assert len(calls) == 6
    journey.after_present(
        _offer("X", offer_id=9, pad_menu=True),
        4,
        _daybook_prompt_projection(),
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
            _daybook_prompt_projection(task_visible=True),
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


def test_initial_status_can_use_only_the_remaining_startup_deadline(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class Client:
        def __init__(self):
            self.calls = []

        def request(self, method, **params):
            self.calls.append(("ordinary", method, None, params))
            return {"state": "ordinary"}

        def request_with_timeout(self, method, timeout, **params):
            self.calls.append(("bounded", method, timeout, params))
            return {"state": "bounded"}

    client = Client()
    monkeypatch.setattr(acceptance_runner.time, "monotonic", lambda: 100.0)

    assert acceptance_runner._request_initial_status(
        client,
        deadline=150.0,
        response_timeout=None,
    ) == {"state": "ordinary"}
    assert acceptance_runner._request_initial_status(
        client,
        deadline=150.0,
        response_timeout=90.0,
    ) == {"state": "bounded"}
    assert client.calls == [
        ("ordinary", "status", None, {"detailed": False}),
        ("bounded", "status", 50.0, {"detailed": False}),
    ]

    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="exhausted its overall deadline",
    ):
        acceptance_runner._request_initial_status(
            client,
            deadline=100.0,
            response_timeout=90.0,
        )
    assert len(client.calls) == 2


@pytest.mark.parametrize(
    ("timeout", "error"),
    (
        (True, TypeError),
        ("not-a-number", TypeError),
        (0, ValueError),
        (-1, ValueError),
        (float("nan"), ValueError),
        (float("inf"), ValueError),
    ),
)
def test_physical_runner_rejects_invalid_initial_status_timeout(
    tmp_path: Path,
    timeout,
    error,
) -> None:
    with pytest.raises(error, match="initial_status_timeout"):
        acceptance_runner.run_physical_desktop_acceptance(
            "/tmp/not-opened.sock",
            tmp_path,
            expected_server_pid=1,
            cols=acceptance_runner.CANONICAL_DESKTOP_COLS,
            rows=acceptance_runner.CANONICAL_DESKTOP_ROWS,
            ready_markers=("READY",),
            timeout=1.0,
            initial_status_timeout=timeout,
        )


def _cell_observation(
    text: str,
    *,
    cursor_visible: bool = True,
) -> acceptance_runner._TerminalCellObservation:
    terminal = acceptance_runner.VirtualTerminal(cols=96, rows=8)
    terminal.write(text.encode("utf-8"))
    terminal.cursor_visible = cursor_visible
    return acceptance_runner._terminal_cell_observation(terminal)


def test_guest_explicit_failures_remain_active_after_cell_ready() -> None:
    normal = "KDOS loaded\r\nRunning autoexec.f...\r\n"
    failures = (
        "COLD SOURCE LOAD FAIL status=12 eval=1 line=488 token=_UTUI-RGN",
        "[akashic] desktop exception status=-3203",
        "EVALUATE depth limit exceeded",
        "  line 66: _UTUI-RGN ? (not found)",
    )
    assert acceptance_runner._guest_boot_failure(
        _cell_observation(normal),
        pre_ready=True,
    ) is None

    for failure in failures:
        excerpt = acceptance_runner._guest_boot_failure(
            _cell_observation(normal + failure),
            pre_ready=False,
        )
        assert excerpt is not None
        assert failure.strip() in excerpt


def test_pre_ready_kdos_quit_prompt_reports_external_memory_overflow() -> None:
    observation = _cell_observation(
        "[akashic boot] framework source 22/30\r\n"
        "[akashic boot] framework source 23/30\r\n"
        "Ext mem overflow> "
    )

    assert observation.kdos_quit_prompt_row == 2
    excerpt = acceptance_runner._guest_boot_failure(
        observation,
        pre_ready=True,
    )

    assert excerpt is not None
    assert "framework source 23/30" in excerpt
    assert excerpt.endswith("Ext mem overflow>")


def test_kdos_quit_prompt_bridge_rejects_nonterminal_prompt_shapes() -> None:
    no_prompt_space = _cell_observation("Ext mem overflow>")
    hidden_prompt = _cell_observation(
        "Ext mem overflow> ",
        cursor_visible=False,
    )
    stale_prompt = _cell_observation("Ext mem overflow> \r\nstill loading")
    prose = _cell_observation("capacity > requested")

    for observation in (
        no_prompt_space,
        hidden_prompt,
        stale_prompt,
        prose,
    ):
        assert observation.kdos_quit_prompt_row is None
        assert acceptance_runner._guest_boot_failure(
            observation,
            pre_ready=True,
        ) is None


def test_kdos_quit_prompt_is_not_a_generic_failure_after_cell_ready() -> None:
    observation = _cell_observation("ordinary shell return> ")
    assert observation.kdos_quit_prompt_row == 0
    assert acceptance_runner._guest_boot_failure(
        observation,
        pre_ready=False,
    ) is None


def _peek_record_fixture(
    records: dict[int, list[int]],
    *,
    address: int,
    count: int,
) -> dict[str, object]:
    for base, cells in records.items():
        byte_offset = address - base
        if byte_offset < 0 or byte_offset % 8:
            continue
        start = byte_offset // 8
        end = start + count
        if end <= len(cells):
            return {
                "address": address,
                "cell_size": 8,
                "values": cells[start:end],
            }
    raise AssertionError((address, count))


def test_guest_failure_diagnostics_capture_existing_service_records(
    tmp_path: Path,
) -> None:
    peek_calls = []
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
        0x3000: list(range(376)),
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
                peek_calls.append((params["address"], params["count"]))
                return _peek_record_fixture(record_cells, **params)
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
    assert peek_calls == [
        (0x2000, 26),
        (0x3000, 256),
        (0x3800, 120),
        (0x4000, 62),
    ]
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
    assert producer["target_active_address"] == 275
    assert producer["target_pending_address"] == 276
    assert producer["next_region"] == 277
    assert producer["next_object"] == 278
    assert producer["active_draw"] == 279
    assert producer["source_directory_bytes"] == 283
    assert producer["document_count"] == 284
    assert producer["row_damage_address"] == 285
    assert producer["row_damage_bytes"] == 286
    assert producer["glyph_id_map_address"] == 287
    assert producer["glyph_id_map_bytes"] == 288
    assert producer["source_content_epoch"] == 300
    assert producer["collection_count"] == 313
    assert producer["collection_items"] == 314
    assert producer["collection_utf8"] == 315
    assert producer["instrument_region_count"] == 370
    assert producer["instrument_count"] == 371
    assert producer["instrument_claim_count"] == 374
    assert producer["base_claim_bytes"] == 375
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
        0x3000: list(range(376)),
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
                return _peek_record_fixture(record_cells, **params)
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
        "peek",
        "resume",
    ]
    assert [
        (params["address"], params["count"])
        for method, params in calls
        if method == "peek"
    ] == [
        (0x2000, 26),
        (0x3000, 256),
        (0x3800, 120),
        (0x4000, 62),
    ]
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
    assert producer["target_active_address"] == 275
    assert producer["target_pending_address"] == 276
    assert producer["source_directory_bytes"] == 283
    assert producer["active_draw"] == 279
    assert producer["row_damage_address"] == 285
    assert producer["row_damage_bytes"] == 286
    assert producer["glyph_id_map_address"] == 287
    assert producer["glyph_id_map_bytes"] == 288
    assert producer["source_content_epoch"] == 300
    assert producer["collection_count"] == 313
    assert producer["instrument_region_count"] == 370
    assert producer["instrument_count"] == 371
    assert producer["base_claim_bytes"] == 375
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


def test_cell_fallback_evidence_is_exact_and_fails_on_missing_markers() -> None:
    markers = ("Selection", "Untitled")
    offer = replace(
        _offer("retained", offer_id=7, pad_menu=True),
        cell=_offer("CELL Selection / Untitled").cell,
    )
    cell_text = offer.cell.text(trim_right=True)
    evidence = acceptance_runner._require_cell_fallback_evidence(
        "initial",
        offer,
        3,
        markers,
    )

    assert evidence.boundary == "initial"
    assert evidence.offer_id == 7
    assert evidence.generation == 3
    assert evidence.ready_markers == markers
    assert evidence.cell_text_sha256 == hashlib.sha256(
        cell_text.encode("utf-8")
    ).hexdigest()
    assert evidence.cell_utf8_bytes == len(cell_text.encode("utf-8"))
    assert evidence.to_dict()["ready"] is True

    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match=r"not final-ready.*missing=\('Untitled',\)",
    ):
        acceptance_runner._require_cell_fallback_evidence(
            "final",
            replace(offer, cell=_offer("CELL Selection only").cell),
            3,
            markers,
        )


def test_manifest_records_physical_pixels_scopes_and_bound_inputs(
    tmp_path: Path,
) -> None:
    pad_area_identity = ControlIdentity(1, 1, 20_000)
    daybook_grid_identity = ControlIdentity(1, 1, 20_001)
    tabset_identity = ControlIdentity(1, 1, 30_000)
    tab_identities = (
        ControlIdentity(1, 1, 30_001),
        ControlIdentity(1, 1, 30_002),
    )
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
        text_area_count=1,
        text_grid_count=1,
        tabset_count=1,
        collection_claim_identities=(
            (ControlKind.TEXT_AREA, pad_area_identity),
            (ControlKind.TEXT_GRID, daybook_grid_identity),
        ),
        tab_identity_graphs=((tabset_identity, tab_identities),),
        selected_tab_identities=((tab_identities[1],),),
        tab_signatures=(("Untitled*", "/daybook.md"),),
        selected_tab_labels=(("/daybook.md",),),
        region_count=3,
        instrument_region_count=2,
        clipped_region_count=1,
        instrument_cell_count=10,
        readout_count=2,
        meter_count=1,
        status_count=1,
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
    cell_markers = ("Selection", "Untitled")
    cell_offer = replace(
        _offer("retained", offer_id=7, pad_menu=True),
        cell=_offer("CELL Selection Untitled initial").cell,
    )
    initial_cell = acceptance_runner._require_cell_fallback_evidence(
        "initial",
        cell_offer,
        0,
        cell_markers,
    )
    final_cell = acceptance_runner._require_cell_fallback_evidence(
        "final",
        replace(
            cell_offer,
            offer_id=8,
            cell=_offer("CELL Selection Untitled final").cell,
        ),
        0,
        cell_markers,
    )
    manifest = write_acceptance_manifest(
        tmp_path,
        "x11",
        (frame,),
        (event, control),
        (initial_cell, final_cell),
        manual_input_rpc_count=0,
    )
    payload = json.loads(manifest.read_text(encoding="utf-8"))
    assert payload["video_driver"] == "x11"
    assert payload["reference_sink_boundary"] == "pygame.display.flip"
    assert payload["acknowledged_evidence_viewport"] == {
        "origin": [0, 0],
        "extent": "recorded frame PNG dimensions",
        "host_mode_bar": "excluded",
    }
    assert payload["frames"] == [frame.to_dict()]
    assert payload["inputs"] == [event.to_dict(), control.to_dict()]
    assert payload["cell_fallback"] == {
        "required": True,
        "proof_source": "CELL snapshot carried by exact acknowledged offer",
        "snapshots": [initial_cell.to_dict(), final_cell.to_dict()],
    }
    assert payload["scripted_input_integrity"] == {
        "manual_pointer_input": "blocked_and_cleared_at_pygame_queue",
        "manual_input_rpc_count": 0,
    }
    assert payload["frames"][0]["renderer_owned_gap_cells"] == 12
    assert payload["frames"][0]["region_count"] == 3
    assert payload["frames"][0]["instrument_region_count"] == 2
    assert payload["frames"][0]["clipped_region_count"] == 1
    assert payload["frames"][0]["instrument_cell_count"] == 10
    assert payload["frames"][0]["readout_count"] == 2
    assert payload["frames"][0]["meter_count"] == 1
    assert payload["frames"][0]["status_count"] == 1
    assert payload["frames"][0]["text_area_count"] == 1
    assert payload["frames"][0]["text_grid_count"] == 1
    assert payload["frames"][0]["tabset_count"] == 1
    assert payload["frames"][0]["tab_signatures"] == [
        ["Untitled*", "/daybook.md"]
    ]
    assert payload["frames"][0]["selected_tab_labels"] == [["/daybook.md"]]
    assert payload["frames"][0]["collection_claim_identities"] == [
        {
            "kind": "TEXT_AREA",
            "owner_id": 1,
            "owner_generation": 1,
            "control_id": 20_000,
        },
        {
            "kind": "TEXT_GRID",
            "owner_id": 1,
            "owner_generation": 1,
            "control_id": 20_001,
        },
    ]
    assert payload["frames"][0]["tab_identity_graphs"] == [
        {
            "tabset": {
                "owner_id": 1,
                "owner_generation": 1,
                "control_id": 30_000,
            },
            "tabs": [
                {
                    "owner_id": 1,
                    "owner_generation": 1,
                    "control_id": 30_001,
                },
                {
                    "owner_id": 1,
                    "owner_generation": 1,
                    "control_id": 30_002,
                },
            ],
        }
    ]
    assert payload["frames"][0]["selected_tab_identities"] == [
        [
            {
                "owner_id": 1,
                "owner_generation": 1,
                "control_id": 30_002,
            }
        ]
    ]
    assert payload["frames"][0]["logical_cols"] == 280
    assert payload["frames"][0]["logical_rows"] == 84
    assert payload["inputs"][1]["semantic_target"] == semantic_target

    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="initial and final CELL evidence",
    ):
        write_acceptance_manifest(
            tmp_path,
            "x11",
            (frame,),
            (event,),
            (initial_cell,),
            manual_input_rpc_count=0,
        )
    with pytest.raises(
        PhysicalDesktopAcceptanceError,
        match="zero manual input RPCs",
    ):
        write_acceptance_manifest(
            tmp_path,
            "x11",
            (frame,),
            (event,),
            (initial_cell, final_cell),
            manual_input_rpc_count=1,
        )
