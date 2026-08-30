"""Seconds-only structural locks for the neutral screen publisher bridge."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CORE_SCREEN = ROOT / "akashic" / "tui" / "screen.f"
DRAW = ROOT / "akashic" / "tui" / "draw.f"
SCREEN = ROOT / "akashic" / "tui" / "screen-backend-apt1.f"
ENGINE = ROOT / "akashic" / "tui" / "rich-terminal" / "apt1-engine.f"
BRIDGE = ROOT / "akashic" / "tui" / "rich-terminal" / "screen-adapter-apt1.f"
SHELL = ROOT / "akashic" / "tui" / "app-shell-apt1.f"
APP_SHELL = ROOT / "akashic" / "tui" / "app-shell.f"
APPLET_HOST = ROOT / "akashic" / "tui" / "applet-host" / "host.f"


def _definition(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$", source
    )
    assert match is not None, f"missing Forth definition {name}"
    return match.group(0)


def _row_damage(
    front: tuple[bytes, ...], back: tuple[bytes, ...], mode: str
) -> bytes:
    assert len(front) == len(back)
    if mode == "snapshot":
        return bytes([0xFF] * len(front))
    if mode == "none":
        return bytes(len(front))
    assert mode == "delta"
    return bytes(0xFF if old != new else 0 for old, new in zip(front, back))


def _retry_damage(mask: bytes, begin_accepted: bool) -> bytes | None:
    """A refusal retains the exact immutable plan; acceptance retires it."""
    return None if begin_accepted else mask


def _candidate_damage(
    front: tuple[bytes, ...],
    back: tuple[bytes, ...],
    touched: set[int],
    mode: str = "delta",
) -> tuple[bytes, set[int]]:
    """Model conservative candidate rows and the exact admitted row plan."""
    assert len(front) == len(back)
    if mode == "snapshot":
        return bytes([0xFF] * len(front)), set(touched)
    assert mode == "delta"
    damage = bytes(
        0xFF if row in touched and old != new else 0
        for row, (old, new) in enumerate(zip(front, back))
    )
    return damage, set(touched)


def _visible_axis(start: int, length: int, low: int, high: int) -> tuple[int, ...]:
    """Independent oracle for the bounded line-prefix clamp."""
    if length <= 0 or low >= high:
        return ()
    skip = max(0, low - start)
    if skip >= length:
        return ()
    first = start + skip
    count = min(length - skip, max(0, high - first))
    return tuple(range(first, first + count))


def _retained_handoff_step(
    *,
    available: bool,
    handed_off: bool,
    publisher_attached: bool,
    exact_backend: bool,
    route_idle: bool,
) -> tuple[bool, bool]:
    """Model the one-shot availability edge and report (latch, force)."""
    if not available:
        return False, False
    eligible = publisher_attached and exact_backend and route_idle
    if handed_off or not eligible:
        return handed_off, False
    return True, True


def test_baseline_publisher_is_neutral_exact_and_immutable() -> None:
    source = SCREEN.read_text(encoding="utf-8")

    assert "RTAPT-" not in source
    assert "rich-terminal/apt1-engine.f" not in source
    assert "REQUIRE screen.f" in source
    assert "REQUIRE ../utils/memory-span.f" in source

    valid = _definition(source, "APTSCB-PUBLISHER-VALID?")
    for field in (
        "APTSCBP.SESSION",
        "APTSCBP.CONTEXT",
        "APTSCBP.BEGIN-XT",
        "APTSCBP.SPAN-XT",
        "APTSCBP.CELL-XT",
        "APTSCBP.CURSOR-XT",
        "APTSCBP.COMMIT-XT",
        "APTSCBP.ABORT-XT",
        "APTSCBP.STEP-XT",
        "APTSCBP.SETTLE-XT",
        "APTSCBP.MAGIC",
    ):
        assert field in valid
    assert "7 AND" in valid
    assert "MSPAN-NONWRAPPING?" in valid

    init = _definition(source, "APTSCB-PUBLISHER-INIT")
    first_mutation = init.index("0 FILL")
    assert init.index("PT-STORAGE-DISJOINT?") < first_mutation
    assert init.index("MSPAN-NONWRAPPING?") < first_mutation
    assert init.index("_APTSCBPI-SETTLE @ 0= OR") < first_mutation

    attach = _definition(source, "APTSCB-PUBLISHER!")
    assert "_APTSCB-ROUTE-IDLE <>" in attach
    assert "APTSCBP.SESSION" in attach
    assert "APTSCB-STORAGE-DISJOINT?" in attach
    assert "APTSCB.PUBLISHER @ ?DUP IF" in attach
    assert "_APTSCBPA-PUBLISHER @ = IF SCB-S-OK" in attach
    assert attach.count("APTSCB.PUBLISHER !") == 1

    adapter_storage = _definition(source, "_APTSCBI-STORAGE-VALID?")
    assert "PT-STORAGE-DISJOINT?" in adapter_storage


def test_screen_transaction_pins_one_route_and_normalizes_cells_once() -> None:
    source = SCREEN.read_text(encoding="utf-8")
    mode_valid = _definition(source, "_APTSCB-MODE?")
    publisher_mode = _definition(source, "_APTSCB-PUBLISHER-CELL-MODE")
    begin = _definition(source, "_APTSCB-BEGIN")
    span_begin = _definition(source, "_APTSCB-SPAN-BEGIN")
    write_cell = _definition(source, "_APTSCB-WRITE-CELL")
    span = _definition(source, "_APTSCB-SPAN")
    cursor = _definition(source, "_APTSCB-CURSOR")
    commit = _definition(source, "_APTSCB-COMMIT")
    abort = _definition(source, "_APTSCB-ABORT")

    assert "PT-RETAINED-AVAILABLE?" in begin
    assert begin.count("_APTSCB.ROUTE !") == 3
    assert "_APTSCB-ROUTE-DIRECT" in begin
    assert "_APTSCB-ROUTE-OUTPUT" in begin
    for mode in ("SCB-M-DELTA", "SCB-M-SNAPSHOT", "SCB-M-NONE"):
        assert mode in mode_valid
    assert "_APTSCB-MODE? 0= IF SCB-S-INVALID EXIT THEN" in begin
    assert "_APTSCB-PUBLISHER-CELL-MODE" in begin
    for mode in ("PT-CELL-NONE", "PT-CELL-REPLACE", "PT-CELL-DELTA"):
        assert mode in publisher_mode
    assert begin.index("PT-RETAINED-AVAILABLE?") < begin.index(
        "APTSCBP.BEGIN-XT"
    )
    none_refusal = begin.index("_APTSCB-MODE @ SCB-M-NONE = IF")
    direct_route = begin.index(
        "_APTSCB-ROUTE-DIRECT _APTSCB-ADAPTER @ _APTSCB.ROUTE !"
    )
    assert "SCB-S-WOULD-BLOCK EXIT" in begin[none_refusal:direct_route]
    assert none_refusal < direct_route
    assert none_refusal < begin.index("PT-SNAPSHOT-BEGIN")
    assert none_refusal < begin.index("PT-TX-BEGIN")

    assert "APTSCBP.SPAN-XT" in span_begin
    assert "APTSCBP.CELL-XT" in write_cell
    assert "_APTSCB-CELL-CP" in write_cell
    assert "_APTSCB-WIRE-ATTRS" in write_cell
    assert span.index("_APTSCB-SPAN-BEGIN") < span.index("_APTSCB-WRITE-CELL")
    assert "_APTSCB.ROUTE !" not in span
    assert "_APTSCB.ROUTE !" not in cursor
    assert "_APTSCB-ROUTE-DIRECT" in cursor
    assert "_APTSCB-ROUTE-OUTPUT" in cursor
    for finalizer in (commit, abort):
        assert "_APTSCB-ROUTE-DIRECT" in finalizer
        assert "_APTSCB-ROUTE-OUTPUT" in finalizer
        assert "_APTSCB-ROUTE-IDLE" in finalizer


def test_retained_availability_handoff_is_exact_one_shot_and_resettable() -> None:
    source = SCREEN.read_text(encoding="utf-8")
    valid = _definition(source, "_APTSCB-CONTEXT-VALID?")
    handoff = _definition(source, "_APTSCB-RETAINED-HANDOFF")
    service = _definition(source, "APTSCB-SERVICE")
    ansi = _definition(source, "_APTSCB-ANSI-RETIRE")

    assert (
        "SCB-DESC-SIZE 32 + CONSTANT _APTSCB-O-RETAINED-HANDOFF" in source
    )
    assert "SCB-DESC-SIZE 40 + CONSTANT APTSCB-SIZE" in source
    assert "_APTSCB.RETAINED-HANDOFF @" in valid
    assert "DUP 0= SWAP -1 = OR 0= IF 0 EXIT THEN" in valid

    unavailable = handoff.index("PT-RETAINED-AVAILABLE? 0= IF")
    clear = handoff.index("0 SWAP _APTSCB.RETAINED-HANDOFF !", unavailable)
    latched = handoff.index("_APTSCB.RETAINED-HANDOFF @ IF DROP EXIT THEN")
    publisher = handoff.index("APTSCB.PUBLISHER @ 0= IF DROP EXIT THEN")
    exact = handoff.index("SCR-BACKEND@ <> IF DROP EXIT THEN")
    idle = handoff.index("_APTSCB-ROUTE-IDLE <> IF DROP EXIT THEN")
    force = handoff.index("SCR-FORCE", idle)
    publish = handoff.index("-1 SWAP _APTSCB.RETAINED-HANDOFF !", force)
    assert unavailable < clear < latched < publisher < exact < idle < force < publish
    assert handoff.count("SCR-FORCE") == 1

    pt_service = service.index("PT-SERVICE")
    active = service.index("PT-ACTIVE? 0= IF", pt_service)
    transition = service.index("_APTSCB-RETAINED-HANDOFF", active)
    producer = service.index("_APTSCB-PUBLISHER-STEP", transition)
    reset_force = service.index("PT-SNAPSHOT-NEEDED?", producer)
    assert pt_service < active < transition < producer < reset_force
    assert "0 OVER _APTSCB.RETAINED-HANDOFF !" in ansi
    assert ansi.index("_APTSCB.RETAINED-HANDOFF !") < ansi.index(
        "_APTSCB-FALLBACK"
    )

    latch = False
    forces = 0

    # Initial CELL-only/PENDING service cannot consume the future edge.
    for _ in range(2):
        latch, forced = _retained_handoff_step(
            available=False,
            handed_off=latch,
            publisher_attached=True,
            exact_backend=True,
            route_idle=True,
        )
        forces += forced
    assert (latch, forces) == (False, 0)

    # The first eligible AVAILABLE observation forces exactly once.
    for _ in range(2):
        latch, forced = _retained_handoff_step(
            available=True,
            handed_off=latch,
            publisher_attached=True,
            exact_backend=True,
            route_idle=True,
        )
        forces += forced
    assert (latch, forces) == (True, 1)

    # Reset clears the epoch latch; rediscovery earns one new force.
    latch, forced = _retained_handoff_step(
        available=False,
        handed_off=latch,
        publisher_attached=True,
        exact_backend=True,
        route_idle=True,
    )
    forces += forced
    latch, forced = _retained_handoff_step(
        available=True,
        handed_off=latch,
        publisher_attached=True,
        exact_backend=True,
        route_idle=True,
    )
    forces += forced
    assert (latch, forces) == (True, 2)

    # Ineligible availability remains pending rather than losing the edge.
    for publisher_attached, exact_backend, route_idle in (
        (False, True, True),
        (True, False, True),
        (True, True, False),
    ):
        pending, forced = _retained_handoff_step(
            available=True,
            handed_off=False,
            publisher_attached=publisher_attached,
            exact_backend=exact_backend,
            route_idle=route_idle,
        )
        assert (pending, forced) == (False, False)

    pending, forced = _retained_handoff_step(
        available=True,
        handed_off=False,
        publisher_attached=False,
        exact_backend=True,
        route_idle=True,
    )
    assert (pending, forced) == (False, False)
    pending, forced = _retained_handoff_step(
        available=True,
        handed_off=pending,
        publisher_attached=True,
        exact_backend=True,
        route_idle=True,
    )
    assert (pending, forced) == (True, True)


def test_neutral_screen_request_is_independent_and_commit_persistent() -> None:
    source = CORE_SCREEN.read_text(encoding="utf-8")

    assert "80 CONSTANT _SCR-O-FLUSH-REQUEST" in source
    assert "104 CONSTANT _SCR-O-DAMAGE" in source
    assert "112 CONSTANT _SCR-O-TOUCHED" in source
    assert "120 CONSTANT _SCR-DESC-SIZE" in source
    assert "2 CONSTANT SCB-M-NONE" in source

    request = _definition(source, "SCR-REQUEST-FLUSH")
    assert "_SCR-O-FLUSH-REQUEST + !" in request
    request_guard = request.index("_SCR-O-FLUSH-REQUEST + @ IF DROP EXIT THEN")
    request_store = request.index("_SCR-O-FLUSH-REQUEST + !")
    request_invalidate = request.index("_SCR-PLAN-INVALIDATE")
    assert request_guard < request_store < request_invalidate
    assert request.count("_SCR-PLAN-INVALIDATE") == 1
    assert "_SCR-O-DIRTY" not in request
    assert "_SCR-O-FORCE" not in request
    assert "SCR-FORCE" not in request

    force_word = _definition(source, "SCR-FORCE")
    force_guard = force_word.index("_SCR-O-FORCE + @ IF DROP EXIT THEN")
    force_store = force_word.index("_SCR-O-FORCE + !")
    force_invalidate = force_word.index("_SCR-PLAN-INVALIDATE")
    dirty_store = force_word.index("_SCR-O-DIRTY + !")
    assert force_guard < force_store < force_invalidate < dirty_store
    assert force_word.count("_SCR-PLAN-INVALIDATE") == 1

    dirty = _definition(source, "SCR-DIRTY?")
    assert "_SCR-O-DIRTY + @" in dirty
    assert "_SCR-O-FLUSH-REQUEST + @ OR" in dirty

    count = _definition(source, "_SCR-COUNT-CHANGES")
    force = count.index("_SCR-O-FORCE + @ IF")
    cell_or_cursor_dirty = count.index("_SCR-O-DIRTY + @ IF", force)
    retained_only = count.index("_SCR-O-FLUSH-REQUEST + @ IF", cell_or_cursor_dirty)
    none = count.index("SCB-M-NONE", retained_only)
    assert force < cell_or_cursor_dirty < retained_only < none
    assert count.index(
        "SCB-M-NONE = IF _SCR-PLAN-SAVE EXIT THEN", none
    ) < count.index(
        "_SCR-SCAN-RESET"
    )

    for cursor_word in ("SCR-CURSOR-AT", "SCR-CURSOR-ON", "SCR-CURSOR-OFF"):
        cursor = _definition(source, cursor_word)
        assert "_SCR-O-DIRTY + !" in cursor
        assert "_SCR-O-FLUSH-REQUEST" not in cursor

    emit = _definition(source, "_SCR-EMIT-SPANS")
    assert "SCB-M-NONE = IF SCB-S-OK EXIT THEN" in emit

    flush = _definition(source, "SCR-FLUSH?")
    cursor_gate = flush.index("_SCR-FLUSH-MODE @ SCB-M-NONE <> IF")
    cursor_call = flush.index("_SCR-CALL-CURSOR", cursor_gate)
    commit = flush.index("_SCR-CALL-COMMIT", cursor_call)
    advance = flush.index("_SCR-ADVANCE-FRONT", commit)
    assert cursor_gate < cursor_call < commit < advance
    assert "_SCR-O-FLUSH-REQUEST + !" not in flush

    advance_front = _definition(source, "_SCR-ADVANCE-FRONT")
    assert "_SCR-FLUSH-MODE @ SCB-M-NONE <> IF" in advance_front
    request_clear = advance_front.index(
        "0 _SCR-CUR @ _SCR-O-FLUSH-REQUEST + !"
    )
    assert advance_front.index("_SCR-O-DIRTY + !") < request_clear
    assert advance_front.index("_SCR-O-FORCE + !") < request_clear

    ansi_begin = _definition(source, "_SCBA-BEGIN")
    ansi_commit = _definition(source, "_SCBA-COMMIT")
    assert ansi_begin.index("SCB-M-NONE = IF") < ansi_begin.index(
        "ANSI-CURSOR-OFF"
    )
    assert ansi_commit.index("SCB-M-NONE = IF") < ansi_commit.index(
        "_SCBA-CVIS @ IF"
    )
    assert "TERM-FLUSH" in ansi_commit

    assert "' SCR-REQUEST-FLUSH" in source
    assert ": SCR-REQUEST-FLUSH   _scr-request-flush-xt" in source


def test_cell_admission_totals_are_reused_only_across_immutable_retries() -> None:
    source = CORE_SCREEN.read_text(encoding="utf-8")
    save = _definition(source, "_SCR-PLAN-SAVE")
    load = _definition(source, "_SCR-PLAN-LOAD?")
    count = _definition(source, "_SCR-COUNT-CHANGES")
    flush = _definition(source, "SCR-FLUSH?")
    advance = _definition(source, "_SCR-ADVANCE-FRONT")
    emit = _definition(source, "_SCR-EMIT-SPANS")
    damage_clear = _definition(source, "_SCR-DAMAGE-CLEAR")
    damage_mark = _definition(source, "_SCR-DAMAGE!")
    damage_test = _definition(source, "_SCR-DAMAGE?")

    for field in (
        "_SCR-PLAN-SCREEN",
        "_SCR-PLAN-MODE",
        "_SCR-PLAN-SPANS",
        "_SCR-PLAN-CELLS",
        "_SCR-PLAN-VALID",
    ):
        assert field in save
    for field in (
        "_SCR-PLAN-MODE @ _SCR-FLUSH-MODE !",
        "_SCR-PLAN-SPANS @ _SCR-SPAN-COUNT !",
        "_SCR-PLAN-CELLS @ _SCR-CELL-COUNT !",
    ):
        assert field in load
    assert load.index("_SCR-PLAN-VALID @ 0=") < load.index(
        "_SCR-PLAN-SCREEN @ _SCR-CUR @ <>"
    )
    assert "_SCR-PLAN-INVALIDATE 0 EXIT" in load
    assert "_SCR-DAMAGE-CLEAR" not in load
    assert "_SCR-PLAN-SAVE" in count
    assert "_SCR-O-DAMAGE" in damage_clear
    assert "0 FILL" in damage_clear
    assert "C!" in damage_mark
    assert "C@ 0<>" in damage_test
    assert count.index("_SCR-DAMAGE-CLEAR") < count.index("SCB-M-NONE")
    snapshot_mark = count.index("I _SCR-DAMAGE!")
    touched_gate = count.index("I _SCR-TOUCHED?", snapshot_mark)
    delta_compare = count.index("COMPARE 0<>", snapshot_mark)
    delta_mark = count.index("I _SCR-DAMAGE!", delta_compare)
    assert (
        snapshot_mark
        < touched_gate
        < delta_compare
        < delta_mark
        < count.rindex("_SCR-PLAN-SAVE")
    )
    assert flush.index("_SCR-PLAN-LOAD?") < flush.index(
        "_SCR-COUNT-CHANGES"
    ) < flush.index("_SCR-CALL-BEGIN")

    # Admission is the only full-row comparison.  Emission re-derives exact
    # spans only inside marked rows, while retirement copies those rows only
    # after COMMIT has succeeded.
    assert count.count("COMPARE") == 1
    assert "_SCR-DAMAGE?" in emit
    assert "COMPARE" not in emit
    assert "_SCR-DAMAGE?" in advance
    assert "COMPARE" not in advance
    assert "CMOVE" in advance

    # A refusal exits before FRONT retirement and deliberately preserves the
    # cached totals.  Only accepted COMMIT reaches the invalidating advance.
    assert flush.index("_SCR-CALL-BEGIN") < flush.index(
        "DUP SCB-S-OK <> IF _SCR-FAIL EXIT THEN"
    ) < flush.index("_SCR-ADVANCE-FRONT")
    assert "_SCR-PLAN-INVALIDATE" in advance
    assert "_SCR-PLAN-INVALIDATE" not in _definition(source, "_SCR-FAIL")

    for mutator in (
        "SCR-FREE",
        "SCR-USE",
        "SCR-DRAW-COMPLETE",
        "SCR-SET",
        "SCR-FILL",
        "SCR-CURSOR-AT",
        "SCR-CURSOR-ON",
        "SCR-CURSOR-OFF",
        "SCR-FORCE",
        "SCR-REQUEST-FLUSH",
        "SCR-RESIZE",
    ):
        assert "_SCR-PLAN-INVALIDATE" in _definition(source, mutator)

    # A backend identity change invalidates independently of the idempotent
    # FORCE latch, which may already be asserted by a prior provider.
    for rebinder in ("SCR-BACKEND!", "SCR-ANSI"):
        body = _definition(source, rebinder)
        assert body.index("_SCR-PLAN-INVALIDATE") < body.index(
            "_SCR-O-BACKEND + !"
        ) < body.index("SCR-FORCE")


def test_touched_rows_narrow_delta_comparison_without_weakening_retry() -> None:
    source = CORE_SCREEN.read_text(encoding="utf-8")
    count = _definition(source, "_SCR-COUNT-CHANGES")
    advance = _definition(source, "_SCR-ADVANCE-FRONT")
    emit = _definition(source, "_SCR-EMIT-SPANS")
    plan_damage = _definition(source, "_SCR-PLAN-DAMAGE@")
    plan_save = _definition(source, "_SCR-PLAN-SAVE")
    plan_load = _definition(source, "_SCR-PLAN-LOAD?")
    set_cell = _definition(source, "SCR-SET")
    fill = _definition(source, "SCR-FILL")

    assert "104 CONSTANT _SCR-O-DAMAGE" in source
    assert "112 CONSTANT _SCR-O-TOUCHED" in source
    assert "120 CONSTANT _SCR-DESC-SIZE" in source
    assert "_SCR-O-DAMAGE" not in _definition(source, "_SCR-TOUCHED!")
    assert "_SCR-O-TOUCHED" not in _definition(source, "_SCR-DAMAGE!")

    # DAMAGE is rebuilt as the immutable admitted plan.  SNAPSHOT remains
    # complete, while only DELTA's sole row comparison is candidate-gated.
    clear_at = count.index("_SCR-DAMAGE-CLEAR")
    snapshot_at = count.index("I _SCR-DAMAGE!")
    touched_at = count.index("I _SCR-TOUCHED?", snapshot_at)
    compare_at = count.index("COMPARE 0<>", touched_at)
    assert clear_at < snapshot_at < touched_at < compare_at
    assert count.count("COMPARE") == 1
    assert "_SCR-TOUCHED?" not in count[:snapshot_at]

    # Exact retry, emission, and front-copy state continue to use DAMAGE.
    for body in (plan_damage, plan_save, plan_load, emit):
        assert "_SCR-O-TOUCHED" not in body
        assert "_SCR-TOUCHED" not in body
    assert "_SCR-DAMAGE?" in emit
    assert "_SCR-DAMAGE?" in advance
    copy_at = advance.index("CMOVE")
    retire_at = advance.index("_SCR-TOUCHED-CLEAR")
    assert copy_at < retire_at < advance.index("_SCR-O-DIRTY + !")
    assert source.count("_SCR-TOUCHED-CLEAR") == 2  # definition + retirement

    # Mutation metadata is conservative even if a following raw store throws.
    for body, marker, write in (
        (set_cell, "OVER _SCR-TOUCHED!", "_SCR-IDX"),
        (fill, "_SCR-TOUCHED-ALL", "_SCR-CELL-FILL"),
    ):
        assert body.index("_SCR-PLAN-INVALIDATE") < body.index(marker)
        assert body.index(marker) < body.index("_SCR-O-DIRTY + !")
        assert body.index("_SCR-O-DIRTY + !") < body.index(write)

    # Planning, refusals, generation/cursor/request/backend changes, and
    # screen selection may invalidate a retry plan but may not retire rows.
    for word in (
        "_SCR-COUNT-CHANGES",
        "_SCR-FAIL",
        "SCR-DRAW-COMPLETE",
        "SCR-CURSOR-AT",
        "SCR-CURSOR-ON",
        "SCR-CURSOR-OFF",
        "SCR-REQUEST-FLUSH",
        "SCR-BACKEND!",
        "SCR-ANSI",
        "SCR-USE",
    ):
        assert "_SCR-TOUCHED-CLEAR" not in _definition(source, word)


def test_touched_row_oracle_preserves_equal_candidates_until_acceptance() -> None:
    front = (b"A", b"B", b"C", b"D")
    back = (b"A", b"b", b"C", b"d")
    touched = {1, 2, 3}

    damage, retained = _candidate_damage(front, back, touched)
    assert damage == b"\x00\xff\x00\xff"
    assert retained == touched

    # Refusal retains both exact admission and the conservative union.
    refused = _retry_damage(damage, begin_accepted=False)
    assert refused is damage
    assert retained == {1, 2, 3}

    # A newer write unions with the candidates before re-admission.
    back = (b"a", b"b", b"C", b"d")
    retained.add(0)
    replanned, retained = _candidate_damage(front, back, retained)
    assert replanned == b"\xff\xff\x00\xff"

    # Accepted exact rows make FRONT equal BACK; only then are candidates
    # retired, including row 2 which was compared and proved equal.
    front = tuple(
        new if mark else old for old, new, mark in zip(front, back, replanned)
    )
    retained.clear()
    assert front == back
    assert retained == set()

    snapshot, _ = _candidate_damage(front, back, set(), mode="snapshot")
    assert snapshot == b"\xff\xff\xff\xff"


def test_cell_damage_byte_oracle_covers_modes_and_immutable_retry() -> None:
    front = (b"abcdefgh", b"ijklmnop", b"qrstuvwx", b"yz012345")
    back = (b"abcdefgh", b"ijkLmnop", b"qrstuvwx", b"yz01234Z")

    snapshot = _row_damage(front, back, "snapshot")
    delta = _row_damage(front, back, "delta")
    none = _row_damage(front, back, "none")
    assert snapshot == b"\xff\xff\xff\xff"
    assert delta == b"\x00\xff\x00\xff"
    assert none == b"\x00\x00\x00\x00"

    refused = _retry_damage(delta, begin_accepted=False)
    assert refused is delta
    assert refused == b"\x00\xff\x00\xff"
    assert _retry_damage(delta, begin_accepted=True) is None


def test_normal_service_and_close_settlement_have_disjoint_schedulers() -> None:
    screen = SCREEN.read_text(encoding="utf-8")
    shell = SHELL.read_text(encoding="utf-8")
    normal = _definition(screen, "APTSCB-SERVICE")
    normal_dispatch = _definition(screen, "_APTSCB-PUBLISHER-STEP")
    settle_dispatch = _definition(screen, "_APTSCB-PUBLISHER-SETTLE")
    ansi_retire = _definition(screen, "_APTSCB-ANSI-RETIRE")
    close = _definition(screen, "APTSCB-CLOSE-STEP")
    shell_close = _definition(shell, "_APTAS-CLOSE")

    assert normal.index("PT-SERVICE") < normal.index("_APTSCB-PUBLISHER-STEP")
    assert "_APTSCB-PUBLISHER-SETTLE" not in normal
    assert normal.count("_APTSCB-ANSI-RETIRE") == 2
    active_gate = normal.index("PT-ACTIVE? 0= IF")
    assert normal.index("PT-SERVICE") < active_gate
    assert active_gate < normal.index("_APTSCB-PUBLISHER-STEP")
    assert "APTSCBP.STEP-XT" in normal_dispatch
    assert "APTSCBP.SETTLE-XT" not in normal_dispatch

    assert "APTSCBP.SETTLE-XT" in settle_dispatch
    assert "APTSCBP.STEP-XT" not in settle_dispatch
    assert "PT-STREAM-OWNED?" in ansi_retire
    assert "_APTSCB-PUBLISHER-SETTLE 2DROP" in ansi_retire
    assert ansi_retire.index("_APTSCB-PUBLISHER-SETTLE") < ansi_retire.index(
        "_APTSCB-ROUTE-IDLE"
    ) < ansi_retire.index("_APTSCB-FALLBACK")
    latch_path = close.split("\\ Latch PT's immutable close reason", 1)[1]
    close_call = latch_path.index("PT-CLOSE")
    service_call = latch_path.index("PT-SERVICE", close_call)
    settle_call = latch_path.rindex("_APTSCB-PUBLISHER-SETTLE")
    assert close_call < service_call < settle_call
    assert latch_path.count("PT-CLOSE") == 1
    for state in ("PT-ST-ANSI", "PT-ST-LOST", "PT-ST-CLOSING"):
        assert state in latch_path[close_call:service_call]
        assert state in latch_path[service_call:settle_call]
    assert close.count("_APTSCB-PUBLISHER-SETTLE") == close.count(
        "_APTSCB-PUBLISHER-SETTLE 2DROP"
    )
    assert close.count("_APTSCB-ANSI-RETIRE") == 4
    assert "_APTSCB-PENDING" not in close
    assert "_APTSCB-PUBLISHER-STEP" not in close
    assert "MS@" not in close
    assert "_PT.S" not in close

    assert shell_close.count("APTSCB-CLOSE-STEP") == 1
    assert "APTSCB-SERVICE" not in shell_close
    assert "PT-CLOSE" not in shell_close
    assert "PT-SERVICE" not in shell_close
    assert "_APTAS-STATE-OWNS?" in shell_close
    shell_step = shell_close.index("APTSCB-CLOSE-STEP")
    post_state = shell_close.index("PT-STATE@", shell_step)
    status_gate = shell_close.index("_APTAS-STATUS @ DUP SCB-S-OK <>", post_state)
    yield_call = shell_close.index("YIELD?", status_gate)
    retry = shell_close.index("AGAIN", yield_call)
    assert shell_step < post_state < status_gate < yield_call < retry
    assert "SCB-S-WOULD-BLOCK <> AND IF" in shell_close[status_gate:yield_call]
    owner_storage = _definition(shell, "_APTASI-STORAGE-VALID?")
    assert "PT-STORAGE-DISJOINT?" in owner_storage


def test_native_control_input_is_optional_exact_and_normalized_to_mouse() -> None:
    shell = SHELL.read_text(encoding="utf-8")
    poll = _definition(shell, "_APTAS-POLL")
    control = _definition(shell, "_APTAS-MAP-CONTROL")
    bind = _definition(shell, "APTAS-CONTROL-ROUTE!")

    assert "PT-EVENT-CONTROL = IF" in poll
    branch = poll.split("PT-EVENT-CONTROL = IF", 1)[1].split("THEN", 1)[0]
    assert "_APTAS-MAP-CONTROL SCB-S-OK SWAP EXIT" in branch
    assert "SCB-S-INVALID" not in branch
    assert "PT-CONTROL-EVENT-KIND@" in control
    assert "PT-CONTROL-ACTIVATE" in control
    for accessor in (
        "PT-CONTROL-EVENT-OWNER@",
        "PT-CONTROL-EVENT-GENERATION@",
        "PT-CONTROL-EVENT-ID@",
    ):
        assert accessor in control
    assert "_APTAS.CONTROL-XT @ EXECUTE" in control
    assert "KEY-MOUSE-LEFT _APTAS-POINTER-EVENT!" in control
    assert "SCR-H U<" in control
    assert "SCR-W U<" in control
    assert "ASHELL-TERMINAL@ = IF SCB-S-INVALID EXIT" in bind


def test_completed_top_level_draw_has_a_renderer_neutral_generation() -> None:
    screen = CORE_SCREEN.read_text(encoding="utf-8")
    shell = APP_SHELL.read_text(encoding="utf-8")
    complete = _definition(screen, "SCR-DRAW-COMPLETE")
    generation = _definition(screen, "SCR-DRAW-GENERATION@")
    paint = _definition(shell, "_ASHELL-PAINT")

    assert "_SCR-O-DRAW-GENERATION" in complete
    assert "1+" in complete
    assert "DUP 0= IF DROP 1 THEN" in complete
    assert "_SCR-O-DRAW-GENERATION" in generation
    assert "' SCR-DRAW-COMPLETE" in screen
    assert ": SCR-DRAW-COMPLETE   _scr-draw-complete-xt" in screen
    assert "' SCR-DRAW-GENERATION@" in screen
    assert ": SCR-DRAW-GENERATION@" in screen
    assert paint.index("UTUI-DRAW-COMPLETE") < paint.index(
        "SCR-DRAW-COMPLETE"
    )
    assert paint.index("SCR-DRAW-COMPLETE") < paint.index(
        "_ASHELL-OUTPUT-PENDING !"
    )


def test_bulk_draw_primitives_use_one_exception_safe_mutable_plane() -> None:
    screen = CORE_SCREEN.read_text(encoding="utf-8")
    draw = DRAW.read_text(encoding="utf-8")
    shell = APP_SHELL.read_text(encoding="utf-8")
    host = APPLET_HOST.read_text(encoding="utf-8")

    borrow = _definition(screen, "SCR-WITH-BACK-MUTATION")
    callback = _definition(screen, "_SCR-BACK-MUTATION-CALL")
    dirty = _definition(screen, "_SCR-BACK-MUTATION-DIRTY")
    touch_range = _definition(screen, "_SCR-BACK-MUTATION-TOUCH-RANGE")
    clear = _definition(screen, "_SCR-BACK-MUTATION-CLEAR")

    # The screen captures one selected plane, catches a callback with no
    # caller arguments beneath it, and admits one conservative physical row
    # interval after a true result.  THROW and malformed true intervals mark
    # every row because a partial write cannot be disproved.
    for field in ("_SCR-O-BACK + @", "_SCR-O-W + @", "_SCR-O-H + @"):
        assert field in callback
    assert "_SCR-BACK-MUTATION-XT @ EXECUTE" in callback
    assert (
        '_SCR-BACK-MUTATION-SCREEN @ IF\n'
        '        DROP -1 ABORT" SCR-WITH-BACK-MUTATION: nested borrow"'
        in borrow
    )
    assert "['] _SCR-BACK-MUTATION-CALL CATCH DUP IF" in borrow
    catch = borrow.index("CATCH DUP IF")
    exceptional = borrow[catch : borrow.index("THEN", catch)]
    assert exceptional.index("_SCR-BACK-MUTATION-ALL-DIRTY") < exceptional.index(
        "_SCR-BACK-MUTATION-CLEAR"
    ) < exceptional.index("THROW")
    assert "DROP IF\n        _SCR-BACK-MUTATION-RANGE-DIRTY" in borrow
    assert "ELSE\n        2DROP" in borrow
    normal = borrow.index("_SCR-BACK-MUTATION-RANGE-DIRTY")
    assert normal < borrow.index("_SCR-BACK-MUTATION-CLEAR ;", normal)
    assert dirty.count("_SCR-PLAN-INVALIDATE") == 1
    assert "_SCR-BACK-MUTATION-SCREEN @ _SCR-O-DIRTY + !" in dirty
    assert "_SCR-BACK-MUTATION-LOW @ 0<" in touch_range
    assert (
        "_SCR-BACK-MUTATION-HIGH @ _SCR-BACK-MUTATION-LOW @ <= OR"
        in touch_range
    )
    assert "_SCR-O-H + @ > OR IF" in touch_range
    assert "_SCR-BACK-MUTATION-TOUCH-ALL" in touch_range
    assert "-1 FILL" in touch_range
    assert "_SCR-O-DRAW-GENERATION" not in borrow + callback + dirty + clear
    assert "0 _SCR-BACK-MUTATION-XT !" in clear
    assert "0 _SCR-BACK-MUTATION-SCREEN !" in clear
    assert "0 _SCR-BACK-MUTATION-LOW !" in clear
    assert "0 _SCR-BACK-MUTATION-HIGH !" in clear
    assert (
        "' SCR-WITH-BACK-MUTATION CONSTANT _scr-with-back-mutation-xt"
        in screen
    )
    assert re.search(
        r"(?ms)^: SCR-WITH-BACK-MUTATION\s*\n"
        r"\s+_scr-with-back-mutation-xt _scr-guard WITH-GUARD ;$",
        screen,
    )

    plane_call = _definition(draw, "_DRW-PLANE-CALL")
    plane_clear = _definition(draw, "_DRW-PLANE-CLEAR")
    plane_set = _definition(draw, "_DRW-PLANE-SET")
    borrow_call = _definition(draw, "_DRW-BACK-MUTATION-CALL")
    scope = _definition(draw, "_DRW-WITH-BACK-MUTATION")
    char = _definition(draw, "DRW-CHAR")
    bounds = _definition(draw, "_DRW-IN-BOUNDS?")

    assert "_DRW-PLANE-BODY @ CATCH DUP IF" in plane_call
    assert plane_call.index("_DRW-PLANE-CLEAR") < plane_call.index("THROW")
    assert plane_call.rindex("_DRW-PLANE-WROTE @") < plane_call.rindex(
        "_DRW-PLANE-CLEAR"
    )
    for state in (
        "_DRW-PLANE-A",
        "_DRW-PLANE-COLS",
        "_DRW-PLANE-ROWS",
        "_DRW-PLANE-TOUCH-LOW",
        "_DRW-PLANE-TOUCH-HIGH",
        "_DRW-PLANE-ACTIVE",
        "_DRW-PLANE-WROTE",
        "_DRW-PLANE-BODY",
    ):
        assert f"0 {state} !" in plane_clear
    assert "_DRW-PLANE-ACTIVE @ IF EXECUTE EXIT THEN" in scope
    assert "SCR-WITH-BACK-MUTATION" in borrow_call
    assert "['] _DRW-BACK-MUTATION-CALL CATCH DUP IF" in scope
    scope_catch = scope.index("CATCH DUP IF")
    assert scope.index("_DRW-PLANE-CLEAR", scope_catch) < scope.index(
        "THROW", scope_catch
    )
    assert "_DRW-PLANE-COLS @ * + 8 * _DRW-PLANE-A @ + !" in plane_set
    assert "0 _DRW-PLANE-ROWS @ WITHIN" in plane_set
    assert "0 _DRW-PLANE-COLS @ WITHIN AND IF" in plane_set
    assert "2DROP DROP" in plane_set
    assert "OVER _DRW-PLANE-TOUCH" in plane_set
    assert plane_set.index("OVER _DRW-PLANE-TOUCH") < plane_set.index(
        "_DRW-PLANE-A @ + !"
    )
    plane_touch = _definition(draw, "_DRW-PLANE-TOUCH")
    assert "_DRW-PLANE-WROTE @ IF" in plane_touch
    assert "MIN _DRW-PLANE-TOUCH-LOW !" in plane_touch
    assert "MAX _DRW-PLANE-TOUCH-HIGH !" in plane_touch
    assert "-1 _DRW-PLANE-WROTE !" in plane_touch
    assert "_DRW-PLANE-TOUCHED-A" not in draw
    assert "IF _DRW-PLANE-SET ELSE SCR-SET THEN" in char
    assert "SCR-H" not in bounds
    assert "SCR-W" not in bounds
    assert "_DRW-SCREEN-ROWS" in bounds
    assert "_DRW-SCREEN-COLS" in bounds
    assert "_DRW-BOUNDS-ROW" not in draw
    assert "_DRW-BOUNDS-COL" not in draw

    for public, body, low, edge, length in (
        (
            "DRW-HLINE",
            "_DRW-HLINE-BODY",
            "_DRW-LOCAL-COL-LOW",
            "_DRW-LOCAL-COL-HIGH",
            "_DRW-HLINE-LEN @ 0> IF",
        ),
        (
            "DRW-VLINE",
            "_DRW-VLINE-BODY",
            "_DRW-LOCAL-ROW-LOW",
            "_DRW-LOCAL-ROW-HIGH",
            "_DRW-VLINE-LEN @ 0> IF",
        ),
    ):
        entry = _definition(draw, public)
        primitive = _definition(draw, body)
        assert f"['] {body} _DRW-WITH-BACK-MUTATION" in entry
        assert length in entry
        assert "DRW-CHAR" in primitive
        assert low in primitive
        assert edge in primitive
        assert " U< 0= IF DROP EXIT THEN" in primitive
        assert "SCR-SET" not in primitive

    for axis, plane in (("ROW", "ROWS"), ("COL", "COLS")):
        low = _definition(draw, f"_DRW-LOCAL-{axis}-LOW")
        high = _definition(draw, f"_DRW-LOCAL-{axis}-HIGH")
        assert "_DRW-PLANE-ACTIVE @ IF" in low
        assert " MAX" in low
        assert f"_DRW-PLANE-{plane} @" in high
        assert " MIN" in high

    # Text now discards an arbitrarily long clipped-left prefix before the
    # borrow, then uses only caller-state, non-yielding helpers while writing
    # the bounded visible interval through the same mutable plane.
    for public, mode in (("DRW-TEXT", "0"), ("DRW-TEXT-UNTRUSTED", "-1")):
        entry = _definition(draw, public)
        assert f"{mode} _DRW-TEXT-START" in entry
        assert "_DRW-WITH-BACK-MUTATION" not in entry
    text_run = _definition(draw, "_DRW-TEXT-RUN")
    text_prefix = _definition(draw, "_DRW-TEXT-SKIP-LEFT")
    text_body = _definition(draw, "_DRW-TEXT-BODY")
    assert "['] _DRW-TEXT-BODY _DRW-WITH-BACK-MUTATION" in text_run
    assert "_DRW-WITH-BACK-MUTATION" not in text_prefix
    assert "UTF8-DECODE-WITH" in _definition(draw, "_DRW-TEXT-NEXT")
    assert "CW-CELL-CP-WITH" in text_body
    assert "_DRW-PLANE-SET" in text_body
    assert "UTF8-DECODE" not in text_body
    assert "CW-CELL-CP\n" not in text_body
    assert "SCR-" not in text_body

    # The borrow stays below bounded synchronous primitives.  Applet paint
    # callbacks may yield, so neither shell nor host may hold it around them.
    assert draw.count("SCR-WITH-BACK-MUTATION") == 1
    assert "SCR-WITH-BACK-MUTATION" not in shell
    assert "SCR-WITH-BACK-MUTATION" not in host


def test_bulk_line_prefix_clamp_is_visible_equivalent_and_bounded() -> None:
    assert _visible_axis(2, 5, 0, 10) == (2, 3, 4, 5, 6)
    assert _visible_axis(-3, 7, 0, 10) == (0, 1, 2, 3)
    assert _visible_axis(-20, 10, 0, 10) == ()
    assert _visible_axis(8, 20, 0, 10) == (8, 9)
    assert _visible_axis(2, 20, 4, 9) == (4, 5, 6, 7, 8)
    assert _visible_axis(6, 2, 4, 9) == (6, 7)
    assert _visible_axis(2, 0, 0, 10) == ()
    assert _visible_axis(2, -4, 0, 10) == ()

    # Work under the screen lease is bounded by the visible interval even
    # when the caller supplies an enormous off-left/off-top prefix.
    huge = _visible_axis(-(10**12), 10**12 + 500, 0, 280)
    assert huge == tuple(range(280))
    assert len(huge) <= 280


def test_concrete_bridge_is_caller_bounded_and_one_to_one() -> None:
    source = BRIDGE.read_text(encoding="utf-8")

    assert "PROVIDED akashic-tui-rtaptscb" in source
    assert "rtaptscb1" not in source.lower()
    assert "REQUIRE ../screen-backend-apt1.f" in source
    assert "REQUIRE apt1-engine.f" in source
    assert not re.search(r"(?m)^REQUIRE\s+.*(?:MegaPad|rich-terminal)\.f\s*$", source)
    assert "PT-SERVICE" not in source
    assert "PT-PRESENT-" not in source
    assert "PT-SNAPSHOT-BEGIN" not in source
    assert "PT-TX-BEGIN" not in source
    assert not re.search(r"\b(?:CREATE|ALLOT|XBUF)\b", source)

    callbacks = {
        "_RTAPTSCB-BEGIN": "RTAPT-CELL-BEGIN",
        "_RTAPTSCB-SPAN": "RTAPT-CELL-SPAN-BEGIN",
        "_RTAPTSCB-CELL": "RTAPT-CELL-WRITE",
        "_RTAPTSCB-CURSOR": "RTAPT-CELL-CURSOR",
        "_RTAPTSCB-COMMIT": "RTAPT-CELL-COMMIT",
        "_RTAPTSCB-ABORT": "RTAPT-CELL-ABORT",
        "_RTAPTSCB-ENGINE-STEP": "RTAPT-STEP",
        "_RTAPTSCB-SETTLE": "RTAPT-SETTLE",
    }
    for word, target in callbacks.items():
        body = _definition(source, word)
        assert body.count(target) == 1

    feed_valid = _definition(source, "_RTAPTSCB-FEED-VALID?")
    assert "RTAPTSCB-SIZE _RTAPTSCB-SPAN?" in feed_valid
    assert feed_valid.index("RTAPTSCB-SIZE _RTAPTSCB-SPAN?") < feed_valid.index(
        "_RTAPTSCB.MAGIC"
    )
    assert "APTSCB-PUBLISHER-VALID?" in feed_valid
    assert "APTSCBP.CONTEXT @ OVER <>" in feed_valid
    assert "_RTAPTSCB-MAGIC" in feed_valid
    assert "RTAPT-ENGINE-BYTES _RTAPTSCB-SPAN?" in feed_valid
    assert "RTAPTSCB-VALID?" not in feed_valid
    assert "RTAPT-VALID?" not in feed_valid
    assert "RTAPT-STORAGE-DISJOINT?" not in feed_valid
    for callback in ("_RTAPTSCB-SPAN", "_RTAPTSCB-CELL", "_RTAPTSCB-CURSOR"):
        body = _definition(source, callback)
        assert "_RTAPTSCB-FEED-VALID?" in body
        assert "RTAPTSCB-VALID?" not in body
    for boundary in ("_RTAPTSCB-BEGIN", "_RTAPTSCB-COMMIT", "_RTAPTSCB-ABORT"):
        assert "RTAPTSCB-VALID?" in _definition(source, boundary)

    init = _definition(source, "RTAPTSCB-INIT")
    assert "RTAPT-VALID?" in init
    assert "RTAPT-USES-SESSION?" in init
    assert "RTAPT-STORAGE-DISJOINT?" in init
    assert "APTSCB-PUBLISHER-INIT" in init
    attach = _definition(source, "RTAPTSCB-ATTACH")
    assert "RTAPTSCB-SIZE" in attach
    assert "APTSCB-SIZE" in attach
    assert "MSPAN-OVERLAP?" in attach
    assert "RTAPT-STORAGE-DISJOINT?" in attach
    assert "APTSCB-PUBLISHER!" in attach

    settle = _definition(source, "_RTAPTSCB-SETTLE")
    pending = settle.index("_RTAPTSCB-PENDING @ IF")
    assert settle.index("SCB-S-WOULD-BLOCK -1 EXIT", pending) > pending
    assert settle.index("SCB-S-OK 0", pending) > pending
    assert "_RTAPTSCB-MAP-STATUS" not in settle

    mapper = _definition(source, "_RTAPTSCB-MAP-STATUS")
    assert "RTAPT-S-OK" in mapper
    assert "RTAPT-S-WOULD-BLOCK" in mapper
    assert "RTAPT-S-BUSY" in mapper
    assert "RTAPT-S-SESSION-LOST" in mapper
    assert "DROP SCB-S-INVALID" in mapper


def test_output_producer_hook_is_optional_immutable_and_caller_bounded() -> None:
    source = BRIDGE.read_text(encoding="utf-8")

    assert "APTSCB-PUBLISHER-SIZE 120 + CONSTANT RTAPTSCB-SIZE" in source
    assert "0 CONSTANT _RTAPTSCB-PHASE-CELL" in source
    assert "1 CONSTANT _RTAPTSCB-PHASE-HIDDEN" in source
    assert "2 CONSTANT _RTAPTSCB-PHASE-REVEAL-AWAITING" in source
    for suffix, offset in {
        "PRODUCER-CONTEXT": 16,
        "PRODUCER-U": 24,
        "PRODUCER-BUDGET": 32,
        "PRODUCER-STEP-XT": 40,
        "PRODUCER-PREPARE-XT": 48,
        "ADAPTER": 56,
        "SURFACE-COLS": 64,
        "SURFACE-ROWS": 72,
        "SURFACE-GENERATION": 80,
        "MORE-WORK": 88,
        "OUTPUT-NEEDED": 96,
        "FAULT-STATUS": 104,
        "PHASE": 112,
    }.items():
        assert (
            f"APTSCB-PUBLISHER-SIZE {offset} + CONSTANT "
            f"_RTAPTSCB-O-{suffix}"
        ) in source

    producer_valid = _definition(source, "_RTAPTSCB-PRODUCER-VALID?")
    for token in (
        "_RTAPTSCB-SPAN?",
        "_RTAPTSCB.PRODUCER-BUDGET @",
        "_RTAPTSCB.PRODUCER-STEP-XT @",
        "_RTAPTSCB.PRODUCER-PREPARE-XT @",
        "_RTAPTSCB-BOOL?",
        "MSPAN-OVERLAP?",
        "RTAPT-STORAGE-DISJOINT?",
        "APTSCB-STORAGE-DISJOINT?",
    ):
        assert token in producer_valid
    assert "_RTAPTSCB-VALID-CONTEXT @ 0= IF" in producer_valid
    assert "_RTAPTSCB.PHASE @" in producer_valid
    assert "_RTAPTSCB-PHASE-CELL = AND" in producer_valid

    phase_valid = _definition(source, "_RTAPTSCB-PHASE?")
    assert "_RTAPTSCB-PHASE-REVEAL-AWAITING U> 0=" in phase_valid

    fault_valid = _definition(source, "_RTAPTSCB-FAULT-VALID?")
    assert "_RTAPTSCB-FAULT-STATUS?" in fault_valid
    assert "_RTAPTSCB.MORE-WORK @ 0=" in fault_valid
    assert "_RTAPTSCB.OUTPUT-NEEDED @ 0=" in fault_valid
    valid = _definition(source, "RTAPTSCB-VALID?")
    assert "RTAPT-USES-SESSION?" in valid
    assert "RTAPT-VALID?" not in valid
    surface = valid.index("_RTAPTSCB-SURFACE-VALID?")
    phase = valid.index("_RTAPTSCB-PHASE?", surface)
    fault = valid.index("_RTAPTSCB-FAULT-VALID?", phase)
    adapter = valid.index("_RTAPTSCB-ADAPTER-VALID?", fault)
    producer = valid.index("_RTAPTSCB-PRODUCER-VALID?", adapter)
    assert surface < phase < fault < adapter < producer

    binder = _definition(source, "RTAPTSCB-OUTPUT-PRODUCER!")
    first_store = binder.index("_RTAPTSCB.PRODUCER-CONTEXT !")
    for preflight in (
        "RTAPTSCB-VALID?",
        "_RTAPTSCB-SPAN?",
        "0> 0= IF",
        "MSPAN-OVERLAP?",
        "RTAPT-STORAGE-DISJOINT?",
        "APTSCB-STORAGE-DISJOINT?",
    ):
        assert binder.index(preflight) < first_store
    assert "_RTAPTSCB.PRODUCER-CONTEXT @ IF" in binder
    assert "IF SCB-S-OK ELSE SCB-S-INVALID THEN EXIT" in binder
    assert binder.count("_RTAPTSCB.PRODUCER-CONTEXT !") == 1
    assert binder.index("_RTAPTSCB.FAULT-STATUS @ IF") < first_store
    assert "_RTAPTSCB.SURFACE-GENERATION @ IF" in binder
    context_publish = binder.index("_RTAPTSCB.PRODUCER-CONTEXT !")
    for field in (
        "_RTAPTSCB.PRODUCER-U !",
        "_RTAPTSCB.PRODUCER-BUDGET !",
        "_RTAPTSCB.PRODUCER-STEP-XT !",
        "_RTAPTSCB.PRODUCER-PREPARE-XT !",
    ):
        assert binder.index(field) < context_publish

    attach = _definition(source, "RTAPTSCB-ATTACH")
    assert "_RTAPTSCB.ADAPTER @ ?DUP IF" in attach
    assert "APTSCB-STORAGE-DISJOINT?" in attach
    first_attach_store = attach.index("_RTAPTSCB.ADAPTER !")
    assert attach.index("APTSCB-PUBLISHER!") < first_attach_store
    assert attach.count("_RTAPTSCB.ADAPTER !") == 1


def test_output_producer_runs_after_reconciliation_at_exact_surface() -> None:
    source = BRIDGE.read_text(encoding="utf-8")
    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())

    step = _definition(source, "_RTAPTSCB-STEP")
    engine_call = step.index("_RTAPTSCB-ENGINE-STEP")
    engine_refusal = step.index("DUP SCB-S-OK <> IF", engine_call)
    fault_override = step.index(
        "_RTAPTSCB.FAULT-STATUS @ 0= IF EXIT THEN", engine_refusal
    )
    producer_call = step.index("_RTAPTSCB-PRODUCER-STEP", fault_override)
    assert engine_call < engine_refusal < fault_override < producer_call
    assert "_RTAPTSCB.FAULT-STATUS @ ?DUP IF EXIT THEN" not in (
        step[:engine_call]
    )
    nonfatal_gate = step.index(
        "DUP SCB-S-OK = SWAP SCB-S-WOULD-BLOCK = OR IF", producer_call
    )
    scheduled = step.index("_RTAPTSCB-SCHEDULE-OUTPUT", nonfatal_gate)
    assert producer_call < nonfatal_gate < scheduled
    assert "SCR-FORCE" not in step
    assert "SCR-FLUSH?" not in step

    schedule_output = _definition(source, "_RTAPTSCB-SCHEDULE-OUTPUT")
    exact_screen = schedule_output.index("_RTAPTSCB-EXACT-SCREEN?")
    output_observation = schedule_output.index(
        "_RTAPTSCB.OUTPUT-NEEDED @", exact_screen
    )
    neutral_request = schedule_output.index(
        "SCR-REQUEST-FLUSH", output_observation
    )
    assert exact_screen < output_observation < neutral_request
    assert "_RTAPTSCB.MORE-WORK" not in schedule_output
    assert "SCR-FORCE" not in schedule_output
    assert "SCR-FLUSH?" not in schedule_output

    producer_step = _definition(source, "_RTAPTSCB-PRODUCER-STEP")
    call_order = (
        "_RTAPTSCB.SURFACE-COLS @",
        "_RTAPTSCB.SURFACE-ROWS @",
        "_RTAPTSCB.SURFACE-GENERATION @",
        "_RTAPTSCB.PRODUCER-BUDGET @",
        "_RTAPTSCB.PRODUCER-CONTEXT @",
        "_RTAPTSCB.PRODUCER-STEP-XT @ EXECUTE",
    )
    callback_tuple = producer_step.index("_RTAPTSCB-EXACT-SCREEN?")
    positions = [producer_step.index(token, callback_tuple) for token in call_order]
    assert positions == sorted(positions)
    producer_save = producer_step.index("_RTAPTSCB-R @ >R", callback_tuple)
    producer_execute = producer_step.index(
        "_RTAPTSCB.PRODUCER-STEP-XT @ EXECUTE", producer_save
    )
    producer_restore = producer_step.index("R> _RTAPTSCB-R !", producer_execute)
    assert producer_save < producer_execute < producer_restore
    status_gate = producer_step.index("_RTAPTSCB-SCB-STATUS? 0= IF")
    bool_gate = producer_step.index("_RTAPTSCB-BOOL? 0=", status_gate)
    fatal_gate = producer_step.index(
        "_RTAPTSCB-PRODUCER-STATUS @ DUP SCB-S-SESSION-LOST =", bool_gate
    )
    fatal_latch = producer_step.index("_RTAPTSCB-FAULT-LATCH", fatal_gate)
    prior_fault = producer_step.index(
        "_RTAPTSCB.FAULT-STATUS @ ?DUP IF EXIT THEN", fatal_latch
    )
    latch = producer_step.rindex("_RTAPTSCB.MORE-WORK !")
    output_latch = producer_step.rindex("_RTAPTSCB.OUTPUT-NEEDED !")
    assert status_gate < bool_gate < fatal_gate < fatal_latch
    assert fatal_latch < prior_fault < latch < output_latch
    latest_output = (
        "_RTAPTSCB-PRODUCER-OUTPUT @\n"
        "        _RTAPTSCB-R @ _RTAPTSCB.OUTPUT-NEEDED !"
    )
    assert latest_output in producer_step
    assert "latest level-triggered observations, not sticky ownership" in source
    assert "SCR-REQUEST-FLUSH persists" in source

    observe = _definition(source, "_RTAPTSCB-SURFACE-OBSERVE")
    assert "_RTAPTSCB-DIMENSION?" in observe
    assert "_RTAPTSCB.SURFACE-GENERATION @ 0= IF" in observe
    assert "1 _RTAPTSCB-SURFACE-PUBLISHER @" in observe
    assert "1+ DUP 0= IF DROP SCB-S-INVALID EXIT THEN" in observe
    assert observe.index("_RTAPTSCB-SURFACE-NEXT !") < observe.index(
        "_RTAPTSCB.SURFACE-COLS !", observe.index("_RTAPTSCB-SURFACE-NEXT !")
    )

    begin = _definition(source, "_RTAPTSCB-BEGIN")
    surface_observe = begin.index("_RTAPTSCB-SURFACE-OBSERVE")
    fault_gate = begin.index("_RTAPTSCB.FAULT-STATUS @ ?DUP IF", surface_observe)
    none_gate = begin.index("_RTAPTSCB-BEGIN-CELL-MODE @ PT-CELL-NONE = IF")
    promote_none = begin.index("_RTAPTSCB-PROMOTE-NONE", none_gate)
    producer_guard = begin.index("_RTAPTSCB-PRODUCER-BOUND?", promote_none)
    prepare_call = begin.index("_RTAPTSCB-AUTHORITATIVE-PREPARE", producer_guard)
    engine_begin = begin.index("RTAPT-CELL-BEGIN", prepare_call)
    assert surface_observe < fault_gate < none_gate < promote_none
    assert promote_none < producer_guard < prepare_call < engine_begin
    assert "_RTAPTSCB.OUTPUT-NEEDED @ AND IF" not in begin
    clear_latch = begin.index("_RTAPTSCB.OUTPUT-NEEDED !")
    assert engine_begin < begin.index("SCB-S-OK = IF", engine_begin) < clear_latch

    authoritative = _definition(source, "_RTAPTSCB-AUTHORITATIVE-PREPARE")
    producer_prepare = authoritative.index("_RTAPTSCB-PRODUCER-PREPARE")
    prepare_refusal = authoritative.index(
        "DUP SCB-S-OK <> IF EXIT THEN DROP", producer_prepare
    )
    sealed_read = authoritative.index("_RTAPTSCB-SEALED-READ", prepare_refusal)
    cell_phase = authoritative.index("_RTAPTSCB-PHASE-CELL", sealed_read)
    delta_shape = authoritative.index("_RTAPTSCB-DELTA-PRESENTATION?", cell_phase)
    hidden_shape = authoritative.index(
        "_RTAPTSCB-HIDDEN-PRESENTATION?", delta_shape
    )
    hidden_publish = authoritative.index("_RTAPTSCB-PUBLISH-HIDDEN", hidden_shape)
    hidden_phase = authoritative.index("_RTAPTSCB-PHASE-HIDDEN", hidden_publish)
    reveal_shape = authoritative.index(
        "_RTAPTSCB-REVEAL-PRESENTATION?", hidden_phase
    )
    repeated_hidden_shape = authoritative.index(
        "_RTAPTSCB-HIDDEN-PRESENTATION?", reveal_shape
    )
    repeated_hidden_publish = authoritative.index(
        "_RTAPTSCB-PUBLISH-HIDDEN", repeated_hidden_shape
    )
    assert producer_prepare < prepare_refusal < sealed_read < cell_phase
    assert cell_phase < delta_shape < hidden_shape
    assert hidden_shape < hidden_publish < hidden_phase < reveal_shape
    assert reveal_shape < repeated_hidden_shape < repeated_hidden_publish
    assert authoritative.count("_RTAPTSCB-DELTA-PRESENTATION?") == 1
    assert "_RTAPTSCB-DELTA-PRESENTATION?" not in authoritative[hidden_phase:]

    hidden = _definition(source, "_RTAPTSCB-PUBLISH-HIDDEN")
    hidden_begin = hidden.index("0 0 PT-CELL-NONE")
    hidden_commit = hidden.index("RTAPT-CELL-COMMIT", hidden_begin)
    hidden_phase_store = hidden.index("_RTAPTSCB-PHASE-HIDDEN", hidden_commit)
    refuse_outer = hidden.index("DROP SCB-S-WOULD-BLOCK", hidden_phase_store)
    assert hidden_begin < hidden_commit < hidden_phase_store < refuse_outer
    for forbidden in (
        "RTAPT-CELL-SPAN-BEGIN",
        "RTAPT-CELL-WRITE",
        "RTAPT-CELL-CURSOR",
        "RTAPT-COMMIT-AND-REVEAL",
    ):
        assert forbidden not in hidden

    hidden_shape_body = _definition(source, "_RTAPTSCB-HIDDEN-PRESENTATION?")
    assert "RTAPT-RICH-REPLACE-START" in hidden_shape_body
    assert "RTAPT-RICH-REPLACE-CONTINUE" in hidden_shape_body
    assert "RTAPT-COMMIT = AND" in hidden_shape_body
    reveal_shape_body = _definition(source, "_RTAPTSCB-REVEAL-PRESENTATION?")
    assert "RTAPT-RICH-REPLACE-CONTINUE" in reveal_shape_body
    assert "RTAPT-COMMIT-AND-REVEAL = AND" in reveal_shape_body
    delta_shape_body = _definition(source, "_RTAPTSCB-DELTA-PRESENTATION?")
    assert "RTAPT-RICH-DELTA" in delta_shape_body
    assert "RTAPT-COMMIT = AND" in delta_shape_body
    for forbidden in (
        "RTAPT-RICH-REPLACE-START",
        "RTAPT-RICH-REPLACE-CONTINUE",
        "RTAPT-COMMIT-AND-REVEAL",
    ):
        assert forbidden not in delta_shape_body

    promote = _definition(source, "_RTAPTSCB-PROMOTE-NONE")
    exact = promote.index("_RTAPTSCB-EXACT-SCREEN?")
    force = promote.index("SCR-FORCE", exact)
    refusal = promote.index("SCB-S-WOULD-BLOCK", force)
    assert exact < force < refusal
    assert "_RTAPTSCB-PRODUCER-PREPARE" not in promote
    assert "RTAPT-CELL-BEGIN" not in promote

    prepare = _definition(source, "_RTAPTSCB-PRODUCER-PREPARE")
    assert "_RTAPTSCB-EXACT-SCREEN?" in prepare
    assert prepare.index("_RTAPTSCB.SURFACE-COLS @") < prepare.index(
        "_RTAPTSCB.PRODUCER-PREPARE-XT @ EXECUTE"
    )
    prepare_save = prepare.index("_RTAPTSCB-R @ >R")
    prepare_execute = prepare.index(
        "_RTAPTSCB.PRODUCER-PREPARE-XT @ EXECUTE", prepare_save
    )
    prepare_restore = prepare.index("R> _RTAPTSCB-R !", prepare_execute)
    assert prepare_save < prepare_execute < prepare_restore
    assert prepare_restore < prepare.index(
        "_RTAPTSCB-FAULT-LATCH", prepare_restore
    )

    engine_step = _definition(source, "_RTAPTSCB-ENGINE-STEP")
    phase_reconcile = engine_step.index("_RTAPTSCB-RECONCILE-PHASE")
    rejected = engine_step.index(
        "RTAPT-S-REJECTED = IF SCB-S-OK EXIT THEN", phase_reconcile
    )
    mapped = engine_step.index("_RTAPTSCB-MAP-STATUS", rejected)
    fatal = engine_step.index("_RTAPTSCB-FATAL-STATUS?", mapped)
    faulted = engine_step.index("_RTAPTSCB-FAULT-LATCH", fatal)
    assert phase_reconcile < rejected < mapped < fatal < faulted

    reconcile = _definition(source, "_RTAPTSCB-RECONCILE-PHASE")
    assert "RTAPT-S-REJECTED" in reconcile
    assert "_RTAPTSCB-SEALED-READ" in reconcile
    assert "_RTAPTSCB-REVEAL-PRESENTATION?" in reconcile
    assert "_RTAPTSCB-PHASE-HIDDEN" in reconcile
    assert "_RTAPTSCB-PHASE-REVEAL-AWAITING" in reconcile
    assert "_RTAPTSCB-PHASE-CELL" in reconcile
    commit_callback = _definition(source, "_RTAPTSCB-COMMIT")
    commit_call = commit_callback.index("RTAPT-CELL-COMMIT")
    reveal_awaiting = commit_callback.index(
        "_RTAPTSCB-PHASE-REVEAL-AWAITING", commit_call
    )
    assert commit_call < reveal_awaiting
    output_query = _definition(source, "RTAPTSCB-OUTPUT-NEEDED?")
    assert "RTAPTSCB-VALID?" in output_query
    assert "_RTAPTSCB-EXACT-SCREEN?" in output_query

    settle = _definition(source, "_RTAPTSCB-SETTLE")
    assert "_RTAPTSCB-SCHEDULE-OUTPUT" not in settle
    assert "SCR-REQUEST-FLUSH" not in settle

    fault_latch = _definition(source, "_RTAPTSCB-FAULT-LATCH")
    clear_more = fault_latch.index("_RTAPTSCB.MORE-WORK !")
    clear_output = fault_latch.index("_RTAPTSCB.OUTPUT-NEEDED !", clear_more)
    existing = fault_latch.index("_RTAPTSCB.FAULT-STATUS @ ?DUP IF", clear_output)
    publish = fault_latch.index("_RTAPTSCB.FAULT-STATUS !", existing)
    assert clear_more < clear_output < existing < publish
    assert source.count("_RTAPTSCB.FAULT-STATUS !") == 1

    for forbidden in (
        "RTE-LABEL-PREFLIGHT",
        "RTERM-",
        "PRESENT-",
        "PRESENT_",
    ):
        assert forbidden not in code
    assert "SCR-REQUEST-FLUSH" in code
    assert code.count("SCR-FORCE") == 1


def test_engine_settlement_only_reconciles_active_wire_authority() -> None:
    source = ENGINE.read_text(encoding="utf-8")
    settle = _definition(source, "RTAPT-SETTLE")

    assert "_RTAPT-E.ACTIVE-KIND" in settle
    assert "_RTAPT-POLL-COMPLETION" in settle
    assert "_RTAPT-SESSION-ENDED?" in settle
    ended = settle.index("_RTAPT-SESSION-ENDED?")
    active_none = settle.index("_RTAPT-ACTIVE-NONE =")
    poll = settle.index("_RTAPT-POLL-COMPLETION")
    assert ended < active_none < poll
    for forbidden in (
        "RTAPT-STEP",
        "_RTAPT-E.QUEUE-HEAD",
        "_RTAPT-E.QUEUE-TAIL",
        "_RTAPT-OWNER-SEND",
        "_RTAPT-QUEUE-POP",
        "PT-OWNER-OPEN",
        "PT-OWNER-DROP",
        "PT-SERVICE",
    ):
        assert forbidden not in settle
