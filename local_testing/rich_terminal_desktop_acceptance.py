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
)
from rich_terminal.retained_scene import ControlKind, ControlState
from rich_terminal.semantic_content import SemanticTextContent, SemanticTextState
from rich_terminal.retained_view import (
    DisplayScope,
    GlyphRunDraw,
    MeterDraw,
    MenuBarDraw,
    MenuDraw,
    MenuItemDraw,
    MenuSeparatorDraw,
    ReadoutDraw,
    RetainedRegionDraw,
    StatusDraw,
    TabSetDraw,
    TextAreaDraw,
    TextGridDraw,
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
SOUNDLAB_FOCUS_MARKER = "[6:Sound Lab*]"
DAYBOOK_PROMPT_MARKER = "New task:"
DAYBOOK_SHARED_SOURCE_MARKER = "# Daybook"
DAYBOOK_INITIAL_DATE = "2026-09-02"
DAYBOOK_NEXT_DATE = "2026-09-03"
CELL_FINAL_STATE_MARKERS = (
    SOUNDLAB_FOCUS_MARKER,
    "SOUND LAB",
    PAD_ACCEPTANCE_TEXT,
    DAYBOOK_NEXT_DATE,
)
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
DAYBOOK_MENU_SIGNATURE = ("File", "Entry", "Go", "Help")
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
    DAYBOOK_MENU_SIGNATURE,
    ("File", "Edit", "Data", "Help"),
    ("Agent", "Run", "Connection", "Access", "Review", "Help"),
)
SOUNDLAB_MENU_SIGNATURE = ("File", "Signal", "Render", "Help")
DESKTOP_LAUNCHER_TITLES = (
    "Akashic Pad",
    "File Explorer",
    "Daybook",
    "Grid",
    "Agent",
    "Sound Lab",
    "Streams",
)
CANONICAL_DESKTOP_COLS = 280
CANONICAL_DESKTOP_ROWS = 84
DESKTOP_LAUNCHER_WIDTH = 68
DESKTOP_LAUNCHER_PAGE_ROWS = min(max(CANONICAL_DESKTOP_ROWS - 8, 1), 10)
DESKTOP_LAUNCHER_HEIGHT = DESKTOP_LAUNCHER_PAGE_ROWS + 4
DESKTOP_LAUNCHER_TOP = (
    CANONICAL_DESKTOP_ROWS - DESKTOP_LAUNCHER_HEIGHT
) // 2
DESKTOP_LAUNCHER_LEFT = (
    CANONICAL_DESKTOP_COLS - DESKTOP_LAUNCHER_WIDTH
) // 2
DESKTOP_LAUNCHER_FIRST_ENTRY_ROW = DESKTOP_LAUNCHER_TOP + 2
DESKTOP_LAUNCHER_MARKER_COL = DESKTOP_LAUNCHER_LEFT + 1
DESKTOP_LAUNCHER_TEXT_COL = DESKTOP_LAUNCHER_LEFT + 3
DESKTOP_LAUNCHER_HEADER_COL = DESKTOP_LAUNCHER_LEFT + 2
DESKTOP_ACCEPTANCE_FINAL_STAGE = 15
DESKTOP_ACCEPTANCE_PAD_TAB_STAGE = 11
DESKTOP_ACCEPTANCE_LAUNCHER_OPEN_STAGE = 12
DESKTOP_ACCEPTANCE_LAUNCHER_END_STAGE = 13
DESKTOP_ACCEPTANCE_SOUNDLAB_SELECTED_STAGE = 14
DESKTOP_TILE_COLUMNS = 3
DESKTOP_TILE_ROWS = 2
PAD_DESKTOP_TILE = 0
DAYBOOK_DESKTOP_TILE = 2
SOUNDLAB_DESKTOP_TILE = 5
MIN_READABLE_FONT_SIZE = 12
SESSION_REQUEST_TIMEOUT_SECONDS = 15.0
CELL_FALLBACK_MODE = "CELL FALLBACK: waiting for retained frame"
RETAINED_PENDING_MODE = "RICH RETAINED: pending reference-sink acknowledgment"
RETAINED_ACKNOWLEDGED_MODE = "RICH RETAINED: reference sink acknowledged"
PERFORMANCE_TRACE_SCHEMA = "akashic-rich-terminal-performance-v2"
PERFORMANCE_TRACE_FILENAME = "performance-trace.json"
GUEST_PHASE_PROFILE_WORD = "_RTPROF-EVENT"
GUEST_PHASE_PROFILE_DEFAULT_MAX_EVENTS = 4096
GUEST_PHASE_PROFILE_MAX_EVENTS = 65_536
GUEST_PHASE_PROFILE_SCHEMA = "megapad.guest-phase-events"
GUEST_PHASE_PROFILE_SCHEMA_VERSION = 1
GUEST_PHASE_PROFILE_ENCODING = "u64-sequence-high56-phase-low8"
GUEST_PHASE_EVENT_MAX = (1 << 64) - 1
GUEST_PHASE_SEQUENCE_MAX = (1 << 56) - 1
GUEST_PEEK_MAX_CELLS = 256
GUEST_CELL_BYTES = 8
GUEST_PHASE_NAMES = {
    0: "other",
    1: "uidl_aggregate",
    2: "snapshot_import",
    3: "control_plan",
    4: "claim_plan",
    5: "residual_plan",
    6: "reserve_wrap",
    7: "hybrid_preflight",
    8: "candidate_validate",
    9: "target_pack",
    10: "delta_compare_normalize",
    11: "rtapt_capture",
    12: "commit_precheck",
    13: "rtapt_audit",
    14: "wire_encode",
}

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
    "hybrid_producer": (
        "_A1D-FAILURE-SCREEN-A",
        376,
        {
            "magic": 0,
            "size": 1,
            "self": 2,
            "adapter": 3,
            "facade": 4,
            "max_records": 7,
            "max_text": 8,
            "max_cols": 9,
            "max_rows": 10,
            "owner": 11,
            "owner_generation": 12,
            "region": 13,
            "first_object": 14,
            "phase": 15,
            "fault_status": 16,
            "cols": 17,
            "rows": 18,
            "surface_generation": 19,
            "candidate_attempt": 20,
            "source_generation": 21,
            "source_draw": 22,
            "source_record_bytes": 25,
            "source_text_bytes": 28,
            "claim_bytes": 41,
            "glyph_text_bytes": 54,
            "control_count": 55,
            "glyph_count": 56,
            "physical_generation": 57,
            "target_active_address": 275,
            "target_pending_address": 276,
            "next_region": 277,
            "next_object": 278,
            "active_draw": 279,
            "max_documents": 280,
            "source_directory_bytes": 283,
            "document_count": 284,
            "row_damage_address": 285,
            "row_damage_bytes": 286,
            "glyph_id_map_address": 287,
            "glyph_id_map_bytes": 288,
            "delta_plan_valid": 289,
            "delta_plan_active_address": 290,
            "delta_plan_pending_address": 291,
            "delta_plan_active_draw": 292,
            "delta_plan_pending_draw": 293,
            "delta_plan_control_count": 294,
            "delta_plan_glyph_count": 295,
            "delta_plan_attempt": 296,
            "delta_plan_source_generation": 297,
            "delta_plan_pending_content": 298,
            "delta_plan_active_content": 299,
            "source_content_epoch": 300,
            "max_collection_native": 301,
            "max_collections": 302,
            "max_controls": 303,
            "source_menu_text_bytes": 304,
            "collection_descriptor_bytes": 307,
            "collection_native_bytes": 310,
            "source_collection_count": 311,
            "menu_control_count": 312,
            "collection_count": 313,
            "collection_items": 314,
            "collection_utf8": 315,
            "max_collection_descriptors": 316,
            "max_data_graphics_native": 350,
            "max_data_graphics_descriptors": 351,
            "max_instrument_regions": 352,
            "max_instruments": 353,
            "data_graphics_descriptor_bytes": 356,
            "data_graphics_native_bytes": 359,
            "source_data_graphics_count": 360,
            "instrument_unit_bytes": 367,
            "instrument_region_count": 370,
            "instrument_count": 371,
            "instrument_claim_count": 374,
            "base_claim_bytes": 375,
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
    "hybrid_producer": "_RTAPTSCBOP-CONTEXT",
    "engine": "_RTAPTSCBI-ENGINE",
}


class PhysicalDesktopAcceptanceError(RuntimeError):
    """The physical Desk/Pad/Daybook contract was not completed."""


def _performance_counter(value) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return None
    return value


def _performance_counter_map(value) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    result = {}
    for key, value_count in sorted(value.items(), key=lambda item: str(item[0])):
        count = _performance_counter(value_count)
        if count is not None:
            result[str(key)] = count
    return result


def _performance_status_snapshot(status) -> dict[str, object] | None:
    """Copy only cumulative machine/transport counters used for timing."""

    if not isinstance(status, dict):
        return None
    rich = status.get("rich_terminal")
    if not isinstance(rich, dict):
        rich = {}
    return {
        "generation": _performance_counter(status.get("generation")),
        "steps": _performance_counter(status.get("steps")),
        "batches": _performance_counter(status.get("batches")),
        "revision": _performance_counter(status.get("revision")),
        "rich_terminal": {
            "machine_publications": _performance_counter(
                rich.get("machine_publications")
            ),
            "machine_publication_bytes": _performance_counter(
                rich.get("machine_publication_bytes")
            ),
            "frames": _performance_counter(rich.get("frames")),
            "frame_bytes": _performance_counter(rich.get("frame_bytes")),
            "frames_by_type": _performance_counter_map(
                rich.get("frames_by_type")
            ),
            "frame_bytes_by_type": _performance_counter_map(
                rich.get("frame_bytes_by_type")
            ),
            "decoder_buffered_bytes": _performance_counter(
                rich.get("decoder_buffered_bytes")
            ),
        },
    }


def _phase_profile_integer(
    value,
    name: str,
    *,
    minimum: int = 0,
    maximum: int | None = None,
) -> int:
    if (
        isinstance(value, bool)
        or not isinstance(value, int)
        or value < minimum
        or (maximum is not None and value > maximum)
    ):
        limit = f" and <= {maximum}" if maximum is not None else ""
        raise ValueError(f"{name} must be an integer >= {minimum}{limit}")
    return value


def _phase_profile_event(value, name: str) -> dict[str, int]:
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be an object")
    event = _phase_profile_integer(
        value.get("event"),
        f"{name} packed event",
        maximum=GUEST_PHASE_EVENT_MAX,
    )
    sequence = _phase_profile_integer(
        value.get("sequence"),
        f"{name} sequence",
        maximum=GUEST_PHASE_SEQUENCE_MAX,
    )
    phase = _phase_profile_integer(
        value.get("phase"),
        f"{name} phase",
        maximum=0xFF,
    )
    if event != (sequence << 8) | phase:
        raise ValueError(f"{name} does not match its packed event")
    if phase not in GUEST_PHASE_NAMES:
        raise ValueError(f"{name} contains an unknown phase")
    return {"event": event, "sequence": sequence, "phase": phase}


def _phase_profile_error(stage: str, exc: Exception) -> dict[str, str]:
    return {
        "stage": stage,
        "kind": type(exc).__name__,
        "message": str(exc),
    }


def _first_offer_status_metadata(status) -> tuple[dict[str, int] | None, int | None]:
    if status is None:
        return None, None
    if not isinstance(status, dict):
        raise ValueError("first-offer status must be an object")
    identity = {
        field: _phase_profile_integer(
            status.get(field),
            f"first-offer status {field}",
        )
        for field in ("generation", "steps", "batches")
    }
    revision = (
        _phase_profile_integer(
            status.get("revision"),
            "first-offer status revision",
        )
        if status.get("revision") is not None
        else None
    )
    return identity, revision


def _start_guest_phase_profile(
    client: SessionClient,
    *,
    max_events: int,
    machine_generation: int,
    first_offer_status: dict | None = None,
) -> dict[str, object]:
    """Resolve and start the generic observer at first-offer backpressure."""

    capacity = _phase_profile_integer(
        max_events,
        "phase profile max_events",
        minimum=1,
        maximum=GUEST_PHASE_PROFILE_MAX_EVENTS,
    )
    expected_generation = _phase_profile_integer(
        machine_generation,
        "phase profile machine generation",
    )
    first_offer_identity, first_offer_revision = _first_offer_status_metadata(
        first_offer_status
    )
    if (
        first_offer_identity is not None
        and first_offer_identity["generation"] != expected_generation
    ):
        raise ValueError("first-offer status belongs to a different generation")
    forth = client.request("forth", names=[GUEST_PHASE_PROFILE_WORD])
    if not isinstance(forth, dict) or not isinstance(forth.get("words"), dict):
        raise ValueError("phase profile Forth lookup returned no word map")
    word = forth["words"].get(GUEST_PHASE_PROFILE_WORD)
    if not isinstance(word, dict):
        raise ValueError(
            f"phase profile word {GUEST_PHASE_PROFILE_WORD} is unavailable"
        )
    if word.get("name") != GUEST_PHASE_PROFILE_WORD:
        raise ValueError("phase profile lookup did not return the exact word")
    address = _phase_profile_integer(
        word.get("data_address"),
        "phase profile data address",
        maximum=GUEST_PHASE_EVENT_MAX,
    )
    resolved_event = _phase_profile_integer(
        word.get("value"),
        "phase profile resolved event",
        maximum=GUEST_PHASE_EVENT_MAX,
    )
    resolved_sequence = resolved_event >> 8
    resolved_phase = resolved_event & 0xFF
    if resolved_phase not in GUEST_PHASE_NAMES:
        raise ValueError("phase profile resolved event contains an unknown phase")

    observer_started = False
    try:
        observer = client.request(
            "start_phase_profile",
            generation=expected_generation,
            address=address,
            max_events=capacity,
        )
        observer_started = True
        if not isinstance(observer, dict) or observer.get("status") != "active":
            raise ValueError("phase observer did not enter active state")
        if observer.get("schema") != GUEST_PHASE_PROFILE_SCHEMA:
            raise ValueError("phase observer returned an unknown schema")
        if observer.get("schema_version") != GUEST_PHASE_PROFILE_SCHEMA_VERSION:
            raise ValueError("phase observer returned an unknown schema version")
        if observer.get("encoding") != GUEST_PHASE_PROFILE_ENCODING:
            raise ValueError("phase observer returned an unknown event encoding")
        if _phase_profile_integer(
            observer.get("address"),
            "phase observer address",
        ) != address:
            raise ValueError("phase observer sampled a different address")
        if _phase_profile_integer(
            observer.get("machine_generation"),
            "phase observer generation",
        ) != expected_generation:
            raise ValueError("phase observer crossed a machine generation")
        if _phase_profile_integer(
            observer.get("max_events"),
            "phase observer max_events",
            minimum=1,
            maximum=GUEST_PHASE_PROFILE_MAX_EVENTS,
        ) != capacity:
            raise ValueError("phase observer used a different event capacity")
        started_steps = _phase_profile_integer(
            observer.get("started_steps"),
            "phase observer start steps",
        )
        started_batches = _phase_profile_integer(
            observer.get("started_batches"),
            "phase observer start batches",
        )
        if first_offer_identity is not None and (
            started_steps < first_offer_identity["steps"]
            or started_batches < first_offer_identity["batches"]
        ):
            raise ValueError("phase observer attachment precedes first-offer status")
        initial = _phase_profile_event(
            observer.get("initial"),
            "phase observer initial event",
        )
        if initial["sequence"] < resolved_sequence:
            raise ValueError("phase event sequence regressed during attachment")
        if (
            initial["sequence"] == resolved_sequence
            and initial["event"] != resolved_event
        ):
            raise ValueError("phase event changed without advancing its sequence")
    except Exception:
        if observer_started:
            try:
                client.request("stop_phase_profile")
            except Exception:
                pass
        raise

    return {
        "requested": True,
        "available": True,
        "word": GUEST_PHASE_PROFILE_WORD,
        "resolved_word": {
            "name": word["name"],
            "data_address": address,
            "event": resolved_event,
        },
        "expected_machine_generation": expected_generation,
        "first_offer_status_identity": first_offer_identity,
        "first_offer_status_revision": first_offer_revision,
        "observer_attach_lag_steps": (
            None
            if first_offer_identity is None
            else started_steps - first_offer_identity["steps"]
        ),
        "observer_attach_lag_batches": (
            None
            if first_offer_identity is None
            else started_batches - first_offer_identity["batches"]
        ),
        "observer_start": observer,
    }


def _validate_phase_profile_start_identity(
    observer: dict,
    observer_start: dict | None,
) -> None:
    if observer_start is None:
        return
    if not isinstance(observer_start, dict):
        raise ValueError("phase observer start snapshot must be an object")
    if observer_start.get("status") != "active":
        raise ValueError("phase observer start snapshot was not active")
    for field in (
        "schema",
        "schema_version",
        "machine_generation",
        "address",
        "encoding",
        "batch_step_bound",
        "max_events",
        "started_steps",
        "started_batches",
    ):
        if observer_start.get(field) != observer.get(field):
            raise ValueError(
                f"phase observer changed its {field} measurement identity"
            )
    if observer_start.get("initial") != observer.get("initial"):
        raise ValueError("phase observer changed its initial event identity")


def _guest_phase_summary(
    observer: dict,
    *,
    expected_generation: int,
    window_end_steps: int,
    observer_start: dict | None = None,
) -> dict[str, object]:
    """Derive honest residency bounds from batch-bounded phase transitions."""

    if not isinstance(observer, dict):
        raise ValueError("phase observer snapshot must be an object")
    if observer.get("schema") != GUEST_PHASE_PROFILE_SCHEMA:
        raise ValueError("phase observer snapshot has an unknown schema")
    if observer.get("schema_version") != GUEST_PHASE_PROFILE_SCHEMA_VERSION:
        raise ValueError("phase observer snapshot has an unknown schema version")
    if observer.get("encoding") != GUEST_PHASE_PROFILE_ENCODING:
        raise ValueError("phase observer snapshot has an unknown event encoding")
    _validate_phase_profile_start_identity(observer, observer_start)
    generation = _phase_profile_integer(
        observer.get("machine_generation"),
        "phase observer generation",
    )
    expected = _phase_profile_integer(
        expected_generation,
        "expected phase observer generation",
    )
    if generation != expected:
        raise ValueError("phase observer crossed the expected machine generation")
    address = _phase_profile_integer(
        observer.get("address"),
        "phase observer address",
        maximum=GUEST_PHASE_EVENT_MAX,
    )
    batch_step_bound = _phase_profile_integer(
        observer.get("batch_step_bound"),
        "phase observer batch step bound",
        minimum=1,
    )
    max_events = _phase_profile_integer(
        observer.get("max_events"),
        "phase observer max_events",
        minimum=1,
        maximum=GUEST_PHASE_PROFILE_MAX_EVENTS,
    )
    start_steps = _phase_profile_integer(
        observer.get("started_steps"),
        "phase observer start steps",
    )
    start_batches = _phase_profile_integer(
        observer.get("started_batches"),
        "phase observer start batches",
    )
    end_steps = _phase_profile_integer(
        window_end_steps,
        "phase observer window end steps",
    )
    if end_steps < start_steps:
        raise ValueError("phase observer window ends before it starts")
    current_steps = _phase_profile_integer(
        observer.get("current_steps"),
        "phase observer current steps",
    )
    current_batches = _phase_profile_integer(
        observer.get("current_batches"),
        "phase observer current batches",
    )
    last_sample_steps = _phase_profile_integer(
        observer.get("last_sample_steps"),
        "phase observer last sample steps",
    )
    last_sample_batches = _phase_profile_integer(
        observer.get("last_sample_batches"),
        "phase observer last sample batches",
    )
    if not (
        start_steps <= last_sample_steps <= current_steps
        and start_batches <= last_sample_batches <= current_batches
    ):
        raise ValueError("phase observer sample identity is not monotonic")
    if end_steps > current_steps:
        raise ValueError("phase observer window extends beyond its snapshot")
    stopped_steps_value = observer.get("stopped_steps")
    stopped_steps = (
        None
        if stopped_steps_value is None
        else _phase_profile_integer(
            stopped_steps_value,
            "phase observer stopped steps",
        )
    )
    stopped_batches_value = observer.get("stopped_batches")
    stopped_batches = (
        None
        if stopped_batches_value is None
        else _phase_profile_integer(
            stopped_batches_value,
            "phase observer stopped batches",
        )
    )
    if stopped_steps is not None and not start_steps <= stopped_steps <= current_steps:
        raise ValueError("phase observer stopped steps are outside its lifetime")
    if (
        stopped_batches is not None
        and not start_batches <= stopped_batches <= current_batches
    ):
        raise ValueError("phase observer stopped batches are outside its lifetime")
    status = observer.get("status")
    if status not in {"active", "stopped", "read_error", "invalid_event"}:
        raise ValueError("phase observer snapshot has an unknown status")
    if status != "active" and (stopped_steps is None or stopped_batches is None):
        raise ValueError("finished phase observer has no stop identity")
    if status == "stopped" and (
        stopped_steps != current_steps or stopped_batches != current_batches
    ):
        raise ValueError("stopped phase observer snapshot is not its stop identity")
    observer_error = observer.get("error")
    if observer_error is not None and not isinstance(observer_error, dict):
        raise ValueError("phase observer error must be an object or null")

    initial = _phase_profile_event(
        observer.get("initial"),
        "phase observer initial event",
    )
    last = _phase_profile_event(
        observer.get("last"),
        "phase observer last event",
    )
    current_phase = initial["phase"]
    last_sequence = initial["sequence"]
    last_event = initial["event"]

    sample_attempts = _phase_profile_integer(
        observer.get("sample_attempts"),
        "phase observer sample attempts",
        minimum=1,
    )
    successful_samples = _phase_profile_integer(
        observer.get("successful_samples"),
        "phase observer successful samples",
        minimum=1,
    )
    if successful_samples > sample_attempts:
        raise ValueError("phase observer has more successful samples than attempts")
    observed_transitions = _phase_profile_integer(
        observer.get("observed_transitions"),
        "phase observer observed transitions",
    )
    observer_coalesced = _phase_profile_integer(
        observer.get("coalesced_transitions"),
        "phase observer coalesced transitions",
    )
    dropped_records = _phase_profile_integer(
        observer.get("dropped_records"),
        "phase observer dropped records",
    )
    dropped_transitions = _phase_profile_integer(
        observer.get("dropped_transitions"),
        "phase observer dropped transitions",
    )
    if dropped_transitions < dropped_records:
        raise ValueError("phase observer dropped-transition counts are inconsistent")

    transitions = observer.get("transitions")
    if not isinstance(transitions, list):
        raise ValueError("phase observer transitions must be an array")
    if len(transitions) > max_events:
        raise ValueError("phase observer retained more records than its capacity")
    normalized_transitions: list[dict[str, object]] = []
    retained_transitions = 0
    retained_coalesced = 0
    previous_upper = start_steps
    previous_sample_index = -1
    previous_batch_index: int | None = None
    previous_phase = current_phase

    for index, transition in enumerate(transitions):
        if not isinstance(transition, dict):
            raise ValueError(f"phase transition {index} must be an object")
        transition_generation = _phase_profile_integer(
            transition.get("machine_generation"),
            f"phase transition {index} generation",
        )
        if transition_generation != generation:
            raise ValueError("phase transition crossed a machine generation")
        sample_index = _phase_profile_integer(
            transition.get("sample_index"),
            f"phase transition {index} sample index",
            minimum=1,
        )
        if sample_index <= previous_sample_index:
            raise ValueError("phase transition sample indexes are not monotonic")
        if sample_index >= successful_samples:
            raise ValueError("phase transition sample index was never sampled")
        source = transition.get("source")
        if not isinstance(source, str) or not source:
            raise ValueError(f"phase transition {index} source must be text")
        batch_index_value = transition.get("batch_index")
        batch_index = (
            None
            if batch_index_value is None
            else _phase_profile_integer(
                batch_index_value,
                f"phase transition {index} batch index",
            )
        )
        if (
            batch_index is not None
            and previous_batch_index is not None
            and batch_index <= previous_batch_index
        ):
            raise ValueError("phase transition batch indexes are not monotonic")
        lower = _phase_profile_integer(
            transition.get("step_lower_bound"),
            f"phase transition {index} lower bound",
        )
        upper = _phase_profile_integer(
            transition.get("step_upper_bound"),
            f"phase transition {index} upper bound",
        )
        if upper < lower:
            raise ValueError("phase transition has reversed step bounds")
        if lower < start_steps:
            raise ValueError("phase transition precedes observer attachment")
        if lower < previous_upper:
            raise ValueError("phase transition step intervals overlap or regress")
        if upper > current_steps:
            raise ValueError("phase transition extends beyond the observer snapshot")
        if upper - lower > batch_step_bound:
            raise ValueError("phase transition exceeds the configured batch bound")

        previous = _phase_profile_event(
            {
                "event": transition.get("previous_event"),
                "sequence": transition.get("previous_sequence"),
                "phase": transition.get("previous_phase"),
            },
            f"phase transition {index} previous event",
        )
        event = _phase_profile_event(
            {
                "event": transition.get("event"),
                "sequence": transition.get("sequence"),
                "phase": transition.get("phase"),
            },
            f"phase transition {index} event",
        )
        if (
            previous["event"] != last_event
            or previous["sequence"] != last_sequence
            or previous["phase"] != previous_phase
        ):
            raise ValueError("phase transition event chain is not contiguous")
        coalesced = _phase_profile_integer(
            transition.get("coalesced_transitions"),
            f"phase transition {index} coalesced count",
        )
        sequence_delta = event["sequence"] - previous["sequence"]
        if sequence_delta <= 0 or coalesced != sequence_delta - 1:
            raise ValueError("phase transition sequence delta is inconsistent")
        retained_transitions += sequence_delta
        retained_coalesced += coalesced
        normalized_transitions.append(
            {
                "index": index,
                "sample_index": sample_index,
                "source": source,
                "batch_index": batch_index,
                "step_lower_bound": lower,
                "step_upper_bound": upper,
                "previous_event": previous["event"],
                "previous_sequence": previous["sequence"],
                "previous_phase": previous["phase"],
                "event": event["event"],
                "sequence": event["sequence"],
                "phase": event["phase"],
                "coalesced_transitions": coalesced,
            }
        )
        previous_upper = upper
        previous_sample_index = sample_index
        if batch_index is not None:
            previous_batch_index = batch_index
        last_event = event["event"]
        last_sequence = event["sequence"]
        previous_phase = event["phase"]

    if observed_transitions != retained_transitions + dropped_transitions:
        raise ValueError("phase observer observed-transition count is inconsistent")
    if observer_coalesced != (
        retained_coalesced + dropped_transitions - dropped_records
    ):
        raise ValueError("phase observer coalesced-transition count is inconsistent")
    if last["sequence"] - initial["sequence"] != observed_transitions:
        raise ValueError("phase observer last sequence disagrees with its counters")
    if dropped_records == 0 and last != {
        "event": last_event,
        "sequence": last_sequence,
        "phase": previous_phase,
    }:
        raise ValueError("phase observer last event disagrees with its records")

    per_phase = {
        phase: {
            "id": phase,
            "name": name,
            "visits": 0,
            "retired_steps_lower_bound": 0,
            "retired_steps_upper_bound": 0,
            "coalesced_boundary_visits": 0,
            "possible_visits": 0,
        }
        for phase, name in GUEST_PHASE_NAMES.items()
        if phase != 0
    }
    residencies: list[dict[str, object]] = []
    open_boundary: tuple[int, int, int] | None = (
        (start_steps, start_steps, 0) if initial["phase"] != 0 else None
    )
    initial_residency_open = initial["phase"] != 0
    current_phase = initial["phase"]
    window_coalesced = 0
    straddling_transition: dict[str, object] | None = None

    def close_residency(
        phase: int,
        end_lower: int,
        end_upper: int,
        end_coalesced: int,
        *,
        kind: str,
        possible: bool = False,
    ) -> None:
        if open_boundary is None:
            raise ValueError("phase residency has no opening boundary")
        start_lower, start_upper, start_coalesced = open_boundary
        lower_bound = max(0, end_lower - start_upper)
        upper_bound = max(0, end_upper - start_lower)
        residency = {
            "phase": phase,
            "name": GUEST_PHASE_NAMES[phase],
            "kind": kind,
            "start_step_lower_bound": start_lower,
            "start_step_upper_bound": start_upper,
            "end_step_lower_bound": end_lower,
            "end_step_upper_bound": end_upper,
            "retired_steps_lower_bound": lower_bound,
            "retired_steps_upper_bound": upper_bound,
            "start_coalesced_transitions": start_coalesced,
            "end_coalesced_transitions": end_coalesced,
        }
        residencies.append(residency)
        totals = per_phase[phase]
        totals["possible_visits" if possible else "visits"] += 1
        totals["retired_steps_lower_bound"] += lower_bound
        totals["retired_steps_upper_bound"] += upper_bound
        if start_coalesced or end_coalesced:
            totals["coalesced_boundary_visits"] += 1

    for transition in normalized_transitions:
        lower = int(transition["step_lower_bound"])
        upper = int(transition["step_upper_bound"])
        if lower >= end_steps:
            break
        if upper > end_steps:
            straddling_transition = dict(transition)
            if current_phase != 0:
                close_residency(
                    current_phase,
                    lower,
                    end_steps,
                    int(transition["coalesced_transitions"]),
                    kind="window-end-ambiguous",
                )
            possible_phase = int(transition["phase"])
            if possible_phase != 0:
                saved_boundary = open_boundary
                open_boundary = (
                    lower,
                    end_steps,
                    int(transition["coalesced_transitions"]),
                )
                close_residency(
                    possible_phase,
                    end_steps,
                    end_steps,
                    0,
                    kind="window-end-possible",
                    possible=True,
                )
                open_boundary = saved_boundary
            break
        if int(transition["previous_phase"]) != current_phase:
            raise ValueError("phase transition is not contiguous in the window")
        if current_phase != 0:
            close_residency(
                current_phase,
                lower,
                upper,
                int(transition["coalesced_transitions"]),
                kind=(
                    "initial-window-open"
                    if initial_residency_open
                    else "closed"
                ),
            )
            initial_residency_open = False
        current_phase = int(transition["phase"])
        window_coalesced += int(transition["coalesced_transitions"])
        open_boundary = (
            (
                lower,
                upper,
                int(transition["coalesced_transitions"]),
            )
            if current_phase != 0
            else None
        )

    window_end_state_known = straddling_transition is None
    incomplete_open_phase = None
    if window_end_state_known and current_phase != 0:
        close_residency(
            current_phase,
            end_steps,
            end_steps,
            0,
            kind="terminal-open",
        )
        incomplete_open_phase = current_phase
    observed_lower = sum(
        int(item["retired_steps_lower_bound"])
        for item in per_phase.values()
    )
    observed_upper = sum(
        int(item["retired_steps_upper_bound"])
        for item in per_phase.values()
    )
    window_steps = end_steps - start_steps
    lifecycle_complete = (
        status == "stopped"
        and observer.get("error") is None
        and dropped_records == 0
        and dropped_transitions == 0
        and stopped_steps is not None
        and stopped_steps >= end_steps
        and last_sample_steps >= end_steps
        and window_end_state_known
        and incomplete_open_phase is None
        and current_phase == 0
    )
    attribution_complete = lifecycle_complete and window_coalesced == 0
    other_lower = max(0, window_steps - observed_upper)
    other_upper = max(0, window_steps - observed_lower)
    phases = {
        "0": {
            "id": 0,
            "name": "other_or_unattributed",
            "visits": None,
            "retired_steps_lower_bound": other_lower,
            "retired_steps_upper_bound": other_upper,
            "kind": "other-or-unattributed-complement",
        }
    }
    phases.update({str(phase): totals for phase, totals in per_phase.items()})
    return {
        "measurement_window": {
            "start_steps": start_steps,
            "end_steps": end_steps,
            "retired_steps": window_steps,
            "boundary": (
                "half-open first-offer observer start through final-offer "
                "pre-screen status"
            ),
        },
        "observer_identity": {
            "machine_generation": generation,
            "address": address,
            "batch_step_bound": batch_step_bound,
            "max_events": max_events,
            "started_batches": start_batches,
            "stopped_steps": stopped_steps,
            "stopped_batches": stopped_batches,
        },
        "observer_status": status,
        "observer_error": observer.get("error"),
        "lifecycle_complete": lifecycle_complete,
        "attribution_complete": attribution_complete,
        "window_end_state_known": window_end_state_known,
        "window_end_phase": current_phase if window_end_state_known else None,
        "initial_phase": initial["phase"],
        "initial_residency_truncated": initial["phase"] != 0,
        "observer_coalesced_transitions": observer_coalesced,
        "window_coalesced_transitions": window_coalesced,
        "observed_transitions": observed_transitions,
        "dropped_records": dropped_records,
        "dropped_transitions": dropped_transitions,
        "incomplete_open_phase": incomplete_open_phase,
        "straddling_transition": straddling_transition,
        "phases": phases,
        "residencies": residencies,
    }


def _finish_guest_phase_profile(
    client: SessionClient,
    capture: dict[str, object],
    *,
    window_end_steps: int,
) -> dict[str, object]:
    """Stop observation without making diagnostic failure normative."""

    result = dict(capture)
    result["phase_names"] = {
        str(phase): name for phase, name in GUEST_PHASE_NAMES.items()
    }
    try:
        observer = client.request("stop_phase_profile")
    except Exception as exc:
        result["observer"] = None
        result["phase_summary"] = None
        result["summary_available"] = False
        result["profile_error"] = _phase_profile_error("stop", exc)
        return result

    result["observer"] = observer
    try:
        result["phase_summary"] = _guest_phase_summary(
            observer,
            expected_generation=_phase_profile_integer(
                result.get("expected_machine_generation"),
                "expected phase observer generation",
            ),
            window_end_steps=window_end_steps,
            observer_start=result.get("observer_start"),
        )
    except Exception as exc:
        result["phase_summary"] = None
        result["summary_available"] = False
        result["profile_error"] = _phase_profile_error("summarize", exc)
        return result
    result["summary_available"] = True
    result["profile_error"] = None
    return result


class _PerformanceTrace:
    """Small, non-normative monotonic trace for one physical journey."""

    def __init__(
        self,
        artifact_root: Path,
        *,
        clock_ns: Callable[[], int] = time.monotonic_ns,
    ):
        self.path = Path(artifact_root).resolve() / PERFORMANCE_TRACE_FILENAME
        self._clock_ns = clock_ns
        self.origin_ns = clock_ns()
        self.events: list[dict[str, object]] = []
        self.guest_phase_profile: dict[str, object] | None = None

    def now(self) -> int:
        return self._clock_ns()

    def mark(
        self,
        event: str,
        *,
        status=None,
        started_ns: int | None = None,
        **detail,
    ) -> None:
        try:
            now_ns = self.now()
            item: dict[str, object] = {
                "sequence": len(self.events),
                "event": event,
                "elapsed_ns": max(now_ns - self.origin_ns, 0),
            }
            if started_ns is not None:
                item["duration_ns"] = max(now_ns - started_ns, 0)
            counters = _performance_status_snapshot(status)
            if counters is not None:
                item["counters"] = counters
            item.update(detail)
            self.events.append(item)
        except Exception:
            pass

    def set_guest_phase_profile(self, profile) -> None:
        """Attach optional guest evidence without turning it into a gate."""

        try:
            if profile is not None and not isinstance(profile, dict):
                raise TypeError("guest phase profile must be an object or null")
            self.guest_phase_profile = (
                None if profile is None else dict(profile)
            )
        except Exception as exc:
            self.guest_phase_profile = {
                "available": False,
                "profile_error": _phase_profile_error("trace-attach", exc),
            }

    def write(self, outcome: str) -> Path | None:
        """Atomically write diagnostics without becoming an acceptance gate."""

        temporary = self.path.with_name(f".{self.path.name}.{os.getpid()}.tmp")
        try:
            payload = {
                "schema": PERFORMANCE_TRACE_SCHEMA,
                "normative": False,
                "clock": "time.monotonic_ns",
                "origin_ns": self.origin_ns,
                "outcome": outcome,
                "guest_phase_profile": self.guest_phase_profile,
                "events": self.events,
            }
            temporary.write_text(
                json.dumps(payload, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
            temporary.replace(self.path)
            return self.path
        except Exception as exc:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
            print(f"Performance trace unavailable: {exc}")
            return None


def _trace_control_identity(
    identity: ControlIdentity | None,
) -> dict[str, int] | None:
    if identity is None:
        return None
    return {
        "owner_id": identity.owner_id,
        "owner_generation": identity.owner_generation,
        "control_id": identity.control_id,
    }


class _ManualInputTraceClient:
    """Observe reference-viewer input RPCs without changing their results."""

    def __init__(self, client, trace: _PerformanceTrace):
        self.client = client
        self.trace = trace
        self.request_count = 0

    def request(self, method: str, **params):
        started_ns = self.trace.now()
        self.request_count += 1
        detail: dict[str, object] = {
            "method": method,
            "generation": params.get("generation"),
            "authorizing_offer_id": params.get("display_offer_id"),
            "display_scope": params.get("display_scope"),
        }
        if method == "send_control_event":
            detail["semantic_target"] = {
                "owner_id": params.get("owner_id"),
                "owner_generation": params.get("owner_generation"),
                "control_id": params.get("control_id"),
            }
            detail["modifiers"] = params.get("modifiers")
        elif method == "send_key":
            detail["key"] = params.get("key")
        elif method == "send_text":
            text_value = params.get("text")
            detail["text_utf8_bytes"] = (
                len(text_value.encode("utf-8"))
                if isinstance(text_value, str)
                else None
            )
        try:
            result = self.client.request(method, **params)
        except Exception as exc:
            self.trace.mark(
                "manual_input_rpc",
                started_ns=started_ns,
                result="exception",
                exception_type=type(exc).__name__,
                **detail,
            )
            raise
        self.trace.mark(
            "manual_input_rpc",
            started_ns=started_ns,
            result=(result.get("status") if isinstance(result, dict) else None),
            **detail,
        )
        return result


def _require_no_manual_scripted_input(
    client: _ManualInputTraceClient,
) -> None:
    """Fail closed if a live viewer input could influence scripted evidence."""

    if not isinstance(client, _ManualInputTraceClient):
        raise TypeError("client must be _ManualInputTraceClient")
    if client.request_count:
        raise PhysicalDesktopAcceptanceError(
            "scripted physical acceptance received manual viewer input: "
            f"rpc-count={client.request_count}"
        )


def _trace_pending_input_drop(
    trace: _PerformanceTrace,
    keyboard: _GuestKeyboardForwarder,
    pending_before: int,
    *,
    reason: str,
    **detail,
) -> None:
    pending_after = keyboard.pending_events
    if pending_after >= pending_before:
        return
    trace.mark(
        "manual_input_dropped",
        reason=reason,
        dropped_events=pending_before - pending_after,
        pending_before=pending_before,
        pending_after=pending_after,
        **detail,
    )


def _semantic_text_content_state(
    content: SemanticTextContent,
) -> tuple[object, ...]:
    """Return the complete STX1 value without retained ControlIdentity."""

    if not isinstance(content, SemanticTextContent):
        raise TypeError("content must be SemanticTextContent")
    return (
        content.rows,
        content.columns,
        content.viewport_row,
        content.viewport_column,
        content.viewport_rows,
        content.viewport_columns,
        int(content.flags),
        content.primary_key,
        content.primary_offset,
        content.anchor_key,
        content.anchor_offset,
        tuple(
            (
                item.item_key,
                item.row,
                item.column,
                item.row_span,
                item.column_span,
                int(item.role),
                int(item.state),
                item.text,
            )
            for item in content.items
        ),
    )


@dataclass(frozen=True)
class _SemanticCollectionClaim:
    """One real retained collection root in logical-screen coordinates."""

    kind: ControlKind
    identity: ControlIdentity
    left: int
    top: int
    right: int
    bottom: int
    visible_text: tuple[str, ...] = ()
    content_revision: int = 1
    primary_key: int = 0
    current_item_keys: tuple[int, ...] = ()
    content_state: tuple[object, ...] = ()
    state: ControlState = ControlState.VISIBLE | ControlState.ENABLED

    @property
    def control_id(self) -> int:
        return self.identity.control_id


_SemanticBounds = tuple[int, int, int, int]


@dataclass(frozen=True)
class _CollectionState:
    """Authored collection state without retained-wire ControlIdentity."""

    content_revision: int
    primary_key: int
    current_item_keys: tuple[int, ...]
    bounds: _SemanticBounds
    content_state: tuple[object, ...]


_CollectionStates = tuple[_CollectionState, ...]
_TabSignature = tuple[int, str, str]


@dataclass(frozen=True)
class _TabSetState:
    """Pad tab state without retained-wire ControlIdentity."""

    bounds: _SemanticBounds
    tabs: tuple[_TabSignature, ...]
    selected: _TabSignature


@dataclass(frozen=True)
class _SemanticTabClaim:
    """One visible TAB child copied out of a retained TABSET draw."""

    identity: ControlIdentity
    state: ControlState
    order: int
    label: str
    shortcut: str

    @property
    def control_id(self) -> int:
        return self.identity.control_id


@dataclass(frozen=True)
class _SemanticTabSetClaim:
    """One retained TABSET root in logical-screen coordinates."""

    identity: ControlIdentity
    state: ControlState
    left: int
    top: int
    right: int
    bottom: int
    tabs: tuple[_SemanticTabClaim, ...]

    @property
    def control_id(self) -> int:
        return self.identity.control_id

    @property
    def selected_tabs(self) -> tuple[_SemanticTabClaim, ...]:
        return tuple(
            tab for tab in self.tabs if tab.state & ControlState.SELECTED
        )


@dataclass(frozen=True)
class _LogicalRectangle:
    """One exact selected-surface cell rectangle with exclusive endpoints."""

    left: int
    top: int
    right: int
    bottom: int

    @property
    def cell_count(self) -> int:
        return (self.right - self.left) * (self.bottom - self.top)


@dataclass(frozen=True)
class _InstrumentClaim:
    """One retained instrument rectangle intersecting the selected surface."""

    kind: str
    owner_id: int
    owner_generation: int
    object_id: int
    left: int
    top: int
    right: int
    bottom: int


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
    semantic_collection_claims: tuple[_SemanticCollectionClaim, ...] = ()
    semantic_tabset_claims: tuple[_SemanticTabSetClaim, ...] = ()
    region_count: int = 0
    instrument_region_count: int = 0
    clipped_region_count: int = 0
    instrument_cell_count: int = 0
    instrument_claims: tuple[_InstrumentClaim, ...] = ()

    @property
    def text_area_count(self) -> int:
        return sum(
            claim.kind is ControlKind.TEXT_AREA
            for claim in self.semantic_collection_claims
        )

    @property
    def text_grid_count(self) -> int:
        return sum(
            claim.kind is ControlKind.TEXT_GRID
            for claim in self.semantic_collection_claims
        )

    @property
    def tabset_count(self) -> int:
        return len(self.semantic_tabset_claims)

    @property
    def readout_count(self) -> int:
        return sum(claim.kind == "READOUT" for claim in self.instrument_claims)

    @property
    def meter_count(self) -> int:
        return sum(claim.kind == "METER" for claim in self.instrument_claims)

    @property
    def status_count(self) -> int:
        return sum(claim.kind == "STATUS" for claim in self.instrument_claims)

    @property
    def collection_claim_identities(
        self,
    ) -> tuple[tuple[ControlKind, ControlIdentity], ...]:
        return tuple(
            (claim.kind, claim.identity)
            for claim in self.semantic_collection_claims
        )

    @property
    def tab_identity_graphs(
        self,
    ) -> tuple[tuple[ControlIdentity, tuple[ControlIdentity, ...]], ...]:
        return tuple(
            (claim.identity, tuple(tab.identity for tab in claim.tabs))
            for claim in self.semantic_tabset_claims
        )

    @property
    def tab_signatures(self) -> tuple[tuple[str, ...], ...]:
        return tuple(
            tuple(tab.label for tab in claim.tabs)
            for claim in self.semantic_tabset_claims
        )

    @property
    def selected_tab_labels(self) -> tuple[tuple[str, ...], ...]:
        return tuple(
            tuple(tab.label for tab in claim.selected_tabs)
            for claim in self.semantic_tabset_claims
        )

    @property
    def selected_tab_identities(
        self,
    ) -> tuple[tuple[ControlIdentity, ...], ...]:
        return tuple(
            tuple(tab.identity for tab in claim.selected_tabs)
            for claim in self.semantic_tabset_claims
        )

    @property
    def text(self) -> str:
        collection_lines = tuple(
            line
            for claim in self.semantic_collection_claims
            for line in claim.visible_text
            if line
        )
        tab_lines = tuple(
            " ".join(
                (
                    f"[{tab.label}]"
                    if tab.state & ControlState.SELECTED
                    else tab.label
                )
                + (f" ({tab.shortcut})" if tab.shortcut else "")
                for tab in claim.tabs
            )
            for claim in self.semantic_tabset_claims
            if claim.tabs
        )
        return "\n".join(
            self.lines
            + self.semantic_lines
            + collection_lines
            + tab_lines
        )


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
    text_area_count: int
    text_grid_count: int
    tabset_count: int
    collection_claim_identities: tuple[
        tuple[ControlKind, ControlIdentity], ...
    ]
    tab_identity_graphs: tuple[
        tuple[ControlIdentity, tuple[ControlIdentity, ...]], ...
    ]
    selected_tab_identities: tuple[tuple[ControlIdentity, ...], ...]
    png_path: Path
    retained_png_path: Path
    retained_text_path: Path
    menu_signatures: tuple[tuple[str, ...], ...] = ()
    tab_signatures: tuple[tuple[str, ...], ...] = ()
    selected_tab_labels: tuple[tuple[str, ...], ...] = ()
    renderer_owned_gap_cells: int = 0
    region_count: int = 0
    instrument_region_count: int = 0
    clipped_region_count: int = 0
    instrument_cell_count: int = 0
    readout_count: int = 0
    meter_count: int = 0
    status_count: int = 0

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
            "region_count": self.region_count,
            "instrument_region_count": self.instrument_region_count,
            "clipped_region_count": self.clipped_region_count,
            "instrument_cell_count": self.instrument_cell_count,
            "readout_count": self.readout_count,
            "meter_count": self.meter_count,
            "status_count": self.status_count,
            "text_area_count": self.text_area_count,
            "text_grid_count": self.text_grid_count,
            "tabset_count": self.tabset_count,
            "collection_claim_identities": [
                {
                    "kind": kind.name,
                    "owner_id": identity.owner_id,
                    "owner_generation": identity.owner_generation,
                    "control_id": identity.control_id,
                }
                for kind, identity in self.collection_claim_identities
            ],
            "tab_identity_graphs": [
                {
                    "tabset": {
                        "owner_id": root.owner_id,
                        "owner_generation": root.owner_generation,
                        "control_id": root.control_id,
                    },
                    "tabs": [
                        {
                            "owner_id": identity.owner_id,
                            "owner_generation": identity.owner_generation,
                            "control_id": identity.control_id,
                        }
                        for identity in tabs
                    ],
                }
                for root, tabs in self.tab_identity_graphs
            ],
            "tab_signatures": [
                list(signature) for signature in self.tab_signatures
            ],
            "selected_tab_labels": [
                list(labels) for labels in self.selected_tab_labels
            ],
            "selected_tab_identities": [
                [
                    {
                        "owner_id": identity.owner_id,
                        "owner_generation": identity.owner_generation,
                        "control_id": identity.control_id,
                    }
                    for identity in identities
                ]
                for identities in self.selected_tab_identities
            ],
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
class CellFallbackFrameEvidence:
    """One exact offer's independently checked CELL fallback snapshot."""

    boundary: str
    offer_id: int
    generation: int
    scope: dict[str, object]
    ready_markers: tuple[str, ...]
    cell_text_sha256: str
    cell_utf8_bytes: int

    def to_dict(self) -> dict[str, object]:
        return {
            "boundary": self.boundary,
            "ready": True,
            "offer_id": self.offer_id,
            "generation": self.generation,
            "scope": self.scope,
            "ready_markers": list(self.ready_markers),
            "cell_text_sha256": self.cell_text_sha256,
            "cell_utf8_bytes": self.cell_utf8_bytes,
        }


@dataclass(frozen=True)
class PhysicalDesktopAcceptanceEvidence:
    manifest_path: Path
    video_driver: str
    frames: tuple[PresentedFrameEvidence, ...]
    inputs: tuple[AcceptedInputEvidence, ...]
    cell_fallback: tuple[CellFallbackFrameEvidence, ...]


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


def _require_cell_fallback_evidence(
    boundary: str,
    offer: TerminalDisplayOffer,
    generation: int,
    ready_markers: tuple[str, ...],
) -> CellFallbackFrameEvidence:
    """Bind mandatory CELL readiness to one exact acknowledged rich offer.

    This is independent fallback evidence.  It does not promote CELL text as
    proof of any retained draw or rich compositor result.
    """

    if boundary not in ("initial", "final"):
        raise ValueError("CELL fallback boundary must be initial or final")
    if not isinstance(offer, TerminalDisplayOffer):
        raise TypeError("offer must be TerminalDisplayOffer")
    # Read the immutable CELL plane carried by this exact offer.  The mutable
    # viewer model normally contains the same snapshot after staging, but it
    # may already be servicing a newer RPC by the time evidence is serialized.
    cell_text = offer.cell.text(trim_right=True)
    markers = tuple(ready_markers)
    ready, missing = _marker_status(cell_text, markers)
    if not ready:
        raise PhysicalDesktopAcceptanceError(
            f"mandatory CELL fallback is not {boundary}-ready for exact "
            f"offer {offer.offer_id}: missing={missing!r}"
        )
    encoded = cell_text.encode("utf-8")
    return CellFallbackFrameEvidence(
        boundary,
        offer.offer_id,
        generation,
        display_scope_to_wire(offer.scope),
        markers,
        hashlib.sha256(encoded).hexdigest(),
        len(encoded),
    )


def _desktop_tile_bounds(
    projection: RichScreenProjection,
    tile: int,
) -> tuple[int, int, int, int]:
    """Return one canonical Desk tile's logical half-open bounds."""

    if not isinstance(projection, RichScreenProjection):
        raise TypeError("projection must be RichScreenProjection")
    tile_count = DESKTOP_TILE_COLUMNS * DESKTOP_TILE_ROWS
    if (
        not isinstance(tile, int)
        or isinstance(tile, bool)
        or not 0 <= tile < tile_count
    ):
        raise ValueError("tile must select one canonical Desk tile")
    tile_col = tile % DESKTOP_TILE_COLUMNS
    tile_row = tile // DESKTOP_TILE_COLUMNS
    content_rows = max(1, projection.rows - 1)
    left = tile_col * projection.cols // DESKTOP_TILE_COLUMNS
    right = (tile_col + 1) * projection.cols // DESKTOP_TILE_COLUMNS
    top = tile_row * content_rows // DESKTOP_TILE_ROWS
    bottom = (tile_row + 1) * content_rows // DESKTOP_TILE_ROWS
    if right <= left:
        right = min(projection.cols, left + 1)
    if bottom <= top:
        bottom = min(projection.rows, top + 1)
    return left, top, right, bottom


def _residual_tile_contains(
    projection: RichScreenProjection,
    marker: str,
    tile: int,
) -> bool:
    """Find text supplied specifically by retained residual glyphs in a tile."""

    if not isinstance(marker, str) or not marker:
        raise ValueError("marker must be a nonempty string")
    left, top, right, bottom = _desktop_tile_bounds(projection, tile)
    return any(
        marker in line[left:right]
        for line in projection.lines[top:bottom]
    )


def _desktop_tile_contains(
    projection: RichScreenProjection,
    marker: str,
    tile: int,
) -> bool:
    """Find visible retained text inside one canonical Desk tile."""

    if _residual_tile_contains(projection, marker, tile):
        return True
    left, top, right, bottom = _desktop_tile_bounds(projection, tile)
    return any(
        left <= claim.left < claim.right <= right
        and top <= claim.top < claim.bottom <= bottom
        and claim.kind is ControlKind.TEXT_AREA
        and any(marker in line for line in claim.visible_text)
        for claim in projection.semantic_collection_claims
    )


def _daybook_date_is(
    projection: RichScreenProjection,
    expected: str,
) -> bool:
    """Require one exact acceptance date in Daybook's retained tile output."""

    if expected not in (DAYBOOK_INITIAL_DATE, DAYBOOK_NEXT_DATE):
        raise ValueError("expected must be one canonical acceptance date")
    other = (
        DAYBOOK_NEXT_DATE
        if expected == DAYBOOK_INITIAL_DATE
        else DAYBOOK_INITIAL_DATE
    )
    return _desktop_tile_contains(
        projection,
        expected,
        DAYBOOK_DESKTOP_TILE,
    ) and not _desktop_tile_contains(
        projection,
        other,
        DAYBOOK_DESKTOP_TILE,
    )


def _collection_claims_in_tile(
    projection: RichScreenProjection,
    kind: ControlKind,
    tile: int,
) -> tuple[_SemanticCollectionClaim, ...]:
    """Return generic semantic roots wholly owned by one Desk gate tile."""

    if kind not in (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID):
        raise ValueError("kind must be a semantic text collection")
    left, top, right, bottom = _desktop_tile_bounds(projection, tile)
    return tuple(
        claim
        for claim in projection.semantic_collection_claims
        if claim.kind is kind
        and left <= claim.left < claim.right <= right
        and top <= claim.top < claim.bottom <= bottom
    )


def _tabset_claims_in_tile(
    projection: RichScreenProjection,
    tile: int,
) -> tuple[_SemanticTabSetClaim, ...]:
    """Return retained TABSET roots wholly owned by one Desk gate tile."""

    left, top, right, bottom = _desktop_tile_bounds(projection, tile)
    return tuple(
        claim
        for claim in projection.semantic_tabset_claims
        if left <= claim.left < claim.right <= right
        and top <= claim.top < claim.bottom <= bottom
    )


def _tab_signature(tab: _SemanticTabClaim) -> _TabSignature:
    """Return authored tab state compared independently of retained IDs."""

    return tab.order, tab.label, tab.shortcut


def _tabset_state(tabset: _SemanticTabSetClaim) -> _TabSetState:
    """Return authored tab state without retained-wire graph identities."""

    selected_tabs = tabset.selected_tabs
    if len(selected_tabs) != 1:
        raise ValueError("tabset must contain exactly one selected tab")
    return _TabSetState(
        (tabset.left, tabset.top, tabset.right, tabset.bottom),
        tuple(_tab_signature(tab) for tab in tabset.tabs),
        _tab_signature(selected_tabs[0]),
    )


def _canonical_pad_tabset_claim(
    projection: RichScreenProjection,
) -> _SemanticTabSetClaim:
    """Require Pad's one ordinary, selected canonical TABSET graph."""

    claims = _tabset_claims_in_tile(projection, PAD_DESKTOP_TILE)
    if len(claims) != 1:
        raise PhysicalDesktopAcceptanceError(
            "canonical retained Desk frame does not contain exactly one "
            f"Pad TABSET in tile {PAD_DESKTOP_TILE}"
        )
    claim = claims[0]
    expected_root_state = ControlState.VISIBLE | ControlState.ENABLED
    if claim.state != expected_root_state:
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET root is not visibly enabled"
        )
    if not claim.tabs:
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET contains no visible tabs"
        )
    if tuple(tab.order for tab in claim.tabs) != tuple(range(len(claim.tabs))):
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET omits a visual tab ordinal"
        )
    expected_tab_state = ControlState.VISIBLE | ControlState.ENABLED
    if any(
        tab.state & expected_tab_state != expected_tab_state
        for tab in claim.tabs
    ):
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET contains a tab that is not visibly enabled"
        )
    if len(claim.selected_tabs) != 1:
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET does not contain exactly one selected tab"
        )
    return claim


