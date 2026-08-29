"""Physical rich-terminal acceptance for the ordinary Akashic Desktop.

This runner is deliberately outside the product renderer and protocol.  It
holds the normal shared-session display lease, uses MegaPad's real pygame
viewer compositor, flips the selected video sink, acknowledges that exact
offer, and only then sends ordinary Desk input carrying the same proof.
"""

from __future__ import annotations

import hashlib
import json
import os
import socket
import struct
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from display import VirtualTerminal
from rich_terminal.pygame_view import (
    ControlHitTarget,
    ControlIdentity,
    composite_draw_plane,
    unorm_high_edge,
    unorm_low_edge,
)
from rich_terminal.retained_scene import ControlKind, ControlState
from rich_terminal.retained_view import (
    DisplayScope,
    GlyphRunDraw,
    MenuBarDraw,
    MenuDraw,
    MenuItemDraw,
    MenuSeparatorDraw,
    RetainedRegionDraw,
)
from session import TerminalDisplayOffer
from session_viewer import (
    _GuestKeyboardForwarder,
    _RetainedDisplayState,
    _SemanticPointerInteractor,
    _accept_screen_update,
    _accept_status_update,
    _display_claimed,
    _pygame_apt_modifiers,
    compose_terminal_frame_result,
    draw_flip_and_present,
)
from shared_session import SessionClient, display_scope_to_wire


# A PT TEXT scalar advances through the ordinary shell once per event loop,
# and every accepted edit may produce a complete retained replacement.  One
# distinctive scalar is sufficient to prove a real mutation in each app
# without turning vertical acceptance into a full-frame cadence stress test.
PAD_ACCEPTANCE_TEXT = "~"
DAYBOOK_ACCEPTANCE_TASK = "^"
PAD_FOCUS_MARKER = "[1:Akashic Pa*]"
DAYBOOK_FOCUS_MARKER = "[3:Daybook*]"
DAYBOOK_PROMPT_MARKER = "New task:"
PAD_FILE_MENU_EVIDENCE = "Pad/File"
PAD_MENU_SIGNATURE = (
    "File",
    "Build",
    "Edit",
    "Selection",
    "View",
    "Go",
    "Help",
)
PAD_FILE_ENTRY_SIGNATURE = (
    ("ITEM", "New File", "Ctrl+N"),
    ("ITEM", "Open File", "Ctrl+O"),
    ("SEPARATOR", "", ""),
    ("ITEM", "Save", "Ctrl+S"),
    ("ITEM", "Save As", "Ctrl+Shift+S"),
    ("ITEM", "Save All", ""),
    ("SEPARATOR", "", ""),
    ("ITEM", "Close Tab", "Ctrl+W"),
    ("ITEM", "Close All", ""),
    ("SEPARATOR", "", ""),
    ("ITEM", "Quit", "Ctrl+Q"),
)
DESKTOP_MENU_SIGNATURES = (
    PAD_MENU_SIGNATURE,
    ("File", "Edit", "View", "Tools"),
    ("File", "Entry", "Go", "Help"),
    ("File", "Edit", "Data", "Help"),
    ("Agent", "Run", "Connection", "Access", "Review", "Help"),
)
CANONICAL_DESKTOP_COLS = 280
CANONICAL_DESKTOP_ROWS = 84
DESKTOP_ACCEPTANCE_FINAL_STAGE = 8
MIN_READABLE_FONT_SIZE = 12
SESSION_REQUEST_TIMEOUT_SECONDS = 15.0
CELL_FALLBACK_MODE = "CELL FALLBACK: waiting for retained frame"
RETAINED_PENDING_MODE = "RICH RETAINED: pending physical acknowledgment"
RETAINED_ACKNOWLEDGED_MODE = "RICH RETAINED: physically acknowledged"

_GUEST_DIAGNOSTIC_WORDS = (
    "_A1D-PHASE",
    "_A1D-RUN-IOR",
    "_A1D-FAILURE-VALID",
    "_A1D-FAILURE-IOR",
    "_A1D-FAILURE-PHASE",
    "_A1D-FAILURE-PUBLISHER-A",
    "_A1D-FAILURE-SCREEN-A",
    "_A1D-FAILURE-ENGINE-A",
    "_ASHELL-TERM-STATUS",
    "_ASHELL-TERM-FLAG",
    "_ASHELL-TERM-OWNS",
    "_APTAS-STATUS",
    "_APTAS-STATE",
    "_APTSCB-STATUS",
    "_RTAPTSCB-STATUS",
    "_RTAPTSCB-PRODUCER-STATUS",
    "_RTAPTSCB-PRODUCER-MORE",
    "_RTAPTSCB-PRODUCER-OUTPUT",
    "_RTAPTSCB-SEALED-MODE",
    "_RTAPTSCB-SEALED-DISPOSITION",
    "_RTAPTSCB-SEALED-STATUS",
    "_RTSCREEN-S-STATUS",
    "_RTSCREEN-S-STATE",
    "_RTSCREEN-S-BUDGET",
    "_RTSCREEN-S-P",
    "_RTSCREEN-C-INDEX",
    "_RTSCREEN-P-P",
    "_RTSCREEN-P-INDEX",
    "_RTSCREEN-P-MODE",
    "_RTSCREEN-P-DISPOSITION",
    "_RTSCREEN-P-START",
    "_RTSCREEN-P-STATUS",
    "_RTSCREEN-P-STATE",
    "_RTSCREEN-P-COUNT",
    "_RTAPT-RS-E",
    "_RTAPT-BV-E",
    "_RTAPT-BV-P",
    "_RTAPT-BV-OFF",
    "_RTAPT-LPF-E",
    "_RTAPT-LPF-PLAN",
    "_RTAPT-LPF-COUNT",
    "_RTAPT-LPF-ITEM",
    "_RTAPT-LPF-LAST-OBJECT",
    "_RTAPT-LPF-OBJECT",
    "_RTAPT-LPF-UTF8",
    "_RTAPT-LPF-COPY-BYTES",
    "_RTAPT-LD-E",
    "_RTAPT-LD-OBJECT",
    "_RTAPT-PF-E",
    "_RTAPT-PF-P",
    "_RTAPT-PF-TOTAL",
    "_RTAPT-PF-RCOUNT",
    "_RTAPT-PF-OCOUNT",
    "_RTAPT-CB-E",
    "_RTAPT-CB-STATE",
    "_RTAPT-CB-STATUS",
    "_RTAPT-ST-PT",
    "_RTAPT-ST-HAS",
    "_RTAPT-ST-STATE",
    "_RTAPTSCB-R",
    "_RTAPT-ST-E",
    "_RTAPTSCBOP-PUBLISHER",
    "_RTAPTSCBOP-CONTEXT",
    "_RTAPTSCBI-ENGINE",
)

_GUEST_FAILURE_RECORDS = {
    "publisher": (
        "_A1D-FAILURE-PUBLISHER-A",
        26,
        {
            "session": 0,
            "context": 1,
            "base_magic": 10,
            "engine": 11,
            "rich_magic": 12,
            "producer_context": 13,
            "producer_bytes": 14,
            "producer_budget": 15,
            "adapter": 18,
            "surface_cols": 19,
            "surface_rows": 20,
            "surface_generation": 21,
            "more_work": 22,
            "output_needed": 23,
            "fault_status": 24,
            "phase": 25,
        },
    ),
    "screen_plane": (
        "_A1D-FAILURE-SCREEN-A",
        71,
        {
            "magic": 0,
            "size": 1,
            "self": 2,
            "facade": 3,
            "items_address": 4,
            "items_bytes": 5,
            "owner": 6,
            "owner_generation": 7,
            "region": 8,
            "first_object": 9,
            "phase": 10,
            "cols": 11,
            "rows": 12,
            "surface_generation": 13,
            "cells": 14,
            "scan": 15,
            "fault_status": 16,
        },
    ),
    "engine": (
        "_A1D-FAILURE-ENGINE-A",
        62,
        {
            "magic": 0,
            "session": 1,
            "owner_used": 5,
            "queue_head": 11,
            "queue_tail": 12,
            "active_owner": 13,
            "active_kind": 14,
            "update_state": 15,
            "coupling": 16,
            "cols": 17,
            "rows": 18,
            "cell_spans": 19,
            "cells": 20,
            "cell_mode": 21,
            "retained_mode": 22,
            "disposition": 23,
            "operation_count": 24,
            "copy_used": 25,
            "retained_bytes": 26,
            "send_index": 27,
            "last_status": 28,
            "last_wire_status": 29,
            "last_detail": 30,
            "last_revision": 31,
        },
    ),
}

_GUEST_LIVE_RECORD_POINTERS = {
    "publisher": "_RTAPTSCBOP-PUBLISHER",
    "screen_plane": "_RTAPTSCBOP-CONTEXT",
    "engine": "_RTAPTSCBI-ENGINE",
}


class PhysicalDesktopAcceptanceError(RuntimeError):
    """The physical Desk/Pad/Daybook contract was not completed."""


