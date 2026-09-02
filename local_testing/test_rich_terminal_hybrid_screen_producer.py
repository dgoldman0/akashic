"""Seconds-only locks and model oracles for the hybrid screen producer."""

from dataclasses import dataclass, replace
from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
PRODUCER = ROOT / "akashic/tui/rich-terminal/hybrid-screen-producer.f"


def _source() -> str:
    return PRODUCER.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _constant(source: str, name: str) -> int:
    match = re.search(
        rf"(?m)^\s*(0x[0-9A-Fa-f]+|[0-9]+)\s+CONSTANT\s+"
        rf"{re.escape(name)}\s*$",
        source,
    )
    assert match is not None, name
    return int(match.group(1), 0)


def _offset(source: str, name: str) -> int:
    definition = _word(source, name)
    match = re.search(r"\([^)]*--[^)]*\)\s*(?:(\d+)\s+\+)?\s*;", definition)
    assert match is not None, name
    return int(match.group(1) or 0)


@dataclass(frozen=True)
class _ExactReuseFacts:
    """Independent fail-closed model of the unchanged-target certificate."""

    live_phase: bool = True
    no_pending_target: bool = True
    acknowledged_active_target: bool = True
    valid_packed_header: bool = True
    valid_target_entries: bool = True
    no_instruments: bool = True
    owner: bool = True
    owner_generation: bool = True
    dimensions: bool = True
    physical_generation: bool = True
    region: bool = True
    first_object: bool = True
    object_counts: bool = True
    text_usage: bool = True
    active_draw_binding: bool = True
    source_generation_binding: bool = True
    content_epoch_binding: bool = True
    negotiated_limits: bool = True
    new_draw_snapshot: bool = True
    new_source_generation: bool = True
    exact_content_epoch: bool = True
    document_count: bool = True
    next_attempt: bool = True
    clone_bounds: bool = True
    clone_disjoint: bool = True
    pointer_rebase: bool = True
    revision_fence: bool = True
    non_forced_cell_plan: bool = True
    plane_dimensions: bool = True
    acknowledged_front_draw: bool = True
    current_plane_draw: bool = True
    exact_damage_span: bool = True
    zero_cell_damage: bool = True
    snapshot_still_current: bool = True


def _exact_reuse_oracle(facts: _ExactReuseFacts) -> bool:
    return all(vars(facts).values())


def _max_collection_controls_oracle(native_bytes: int) -> int:
    """Worst-case TABSET/TAB density in a caller-bounded native bank."""

    if native_bytes <= 0 or native_bytes > 0xFFFFFFFF or native_bytes < 80:
        return 0
    return 1 + (native_bytes - 80) // 48


def _tab_point_oracle(
    *,
    root_row: int,
    root_col: int,
    root_width: int,
    root_actionable: bool,
    tabs: tuple[tuple[int, int, bool, bool], ...],
) -> tuple[tuple[int, int, int], ...]:
    """Ordinary visible-tab compaction and label-start target projection."""

    position = root_col + 1
    end = root_col + root_width
    targets: list[tuple[int, int, int]] = []
    for control_id, label_bytes, visible, enabled in tabs:
        if not visible:
            continue
        label_start = position
        position += label_bytes + 2
        if root_actionable and enabled and label_start < end:
            targets.append((control_id, root_row, label_start))
    return tuple(targets)


def _clone_bank_oracle(
    active: bytes,
    *,
    draw: int,
    source_generation: int,
    content_epoch: int,
    active_source_base: int,
    pending_source_base: int,
    source_bytes: int,
    text_fields: tuple[tuple[int, int], ...],
) -> bytes:
    """Byte oracle for clone header patching and packed pointer rebasing."""

    pending = bytearray(active)
    struct.pack_into("<Q", pending, 40, draw)
    struct.pack_into("<Q", pending, 48, source_generation)
    struct.pack_into("<Q", pending, 128, content_epoch)
    for address_offset, length_offset in text_fields:
        address = struct.unpack_from("<Q", active, address_offset)[0]
        length = struct.unpack_from("<Q", active, length_offset)[0]
        if length == 0:
            assert address == 0
            rebased = 0
        else:
            assert active_source_base <= address
            relative = address - active_source_base
            assert relative + length <= source_bytes
            rebased = pending_source_base + relative
        struct.pack_into("<Q", pending, address_offset, rebased)
    return bytes(pending)


@dataclass(frozen=True)
class _Control:
    """Renderer-neutral control state used by the independent delta oracle."""

    semantic_key: tuple[int, int, int, int]
    object_id: int
    region_id: int
    kind: int
    state: int
    z: int
    parent_key: tuple[int, int, int, int] | None
    parent_id: int
    order: int
    geometry: tuple[int, int, int, int, int, int]
    label: bytes
    shortcut: bytes
    content: bytes = b""
    content_items: int = 0
    content_utf8: int = 0
    content_epoch: int = 0
    lifecycle_generation: int = 0

    def with_identity(
        self, *, object_id: int, region_id: int, parent_id: int
    ) -> "_Control":
        return replace(
            self,
            object_id=object_id,
            region_id=region_id,
            parent_id=parent_id,
        )

    def retained_shape_tuple(self) -> tuple[object, ...]:
        return (
            self.semantic_key,
            self.kind,
            self.z,
            self.parent_key,
            self.order,
            self.geometry,
            self.lifecycle_generation,
        )


@dataclass(frozen=True)
class _Glyph:
    """One acknowledged glyph slot or one newly projected candidate run."""

    object_id: int
    region_id: int
    parent_id: int
    row: int
    col: int
    height: int
    width: int
    root_height: int
    root_width: int
    z: int
    visible: bool
    foreground: int
    background: int
    attrs: int
    text: bytes

    def with_identity(self, active: "_Glyph") -> "_Glyph":
        return replace(
            self,
            object_id=active.object_id,
            region_id=active.region_id,
            parent_id=active.parent_id,
        )


@dataclass(frozen=True)
class _Replacement:
    family: str
    object_id: int
    value: _Control | _Glyph


_U64_MAX = (1 << 64) - 1
_CONTROL_TEXT_AREA = 5
_CONTROL_TEXT_GRID = 6
_CONTROL_TABSET = 7
_CONTROL_TAB = 8
_STX1_TAG = 0x31585453
_STX1_VERSION = 1
_STX1_HEADER_BYTES = 72


def _stx1_content(revision: int, payload: bytes = b"") -> bytes:
    """Small canonical STX1 value sufficient for the delta revision oracle."""

    assert 0 < revision <= _U64_MAX
    return (
        struct.pack("<IHHQ", _STX1_TAG, _STX1_VERSION, 0, revision)
        + bytes(_STX1_HEADER_BYTES - 16)
        + payload
    )


def _stx1_revision(control: _Control) -> int | None:
    if len(control.content) < _STX1_HEADER_BYTES:
        return None
    tag, version, reserved, revision = struct.unpack_from(
        "<IHHQ", control.content
    )
    if (
        tag != _STX1_TAG
        or version != _STX1_VERSION
        or reserved != 0
        or revision == 0
        or revision != control.content_epoch
    ):
        return None
    return revision


def _control_delta_compatible(
    active: _Control, candidate: _Control
) -> tuple[bool, bool]:
    """Return exact producer compatibility and whether REPLACE is required."""

    if active.retained_shape_tuple() != candidate.retained_shape_tuple():
        return False, False
    changed = active.state != candidate.state
    if active.kind in (_CONTROL_TEXT_AREA, _CONTROL_TEXT_GRID):
        if active.label != candidate.label or active.shortcut != candidate.shortcut:
            return False, False
        if active.content == candidate.content:
            if (
                active.content_items != candidate.content_items
                or active.content_utf8 != candidate.content_utf8
            ):
                return False, False
        else:
            active_revision = _stx1_revision(active)
            candidate_revision = _stx1_revision(candidate)
            if (
                active_revision is None
                or candidate_revision is None
                or candidate_revision <= active_revision
            ):
                return False, False
            changed = True
    elif active.kind == _CONTROL_TAB:
        if (
            active.content != candidate.content
            or active.content_items != candidate.content_items
            or active.content_utf8 != candidate.content_utf8
        ):
            return False, False
        changed = changed or active.label != candidate.label
        changed = changed or active.shortcut != candidate.shortcut
    elif (
        active.label != candidate.label
        or active.shortcut != candidate.shortcut
        or active.content != candidate.content
        or active.content_items != candidate.content_items
        or active.content_utf8 != candidate.content_utf8
    ):
        return False, False
    return True, changed


def _glyph_bank_shape(
    glyphs: tuple[_Glyph, ...], *, fresh_ids: bool
) -> tuple[int, tuple[int, int] | None] | None:
    """Validate the compact bank ordering assumed by the stable-ID oracle."""

    ids = tuple(glyph.object_id for glyph in glyphs)
    if any(object_id <= 0 or object_id > _U64_MAX for object_id in ids):
        return None
    if len(set(ids)) != len(ids):
        return None
    ordered_ids = tuple(sorted(ids))
    if any(right != left + 1 for left, right in zip(ordered_ids, ordered_ids[1:])):
        return None
    if fresh_ids and ids != ordered_ids:
        return None

    roots = {
        (glyph.root_height, glyph.root_width)
        for glyph in glyphs
    }
    if len(roots) > 1:
        return None
    root = next(iter(roots), None)
    if root is not None and (root[0] <= 0 or root[1] <= 0):
        return None
    if len({glyph.region_id for glyph in glyphs}) > 1:
        return None

    visible_count = 0
    prior_row = -1
    prior_col = -1
    prior_end = -1
    in_tombstones = False
    for glyph in glyphs:
        if glyph.parent_id != 0:
            return None
        if not glyph.visible:
            in_tombstones = True
            if (
                glyph.text
                or glyph.row != 0
                or glyph.col != 0
                or glyph.height != 1
                or glyph.width != 1
            ):
                return None
            continue
        if in_tombstones or root is None:
            return None
        if glyph.height != 1 or glyph.width <= 0 or not glyph.text:
            return None
        if glyph.row < 0 or glyph.row >= root[0] or glyph.col < 0:
            return None
        if glyph.col + glyph.width > root[1]:
            return None
        if (glyph.row, glyph.col) <= (prior_row, prior_col):
            return None
        if glyph.row == prior_row and glyph.col < prior_end:
            return None
        visible_count += 1
        prior_row = glyph.row
        prior_col = glyph.col
        prior_end = glyph.col + glyph.width
    return visible_count, root


def _stable_glyph_delta(
    active_glyphs: tuple[_Glyph, ...],
    candidate_glyphs: tuple[_Glyph, ...],
) -> tuple[str, tuple[_Glyph, ...], tuple[_Replacement, ...]]:
    """Independently assign candidate runs to acknowledged spatial slots.

    The active bank is allowed to carry a non-monotone permutation of its
    contiguous ID set because its records remain in canonical spatial order.
    The candidate entering normalization is still the freshly preflighted
    complete plan, so its IDs must be monotone.  Any failed proof returns that
    fresh candidate byte-for-byte rather than a partially normalized bank.
    """

    active_shape = _glyph_bank_shape(active_glyphs, fresh_ids=False)
    candidate_shape = _glyph_bank_shape(candidate_glyphs, fresh_ids=True)
    if active_shape is None or candidate_shape is None:
        return "full", candidate_glyphs, ()
    active_visible, active_root = active_shape
    candidate_visible, candidate_root = candidate_shape
    if candidate_root is not None and active_root != candidate_root:
        return "full", candidate_glyphs, ()
    if len(candidate_glyphs) > len(active_glyphs):
        return "full", candidate_glyphs, ()
    if candidate_visible > len(active_glyphs):
        return "full", candidate_glyphs, ()

    # First retain every exact spatial anchor using one linear row-major merge.
    assignments: dict[int, int] = {}
    active_index = 0
    candidate_index = 0
    while active_index < active_visible and candidate_index < candidate_visible:
        active_anchor = (
            active_glyphs[active_index].row,
            active_glyphs[active_index].col,
        )
        candidate_anchor = (
            candidate_glyphs[candidate_index].row,
            candidate_glyphs[candidate_index].col,
        )
        if active_anchor == candidate_anchor:
            assignments[candidate_index] = active_index
            active_index += 1
            candidate_index += 1
        elif active_anchor < candidate_anchor:
            active_index += 1
        else:
            candidate_index += 1

    matched_active = set(assignments.values())
    unmatched_candidates = [
        index for index in range(candidate_visible) if index not in assignments
    ]
    # A genuinely new spatial run consumes an already invisible slot before a
    # visible identity retired by this same draw.  This makes moves explicit
    # delete+insert operations while acknowledged reserve remains available.
    free_active = list(range(active_visible, len(active_glyphs)))
    free_active.extend(
        index for index in range(active_visible) if index not in matched_active
    )
    if len(unmatched_candidates) > len(free_active):
        return "full", candidate_glyphs, ()
    for candidate_index, active_index in zip(unmatched_candidates, free_active):
        assignments[candidate_index] = active_index

    used_active = set(assignments.values())
    normalized_visible = tuple(
        candidate_glyphs[index].with_identity(active_glyphs[assignments[index]])
        for index in range(candidate_visible)
    )
    normalized_tombstones = tuple(
        _canonical_glyph_tomb(active)
        for index, active in enumerate(active_glyphs)
        if index not in used_active
    )
    normalized = normalized_visible + normalized_tombstones
    if len(normalized) != len(active_glyphs):
        return "full", candidate_glyphs, ()
    if {glyph.object_id for glyph in normalized} != {
        glyph.object_id for glyph in active_glyphs
    }:
        return "full", candidate_glyphs, ()

    active_by_id = {glyph.object_id: glyph for glyph in active_glyphs}
    replacements = tuple(
        _Replacement("glyph", glyph.object_id, glyph)
        for glyph in normalized
        if glyph != active_by_id[glyph.object_id]
    )
    return "delta", normalized, replacements


def _delta_or_full(
    active_controls: tuple[_Control, ...],
    candidate_controls: tuple[_Control, ...],
    active_glyphs: tuple[_Glyph, ...],
    candidate_glyphs: tuple[_Glyph, ...],
) -> tuple[str, tuple[_Replacement, ...]]:
    """Independent model of the producer's legal retained-delta subset."""

    if len(active_controls) > len(candidate_controls):
        return "full", ()
    active_by_key = {control.semantic_key: control for control in active_controls}
    candidate_by_key = {
        control.semantic_key: control for control in candidate_controls
    }
    if (
        len(active_by_key) != len(active_controls)
        or len(candidate_by_key) != len(candidate_controls)
        or not active_by_key.keys() <= candidate_by_key.keys()
    ):
        return "full", ()
    if candidate_controls:
        fresh_first = candidate_controls[0].object_id
        if (
            fresh_first <= 0
            or fresh_first > _U64_MAX
            or any(
                control.object_id != fresh_first + index
                or control.object_id > _U64_MAX
                for index, control in enumerate(candidate_controls)
            )
            or any(
                control.object_id <= 0
                or control.object_id >= fresh_first
                for control in active_controls
            )
            or len({control.object_id for control in active_controls})
            != len(active_controls)
        ):
            return "full", ()

    final_ids = {
        key: (
            active_by_key[key].object_id
            if key in active_by_key
            else candidate.object_id
        )
        for key, candidate in candidate_by_key.items()
    }
    candidate_ordinals = {
        control.semantic_key: index
        for index, control in enumerate(candidate_controls)
    }
    active_region = (
        active_controls[0].region_id
        if active_controls
        else candidate_controls[0].region_id if candidate_controls else 0
    )
    replacements: list[_Replacement] = []
    normalized_controls: list[_Control] = []
    for ordinal, candidate in enumerate(candidate_controls):
        key = candidate.semantic_key
        active = active_by_key.get(key)
        if active is not None:
            compatible, changed = _control_delta_compatible(active, candidate)
            if not compatible:
                return "full", ()
            object_id = active.object_id
            parent_id = active.parent_id
        else:
            changed = True
            object_id = candidate.object_id
            if candidate.parent_key is None:
                parent_id = 0
            else:
                parent_id = final_ids.get(candidate.parent_key, 0)
                if parent_id == 0:
                    return "full", ()
                parent_ordinal = candidate_ordinals[candidate.parent_key]
                if (
                    candidate.parent_key not in active_by_key
                    and parent_ordinal >= ordinal
                ):
                    return "full", ()
        normalized = candidate.with_identity(
            object_id=object_id,
            region_id=active_region,
            parent_id=parent_id,
        )
        normalized_controls.append(normalized)
        if changed:
            replacements.append(
                _Replacement(
                    "control" if active is not None else "control-define",
                    object_id,
                    normalized,
                )
            )

    glyph_mode, normalized_glyphs, glyph_replacements = _stable_glyph_delta(
        active_glyphs, candidate_glyphs
    )
    if glyph_mode == "full":
        return "full", ()
    replacements.extend(glyph_replacements)
    if not replacements:
        # A new ordinary draw still needs a physically acknowledged revision,
        # while RET_DELTA intentionally forbids an empty transaction.  Reuse
        # one ACK-stable definition as an idempotent revision fence, preferring
        # the canonical invisible glyph tail when the active bank has one.
        fence_glyph = next(
            (glyph for glyph in normalized_glyphs if not glyph.visible), None
        )
        if fence_glyph is not None:
            replacements.append(
                _Replacement("glyph", fence_glyph.object_id, fence_glyph)
            )
        elif normalized_controls:
            control = normalized_controls[0]
            replacements.append(
                _Replacement("control", control.object_id, control)
            )
        elif normalized_glyphs:
            glyph = normalized_glyphs[0]
            replacements.append(_Replacement("glyph", glyph.object_id, glyph))
        else:
            return "full", ()
    return "delta", tuple(replacements)


def _settle_delta(
    active: str,
    candidate: str,
    *,
    update_state: str,
    update_status: str,
    candidate_current: bool = True,
    cell_coupled: bool = True,
) -> tuple[str, str]:
    """Model the physical-ACK publication barrier for a sealed delta."""

    if update_status == "SESSION_LOST":
        return active, "fault"
    if update_state == "IDLE" and update_status == "OK":
        return candidate, "publish"
    if update_state == "SEALED" and update_status == "STALE":
        return active, "fault" if cell_coupled else "full-recapture"
    if update_state == "SEALED" and not candidate_current:
        return active, "full-recapture"
    return active, "wait"


def _settle_stale_reveal(
    active: str,
    revealed: str,
    *,
    update_state: str,
    update_status: str,
) -> tuple[str, str]:
    """Model a newer draw racing STEP's observation of a reveal ACK."""

    if update_status == "SESSION_LOST":
        return active, "fault"
    if update_state == "IDLE" and update_status == "OK":
        return revealed, "delta-from-ack"
    if update_state in ("PUBLISHING", "AWAITING"):
        return active, "wait"
    if update_state in ("CAPTURING", "SEALED"):
        return active, "full-recapture"
    return active, "invalid"


def _packed_bank_usage(
    *,
    max_documents: int,
    max_records: int,
    max_controls: int,
    max_control_bytes: int,
    cell_capacity: int,
    document_count: int,
    target_count: int,
    control_count: int,
    glyph_count: int,
    source_text_bytes: int,
    glyph_text_bytes: int,
) -> tuple[int, int]:
    """Independent byte oracle for one complete retained target bank."""

    align8 = lambda value: (value + 7) & ~7
    bank_bytes = (
        216
        + max_records * 24
        + max_controls * 192
        + max_controls * 48
        + align8(max_control_bytes)
        + cell_capacity * 120
        + cell_capacity * 16
        + align8(cell_capacity * 4)
        + max_documents * 160
    )
    used_bytes = (
        216
        + target_count * 24
        + control_count * 192
        + control_count * 48
        + align8(source_text_bytes)
        + glyph_count * 120
        + glyph_count * 16
        + align8(glyph_text_bytes)
        + document_count * 160
    )
    return used_bytes, bank_bytes


@dataclass(frozen=True)
class _MenuDocument:
    token: int
    slot: int
    geometry: tuple[int, int, int, int]
    epoch: int
    topology_epoch: int
    record_offset: int
    record_bytes: int
    text_offset: int
    text: bytes


@dataclass(frozen=True)
class _MenuControl:
    object_id: int
    parent_id: int
    region_id: int
    owner: int
    generation: int
    kind: int
    root_height: int
    root_width: int
    label_address: int
    label_bytes: int
    shortcut_address: int
    shortcut_bytes: int
    content_address: int = 0
    content_bytes: int = 0
    state: int = 3
    order: int = 0
    row: int = 0
    col: int = 0
    height: int = 0
    width: int = 0
    z: int = 0


@dataclass(frozen=True)
class _MenuCorrelation:
    attachment: int
    source: int
    index: int
    subkey: int
    control_id: int
    lifecycle_generation: int


@dataclass(frozen=True)
class _MenuStateRecord:
    source_index: int
    subkey: int
    parent_index_plus_one: int
    kind: int
    state: int
    ordinal: int
    label_offset: int
    label_bytes: int
    shortcut_offset: int
    shortcut_bytes: int
    resolved: tuple[int, int, int, int, int]
    header_valid: bool = True


@dataclass(frozen=True)
class _MenuAckBaseline:
    bank_role: str
    owner: int
    generation: int
    region_id: int
    first_id: int
    rows: int
    cols: int
    text_base: int
    documents: tuple[_MenuDocument, ...]
    controls: tuple[_MenuControl, ...]
    correlations: tuple[_MenuCorrelation, ...]


def _menu_text_rebase(
    address: int,
    length: int,
    *,
    old_start: int,
    old_bytes: int,
    new_start: int,
) -> int | None:
    """Rebase one pointer only after its complete old document-local span."""

    if length == 0:
        return 0 if address == 0 else None
    if address < old_start or address + length > old_start + old_bytes:
        return None
    return new_start + address - old_start


def _menu_patch_rte_state(kind: int, state: int) -> int | None:
    """Independent UMSN validation and state projection for the patch path."""

    visible, enabled, focused, opened, selected, paintable = (1, 2, 4, 8, 16, 32)
    if state & ~63:
        return None
    if state & paintable and not state & visible:
        return None
    if state & (opened | selected) and not state & paintable:
        return None
    allowed = {
        1: visible | enabled | paintable,
        2: 63,
        3: visible | enabled | focused | selected | paintable,
        4: visible | paintable,
    }.get(kind)
    if allowed is None or state & ~allowed or kind != 4 and not state & enabled:
        return None
    return (
        (1 if state & visible else 0)
        | (2 if state & enabled else 0)
        | (4 if state & opened else 0)
        | (8 if state & selected else 0)
    )


def _preflight_menu_state_patch(
    baseline: _MenuAckBaseline,
    current: _MenuDocument,
    records: tuple[_MenuStateRecord, ...],
) -> tuple[_MenuControl, ...] | None:
    """Model the unequal-epoch proof; return state-only patched controls."""

    if baseline.bank_role != "TARGET-ACTIVE":
        return None
    matches = tuple(
        document
        for document in baseline.documents
        if document.token == current.token and document.slot == current.slot
    )
    if len(matches) != 1:
        return None
    prior = matches[0]
    if (
        current.token == 0
        or current.slot == 0
        or current.epoch == 0
        or prior.epoch == 0
        or current.epoch == prior.epoch
        or current.topology_epoch == 0
        or prior.topology_epoch == 0
        or current.topology_epoch != prior.topology_epoch
        or current.topology_epoch > current.epoch
        or prior.topology_epoch > prior.epoch
        or current.geometry != prior.geometry
        or current.record_bytes != prior.record_bytes
        or current.text != prior.text
        or current.record_bytes <= 0
        or current.record_bytes % 192
    ):
        return None

    count = current.record_bytes // 192
    old_offset = prior.record_offset // 192
    if len(records) != count:
        return None
    controls = baseline.controls[old_offset : old_offset + count]
    correlations = baseline.correlations[old_offset : old_offset + count]
    if len(controls) != count or len(correlations) != count:
        return None

    old_first = baseline.first_id + old_offset
    old_last = old_first + count - 1
    controls_by_id: dict[int, _MenuControl] = {}
    for ordinal, control in enumerate(controls):
        if (
            control.object_id != old_first + ordinal
            or control.owner != baseline.owner
            or control.generation != baseline.generation
            or control.region_id != baseline.region_id
            or control.root_height != baseline.rows
            or control.root_width != baseline.cols
            or control.kind not in (1, 2, 3, 4)
            or control.content_address != 0
            or control.content_bytes != 0
            or (
                control.parent_id != 0
                and not old_first <= control.parent_id < control.object_id
            )
        ):
            return None
        controls_by_id[control.object_id] = control

    seen_ids: set[int] = set()
    for record, correlation in zip(records, correlations, strict=True):
        if (
            record.source_index < 0
            or record.subkey != 0
            or correlation.attachment != current.token
            or correlation.source != 1
            or correlation.index != record.source_index
            or correlation.subkey != record.subkey
            or correlation.lifecycle_generation != 0
            or not old_first <= correlation.control_id <= old_last
            or correlation.control_id in seen_ids
        ):
            return None
        seen_ids.add(correlation.control_id)
    if seen_ids != set(range(old_first, old_last + 1)):
        return None

    open_menu_seen = False
    selected_menu_seen = False
    selected_item_parents: set[int] = set()
    state_by_id: dict[int, int] = {}
    for record, correlation in zip(records, correlations, strict=True):
        control = controls_by_id[correlation.control_id]
        projected_state = _menu_patch_rte_state(record.kind, record.state)
        if (
            not record.header_valid
            or projected_state is None
            or control.kind != record.kind
        ):
            return None

        if record.kind == 2:
            if record.state & 8:
                if open_menu_seen:
                    return None
                open_menu_seen = True
            if record.state & 16:
                if selected_menu_seen:
                    return None
                selected_menu_seen = True
        if record.kind == 3 and record.state & 16:
            if (
                control.parent_id == 0
                or control.parent_id in selected_item_parents
            ):
                return None
            selected_item_parents.add(control.parent_id)
        state_by_id[correlation.control_id] = projected_state

    return tuple(
        replace(control, state=state_by_id[control.object_id])
        for control in controls
    )


def _preflight_exact_menu_reuse(
    baseline: _MenuAckBaseline,
    current: _MenuDocument,
    *,
    current_owner: int,
    current_generation: int,
    current_region: int,
    current_first_id: int,
    current_text_base: int,
    output_control_count: int,
    output_correlation_count: int,
    control_capacity_bytes: int,
    correlation_capacity_bytes: int,
) -> tuple[tuple[_MenuControl, ...], tuple[_MenuCorrelation, ...]] | None:
    """Read-only model of the unchanged-epoch reuse preflight."""

    if baseline.bank_role != "TARGET-ACTIVE":
        return None
    if baseline.owner != current_owner or baseline.generation != current_generation:
        return None
    matches = tuple(
        document
        for document in baseline.documents
        if document.token == current.token and document.slot == current.slot
    )
    if len(matches) != 1:
        return None
    prior = matches[0]
    if (
        current.token == 0
        or current.slot == 0
        or current.epoch == 0
        or current.topology_epoch == 0
        or prior.topology_epoch == 0
        or current.topology_epoch > current.epoch
        or prior.topology_epoch > prior.epoch
        or prior.epoch != current.epoch
        or prior.geometry != current.geometry
        or prior.record_bytes != current.record_bytes
        or len(prior.text) != len(current.text)
        or prior.text != current.text
        or prior.record_bytes <= 0
        or prior.record_bytes % 192
        or prior.record_offset % 192
        or current.record_offset % 192
    ):
        return None

    count = current.record_bytes // 192
    old_offset = prior.record_offset // 192
    new_offset = current.record_offset // 192
    if output_control_count != new_offset or output_correlation_count != new_offset:
        return None
    if (new_offset + count) * 192 > control_capacity_bytes:
        return None
    if (new_offset + count) * 48 > correlation_capacity_bytes:
        return None
    if old_offset + count > len(baseline.controls):
        return None
    if old_offset + count > len(baseline.correlations):
        return None

    old_first = baseline.first_id + old_offset
    new_first = current_first_id + new_offset
    old_text_start = baseline.text_base + prior.text_offset
    new_text_start = current_text_base + current.text_offset
    planned_controls: list[_MenuControl] = []
    for ordinal, control in enumerate(
        baseline.controls[old_offset : old_offset + count]
    ):
        expected_id = old_first + ordinal
        if (
            control.object_id != expected_id
            or control.owner != baseline.owner
            or control.generation != baseline.generation
            or control.region_id != baseline.region_id
            or control.kind not in (1, 2, 3, 4)
            or control.root_height != baseline.rows
            or control.root_width != baseline.cols
            or (
                control.parent_id != 0
                and not old_first <= control.parent_id < old_first + count
            )
            or control.content_address != 0
            or control.content_bytes != 0
        ):
            return None
        rebased: list[int] = []
        for address, length in (
            (control.label_address, control.label_bytes),
            (control.shortcut_address, control.shortcut_bytes),
        ):
            new_address = _menu_text_rebase(
                address,
                length,
                old_start=old_text_start,
                old_bytes=len(prior.text),
                new_start=new_text_start,
            )
            if new_address is None:
                return None
            rebased.append(new_address)
        planned_controls.append(
            replace(
                control,
                object_id=new_first + ordinal,
                parent_id=(
                    0
                    if control.parent_id == 0
                    else new_first + control.parent_id - old_first
                ),
                region_id=current_region,
                label_address=rebased[0],
                shortcut_address=rebased[1],
                content_address=0,
            )
        )

    planned_correlations: list[_MenuCorrelation] = []
    seen_ids: set[int] = set()
    for correlation in baseline.correlations[old_offset : old_offset + count]:
        if (
            correlation.attachment != current.token
            or correlation.source != 1
            or correlation.index < 0
            or correlation.subkey != 0
            or correlation.lifecycle_generation != 0
            or not old_first <= correlation.control_id < old_first + count
            or correlation.control_id in seen_ids
        ):
            return None
        seen_ids.add(correlation.control_id)
        planned_correlations.append(
            replace(
                correlation,
                control_id=new_first + correlation.control_id - old_first,
            )
        )
    if seen_ids != set(range(old_first, old_first + count)):
        return None
    return tuple(planned_controls), tuple(planned_correlations)


def _try_exact_menu_reuse(
    baseline: _MenuAckBaseline,
    current: _MenuDocument,
    output_controls: tuple[_MenuControl, ...],
    output_correlations: tuple[_MenuCorrelation, ...],
    **kwargs: int,
) -> tuple[
    tuple[_MenuControl, ...], tuple[_MenuCorrelation, ...], bool
]:
    """Commit only a completely preflighted exact-epoch segment."""

    planned = _preflight_exact_menu_reuse(
        baseline,
        current,
        output_control_count=len(output_controls),
        output_correlation_count=len(output_correlations),
        **kwargs,
    )
    if planned is None:
        return output_controls, output_correlations, False
    controls, correlations = planned
    return output_controls + controls, output_correlations + correlations, True


def _model_menu_segment(
    document: _MenuDocument,
    *,
    owner: int,
    generation: int,
    region: int,
    frame_first_id: int,
    rows: int,
    cols: int,
    text_base: int,
) -> tuple[tuple[_MenuControl, ...], tuple[_MenuCorrelation, ...]]:
    """Construct a canonical model segment without production helpers."""

    count = document.record_bytes // 192
    offset = document.record_offset // 192
    first = frame_first_id + offset
    text_start = text_base + document.text_offset
    controls = tuple(
        _MenuControl(
            object_id=first + ordinal,
            parent_id=0 if ordinal == 0 else first,
            region_id=region,
            owner=owner,
            generation=generation,
            kind=1 if ordinal == 0 else 2,
            root_height=rows,
            root_width=cols,
            label_address=text_start + ordinal % len(document.text),
            label_bytes=1,
            shortcut_address=text_start + ordinal % len(document.text),
            shortcut_bytes=1,
        )
        for ordinal in range(count)
    )
    correlations = tuple(
        _MenuCorrelation(
            attachment=document.token,
            source=1,
            index=ordinal,
            subkey=0,
            control_id=first + count - 1 - ordinal,
            lifecycle_generation=0,
        )
        for ordinal in range(count)
    )
    return controls, correlations