def _collection_claims_containing(
    projection: RichScreenProjection,
    kind: ControlKind,
    tile: int,
    *markers: str,
) -> tuple[_SemanticCollectionClaim, ...]:
    """Return the exact generic collection roots carrying every marker."""

    if not markers or any(
        not isinstance(marker, str) or not marker for marker in markers
    ):
        raise ValueError("markers must contain nonempty strings")
    return tuple(
        claim
        for claim in _collection_claims_in_tile(projection, kind, tile)
        if _collection_is_available(claim)
        and all(
            any(marker in line for line in claim.visible_text)
            for marker in markers
        )
    )


def _collection_claims_advanced_containing(
    projection: RichScreenProjection,
    kind: ControlKind,
    tile: int,
    prior: _CollectionStates | None,
    *markers: str,
    require_position_change: bool,
) -> tuple[_SemanticCollectionClaim, ...]:
    """Return same-bounds app state that advanced across any wire rebuild."""

    if not prior:
        return ()
    if not markers or any(
        not isinstance(marker, str) or not marker for marker in markers
    ):
        raise ValueError("markers must contain nonempty strings")
    matches = []
    for claim in _collection_claims_in_tile(projection, kind, tile):
        if not _collection_is_available(claim):
            continue
        prior_matches = _prior_collection_states_for_claim(prior, claim)
        if len(prior_matches) != 1:
            continue
        previous = prior_matches[0]
        if claim.content_revision <= previous.content_revision:
            continue
        if require_position_change and (
            claim.primary_key,
            claim.current_item_keys,
        ) == (previous.primary_key, previous.current_item_keys):
            continue
        if all(
            any(marker in line for line in claim.visible_text)
            for marker in markers
        ):
            matches.append(claim)
    return tuple(matches)