@dataclass(frozen=True)
class RichScreenProjection:
    """Validated logical text reconstructed only from retained draw values."""

    cols: int
    rows: int
    lines: tuple[str, ...]
    draw_count: int
    semantic_lines: tuple[str, ...] = ()
    glyph_cell_count: int = 0
    menu_bar_count: int = 0
    menu_signatures: tuple[tuple[str, ...], ...] = ()
    renderer_owned_gap_cells: int = 0

    @property
    def text(self) -> str:
        return "\n".join(self.lines + self.semantic_lines)


@dataclass(frozen=True)
class PresentedFrameEvidence:
    milestone: str
    offer_id: int
    generation: int
    scope: dict[str, object]
    logical_cols: int
    logical_rows: int
    draw_count: int
    pixel_sha256: str
    retained_text_sha256: str
    retained_only_sha256: str
    retained_only_nonblack_pixels: int
    png_path: Path
    retained_png_path: Path
    retained_text_path: Path
    menu_signatures: tuple[tuple[str, ...], ...] = ()
    renderer_owned_gap_cells: int = 0

    def to_dict(self) -> dict[str, object]:
        return {
            "milestone": self.milestone,
            "offer_id": self.offer_id,
            "generation": self.generation,
            "scope": self.scope,
            "logical_cols": self.logical_cols,
            "logical_rows": self.logical_rows,
            "draw_count": self.draw_count,
            "pixel_sha256": self.pixel_sha256,
            "retained_text_sha256": self.retained_text_sha256,
            "retained_only_sha256": self.retained_only_sha256,
            "retained_only_nonblack_pixels": (
                self.retained_only_nonblack_pixels
            ),
            "menu_signatures": [
                list(signature) for signature in self.menu_signatures
            ],
            "renderer_owned_gap_cells": self.renderer_owned_gap_cells,
            "png_path": str(self.png_path),
            "retained_png_path": str(self.retained_png_path),
            "retained_text_path": str(self.retained_text_path),
        }


@dataclass(frozen=True)
class AcceptedInputEvidence:
    method: str
    value: str
    offer_id: int
    generation: int
    scope: dict[str, object]
    semantic_target: dict[str, object] | None = None

    def to_dict(self) -> dict[str, object]:
        payload = {
            "method": self.method,
            "value": self.value,
            "offer_id": self.offer_id,
            "generation": self.generation,
            "scope": self.scope,
        }
        if self.semantic_target is not None:
            payload["semantic_target"] = self.semantic_target
        return payload


@dataclass(frozen=True)
class PhysicalDesktopAcceptanceEvidence:
    manifest_path: Path
    video_driver: str
    frames: tuple[PresentedFrameEvidence, ...]
    inputs: tuple[AcceptedInputEvidence, ...]


@dataclass(frozen=True)
class AcceptanceDiagnosticState:
    """One truthful host-only description of the current display boundary."""

    mode: str
    cell_ready: bool
    offer_id: int | None = None
    scope: dict[str, object] | None = None
    draw_count: int = 0
    retained_text_sha256: str | None = None
    missing_ready_markers: tuple[str, ...] = ()

    def summary(self) -> str:
        detail = [self.mode, f"CELL-ready={self.cell_ready}"]
        if self.offer_id is not None:
            detail.extend(
                (
                    f"offer={self.offer_id}",
                    f"draws={self.draw_count}",
                    f"scope={json.dumps(self.scope, sort_keys=True)}",
                )
            )
        if self.retained_text_sha256 is not None:
            detail.append(f"retained-text={self.retained_text_sha256}")
        if self.missing_ready_markers:
            detail.append(
                "missing=" + ",".join(self.missing_ready_markers)
            )
        return " | ".join(detail)


def _marker_status(
    text: str,
    ready_markers: tuple[str, ...],
) -> tuple[bool, tuple[str, ...]]:
    missing = tuple(marker for marker in ready_markers if marker not in text)
    return not missing, missing


def _require_canonical_pad_file_entries(menu: MenuDraw) -> None:
    """Require Pad's authored File rows, order, labels, shortcuts, and state."""

    signature = tuple(
        ("ITEM", entry.label, entry.shortcut)
        if isinstance(entry, MenuItemDraw)
        else ("SEPARATOR", "", "")
        for entry in menu.entries
    )
    if signature != PAD_FILE_ENTRY_SIGNATURE:
        raise PhysicalDesktopAcceptanceError(
            "open Pad File menu does not contain its exact canonical entries: "
            f"expected={PAD_FILE_ENTRY_SIGNATURE!r} actual={signature!r}"
        )
    ordinary_item_state = ControlState.VISIBLE | ControlState.ENABLED
    selected_item_state = ordinary_item_state | ControlState.SELECTED
    if any(
        (
            isinstance(entry, MenuItemDraw)
            and entry.state
            != (selected_item_state if index == 0 else ordinary_item_state)
        )
        or (
            isinstance(entry, MenuSeparatorDraw)
            and entry.state != ControlState.VISIBLE
        )
        or entry.order != index
        for index, entry in enumerate(menu.entries)
    ):
        raise PhysicalDesktopAcceptanceError(
            "open Pad File menu entries do not have canonical order and state"
        )


