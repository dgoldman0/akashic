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
import re
import socket
import struct
import time
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path
from typing import Callable

from display import VirtualTerminal
from rich_terminal.font_set import FontSet, discover_fallback_fonts
from rich_terminal import text_rules
from rich_terminal.pygame_view import (
    ATTR_REVERSE,
    ControlHitTarget,
    FieldHitTarget,
    PixelRect,
    ControlIdentity,
    ItemHitTarget,
    ResidualPoint,
    TextHitTarget,
    TextPosition,
    _glyph_slots,
    _text_area_shift,
    composite_draw_plane,
)
from rich_terminal.retained_scene import ControlKind, ControlState, StatusSeverity
from rich_terminal.retained_wire import ControlEventKind
from rich_terminal.semantic_content import SemanticTextContent, SemanticTextState
from rich_terminal.semantic_items import (
    ItemState,
    ItemViewContent,
    ItemViewRole,
    ViewItem,
)
from rich_terminal.retained_view import (
    DisplayScope,
    GlyphRunDraw,
    FieldDraw,
    ItemViewDraw,
    MeterDraw,
    PaneDraw,
    MenuBarDraw,
    MenuDraw,
    MenuItemDraw,
    MenuSeparatorDraw,
    ReadoutDraw,
    RetainedRegionDraw,
    StatusDraw,
    StatusFieldDraw,
    TabSetDraw,
    TaskBarDraw,
    TextAreaDraw,
    TextGridDraw,
    WaveformDraw,
)
from rich_terminal.semantic_fields import FieldContent
from shared.session import TerminalDisplayOffer
from session_viewer import (
    _GuestKeyboardForwarder,
    _PointerRouter,
    _RetainedDisplayState,
    _accept_screen_update,
    _accept_status_update,
    _display_claimed,
    _pygame_apt_modifiers,
    compose_terminal_frame_changes,
    draw_flip_and_present,
)
from shared_session import SessionClient, display_scope_to_wire

import mixed_text
import styled_text


# A PT TEXT scalar advances through the ordinary shell once per event loop,
# and every accepted edit may produce a complete retained replacement.  One
# distinctive scalar is sufficient to prove a real mutation in each app
# without turning vertical acceptance into a full-frame cadence stress test.
PAD_ACCEPTANCE_TEXT = "~"
DAYBOOK_ACCEPTANCE_TASK = "^"
PAD_FOCUS_MARKER = "[1:Akashic Pa*]"
FEXPLORER_FOCUS_MARKER = "[2:File Explo*]"
DAYBOOK_FOCUS_MARKER = "[3:Daybook*]"
SOUNDLAB_FOCUS_MARKER = "[6:Sound Lab*]"
DAYBOOK_PROMPT_MARKER = "New task:"
DAYBOOK_SHARED_SOURCE_MARKER = "# Daybook"
FEXPLORER_TASKBAR_BUTTON = "[2:File Explo"
# The pointer journey scrolls File Explorer's detail table, selects this
# file's row, and opens it in Pad through item events, and then scrolls,
# places the caret, and selects in Pad with the mouse alone.  The canonical Desktop image carries the 48-line fixture,
# which is longer than Pad's viewport and sorts below the list's third row.
# Loading text puts the caret at its end, so the preview and Pad both open
# showing the fixture's last lines.
POINTER_LIST_FILE = "large.txt"
POINTER_LIST_PATH = "/large.txt"
POINTER_FILE_MARKER = "Large fixture line"
# One wheel detent is one ordinary wheel step: three list rows or text lines.
POINTER_WHEEL_ROWS = 3
# After Pad scrolls up, the caret is placed and the selection made on the
# view's sixth row.  Fixture lines read "Large fixture line NNN: ...", so
# scalar offsets 6 and 13 bound the word "fixture".
POINTER_TARGET_VIEW_ROW = 5
POINTER_PLACE_OFFSET = 6
POINTER_EXTEND_OFFSET = 13
# With the fixture's row selected, F2 opens File Explorer's rename prompt
# holding its name.  A drag across the name's stem selects exactly that stem,
# typing replaces it, and Escape cancels without renaming anything.
RENAME_PROMPT_LABEL = "Rename:"
RENAME_STEM, RENAME_SUFFIX = POINTER_LIST_FILE.split(".", 1)
RENAME_REPLACEMENT = "notes"
# Pad's status bar shows its caret as "Ln L, Col C": L is the caret's item
# key (its line plus one) and C the characters before it plus one.  The readout must
# change in the same frame as the caret, whether the mouse or a key moved it.
_PAD_READOUT_PATTERN = re.compile(r"Ln (\d+), Col (\d+)")
# One wheel step over Daybook's calendar moves its date one week.
DAYBOOK_WHEEL_DAYS = 7
# The journey ends in Pad, which has just followed a Markdown link.
CELL_FINAL_STATIC_MARKERS = (
    PAD_FOCUS_MARKER,
    "SOUND LAB",
)
# Pad's Open prompt, which Ctrl+O shows in its tile.
PAD_OPEN_PROMPT_MARKER = "Open:"
_ISO_DATE_PATTERN = re.compile(r"(?<!\d)\d{4}-\d{2}-\d{2}(?!\d)")
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
FEXPLORER_MENU_SIGNATURE = ("File", "Edit", "View", "Tools")
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
    FEXPLORER_MENU_SIGNATURE,
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
DESKTOP_ACCEPTANCE_PAD_TAB_STAGE = 11
DESKTOP_ACCEPTANCE_LAUNCHER_OPEN_STAGE = 12
DESKTOP_ACCEPTANCE_LAUNCHER_END_STAGE = 13
DESKTOP_ACCEPTANCE_SOUNDLAB_SELECTED_STAGE = 14
# Sound Lab's instruments are live at stage 15.  Stages 16-21 then open and
# close File Explorer's View and Daybook's Go menus through their acknowledged
# hit maps; stage 22 restores Sound Lab focus with all exercised state intact.
DESKTOP_ACCEPTANCE_SOUNDLAB_LIVE_STAGE = 15
# Stage 22 proves Sound Lab and the exercised state after the ordinary menus,
# then the pointer journey drives Desk, File Explorer, and Pad by mouse:
# File Explorer's detail table through item events and its rename prompt
# (23-29), Pad's editor and caret
# readout (30-34), and Daybook's calendar wheel (35).  Then typed text that
# mixes scripts goes into Pad (36-41) and a Daybook task (42-47).  Last, Pad
# opens a Markdown file, highlighted, and follows its link (48-52).
DESKTOP_ACCEPTANCE_POINTER_STAGE = 22
DESKTOP_ACCEPTANCE_FEXPLORER_CLICKED_STAGE = 23
DESKTOP_ACCEPTANCE_LIST_WHEEL_STAGE = 24
DESKTOP_ACCEPTANCE_LIST_ROW_STAGE = 25
DESKTOP_ACCEPTANCE_RENAME_PROMPT_STAGE = 26
DESKTOP_ACCEPTANCE_RENAME_DRAGGED_STAGE = 27
DESKTOP_ACCEPTANCE_RENAME_TYPED_STAGE = 28
DESKTOP_ACCEPTANCE_RENAME_CANCELLED_STAGE = 29
DESKTOP_ACCEPTANCE_PAD_OPENED_STAGE = 30
DESKTOP_ACCEPTANCE_PAD_WHEEL_STAGE = 31
DESKTOP_ACCEPTANCE_PAD_PLACE_STAGE = 32
DESKTOP_ACCEPTANCE_PAD_EXTEND_STAGE = 33
DESKTOP_ACCEPTANCE_PAD_KEY_STAGE = 34
DESKTOP_ACCEPTANCE_DAYBOOK_WHEEL_STAGE = 35
# Pad: End and Enter open a line after the selected one (36-37), typing
# fills it (38), a click lands on the combined accent (39), Right moves over
# both its scalars (40), and a click lands inside the Hebrew word (41).
DESKTOP_ACCEPTANCE_MIXED_LINE_END_STAGE = 36
DESKTOP_ACCEPTANCE_MIXED_LINE_OPENED_STAGE = 37
DESKTOP_ACCEPTANCE_MIXED_TYPED_STAGE = 38
DESKTOP_ACCEPTANCE_MIXED_CLUSTER_PLACED_STAGE = 39
DESKTOP_ACCEPTANCE_MIXED_CLUSTER_RIGHT_STAGE = 40
DESKTOP_ACCEPTANCE_MIXED_HEBREW_PLACED_STAGE = 41
# Daybook: focus and its task prompt (42-43), typing a task (44), a click on
# a Han character's second cell (45), one character typed there (46), and
# Enter adds the task (47).
DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_FOCUS_STAGE = 42
DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_PROMPT_STAGE = 43
DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_TYPED_STAGE = 44
DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_CLICKED_STAGE = 45
DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_INSERTED_STAGE = 46
DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_ADDED_STAGE = 47
# Pad: Alt+1 focuses it (48), Ctrl+O opens its prompt (49), the notes path is
# typed (50) and entered (51), and notes.md's style runs are checked before a
# FOLLOW on its link opens example.f with its own runs (52).
DESKTOP_ACCEPTANCE_STYLED_FOCUS_STAGE = 48
DESKTOP_ACCEPTANCE_STYLED_PROMPT_STAGE = 49
DESKTOP_ACCEPTANCE_STYLED_PATH_STAGE = 50
DESKTOP_ACCEPTANCE_STYLED_NOTES_STAGE = 51
DESKTOP_ACCEPTANCE_FINAL_STAGE = 52
DESKTOP_TILE_COLUMNS = 3
DESKTOP_TILE_ROWS = 2
PAD_DESKTOP_TILE = 0
FEXPLORER_DESKTOP_TILE = 1
DAYBOOK_DESKTOP_TILE = 2
SOUNDLAB_DESKTOP_TILE = 5
DAYBOOK_DATE_HEADER_ROW_OFFSET = 1
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
    "_A1D-FAILURE-SESSION-A",
    "_A1D-FAILURE-MS",
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
    "_RTHP-DIAG-DELTA-REFUSALS",
    "_RSHSP-DIAG-PROBE-REFUSALS",
    "_RSHSP-DIAG-REFUSALS",
    "_RSHSP-DIAG-PREPARED",
    "_RSHSP-DIAG-STAGE",
    "_RSHSP-DIAG-FAMILY",
    "_RSHSP-DIAG-STATUS",
)