_COLLECTION_REQUIRED_STATE = ControlState.VISIBLE | ControlState.ENABLED


def _collection_is_available(claim: _SemanticCollectionClaim) -> bool:
    return (
        claim.state & _COLLECTION_REQUIRED_STATE
        == _COLLECTION_REQUIRED_STATE
    )


def _collection_state(claim: _SemanticCollectionClaim) -> _CollectionState:
    return _CollectionState(
        claim.content_revision,
        claim.primary_key,
        claim.current_item_keys,
        (claim.left, claim.top, claim.right, claim.bottom),
        claim.content_state,
    )


def _prior_collection_states_for_claim(
    prior: _CollectionStates,
    claim: _SemanticCollectionClaim,
) -> tuple[_CollectionState, ...]:
    """Match one available root by authored geometry, never by wire ID."""

    bounds = (claim.left, claim.top, claim.right, claim.bottom)
    return tuple(
        state
        for state in prior
        if state.bounds == bounds
    )


def _collection_states_in_tile(
    projection: RichScreenProjection,
    kind: ControlKind,
    tile: int,
) -> _CollectionStates:
    """Copy live generic collection states for a later acknowledged frame."""

    return tuple(
        _collection_state(claim)
        for claim in _collection_claims_in_tile(projection, kind, tile)
        if _collection_is_available(claim)
    )