def _write_timeout_diagnostics(
    artifact_root: Path,
    *,
    cell_text: str,
    retained_text: str | None,
    stage: int,
    cell_ready: bool,
    offers_seen: int,
    since_offer: int,
    cell_missing_markers: tuple[str, ...],
    retained_missing_markers: tuple[str, ...] | None,
    frame_barrier: int,
    pending_input: bool,
) -> str:
    """Persist exact last-seen text planes and return the timeout detail."""

    root = Path(artifact_root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    (root / "timeout-cell.txt").write_text(cell_text, encoding="utf-8")
    retained_path = root / "timeout-retained.txt"
    if retained_text is not None:
        retained_path.write_text(retained_text, encoding="utf-8")
    else:
        retained_path.unlink(missing_ok=True)
    cell_missing = ",".join(cell_missing_markers) or "none"
    retained_missing = (
        "not-seen"
        if retained_missing_markers is None
        else ",".join(retained_missing_markers) or "none"
    )
    return (
        f"stage={stage} CELL-ready={cell_ready} offers-seen={offers_seen} "
        f"since-offer={since_offer} cell-missing={cell_missing} "
        f"retained-missing={retained_missing} "
        f"frame-barrier={frame_barrier} pending-input={pending_input}"
    )


def _write_guest_failure_diagnostics(
    client: SessionClient,
    artifact_root: Path,
    failure: str,
) -> Path:
    """Persist best-effort host/Forth state after the guest has stopped."""

    root = Path(artifact_root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    status = client.request("status", detailed=True)
    payload = _guest_state_payload(
        client,
        status,
        reason_name="failure",
        reason=failure,
    )
    path = root / "guest-failure.json"
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return path


def _guest_state_payload(
    client: SessionClient,
    machine: dict,
    *,
    reason_name: str,
    reason: str,
) -> dict:
    """Read one stable guest rich-composition state under the caller's lock."""

    forth = client.request("forth", names=list(_GUEST_DIAGNOSTIC_WORDS))
    words = forth.get("words", {})
    variables = {
        name: {
            "address": int(word["data_address"]),
            "value": int(word["value"]),
        }
        for name in _GUEST_DIAGNOSTIC_WORDS
        if (word := words.get(name)) is not None
        and "data_address" in word
        and "value" in word
    }
    failure_snapshot = bool(
        variables.get("_A1D-FAILURE-VALID", {}).get("value", 0) != 0
        and variables.get("_A1D-FAILURE-IOR", {}).get("value", 0) != 0
    )
    if failure_snapshot:
        record_source = "failure_snapshot"
        pointers = {
            record_name: variables.get(pointer_name, {}).get("value", 0)
            for record_name, (pointer_name, _count, _fields) in (
                _GUEST_FAILURE_RECORDS.items()
            )
        }
    else:
        record_source = "live_composition"
        pointers = {
            record_name: variables.get(pointer_name, {}).get("value", 0)
            for record_name, pointer_name in (
                _GUEST_LIVE_RECORD_POINTERS.items()
            )
        }
    records: dict[str, object] = {}
    for record_name, (pointer_name, count, fields) in (
        _GUEST_FAILURE_RECORDS.items()
    ):
        pointer = pointers.get(record_name, 0)
        if not isinstance(pointer, int) or pointer <= 0:
            records[record_name] = {"address": pointer, "unavailable": True}
            continue
        try:
            response = client.request("peek", address=pointer, count=count)
        except (ConnectionError, OSError):
            raise
        except Exception as exc:
            records[record_name] = {
                "address": pointer,
                "unavailable": True,
                "error": f"{type(exc).__name__}: {exc}",
            }
            continue
        cells = [int(value) for value in response["values"]]
        records[record_name] = {
            "address": pointer,
            "fields": {
                name: cells[index]
                for name, index in fields.items()
                if index < len(cells)
            },
            "cells": cells,
        }
    return {
        reason_name: reason,
        "machine": machine,
        "forth_here": forth.get("here"),
        "record_source": record_source,
        "variables": variables,
        "records": records,
    }


def _write_timeout_state_diagnostics(
    client: SessionClient,
    artifact_root: Path,
    timeout_detail: str,
) -> Path:
    """Pause once, persist live rich state, and resume when it remains safe."""

    root = Path(artifact_root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    before_pause = client.request("status", detailed=False)
    was_paused = before_pause.get("paused")
    if was_paused is not True and was_paused is not False:
        raise RuntimeError("pre-pause status has no boolean paused state")
    payload = None
    resume_error = None
    capture_error = None
    pause_succeeded = False
    should_resume = False
    machine = None
    try:
        try:
            machine = client.request("pause")
            pause_succeeded = True
            should_resume = was_paused is False
        except (ConnectionError, OSError):
            raise
        except Exception:
            # A synchronized error response can follow the server-side pause
            # mutation.  Restore only a previously clean running machine;
            # transport errors above leave response framing ambiguous and are
            # contained by the launcher's guaranteed server teardown.
            pre_rich = before_pause.get("rich_terminal", {})
            if (
                was_paused is False
                and before_pause.get("error") is None
                and isinstance(pre_rich, dict)
                and pre_rich.get("failure") is None
                and not pre_rich.get("lost")
            ):
                try:
                    client.request("resume")
                except Exception:
                    pass
            raise
        if not isinstance(machine, dict):
            raise TypeError("pause response must be an object")
        rich_state = machine.get("rich_terminal", {})
        if not isinstance(rich_state, dict):
            raise TypeError("pause response rich_terminal must be an object")
        should_resume = bool(
            should_resume
            and machine.get("error") is None
            and rich_state.get("failure") is None
            and not rich_state.get("lost")
        )
        if machine.get("paused") is not True:
            if machine.get("paused") is False:
                should_resume = False
            raise RuntimeError("pause response has no true paused state")
        payload = _guest_state_payload(
            client,
            machine,
            reason_name="timeout",
            reason=timeout_detail,
        )
    except Exception as exc:
        capture_error = exc
        raise
    finally:
        transport_failed = isinstance(capture_error, (ConnectionError, OSError))
        if should_resume and not transport_failed:
            try:
                resumed = client.request("resume")
                if (
                    not isinstance(resumed, dict)
                    or resumed.get("paused") is not False
                ):
                    resume_error = "resume response has no false paused state"
            except Exception as exc:
                resume_error = f"{type(exc).__name__}: {exc}"
    if payload is None:
        raise RuntimeError("timeout diagnostic capture produced no payload")
    payload["pre_pause"] = before_pause
    payload["resume_attempted"] = bool(
        pause_succeeded and should_resume and not transport_failed
    )
    if resume_error is not None:
        payload["resume_error"] = resume_error
    path = root / "timeout-state.json"
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return path


def _timeout_state_message(
    client: SessionClient,
    artifact_root: Path,
    timeout_detail: str,
) -> str:
    """Keep optional timeout-state failures subordinate to the timeout."""

    try:
        path = _write_timeout_state_diagnostics(
            client,
            artifact_root,
            timeout_detail,
        )
        return f"diagnostic: {path}"
    except Exception as exc:
        return f"diagnostic capture failed: {exc}"


def _guest_failure_message(
    client: SessionClient,
    artifact_root: Path,
    failure: str,
) -> str:
    """Keep optional diagnostic failures subordinate to the guest failure."""

    try:
        diagnostic_path = _write_guest_failure_diagnostics(
            client,
            artifact_root,
            failure,
        )
        diagnostic = f"\ndiagnostic: {diagnostic_path}"
    except Exception as exc:
        diagnostic = f"\ndiagnostic capture failed: {exc}"
    return (
        "guest failed before physical Desktop acceptance:\n"
        f"{failure}{diagnostic}"
    )


def _menu_popup_source_claim(
    menu_bar: MenuBarDraw,
    menu: MenuDraw,
    *,
    bar_left: int,
    bar_right: int,
    bar_top: int,
    screen_rows: int,
) -> set[tuple[int, int]]:
    """Derive the ordinary UIDL-TUI cell rectangle owned by one popup.

    UIDL-TUI positions menu siblings and measures item labels from the byte
    lengths returned by ``UIDL-ATTR``.  The retained draw projection omits
    invisible controls.  Canonical acceptance therefore requires every
    layout-participating menu and row needed by an open popup to be visible; a
    gap in either zero-based sibling order is proof that this invariant was
    broken.  Refuse such a frame instead of silently moving or shrinking its
    source claim.  (An omitted trailing source sibling is not representable in
    ``MenuDraw`` and remains an explicit all-visible profile invariant.)
    """

    menu_orders = tuple(candidate.order for candidate in menu_bar.menus)
    if menu_orders != tuple(range(len(menu_orders))):
        raise PhysicalDesktopAcceptanceError(
            "semantic menu bar omits source-order menus needed to derive "
            "popup geometry"
        )
    entry_orders = tuple(entry.order for entry in menu.entries)
    if entry_orders != tuple(range(len(entry_orders))):
        raise PhysicalDesktopAcceptanceError(
            "open semantic menu omits source-order rows needed to derive "
            "popup geometry"
        )

    def uidl_text_width(text: str) -> int:
        return len(text.encode("utf-8", "strict"))

    title_left = bar_left + 1
    found = False
    for candidate in menu_bar.menus:
        if candidate.control_id == menu.control_id:
            found = True
            break
        title_left += uidl_text_width(candidate.label) + 2
    if not found:
        raise PhysicalDesktopAcceptanceError(
            "open semantic menu is not a child of its retained menu bar"
        )
    popup_top = bar_top + 1
    popup_width = (
        max(
            (
                uidl_text_width(entry.label)
                for entry in menu.entries
                if isinstance(entry, MenuItemDraw)
            ),
            default=0,
        )
        + 4
    )
    popup_height = len(menu.entries) + 2
    if (
        title_left < bar_left
        or title_left + popup_width > bar_right
        or popup_top < 0
        or popup_top + popup_height > screen_rows
    ):
        raise PhysicalDesktopAcceptanceError(
            "open semantic menu source claim does not fit its viewport"
        )
    return {
        (col, row)
        for row in range(popup_top, popup_top + popup_height)
        for col in range(title_left, title_left + popup_width)
    }


def reconstruct_retained_screen(
    offer: TerminalDisplayOffer,
) -> RichScreenProjection:
    """Validate one complete rich screen and reconstruct its logical text."""

    if not isinstance(offer, TerminalDisplayOffer):
        raise TypeError("offer must be TerminalDisplayOffer")
    scope = offer.scope
    plane = offer.retained
    cell = offer.cell
    if scope.retained_revision is None:
        raise PhysicalDesktopAcceptanceError(
            "display offer has no retained frame identity"
        )
    if plane is None or not plane.retained_initialized or not plane.retained_visible:
        raise PhysicalDesktopAcceptanceError(
            "display offer does not carry a visible initialized retained plane"
        )
    if len(plane.regions) != 1:
        raise PhysicalDesktopAcceptanceError(
            "retained screen must contain exactly one full-screen region"
        )
    region = plane.regions[0]
    expected_region = (0, 0, cell.cols, cell.rows)
    actual_region = (
        region.cell_x,
        region.cell_y,
        region.cell_cols,
        region.cell_rows,
    )
    if actual_region != expected_region:
        raise PhysicalDesktopAcceptanceError(
            f"retained region {actual_region!r} is not full screen "
            f"{expected_region!r}"
        )
    glyphs: list[str | None] = [None] * (cell.cols * cell.rows)
    glyph_cells: set[tuple[int, int]] = set()
    semantic_cells: set[tuple[int, int]] = set()
    semantic_lines: list[str] = []
    menu_signatures: list[tuple[str, ...]] = []
    menu_bar_count = 0
    open_menus: list[tuple[MenuBarDraw, MenuDraw, int, int, int]] = []
    for draw in region.draws:
        left = unorm_low_edge(draw.bounds.left, cell.cols)
        right = unorm_high_edge(draw.bounds.right, cell.cols)
        top = unorm_low_edge(draw.bounds.top, cell.rows)
        bottom = unorm_high_edge(draw.bounds.bottom, cell.rows)
        if not (
            0 <= left < right <= cell.cols
            and 0 <= top < bottom <= cell.rows
        ):
            raise PhysicalDesktopAcceptanceError(
                "retained draw bounds do not map inside the full screen"
            )

        if isinstance(draw, GlyphRunDraw):
            if not draw.text or bottom - top != 1 or right - left != len(draw.text):
                raise PhysicalDesktopAcceptanceError(
                    f"retained glyph run {draw.object_id} geometry does not "
                    "match its horizontal scalar run"
                )
            for offset, scalar in enumerate(draw.text):
                coordinate = (left + offset, top)
                if coordinate in glyph_cells:
                    raise PhysicalDesktopAcceptanceError(
                        f"retained glyph run {draw.object_id} overlaps another "
                        f"glyph at {coordinate!r}"
                    )
                glyph_cells.add(coordinate)
                glyphs[top * cell.cols + left + offset] = scalar
            continue

        if isinstance(draw, MenuBarDraw):
            menu_bar_count += 1
            for row in range(top, bottom):
                for col in range(left, right):
                    semantic_cells.add((col, row))
            signature = tuple(menu.label for menu in draw.menus)
            menu_signatures.append(signature)
            open_menus.extend(
                (draw, menu, left, right, top)
                for menu in draw.menus
                if menu.state & ControlState.OPEN
            )
            labels = list(signature)
            labels.extend(
                entry.label
                for menu in draw.menus
                for entry in menu.entries
                if isinstance(entry, MenuItemDraw)
            )
            if labels:
                semantic_lines.append(" ".join(labels))
            continue

        raise PhysicalDesktopAcceptanceError(
            f"retained screen contains unsupported draw {type(draw).__name__}"
        )

    if not glyph_cells:
        raise PhysicalDesktopAcceptanceError(
            "retained screen contains no substantive glyph cells"
        )
    if menu_bar_count == 0 or not semantic_lines:
        raise PhysicalDesktopAcceptanceError(
            "retained screen contains no semantic menu bar"
        )
    covered = glyph_cells | semantic_cells
    uncovered = {
        (col, row)
        for row in range(cell.rows)
        for col in range(cell.cols)
        if (col, row) not in covered
    }
    expected_popup_claim: set[tuple[int, int]] = set()
    for menu_bar, menu, bar_left, bar_right, bar_top in open_menus:
        expected_popup_claim.update(
            _menu_popup_source_claim(
                menu_bar,
                menu,
                bar_left=bar_left,
                bar_right=bar_right,
                bar_top=bar_top,
                screen_rows=cell.rows,
            )
        )
    if uncovered != expected_popup_claim:
        raise PhysicalDesktopAcceptanceError(
            "retained rich draws leave logical cells uncovered outside the "
            "exact semantic popup source claims: "
            f"actual={len(uncovered)} expected={len(expected_popup_claim)}"
        )
    renderer_owned_gap_cells = len(uncovered)
    lines = tuple(
        "".join(
            scalar if scalar is not None else " "
            for scalar in glyphs[row * cell.cols : (row + 1) * cell.cols]
        )
        for row in range(cell.rows)
    )
    return RichScreenProjection(
        cell.cols,
        cell.rows,
        lines,
        len(region.draws),
        tuple(semantic_lines),
        len(glyph_cells),
        menu_bar_count,
        tuple(menu_signatures),
        renderer_owned_gap_cells,
    )


def _require_canonical_menu_aggregate(projection: RichScreenProjection) -> None:
    """Require exactly one semantic forest for every canonical visible applet."""

    missing = tuple(
        signature
        for signature in DESKTOP_MENU_SIGNATURES
        if projection.menu_signatures.count(signature) != 1
    )
    exact_count = len(DESKTOP_MENU_SIGNATURES)
    if (
        missing
        or projection.menu_bar_count != exact_count
        or len(projection.menu_signatures) != exact_count
    ):
        raise PhysicalDesktopAcceptanceError(
            "retained frame does not contain one exact semantic menu forest "
            "for every canonical visible applet and no unexpected applet: "
            f"missing-or-duplicated={missing!r} "
            f"bars={projection.menu_bar_count} "
            f"signatures={len(projection.menu_signatures)}"
        )


def _require_canonical_desktop_geometry(
    projection: RichScreenProjection,
) -> None:
    """Reject negotiated or delivered geometry drift in canonical acceptance."""

    actual = (projection.cols, projection.rows)
    expected = (CANONICAL_DESKTOP_COLS, CANONICAL_DESKTOP_ROWS)
    if actual != expected:
        raise PhysicalDesktopAcceptanceError(
            f"observed retained frame geometry {actual[0]}x{actual[1]} is not "
            f"the canonical {expected[0]}x{expected[1]} acceptance geometry"
        )


def _pad_file_menu(
    offer: TerminalDisplayOffer,
) -> tuple[RetainedRegionDraw, MenuBarDraw, MenuDraw]:
    """Resolve Pad's File menu from its unique canonical semantic forest."""

    plane = offer.retained
    if plane is None:
        raise PhysicalDesktopAcceptanceError(
            "Pad File-menu lookup requires a retained display plane"
        )
    matches: list[tuple[RetainedRegionDraw, MenuBarDraw, MenuDraw]] = []
    for region in plane.regions:
        for draw in region.draws:
            if not isinstance(draw, MenuBarDraw):
                continue
            if tuple(menu.label for menu in draw.menus) != PAD_MENU_SIGNATURE:
                continue
            file_menus = tuple(menu for menu in draw.menus if menu.label == "File")
            if len(file_menus) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "canonical Pad menu forest does not contain one File menu"
                )
            matches.append((region, draw, file_menus[0]))
    if len(matches) != 1:
        raise PhysicalDesktopAcceptanceError(
            "retained frame does not contain exactly one canonical Pad menu forest"
        )
    return matches[0]


def _pad_file_menu_is_open(offer: TerminalDisplayOffer) -> bool:
    _region, menu_bar, menu = _pad_file_menu(offer)
    root_state = menu_bar.state
    if not root_state & ControlState.VISIBLE or not root_state & ControlState.ENABLED:
        raise PhysicalDesktopAcceptanceError(
            "Pad menu bar is not visibly enabled"
        )
    if not menu.state & ControlState.VISIBLE or not menu.state & ControlState.ENABLED:
        raise PhysicalDesktopAcceptanceError(
            "Pad File menu is not visibly enabled"
        )
    opened = bool(menu.state & ControlState.OPEN)
    if opened:
        expected_state = (
            ControlState.VISIBLE
            | ControlState.ENABLED
            | ControlState.OPEN
            | ControlState.SELECTED
        )
        if menu.state != expected_state:
            raise PhysicalDesktopAcceptanceError(
                "open Pad File menu does not have canonical selected state"
            )
        _require_canonical_pad_file_entries(menu)
    return opened


def _pad_file_hit_target(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
) -> ControlHitTarget:
    """Resolve the painter-order Pad/File target from one exact physical ACK."""

    token = (offer.offer_id, offer.scope)
    if display_state.hit_map_token != token or display_ack != token:
        raise PhysicalDesktopAcceptanceError(
            "Pad File activation lacks the exact acknowledged semantic hit map"
        )
    region, menu_bar, menu = _pad_file_menu(offer)
    root_state = menu_bar.state
    expected_root_state = ControlState.VISIBLE | ControlState.ENABLED
    if root_state != expected_root_state:
        raise PhysicalDesktopAcceptanceError(
            "Pad menu bar is not in its canonical activation state"
        )
    expected_menu_state = ControlState.VISIBLE | ControlState.ENABLED
    if menu.state != expected_menu_state or menu.entries:
        raise PhysicalDesktopAcceptanceError(
            "Pad File menu is not the exact closed activation source"
        )
    identity = ControlIdentity(
        region.owner_id,
        region.owner_generation,
        menu.control_id,
    )
    matches = tuple(
        target
        for target in display_state.hit_targets
        if target.identity == identity and target.kind is ControlKind.MENU
    )
    if len(matches) != 1:
        raise PhysicalDesktopAcceptanceError(
            "acknowledged frame does not expose one Pad File-menu hit target"
        )
    target = matches[0]
    center_x = target.rect.left + target.rect.width // 2
    center_y = target.rect.top + target.rect.height // 2
    if display_state.hit_test(center_x, center_y, display_token=token) != target:
        raise PhysicalDesktopAcceptanceError(
            "Pad File-menu target is not the acknowledged painter-order hit"
        )
    return target


def _require_pad_file_popup_hits(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
) -> tuple[ControlHitTarget, ...]:
    """Bind every enabled File entry to the exact acknowledged paint hit map."""

    token = (offer.offer_id, offer.scope)
    if display_state.hit_map_token != token or display_ack != token:
        raise PhysicalDesktopAcceptanceError(
            "Pad File popup lacks the exact acknowledged semantic hit map"
        )
    region, _menu_bar, menu = _pad_file_menu(offer)
    if not _pad_file_menu_is_open(offer):
        raise PhysicalDesktopAcceptanceError(
            "Pad File popup hit validation requires an open menu"
        )
    title_identity = ControlIdentity(
        region.owner_id,
        region.owner_generation,
        menu.control_id,
    )
    title_matches = tuple(
        target
        for target in display_state.hit_targets
        if target.identity == title_identity and target.kind is ControlKind.MENU
    )
    if len(title_matches) != 1:
        raise PhysicalDesktopAcceptanceError(
            "acknowledged open frame does not expose one Pad File title target"
        )
    expected = tuple(
        ControlIdentity(
            region.owner_id,
            region.owner_generation,
            entry.control_id,
        )
        for entry in menu.entries
        if isinstance(entry, MenuItemDraw)
        and entry.state & ControlState.ENABLED
    )
    actual = tuple(
        target
        for target in display_state.hit_targets
        if target.kind is ControlKind.MENU_ITEM
    )
    actual_identities = tuple(target.identity for target in actual)
    if (
        len(actual_identities) != len(set(actual_identities))
        or actual_identities != expected
    ):
        raise PhysicalDesktopAcceptanceError(
            "acknowledged Pad File popup hit targets do not exactly match its "
            "enabled visible items in semantic painter order"
        )
    for target in title_matches + actual:
        if target.rect.width <= 0 or target.rect.height <= 0:
            raise PhysicalDesktopAcceptanceError(
                "acknowledged Pad File popup contains an empty item hit target"
            )
        center_x = target.rect.left + target.rect.width // 2
        center_y = target.rect.top + target.rect.height // 2
        if display_state.hit_test(
            center_x,
            center_y,
            display_token=token,
        ) != target:
            raise PhysicalDesktopAcceptanceError(
                "Pad File popup item is not the acknowledged painter-order hit"
            )
    return title_matches + actual


def _control_target_evidence(
    target: ControlHitTarget,
    *,
    label: str,
    shortcut: str = "",
) -> dict[str, object]:
    """Serialize one physical semantic target without changing its identity."""

    identity = target.identity
    payload: dict[str, object] = {
        "owner_id": identity.owner_id,
        "owner_generation": identity.owner_generation,
        "control_id": identity.control_id,
        "kind": target.kind.name,
        "label": label,
        "pixel_rect": {
            "left": target.rect.left,
            "top": target.rect.top,
            "right": target.rect.right,
            "bottom": target.rect.bottom,
        },
    }
    if shortcut:
        payload["shortcut"] = shortcut
    return payload


def _request_acceptance_input(
    client: SessionClient,
    method: str,
    value: str,
    offer: TerminalDisplayOffer,
    generation: int,
    *,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
) -> tuple[str, AcceptedInputEvidence | None]:
    """Send one display-bound journey action and preserve exact evidence."""

    params: dict[str, object] = {
        "generation": generation,
        "display_offer_id": offer.offer_id,
        "display_scope": display_scope_to_wire(offer.scope),
    }
    rpc_method = method
    semantic_target = None
    if method == "send_key":
        if value == "escape" and _pad_file_menu_is_open(offer):
            popup_targets = _require_pad_file_popup_hits(
                offer,
                display_state,
                display_ack,
            )
            _region, _menu_bar, menu = _pad_file_menu(offer)
            item_entries = tuple(
                entry
                for entry in menu.entries
                if isinstance(entry, MenuItemDraw)
                and entry.state & ControlState.ENABLED
            )
            semantic_target = {
                "kind": "MENU_POPUP",
                "label": PAD_FILE_MENU_EVIDENCE,
                "targets": [
                    _control_target_evidence(
                        popup_targets[0],
                        label=menu.label,
                    )
                ]
                + [
                    _control_target_evidence(
                        target,
                        label=entry.label,
                        shortcut=entry.shortcut,
                    )
                    for entry, target in zip(
                        item_entries,
                        popup_targets[1:],
                        strict=True,
                    )
                ],
            }
        params["key"] = value
    elif method == "send_text":
        params["text"] = value
    elif method == "activate_pad_file_menu":
        if value != PAD_FILE_MENU_EVIDENCE:
            raise PhysicalDesktopAcceptanceError(
                "Pad File activation carries an unexpected evidence label"
            )
        target = _pad_file_hit_target(offer, display_state, display_ack)
        identity = target.identity
        rpc_method = "send_control_event"
        params.update(
            {
                "owner_id": identity.owner_id,
                "owner_generation": identity.owner_generation,
                "control_id": identity.control_id,
                "modifiers": 0,
            }
        )
        semantic_target = _control_target_evidence(
            target,
            label=PAD_FILE_MENU_EVIDENCE,
        )
    else:
        raise PhysicalDesktopAcceptanceError(
            f"unsupported acceptance input method {method!r}"
        )

    response = client.request(rpc_method, **params)
    input_status = response.get("status")
    expected_field = (
        "accepted_bytes" if rpc_method == "send_text" else "accepted_events"
    )
    expected_value = (
        len(value.encode("utf-8")) if rpc_method == "send_text" else 1
    )
    if input_status == "progress":
        if response.get(expected_field) != expected_value:
            raise PhysicalDesktopAcceptanceError(
                f"{rpc_method} reported partial acceptance"
            )
        evidence = AcceptedInputEvidence(
            rpc_method,
            value,
            offer.offer_id,
            generation,
            display_scope_to_wire(offer.scope),
            semantic_target,
        )
    elif input_status == "backpressured":
        if response.get(expected_field) != 0:
            raise PhysicalDesktopAcceptanceError(
                f"{rpc_method} backpressure reported accepted input"
            )
        evidence = None
    else:
        raise PhysicalDesktopAcceptanceError(
            f"{rpc_method} returned invalid status {input_status!r}"
        )
    return str(input_status), evidence


InputSender = Callable[[str, str, TerminalDisplayOffer, int], str]


@dataclass(frozen=True)
class JourneyProgress:
    milestone: str | None = None
    complete: bool = False


@dataclass(frozen=True)
class _PendingJourneyInput:
    method: str
    value: str
    target_stage: int
    offer_id: int
    scope: DisplayScope
    generation: int


class DesktopAcceptanceJourney:
    """Advance app input only across newly acknowledged physical frames."""

    def __init__(self, ready_markers: tuple[str, ...]):
        if not ready_markers or any(not marker for marker in ready_markers):
            raise ValueError("ready_markers must contain visible strings")
        self.ready_markers = tuple(ready_markers)
        self.stage = 0
        self.frame_barrier = 0
        self._pending: _PendingJourneyInput | None = None
        self._lineage: tuple[int, int, int, int, int] | None = None

    @property
    def has_pending_input(self) -> bool:
        return self._pending is not None

    @property
    def final_stage(self) -> int:
        return DESKTOP_ACCEPTANCE_FINAL_STAGE

    def _milestone(self, name: str) -> str:
        """Re-emit a source name when a newer frame reauthorizes its action."""

        return name

    @staticmethod
    def _offer_lineage(
        offer: TerminalDisplayOffer,
        generation: int,
    ) -> tuple[int, int, int, int, int]:
        scope = offer.scope
        return (
            generation,
            scope.attachment_epoch,
            scope.session_id,
            scope.presentation_epoch,
            scope.geometry_generation,
        )

    def _send(
        self,
        method: str,
        value: str,
        target_stage: int,
        offer: TerminalDisplayOffer,
        generation: int,
        sender: InputSender,
    ) -> None:
        attempted = _PendingJourneyInput(
            method,
            value,
            target_stage,
            offer.offer_id,
            offer.scope,
            generation,
        )
        if self._pending is not None and attempted != self._pending:
            raise PhysicalDesktopAcceptanceError(
                "pending input retry changed its exact authorizing frame"
            )
        status = sender(method, value, offer, generation)
        if status == "progress":
            self.stage = target_stage
            self._pending = None
        elif status == "backpressured":
            self._pending = attempted
        else:
            raise PhysicalDesktopAcceptanceError(
                f"viewer-owned {method} input was rejected as {status!r}"
            )
        self.frame_barrier = offer.offer_id

    def retry_pending_current(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        sender: InputSender,
    ) -> bool:
        """Retry backpressured input against the same acknowledged frame."""

        if self._pending is None:
            return False
        pending = self._pending
        if (
            offer.offer_id != pending.offer_id
            or offer.scope != pending.scope
            or generation != pending.generation
        ):
            raise PhysicalDesktopAcceptanceError(
                "pending input cannot leave its exact authorizing frame"
            )
        self._send(
            pending.method,
            pending.value,
            pending.target_stage,
            offer,
            generation,
            sender,
        )
        return True

    def after_present(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
    ) -> JourneyProgress:
        """Observe one successfully presented frame and maybe send one action."""

        lineage = self._offer_lineage(offer, generation)
        if self._lineage is not None and lineage != self._lineage:
            raise PhysicalDesktopAcceptanceError(
                "physical acceptance frame left its original session lineage"
            )
        if offer.offer_id <= self.frame_barrier:
            return JourneyProgress()
        text = projection.text
        if self.stage > 0:
            _require_canonical_menu_aggregate(projection)
        if self._pending is not None:
            # Backpressure is admitted only with zero accepted input.  A newer
            # acknowledged frame therefore discards the old authorization and
            # must independently satisfy the current stage before _send binds
            # a fresh request to its offer, scope, and generation.
            self._pending = None

        if self.stage == 0 and all(marker in text for marker in self.ready_markers):
            self._lineage = lineage
            _require_canonical_menu_aggregate(projection)
            if _pad_file_menu_is_open(offer):
                raise PhysicalDesktopAcceptanceError(
                    "canonical initial Pad File menu is already open"
                )
            milestone = self._milestone("desk-complete")
            self._send("send_key", "alt+1", 1, offer, generation, sender)
            return JourneyProgress(milestone)
        if self.stage == 1 and PAD_FOCUS_MARKER in text:
            milestone = self._milestone("pad-file-menu-activation-source")
            self._send(
                "activate_pad_file_menu",
                PAD_FILE_MENU_EVIDENCE,
                2,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if (
            self.stage == 2
            and PAD_FOCUS_MARKER in text
            and _pad_file_menu_is_open(offer)
        ):
            milestone = self._milestone("pad-file-menu-open")
            self._send("send_key", "escape", 3, offer, generation, sender)
            return JourneyProgress(milestone)
        if (
            self.stage == 3
            and PAD_FOCUS_MARKER in text
            and not _pad_file_menu_is_open(offer)
        ):
            if PAD_ACCEPTANCE_TEXT in text:
                raise PhysicalDesktopAcceptanceError(
                    "Pad acceptance marker was visible before editor input"
                )
            milestone = self._milestone("pad-file-menu-closed")
            self._send(
                "send_text",
                PAD_ACCEPTANCE_TEXT,
                4,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if (
            self.stage == 4
            and PAD_FOCUS_MARKER in text
            and PAD_ACCEPTANCE_TEXT in text
        ):
            milestone = self._milestone("pad-edited")
            self._send("send_key", "alt+3", 5, offer, generation, sender)
            return JourneyProgress(milestone)
        if self.stage == 5 and DAYBOOK_FOCUS_MARKER in text:
            self._send("send_key", "ctrl+n", 6, offer, generation, sender)
            return JourneyProgress()
        if (
            self.stage == 6
            and DAYBOOK_FOCUS_MARKER in text
            and DAYBOOK_PROMPT_MARKER in text
        ):
            if DAYBOOK_ACCEPTANCE_TASK in text:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook acceptance marker was visible before task input"
                )
            self._send(
                "send_text",
                DAYBOOK_ACCEPTANCE_TASK,
                7,
                offer,
                generation,
                sender,
            )
            return JourneyProgress()
        if (
            self.stage == 7
            and DAYBOOK_FOCUS_MARKER in text
            and DAYBOOK_PROMPT_MARKER in text
            and DAYBOOK_ACCEPTANCE_TASK in text
        ):
            self._send("send_key", "enter", 8, offer, generation, sender)
            return JourneyProgress()
        if (
            self.stage == DESKTOP_ACCEPTANCE_FINAL_STAGE
            and DAYBOOK_FOCUS_MARKER in text
            and DAYBOOK_ACCEPTANCE_TASK in text
            and DAYBOOK_PROMPT_MARKER not in text
        ):
            self.frame_barrier = offer.offer_id
            return JourneyProgress(
                self._milestone("daybook-task-added"),
                True,
            )
        return JourneyProgress()


def _surface_rgba(pygame_module, surface) -> bytes:
    return pygame_module.image.tostring(surface, "RGBA")


def _terminal_text(terminal: VirtualTerminal) -> str:
    with terminal._lock:
        return "\n".join(
            "".join(cell[0] for cell in row).rstrip()
            for row in terminal.grid
        )


def _guest_boot_failure(text: str) -> str | None:
    lines = [line.rstrip() for line in text.splitlines() if line.strip()]
    failure_indexes = [
        index
        for index, line in enumerate(lines)
        if (
            "COLD SOURCE LOAD FAIL" in line
            or "[akashic] desktop exception" in line
            or "EVALUATE depth limit exceeded" in line
            or ("line " in line and "? (not found)" in line)
        )
    ]
    if not failure_indexes:
        return None
    index = failure_indexes[-1]
    return "\n".join(lines[max(0, index - 2) : index + 1])


def _fit_viewer_font(
    pygame_module,
    font_path: Path | None,
    requested_size: int,
    cols: int,
    rows: int,
):
    """Choose the largest requested font that fits the physical display."""

    display = pygame_module.display.Info()
    max_width = max(1, int(display.current_w * 0.92))
    max_height = max(1, int(display.current_h * 0.86))
    smallest = min(MIN_READABLE_FONT_SIZE, requested_size)
    for size in range(requested_size, smallest - 1, -1):
        font = (
            pygame_module.font.Font(str(font_path), size)
            if font_path is not None
            else pygame_module.font.SysFont("monospace", size)
        )
        cell_width = max(1, font.size("M")[0])
        cell_height = font.get_linesize()
        if cols * cell_width <= max_width and rows * cell_height <= max_height:
            return font, cell_width, cell_height, size
    raise PhysicalDesktopAcceptanceError(
        f"{cols}x{rows} terminal does not fit the {display.current_w}x"
        f"{display.current_h} physical display at readable font size "
        f"{smallest}"
    )


def _dispatch_semantic_pointer_event(
    pygame_module,
    semantic_pointer: _SemanticPointerInteractor,
    keyboard: _GuestKeyboardForwarder,
    event,
    terminal_size: tuple[int, int],
) -> bool:
    """Route one physical event through the normal ACK-bound control path."""

    if event.type == getattr(pygame_module, "MOUSEMOTION", -1):
        semantic_pointer.move(event.pos, terminal_size)
        return True
    if (
        event.type == getattr(pygame_module, "MOUSEBUTTONDOWN", -1)
        and event.button == 1
    ):
        semantic_pointer.left_down(event.pos, terminal_size)
        return True
    if (
        event.type == getattr(pygame_module, "MOUSEBUTTONUP", -1)
        and event.button == 1
    ):
        semantic_pointer.left_up(
            event.pos,
            terminal_size,
            modifiers=_pygame_apt_modifiers(pygame_module, event),
        )
        return True
    if event.type in {
        getattr(pygame_module, "WINDOWFOCUSLOST", -1),
        getattr(pygame_module, "WINDOWFOCUSGAINED", -2),
    }:
        semantic_pointer.clear()
        if event.type == getattr(pygame_module, "WINDOWFOCUSLOST", -1):
            keyboard.reset()
        return True
    return False


def _pump_physical_viewer_events(
    pygame_module,
    semantic_pointer: _SemanticPointerInteractor,
    keyboard: _GuestKeyboardForwarder,
    terminal_size: tuple[int, int],
    *,
    closing_is_error: bool,
) -> bool:
    """Process viewer events without discarding semantic pointer input."""

    for event in pygame_module.event.get():
        if event.type == pygame_module.QUIT:
            if closing_is_error:
                raise PhysicalDesktopAcceptanceError(
                    "physical acceptance window was closed"
                )
            return False
        _dispatch_semantic_pointer_event(
            pygame_module,
            semantic_pointer,
            keyboard,
            event,
            terminal_size,
        )
    keyboard.flush_pending()
    return True


def _keep_window_visible(
    seconds: float,
    *,
    event_pump: Callable[[bool], bool],
    closing_is_error: bool,
) -> None:
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        if not event_pump(closing_is_error):
            return
        time.sleep(min(0.02, max(0.0, until - time.monotonic())))


def _record_frame(
    pygame_module,
    font,
    cell_width: int,
    cell_height: int,
    artifact_root: Path,
    milestone: str,
    offer: TerminalDisplayOffer,
    generation: int,
    projection: RichScreenProjection,
    composed_surface,
) -> PresentedFrameEvidence:
    png_path = (artifact_root / f"{milestone}.png").resolve()
    retained_path = (artifact_root / f"{milestone}-retained-only.png").resolve()
    text_path = (artifact_root / f"{milestone}-retained.txt").resolve()
    pygame_module.image.save(composed_surface, str(png_path))
    composed_bytes = _surface_rgba(pygame_module, composed_surface)

    retained_surface = pygame_module.Surface(
        composed_surface.get_size(), flags=pygame_module.SRCALPHA
    )
    retained_surface.fill((0, 0, 0, 0))
    composite_draw_plane(
        pygame_module,
        retained_surface,
        offer.retained,
        font,
        cell_width,
        cell_height,
    )
    retained_bytes = _surface_rgba(pygame_module, retained_surface)
    nonblack = sum(
        any(retained_bytes[offset : offset + 3])
        for offset in range(0, len(retained_bytes), 4)
    )
    if nonblack == 0:
        raise PhysicalDesktopAcceptanceError(
            f"{milestone} retained compositor produced no non-black "
            "physical pixels"
        )
    pygame_module.image.save(retained_surface, str(retained_path))
    text_path.write_text(projection.text, encoding="utf-8")
    retained_text_bytes = projection.text.encode("utf-8")
    return PresentedFrameEvidence(
        milestone=milestone,
        offer_id=offer.offer_id,
        generation=generation,
        scope=display_scope_to_wire(offer.scope),
        logical_cols=projection.cols,
        logical_rows=projection.rows,
        draw_count=projection.draw_count,
        pixel_sha256=hashlib.sha256(composed_bytes).hexdigest(),
        retained_text_sha256=hashlib.sha256(retained_text_bytes).hexdigest(),
        retained_only_sha256=hashlib.sha256(retained_bytes).hexdigest(),
        retained_only_nonblack_pixels=nonblack,
        png_path=png_path,
        retained_png_path=retained_path,
        retained_text_path=text_path,
        menu_signatures=projection.menu_signatures,
        renderer_owned_gap_cells=projection.renderer_owned_gap_cells,
    )


def _store_milestone_frame(
    frames: list[PresentedFrameEvidence],
    frame: PresentedFrameEvidence,
) -> None:
    """Keep only the latest independently authorized source for a milestone."""

    matches = tuple(
        index
        for index, existing in enumerate(frames)
        if existing.milestone == frame.milestone
    )
    if len(matches) > 1:
        raise PhysicalDesktopAcceptanceError(
            f"acceptance evidence duplicated milestone {frame.milestone!r}"
        )
    if matches:
        frames[matches[0]] = frame
    else:
        frames.append(frame)


def write_acceptance_manifest(
    artifact_root: Path,
    video_driver: str,
    frames: tuple[PresentedFrameEvidence, ...],
    inputs: tuple[AcceptedInputEvidence, ...],
) -> Path:
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    manifest_path = artifact_root / "manifest.json"
    payload = {
        "video_driver": video_driver,
        "physical_boundary": "pygame.display.flip",
        "acknowledged_evidence_viewport": {
            "origin": [0, 0],
            "extent": "recorded frame PNG dimensions",
            "host_mode_bar": "excluded",
        },
        "frames": [frame.to_dict() for frame in frames],
        "inputs": [event.to_dict() for event in inputs],
    }
    manifest_path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest_path


def _connected_peer_pid(client: SessionClient) -> int:
    if not hasattr(socket, "SO_PEERCRED"):
        raise PhysicalDesktopAcceptanceError(
            "physical acceptance requires Unix SO_PEERCRED process binding"
        )
    connection = client._socket
    if connection is None:
        raise PhysicalDesktopAcceptanceError(
            "shared-session client has no connected socket"
        )
    credentials = connection.getsockopt(
        socket.SOL_SOCKET,
        socket.SO_PEERCRED,
        struct.calcsize("3i"),
    )
    peer_pid, _peer_uid, _peer_gid = struct.unpack("3i", credentials)
    return peer_pid


def _connect(
    socket_path: str,
    deadline: float,
    expected_server_pid: int,
) -> SessionClient:
    if (
        isinstance(expected_server_pid, bool)
        or not isinstance(expected_server_pid, int)
        or expected_server_pid <= 0
    ):
        raise ValueError("expected_server_pid must be a positive process id")
    last_error: OSError | None = None
    while time.monotonic() < deadline:
        client = SessionClient(
            socket_path,
            timeout=SESSION_REQUEST_TIMEOUT_SECONDS,
        )
        try:
            client.connect()
        except OSError as exc:
            last_error = exc
            client.close()
            time.sleep(0.05)
            continue
        peer_pid = _connected_peer_pid(client)
        if peer_pid != expected_server_pid:
            client.close()
            raise PhysicalDesktopAcceptanceError(
                f"shared-session socket belongs to process {peer_pid}, not "
                f"the launched server process {expected_server_pid}"
            )
        return client
    raise PhysicalDesktopAcceptanceError(
        f"shared-session server did not become reachable: {last_error}"
    )


def run_physical_desktop_acceptance(
    socket_path: str,
    artifact_root: Path,
    *,
    expected_server_pid: int,
    cols: int,
    rows: int,
    ready_markers: tuple[str, ...],
    timeout: float,
    font_path: Path | None = None,
    font_size: int = 18,
    action_delay: float = 0.75,
    hold_seconds: float = 10.0,
) -> PhysicalDesktopAcceptanceEvidence:
    """Run and record the real Desk/Pad/Daybook physical-view journey."""

    if timeout <= 0:
        raise ValueError("timeout must be positive")
    if (cols, rows) != (CANONICAL_DESKTOP_COLS, CANONICAL_DESKTOP_ROWS):
        raise ValueError(
            "physical Desktop acceptance requires the canonical "
            f"{CANONICAL_DESKTOP_COLS}x{CANONICAL_DESKTOP_ROWS} geometry"
        )
    if font_size <= 0:
        raise ValueError("font_size must be positive")
    if action_delay < 0:
        raise ValueError("action_delay must not be negative")
    if hold_seconds < 0:
        raise ValueError("hold_seconds must not be negative")
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + timeout
    client = _connect(socket_path, deadline, expected_server_pid)
    pygame_initialized = False
    try:
        try:
            import pygame
        except ImportError as exc:
            raise PhysicalDesktopAcceptanceError(
                "physical desktop acceptance requires pygame"
            ) from exc

        if not _display_claimed(client.request("claim_display")):
            raise PhysicalDesktopAcceptanceError(
                "physical acceptance could not claim the display lease"
            )
        status = client.request("status", detailed=False)
        generation = int(status["generation"])
        display_required = bool(status["rich_terminal"]["display_required"])
        terminal = VirtualTerminal(cols=cols, rows=rows)
        revision = -1
        display_state = _RetainedDisplayState()
        keyboard = _GuestKeyboardForwarder(
            pygame,
            client,
            generation=generation,
            input_enabled=True,
            display_required=display_required,
        )
        semantic_pointer = _SemanticPointerInteractor(display_state, keyboard)

        os.environ.setdefault("SDL_VIDEO_CENTERED", "1")
        pygame.display.init()
        pygame_initialized = True
        pygame.font.init()
        driver = pygame.display.get_driver()
        if driver.lower() in {"dummy", "offscreen"}:
            raise PhysicalDesktopAcceptanceError(
                f"SDL video driver {driver!r} is not a physical display sink"
            )
        font, cell_width, cell_height, fitted_font_size = _fit_viewer_font(
            pygame,
            font_path,
            font_size,
            terminal.cols,
            terminal.rows,
        )
        chrome_font = pygame.font.SysFont("monospace", 16, bold=True)
        chrome_height = chrome_font.get_linesize() + 6
        window = pygame.display.set_mode(
            (
                terminal.cols * cell_width,
                terminal.rows * cell_height + chrome_height,
            )
        )
        print(
            "Physical viewer: "
            f"{terminal.cols}x{terminal.rows} cells, "
            f"{terminal.cols * cell_width}x"
            f"{terminal.rows * cell_height} terminal pixels, "
            f"{terminal.cols * cell_width}x"
            f"{terminal.rows * cell_height + chrome_height} window pixels, "
            f"{fitted_font_size}px font, {driver} driver"
        )
        pygame.display.set_caption(
            "Akashic rich-terminal acceptance — starting "
            f"({fitted_font_size}px)"
        )
        glyph_cache: dict = {}
        journey = DesktopAcceptanceJourney(tuple(ready_markers))
        frames: list[PresentedFrameEvidence] = []
        inputs: list[AcceptedInputEvidence] = []
        last_accepted_offer: TerminalDisplayOffer | None = None
        last_accepted_generation: int | None = None
        latest_cell_text = ""
        latest_retained_text: str | None = None
        latest_retained_draw_count = 0
        cell_missing_markers = tuple(ready_markers)
        retained_missing_markers: tuple[str, ...] | None = None
        cell_ready = False
        offers_seen = 0
        last_seen_offer_id = 0
        diagnostic_state: AcceptanceDiagnosticState | None = None
        chrome_text = CELL_FALLBACK_MODE
        chrome_background = (96, 28, 28)
        chrome_foreground = (255, 238, 238)

        def pump_events(closing_is_error: bool) -> bool:
            return _pump_physical_viewer_events(
                pygame,
                semantic_pointer,
                keyboard,
                (
                    terminal.cols * cell_width,
                    terminal.rows * cell_height,
                ),
                closing_is_error=closing_is_error,
            )

        def announce(state: AcceptanceDiagnosticState) -> None:
            nonlocal diagnostic_state, chrome_text
            nonlocal chrome_background, chrome_foreground
            chrome_text = (
                f"{state.mode} | stage={journey.stage}/{journey.final_stage} | "
                f"CELL-ready={state.cell_ready}"
                + (
                    ""
                    if state.offer_id is None
                    else f" | offer={state.offer_id} draws={state.draw_count}"
                )
                + f" | missing={len(state.missing_ready_markers)}"
            )
            if state.mode == RETAINED_ACKNOWLEDGED_MODE:
                chrome_background = (0, 82, 68)
                chrome_foreground = (225, 255, 248)
            elif state.mode == RETAINED_PENDING_MODE:
                chrome_background = (103, 73, 0)
                chrome_foreground = (255, 247, 214)
            else:
                chrome_background = (96, 28, 28)
                chrome_foreground = (255, 238, 238)
            if state != diagnostic_state:
                print(f"Physical viewer state: {state.summary()}")
                pygame.display.set_caption(
                    f"Akashic acceptance — {state.mode} "
                    f"({fitted_font_size}px)"
                )
                diagnostic_state = state

        def send_input(
            method: str,
            value: str,
            offer: TerminalDisplayOffer,
            input_generation: int,
        ) -> str:
            _keep_window_visible(
                action_delay,
                event_pump=pump_events,
                closing_is_error=True,
            )
            input_status, evidence = _request_acceptance_input(
                client,
                method,
                value,
                offer,
                input_generation,
                display_state=display_state,
                display_ack=keyboard.display_ack,
            )
            if evidence is not None:
                inputs.append(evidence)
            return input_status

        while time.monotonic() < deadline:
            pump_events(True)

            status = client.request("status", detailed=False)
            revision, _ = _accept_status_update(
                status,
                keyboard=keyboard,
                display_state=display_state,
                revision=revision,
            )
            update = client.request(
                "screen",
                since=revision,
                since_offer=display_state.since_offer,
            )
            revision, resized = _accept_screen_update(
                update,
                display_holder=True,
                terminal=terminal,
                keyboard=keyboard,
                display_state=display_state,
                revision=revision,
            )
            guest_failure = _guest_boot_failure(_terminal_text(terminal))
            if guest_failure is not None:
                raise PhysicalDesktopAcceptanceError(
                    _guest_failure_message(
                        client,
                        artifact_root,
                        guest_failure,
                    )
                )
            latest_cell_text = _terminal_text(terminal)
            cell_ready, cell_missing_markers = _marker_status(
                latest_cell_text,
                tuple(ready_markers),
            )
            if resized:
                font, cell_width, cell_height, fitted_font_size = (
                    _fit_viewer_font(
                        pygame,
                        font_path,
                        font_size,
                        terminal.cols,
                        terminal.rows,
                    )
                )
                glyph_cache.clear()
                window = pygame.display.set_mode(
                    (
                        terminal.cols * cell_width,
                        terminal.rows * cell_height + chrome_height,
                    )
                )
                print(
                    "Physical viewer resized: "
                    f"{terminal.cols}x{terminal.rows} cells, "
                    f"{terminal.cols * cell_width}x"
                    f"{terminal.rows * cell_height} terminal pixels, "
                    f"{terminal.cols * cell_width}x"
                    f"{terminal.rows * cell_height + chrome_height} "
                    "window pixels, "
                    f"{fitted_font_size}px font"
                )
                pygame.display.set_caption(
                    "Akashic rich-terminal acceptance — running "
                    f"({fitted_font_size}px)"
                )

            frame_offer = display_state.pending_offer
            frame_generation = (
                keyboard.generation
                if display_state.pending_generation is None
                else display_state.pending_generation
            )
            frame_projection = (
                None
                if frame_offer is None
                else reconstruct_retained_screen(frame_offer)
            )
            if frame_projection is not None:
                _require_canonical_desktop_geometry(frame_projection)
            if frame_offer is None and display_state.retained_plane is None:
                announce(
                    AcceptanceDiagnosticState(
                        CELL_FALLBACK_MODE,
                        cell_ready,
                        missing_ready_markers=cell_missing_markers,
                    )
                )
            elif frame_offer is None:
                assert last_accepted_offer is not None
                announce(
                    AcceptanceDiagnosticState(
                        RETAINED_ACKNOWLEDGED_MODE,
                        cell_ready,
                        offer_id=last_accepted_offer.offer_id,
                        scope=display_scope_to_wire(last_accepted_offer.scope),
                        draw_count=latest_retained_draw_count,
                        retained_text_sha256=(
                            None
                            if latest_retained_text is None
                            else hashlib.sha256(
                                latest_retained_text.encode("utf-8")
                            ).hexdigest()
                        ),
                        missing_ready_markers=(
                            ()
                            if retained_missing_markers is None
                            else retained_missing_markers
                        ),
                    )
                )
            else:
                if frame_offer.offer_id != last_seen_offer_id:
                    offers_seen += 1
                    last_seen_offer_id = frame_offer.offer_id
                assert frame_projection is not None
                latest_retained_text = frame_projection.text
                latest_retained_draw_count = frame_projection.draw_count
                retained_sha = hashlib.sha256(
                    latest_retained_text.encode("utf-8")
                ).hexdigest()
                _retained_ready, retained_missing_markers = _marker_status(
                    latest_retained_text,
                    tuple(ready_markers),
                )
                announce(
                    AcceptanceDiagnosticState(
                        RETAINED_PENDING_MODE,
                        cell_ready,
                        offer_id=frame_offer.offer_id,
                        scope=display_scope_to_wire(frame_offer.scope),
                        draw_count=frame_projection.draw_count,
                        retained_text_sha256=retained_sha,
                        missing_ready_markers=retained_missing_markers,
                    )
                )
            composed_surface = None

            def draw_host_chrome() -> tuple[int, int, int, int]:
                terminal_height = terminal.rows * cell_height
                chrome_rect = (
                    0,
                    terminal_height,
                    window.get_width(),
                    chrome_height,
                )
                pygame.draw.rect(window, chrome_background, chrome_rect)
                chrome_surface = chrome_font.render(
                    chrome_text,
                    True,
                    chrome_foreground,
                )
                window.blit(chrome_surface, (4, terminal_height + 3))
                return chrome_rect

            def draw_frame() -> None:
                nonlocal composed_surface
                window.fill((0, 0, 0))
                frame_result = compose_terminal_frame_result(
                    pygame,
                    terminal,
                    font,
                    cell_width,
                    cell_height,
                    retained_plane=display_state.frame_plane,
                    show_cursor=True,
                    glyph_cache=glyph_cache,
                    control_font=chrome_font,
                    hovered=semantic_pointer.hovered,
                    pressed=semantic_pointer.pressed,
                )
                composed_surface = frame_result.surface
                window.blit(composed_surface, (0, 0))
                # Host diagnostics occupy separate window rows.  The composed
                # terminal surface recorded as acceptance evidence stays exact.
                draw_host_chrome()
                if frame_offer is not None:
                    display_state.stage_frame_hit_map(
                        frame_offer,
                        frame_result.hit_targets,
                    )

            presentation = draw_flip_and_present(
                pygame,
                client,
                draw_frame,
                offer=frame_offer,
                generation=frame_generation,
                active=True,
            )
            if frame_offer is None:
                if (
                    journey.has_pending_input
                    and last_accepted_offer is not None
                    and last_accepted_generation is not None
                ):
                    journey.retry_pending_current(
                        last_accepted_offer,
                        last_accepted_generation,
                        send_input,
                    )
                time.sleep(0.01)
                continue
            accepted_revision = display_state.finish_presentation(presentation)
            if accepted_revision is None:
                revision = -1
                keyboard.clear_display_context(waiting=True)
                time.sleep(0.01)
                continue
            revision = accepted_revision
            keyboard.acknowledge_display_offer(
                frame_offer.offer_id,
                frame_offer.scope,
            )
            if frame_projection is None:
                raise PhysicalDesktopAcceptanceError(
                    "accepted display offer lost its retained projection"
                )
            last_accepted_offer = frame_offer
            last_accepted_generation = frame_generation
            announce(
                AcceptanceDiagnosticState(
                    RETAINED_ACKNOWLEDGED_MODE,
                    cell_ready,
                    offer_id=frame_offer.offer_id,
                    scope=display_scope_to_wire(frame_offer.scope),
                    draw_count=frame_projection.draw_count,
                    retained_text_sha256=hashlib.sha256(
                        frame_projection.text.encode("utf-8")
                    ).hexdigest(),
                    missing_ready_markers=(
                        ()
                        if retained_missing_markers is None
                        else retained_missing_markers
                    ),
                )
            )
            pygame.display.update(draw_host_chrome())
            progress = journey.after_present(
                frame_offer,
                frame_generation,
                frame_projection,
                send_input,
            )
            pygame.display.set_caption(
                f"Akashic acceptance — {diagnostic_state.mode} | "
                f"stage {journey.stage}/{journey.final_stage} "
                f"({fitted_font_size}px)"
            )
            if progress.milestone is not None:
                if composed_surface is None:
                    raise PhysicalDesktopAcceptanceError(
                        "physical compositor produced no frame surface"
                    )
                _store_milestone_frame(
                    frames,
                    _record_frame(
                        pygame,
                        font,
                        cell_width,
                        cell_height,
                        artifact_root,
                        progress.milestone,
                        frame_offer,
                        frame_generation,
                        frame_projection,
                        composed_surface,
                    ),
                )
            if progress.complete:
                manifest = write_acceptance_manifest(
                    artifact_root,
                    driver,
                    tuple(frames),
                    tuple(inputs),
                )
                pygame.display.set_caption(
                    "Akashic rich-terminal acceptance — PASS "
                    f"({fitted_font_size}px)"
                )
                _keep_window_visible(
                    hold_seconds,
                    event_pump=pump_events,
                    closing_is_error=False,
                )
                return PhysicalDesktopAcceptanceEvidence(
                    manifest,
                    driver,
                    tuple(frames),
                    tuple(inputs),
                )
            time.sleep(0.01)
        timeout_detail = _write_timeout_diagnostics(
            artifact_root,
            cell_text=latest_cell_text,
            retained_text=latest_retained_text,
            stage=journey.stage,
            cell_ready=cell_ready,
            offers_seen=offers_seen,
            since_offer=display_state.since_offer,
            cell_missing_markers=cell_missing_markers,
            retained_missing_markers=retained_missing_markers,
            frame_barrier=journey.frame_barrier,
            pending_input=journey.has_pending_input,
        )
        state_detail = _timeout_state_message(
            client,
            artifact_root,
            timeout_detail,
        )
        raise PhysicalDesktopAcceptanceError(
            "physical Desktop journey timed out: "
            f"{timeout_detail}\n  {state_detail}"
        )
    except PhysicalDesktopAcceptanceError:
        raise
    except (ConnectionError, OSError, RuntimeError, TypeError, ValueError) as exc:
        raise PhysicalDesktopAcceptanceError(str(exc)) from exc
    finally:
        client.close()
        if pygame_initialized:
            try:
                pygame.quit()
            except Exception:
                pass


__all__ = [
    "DAYBOOK_ACCEPTANCE_TASK",
    "DesktopAcceptanceJourney",
    "PAD_ACCEPTANCE_TEXT",
    "PhysicalDesktopAcceptanceError",
    "PhysicalDesktopAcceptanceEvidence",
    "PresentedFrameEvidence",
    "AcceptedInputEvidence",
    "RichScreenProjection",
    "reconstruct_retained_screen",
    "run_physical_desktop_acceptance",
    "write_acceptance_manifest",
]
