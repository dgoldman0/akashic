"""Focused pure checks for the physical Desktop acceptance runner."""

from __future__ import annotations

import json
import time
from dataclasses import replace
from pathlib import Path

import pytest

import akashic_tui  # noqa: F401  Ensures the selected MegaPad tree is importable.
import rich_terminal_desktop_acceptance as acceptance_runner
from rich_terminal.retained_scene import ControlState, ObjectBounds, RGBA
from rich_terminal.retained_view import (
    DisplayScope,
    GlyphRunDraw,
    MenuBarDraw,
    MenuDraw,
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


def _low(index: int, extent: int) -> int:
    return (index * UINT32_MAX + extent - 1) // extent


def _high(index: int, extent: int) -> int:
    return ((index + 1) * UINT32_MAX) // extent


def _offer(text: str, *, offer_id: int = 1) -> TerminalDisplayOffer:
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
            GlyphRunDraw(
                object_id,
                0,
                ObjectBounds(
                    _low(0, cols),
                    _low(row, rows),
                    _high(cols - 1, cols),
                    _high(row, rows),
                ),
                RGBA(255, 255, 255, 255),
                RGBA(0, 0, 0, 255),
                0,
                line,
            )
        )
        object_id += 1
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
            (
                MenuDraw(
                    10_001,
                    ControlState.VISIBLE | ControlState.ENABLED,
                    0,
                    "File",
                    (),
                ),
            ),
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
    )


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


def test_journey_advances_only_across_new_physically_presented_frames() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    actions: list[tuple[str, str, int, int]] = []

    def sender(method, value, offer, generation):
        actions.append((method, value, offer.offer_id, generation))
        return "progress"

    first = _offer("X", offer_id=1)
    progress = journey.after_present(
        first, 9, _projection("READY"), sender
    )
    assert progress.milestone == "desk-complete"
    assert actions == [("send_key", "alt+1", 1, 9)]

    journey.after_present(first, 9, _projection(PAD_FOCUS_MARKER), sender)
    assert len(actions) == 1
    second = _offer("X", offer_id=2)
    journey.after_present(second, 9, _projection(PAD_FOCUS_MARKER), sender)
    third = _offer("X", offer_id=3)
    progress = journey.after_present(
        third, 9, _projection(PAD_ACCEPTANCE_TEXT), sender
    )
    assert progress.milestone == "pad-edited"
    fourth = _offer("X", offer_id=4)
    journey.after_present(fourth, 9, _projection(DAYBOOK_FOCUS_MARKER), sender)
    fifth = _offer("X", offer_id=5)
    journey.after_present(fifth, 9, _projection(DAYBOOK_PROMPT_MARKER), sender)
    sixth = _offer("X", offer_id=6)
    journey.after_present(sixth, 9, _projection(DAYBOOK_ACCEPTANCE_TASK), sender)
    seventh = _offer("X", offer_id=7)
    progress = journey.after_present(
        seventh, 9, _projection(DAYBOOK_ACCEPTANCE_TASK), sender
    )
    assert progress.milestone == "daybook-task-added"
    assert progress.complete
    assert actions == [
        ("send_key", "alt+1", 1, 9),
        ("send_text", PAD_ACCEPTANCE_TEXT, 2, 9),
        ("send_key", "alt+3", 3, 9),
        ("send_key", "ctrl+n", 4, 9),
        ("send_text", DAYBOOK_ACCEPTANCE_TASK, 5, 9),
        ("send_key", "enter", 6, 9),
    ]


def test_backpressured_action_retries_against_same_acknowledged_frame() -> None:
    journey = DesktopAcceptanceJourney(("READY",))
    statuses = iter(("backpressured", "progress", "progress"))
    calls = []

    def sender(method, value, offer, generation):
        calls.append((method, value, offer.offer_id))
        return next(statuses)

    first = _offer("X", offer_id=1)
    journey.after_present(first, 4, _projection("READY"), sender)
    assert journey.stage == 0
    journey.after_present(first, 4, _projection("READY"), sender)
    assert calls == [("send_key", "alt+1", 1)]

    assert journey.has_pending_input
    assert journey.retry_pending_current(first, 4, sender)
    assert journey.stage == 1
    assert not journey.has_pending_input
    assert calls[-1] == ("send_key", "alt+1", 1)

    second = _offer("X", offer_id=2)
    journey.after_present(second, 4, _projection(PAD_FOCUS_MARKER), sender)
    assert journey.stage == 2
    assert calls[-1] == ("send_text", PAD_ACCEPTANCE_TEXT, 2)


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
        0x3000: list(range(71)),
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
    assert payload["records"]["screen_plane"]["fields"]["phase"] == 10
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
        "_RTSCREEN-P-INDEX": {
            "data_address": 0x1010,
            "value": 7_321,
        },
    }
    record_cells = {
        0x2000: list(range(26)),
        0x3000: list(range(71)),
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
                        "word": {"name": "_RTSCREEN-CAPTURE-START-BODY"}
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
    ] == [(0x2000, 26), (0x3000, 71), (0x4000, 62)]
    assert payload["timeout"] == "stage=0 offers-seen=0"
    assert payload["record_source"] == "live_composition"
    assert payload["machine"]["forth"]["word"]["name"] == (
        "_RTSCREEN-CAPTURE-START-BODY"
    )
    assert payload["variables"]["_RTSCREEN-P-INDEX"]["value"] == 7_321
    assert payload["records"]["publisher"]["fields"]["phase"] == 25
    assert payload["records"]["screen_plane"]["fields"]["phase"] == 10
    assert payload["records"]["screen_plane"]["fields"]["cells"] == 14
    assert payload["records"]["screen_plane"]["fields"]["scan"] == 15
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
        "desk-complete",
        7,
        0,
        scope,
        3200,
        "a" * 64,
        "b" * 64,
        "c" * 64,
        900,
        tmp_path / "desk.png",
        tmp_path / "desk-retained.png",
        tmp_path / "desk-retained.txt",
    )
    event = AcceptedInputEvidence("send_key", "alt+1", 7, 0, scope)
    manifest = write_acceptance_manifest(
        tmp_path,
        "x11",
        (frame,),
        (event,),
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
    assert payload["inputs"] == [event.to_dict()]