def _collection_state_advanced(
    projection: RichScreenProjection,
    kind: ControlKind,
    tile: int,
    prior: _CollectionStates | None,
    *,
    require_position_change: bool,
) -> bool:
    """Prove one semantic collection advanced after acknowledged input."""

    if not prior:
        return False
    for claim in _collection_claims_in_tile(projection, kind, tile):
        if not _collection_is_available(claim):
            continue
        prior_matches = _prior_collection_states_for_claim(prior, claim)
        if len(prior_matches) != 1:
            continue
        previous = prior_matches[0]
        if claim.content_revision <= previous.content_revision:
            continue
        if require_position_change and (
            claim.primary_key,
            claim.current_item_keys,
        ) == (previous.primary_key, previous.current_item_keys):
            continue
        return True
    return False


def _collection_claims_preserving_state(
    projection: RichScreenProjection,
    kind: ControlKind,
    tile: int,
    prior: _CollectionStates | None,
    *markers: str,
) -> tuple[_SemanticCollectionClaim, ...]:
    """Match accepted app state across a retained control-ID replacement.

    ControlIdentity is retained-wire identity within an owner generation.
    RET_REPLACE_START starts empty, so recreated controls receive fresh IDs
    above the owner's control-ID high-water mark.  Geometry, collection
    revisions, required availability, and the complete authored STX1 value
    come from the live widget snapshot, so they remain the continuity evidence
    while the surrounding session, presentation, and owner lineage is held
    separately by the journey.
    """

    if not prior:
        return ()
    if any(not isinstance(marker, str) or not marker for marker in markers):
        raise ValueError("markers must contain nonempty strings")
    matches = []
    for claim in _collection_claims_in_tile(projection, kind, tile):
        if not _collection_is_available(claim):
            continue
        prior_matches = _prior_collection_states_for_claim(prior, claim)
        if len(prior_matches) != 1:
            continue
        previous = prior_matches[0]
        if (
            claim.content_revision < previous.content_revision
            or claim.content_state != previous.content_state
        ):
            continue
        if all(
            any(marker in line for line in claim.visible_text)
            for marker in markers
        ):
            matches.append(claim)
    return tuple(matches)


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
            cells = _read_guest_cells(client, address=pointer, count=count)
        except (ConnectionError, OSError):
            raise
        except Exception as exc:
            records[record_name] = {
                "address": pointer,
                "unavailable": True,
                "error": f"{type(exc).__name__}: {exc}",
            }
            continue
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


def _read_guest_cells(
    client: SessionClient,
    *,
    address: int,
    count: int,
) -> list[int]:
    """Read one logical record across the session protocol's peek bound."""

    if address < 0 or count <= 0:
        raise ValueError("guest record requires a non-negative address and cells")
    cells: list[int] = []
    while len(cells) < count:
        chunk_address = address + len(cells) * GUEST_CELL_BYTES
        chunk_count = min(GUEST_PEEK_MAX_CELLS, count - len(cells))
        response = client.request(
            "peek",
            address=chunk_address,
            count=chunk_count,
        )
        if not isinstance(response, dict):
            raise RuntimeError("guest peek returned a non-object response")
        if response.get("address", chunk_address) != chunk_address:
            raise RuntimeError("guest peek returned cells from the wrong address")
        if response.get("cell_size", GUEST_CELL_BYTES) != GUEST_CELL_BYTES:
            raise RuntimeError("guest peek returned an unexpected cell size")
        values = response.get("values")
        if not isinstance(values, list) or len(values) != chunk_count:
            raise RuntimeError(
                "guest peek returned an incomplete cell chunk: "
                f"expected={chunk_count} actual="
                f"{len(values) if isinstance(values, list) else 'invalid'}"
            )
        try:
            chunk_cells = [int(value) for value in values]
        except (TypeError, ValueError) as exc:
            raise RuntimeError("guest peek returned a non-integer cell") from exc
        cells.extend(chunk_cells)
    return cells


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


def _visible_semantic_text(
    draw: TextAreaDraw | TextGridDraw,
) -> tuple[str, ...]:
    """Return only item text intersecting the authoritative viewport."""

    content = draw.content
    if isinstance(draw, TextGridDraw):
        # Grid text is clipped in physical pixels inside renderer-owned item
        # rectangles.  The logical viewport alone cannot prove which suffix
        # was physically drawable, so grid strings are never marker evidence.
        return ()
    viewport_top = content.viewport_row
    viewport_left = content.viewport_column
    viewport_bottom = viewport_top + content.viewport_rows
    viewport_right = viewport_left + content.viewport_columns
    visible: list[str] = []
    for item in content.items:
        item_bottom = item.row + item.row_span
        item_right = item.column + item.column_span
        if (
            item_bottom <= viewport_top
            or item.row >= viewport_bottom
            or item_right <= viewport_left
            or item.column >= viewport_right
        ):
            continue
        text = item.text
        if isinstance(draw, TextAreaDraw):
            first_scalar = max(viewport_left - item.column, 0)
            last_scalar = min(
                viewport_right - item.column,
                len(item.text),
            )
            text = item.text[first_scalar:last_scalar]
        if text:
            visible.append(text)
    return tuple(visible)


def _rectangle_intersection(
    first: _LogicalRectangle,
    second: _LogicalRectangle,
) -> _LogicalRectangle | None:
    left = max(first.left, second.left)
    top = max(first.top, second.top)
    right = min(first.right, second.right)
    bottom = min(first.bottom, second.bottom)
    if left >= right or top >= bottom:
        return None
    return _LogicalRectangle(left, top, right, bottom)


def _rectangle_cells(
    rectangle: _LogicalRectangle,
) -> set[tuple[int, int]]:
    return {
        (column, row)
        for row in range(rectangle.top, rectangle.bottom)
        for column in range(rectangle.left, rectangle.right)
    }


def _region_logical_rectangle(region: RetainedRegionDraw) -> _LogicalRectangle:
    return _LogicalRectangle(
        region.logical_x,
        region.logical_y,
        region.logical_x + region.logical_cols,
        region.logical_y + region.logical_rows,
    )


def _region_viewport_rectangle(
    region: RetainedRegionDraw,
    cols: int,
    rows: int,
) -> _LogicalRectangle | None:
    """Resolve RETAINED-1's independent physical clip in screen cells."""

    screen = _LogicalRectangle(0, 0, cols, rows)
    clip_values = (
        region.clip_x,
        region.clip_y,
        region.clip_cols,
        region.clip_rows,
    )
    if not region.clipped:
        if any(clip_values):
            raise PhysicalDesktopAcceptanceError(
                "unclipped retained region carries a nonzero physical clip"
            )
        return screen
    if not any(clip_values):
        return None
    if region.clip_cols <= 0 or region.clip_rows <= 0:
        raise PhysicalDesktopAcceptanceError(
            "clipped retained region carries a noncanonical empty clip"
        )
    clip = _LogicalRectangle(
        region.clip_x,
        region.clip_y,
        region.clip_x + region.clip_cols,
        region.clip_y + region.clip_rows,
    )
    logical_on_screen = _rectangle_intersection(
        _region_logical_rectangle(region),
        screen,
    )
    if (
        logical_on_screen is None
        or clip.left < logical_on_screen.left
        or clip.top < logical_on_screen.top
        or clip.right > logical_on_screen.right
        or clip.bottom > logical_on_screen.bottom
    ):
        raise PhysicalDesktopAcceptanceError(
            "retained region clip is outside its logical/surface intersection"
        )
    return clip


def _draw_logical_rectangle(
    region: RetainedRegionDraw,
    draw,
) -> _LogicalRectangle:
    """Resolve CELL_RECT32 through the exact region/parent origin path."""

    left = region.logical_x
    top = region.logical_y
    for parent in getattr(draw, "parent_bounds", ()):
        left += parent.cell_x
        top += parent.cell_y
    bounds = draw.bounds
    left += bounds.cell_x
    top += bounds.cell_y
    return _LogicalRectangle(
        left,
        top,
        left + bounds.cell_cols,
        top + bounds.cell_rows,
    )