_GUEST_FAILURE_RECORDS = {
    "pt_session": (
        "_A1D-FAILURE-SESSION-A",
        124,
        {
            "state": 15,
            "deadline": 16,
            "session_id": 19,
            "tx_sequence": 31,
            "rx_sequence": 32,
            "epoch": 33,
            "next_txid": 34,
            "revision": 35,
            "tx_open": 37,
            "txid": 39,
            "spans": 40,
            "cells": 41,
            "spans_done": 42,
            "cells_done": 43,
            "tx_bytes": 47,
            "await": 48,
            "await_txid": 49,
            "close_reason": 51,
            "retained_state": 57,
            "tx_kind": 77,
            "cell_mode": 78,
            "retained_mode": 79,
            "retained_ops": 80,
            "retained_ops_done": 81,
            "retained_bytes": 82,
            "retained_bytes_done": 83,
            "completion_status": 98,
            "completion_detail": 99,
            "completion_txid": 100,
            "completion_revision": 101,
            "close_pending": 109,
        },
    ),
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
        517,
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
            "target_active_address": 298,
            "target_pending_address": 299,
            "next_region": 300,
            "next_object": 301,
            "active_draw": 302,
            "max_documents": 303,
            "source_directory_bytes": 306,
            "document_count": 307,
            "row_damage_address": 308,
            "row_damage_bytes": 309,
            "glyph_id_map_address": 310,
            "glyph_id_map_bytes": 311,
            "delta_plan_valid": 312,
            "delta_plan_active_address": 313,
            "delta_plan_pending_address": 314,
            "delta_plan_active_draw": 315,
            "delta_plan_pending_draw": 316,
            "delta_plan_control_count": 317,
            "delta_plan_glyph_count": 318,
            "delta_plan_attempt": 319,
            "delta_plan_source_generation": 320,
            "delta_plan_pending_content": 321,
            "delta_plan_active_content": 322,
            "source_content_epoch": 323,
            "max_collection_native": 324,
            "max_collections": 325,
            "max_controls": 326,
            "source_menu_text_bytes": 327,
            "collection_descriptor_bytes": 330,
            "collection_native_bytes": 333,
            "source_collection_count": 334,
            "menu_control_count": 335,
            "collection_count": 336,
            "collection_items": 337,
            "collection_utf8": 338,
            "max_collection_descriptors": 339,
            "max_data_graphics_native": 395,
            "max_data_graphics_descriptors": 396,
            "max_instrument_regions": 397,
            "max_instruments": 398,
            "data_graphics_descriptor_bytes": 401,
            "data_graphics_native_bytes": 404,
            "source_data_graphics_count": 405,
            "instrument_unit_bytes": 412,
            "instrument_region_count": 415,
            "instrument_count": 416,
            "instrument_claim_count": 419,
            "base_claim_bytes": 420,
            "menu_claim_count": 421,
            "active_facts_bank": 422,
            "pending_facts_bank": 428,
            "refused_draw": 437,
            "max_status_native": 438,
            "max_statics": 439,
            "status_descriptor_bytes": 442,
            "status_native_bytes": 445,
            "static_text_bytes": 450,
            "static_count": 453,
            "static_last": 454,
            "static_base_claim_bytes": 455,
            "max_field_native": 474,
            "max_fields": 475,
            "field_descriptor_bytes": 478,
            "field_native_bytes": 481,
            "field_count": 482,
            "field_items": 483,
            "field_utf8": 484,
            "field_refused": 488,
            "max_series": 489,
            "series_address": 490,
            "series_bytes": 491,
            "series_samples_address": 492,
            "series_samples_bytes": 493,
            "series_samples_used": 494,
            "series_count": 497,
            "series_last": 498,
            "series_slots": 499,
            "series_chunks": 500,
            "series_history_max": 501,
            "series_chunk_max": 502,
            "series_chunk_bytes_max": 503,
            "waveform_count": 504,
            "first_series": 505,
            "next_series": 506,
            "omitted_graphs_used": 509,
            "extension_address": 516,
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
            "presents_committed": _performance_counter_map(
                rich.get("presents_committed")
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
    # The emulator samples after exact instruction batches.  The simulator
    # samples at semantic boundaries, which have no fixed size, and reports
    # None; each transition still carries the exact interval it was seen in.
    batch_step_bound = (
        None
        if observer.get("batch_step_bound") is None
        else _phase_profile_integer(
            observer.get("batch_step_bound"),
            "phase observer batch step bound",
            minimum=1,
        )
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
        if batch_step_bound is not None and upper - lower > batch_step_bound:
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
    # Each style run as (item key, start, length, meaning).
    style_runs: tuple[tuple[int, int, int, int], ...] = ()

    @property
    def control_id(self) -> int:
        return self.identity.control_id


_SemanticBounds = tuple[int, int, int, int]


@dataclass(frozen=True)
class _SemanticItemViewClaim:
    """One real retained ITEM_VIEW root in logical-screen coordinates, with
    the complete item view it carried."""

    identity: ControlIdentity
    left: int
    top: int
    right: int
    bottom: int
    content: ItemViewContent
    state: ControlState = ControlState.VISIBLE | ControlState.ENABLED

    @property
    def control_id(self) -> int:
        return self.identity.control_id

    def named(self, text: str) -> ViewItem | None:
        """The carried item whose first field reads TEXT, if exactly one."""

        found = [item for item in self.content.items if item.fields[0].text == text]
        return found[0] if len(found) == 1 else None

    @property
    def selected(self) -> ViewItem | None:
        found = [
            item for item in self.content.items if item.state & ItemState.SELECTED
        ]
        return found[0] if found else None

    def value(self, *fields: int) -> str:
        """A journey input value naming this root, then FIELDS."""

        identity = self.identity
        return ",".join(
            str(value)
            for value in (
                identity.owner_id,
                identity.owner_generation,
                identity.control_id,
                *fields,
            )
        )


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
class _SemanticStatusFieldClaim:
    """Exact retained STATUS_FIELD state and guest-assigned logical slots.

    Label and value are authored state, not proof that every character fits
    the renderer's clipped font pixels. They never enter projection.text.
    """

    owner_id: int
    owner_generation: int
    object_id: int
    left: int
    top: int
    right: int
    bottom: int
    label_cols: int
    label: str
    value: str
    severity: StatusSeverity
    emphasized: bool

    @property
    def label_bounds(self) -> tuple[int, int, int, int]:
        return self.left, self.top, self.left + self.label_cols, self.bottom

    @property
    def value_bounds(self) -> tuple[int, int, int, int]:
        return self.left + self.label_cols, self.top, self.right, self.bottom


@dataclass(frozen=True)
class _SemanticFieldClaim:
    """Committed FIELD state and slots, without clipped-text visibility inference."""

    identity: ControlIdentity
    left: int
    top: int
    right: int
    bottom: int
    label: str
    state: ControlState
    content: FieldContent

    @property
    def label_bounds(self) -> tuple[int, int, int, int] | None:
        bounds = self.content.label_bounds
        if bounds.empty:
            return None
        return (self.left + bounds.x, self.top + bounds.y,
                self.left + bounds.right, self.top + bounds.bottom)

    @property
    def value_bounds(self) -> tuple[int, int, int, int]:
        bounds = self.content.value_bounds
        return (self.left + bounds.x, self.top + bounds.y,
                self.left + bounds.right, self.top + bounds.bottom)

    @property
    def content_revision(self) -> int:
        return self.content.content_revision


@dataclass(frozen=True)
class _SemanticPaneClaim:
    owner_id: int
    owner_generation: int
    object_id: int
    region_id: int
    content_region_id: int
    bounds: _LogicalRectangle
    content_bounds: _LogicalRectangle
    title: str
    focused: bool


@dataclass(frozen=True)
class _SemanticTaskClaim:
    identity: ControlIdentity
    kind: ControlKind
    state: ControlState
    order: int
    bounds: _LogicalRectangle
    label: str
    shortcut: str


@dataclass(frozen=True)
class _SemanticTaskBarClaim:
    identity: ControlIdentity
    state: ControlState
    bounds: _LogicalRectangle
    tasks: tuple[_SemanticTaskClaim, ...]


@dataclass(frozen=True)
class RichScreenProjection:
    """Validated logical text reconstructed only from retained draw values.

    ``lines`` is each row's text as the CELL snapshot joins it: a character
    in its lead cell and nothing in a wide character's continuation, so its
    string offsets are columns only before a row's first wide or
    multi-scalar character.  ``cells`` keeps each cell's own text, and
    ``row_text`` and ``find_cells`` count true columns.  A projection built
    from plain lines has one scalar per cell.
    """

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
    semantic_item_view_claims: tuple[_SemanticItemViewClaim, ...] = ()
    region_count: int = 0
    instrument_region_count: int = 0
    clipped_region_count: int = 0
    instrument_cell_count: int = 0
    instrument_claims: tuple[_InstrumentClaim, ...] = ()
    semantic_status_field_claims: tuple[_SemanticStatusFieldClaim, ...] = ()
    semantic_field_claims: tuple[_SemanticFieldClaim, ...] = ()
    cells: tuple[tuple[str, ...], ...] = ()
    semantic_pane_claims: tuple[_SemanticPaneClaim, ...] = ()
    semantic_taskbar_claims: tuple[_SemanticTaskBarClaim, ...] = ()

    def _row_cells(self, row: int) -> tuple[str, ...]:
        if self.cells:
            return self.cells[row] if 0 <= row < len(self.cells) else ()
        return tuple(self.lines[row]) if 0 <= row < len(self.lines) else ()

    def row_text(self, row: int, start: int = 0, end: int | None = None) -> str:
        """The text of the characters whose lead cells lie in columns START
        to END of ROW."""

        return "".join(self._row_cells(row)[start:end])

    def cell_line(self, row: int) -> str:
        """ROW with one character per cell, for fixed-column checks: a cell's
        text when it is one scalar, else U+FFFD, so string offsets are
        columns."""

        return "".join(
            text if len(text) == 1 else "\ufffd" for text in self._row_cells(row)
        )

    def find_cells(
        self, needle: str, row: int, start: int = 0, end: int | None = None
    ) -> list[int]:
        """Each column of ROW, from START to END, whose cell begins NEEDLE."""

        columns: list[int] = []
        text: list[str] = []
        cells = self._row_cells(row)
        stop = len(cells) if end is None else min(end, len(cells))
        for column in range(max(start, 0), stop):
            for _ in cells[column]:
                columns.append(column)
            text.append(cells[column])
        joined = "".join(text)
        found = []
        offset = joined.find(needle)
        while offset >= 0:
            found.append(columns[offset])
            offset = joined.find(needle, offset + 1)
        return found

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
    def waveform_count(self) -> int:
        return sum(claim.kind == "WAVEFORM" for claim in self.instrument_claims)

    @property
    def status_field_count(self) -> int:
        return len(self.semantic_status_field_claims)

    @property
    def field_count(self) -> int:
        return len(self.semantic_field_claims)

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


# This is a binding to the canonical acceptance fixture, not a parser for
# application names. The task's typed presence replaces the old residual
# taskbar marker; neither its label nor a PANE title becomes visible text.
_DESKTOP_TASK_READINESS_TITLES = frozenset({"Grid"})


def _desktop_task_selected(title: str, label: str) -> bool | None:
    """Whether LABEL is Desk's taskbar label for TITLE, and if it is selected.

    Desk writes "[<slot>:<title>]", with "*" before the bracket when focused.
    The slot number follows launch order, so any positive one is accepted.
    """
    match = re.fullmatch(rf"\[[1-9][0-9]*:{re.escape(title)}(\*?)\]", label)
    return None if match is None else bool(match.group(1))


def _projection_marker_status(
    projection: RichScreenProjection,
    ready_markers: tuple[str, ...],
) -> tuple[bool, tuple[str, ...]]:
    """Readiness from existing text or one exact enabled canonical TASK.

    Semantic task presence is readiness evidence, independent of whether the
    task label's font pixels fit its slot. It never modifies projection.text.
    Mandatory initial/final CELL fallback still uses _marker_status directly.
    """
    missing = []
    required = ControlState.VISIBLE | ControlState.ENABLED
    for marker in ready_markers:
        if marker in projection.text:
            continue
        if marker not in _DESKTOP_TASK_READINESS_TITLES:
            missing.append(marker)
            continue
        matches = [(bar, task, selected) for bar in projection.semantic_taskbar_claims
                   for task in bar.tasks if task.kind is ControlKind.TASK
                   and (selected := _desktop_task_selected(marker, task.label)) is not None]
        if len(matches) != 1:
            missing.append(marker)
            continue
        bar, task, selected = matches[0]
        b, t = bar.bounds, task.bounds
        if not (bar.state & required == required and task.state & required == required and
                not task.state & ControlState.MINIMIZED and
                bool(task.state & ControlState.SELECTED) == selected and
                b.top == t.top == projection.rows - 1 and b.bottom == t.bottom == projection.rows and
                0 <= b.left <= t.left < t.right <= b.right <= projection.cols and
                t.right - t.left == text_rules.string_width(task.label)):
            missing.append(marker)
    return not missing, tuple(missing)


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

    if boundary not in ("initial", "final", "field-prompt", "series-prompt"):
        raise ValueError("unknown CELL fallback boundary")
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


def _desktop_pane_content_bounds(
    projection: RichScreenProjection,
    tile: int,
) -> tuple[int, int, int, int]:
    """Exact canonical Desk child geometry, excluding owned divider cells.

    Desk's _DESK-TILE-SIZES reserves one cell between columns and rows;
    _DESK-ASSIGN-TILE assigns division remainders to the last column/row.
    The broad proportional tile gates above are insufficient for a status
    row or another exact slot boundary.
    """

    _desktop_tile_bounds(projection, tile)  # canonical tile validation
    col, row = tile % DESKTOP_TILE_COLUMNS, tile // DESKTOP_TILE_COLUMNS
    content_height = projection.rows - 1
    width = (projection.cols - (DESKTOP_TILE_COLUMNS - 1)) // DESKTOP_TILE_COLUMNS
    height = (content_height - (DESKTOP_TILE_ROWS - 1)) // DESKTOP_TILE_ROWS
    left, top = col * (width + 1), row * (height + 1)
    right = projection.cols if col == DESKTOP_TILE_COLUMNS - 1 else left + width
    bottom = content_height if row == DESKTOP_TILE_ROWS - 1 else top + height
    return left, top, right, bottom


def _menu_body_status_bounds(
    bounds: tuple[int, int, int, int],
) -> tuple[int, int, int, int]:
    """Current ordinary UIDL menu/body/status stack's exact status row.

    _UTUI-LAYOUT-STACK allocates the expandable body after subtracting both
    leaf rows and the preceding menu's row. The following status therefore
    sits two rows before the pane's exclusive bottom, leaving the last row
    unused. Preserve that authored layout; a broad tile's bottom is no proof.
    """

    left, _top, right, bottom = bounds
    return left, bottom - 2, right, bottom - 1


def _desk_content_bounds(
    projection: RichScreenProjection,
) -> tuple[int, int, int, int]:
    """The Desk's whole content area above the taskbar, which is the one
    tile of a Desk holding a single applet."""

    return 0, 0, projection.cols, max(1, projection.rows - 1)


def _residual_contains(
    projection: RichScreenProjection,
    marker: str,
    bounds: tuple[int, int, int, int],
) -> bool:
    """Find text supplied specifically by retained residual glyphs in BOUNDS."""

    if not isinstance(marker, str) or not marker:
        raise ValueError("marker must be a nonempty string")
    left, top, right, bottom = bounds
    return any(
        marker in projection.row_text(row, left, right)
        for row in range(top, bottom)
    )


def _residual_tile_contains(
    projection: RichScreenProjection,
    marker: str,
    tile: int,
) -> bool:
    """Find text supplied specifically by retained residual glyphs in a tile."""

    return _residual_contains(
        projection, marker, _desktop_tile_bounds(projection, tile)
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
    ) or _item_view_text_in_tile(projection, marker, tile)


def _fexplorer_selected_path_is(
    projection: RichScreenProjection,
    expected: str,
) -> bool:
    """Observe the selected path through visible legacy text or typed status.

    STATUS_FIELD's exact value proves authored selection state, not that the
    complete path is physically readable inside its clipped value slot.
    Only File Explorer's authored status row and an empty-label value qualify.
    """

    if _desktop_tile_contains(projection, expected, FEXPLORER_DESKTOP_TILE):
        return True
    bounds = _desktop_pane_content_bounds(projection, FEXPLORER_DESKTOP_TILE)
    return any(
        claim.label_cols == 0 and not claim.label and claim.value == expected
        for claim in _status_field_claims_in(projection, _menu_body_status_bounds(bounds))
    )


def _item_view_text_in_tile(
    projection: RichScreenProjection,
    marker: str,
    tile: int,
) -> bool:
    """Find text in a field of an item an ITEM_VIEW root in a tile shows."""

    return any(
        marker in field.text
        for claim in _item_view_claims_in_tile(projection, tile)
        for item in claim.content.items
        if _item_shown(claim, item)
        for field in item.fields
    )


def _text_cell_in(
    projection: RichScreenProjection,
    marker: str,
    bounds: tuple[int, int, int, int],
    where: str,
) -> tuple[int, int] | None:
    """Return the (column, row) of marker's only residual copy in BOUNDS,
    which WHERE names for errors."""

    if not isinstance(marker, str) or not marker:
        raise ValueError("marker must be a nonempty string")
    left, top, right, bottom = bounds
    cells = [
        (column, row)
        for row in range(top, min(bottom, len(projection.lines)))
        for column in projection.find_cells(marker, row, left, right)
    ]
    if len(cells) > 1:
        raise PhysicalDesktopAcceptanceError(f"{marker!r} is not unique in {where}")
    return cells[0] if cells else None


def _tile_text_cell(
    projection: RichScreenProjection,
    marker: str,
    tile: int,
) -> tuple[int, int] | None:
    """Return the (column, row) of marker's only residual copy in one tile."""

    return _text_cell_in(
        projection,
        marker,
        _desktop_tile_bounds(projection, tile),
        f"Desk tile {tile}",
    )


def _taskbar_has_focus(projection: RichScreenProjection, marker: str, *, legacy_row=False) -> bool:
    """Known journey label plus typed focus state, or the complete legacy row."""
    if projection.semantic_taskbar_claims:
        matches = [(bar, task) for bar in projection.semantic_taskbar_claims
                   for task in bar.tasks if task.kind is ControlKind.TASK and
                   task.label == marker and task.bounds.top == projection.rows - 1]
        if len(matches) != 1:
            return False
        bar, task = matches[0]
        required = ControlState.VISIBLE | ControlState.ENABLED | ControlState.SELECTED
        return bool(bar.state & ControlState.ENABLED and
                    task.state & required == required and
                    not task.state & ControlState.MINIMIZED)
    legacy = projection.row_text(projection.rows - 1) if legacy_row else projection.text
    return marker in legacy


def _taskbar_button_cell(
    projection: RichScreenProjection,
    button: str,
) -> tuple[int, int]:
    """Return an exact authored slot, or one legacy residual label position."""

    if projection.semantic_taskbar_claims:
        matches = [task for bar in projection.semantic_taskbar_claims
                   if bar.state & ControlState.ENABLED for task in bar.tasks
                   if task.kind is ControlKind.TASK and task.state & ControlState.ENABLED
                   and task.label.startswith(button) and task.bounds.top == projection.rows - 1]
        if len(matches) != 1:
            raise PhysicalDesktopAcceptanceError(
                f"semantic taskbar does not show exactly one enabled {button!r} task")
        bounds = matches[0].bounds
        return bounds.left + (bounds.right - bounds.left) // 2, bounds.top

    row = CANONICAL_DESKTOP_ROWS - 1
    found = projection.find_cells(button, row)
    if len(found) != 1:
        raise PhysicalDesktopAcceptanceError(
            f"taskbar does not show exactly one {button!r} button"
        )
    return found[0] + 1, row


@dataclass(frozen=True)
class _TextAreaPointerState:
    """The viewport, caret, and anchor fields of one TEXT_AREA STX1 value."""

    viewport_row: int
    viewport_rows: int
    primary: tuple[int, int]
    anchor: tuple[int, int]


def _text_area_pointer_state(
    claim: _SemanticCollectionClaim,
) -> _TextAreaPointerState:
    """Read one claim's state in _semantic_text_content_state's field order.

    An anchor of (0, 0) means no selection; keys are line numbers plus one.
    """

    (
        _rows,
        _columns,
        viewport_row,
        _viewport_column,
        viewport_rows,
        _viewport_columns,
        _flags,
        primary_key,
        primary_offset,
        anchor_key,
        anchor_offset,
        _items,
    ) = claim.content_state
    return _TextAreaPointerState(
        viewport_row,
        viewport_rows,
        (primary_key, primary_offset),
        (anchor_key, anchor_offset),
    )


def _caret_in_view(state: _TextAreaPointerState) -> bool:
    """Is the caret's line (its key minus one) inside the viewport rows?"""

    line = state.primary[0] - 1
    return state.viewport_row <= line < state.viewport_row + state.viewport_rows


def _pad_pointer_text_area(
    projection: RichScreenProjection,
    bounds: _SemanticBounds | None = None,
) -> _SemanticCollectionClaim | None:
    """Return Pad's one available editor root showing the pointer fixture."""

    claims = tuple(
        claim
        for claim in _collection_claims_containing(
            projection,
            ControlKind.TEXT_AREA,
            PAD_DESKTOP_TILE,
            POINTER_FILE_MARKER,
        )
        if bounds is None
        or (claim.left, claim.top, claim.right, claim.bottom) == bounds
    )
    if len(claims) > 1:
        raise PhysicalDesktopAcceptanceError(
            "Pad pointer fixture is ambiguous across multiple TEXT_AREA roots"
        )
    return claims[0] if claims else None


def _pad_caret_readout(
    projection: RichScreenProjection,
    bounds: tuple[int, int, int, int] | None = None,
) -> tuple[int, int] | None:
    """Return Pad's one acknowledged caret readout state.

    Residual cells supply visible text. A typed field in the exact authored
    status row supplies semantic state, not a claim of unclipped font text.
    """

    left, top, right, bottom = (
        _desktop_pane_content_bounds(projection, PAD_DESKTOP_TILE)
        if bounds is None
        else bounds
    )
    found = [
        (int(match.group(1)), int(match.group(2)))
        for row in range(top, bottom)
        for match in _PAD_READOUT_PATTERN.finditer(projection.row_text(row, left, right))
    ]
    for claim in _status_field_claims_in(
        projection, _menu_body_status_bounds((left, top, right, bottom)),
    ):
        if claim.label or claim.label_cols:
            continue
        match = _PAD_READOUT_PATTERN.fullmatch(claim.value)
        if match is not None:
            found.append((int(match.group(1)), int(match.group(2))))
    if len(found) > 1:
        raise PhysicalDesktopAcceptanceError(
            "Pad's tile shows more than one caret readout"
        )
    return found[0] if found else None


def _claim_item_text(claim: _SemanticCollectionClaim, key: int) -> str | None:
    """The text of one claim's carried item KEY, or None."""

    for item in claim.content_state[-1]:
        if item[0] == key:
            return item[-1]
    return None


def _claim_item_runs(
    claim: _SemanticCollectionClaim, key: int
) -> list[tuple[int, int, int]]:
    """The style runs (start, length, meaning) of one claim's item KEY."""

    return [
        (start, length, meaning)
        for item_key, start, length, meaning in claim.style_runs
        if item_key == key
    ]


def _require_pad_readout(
    projection: RichScreenProjection,
    claim: _SemanticCollectionClaim,
    bounds: tuple[int, int, int, int] | None = None,
) -> None:
    """Require Pad's readout to name the caret in the frame that moved it:
    its line's key and the characters before it, plus one."""

    state = _text_area_pointer_state(claim)
    key, offset = state.primary
    before = (_claim_item_text(claim, key) or "")[:offset]
    expected = (key, len(text_rules.characters(before, keep_tab=True)) + 1)
    observed = _pad_caret_readout(projection, bounds)
    if observed != expected:
        raise PhysicalDesktopAcceptanceError(
            f"Pad's Ln/Col readout {observed!r} did not follow its caret "
            f"{expected!r} in the same frame"
        )


def _prompt_row_text(
    projection: RichScreenProjection,
    cell: tuple[int, int],
    tile: int,
) -> str:
    """Return a prompt's text from its label's cell to the tile's edge."""

    column, row = cell
    left, top, right, bottom = _desktop_pane_content_bounds(projection, tile)
    if not (left <= column < right and top <= row < bottom):
        return ""
    if row >= len(projection.lines):
        return ""
    return projection.row_text(row, column, right).rstrip()


def _daybook_dates(projection: RichScreenProjection) -> tuple[str, ...]:
    """Return valid ISO dates in Daybook's selected-date agenda header."""

    left, top, right, bottom = _desktop_tile_bounds(
        projection,
        DAYBOOK_DESKTOP_TILE,
    )
    header_row = top + DAYBOOK_DATE_HEADER_ROW_OFFSET
    if not top <= header_row < bottom:
        return ()
    # Daybook paints this ordinary agenda header immediately below its menu.
    # Restricting the evidence to that stable slot prevents ISO-looking task
    # text elsewhere in the tile from becoming accidental acceptance policy.
    segment = projection.row_text(header_row, left, right)
    candidates = set()
    for match in _ISO_DATE_PATTERN.findall(segment):
        try:
            parsed = date.fromisoformat(match)
        except ValueError:
            continue
        if parsed.isoformat() == match:
            candidates.add(match)
    return tuple(sorted(candidates))


def _require_daybook_date(projection: RichScreenProjection) -> str:
    """Require one unambiguous calendar date in the acknowledged Daybook tile."""

    dates = _daybook_dates(projection)
    if len(dates) != 1:
        raise PhysicalDesktopAcceptanceError(
            "acknowledged Daybook tile does not contain exactly one valid "
            f"ISO calendar date: dates={dates!r}"
        )
    return dates[0]


def _iso_date_after(value: str, days: int) -> str:
    """Return the calendar day some days after one canonical ISO date."""

    try:
        parsed = date.fromisoformat(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("value must be a valid canonical ISO date") from exc
    if parsed.isoformat() != value:
        raise ValueError("value must be a valid canonical ISO date")
    return (parsed + timedelta(days=days)).isoformat()


def _next_iso_date(value: str) -> str:
    """Return the calendar day after one canonical ISO date."""

    return _iso_date_after(value, 1)


def _daybook_date_is(
    projection: RichScreenProjection,
    expected: str,
) -> bool:
    """Return whether Daybook shows exactly one expected valid ISO date."""

    _next_iso_date(expected)
    return _daybook_dates(projection) == (expected,)


def _collection_claims_in_tile(
    projection: RichScreenProjection,
    kind: ControlKind,
    tile: int,
) -> tuple[_SemanticCollectionClaim, ...]:
    """Return generic semantic roots wholly owned by one Desk gate tile."""

    return _collection_claims_in(
        projection, kind, _desktop_tile_bounds(projection, tile)
    )


def _collection_claims_in(
    projection: RichScreenProjection,
    kind: ControlKind,
    bounds: tuple[int, int, int, int],
) -> tuple[_SemanticCollectionClaim, ...]:
    """Return generic semantic roots wholly inside BOUNDS."""

    if kind not in (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID):
        raise ValueError("kind must be a semantic text collection")
    left, top, right, bottom = bounds
    return tuple(
        claim
        for claim in projection.semantic_collection_claims
        if claim.kind is kind
        and left <= claim.left < claim.right <= right
        and top <= claim.top < claim.bottom <= bottom
    )


def _field_claims_in(
    projection: RichScreenProjection,
    bounds: tuple[int, int, int, int],
) -> tuple[_SemanticFieldClaim, ...]:
    """Return exact typed FIELD roots wholly inside the requested bounds."""

    left, top, right, bottom = bounds
    return tuple(
        claim for claim in projection.semantic_field_claims
        if left <= claim.left < claim.right <= right
        and top <= claim.top < claim.bottom <= bottom
    )


def _field_claims_in_tile(
    projection: RichScreenProjection,
    tile: int,
) -> tuple[_SemanticFieldClaim, ...]:
    return _field_claims_in(projection, _desktop_pane_content_bounds(projection, tile))


def _status_field_claims_in(
    projection: RichScreenProjection,
    bounds: tuple[int, int, int, int],
) -> tuple[_SemanticStatusFieldClaim, ...]:
    """Return typed static state wholly inside BOUNDS, without text inference."""

    left, top, right, bottom = bounds
    return tuple(
        claim
        for claim in projection.semantic_status_field_claims
        if left <= claim.left < claim.right <= right
        and top <= claim.top < claim.bottom <= bottom
    )


def _status_field_claims_in_tile(
    projection: RichScreenProjection,
    tile: int,
) -> tuple[_SemanticStatusFieldClaim, ...]:
    return _status_field_claims_in(projection, _desktop_tile_bounds(projection, tile))


def _item_view_claims_in_tile(
    projection: RichScreenProjection,
    tile: int,
) -> tuple[_SemanticItemViewClaim, ...]:
    """Return retained ITEM_VIEW roots wholly owned by one Desk gate tile."""

    left, top, right, bottom = _desktop_tile_bounds(projection, tile)
    return tuple(
        claim
        for claim in projection.semantic_item_view_claims
        if left <= claim.left < claim.right <= right
        and top <= claim.top < claim.bottom <= bottom
    )


def _fexplorer_table_claim(
    projection: RichScreenProjection,
) -> _SemanticItemViewClaim | None:
    """File Explorer's detail table, when its tile carries exactly one."""

    tables = tuple(
        claim
        for claim in _item_view_claims_in_tile(projection, FEXPLORER_DESKTOP_TILE)
        if claim.content.role is ItemViewRole.TABLE
    )
    return tables[0] if len(tables) == 1 else None


def _item_shown(claim: _SemanticItemViewClaim, item: ViewItem) -> bool:
    content = claim.content
    return (
        content.viewport_first
        <= item.ordinal
        < content.viewport_first + content.viewport_count
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
    waiting: str | None = None,
) -> str:
    """Persist exact last-seen text planes and return the timeout detail,
    with what the journey last said it was waiting for."""

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
        + ("" if waiting is None else f" waiting-for={waiting}")
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


def _require_healthy_backend(status: dict, artifact_root: Path) -> None:
    """Fail from the current status before another screen or input request."""
    error = status.get("error")
    if not error and status.get("state") != "error":
        return
    reason = str(error or "backend entered error state without a diagnostic")
    path = Path(artifact_root) / "backend-failure.json"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(status, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")
        detail = f"status saved to {path}"
    except OSError as exc:
        detail = f"status capture failed: {exc}"
    raise PhysicalDesktopAcceptanceError(f"Desktop backend failed: {reason}; {detail}")


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


@dataclass(frozen=True)
class SoundLabWaveformSource:
    """Owned host copy of the ordinary immutable UDG model, read while paused."""

    address: int
    byte_count: int
    graph_sha256: str
    bounds: tuple[int, int, int, int]
    values: tuple[int, ...]
    duration: int
    amplitude: int
    frequency: int
    shape: int


def _soundlab_source_cells(client, address: int, count: int, *, dictionary_body: bool = False) -> list[int]:
    if (type(address) is not int or type(count) is not int or address <= 0
            or (address % 8 and not dictionary_body)
            or not 1 <= count <= (2 if dictionary_body else 130176 // 8)
            or address + count * 8 > 1 << 64):
        raise PhysicalDesktopAcceptanceError("invalid bounded Sound Lab source span")
    cells = _read_guest_cells(client, address=address, count=count)
    if any(not 0 <= cell < 1 << 64 for cell in cells):
        raise PhysicalDesktopAcceptanceError("Sound Lab source contains a non-cell value")
    return cells


def _signed_cell(value: int) -> int:
    return value - (1 << 64) if value & (1 << 63) else value


def _read_soundlab_waveform_source(client) -> SoundLabWaveformSource:
    """Read actual CMP fields and the owned UDG history, without guest execution.

    CMP-FIELD bodies contain the current-state cell address and an instance
    offset. Resolving those two cells avoids guessing the large app state
    layout. Dictionary bodies may be byte-packed; instance and graph storage
    remain aligned. Each RPC reads at most 256 cells, and the complete graph is bounded
    by Sound Lab's 130176-byte caller-owned bank. No synthesis is reproduced.
    """
    before = client.request("status", detailed=False)
    if type(before.get("paused")) is not bool or before.get("error"):
        raise PhysicalDesktopAcceptanceError("Sound Lab source requires a healthy pause boundary")
    resume_after = False
    transport_failed = False
    try:
        paused = client.request("pause")
        if paused.get("paused") is not True or paused.get("error"):
            raise PhysicalDesktopAcceptanceError("Sound Lab source pause failed")
        resume_after = not before["paused"]
        names = ("_SL-DGRAPH-ACTIVE-A", "_SL-DGRAPH-ACTIVE-U", "_SL-PANEL-RGN",
                 "_SL-RENDER-VALID", "_SL-DURATION", "_SL-AMPLITUDE",
                 "_SL-FREQUENCY", "_SL-SHAPE")
        words = client.request("forth", names=["_SL-CURRENT-STATE", *names]).get("words", {})
        try:
            state_cell = words["_SL-CURRENT-STATE"]["data_address"]
            state = _soundlab_source_cells(client, state_cell, 1, dictionary_body=True)[0]
            fields = {}
            for name in names:
                owner, offset = _soundlab_source_cells(client, words[name]["data_address"], 2, dictionary_body=True)
                if owner != state_cell or offset % 8 or offset >= 512 * 1024:
                    raise PhysicalDesktopAcceptanceError("Sound Lab CMP field has a foreign or unbounded layout")
                fields[name] = _soundlab_source_cells(client, state + offset, 1)[0]
        except KeyError as exc:
            raise PhysicalDesktopAcceptanceError("Sound Lab source fields are unavailable") from exc
        if not fields["_SL-RENDER-VALID"]:
            raise PhysicalDesktopAcceptanceError("Sound Lab ordinary render is not valid")
        address, size = fields["_SL-DGRAPH-ACTIVE-A"], fields["_SL-DGRAPH-ACTIVE-U"]
        if size % 8 or not 112 <= size <= 130176:
            raise PhysicalDesktopAcceptanceError("Sound Lab graph exceeds its ordinary bank")
        cells = _soundlab_source_cells(client, address, size // 8)
        panel_row, panel_col, height, width = _soundlab_source_cells(
            client, fields["_SL-PANEL-RGN"], 4)
        if (cells[:3] != [size, 1, 1] or cells[3:7] != [0, 0, height, width]
                or cells[7] != 3 or cells[13] != 0 or height < 18 or width < 8
                or not 0 < cells[8] <= 64):
            raise PhysicalDesktopAcceptanceError("Sound Lab canonical graph header is inconsistent")
        offset, previous_key, records, objects = 14, 1, 0, 0
        series = waveform = None
        while offset < len(cells):
            if offset + 3 > len(cells):
                raise PhysicalDesktopAcceptanceError("truncated Sound Lab graph record")
            byte_count, kind, key = cells[offset:offset + 3]
            if (byte_count < 24 or byte_count % 8 or offset + byte_count // 8 > len(cells)
                    or key <= previous_key or kind not in (1, 2, 3, 4, 5)):
                raise PhysicalDesktopAcceptanceError("invalid Sound Lab graph record extent or identity")
            record = cells[offset:offset + byte_count // 8]
            if kind == 4:
                if series is not None or len(record) < 9:
                    raise PhysicalDesktopAcceptanceError("Sound Lab must own exactly one canonical history")
                series = record
            else:
                objects += 1
                if len(record) < 10:
                    raise PhysicalDesktopAcceptanceError("truncated Sound Lab object")
                if kind == 5:
                    if waveform is not None or series is None or len(record) != 18:
                        raise PhysicalDesktopAcceptanceError("Sound Lab waveform lacks an earlier owned history")
                    waveform = record
            offset += byte_count // 8
            records += 1
            previous_key = key
        if (series is None or waveform is None or cells[8:11] != [records, objects, 1]
                or not 1 <= series[6] <= 16000 or series[2:6] != [40, series[6], 1, 125]
                or series[7:9] != [0, 0] or len(series) != 9 + series[6]
                or cells[11] != series[6] or fields["_SL-DURATION"] * 8 != series[6]):
            raise PhysicalDesktopAcceptanceError("Sound Lab source is not its complete 125us PCM-derived history")
        expected_h, expected_w = min(max(height - 17, 3), 12), max(width - 4, 4)
        if (waveform[2:11] != [41, 0, 11, 2, expected_h, expected_w, 0, 1, 40]
                or tuple(map(_signed_cell, waveform[11:13])) != (-32768, 32767)
                or waveform[13:] != [0x5FD7FFFF, 0x4E4E4EFF, 0, 1, 0]):
            raise PhysicalDesktopAcceptanceError("Sound Lab ordinary waveform geometry or style changed")
        values = tuple(map(_signed_cell, series[9:]))
        if any(not -32768 <= value <= 32767 for value in values):
            raise PhysicalDesktopAcceptanceError("Sound Lab canonical PCM projection is not signed Q15")
        if _soundlab_source_cells(client, state_cell, 1, dictionary_body=True)[0] != state:
            raise PhysicalDesktopAcceptanceError("Sound Lab instance changed during paused source capture")
        encoded = struct.pack(f"<{len(cells)}Q", *cells)
        return SoundLabWaveformSource(
            address, size, hashlib.sha256(encoded).hexdigest(),
            (panel_col + 2, panel_row + 11, panel_col + 2 + expected_w, panel_row + 11 + expected_h),
            values, fields["_SL-DURATION"], fields["_SL-AMPLITUDE"],
            fields["_SL-FREQUENCY"], fields["_SL-SHAPE"],
        )
    except (ConnectionError, OSError):
        transport_failed = True
        raise
    finally:
        if resume_after and not transport_failed:
            if client.request("resume").get("paused") is not False:
                raise PhysicalDesktopAcceptanceError("Sound Lab source capture could not restore running state")


def _require_soundlab_waveform_evidence(offer, generation, source: SoundLabWaveformSource) -> dict:
    """Compare every committed timestamp/value with the copied ordinary model."""
    plane = offer.retained
    waves = [(region, draw) for region in plane.regions for draw in region.draws
             if isinstance(draw, WaveformDraw)] if plane is not None else []
    if len(waves) != 1 or len(plane.series) != 1:
        raise PhysicalDesktopAcceptanceError("Sound Lab requires one waveform and one owned history")
    region, wave = waves[0]
    history = plane.series[0]
    if history.key != (region.owner_id, region.owner_generation, wave.series_id):
        raise PhysicalDesktopAcceptanceError("Sound Lab waveform references another owner's history")
    logical, visible = _visible_draw_rectangle(region, wave, offer.cell.cols, offer.cell.rows)
    bounds = (logical.left, logical.top, logical.right, logical.bottom)
    if visible != logical or bounds != source.bounds:
        raise PhysicalDesktopAcceptanceError("Sound Lab waveform changed or clipped its ordinary plot bounds")
    if (wave.minimum, wave.maximum, wave.zero_value, wave.draw_zero_line) != (-32768, 32767, 0, True):
        raise PhysicalDesktopAcceptanceError("Sound Lab retained waveform range or zero line differs")
    if (tuple((color.red, color.green, color.blue, color.alpha) for color in (wave.trace, wave.zero_line))
            != ((95, 215, 255, 255), (78, 78, 78, 255))):
        raise PhysicalDesktopAcceptanceError("Sound Lab retained waveform colors differ from its ordinary model")
    if source.duration != 2000 or len(source.values) != 16000 or len(history.samples) != 16000:
        raise PhysicalDesktopAcceptanceError("Sound Lab full history requires all 16000 samples")
    for index, (sample, value) in enumerate(zip(history.samples, source.values, strict=True)):
        if (sample.timestamp_us, sample.value) != (index * 125, value):
            raise PhysicalDesktopAcceptanceError(f"Sound Lab retained sample differs from ordinary source at {index}")
    samples_hash = hashlib.sha256(struct.pack("<16000q", *source.values)).hexdigest()
    return {"offer_id": offer.offer_id, "generation": generation,
            "scope": display_scope_to_wire(offer.scope), "history_key": list(history.key),
            "waveform_id": wave.object_id, "bounds": list(bounds), "sample_count": 16000,
            "first_timestamp_us": 0, "interval_us": 125, "last_timestamp_us": 1999875,
            "samples_sha256": samples_hash, "source": "paused ordinary Sound Lab canonical UDG",
            "source_address": source.address, "source_bytes": source.byte_count,
            "source_graph_sha256": source.graph_sha256, "duration_ms": source.duration,
            "amplitude_percent": source.amplitude, "frequency_hz": source.frequency,
            "shape": source.shape, "every_sample_compared": True}


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
            layout = text_rules.cached_row(item.text, content.direction, True)
            shift = _text_area_shift(
                layout, viewport_left, content.viewport_columns
            )
            shown = sorted(
                placed.start
                for placed in layout.characters
                if placed.column + shift < content.viewport_columns
                and placed.column + placed.width + shift > 0
            )
            spans = {
                placed.start: placed.scalars for placed in layout.characters
            }
            text = "".join(
                item.text[start : start + spans[start]] for start in shown
            )
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


def _pane_chrome_rectangles(
    outer: _LogicalRectangle, content: _LogicalRectangle,
) -> tuple[_LogicalRectangle, ...]:
    """The renderer fills these four bands, never the content hole."""
    return tuple(rect for rect in (
        _LogicalRectangle(outer.left, outer.top, outer.right, content.top),
        _LogicalRectangle(outer.left, content.bottom, outer.right, outer.bottom),
        _LogicalRectangle(outer.left, content.top, content.left, content.bottom),
        _LogicalRectangle(content.right, content.top, outer.right, content.bottom),
    ) if rect.left < rect.right and rect.top < rect.bottom)


def _shell_scene_geometry(plane, cols: int, rows: int):
    """Validate the canonical shell's region membership before crediting paint.

    This proves draw geometry only. Ordinary component/action provenance is a
    separate comparison with the acknowledged frozen guest shell snapshot.
    """
    screen = _LogicalRectangle(0, 0, cols, rows)
    regions = {region.region_id: region for region in plane.regions}
    indices = {region.region_id: index for index, region in enumerate(plane.regions)}
    panes, bars = [], []
    roles = {}
    shell_cells = set()
    owners = {(region.owner_id, region.owner_generation) for region in plane.regions}
    if len(owners) != 1:
        raise PhysicalDesktopAcceptanceError("shell regions do not share one aggregate owner")

    def full_surface(region):
        if (_region_logical_rectangle(region) != screen or
                _region_viewport_rectangle(region, cols, rows) != screen):
            raise PhysicalDesktopAcceptanceError("shell material region does not cover the exact full surface")

    def add_material(rectangles):
        for rectangle in rectangles:
            cells = _rectangle_cells(rectangle)
            if cells & shell_cells:
                raise PhysicalDesktopAcceptanceError("shell material claims overlap")
            shell_cells.update(cells)

    for region in plane.regions:
        for draw in region.draws:
            if isinstance(draw, PaneDraw):
                full_surface(region)
                outer, visible = _visible_draw_rectangle(region, draw, cols, rows)
                if visible != outer:
                    raise PhysicalDesktopAcceptanceError("PANE outer geometry is not fully on screen")
                offset = draw.content_bounds
                content = _LogicalRectangle(
                    outer.left + offset.cell_x, outer.top + offset.cell_y,
                    outer.left + offset.cell_x + offset.cell_cols,
                    outer.top + offset.cell_y + offset.cell_rows,
                )
                target = regions.get(draw.content_region_id)
                if target is None or target is region:
                    raise PhysicalDesktopAcceptanceError("PANE content region is missing or self-referential")
                if draw.content_region_id in roles:
                    raise PhysicalDesktopAcceptanceError("PANE content region is reused")
                if (not target.clipped or _region_logical_rectangle(target) != screen or
                        _region_viewport_rectangle(target, cols, rows) != content):
                    raise PhysicalDesktopAcceptanceError("PANE content region does not match its exact content bounds")
                if indices[target.region_id] <= indices[region.region_id]:
                    raise PhysicalDesktopAcceptanceError("PANE content region does not paint after chrome")
                roles[target.region_id] = "content"
                panes.append(_SemanticPaneClaim(
                    region.owner_id, region.owner_generation, draw.object_id,
                    region.region_id, target.region_id, outer, content,
                    draw.title, draw.focused,
                ))
                add_material(_pane_chrome_rectangles(outer, content))
            elif isinstance(draw, TaskBarDraw):
                viewport = _region_viewport_rectangle(region, cols, rows)
                if (_region_logical_rectangle(region) != screen or not region.clipped or
                        viewport is None or viewport.left != 0 or viewport.top != rows - 1 or
                        viewport.bottom != rows):
                    raise PhysicalDesktopAcceptanceError("TASKBAR region needs its exact one-row physical clip")
                bounds, visible = _visible_draw_rectangle(region, draw, cols, rows)
                if bounds != visible:
                    raise PhysicalDesktopAcceptanceError("TASKBAR is not fully on screen")
                tasks = tuple(_SemanticTaskClaim(
                    ControlIdentity(region.owner_id, region.owner_generation, task.control_id),
                    task.kind, task.state, task.order,
                    _LogicalRectangle(bounds.left + task.bounds.cell_x,
                                      bounds.top + task.bounds.cell_y,
                                      bounds.left + task.bounds.cell_x + task.bounds.cell_cols,
                                      bounds.top + task.bounds.cell_y + task.bounds.cell_rows),
                    task.label, task.shortcut,
                ) for task in draw.tasks)
                bars.append(_SemanticTaskBarClaim(
                    ControlIdentity(region.owner_id, region.owner_generation, draw.control_id),
                    draw.state, bounds, tasks,
                ))
                add_material((bounds,))

    content_cells = set()
    for pane in panes:
        cells = _rectangle_cells(pane.content_bounds)
        if cells & (content_cells | shell_cells):
            raise PhysicalDesktopAcceptanceError("PANE contents overlap another pane or shell material")
        content_cells.update(cells)
    for region in plane.regions:
        band_bounds = [_draw_logical_rectangle(region, draw) for draw in region.draws
                       if isinstance(draw, TaskBarDraw)]
        if band_bounds:
            viewport = _region_viewport_rectangle(region, cols, rows)
            if (min(bounds.left for bounds in band_bounds) != viewport.left or
                    max(bounds.right for bounds in band_bounds) != viewport.right):
                raise PhysicalDesktopAcceptanceError("TASKBAR clip extends beyond its admitted bands")
        for draw in region.draws:
            if not isinstance(draw, TaskBarDraw):
                continue
            bounds = _draw_logical_rectangle(region, draw)
            for later_region in plane.regions[indices[region.region_id] + 1:]:
                viewport = _region_viewport_rectangle(later_region, cols, rows)
                if viewport is not None and _rectangle_intersection(bounds, viewport) is not None:
                    raise PhysicalDesktopAcceptanceError("a later region blocks TASKBAR input slots")
    if not panes:
        return tuple(panes), tuple(bars), shell_cells, roles
    instrument_types = (ReadoutDraw, MeterDraw, StatusDraw, WaveformDraw)
    for region in plane.regions:
        if region.region_id in roles:
            if any(isinstance(draw, (PaneDraw, TaskBarDraw) + instrument_types) for draw in region.draws):
                raise PhysicalDesktopAcceptanceError("PANE content region has nonmatching shell or instrument draws")
            continue
        if region.draws and all(isinstance(draw, PaneDraw) for draw in region.draws):
            roles[region.region_id] = "chrome"
        elif region.draws and all(isinstance(draw, TaskBarDraw) for draw in region.draws):
            roles[region.region_id] = "taskbar"
        elif region.draws and all(isinstance(draw, instrument_types) for draw in region.draws):
            viewport = _region_viewport_rectangle(region, cols, rows)
            matches = [pane for pane in panes if viewport is not None and
                       _rectangle_intersection(viewport, pane.content_bounds) == viewport]
            if not region.clipped or len(matches) != 1:
                raise PhysicalDesktopAcceptanceError("instrument region has no unique PANE content membership")
            pane = matches[0]
            if not (indices[pane.region_id] < indices[region.region_id] <
                    indices[pane.content_region_id]):
                raise PhysicalDesktopAcceptanceError("PANE instrument region does not paint between chrome and content")
            roles[region.region_id] = "instrument"
        elif region.draws and all(isinstance(draw, GlyphRunDraw) for draw in region.draws):
            full_surface(region)
            for draw in region.draws:
                _logical, visible = _visible_draw_rectangle(region, draw, cols, rows)
                if visible is not None and _rectangle_cells(visible) & (content_cells | shell_cells):
                    raise PhysicalDesktopAcceptanceError("global residual glyphs intrude on PANE or shell claims")
            roles[region.region_id] = "residual"
        else:
            raise PhysicalDesktopAcceptanceError("shell scene has an unrelated or nonmatching region")
    # An otherwise empty full-frame region still installs an input barrier.
    # Residual/chrome cannot follow TASKBAR or interactive pane content.
    targets = [indices[region_id] for region_id, role in roles.items()
               if role in ("content", "taskbar")]
    for region_id, role in roles.items():
        if role in ("chrome", "residual") and any(indices[region_id] >= index for index in targets):
            raise PhysicalDesktopAcceptanceError("full-surface shell region blocks an earlier interactive region")
    return tuple(panes), tuple(bars), shell_cells, roles


def reconstruct_retained_screen(
    offer: TerminalDisplayOffer,
    *,
    require_menu_bar: bool = True,
    allow_empty: bool = False,
) -> RichScreenProjection:
    """Validate one complete rich screen and reconstruct its logical text.

    The canonical Desktop always shows some applet's semantic menu bar.  Desk
    holding a single applet shows none while that applet's modal prompt
    withholds its menu, so a journey for it may relax REQUIRE_MENU_BAR and
    check the menu itself.

    A draw the producer cannot show rich replaces the retained scene with an
    empty one, and the viewer then shows the CELL plane.  A journey that
    expects that may ALLOW_EMPTY: a visible retained plane with no region is
    then reconstructed as the CELL text it shows, with no draw and no claim.
    """

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
    if allow_empty and not plane.regions:
        cells = tuple(tuple(item.char for item in row) for row in cell.cells)
        return RichScreenProjection(
            cell.cols,
            cell.rows,
            tuple("".join(row) for row in cells),
            0,
            cells=cells,
        )
    base_draw_types = (
        GlyphRunDraw,
        MenuBarDraw,
        TextAreaDraw,
        TextGridDraw,
        TabSetDraw,
        ItemViewDraw,
        StatusFieldDraw,
        FieldDraw,
    )
    instrument_draw_types = (ReadoutDraw, MeterDraw, StatusDraw, WaveformDraw)
    supported_draw_types = base_draw_types + instrument_draw_types + (PaneDraw, TaskBarDraw)
    for region in plane.regions:
        for draw in region.draws:
            if not isinstance(draw, supported_draw_types):
                raise PhysicalDesktopAcceptanceError(
                    "retained screen contains unsupported draw "
                    f"{type(draw).__name__}"
                )
    has_shell = any(isinstance(draw, (PaneDraw, TaskBarDraw))
                    for region in plane.regions for draw in region.draws)
    pane_claims, taskbar_claims, shell_cells, shell_roles = (
        _shell_scene_geometry(plane, cell.cols, cell.rows) if has_shell
        else ((), (), set(), {}))
    later_region_cells = {}
    if pane_claims:
        base_region = None
        base_draw_cells = set()
        background_instrument_regions = set()
        foreground_instrument_cells = set()
        later = set()
        for region in reversed(plane.regions):
            later_region_cells[region.region_id] = set(later)
            for draw in region.draws:
                logical, visible = _visible_draw_rectangle(region, draw, cell.cols, cell.rows)
                if visible is None:
                    continue
                if isinstance(draw, PaneDraw):
                    pane = next(item for item in pane_claims if item.object_id == draw.object_id)
                    for band in _pane_chrome_rectangles(pane.bounds, pane.content_bounds):
                        later.update(_rectangle_cells(band))
                else:
                    later.update(_rectangle_cells(visible))
    else:
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
            elif any(not isinstance(draw, instrument_draw_types + (TaskBarDraw,)) for draw in region.draws):
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
        # Sparse noninteractive regions may precede the base so their region-wide
        # input barriers do not hide disjoint FIELD targets. Apply the same
        # conservative evidence rule to instruments beneath ordinary base draws.
        base_draw_cells: set[tuple[int, int]] = set()
        for draw in base_region.draws:
            _logical, visible = _visible_draw_rectangle(
                base_region, draw, cell.cols, cell.rows
            )
            if visible is not None:
                base_draw_cells.update(_rectangle_cells(visible))
        background_instrument_regions = {
            region.region_id for region in plane.regions[:base_region_index]
        }
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
    glyph_z_orders: dict[tuple[int, int], int] = {}
    semantic_cells: set[tuple[int, int]] = set()
    opaque_semantic_cells: set[tuple[int, int]] = set()
    instrument_cells: set[tuple[int, int]] = set()
    semantic_lines: list[str] = []
    menu_signatures: list[tuple[str, ...]] = []
    menu_bar_count = 0
    semantic_collection_claims: list[_SemanticCollectionClaim] = []
    semantic_item_view_claims: list[_SemanticItemViewClaim] = []
    semantic_tabset_claims: list[_SemanticTabSetClaim] = []
    instrument_claims: list[_InstrumentClaim] = []
    semantic_status_field_claims: list[_SemanticStatusFieldClaim] = []
    semantic_field_claims: list[_SemanticFieldClaim] = []
    menu_underlay_cells: set[tuple[int, int]] = set()
    menu_bar_planes: list[tuple[set[tuple[int, int]], int]] = []

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
        if pane_claims:
            foreground_instrument_cells = later_region_cells[region.region_id]
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

        if isinstance(draw, PaneDraw):
            pane = next(item for item in pane_claims if item.object_id == draw.object_id)
            for band in _pane_chrome_rectangles(pane.bounds, pane.content_bounds):
                claim_semantic_rectangle(band.left, band.top, band.right, band.bottom)
                opaque_semantic_cells.update(_rectangle_cells(band))
            continue

        if isinstance(draw, TaskBarDraw):
            claim_semantic_rectangle(left, top, right, bottom)
            opaque_semantic_cells.update(_rectangle_cells(visible))
            continue

        if isinstance(draw, GlyphRunDraw):
            # Each character takes W(c) cells (APT-1-TEXT Section 10).
            slots, slot_count = _glyph_slots(draw.text)
            slots = tuple(slots)
            if (
                not draw.text
                or logical.bottom - logical.top != 1
                or logical.right - logical.left != slot_count
                or bottom - top != 1
            ):
                raise PhysicalDesktopAcceptanceError(
                    f"retained glyph run {draw.object_id} geometry does not "
                    "match its horizontal character run"
                )
            background = (
                draw.foreground
                if draw.attributes & ATTR_REVERSE
                else draw.background
            )
            if background.alpha != 255:
                raise PhysicalDesktopAcceptanceError(
                    f"retained glyph run {draw.object_id} has no opaque "
                    "background for complete rich coverage"
                )
            # A character's text is in its lead cell; a continuation cell
            # holds none, as in the CELL snapshot.
            for character, first_slot, width in slots:
                for part in range(width):
                    column = logical.left + first_slot + part
                    if not left <= column < right:
                        continue
                    coordinate = (column, top)
                    if coordinate in glyph_cells:
                        raise PhysicalDesktopAcceptanceError(
                            f"retained glyph run {draw.object_id} overlaps "
                            f"another glyph at {coordinate!r}"
                        )
                    glyph_cells.add(coordinate)
                    glyph_z_orders[coordinate] = draw.z_order
                    glyphs[top * cell.cols + column] = character if not part else ""
            continue

        if isinstance(draw, MenuBarDraw):
            claim_semantic_rectangle(left, top, right, bottom)
            signature = tuple(menu.label for menu in draw.menus)
            evidence_cells = _rectangle_cells(visible)
            menu_bar_planes.append((set(evidence_cells), draw.z_order))
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
                evidence_cells.update(popup_claim)
            menu_underlay_cells.update(evidence_cells)
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

        if isinstance(draw, FieldDraw):
            # The complete root is opaque; independently clipped label/value
            # slots preserve exact semantic state without making their source
            # strings evidence of readable pixels.
            if visible == logical and not _rectangle_cells(visible) & foreground_instrument_cells:
                semantic_field_claims.append(_SemanticFieldClaim(
                    identity=ControlIdentity(
                        region.owner_id, region.owner_generation, draw.control_id,
                    ),
                    left=left, top=top, right=right, bottom=bottom,
                    label=draw.label, state=draw.state, content=draw.content,
                ))
            claim_semantic_rectangle(left, top, right, bottom)
            opaque_semantic_cells.update(_rectangle_cells(visible))
            continue

        if isinstance(draw, StatusFieldDraw):
            # The viewer fills the complete square one-row material, then
            # clips each string independently to its explicit label/value
            # slot. Preserve those exact slots and authored state; do not
            # pretend a long string was physically readable in that slot.
            if visible == logical and not _rectangle_cells(visible) & foreground_instrument_cells:
                semantic_status_field_claims.append(
                    _SemanticStatusFieldClaim(
                        owner_id=region.owner_id,
                        owner_generation=region.owner_generation,
                        object_id=draw.object_id,
                        left=left,
                        top=top,
                        right=right,
                        bottom=bottom,
                        label_cols=draw.label_cols,
                        label=draw.label,
                        value=draw.value,
                        severity=draw.severity,
                        emphasized=draw.emphasized,
                    )
                )
            claim_semantic_rectangle(left, top, right, bottom)
            opaque_semantic_cells.update(_rectangle_cells(visible))
            continue

        if isinstance(draw, (TextAreaDraw, TextGridDraw)):
            kind = (
                ControlKind.TEXT_AREA
                if isinstance(draw, TextAreaDraw)
                else ControlKind.TEXT_GRID
            )
            if visible == logical and not _rectangle_cells(visible) & foreground_instrument_cells:
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
                        style_runs=tuple(
                            (item.item_key, run.start, run.length, int(run.meaning))
                            for item in draw.content.items
                            for run in item.runs
                        ),
                    )
                )
            claim_semantic_rectangle(left, top, right, bottom)
            opaque_semantic_cells.update(_rectangle_cells(visible))
            continue

        if isinstance(draw, ItemViewDraw):
            if visible == logical and not _rectangle_cells(visible) & foreground_instrument_cells:
                semantic_item_view_claims.append(
                    _SemanticItemViewClaim(
                        identity=ControlIdentity(
                            region.owner_id,
                            region.owner_generation,
                            draw.control_id,
                        ),
                        left=left,
                        top=top,
                        right=right,
                        bottom=bottom,
                        content=draw.content,
                        state=draw.state,
                    )
                )
            claim_semantic_rectangle(left, top, right, bottom)
            opaque_semantic_cells.update(_rectangle_cells(visible))
            continue

        if isinstance(draw, TabSetDraw):
            if visible == logical and not _rectangle_cells(visible) & foreground_instrument_cells:
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
            opaque_semantic_cells.update(_rectangle_cells(visible))
            continue

        if isinstance(draw, instrument_draw_types):
            if isinstance(draw, ReadoutDraw):
                kind = "READOUT"
            elif isinstance(draw, MeterDraw):
                kind = "METER"
            elif isinstance(draw, WaveformDraw):
                kind = "WAVEFORM"
            else:
                kind = "STATUS"
            if not (pane_claims and _rectangle_cells(visible) & foreground_instrument_cells) and not (
                region.region_id in background_instrument_regions
                and _rectangle_cells(visible) & base_draw_cells
            ):
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
    if require_menu_bar and (menu_bar_count == 0 or not semantic_lines):
        raise PhysicalDesktopAcceptanceError(
            "retained screen contains no semantic menu bar"
        )
    semantic_residual_cells = glyph_cells & opaque_semantic_cells
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
    # Menus replace ordinary CELL painting without preserving its metrics.
    # Their source rectangles therefore need independently retained backing:
    # residual glyphs or an opaque collection/instrument.  Neither a semantic
    # bar nor a source-popup claim can excuse a hole through to CELL.
    for bar_cells, bar_z_order in menu_bar_planes:
        late_underlay = {
            coordinate
            for coordinate in bar_cells & glyph_cells
            if glyph_z_orders[coordinate] > bar_z_order
        }
        if late_underlay:
            raise PhysicalDesktopAcceptanceError(
                "retained menu underlay paints above its semantic bar: "
                f"cells={len(late_underlay)}"
            )
    # Equal-z glyph objects precede semantic roots in RetainedRegionDraw.
    # Open popups are deferred above ordinary draws within their region by
    # the compositor, so their backing has no additional root-z constraint.
    covered = glyph_cells | opaque_semantic_cells | instrument_cells
    missing_menu_underlay = menu_underlay_cells - covered
    if missing_menu_underlay:
        raise PhysicalDesktopAcceptanceError(
            "retained menu source claims leave logical cells uncovered "
            "without opaque underlay: "
            f"cells={len(missing_menu_underlay)}"
        )
    uncovered = {
        (col, row)
        for row in range(cell.rows)
        for col in range(cell.cols)
        if (col, row) not in covered
    }
    if uncovered:
        raise PhysicalDesktopAcceptanceError(
            "retained rich draws leave logical cells uncovered: "
            f"cells={len(uncovered)}"
        )
    cells = tuple(
        tuple(
            text if text is not None else " "
            for text in glyphs[row * cell.cols : (row + 1) * cell.cols]
        )
        for row in range(cell.rows)
    )
    lines = tuple("".join(row) for row in cells)
    return RichScreenProjection(
        cell.cols,
        cell.rows,
        lines,
        sum(len(region.draws) for region in plane.regions),
        semantic_lines=tuple(semantic_lines),
        glyph_cell_count=len(glyph_cells),
        menu_bar_count=menu_bar_count,
        menu_signatures=tuple(menu_signatures),
        renderer_owned_gap_cells=0,
        semantic_collection_claims=tuple(semantic_collection_claims),
        semantic_tabset_claims=tuple(semantic_tabset_claims),
        semantic_item_view_claims=tuple(semantic_item_view_claims),
        region_count=len(plane.regions),
        instrument_region_count=sum(any(isinstance(draw, instrument_draw_types)
                                        for draw in region.draws) for region in plane.regions),
        clipped_region_count=sum(region.clipped for region in plane.regions),
        instrument_cell_count=len(instrument_cells),
        instrument_claims=tuple(instrument_claims),
        semantic_status_field_claims=tuple(semantic_status_field_claims),
        semantic_field_claims=tuple(semantic_field_claims),
        semantic_pane_claims=pane_claims,
        semantic_taskbar_claims=taskbar_claims,
        cells=cells,
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
    daybook_items = _item_view_claims_in_tile(projection, DAYBOOK_DESKTOP_TILE)
    if daybook_items:
        missing.append(
            "the document-atomic Daybook fallback must not retain a partial "
            f"item view (found {len(daybook_items)})"
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
    if _field_claims_in_tile(projection, DAYBOOK_DESKTOP_TILE):
        raise PhysicalDesktopAcceptanceError(
            "modal document fallback retained a FIELD root"
        )
    if _status_field_claims_in_tile(projection, DAYBOOK_DESKTOP_TILE):
        missing.append("document-atomic prompt fallback retained a STATUS_FIELD")
    if missing:
        raise PhysicalDesktopAcceptanceError(
            "Daybook prompt retained fallback is incomplete: "
            f"{', '.join(missing)}"
        )


def _desk_launcher_claim(
    projection: RichScreenProjection,
) -> _SemanticItemViewClaim | None:
    """Desk's launcher: an overlay document whose catalog is the one
    two-column item view listing every canonical applet."""

    views = [
        claim
        for claim in projection.semantic_item_view_claims
        if len(claim.content.columns) == 2
        and all(claim.named(title) is not None for title in DESKTOP_LAUNCHER_TITLES)
    ]
    return views[0] if len(views) == 1 else None


def _desk_launcher_selected(
    projection: RichScreenProjection,
    title: str,
) -> bool:
    """Return whether Desk's launcher selects one title."""

    launcher = _desk_launcher_claim(projection)
    selected = None if launcher is None else launcher.selected
    return selected is not None and selected.fields[0].text == title


def _require_desk_launcher_selection(
    projection: RichScreenProjection,
    title: str,
) -> _SemanticItemViewClaim:
    """Require the launcher to list the canonical catalog in order with one
    title selected."""

    launcher = _desk_launcher_claim(projection)
    if launcher is None:
        raise PhysicalDesktopAcceptanceError(
            "Desk's launcher is not one rich item view of the catalog"
        )
    titles = tuple(item.fields[0].text for item in launcher.content.items)
    if titles != DESKTOP_LAUNCHER_TITLES:
        raise PhysicalDesktopAcceptanceError(f"Desk's launcher lists {titles!r}")
    selected = launcher.selected
    shown = None if selected is None else selected.fields[0].text
    if shown != title:
        raise PhysicalDesktopAcceptanceError(
            f"Desk's launcher selects {shown!r}, expected visible selection "
            f"{title!r}"
        )
    return launcher

def _soundlab_semantic_failures(
    projection: RichScreenProjection,
    expected_menus: tuple[tuple[str, ...], ...],
    *,
    daybook_prompt: bool = False,
    pad_prompt: bool = False,
) -> list[str]:
    """List what a launched-Sound-Lab frame lacks, given its menu forests.

    With ``daybook_prompt`` Daybook's prompt is open, so its calendar is
    withheld with the rest of its slices; with ``pad_prompt`` Pad's is, so
    its text areas and tabs are.
    """

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
    if not pad_prompt and not any(
        _collection_is_available(claim) for claim in pad_areas
    ):
        missing_semantics.append(
            f"at least one TEXT_AREA in Pad tile {PAD_DESKTOP_TILE} must be "
            "visibly enabled"
        )
    daybook_grids = _collection_claims_in_tile(
        projection, ControlKind.TEXT_GRID, DAYBOOK_DESKTOP_TILE
    )
    if not daybook_prompt and (
        len(daybook_grids) != 1 or not _collection_is_available(daybook_grids[0])
    ):
        missing_semantics.append(
            f"exactly one TEXT_GRID in Daybook tile {DAYBOOK_DESKTOP_TILE} "
            "must be visibly enabled "
            f"(found {len(daybook_grids)})"
        )
    if not pad_prompt:
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
    return missing_semantics


def _require_soundlab_desktop_semantics(
    projection: RichScreenProjection,
) -> None:
    """Require the launched Sound Lab and its complete instrument family."""

    missing = _soundlab_semantic_failures(
        projection,
        DESKTOP_MENU_SIGNATURES + (SOUNDLAB_MENU_SIGNATURE,),
    )
    if missing:
        raise PhysicalDesktopAcceptanceError(
            "launched Sound Lab retained frame is missing exact product "
            f"semantics: {', '.join(missing)}"
        )


def _require_soundlab_daybook_prompt_fallback_semantics(
    projection: RichScreenProjection,
) -> None:
    """Require the document-atomic fallback while Daybook's prompt is open
    after Sound Lab's launch: Daybook's menu forest and collections are
    withheld and its tile stays complete through residual glyphs, while
    the other applets, Sound Lab included, stay rich."""

    missing = _soundlab_semantic_failures(
        projection,
        tuple(
            signature
            for signature in DESKTOP_MENU_SIGNATURES + (SOUNDLAB_MENU_SIGNATURE,)
            if signature != DAYBOOK_MENU_SIGNATURE
        ),
        daybook_prompt=True,
    )
    collections = tuple(
        claim
        for kind in (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID)
        for claim in _collection_claims_in_tile(
            projection,
            kind,
            DAYBOOK_DESKTOP_TILE,
        )
    )
    if collections:
        missing.append(
            "the document-atomic Daybook fallback must not retain a partial "
            f"text collection (found {len(collections)})"
        )
    items = _item_view_claims_in_tile(projection, DAYBOOK_DESKTOP_TILE)
    if items:
        missing.append(
            "the document-atomic Daybook fallback must not retain a partial "
            f"item view (found {len(items)})"
        )
    if not _residual_tile_contains(
        projection,
        DAYBOOK_PROMPT_MARKER,
        DAYBOOK_DESKTOP_TILE,
    ):
        missing.append("the Daybook prompt is not visible inside its Desk tile")
    if _field_claims_in_tile(projection, DAYBOOK_DESKTOP_TILE):
        raise PhysicalDesktopAcceptanceError(
            "modal document fallback retained a FIELD root"
        )
    if _status_field_claims_in_tile(projection, DAYBOOK_DESKTOP_TILE):
        missing.append("document-atomic prompt fallback retained a STATUS_FIELD")
    if missing:
        raise PhysicalDesktopAcceptanceError(
            "Daybook prompt retained fallback is incomplete: "
            f"{', '.join(missing)}"
        )


def _require_soundlab_pad_prompt_fallback_semantics(
    projection: RichScreenProjection,
) -> None:
    """Require the document-atomic fallback while Pad's Open prompt is up:
    Pad's menu forest, tabs, text areas, and item views are withheld and its
    tile stays complete through residual glyphs, while the other applets,
    Sound Lab included, stay rich."""

    missing = _soundlab_semantic_failures(
        projection,
        tuple(
            signature
            for signature in DESKTOP_MENU_SIGNATURES + (SOUNDLAB_MENU_SIGNATURE,)
            if signature != PAD_MENU_SIGNATURE
        ),
        pad_prompt=True,
    )
    collections = _collection_claims_in_tile(
        projection, ControlKind.TEXT_AREA, PAD_DESKTOP_TILE
    )
    tabsets = _tabset_claims_in_tile(projection, PAD_DESKTOP_TILE)
    item_views = _item_view_claims_in_tile(projection, PAD_DESKTOP_TILE)
    if collections or tabsets or item_views:
        missing.append(
            "the document-atomic Pad fallback must not retain a partial text "
            f"area, tabset, or item view (found {len(collections)}, "
            f"{len(tabsets)}, and {len(item_views)})"
        )
    if not _residual_tile_contains(
        projection,
        PAD_OPEN_PROMPT_MARKER,
        PAD_DESKTOP_TILE,
    ):
        missing.append("the Pad prompt is not visible inside its Desk tile")
    if _field_claims_in_tile(projection, PAD_DESKTOP_TILE):
        raise PhysicalDesktopAcceptanceError(
            "modal document fallback retained a FIELD root"
        )
    if _status_field_claims_in_tile(projection, PAD_DESKTOP_TILE):
        missing.append("document-atomic prompt fallback retained a STATUS_FIELD")
    if missing:
        raise PhysicalDesktopAcceptanceError(
            f"Pad prompt retained fallback is incomplete: {', '.join(missing)}"
        )


def _require_fexplorer_prompt_fallback_semantics(
    projection: RichScreenProjection,
) -> None:
    """Require the document-atomic fallback while File Explorer is modal.

    Its rename prompt is an ordinary final-writer overlay, so, exactly as for
    Daybook's prompt, all of File Explorer's semantic slices are withheld
    until it closes and its tile stays complete through residual glyphs.  The
    other applets, Sound Lab included, stay rich.
    """

    missing = _soundlab_semantic_failures(
        projection,
        tuple(
            signature
            for signature in DESKTOP_MENU_SIGNATURES + (SOUNDLAB_MENU_SIGNATURE,)
            if signature != FEXPLORER_MENU_SIGNATURE
        ),
    )
    collections = tuple(
        claim
        for kind in (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID)
        for claim in _collection_claims_in_tile(
            projection,
            kind,
            FEXPLORER_DESKTOP_TILE,
        )
    )
    if collections:
        missing.append(
            "the document-atomic File Explorer fallback must not retain a "
            f"partial text collection (found {len(collections)})"
        )
    tabsets = _tabset_claims_in_tile(projection, FEXPLORER_DESKTOP_TILE)
    if tabsets:
        missing.append(
            "the document-atomic File Explorer fallback must not retain a "
            f"partial TABSET (found {len(tabsets)})"
        )
    item_views = _item_view_claims_in_tile(projection, FEXPLORER_DESKTOP_TILE)
    if item_views:
        missing.append(
            "the document-atomic File Explorer fallback must not retain a "
            f"partial item view (found {len(item_views)})"
        )
    if not _residual_tile_contains(
        projection,
        RENAME_PROMPT_LABEL,
        FEXPLORER_DESKTOP_TILE,
    ):
        missing.append(
            "the File Explorer prompt is not visible inside its Desk tile"
        )
    if _field_claims_in_tile(projection, FEXPLORER_DESKTOP_TILE):
        raise PhysicalDesktopAcceptanceError(
            "modal document fallback retained a FIELD root"
        )
    if _status_field_claims_in_tile(projection, FEXPLORER_DESKTOP_TILE):
        missing.append("document-atomic prompt fallback retained a STATUS_FIELD")
    if missing:
        raise PhysicalDesktopAcceptanceError(
            "File Explorer prompt retained fallback is incomplete: "
            f"{', '.join(missing)}"
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


def _shell_hit_target(offer, display_state, display_ack, identity, kind):
    """Bind one enabled TASK/LAUNCHER to the exact acknowledged painter hit."""
    token = _exact_hit_map_token(offer, display_state, display_ack, "shell activation")
    if offer.retained is None or kind not in (ControlKind.TASK, ControlKind.LAUNCHER):
        raise PhysicalDesktopAcceptanceError("shell activation needs a retained TASK or LAUNCHER")
    matches = [(region, bar, task) for region in offer.retained.regions
               for bar in region.draws if isinstance(bar, TaskBarDraw)
               for task in bar.tasks if task.kind is kind and
               ControlIdentity(region.owner_id, region.owner_generation, task.control_id) == identity]
    if len(matches) != 1:
        raise PhysicalDesktopAcceptanceError("shell activation does not name one committed task slot")
    _region, bar, task = matches[0]
    required = ControlState.VISIBLE | ControlState.ENABLED
    if bar.state & required != required or task.state & required != required:
        raise PhysicalDesktopAcceptanceError("shell activation target or parent is disabled")
    targets = tuple(target for target in display_state.hit_targets
                    if target.kind is kind and target.identity == identity)
    if len(targets) != 1:
        raise PhysicalDesktopAcceptanceError("shell activation lacks one acknowledged control target")
    target = targets[0]
    x, y = target.rect.left + target.rect.width // 2, target.rect.top + target.rect.height // 2
    if target.rect.width <= 0 or target.rect.height <= 0 or display_state.hit_test(
            x, y, display_token=token) != target:
        raise PhysicalDesktopAcceptanceError("shell target is not an exposed acknowledged painter hit")
    return target, task.label


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


@dataclass(frozen=True)
class _OrdinaryMenuCapture:
    """One ordinary applet menu opened and closed after Sound Lab is live."""

    key: str
    signature: tuple[str, ...]
    label: str
    tile: int
    focus_marker: str
    entries: tuple[tuple[str, str] | None, ...]


ORDINARY_MENU_CAPTURES = {
    capture.key: capture
    for capture in (
        _OrdinaryMenuCapture(
            "fexplorer-view",
            FEXPLORER_MENU_SIGNATURE,
            "View",
            FEXPLORER_DESKTOP_TILE,
            FEXPLORER_FOCUS_MARKER,
            (
                ("Show_Hidden", "Ctrl+H"),
                None,
                ("Sort:_Name", ""),
                ("Sort:_Size", ""),
                ("Sort:_Type", ""),
                None,
                ("Expand_All", ""),
                ("Collapse_All", ""),
            ),
        ),
        _OrdinaryMenuCapture(
            "daybook-go",
            DAYBOOK_MENU_SIGNATURE,
            "Go",
            DAYBOOK_DESKTOP_TILE,
            DAYBOOK_FOCUS_MARKER,
            (("Today", "Home"), ("Previous_Day", ""), ("Next_Day", "")),
        ),
    )
}
_ORDINARY_MENU_STATE = ControlState.VISIBLE | ControlState.ENABLED


def _ordinary_menu_in_tile(
    offer: TerminalDisplayOffer,
    capture: _OrdinaryMenuCapture,
) -> tuple[RetainedRegionDraw, MenuBarDraw, MenuDraw]:
    """Resolve one ordinary applet menu from its unique bar in its Desk tile."""

    plane = offer.retained
    if plane is None:
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: menu lookup requires a retained display plane"
        )
    geometry = RichScreenProjection(offer.cell.cols, offer.cell.rows, (), 0)
    left, top, right, bottom = _desktop_tile_bounds(geometry, capture.tile)
    matches: list[tuple[RetainedRegionDraw, MenuBarDraw, MenuDraw]] = []
    for region in plane.regions:
        for bar in region.draws:
            if not isinstance(bar, MenuBarDraw):
                continue
            if tuple(menu.label for menu in bar.menus) != capture.signature:
                continue
            _logical, visible = _visible_draw_rectangle(
                region,
                bar,
                offer.cell.cols,
                offer.cell.rows,
            )
            if visible is None or not (
                left <= visible.left < visible.right <= right
                and top <= visible.top < visible.bottom <= bottom
            ):
                continue
            menus = tuple(
                menu for menu in bar.menus if menu.label == capture.label
            )
            if len(menus) != 1:
                raise PhysicalDesktopAcceptanceError(
                    f"{capture.key}: ambiguous semantic menu in its ordinary bar"
                )
            matches.append((region, bar, menus[0]))
    if len(matches) != 1:
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: expected exactly one ordinary menu in tile "
            f"{capture.tile}"
        )
    region, bar, menu = matches[0]
    if (
        bar.state != _ORDINARY_MENU_STATE
        or menu.state & _ORDINARY_MENU_STATE != _ORDINARY_MENU_STATE
    ):
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: menu is not visibly enabled"
        )
    return region, bar, menu


def _require_ordinary_menu_state(
    offer: TerminalDisplayOffer,
    capture: _OrdinaryMenuCapture,
    opened: bool,
) -> tuple[RetainedRegionDraw, MenuBarDraw, MenuDraw]:
    """Require the exact closed or open state and the authored popup rows."""

    region, bar, menu = _ordinary_menu_in_tile(offer, capture)
    expected_state = _ORDINARY_MENU_STATE
    if opened:
        expected_state |= ControlState.OPEN | ControlState.SELECTED
    if menu.state != expected_state:
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: unexpected menu state {menu.state!r}"
        )
    if not opened:
        if menu.entries:
            raise PhysicalDesktopAcceptanceError(
                f"{capture.key}: closed menu retained popup rows"
            )
        return region, bar, menu
    signature = tuple(
        (entry.label, entry.shortcut) if isinstance(entry, MenuItemDraw) else None
        for entry in menu.entries
    )
    if signature != capture.entries:
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: ordinary popup rows changed: {signature!r}"
        )
    if tuple(entry.order for entry in menu.entries) != tuple(
        range(len(menu.entries))
    ):
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: ordinary popup row order is incomplete"
        )
    for entry in menu.entries:
        if (
            isinstance(entry, MenuItemDraw)
            and entry.state & _ORDINARY_MENU_STATE != _ORDINARY_MENU_STATE
        ):
            raise PhysicalDesktopAcceptanceError(
                f"{capture.key}: expected a visible enabled ordinary popup item"
            )
    return region, bar, menu


def _ordinary_menu_hit_evidence(
    offer: TerminalDisplayOffer,
    capture: _OrdinaryMenuCapture,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    opened: bool,
) -> list[dict[str, object]]:
    """Bind the menu title and any open items to the exact acknowledged hits."""

    token = (offer.offer_id, offer.scope)
    if display_state.hit_map_token != token or display_ack != token:
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: action lacks the exact composited and "
            "acknowledged hit map"
        )
    if capture.focus_marker not in offer.cell.text().split("\n")[-1]:
        raise PhysicalDesktopAcceptanceError(
            f"{capture.key}: ordinary Desk slot is not focused"
        )
    region, _bar, menu = _require_ordinary_menu_state(offer, capture, opened)
    expected = [(menu, ControlKind.MENU)]
    if opened:
        expected += [
            (entry, ControlKind.MENU_ITEM)
            for entry in menu.entries
            if isinstance(entry, MenuItemDraw)
        ]
    evidence = []
    for control, kind in expected:
        identity = ControlIdentity(
            region.owner_id,
            region.owner_generation,
            control.control_id,
        )
        matches = tuple(
            target
            for target in display_state.hit_targets
            if target.identity == identity and target.kind is kind
        )
        if len(matches) != 1:
            raise PhysicalDesktopAcceptanceError(
                f"{capture.key}: missing or ambiguous physical target {identity}"
            )
        target = matches[0]
        if target.rect.width <= 0 or target.rect.height <= 0:
            raise PhysicalDesktopAcceptanceError(
                f"{capture.key}: empty physical menu target"
            )
        center_x = target.rect.left + target.rect.width // 2
        center_y = target.rect.top + target.rect.height // 2
        if display_state.hit_test(center_x, center_y, display_token=token) != target:
            raise PhysicalDesktopAcceptanceError(
                f"{capture.key}: menu target is occluded in acknowledged "
                "painter order"
            )
        evidence.append(
            _control_target_evidence(
                target,
                label=control.label,
                shortcut=getattr(control, "shortcut", ""),
            )
        )
    return evidence


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


_POINTER_INPUT_METHODS = frozenset(
    (
        "pointer_click",
        "pointer_drag",
        "pointer_drag_rest",
        "pointer_release",
        "pointer_wheel",
        "text_scroll",
        "text_place",
        "text_extend",
        "text_follow",
        "item_select",
        "item_open",
        "item_expand",
        "item_collapse",
        "item_check",
        "item_scroll",
        "field_adjust",
        "field_activate",
    )
)

# Item view events and the press on the item that the viewer turns into
# each one (SEMANTIC-CONTENT-1): OPEN is a second press on the item.
_ITEM_EVENTS = {
    "item_select": (ControlEventKind.SELECT, "select"),
    "item_open": (ControlEventKind.OPEN, "select"),
    "item_expand": (ControlEventKind.EXPAND, "expand"),
    "item_collapse": (ControlEventKind.COLLAPSE, "collapse"),
    "item_check": (ControlEventKind.CHECK, "check"),
    "item_scroll": (ControlEventKind.SCROLL, None),
}


def _canonical_integers(value: str, count: int, label: str) -> tuple[int, ...]:
    """Parse exactly count comma-separated canonical decimal integers."""

    parts = value.split(",") if isinstance(value, str) else ()
    try:
        numbers = tuple(int(part, 10) for part in parts)
    except ValueError as exc:
        raise PhysicalDesktopAcceptanceError(
            f"{label} carries a noncanonical value"
        ) from exc
    if len(numbers) != count or ",".join(map(str, numbers)) != value:
        raise PhysicalDesktopAcceptanceError(
            f"{label} carries a noncanonical value"
        )
    return numbers


def _exact_hit_map_token(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    label: str,
) -> tuple[int, DisplayScope]:
    token = (offer.offer_id, offer.scope)
    if display_state.hit_map_token != token or display_ack != token:
        raise PhysicalDesktopAcceptanceError(
            f"{label} lacks the exact acknowledged hit map"
        )
    return token


def _residual_pointer_point(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    cell: tuple[int, int],
    *,
    cell_width: int,
    cell_height: int,
) -> tuple[int, int]:
    """Prove the viewer would start a raw gesture at this cell's center."""

    token = _exact_hit_map_token(offer, display_state, display_ack, "raw pointer input")
    column, row = cell
    x = column * cell_width + cell_width // 2
    y = row * cell_height + cell_height // 2
    target = display_state.resolve_pointer(
        x,
        y,
        display_token=token,
        cell_width=cell_width,
        cell_height=cell_height,
    )
    if target != ResidualPoint(column, row):
        raise PhysicalDesktopAcceptanceError(
            f"cell ({column}, {row}) is not residual content in the "
            "acknowledged hit map"
        )
    return x, y


def _text_hit_target(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    identity: ControlIdentity,
    kinds: tuple[ControlKind, ...],
) -> tuple[TextHitTarget, tuple[int, DisplayScope]]:
    token = _exact_hit_map_token(offer, display_state, display_ack, "text input")
    target = display_state.text_target(identity, display_token=token)
    if target is None or target.kind not in kinds:
        names = " or ".join(kind.name for kind in kinds)
        raise PhysicalDesktopAcceptanceError(
            f"acknowledged hit map has no enabled {names} target for the "
            "requested root"
        )
    return target, token


def _text_target_point(
    display_state: _RetainedDisplayState,
    token: tuple[int, DisplayScope],
    target: TextHitTarget,
    position: TextPosition | None,
    *,
    cell_width: int,
    cell_height: int,
    link: bool = False,
) -> tuple[int, int]:
    """Find a visible point the viewer maps to position, or any for None;
    with LINK, a point the viewer also finds a link at, where a Ctrl press
    follows it.

    Points are sampled every half cell and must resolve to this root in the
    acknowledged painter order, so nothing painted above it covers them.
    """

    rect = target.rect
    step_x = max(1, cell_width // 2)
    step_y = max(1, cell_height // 2)
    for y in range(rect.top + step_y // 2, rect.bottom, step_y):
        for x in range(rect.left + step_x // 2, rect.right, step_x):
            if position is not None and target.position_at(x, y) != position:
                continue
            if link and target.link_at(x, y) != position:
                continue
            if (
                display_state.resolve_pointer(
                    x,
                    y,
                    display_token=token,
                    cell_width=cell_width,
                    cell_height=cell_height,
                )
                == target
            ):
                return x, y
    raise PhysicalDesktopAcceptanceError(
        f"{target.kind.name} position is not painted at any visible point"
    )


def _item_hit_target(
    offer: TerminalDisplayOffer,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    identity: ControlIdentity,
) -> tuple[ItemHitTarget, tuple[int, DisplayScope]]:
    token = _exact_hit_map_token(offer, display_state, display_ack, "item input")
    target = display_state.item_target(identity, display_token=token)
    if target is None:
        raise PhysicalDesktopAcceptanceError(
            "acknowledged hit map has no enabled ITEM_VIEW target for the "
            "requested root"
        )
    return target, token


def _item_target_point(
    display_state: _RetainedDisplayState,
    token: tuple[int, DisplayScope],
    target: ItemHitTarget,
    press: tuple[str, int] | None,
    *,
    cell_width: int,
    cell_height: int,
) -> tuple[int, int]:
    """Find a visible point where the viewer's press asks for PRESS, an
    (action, item key) pair, or any point of the root for None.

    Points are sampled every half cell and must resolve to this root in the
    acknowledged painter order, so nothing painted above it covers them.
    """

    rect = target.rect
    step_x = max(1, cell_width // 2)
    step_y = max(1, cell_height // 2)
    for y in range(rect.top + step_y // 2, rect.bottom, step_y):
        for x in range(rect.left + step_x // 2, rect.right, step_x):
            if press is not None and target.item_at(x, y) != press:
                continue
            if (
                display_state.resolve_pointer(
                    x,
                    y,
                    display_token=token,
                    cell_width=cell_width,
                    cell_height=cell_height,
                )
                == target
            ):
                return x, y
    raise PhysicalDesktopAcceptanceError(
        f"ITEM_VIEW press {press!r} is not painted at any visible point"
    )


def _request_field_input(
    client: SessionClient,
    method: str,
    value: str,
    offer: TerminalDisplayOffer,
    params: dict[str, object],
    *,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    cell_width: int,
    cell_height: int,
) -> tuple[str, AcceptedInputEvidence | None]:
    """Send one FIELD intent at its exact acknowledged, unoccluded value slot."""

    adjusting = method == "field_adjust"
    values = _canonical_integers(value, 4 if adjusting else 3, method)
    owner_id, owner_generation, control_id = values[:3]
    count = values[3] if adjusting else 0
    if adjusting and (count == 0 or not -(1 << 63) <= count < (1 << 63)):
        raise PhysicalDesktopAcceptanceError("field adjustment must be nonzero signed i64")
    identity = ControlIdentity(owner_id, owner_generation, control_id)
    token = _exact_hit_map_token(offer, display_state, display_ack, "field input")
    draws = tuple(
        (region, draw)
        for region in (() if offer.retained is None else offer.retained.regions)
        for draw in region.draws
        if isinstance(draw, FieldDraw)
        and (region.owner_id, region.owner_generation, draw.control_id)
        == (owner_id, owner_generation, control_id)
    )
    targets = tuple(
        target for target in display_state.hit_targets
        if isinstance(target, FieldHitTarget) and target.identity == identity
    )
    if len(draws) != 1 or len(targets) != 1:
        raise PhysicalDesktopAcceptanceError("field input requires one acknowledged FIELD value target")
    region, draw = draws[0]
    target = targets[0]
    content = draw.content
    enabled = ControlState.VISIBLE | ControlState.ENABLED
    if draw.state & enabled != enabled or content.read_only:
        raise PhysicalDesktopAcceptanceError("field input requires an enabled writable FIELD")
    if target.content_revision != content.content_revision or target.adjustable != content.is_adjustable:
        raise PhysicalDesktopAcceptanceError("FIELD hit target does not match its committed content revision or kind")
    if adjusting and not target.adjustable:
        raise PhysicalDesktopAcceptanceError("FIELD value target does not permit adjustment")
    logical, visible = _visible_draw_rectangle(region, draw, offer.cell.cols, offer.cell.rows)
    slot = content.value_bounds
    value_rect = _LogicalRectangle(logical.left + slot.x, logical.top + slot.y,
                                   logical.left + slot.right, logical.top + slot.bottom)
    clipped = None if visible is None else _rectangle_intersection(value_rect, visible)
    expected_rect = None if clipped is None else PixelRect(
        clipped.left * cell_width, clipped.top * cell_height,
        clipped.right * cell_width, clipped.bottom * cell_height,
    )
    if target.rect != expected_rect:
        raise PhysicalDesktopAcceptanceError("FIELD hit target is not its exact clipped value slot")
    point = None
    step_x, step_y = max(1, cell_width // 2), max(1, cell_height // 2)
    for y in range(target.rect.top + step_y // 2, target.rect.bottom, step_y):
        for x in range(target.rect.left + step_x // 2, target.rect.right, step_x):
            if display_state.resolve_pointer(
                x, y, display_token=token, cell_width=cell_width, cell_height=cell_height,
            ) == target:
                point = (x, y)
                break
        if point is not None:
            break
    if point is None:
        raise PhysicalDesktopAcceptanceError("FIELD value slot is occluded in the acknowledged hit map")
    request = dict(params, owner_id=owner_id, owner_generation=owner_generation,
                   control_id=control_id, modifiers=0)
    evidence = _control_target_evidence(target, label=draw.label)
    evidence.update(content_revision=content.content_revision, pixel=list(point),
                    event_kind="ADJUST" if adjusting else "ACTIVATE")
    if adjusting:
        request.update(event_kind=int(ControlEventKind.ADJUST),
                       content_revision=content.content_revision, adjustment=count)
        evidence["adjustment"] = count
    rpc_method = "send_text_event" if adjusting else "send_control_event"
    if _display_bound_status(client, rpc_method, request) != "progress":
        return "backpressured", None
    return "progress", AcceptedInputEvidence(
        rpc_method, f"{method} {value}", offer.offer_id, params["generation"],
        display_scope_to_wire(offer.scope), evidence,
    )


def _request_item_input(
    client: SessionClient,
    method: str,
    value: str,
    offer: TerminalDisplayOffer,
    params: dict[str, object],
    *,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    cell_width: int,
    cell_height: int,
) -> tuple[str, AcceptedInputEvidence | None]:
    """Send one item event, or SCROLL, where the physical viewer would: at a
    visible point its own item layout maps to that press on that item."""

    kind, action = _ITEM_EVENTS[method]
    owner_id, owner_generation, control_id, field = _canonical_integers(
        value, 4, method
    )
    identity = ControlIdentity(owner_id, owner_generation, control_id)
    target, token = _item_hit_target(offer, display_state, display_ack, identity)
    if kind is ControlEventKind.SCROLL:
        if not field:
            raise PhysicalDesktopAcceptanceError("item scroll input carries no detent")
        press = None
    else:
        press = (action, field)
    x, y = _item_target_point(
        display_state,
        token,
        target,
        press,
        cell_width=cell_width,
        cell_height=cell_height,
    )
    request = dict(
        params,
        owner_id=owner_id,
        owner_generation=owner_generation,
        control_id=control_id,
        event_kind=int(kind),
        modifiers=0,
    )
    evidence = {
        "kind": ControlKind.ITEM_VIEW.name,
        "owner_id": owner_id,
        "owner_generation": owner_generation,
        "control_id": control_id,
        "content_revision": target.content_revision,
        "pixel": [x, y],
        "event_kind": kind.name,
    }
    if kind is ControlEventKind.SCROLL:
        request.update(wheel_x=0, wheel_y=field)
        evidence["wheel_y"] = field
    else:
        request.update(content_revision=target.content_revision, item_key=field)
        evidence["item_key"] = field
    if _display_bound_status(client, "send_text_event", request) != "progress":
        return "backpressured", None
    return "progress", AcceptedInputEvidence(
        "send_text_event",
        f"{method} {value}",
        offer.offer_id,
        params["generation"],
        display_scope_to_wire(offer.scope),
        evidence,
    )


def _display_bound_status(client: SessionClient, rpc_method: str, params) -> str:
    """Send one display-bound input and return progress or backpressured."""

    response = client.request(rpc_method, **params)
    status = response.get("status")
    accepted = response.get("accepted_events")
    if status == "progress" and accepted == 1:
        return status
    if status == "backpressured" and accepted == 0:
        return status
    if status in ("progress", "backpressured"):
        raise PhysicalDesktopAcceptanceError(
            f"{rpc_method} reported partial acceptance"
        )
    raise PhysicalDesktopAcceptanceError(
        f"{rpc_method} returned invalid status {status!r}"
    )


def _request_pointer_input(
    client: SessionClient,
    method: str,
    value: str,
    offer: TerminalDisplayOffer,
    params: dict[str, object],
    *,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    cell_width: int | None,
    cell_height: int | None,
) -> tuple[str, AcceptedInputEvidence | None]:
    """Send one mouse action exactly where the physical viewer would.

    Residual cells take raw POINTER input.  A click is its press and release,
    and a drag its press, one move with the button held, and release, all
    against the same acknowledged frame.  Once the guest has seen a press the
    rest of that gesture is owed: the status is ``release_owed`` when only
    the release was backpressured and ``drag_owed`` when the move was too,
    and the journey must deliver it before any other input.  Text roots take
    PLACE, EXTEND, or SCROLL at a point whose position comes from the
    viewer's own layout; SCROLL also reaches TEXT_GRID roots.
    """

    if (
        not isinstance(cell_width, int)
        or not isinstance(cell_height, int)
        or cell_width <= 0
        or cell_height <= 0
    ):
        raise PhysicalDesktopAcceptanceError(
            "pointer input requires the physical cell geometry"
        )
    if method in ("field_adjust", "field_activate"):
        return _request_field_input(
            client, method, value, offer, params, display_state=display_state,
            display_ack=display_ack, cell_width=cell_width, cell_height=cell_height,
        )
    if method in _ITEM_EVENTS:
        return _request_item_input(
            client,
            method,
            value,
            offer,
            params,
            display_state=display_state,
            display_ack=display_ack,
            cell_width=cell_width,
            cell_height=cell_height,
        )
    generation = params["generation"]
    scope = display_scope_to_wire(offer.scope)
    if not method.startswith("text_"):
        detents = 0
        if method == "pointer_wheel":
            column, row, detents = _canonical_integers(value, 3, method)
            if not detents:
                raise PhysicalDesktopAcceptanceError(
                    "pointer wheel input carries no detent"
                )
            cells = ((column, row),)
        elif method == "pointer_drag":
            start_column, start_row, column, row = _canonical_integers(
                value, 4, method
            )
            if (start_column, start_row) == (column, row):
                raise PhysicalDesktopAcceptanceError(
                    "pointer drag input does not move"
                )
            cells = ((start_column, start_row), (column, row))
        else:
            column, row = _canonical_integers(value, 2, method)
            cells = ((column, row),)
        pixels = [
            _residual_pointer_point(
                offer,
                display_state,
                display_ack,
                cell,
                cell_width=cell_width,
                cell_height=cell_height,
            )
            for cell in cells
        ]
        pointer = dict(params, modifiers=0, wheel_x=0, wheel_y=0)

        def at(cell: tuple[int, int], **fields) -> dict[str, object]:
            return dict(pointer, x=cell[0], y=cell[1], **fields)

        start, end = cells[0], cells[-1]
        press = ("press", at(start, buttons=1, kind=2))
        move = ("move", at(end, buttons=1, kind=1))
        release = ("release", at(end, buttons=0, kind=3))
        requests = {
            "pointer_wheel": [("wheel", at(end, buttons=0, kind=4, wheel_y=detents))],
            "pointer_release": [release],
            "pointer_click": [press, release],
            "pointer_drag": [press, move, release],
            "pointer_drag_rest": [move, release],
        }[method]
        events: list[str] = []
        status = "progress"
        for event, request in requests:
            if _display_bound_status(client, "send_pointer", request) != "progress":
                if not events:
                    return "backpressured", None
                status = "release_owed" if event == "release" else "drag_owed"
                break
            events.append(event)
        target: dict[str, object] = {
            "kind": "RESIDUAL",
            "cell": [column, row],
            "pixel": list(pixels[-1]),
            "events": events,
        }
        if len(cells) == 2:
            target["start_cell"] = list(start)
            target["start_pixel"] = list(pixels[0])
        if detents:
            target["wheel_y"] = detents
        return status, AcceptedInputEvidence(
            "send_pointer",
            f"{method} {value}",
            offer.offer_id,
            generation,
            scope,
            target,
        )

    if method == "text_scroll":
        owner_id, owner_generation, control_id, detents = _canonical_integers(
            value, 4, method
        )
        position = None
        if not detents:
            raise PhysicalDesktopAcceptanceError(
                "text scroll input carries no detent"
            )
    else:
        owner_id, owner_generation, control_id, item_key, offset = (
            _canonical_integers(value, 5, method)
        )
        position = TextPosition(item_key, offset)
    identity = ControlIdentity(owner_id, owner_generation, control_id)
    text_target, token = _text_hit_target(
        offer,
        display_state,
        display_ack,
        identity,
        (ControlKind.TEXT_AREA, ControlKind.TEXT_GRID)
        if position is None or method == "text_place"
        else (ControlKind.TEXT_AREA,),
    )
    x, y = _text_target_point(
        display_state,
        token,
        text_target,
        position,
        cell_width=cell_width,
        cell_height=cell_height,
        link=method == "text_follow",
    )
    # A link is followed as the viewer follows it: Ctrl and a press.
    request = dict(
        params,
        owner_id=owner_id,
        owner_generation=owner_generation,
        control_id=control_id,
        modifiers=2 if method == "text_follow" else 0,
    )
    target = {
        "kind": text_target.kind.name,
        "owner_id": owner_id,
        "owner_generation": owner_generation,
        "control_id": control_id,
        "content_revision": text_target.content_revision,
        "pixel": [x, y],
    }
    if position is None:
        event_kind = ControlEventKind.SCROLL
        request.update(event_kind=int(event_kind), wheel_x=0, wheel_y=detents)
        target["wheel_y"] = detents
    else:
        event_kind = {
            "text_place": ControlEventKind.PLACE,
            "text_extend": ControlEventKind.EXTEND,
            "text_follow": ControlEventKind.FOLLOW,
        }[method]
        request.update(
            event_kind=int(event_kind),
            content_revision=text_target.content_revision,
            item_key=position.item_key,
            scalar_offset=position.scalar_offset,
        )
        target["position"] = [position.item_key, position.scalar_offset]
    target["event_kind"] = event_kind.name
    if _display_bound_status(client, "send_text_event", request) != "progress":
        return "backpressured", None
    return "progress", AcceptedInputEvidence(
        "send_text_event",
        f"{method} {value}",
        offer.offer_id,
        generation,
        scope,
        target,
    )


def _request_acceptance_input(
    client: SessionClient,
    method: str,
    value: str,
    offer: TerminalDisplayOffer,
    generation: int,
    *,
    display_state: _RetainedDisplayState,
    display_ack: tuple[int, DisplayScope] | None,
    cell_width: int | None = None,
    cell_height: int | None = None,
) -> tuple[str, AcceptedInputEvidence | None]:
    """Send one display-bound journey action and preserve exact evidence."""

    params: dict[str, object] = {
        "generation": generation,
        "display_offer_id": offer.offer_id,
        "display_scope": display_scope_to_wire(offer.scope),
    }
    if method in _POINTER_INPUT_METHODS:
        return _request_pointer_input(
            client,
            method,
            value,
            offer,
            params,
            display_state=display_state,
            display_ack=display_ack,
            cell_width=cell_width,
            cell_height=cell_height,
        )
    rpc_method = method
    evidence_value = value
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
    elif method in ("activate_shell_task", "activate_shell_launcher"):
        owner, owner_generation, control_id = _canonical_integers(value, 3, "shell activation")
        identity = ControlIdentity(owner, owner_generation, control_id)
        kind = ControlKind.TASK if method == "activate_shell_task" else ControlKind.LAUNCHER
        target, label = _shell_hit_target(offer, display_state, display_ack, identity, kind)
        rpc_method = "send_control_event"
        params.update(owner_id=owner, owner_generation=owner_generation,
                      control_id=control_id, modifiers=0)
        semantic_target = _control_target_evidence(target, label=label)
    elif method in ("activate_ordinary_menu", "close_ordinary_menu"):
        capture = ORDINARY_MENU_CAPTURES.get(value)
        if capture is None:
            raise PhysicalDesktopAcceptanceError(
                f"unknown ordinary menu capture {value!r}"
            )
        opened = method == "close_ordinary_menu"
        targets = _ordinary_menu_hit_evidence(
            offer,
            capture,
            display_state,
            display_ack,
            opened,
        )
        if opened:
            # Escape closes the popup; bind the whole acknowledged popup.
            rpc_method = "send_key"
            evidence_value = "escape"
            params["key"] = "escape"
            semantic_target = {
                "kind": "MENU_POPUP",
                "label": value,
                "targets": targets,
            }
        else:
            rpc_method = "send_control_event"
            params.update(
                {
                    key: targets[0][key]
                    for key in ("owner_id", "owner_generation", "control_id")
                }
            )
            params["modifiers"] = 0
            semantic_target = targets[0]
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
            evidence_value,
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
class ShellNativeEntry:
    index: int
    key: int
    kind: int
    flags: int
    bounds: _LogicalRectangle
    content_bounds: _LogicalRectangle | None
    owner_id: int
    owner_generation: int
    identity: int
    action: int
    label: str
    title: str
    action_id: str

    @property
    def component(self):
        return self.identity, self.owner_id, self.owner_generation


@dataclass(frozen=True)
class ShellNativeModel:
    owner_id: int
    owner_generation: int
    epoch: int
    cols: int
    rows: int
    flags: int
    divider_col: int
    end_col: int
    entries: tuple[ShellNativeEntry, ...]
    sha256: str


def _shell_require(condition, reason):
    if not condition:
        raise PhysicalDesktopAcceptanceError(f"shell source {reason}")


def _shell_text(raw):
    try:
        value = raw.decode("utf-8", "strict")
    except UnicodeError as exc:
        raise PhysicalDesktopAcceptanceError("shell source has malformed UTF-8") from exc
    _shell_require(not any(ord(char) < 32 or 127 <= ord(char) <= 159 or
                           ord(char) in (0x2028, 0x2029) for char in value),
                   "text contains a control or line separator")
    return value


def _decode_shell_model(payload: bytes) -> ShellNativeModel:
    """Decode the actual bounded, pointer-free SHSN copy of ordinary SHM."""
    _shell_require(isinstance(payload, bytes) and 128 <= len(payload) <= 49152,
                   "model extent is outside the canonical owned bank")
    h = struct.unpack_from("<16Q", payload)
    abi, capacity, limit, count, used, owner, generation, epoch, cols, rows, flags, divider, end, ready, r0, r1 = h
    _shell_require(abi == 1 and capacity == used == len(payload) and ready == (1 << 64) - 1 and
                   r0 == r1 == 0 and owner > 0 and generation > 0 and epoch > 0,
                   "model header is not a complete immutable SHM")
    _shell_require(0 < cols < 1 << 32 and 0 < rows < 1 << 32 and flags & ~3 == 0 and
                   (not flags & 1 or flags == 3), "surface or model flags are invalid")
    divider = _signed_cell(divider)
    _shell_require(divider == -1 or 0 <= divider < cols, "divider is outside the surface")
    _shell_require(end <= cols and (not flags & 1 or divider == -1 and end == 0),
                   "taskbar endpoint is invalid")
    _shell_require(count <= limit <= (len(payload) - 128) // 168,
                   "entry reservation is outside the model")
    cursor = 128 + 168 * limit
    _shell_require(not any(payload[128 + 168 * count:cursor]), "unused reserved entries are nonzero")
    entries, identities = [], set()
    last_kind = slot_end = selected = 0
    for index in range(count):
        v = struct.unpack_from("<21Q", payload, 128 + index * 168)
        key, kind, entry_flags, row, col, height, width, crow, ccol, ch, cw, child_owner, child_gen, identity, action = v[:15]
        identity, action = _signed_cell(identity), _signed_cell(action)
        _shell_require(0 < key < 1 << 63 and child_owner > 0 and child_gen > 0 and last_kind <= kind <= 3 and kind >= 1,
                       "entry kind, ordering or lifecycle identity is invalid")
        last_kind = kind
        signature = (kind, key, identity, child_owner, child_gen)
        _shell_require(signature not in identities, "entry lifecycle identity is duplicated")
        identities.add(signature)
        _shell_require(height > 0 and width > 0 and row + height <= rows and col + width <= cols,
                       "entry rectangle is outside its source surface")
        bounds = _LogicalRectangle(col, row, col + width, row + height)
        strings = []
        for offset, size in zip(v[15::2], v[16::2]):
            _shell_require((size == 0 and offset in (0, cursor)) or
                           (size > 0 and offset == cursor and size <= len(payload) - cursor),
                           "text spans are not an exact ordered owned partition")
            strings.append(_shell_text(payload[cursor:cursor + size]))
            cursor += size
        label, title, action_id = strings
        content = None
        if kind == 1:
            _shell_require(entry_flags & ~9 == 0 and identity not in (0, -1) and action == identity and
                           (identity < -1 and key == -identity if entry_flags & 8 else identity > 0 and key == identity),
                           "PANE flags or signed slot identity are invalid")
            _shell_require(ch > 0 and cw > 0 and row <= crow and col <= ccol and
                           crow + ch <= row + height and ccol + cw <= col + width and
                           not label and not action_id, "PANE content or text fields are invalid")
            content = _LogicalRectangle(ccol, crow, ccol + cw, crow + ch)
        else:
            _shell_require(not flags & 1 and (crow, ccol, ch, cw) == (0, 0, 0, 0) and
                           height == 1 and row == rows - 1 and col >= slot_end and
                           text_rules.string_width(label) == width,
                           "taskbar slot geometry or exact label width is invalid")
            slot_end = col + width
            if kind == 2:
                _shell_require(entry_flags & ~3 == 0 and entry_flags != 3 and
                               identity > 0 and key == action == identity and not action_id,
                               "TASK state or ordinary slot action is invalid")
                selected += bool(entry_flags & 1)
                _shell_require(selected <= 1, "more than one ordinary task is selected")
            else:
                _shell_require(entry_flags & ~52 == 0 and (child_owner, child_gen) == (owner, generation),
                               "LAUNCHER flags or root ownership are invalid")
                _shell_require((action == 0 and entry_flags & 4 and identity == 0 and not action_id) or
                               (action == key and identity > 0 and bool(action_id)),
                               "LAUNCHER catalog authority is invalid")
        entries.append(ShellNativeEntry(index, key, kind, entry_flags, bounds, content,
                                        child_owner, child_gen, identity, action, label, title, action_id))
    _shell_require(cursor == len(payload) and slot_end <= end, "model has unowned trailing text or slots")
    return ShellNativeModel(owner, generation, epoch, cols, rows, flags, divider, end,
                            tuple(entries), hashlib.sha256(payload).hexdigest())


@dataclass(frozen=True)
class ShellSource:
    model: ShellNativeModel
    correlations: tuple[tuple[int, ...], ...]
    actions: bytes
    owner_id: int
    owner_generation: int
    draw: int
    physical_generation: int
    model_revision: int
    launcher_slots: tuple[tuple[int, int], ...]
    memory: dict[str, int]


def _shell_cells(client, address, count, *, dictionary_body=False):
    _shell_require(type(address) is int and type(count) is int and address > 0 and
                   (dictionary_body or address % 8 == 0) and
                   0 < count <= (2 if dictionary_body else 49152 // 8) and
                   address + count * 8 <= 1 << 64, "read exceeds its bounded aligned span")
    values = _read_guest_cells(client, address=address, count=count)
    _shell_require(all(type(value) is int and 0 <= value < 1 << 64 for value in values),
                   "read contains a non-cell value")
    return values


def _shell_bytes(client, address, size, capacity):
    _shell_require(type(size) is int and type(capacity) is int and
                   0 <= size <= min(capacity, 49152) and type(address) is int and
                   address > 0 and address % 8 == 0 and address + capacity <= 1 << 64,
                   "byte extent exceeds its owned bound")
    if not size:
        return b""
    rounded = (size + 7) & ~7
    if rounded <= capacity:
        cells = _shell_cells(client, address, rounded // 8)
        return struct.pack(f"<{len(cells)}Q", *cells)[:size]
    # An exactly sized immutable SHM may end in an unaligned string. Read
    # the final cell wholly inside that owned span, overlapping earlier bytes.
    _shell_require(size >= 8, "short byte span has no bounded cell read")
    cells = _shell_cells(client, address, size // 8)
    tail = _read_guest_cells(client, address=address + size - 8, count=1)[0]
    _shell_require(type(tail) is int and 0 <= tail < 1 << 64, "tail read contains a non-cell")
    return struct.pack(f"<{len(cells)}Q", *cells) + struct.pack("<Q", tail)[-(size % 8):]


def _read_shell_source(client, offer, generation, *, diagnostics=None) -> ShellSource | None:
    """Read only bounded native metadata at a paused, completed PRESENT boundary.

    None means the displayed offer and the live guest have not converged yet.
    Invalid owned extents fail before reading their payload. No Forth executes.
    An optional dictionary receives bounded metadata and the exact pending gate;
    collecting it adds no guest reads and changes no acceptance condition.
    """
    def note(name, value):
        if diagnostics is not None:
            diagnostics[name] = value

    def pending(reason):
        note("pending_reason", reason)
        return None

    if diagnostics is not None:
        diagnostics.clear()
        diagnostics.update(offer_id=offer.offer_id, generation=generation,
                           session_id=offer.scope.session_id,
                           presentation_epoch=offer.scope.presentation_epoch,
                           geometry_generation=offer.scope.geometry_generation,
                           model_revision=offer.scope.model_revision,
                           retained_revision=offer.scope.retained_revision)
    before = client.request("status", detailed=False)
    note("status_before", {key: before.get(key) for key in ("paused", "generation", "error")})
    _shell_require(type(before.get("paused")) is bool and not before.get("error"),
                   "requires a healthy pause boundary")
    if before.get("generation") != generation:
        return pending("execution-generation-before-pause")
    resume_after = transport_failed = False
    try:
        paused = client.request("pause")
        _shell_require(paused.get("paused") is True and not paused.get("error"), "pause failed")
        resume_after = not before["paused"]
        paused_generation = client.request("status", detailed=False).get("generation")
        note("paused_generation", paused_generation)
        if paused_generation != generation:
            return pending("execution-generation-after-pause")
        names = ("_RTAPTSCBOP-CONTEXT", "_RTAPTSCBI-ENGINE", "_DESK-CURRENT-STATE", "_DESK-CATALOG",
                 "_SHSN-INSTALLED", "_SHSN-REFUSED", "_SCR-CUR", "_SHSN-H-H", "_SHSN-H-M",
                 "_AH-SHELL-OBSERVER", "_AH-SHELL-OBSERVER-CTX", "_ASHELL-DRAW-OBSERVER",
                 "_ASHELL-DRAW-OBSERVER-CTX", "_SHSN-HOST-CALL", "_SHSN-DRAW-CALL")
        words = client.request("forth", names=list(names)).get("words", {})
        try:
            def body(name, count=1):
                values = _shell_cells(client, words[name]["data_address"], count, dictionary_body=True)
                note(name, {"address": words[name]["data_address"], "values": values})
                return values
            producer, engine = body(names[0])[0], body(names[1])[0]
            p = _shell_cells(client, producer, 517)
            note("producer", p)
            _shell_require(p[:3] == [0x3250444952425948, 4136, producer], "RTHP descriptor is invalid")
            e = _shell_cells(client, engine, 42)
            note("engine", e)
            _shell_require(e[0] == 0x5254415054454E47, "provider descriptor is invalid")
            session = _shell_cells(client, e[1], 124)
            note("session", session)
            if (session[15] != 3 or session[19] != offer.scope.session_id or
                    session[33] != offer.scope.presentation_epoch or
                    session[54] != offer.scope.geometry_generation or
                    session[24:26] != [offer.cell.cols, offer.cell.rows] or
                    session[37] or session[48] or session[51]):
                return pending("active-session-scope-or-output-state")
            # LAST-REVISION is the reconciled global PRESENT result, not a
            # durable retained-only revision. Require this exact idle output.
            revision = offer.scope.model_revision
            if (e[14] or e[15] or e[28:31] != [0, 0, 0] or
                    e[31] != revision or revision != offer.scope.retained_revision):
                return pending("idle-provider-present-revision")
            completion = e[32:42]
            if (completion[:4] != [1, 0x2001, 0, 0] or not completion[4] or
                    completion[5] != revision or any(completion[6:])):
                return pending("successful-present-completion")
            extension = p[516]
            if not extension or not p[298]:
                return pending("active-shell-extension-or-target")
            x = _shell_cells(client, extension, 8)
            note("extension", x)
            _shell_require(x[:3] == [0x5254485045585431, 64, extension], "extension descriptor is invalid")
            sidecar = x[3]
            s = _shell_cells(client, sidecar, 30)
            note("sidecar", s)
            _shell_require(s[:4] == [0x5253485350303031, 240, sidecar, producer] and
                           extension == sidecar + 176, "sidecar descriptor has foreign provenance")
            bank = s[12]
            if not bank:
                return pending("committed-shell-bank")
            _shell_require(bank in (s[8], s[10]) and s[8] != s[10], "active bank is not caller-owned")
            capacity = s[9] if bank == s[8] else s[11]
            _shell_require(128 <= capacity <= 64 * 1024 * 1024 and bank + capacity <= 1 << 64 and
                           0 < s[7] <= 64 * 1024 * 1024 and s[19] <= s[7] and
                           0 < s[20] <= 512 and s[21] <= 49152, "configured storage or work usage is invalid")
            b = _shell_cells(client, bank, 16)
            note("bank", b)
            _shell_require(128 <= b[0] <= capacity and b[0] % 8 == 0,
                           "committed bank used extent exceeds capacity or is unaligned")
            target = p[298]
            # Hosted dictionary metadata does not expose CONSTANT values.
            # Mirror _RTHP-ARENA-SPAN? against the authenticated descriptor;
            # only this fixed header is read, never the entire arena extent.
            _shell_require(target in (p[296], p[297]) and p[296] != p[297] and
                           target % 8 == 0 and 0 < p[5] <= target and 336 <= p[6] < 1 << 63 and
                           target + 336 <= p[5] + p[6] < 1 << 64,
                           "active target header is outside the producer-owned arena")
            if (s[14] != target or b[10] != target or not b[11] or
                    s[16] != b[11] or p[302] != b[11]):
                return pending("acknowledged-target-draw")
            t = _shell_cells(client, target, 42)
            note("target", t)
            _shell_require(t[25] == 0x3354475450485452, "active target header is invalid")
            if (t[:2] != b[12:14] or b[12:14] != p[11:13] or
                    t[5] != b[11] or t[7] != p[57] or
                    t[2:4] != [offer.cell.cols, offer.cell.rows]):
                return pending("target-owner-geometry-physical-generation")
            # Every copied subspan must belong to the USED prefix, even
            # membership/batch spans whose contents this reader never needs.
            spans = []
            next_offset = 128
            for offset, size in ((b[2], b[3]), (b[4], b[5]), (b[6], b[7]), (b[8], b[9])):
                _shell_require((not size and offset == 0) or
                               (size > 0 and offset == next_offset and size <= b[0] - offset),
                               "copied subspan escapes committed bank")
                if size:
                    spans.append((offset, offset + size))
                    next_offset += (size + 7) & ~7
            _shell_require(all(left[1] <= right[0] for left, right in zip(sorted(spans), sorted(spans)[1:])) and
                           128 <= b[1] < b[0] and b[1] == next_offset and
                           all(not start <= b[1] < end for start, end in spans),
                           "copied subspans overlap or alias the family batch")
            _shell_require(128 <= b[3] <= 49152 and b[5] % 192 == 0 and
                           0 < b[5] <= (s[20] + 2) * 192 and b[5] <= 49152 and b[7] <= s[21],
                           "copied model, correlations or actions exceed their bounds")
            model_raw = _shell_bytes(client, bank + b[2], b[3], b[0] - b[2])
            model = _decode_shell_model(model_raw)
            _shell_require((model.cols, model.rows) == (offer.cell.cols, offer.cell.rows),
                           "ordinary surface differs from the acknowledged offer")
            _shell_require(len(model.entries) <= s[20], "model exceeds configured entry bound")
            correlations_raw = _shell_bytes(client, bank + b[4], b[5], b[0] - b[4])
            correlations = tuple(struct.unpack_from("<24Q", correlations_raw, offset)
                                 for offset in range(0, b[5], 192))
            actions = _shell_bytes(client, bank + b[6], b[7], b[0] - b[6])
            snapshot = _shell_cells(client, s[4], 20)
            note("snapshot", snapshot)
            _shell_require(snapshot[:3] == [0x31534E53484B4141, 160, s[4]], "SHSN descriptor is invalid")
            screen = body("_SCR-CUR")[0]
            if (snapshot[11] or snapshot[9] != b[11] or body("_SHSN-INSTALLED")[0] != s[4] or
                    body("_SHSN-REFUSED")[0] or not screen or snapshot[10] != screen or
                    body("_AH-SHELL-OBSERVER-CTX")[0] != s[4] or
                    body("_ASHELL-DRAW-OBSERVER-CTX")[0] != s[4] or
                    body("_AH-SHELL-OBSERVER")[0] != words["_SHSN-HOST-CALL"]["code"] or
                    body("_ASHELL-DRAW-OBSERVER")[0] != words["_SHSN-DRAW-CALL"]["code"] or
                    snapshot[13] != body("_SHSN-H-H")[0] or snapshot[14] != body("_SHSN-H-M")[0]):
                return pending("current-snapshot-observer-and-draw")
            screen_header = _shell_cells(client, screen, 12)
            note("screen", screen_header)
            if (screen_header[11] != b[11] or screen_header[:2] != [model.cols, model.rows] or
                    snapshot[18:20] != screen_header[:2] or not snapshot[13] or
                    _shell_cells(client, snapshot[13] + 128, 1)[0] != snapshot[14]):
                return pending("current-screen-and-borrowed-model")
            current = snapshot[7]
            _shell_require(current in (snapshot[3], snapshot[5]) and snapshot[3] != snapshot[5],
                           "SHSN active copy is not caller-owned")
            current_capacity = snapshot[4] if current == snapshot[3] else snapshot[6]
            _shell_require(128 <= snapshot[8] <= current_capacity <= 49152 and
                           current + current_capacity <= 1 << 64, "SHSN owned extent is invalid")
            if _shell_bytes(client, current, snapshot[8], current_capacity) != model_raw:
                return pending("current-frozen-model-bytes")
            borrowed_header = _shell_cells(client, snapshot[14], 16)
            note("borrowed_header", borrowed_header)
            _shell_require(128 <= borrowed_header[4] <= borrowed_header[1] <= 49152,
                           "borrowed ordinary model exceeds its owned capacity")
            borrowed = bytearray(_shell_bytes(client, snapshot[14], borrowed_header[4], borrowed_header[1]))
            struct.pack_into("<Q", borrowed, 8, borrowed_header[4])
            if borrowed != model_raw:
                return pending("current-borrowed-model-bytes")
            instance = _shell_cells(client, snapshot[12], 10)
            _shell_require(instance[2:4] == [model.owner_id, model.owner_generation] and instance[1] > 0,
                           "root component lifecycle differs from SHM")
            state_cell, catalog_offset = body("_DESK-CATALOG", 2)
            _shell_require(state_cell == words["_DESK-CURRENT-STATE"]["data_address"] and
                           catalog_offset % 8 == 0 and catalog_offset < 512 * 1024,
                           "catalog CMP field has foreign or unbounded provenance")
            catalog = _shell_cells(client, instance[1] + catalog_offset, 1)[0]
            catalog_header = _shell_cells(client, catalog, 5)
            _shell_require(catalog_header[0] == 0x4143415444455343 and
                           0 < catalog_header[3] and catalog_header[4] <= 32, "catalog header is invalid")
            launcher_slots = []
            for entry in model.entries:
                if entry.kind != 3 or not entry.action:
                    continue
                _shell_require(entry.identity == catalog_header[3] and 1 <= entry.action <= catalog_header[4],
                               "launcher catalog generation or selector is stale")
                record = _shell_cells(client, catalog + 1232 + (entry.action - 1) * 496, 62)
                _shell_require(record[2] <= 64, "catalog action ID exceeds its inline bound")
                action_id = _shell_text(struct.pack("<8Q", *record[6:14])[:record[2]])
                _shell_require(action_id == entry.action_id, "launcher copied action differs from catalog")
                if not entry.flags & 4:
                    _shell_require(record[0] & 1 and not record[0] & 8,
                                   "enabled launcher refers to disabled or quarantined catalog entry")
                launcher_slots.append((entry.index, record[61]))
            note("pending_reason", None)
            note("ready", True)
            return ShellSource(model, correlations, actions, b[12], b[13], b[11], t[7], revision,
                               tuple(launcher_slots), {"work_capacity": s[7], "work_used": s[19],
                               "bank_capacity": capacity, "bank_used": b[0], "model_bytes": b[3]})
        except KeyError as exc:
            raise PhysicalDesktopAcceptanceError("shell source dictionary metadata is unavailable") from exc
    except (ConnectionError, OSError):
        transport_failed = True
        raise
    finally:
        if resume_after and not transport_failed:
            _shell_require(client.request("resume").get("paused") is False,
                           "capture could not restore running state")


def _require_shell_source_evidence(projection, offer, generation, source: ShellSource) -> dict:
    """Prove every shell object from native identities, geometry and state."""
    model = source.model
    _shell_require(source.model_revision == offer.scope.model_revision == offer.scope.retained_revision,
                   "snapshot revision does not name this offer")
    _shell_require((model.cols, model.rows) == (projection.cols, projection.rows), "projection size differs")
    panes = {claim.object_id: claim for claim in projection.semantic_pane_claims}
    bars = {claim.identity.control_id: claim for claim in projection.semantic_taskbar_claims}
    tasks = {task.identity.control_id: task for bar in bars.values() for task in bar.tasks}
    root_regions = {draw.control_id: region.region_id for region in offer.retained.regions
                    for draw in region.draws if isinstance(draw, TaskBarDraw)}
    task_regions = {task.identity.control_id: root_regions[bar.identity.control_id]
                    for bar in bars.values() for task in bar.tasks}
    seen_entries, seen_panes, seen_bars, seen_tasks = set(), set(), set(), set()
    entry_controls = {}
    for v in source.correlations:
        _shell_require(len(v) == 24 and v[9:14] == (model.owner_id, model.owner_generation,
                       model.epoch, source.draw, model.owner_id), "correlation source lineage is invalid")
        index, kind = _signed_cell(v[0]), v[1]
        bounds = _LogicalRectangle(v[18], v[17], v[18] + v[20], v[17] + v[19])
        _shell_require(v[6] > 0 and v[7] > 0 and v[16] <= len(source.actions) - v[15],
                       "correlation object or action extent is invalid")
        action = _shell_text(source.actions[v[15]:v[15] + v[16]])
        if index < 0:
            _shell_require((index, kind) in ((-1, 4), (-2, 5)) and v[2:4] == (0, 0) and
                           v[4:6] == (model.owner_id, model.owner_generation) and
                           v[8] == 0 and v[14] == 0 and not action and v[22] == 0 and v[23] == model.flags,
                           "synthetic taskbar correlation is invalid")
            bar = bars.get(v[6])
            _shell_require(bar is not None and v[6] not in seen_bars and root_regions[v[6]] == v[7] and
                           bar.identity == ControlIdentity(source.owner_id, source.owner_generation, v[6]) and
                           bar.bounds == bounds and int(bar.state) == (1 if model.flags & 2 else 3),
                           "taskbar root differs from its native band")
            expected_left = 0 if kind == 4 or model.divider_col < 0 else model.divider_col + 2
            expected_right = (model.divider_col if model.divider_col >= 0 else model.end_col) if kind == 4 else model.end_col
            _shell_require(bounds == _LogicalRectangle(expected_left, model.rows - 1, expected_right, model.rows),
                           "taskbar root changed its ordinary band")
            seen_bars.add(v[6])
            continue
        _shell_require(0 <= index < len(model.entries) and index not in seen_entries, "entry correlation is missing or duplicated")
        entry = model.entries[index]
        _shell_require((kind, v[2], _signed_cell(v[3]), v[4], v[5], _signed_cell(v[14]), v[23]) ==
                       (entry.kind, entry.key, entry.identity, entry.owner_id, entry.owner_generation, entry.action, entry.flags)
                       and bounds == entry.bounds and action == entry.action_id,
                       "correlation differs from the copied ordinary entry")
        seen_entries.add(index)
        if kind == 1:
            claim = panes.get(v[6])
            _shell_require(claim is not None and v[6] not in seen_panes and
                           (claim.owner_id, claim.owner_generation, claim.region_id, claim.content_region_id) ==
                           (source.owner_id, source.owner_generation, v[7], v[8]) and
                           claim.bounds == bounds and claim.content_bounds == entry.content_bounds and
                           claim.title == entry.title and claim.focused == bool(entry.flags & 1) and
                           v[22] == len(entry.title.encode("utf-8")), "PANE differs from its ordinary entry")
            seen_panes.add(v[6])
        else:
            claim = tasks.get(v[6])
            state = (3 | (8 if entry.flags & 1 else 0) | (32 if entry.flags & 2 else 0)) if kind == 2 else (1 if entry.flags & 4 or not entry.action else 3)
            _shell_require(claim is not None and v[6] not in seen_tasks and v[8] == 0 and
                           claim.identity == ControlIdentity(source.owner_id, source.owner_generation, v[6]) and
                           claim.kind == (ControlKind.TASK if kind == 2 else ControlKind.LAUNCHER) and
                           claim.bounds == bounds and int(claim.state) == state and claim.order == index and
                           task_regions[v[6]] == v[7] and claim.label == entry.label and not claim.shortcut and
                           v[22] == len(entry.label.encode("utf-8")), "task or launcher differs from its ordinary entry")
            seen_tasks.add(v[6])
            entry_controls[index] = claim.identity
    _shell_require(seen_entries == set(range(len(model.entries))) and seen_panes == set(panes) and
                   seen_bars == set(bars) and seen_tasks == set(tasks), "shell projection is not a complete native bijection")
    return {"offer_id": offer.offer_id, "generation": generation, "scope": display_scope_to_wire(offer.scope),
            "source": "paused ordinary SHSN and acknowledged RSHSP bank", "model_sha256": model.sha256,
            "root_component": [model.owner_id, model.owner_generation], "epoch": model.epoch,
            "draw": source.draw, "physical_generation": source.physical_generation,
            "pane_count": len(panes), "taskbar_count": len(bars), "memory": dict(source.memory),
            "tasks": [{"component": list(entry.component), "flags": entry.flags,
                       "bounds": [entry.bounds.left, entry.bounds.top, entry.bounds.right, entry.bounds.bottom],
                       "control_id": entry_controls[entry.index].control_id}
                      for entry in model.entries if entry.kind == 2],
            "entry_controls": entry_controls}


class ShellAcceptanceProbe:
    """Exercise ordinary component lifecycle using exact acknowledged targets."""

    final_stage = 5

    def __init__(self):
        self.stage = 0
        self.pending = None
        self.awaiting_source = False
        self.frame_barrier = None
        self.evidence = {"snapshots": [], "memory_max": {}, "actions": []}
        self.original_panes = None
        self.target = self.launch_target = None

    @property
    def complete(self):
        return self.stage == self.final_stage

    def retry_pending_current(self, offer, generation, sender):
        if self.pending is None:
            return False
        method, value, stage, offer_id, scope, prior_generation = self.pending
        _shell_require((offer.offer_id, offer.scope, generation) == (offer_id, scope, prior_generation),
                       "backpressured input lost its exact acknowledged frame")
        status = sender(method, value, offer, generation)
        _shell_require(status in ("progress", "backpressured"), "input returned an unexpected status")
        if status == "progress":
            self.evidence["actions"].append({"method": method, "value": value, "offer_id": offer_id,
                                             "generation": generation, "scope": display_scope_to_wire(scope)})
            self.stage = stage
            self.pending = None
            self.frame_barrier = offer_id
        return status == "progress"

    def _send(self, method, value, stage, offer, generation, sender):
        self.pending = (method, value, stage, offer.offer_id, offer.scope, generation)
        self.retry_pending_current(offer, generation, sender)
        return False

    def after_present(self, projection, offer, generation, sender, source_reader):
        if self.complete:
            return True
        if self.pending is not None:
            if (offer.offer_id, offer.scope, generation) == self.pending[3:]:
                self.retry_pending_current(offer, generation, sender)
                return False
            # Backpressure accepted no input. A new acknowledged START may
            # assign every retained ID again; discard only that old authority
            # and resolve this stage's same ordinary component from the new
            # source. Never replay the old control ID against a fresh offer.
            self.pending = None
            self.awaiting_source = False
        if offer.offer_id == self.frame_barrier or not projection.semantic_pane_claims or not projection.semantic_taskbar_claims:
            return False
        source = source_reader()
        self.awaiting_source = source is None
        if source is None:
            return False
        snapshot = _require_shell_source_evidence(projection, offer, generation, source)
        controls = snapshot.pop("entry_controls")
        model = source.model
        _shell_require(model.flags == 0, "probe requires an ordinary unblocked shell")
        tasks = {entry.component: entry for entry in model.entries if entry.kind == 2}
        panes = {entry.component: (entry.bounds, entry.content_bounds) for entry in model.entries if entry.kind == 1}
        selected = [entry.component for entry in tasks.values() if entry.flags & 1]
        _shell_require(len(selected) == 1, "probe requires one selected ordinary task")
        if self.stage == 0:
            _shell_require(len(panes) == 6 and set(panes) == set(tasks) and all(not entry.flags & 2 for entry in tasks.values()),
                           "initial shell must contain the six visible ordinary components")
            if self.original_panes is None:
                self.original_panes = panes
                self.target = next(component for component in tasks if component != selected[0])
            else:
                _shell_require(panes == self.original_panes,
                               "initial source refresh changed ordinary component identity or pane geometry")
                _shell_require(selected[0] != self.target,
                               "initial source refresh already selected the unactivated target")
        else:
            _shell_require(set(tasks) == set(self.original_panes), "ordinary task lifecycle identities changed")
            if self.stage == 1 and selected[0] != self.target:
                return False
            if self.stage == 2 and not tasks[self.target].flags & 2:
                return False
            if self.stage == 3 and (tasks[self.target].flags & 2 or selected[0] != self.target):
                return False
            if self.stage == 4 and selected[0] != self.launch_target:
                return False
            if self.stage == 2:
                _shell_require(self.target not in panes and set(panes) == set(tasks) - {self.target},
                               "minimized component retained a PANE or removed another component")
            else:
                _shell_require(panes == self.original_panes and all(not entry.flags & 2 for entry in tasks.values()),
                               "focus or restoration changed ordinary pane geometry")
        snapshot["stage"] = self.stage
        if self.evidence["snapshots"] and self.evidence["snapshots"][-1]["stage"] == self.stage:
            self.evidence["snapshots"][-1] = snapshot
        else:
            self.evidence["snapshots"].append(snapshot)
        for name, value in source.memory.items():
            self.evidence["memory_max"][name] = max(self.evidence["memory_max"].get(name, 0), value)
        def activate(entry, next_stage):
            identity = controls[entry.index]
            value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id}"
            method = "activate_shell_task" if entry.kind == 2 else "activate_shell_launcher"
            return self._send(method, value, next_stage, offer, generation, sender)
        if self.stage == 0:
            return activate(tasks[self.target], 1)
        if self.stage == 1:
            return self._send("send_key", "alt+m", 2, offer, generation, sender)
        if self.stage == 2:
            return activate(tasks[self.target], 3)
        if self.stage == 3:
            slots = dict(source.launcher_slots)
            candidates = [(entry, component) for entry in model.entries
                          if entry.kind == 3 and entry.flags & 32 and not entry.flags & 4
                          for component in tasks if component[0] == slots.get(entry.index) and component != self.target
                          and (self.launch_target is None or component == self.launch_target)]
            _shell_require(bool(candidates), "no enabled running catalog launcher maps to another ordinary component")
            entry, self.launch_target = candidates[0]
            self.evidence["launcher"] = {"action_id": entry.action_id, "catalog_generation": entry.identity,
                                         "catalog_selector": entry.action, "component": list(self.launch_target)}
            return activate(entry, 4)
        self.stage = self.final_stage
        return True


class SoundLabSeriesProbe:
    """Ordinary acknowledged input after the complete Desk/Grid/FIELD journey."""

    def __init__(self):
        self.stage = 0
        self.pending = None
        self.evidence = {"renders": [], "stable_reuse": None}
        self.changed_amplitude = None
        self.prior_selection = None

    @property
    def complete(self):
        return self.stage == 13

    def retry_pending(self, offer, generation, sender):
        if self.pending is None:
            return False
        method, value, next_stage, offer_id, scope, prior_generation = self.pending
        if (offer.offer_id, offer.scope, generation) != (offer_id, scope, prior_generation):
            # Nothing was accepted. Resolve the same stage against the new
            # projection instead of replaying a retired FIELD identity or key.
            self.pending = None
            return False
        status = sender(method, value, offer, generation)
        if status not in ("progress", "backpressured"):
            raise PhysicalDesktopAcceptanceError("SERIES probe input returned an unexpected status")
        if status != "progress":
            return False
        self.stage = next_stage
        self.pending = None
        return True

    def _send(self, method, value, next_stage, offer, generation, sender):
        self.pending = (method, value, next_stage, offer.offer_id, offer.scope, generation)
        self.retry_pending(offer, generation, sender)
        return False

    def after_present(self, projection, offer, generation, sender, source_reader):
        if self.complete:
            return True
        if self.pending is not None:
            if self.retry_pending(offer, generation, sender) or self.pending is not None:
                return False
        if self.stage == 0:
            return self._send("send_key", "alt+6", 1, offer, generation, sender)
        if not _taskbar_has_focus(projection, SOUNDLAB_FOCUS_MARKER):
            return False
        fields = {claim.label: claim for claim in _field_claims_in_tile(projection, 5)}
        prompt = "Duration (100-2000 ms):" if self.stage < 7 else "Amplitude (0-100 percent):"
        if self.stage in (2, 7):
            if prompt not in projection.text:
                return False
            if fields:
                raise PhysicalDesktopAcceptanceError("Sound Lab modal prompt retained covered FIELD roots")
            _require_cell_fallback_evidence("series-prompt", offer, generation, (prompt,))
            return self._send("send_key", "ctrl+a", self.stage + 1, offer, generation, sender)
        if self.stage in (3, 8):
            if prompt not in projection.text:
                return False
            value = "2000" if self.stage == 3 else str(self.changed_amplitude)
            return self._send("send_text", value, self.stage + 1, offer, generation, sender)
        if self.stage in (4, 9):
            value = "2000" if self.stage == 4 else str(self.changed_amplitude)
            if f"{prompt} {value}" not in projection.text:
                return False
            return self._send("send_key", "enter", self.stage + 1, offer, generation, sender)
        if set(fields) != {"Waveform", "Frequency (Hz)", "Amplitude (%)", "Duration (ms)"}:
            return False
        if self.stage == 1:
            identity = fields["Duration (ms)"].identity
            value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id}"
            return self._send("field_activate", value, 2, offer, generation, sender)
        if self.stage in (5, 10):
            if fields["Duration (ms)"].content.value != 2000:
                return False
            if self.stage == 10 and fields["Amplitude (%)"].content.value != self.changed_amplitude:
                return False
            return self._send("send_key", "f5", self.stage + 1, offer, generation, sender)
        if self.stage in (6, 11):
            plane = offer.retained
            if plane is None or len(plane.series) != 1 or len(plane.series[0].samples) != 16000:
                return False
            source = source_reader()
            evidence = _require_soundlab_waveform_evidence(offer, generation, source)
            if (source.amplitude, source.frequency, source.shape) != tuple(
                    fields[label].content.value for label in ("Amplitude (%)", "Frequency (Hz)", "Waveform")):
                raise PhysicalDesktopAcceptanceError("Sound Lab acknowledged settings differ from ordinary source")
            if self.stage == 6:
                # Rebinding unaccepted input on a newer frame refreshes this
                # stage's evidence; it must not append another logical render.
                self.evidence["renders"][:] = [evidence]
                self.changed_amplitude = 40 if source.amplitude != 40 else 60
                identity = fields["Amplitude (%)"].identity
                value = f"{identity.owner_id},{identity.owner_generation},{identity.control_id}"
                return self._send("field_activate", value, 7, offer, generation, sender)
            first = self.evidence["renders"][0]
            if (evidence["samples_sha256"] == first["samples_sha256"]
                    or evidence["history_key"] == first["history_key"]
                    or evidence["bounds"] != first["bounds"]
                    or source.amplitude != self.changed_amplitude):
                raise PhysicalDesktopAcceptanceError("Sound Lab changed render did not replace its exact full history")
            self.evidence["renders"][1:] = [evidence]
            self.prior_selection = tuple(sorted(
                label for label, claim in fields.items() if claim.state & ControlState.SELECTED))
            return self._send("send_key", "down", 12, offer, generation, sender)
        assert self.stage == 12
        selected = tuple(sorted(label for label, claim in fields.items()
                                if claim.state & ControlState.SELECTED))
        second = self.evidence["renders"][1]
        if selected == self.prior_selection or offer.offer_id == second["offer_id"]:
            return False
        evidence = _require_soundlab_waveform_evidence(offer, generation, source_reader())
        self.evidence["reuse_candidate"] = evidence
        for name in ("bounds", "samples_sha256", "source_graph_sha256", "history_key", "waveform_id"):
            if evidence[name] != second[name]:
                raise PhysicalDesktopAcceptanceError(f"Sound Lab ordinary selection redraw did not reuse {name}")
        evidence["selection_before"] = list(self.prior_selection)
        evidence["selection_after"] = list(selected)
        self.evidence["stable_reuse"] = evidence
        self.stage = 13
        return True


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


def _owed_pointer_action(method: str, value: str, status: str) -> tuple[str, str]:
    """Name the rest of a gesture whose press the guest already saw."""

    if method == "pointer_click" and status == "release_owed":
        return "pointer_release", value
    if method == "pointer_drag" and status in ("release_owed", "drag_owed"):
        _start_column, _start_row, column, row = _canonical_integers(
            value, 4, method
        )
        end = f"{column},{row}"
        return (
            ("pointer_release", end)
            if status == "release_owed"
            else ("pointer_drag_rest", end)
        )
    raise PhysicalDesktopAcceptanceError(f"{method} cannot owe {status!r}")


class FrameBoundJourney:
    """Send app input only across newly acknowledged reference-sink frames.

    The physical runner shows the journey each presented frame through
    after_present.  The journey sends at most one input per frame, bound to
    that frame's exact offer, scope, and generation.  Input the terminal
    backpressures is retried against the same frame, and a pointer press the
    guest has seen owes the rest of its gesture before anything else.
    Subclasses give the stages, final_stage, and final_cell_markers.
    """

    def __init__(self, ready_markers: tuple[str, ...]):
        if not ready_markers or any(not marker for marker in ready_markers):
            raise ValueError("ready_markers must contain visible strings")
        self.ready_markers = tuple(ready_markers)
        self.stage = 0
        self.frame_barrier = 0
        self._pending: _PendingJourneyInput | None = None
        self._lineage: tuple[int, int, int, int, int, int, int] | None = None
        # A click or drag whose press reached the guest owes the rest of its
        # gesture, as (method, value), before any other input.
        self._owed_pointer: tuple[str, str] | None = None
        # What a journey that says so is waiting for, for timeout diagnostics.
        self.waiting: str | None = None

    # Whether every presented frame must show a semantic menu bar.
    requires_menu_bar = True
    # A journey that expects a draw shown as CELL, with an empty retained
    # scene, sets this; every other journey refuses such a frame.
    allows_empty_retained_frames = False

    @property
    def has_pending_input(self) -> bool:
        return self._pending is not None or self._owed_pointer is not None

    @property
    def final_stage(self) -> int:
        raise NotImplementedError

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        """The markers the final CELL fallback frame must show."""

        raise NotImplementedError

    def after_present(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
    ) -> JourneyProgress:
        """Observe one successfully presented frame and maybe send one action."""

        raise NotImplementedError

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
        if status in ("progress", "release_owed", "drag_owed"):
            self.stage = target_stage
            self._pending = None
            if status != "progress":
                self._owed_pointer = _owed_pointer_action(method, value, status)
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

        if self._owed_pointer is not None:
            self._deliver_owed_pointer(offer, generation, sender)
            return True
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

    def _deliver_owed_pointer(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        sender: InputSender,
    ) -> bool:
        """Finish a pressed gesture, bound to the current acknowledged frame."""

        owed = self._owed_pointer
        if owed is None:
            return True
        method, value = owed
        status = sender(method, value, offer, generation)
        if status == "progress":
            self._owed_pointer = None
            return True
        if status == "backpressured":
            return False
        if status == "release_owed" and method == "pointer_drag_rest":
            self._owed_pointer = ("pointer_release", value)
            return False
        raise PhysicalDesktopAcceptanceError(
            f"owed {method} was rejected as {status!r}"
        )

    @staticmethod
    def _taskbar_line(projection: RichScreenProjection) -> str:
        if len(projection.lines) < CANONICAL_DESKTOP_ROWS:
            return ""
        return projection.lines[CANONICAL_DESKTOP_ROWS - 1]

    @staticmethod
    def _text_value(claim: _SemanticCollectionClaim, *fields: int) -> str:
        identity = claim.identity
        return ",".join(
            str(value)
            for value in (
                identity.owner_id,
                identity.owner_generation,
                identity.control_id,
                *fields,
            )
        )


class DesktopAcceptanceJourney(FrameBoundJourney):
    """The canonical journey across Desk, Pad, File Explorer, Daybook, and
    Sound Lab."""

    def __init__(self, ready_markers: tuple[str, ...]):
        super().__init__(ready_markers)
        self._pad_area_before_edit: _CollectionStates | None = None
        self._pad_area_after_edit: _CollectionStates | None = None
        self._daybook_grid_before_navigation: _CollectionStates | None = None
        self._daybook_grid_after_navigation: _CollectionStates | None = None
        self._daybook_initial_date: str | None = None
        self._daybook_next_date: str | None = None
        self._pad_tabset_before_handoff: _TabSetState | None = None
        self._pad_tabset_before_activation: _TabSetState | None = None
        self._pad_tabset_after_activation: _TabSetState | None = None
        self._pad_tab_activation_target: _TabSignature | None = None
        self._pad_area_before_tab_activation: _CollectionStates | None = None
        self._pad_area_after_tab_activation: _CollectionStates | None = None
        self._pointer_list_first: int | None = None
        self._rename_prompt_cell: tuple[int, int] | None = None
        self._pad_tabset_before_pointer_open: _TabSetState | None = None
        self._pad_pointer_bounds: _SemanticBounds | None = None
        self._pad_pointer_viewport: int | None = None
        self._pointer_text_key: int | None = None
        self._daybook_wheel_date: str | None = None
        self._daybook_han_cell: tuple[int, int] = (0, 0)
        self._mixed_daybook_text: str | None = None
        self._followed_text: str | None = None

    @property
    def final_stage(self) -> int:
        return DESKTOP_ACCEPTANCE_FINAL_STAGE

    @property
    def final_cell_markers(self) -> tuple[str, ...]:
        """Return final CELL evidence bound to the observed Daybook date."""

        if self._daybook_wheel_date is None:
            raise PhysicalDesktopAcceptanceError(
                "final CELL evidence has no acknowledged Daybook wheel date"
            )
        if self._pointer_text_key is None:
            raise PhysicalDesktopAcceptanceError(
                "final CELL evidence has no acknowledged pointer selection"
            )
        if self._mixed_daybook_text is None:
            raise PhysicalDesktopAcceptanceError(
                "final CELL evidence has no acknowledged mixed Daybook task"
            )
        if self._followed_text is None:
            raise PhysicalDesktopAcceptanceError(
                "final CELL evidence has no acknowledged followed link"
            )
        return CELL_FINAL_STATIC_MARKERS + (
            self._daybook_wheel_date,
            # Daybook's task that mixes scripts, as its cells show it.
            mixed_text.visual(self._mixed_daybook_text),
            # The Forth file Pad's Markdown link opened.
            self._followed_text,
        )

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
            or self._daybook_next_date is None
            or not _daybook_date_is(projection, self._daybook_next_date)
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
        if not self._deliver_owed_pointer(offer, generation, sender):
            return JourneyProgress()

        if self.stage == 0 and _projection_marker_status(projection, self.ready_markers)[0]:
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
            if _taskbar_has_focus(projection, PAD_FOCUS_MARKER):
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
        if self.stage == 1 and _taskbar_has_focus(projection, PAD_FOCUS_MARKER):
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
            and _taskbar_has_focus(projection, PAD_FOCUS_MARKER)
            and _pad_file_menu_is_open(offer)
        ):
            milestone = self._milestone("pad-file-menu-open")
            self._send("send_key", "escape", 3, offer, generation, sender)
            return JourneyProgress(milestone)
        if (
            self.stage == 3
            and _taskbar_has_focus(projection, PAD_FOCUS_MARKER)
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
        if self.stage == 4 and _taskbar_has_focus(projection, PAD_FOCUS_MARKER):
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
        if self.stage == 5 and _taskbar_has_focus(projection, DAYBOOK_FOCUS_MARKER):
            self._send("send_key", "ctrl+n", 6, offer, generation, sender)
            return JourneyProgress()
        if (
            self.stage == 6
            and _taskbar_has_focus(projection, DAYBOOK_FOCUS_MARKER)
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
            and _taskbar_has_focus(projection, DAYBOOK_FOCUS_MARKER)
            and daybook_prompt_visible
            and DAYBOOK_ACCEPTANCE_TASK in text
        ):
            self._send("send_key", "enter", 8, offer, generation, sender)
            return JourneyProgress()
        if (
            self.stage == 8
            and _taskbar_has_focus(projection, DAYBOOK_FOCUS_MARKER)
            and _desktop_tile_contains(
                projection,
                DAYBOOK_ACCEPTANCE_TASK,
                DAYBOOK_DESKTOP_TILE,
            )
            and not daybook_prompt_visible
        ):
            self._daybook_initial_date = _require_daybook_date(projection)
            self._daybook_next_date = _next_iso_date(
                self._daybook_initial_date
            )
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
            and _taskbar_has_focus(projection, DAYBOOK_FOCUS_MARKER)
            and not _desktop_tile_contains(
                projection,
                DAYBOOK_ACCEPTANCE_TASK,
                DAYBOOK_DESKTOP_TILE,
            )
            and self._daybook_next_date is not None
            and _daybook_date_is(projection, self._daybook_next_date)
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
        if self.stage == 10 and _taskbar_has_focus(projection, PAD_FOCUS_MARKER):
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
                _taskbar_has_focus(projection, PAD_FOCUS_MARKER)
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
            launcher = _require_desk_launcher_selection(projection, "Streams")
            self._send(
                "item_select",
                launcher.value(launcher.named("Sound Lab").item_key),
                DESKTOP_ACCEPTANCE_SOUNDLAB_SELECTED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress()
        if self.stage == DESKTOP_ACCEPTANCE_SOUNDLAB_SELECTED_STAGE:
            if not _desk_launcher_selected(projection, "Sound Lab"):
                return JourneyProgress()
            launcher = _require_desk_launcher_selection(projection, "Sound Lab")
            milestone = self._milestone("soundlab-launch-source")
            self._send(
                "item_open",
                launcher.value(launcher.selected.item_key),
                DESKTOP_ACCEPTANCE_SOUNDLAB_LIVE_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_SOUNDLAB_LIVE_STAGE:
            if (
                not _taskbar_has_focus(projection, SOUNDLAB_FOCUS_MARKER, legacy_row=True)
                or not _desktop_tile_contains(
                    projection,
                    "SOUND LAB",
                    SOUNDLAB_DESKTOP_TILE,
                )
            ):
                return JourneyProgress()
            _require_soundlab_desktop_semantics(projection)
            self._require_exercised_state_survives(projection)
            milestone = self._milestone("soundlab-instruments-live")
            self._send(
                "send_key",
                "alt+2",
                DESKTOP_ACCEPTANCE_SOUNDLAB_LIVE_STAGE + 1,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if (
            DESKTOP_ACCEPTANCE_SOUNDLAB_LIVE_STAGE
            < self.stage
            < DESKTOP_ACCEPTANCE_POINTER_STAGE
        ):
            return self._ordinary_menu_stage(
                offer,
                generation,
                projection,
                sender,
            )
        if self.stage == DESKTOP_ACCEPTANCE_POINTER_STAGE:
            _require_soundlab_desktop_semantics(projection)
            if not _taskbar_has_focus(projection, SOUNDLAB_FOCUS_MARKER, legacy_row=True):
                return JourneyProgress()
            self._require_exercised_state_survives(projection)
            column, row = _taskbar_button_cell(
                projection,
                FEXPLORER_TASKBAR_BUTTON,
            )
            milestone = self._milestone("soundlab-restored-after-menus")
            method, value = "pointer_click", f"{column},{row}"
            if projection.semantic_taskbar_claims:
                matches = [task for bar in projection.semantic_taskbar_claims for task in bar.tasks
                           if task.kind is ControlKind.TASK and
                           task.bounds.left <= column < task.bounds.right and
                           task.bounds.top <= row < task.bounds.bottom]
                if len(matches) != 1:
                    raise PhysicalDesktopAcceptanceError("canonical taskbar click has ambiguous semantic authority")
                target = matches[0].identity
                method = "activate_shell_task"
                value = f"{target.owner_id},{target.owner_generation},{target.control_id}"
            self._send(
                method,
                value,
                DESKTOP_ACCEPTANCE_FEXPLORER_CLICKED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if (
            DESKTOP_ACCEPTANCE_POINTER_STAGE
            < self.stage
            <= DESKTOP_ACCEPTANCE_DAYBOOK_WHEEL_STAGE
        ):
            return self._pointer_stage(offer, generation, projection, sender)
        if (
            DESKTOP_ACCEPTANCE_DAYBOOK_WHEEL_STAGE
            < self.stage
            <= DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_ADDED_STAGE
        ):
            return self._mixed_text_stage(offer, generation, projection, sender)
        if (
            DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_ADDED_STAGE
            < self.stage
            <= DESKTOP_ACCEPTANCE_FINAL_STAGE
        ):
            return self._styled_text_stage(offer, generation, projection, sender)
        return JourneyProgress()

    def _ordinary_menu_stage(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
    ) -> JourneyProgress:
        """Open and close File Explorer View, then Daybook Go, while live.

        Each menu takes three acknowledged frames: focused with the menu
        closed, open with its authored popup, then closed again.  Instrument
        semantics must stay live throughout, and both popups must paint
        above their ordinary content.
        """

        _require_soundlab_desktop_semantics(projection)
        phase = self.stage - DESKTOP_ACCEPTANCE_SOUNDLAB_LIVE_STAGE
        capture = ORDINARY_MENU_CAPTURES[
            "fexplorer-view" if phase <= 3 else "daybook-go"
        ]
        if not _taskbar_has_focus(projection, capture.focus_marker, legacy_row=True):
            return JourneyProgress()
        _region, _bar, menu = _ordinary_menu_in_tile(offer, capture)
        local_phase = phase if phase <= 3 else phase - 3
        if bool(menu.state & ControlState.OPEN) != (local_phase == 2):
            return JourneyProgress()
        _require_ordinary_menu_state(offer, capture, local_phase == 2)
        if local_phase == 1:
            method, value, suffix = "activate_ordinary_menu", capture.key, "focused"
        elif local_phase == 2:
            method, value, suffix = "close_ordinary_menu", capture.key, "open"
        else:
            method, value, suffix = (
                "send_key",
                "alt+3" if phase == 3 else "alt+6",
                "closed",
            )
        self._send(method, value, self.stage + 1, offer, generation, sender)
        return JourneyProgress(self._milestone(f"{capture.key}-{suffix}"))

    def _pad_pointer_claim(
        self,
        projection: RichScreenProjection,
    ) -> _SemanticCollectionClaim | None:
        if not _taskbar_has_focus(projection, PAD_FOCUS_MARKER, legacy_row=True):
            raise PhysicalDesktopAcceptanceError(
                "Pad lost focus during pointer input"
            )
        return _pad_pointer_text_area(projection, self._pad_pointer_bounds)

    def _pointer_stage(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
    ) -> JourneyProgress:
        """Drive Desk, File Explorer, Pad, and Daybook with the mouse.

        A taskbar click focuses File Explorer, a SCROLL of one wheel detent
        moves its detail table three rows, and a SELECT on the fixture's row
        selects it, which shows its path and preview.  F2 opens the rename
        prompt; a drag across the name's stem selects it, typing replaces it,
        and Escape cancels.  An OPEN on the row opens the file in Pad, where
        one detent scrolls three
        lines, a press places the caret, a drag extends the selection, and a
        Right key moves the caret; Pad's Ln/Col readout follows in each frame
        that moves the caret.  Last, one wheel step over Daybook's calendar
        moves its date a week.  Residual cells take raw pointer input; text
        roots take STX1 positions and scrolls from the viewer's own layout,
        and item views take item events at the viewer's own item layout.
        Sound Lab stays live throughout.
        """

        if (
            DESKTOP_ACCEPTANCE_RENAME_PROMPT_STAGE
            <= self.stage
            <= DESKTOP_ACCEPTANCE_RENAME_CANCELLED_STAGE
            and _residual_tile_contains(
                projection,
                RENAME_PROMPT_LABEL,
                FEXPLORER_DESKTOP_TILE,
            )
        ):
            _require_fexplorer_prompt_fallback_semantics(projection)
        else:
            _require_soundlab_desktop_semantics(projection)
        taskbar = self._taskbar_line(projection)
        if self.stage == DESKTOP_ACCEPTANCE_FEXPLORER_CLICKED_STAGE:
            if not _taskbar_has_focus(projection, FEXPLORER_FOCUS_MARKER, legacy_row=True):
                return JourneyProgress()
            table = _fexplorer_table_claim(projection)
            if table is None:
                return JourneyProgress()
            content = table.content
            row = table.named(POINTER_LIST_FILE)
            if (
                row is None
                or not _item_shown(table, row)
                or row.ordinal - content.viewport_first < POINTER_WHEEL_ROWS
                or content.viewport_first + content.viewport_count
                + POINTER_WHEEL_ROWS > content.item_total
            ):
                raise PhysicalDesktopAcceptanceError(
                    "File Explorer's detail table does not show the pointer "
                    "fixture below its first scrollable rows"
                )
            self._pointer_list_first = content.viewport_first
            milestone = self._milestone("fexplorer-taskbar-clicked")
            self._send(
                "item_scroll",
                table.value(1),
                DESKTOP_ACCEPTANCE_LIST_WHEEL_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_LIST_WHEEL_STAGE:
            if not _taskbar_has_focus(projection, FEXPLORER_FOCUS_MARKER, legacy_row=True):
                raise PhysicalDesktopAcceptanceError(
                    "the table scroll moved focus away from File Explorer"
                )
            prior = self._pointer_list_first
            if prior is None:
                raise PhysicalDesktopAcceptanceError(
                    "the table scroll stage has no acknowledged first row"
                )
            table = _fexplorer_table_claim(projection)
            if table is None or table.content.viewport_first == prior:
                return JourneyProgress()
            row = table.named(POINTER_LIST_FILE)
            if (
                table.content.viewport_first != prior + POINTER_WHEEL_ROWS
                or row is None
                or not _item_shown(table, row)
            ):
                raise PhysicalDesktopAcceptanceError(
                    "one wheel detent did not scroll File Explorer's detail "
                    f"table exactly {POINTER_WHEEL_ROWS} rows"
                )
            milestone = self._milestone("fexplorer-list-wheel-scrolled")
            self._send(
                "item_select",
                table.value(row.item_key),
                DESKTOP_ACCEPTANCE_LIST_ROW_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_LIST_ROW_STAGE:
            # Selecting a file loads its preview but keeps the table in view,
            # so the row can be opened; the Preview tab stays hidden.
            table = _fexplorer_table_claim(projection)
            selected = None if table is None else table.selected
            if (
                not _taskbar_has_focus(projection, FEXPLORER_FOCUS_MARKER, legacy_row=True)
                or selected is None
                or selected.fields[0].text != POINTER_LIST_FILE
                or not _fexplorer_selected_path_is(projection, POINTER_LIST_PATH)
            ):
                return JourneyProgress()
            milestone = self._milestone("fexplorer-list-row-clicked")
            self._send(
                "send_key",
                "f2",
                DESKTOP_ACCEPTANCE_RENAME_PROMPT_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        prompt = f"{RENAME_PROMPT_LABEL} {POINTER_LIST_FILE}"
        renamed = f"{RENAME_PROMPT_LABEL} {RENAME_REPLACEMENT}.{RENAME_SUFFIX}"
        if self.stage == DESKTOP_ACCEPTANCE_RENAME_PROMPT_STAGE:
            if not _taskbar_has_focus(projection, FEXPLORER_FOCUS_MARKER, legacy_row=True):
                raise PhysicalDesktopAcceptanceError(
                    "File Explorer lost focus before its rename prompt"
                )
            cell = _tile_text_cell(projection, prompt, FEXPLORER_DESKTOP_TILE)
            if cell is None:
                return JourneyProgress()
            if _prompt_row_text(projection, cell, FEXPLORER_DESKTOP_TILE) != prompt:
                raise PhysicalDesktopAcceptanceError(
                    "File Explorer's rename prompt does not hold exactly the "
                    "selected file's name"
                )
            self._rename_prompt_cell = cell
            column, row = cell
            start = column + len(RENAME_PROMPT_LABEL) + 1
            milestone = self._milestone("fexplorer-rename-prompt-opened")
            self._send(
                "pointer_drag",
                f"{start},{row},{start + len(RENAME_STEM)},{row}",
                DESKTOP_ACCEPTANCE_RENAME_DRAGGED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage in (
            DESKTOP_ACCEPTANCE_RENAME_DRAGGED_STAGE,
            DESKTOP_ACCEPTANCE_RENAME_TYPED_STAGE,
        ):
            cell = self._rename_prompt_cell
            if cell is None:
                raise PhysicalDesktopAcceptanceError(
                    "rename stage has no acknowledged prompt"
                )
            if not _taskbar_has_focus(projection, FEXPLORER_FOCUS_MARKER, legacy_row=True):
                raise PhysicalDesktopAcceptanceError(
                    "the prompt drag moved focus away from File Explorer"
                )
            text = _prompt_row_text(projection, cell, FEXPLORER_DESKTOP_TILE)
            if self.stage == DESKTOP_ACCEPTANCE_RENAME_DRAGGED_STAGE:
                # A selection changes no text; the next frame authorizes the
                # typing that replaces it.
                if text != prompt:
                    raise PhysicalDesktopAcceptanceError(
                        f"the prompt drag changed its text to {text!r}"
                    )
                milestone = self._milestone("fexplorer-rename-stem-dragged")
                self._send(
                    "send_text",
                    RENAME_REPLACEMENT,
                    DESKTOP_ACCEPTANCE_RENAME_TYPED_STAGE,
                    offer,
                    generation,
                    sender,
                )
                return JourneyProgress(milestone)
            # The guest may paint after each typed scalar.  Anything but the
            # original text or the replacement typed over exactly the stem
            # means the drag selected the wrong span.
            partial = {
                f"{RENAME_PROMPT_LABEL} {RENAME_REPLACEMENT[:length]}.{RENAME_SUFFIX}"
                for length in range(1, len(RENAME_REPLACEMENT))
            }
            if text == prompt or text in partial:
                return JourneyProgress()
            if text != renamed:
                raise PhysicalDesktopAcceptanceError(
                    f"typing over the dragged stem produced {text!r}, not "
                    f"{renamed!r}"
                )
            milestone = self._milestone("fexplorer-rename-stem-replaced")
            self._send(
                "send_key",
                "escape",
                DESKTOP_ACCEPTANCE_RENAME_CANCELLED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_RENAME_CANCELLED_STAGE:
            if not _taskbar_has_focus(projection, FEXPLORER_FOCUS_MARKER, legacy_row=True):
                raise PhysicalDesktopAcceptanceError(
                    "cancelling the rename moved focus away from File Explorer"
                )
            if _residual_tile_contains(
                projection,
                RENAME_PROMPT_LABEL,
                FEXPLORER_DESKTOP_TILE,
            ) or not _fexplorer_selected_path_is(projection, POINTER_LIST_PATH):
                return JourneyProgress()
            if _residual_tile_contains(
                projection,
                f"{RENAME_REPLACEMENT}.{RENAME_SUFFIX}",
                FEXPLORER_DESKTOP_TILE,
            ):
                raise PhysicalDesktopAcceptanceError(
                    "cancelling the rename prompt renamed the file"
                )
            table = _fexplorer_table_claim(projection)
            row = None if table is None else table.named(POINTER_LIST_FILE)
            if row is None:
                return JourneyProgress()
            if not row.state & ItemState.SELECTED:
                raise PhysicalDesktopAcceptanceError(
                    "cancelling the rename moved the table's selection"
                )
            self._pad_tabset_before_pointer_open = _tabset_state(
                _canonical_pad_tabset_claim(projection)
            )
            milestone = self._milestone("fexplorer-rename-cancelled")
            self._send(
                "item_open",
                table.value(row.item_key),
                DESKTOP_ACCEPTANCE_PAD_OPENED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_PAD_OPENED_STAGE:
            if not _taskbar_has_focus(projection, PAD_FOCUS_MARKER, legacy_row=True):
                return JourneyProgress()
            claim = _pad_pointer_text_area(projection)
            if claim is None:
                return JourneyProgress()
            before = self._pad_tabset_before_pointer_open
            tabset = _tabset_state(_canonical_pad_tabset_claim(projection))
            if (
                before is None
                or tabset.bounds != before.bounds
                or tabset.tabs[:-1] != before.tabs
                or tabset.selected != tabset.tabs[-1]
                or POINTER_LIST_PATH not in tabset.selected[1]
            ):
                raise PhysicalDesktopAcceptanceError(
                    "opening the clicked file did not append and select one "
                    "Pad tab for it"
                )
            state = _text_area_pointer_state(claim)
            if (
                state.viewport_row < POINTER_WHEEL_ROWS
                or not _caret_in_view(state)
                or state.anchor != (0, 0)
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Pad did not open the pointer fixture scrolled to its "
                    "caret at the end, without a selection"
                )
            self._pad_pointer_bounds = (
                claim.left,
                claim.top,
                claim.right,
                claim.bottom,
            )
            self._pad_pointer_viewport = state.viewport_row
            milestone = self._milestone("pad-fixture-opened")
            # The view starts at the end, so one detent scrolls up.
            self._send(
                "text_scroll",
                self._text_value(claim, -1),
                DESKTOP_ACCEPTANCE_PAD_WHEEL_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        claim = self._pad_pointer_claim(projection)
        if claim is None:
            return JourneyProgress()
        state = _text_area_pointer_state(claim)
        if self.stage == DESKTOP_ACCEPTANCE_PAD_WHEEL_STAGE:
            opened = self._pad_pointer_viewport
            if opened is None:
                raise PhysicalDesktopAcceptanceError(
                    "Pad wheel stage has no acknowledged opened view"
                )
            if state.viewport_row == opened:
                return JourneyProgress()
            if (
                state.viewport_row != opened - POINTER_WHEEL_ROWS
                or not _caret_in_view(state)
                or state.anchor != (0, 0)
            ):
                raise PhysicalDesktopAcceptanceError(
                    "one wheel detent did not scroll Pad exactly "
                    f"{POINTER_WHEEL_ROWS} lines with its caret kept in view"
                )
            _require_pad_readout(projection, claim)
            # Keys are line numbers plus one.
            self._pointer_text_key = (
                state.viewport_row + POINTER_TARGET_VIEW_ROW + 1
            )
            milestone = self._milestone("pad-wheel-scrolled")
            self._send(
                "text_place",
                self._text_value(
                    claim,
                    self._pointer_text_key,
                    POINTER_PLACE_OFFSET,
                ),
                DESKTOP_ACCEPTANCE_PAD_PLACE_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        key = self._pointer_text_key
        if key is None:
            raise PhysicalDesktopAcceptanceError(
                "Pad pointer stage has no acknowledged target line"
            )
        placed = (key, POINTER_PLACE_OFFSET)
        scrolled = self._pad_pointer_viewport - POINTER_WHEEL_ROWS
        if self.stage == DESKTOP_ACCEPTANCE_PAD_PLACE_STAGE:
            if state.primary != placed:
                return JourneyProgress()
            if state.anchor != (0, 0) or state.viewport_row != scrolled:
                raise PhysicalDesktopAcceptanceError(
                    "placing Pad's caret moved its view or left a selection"
                )
            _require_pad_readout(projection, claim)
            milestone = self._milestone("pad-caret-placed")
            self._send(
                "text_extend",
                self._text_value(claim, key, POINTER_EXTEND_OFFSET),
                DESKTOP_ACCEPTANCE_PAD_EXTEND_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        extended = (key, POINTER_EXTEND_OFFSET)
        if self.stage == DESKTOP_ACCEPTANCE_PAD_EXTEND_STAGE:
            if state.primary != extended:
                return JourneyProgress()
            if state.anchor != placed or state.viewport_row != scrolled:
                raise PhysicalDesktopAcceptanceError(
                    "extending Pad's selection moved its view or lost its anchor"
                )
            _require_pad_readout(projection, claim)
            milestone = self._milestone("pad-text-selected")
            self._send(
                "send_key",
                "right",
                DESKTOP_ACCEPTANCE_PAD_KEY_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        moved = (key, POINTER_EXTEND_OFFSET + 1)
        if self.stage == DESKTOP_ACCEPTANCE_PAD_KEY_STAGE:
            if state.primary == extended:
                return JourneyProgress()
            if (
                state.primary != moved
                or state.anchor != (0, 0)
                or state.viewport_row != scrolled
            ):
                raise PhysicalDesktopAcceptanceError(
                    "Right did not move Pad's caret one scalar and drop the "
                    "selection in place"
                )
            _require_pad_readout(projection, claim)
            grids = _collection_claims_in_tile(
                projection,
                ControlKind.TEXT_GRID,
                DAYBOOK_DESKTOP_TILE,
            )
            if len(grids) != 1 or self._daybook_next_date is None:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook does not show exactly one calendar TEXT_GRID at "
                    "its acknowledged date"
                )
            if not _daybook_date_is(projection, self._daybook_next_date):
                raise PhysicalDesktopAcceptanceError(
                    "Daybook left its acknowledged date before the wheel"
                )
            milestone = self._milestone("pad-caret-moved-by-key")
            # A positive APT detent is one step down: a week later.
            self._send(
                "text_scroll",
                self._text_value(grids[0], 1),
                DESKTOP_ACCEPTANCE_DAYBOOK_WHEEL_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        # The wheel leaves Pad's focus, caret, and view untouched.
        if state.primary != moved or state.anchor != (0, 0):
            raise PhysicalDesktopAcceptanceError(
                "the Daybook wheel changed Pad's caret or selection"
            )
        expected = _iso_date_after(self._daybook_next_date, DAYBOOK_WHEEL_DAYS)
        if _daybook_date_is(projection, self._daybook_next_date):
            return JourneyProgress()
        if not _daybook_date_is(projection, expected):
            raise PhysicalDesktopAcceptanceError(
                "one wheel step over Daybook's calendar did not move its date "
                f"exactly {DAYBOOK_WHEEL_DAYS} days"
            )
        if (
            len(
                _collection_claims_in_tile(
                    projection,
                    ControlKind.TEXT_GRID,
                    DAYBOOK_DESKTOP_TILE,
                )
            )
            != 1
        ):
            raise PhysicalDesktopAcceptanceError(
                "Daybook's calendar TEXT_GRID did not survive its wheel step"
            )
        self._daybook_wheel_date = expected
        milestone = self._milestone("daybook-calendar-wheel-scrolled")
        # Pad keeps the keyboard; its caret goes to its line's end.
        self._send(
            "send_key",
            "end",
            DESKTOP_ACCEPTANCE_MIXED_LINE_END_STAGE,
            offer,
            generation,
            sender,
        )
        return JourneyProgress(milestone)

    def _mixed_text_stage(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
    ) -> JourneyProgress:
        """Type text that mixes scripts into Pad and into a Daybook task.

        Pad opens a line after the selected one and takes English, Chinese,
        an accent built from a combining mark, an emoji sequence, a flag,
        Hebrew, and Arabic.  Its TEXT_AREA carries the line logically and
        its CELL cells show the characters in visual order.  A click on the
        combined accent, found through the viewer's own layout, places the
        caret at its start; Right moves over both its scalars; and a click
        inside the Hebrew word lands on that letter.  Pad's Ln/Col readout
        counts characters in every frame that moves the caret.  Then Daybook
        takes a mixed task through its prompt, whose residual glyph runs and
        CELL cells show it in visual order; a click on a Han character's
        second cell puts the caret before that character, where one typed
        character lands, and Enter adds the task to the agenda.
        """

        daybook_prompt = _residual_tile_contains(
            projection,
            DAYBOOK_PROMPT_MARKER,
            DAYBOOK_DESKTOP_TILE,
        )
        if daybook_prompt:
            _require_soundlab_daybook_prompt_fallback_semantics(projection)
        else:
            _require_soundlab_desktop_semantics(projection)
        key = self._pointer_text_key
        if key is None:
            raise PhysicalDesktopAcceptanceError(
                "mixed text stages have no acknowledged Pad line"
            )
        if self.stage <= DESKTOP_ACCEPTANCE_MIXED_HEBREW_PLACED_STAGE:
            return self._mixed_pad_stage(offer, generation, projection, sender, key)
        return self._mixed_daybook_stage(
            offer, generation, projection, sender, daybook_prompt
        )

    def _pad_editor_claim(
        self,
        projection: RichScreenProjection,
    ) -> _SemanticCollectionClaim | None:
        """Pad's editor root at the bounds the pointer stages recorded.

        It is found by its bounds alone: End moves the caret past the view's
        right edge, and the view then scrolls the fixture's marker text out
        of sight.
        """

        if not _taskbar_has_focus(projection, PAD_FOCUS_MARKER, legacy_row=True):
            raise PhysicalDesktopAcceptanceError(
                "Pad lost focus during mixed text input"
            )
        bounds = self._pad_pointer_bounds
        claims = tuple(
            claim
            for claim in _collection_claims_in_tile(
                projection,
                ControlKind.TEXT_AREA,
                PAD_DESKTOP_TILE,
            )
            if bounds is None
            or (claim.left, claim.top, claim.right, claim.bottom) == bounds
        )
        if len(claims) > 1:
            raise PhysicalDesktopAcceptanceError(
                "Pad's editor is ambiguous across multiple TEXT_AREA roots"
            )
        return claims[0] if claims else None

    def _mixed_pad_stage(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
        key: int,
    ) -> JourneyProgress:
        claim = self._pad_editor_claim(projection)
        if claim is None:
            return JourneyProgress()
        state = _text_area_pointer_state(claim)
        line = key + 1
        typed_end = (line, len(mixed_text.PAD_TEXT))
        cluster = (line, mixed_text.PAD_TEXT.index(mixed_text.PAD_CLUSTER))
        past_cluster = (cluster[0], cluster[1] + len(mixed_text.PAD_CLUSTER))
        # The second letter of the Hebrew word, away from its edges.
        hebrew = (line, mixed_text.PAD_TEXT.index(mixed_text.PAD_HEBREW) + 1)
        if state.anchor != (0, 0):
            raise PhysicalDesktopAcceptanceError(
                "Pad gained a selection during mixed text input"
            )
        if self.stage == DESKTOP_ACCEPTANCE_MIXED_LINE_END_STAGE:
            text = _claim_item_text(claim, key)
            if text is None or state.primary != (key, len(text)):
                return JourneyProgress()
            _require_pad_readout(projection, claim)
            milestone = self._milestone("pad-caret-at-line-end")
            self._send(
                "send_key",
                "enter",
                DESKTOP_ACCEPTANCE_MIXED_LINE_OPENED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_MIXED_LINE_OPENED_STAGE:
            if state.primary != (line, 0):
                return JourneyProgress()
            if _claim_item_text(claim, line) != "":
                raise PhysicalDesktopAcceptanceError(
                    "Enter at a line's end did not open an empty line"
                )
            _require_pad_readout(projection, claim)
            milestone = self._milestone("pad-line-opened")
            self._send(
                "send_text",
                mixed_text.PAD_TEXT,
                DESKTOP_ACCEPTANCE_MIXED_TYPED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_MIXED_TYPED_STAGE:
            text = _claim_item_text(claim, line) or ""
            if text != mixed_text.PAD_TEXT:
                # The guest may paint between typed characters.
                if not mixed_text.PAD_TEXT.startswith(text):
                    raise PhysicalDesktopAcceptanceError(
                        f"Pad's typed line diverged from the text sent: {text!r}"
                    )
                return JourneyProgress()
            if state.primary != typed_end:
                return JourneyProgress()
            _require_pad_readout(projection, claim)
            self._require_cell_text(
                offer,
                projection,
                mixed_text.visual(mixed_text.PAD_TEXT),
                PAD_DESKTOP_TILE,
            )
            milestone = self._milestone("pad-mixed-text-typed")
            self._send(
                "text_place",
                self._text_value(claim, *cluster),
                DESKTOP_ACCEPTANCE_MIXED_CLUSTER_PLACED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_MIXED_CLUSTER_PLACED_STAGE:
            if state.primary == typed_end:
                return JourneyProgress()
            if state.primary != cluster:
                raise PhysicalDesktopAcceptanceError(
                    "a click on the combined accent did not place the caret "
                    f"at its start: {state.primary!r}"
                )
            _require_pad_readout(projection, claim)
            milestone = self._milestone("pad-caret-placed-on-cluster")
            self._send(
                "send_key",
                "right",
                DESKTOP_ACCEPTANCE_MIXED_CLUSTER_RIGHT_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_MIXED_CLUSTER_RIGHT_STAGE:
            if state.primary == cluster:
                return JourneyProgress()
            if state.primary != past_cluster:
                raise PhysicalDesktopAcceptanceError(
                    "Right did not move Pad's caret over both scalars of the "
                    f"combined accent: {state.primary!r}"
                )
            _require_pad_readout(projection, claim)
            milestone = self._milestone("pad-caret-moved-over-cluster")
            self._send(
                "text_place",
                self._text_value(claim, *hebrew),
                DESKTOP_ACCEPTANCE_MIXED_HEBREW_PLACED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if state.primary == past_cluster:
            return JourneyProgress()
        if state.primary != hebrew:
            raise PhysicalDesktopAcceptanceError(
                "a click inside the Hebrew word did not land on its letter: "
                f"{state.primary!r}"
            )
        _require_pad_readout(projection, claim)
        milestone = self._milestone("pad-caret-placed-in-hebrew")
        self._send(
            "send_key",
            "alt+3",
            DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_FOCUS_STAGE,
            offer,
            generation,
            sender,
        )
        return JourneyProgress(milestone)

    def _mixed_daybook_stage(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
        daybook_prompt: bool,
    ) -> JourneyProgress:
        if not _taskbar_has_focus(projection, DAYBOOK_FOCUS_MARKER, legacy_row=True):
            if self.stage == DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_FOCUS_STAGE:
                return JourneyProgress()
            raise PhysicalDesktopAcceptanceError(
                "Daybook lost focus during mixed task input"
            )
        inserted = mixed_text.DAYBOOK_ENTRY
        if self.stage == DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_FOCUS_STAGE:
            if daybook_prompt:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt was open before its task shortcut"
                )
            milestone = self._milestone("daybook-focused-for-mixed-task")
            self._send(
                "send_key",
                "ctrl+n",
                DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_PROMPT_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_PROMPT_STAGE:
            if not daybook_prompt:
                return JourneyProgress()
            milestone = self._milestone("daybook-mixed-prompt-opened")
            self._send(
                "send_text",
                mixed_text.DAYBOOK_TASK,
                DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_TYPED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage < DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_ADDED_STAGE:
            if not daybook_prompt:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt closed during mixed task input"
                )
            prompt = _tile_text_cell(
                projection, DAYBOOK_PROMPT_MARKER, DAYBOOK_DESKTOP_TILE
            )
            if prompt is None:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt label has no unique cell"
                )
            _column, row = prompt
            left, _top, right, _bottom = _desktop_tile_bounds(
                projection, DAYBOOK_DESKTOP_TILE
            )
        if self.stage == DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_TYPED_STAGE:
            if not projection.find_cells(
                mixed_text.visual(mixed_text.DAYBOOK_TASK), row, left, right
            ):
                return JourneyProgress()
            self._require_cell_text(
                offer,
                projection,
                mixed_text.visual(mixed_text.DAYBOOK_TASK),
                DAYBOOK_DESKTOP_TILE,
            )
            columns = projection.find_cells(mixed_text.DAYBOOK_HAN, row, left, right)
            if len(columns) != 1:
                raise PhysicalDesktopAcceptanceError(
                    "Daybook's prompt does not show its Han character once"
                )
            self._daybook_han_cell = (columns[0], row)
            milestone = self._milestone("daybook-mixed-task-typed")
            # The character's second cell names its start (APT-1-TEXT 9.1).
            self._send(
                "pointer_click",
                f"{columns[0] + 1},{row}",
                DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_CLICKED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_CLICKED_STAGE:
            column, han_row = self._daybook_han_cell
            cell = offer.cell.cells[han_row][column]
            # The focused caret now marks the Han character's cells.
            if not cell.attrs & ATTR_REVERSE:
                return JourneyProgress()
            milestone = self._milestone("daybook-prompt-caret-on-han")
            self._send(
                "send_text",
                mixed_text.DAYBOOK_INSERT,
                DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_INSERTED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_INSERTED_STAGE:
            if not projection.find_cells(mixed_text.visual(inserted), row, left, right):
                return JourneyProgress()
            milestone = self._milestone("daybook-prompt-text-inserted-at-click")
            self._send(
                "send_key",
                "enter",
                DESKTOP_ACCEPTANCE_DAYBOOK_MIXED_ADDED_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if daybook_prompt:
            return JourneyProgress()
        left, top, right, bottom = _desktop_tile_bounds(
            projection, DAYBOOK_DESKTOP_TILE
        )
        visual = mixed_text.visual(inserted)
        # The agenda is an item view in a rich frame and cells in CELL.
        if not any(
            projection.find_cells(visual, row, left, right)
            for row in range(top, bottom)
        ) and not _item_view_text_in_tile(
            projection, inserted, DAYBOOK_DESKTOP_TILE
        ):
            return JourneyProgress()
        self._require_cell_text(offer, projection, visual, DAYBOOK_DESKTOP_TILE)
        self._mixed_daybook_text = inserted
        milestone = self._milestone("daybook-mixed-task-added")
        self._send(
            "send_key",
            "alt+1",
            DESKTOP_ACCEPTANCE_STYLED_FOCUS_STAGE,
            offer,
            generation,
            sender,
        )
        return JourneyProgress(milestone)

    def _styled_text_stage(
        self,
        offer: TerminalDisplayOffer,
        generation: int,
        projection: RichScreenProjection,
        sender: InputSender,
    ) -> JourneyProgress:
        """Open notes.md in Pad and follow its Markdown link.

        Pad highlights by file name: notes.md's TEXT_AREA carries the style
        runs of its heading, its link, and its strong text.  A FOLLOW on the
        link, sent where the viewer's own hit map finds the link, as Ctrl and
        a click is, opens example.f, whose keywords its runs mark and whose
        cells show it.  While Pad's Open prompt is up, Pad's menu, tabs, and
        text areas are withheld, as for any modal prompt.
        """

        pad_prompt = _residual_tile_contains(
            projection, PAD_OPEN_PROMPT_MARKER, PAD_DESKTOP_TILE
        )
        if pad_prompt:
            _require_soundlab_pad_prompt_fallback_semantics(projection)
        else:
            _require_soundlab_desktop_semantics(projection)
        focused = _taskbar_has_focus(projection, PAD_FOCUS_MARKER, legacy_row=True)
        if self.stage == DESKTOP_ACCEPTANCE_STYLED_FOCUS_STAGE:
            if not focused:
                return JourneyProgress()
            if pad_prompt:
                raise PhysicalDesktopAcceptanceError(
                    "Pad's prompt was open before its Open shortcut"
                )
            milestone = self._milestone("pad-focused-for-link")
            self._send(
                "send_key",
                "ctrl+o",
                DESKTOP_ACCEPTANCE_STYLED_PROMPT_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if not focused:
            raise PhysicalDesktopAcceptanceError(
                "Pad lost focus while opening and following a link"
            )
        if self.stage == DESKTOP_ACCEPTANCE_STYLED_PROMPT_STAGE:
            if not pad_prompt:
                return JourneyProgress()
            milestone = self._milestone("pad-open-prompt-shown")
            self._send(
                "send_text",
                styled_text.NOTES_PATH,
                DESKTOP_ACCEPTANCE_STYLED_PATH_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if self.stage == DESKTOP_ACCEPTANCE_STYLED_PATH_STAGE:
            if not pad_prompt:
                raise PhysicalDesktopAcceptanceError(
                    "Pad's prompt closed before its path was entered"
                )
            if not _residual_tile_contains(
                projection, styled_text.NOTES_PATH, PAD_DESKTOP_TILE
            ):
                return JourneyProgress()
            milestone = self._milestone("pad-notes-path-typed")
            self._send(
                "send_key",
                "enter",
                DESKTOP_ACCEPTANCE_STYLED_NOTES_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if pad_prompt:
            return JourneyProgress()
        claim = self._pad_editor_claim(projection)
        if claim is None:
            return JourneyProgress()
        if self.stage == DESKTOP_ACCEPTANCE_STYLED_NOTES_STAGE:
            if _claim_item_text(claim, 2) != styled_text.NOTES_LINE:
                return JourneyProgress()
            heading = _claim_item_runs(claim, 1)
            line = _claim_item_runs(claim, 2)
            if (
                heading != styled_text.NOTES_HEADING_RUNS
                or line != styled_text.NOTES_LINE_RUNS
            ):
                raise PhysicalDesktopAcceptanceError(
                    f"notes.md's style runs are {heading!r} and {line!r}"
                )
            milestone = self._milestone("pad-markdown-styled")
            # Follow the link from inside its text.
            offset = styled_text.NOTES_LINE.index(styled_text.NOTES_LINK_WORD) + 2
            self._send(
                "text_follow",
                self._text_value(claim, 2, offset),
                DESKTOP_ACCEPTANCE_FINAL_STAGE,
                offer,
                generation,
                sender,
            )
            return JourneyProgress(milestone)
        if _claim_item_text(claim, 1) != styled_text.EXAMPLE_LINE:
            return JourneyProgress()
        runs = _claim_item_runs(claim, 1)
        if runs != styled_text.EXAMPLE_LINE_RUNS:
            raise PhysicalDesktopAcceptanceError(
                f"example.f's style runs are {runs!r}"
            )
        self._require_cell_text(
            offer, projection, styled_text.EXAMPLE_LINE, PAD_DESKTOP_TILE
        )
        self._followed_text = styled_text.EXAMPLE_LINE
        self.frame_barrier = offer.offer_id
        return JourneyProgress(self._milestone("pad-link-followed-to-forth"), True)

    @staticmethod
    def _require_cell_text(
        offer: TerminalDisplayOffer,
        projection: RichScreenProjection,
        visual: str,
        tile: int,
    ) -> None:
        """Require CELL to show VISUAL's cells inside one Desk tile."""

        _require_cell_text_in(
            offer,
            visual,
            _desktop_tile_bounds(projection, tile),
            f"Desk tile {tile}",
        )


def _require_cell_text_in(
    offer: TerminalDisplayOffer,
    visual: str,
    bounds: tuple[int, int, int, int],
    where: str,
) -> None:
    """Require CELL to show VISUAL's cells inside BOUNDS, which WHERE names."""

    left, top, right, bottom = bounds
    if not any(
        top <= row < bottom and left <= column < right
        for row, column in offer.cell.find(visual)
    ):
        raise PhysicalDesktopAcceptanceError(f"CELL does not show {visual!r} in {where}")


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
    fallbacks: tuple[Path, ...] = (),
):
    """Choose the largest requested font that fits the physical display.

    The font is a set: the requested face, then FALLBACKS for characters it
    lacks, each fitted to its cells.
    """

    display = pygame_module.display.Info()
    max_width = max(1, int(display.current_w * 0.92))
    max_height = max(1, int(display.current_h * 0.86))
    smallest = min(MIN_READABLE_FONT_SIZE, requested_size)
    for size in range(requested_size, smallest - 1, -1):
        font = FontSet(pygame_module, font_path, size, fallbacks)
        cell_width = font.cell_width
        cell_height = font.cell_height
        if cols * cell_width <= max_width and rows * cell_height <= max_height:
            return font, cell_width, cell_height, size
    raise PhysicalDesktopAcceptanceError(
        f"{cols}x{rows} terminal does not fit the {display.current_w}x"
        f"{display.current_h} physical display at readable font size "
        f"{smallest}"
    )


def _dispatch_physical_pointer_event(
    pygame_module,
    pointer: _PointerRouter,
    keyboard: _GuestKeyboardForwarder,
    event,
    terminal_size: tuple[int, int],
    *,
    trace: _PerformanceTrace | None = None,
) -> bool:
    """Route one physical event through the viewer's own pointer router."""

    if event.type == getattr(pygame_module, "MOUSEMOTION", -1):
        pointer.move(
            event.pos,
            terminal_size,
            modifiers=_pygame_apt_modifiers(pygame_module, event),
        )
        return True
    if event.type == getattr(pygame_module, "MOUSEBUTTONDOWN", -1):
        sent = pointer.button_down(
            event.button,
            event.pos,
            terminal_size,
            modifiers=_pygame_apt_modifiers(pygame_module, event),
        )
        if trace is not None:
            pressed = pointer.pressed
            trace.mark(
                "manual_pointer_down",
                position=tuple(event.pos),
                button=event.button,
                semantic_target=_trace_control_identity(pressed),
                result=(
                    "targeted"
                    if pressed is not None
                    else "sent"
                    if sent
                    else "miss"
                ),
            )
        return True
    if event.type == getattr(pygame_module, "MOUSEBUTTONUP", -1):
        modifiers = _pygame_apt_modifiers(pygame_module, event)
        if trace is None:
            pointer.button_up(
                event.button,
                event.pos,
                terminal_size,
                modifiers=modifiers,
            )
            return True
        pressed = pointer.pressed
        pending_before = keyboard.pending_events
        error_before = keyboard.last_error
        request_count_before = getattr(
            keyboard.client,
            "request_count",
            None,
        )
        delivered = pointer.button_up(
            event.button,
            event.pos,
            terminal_size,
            modifiers=modifiers,
        )
        released = pointer.hovered
        reason = None
        if not delivered:
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
            button=event.button,
            pressed_target=_trace_control_identity(pressed),
            semantic_target=_trace_control_identity(released),
            result=result,
            reason=reason,
            pending_events=keyboard.pending_events,
        )
        return True
    if event.type == getattr(pygame_module, "MOUSEWHEEL", -1):
        flip = -1 if getattr(event, "flipped", False) else 1
        position = pygame_module.mouse.get_pos()
        sent = pointer.wheel(
            flip * event.x,
            flip * event.y,
            position,
            terminal_size,
            modifiers=_pygame_apt_modifiers(pygame_module, event),
        )
        if trace is not None:
            trace.mark(
                "manual_pointer_wheel",
                position=tuple(position),
                steps=[flip * event.x, flip * event.y],
                result="sent" if sent else "miss",
            )
        return True
    if event.type in {
        getattr(pygame_module, "WINDOWFOCUSLOST", -1),
        getattr(pygame_module, "WINDOWFOCUSGAINED", -2),
    }:
        pointer.cancel()
        if event.type == getattr(pygame_module, "WINDOWFOCUSLOST", -1):
            keyboard.reset()
        return True
    return False


def _pointer_event_types(pygame_module) -> tuple[int, ...]:
    """Return the complete physical-pointer event family used by the viewer."""

    return tuple(
        getattr(pygame_module, name)
        for name in (
            "MOUSEMOTION",
            "MOUSEBUTTONDOWN",
            "MOUSEBUTTONUP",
            "MOUSEWHEEL",
        )
        if hasattr(pygame_module, name)
    )


def _isolate_scripted_pointer_input(pygame_module) -> None:
    """Keep host pointer traffic outside the scripted evidence journey."""

    event_types = _pointer_event_types(pygame_module)
    pygame_module.event.set_blocked(event_types)
    # set_mode may already have queued a synthetic initial motion event.
    pygame_module.event.clear(event_types)


def _pump_physical_viewer_events(
    pygame_module,
    pointer: _PointerRouter,
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
        _dispatch_physical_pointer_event(
            pygame_module,
            pointer,
            keyboard,
            event,
            terminal_size,
            trace=trace,
        )
    keyboard.flush_pending()
    pointer.flush()
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
    # An empty retained scene, which only a journey that expects one gets
    # past reconstruction, leaves the CELL plane on screen by design.
    if nonblack == 0 and offer.retained.regions:
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


def _write_final_guest_diagnostics(artifact_root: Path, client) -> None:
    """After a passing journey, keep how the guest published its frames.

    The guest's DELTA counters and the terminal's committed PRESENT modes say
    whether changed draws went out as DELTAs or as complete replacements.
    These are diagnostics only; failing to read them never changes the verdict.
    """

    try:
        forth = client.request("forth", names=list(_GUEST_DIAGNOSTIC_WORDS))
        status = client.request("status", detailed=True)
    except Exception as exc:  # noqa: BLE001 - diagnostics must not fail a pass
        payload = {"error": str(exc)}
    else:
        words = forth.get("words", {})
        payload = {
            "variables": {
                name: int(word["value"])
                for name, word in words.items()
                if isinstance(word, dict) and "value" in word
            },
            "presents_committed": (status.get("rich_terminal") or {}).get(
                "presents_committed"
            ),
        }
    path = Path(artifact_root) / "final-guest-diagnostics.json"
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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
    journey: FrameBoundJourney | None = None,
) -> PhysicalDesktopAcceptanceEvidence:
    """Run and record a reference-sink journey: the canonical one across Desk,
    Pad, and Daybook, or JOURNEY, such as one for Desk with a single applet."""

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

        os.environ.setdefault("SDL_VIDEO_CENTERED", "1")
        pygame.display.init()
        pygame_initialized = True
        pygame.font.init()
        driver = pygame.display.get_driver()
        if driver.lower() in {"dummy", "offscreen"}:
            raise PhysicalDesktopAcceptanceError(
                f"SDL video driver {driver!r} is not a physical display sink"
            )
        fallback_fonts = discover_fallback_fonts()
        font, cell_width, cell_height, fitted_font_size = _fit_viewer_font(
            pygame,
            font_path,
            font_size,
            terminal.cols,
            terminal.rows,
            fallback_fonts,
        )
        pointer = _PointerRouter(
            display_state,
            keyboard,
            cell_width=cell_width,
            cell_height=cell_height,
        )
        chrome_font = FontSet(
            pygame,
            pygame.font.match_font("monospace", bold=True),
            16,
            fallback_fonts,
            cells=False,
        )
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
        # The frame the viewer last composed: the next one repaints only what
        # changes from it.
        composed_frame = None
        if journey is None:
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
                pointer,
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
                cell_width=cell_width,
                cell_height=cell_height,
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
            _require_healthy_backend(status, artifact_root)
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
                base_offer=display_state.base_offer_id,
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
                        fallback_fonts,
                    )
                )
                glyph_cache.clear()
                composed_frame = None
                pointer.cancel()
                pointer = _PointerRouter(
                    display_state,
                    keyboard,
                    cell_width=cell_width,
                    cell_height=cell_height,
                )
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
                else reconstruct_retained_screen(
                    frame_offer,
                    require_menu_bar=journey.requires_menu_bar,
                    allow_empty=journey.allows_empty_retained_frames,
                )
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
                _retained_ready, retained_missing_markers = _projection_marker_status(
                    frame_projection,
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
                nonlocal composed_surface, compose_duration_ns, composed_frame
                window.fill((0, 0, 0))
                compose_started_ns = trace.now()
                frame_result = compose_terminal_frame_changes(
                    pygame,
                    terminal,
                    font,
                    cell_width,
                    cell_height,
                    retained_plane=display_state.frame_plane,
                    show_cursor=True,
                    glyph_cache=glyph_cache,
                    control_font=chrome_font,
                    hovered=pointer.hovered,
                    pressed=pointer.pressed,
                    previous=composed_frame,
                )
                compose_duration_ns = max(trace.now() - compose_started_ns, 0)
                composed_frame = frame_result
                composed_surface = frame_result.surface
                window.blit(composed_surface, (0, 0))
                # Host diagnostics occupy separate window rows.  The composed
                # terminal surface recorded as acceptance evidence stays exact.
                draw_host_chrome()
                if frame_offer is not None:
                    display_state.stage_frame_hit_map(
                        frame_offer,
                        frame_result.hit_entries,
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
                retained_ready, _ = _projection_marker_status(
                    frame_projection,
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
            waited = journey.waiting
            progress = journey.after_present(
                frame_offer,
                frame_generation,
                frame_projection,
                send_input,
            )
            if journey.waiting is not None and journey.waiting != waited:
                print(
                    f"Journey stage {journey.stage} waits for: {journey.waiting}",
                    flush=True,
                )
            if progress.complete:
                final_cell = _require_cell_fallback_evidence(
                    "final",
                    frame_offer,
                    frame_generation,
                    tuple(ready_markers) + journey.final_cell_markers,
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
                _write_final_guest_diagnostics(artifact_root, client)
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
            waiting=journey.waiting,
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