def _menu_reuse_scenario() -> tuple[
    _MenuAckBaseline, tuple[_MenuDocument, ...]
]:
    """Three documents with a changed, resized middle menu family."""

    prior = (
        _MenuDocument(1, 101, (0, 0, 20, 80), 11, 11, 0, 384, 0, b"aa"),
        _MenuDocument(
            2, 102, (20, 0, 20, 80), 12, 12, 384, 384, 2, b"bbb"
        ),
        _MenuDocument(
            3, 103, (40, 0, 20, 80), 13, 13, 768, 384, 5, b"cc"
        ),
    )
    current = (
        prior[0],
        _MenuDocument(
            2, 102, (20, 0, 20, 80), 22, 22, 384, 576, 2, b"middle"
        ),
        _MenuDocument(
            3, 103, (40, 0, 20, 80), 13, 13, 960, 384, 8, b"cc"
        ),
    )
    controls: list[_MenuControl] = []
    correlations: list[_MenuCorrelation] = []
    for document in prior:
        one_controls, one_correlations = _model_menu_segment(
            document,
            owner=70,
            generation=9,
            region=7,
            frame_first_id=100,
            rows=84,
            cols=280,
            text_base=0x1000,
        )
        controls.extend(one_controls)
        correlations.extend(one_correlations)
    return (
        _MenuAckBaseline(
            bank_role="TARGET-ACTIVE",
            owner=70,
            generation=9,
            region_id=7,
            first_id=100,
            rows=84,
            cols=280,
            text_base=0x1000,
            documents=prior,
            controls=tuple(controls),
            correlations=tuple(correlations),
        ),
        current,
    )


@dataclass(frozen=True)
class _ResidualRun:
    """Renderer-neutral residual run used by the row-damage byte oracle."""

    row: int
    col: int
    width: int
    style: int
    text: bytes


def _project_residual_rows(
    cells: tuple[tuple[tuple[str, int], ...], ...],
    claims: tuple[tuple[int, int, int, int], ...],
    *,
    max_run_bytes: int,
    selected_rows: set[int] | None = None,
    reads: set[tuple[int, int]] | None = None,
) -> tuple[_ResidualRun, ...]:
    """Small independent model of canonical residual row projection."""

    output: list[_ResidualRun] = []
    for row, source_row in enumerate(cells):
        if selected_rows is not None and row not in selected_rows:
            continue
        run_col = 0
        run_style = 0
        run_width = 0
        run_text = bytearray()

        def close_run() -> None:
            nonlocal run_width, run_text
            if run_width:
                output.append(
                    _ResidualRun(
                        row, run_col, run_width, run_style, bytes(run_text)
                    )
                )
            run_width = 0
            run_text = bytearray()

        for col, (character, style) in enumerate(source_row):
            claimed = any(
                row0 <= row < row1 and col0 <= col < col1
                for row0, col0, row1, col1 in claims
            )
            if claimed:
                close_run()
                continue
            if reads is not None:
                reads.add((row, col))
            encoded = character.encode("utf-8")
            if run_width and (
                style != run_style
                or len(run_text) + len(encoded) > max_run_bytes
            ):
                close_run()
            if not run_width:
                run_col = col
                run_style = style
            run_width += 1
            run_text.extend(encoded)
        close_run()
    return tuple(output)


def _old_claim_rows_from_residual(
    runs: tuple[_ResidualRun, ...], *, cols: int, rows: int
) -> set[int]:
    """Infer exactly which ACK rows contain a residual coverage gap."""

    dirty: set[int] = set()
    cursor = 0
    for row in range(rows):
        cover = 0
        while cursor < len(runs) and runs[cursor].row == row:
            run = runs[cursor]
            assert run.col >= cover
            if run.col != cover:
                dirty.add(row)
            cover = run.col + run.width
            assert cover <= cols
            cursor += 1
        if cover != cols:
            dirty.add(row)
    assert cursor == len(runs)
    return dirty


def _assemble_residual_damage(
    front: tuple[tuple[tuple[str, int], ...], ...],
    back: tuple[tuple[tuple[str, int], ...], ...],
    old_claims: tuple[tuple[int, int, int, int], ...],
    current_claims: tuple[tuple[int, int, int, int], ...],
    *,
    max_run_bytes: int,
    eligible: bool = True,
    force: bool = False,
) -> tuple[tuple[_ResidualRun, ...], set[int], set[tuple[int, int]], str]:
    """Model ACK-baselined clean-row reuse and dirty-row reconstruction."""

    rows = len(back)
    cols = len(back[0])
    active = _project_residual_rows(
        front, old_claims, max_run_bytes=max_run_bytes
    )
    reads: set[tuple[int, int]] = set()
    if not eligible or force:
        return (
            _project_residual_rows(
                back,
                current_claims,
                max_run_bytes=max_run_bytes,
                reads=reads,
            ),
            set(range(rows)),
            reads,
            "full",
        )

    dirty = {row for row in range(rows) if front[row] != back[row]}
    dirty.update(
        row
        for row0, _col0, row1, _col1 in current_claims
        for row in range(row0, row1)
    )
    dirty.update(_old_claim_rows_from_residual(active, cols=cols, rows=rows))
    rebuilt = _project_residual_rows(
        back,
        current_claims,
        max_run_bytes=max_run_bytes,
        selected_rows=dirty,
        reads=reads,
    )
    by_row = {
        row: tuple(run for run in runs if run.row == row)
        for row in range(rows)
        for runs in (rebuilt if row in dirty else active,)
    }
    return tuple(run for row in range(rows) for run in by_row[row]), dirty, reads, "damage"


def _pack_residual_text(
    runs: tuple[_ResidualRun, ...],
) -> tuple[bytes, tuple[tuple[int, int], ...]]:
    text = bytearray()
    refs: list[tuple[int, int]] = []
    for run in runs:
        refs.append((len(text), len(run.text)))
        text.extend(run.text)
    return bytes(text), tuple(refs)


def _pack_residual_plan(
    runs: tuple[_ResidualRun, ...],
    *,
    rows: int,
    cols: int,
    first_object: int,
) -> tuple[bytes, bytes, bytes, bytes]:
    """Pack the exact plan/item/ref/text shapes assembled by the producer."""

    text, refs = _pack_residual_text(runs)
    items = b"".join(
        struct.pack(
            "<15Q",
            first_object + index,
            0,
            run.row,
            run.col,
            1,
            run.width,
            rows,
            cols,
            0,
            (1 << 64) - 1,
            run.style,
            0,
            0,
            len(run.text),
            0,
        )
        for index, run in enumerate(runs)
    )
    packed_refs = b"".join(struct.pack("<2Q", *ref) for ref in refs)
    plan = (
        struct.pack(
            "<18Q",
            1,
            2,
            cols,
            rows,
            3,
            0,
            0,
            cols,
            rows,
            0,
            0,
            0,
            0,
            0,
            1,
            0x1000 if items else 0,
            len(items),
            0,
        )
        if items
        else bytes(144)
    )
    return plan, items, packed_refs, text


@dataclass(frozen=True)
class _ReservePlan:
    """Independent result for the producer's optional empty-slot padding."""

    glyph_slots: int
    identity_basis: str
    reserve_applied: bool


def _bounded_glyph_reserve(
    *,
    control_count: int,
    content_items: int,
    actual_glyph_count: int,
    active_glyph_slots: int,
    cell_capacity: int,
    glyph_item_capacity: int,
    glyph_ref_capacity: int,
    object_limit: int,
    op_limit: int,
    instrument_count: int = 0,
    instrument_region_count: int = 0,
) -> _ReservePlan:
    """Model exact-new topology and bounded acknowledged-topology reuse."""

    base_region_ops = int(control_count > 0 or actual_glyph_count > 0)
    maximum = min(
        cell_capacity,
        glyph_item_capacity,
        glyph_ref_capacity,
        max(
            0,
            object_limit - control_count - content_items - instrument_count,
        ),
        max(
            0,
            op_limit
            - control_count
            - instrument_count
            - instrument_region_count
            - base_region_ops,
        ),
    )

    if actual_glyph_count <= active_glyph_slots <= maximum:
        return _ReservePlan(
            active_glyph_slots,
            "active",
            active_glyph_slots > actual_glyph_count,
        )
    return _ReservePlan(actual_glyph_count, "actual-only", False)


def _preflight_reserved_candidate(
    plan: _ReservePlan,
    *,
    actual_glyph_count: int,
    padded_status: str,
    unpadded_status: str = "OK",
) -> tuple[_ReservePlan, str, int]:
    """Model one conservative retry for opaque provider CAPACITY."""

    if padded_status == "CAPACITY" and plan.reserve_applied:
        unpadded = _ReservePlan(actual_glyph_count, "actual-only", False)
        return unpadded, unpadded_status, 2
    return plan, padded_status, 1


def _control(
    *,
    object_id: int,
    state: int,
    semantic_key: tuple[int, int, int, int] = (7, 3, 0, 11),
    region_id: int = 11,
    parent_id: int = 40,
    label: bytes = b"File",
    kind: int = 2,
) -> _Control:
    return _Control(
        semantic_key=semantic_key,
        object_id=object_id,
        region_id=region_id,
        kind=kind,
        state=state,
        z=0,
        parent_key=(7, 3, 0, 0),
        parent_id=parent_id,
        order=0,
        geometry=(0, 0, 1, 4, 84, 280),
        label=label,
        shortcut=b"Alt+F",
    )


def _glyph(
    *,
    object_id: int,
    text: bytes,
    region_id: int = 11,
    parent_id: int = 0,
    row: int = 1,
    col: int = 0,
    height: int = 1,
    width: int | None = None,
    root_height: int = 84,
    root_width: int = 280,
    z: int = 0,
    visible: bool = True,
    foreground: int = 0xCCCCCCFF,
    background: int = 0x202020FF,
    attrs: int = 0,
) -> _Glyph:
    return _Glyph(
        object_id=object_id,
        region_id=region_id,
        parent_id=parent_id,
        row=row,
        col=col,
        height=height,
        width=max(1, len(text)) if width is None else width,
        root_height=root_height,
        root_width=root_width,
        z=z,
        visible=visible,
        foreground=foreground,
        background=background,
        attrs=attrs,
        text=text,
    )


def _glyph_tomb(*, object_id: int, region_id: int = 11) -> _Glyph:
    return _glyph(
        object_id=object_id,
        region_id=region_id,
        text=b"",
        row=0,
        col=0,
        height=1,
        width=1,
        visible=False,
        foreground=0,
        background=0,
    )


def _canonical_glyph_tomb(active: _Glyph) -> _Glyph:
    """Return the exact invisible one-cell tombstone retained for an ACK slot."""

    return replace(
        active,
        parent_id=0,
        row=0,
        col=0,
        height=1,
        width=1,
        z=0,
        visible=False,
        foreground=0,
        background=0,
        attrs=0,
        text=b"",
    )


def _pack_glyph_bank(glyphs: tuple[_Glyph, ...]) -> tuple[bytes, bytes, bytes]:
    """Pack exact compact item/ref/text bytes without production helpers."""

    items = bytearray()
    refs = bytearray()
    text = bytearray()
    for glyph in glyphs:
        offset = len(text)
        text.extend(glyph.text)
        fields = (
            glyph.object_id,
            glyph.parent_id,
            glyph.row,
            glyph.col,
            glyph.height,
            glyph.width,
            glyph.root_height,
            glyph.root_width,
            glyph.z,
            _U64_MAX if glyph.visible else 0,
            glyph.foreground,
            glyph.background,
            glyph.attrs,
            len(glyph.text),
            0,
        )
        items.extend(struct.pack("<15Q", *(value & _U64_MAX for value in fields)))
        refs.extend(struct.pack("<2Q", offset, len(glyph.text)))
    return bytes(items), bytes(refs), bytes(text)


def test_invisible_glyph_oracle_requires_canonical_one_cell_geometry() -> None:
    tombstone = _glyph_tomb(object_id=0x1_0000_0001)

    assert _glyph_bank_shape((tombstone,), fresh_ids=True) == (0, (84, 280))
    for malformed in (
        replace(tombstone, row=1),
        replace(tombstone, col=1),
        replace(tombstone, height=0),
        replace(tombstone, width=0),
    ):
        assert _glyph_bank_shape((malformed,), fresh_ids=True) is None

    items, refs, text = _pack_glyph_bank((tombstone,))
    fields = struct.unpack("<15Q", items)
    assert (fields[2], fields[3], fields[4], fields[5]) == (0, 0, 1, 1)
    assert fields[9] == 0
    assert refs == bytes(16)
    assert text == b""