def _visible_draw_rectangle(
    region: RetainedRegionDraw,
    draw,
    cols: int,
    rows: int,
) -> tuple[_LogicalRectangle, _LogicalRectangle | None]:
    logical = _draw_logical_rectangle(region, draw)
    viewport = _region_viewport_rectangle(region, cols, rows)
    if viewport is None:
        return logical, None
    return logical, _rectangle_intersection(logical, viewport)


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
            "display offer has no retained revision"
        )
    if plane is None or not plane.retained_initialized or not plane.retained_visible:
        raise PhysicalDesktopAcceptanceError(
            "display offer does not carry a visible initialized retained plane"
        )
    base_draw_types = (
        GlyphRunDraw,
        MenuBarDraw,
        TextAreaDraw,
        TextGridDraw,
        TabSetDraw,
    )
    instrument_draw_types = (ReadoutDraw, MeterDraw, StatusDraw)
    supported_draw_types = base_draw_types + instrument_draw_types
    for region in plane.regions:
        for draw in region.draws:
            if not isinstance(draw, supported_draw_types):
                raise PhysicalDesktopAcceptanceError(
                    "retained screen contains unsupported draw "
                    f"{type(draw).__name__}"
                )
    base_regions = tuple(
        region
        for region in plane.regions
        if any(isinstance(draw, base_draw_types) for draw in region.draws)
    )
    if len(base_regions) != 1:
        raise PhysicalDesktopAcceptanceError(
            "retained screen must contain exactly one ordinary base region"
        )
    base_region = base_regions[0]
    base_region_index = next(
        index
        for index, region in enumerate(plane.regions)
        if region is base_region
    )
    if base_region_index != 0:
        raise PhysicalDesktopAcceptanceError(
            "retained instrument region precedes the ordinary base region"
        )
    expected_region = _LogicalRectangle(0, 0, cell.cols, cell.rows)
    actual_region = _region_logical_rectangle(base_region)
    if actual_region != expected_region or base_region.clipped:
        raise PhysicalDesktopAcceptanceError(
            f"ordinary retained base region {actual_region!r} is not the "
            f"unclipped full screen {expected_region!r}"
        )
    aggregate_owner = (base_region.owner_id, base_region.owner_generation)
    for region in plane.regions:
        if (region.owner_id, region.owner_generation) != aggregate_owner:
            raise PhysicalDesktopAcceptanceError(
                "retained instrument regions do not share the base aggregate owner"
            )
        _region_viewport_rectangle(region, cell.cols, cell.rows)
        if region is base_region:
            if any(isinstance(draw, instrument_draw_types) for draw in region.draws):
                raise PhysicalDesktopAcceptanceError(
                    "ordinary retained base region contains an instrument draw"
                )
        elif any(not isinstance(draw, instrument_draw_types) for draw in region.draws):
            raise PhysicalDesktopAcceptanceError(
                "non-base retained region contains a non-instrument draw"
            )
    # Regions are in compositor painter order.  A later instrument rectangle
    # may legally cover part of an ordinary semantic root, but the acceptance
    # observer must not promote that root's authored source strings as proof
    # of physically visible Desk state.  Treat the whole intersected root as
    # unavailable evidence because this cell-level observer cannot prove
    # which font pixels survived alpha, padding, and shape rasterization.
    # This is deliberately an evidence rule, not a protocol overlap ban.
    foreground_instrument_cells: set[tuple[int, int]] = set()
    for region in plane.regions[base_region_index + 1 :]:
        for draw in region.draws:
            if not isinstance(draw, instrument_draw_types):
                continue
            _logical, visible = _visible_draw_rectangle(
                region,
                draw,
                cell.cols,
                cell.rows,
            )
            if visible is not None:
                foreground_instrument_cells.update(_rectangle_cells(visible))
    glyphs: list[str | None] = [None] * (cell.cols * cell.rows)
    glyph_cells: set[tuple[int, int]] = set()
    semantic_cells: set[tuple[int, int]] = set()
    instrument_cells: set[tuple[int, int]] = set()
    semantic_lines: list[str] = []
    menu_signatures: list[tuple[str, ...]] = []
    menu_bar_count = 0
    semantic_collection_claims: list[_SemanticCollectionClaim] = []
    semantic_tabset_claims: list[_SemanticTabSetClaim] = []
    instrument_claims: list[_InstrumentClaim] = []
    open_menu_claims: list[set[tuple[int, int]]] = []

    def claim_semantic_rectangle(
        left: int,
        top: int,
        right: int,
        bottom: int,
    ) -> None:
        claimed = _rectangle_cells(_LogicalRectangle(left, top, right, bottom))
        overlap = claimed & semantic_cells
        if overlap:
            raise PhysicalDesktopAcceptanceError(
                "retained semantic root claims overlap: "
                f"cells={len(overlap)}"
            )
        semantic_cells.update(claimed)

    for region, draw in (
        (candidate_region, candidate_draw)
        for candidate_region in plane.regions
        for candidate_draw in candidate_region.draws
    ):
        logical, visible = _visible_draw_rectangle(
            region,
            draw,
            cell.cols,
            cell.rows,
        )
        if visible is None:
            if isinstance(draw, instrument_draw_types):
                continue
            raise PhysicalDesktopAcceptanceError(
                "ordinary retained draw has no physical screen intersection"
            )
        if region is base_region and visible != logical:
            raise PhysicalDesktopAcceptanceError(
                "ordinary retained base draw is not wholly inside the "
                "physical screen"
            )
        left, top, right, bottom = (
            visible.left,
            visible.top,
            visible.right,
            visible.bottom,
        )

        if isinstance(draw, GlyphRunDraw):
            if (
                not draw.text
                or logical.bottom - logical.top != 1
                or logical.right - logical.left != len(draw.text)
                or bottom - top != 1
            ):
                raise PhysicalDesktopAcceptanceError(
                    f"retained glyph run {draw.object_id} geometry does not "
                    "match its horizontal scalar run"
                )
            first_scalar = left - logical.left
            visible_text = draw.text[
                first_scalar : first_scalar + (right - left)
            ]
            if len(visible_text) != right - left:
                raise PhysicalDesktopAcceptanceError(
                    f"retained glyph run {draw.object_id} clip exceeds its "
                    "horizontal scalar run"
                )
            for offset, scalar in enumerate(visible_text):
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
            claim_semantic_rectangle(left, top, right, bottom)
            signature = tuple(menu.label for menu in draw.menus)
            evidence_cells = _rectangle_cells(visible)
            for menu in draw.menus:
                if not menu.state & ControlState.OPEN:
                    continue
                popup_claim = _menu_popup_source_claim(
                    draw,
                    menu,
                    bar_left=logical.left,
                    bar_right=logical.right,
                    bar_top=logical.top,
                    screen_rows=cell.rows,
                )
                open_menu_claims.append(popup_claim)
                evidence_cells.update(popup_claim)
            if not evidence_cells & foreground_instrument_cells:
                menu_bar_count += 1
                menu_signatures.append(signature)
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

        if isinstance(draw, (TextAreaDraw, TextGridDraw)):
            kind = (
                ControlKind.TEXT_AREA
                if isinstance(draw, TextAreaDraw)
                else ControlKind.TEXT_GRID
            )
            if not _rectangle_cells(visible) & foreground_instrument_cells:
                semantic_collection_claims.append(
                    _SemanticCollectionClaim(
                        kind=kind,
                        identity=ControlIdentity(
                            region.owner_id,
                            region.owner_generation,
                            draw.control_id,
                        ),
                        left=left,
                        top=top,
                        right=right,
                        bottom=bottom,
                        visible_text=_visible_semantic_text(draw),
                        content_revision=draw.content.content_revision,
                        primary_key=draw.content.primary_key,
                        current_item_keys=tuple(
                            item.item_key
                            for item in draw.content.items
                            if item.state & SemanticTextState.CURRENT
                        ),
                        content_state=_semantic_text_content_state(
                            draw.content
                        ),
                        state=draw.state,
                    )
                )
            claim_semantic_rectangle(left, top, right, bottom)
            continue

        if isinstance(draw, TabSetDraw):
            if not _rectangle_cells(visible) & foreground_instrument_cells:
                semantic_tabset_claims.append(
                    _SemanticTabSetClaim(
                        identity=ControlIdentity(
                            region.owner_id,
                            region.owner_generation,
                            draw.control_id,
                        ),
                        state=draw.state,
                        left=left,
                        top=top,
                        right=right,
                        bottom=bottom,
                        tabs=tuple(
                            _SemanticTabClaim(
                                identity=ControlIdentity(
                                    region.owner_id,
                                    region.owner_generation,
                                    tab.control_id,
                                ),
                                state=tab.state,
                                order=tab.order,
                                label=tab.label,
                                shortcut=tab.shortcut,
                            )
                            for tab in draw.tabs
                        ),
                    )
                )
            claim_semantic_rectangle(left, top, right, bottom)
            continue

        if isinstance(draw, instrument_draw_types):
            if isinstance(draw, ReadoutDraw):
                kind = "READOUT"
            elif isinstance(draw, MeterDraw):
                kind = "METER"
            else:
                kind = "STATUS"
            instrument_claims.append(
                _InstrumentClaim(
                    kind=kind,
                    owner_id=region.owner_id,
                    owner_generation=region.owner_generation,
                    object_id=draw.object_id,
                    left=left,
                    top=top,
                    right=right,
                    bottom=bottom,
                )
            )
            instrument_cells.update(_rectangle_cells(visible))
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
    semantic_residual_cells = glyph_cells & semantic_cells
    if semantic_residual_cells:
        raise PhysicalDesktopAcceptanceError(
            "retained residual glyphs overlap semantic root claims: "
            f"cells={len(semantic_residual_cells)}"
        )
    instrument_residual_cells = glyph_cells & instrument_cells
    if instrument_residual_cells:
        # The unified producer passes every instrument claim to the residual
        # planner, so this is a producer-invariant check rather than a ban on
        # generic compositor layering.
        raise PhysicalDesktopAcceptanceError(
            "retained residual glyphs overlap instrument claims: "
            f"cells={len(instrument_residual_cells)}"
        )
    covered = glyph_cells | semantic_cells | instrument_cells
    uncovered = {
        (col, row)
        for row in range(cell.rows)
        for col in range(cell.cols)
        if (col, row) not in covered
    }
    expected_popup_claim: set[tuple[int, int]] = set()
    for popup_claim in open_menu_claims:
        expected_popup_claim.update(popup_claim)
    unexpected_uncovered = uncovered - expected_popup_claim
    popup_residual_cells = glyph_cells & expected_popup_claim
    if unexpected_uncovered or popup_residual_cells:
        raise PhysicalDesktopAcceptanceError(
            "retained rich draws leave logical cells uncovered outside the "
            "exact semantic popup source claims: "
            f"actual={len(uncovered)} expected={len(expected_popup_claim)} "
            f"popup-residual={len(popup_residual_cells)}"
        )
    renderer_owned_gap_cells = len(expected_popup_claim)
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
        sum(len(region.draws) for region in plane.regions),
        semantic_lines=tuple(semantic_lines),
        glyph_cell_count=len(glyph_cells),
        menu_bar_count=menu_bar_count,
        menu_signatures=tuple(menu_signatures),
        renderer_owned_gap_cells=renderer_owned_gap_cells,
        semantic_collection_claims=tuple(semantic_collection_claims),
        semantic_tabset_claims=tuple(semantic_tabset_claims),
        region_count=len(plane.regions),
        instrument_region_count=len(plane.regions) - 1,
        clipped_region_count=sum(region.clipped for region in plane.regions),
        instrument_cell_count=len(instrument_cells),
        instrument_claims=tuple(instrument_claims),
    )


def _require_exact_menu_aggregate(
    projection: RichScreenProjection,
    expected: tuple[tuple[str, ...], ...],
    requirement: str,
) -> None:
    """Require one exact semantic menu forest for each expected applet."""

    missing = tuple(
        signature
        for signature in expected
        if projection.menu_signatures.count(signature) != 1
    )
    unexpected = tuple(
        signature
        for signature in projection.menu_signatures
        if signature not in expected
    )
    exact_count = len(expected)
    if (
        missing
        or unexpected
        or projection.menu_bar_count != exact_count
        or len(projection.menu_signatures) != exact_count
    ):
        raise PhysicalDesktopAcceptanceError(
            f"{requirement}: "
            f"missing-or-duplicated={missing!r} "
            f"unexpected={unexpected!r} "
            f"bars={projection.menu_bar_count} "
            f"signatures={len(projection.menu_signatures)}"
        )


def _require_canonical_menu_aggregate(projection: RichScreenProjection) -> None:
    """Require exactly one semantic forest for every canonical visible applet."""

    _require_exact_menu_aggregate(
        projection,
        DESKTOP_MENU_SIGNATURES,
        "retained frame does not contain one exact semantic menu forest "
        "for every canonical visible applet and no unexpected applet",
    )


def _canonical_pad_semantic_failures(
    projection: RichScreenProjection,
) -> list[str]:
    """Return failures for the Pad roots that remain rich across this journey."""

    missing = []
    pad_areas = _collection_claims_in_tile(
        projection, ControlKind.TEXT_AREA, PAD_DESKTOP_TILE
    )
    if not any(_collection_is_available(claim) for claim in pad_areas):
        missing.append(
            f"at least one TEXT_AREA in Pad tile {PAD_DESKTOP_TILE} must be "
            "visibly enabled"
        )
    try:
        _canonical_pad_tabset_claim(projection)
    except PhysicalDesktopAcceptanceError as exc:
        missing.append(str(exc))
    return missing


def _require_canonical_desktop_semantics(
    projection: RichScreenProjection,
) -> None:
    """Require the exact menu forest plus real editor and grid roots."""

    _require_canonical_menu_aggregate(projection)

    missing = _canonical_pad_semantic_failures(projection)
    daybook_grids = _collection_claims_in_tile(
        projection, ControlKind.TEXT_GRID, DAYBOOK_DESKTOP_TILE
    )
    if len(daybook_grids) != 1 or not _collection_is_available(
        daybook_grids[0]
    ):
        missing.append(
            f"exactly one TEXT_GRID in Daybook tile {DAYBOOK_DESKTOP_TILE} "
            "must be visibly enabled "
            f"(found {len(daybook_grids)})"
        )
    if missing:
        raise PhysicalDesktopAcceptanceError(
            "canonical retained Desk frame is missing real semantic "
            f"collection roots: {', '.join(missing)}"
        )


def _require_daybook_prompt_fallback_semantics(
    projection: RichScreenProjection,
) -> None:
    """Require the exact document-atomic fallback while Daybook is modal."""

    unaffected_menus = tuple(
        signature
        for signature in DESKTOP_MENU_SIGNATURES
        if signature != DAYBOOK_MENU_SIGNATURE
    )
    _require_exact_menu_aggregate(
        projection,
        unaffected_menus,
        "Daybook prompt fallback does not retain exactly the four unaffected "
        "canonical menu forests and no Daybook or unexpected applet",
    )

    missing = _canonical_pad_semantic_failures(projection)
    daybook_collections = tuple(
        claim
        for kind in (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID)
        for claim in _collection_claims_in_tile(
            projection,
            kind,
            DAYBOOK_DESKTOP_TILE,
        )
    )
    if daybook_collections:
        missing.append(
            "the document-atomic Daybook fallback must not retain a partial "
            f"text collection (found {len(daybook_collections)})"
        )
    daybook_tabsets = _tabset_claims_in_tile(
        projection,
        DAYBOOK_DESKTOP_TILE,
    )
    if daybook_tabsets:
        missing.append(
            "the document-atomic Daybook fallback must not retain a partial "
            f"TABSET (found {len(daybook_tabsets)})"
        )
    if not _residual_tile_contains(
        projection,
        DAYBOOK_PROMPT_MARKER,
        DAYBOOK_DESKTOP_TILE,
    ):
        missing.append("the Daybook prompt is not visible inside its Desk tile")
    if missing:
        raise PhysicalDesktopAcceptanceError(
            "Daybook prompt retained fallback is incomplete: "
            f"{', '.join(missing)}"
        )


def _desk_launcher_selected(
    projection: RichScreenProjection,
    title: str,
) -> bool:
    """Return whether Desk's ordinary launcher visibly selects one title."""

    index = DESKTOP_LAUNCHER_TITLES.index(title)
    row = DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index
    if row >= len(projection.lines):
        return False
    line = projection.lines[row]
    end = DESKTOP_LAUNCHER_TEXT_COL + len(title)
    return (
        len(line) >= end
        and line[DESKTOP_LAUNCHER_MARKER_COL] == ">"
        and line[DESKTOP_LAUNCHER_MARKER_COL + 1] == " "
        and line[DESKTOP_LAUNCHER_TEXT_COL:end] == title
        and (len(line) == end or line[end].isspace())
    )


def _require_desk_launcher_selection(
    projection: RichScreenProjection,
    title: str,
) -> None:
    """Require one visible, ordinary Desk-launcher selection."""

    selected_titles = tuple(
        candidate
        for index, candidate in enumerate(DESKTOP_LAUNCHER_TITLES)
        if DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index < len(projection.lines)
        and len(projection.lines[DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index])
        > DESKTOP_LAUNCHER_MARKER_COL
        and projection.lines[DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index][
            DESKTOP_LAUNCHER_MARKER_COL
        ]
        == ">"
    )
    malformed_entries = tuple(
        candidate
        for index, candidate in enumerate(DESKTOP_LAUNCHER_TITLES)
        if (
            DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index
            >= len(projection.lines)
            or len(
                projection.lines[DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index]
            )
            < DESKTOP_LAUNCHER_TEXT_COL + len(candidate)
            or projection.lines[DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index][
                DESKTOP_LAUNCHER_MARKER_COL
            ]
            not in (" ", ">")
            or projection.lines[DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index][
                DESKTOP_LAUNCHER_MARKER_COL + 1
            ]
            != " "
            or projection.lines[DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index][
                DESKTOP_LAUNCHER_TEXT_COL : DESKTOP_LAUNCHER_TEXT_COL
                + len(candidate)
            ]
            != candidate
            or (
                len(
                    projection.lines[
                        DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index
                    ]
                )
                > DESKTOP_LAUNCHER_TEXT_COL + len(candidate)
                and not projection.lines[
                    DESKTOP_LAUNCHER_FIRST_ENTRY_ROW + index
                ][
                    DESKTOP_LAUNCHER_TEXT_COL + len(candidate)
                ].isspace()
            )
        )
    )
    exact_header = (
        len(projection.lines) > DESKTOP_LAUNCHER_TOP + 1
        and len(projection.lines[DESKTOP_LAUNCHER_TOP])
        >= DESKTOP_LAUNCHER_HEADER_COL + len("Applets")
        and projection.lines[DESKTOP_LAUNCHER_TOP][
            DESKTOP_LAUNCHER_HEADER_COL : DESKTOP_LAUNCHER_HEADER_COL
            + len("Applets")
        ]
        == "Applets"
        and len(projection.lines[DESKTOP_LAUNCHER_TOP + 1])
        >= DESKTOP_LAUNCHER_HEADER_COL + len("select an applet")
        and projection.lines[DESKTOP_LAUNCHER_TOP + 1][
            DESKTOP_LAUNCHER_HEADER_COL : DESKTOP_LAUNCHER_HEADER_COL
            + len("select an applet")
        ]
        == "select an applet"
    )
    if (
        not exact_header
        or malformed_entries
        or len(selected_titles) != 1
        or not _desk_launcher_selected(projection, title)
    ):
        raise PhysicalDesktopAcceptanceError(
            "ordinary Desk launcher does not have the expected visible "
            f"selection {title!r}: selected={selected_titles!r}, "
            f"malformed={malformed_entries!r}"
        )


