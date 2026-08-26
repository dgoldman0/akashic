"""Focused pure checks for the physical Desktop acceptance runner."""

from __future__ import annotations

import json
import time
from dataclasses import replace
from pathlib import Path

import pytest

import akashic_tui  # noqa: F401  Ensures the selected MegaPad tree is importable.
import rich_terminal_desktop_acceptance as acceptance_runner
from rich_terminal.retained_scene import ObjectBounds, RGBA
from rich_terminal.retained_view import (
    DisplayScope,
    GlyphRunDraw,
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
    reconstruct_full_screen_glyphs,
    write_acceptance_manifest,
)


UINT32_MAX = 0xFFFFFFFF


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
        for col, char in enumerate(line):
            draws.append(
                GlyphRunDraw(
                    object_id,
                    0,
                    ObjectBounds(
                        _low(col, cols),
                        _low(row, rows),
                        _high(col, cols),
                        _high(row, rows),
                    ),
                    RGBA(255, 255, 255, 255),
                    RGBA(0, 0, 0, 255),
                    0,
                    char,
                )
            )
            object_id += 1
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


def test_full_screen_projection_reconstructs_unique_row_major_glyphs() -> None:
    offer = _offer("AB\nCD")
    projection = reconstruct_full_screen_glyphs(offer)
    assert projection.cols == 2
    assert projection.rows == 2
    assert projection.draw_count == 4
    assert projection.lines == ("AB", "CD")
    assert projection.text == "AB\nCD"

    missing = replace(
        offer,
        retained=replace(
            offer.retained,
            regions=(
                replace(
                    offer.retained.regions[0],
                    draws=offer.retained.regions[0].draws[:-1],
                ),
            ),
        ),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="glyph draws"):
        reconstruct_full_screen_glyphs(missing)

    hidden = replace(
        offer,
        retained=RetainedDrawPlane(True, False, ()),
    )
    with pytest.raises(PhysicalDesktopAcceptanceError, match="visible initialized"):
        reconstruct_full_screen_glyphs(hidden)


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