def test_row_damage_oracle_reuses_only_ack_equivalent_rows() -> None:
    front = tuple(
        tuple((character, 1) for character in row)
        for row in ("abcdef", "ghijkl", "mnopqr", "stuvwx")
    )

    # A one-cell style/text edit rebuilds exactly its row.  The canonical
    # output, dense text packing, and rebased refs remain byte-equivalent to a
    # complete projection; no clean-row cell is read.
    changed = [list(row) for row in front]
    changed[1][2] = ("Z", 2)
    back = tuple(tuple(row) for row in changed)
    assembled, dirty, reads, path = _assemble_residual_damage(
        front, back, (), (), max_run_bytes=3
    )
    full = _project_residual_rows(back, (), max_run_bytes=3)
    assert (assembled, dirty, path) == (full, {1}, "damage")
    assert reads == {(1, col) for col in range(6)}
    packed_text, refs = _pack_residual_text(assembled)
    assert [offset for offset, _length in refs] == [
        sum(len(run.text) for run in assembled[:index])
        for index in range(len(assembled))
    ]
    assert [packed_text[offset : offset + length] for offset, length in refs] == [
        run.text for run in assembled
    ]

    # CELL equality is insufficient when semantic claims move or disappear.
    # Old residual gaps dirty removed/whole-row claims; current claims dirty
    # their new rows.  The untouched final row is copied without CELL reads.
    old_claims = ((0, 1, 1, 3), (1, 0, 2, 6))
    current_claims = ((2, 2, 3, 4),)
    assembled, dirty, reads, path = _assemble_residual_damage(
        front,
        front,
        old_claims,
        current_claims,
        max_run_bytes=3,
    )
    full = _project_residual_rows(front, current_claims, max_run_bytes=3)
    assert (assembled, dirty, path) == (full, {0, 1, 2}, "damage")
    assert not any(row == 3 for row, _col in reads)
    assert reads == {
        (row, col)
        for row in (0, 1, 2)
        for col in range(6)
        if not (row == 2 and 2 <= col < 4)
    }

    # Even an unchanged claim row is conservatively rebuilt.  FORCE or an
    # ACK/front-generation mismatch takes the ordinary complete path.
    assembled, dirty, reads, path = _assemble_residual_damage(
        front, front, ((2, 2, 3, 4),), ((2, 2, 3, 4),), max_run_bytes=3
    )
    assert dirty == {2}
    assert reads == {(2, col) for col in (0, 1, 4, 5)}
    assert assembled == _project_residual_rows(
        front, ((2, 2, 3, 4),), max_run_bytes=3
    )
    for force, eligible in ((True, True), (False, False)):
        assembled, dirty, reads, path = _assemble_residual_damage(
            front,
            front,
            (),
            (),
            max_run_bytes=3,
            force=force,
            eligible=eligible,
        )
        assert path == "full"
        assert dirty == set(range(4))
        assert reads == {(row, col) for row in range(4) for col in range(6)}
        assert assembled == _project_residual_rows(front, (), max_run_bytes=3)

    # Compare the actual 144-byte plan, 120-byte items, refs, and dense text
    # for dirty/clean/dirty ordering with multibyte UTF-8 splits and native
    # 64-bit object IDs.  A fully claimed dirty row legally emits no item.
    unicode_front = (
        (("é", 1), ("a", 1), ("b", 1), ("c", 1)),
        (("d", 1), ("e", 1), ("f", 1), ("g", 1)),
        (("h", 1), ("i", 1), ("j", 1), ("k", 1)),
    )
    unicode_back = (
        (("é", 1), ("A", 2), ("b", 1), ("c", 1)),
        unicode_front[1],
        (("h", 1), ("i", 1), ("J", 2), ("k", 1)),
    )
    whole_row_claim = ((2, 0, 3, 4),)
    assembled, dirty, reads, path = _assemble_residual_damage(
        unicode_front,
        unicode_back,
        (),
        whole_row_claim,
        max_run_bytes=3,
    )
    full = _project_residual_rows(
        unicode_back, whole_row_claim, max_run_bytes=3
    )
    first_object = 0x1_0000_0010
    assert (dirty, path) == ({0, 2}, "damage")
    assert not any(row == 1 for row, _col in reads)
    assert not any(run.row == 2 for run in assembled)
    assert _pack_residual_plan(
        assembled, rows=3, cols=4, first_object=first_object
    ) == _pack_residual_plan(full, rows=3, cols=4, first_object=first_object)
    plan, items, packed_refs, text = _pack_residual_plan(
        assembled, rows=3, cols=4, first_object=first_object
    )
    assert len(plan) == 144
    plan_fields = struct.unpack("<18Q", plan)
    assert plan_fields[5:15] == (0, 0, 4, 3, 0, 0, 0, 0, 0, 1)
    assert len(items) % 120 == 0
    assert len(packed_refs) == len(items) // 120 * 16
    assert struct.unpack_from("<Q", items, 0)[0] == first_object
    for index in range(len(items) // 120):
        fields = struct.unpack_from("<15Q", items, index * 120)
        assert fields[0] == first_object + index
        assert (fields[6], fields[7]) == (3, 4)
        offset, length = struct.unpack_from("<2Q", packed_refs, index * 16)
        assert length == fields[13]
        assert text[offset : offset + length] == assembled[index].text


def test_delta_oracle_allows_state_changes_and_one_equal_revision_fence() -> None:
    active = (_control(object_id=41, state=0x03),)
    opened = (_control(object_id=1001, state=0x07, region_id=700, parent_id=1000),)

    mode, operations = _delta_or_full(active, opened, (), ())

    assert mode == "delta"
    assert operations == (
        _Replacement(
            "control",
            41,
            opened[0].with_identity(object_id=41, region_id=11, parent_id=40),
        ),
    )

    # MENU payload, geometry, topology, and control count are not state.  None
    # may be smuggled through its state-only CONTROL_REPLACE contract.
    assert _delta_or_full(
        active, (_control(object_id=1001, state=0x07, label=b"Files"),), (), ()
    ) == ("full", ())
    assert _delta_or_full(
        active,
        (replace(opened[0], content=b"STX1", content_items=1, content_utf8=4),),
        (),
        (),
    ) == ("full", ())
    assert _delta_or_full(
        active, (replace(opened[0], lifecycle_generation=9),), (), ()
    ) == ("full", ())
    assert _delta_or_full(active, (), (), ()) == ("full", ())
    moved = replace(opened[0], geometry=(0, 1, 1, 4, 84, 280))
    assert _delta_or_full(active, (moved,), (), ()) == ("full", ())
    unchanged = (
        replace(active[0], object_id=1001, region_id=700, parent_id=1000),
    )
    assert _delta_or_full(active, unchanged, (), ()) == (
        "delta",
        (_Replacement("control", 41, active[0]),),
    )

    # A changed top-level control at a nonzero graph ordinal must retain that
    # ordinal; parent comparison is allowed to use zero as its own sentinel
    # without redirecting the replacement to control zero.
    active_top = tuple(
        _control(
            object_id=41 + index,
            state=0x03,
            semantic_key=(7, 3, 0, 20 + index),
            parent_id=0,
        )
        for index in range(3)
    )
    candidate_top = tuple(
        replace(
            control,
            object_id=1001 + index,
            region_id=700,
            state=0x07 if index == 2 else 0x03,
        )
        for index, control in enumerate(active_top)
    )
    mode, operations = _delta_or_full(active_top, candidate_top, (), ())
    assert mode == "delta"
    assert [(op.family, op.object_id) for op in operations] == [("control", 43)]


def test_delta_oracle_reuses_text_identity_only_for_a_newer_stx1_revision() -> None:
    active = replace(
        _control(
            object_id=41,
            state=0x03,
            kind=_CONTROL_TEXT_AREA,
            parent_id=0,
            label=b"",
        ),
        parent_key=None,
        shortcut=b"",
        content=_stx1_content(11, b"old"),
        content_items=1,
        content_utf8=3,
        content_epoch=11,
    )
    pending = replace(
        active,
        object_id=1001,
        region_id=700,
        content=_stx1_content(12, b"new text"),
        content_items=2,
        content_utf8=8,
        content_epoch=12,
    )

    mode, operations = _delta_or_full((active,), (pending,), (), ())
    assert mode == "delta"
    assert operations == (
        _Replacement(
            "control",
            41,
            pending.with_identity(object_id=41, region_id=11, parent_id=0),
        ),
    )
    grid_active = replace(active, kind=_CONTROL_TEXT_GRID)
    grid_pending = replace(pending, kind=_CONTROL_TEXT_GRID)
    assert _delta_or_full((grid_active,), (grid_pending,), (), ())[0] == "delta"

    def rejected(**changes: object) -> None:
        candidate = replace(pending, **changes)
        assert _delta_or_full((active,), (candidate,), (), ()) == ("full", ())

    rejected(content=_stx1_content(11, b"different"), content_epoch=11)
    rejected(content=_stx1_content(10, b"older"), content_epoch=10)
    rejected(content=_stx1_content(12, b"new text"), content_epoch=13)
    rejected(content=b"STX1")
    rejected(
        content=struct.pack("<IHHQ", 0, _STX1_VERSION, 0, 12)
        + bytes(_STX1_HEADER_BYTES - 16),
    )
    rejected(
        content=struct.pack("<IHHQ", _STX1_TAG, 2, 0, 12)
        + bytes(_STX1_HEADER_BYTES - 16),
    )
    rejected(
        content=struct.pack("<IHHQ", _STX1_TAG, _STX1_VERSION, 1, 12)
        + bytes(_STX1_HEADER_BYTES - 16),
    )
    rejected(
        content=struct.pack("<IHHQ", _STX1_TAG, _STX1_VERSION, 0, 0)
        + bytes(_STX1_HEADER_BYTES - 16),
        content_epoch=0,
    )
    rejected(label=b"editor")
    rejected(shortcut=b"Ctrl+E")

    last_active = replace(
        active,
        content=_stx1_content(_U64_MAX - 1, b"penultimate"),
        content_epoch=_U64_MAX - 1,
    )
    last_pending = replace(
        pending,
        content=_stx1_content(_U64_MAX, b"last"),
        content_epoch=_U64_MAX,
    )
    assert _delta_or_full((last_active,), (last_pending,), (), ())[0] == "delta"

    wrapped_active = replace(
        active,
        content=_stx1_content(_U64_MAX, b"last"),
        content_epoch=_U64_MAX,
    )
    wrapped_pending = replace(
        pending,
        content=_stx1_content(1, b"wrapped"),
        content_epoch=1,
    )
    assert _delta_or_full(
        (wrapped_active,), (wrapped_pending,), (), ()
    ) == ("full", ())

    unchanged = replace(active, object_id=1001, region_id=700)
    rejected_metadata = replace(unchanged, content_items=2)
    assert _delta_or_full(
        (active,), (rejected_metadata,), (), ()
    ) == ("full", ())


def test_delta_oracle_allows_tab_text_but_not_tab_content_changes() -> None:
    active = _control(object_id=41, state=0x03, kind=_CONTROL_TAB)
    pending = replace(
        active,
        object_id=1001,
        region_id=700,
        parent_id=1000,
        label=b"Journal",
        shortcut=b"Alt+J",
    )

    mode, operations = _delta_or_full((active,), (pending,), (), ())
    assert mode == "delta"
    assert operations == (
        _Replacement(
            "control",
            41,
            pending.with_identity(object_id=41, region_id=11, parent_id=40),
        ),
    )
    assert _delta_or_full(
        (active,), (replace(pending, content=b"not-tab-content"),), (), ()
    ) == ("full", ())
    assert _delta_or_full(
        (active,), (replace(pending, content_items=1),), (), ()
    ) == ("full", ())
    assert _delta_or_full(
        (active,), (replace(pending, content_utf8=1),), (), ()
    ) == ("full", ())


def test_delta_oracle_matches_survivors_after_graph_emission_order_moves() -> None:
    active = (
        _control(object_id=41, state=0x03, semantic_key=(7, 3, 0, 11)),
        _control(object_id=42, state=0x03, semantic_key=(7, 3, 0, 12)),
    )
    candidate = (
        _control(
            object_id=1001,
            state=0x03,
            semantic_key=(7, 3, 0, 12),
            region_id=700,
        ),
        _control(
            object_id=1002,
            state=0x07,
            semantic_key=(7, 3, 0, 11),
            region_id=700,
        ),
    )

    mode, operations = _delta_or_full(active, candidate, (), ())

    assert mode == "delta"
    assert operations == (
        _Replacement(
            "control",
            41,
            candidate[1].with_identity(
                object_id=41,
                region_id=11,
                parent_id=40,
            ),
        ),
    )


def test_delta_oracle_defines_an_appended_tab_without_rotating_pad() -> None:
    tabset_key = (9, 1, 0, 100)
    original_tab_key = (9, 1, 0, 101)
    daybook_tab_key = (9, 1, 0, 102)
    editor_key = (9, 1, 0, 103)

    active_tabset = replace(
        _control(
            object_id=1072,
            state=0x03,
            semantic_key=tabset_key,
            kind=_CONTROL_TABSET,
            parent_id=0,
            label=b"",
        ),
        parent_key=None,
        shortcut=b"",
    )
    active_tab = replace(
        _control(
            object_id=1073,
            state=0x07,
            semantic_key=original_tab_key,
            kind=_CONTROL_TAB,
            parent_id=1072,
            label=b"Notes",
        ),
        parent_key=tabset_key,
        shortcut=b"",
    )
    active_editor = replace(
        _control(
            object_id=1074,
            state=0x03,
            semantic_key=editor_key,
            kind=_CONTROL_TEXT_AREA,
            parent_id=0,
            label=b"",
        ),
        parent_key=None,
        shortcut=b"",
        content=_stx1_content(11, b"notes"),
        content_items=1,
        content_utf8=5,
        content_epoch=11,
    )
    active = (active_tabset, active_tab, active_editor)

    pending_tabset = replace(active_tabset, object_id=2000, region_id=700)
    pending_tab = replace(
        active_tab,
        object_id=2001,
        region_id=700,
        parent_id=2000,
        state=0x03,
    )
    pending_daybook_tab = replace(
        active_tab,
        semantic_key=daybook_tab_key,
        object_id=2002,
        region_id=700,
        parent_id=2000,
        state=0x07,
        order=1,
        label=b"Daybook",
    )
    pending_editor = replace(
        active_editor,
        object_id=2003,
        region_id=700,
        content=_stx1_content(12, b"# Daybook\n^"),
        content_items=2,
        content_utf8=11,
        content_epoch=12,
    )
    pending = (
        pending_tabset,
        pending_tab,
        pending_daybook_tab,
        pending_editor,
    )

    mode, operations = _delta_or_full(active, pending, (), ())

    assert mode == "delta"
    assert [(op.family, op.object_id) for op in operations] == [
        ("control", 1073),
        ("control-define", 2002),
        ("control", 1074),
    ]
    assert operations[1].value.parent_id == 1072
    assert operations[2].value.object_id == 1074
    assert operations[2].value.content == _stx1_content(12, b"# Daybook\n^")


def test_delta_oracle_reuses_spatial_glyph_ids_and_tombstones_shrink() -> None:
    active = (
        _glyph(object_id=80, text=b"File", col=0),
        _glyph(object_id=81, text=b"Edit", col=5),
    )
    candidate = (_glyph(object_id=900, region_id=700, text=b"FILE", col=0),)

    mode, operations = _delta_or_full((), (), active, candidate)

    assert mode == "delta"
    assert operations == (
        _Replacement("glyph", 80, candidate[0].with_identity(active[0])),
        _Replacement(
            "glyph",
            81,
            _canonical_glyph_tomb(active[1]),
        ),
    )

    # A delta may replace existing object identities, never create another.
    grown = candidate + (
        _glyph(object_id=901, region_id=700, text=b"Edit", col=5),
    ) + (
        _glyph(object_id=902, region_id=700, text=b"View", col=10),
    )
    assert _delta_or_full((), (), active, grown) == ("full", ())


def test_stable_glyph_tail_assignment_is_a_bijection_at_both_extremes() -> None:
    first = 0x1_0000_0800
    fresh = 0x2_0000_0800
    active = (
        _glyph(object_id=first + 1, text=b"A", row=0, col=0),
        _glyph(object_id=first, text=b"B", row=0, col=2),
        _glyph_tomb(object_id=first + 2),
    )

    mode, retired, operations = _stable_glyph_delta(active, ())
    assert mode == "delta"
    assert retired == tuple(_canonical_glyph_tomb(glyph) for glyph in active)
    assert {glyph.object_id for glyph in retired} == {
        glyph.object_id for glyph in active
    }
    assert tuple(operation.object_id for operation in operations) == (
        first + 1,
        first,
    )

    all_visible = (
        _glyph(object_id=fresh, region_id=700, text=b"A", row=0, col=0),
        _glyph(object_id=fresh + 1, region_id=700, text=b"B", row=0, col=2),
        _glyph(object_id=fresh + 2, region_id=700, text=b"C", row=0, col=4),
    )
    mode, filled, _ = _stable_glyph_delta(active, all_visible)
    assert mode == "delta"
    assert all(glyph.visible for glyph in filled)
    assert len(filled) == len(active)
    assert {glyph.object_id for glyph in filled} == {
        glyph.object_id for glyph in active
    }


def test_exact_equal_delta_uses_one_invisible_ack_slot_as_revision_fence() -> None:
    active = (
        _glyph(object_id=80, text=b"File", col=0),
        _canonical_glyph_tomb(_glyph(object_id=81, text=b"Edit", col=5)),
    )
    candidate = (_glyph(object_id=900, region_id=700, text=b"File", col=0),)

    mode, operations = _delta_or_full((), (), active, candidate)

    assert mode == "delta"
    assert operations == (
        _Replacement("glyph", 81, _canonical_glyph_tomb(active[1])),
    )

    visible_only = (_glyph(object_id=80, text=b"File", col=0),)
    fresh_visible = (_glyph(object_id=900, region_id=700, text=b"File", col=0),)
    assert _delta_or_full((), (), visible_only, fresh_visible) == (
        "delta",
        (_Replacement("glyph", 80, visible_only[0]),),
    )
    assert _delta_or_full((), (), (), ()) == ("full", ())


def test_stable_glyph_ids_survive_native_width_top_split_and_merge() -> None:
    first = 0x1_0000_0010
    fresh = 0x2_0000_0100
    active = (
        _glyph(
            object_id=first,
            row=0,
            col=0,
            width=4,
            text=b"abcd",
            foreground=0xAAAAAAFF,
        ),
        _glyph(object_id=first + 1, row=0, col=5, width=2, text=b"EF"),
        _glyph(object_id=first + 2, row=1, col=0, width=2, text=b"GH"),
        _glyph(object_id=first + 3, row=2, col=0, width=2, text=b"IJ"),
        _glyph_tomb(object_id=first + 4),
        _glyph_tomb(object_id=first + 5),
    )
    split_candidate = (
        _glyph(
            object_id=fresh,
            region_id=700,
            row=0,
            col=0,
            width=1,
            text=b"a",
            foreground=0xAAAAAAFF,
        ),
        _glyph(
            object_id=fresh + 1,
            region_id=700,
            row=0,
            col=1,
            width=3,
            text=b"bcd",
            foreground=0xBBBBBBFF,
        ),
        _glyph(
            object_id=fresh + 2,
            region_id=700,
            row=0,
            col=5,
            width=2,
            text=b"EF",
        ),
        _glyph(
            object_id=fresh + 3,
            region_id=700,
            row=1,
            col=0,
            width=2,
            text=b"GH",
        ),
        _glyph(
            object_id=fresh + 4,
            region_id=700,
            row=2,
            col=0,
            width=2,
            text=b"IJ",
        ),
    )

    mode, split_bank, operations = _stable_glyph_delta(active, split_candidate)
    expected_split = (
        split_candidate[0].with_identity(active[0]),
        split_candidate[1].with_identity(active[4]),
        split_candidate[2].with_identity(active[1]),
        split_candidate[3].with_identity(active[2]),
        split_candidate[4].with_identity(active[3]),
        active[5],
    )
    assert (mode, split_bank) == ("delta", expected_split)
    assert operations == (
        _Replacement("glyph", first, expected_split[0]),
        _Replacement("glyph", first + 4, expected_split[1]),
    )

    items, refs, text = _pack_glyph_bank(split_bank)
    assert len(items) == 6 * 120
    assert len(refs) == 6 * 16
    assert text == b"abcdEFGHIJ"
    assert tuple(
        struct.unpack_from("<Q", items, index * 120)[0] for index in range(6)
    ) == (first, first + 4, first + 1, first + 2, first + 3, first + 5)
    assert tuple(
        struct.unpack_from("<2Q", refs, index * 16) for index in range(6)
    ) == ((0, 1), (1, 3), (4, 2), (6, 2), (8, 2), (10, 0))

    merge_fresh = fresh + 0x100
    merge_candidate = (
        replace(active[0], object_id=merge_fresh, region_id=701),
        replace(active[1], object_id=merge_fresh + 1, region_id=701),
        replace(active[2], object_id=merge_fresh + 2, region_id=701),
        replace(active[3], object_id=merge_fresh + 3, region_id=701),
    )
    mode, merged_bank, operations = _stable_glyph_delta(
        split_bank, merge_candidate
    )
    expected_merged = (
        merge_candidate[0].with_identity(split_bank[0]),
        merge_candidate[1].with_identity(split_bank[2]),
        merge_candidate[2].with_identity(split_bank[3]),
        merge_candidate[3].with_identity(split_bank[4]),
        _canonical_glyph_tomb(split_bank[1]),
        split_bank[5],
    )
    assert (mode, merged_bank) == ("delta", expected_merged)
    assert tuple(operation.object_id for operation in operations) == (
        first,
        first + 4,
    )
    merged_items, merged_refs, merged_text = _pack_glyph_bank(merged_bank)
    assert merged_text == b"abcdEFGHIJ"
    assert tuple(
        struct.unpack_from("<Q", merged_items, index * 120)[0]
        for index in range(6)
    ) == tuple(first + index for index in range(6))
    assert tuple(
        struct.unpack_from("<2Q", merged_refs, index * 16)
        for index in range(6)
    ) == ((0, 4), (4, 2), (6, 2), (8, 2), (10, 0), (10, 0))

    # Publishing the merge really returns the released split identity to the
    # ACK tombstone pool; the next split reuses that same native-width ID.
    mode, split_again, operations = _stable_glyph_delta(
        merged_bank, split_candidate
    )
    assert (mode, split_again) == ("delta", split_bank)
    assert tuple(operation.object_id for operation in operations) == (
        first,
        first + 4,
    )


def test_stable_glyph_ids_ignore_dense_utf8_ref_rebasing() -> None:
    first = 0x1_0000_1010
    fresh = 0x2_0000_1010
    active = (
        _glyph(object_id=first, row=0, col=0, width=4, text=b"Abcd"),
        _glyph(object_id=first + 1, row=0, col=5, width=2, text=b"EF"),
        _glyph(object_id=first + 2, row=1, col=0, width=2, text=b"GH"),
        _glyph_tomb(object_id=first + 3),
    )
    candidate = (
        replace(
            active[0],
            object_id=fresh,
            region_id=700,
            text="ébcd".encode("utf-8"),
            foreground=0x55AA55FF,
            attrs=1,
        ),
        replace(active[1], object_id=fresh + 1, region_id=700),
        replace(active[2], object_id=fresh + 2, region_id=700),
    )

    mode, normalized, operations = _stable_glyph_delta(active, candidate)

    assert mode == "delta"
    assert tuple(glyph.object_id for glyph in normalized) == tuple(
        first + index for index in range(4)
    )
    assert operations == (
        _Replacement("glyph", first, candidate[0].with_identity(active[0])),
    )
    _active_items, active_refs, active_text = _pack_glyph_bank(active)
    _next_items, next_refs, next_text = _pack_glyph_bank(normalized)
    assert active_text == b"AbcdEFGH"
    assert next_text == "ébcdEFGH".encode("utf-8")
    assert tuple(
        struct.unpack_from("<2Q", active_refs, index * 16)
        for index in range(4)
    ) == ((0, 4), (4, 2), (6, 2), (8, 0))
    assert tuple(
        struct.unpack_from("<2Q", next_refs, index * 16)
        for index in range(4)
    ) == ((0, 5), (5, 2), (7, 2), (9, 0))


def test_stable_glyph_geometry_move_uses_ack_tomb_before_retired_id() -> None:
    first = 0x1_0000_2010
    fresh = 0x2_0000_2010
    active = (
        _glyph(object_id=first, row=0, col=0, width=4, text=b"ABCD"),
        _glyph(object_id=first + 1, row=0, col=5, width=2, text=b"EF"),
        _glyph(object_id=first + 2, row=1, col=0, width=2, text=b"GH"),
        _glyph_tomb(object_id=first + 3),
        _glyph_tomb(object_id=first + 4),
    )
    moved = (
        replace(active[0], object_id=fresh, region_id=700, col=1),
        replace(active[1], object_id=fresh + 1, region_id=700),
        replace(active[2], object_id=fresh + 2, region_id=700),
    )

    mode, normalized, operations = _stable_glyph_delta(active, moved)
    retired = _canonical_glyph_tomb(active[0])
    expected = (
        moved[0].with_identity(active[3]),
        moved[1].with_identity(active[1]),
        moved[2].with_identity(active[2]),
        retired,
        active[4],
    )

    assert (mode, normalized) == ("delta", expected)
    assert tuple(glyph.object_id for glyph in normalized) == (
        first + 3,
        first + 1,
        first + 2,
        first,
        first + 4,
    )
    assert operations == (
        _Replacement("glyph", first + 3, expected[0]),
        _Replacement("glyph", first, retired),
    )
    items, refs, text = _pack_glyph_bank(normalized)
    assert len(items) == 5 * 120
    assert text == b"ABCDEFGH"
    assert tuple(
        struct.unpack_from("<2Q", refs, index * 16) for index in range(5)
    ) == ((0, 4), (4, 2), (6, 2), (8, 0), (8, 0))


def test_stable_glyph_normalization_falls_back_without_partial_rewrite() -> None:
    first = 0x1_0000_3010
    fresh = 0x2_0000_3010
    active = (
        _glyph(object_id=first, row=0, col=0, width=2, text=b"AB"),
        _glyph(object_id=first + 1, row=1, col=0, width=2, text=b"CD"),
        _glyph_tomb(object_id=first + 2),
    )
    candidate = (
        _glyph(
            object_id=fresh,
            region_id=700,
            row=0,
            col=0,
            width=2,
            text=b"AB",
        ),
        _glyph(
            object_id=fresh + 1,
            region_id=700,
            row=1,
            col=0,
            width=2,
            text=b"CD",
        ),
    )
    malformed_active_banks = (
        (
            active[0],
            active[1],
            replace(active[2], object_id=first + 1),
        ),
        (
            active[0],
            active[2],
            active[1],
        ),
    )
    malformed_candidates = (
        (
            candidate[0],
            replace(candidate[1], row=0, col=0),
        ),
        (
            replace(candidate[0], object_id=fresh + 1),
            replace(candidate[1], object_id=fresh),
        ),
        (
            candidate[0],
            replace(candidate[1], object_id=_U64_MAX + 1),
        ),
    )

    for malformed_active in malformed_active_banks:
        mode, untouched, operations = _stable_glyph_delta(
            malformed_active, candidate
        )
        assert (mode, untouched, operations) == ("full", candidate, ())
    for malformed_candidate in malformed_candidates:
        mode, untouched, operations = _stable_glyph_delta(
            active, malformed_candidate
        )
        assert (mode, untouched, operations) == (
            "full",
            malformed_candidate,
            (),
        )


def test_delta_oracle_publishes_only_after_exact_ack_and_recaptures_stale() -> None:
    for state in ("SEALED", "PUBLISHING", "AWAITING"):
        assert _settle_delta(
            "frame-7",
            "frame-8",
            update_state=state,
            update_status="OK",
        ) == ("frame-7", "wait")

    assert _settle_delta(
        "frame-7",
        "frame-8",
        update_state="IDLE",
        update_status="OK",
    ) == ("frame-8", "publish")

    # Once publication has begun, a newer guest draw cannot revoke the frame
    # whose physical completion is in flight.  Exact ACK publishes that bank;
    # the following draw can then produce another revision.
    for state in ("PUBLISHING", "AWAITING"):
        assert _settle_delta(
            "frame-7",
            "frame-8",
            update_state=state,
            update_status="OK",
            candidate_current=False,
        ) == ("frame-7", "wait")
    assert _settle_delta(
        "frame-7",
        "frame-8",
        update_state="IDLE",
        update_status="OK",
        candidate_current=False,
    ) == ("frame-8", "publish")

    # Supersession remains cancellable before publication.  A retained-only
    # rejection rewinds to SEALED+STALE, but an ordinary CELL-coupled delta
    # quarantines the session and reports SESSION_LOST instead.
    assert _settle_delta(
        "frame-7",
        "frame-8",
        update_state="SEALED",
        update_status="OK",
        candidate_current=False,
    ) == ("frame-7", "full-recapture")
    assert _settle_delta(
        "frame-7",
        "frame-8",
        update_state="SEALED",
        update_status="STALE",
        cell_coupled=False,
    ) == ("frame-7", "full-recapture")
    assert _settle_delta(
        "frame-7",
        "frame-8",
        update_state="IDLE",
        update_status="SESSION_LOST",
    ) == ("frame-7", "fault")


def test_stale_reveal_oracle_promotes_an_exact_ack_before_deriving_delta() -> None:
    assert _settle_stale_reveal(
        "cell-fallback",
        "rich-frame-1",
        update_state="IDLE",
        update_status="OK",
    ) == ("rich-frame-1", "delta-from-ack")

    for state in ("PUBLISHING", "AWAITING"):
        assert _settle_stale_reveal(
            "cell-fallback",
            "rich-frame-1",
            update_state=state,
            update_status="OK",
        ) == ("cell-fallback", "wait")

    for state in ("CAPTURING", "SEALED"):
        assert _settle_stale_reveal(
            "cell-fallback",
            "rich-frame-1",
            update_state=state,
            update_status="OK",
        ) == ("cell-fallback", "full-recapture")

    assert _settle_stale_reveal(
        "cell-fallback",
        "rich-frame-1",
        update_state="IDLE",
        update_status="SESSION_LOST",
    ) == ("cell-fallback", "fault")


def test_full_ack_bank_capacity_covers_every_configured_candidate_byte() -> None:
    maximum = dict(
        max_documents=3,
        max_records=5,
        max_controls=7,
        max_control_bytes=99,
        cell_capacity=12,
    )
    used, capacity = _packed_bank_usage(
        **maximum,
        document_count=3,
        target_count=5,
        control_count=7,
        glyph_count=12,
        source_text_bytes=99,
        glyph_text_bytes=48,
    )
    assert used == capacity == 4_280

    partial, same_capacity = _packed_bank_usage(
        **maximum,
        document_count=2,
        target_count=3,
        control_count=4,
        glyph_count=8,
        source_text_bytes=61,
        glyph_text_bytes=29,
    )
    assert partial < same_capacity == capacity


def test_retained_uidl_directory_is_caller_bounded_packed_copied_and_validated() -> None:
    source = _source()
    sizing = _word(source, "_RTHP-BYTES-BODY")
    target_sizing = _word(source, "_RTHP-TARGET-BYTES-CALC")
    target_bank_sizing = _word(source, "_RTHP-TARGET-BANK-BYTES?")
    pack_layout = _word(source, "_RTHP-PK-LAYOUT?")
    pack_sources = _word(source, "_RTHP-PK-SOURCE-SPANS?")
    pack_copy = _word(source, "_RTHP-PK-COPY?")
    packed_directory = _word(source, "_RTHP-PACK-DIRECTORY-A")
    candidate = _word(source, "_RTHP-TARGET-CANDIDATE?")
    directory = _word(source, "_RTHP-TARGET-MENU-DIRECTORY?")
    header = _word(source, "_RTHP-TARGET-BANK-HEADER?")
    publish = _word(source, "_RTHP-TARGET-PUBLISH?")

    assert (
        "document-capacity target-capacity control-capacity "
        "control-byte-capacity cells"
    ) in target_sizing
    assert (
        "_RTHP-TBS-DOCUMENTS @ RUHA-DOCUMENT-SIZE "
        "_RTHP-TBS-MUL-ADD"
    ) in target_sizing
    assert target_bank_sizing.index("_RTHP.MAX-DOCUMENTS @") < (
        target_bank_sizing.index("_RTHP.MAX-CONTROLS @")
    )
    assert sizing.index("_RTHP-B-DOCUMENTS @") < sizing.index(
        "_RTHP-TARGET-BYTES-CALC"
    )

    for exact in (
        "_RTHP-TB.DOCUMENT-COUNT @ DUP",
        "_RTHP.MAX-DOCUMENTS @ U>",
        "RUHA-DOCUMENT-SIZE _RTHP-U32*?",
        "_RTHP-PK-DIRECTORY-U !",
        "_RTHP-PK-DIRECTORY-U @ _RTHP-PK-ADD?",
        "_RTHP-PK-DIRECTORY-U @ _RTHP-PK-TAKE "
        "_RTHP-PK-DIRECTORY-A !",
    ):
        assert exact in pack_layout
    assert "_RTHP.SOURCE-DIR-USED @ _RTHP-PK-DIRECTORY-U @ <>" in pack_sources
    assert "_RTHP.SOURCE-DIR-A @ _RTHP-PK-DIRECTORY-U @" in pack_sources
    assert "_RTHP.SOURCE-DIR-U @ _RTHP-PK-BOUNDED-SOURCE?" in pack_sources
    assert (
        "_RTHP.SOURCE-DIR-A @ _RTHP-PK-DIRECTORY-A @" in pack_copy
    )
    assert "_RTHP-PK-DIRECTORY-U @ MOVE" in pack_copy
    assert "_RTHP-PACK-GLYPH-A" in packed_directory
    assert "_RTHP-TB.GLYPH-TEXT-USED @" in packed_directory
    assert "_RTHP-ALIGN8? DROP +" in packed_directory
    assert "_RTHP-TB.DOCUMENT-COUNT !" in candidate
    assert candidate.index("_RTHP-TB.DOCUMENT-COUNT !") < candidate.index(
        "_RTHP-PACK-ADMITTED-CANDIDATE"
    )

    for proof in (
        "_RTHP-TB.DOCUMENT-COUNT",
        "_RTHP.MAX-DOCUMENTS",
        "_RTHP-PACK-DIRECTORY-A",
        "RUHA-DOCUMENT-TOKEN@",
        "RUHA-DOCUMENT-SLOT-ID@",
        "_RTHP-TV-DOCUMENT-GEOMETRY?",
        "_RTHP-TV-DOCUMENT-UNIQUE?",
        "RUHA-DOCUMENT-RECORD-OFFSET@",
        "UMSN-RECORD-SIZE MOD",
        "RUHA-DOCUMENT-TEXT-OFFSET@",
        "RUHA-DOCUMENT-MENU-EPOCH@",
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@",
        "_RTHP-TV-EXPECTED-RECORD-U",
        "_RTHP-TB.MENU-TEXT-USED",
    ):
        assert proof in directory
    assert (
        "_RTHP-TV-RECORD-U @ 0= _RTHP-TV-EPOCH @ 0= <> IF 0 EXIT THEN"
        in directory
    )
    assert (
        "_RTHP-TV-RECORD-U @ 0= "
        "_RTHP-TV-TOPOLOGY-EPOCH @ 0= <> IF 0 EXIT THEN"
        in " ".join(directory.split())
    )
    assert (
        "_RTHP-TV-TOPOLOGY-EPOCH @ _RTHP-TV-EPOCH @ U> IF 0 EXIT THEN"
        in directory
    )
    assert header.index("_RTHP-PACKED-BANK?") < header.index(
        "_RTHP-TARGET-MENU-DIRECTORY?"
    )
    assert "_RTHP-TB.DOCUMENT-COUNT" in publish

    partial_used, three_document_capacity = _packed_bank_usage(
        max_documents=3,
        max_records=5,
        max_controls=7,
        max_control_bytes=99,
        cell_capacity=12,
        document_count=2,
        target_count=3,
        control_count=4,
        glyph_count=8,
        source_text_bytes=61,
        glyph_text_bytes=29,
    )
    three_used, same_capacity = _packed_bank_usage(
        max_documents=3,
        max_records=5,
        max_controls=7,
        max_control_bytes=99,
        cell_capacity=12,
        document_count=3,
        target_count=3,
        control_count=4,
        glyph_count=8,
        source_text_bytes=61,
        glyph_text_bytes=29,
    )
    _, four_document_capacity = _packed_bank_usage(
        max_documents=4,
        max_records=5,
        max_controls=7,
        max_control_bytes=99,
        cell_capacity=12,
        document_count=3,
        target_count=3,
        control_count=4,
        glyph_count=8,
        source_text_bytes=61,
        glyph_text_bytes=29,
    )
    assert three_used - partial_used == 160
    assert same_capacity == three_document_capacity
    assert four_document_capacity - three_document_capacity == 160


def test_per_document_menu_reuse_is_ack_bound_preflighted_and_rebased() -> None:
    source = _source()
    baseline = _word(source, "_RTHP-W-MENU-REUSE-BASELINE?")
    find_document = _word(source, "_RTHP-W-MENU-REUSE-FIND-DOCUMENT?")
    document = _word(source, "_RTHP-W-MENU-REUSE-DOCUMENT?")
    preflight = _word(source, "_RTHP-W-MENU-REUSE-PREFLIGHT?")
    controls = _word(source, "_RTHP-W-MENU-REUSE-CONTROLS?")
    correlations = _word(source, "_RTHP-W-MENU-REUSE-CORRELATIONS?")
    copy = _word(source, "_RTHP-W-MENU-REUSE-COPY")
    reuse = _word(source, "_RTHP-W-MENU-REUSE?")
    build = _word(source, "_RTHP-BUILD-MENU-CONTROLS?")

    assert baseline.count("_RTHP.TARGET-ACTIVE @") == 1
    assert "_RTHP.TARGET-PENDING" not in baseline
    assert "_RTHP-TARGET-BANK-HEADER?" in baseline
    for bound in (
        "_RTHP-TB.OWNER",
        "_RTHP-TB.GENERATION",
        "_RTHP-TB.COLS",
        "_RTHP-TB.ROWS",
        "_RTHP-TB.PHYSICAL-GEN",
        "_RTHP-TB.DRAW",
    ):
        assert bound in baseline
    assert build.count("_RTHP-W-MENU-REUSE-BASELINE?") == 1
    assert build.index("_RTHP-W-MENU-REUSE-BASELINE?") < build.index(
        "\n    BEGIN "
    )
    assert "_RTHP-W-MENU-REUSE-BASELINE?" not in reuse

    for match in (
        "RUHA-DOCUMENT-TOKEN@",
        "RUHA-DOCUMENT-SLOT-ID@",
        "_RTHP-W-MR-MATCHES",
    ):
        assert match in find_document
    for match in (
        "RUHA-DOCUMENT-MENU-EPOCH@",
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@",
        "RUHA-DOCUMENT-RECORD-BYTES@",
        "RUHA-DOCUMENT-TEXT-BYTES@",
    ):
        assert match in document
    assert "_RTHP-W-DOCUMENT @ 16 + 32" in document
    assert "_RTHP-W-MR-ACTIVE-DOCUMENT @ 16 + 32 COMPARE" in document
    assert re.search(r"RUHA-DOCUMENT-MENU-EPOCH@\s+DUP\s+0=", document)
    assert document.count("COMPARE") == 2
    assert "_RTHP-TB.FIRST-OBJECT" in document

    assert "_RTHP-W-MENU-REUSE-CONTROLS?" in preflight
    assert "_RTHP-W-MENU-REUSE-CORRELATIONS?" in preflight
    proofs = controls + correlations

    for proof in (
        "RTE-CONTROL-SIZE",
        "RUCP-CORRELATION-SIZE",
        "_RTE-CONTROL.ID",
        "_RTE-CONTROL.PARENT",
        "_RTE-CONTROL.REGION",
        "_RTE-CONTROL.LABEL-A",
        "_RTE-CONTROL.LABEL-U",
        "_RTE-CONTROL.SHORTCUT-A",
        "_RTE-CONTROL.SHORTCUT-U",
        "_RTE-CONTROL.CONTENT-A",
        "_RTE-CONTROL.CONTENT-U",
        "RUCP-CORRELATION-CONTROL-ID@",
    ):
        assert proof in proofs
    assert " MOVE" not in proofs
    # Never hand retained pointers to the generic validator before proving that
    # both complete spans are inside this acknowledged document's text slice.
    assert controls.rindex("_RTHP-W-MENU-REUSE-TEXT?") < controls.index(
        "RTE-CONTROL-VALID?"
    )
    assert controls.index("_RTE-CONTROL.CONTENT-A @") < controls.index(
        "RTE-CONTROL-VALID?"
    )
    for output_write in (
        "_RTE-CONTROL.ID !",
        "_RTE-CONTROL.PARENT !",
        "_RTE-CONTROL.REGION !",
        "_RUCP-X.CONTROL-ID !",
    ):
        assert output_write not in proofs

    for rewrite in (
        "_RTE-CONTROL.ID !",
        "_RTE-CONTROL.PARENT !",
        "_RTE-CONTROL.REGION !",
        "_RTE-CONTROL.LABEL-A !",
        "_RTE-CONTROL.SHORTCUT-A !",
        "_RTE-CONTROL.CONTENT-A !",
        "_RUCP-X.CONTROL-ID !",
    ):
        assert rewrite in copy
    assert "_RTHP.REGION" in copy
    assert reuse.index("_RTHP-W-MENU-REUSE-DOCUMENT?") < reuse.index(
        "_RTHP-W-MENU-REUSE-PREFLIGHT?"
    ) < reuse.index(
        "_RTHP-W-MENU-REUSE-COPY"
    )
    assert "0 EXIT" in reuse
    assert build.index("_RTHP-W-MENU-REUSE?") < build.index("RUCP-BUILD")


def test_changed_menu_epoch_has_a_preflighted_state_only_ack_patch() -> None:
    source = _source()
    document = _word(source, "_RTHP-W-MENU-REUSE-DOCUMENT?")
    correlations = _word(source, "_RTHP-W-MENU-REUSE-CORRELATIONS?")
    patch_state = _word(source, "_RTHP-W-MENU-PATCH-STATE?")
    patch_unique = _word(source, "_RTHP-W-MENU-PATCH-UNIQUE?")
    patch_bind = _word(source, "_RTHP-W-MENU-PATCH-BIND?")
    patch_record = _word(source, "_RTHP-W-MENU-PATCH-RECORD?")
    patch_preflight = _word(source, "_RTHP-W-MENU-PATCH-PREFLIGHT?")
    patch_states = _word(source, "_RTHP-W-MENU-PATCH-STATES")
    reuse = _word(source, "_RTHP-W-MENU-REUSE?")

    compact_document = " ".join(document.split())
    assert "= IF 0 _RTHP-W-MR-PATCH-STATE ! ELSE" in compact_document
    assert document.count("RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@") == 2
    assert (
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ DUP 0= IF DROP 0 EXIT THEN"
        in compact_document
    )
    assert (
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ DUP 0= IF 2DROP 0 EXIT THEN"
        in compact_document
    )
    assert "<> IF 0 EXIT THEN -1 _RTHP-W-MR-PATCH-STATE !" in compact_document

    for proof in (
        "RUCP-CORRELATION-ATTACHMENT@",
        "RUCP-CORRELATION-SOURCE@",
        "RUCP-CORRELATION-INDEX@",
        "RUCP-CORRELATION-SUBKEY@",
        "RUCP-CORRELATION-LIFECYCLE-GENERATION@",
        "RUCP-CORRELATION-CONTROL-ID@",
        "UMSN-RECORD-SOURCE-INDEX@",
        "UMSN-RECORD-SUBKEY@",
        "_RTHP.ORDER-A",
    ):
        assert proof in correlations
    assert "_RTHP.LOOKUP-A" not in correlations
    assert "_RUCP-L.CONTROL-ID" not in correlations

    for proof in (
        "_UMSN-R.MAGIC",
        "_UMSN-R.ABI",
        "_UMSN-R.BYTES",
        "_UMSN-R.SOURCE",
        "UMSN-RECORD-GENERATION@",
        "UMSN-RECORD-SOURCE-INDEX@",
        "UMSN-RECORD-SUBKEY@",
        "UMSN-RECORD-KIND@",
        "UMSN-RECORD-STATE@",
        "_RTHP-W-MENU-PATCH-STATE?",
        "_RTHP-W-MENU-PATCH-UNIQUE?",
    ):
        assert proof in patch_record
    for certified_structure in (
        "UMSN-RECORD-PARENT@",
        "UMSN-RECORD-ORDINAL@",
        "UMSN-RECORD-LABEL-OFFSET@",
        "UMSN-RECORD-LABEL-BYTES@",
        "UMSN-RECORD-SHORTCUT-OFFSET@",
        "UMSN-RECORD-SHORTCUT-BYTES@",
        "UMSN-RECORD-RESOLVED",
        "UTUI-RESOLVED-VALID?",
    ):
        assert certified_structure not in patch_record
    for removed_proof in (
        "_RTHP-W-MENU-PATCH-PARENT?",
        "_RTHP-W-MENU-PATCH-TEXT?",
        "_RTHP-W-MENU-PATCH-GEOMETRY?",
    ):
        assert removed_proof not in source
    assert "_RTE-CONTROL.PARENT @" in patch_record
    assert "_RTHP-W-MR-PARENT-ID !" in patch_record
    assert "_RTHP-W-MR-PARENT-ID @ DUP 0=" in patch_unique
    assert "_RTHP.ORDER-A" in patch_unique
    assert "3DROP" not in patch_record
    proof_slice = (
        patch_bind
        + patch_state
        + patch_unique
        + patch_record
        + patch_preflight
    )
    assert " MOVE" not in proof_slice
    assert "_RTE-CONTROL.STATE !" not in proof_slice
    assert patch_states.count("_RTE-CONTROL.STATE !") == 1
    assert reuse.index("_RTHP-W-MENU-REUSE-PREFLIGHT?") < reuse.index(
        "_RTHP-W-MENU-PATCH-PREFLIGHT?"
    ) < reuse.index(
        "_RTHP-W-MENU-REUSE-COPY"
    ) < reuse.index("_RTHP-W-MENU-PATCH-STATES")


def test_changed_menu_epoch_state_patch_proves_nonempty_topology_first() -> None:
    text = b"FileExitOpenCtrl+O"
    prior = _MenuDocument(
        7, 17, (0, 0, 84, 280), 41, 41, 0, 4 * 192, 0, text
    )
    current = replace(prior, epoch=42)
    old_text = 0x1000
    controls = (
        _MenuControl(100, 0, 9, 70, 3, 1, 84, 280, 0, 0, 0, 0,
                     state=3, row=0, col=0, height=1, width=80, z=5),
        _MenuControl(101, 100, 9, 70, 3, 2, 84, 280,
                     old_text, 4, 0, 0, state=3, order=0),
        _MenuControl(102, 101, 9, 70, 3, 3, 84, 280,
                     old_text + 8, 4, old_text + 12, 6, state=3, order=0),
        _MenuControl(103, 101, 9, 70, 3, 3, 84, 280,
                     old_text + 4, 4, 0, 0, state=3, order=1),
    )
    correlations = (
        _MenuCorrelation(7, 1, 0, 0, 100, 0),
        _MenuCorrelation(7, 1, 2, 0, 101, 0),
        _MenuCorrelation(7, 1, 5, 0, 103, 0),
        _MenuCorrelation(7, 1, 7, 0, 102, 0),
    )
    baseline = _MenuAckBaseline(
        "TARGET-ACTIVE",
        70,
        3,
        9,
        100,
        84,
        280,
        old_text,
        (prior,),
        controls,
        correlations,
    )
    records = (
        _MenuStateRecord(0, 0, 0, 1, 35, 0, 0, 0, 0, 0,
                         (0, 0, 1, 80, 5)),
        _MenuStateRecord(2, 0, 1, 2, 59, 0, 0, 4, 4, 0,
                         (1, 0, 1, 4, 0)),
        _MenuStateRecord(5, 0, 3, 3, 35, 1, 4, 4, 8, 0,
                         (3, 0, 1, 4, 0)),
        _MenuStateRecord(7, 0, 3, 3, 51, 0, 8, 4, 12, 6,
                         (2, 0, 1, 10, 0)),
    )

    patched = _preflight_menu_state_patch(baseline, current, records)
    assert patched is not None
    assert tuple(control.state for control in patched) == (3, 15, 11, 3)
    assert tuple(replace(control, state=3) for control in patched) == controls
    assert tuple(control.state for control in baseline.controls) == (3, 3, 3, 3)

    def changed_record(index: int, **changes: int | tuple[int, ...]):
        candidate = list(records)
        candidate[index] = replace(candidate[index], **changes)
        return tuple(candidate)

    authenticated_mismatches = (
        changed_record(2, kind=99),
        changed_record(2, state=51),
        changed_record(2, source_index=6),
        changed_record(2, subkey=1),
        changed_record(2, header_valid=False),
    )
    for candidate in authenticated_mismatches:
        assert _preflight_menu_state_patch(baseline, current, candidate) is None

    # These fields are covered by the adapter's collision-free topology epoch;
    # the producer no longer retraverses them on a state-only patch.
    certificate_covered_changes = (
        changed_record(3, parent_index_plus_one=1),
        changed_record(2, ordinal=0),
        changed_record(3, label_offset=9),
        changed_record(3, shortcut_bytes=5),
        changed_record(0, resolved=(1, 0, 1, 80, 5)),
    )
    for candidate in certificate_covered_changes:
        assert _preflight_menu_state_patch(baseline, current, candidate) == patched

    for topology_mismatch in (0, 40, 42):
        malformed_current = replace(current, topology_epoch=topology_mismatch)
        assert (
            _preflight_menu_state_patch(baseline, malformed_current, records)
            is None
        )

    duplicate = list(correlations)
    duplicate[3] = replace(duplicate[3], control_id=103)
    malformed_baseline = replace(baseline, correlations=tuple(duplicate))
    assert _preflight_menu_state_patch(malformed_baseline, current, records) is None


def test_changed_middle_menu_document_falls_back_while_suffix_reuses() -> None:
    baseline, current = _menu_reuse_scenario()
    assert baseline.first_id != 900
    assert baseline.region_id != 42
    output_controls: tuple[_MenuControl, ...] = ()
    output_correlations: tuple[_MenuCorrelation, ...] = ()
    reused: list[bool] = []
    build_count = 0
    common = dict(
        current_owner=70,
        current_generation=9,
        current_region=42,
        current_first_id=900,
        current_text_base=0x5000,
        control_capacity_bytes=7 * 192,
        correlation_capacity_bytes=7 * 48,
    )
    for document in current:
        output_controls, output_correlations, did_reuse = _try_exact_menu_reuse(
            baseline,
            document,
            output_controls,
            output_correlations,
            **common,
        )
        reused.append(did_reuse)
        if not did_reuse:
            build_count += 1
            built_controls, built_correlations = _model_menu_segment(
                document,
                owner=70,
                generation=9,
                region=42,
                frame_first_id=900,
                rows=84,
                cols=280,
                text_base=0x5000,
            )
            output_controls += built_controls
            output_correlations += built_correlations

    assert reused == [True, False, True]
    assert build_count == 1
    assert tuple(control.object_id for control in output_controls) == tuple(
        range(900, 907)
    )
    assert {control.region_id for control in output_controls} == {42}
    assert output_controls[1].parent_id == 900
    assert output_controls[6].parent_id == 905
    assert output_controls[5].label_address == 0x5000 + 8
    assert output_controls[6].label_address == 0x5000 + 9
    assert output_controls[5].shortcut_address == 0x5000 + 8
    assert output_controls[6].shortcut_address == 0x5000 + 9
    assert output_correlations[5].control_id == 906
    assert output_correlations[6].control_id == 905


def test_exact_epoch_menu_reuse_miss_is_read_only() -> None:
    baseline, current = _menu_reuse_scenario()
    current_document = current[2]
    prefix_controls: tuple[_MenuControl, ...] = ()
    prefix_correlations: tuple[_MenuCorrelation, ...] = ()
    for document in current[:2]:
        controls, correlations = _model_menu_segment(
            document,
            owner=70,
            generation=9,
            region=42,
            frame_first_id=900,
            rows=84,
            cols=280,
            text_base=0x5000,
        )
        prefix_controls += controls
        prefix_correlations += correlations
    assert len(prefix_controls) == len(prefix_correlations) == 5

    old_document = baseline.documents[2]
    last_control = old_document.record_offset // 192 + 1
    malformed_controls = list(baseline.controls)
    malformed_controls[last_control] = replace(
        malformed_controls[last_control],
        label_address=(
            baseline.text_base + old_document.text_offset + len(old_document.text)
        ),
        label_bytes=1,
    )
    malformed_correlations = list(baseline.correlations)
    malformed_correlations[last_control] = replace(
        malformed_correlations[last_control],
        lifecycle_generation=1,
    )
    candidates = (
        (replace(baseline, bank_role="TARGET-PENDING"), current_document),
        (replace(baseline, controls=tuple(malformed_controls)), current_document),
        (
            replace(baseline, correlations=tuple(malformed_correlations)),
            current_document,
        ),
        (baseline, replace(current_document, token=999)),
        (baseline, replace(current_document, slot=999)),
        (baseline, replace(current_document, geometry=(41, 0, 20, 80))),
        (baseline, replace(current_document, epoch=0)),
        (baseline, replace(current_document, topology_epoch=0)),
        (
            baseline,
            replace(
                current_document,
                topology_epoch=current_document.epoch + 1,
            ),
        ),
        (baseline, replace(current_document, record_bytes=192)),
        (baseline, replace(current_document, text=b"cx")),
        (baseline, replace(current_document, text=b"longer")),
    )
    common = dict(
        current_owner=70,
        current_generation=9,
        current_region=42,
        current_first_id=900,
        current_text_base=0x5000,
        control_capacity_bytes=7 * 192,
        correlation_capacity_bytes=7 * 48,
    )
    for candidate_baseline, candidate_document in candidates:
        controls, correlations, reused = _try_exact_menu_reuse(
            candidate_baseline,
            candidate_document,
            prefix_controls,
            prefix_correlations,
            **common,
        )
        assert not reused
        assert controls is prefix_controls
        assert correlations is prefix_correlations

    controls, correlations, reused = _try_exact_menu_reuse(
        baseline,
        current_document,
        prefix_controls,
        prefix_correlations,
        **(common | {"control_capacity_bytes": 7 * 192 - 1}),
    )
    assert not reused
    assert controls is prefix_controls
    assert correlations is prefix_correlations

    controls, correlations, reused = _try_exact_menu_reuse(
        baseline,
        current_document,
        prefix_controls,
        prefix_correlations,
        **(common | {"correlation_capacity_bytes": 7 * 48 - 1}),
    )
    assert not reused
    assert controls is prefix_controls
    assert correlations is prefix_correlations


def test_new_ack_bank_uses_exact_actual_slots_without_speculative_padding() -> None:
    plan = _bounded_glyph_reserve(
        control_count=142,
        content_items=57,
        actual_glyph_count=776,
        active_glyph_slots=0,
        cell_capacity=280 * 84,
        glyph_item_capacity=280 * 84,
        glyph_ref_capacity=280 * 84,
        object_limit=16384,
        op_limit=16385,
    )
    assert plan == _ReservePlan(776, "actual-only", False)


def test_acknowledged_reserve_obeys_each_runtime_and_storage_bound() -> None:
    base = dict(
        control_count=142,
        content_items=57,
        actual_glyph_count=776,
        active_glyph_slots=900,
        cell_capacity=280 * 84,
        glyph_item_capacity=280 * 84,
        glyph_ref_capacity=280 * 84,
        object_limit=1 << 20,
        op_limit=1 << 20,
    )
    cases = (
        {"cell_capacity": 899},
        {"object_limit": 142 + 57 + 899},
        {"op_limit": 1 + 142 + 899},
        {"glyph_item_capacity": 899},
        {"glyph_ref_capacity": 899},
    )

    assert _bounded_glyph_reserve(**base) == _ReservePlan(900, "active", True)
    for overrides in cases:
        plan = _bounded_glyph_reserve(**{**base, **overrides})
        assert plan == _ReservePlan(776, "actual-only", False)


def test_instrument_family_is_charged_to_object_region_and_op_reserve() -> None:
    base = dict(
        control_count=142,
        content_items=57,
        instrument_count=12,
        instrument_region_count=3,
        actual_glyph_count=776,
        active_glyph_slots=900,
        cell_capacity=280 * 84,
        glyph_item_capacity=280 * 84,
        glyph_ref_capacity=280 * 84,
        object_limit=1 << 20,
        op_limit=1 << 20,
    )
    assert _bounded_glyph_reserve(**base) == _ReservePlan(900, "active", True)

    object_tight = {
        **base,
        "object_limit": 142 + 57 + 12 + 899,
    }
    op_tight = {
        **base,
        # Base region + instrument regions + controls + instruments + glyphs.
        "op_limit": 1 + 3 + 142 + 12 + 899,
    }
    assert _bounded_glyph_reserve(**object_tight) == _ReservePlan(
        776, "actual-only", False
    )
    assert _bounded_glyph_reserve(**op_tight) == _ReservePlan(
        776, "actual-only", False
    )


def test_reserve_reuses_only_an_acknowledged_slot_bank_that_still_fits() -> None:
    base = dict(
        control_count=142,
        content_items=57,
        cell_capacity=280 * 84,
        glyph_item_capacity=280 * 84,
        glyph_ref_capacity=280 * 84,
        object_limit=16384,
        op_limit=16385,
    )

    reused = _bounded_glyph_reserve(
        **base,
        actual_glyph_count=789,
        active_glyph_slots=900,
    )
    assert reused == _ReservePlan(900, "active", True)

    # Growth beyond the acknowledged topology takes an exact full replacement.
    grown = _bounded_glyph_reserve(
        **base,
        actual_glyph_count=901,
        active_glyph_slots=900,
    )
    assert grown == _ReservePlan(901, "actual-only", False)

    no_longer_fits = _bounded_glyph_reserve(
        **{**base, "cell_capacity": 850},
        actual_glyph_count=800,
        active_glyph_slots=900,
    )
    assert no_longer_fits == _ReservePlan(800, "actual-only", False)


def test_reserve_pressure_never_removes_an_actual_glyph_or_rejects_padding() -> None:
    base = dict(
        control_count=142,
        content_items=57,
        actual_glyph_count=776,
        active_glyph_slots=900,
        cell_capacity=280 * 84,
        glyph_item_capacity=280 * 84,
        glyph_ref_capacity=280 * 84,
        object_limit=16384,
        op_limit=16385,
    )
    exact_actual_bounds = (
        {"cell_capacity": 776},
        {"glyph_item_capacity": 776},
        {"glyph_ref_capacity": 776},
        {"object_limit": 142 + 57 + 776},
        {"op_limit": 1 + 142 + 776},
    )
    for overrides in exact_actual_bounds:
        plan = _bounded_glyph_reserve(**{**base, **overrides})
        assert plan == _ReservePlan(776, "actual-only", False)


def test_provider_update_or_copy_pressure_retries_without_padding() -> None:
    proposed = _bounded_glyph_reserve(
        control_count=142,
        content_items=57,
        actual_glyph_count=776,
        active_glyph_slots=900,
        cell_capacity=280 * 84,
        glyph_item_capacity=280 * 84,
        glyph_ref_capacity=280 * 84,
        object_limit=16384,
        op_limit=16385,
    )
    assert proposed == _ReservePlan(900, "active", True)

    admitted, status, attempts = _preflight_reserved_candidate(
        proposed,
        actual_glyph_count=776,
        padded_status="CAPACITY",
        unpadded_status="OK",
    )
    assert (admitted, status, attempts) == (
        _ReservePlan(776, "actual-only", False),
        "OK",
        2,
    )

    unchanged, status, attempts = _preflight_reserved_candidate(
        proposed,
        actual_glyph_count=776,
        padded_status="OK",
    )
    assert (unchanged, status, attempts) == (proposed, "OK", 1)


def test_inline_records_are_disjoint_and_exactly_cover_the_producer() -> None:
    source = _source()
    records = (
        ("_RTHP.LIMITS", 168),
        ("_RTHP.RUCP-Q", 280),
        ("_RTHP.RUCL-Q", 112),
        ("_RTHP.RGRP-Q", 280),
        ("_RTHP.CONTROL-PLAN", 144),
        ("_RTHP.GLYPH-PLAN", 144),
        ("_RTHP.HYBRID", 120),
        ("_RTHP.ADMISSION", 320),
        ("_RTHP.RUN", 152),
    )
    expected = 464
    for name, size in records:
        assert _offset(source, name) == expected
        expected += size
    assert expected == 2184
    for name in (
        "_RTHP.TARGET0-A",
        "_RTHP.TARGET1-A",
        "_RTHP.TARGET-ACTIVE",
        "_RTHP.TARGET-PENDING",
        "_RTHP.NEXT-REGION",
        "_RTHP.NEXT-OBJECT",
        "_RTHP.ACTIVE-DRAW",
    ):
        assert _offset(source, name) == expected
        expected += 8
    for name in (
        "_RTHP.MAX-DOCUMENTS",
        "_RTHP.SOURCE-DIR-A",
        "_RTHP.SOURCE-DIR-U",
        "_RTHP.SOURCE-DIR-USED",
        "_RTHP.DOCUMENT-COUNT",
        "_RTHP.ROW-DAMAGE-A",
        "_RTHP.ROW-DAMAGE-U",
        "_RTHP.GLYPH-ID-MAP-A",
        "_RTHP.GLYPH-ID-MAP-U",
        "_RTHP.DELTA-PLAN-VALID",
        "_RTHP.DELTA-PLAN-ACTIVE",
        "_RTHP.DELTA-PLAN-PENDING",
        "_RTHP.DELTA-PLAN-ACTIVE-DRAW",
        "_RTHP.DELTA-PLAN-PENDING-DRAW",
        "_RTHP.DELTA-PLAN-CONTROLS",
        "_RTHP.DELTA-PLAN-GLYPHS",
        "_RTHP.DELTA-PLAN-ATTEMPT",
        "_RTHP.DELTA-PLAN-SOURCE-GEN",
        "_RTHP.DELTA-PLAN-PENDING-CONTENT",
        "_RTHP.DELTA-PLAN-ACTIVE-CONTENT",
        "_RTHP.SOURCE-CONTENT-EPOCH",
        "_RTHP.MAX-COLLECTION-NATIVE",
        "_RTHP.MAX-COLLECTIONS",
        "_RTHP.MAX-CONTROLS",
        "_RTHP.SOURCE-MENU-TEXT-USED",
        "_RTHP.COLLECTION-DESCRIPTORS-A",
        "_RTHP.COLLECTION-DESCRIPTORS-U",
        "_RTHP.COLLECTION-DESCRIPTORS-USED",
        "_RTHP.COLLECTION-NATIVE-A",
        "_RTHP.COLLECTION-NATIVE-U",
        "_RTHP.COLLECTION-NATIVE-USED",
        "_RTHP.SOURCE-COLLECTION-COUNT",
        "_RTHP.MENU-CONTROL-COUNT",
        "_RTHP.COLLECTION-COUNT",
        "_RTHP.COLLECTION-ITEMS",
        "_RTHP.COLLECTION-UTF8",
        "_RTHP.MAX-COLLECTION-DESCRIPTORS",
    ):
        assert _offset(source, name) == expected
        expected += 8
    assert expected == 2536
    assert _offset(source, "_RTHP.RUIP-Q") == expected
    expected += 192
    assert _offset(source, "_RTHP.INSTRUMENT-PLAN") == expected
    expected += 72
    for name in (
        "_RTHP.MAX-DGRAPH-NATIVE",
        "_RTHP.MAX-DGRAPH-DESCRIPTORS",
        "_RTHP.MAX-INSTRUMENT-REGIONS",
        "_RTHP.MAX-INSTRUMENTS",
        "_RTHP.DGRAPH-DESCRIPTORS-A",
        "_RTHP.DGRAPH-DESCRIPTORS-U",
        "_RTHP.DGRAPH-DESCRIPTORS-USED",
        "_RTHP.DGRAPH-NATIVE-A",
        "_RTHP.DGRAPH-NATIVE-U",
        "_RTHP.DGRAPH-NATIVE-USED",
        "_RTHP.SOURCE-DGRAPH-COUNT",
        "_RTHP.INSTRUMENT-REGIONS-A",
        "_RTHP.INSTRUMENT-REGIONS-U",
        "_RTHP.INSTRUMENTS-A",
        "_RTHP.INSTRUMENTS-U",
        "_RTHP.INSTRUMENT-UNITS-A",
        "_RTHP.INSTRUMENT-UNITS-U",
        "_RTHP.INSTRUMENT-UNITS-USED",
        "_RTHP.INSTRUMENT-CORR-A",
        "_RTHP.INSTRUMENT-CORR-U",
        "_RTHP.INSTRUMENT-REGION-COUNT",
        "_RTHP.INSTRUMENT-COUNT",
        "_RTHP.INSTRUMENT-LAST-REGION",
        "_RTHP.INSTRUMENT-LAST",
        "_RTHP.INSTRUMENT-CLAIM-COUNT",
        "_RTHP.BASE-CLAIMS-USED",
    ):
        assert _offset(source, name) == expected
        expected += 8
    assert _constant(source, "RTHP-SIZE") == expected == 3008


def test_full_base_projection_uses_unclipped_visible_region_contract() -> None:
    source = _source()
    control_wrap = _word(source, "_RTHP-W-WRAP-CONTROL-PLAN?")
    glyph_wrap = _word(source, "_RTHP-WRAP-GLYPH-PLAN?")
    reserve_wrap = _word(source, "_RTHP-R-PLAN-SLOTS?")

    for body, producer, plan, prefix in (
        (control_wrap, "_RTHP-W-P", "_RTHP.CONTROL-PLAN", "_RTE-CP"),
        (glyph_wrap, "_RTHP-GP-P", "_RTHP.GLYPH-PLAN", "_RTE-LP"),
        (reserve_wrap, "_RTHP-R-P", "_RTHP.GLYPH-PLAN", "_RTE-LP"),
    ):
        code = " ".join(body.split())
        for field in ("X", "Y", "COLS", "ROWS"):
            assert f"0 {producer} @ {plan} {prefix}.CLIP-{field} !" in code
        assert (
            f"RTE-REGION-VISIBLE {producer} @ {plan} "
            f"{prefix}.REGION-FLAGS !"
        ) in code
        assert "RTE-REGION-CLIPPED" not in body

    menu = " ".join(_word(source, "_RTHP-BUILD-MENU-CONTROLS?").split())
    assert (
        "_RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @ "
        "_RTHP-W-P @ _RTHP.REGION @ 0 0 _RTHP-W-P @ _RTHP.COLS @ "
        "_RTHP-W-P @ _RTHP.ROWS @ 0 0 0 0 0 RTE-REGION-VISIBLE "
        "_RTHP-W-P @ _RTHP.RUCP-Q RUCP-REQUEST-REGION!"
    ) in menu

    glyph_full = " ".join(_word(source, "_RTHP-BUILD-GLYPHS-FULL?").split())
    assert (
        "_RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @ 0 0 "
        "_RTHP-W-P @ _RTHP.COLS @ _RTHP-W-P @ _RTHP.ROWS @ "
        "0 0 0 0 0 RTE-REGION-VISIBLE 0 _RTHP-W-P @ _RTHP.RGRP-Q "
        "RGRP-REQUEST-REGION!"
    ) in glyph_full

    fixed = " ".join(_word(source, "_RTHP-FIXED-BODY?").split())
    base_present = (
        "_RTHP-X-P @ _RTHP.CONTROL-COUNT @ "
        "_RTHP-X-P @ _RTHP.GLYPH-COUNT @ OR IF"
    )
    assert base_present in fixed
    base_admission = fixed[fixed.index(base_present) :]
    base_admission = base_admission[
        : base_admission.index("_RTE-HA.CONTROL-COUNT")
    ]
    canonical_zero = base_admission.split(" ELSE ", 1)[1]
    for field in (
        "REGION-ID",
        "REGION-X",
        "REGION-Y",
        "REGION-COLS",
        "REGION-ROWS",
        "CLIP-X",
        "CLIP-Y",
        "CLIP-COLS",
        "CLIP-ROWS",
        "REGION-Z",
        "REGION-FLAGS",
    ):
        assert f"_RTE-HA.{field} @" in canonical_zero
    for plan, prefix in (
        ("_RTHP.ADMISSION", "_RTE-HA"),
        ("_RTHP.CONTROL-PLAN", "_RTE-CP"),
        ("_RTHP.GLYPH-PLAN", "_RTE-LP"),
    ):
        assert (
            f"_RTHP-X-P @ {plan} {prefix}.CLIP-X @ "
            f"_RTHP-X-P @ {plan} {prefix}.CLIP-Y @ OR "
            f"_RTHP-X-P @ {plan} {prefix}.CLIP-COLS @ OR "
            f"_RTHP-X-P @ {plan} {prefix}.CLIP-ROWS @ OR IF 0 EXIT THEN"
        ) in fixed
        assert (
            f"_RTHP-X-P @ {plan} {prefix}.REGION-FLAGS @ "
            "RTE-REGION-VISIBLE <> IF 0 EXIT THEN"
        ) in fixed

    start = " ".join(_word(source, "_RTHP-PREPARE-START").split())
    start_base_present = (
        "_RTHP-P-P @ _RTHP.CONTROL-COUNT @ "
        "_RTHP-P-P @ _RTHP.GLYPH-COUNT @ OR IF"
    )
    assert start.index(start_base_present) < start.index("RTE-REGION-DEFINE")
    assert (
        "_RTHP-P-P @ _RTHP.OWNER @ _RTHP-P-P @ _RTHP.OWNER-GEN @ "
        "_RTHP-P-P @ _RTHP.REGION @ 0 0 _RTHP-P-P @ _RTHP.COLS @ "
        "_RTHP-P-P @ _RTHP.ROWS @ 0 0 0 0 0 RTE-REGION-VISIBLE "
        "_RTHP-P-P @ _RTHP.FACADE @ RTE-REGION-DEFINE"
    ) in start
    assert start.index("RTE-REGION-DEFINE") < start.index(
        "_RTHP-EMIT-INSTRUMENT-REGIONS"
    )


def test_visible_document_directory_is_caller_bounded_copied_and_appended() -> None:
    source = _source()
    collection_capacity = _word(
        source, "RTHP-COLLECTION-CONTROL-CAPACITY"
    )
    sizing = _word(source, "_RTHP-BYTES-BODY")
    target_bank_sizing = _word(source, "_RTHP-TARGET-BANK-BYTES?")
    storage = _word(source, "RTHP-STORAGE-BYTES")
    layout = _word(source, "_RTHP-LAYOUT")
    init = _word(source, "RTHP-INIT")
    snapshot_shape = _word(source, "_RTHP-W-SNAPSHOT-SPANS?")
    document_shape = _word(source, "_RTHP-W-DOCUMENT-SHAPE?")
    copied_complete = _word(source, "_RTHP-W-COPIED-COMPLETE?")
    copy = _word(source, "_RTHP-COPY-SNAPSHOT?")
    controls = _word(source, "_RTHP-BUILD-MENU-CONTROLS?")
    control_pipeline = _word(source, "_RTHP-BUILD-CONTROLS")
    strip_collections = _word(source, "_RTHP-W-STRIP-COLLECTIONS?")
    claims = _word(source, "_RTHP-BUILD-CLAIMS?")
    wrap_control = _word(source, "_RTHP-W-WRAP-CONTROL-PLAN?")
    document_at = _word(source, "_RTHP-DOCUMENT-AT")
    target_build = _word(source, "_RTHP-TARGET-CANDIDATE?")

    assert (
        "max-documents max-records max-source-text max-collection-native "
        "max-data-graphics-native max-cols max-rows"
    ) in storage
    assert "_RTHP-B-DOCUMENTS" in storage
    assert "_RTHP-B-DOCUMENTS @ RUHA-DOCUMENT-SIZE" in sizing
    assert "_RTHP-B-COLLECTION-NATIVE" in storage
    assert "_RTHP-B-COLLECTION-NATIVE @ USCOL-ENTRY-HEADER-SIZE /" in sizing
    assert (
        "_RTHP-B-COLLECTION-NATIVE @ RTHP-COLLECTION-CONTROL-CAPACITY"
        in sizing
    )
    assert "USCOL-TABSET-FIXED-SIZE" in collection_capacity
    assert "1 0 USCOL-TAB-BYTES" in collection_capacity
    assert "1 _RTHP-U32+?" in collection_capacity
    assert "_RTHP-POS-U32?" in collection_capacity
    assert "_RTHP-B-RECORDS @ _RTHP-B-COLLECTIONS @ _RTHP-U32+?" in sizing
    assert "_RTHP-B-TEXT @ _RTHP-B-COLLECTION-NATIVE @ _RTHP-U32+?" in sizing
    assert "_RTHP-B-CONTROLS @ _RTHP-B-CONTROLS @" in sizing
    assert target_bank_sizing.count("_RTHP.MAX-CONTROLS @") == 2
    assert "_RTHP.MAX-RECORDS @" not in target_bank_sizing
    assert "_RTHP.MAX-DOCUMENTS @ RUHA-DOCUMENT-SIZE" in layout
    assert "_RTHP.SOURCE-DIR-A" in layout
    assert "_RTHP.MAX-COLLECTION-DESCRIPTORS @ UCSN-DESCRIPTOR-SIZE" in layout
    assert "_RTHP.COLLECTION-DESCRIPTORS-A" in layout
    assert "_RTHP.MAX-COLLECTION-NATIVE" in layout
    assert "_RTHP.COLLECTION-NATIVE-A" in layout
    assert "_RTHP.MAX-CONTROLS @ RTE-CONTROL-SIZE" in layout
    assert "_RTHP.MAX-CONTROLS @ RUCP-CORRELATION-SIZE" in layout
    assert "RUHA-DOCUMENT-CAPACITY@" in init
    assert "_RTHP.MAX-DOCUMENTS !" in init
    assert source.index(document_at) < source.index(target_build)

    for aggregate in (
        "RUHA-SNAPSHOT-DOCUMENT-COUNT@",
        "RUHA-SNAPSHOT-DIRECTORY@",
        "RUHA-SNAPSHOT-RECORDS@",
        "RUHA-SNAPSHOT-TEXT@",
        "RUHA-SNAPSHOT-COLLECTION-COUNT@",
        "RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@",
        "RUHA-SNAPSHOT-COLLECTION-NATIVE@",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-DESCRIPTORS@",
        "RUHA-SNAPSHOT-DATA-GRAPHICS-NATIVE@",
    ):
        assert aggregate in snapshot_shape
    for field in (
        "RUHA-DOCUMENT-TOKEN@",
        "RUHA-DOCUMENT-SLOT-ID@",
        "RUHA-DOCUMENT-ROW@",
        "RUHA-DOCUMENT-COL@",
        "RUHA-DOCUMENT-HEIGHT@",
        "RUHA-DOCUMENT-WIDTH@",
        "RUHA-DOCUMENT-RECORD-OFFSET@",
        "RUHA-DOCUMENT-RECORD-BYTES@",
        "RUHA-DOCUMENT-TEXT-OFFSET@",
        "RUHA-DOCUMENT-TEXT-BYTES@",
        "RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-OFFSET@",
        "RUHA-DOCUMENT-COLLECTION-DESCRIPTOR-BYTES@",
        "RUHA-DOCUMENT-COLLECTION-NATIVE-OFFSET@",
        "RUHA-DOCUMENT-COLLECTION-NATIVE-BYTES@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-OFFSET@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-DESCRIPTOR-BYTES@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-OFFSET@",
        "RUHA-DOCUMENT-DATA-GRAPHICS-NATIVE-BYTES@",
        "RUHA-DOCUMENT-MENU-EPOCH@",
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@",
    ):
        assert field in source
    compact_document_shape = " ".join(document_shape.split())
    assert (
        "_RTHP-W-DOC-RECORD-U @ 0= _RTHP-W-DOCUMENT @ "
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ 0= <> IF 0 EXIT THEN"
        in compact_document_shape
    )
    assert (
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ "
        "_RTHP-W-SOURCE-GEN @ U> IF 0 EXIT THEN"
        in compact_document_shape
    )
    assert (
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ _RTHP-W-DOCUMENT @ "
        "RUHA-DOCUMENT-MENU-EPOCH@ U> IF 0 EXIT THEN"
        in compact_document_shape
    )
    assert snapshot_shape.count("_RTHP-W-DOCUMENT-SHAPE?") == 1
    assert "_RTHP.SOURCE-DIR-A" in copy
    assert "_RTHP.SOURCE-DIR-USED" in copy
    assert "_RTHP.SOURCE-DRAW !" in copy
    assert "_RTHP.DOCUMENT-COUNT !" in copy
    assert "_RTHP.COLLECTION-DESCRIPTORS-USED !" in copy
    assert "_RTHP.COLLECTION-NATIVE-USED !" in copy
    assert "_RTHP.SOURCE-COLLECTION-COUNT !" in copy
    assert "_RTHP.DGRAPH-DESCRIPTORS-USED !" in copy
    assert "_RTHP.DGRAPH-NATIVE-USED !" in copy
    assert "_RTHP.SOURCE-DGRAPH-COUNT !" in copy

    # Each aggregate is an exact concatenation of document partitions.  The
    # already-carried native length is consumed by IF; rereading it there
    # would leak one stack cell per aggregate before the final flag.
    for cursor, total in (
        ("_RTHP-W-DGRAPH-DESCRIPTOR-CURSOR", "_RTHP-W-DGRAPH-DESCRIPTORS-U"),
        ("_RTHP-W-DGRAPH-NATIVE-CURSOR", "_RTHP-W-DGRAPH-NATIVE-U"),
    ):
        assert f"{cursor} @ <> IF 0 EXIT THEN" in document_shape
        assert f"{cursor} @\n        {total} @ = AND" in snapshot_shape
        assert f"{cursor} @\n        _RTHP-W-P @" in copied_complete
    assert "_RTHP-W-NATIVE-U @ IF" not in snapshot_shape
    assert "_RTHP-W-DGRAPH-NATIVE-U @ IF" not in snapshot_shape

    for build, planner in ((controls, "RUCP-BUILD"), (claims, "RUCL-BUILD")):
        assert "_RTHP-W-COPIED-DOCUMENT?" in build
        assert "_RTHP-W-DOC-RECORD-O" in build
        assert "_RTHP-W-DOC-RECORD-COUNT" in build
        assert build.count(planner) == 1
        assert "BEGIN _RTHP-W-DOCUMENT-I @" in build
        assert "_RTHP-W-COPIED-COMPLETE?" in build
    assert "_RTHP-W-DOC-TEXT-O" in controls
    assert "_RTHP-W-NEXT-ID" in controls
    assert "_RTHP-W-WRAP-CONTROL-PLAN?" in control_pipeline
    assert control_pipeline.count("_RTHP-W-WRAP-CONTROL-PLAN?") == 1
    assert "RTE-CONTROL-PREFLIGHT" not in control_pipeline
    assert "_RTHP-W-PREFLIGHT-CONTROLS" not in source
    strip_order = (
        "_RTHP.CONTROL-COUNT !",
        "_RTHP.SOURCE-TEXT-USED !",
        "_RTHP.COLLECTION-COUNT !",
        "_RTHP.COLLECTION-ITEMS !",
        "_RTHP.COLLECTION-UTF8 !",
        "_RTHP-W-GLYPH-FIRST !",
        "_RTHP-W-WRAP-CONTROL-PLAN?",
    )
    assert [strip_collections.index(item) for item in strip_order] == sorted(
        strip_collections.index(item) for item in strip_order
    )
    assert strip_collections.count("_RTHP-W-WRAP-CONTROL-PLAN?") == 1
    assert "RUCP-BUILD" not in wrap_control
    assert "_RTHP.CONTROLS-A" in wrap_control

    # Independent byte-density locks: an aligned bank below the root size is
    # unusable, and every additional minimum one-byte TAB costs 48 bytes.
    assert _max_collection_controls_oracle(72) == 0
    assert _max_collection_controls_oracle(0x100000000) == 0
    assert _max_collection_controls_oracle(80) == 1
    assert _max_collection_controls_oracle(120) == 1
    assert _max_collection_controls_oracle(128) == 2
    assert _max_collection_controls_oracle(176) == 3


def test_canonical_collections_lower_through_the_generic_producer() -> None:
    source = _source()
    spans = _word(source, "_RTHP-W-SNAPSHOT-SPANS?")
    copy = _word(source, "_RTHP-COPY-SNAPSHOT?")
    family_to_kind = _word(source, "_RTHP-USCOL-FAMILY>CONTROL-KIND")
    family_fixed = _word(source, "_RTHP-USCOL-FAMILY-FIXED-SIZE")
    text_kind = _word(source, "_RTHP-TEXT-COLLECTION-CONTROL-KIND?")
    collection_kind = _word(source, "_RTHP-COLLECTION-CONTROL-KIND?")
    root_kind = _word(source, "_RTHP-COLLECTION-ROOT-KIND?")
    geometry = _word(source, "_RTHP-W-COLLECTION-GEOMETRY?")
    entry = _word(source, "_RTHP-W-COLLECTION-ENTRY?")
    overlap = _word(source, "_RTHP-W-COLLECTION-NONOVERLAPPING?")
    content = _word(source, "_RTHP-W-COLLECTION-CONTENT")
    write_text = _word(source, "_RTHP-W-WRITE-TEXT-COLLECTION")
    copy_tab_text = _word(source, "_RTHP-W-COPY-TAB-TEXT")
    tab_correlation = _word(source, "_RTHP-W-TAB-CORRELATION!")
    tab_common = _word(source, "_RTHP-W-TAB-COMMON!")
    write_tab_root = _word(source, "_RTHP-W-WRITE-TABSET-ROOT")
    write_tab = _word(source, "_RTHP-W-WRITE-TAB")
    write_tabset = _word(source, "_RTHP-W-WRITE-TABSET")
    write = _word(source, "_RTHP-W-WRITE-COLLECTION")
    lower = _word(source, "_RTHP-W-LOWER-COLLECTIONS")
    build_controls = _word(source, "_RTHP-BUILD-CONTROLS")
    append_claim = _word(source, "_RTHP-W-APPEND-COLLECTION-CLAIM?")
    build_claims = _word(source, "_RTHP-BUILD-CLAIMS?")
    build_candidate = _word(source, "_RTHP-BUILD-CANDIDATE")
    fixed = _word(source, "_RTHP-FIXED-BODY?")
    emit = _word(source, "_RTHP-EMIT-CONTROLS")
    delta_bind = _word(source, "_RTHP-D-BIND?")
    delta_pair = _word(source, "_RTHP-D-CONTROL-PAIR")
    delta_match = _word(source, "_RTHP-D-ACTIVE-CORRELATION?")
    delta_coverage = _word(source, "_RTHP-D-CORRELATIONS-COVERED?")
    delta_control = _word(source, "_RTHP-D-CONTROL-COMPATIBLE?")
    target = _word(source, "_RTHP-TARGET-CANDIDATE?")

    # The producer consumes only the canonical frozen collection aggregate.
    # Neither text nor tab lowering reaches back into an applet or widget.
    assert "REQUIRE uidl-semantic-content-stx1.f" in source
    for accessor in (
        "RUHA-SNAPSHOT-COLLECTION-COUNT@",
        "RUHA-SNAPSHOT-COLLECTION-DESCRIPTORS@",
        "RUHA-SNAPSHOT-COLLECTION-NATIVE@",
    ):
        assert accessor in spans
    for copied_bank in (
        "_RTHP.COLLECTION-DESCRIPTORS-A",
        "_RTHP.COLLECTION-DESCRIPTORS-USED",
        "_RTHP.COLLECTION-NATIVE-A",
        "_RTHP.COLLECTION-NATIVE-USED",
        "_RTHP.SOURCE-COLLECTION-COUNT",
    ):
        assert copied_bank in copy

    for family, kind in (
        ("TEXT-AREA", "TEXT-AREA"),
        ("TEXT-GRID", "TEXT-GRID"),
        ("TABSET", "TABSET"),
    ):
        assert re.search(
            rf"USCOL-F-{family}\s*=\s*IF.*?RTE-CONTROL-{kind}",
            family_to_kind,
            re.S,
        )
    assert family_to_kind.count("USCOL-F-") == 3
    assert family_to_kind.count("RTE-CONTROL-") == 3
    assert "ELSE 0 THEN" in family_to_kind
    assert text_kind.count("RTE-CONTROL-TEXT-") == 2
    assert "_RTHP-TEXT-COLLECTION-CONTROL-KIND?" in collection_kind
    assert "RTE-CONTROL-TABSET" in collection_kind
    assert "RTE-CONTROL-TAB" in collection_kind
    assert "_RTHP-TEXT-COLLECTION-CONTROL-KIND?" in root_kind
    assert "RTE-CONTROL-TABSET" in root_kind
    assert "RTE-CONTROL-TAB =" not in root_kind
    assert "USCOL-TEXT-FIXED-SIZE" in family_fixed
    assert "USCOL-TABSET-FIXED-SIZE" in family_fixed

    # Every selected descriptor is an exact mounted-root clip tied back to
    # the exact native entry and summary before either lowering path runs.
    assert "UCSN-DESCRIPTOR-FAMILY@" in lower
    assert "_RTHP-USCOL-FAMILY>CONTROL-KIND" in lower
    assert "USCOL-F-" not in lower
    assert "_RTHP-USCOL-FAMILY>CONTROL-KIND" in write
    assert "USCOL-F-TABSET" in write
    for exact_clip in (
        "UCSN-DESCRIPTOR-CLIP-ROW@",
        "UCSN-DESCRIPTOR-CLIP-COLUMN@",
        "UCSN-DESCRIPTOR-CLIP-HEIGHT@",
        "UCSN-DESCRIPTOR-CLIP-WIDTH@",
    ):
        assert exact_clip in geometry
    for identity in (
        "UCSN-SOURCE-UIDL",
        "UCSN-DESCRIPTOR-SOURCE-INDEX@",
        "UCSN-DESCRIPTOR-SOURCE-GENERATION@",
        "UCSN-DESCRIPTOR-ROOT-KEY@",
        "_RTHP-USCOL-FAMILY-FIXED-SIZE",
        "USCOL-ROOT-HEIGHT@",
        "USCOL-ROOT-WIDTH@",
        "USCOL-SUMMARY-FAMILY@",
        "USCOL-SUMMARY-ENTRY-BYTES@",
    ):
        assert identity in entry

    # STX1 remains exclusive to the two text roots.
    for semantic_pack in (
        "USCOL-SUMMARY-STX1-BYTES",
        "USSTX-PACK",
        "_RTHP.SOURCE-CONTENT-EPOCH",
        "_RTHP.SOURCE-TEXT-A",
        "_RTHP.SOURCE-TEXT-U",
    ):
        assert semantic_pack in content
    assert content.index("USCOL-SUMMARY-STX1-BYTES") < content.index(
        "USSTX-PACK"
    )
    assert "_RTHP-W-COLLECTION-CONTENT" in write_text
    tab_slice = "\n".join(
        (copy_tab_text, tab_common, write_tab_root, write_tab, write_tabset)
    )
    assert "USSTX-PACK" not in tab_slice
    assert "_RTHP-W-COLLECTION-CONTENT" not in tab_slice
    assert source.count("USSTX-PACK") == 1

    for field in (
        "_RTE-CONTROL.CONTENT-A !",
        "_RTE-CONTROL.CONTENT-U !",
        "_RTE-CONTROL.CONTENT-ITEMS !",
        "_RTE-CONTROL.CONTENT-UTF8 !",
        "_RUCP-X.LIFECYCLE-GENERATION !",
    ):
        assert field in write_text
    assert write_text.index("_RTHP-USCOL-FAMILY>CONTROL-KIND") < (
        write_text.index("_RTHP-W-COLLECTION-NONOVERLAPPING?")
    ) < write_text.index("_RTHP-W-COLLECTION-OUTPUT?") < write_text.index(
        "_RTHP-W-COLLECTION-CONTENT"
    )
    assert "RUCP-CORRELATION-LIFECYCLE-GENERATION@" in overlap
    assert "_RTHP-COLLECTION-ROOT-KIND?" in overlap

    # TABSET is one geometric root followed by every native TAB descendant in
    # strict native order. Descendants inherit root bounds but have zero local
    # geometry/z from the freshly cleared record.
    for root_field in (
        "RTE-CONTROL-TABSET",
        "USCOL-ROOT-STATE@",
        "UCSN-DESCRIPTOR-Z@",
        "_RTE-CONTROL.ROW !",
        "_RTE-CONTROL.COL !",
        "_RTE-CONTROL.HEIGHT !",
        "_RTE-CONTROL.WIDTH !",
        "UCSN-DESCRIPTOR-ROOT-KEY@",
    ):
        assert root_field in write_tab_root
    for child_field in (
        "RTE-CONTROL-TAB",
        "USCOL-TAB-STATE@",
        "_RTE-CONTROL.PARENT !",
        "USCOL-TAB-ORDER@",
        "_RTE-CONTROL.LABEL-A !",
        "_RTE-CONTROL.LABEL-U !",
        "_RTE-CONTROL.SHORTCUT-A !",
        "_RTE-CONTROL.SHORTCUT-U !",
        "USCOL-TAB-KEY@",
    ):
        assert child_field in write_tab
    for zero_descendant_field in (
        "_RTE-CONTROL.Z !",
        "_RTE-CONTROL.ROW !",
        "_RTE-CONTROL.COL !",
        "_RTE-CONTROL.HEIGHT !",
        "_RTE-CONTROL.WIDTH !",
        "_RTE-CONTROL.CONTENT-A !",
        "_RTE-CONTROL.CONTENT-U !",
    ):
        assert zero_descendant_field not in write_tab
    assert "RTE-CONTROL-SIZE 0 FILL" in _word(
        source, "_RTHP-W-COLLECTION-OUTPUT?"
    )
    assert tab_common.count("_RTE-CONTROL.ROOT-") == 2
    assert "_RTHP-W-TAB-ROOT-ID" in write_tab_root
    assert "_RTHP-W-TAB-ROOT-ID" in write_tab
    assert "USCOL-TABSET-FIRST" in write_tabset
    assert "USCOL-TABSET-COUNT@" in write_tabset
    assert write_tabset.index("_RTHP-W-WRITE-TAB DUP") < write_tabset.index(
        "USCOL-TAB-NEXT"
    )
    assert (
        "_RTHP-W-TAB-END @ U> IF DROP RTE-S-INVALID EXIT THEN\n"
        "        DROP\n"
        "        _RTHP-W-WRITE-TAB"
    ) in write_tabset
    assert "USCOL-SUMMARY-CHILD-COUNT@" in write_tabset
    assert "USCOL-SUMMARY-UTF8-BYTES@" in write_tabset

    # Labels and optional shortcuts are copied into caller-owned SOURCE-TEXT;
    # correlations use the root key for the root and each native TAB key for
    # its descendant.
    for copied in (
        "_RTHP.SOURCE-TEXT-A",
        "_RTHP.SOURCE-TEXT-U",
        "_RTHP-W-CONTENT-CURSOR",
        "MSPAN-NONWRAPPING?",
        "MOVE",
    ):
        assert copied in copy_tab_text
    assert "THEN _RTHP-W-COPY-END !" in copy_tab_text
    assert "_RTHP-W-COPY-END @ _RTHP-W-CONTENT-CURSOR !" in copy_tab_text
    assert "DUP _RTHP-W-COPY-DST !" not in copy_tab_text
    assert write_tab.count("_RTHP-W-COPY-TAB-TEXT") == 2
    for correlation_field in (
        "_RUCP-X.ATTACHMENT !",
        "_RUCP-X.SOURCE !",
        "_RUCP-X.INDEX !",
        "_RUCP-X.SUBKEY !",
        "_RUCP-X.CONTROL-ID !",
        "_RUCP-X.LIFECYCLE-GENERATION !",
    ):
        assert correlation_field in tab_correlation
    assert "UCSN-DESCRIPTOR-ROOT-KEY@" in write_tab_root
    assert "USCOL-TAB-KEY@" in write_tab

    # Local capacity or unavailable representation strips the entire
    # collection layer before claims.  Provider admission is deliberately
    # deferred to the one combined preflight after residual construction.
    assert build_controls.index("_RTHP-W-LOWER-COLLECTIONS") < (
        build_controls.index("_RTHP-W-WRAP-CONTROL-PLAN?")
    )
    assert "RTE-S-CAPACITY =" in build_controls
    assert "RTE-S-UNAVAILABLE =" in build_controls
    assert "_RTHP-W-STRIP-COLLECTIONS?" in build_controls
    assert "RTE-CONTROL-PREFLIGHT" not in build_controls
    assert build_candidate.index("_RTHP-BUILD-CONTROLS") < (
        build_candidate.index("_RTHP-BUILD-CLAIMS?")
    )
    assert "_RTHP-W-REBUILD-MENU-ONLY" in build_candidate
    assert "_RTHP.COLLECTION-COUNT @ 0<>" in build_candidate

    # Only text roots and TABSET roots claim their exact descriptor rectangle;
    # a TAB descendant succeeds without appending a claim.
    for claim_identity in (
        "RUCP-CORRELATION-ATTACHMENT@",
        "RUCP-CORRELATION-SOURCE@",
        "RUCP-CORRELATION-INDEX@",
        "RUCP-CORRELATION-SUBKEY@",
        "RUCP-CORRELATION-LIFECYCLE-GENERATION@",
        "RUCL-ADMITTED-RECTANGLE!",
    ):
        assert claim_identity in append_claim
    assert "_RTHP-COLLECTION-CONTROL-KIND?" in append_claim
    assert "RTE-CONTROL-TAB = IF DROP -1 EXIT THEN" in append_claim
    assert "_RUCL-C." not in append_claim
    assert build_claims.index("RUCL-BUILD") < build_claims.index(
        "_RTHP-W-APPEND-COLLECTION-CLAIMS?"
    )

    # Collection-count is the exact root+descendant CONTROL aggregate, while
    # SOURCE-COLLECTION-COUNT remains the separate copied root count.
    for aggregate in (
        "_RTE-HA.CONTROL-COLLECTIONS",
        "_RTE-HA.CONTROL-ITEMS",
        "_RTE-HA.CONTROL-UTF8",
    ):
        assert aggregate in fixed
        assert aggregate in emit
    assert "_RTHP-W-COMMIT-COLLECTION-CONTROL" in write_tab_root
    assert "_RTHP-W-COMMIT-COLLECTION-CONTROL" in write_tab
    assert "_RTHP-COLLECTION-CONTROL-KIND?" in emit
    for retained in (
        "_RTHP-TB.MENU-CONTROL-COUNT",
        "_RTHP-TB.COLLECTION-COUNT",
        "_RTHP-TB.COLLECTION-ITEMS",
        "_RTHP-TB.COLLECTION-UTF8",
        "_RTHP-TB.MENU-TEXT-USED",
    ):
        assert retained in delta_bind
        assert retained in target
    assert "_RTHP-D-ACTIVE-CORRELATION?" in delta_pair
    assert "RUCP-CORRELATION-LIFECYCLE-GENERATION@" in (
        delta_match + delta_coverage
    )
    assert "_RTE-CONTROL.CONTENT-ITEMS" in delta_control
    assert "_RTE-CONTROL.CONTENT-UTF8" in delta_control
    assert "_RTHP-TEXT-COLLECTION-CONTROL-KIND?" in delta_control
    assert "_RTHP-D-CONTROL-TEXT-SPANS?" in delta_control
    assert "_RTHP-D-CONTROL-CONTENT-NEWER?" in delta_control
    assert "_RTHP-D-CONTROL-LABEL-EQUAL?" in delta_control
    assert "_RTHP-D-CONTROL-SHORTCUT-EQUAL?" in delta_control
    assert "_RTHP-D-CONTROL-CONTENT-EQUAL?" in delta_control
    assert "_RTHP-D-BYTE-LE64@" in source
    assert "_RTHP-TB.CONTENT-EPOCH" in _word(
        source, "_RTHP-D-STX1-REVISION?"
    )
    assert (
        "_RTHP-D-ACTIVE @ _RTHP-TB.COLLECTION-ITEMS @\n"
        "        _RTHP-D-PENDING @ _RTHP-TB.COLLECTION-ITEMS @ <>"
        not in delta_bind
    )
    assert (
        "_RTHP-D-ACTIVE @ _RTHP-TB.COLLECTION-UTF8 @\n"
        "        _RTHP-D-PENDING @ _RTHP-TB.COLLECTION-UTF8 @ <>"
        not in delta_bind
    )
    assert (
        "_RTHP-D-PENDING @ _RTHP-TB.COLLECTION-ITEMS @\n"
        "        _RTHP-D-P @ _RTHP.COLLECTION-ITEMS @ <>"
        in delta_bind
    )
    assert (
        "_RTHP-D-PENDING @ _RTHP-TB.COLLECTION-UTF8 @\n"
        "        _RTHP-D-P @ _RTHP.COLLECTION-UTF8 @ <>"
        in delta_bind
    )
    revision = _word(source, "_RTHP-D-STX1-REVISION?")
    for proof in (
        "USSTX-CONTENT-HEADER-SIZE U<",
        "_RTHP-TEXT-WITHIN?",
        "_RTHP-D-BYTE-LE32@ USSTX-TAG <>",
        "_RTHP-D-BYTE-LE16@ USSTX-VERSION <>",
        "6 + _RTHP-D-BYTE-LE16@ IF",
        "8 + _RTHP-D-BYTE-LE64@ DUP 0=",
        "_RTHP-TB.CONTENT-EPOCH",
    ):
        assert proof in revision
    assert "_RTHP-D-REV-A @ 8 + @" not in revision
    assert "C@" in _word(source, "_RTHP-D-BYTE-LE16@")
    assert "_RTHP-D-BYTE-LE16@" in _word(
        source, "_RTHP-D-BYTE-LE32@"
    )
    assert "_RTHP-D-BYTE-LE32@" in _word(
        source, "_RTHP-D-BYTE-LE64@"
    )
    assert "_RTHP-TG-COLLECTION-TARGETS?" in target

    generic_slice = "\n".join(
        (
            family_to_kind,
            collection_kind,
            geometry,
            entry,
            overlap,
            content,
            write_text,
            tab_slice,
            write,
            lower,
            append_claim,
            emit,
        )
    )
    assert not re.search(
        r"\b(?:PAD|DAYBOOK|DESK|SOUND[ -]?LAB)\b", generic_slice, re.I
    )


def test_data_graphics_lower_through_one_generic_instrument_family() -> None:
    source = _source()
    sizing = _word(source, "_RTHP-BYTES-BODY")
    storage = _word(source, "RTHP-STORAGE-BYTES")
    layout = _word(source, "_RTHP-LAYOUT")
    init = _word(source, "RTHP-INIT")
    valid = _word(source, "_RTHP-VALID-BODY?")
    request = _word(source, "_RTHP-W-RUIP-REQUEST?")
    firsts = _word(source, "_RTHP-W-INSTRUMENT-FIRSTS?")
    outputs = _word(source, "_RTHP-W-INSTRUMENT-OUTPUTS?")
    accumulate = _word(source, "_RTHP-W-RUIP-ACCUMULATE?")
    wrap_instruments = _word(source, "_RTHP-W-WRAP-INSTRUMENT-PLAN?")
    build_instruments = _word(source, "_RTHP-BUILD-INSTRUMENTS")
    strip_instruments = _word(source, "_RTHP-W-STRIP-INSTRUMENTS?")
    wrap_hybrid = _word(source, "_RTHP-WRAP-HYBRID")
    menu_retry = _word(source, "_RTHP-W-REBUILD-MENU-ONLY")
    instrument_retry = _word(
        source, "_RTHP-W-REBUILD-WITHOUT-INSTRUMENTS"
    )
    candidate = _word(source, "_RTHP-BUILD-CANDIDATE")
    next_ids = _word(source, "_RTHP-CANDIDATE-NEXT?")
    last_object = _word(source, "_RTHP-CANDIDATE-LAST-OBJECT")
    fixed_body = _word(source, "_RTHP-FIXED-BODY?")
    fixed_instruments = _word(source, "_RTHP-INSTRUMENT-FIXED?")
    fixed_aggregates = _word(source, "_RTHP-X-INSTRUMENT-AGGREGATES?")
    target = _word(source, "_RTHP-TARGET-CANDIDATE?")
    target_header = _word(source, "_RTHP-TARGET-BANK-HEADER?")
    target_publish = _word(source, "_RTHP-TARGET-PUBLISH?")
    pack_copy = _word(source, "_RTHP-PK-COPY?")
    delta_bind = _word(source, "_RTHP-D-BIND?")
    delta_candidate = _word(source, "_RTHP-DELTA-CANDIDATE?")
    unchanged = _word(source, "_RTHP-U-ACTIVE?")
    prepare_start = _word(source, "_RTHP-PREPARE-START")
    emit_regions = _word(source, "_RTHP-EMIT-INSTRUMENT-REGIONS")
    emit_instruments = _word(source, "_RTHP-EMIT-INSTRUMENTS")

    assert "REQUIRE uidl-instrument-planner.f" in source
    public_args = (
        "max-documents max-records max-source-text "
        "max-collection-native max-data-graphics-native max-cols max-rows"
    )
    assert public_args in storage
    assert public_args in init
    assert storage.index("_RTHP-B-DGRAPH-NATIVE !") < storage.index(
        "_RTHP-B-COLLECTION-NATIVE !"
    )
    assert init.index("_RTHP-I-DGRAPH-NATIVE !") < init.index(
        "_RTHP-I-COLLECTION-NATIVE !"
    )

    # Capacities come only from negotiated record/native bounds and ABI record
    # sizes.  Region capacity is the minimum of descriptor and object ceilings.
    for body in (sizing, init, valid):
        assert "UDG-HEADER-SIZE /" in body
        assert "UDG-STATUS-RECORD-SIZE /" in body
        assert "_RTHP-UMIN" in body
    for field in (
        "MAX-DGRAPH-DESCRIPTORS",
        "MAX-INSTRUMENT-REGIONS",
        "MAX-INSTRUMENTS",
    ):
        assert field in init
        assert field in valid
    for sizing_value in (
        "_RTHP-B-DGRAPH-DESCRIPTORS",
        "_RTHP-B-INSTRUMENT-REGIONS",
        "_RTHP-B-INSTRUMENTS",
    ):
        assert sizing_value in sizing
    assert (
        "_RTHP-B-DGRAPH-DESCRIPTORS @ _RTHP-UMIN\n"
        "        _RTHP-B-INSTRUMENT-REGIONS !" in sizing
    )
    assert (
        "_RTHP-I-P @ _RTHP.MAX-DGRAPH-DESCRIPTORS @ _RTHP-UMIN\n"
        "        _RTHP-I-P @ _RTHP.MAX-INSTRUMENT-REGIONS !" in init
    )
    assert "_RTHP-B-CONTROLS @ _RTHP-B-INSTRUMENTS @ _RTHP-U32+?" in sizing
    assert "_RTHP-B-CLAIMS @ 2 _RTHP-U32*?" in sizing

    for bank in (
        "_RTHP.DGRAPH-DESCRIPTORS-A",
        "_RTHP.DGRAPH-NATIVE-A",
        "_RTHP.INSTRUMENT-REGIONS-A",
        "_RTHP.INSTRUMENTS-A",
        "_RTHP.INSTRUMENT-UNITS-A",
        "_RTHP.INSTRUMENT-CORR-A",
    ):
        assert bank in layout
    assert (
        "_RTHP.MAX-CONTROLS @ OVER _RTHP.MAX-INSTRUMENTS @ +\n"
        "        RUCL-CLAIM-SIZE *" in layout
    )
    assert (
        "_RTHP.MAX-CONTROLS @ OVER _RTHP.MAX-INSTRUMENTS @ +\n"
        "        2 * RGRP-EVENT-SIZE *" in layout
    )

    # Each copied document is lowered once with its own attachment and exact
    # descriptor/native slices.  Output banks are suffixes of aggregate
    # prefixes, so IDs, dense units, correlations, and claims stay contiguous.
    assert build_instruments.count("RUIP-BUILD") == 1
    assert "BEGIN _RTHP-W-DOCUMENT-I @" in build_instruments
    assert "_RTHP-W-COPIED-DOCUMENT?" in build_instruments
    assert "_RTHP-W-DOC-DGRAPH-DESCRIPTOR-U @ IF" in build_instruments
    assert "_RTHP-W-COPIED-COMPLETE?" in build_instruments
    assert "RUHA-DOCUMENT-TOKEN@" in request
    for exact_slice in (
        "_RTHP.DGRAPH-DESCRIPTORS-A @",
        "_RTHP-W-DOC-DGRAPH-DESCRIPTOR-O @ +",
        "_RTHP-W-DOC-DGRAPH-DESCRIPTOR-U @",
        "_RTHP.DGRAPH-NATIVE-A @",
        "_RTHP-W-DOC-DGRAPH-NATIVE-O @ +",
        "_RTHP-W-DOC-DGRAPH-NATIVE-U @",
    ):
        assert exact_slice in request
    for request_part in (
        "RUIP-REQUEST-IDENTITY!",
        "RUIP-REQUEST-SURFACE!",
        "RUIP-REQUEST-SOURCE!",
        "RUIP-REQUEST-PLAN!",
        "RUIP-REQUEST-AUXILIARY!",
    ):
        assert request_part in request
    assert outputs.count("_RTHP-W-SUFFIX?") == 4
    assert "_RTHP-W-CLAIM-OUTPUT?" in outputs
    assert "_RTHP-W-INSTRUMENT-REGIONS @ _RTHP-U+?" in firsts
    assert "_RTHP-W-INSTRUMENTS @ _RTHP-U+?" in firsts
    for bounded_total in (
        "_RTHP.MAX-INSTRUMENT-REGIONS",
        "_RTHP.MAX-INSTRUMENTS",
        "_RTHP.INSTRUMENT-UNITS-U",
        "_RTHP.CLAIMS-U",
    ):
        assert bounded_total in accumulate

    # One global plan wraps the accumulated region/item banks.  A zero-item
    # family leaves both the embedded plan and hybrid instrument pointer zero.
    assert "RTE-INSTRUMENT-PLAN-SIZE 0 FILL" in wrap_instruments
    assert "_RTHP-W-INSTRUMENTS @ 0= IF" in wrap_instruments
    assert "_RTE-IP.REGIONS-A !" in wrap_instruments
    assert "_RTE-IP.ITEMS-A !" in wrap_instruments
    instrument_wrap_branch = wrap_hybrid[
        wrap_hybrid.index("_RTHP.INSTRUMENT-COUNT @ IF") :
        wrap_hybrid.index("_RTHP.GLYPH-COUNT @ IF")
    ]
    assert "_RTE-HP.INSTRUMENT-PLAN !" in instrument_wrap_branch
    assert "_RTE-HP.INSTRUMENT-BYTES-A !" in instrument_wrap_branch
    assert "_RTE-HP.INSTRUMENT-BYTES-U !" in instrument_wrap_branch
    assert "RTE-INSTRUMENT-PLAN-SIZE 0 FILL" in strip_instruments

    # Stable retained IDs are controls, instruments, then residual glyphs;
    # base region is reserved first and instrument regions follow it.
    initial_order = (
        "_RTHP-BUILD-CONTROLS",
        "_RTHP-BUILD-CLAIMS?",
        "_RTHP-BUILD-INSTRUMENTS",
        "_RTHP-BUILD-GLYPHS?",
    )
    assert [candidate.index(word) for word in initial_order] == sorted(
        candidate.index(word) for word in initial_order
    )
    assert (
        "_RTHP.FIRST-OBJECT @\n"
        "    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?" in firsts
    )
    assert (
        "_RTHP.FIRST-OBJECT @\n"
        "    _RTHP-W-P @ _RTHP.CONTROL-COUNT @ _RTHP-U+?"
        in build_instruments
    )
    assert "_RTE-HA.GLYPH-COUNT @ IF" in last_object
    assert "_RTE-HA.INSTRUMENT-COUNT @ IF" in last_object
    assert "_RTHP.INSTRUMENT-REGION-COUNT @ _RTHP-U+?" in next_ids

    # Opaque CAPACITY/UNAVAILABLE explores both one-family candidates before
    # the final menu+residual candidate: collections-only, instruments-only,
    # then neither.  Every branch rebuilds claims and residual glyphs.
    first_without = candidate.index("_RTHP-W-REBUILD-WITHOUT-INSTRUMENTS")
    without_collections = candidate.index("_RTHP-W-REBUILD-MENU-ONLY")
    final_without = candidate.rindex("_RTHP-W-REBUILD-WITHOUT-INSTRUMENTS")
    assert first_without < without_collections < final_without
    assert candidate.count(
        "DUP RTE-S-CAPACITY = OVER RTE-S-UNAVAILABLE = OR"
    ) == 3
    assert "_RTHP-W-STRIP-COLLECTIONS?" in menu_retry
    assert "RTE-CONTROL-PREFLIGHT" not in menu_retry
    menu_retry_order = (
        "_RTHP-W-STRIP-COLLECTIONS?",
        "_RTHP-BUILD-CLAIMS?",
        "_RTHP-BUILD-INSTRUMENTS",
        "_RTHP-BUILD-GLYPHS?",
        "_RTHP-RESERVE-GLYPHS?",
        "_RTHP-WRAP-HYBRID",
        "_RTHP-W-PREFLIGHT-HYBRID",
    )
    assert [menu_retry.index(item) for item in menu_retry_order] == sorted(
        menu_retry.index(item) for item in menu_retry_order
    )
    assert menu_retry.count("_RTHP-W-PREFLIGHT-HYBRID") == 1
    assert "_RTHP-W-STRIP-INSTRUMENTS?" in instrument_retry
    instrument_retry_order = (
        "_RTHP-W-STRIP-INSTRUMENTS?",
        "_RTHP-BUILD-CLAIMS?",
        "_RTHP-BUILD-GLYPHS?",
        "_RTHP-RESERVE-GLYPHS?",
        "_RTHP-WRAP-HYBRID",
        "_RTHP-W-PREFLIGHT-HYBRID",
    )
    assert [
        instrument_retry.index(item) for item in instrument_retry_order
    ] == sorted(
        instrument_retry.index(item) for item in instrument_retry_order
    )
    assert instrument_retry.count("_RTHP-W-PREFLIGHT-HYBRID") == 1
    assert "_RTHP.BASE-CLAIMS-USED !" in instrument_retry
    assert "RTE-S-WOULD-BLOCK" not in menu_retry + instrument_retry
    assert "RTE-S-SESSION-LOST" not in menu_retry + instrument_retry

    # Fixed validation recomputes every engine admission aggregate before
    # BEGIN.  Invisible instruments still participate in sequential ID and
    # kind/unit/formatted totals; no post-emission check is the first proof.
    for aggregate in (
        "_RTE-HA.INSTRUMENT-UNIT-BYTES",
        "_RTE-HA.INSTRUMENT-UNIT-ALIGNED",
        "_RTE-HA.INSTRUMENT-UNIT-MAX",
        "_RTE-HA.INSTRUMENT-FORMATTED-BYTES",
        "_RTE-HA.INSTRUMENT-FORMATTED-MAX",
        "_RTE-HA.READOUT-COUNT",
        "_RTE-HA.METER-COUNT",
        "_RTE-HA.STATUS-COUNT",
        "_RTE-HA.INSTRUMENT-LAST",
    ):
        assert aggregate in fixed_aggregates
    for traversal in (
        "_RTHP-X-I-REGIONS?",
        "_RTHP-X-I-ITEMS?",
        "_RTHP-X-I-UNIT-AUTHORITY?",
        "_RTHP-X-I-KIND?",
    ):
        assert traversal in source
    assert "_RTHP-X-INSTRUMENT-AGGREGATES?" in fixed_instruments
    assert "_RTHP-INSTRUMENT-FIXED?" in fixed_body
    zero_family = fixed_instruments[
        fixed_instruments.index("_RTHP.INSTRUMENT-COUNT @ 0= IF") :
    ]
    zero_family = zero_family[: zero_family.index("THEN\n\n    _RTHP-X-P")]
    assert "_RTE-IP.OWNER @" in zero_family
    assert "_RTE-HP.INSTRUMENT-PLAN @" in zero_family
    assert "_RTE-HP.INSTRUMENT-BYTES-A @" in zero_family
    assert "_RTE-HP.INSTRUMENT-BYTES-U @" in zero_family

    # Target banks deliberately retain only instrument metadata.  Either an
    # active or pending instrument family disables DELTA and exact-reuse;
    # replacement START remains the sole mutation path for changed frames.
    for metadata in (
        "_RTHP-TB.INSTRUMENT-REGION-COUNT",
        "_RTHP-TB.INSTRUMENT-COUNT",
        "_RTHP-TB.INSTRUMENT-UNIT-BYTES",
    ):
        assert metadata in target
        assert metadata in target_header
        assert metadata in target_publish
    assert "_RTHP.INSTRUMENTS-A" not in pack_copy
    assert "_RTHP.INSTRUMENT-UNITS-A" not in pack_copy
    for delta_gate in (delta_bind, delta_candidate):
        assert delta_gate.count("_RTHP-TB.INSTRUMENT-COUNT") == 2
        assert "OR IF" in delta_gate
    assert "_RTHP-TB.INSTRUMENT-COUNT @ IF 0 EXIT THEN" in unchanged

    # START emits the optional base region only for controls/residual glyphs,
    # then instrument regions, controls, instruments, and residual glyphs.
    start_order = (
        "_RTHP-EMIT-INSTRUMENT-REGIONS",
        "_RTHP-EMIT-CONTROLS",
        "_RTHP-EMIT-INSTRUMENTS",
        "_RTHP-EMIT-GLYPHS",
    )
    assert [prepare_start.index(word) for word in start_order] == sorted(
        prepare_start.index(word) for word in start_order
    )
    base_condition = (
        "_RTHP.CONTROL-COUNT @\n"
        "    _RTHP-P-P @ _RTHP.GLYPH-COUNT @ OR IF"
    )
    assert prepare_start.index(base_condition) < prepare_start.index(
        "RTE-REGION-DEFINE"
    ) < prepare_start.index("_RTHP-EMIT-INSTRUMENT-REGIONS")
    assert emit_regions.index("DROP\n        _RTHP-E-P @") < (
        emit_regions.index("RTE-REGION-DEFINE")
    )
    assert "RTE-INSTRUMENT-DEFINE" in emit_instruments

    generic_slice = "\n".join(
        (
            request,
            build_instruments,
            wrap_instruments,
            instrument_retry,
            emit_regions,
            emit_instruments,
        )
    )
    assert not re.search(
        r"\b(?:PAD|DAYBOOK|DESK|SOUND[ -]?LAB)\b", generic_slice, re.I
    )


def test_each_rucp_document_uses_exact_sparse_work_and_output_spans() -> None:
    source = _source()
    work = _word(source, "_RTHP-W-RUCP-WORK-SPANS?")
    output = _word(source, "_RTHP-W-CONTROL-OUTPUT?")
    build = _word(source, "_RTHP-BUILD-MENU-CONTROLS?")

    # Work banks follow sparse UMSN source indices.  The last canonical
    # record supplies high-water; record count alone is not sufficient.
    assert "UMSN-RECORD-SOURCE-INDEX@" in work
    assert "1 _RTHP-U32+?" in work
    assert "_RTHP.MAX-RECORDS @ U>" in work
    assert "RUCP-LOOKUP-ENTRY-SIZE _RTHP-U32*?" in work
    assert "_RTHP-W-RUCP-HIGH-WATER @ 8 _RTHP-U32*?" in work
    assert "_RTHP.LOOKUP-U @ U>" in work
    assert "_RTHP.ORDER-U @ U>" in work
    assert "_RTHP.ORDER2-U @ U>" in work
    for return_stack_word in (">R", "R@", "R>"):
        assert return_stack_word not in work

    assert build.index("_RTHP-W-RUCP-WORK-SPANS?") < build.index(
        "RUCP-REQUEST-CLEAR"
    )
    for exact in (
        "_RTHP.LOOKUP-A @ _RTHP-W-RUCP-LOOKUP-U @",
        "_RTHP.ORDER-A @ _RTHP-W-RUCP-ORDER-U @",
        "_RTHP.ORDER2-A @ _RTHP-W-RUCP-ORDER-U @",
    ):
        assert exact in build
    for broad in (
        "_RTHP.LOOKUP-A @ _RTHP-W-P @ _RTHP.LOOKUP-U @",
        "_RTHP.ORDER-A @ _RTHP-W-P @ _RTHP.ORDER-U @",
        "_RTHP.ORDER2-A @ _RTHP-W-P @ _RTHP.ORDER2-U @",
    ):
        assert broad not in build

    assert (
        "_RTHP-W-DOC-RECORD-COUNT @ RTE-CONTROL-SIZE _RTHP-U32*?"
        in output
    )
    assert (
        "_RTHP-W-DOC-RECORD-COUNT @ RUCP-CORRELATION-SIZE "
        "_RTHP-U32*?" in output
    )
    assert "_RTHP-W-RUCP-CONTROL-U @ _RTHP-W-OUT-CONTROLS-U !" in output
    assert "_RTHP-W-RUCP-CORR-U @ _RTHP-W-OUT-CORR-U !" in output
    assert "SWAP - _RTHP-W-OUT-CONTROLS-U !" not in output
    assert "SWAP - _RTHP-W-OUT-CORR-U !" not in output

    # Independent sparse-document byte oracle: n=6 records whose greatest
    # source index is 12 requires h=13 work entries, not six and not 8,192.
    records = 6
    high_water = 13
    assert high_water * 32 == 416
    assert high_water * 8 == 104
    assert records * 192 == 1_152
    assert records * 48 == 288
    assert 144 + 2 * (416 + 104 + 104) + 1_152 + 288 == 2_832

def test_candidate_is_copied_planned_reserved_and_admitted_before_owner_open() -> None:
    source = _source()
    build = _word(source, "_RTHP-BUILD-CANDIDATE")
    preflight = _word(source, "_RTHP-W-PREFLIGHT-HYBRID")
    attempt = _word(source, "_RTHP-TRY-CANDIDATE")
    ordered = (
        "_RTHP-COPY-SNAPSHOT?",
        "_RTHP-BUILD-CONTROLS",
        "_RTHP-BUILD-CLAIMS?",
        "_RTHP-BUILD-INSTRUMENTS",
        "_RTHP-BUILD-GLYPHS?",
        "_RTHP-RESERVE-GLYPHS?",
        "_RTHP-WRAP-HYBRID",
        "_RTHP-W-PREFLIGHT-HYBRID",
        "_RTHP-DRAW-CURRENT?",
    )
    positions = [build.index(item) for item in ordered]
    assert positions == sorted(positions)
    assert build.count("_RTHP-W-PREFLIGHT-HYBRID") == 1
    assert preflight.count("RTE-HYBRID-PREFLIGHT") == 1
    assert "_RTHP-OPEN" not in build
    assert "_RTHP.PHASE !" not in build
    assert attempt.index("_RTHP-BUILD-CANDIDATE") < attempt.index("_RTHP-OPEN")
    assert _source().count("RTE-HYBRID-PREFLIGHT") == 1
    assert "RTE-CONTROL-PREFLIGHT" not in source
    assert "RTE-GLYPH-RUN-PREFLIGHT" not in source


def test_glyph_reserve_reuses_only_bounded_ack_topology_and_recovers() -> None:
    source = _source()
    bank = _word(source, "_RTHP-R-BANK-CEILING?")
    slots = _word(source, "_RTHP-R-SLOT-CEILING?")
    reserve = _word(source, "_RTHP-RESERVE-GLYPHS?")
    strip = _word(source, "_RTHP-STRIP-GLYPH-RESERVE")
    build = _word(source, "_RTHP-BUILD-CANDIDATE")
    preflight = _word(source, "_RTHP-W-PREFLIGHT-HYBRID")
    delta_run = _word(source, "_RTHP-D-RUN!")
    glyph_run = _word(source, "_RTHP-GLYPH-RUN!")

    # The complete bank proof reserves the conservative all-control target
    # ceiling and accounts for every retained byte family before reuse.
    for bound in (
        "_RTHP-TARGET-BANK-BYTES?",
        "_RTHP-TARGET-BANK-HEADER-SIZE",
        "_RTHP.CONTROL-COUNT",
        "_RTHP-TARGET-ENTRY-SIZE",
        "RTE-CONTROL-SIZE",
        "RUCP-CORRELATION-SIZE",
        "_RTHP.SOURCE-TEXT-USED",
        "_RTHP.GLYPH-TEXT-USED",
        "_RTHP-ALIGN8?",
        "RTE-GLYPH-RUN-PLAN-ITEM-SIZE",
        "RGRP-TEXT-REF-SIZE",
    ):
        assert bound in bank
    assert bank.count("_RTHP.CONTROL-COUNT") == 3
    assert "_RTHP.MENU-CONTROL-COUNT" not in bank

    for bound in (
        "_RTHP-R-BANK-CEILING?",
        "_RTHP.COLS",
        "_RTHP.ROWS",
        "_RTHP.GLYPH-ITEMS-U",
        "_RTHP.GLYPH-REFS-U",
        "_RTHP.COLLECTION-ITEMS",
        "_RTHP.INSTRUMENT-COUNT",
        "_RTHP.INSTRUMENT-REGION-COUNT",
        "RTE-LIMITS-OBJECTS@",
        "RTE-LIMITS-OPS@",
    ):
        assert bound in slots
    assert slots.count("_RTHP-R-LIMIT") >= 3
    assert not re.search(
        r"(?m)^\s*(?:0x[0-9A-Fa-f]+|\d+)\s+CONSTANT\s+\S*RESERVE",
        source,
    )

    # A fitting ACK slot bank is binary: reuse the whole acknowledged count,
    # or retain the exact actual count and let growth use full replacement.
    assert "_RTHP.TARGET-ACTIVE" in reserve
    assert "_RTHP-TARGET-BANK-HEADER?" in reserve
    assert reserve.count("_RTHP-TB.GLYPH-SLOT-COUNT") == 1
    assert "_RTHP-TB.GLYPH-SLOT-COUNT @ _RTHP-R-SLOTS !" in reserve
    assert "_RTHP-R-ACTUAL @" in reserve
    assert "_RTHP-R-SLOTS @ _RTHP-R-ACTUAL @ U< 0=" in reserve
    assert "_RTHP-R-SLOTS @ _RTHP-R-CEILING @ U> 0=" in reserve
    assert "_RTHP-R-CEILING @ _RTHP-R-TARGET !" not in reserve
    assert reserve.index("_RTHP-R-SLOT-CEILING?") < reserve.index(
        "_RTHP.TARGET-ACTIVE"
    )

    # Appended slots are valid contiguous, invisible, text-empty glyphs.  A
    # zero-length run receives no borrowed text pointer at emission time.
    assert "?DO" in reserve
    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE 0 FILL" in reserve
    assert "RGRP-TEXT-REF-SIZE 0 FILL" in reserve
    assert "_RTE-LPI.OBJECT !" in reserve
    assert "1 _RTHP-R-ITEM @ _RTE-LPI.HEIGHT !" in reserve
    assert "1 _RTHP-R-ITEM @ _RTE-LPI.WIDTH !" in reserve
    assert "0 _RTHP-R-ITEM @ _RTE-LPI.HEIGHT !" not in reserve
    assert "0 _RTHP-R-ITEM @ _RTE-LPI.WIDTH !" not in reserve
    assert "_RTE-LPI.ROOT-HEIGHT !" in reserve
    assert "_RTE-LPI.ROOT-WIDTH !" in reserve
    assert "_RGRP-T.OFFSET !" in reserve
    assert "_RTHP-U+?" in reserve
    assert "_RTE-LPI.VISIBLE !" not in reserve
    assert "_RTE-LPI.TEXT-CAPACITY !" not in reserve
    assert "0 OVER _RTE-GLYPH-RUN.TEXT-A !" in delta_run
    assert "_RTHP-D-EXPECTED-P @ SWAP _RTE-GLYPH-RUN.TEXT-U !" in delta_run
    assert "0 _RTHP-E-P @ _RTHP.RUN _RTE-GLYPH-RUN.TEXT-A !" in glyph_run
    assert "_RTHP-E-NEXT @ _RTHP-E-P @ _RTHP.RUN _RTE-GLYPH-RUN.TEXT-U !" in (
        glyph_run
    )

    # Backend-specific update and copy capacity stays behind exact preflight.
    # CAPACITY strips all padding, rewraps the original plan, and can iterate
    # only once because GLYPH-COUNT then equals the saved actual count.
    assert "_RTHP-R-ACTUAL" in strip
    assert "_RTHP-R-PLAN-SLOTS?" in strip
    assert "_RTHP.GLYPH-COUNT !" in strip
    assert "RTE-LIMITS-UPDATE-BYTES@" not in bank + slots + reserve
    assert build.count("_RTHP-W-PREFLIGHT-HYBRID") == 1
    assert preflight.count("RTE-HYBRID-PREFLIGHT") == 1
    assert preflight.count("_RTHP-STRIP-GLYPH-RESERVE") == 1
    assert "DUP RTE-S-CAPACITY =" in preflight
    assert "_RTHP.GLYPH-COUNT @ _RTHP-R-ACTUAL @ U> AND" in preflight
    assert build.index("_RTHP-RESERVE-GLYPHS?") < build.index(
        "_RTHP-WRAP-HYBRID"
    ) < build.index("_RTHP-W-PREFLIGHT-HYBRID")
    assert preflight.index("_RTHP-STRIP-GLYPH-RESERVE") < preflight.index(
        "_RTHP-WRAP-HYBRID"
    )


def test_owner_open_reserves_one_frame_independently_of_current_content() -> None:
    source = _source()
    open_owner = _word(source, "_RTHP-OPEN")
    collection_items = _word(source, "_RTHP-MAX-COLLECTION-ITEMS")

    assert "_RTHP.ADMISSION" not in open_owner
    for bound in (
        "_RTHP.MAX-CONTROLS",
        "_RTHP.MAX-COLLECTION-NATIVE",
        "_RTHP.MAX-INSTRUMENT-REGIONS",
        "_RTHP.MAX-INSTRUMENTS",
        "_RTHP.MAX-COLS",
        "_RTHP.MAX-ROWS",
        "_RTHP.MAX-TEXT",
        "RTE-LIMITS-OBJECTS@",
        "RTE-LIMITS-UTF8-BYTES@",
    ):
        assert bound in open_owner
    assert "_RTHP-MAX-COLLECTION-ITEMS" in open_owner
    assert "_RTHP.MAX-INSTRUMENT-REGIONS @ 1 _RTHP-U32+?" in open_owner
    assert "_RTHP.MAX-INSTRUMENTS @ _RTHP-U32+?" in open_owner
    assert "_RTHP.MAX-INSTRUMENTS @ IF" in open_owner
    instrument_text = open_owner[open_owner.index("_RTHP.MAX-INSTRUMENTS @ IF") :]
    instrument_text = instrument_text[: instrument_text.index("ELSE")]
    assert "RTE-LIMITS-UTF8-BYTES@" in instrument_text
    assert "_RTHP.MAX-DGRAPH-NATIVE" not in instrument_text
    assert "USCOL-TEXT-FIXED-SIZE -" in collection_items
    assert "USCOL-ITEM-HEADER-SIZE /" in collection_items
    assert open_owner.count("_RTHP-UMIN") == 3
    assert "_RTHP-O-REGIONS @ 0 _RTHP-O-OBJECTS @ 0 0 _RTHP-O-TEXT @ 0" in open_owner


def test_candidate_ids_advance_only_after_exact_hidden_start_ack() -> None:
    source = _source()
    init = _word(source, "RTHP-INIT")
    build = _word(source, "_RTHP-BUILD-CANDIDATE")
    fixed = _word(source, "_RTHP-FIXED-BODY?")
    candidate_last = _word(source, "_RTHP-CANDIDATE-LAST-OBJECT")
    successors = _word(source, "_RTHP-CANDIDATE-NEXT?")
    advance = _word(source, "_RTHP-ADVANCE-IDS?")
    publish_frontier = _word(source, "_RTHP-TARGET-NEXT-OBJECT?")
    publish = _word(source, "_RTHP-TARGET-PUBLISH?")
    sealed = _word(source, "_RTHP-STEP-SEALED")
    prepare = _word(source, "RTHP-PREPARE")

    assert "_RTHP.NEXT-REGION !" in init
    assert "_RTHP.NEXT-OBJECT !" in init
    assert build.index("_RTHP-SELECT-NEXT-IDS?") < build.index(
        "_RTHP-BUILD-CONTROLS"
    )
    assert build.index("_RTHP-W-PREFLIGHT-HYBRID") < build.index(
        "_RTHP-CANDIDATE-NEXT?"
    ) < build.index("_RTHP-DRAW-CURRENT?")
    assert "_RTHP.NEXT-REGION" in fixed
    assert "_RTHP.NEXT-OBJECT" in fixed
    assert (
        "_RTE-HA.CONTROL-BYTES @\n"
        "        _RTHP-X-P @ _RTHP.SOURCE-TEXT-USED @ <>"
    ) in fixed
    assert (
        "_RTE-HA.GLYPH-TEXT @\n"
        "        _RTHP-X-P @ _RTHP.GLYPH-TEXT-USED @ <>"
    ) in fixed
    assert successors.count("_RTHP-U+?") == 3
    assert "_RTHP-U32+?" not in successors

    build_controls = _word(source, "_RTHP-BUILD-MENU-CONTROLS?")
    assert "_RTHP-W-LAST @ 1 _RTHP-U+?" in build_controls
    assert "_RTHP-W-LAST @ 1 _RTHP-U32+?" not in build_controls
    assert "_RTE-HA.GLYPH-LAST" in candidate_last
    assert "_RTE-HA.INSTRUMENT-LAST" in candidate_last
    assert "_RTE-HA.CONTROL-LAST" in candidate_last
    assert "_RTHP.NEXT-REGION !" in advance
    assert "_RTHP.NEXT-OBJECT !" in advance
    exact_ack = (
        "_RTHP-S-STATE @ RTE-UPDATE-IDLE =\n"
        "    _RTHP-S-STATUS @ RTE-S-OK = AND IF"
    )
    assert sealed.index(exact_ack) < sealed.index("_RTHP-ADVANCE-IDS?")
    assert "_RTHP-PH-READY-REVEAL = IF" in sealed
    assert "_RTHP-ADVANCE-IDS?" not in prepare
    assert source.count("_RTHP-ADVANCE-IDS?") == 2

    # DELTA definitions consume their sparse fresh IDs only after the exact
    # target is physically acknowledged.  Cancellation and sealing never call
    # this frontier scan, and every acknowledged ID+1 is overflow-checked.
    assert "_RTHP-TB.CONTROL-COUNT @ 0 ?DO" in publish_frontier
    assert "_RTHP-PACK-CONTROLS-A" in publish_frontier
    assert "1 _RTHP-U+?" in publish_frontier
    assert "_RTHP.NEXT-OBJECT @" in publish_frontier
    assert publish.index("_RTHP-TARGET-BANK-ENTRIES?") < publish.index(
        "_RTHP-TARGET-NEXT-OBJECT?"
    ) < publish.index("_RTHP.TARGET-PENDING !")
    assert source.count("_RTHP-TARGET-NEXT-OBJECT?") == 2


def test_completed_draws_choose_ack_baselined_delta_or_full_recapture() -> None:
    source = _source()
    copy = _word(source, "_RTHP-COPY-SNAPSHOT?")
    wrap = _word(source, "_RTHP-WRAP-HYBRID")
    current = _word(source, "_RTHP-DRAW-CURRENT?")
    candidate_current = _word(source, "_RTHP-CANDIDATE-CURRENT?")
    build = _word(source, "_RTHP-BUILD-CANDIDATE")
    rebuild = _word(source, "_RTHP-REBUILD-CANDIDATE")
    recapture = _word(source, "_RTHP-RECAPTURE-START")
    step = _word(source, "RTHP-STEP")
    prepare = _word(source, "RTHP-PREPARE")
    reveal = _word(source, "_RTHP-PREPARE-REVEAL")
    delta_candidate = _word(source, "_RTHP-DELTA-CANDIDATE?")
    emit_delta = _word(source, "_RTHP-EMIT-DELTA")
    build_slot_map = _word(source, "_RTHP-D-BUILD-SLOT-MAP?")
    anchor_compare = _word(source, "_RTHP-D-ANCHOR-COMPARE")
    normalize_ids = _word(source, "_RTHP-D-NORMALIZE-GLYPH-IDS?")
    restore_fresh = _word(source, "_RTHP-D-RESTORE-FRESH-CANDIDATE")
    fence_glyph = _word(source, "_RTHP-D-PLAN-FENCE-GLYPH?")
    revision_fence = _word(source, "_RTHP-D-PLAN-REVISION-FENCE?")
    normalize = _word(source, "_RTHP-D-NORMALIZE")
    delta = _word(source, "_RTHP-PREPARE-DELTA")
    delta_stale = _word(source, "_RTHP-DELTA-STALE")
    prepare_live = _word(source, "_RTHP-PREPARE-LIVE")
    reveal_stale = _word(source, "_RTHP-REVEAL-STALE")
    valid = _word(source, "_RTHP-VALID-BODY?")

    assert "_RTHP.SURFACE-GEN !" not in copy
    assert "_RTHP.SOURCE-DRAW @" in wrap
    assert "SCR-DRAW-GENERATION@" in build
    assert build.index("_RTHP-W-PREFLIGHT-HYBRID") < build.index(
        "_RTHP-DRAW-CURRENT?"
    ) < build.index("_RTHP.SURFACE-GEN !")
    assert current.count("SCR-DRAW-GENERATION@") == 1
    assert current.count("RUHA-SNAPSHOT-FOR@") == 1
    assert "RUHA-SNAPSHOT-GENERATION@" in current
    assert "RUHA-SNAPSHOT-DRAW-GENERATION@" in current
    assert "RUHA-SNAPSHOT-DOCUMENT-COUNT@" in current
    assert "_RTHP.SOURCE-DRAW" in current
    assert "_RTE-HP.SURFACE-GENERATION" in current
    assert "_RTHP.SURFACE-GEN" in candidate_current

    assert "_RTHP-BUILD-CANDIDATE" in rebuild
    assert "SCB-S-WOULD-BLOCK" in rebuild
    assert "_RTHP-TARGET-ABORT" in recapture
    assert "_RTHP-PH-READY-START" in recapture
    assert recapture.index("_RTHP-REBUILD-CANDIDATE") < recapture.index(
        "_RTHP-PREPARE-START"
    )
    assert "_RTHP-RECAPTURE-START" not in step
    assert "_RTHP-RECAPTURE-START" in prepare
    assert "_RTHP-CANDIDATE-CURRENT?" in prepare
    assert "_RTHP-ACTIVE-DRAW-CURRENT?" in prepare_live
    assert "_RTHP.PHASE @ _RTHP-PH-LIVE = IF" in valid
    assert "_RTHP.SURFACE-GEN @" in valid
    assert "_RTHP.ACTIVE-DRAW @ <>" in valid
    ready_reveal = prepare[prepare.index("_RTHP-PH-READY-REVEAL = IF") :]
    ready_reveal = ready_reveal[: ready_reveal.index("_RTHP-PH-REVEAL-SEALED")]
    assert ready_reveal.index("_RTHP-CANDIDATE-CURRENT?") < ready_reveal.index(
        "_RTHP-PREPARE-REVEAL"
    ) < ready_reveal.index("_RTHP-RECAPTURE-START")
    live = prepare[prepare.index("_RTHP-PH-LIVE = IF") :]
    assert "_RTHP-PREPARE-LIVE" in live
    for anchor in (
        "_RTHP-ACTIVE-DRAW-CURRENT?",
        "_RTHP-DELTA-CANDIDATE?",
        "_RTHP-PREPARE-DELTA",
        "_RTHP-RECAPTURE-START",
    ):
        assert anchor in prepare_live

    exact_ack = (
        "_RTHP-P-STATE @ RTE-UPDATE-IDLE =\n"
        "    _RTHP-P-STATUS @ RTE-S-OK = AND IF"
    )
    assert "RTE-UPDATE-STATE@" in reveal_stale
    assert exact_ack in reveal_stale
    acked = reveal_stale[reveal_stale.index(exact_ack) :]
    assert acked.index("_RTHP-PH-LIVE") < acked.index(
        "_RTHP-TARGET-PUBLISH?"
    ) < acked.index("_RTHP-PREPARE-LIVE")
    assert acked.index("_RTHP-PREPARE-LIVE") < acked.index(
        "_RTHP-RECAPTURE-START"
    )

    # Compatibility is judged against the physically acknowledged active
    # bank, not against the mutable planner arrays alone.
    assert "_RTHP.TARGET-ACTIVE" in delta_candidate
    assert "_RTHP.TARGET-PENDING" in delta_candidate
    assert "_RTHP.GLYPH-ID-MAP-A" in build_slot_map
    assert "_RTHP.GLYPH-ID-MAP-U" in build_slot_map
    assert build_slot_map.count("_RTHP-U+?") == 1
    assert "_RTHP-D-GLYPH-BASE @ _RTHP-UMIN" in build_slot_map
    assert "_RTHP-D-PENDING-FRESH?" not in source
    assert "_RTE-LPI.ROW" in anchor_compare
    assert "_RTE-LPI.COL" in anchor_compare
    for payload_field in ("WIDTH", "ATTRS", "TEXT"):
        assert payload_field not in anchor_compare
    assert normalize_ids.index("_RTHP-D-ACTIVE-VISIBLE @ _RTHP-D-SLOTS @") < (
        normalize_ids.index("0 _RTHP-D-ACTIVE-VISIBLE @")
    )
    assert "_RTHP-D-NORMALIZE-GLYPH-IDS?" in delta_candidate
    assert delta_candidate.index("_RTHP-D-EXTEND-TOMBSTONES?") < (
        delta_candidate.index("_RTHP-D-NORMALIZE-GLYPH-IDS?")
    ) < delta_candidate.index("_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?")
    assert "_RTHP-R-PLAN-SLOTS?" in restore_fresh
    assert "_RTHP-WRAP-HYBRID" in restore_fresh
    assert "_RTHP-TARGET-ABORT" in restore_fresh
    zero_ops = delta_candidate.index("_RTHP-D-OPS @ 0= IF")
    assert zero_ops < delta_candidate.index(
        "_RTHP-D-PLAN-REVISION-FENCE?"
    ) < delta_candidate.index("_RTHP-D-PLAN-COMPACT-GLYPHS")
    assert "_RTHP-D-ID>MAP?" in fence_glyph
    assert "_RTHP-D-OPS +!" in fence_glyph
    assert revision_fence.index("_RTHP-D-PENDING-VISIBLE") < (
        revision_fence.index("_RTHP-D-CONTROL-PAIR")
    ) < revision_fence.rindex("_RTHP-D-PLAN-FENCE-GLYPH?")
    for wire_call in ("RTE-RETAINED-BEGIN", "RTE-GLYPH-RUN-REPLACE"):
        assert wire_call not in revision_fence
    assert "_RTE-LPI.OBJECT !" not in normalize
    assert "_RTHP-D-SURPLUS-COMPATIBLE?" not in source
    assert "_RTHP-D-PLAN-SEAL" in delta_candidate
    assert "_RTHP-D-PLAN-BIND?" in emit_delta
    for repeated_proof in (
        "_RTHP-D-BUILD-SLOT-MAP?",
        "_RTHP-D-CANONICAL-SLOT?",
        "_RTHP-D-CONTROL-COMPATIBLE?",
        "_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?",
    ):
        assert repeated_proof not in emit_delta
    assert "_RTHP-PH-READY-DELTA" in prepare
    assert "_RTHP-PH-DELTA-SEALED" in prepare
    assert "_RTHP-DELTA-STALE" in prepare
    assert "_RTHP-RECAPTURE-START" in delta_stale
    assert "_RTHP-TARGET-PUBLISH?" not in delta_stale

    assert "RTE-RETAINED-REPLACE-CONTINUE" in reveal
    assert "RTE-COMMIT-AND-REVEAL" in reveal
    assert "_RTHP-EMIT-" not in reveal
    assert source.count("RTE-RETAINED-REPLACE-START") == 1
    assert delta.count("RTE-RETAINED-DELTA") == 1
    assert "RTE-CONTROL-REPLACE" in source
    assert "RTE-GLYPH-RUN-REPLACE" in source
    assert "RTE-CONTROL-DEFINE" in emit_delta
    assert "_RTHP-D-PLAN-DEFINE @ IF" in emit_delta
    assert "RTE-GLYPH-RUN-DEFINE" not in emit_delta
    assert delta.index("RTE-RETAINED-DELTA") < delta.index(
        "_RTHP-EMIT-DELTA"
    ) < delta.index("RTE-COMMIT") < delta.index("RTE-RETAINED-SEAL")
    assert "_RTHP-PH-DELTA-SEALED" in delta


def test_stable_glyph_delta_is_proved_once_and_revision_bound_at_emit() -> None:
    source = _source()
    build_map = _word(source, "_RTHP-D-BUILD-SLOT-MAP?")
    canonical_begin = _word(source, "_RTHP-D-CANONICAL-BEGIN")
    canonical_slot = _word(source, "_RTHP-D-CANONICAL-SLOT?")
    id_to_map = _word(source, "_RTHP-D-ID>MAP?")
    active_index = _word(source, "_RTHP-D-ACTIVE-INDEX?")
    pair = _word(source, "_RTHP-D-GLYPH-PAIR?")
    ref_valid = _word(source, "_RTHP-D-REF-VALID?")
    glyph_text_equal = _word(source, "_RTHP-D-GLYPH-TEXT-EQUAL?")
    candidate = _word(source, "_RTHP-DELTA-CANDIDATE?")
    restore = _word(source, "_RTHP-D-RESTORE-FRESH-CANDIDATE")
    match = _word(source, "_RTHP-D-MATCH-ANCHORS?")
    normalize_ids = _word(source, "_RTHP-D-NORMALIZE-GLYPH-IDS?")
    visible_pool = _word(source, "_RTHP-D-ASSIGN-VISIBLE-POOL?")
    next_visible = _word(source, "_RTHP-D-NEXT-UNMATCHED-VISIBLE?")
    active_unused = _word(source, "_RTHP-D-ACTIVE-UNUSED?")
    tombstone = _word(source, "_RTHP-D-CANONICAL-TOMBSTONE!")
    extend_tombstones = _word(source, "_RTHP-D-EXTEND-TOMBSTONES?")
    assign_tail = _word(source, "_RTHP-D-ASSIGN-PENDING-TAIL?")
    plan_start = _word(source, "_RTHP-D-PLAN-START?")
    plan_compact = _word(source, "_RTHP-D-PLAN-COMPACT-GLYPHS")
    plan_seal = _word(source, "_RTHP-D-PLAN-SEAL")
    plan_bind = _word(source, "_RTHP-D-PLAN-BIND?")
    plan_control = _word(source, "_RTHP-D-PLAN-CONTROL!")
    plan_control_store = _word(source, "_RTHP-D-PLAN-CONTROL-STORE?")
    control_pair = _word(source, "_RTHP-D-CONTROL-PAIR")
    parent_topology = _word(source, "_RTHP-D-PARENT-TOPOLOGY?")
    target_abort = _word(source, "_RTHP-TARGET-ABORT")
    target_publish = _word(source, "_RTHP-TARGET-PUBLISH?")
    emit = _word(source, "_RTHP-EMIT-DELTA")
    normalize = _word(source, "_RTHP-D-NORMALIZE")
    compatible = _word(source, "_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?")

    # The inverse map is caller-bounded, native-ID-safe, and rejects duplicate
    # acknowledged identities before any pending bank can be normalized.
    assert build_map.count("_RTHP-U+?") == 1
    assert "_RTHP-D-SLOTS @ 1 ?DO" in build_map
    assert "_RTHP-D-GLYPH-BASE @ _RTHP-UMIN" in build_map
    assert "_RTHP-D-SLOTS @ 8 _RTHP-U32*?" in build_map
    assert "_RTHP.GLYPH-ID-MAP-A" in build_map
    assert "_RTHP.GLYPH-ID-MAP-U" in build_map
    assert "_RTHP-ARENA-SPAN?" in build_map
    assert build_map.count("MSPAN-OVERLAP?") == 2
    assert "_RTHP.TARGET0-A" in build_map
    assert "_RTHP.TARGET1-A" in build_map
    assert "DUP @ IF DROP 0 UNLOOP EXIT THEN" in build_map
    active_audit_order = (
        "_RTHP-D-ACTIVE @ _RTHP-D-CANONICAL-BEGIN",
        "_RTHP-D-SLOTS @ 0 ?DO",
        "I _RTHP-D-CANONICAL-SLOT? 0= IF 0 UNLOOP EXIT THEN",
        "_RTE-LPI.OBJECT @",
        "_RTHP-D-ID>MAP?",
        "I 1+ SWAP !\n    LOOP",
        "_RTHP-D-SCAN-VISIBLE @ _RTHP-D-ACTIVE-VISIBLE !",
    )
    active_audit = build_map[
        build_map.index("_RTHP-D-ACTIVE @ _RTHP-D-CANONICAL-BEGIN") :
    ]
    positions = [active_audit.index(anchor) for anchor in active_audit_order]
    assert positions == sorted(positions)
    assert build_map.count("?DO") == 2
    assert build_map.count("_RTHP-D-CANONICAL-SLOT?") == 1
    for reset in (
        "_RTHP-D-SCAN-BANK !",
        "0 _RTHP-D-SCAN-VISIBLE !",
        "0 _RTHP-D-SCAN-TAIL !",
        "-1 _RTHP-D-SCAN-PRIOR-ROW !",
        "0 _RTHP-D-SCAN-PRIOR-END !",
    ):
        assert reset in canonical_begin
    for validation in (
        "_RTE-LPI.PARENT",
        "_RTE-LPI.RESERVED",
        "_RTE-LPI.VISIBLE",
        "_RTE-LPI.FG-RGBA",
        "_RTE-LPI.BG-RGBA",
        "_RTE-LPI.ATTRS",
        "_RTE-LPI.ROOT-HEIGHT",
        "_RTE-LPI.ROOT-WIDTH",
        "_RTE-LPI.HEIGHT",
        "_RTE-LPI.ROW",
        "_RTE-LPI.COL",
        "_RTE-LPI.WIDTH",
        "_RTHP-D-REF-VALID?",
        "_RTHP-D-SCAN-TAIL",
        "_RTHP-D-SCAN-PRIOR-ROW",
        "_RTHP-D-SCAN-PRIOR-END",
        "_RTHP-D-REF-TEXT-EMPTY?",
    ):
        assert validation in canonical_slot
    canonical_code = " ".join(canonical_slot.split())
    assert canonical_code.count("0xFFFFFFFF U> IF 0 EXIT THEN") == 2
    assert "_RTE-GLYPH-RUN-ATTRS? 0= IF 0 EXIT THEN" in canonical_code
    assert "_RTE-LPI.HEIGHT @ 1 <> IF 0 EXIT THEN" in canonical_code
    assert "_RTE-LPI.ROW @ DUP _RTHP-D-SCAN-ROW ! 0< IF 0 EXIT THEN" in (
        canonical_code
    )
    assert "_RTE-LPI.COL @ DUP _RTHP-D-SCAN-COL ! 0< IF 0 EXIT THEN" in (
        canonical_code
    )
    assert "_RTE-LPI.WIDTH @ DUP 0> 0= IF DROP 0 EXIT THEN" in canonical_code
    assert "_RTHP-D-SCAN-COL @ SWAP _RTHP-U32+?" in canonical_code
    assert "_RTHP-TB.COLS @ U> IF 0 EXIT THEN" in canonical_code
    for exact in (
        "_RTHP-D-PENDING-I @ _RTE-LPI.ROW @ IF 0 EXIT THEN",
        "_RTHP-D-PENDING-I @ _RTE-LPI.COL @ IF 0 EXIT THEN",
        "_RTHP-D-PENDING-I @ _RTE-LPI.HEIGHT @ 1 <> IF 0 EXIT THEN",
        "_RTHP-D-PENDING-I @ _RTE-LPI.WIDTH @ 1 <> IF 0 EXIT THEN",
    ):
        assert exact in canonical_code
    assert "?DO" not in canonical_slot and "BEGIN" not in canonical_slot
    assert source.count("_RTHP-D-CANONICAL-BEGIN") == 3
    assert source.count("_RTHP-D-CANONICAL-SLOT?") == 3
    assert "_RTHP-D-GLYPH-BASE" in id_to_map
    binding_order = (
        "_RTHP-D-ID>MAP?",
        "DUP _RTHP-D-MAP-ENTRY !",
        "@ DUP 0< 0=",
        "_RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT",
        "DUP _RTHP-D-ACTIVE-I !",
        "_RTHP-D-MAP-ID @ <> IF DROP 0 0 EXIT THEN",
    )
    positions = [active_index.index(anchor) for anchor in binding_order]
    assert positions == sorted(positions)
    assert "_RTHP-D-ACTIVE-INDEX?" in pair
    assert pair.count("_RTHP-D-ITEM-AT") == 1
    assert "_RTHP-D-ACTIVE @ _RTHP-D-ITEM-AT" not in pair
    assert "BEGIN" not in pair and "?DO" not in pair

    ordered = (
        "_RTHP-D-BUILD-SLOT-MAP?",
        "_RTHP-D-EXTEND-TOMBSTONES?",
        "_RTHP-D-NORMALIZE-GLYPH-IDS?",
        "_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?",
        "_RTHP-D-PLAN-COMPACT-GLYPHS",
        "_RTHP-D-PLAN-SEAL",
    )
    positions = [candidate.index(anchor) for anchor in ordered]
    assert positions == sorted(positions)
    assert candidate.index("_RTHP-D-PLAN-COMPACT-GLYPHS") < candidate.rindex(
        "\n    _RTHP-D-NORMALIZE 0= IF"
    ) < candidate.index("_RTHP-D-PLAN-SEAL")
    assert "_RTHP-D-CANONICAL-GLYPHS?" not in source
    assert "_RTHP-D-PLAN-GLYPH-MARK?" not in source
    assert candidate.count("_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?") == 1
    assert candidate.count("_RTHP-D-RESTORE-FRESH-CANDIDATE") == 5
    candidate_code = " ".join(candidate.split())
    assert (
        "I _RTHP-D-GLYPH-COMPATIBLE-AND-MARK? 0= IF "
        "_RTHP-D-RESTORE-FRESH-CANDIDATE 0 UNLOOP EXIT THEN"
    ) in candidate_code
    restore_order = (
        "_RTHP.GLYPH-COUNT !",
        "_RTHP-R-PLAN-SLOTS?",
        "_RTHP-WRAP-HYBRID",
        "_RTHP-TARGET-ABORT",
    )
    positions = [restore.index(anchor) for anchor in restore_order]
    assert positions == sorted(positions)

    # Both spatial scans advance monotone cursors.  Pool assignment never
    # restarts the pending scan, so two allocation pools remain O(slots).
    fresh_clear = match[: match.index("0 _RTHP-D-ACTIVE-CURSOR !")]
    fresh_clear_order = (
        "_RTHP-D-PENDING @ _RTHP-D-CANONICAL-BEGIN",
        "_RTHP-D-SLOTS @ 0 ?DO",
        "I _RTHP-D-CANONICAL-SLOT? 0= IF 0 UNLOOP EXIT THEN",
        "_RTHP-D-GLYPH-EXPECTED?",
        "_RTE-LPI.OBJECT @",
        "<> IF 0 UNLOOP EXIT THEN",
        "0 _RTHP-D-PENDING-I @ _RTE-LPI.OBJECT !",
        "\n    LOOP",
        "_RTHP-D-SCAN-VISIBLE @ _RTHP-D-PENDING-VISIBLE !",
    )
    positions = [fresh_clear.index(anchor) for anchor in fresh_clear_order]
    assert positions == sorted(positions)
    assert fresh_clear.count("?DO") == 1
    assert fresh_clear.count("_RTHP-D-CANONICAL-SLOT?") == 1
    assert "_RTHP-D-ANCHOR-COMPARE" in match
    assert "_RTHP-D-SLOT-USE?" in match
    assert "_RTHP-D-PENDING-FRESH?" not in source
    assert match.count("1 _RTHP-D-ACTIVE-CURSOR +!") >= 2
    assert match.count("1 _RTHP-D-PENDING-CURSOR +!") >= 2
    assert normalize_ids.count("0 _RTHP-D-PENDING-CURSOR !") == 1
    assert normalize_ids.count("_RTHP-D-ASSIGN-VISIBLE-POOL?") == 2
    assert normalize_ids.index(
        "_RTHP-D-ACTIVE-VISIBLE @ _RTHP-D-SLOTS @"
    ) < normalize_ids.index("0 _RTHP-D-ACTIVE-VISIBLE @")
    assert "_RTHP-D-ASSIGN-PENDING-TAIL?" in normalize_ids
    assert "0 _RTHP-D-PENDING-CURSOR !" not in visible_pool + next_visible
    assert "_RTHP-D-ID>MAP?" in active_unused
    assert "BEGIN" not in active_unused and "?DO" not in active_unused

    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE 0 FILL" in tombstone
    assert "RGRP-TEXT-REF-SIZE 0 FILL" in tombstone
    assert "_RTHP-D-SLOT-USE?" in tombstone
    assert "1 _RTHP-D-PENDING-I @ _RTE-LPI.HEIGHT !" in tombstone
    assert "1 _RTHP-D-PENDING-I @ _RTE-LPI.WIDTH !" in tombstone
    assert "_RTE-LPI.ROOT-HEIGHT !" in tombstone
    assert "_RTE-LPI.ROOT-WIDTH !" in tombstone
    assert "_RTHP-TB.GLYPH-TEXT-USED @" in tombstone
    assert "RTE-GLYPH-RUN-PLAN-ITEM-SIZE 0 FILL" in extend_tombstones
    assert "1 _RTHP-D-PENDING-I @ _RTE-LPI.HEIGHT !" in extend_tombstones
    assert "1 _RTHP-D-PENDING-I @ _RTE-LPI.WIDTH !" in extend_tombstones
    assert not re.search(
        r"\b0\s+_RTHP-D-PENDING-I\s+@\s+_RTE-LPI\.(?:HEIGHT|WIDTH)\s+!",
        tombstone + extend_tombstones,
    )
    assert "_RTHP-D-CANONICAL-TOMBSTONE!" in assign_tail
    assert assign_tail.count("?DO") == 1
    assert "_RTHP-D-MAP-AT @ 0< 0=" not in assign_tail
    assert "_RTE-LPI.OBJECT @ 0=" not in assign_tail
    assert "_RTHP-D-TAIL-CURSOR @ _RTHP-D-SLOTS @ U< 0=" in assign_tail
    assert "_RTHP-D-TAIL-CURSOR @ _RTHP-D-SLOTS @ <> IF 0 EXIT THEN" in (
        assign_tail
    )
    tombstone_order = (
        "I _RTHP-D-TAIL-CURSOR @ _RTHP-D-CANONICAL-TOMBSTONE!",
        "0= IF 0 UNLOOP EXIT THEN",
        "1 _RTHP-D-TAIL-CURSOR +!",
    )
    positions = [assign_tail.index(anchor) for anchor in tombstone_order]
    assert positions == sorted(positions)

    # Tail cardinality constructs a bijection; the next per-slot pass rejects
    # an invalid, missing, or duplicate pending identity and compaction proves
    # that no acknowledged identity remains unconsumed.
    assert "_RTHP-D-ID>MAP?" in active_index
    assert "@ DUP 0< 0=" in active_index
    assert "_RTHP-D-MAP-ID @ <> IF DROP 0 0 EXIT THEN" in active_index
    assert "_RTHP-D-ACTIVE-INDEX?" in pair
    marker_order = (
        "_RTHP-D-GLYPH-TEXT-EQUAL?",
        "_RTHP-D-MAP-ENTRY @ DUP @ 0< 0= IF DROP 0 EXIT THEN",
        "_RTHP-D-I @ 1+ 1 _RTHP-D-OPS +!",
        "THEN SWAP !",
    )
    positions = [compatible.index(anchor) for anchor in marker_order]
    assert positions == sorted(positions)
    assert "_RTHP-D-ID>MAP?" not in compatible
    assert "_RTHP-D-ITEM-AT" not in compatible
    assert "_RTHP-D-MAP-ENTRY !" not in ref_valid + glyph_text_equal
    assert source.count("_RTHP-D-MAP-ENTRY !") == 2
    assert "DUP 0< IF DROP 0 UNLOOP EXIT THEN" in plan_compact

    # READY_DELTA may be delayed, so the compact plan is bound to both exact
    # banks, their draws, the candidate attempt, and source generation.  Emit
    # uses that plan without repeating the topology/text proof and retains it
    # until abort or publication so a delayed retry remains exact.
    assert "_RTHP.ORDER2-U" in plan_start
    assert "_RTHP-ARENA-SPAN?" in plan_start
    assert plan_compact.count("?DO") == 1
    assert "DUP 0< IF DROP 0 UNLOOP EXIT THEN" in plan_compact
    assert "_RTHP-D-SLOTS @ U< 0=" in plan_compact
    for key in (
        "_RTHP.DELTA-PLAN-ACTIVE",
        "_RTHP.DELTA-PLAN-PENDING",
        "_RTHP.DELTA-PLAN-ACTIVE-DRAW",
        "_RTHP.DELTA-PLAN-PENDING-DRAW",
        "_RTHP.DELTA-PLAN-ATTEMPT",
        "_RTHP.DELTA-PLAN-SOURCE-GEN",
    ):
        assert key in plan_seal
        assert key in plan_bind
    assert "_RTHP-D-BIND?" in plan_bind
    assert plan_bind.count("_RTHP-TB.GLYPH-SLOT-COUNT @") >= 3
    assert "_RTHP-D-PLAN-BIND?" in emit
    assert "_RTHP-DELTA-PLAN-CLEAR" not in emit
    assert "_RTHP-DELTA-PLAN-CLEAR" in target_abort
    assert "_RTHP-DELTA-PLAN-CLEAR" in target_publish
    # Graph ordinals and semantic parents have separate lifetimes: survivor
    # matching may move an ordinal, while plan records retain the pending one.
    assert "_RTHP-D-CONTROL-ORDINAL !" in control_pair
    assert "_RTHP-D-CONTROL-FIND?" in control_pair
    assert "_RTHP-D-OFFSET-P" in parent_topology
    assert "_RTHP-D-CONTROL-ORDINAL @" in plan_control_store
    assert "_RTHP-D-OFFSET-P @" not in plan_control + plan_control_store
    for repeated_proof in (
        "_RTHP-D-BUILD-SLOT-MAP?",
        "_RTHP-D-CANONICAL-SLOT?",
        "_RTHP-D-CONTROL-COMPATIBLE?",
        "_RTHP-D-GLYPH-COMPATIBLE-AND-MARK?",
        "COMPARE",
    ):
        assert repeated_proof not in emit
    assert "_RTHP-D-PLAN-CONTROLS @ 0 ?DO" in emit
    assert "_RTHP-D-PLAN-GLYPHS @ 0 ?DO" in emit
    assert "_RTE-LPI.OBJECT !" not in normalize
    assert "_RTHP-D-SURPLUS-COMPATIBLE?" not in source
    assert "_RTHP-D-GLYPH-PAIR?" in compatible
    assert "_RTHP-D-GLYPH-EXPECTED?" not in compatible


def test_final_capture_rechecks_fixed_authority_then_traverses_each_family_once() -> None:
    source = _source()
    start = _word(source, "_RTHP-PREPARE-START")
    assert start.index("_RTHP-FIXED?") < start.index("RTE-RETAINED-BEGIN")
    assert start.count("_RTHP-EMIT-CONTROLS") == 1
    assert start.count("_RTHP-EMIT-INSTRUMENT-REGIONS") == 1
    assert start.count("_RTHP-EMIT-INSTRUMENTS") == 1
    assert start.count("_RTHP-EMIT-GLYPHS") == 1
    family_order = (
        "_RTHP-EMIT-INSTRUMENT-REGIONS",
        "_RTHP-EMIT-CONTROLS",
        "_RTHP-EMIT-INSTRUMENTS",
        "_RTHP-EMIT-GLYPHS",
    )
    assert [start.index(word) for word in family_order] == sorted(
        start.index(word) for word in family_order
    )
    controls = _word(source, "_RTHP-EMIT-CONTROLS")
    regions = _word(source, "_RTHP-EMIT-INSTRUMENT-REGIONS")
    instruments = _word(source, "_RTHP-EMIT-INSTRUMENTS")
    glyphs = _word(source, "_RTHP-EMIT-GLYPHS")
    fixed_instruments = _word(source, "_RTHP-INSTRUMENT-FIXED?")
    fixed_aggregates = _word(source, "_RTHP-X-INSTRUMENT-AGGREGATES?")
    assert "_RTHP-X-INSTRUMENT-AGGREGATES?" in fixed_instruments
    for exact in (
        "_RTE-HA.INSTRUMENT-UNIT-BYTES",
        "_RTE-HA.INSTRUMENT-UNIT-ALIGNED",
        "_RTE-HA.INSTRUMENT-UNIT-MAX",
        "_RTE-HA.INSTRUMENT-FORMATTED-BYTES",
        "_RTE-HA.INSTRUMENT-FORMATTED-MAX",
        "_RTE-HA.READOUT-COUNT",
        "_RTE-HA.METER-COUNT",
        "_RTE-HA.STATUS-COUNT",
    ):
        assert exact in fixed_aggregates
    assert controls.count("?DO") == len(re.findall(r"(?m)^\s*LOOP\s*$", controls)) == 1
    assert regions.count("?DO") == len(re.findall(r"(?m)^\s*LOOP\s*$", regions)) == 1
    assert instruments.count("?DO") == len(re.findall(r"(?m)^\s*LOOP\s*$", instruments)) == 1
    assert glyphs.count("?DO") == len(re.findall(r"(?m)^\s*LOOP\s*$", glyphs)) == 1
    assert regions.index("DROP\n        _RTHP-E-P @") < regions.index(
        "RTE-REGION-DEFINE"
    )
    assert ">R" not in controls + regions + instruments + glyphs


def test_sealed_retry_preserves_only_a_current_exact_candidate() -> None:
    prepare = _word(_source(), "RTHP-PREPARE")
    start_sealed = prepare.split("_RTHP-PH-START-SEALED = IF", 1)[1].split(
        "THEN", 1
    )[0]
    reveal_sealed = prepare.split("_RTHP-PH-REVEAL-SEALED = IF", 1)[1].split(
        "THEN", 1
    )[0]
    delta_sealed = prepare[prepare.index("_RTHP-PH-DELTA-SEALED = IF") :]
    delta_sealed = delta_sealed[: delta_sealed.index("_RTHP-PH-LIVE = IF")]
    assert "SCB-S-OK EXIT" in start_sealed
    assert "_RTHP-PREPARE-START" not in start_sealed
    assert "_RTHP-PREPARE-REVEAL" not in reveal_sealed
    assert "_RTHP-RECAPTURE-START" not in start_sealed
    assert reveal_sealed.index("_RTHP-CANDIDATE-CURRENT?") < reveal_sealed.index(
        "SCB-S-OK"
    ) < reveal_sealed.index("_RTHP-REVEAL-STALE")
    assert delta_sealed.index("_RTHP-CANDIDATE-CURRENT?") < delta_sealed.index(
        "SCB-S-OK"
    ) < delta_sealed.index("_RTHP-DELTA-STALE")


def test_slice_remains_generic_caller_bounded_and_digest_free() -> None:
    source = _source()
    lowered = source.lower()
    assert "allocate" not in lowered
    assert "xbuf" not in lowered
    assert "sha3" not in lowered
    assert "pad-entry" not in lowered
    assert "daybook-entry" not in lowered
    for required in (
        "RTHP-STORAGE-BYTES",
        "RUHA-SNAPSHOT-FOR@",
        "RUCP-BUILD",
        "RUCL-BUILD",
        "RUIP-BUILD",
        "RGRP-BUILD",
        "RTE-CONTROL-DEFINE",
        "RTE-INSTRUMENT-DEFINE",
        "RTE-GLYPH-RUN-DEFINE",
    ):
        assert required in source


def test_residual_capture_is_ack_baselined_and_row_damage_bounded() -> None:
    source = _source()
    sizing = _word(source, "_RTHP-BYTES-BODY")
    layout = _word(source, "_RTHP-LAYOUT")
    target = _word(source, "_RTHP-TARGET-CANDIDATE?")
    header = _word(source, "_RTHP-TARGET-BANK-HEADER?")
    publish = _word(source, "_RTHP-TARGET-PUBLISH?")
    bind = _word(source, "_RTHP-D-BIND?")
    eligible = _word(source, "_RTHP-RD-ELIGIBLE?")
    authority = _word(source, "_RTHP-RD-SCREEN-AUTHORITY?")
    mark_cells = _word(source, "_RTHP-RD-MARK-CELL-DAMAGE?")
    mark_claims = _word(source, "_RTHP-RD-MARK-CURRENT-CLAIMS?")
    scan_active = _word(source, "_RTHP-RD-SCAN-ACTIVE-ROW?")
    copy_one = _word(source, "_RTHP-RD-COPY-ACTIVE-ONE?")
    row_output = _word(source, "_RTHP-RD-ROW-OUTPUT?")
    row_build = _word(source, "_RTHP-RD-BUILD-ROW?")
    body = _word(source, "_RTHP-RD-BUILD-BODY?")
    callback = _word(source, "_RTHP-RD-BUILD-IN-PLANES")
    cleanup = _word(source, "_RTHP-RD-CLEAR-PLANE-BORROW")
    damage = _word(source, "_RTHP-BUILD-GLYPHS-DAMAGE?")
    dispatcher = _word(source, "_RTHP-BUILD-GLYPHS?")

    assert "_RTHP-B-ROWS @ _RTHP-ALIGN8?" in sizing
    assert "_RTHP-B-CELLS @ 8 _RTHP-B-MUL-ADD" in sizing
    assert "_RTHP.MAX-ROWS @" in layout
    assert "_RTHP.ROW-DAMAGE-A" in layout
    assert "_RTHP.ROW-DAMAGE-U" in layout
    assert "_RTHP.MAX-COLS @ OVER _RTHP.MAX-ROWS @ * 8 *" in layout
    assert "_RTHP.GLYPH-ID-MAP-A" in layout
    assert "_RTHP.GLYPH-ID-MAP-U" in layout
    assert "_RTHP-TB.GLYPH-RUN-LIMIT !" in target
    for verifier in (header, publish, bind, eligible):
        assert "_RTHP-TB.GLYPH-RUN-LIMIT" in verifier

    for proof in (
        "_RTHP.TARGET-ACTIVE",
        "_RTHP-TARGET-BANK-HEADER?",
        "_RTHP-TB.OWNER",
        "_RTHP-TB.GENERATION",
        "_RTHP-TB.COLS",
        "_RTHP-TB.ROWS",
        "_RTHP-TB.PHYSICAL-GEN",
        "_RTHP-TB.GLYPH-RUN-LIMIT",
        "_RTHP-TB.DRAW",
        "_RTHP.ACTIVE-DRAW",
    ):
        assert proof in eligible
    assert "_RTHP-RD-FORCE @ IF 0 EXIT THEN" in eligible
    assert "COMPARE" not in mark_cells
    assert "_RTHP-RD-CELL-DAMAGE-A @ 0= IF 0 EXIT THEN" in mark_cells
    assert "_RTHP-RD-CELL-DAMAGE-U @ _RTHP-RD-ROWS @ <>" in mark_cells
    assert "MSPAN-NONWRAPPING?" in mark_cells
    assert "_RTHP.ROW-DAMAGE-A @ _RTHP-RD-ROWS @ MOVE" in mark_cells
    assert "SCR-GET" not in source
    assert "RUCL-CLAIM-ROW0@" in mark_claims
    assert "RUCL-CLAIM-ROW1@" in mark_claims
    assert "_RTHP-RD-COVER" in scan_active
    assert "_RTHP-RD-DAMAGE!" in scan_active
    assert "_RTE-LPI.TEXT-CAPACITY @" in copy_one
    assert (
        "_RTHP-W-GLYPH-FIRST @ _RTHP-RD-OUT-COUNT @ _RTHP-U+?"
        in copy_one
    )

    # A row invocation can consume at most COLS items/refs and four UTF-8
    # bytes per cell, and it scans the already-borrowed back plane directly.
    for bound in (
        "RTE-GLYPH-RUN-PLAN-ITEM-SIZE",
        "RGRP-TEXT-REF-SIZE",
        "_RTHP-RD-COLS @ 4 _RTHP-U32*?",
        "_RTHP-UMIN",
    ):
        assert bound in row_output
    for optional in (
        "ELSE 0 _RTHP-RD-OUT-ITEMS-A ! THEN",
        "ELSE 0 _RTHP-RD-OUT-REFS-A ! THEN",
        "ELSE 0 _RTHP-RD-OUT-TEXT-A ! THEN",
    ):
        assert optional in row_output
    assert "_RGRP-BUILD-FROM-AUTHORIZED-PLANE" in row_build
    assert "RGRP-BUILD" not in row_build.replace(
        "_RGRP-BUILD-FROM-AUTHORIZED-PLANE", ""
    )
    assert "_RTHP-RD-BACK @" in row_build
    assert (
        "_RTHP-W-GLYPH-FIRST @ _RTHP-RD-OUT-COUNT @ _RTHP-U+?"
        in row_build
    )
    assert authority.count("SCR-STORAGE-DISJOINT?") == 2
    assert "MSPAN-OVERLAP?" in authority
    assert authority.count("_RTHP-ARENA-SPAN?") == 4
    assert "_RTHP-RD-SCREEN-AUTHORITY?" in body
    assert "_RTHP-RD-WORK-BOUNDS?" in body
    assert body.index("_RTHP-RD-SCREEN-AUTHORITY?") < body.index(
        "_RTHP-RD-MARK-CELL-DAMAGE?"
    ) < body.index("_RTHP-RD-MARK-CURRENT-CLAIMS?")
    assert "_RTHP-RD-COPY-ACTIVE-ROW?" in body
    assert "_RTHP-RD-BUILD-ROW?" in body
    assert "_RTHP-RD-BUILD-BODY?" in callback
    assert "CATCH" in callback
    assert "THROW" in callback
    assert callback.index("_RTHP-RD-BUILD-BODY?") < callback.index(
        "_RTHP-RD-CLEAR-PLANE-BORROW"
    )
    assert "damage-a damage-u -- flag" in callback
    assert callback.index("_RTHP-RD-CELL-DAMAGE-U !") < callback.index(
        "_RTHP-RD-FORCE !"
    )
    for borrowed in (
        "_RTHP-RD-FRONT",
        "_RTHP-RD-BACK",
        "_RTHP-RD-CELL-DAMAGE-A",
        "_RTHP-RD-CELL-DAMAGE-U",
    ):
        assert f"0 {borrowed} !" in cleanup
    assert damage.count("SCR-WITH-FRAME-PLANES") == 1
    assert dispatcher.index("_RTHP-BUILD-GLYPHS-DAMAGE?") < dispatcher.index(
        "_RTHP-BUILD-GLYPHS-FULL?"
    )


def test_native_semantic_targets_are_built_once_into_the_inactive_bounded_bank() -> None:
    source = _source()
    sizing = _word(source, "_RTHP-BYTES-BODY")
    target_sizing = _word(source, "_RTHP-TARGET-BYTES-CALC")
    layout = _word(source, "_RTHP-LAYOUT")
    build = _word(source, "_RTHP-TARGET-CANDIDATE?")
    candidate_shape = _word(source, "_RTHP-CT-CANDIDATE-SHAPE?")
    find_control = _word(source, "_RTHP-CT-FIND-CONTROL?")
    control = _word(source, "_RTHP-CT-CONTROL?")
    target_control = _word(source, "_RTHP-CT-TARGET?")
    correlation_at = _word(source, "_RTHP-CT-CORRELATION-AT?")
    correlation = _word(source, "_RTHP-CT-CORRELATION?")
    record = _word(source, "_RTHP-CT-RECORD?")
    geometry = _word(source, "_RTHP-CT-GEOMETRY?")
    append = _word(source, "_RTHP-TG-APPEND-CURRENT?")
    collection_correlation_at = _word(
        source, "_RTHP-CT-COLLECTION-CORRELATION-AT?"
    )
    collection_correlation = _word(
        source, "_RTHP-CT-COLLECTION-CORRELATION?"
    )
    collection_control = _word(
        source, "_RTHP-CT-COLLECTION-CONTROL-AT?"
    )
    attachment = _word(source, "_RTHP-CT-ATTACHMENT?")
    text_span = _word(source, "_RTHP-CT-TEXT-SPAN?")
    tabset = _word(source, "_RTHP-CT-TABSET?")
    tab = _word(source, "_RTHP-CT-TAB?")
    collection_targets = _word(source, "_RTHP-TG-COLLECTION-TARGETS?")
    prepare = _word(source, "_RTHP-PREPARE-START")

    assert _constant(source, "_RTHP-TARGET-BANK-HEADER-SIZE") == 216
    assert _offset(source, "_RTHP-TB.INSTRUMENT-REGION-COUNT") == 176
    assert _offset(source, "_RTHP-TB.INSTRUMENT-COUNT") == 184
    assert _offset(source, "_RTHP-TB.INSTRUMENT-UNIT-BYTES") == 192
    assert _offset(source, "_RTHP-TB.VALID") == 200
    assert _offset(source, "_RTHP-TB.DOCUMENT-COUNT") == 208
    assert "CONSTANT _RTHP-TARGET-VALID-MAGIC" in source
    for retained_family in (
        "_RTHP-TARGET-BANK-HEADER-SIZE",
        "_RTHP-TBS-TARGETS @ _RTHP-TARGET-ENTRY-SIZE",
        "_RTHP-TBS-CONTROLS @ RTE-CONTROL-SIZE",
        "_RTHP-TBS-CONTROLS @ RUCP-CORRELATION-SIZE",
        "_RTHP-TBS-CONTROL-BYTES @ _RTHP-ALIGN8?",
        "_RTHP-TBS-CELLS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE",
        "_RTHP-TBS-CELLS @ RGRP-TEXT-REF-SIZE",
        "_RTHP-TBS-CELLS @ 4 _RTHP-U32*?",
    ):
        assert retained_family in target_sizing
    assert sizing.count("_RTHP-TARGET-BYTES-CALC") == 1
    assert "_RTHP-B-CONTROLS @ _RTHP-B-CONTROLS @" in sizing
    assert "DUP _RTHP-B-TARGET-BYTES ! _RTHP-B-ADD" in sizing
    assert "_RTHP-B-TARGET-BYTES @ _RTHP-B-ADD" in sizing
    assert layout.count("_RTHP-TARGET-BANK-BYTES?") == 2
    assert layout.count("_RTHP.TARGET0-A") == 1
    assert layout.count("_RTHP.TARGET1-A") == 1
    assert "_RTHP-TARGET-INACTIVE" in build
    assert "_RTHP.TARGET-PENDING" in build
    assert "_RTHP-CT-CANDIDATE-SHAPE?" in build
    assert "0 ?DO" not in build
    assert build.count("BEGIN") == 2
    assert "0 ?DO" not in correlation_at
    assert "0 ?DO" not in find_control
    assert "_RTHP.FIRST-OBJECT" in find_control
    assert "_RTHP.CONTROLS-A" in find_control
    assert build.index("_RTHP-CT-CORRELATION-AT?") < build.index(
        "_RTHP-CT-FIND-CONTROL?"
    )
    assert candidate_shape.count("_RTHP-ARENA-SPAN?") == 4
    assert candidate_shape.count("@ 7 AND IF 0 EXIT THEN") == 4
    assert "DUP 7 AND" not in candidate_shape
    for bounded_bank in (
        "_RTHP.SOURCE-DIR-A",
        "_RTHP.SOURCE-RECS-A",
        "_RTHP.CONTROLS-A",
        "_RTHP.CORR-A",
    ):
        assert candidate_shape.count(bounded_bank) == 2
        assert (
            f"_RTHP-CT-P @ {bounded_bank} @\n"
            "        _RTHP-CT-BYTES @ _RTHP-CT-P @ _RTHP-ARENA-SPAN?"
        ) in candidate_shape
    assert "RTE-CONTROL-MENU" in target_control
    assert "RTE-CONTROL-MENU-ITEM" in target_control
    assert "RTE-CONTROL-TAB" in target_control
    assert "RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR" in target_control
    for exact in (
        "_RTE-CONTROL.OWNER",
        "_RTE-CONTROL.GENERATION",
        "_RTE-CONTROL.ID",
    ):
        assert exact in control
    assert "RTE-CONTROL-MENU-BAR" in control
    assert "RTE-CONTROL-TAB U> 0=" in control

    assert "RUCP-CORRELATION-CONTROL-ID@" in correlation_at
    assert "RUCP-CORRELATION-ATTACHMENT@" in correlation
    assert "_RTHP-CT-ATTACHMENT" in correlation
    assert "RUCP-CORRELATION-SOURCE@" in correlation
    assert "RUCP-CORRELATION-SUBKEY@" in correlation
    record_at = _word(source, "_RTHP-CT-RECORD-AT?")
    document_shape = _word(source, "_RTHP-CT-DOCUMENT-SHAPE?")
    assert "_RTHP.SOURCE-RECS-A" in record_at
    assert "_RTHP-CT-LOCAL" in record_at
    assert "RUHA-DOCUMENT-TOKEN@" in document_shape
    assert "RUHA-DOCUMENT-RECORD-OFFSET@" in document_shape
    assert "RUHA-DOCUMENT-TEXT-OFFSET@" in document_shape
    compact_document_shape = " ".join(document_shape.split())
    assert (
        "_RTHP-CT-DOC-RECORD-U @ 0= _RTHP-CT-DOCUMENT @ "
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ 0= <> IF 0 EXIT THEN"
        in compact_document_shape
    )
    assert (
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ "
        "_RTHP-CT-P @ _RTHP.SOURCE-GEN @ U> IF 0 EXIT THEN"
        in compact_document_shape
    )
    assert (
        "RUHA-DOCUMENT-MENU-TOPOLOGY-EPOCH@ _RTHP-CT-DOCUMENT @ "
        "RUHA-DOCUMENT-MENU-EPOCH@ U> IF 0 EXIT THEN"
        in compact_document_shape
    )
    assert "UMSN-RECORD-GENERATION@" in record
    assert "UMSN-RECORD-SOURCE-INDEX@" in record
    assert "_UMSN-R.SOURCE" in record
    assert "UMSN-F-PAINTABLE" not in record
    assert "UMSN-RECORD-RESOLVED" not in record
    assert "UTUI-RESOLVED-VALID?" not in record
    assert "UMSN-RECORD-RESOLVED" in geometry
    assert "UTUI-RESOLVED-VALID?" in geometry
    assert "_RTE-CONTROL.ROW" not in geometry
    assert "_RTE-CONTROL.COL" not in geometry
    assert "_RTHP.ROWS" in geometry
    assert "_RTHP.COLS" in geometry
    for metadata in (
        "_RTHP-TB.OWNER",
        "_RTHP-TB.GENERATION",
        "_RTHP-TB.COLS",
        "_RTHP-TB.ROWS",
        "_RTHP-TB.COUNT",
        "_RTHP-TB.DRAW",
    ):
        assert metadata in build
    assert "_RTHP.SURFACE-GEN @" in build
    for entry in ("_RTHP-TE.ID", "_RTHP-TE.ROW", "_RTHP-TE.COL"):
        assert entry in append
    assert "UMSN-F-PAINTABLE" in build
    assert build.index("_RTHP-CT-DOCUMENT-SHAPE?") < build.index(
        "_RTHP-CT-CORRELATION-AT?"
    )
    assert build.index("_RTHP-CT-RECORD-AT?") < build.index(
        "_RTHP-CT-RECORD?"
    )
    assert prepare.index("_RTHP-FIXED?") < prepare.index(
        "_RTHP-TARGET-CANDIDATE?"
    ) < prepare.index("RTE-RETAINED-BEGIN")
    assert "_RTHP-TARGET-CONTROL?" not in _word(source, "_RTHP-EMIT-CONTROLS")

    # Collection controls occupy the exact suffix after menu controls.  Every
    # correlation is rebound to one copied document and its sealed control;
    # no live UIDL/widget lookup participates in point derivation.
    assert "_RTHP.MENU-CONTROL-COUNT" in collection_correlation_at
    assert "_RTHP.CONTROL-COUNT" in collection_correlation_at
    assert "_RTHP-CT-COLLECTION-CORRELATION-AT?" in collection_control
    assert "_RTHP-CT-FIND-CONTROL?" in collection_control
    assert "_RTHP-COLLECTION-CONTROL-KIND?" in collection_control
    assert "_RTHP-CT-COLLECTION-CORRELATION?" in collection_control
    assert "_RTHP.DOCUMENT-COUNT" in attachment
    assert "RUHA-DOCUMENT-TOKEN@" in attachment
    assert "_RTHP-CT-DOC-MATCHES @ 1 =" in attachment
    for exact_correlation in (
        "RUCP-CORRELATION-ATTACHMENT@",
        "RUCP-CORRELATION-SOURCE@",
        "RUCP-CORRELATION-INDEX@",
        "RUCP-CORRELATION-SUBKEY@",
        "RUCP-CORRELATION-LIFECYCLE-GENERATION@",
        "RUCP-CORRELATION-CONTROL-ID@",
    ):
        assert exact_correlation in collection_correlation
    assert "_RTHP.SOURCE-TEXT-A" in text_span
    assert "_RTHP.SOURCE-TEXT-USED" in text_span
    assert "MSPAN-NONWRAPPING?" in text_span

    # TABSET supplies the exact header bounds and correlation tuple. Visible
    # children compact left-to-right; visible disabled children still consume
    # layout width, while invisible children do not. A clipped label start is
    # a valid non-target rather than a candidate failure.
    for root_proof in (
        "RTE-CONTROL-TABSET",
        "_RTE-CONTROL.PARENT @",
        "_RTE-CONTROL.ORDER @",
        "_RTE-CONTROL.ROW @",
        "_RTE-CONTROL.HEIGHT @",
        "_RTE-CONTROL.COL @",
        "_RTE-CONTROL.WIDTH @",
        "_RTHP-U32+?",
        "_RTHP.ROWS @",
        "_RTHP.COLS @",
        "RUCP-CORRELATION-ATTACHMENT@",
        "RUCP-CORRELATION-INDEX@",
        "RUCP-CORRELATION-LIFECYCLE-GENERATION@",
    ):
        assert root_proof in tabset
    for child_proof in (
        "RTE-CONTROL-TAB",
        "_RTE-CONTROL.PARENT @",
        "RUCP-CORRELATION-ATTACHMENT@",
        "RUCP-CORRELATION-INDEX@",
        "RUCP-CORRELATION-LIFECYCLE-GENERATION@",
        "_RTE-CONTROL.LABEL-A @",
        "_RTE-CONTROL.LABEL-U @",
        "_RTE-CONTROL.SHORTCUT-A @",
        "_RTE-CONTROL.SHORTCUT-U @",
        "_RTHP-CT-TEXT-SPAN?",
    ):
        assert child_proof in tab
    invisible = "_RTE-CONTROL.STATE @ RTE-CONTROL-VISIBLE AND 0= IF"
    assert tab.index(invisible) < tab.index("_RTHP-CT-TAB-POS @ _RTHP-CT-COL !")
    assert tab.index("_RTHP-CT-TAB-NEXT @ _RTHP-CT-TAB-POS !") < tab.index(
        "_RTHP-CT-TARGET?"
    )
    assert "_RTHP-CT-TAB-ROOT-STATE" in tab
    assert "_RTHP-CT-TAB-ROOT-END @ U< 0= IF\n        0 -1 EXIT" in tab
    assert "_RTHP.MENU-CONTROL-COUNT" in collection_targets
    assert "_RTHP.CONTROL-COUNT" in collection_targets
    assert "_RTHP-TEXT-COLLECTION-CONTROL-KIND?" in collection_targets
    assert "_RTHP-CT-TABSET?" in collection_targets
    assert "_RTHP-CT-TAB?" in collection_targets
    assert "_RTHP-TG-APPEND-CURRENT?" in collection_targets
    assert build.index("_RTHP-TG-COLLECTION-TARGETS?") < build.rindex(
        "_RTHP-TB.COUNT !"
    )
    sealed_tab_slice = "\n".join(
        (
            collection_correlation_at,
            collection_correlation,
            collection_control,
            attachment,
            text_span,
            tabset,
            tab,
            collection_targets,
        )
    )
    for forbidden_live_lookup in (
        "TAB-HIT-INDEX",
        "TAB-INSTANCE@",
        "UIDL-ELEM",
        "WDG-",
    ):
        assert forbidden_live_lookup not in sealed_tab_slice

    assert _tab_point_oracle(
        root_row=4,
        root_col=10,
        root_width=10,
        root_actionable=True,
        tabs=(
            (101, 3, True, True),
            (102, 20, False, True),
            (103, 2, True, False),
            (104, 1, True, True),
        ),
    ) == ((101, 4, 11),)
    assert _tab_point_oracle(
        root_row=4,
        root_col=10,
        root_width=11,
        root_actionable=True,
        tabs=(
            (101, 3, True, True),
            (102, 20, False, True),
            (103, 2, True, False),
            (104, 1, True, True),
        ),
    ) == ((101, 4, 11), (104, 4, 20))
    assert not _tab_point_oracle(
        root_row=4,
        root_col=10,
        root_width=11,
        root_actionable=False,
        tabs=((101, 3, True, True),),
    )


def test_ack_baseline_has_complete_caller_bounded_storage_and_required_pack() -> None:
    source = _source()
    sizing = _word(source, "_RTHP-BYTES-BODY")
    target_sizing = _word(source, "_RTHP-TARGET-BYTES-CALC")
    layout = _word(source, "_RTHP-LAYOUT")
    candidate = _word(source, "_RTHP-TARGET-CANDIDATE?")
    pack_layout = _word(source, "_RTHP-PK-LAYOUT?")
    assert (
        "_RTHP-TB.ROWS @ _RTHP-U32*?\n        0= IF 2DROP 0 EXIT THEN U>"
        in pack_layout
    )
    pack_begin = _word(source, "_RTHP-PK-BEGIN?")
    pack_copy = _word(source, "_RTHP-PK-COPY?")
    checked_pack = _word(source, "_RTHP-PACK-CANDIDATE")
    admitted_pack = _word(source, "_RTHP-PACK-ADMITTED-CANDIDATE")
    target_abort = _word(source, "_RTHP-TARGET-ABORT")
    unchanged_finish = _word(source, "_RTHP-U-FINISH")
    unchanged_clone = _word(source, "_RTHP-U-CLONE?")
    unchanged_commit = _word(source, "_RTHP-U-COMMIT")
    prepare_start = _word(source, "_RTHP-PREPARE-START")
    stage_live = _word(source, "_RTHP-STAGE-LIVE-CANDIDATE")
    validate = _word(source, "_RTHP-PACKED-BANK?")

    # Each inactive/active bank has a complete caller-bounded retained
    # capacity. Actual point targets consume only their semantic prefix;
    # all controls, correlations, text, glyph items/references, and glyph text
    # remain representable without borrowing an opportunistic arena tail.
    for retained_family in (
        "_RTHP-TARGET-BANK-HEADER-SIZE",
        "_RTHP-TBS-TARGETS @ _RTHP-TARGET-ENTRY-SIZE",
        "_RTHP-TBS-CONTROLS @ RTE-CONTROL-SIZE",
        "_RTHP-TBS-CONTROLS @ RUCP-CORRELATION-SIZE",
        "_RTHP-TBS-CONTROL-BYTES @ _RTHP-ALIGN8?",
        "_RTHP-TBS-CELLS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE",
        "_RTHP-TBS-CELLS @ RGRP-TEXT-REF-SIZE",
        "_RTHP-TBS-CELLS @ 4 _RTHP-U32*?",
    ):
        assert retained_family in target_sizing
    assert sizing.count("_RTHP-TARGET-BYTES-CALC") == 1
    assert "DUP _RTHP-B-TARGET-BYTES ! _RTHP-B-ADD" in sizing
    assert "_RTHP-B-TARGET-BYTES @ _RTHP-B-ADD" in sizing
    assert layout.count("_RTHP-TARGET-BANK-BYTES?") == 2
    assert "_RTHP-TB.COUNT @ _RTHP-TARGET-ENTRY-SIZE" in pack_layout
    assert "_RTHP-TB.MENU-CONTROL-COUNT" in pack_layout
    assert "_RTHP-TB.CONTROL-COUNT" in pack_layout
    assert "_RTHP-PK-PREFIX" in pack_layout

    # PACKED-BYTES is an exact payload length, not the validity certificate:
    # an instrument-only target has authoritative metadata and zero payload.
    # The dedicated magic is cleared before any fallible construction and is
    # published last only after copy/rebase succeeds.
    assert candidate.index(
        "0 _RTHP-TG-BANK @ _RTHP-TB.VALID !"
    ) < candidate.index(
        "_RTHP-TB.OWNER !"
    )
    assert pack_begin.index(
        "0 _RTHP-PK-BANK @ _RTHP-TB.VALID !"
    ) < pack_begin.index(
        "0 _RTHP-PK-BANK @ _RTHP-TB.PACKED-BYTES !"
    ) < pack_begin.index(
        "_RTHP-PK-LAYOUT?"
    )
    assert "_RTHP-PK-SOURCE-SPANS?" in pack_begin
    assert "_RTHP-PACK-ADMITTED-CANDIDATE" in candidate
    assert candidate.index("_RTHP-PACK-ADMITTED-CANDIDATE") < candidate.index(
        "_RTHP.TARGET-PENDING !"
    )
    pack_branch = candidate[candidate.index("_RTHP-PACK-ADMITTED-CANDIDATE") :]
    assert "0= IF _RTHP-TG-FAIL EXIT THEN" in pack_branch
    assert (
        "OVER _RTHP-TB.VALID @ _RTHP-TARGET-VALID-MAGIC <> IF"
        in validate
    )
    assert "2DROP 0 _RTHP-PK-FINISH EXIT" in validate
    zero_payload = validate[validate.index("_RTHP-PK-TOTAL @ 0= IF") :]
    zero_payload = zero_payload[: zero_payload.index("THEN\n    THEN")]
    assert "_RTHP-TB.INSTRUMENT-COUNT @ 0= IF" in zero_payload
    assert (
        pack_copy.index("_RTHP-TB.PACKED-BYTES !")
        < pack_copy.index("_RTHP-TARGET-VALID-MAGIC")
        < pack_copy.index("_RTHP-TB.VALID !")
    )

    # Abort/failure invalidates every reachable pending bank.  The unchanged
    # clone clears copied magic immediately after MOVE and republishes it only
    # after all rebasing/fence work, directly before TARGET-PENDING.
    assert "?DUP IF\n        0 SWAP _RTHP-TB.VALID !" in target_abort
    assert "?DUP IF 0 SWAP _RTHP-TB.VALID ! THEN" in unchanged_finish
    assert unchanged_clone.index(" MOVE") < unchanged_clone.index(
        "0 _RTHP-U-PENDING @ _RTHP-TB.VALID !"
    ) < unchanged_clone.index("_RTHP-U-REBASE-CONTROLS?")
    assert unchanged_commit.index(
        "_RTHP-TARGET-VALID-MAGIC _RTHP-U-PENDING @ _RTHP-TB.VALID !"
    ) < unchanged_commit.index("_RTHP.TARGET-PENDING !")

    # Ordinary target packing is reached only after the exact preflight
    # admission has been rebound.  It reuses that glyph-reference proof,
    # whereas the post-admission tombstone mutation keeps the checked entry.
    assert prepare_start.index("_RTHP-FIXED?") < prepare_start.index(
        "_RTHP-TARGET-CANDIDATE?"
    )
    assert stage_live.index("_RTHP-FIXED?") < stage_live.index(
        "_RTHP-TARGET-CANDIDATE?"
    )
    assert checked_pack.index("_RTHP-PK-BEGIN?") < checked_pack.index(
        "_RTHP-PK-REFS?"
    ) < checked_pack.index("_RTHP-PK-COPY?")
    assert admitted_pack.index("_RTHP-PK-BEGIN?") < admitted_pack.index(
        "_RTHP-PK-COPY?"
    )
    assert "_RTHP-PK-REFS?" not in admitted_pack
    assert (
        "_RTHP-D-PENDING @ _RTHP-D-P @ _RTHP-PACK-CANDIDATE 0= IF"
        in source
    )
    assert source.count("_RTHP-PK-REFS?") == 2
    assert source.count("_RTHP-PACK-ADMITTED-CANDIDATE") == 2
    assert source.count("_RTHP-PACK-CANDIDATE") == 2

    # Both packing entries share the exact copy/rebase implementation, including the
    # deterministic padding clear, exact payload length, and validity magic.
    assert pack_copy.count(" FILL") == 1
    assert pack_copy.count(" MOVE") == 7
    assert "_RTHP-PK-CONTROL-REBASE?" in pack_copy
    assert "_RTHP-TB.PACKED-BYTES !" in pack_copy
    assert "_RTHP-TB.VALID !" in pack_copy
    for wrapper in (checked_pack, admitted_pack):
        assert " FILL" not in wrapper
        assert " MOVE" not in wrapper
        assert "_RTHP-PK-CONTROL-REBASE?" not in wrapper


def test_only_an_exactly_acknowledged_target_bank_becomes_input_active() -> None:
    source = _source()
    sealed = _word(source, "_RTHP-STEP-SEALED")
    step = _word(source, "RTHP-STEP")
    publish = _word(source, "_RTHP-TARGET-PUBLISH?")
    lookup = _word(source, "RTHP-CONTROL-TARGET@")
    header = _word(source, "_RTHP-TARGET-BANK-HEADER?")
    entries = _word(source, "_RTHP-TARGET-BANK-ENTRIES?")
    find = _word(source, "_RTHP-TARGET-BANK-FIND?")
    live = _word(source, "RTHP-LIVE?")

    accepted = "_RTHP-Z-ACCEPT @ _RTHP-Z-P @ _RTHP.PHASE !"
    exact_ack = (
        "_RTHP-S-STATE @ RTE-UPDATE-IDLE =\n"
        "    _RTHP-S-STATUS @ RTE-S-OK = AND IF"
    )
    assert sealed.index(exact_ack) < sealed.index(accepted) < sealed.index(
        "_RTHP-TARGET-PUBLISH?"
    )
    assert "_RTHP-PH-LIVE = IF" in sealed
    delta_sealed = step[step.index("_RTHP-PH-DELTA-SEALED = IF") :]
    delta_sealed = delta_sealed[: delta_sealed.index("_RTHP-PH-LIVE = IF")]
    assert "_RTHP-PH-LIVE" in delta_sealed
    assert "_RTHP-STEP-SEALED" in delta_sealed
    assert "_RTHP.TARGET-PENDING" in publish
    assert publish.index("_RTHP-TARGET-BANK-ENTRIES?") < publish.index(
        "_RTHP.TARGET-ACTIVE !"
    )
    assert publish.index("_RTHP.TARGET-PENDING !") < publish.index(
        "_RTHP.TARGET-ACTIVE !"
    )
    assert publish.index("_RTHP-TB.DRAW @") < publish.index(
        "_RTHP.SURFACE-GEN @"
    ) < publish.index("_RTHP-TARGET-BANK-ENTRIES?")
    assert publish.rindex("_RTHP-TB.DRAW @") < publish.index(
        "_RTHP.ACTIVE-DRAW !"
    ) < publish.index("_RTHP.TARGET-ACTIVE !")
    assert source.count("_RTHP.ACTIVE-DRAW !") == 2

    assert "_RTHP.TARGET-ACTIVE" in lookup
    assert "_RTHP-TARGET-BANK-HEADER?" in lookup
    assert "_RTHP-TARGET-BANK-FIND?" in lookup
    assert "_RTHP.PHASE" not in lookup
    assert "_RTHP.OWNER" in lookup
    assert "_RTHP.OWNER-GEN" in lookup
    assert "_RTHP.ACTIVE-DRAW" in lookup
    assert "RTHP-CONTROL-MENU-TARGET@" not in source
    assert "_RTHP.TARGET-ACTIVE" in live
    assert "_RTHP.PHASE" not in live
    assert entries.count("0 ?DO") == 1
    assert find.count("0 ?DO") == 1
    assert "_RTHP-TL-MATCHES @ 1 =" in find
    for candidate_bank in (
        "_RTHP.SOURCE-RECS-A",
        "_RTHP.CONTROLS-A",
        "_RTHP.CORR-A",
        "_RTHP.ADMISSION",
    ):
        assert candidate_bank not in lookup + header + find
    for metadata in (
        "_RTHP-TB.OWNER",
        "_RTHP-TB.GENERATION",
        "_RTHP-TB.COLS",
        "_RTHP-TB.ROWS",
        "_RTHP-TB.COUNT",
        "_RTHP-TB.DRAW",
    ):
        assert metadata in lookup + header + find


def test_repeat_capacity_pressure_preserves_the_active_frame_and_backpressures_cell() -> None:
    rebuild = _word(_source(), "_RTHP-REBUILD-CANDIDATE")

    for temporary_status in (
        "RTE-S-WOULD-BLOCK",
        "RTE-S-UNAVAILABLE",
        "RTE-S-CAPACITY",
    ):
        branch = rebuild[rebuild.index(f"DUP {temporary_status} = IF") :]
        branch = branch[: branch.index("EXIT THEN")]
        assert "SCB-S-WOULD-BLOCK 0" in branch


def test_content_epoch_is_carried_by_candidates_ack_targets_and_retry_plans() -> None:
    source = _source()
    copy = _word(source, "_RTHP-COPY-SNAPSHOT?")
    current = _word(source, "_RTHP-DRAW-CURRENT?")
    target = _word(source, "_RTHP-TARGET-CANDIDATE?")
    header = _word(source, "_RTHP-TARGET-BANK-HEADER?")
    publish = _word(source, "_RTHP-TARGET-PUBLISH?")
    bind = _word(source, "_RTHP-D-BIND?")
    seal = _word(source, "_RTHP-D-PLAN-SEAL")
    plan_bind = _word(source, "_RTHP-D-PLAN-BIND?")
    clear = _word(source, "_RTHP-DELTA-PLAN-CLEAR")

    assert "RUHA-SNAPSHOT-CONTENT-EPOCH@" in copy
    assert "_RTHP.SOURCE-CONTENT-EPOCH !" in copy
    assert "RUHA-SNAPSHOT-CONTENT-EPOCH@" in current
    assert "_RTHP.SOURCE-CONTENT-EPOCH @ = AND" in current
    assert "_RTHP-TB.CONTENT-EPOCH !" in target
    for verifier in (header, publish, bind):
        assert "_RTHP-TB.CONTENT-EPOCH" in verifier
    assert "_RTHP.DELTA-PLAN-PENDING-CONTENT !" in seal
    assert "_RTHP.DELTA-PLAN-ACTIVE-CONTENT !" in seal
    assert "_RTHP.DELTA-PLAN-PENDING-CONTENT @" in plan_bind
    assert "_RTHP.DELTA-PLAN-ACTIVE-CONTENT @" in plan_bind
    assert "_RTHP.DELTA-PLAN-VALID 88 0 FILL" in clear
    assert _offset(source, "_RTHP-TB.CONTENT-EPOCH") == 128


def test_exact_reuse_fast_path_rejects_each_missing_certificate_dimension() -> None:
    assert _exact_reuse_oracle(_ExactReuseFacts())
    for field in vars(_ExactReuseFacts()):
        rejected = replace(_ExactReuseFacts(), **{field: False})
        assert not _exact_reuse_oracle(rejected), field


def test_exact_reuse_fast_path_is_ack_bound_zero_damage_and_fail_closed() -> None:
    source = _source()
    active = _word(source, "_RTHP-U-ACTIVE?")
    snapshot = _word(source, "_RTHP-U-SNAPSHOT?")
    clone = _word(source, "_RTHP-U-CLONE?")
    rebase = _word(source, "_RTHP-U-REBASE-CONTROLS?")
    fence = _word(source, "_RTHP-U-FENCE-PLAN?")
    zero = _word(source, "_RTHP-U-ZERO-DAMAGE?")
    planes = _word(source, "_RTHP-U-PLANE-BODY?")
    callback = _word(source, "_RTHP-U-IN-PLANES")
    screen = _word(source, "_RTHP-U-SCREEN?")
    commit = _word(source, "_RTHP-U-COMMIT")
    candidate = _word(source, "_RTHP-UNCHANGED-CANDIDATE?")
    stage = _word(source, "_RTHP-STAGE-LIVE-CANDIDATE")
    prepare = _word(source, "_RTHP-PREPARE-LIVE")

    # The baseline is the bank published only after an exact physical ACK.
    for proof in (
        "_RTHP-PH-LIVE",
        "_RTHP.TARGET-PENDING",
        "_RTHP.TARGET-ACTIVE",
        "_RTHP-TARGET-BANK-HEADER?",
        "_RTHP-TARGET-BANK-ENTRIES?",
        "_RTHP-TB.INSTRUMENT-COUNT",
        "_RTHP-TB.OWNER",
        "_RTHP-TB.GENERATION",
        "_RTHP-TB.COLS",
        "_RTHP-TB.ROWS",
        "_RTHP-TB.PHYSICAL-GEN",
        "_RTHP-TB.REGION",
        "_RTHP-TB.FIRST-OBJECT",
        "_RTHP-TB.CONTROL-COUNT",
        "_RTHP-TB.GLYPH-SLOT-COUNT",
        "_RTHP-TB.SOURCE-TEXT-USED",
        "_RTHP-TB.GLYPH-TEXT-USED",
        "_RTHP-TB.DRAW",
        "_RTHP.ACTIVE-DRAW",
        "_RTHP.SOURCE-DRAW",
        "_RTHP.SURFACE-GEN",
        "_RTHP-TB.SOURCE-GEN",
        "_RTHP-TB.CONTENT-EPOCH",
        "_RTHP.SOURCE-CONTENT-EPOCH",
    ):
        assert proof in active
    assert "RTE-LIMITS@" in active
    assert "RTE-LIMITS-SIZE COMPARE" in active
    assert "RTE-LIMITS-GLYPH-RUN-BYTES@" in active

    # RUHA supplies an exact nonzero epoch for a newer draw and the snapshot
    # keeps document cardinality and attempt arithmetic bound to the candidate.
    for proof in (
        "SCR-DRAW-GENERATION@",
        "RUHA-SNAPSHOT-FOR@",
        "RUHA-SNAPSHOT-DRAW-GENERATION@",
        "RUHA-SNAPSHOT-GENERATION@",
        "RUHA-SNAPSHOT-CONTENT-EPOCH@",
        "_RTHP-TB.CONTENT-EPOCH",
        "RUHA-SNAPSHOT-DOCUMENT-COUNT@",
        "_RTHP.DOCUMENT-COUNT",
        "_RTHP-U32+?",
    ):
        assert proof in snapshot

    # Only the checked used prefix is cloned; pointer-bearing packed controls
    # are rebased from the active source-text span into the inactive one.
    assert "_RTHP-TARGET-BANK-BYTES?" in clone
    assert "_RTHP-U32*?" in clone and clone.count("_RTHP-U32+?") == 2
    assert "_RTHP-ARENA-SPAN?" in clone
    assert "MSPAN-OVERLAP?" in clone
    assert clone.index(" MOVE") < clone.index("_RTHP-TB.DRAW !")
    assert "_RTHP-TB.SOURCE-GEN !" in clone
    assert "_RTHP-TB.CONTENT-EPOCH !" in clone
    assert "_RTHP-U-REBASE-CONTROLS?" in clone
    assert rebase.count("_RTHP-U-TEXT-REBASE?") == 3
    assert "_RTE-CONTROL.LABEL-A !" in rebase
    assert "_RTE-CONTROL.SHORTCUT-A !" in rebase
    assert "_RTE-CONTROL.CONTENT-A !" in rebase

    # The clone uses the existing compact DELTA representation but writes one
    # direct control-or-glyph ordinal.  Rebuilding the full target map merely
    # to choose an idempotent revision carrier would retain an avoidable scan
    # in the shortcut itself.
    for reused in (
        "_RTHP-D-PLAN-START?",
        "_RTHP-D-PLAN-CONTROLS",
        "_RTHP-D-PLAN-GLYPHS",
        "_RTHP.ORDER2-A",
        "_RTHP.GLYPH-ID-MAP-A",
    ):
        assert reused in fence
    for avoided_scan in (
        "_RTHP-D-TARGETS-NORMALIZABLE?",
        "_RTHP-D-BUILD-SLOT-MAP?",
        "_RTHP-D-PLAN-REVISION-FENCE?",
        "_RTHP-D-PLAN-COMPACT-GLYPHS",
    ):
        assert avoided_scan not in fence
    assert "_RTHP-DELTA-CANDIDATE?" not in candidate

    # The admitted screen proof is exact: no FORCE, same dimensions, active
    # FRONT-DRAW, current DRAW, a complete nonwrapping row map, and every byte
    # zero.  The snapshot is rechecked and committed inside that borrow.
    assert "_RTHP-U-FORCE @ IF 0 EXIT THEN" in planes
    assert "_RTHP-U-COLS" in planes and "_RTHP-U-ROWS" in planes
    assert "_RTHP-U-FRONT-DRAW" in planes
    assert "_RTHP.ACTIVE-DRAW" in planes
    assert "_RTHP-U-PLANE-DRAW" in planes
    assert "_RTHP-U-ZERO-DAMAGE?" in planes
    assert planes.index("_RTHP-U-SNAPSHOT-CURRENT?") < planes.index(
        "_RTHP-U-COMMIT"
    )
    assert "_RTHP-U-DAMAGE-A @ 0= IF 0 EXIT THEN" in zero
    assert "_RTHP-U-DAMAGE-U @ _RTHP-U-ROWS @ <>" in zero
    assert "MSPAN-NONWRAPPING?" in zero
    assert "C@ IF 0 EXIT THEN" in zero
    assert "front-a back-a cols rows front-draw draw force?" in callback
    assert "SCR-WITH-FRAME-PLANES" in _word(source, "_RTHP-U-SCREEN-CALL")
    assert "CATCH" in screen

    # TARGET-PENDING and the attempt/draw metadata become authoritative only
    # after all fallible proofs.  PLAN-SEAL then publishes VALID last.
    assert commit.index("_RTHP.SOURCE-GEN !") < commit.index(
        "_RTHP.TARGET-PENDING !"
    ) < commit.index("_RTHP-D-PLAN-SEAL")
    assert candidate.index("_RTHP-U-ACTIVE?") < candidate.index(
        "_RTHP-U-SNAPSHOT?"
    ) < candidate.index("_RTHP-U-CLONE?") < candidate.index(
        "_RTHP-U-FENCE-PLAN?"
    ) < candidate.index("_RTHP-U-SCREEN?")
    assert stage.index("_RTHP-UNCHANGED-CANDIDATE?") < stage.index(
        "_RTHP-REBUILD-CANDIDATE"
    )
    unchanged_branch = prepare[prepare.index("_RTHP-STAGE-UNCHANGED = IF") :]
    unchanged_branch = unchanged_branch[: unchanged_branch.index("THEN")]
    assert "_RTHP-PREPARE-DELTA" in unchanged_branch
    assert "_RTHP-DELTA-CANDIDATE?" not in unchanged_branch


def test_ack_target_clone_byte_oracle_changes_only_revision_and_local_pointers() -> None:
    active = bytearray((index * 37 + 11) & 0xFF for index in range(400))
    active_source_base = 0x1000
    pending_source_base = 0x4000
    source_bytes = 64
    struct.pack_into("<Q", active, 40, 91)
    struct.pack_into("<Q", active, 48, 17)
    struct.pack_into("<Q", active, 128, 13)
    # With no point-target entries, the first packed 192-byte CONTROL starts
    # at the 216-byte target header.  Rebase LABEL, SHORTCUT, and CONTENT.
    struct.pack_into("<Q", active, 336, active_source_base + 9)
    struct.pack_into("<Q", active, 344, 7)
    struct.pack_into("<Q", active, 352, 0)
    struct.pack_into("<Q", active, 360, 0)
    struct.pack_into("<Q", active, 368, active_source_base + 24)
    struct.pack_into("<Q", active, 376, 11)
    frozen_active = bytes(active)

    pending = _clone_bank_oracle(
        frozen_active,
        draw=92,
        source_generation=18,
        content_epoch=13,
        active_source_base=active_source_base,
        pending_source_base=pending_source_base,
        source_bytes=source_bytes,
        text_fields=((336, 344), (352, 360), (368, 376)),
    )
    assert bytes(active) == frozen_active
    assert struct.unpack_from("<Q", pending, 40)[0] == 92
    assert struct.unpack_from("<Q", pending, 48)[0] == 18
    assert struct.unpack_from("<Q", pending, 128)[0] == 13
    assert struct.unpack_from("<Q", pending, 336)[0] == pending_source_base + 9
    assert struct.unpack_from("<Q", pending, 352)[0] == 0
    assert struct.unpack_from("<Q", pending, 368)[0] == pending_source_base + 24

    mutable_expected = bytearray(frozen_active)
    for start in (40, 48, 128, 336, 352, 368):
        mutable_expected[start : start + 8] = pending[start : start + 8]
    assert pending == bytes(mutable_expected)