def _require_soundlab_desktop_semantics(
    projection: RichScreenProjection,
) -> None:
    """Require the launched Sound Lab and its complete instrument family."""

    expected_menus = DESKTOP_MENU_SIGNATURES + (SOUNDLAB_MENU_SIGNATURE,)
    missing = tuple(
        signature
        for signature in expected_menus
        if projection.menu_signatures.count(signature) != 1
    )
    actual_instruments = (
        projection.readout_count,
        projection.meter_count,
        projection.status_count,
    )
    expected_instruments = (8, 2, 3)
    soundlab_left, soundlab_top, soundlab_right, soundlab_bottom = (
        _desktop_tile_bounds(projection, SOUNDLAB_DESKTOP_TILE)
    )
    misplaced_instruments = tuple(
        claim.object_id
        for claim in projection.instrument_claims
        if not (
            soundlab_left <= claim.left < claim.right <= soundlab_right
            and soundlab_top <= claim.top < claim.bottom <= soundlab_bottom
        )
    )
    missing_semantics: list[str] = []
    if (
        missing
        or projection.menu_bar_count != len(expected_menus)
        or len(projection.menu_signatures) != len(expected_menus)
    ):
        missing_semantics.append(
            "one exact semantic menu forest for each startup applet and "
            f"Sound Lab (missing-or-duplicated={missing!r}, "
            f"bars={projection.menu_bar_count}, "
            f"signatures={len(projection.menu_signatures)})"
        )
    pad_areas = _collection_claims_in_tile(
        projection, ControlKind.TEXT_AREA, PAD_DESKTOP_TILE
    )
    if not any(_collection_is_available(claim) for claim in pad_areas):
        missing_semantics.append(
            f"at least one TEXT_AREA in Pad tile {PAD_DESKTOP_TILE} must be "
            "visibly enabled"
        )
    daybook_grids = _collection_claims_in_tile(
        projection, ControlKind.TEXT_GRID, DAYBOOK_DESKTOP_TILE
    )
    if len(daybook_grids) != 1 or not _collection_is_available(
        daybook_grids[0]
    ):
        missing_semantics.append(
            f"exactly one TEXT_GRID in Daybook tile {DAYBOOK_DESKTOP_TILE} "
            "must be visibly enabled "
            f"(found {len(daybook_grids)})"
        )
    try:
        _canonical_pad_tabset_claim(projection)
    except PhysicalDesktopAcceptanceError as exc:
        missing_semantics.append(str(exc))
    if (
        projection.instrument_region_count != 1
        or projection.instrument_cell_count == 0
        or actual_instruments != expected_instruments
        or misplaced_instruments
    ):
        missing_semantics.append(
            "one nonempty Sound Lab instrument region with exactly "
            "8 READOUT, 2 METER, and 3 STATUS objects "
            f"(regions={projection.instrument_region_count}, "
            f"cells={projection.instrument_cell_count}, "
            f"kinds={actual_instruments!r}, "
            f"outside-tile-{SOUNDLAB_DESKTOP_TILE}="
            f"{misplaced_instruments!r})"
        )
    if missing_semantics:
        raise PhysicalDesktopAcceptanceError(
            "launched Sound Lab retained frame is missing exact product "
            f"semantics: {', '.join(missing_semantics)}"
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


def _pad_tabset(
    offer: TerminalDisplayOffer,
) -> tuple[RetainedRegionDraw, TabSetDraw]:
    """Resolve Pad's ordinary canonical TABSET from its Desk tile."""

    plane = offer.retained
    if plane is None:
        raise PhysicalDesktopAcceptanceError(
            "Pad TABSET lookup requires a retained display plane"
        )
    geometry = RichScreenProjection(
        offer.cell.cols,
        offer.cell.rows,
        (),
        0,
    )
    tile_left, tile_top, tile_right, tile_bottom = _desktop_tile_bounds(
        geometry,
        PAD_DESKTOP_TILE,
    )
    matches: list[tuple[RetainedRegionDraw, TabSetDraw]] = []
    for region in plane.regions:
        for draw in region.draws:
            if not isinstance(draw, TabSetDraw):
                continue
            _logical, visible = _visible_draw_rectangle(
                region,
                draw,
                offer.cell.cols,
                offer.cell.rows,
            )
            if visible is None:
                continue
            left, top, right, bottom = (
                visible.left,
                visible.top,
                visible.right,
                visible.bottom,
            )
            if (
                tile_left <= left < right <= tile_right
                and tile_top <= top < bottom <= tile_bottom
            ):
                matches.append((region, draw))
    if len(matches) != 1:
        raise PhysicalDesktopAcceptanceError(
            "retained frame does not contain exactly one canonical Pad TABSET"
        )
    region, tabset = matches[0]
    expected_root_state = ControlState.VISIBLE | ControlState.ENABLED
    if tabset.state != expected_root_state:
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET root is not visibly enabled"
        )
    if not tabset.tabs:
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET contains no visible tabs"
        )
    if tuple(tab.order for tab in tabset.tabs) != tuple(range(len(tabset.tabs))):
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET omits a visual tab ordinal"
        )
    if len(
        tuple(tab for tab in tabset.tabs if tab.state & ControlState.SELECTED)
    ) != 1:
        raise PhysicalDesktopAcceptanceError(
            "canonical Pad TABSET does not contain exactly one selected tab"
        )
    return region, tabset


def _pad_tab_hit_target(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    control_id: int,
) -> tuple[ControlHitTarget, str]:
    """Resolve one unselected Pad tab from the exact acknowledged hit map."""

    token = (offer.offer_id, offer.scope)
    if display_state.hit_map_token != token or display_ack != token:
        raise PhysicalDesktopAcceptanceError(
            "Pad tab activation lacks the exact acknowledged semantic hit map"
        )
    region, tabset = _pad_tabset(offer)
    tab_matches = tuple(
        tab for tab in tabset.tabs if tab.control_id == control_id
    )
    if len(tab_matches) != 1:
        raise PhysicalDesktopAcceptanceError(
            "Pad tab activation target is not in the canonical TABSET"
        )
    tab = tab_matches[0]
    expected_tab_state = ControlState.VISIBLE | ControlState.ENABLED
    if (
        tab.state & expected_tab_state != expected_tab_state
        or tab.state & ControlState.SELECTED
    ):
        raise PhysicalDesktopAcceptanceError(
            "Pad tab activation target is not an enabled unselected tab"
        )
    expected_identities = tuple(
        ControlIdentity(
            region.owner_id,
            region.owner_generation,
            candidate.control_id,
        )
        for candidate in tabset.tabs
        if candidate.state & ControlState.ENABLED
    )
    expected_identity_set = set(expected_identities)
    actual = tuple(
        target
        for target in display_state.hit_targets
        if target.kind is ControlKind.TAB
        and target.identity in expected_identity_set
    )
    if tuple(target.identity for target in actual) != expected_identities:
        raise PhysicalDesktopAcceptanceError(
            "acknowledged Pad TAB hit targets do not exactly match its "
            "enabled visible tabs in semantic painter order"
        )
    identity = ControlIdentity(
        region.owner_id,
        region.owner_generation,
        control_id,
    )
    matches = tuple(target for target in actual if target.identity == identity)
    if len(matches) != 1:
        raise PhysicalDesktopAcceptanceError(
            "acknowledged frame does not expose one requested Pad TAB target"
        )
    target = matches[0]
    if target.rect.width <= 0 or target.rect.height <= 0:
        raise PhysicalDesktopAcceptanceError(
            "acknowledged Pad TAB target has empty physical geometry"
        )
    center_x = target.rect.left + target.rect.width // 2
    center_y = target.rect.top + target.rect.height // 2
    if display_state.hit_test(center_x, center_y, display_token=token) != target:
        raise PhysicalDesktopAcceptanceError(
            "Pad TAB target is not the acknowledged painter-order hit"
        )
    return target, tab.label


def _pad_file_hit_target(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
) -> ControlHitTarget:
    """Resolve the painter-order Pad/File target from one exact sink ACK."""

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
    elif method == "activate_pad_tab":
        try:
            control_id = int(value, 10)
        except (TypeError, ValueError) as exc:
            raise PhysicalDesktopAcceptanceError(
                "Pad tab activation carries an invalid control ID"
            ) from exc
        if control_id <= 0 or str(control_id) != value:
            raise PhysicalDesktopAcceptanceError(
                "Pad tab activation carries a non-canonical control ID"
            )
        target, label = _pad_tab_hit_target(
            offer,
            display_state,
            display_ack,
            control_id,
        )
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
        semantic_target = _control_target_evidence(target, label=label)
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
    """Advance app input only across newly acknowledged reference-sink frames."""

    def __init__(self, ready_markers: tuple[str, ...]):
        if not ready_markers or any(not marker for marker in ready_markers):
            raise ValueError("ready_markers must contain visible strings")
        self.ready_markers = tuple(ready_markers)
        self.stage = 0
        self.frame_barrier = 0
        self._pending: _PendingJourneyInput | None = None
        self._lineage: tuple[int, int, int, int, int, int, int] | None = None
        self._pad_area_before_edit: _CollectionStates | None = None
        self._pad_area_after_edit: _CollectionStates | None = None
        self._daybook_grid_before_navigation: _CollectionStates | None = None
        self._daybook_grid_after_navigation: _CollectionStates | None = None
        self._pad_tabset_before_handoff: _TabSetState | None = None
        self._pad_tabset_before_activation: _TabSetState | None = None
        self._pad_tabset_after_activation: _TabSetState | None = None
        self._pad_tab_activation_target: _TabSignature | None = None
        self._pad_area_before_tab_activation: _CollectionStates | None = None
        self._pad_area_after_tab_activation: _CollectionStates | None = None

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
    ) -> tuple[int, int, int, int, int, int, int]:
        scope = offer.scope
        plane = offer.retained
        if plane is None or not plane.regions:
            raise PhysicalDesktopAcceptanceError(
                "physical acceptance lineage requires one retained owner"
            )
        owners = {
            (region.owner_id, region.owner_generation)
            for region in plane.regions
        }
        if len(owners) != 1:
            raise PhysicalDesktopAcceptanceError(
                "physical acceptance lineage requires one retained owner"
            )
        owner_id, owner_generation = next(iter(owners))
        return (
            generation,
            scope.attachment_epoch,
            scope.session_id,
            scope.presentation_epoch,
            scope.geometry_generation,
            owner_id,
            owner_generation,
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

    def _require_exercised_state_survives(
        self,
        projection: RichScreenProjection,
    ) -> None:
        """Keep the accepted Pad/Daybook state live after Sound Lab opens."""

        expected_tabset = self._pad_tabset_after_activation
        if expected_tabset is None:
            raise PhysicalDesktopAcceptanceError(
                "final Sound Lab frame has no acknowledged activated Pad "
                "tab state"
            )
        tabset = _canonical_pad_tabset_claim(projection)
        current_tabset = _tabset_state(tabset)
        if current_tabset != expected_tabset:
            raise PhysicalDesktopAcceptanceError(
                "final Sound Lab frame did not preserve the exercised Pad "
                "two-tab signature graph, root bounds, and activated original "
                f"tab: expected={expected_tabset!r} "
                f"observed={current_tabset!r}"
            )

        if self._pad_area_after_tab_activation is None:
            raise PhysicalDesktopAcceptanceError(
                "final Sound Lab frame has no acknowledged activated Pad "
                "editor state"
            )
        pad_claims = _collection_claims_preserving_state(
            projection,
            ControlKind.TEXT_AREA,
            PAD_DESKTOP_TILE,
            self._pad_area_after_tab_activation,
            PAD_ACCEPTANCE_TEXT,
        )
        if len(pad_claims) != 1:
            raise PhysicalDesktopAcceptanceError(
                "final Sound Lab frame did not preserve the exercised Pad "
                "editor state and accepted text across retained replacement"
            )

        if self._daybook_grid_after_navigation is None:
            raise PhysicalDesktopAcceptanceError(
                "final Sound Lab frame has no acknowledged navigated Daybook "
                "state"
            )
        if (
            _desktop_tile_contains(
                projection,
                DAYBOOK_ACCEPTANCE_TASK,
                DAYBOOK_DESKTOP_TILE,
            )
            or not _daybook_date_is(projection, DAYBOOK_NEXT_DATE)
            or len(
                _collection_claims_preserving_state(
                    projection,
                    ControlKind.TEXT_GRID,
                    DAYBOOK_DESKTOP_TILE,
                    self._daybook_grid_after_navigation,
                )
            )
            != 1
        ):
            raise PhysicalDesktopAcceptanceError(
                "final Sound Lab frame did not preserve the exercised "
                "Daybook navigation state across retained replacement"
            )

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
        daybook_prompt_visible = _residual_tile_contains(
            projection,
            DAYBOOK_PROMPT_MARKER,
            DAYBOOK_DESKTOP_TILE,
        )
        if 0 < self.stage <= DESKTOP_ACCEPTANCE_PAD_TAB_STAGE:
            if self.stage in (6, 7, 8) and daybook_prompt_visible:
                # The prompt is an ordinary final-writer overlay.  RUHA's
                # existing document-atomic rule therefore withholds all of
                # Daybook's intersected semantic slices until the overlay is
                # gone; the other applets remain rich and Daybook remains
                # physically complete through residual glyphs.
                _require_daybook_prompt_fallback_semantics(projection)
            else:
                _require_canonical_desktop_semantics(projection)
        if self._pending is not None:
            # Backpressure is admitted only with zero accepted input.  A newer
            # acknowledged frame therefore discards the old authorization and
            # must independently satisfy the current stage before _send binds
            # a fresh request to its offer, scope, and generation.
            self._pending = None

        if self.stage == 0 and all(marker in text for marker in self.ready_markers):
            self._lineage = lineage
            _require_canonical_desktop_semantics(projection)
            initial_tabset = _canonical_pad_tabset_claim(projection)
            if len(initial_tabset.tabs) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "canonical initial Pad TABSET does not contain exactly "
                    "one ordinary buffer tab"
                )
            if _pad_file_menu_is_open(offer):
                raise PhysicalDesktopAcceptanceError(
                    "canonical initial Pad File menu is already open"
                )
            milestone = self._milestone("desk-complete")
            if PAD_FOCUS_MARKER in text:
                # Focus is already proven by this exact acknowledged frame.
                # Re-focusing the same tile is a legitimate visual no-op and
                # therefore need not produce the newer offer that stage 1
                # awaits.  Exercise Pad through its authored semantic menu
                # target directly instead of manufacturing a frame change.
                self._send(
                    "activate_pad_file_menu",
                    PAD_FILE_MENU_EVIDENCE,
                    2,
                    offer,
                    generation,
                    sender,
                )
            else:
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
            if _collection_claims_containing(
                projection,
                ControlKind.TEXT_AREA,
                PAD_DESKTOP_TILE,
                PAD_ACCEPTANCE_TEXT,
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Pad acceptance marker was visible before editor input"
                )
            self._pad_area_before_edit = _collection_states_in_tile(
                projection,
                ControlKind.TEXT_AREA,
                PAD_DESKTOP_TILE,
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
        if self.stage == 4 and PAD_FOCUS_MARKER in text:
            edited_claims = _collection_claims_advanced_containing(
                projection,
                ControlKind.TEXT_AREA,
                PAD_DESKTOP_TILE,
                self._pad_area_before_edit,
                PAD_ACCEPTANCE_TEXT,
                require_position_change=False,
            )
            if not edited_claims:
                return JourneyProgress()
            if len(edited_claims) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "acknowledged Pad edit is ambiguous across multiple "
                    "TEXT_AREA roots"
                )
            edited_claim = edited_claims[0]
            self._pad_area_after_edit = (_collection_state(edited_claim),)
            milestone = self._milestone("pad-edited")
            self._send("send_key", "alt+3", 5, offer, generation, sender)
            return JourneyProgress(milestone)
        if self.stage == 5 and DAYBOOK_FOCUS_MARKER in text:
            self._send("send_key", "ctrl+n", 6, offer, generation, sender)
            return JourneyProgress()
        if (
            self.stage == 6
            and DAYBOOK_FOCUS_MARKER in text
            and daybook_prompt_visible
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
            and daybook_prompt_visible
            and DAYBOOK_ACCEPTANCE_TASK in text
        ):
            self._send("send_key", "enter", 8, offer, generation, sender)
            return JourneyProgress()
        if (
            self.stage == 8
            and DAYBOOK_FOCUS_MARKER in text
            and _desktop_tile_contains(
                projection,
                DAYBOOK_ACCEPTANCE_TASK,
                DAYBOOK_DESKTOP_TILE,
            )
            and _daybook_date_is(projection, DAYBOOK_INITIAL_DATE)
            and not daybook_prompt_visible
        ):
            self._daybook_grid_before_navigation = _collection_states_in_tile(
                projection,
                ControlKind.TEXT_GRID,
                DAYBOOK_DESKTOP_TILE,
            )
            milestone = self._milestone("daybook-task-added")
            self._send("send_key", "right", 9, offer, generation, sender)
            return JourneyProgress(milestone)
        if (
            self.stage == 9
            and DAYBOOK_FOCUS_MARKER in text
            and not _desktop_tile_contains(
                projection,
                DAYBOOK_ACCEPTANCE_TASK,
                DAYBOOK_DESKTOP_TILE,
            )
            and _daybook_date_is(projection, DAYBOOK_NEXT_DATE)
            and _collection_state_advanced(
                projection,
                ControlKind.TEXT_GRID,
                DAYBOOK_DESKTOP_TILE,
                self._daybook_grid_before_navigation,
                require_position_change=True,
            )
        ):
            self._daybook_grid_after_navigation = _collection_states_in_tile(
                projection,
                ControlKind.TEXT_GRID,
                DAYBOOK_DESKTOP_TILE,
            )
            tabset = _canonical_pad_tabset_claim(projection)
            if len(tabset.tabs) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "canonical Pad TABSET does not contain exactly one "
                    "buffer immediately before the Daybook handoff"
                )
            self._pad_tabset_before_handoff = _tabset_state(tabset)
            milestone = self._milestone("daybook-date-advanced")
            self._send("send_key", "ctrl+o", 10, offer, generation, sender)
            return JourneyProgress(milestone)
        if self.stage == 10 and PAD_FOCUS_MARKER in text:
            handoff_claims = _collection_claims_containing(
                projection,
                ControlKind.TEXT_AREA,
                PAD_DESKTOP_TILE,
                DAYBOOK_SHARED_SOURCE_MARKER,
                DAYBOOK_ACCEPTANCE_TASK,
            )
            if not handoff_claims:
                return JourneyProgress()
            if len(handoff_claims) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff is ambiguous across multiple "
                    "TEXT_AREA roots"
                )
            if self._pad_area_after_edit is None:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff has no acknowledged Pad editor "
                    "state"
                )
            handoff_claim = handoff_claims[0]
            prior_handoff_states = _prior_collection_states_for_claim(
                self._pad_area_after_edit,
                handoff_claim,
            )
            if (
                len(prior_handoff_states) != 1
                or handoff_claim.content_revision
                <= prior_handoff_states[0].content_revision
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff moved away from or did not "
                    "advance the acknowledged Pad editor root"
                )
            tabset = _canonical_pad_tabset_claim(projection)
            before_handoff = self._pad_tabset_before_handoff
            if before_handoff is None:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff has no acknowledged pre-handoff "
                    "canonical tab graph"
                )
            current_tabset = _tabset_state(tabset)
            if current_tabset.bounds != before_handoff.bounds:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff moved the canonical TABSET root "
                    "away from its acknowledged bounds"
                )
            prior_tabs = before_handoff.tabs
            if len(tabset.tabs) != len(prior_tabs) + 1:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff did not append exactly one "
                    "canonical tab to its acknowledged pre-handoff graph"
                )
            current_graph = current_tabset.tabs
            if current_graph[: len(prior_tabs)] != prior_tabs:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff replaced, reordered, or relabeled "
                    "an existing canonical tab since its acknowledged "
                    "pre-handoff frame"
                )
            target_tab_signature = prior_tabs[0]
            target_matches = tuple(
                tab
                for tab in tabset.tabs
                if _tab_signature(tab) == target_tab_signature
            )
            if len(target_matches) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "Pad's original canonical tab did not retain its "
                    "acknowledged signature"
                )
            target_tab = target_matches[0]
            if (
                target_tab.state & ControlState.SELECTED
                or current_tabset.selected == target_tab_signature
                or current_tabset.selected != current_graph[-1]
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Daybook-to-Pad handoff did not select its appended tab"
                )
            self._pad_tabset_before_activation = current_tabset
            self._pad_tab_activation_target = target_tab_signature
            self._pad_area_before_tab_activation = (
                _collection_state(handoff_claim),
            )
            milestone = self._milestone("daybook-source-opened-in-pad")
            self._send(
                "activate_pad_tab",
                str(target_tab.identity.control_id),
                DESKTOP_ACCEPTANCE_PAD_TAB_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_PAD_TAB_STAGE:
            before = self._pad_tabset_before_activation
            target_signature = self._pad_tab_activation_target
            if before is None or target_signature is None:
                raise PhysicalDesktopAcceptanceError(
                    "Pad tab activation has no acknowledged source state"
                )
            tabset = _canonical_pad_tabset_claim(projection)
            current_tabset = _tabset_state(tabset)
            if (
                current_tabset.bounds != before.bounds
                or current_tabset.tabs != before.tabs
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Pad TABSET bounds or signature graph changed during "
                    "activation"
                )
            if (
                PAD_FOCUS_MARKER in text
                and current_tabset.selected == target_signature
                and current_tabset.selected != before.selected
            ):
                activated_claims = _collection_claims_advanced_containing(
                    projection,
                    ControlKind.TEXT_AREA,
                    PAD_DESKTOP_TILE,
                    self._pad_area_before_tab_activation,
                    PAD_ACCEPTANCE_TEXT,
                    require_position_change=False,
                )
                if not activated_claims:
                    return JourneyProgress()
                if len(activated_claims) != 1:
                    raise PhysicalDesktopAcceptanceError(
                        "acknowledged Pad tab activation is ambiguous across "
                        "multiple TEXT_AREA roots"
                    )
                if self._pad_area_after_edit is None:
                    raise PhysicalDesktopAcceptanceError(
                        "Pad tab activation has no acknowledged edited "
                        "content state"
                    )
                restored_claims = _collection_claims_preserving_state(
                    projection,
                    ControlKind.TEXT_AREA,
                    PAD_DESKTOP_TILE,
                    self._pad_area_after_edit,
                    PAD_ACCEPTANCE_TEXT,
                )
                activated_claims = tuple(
                    claim
                    for claim in activated_claims
                    if claim in restored_claims
                )
                if len(activated_claims) != 1:
                    raise PhysicalDesktopAcceptanceError(
                        "acknowledged Pad tab activation did not restore the "
                        "exact edited STX1 state"
                    )
                activated_claim = activated_claims[0]
                self._pad_area_after_tab_activation = (
                    _collection_state(activated_claim),
                )
                self._pad_tabset_after_activation = current_tabset
                milestone = self._milestone("pad-tab-activated")
                self._send(
                    "send_key",
                    "alt+h",
                    DESKTOP_ACCEPTANCE_LAUNCHER_OPEN_STAGE,
                    offer,
                    generation,
                    sender,
                )
                return JourneyProgress(
                    milestone,
                )
        if self.stage == DESKTOP_ACCEPTANCE_LAUNCHER_OPEN_STAGE:
            if not _desk_launcher_selected(projection, "Akashic Pad"):
                return JourneyProgress()
            _require_desk_launcher_selection(projection, "Akashic Pad")
            milestone = self._milestone("desk-launcher-open")
            self._send(
                "send_key",
                "end",
                DESKTOP_ACCEPTANCE_LAUNCHER_END_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_LAUNCHER_END_STAGE:
            if not _desk_launcher_selected(projection, "Streams"):
                return JourneyProgress()
            _require_desk_launcher_selection(projection, "Streams")
            self._send(
                "send_key",
                "up",
                DESKTOP_ACCEPTANCE_SOUNDLAB_SELECTED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress()
        if self.stage == DESKTOP_ACCEPTANCE_SOUNDLAB_SELECTED_STAGE:
            if not _desk_launcher_selected(projection, "Sound Lab"):
                return JourneyProgress()
            _require_desk_launcher_selection(projection, "Sound Lab")
            milestone = self._milestone("soundlab-launch-source")
            self._send(
                "send_key",
                "enter",
                DESKTOP_ACCEPTANCE_FINAL_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_FINAL_STAGE:
            taskbar = (
                projection.lines[CANONICAL_DESKTOP_ROWS - 1]
                if len(projection.lines) >= CANONICAL_DESKTOP_ROWS
                else ""
            )
            if (
                SOUNDLAB_FOCUS_MARKER not in taskbar
                or not _desktop_tile_contains(
                    projection,
                    "SOUND LAB",
                    SOUNDLAB_DESKTOP_TILE,
                )
            ):
                return JourneyProgress()
            _require_soundlab_desktop_semantics(projection)
            self._require_exercised_state_survives(projection)
            self.frame_barrier = offer.offer_id
            return JourneyProgress(
                self._milestone("soundlab-instruments-live"),
                True,
            )
        return JourneyProgress()


def _surface_rgba(pygame_module, surface) -> bytes:
    return pygame_module.image.tostring(surface, "RGBA")


@dataclass(frozen=True)
class _TerminalCellObservation:
    text: str
    kdos_quit_prompt_row: int | None


def _terminal_cell_observation(
    terminal: VirtualTerminal,
) -> _TerminalCellObservation:
    """Snapshot CELL text and exact live KDOS QUIT-prompt evidence."""

    with terminal._lock:
        rows = [
            "".join(cell[0] for cell in row).rstrip()
            for row in terminal.grid
        ]
        cursor_row = terminal.cy
        cursor_col = terminal.cx
        prompt_row: int | None = None
        if (
            terminal.cursor_visible
            and 0 <= cursor_row < len(terminal.grid)
            and 2 <= cursor_col < len(terminal.grid[cursor_row])
            and terminal.grid[cursor_row][cursor_col - 2][0] == ">"
            and terminal.grid[cursor_row][cursor_col - 1][0] == " "
        ):
            prompt_row = cursor_row
        return _TerminalCellObservation("\n".join(rows), prompt_row)


def _guest_boot_failure(
    observation: _TerminalCellObservation,
    *,
    pre_ready: bool,
) -> str | None:
    """Report explicit failures, or a pre-ready return to KDOS QUIT."""

    text = observation.text
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
    if failure_indexes:
        index = failure_indexes[-1]
        return "\n".join(lines[max(0, index - 2) : index + 1])
    if not pre_ready or observation.kdos_quit_prompt_row is None:
        return None
    screen_lines = text.split("\n")
    prompt_row = observation.kdos_quit_prompt_row
    return "\n".join(
        line.rstrip()
        for line in screen_lines[max(0, prompt_row - 2) : prompt_row + 1]
        if line.strip()
    )


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
    *,
    trace: _PerformanceTrace | None = None,
) -> bool:
    """Route one physical event through the normal ACK-bound control path."""

    if event.type == getattr(pygame_module, "MOUSEMOTION", -1):
        semantic_pointer.move(event.pos, terminal_size)
        return True
    if (
        event.type == getattr(pygame_module, "MOUSEBUTTONDOWN", -1)
        and event.button == 1
    ):
        targeted = semantic_pointer.left_down(event.pos, terminal_size)
        if trace is not None:
            trace.mark(
                "manual_pointer_down",
                position=tuple(event.pos),
                semantic_target=_trace_control_identity(
                    semantic_pointer.pressed
                ),
                result="targeted" if targeted else "miss",
            )
        return True
    if (
        event.type == getattr(pygame_module, "MOUSEBUTTONUP", -1)
        and event.button == 1
    ):
        if trace is None:
            semantic_pointer.left_up(
                event.pos,
                terminal_size,
                modifiers=_pygame_apt_modifiers(pygame_module, event),
            )
            return True
        pressed = semantic_pointer.pressed
        pending_before = keyboard.pending_events
        error_before = keyboard.last_error
        request_count_before = getattr(
            keyboard.client,
            "request_count",
            None,
        )
        activated = semantic_pointer.left_up(
            event.pos,
            terminal_size,
            modifiers=_pygame_apt_modifiers(pygame_module, event),
        )
        released = semantic_pointer.hovered
        reason = None
        if not activated:
            if pressed is None:
                reason = "no_pressed_target"
            elif released is None:
                reason = "release_miss"
            elif released != pressed:
                reason = "release_target_changed"
            else:
                reason = "display_authority_changed"
            result = "not_activated"
        else:
            request_count_after = getattr(
                keyboard.client,
                "request_count",
                None,
            )
            if (
                request_count_before is not None
                and request_count_after is not None
                and request_count_after > request_count_before
            ):
                result = "rpc_submitted"
            elif keyboard.pending_events > pending_before:
                result = "queued"
            elif keyboard.last_error != error_before or keyboard.last_error:
                result = "locally_dropped"
                reason = keyboard.last_error
            else:
                result = "handled_without_rpc"
        trace.mark(
            "manual_pointer_up",
            position=tuple(event.pos),
            pressed_target=_trace_control_identity(pressed),
            semantic_target=_trace_control_identity(released),
            result=result,
            reason=reason,
            pending_events=keyboard.pending_events,
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


def _pointer_event_types(pygame_module) -> tuple[int, int, int]:
    """Return the complete physical-pointer event family used by the viewer."""

    return (
        pygame_module.MOUSEMOTION,
        pygame_module.MOUSEBUTTONDOWN,
        pygame_module.MOUSEBUTTONUP,
    )


def _isolate_scripted_pointer_input(pygame_module) -> None:
    """Keep host pointer traffic outside the scripted evidence journey."""

    event_types = _pointer_event_types(pygame_module)
    pygame_module.event.set_blocked(event_types)
    # set_mode may already have queued a synthetic initial motion event.
    pygame_module.event.clear(event_types)


def _pump_physical_viewer_events(
    pygame_module,
    semantic_pointer: _SemanticPointerInteractor,
    keyboard: _GuestKeyboardForwarder,
    terminal_size: tuple[int, int],
    *,
    closing_is_error: bool,
    trace: _PerformanceTrace | None = None,
    reject_pointer_input: bool = False,
) -> bool:
    """Process viewer events without discarding semantic pointer input."""

    if not isinstance(reject_pointer_input, bool):
        raise TypeError("reject_pointer_input must be bool")
    pointer_event_types = _pointer_event_types(pygame_module)
    for event in pygame_module.event.get():
        if event.type == pygame_module.QUIT:
            if closing_is_error:
                raise PhysicalDesktopAcceptanceError(
                    "physical acceptance window was closed"
                )
            return False
        if reject_pointer_input and event.type in pointer_event_types:
            raise PhysicalDesktopAcceptanceError(
                "scripted physical acceptance refuses manual pointer input"
            )
        _dispatch_semantic_pointer_event(
            pygame_module,
            semantic_pointer,
            keyboard,
            event,
            terminal_size,
            trace=trace,
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
        text_area_count=projection.text_area_count,
        text_grid_count=projection.text_grid_count,
        tabset_count=projection.tabset_count,
        collection_claim_identities=projection.collection_claim_identities,
        tab_identity_graphs=projection.tab_identity_graphs,
        selected_tab_identities=projection.selected_tab_identities,
        tab_signatures=projection.tab_signatures,
        selected_tab_labels=projection.selected_tab_labels,
        region_count=projection.region_count,
        instrument_region_count=projection.instrument_region_count,
        clipped_region_count=projection.clipped_region_count,
        instrument_cell_count=projection.instrument_cell_count,
        readout_count=projection.readout_count,
        meter_count=projection.meter_count,
        status_count=projection.status_count,
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
    cell_fallback: tuple[CellFallbackFrameEvidence, ...],
    *,
    manual_input_rpc_count: int,
) -> Path:
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    if (
        len(cell_fallback) != 2
        or any(
            not isinstance(snapshot, CellFallbackFrameEvidence)
            for snapshot in cell_fallback
        )
        or tuple(snapshot.boundary for snapshot in cell_fallback)
        != ("initial", "final")
    ):
        raise PhysicalDesktopAcceptanceError(
            "acceptance manifest requires exact initial and final CELL evidence"
        )
    if (
        isinstance(manual_input_rpc_count, bool)
        or not isinstance(manual_input_rpc_count, int)
        or manual_input_rpc_count != 0
    ):
        raise PhysicalDesktopAcceptanceError(
            "scripted acceptance manifest requires zero manual input RPCs"
        )
    manifest_path = artifact_root / "manifest.json"
    payload = {
        "video_driver": video_driver,
        "reference_sink_boundary": "pygame.display.flip",
        "acknowledged_evidence_viewport": {
            "origin": [0, 0],
            "extent": "recorded frame PNG dimensions",
            "host_mode_bar": "excluded",
        },
        "cell_fallback": {
            "required": True,
            "proof_source": "CELL snapshot carried by exact acknowledged offer",
            "snapshots": [snapshot.to_dict() for snapshot in cell_fallback],
        },
        "scripted_input_integrity": {
            "manual_pointer_input": "blocked_and_cleared_at_pygame_queue",
            "manual_input_rpc_count": manual_input_rpc_count,
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
    phase_profile: bool = False,
    phase_profile_max_events: int = GUEST_PHASE_PROFILE_DEFAULT_MAX_EVENTS,
) -> PhysicalDesktopAcceptanceEvidence:
    """Run and record the real Desk/Pad/Daybook reference-sink journey."""

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
    if not isinstance(phase_profile, bool):
        raise TypeError("phase_profile must be a boolean")
    _phase_profile_integer(
        phase_profile_max_events,
        "phase_profile_max_events",
        minimum=1,
        maximum=GUEST_PHASE_PROFILE_MAX_EVENTS,
    )
    artifact_root = Path(artifact_root).resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    trace = _PerformanceTrace(artifact_root)
    trace.mark(
        "acceptance_started",
        cols=cols,
        rows=rows,
        timeout_seconds=timeout,
        action_delay_seconds=action_delay,
        hold_seconds=hold_seconds,
        guest_phase_profile_requested=phase_profile,
        guest_phase_profile_max_events=phase_profile_max_events,
    )
    trace_outcome = "failure"
    last_status = None
    deadline = time.monotonic() + timeout
    client: SessionClient | None = None
    pygame_initialized = False
    phase_profile_attempted = False
    phase_profile_active = False
    phase_capture: dict[str, object] | None = None
    connect_started_ns = trace.now()
    try:
        client = _connect(socket_path, deadline, expected_server_pid)
        trace.mark("session_connected", started_ns=connect_started_ns)
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
        last_status = status
        generation = int(status["generation"])
        display_required = bool(status["rich_terminal"]["display_required"])
        trace.mark(
            "initial_status",
            status=status,
            generation=generation,
            display_required=display_required,
        )
        terminal = VirtualTerminal(cols=cols, rows=rows)
        revision = -1
        display_state = _RetainedDisplayState()
        manual_input_client = _ManualInputTraceClient(client, trace)
        keyboard = _GuestKeyboardForwarder(
            pygame,
            manual_input_client,
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
        _isolate_scripted_pointer_input(pygame)
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
        cell_fallback_evidence: dict[str, CellFallbackFrameEvidence] = {}
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
                trace=trace,
                reject_pointer_input=closing_is_error,
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
            _require_no_manual_scripted_input(manual_input_client)
            input_started_ns = trace.now()
            input_status, evidence = _request_acceptance_input(
                client,
                method,
                value,
                offer,
                input_generation,
                display_state=display_state,
                display_ack=keyboard.display_ack,
            )
            input_ended_ns = trace.now()
            if evidence is not None:
                inputs.append(evidence)
            trace.mark(
                "input_result",
                status=last_status,
                method=method,
                value_utf8_bytes=len(value.encode("utf-8")),
                authorizing_offer_id=offer.offer_id,
                generation=input_generation,
                journey_stage=journey.stage,
                result=input_status,
                rpc_duration_ns=max(input_ended_ns - input_started_ns, 0),
                counter_sample="latest_status_before_input",
            )
            return input_status

        while time.monotonic() < deadline:
            pump_events(True)
            _require_no_manual_scripted_input(manual_input_client)

            status = client.request("status", detailed=False)
            last_status = status
            pending_before_status = keyboard.pending_events
            generation_before_status = keyboard.generation
            display_required_before_status = keyboard.display_required
            revision, _ = _accept_status_update(
                status,
                keyboard=keyboard,
                display_state=display_state,
                revision=revision,
            )
            if keyboard.generation != generation_before_status:
                status_drop_reason = "status_generation_changed"
            elif keyboard.display_required != display_required_before_status:
                status_drop_reason = "display_requirement_changed"
            else:
                status_drop_reason = "status_context_changed"
            _trace_pending_input_drop(
                trace,
                keyboard,
                pending_before_status,
                reason=status_drop_reason,
                generation=keyboard.generation,
            )
            screen_started_ns = trace.now()
            update = client.request(
                "screen",
                since=revision,
                since_offer=display_state.since_offer,
            )
            screen_ended_ns = trace.now()
            pending_before_screen = keyboard.pending_events
            generation_before_screen = keyboard.generation
            revision, resized = _accept_screen_update(
                update,
                display_holder=True,
                terminal=terminal,
                keyboard=keyboard,
                display_state=display_state,
                revision=revision,
            )
            if keyboard.generation != generation_before_screen:
                screen_drop_reason = "screen_generation_changed"
            elif "display_offer" in update:
                screen_drop_reason = "new_display_offer"
            elif "snapshot" in update:
                screen_drop_reason = "cell_snapshot_replaced_display"
            else:
                screen_drop_reason = "screen_context_changed"
            _trace_pending_input_drop(
                trace,
                keyboard,
                pending_before_screen,
                reason=screen_drop_reason,
                offer_id=(
                    update["display_offer"].get("offer_id")
                    if isinstance(update.get("display_offer"), dict)
                    else None
                ),
            )
            cell_observation = _terminal_cell_observation(terminal)
            latest_cell_text = cell_observation.text
            cell_ready, cell_missing_markers = _marker_status(
                latest_cell_text,
                tuple(ready_markers),
            )
            guest_failure = _guest_boot_failure(
                cell_observation,
                pre_ready=not cell_ready,
            )
            if guest_failure is not None:
                raise PhysicalDesktopAcceptanceError(
                    _guest_failure_message(
                        client,
                        artifact_root,
                        guest_failure,
                    )
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
                _isolate_scripted_pointer_input(pygame)
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
            new_offer = (
                frame_offer is not None
                and frame_offer.offer_id != last_seen_offer_id
            )
            if new_offer:
                assert frame_offer is not None
                offers_seen += 1
                last_seen_offer_id = frame_offer.offer_id
                trace.mark(
                    "offer_observed",
                    status=status,
                    offer_id=frame_offer.offer_id,
                    generation=frame_generation,
                    scope=display_scope_to_wire(frame_offer.scope),
                    journey_stage=journey.stage,
                    screen_rpc_duration_ns=max(
                        screen_ended_ns - screen_started_ns,
                        0,
                    ),
                    counter_sample="status_before_screen",
                )
            projection_started_ns = (
                None if frame_offer is None else trace.now()
            )
            frame_projection = (
                None
                if frame_offer is None
                else reconstruct_retained_screen(frame_offer)
            )
            if frame_projection is not None:
                _require_canonical_desktop_geometry(frame_projection)
                trace.mark(
                    "projection_complete",
                    started_ns=projection_started_ns,
                    offer_id=frame_offer.offer_id,
                    draw_count=frame_projection.draw_count,
                    journey_stage=journey.stage,
                )
                if phase_profile and not phase_profile_attempted:
                    phase_profile_attempted = True
                    profile_started_ns = trace.now()
                    try:
                        phase_capture = _start_guest_phase_profile(
                            client,
                            max_events=phase_profile_max_events,
                            machine_generation=frame_generation,
                            first_offer_status=status,
                        )
                        phase_profile_active = True
                        observer_start = phase_capture["observer_start"]
                        trace.mark(
                            "guest_phase_profile_started",
                            started_ns=profile_started_ns,
                            offer_id=frame_offer.offer_id,
                            generation=frame_generation,
                            observer_started_steps=observer_start[
                                "started_steps"
                            ],
                            observer_started_batches=observer_start[
                                "started_batches"
                            ],
                        )
                    except Exception as exc:
                        unavailable = {
                            "requested": True,
                            "available": False,
                            "word": GUEST_PHASE_PROFILE_WORD,
                            "summary_available": False,
                            "profile_error": _phase_profile_error("start", exc),
                        }
                        trace.set_guest_phase_profile(unavailable)
                        trace.mark(
                            "guest_phase_profile_unavailable",
                            started_ns=profile_started_ns,
                            offer_id=frame_offer.offer_id,
                            generation=frame_generation,
                            error_type=type(exc).__name__,
                        )
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
            compose_duration_ns = None

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
                nonlocal composed_surface, compose_duration_ns
                window.fill((0, 0, 0))
                compose_started_ns = trace.now()
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
                compose_duration_ns = max(trace.now() - compose_started_ns, 0)
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

            presentation_started_ns = (
                None if frame_offer is None else trace.now()
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
                trace.mark(
                    "presentation_rejected",
                    started_ns=presentation_started_ns,
                    offer_id=frame_offer.offer_id,
                    compose_duration_ns=compose_duration_ns,
                    journey_stage=journey.stage,
                )
                revision = -1
                pending_before_rejection = keyboard.pending_events
                keyboard.clear_display_context(waiting=True)
                _trace_pending_input_drop(
                    trace,
                    keyboard,
                    pending_before_rejection,
                    reason="presentation_rejected",
                    offer_id=frame_offer.offer_id,
                )
                time.sleep(0.01)
                continue
            revision = accepted_revision
            pending_before_ack = keyboard.pending_events
            keyboard.acknowledge_display_offer(
                frame_offer.offer_id,
                frame_offer.scope,
            )
            _trace_pending_input_drop(
                trace,
                keyboard,
                pending_before_ack,
                reason="display_ack_changed",
                offer_id=frame_offer.offer_id,
            )
            trace.mark(
                "offer_acknowledged",
                started_ns=presentation_started_ns,
                offer_id=frame_offer.offer_id,
                generation=frame_generation,
                compose_duration_ns=compose_duration_ns,
                journey_stage=journey.stage,
                cell_ready=cell_ready,
                cell_text_sha256=hashlib.sha256(
                    latest_cell_text.encode("utf-8")
                ).hexdigest(),
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
            if journey.stage == 0:
                retained_ready, _ = _marker_status(
                    frame_projection.text,
                    tuple(ready_markers),
                )
                if retained_ready:
                    initial_cell = _require_cell_fallback_evidence(
                        "initial",
                        frame_offer,
                        frame_generation,
                        tuple(ready_markers),
                    )
                    cell_fallback_evidence["initial"] = initial_cell
                    trace.mark(
                        "cell_fallback_gate",
                        boundary="initial",
                        offer_id=frame_offer.offer_id,
                        generation=frame_generation,
                        scope=display_scope_to_wire(frame_offer.scope),
                        ready=True,
                        ready_markers=list(initial_cell.ready_markers),
                        cell_text_sha256=initial_cell.cell_text_sha256,
                        cell_utf8_bytes=initial_cell.cell_utf8_bytes,
                    )
            progress = journey.after_present(
                frame_offer,
                frame_generation,
                frame_projection,
                send_input,
            )
            if progress.complete:
                final_cell = _require_cell_fallback_evidence(
                    "final",
                    frame_offer,
                    frame_generation,
                    tuple(ready_markers) + CELL_FINAL_STATE_MARKERS,
                )
                if "initial" not in cell_fallback_evidence:
                    raise PhysicalDesktopAcceptanceError(
                        "final rich frame has no initial CELL fallback evidence"
                    )
                cell_fallback_evidence["final"] = final_cell
                _require_no_manual_scripted_input(manual_input_client)
                trace.mark(
                    "cell_fallback_gate",
                    boundary="final",
                    offer_id=frame_offer.offer_id,
                    generation=frame_generation,
                    scope=display_scope_to_wire(frame_offer.scope),
                    ready=True,
                    ready_markers=list(final_cell.ready_markers),
                    cell_text_sha256=final_cell.cell_text_sha256,
                    cell_utf8_bytes=final_cell.cell_utf8_bytes,
                )
            if progress.complete and phase_profile_active:
                profile_stopped_ns = trace.now()
                try:
                    window_end_steps = _phase_profile_integer(
                        (
                            last_status.get("steps")
                            if isinstance(last_status, dict)
                            else None
                        ),
                        "final pre-screen status steps",
                    )
                    if phase_capture is None:
                        raise ValueError("phase profile has no start capture")
                    profile_result = _finish_guest_phase_profile(
                        client,
                        phase_capture,
                        window_end_steps=window_end_steps,
                    )
                    phase_profile_active = profile_result.get("observer") is None
                    trace.set_guest_phase_profile(profile_result)
                    phase_summary = profile_result.get("phase_summary")
                    trace.mark(
                        "guest_phase_profile_stopped",
                        started_ns=profile_stopped_ns,
                        offer_id=frame_offer.offer_id,
                        generation=frame_generation,
                        window_end_steps=window_end_steps,
                        summary_available=profile_result.get(
                            "summary_available", False
                        ),
                        lifecycle_complete=(
                            phase_summary.get("lifecycle_complete")
                            if isinstance(phase_summary, dict)
                            else False
                        ),
                        attribution_complete=(
                            phase_summary.get("attribution_complete")
                            if isinstance(phase_summary, dict)
                            else False
                        ),
                    )
                except Exception as exc:
                    # This evidence is intentionally non-normative.  A host
                    # profiling defect must not reject a semantically valid
                    # physical Desk journey.
                    failed = dict(phase_capture or {})
                    failed.update(
                        {
                            "requested": True,
                            "available": bool(phase_capture),
                            "summary_available": False,
                            "profile_error": _phase_profile_error(
                                "finish", exc
                            ),
                        }
                    )
                    trace.set_guest_phase_profile(failed)
                    trace.mark(
                        "guest_phase_profile_incomplete",
                        started_ns=profile_stopped_ns,
                        offer_id=frame_offer.offer_id,
                        generation=frame_generation,
                        error_type=type(exc).__name__,
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
                artifact_started_ns = trace.now()
                recorded_frame = _record_frame(
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
                )
                _store_milestone_frame(
                    frames,
                    recorded_frame,
                )
                trace.mark(
                    "artifact_recorded",
                    started_ns=artifact_started_ns,
                    offer_id=frame_offer.offer_id,
                    milestone=progress.milestone,
                    journey_stage=journey.stage,
                )
            if progress.complete:
                manifest_started_ns = trace.now()
                manifest = write_acceptance_manifest(
                    artifact_root,
                    driver,
                    tuple(frames),
                    tuple(inputs),
                    (
                        cell_fallback_evidence["initial"],
                        cell_fallback_evidence["final"],
                    ),
                    manual_input_rpc_count=manual_input_client.request_count,
                )
                trace.mark(
                    "manifest_recorded",
                    started_ns=manifest_started_ns,
                    offer_id=frame_offer.offer_id,
                    journey_stage=journey.stage,
                )
                # The evidence boundary is complete.  Keep the post-pass window
                # visible for inspection, but make it view-only so late host
                # events cannot mutate the guest outside the recorded journey.
                keyboard.set_input_enabled(False)
                pygame.display.set_caption(
                    "Akashic rich-terminal acceptance — PASS "
                    f"({fitted_font_size}px)"
                )
                _keep_window_visible(
                    hold_seconds,
                    event_pump=pump_events,
                    closing_is_error=False,
                )
                trace_outcome = "pass"
                return PhysicalDesktopAcceptanceEvidence(
                    manifest,
                    driver,
                    tuple(frames),
                    tuple(inputs),
                    (
                        cell_fallback_evidence["initial"],
                        cell_fallback_evidence["final"],
                    ),
                )
            time.sleep(0.01)
        trace_outcome = "timeout"
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
        trace.mark("acceptance_failed", status=last_status, outcome=trace_outcome)
        raise
    except (ConnectionError, OSError, RuntimeError, TypeError, ValueError) as exc:
        trace.mark(
            "acceptance_failed",
            status=last_status,
            outcome=trace_outcome,
            error_type=type(exc).__name__,
        )
        raise PhysicalDesktopAcceptanceError(str(exc)) from exc
    finally:
        if phase_profile and phase_profile_active and client is not None:
            incomplete = dict(phase_capture or {})
            incomplete.update(
                {
                    "requested": True,
                    "available": bool(phase_capture),
                    "summary_available": False,
                    "phase_summary": None,
                    "incomplete_reason": (
                        "acceptance ended before the final measurement boundary"
                    ),
                }
            )
            try:
                incomplete["observer"] = client.request("stop_phase_profile")
            except Exception as exc:
                incomplete["observer"] = None
                incomplete["profile_error"] = _phase_profile_error(
                    "cleanup-stop", exc
                )
            trace.set_guest_phase_profile(incomplete)
            phase_profile_active = False
        elif (
            phase_profile
            and not phase_profile_attempted
            and trace.guest_phase_profile is None
        ):
            trace.set_guest_phase_profile(
                {
                    "requested": True,
                    "available": False,
                    "word": GUEST_PHASE_PROFILE_WORD,
                    "summary_available": False,
                    "phase_summary": None,
                    "incomplete_reason": (
                        "acceptance ended before the first retained offer"
                    ),
                }
            )
        trace.mark("acceptance_finished", status=last_status, outcome=trace_outcome)
        trace.write(trace_outcome)
        if client is not None:
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
