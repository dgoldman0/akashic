"""Seconds-only structural and byte oracles for UIDL CONTROL planning."""

from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/rich-terminal/uidl-control-planner.f"


def _source() -> str:
    return SOURCE.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_exact_caller_bounded_records_and_public_construction_api() -> None:
    source = _source()
    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())

    assert "280 CONSTANT RUCP-REQUEST-SIZE" in source
    assert "32 CONSTANT RUCP-LOOKUP-ENTRY-SIZE" in source
    assert "56 CONSTANT RUCP-CORRELATION-SIZE" in source
    assert ": _RUCP-Q.OWNER-GEN    ( q -- a )   16 + ;" in source
    assert ": _RUCP-Q.SOURCE-GEN   ( q -- a )   24 + ;" in source
    assert ": _RUCP-Q.RESERVED     ( q -- a )  272 + ;" in source

    request_fields = (
        "ATTACHMENT",
        "OWNER",
        "OWNER-GEN",
        "SOURCE-GEN",
        "SURFACE-W",
        "SURFACE-H",
        "REGION-ID",
        "REGION-X",
        "REGION-Y",
        "REGION-W",
        "REGION-H",
        "CLIP-X",
        "CLIP-Y",
        "CLIP-W",
        "CLIP-H",
        "REGION-Z",
        "REGION-F",
        "FIRST-ID",
        "RECORDS-A",
        "RECORDS-U",
        "TEXT-A",
        "TEXT-U",
        "LOOKUP-A",
        "LOOKUP-U",
        "ORDER-A",
        "ORDER-U",
        "ORDER2-A",
        "ORDER2-U",
        "PLAN-A",
        "PLAN-U",
        "CONTROLS-A",
        "CONTROLS-U",
        "CORR-A",
        "CORR-U",
        "RESERVED",
    )
    for offset, field in enumerate(request_fields):
        word = _word(source, f"_RUCP-Q.{field}")
        if offset:
            assert f"{offset * 8} +" in word
        else:
            assert "+" not in word

    request = tuple(range(1, 35)) + (0,)
    packed_request = struct.pack("<35Q", *request)
    assert len(packed_request) == 280
    assert struct.unpack_from("<Q", packed_request, 16)[0] == 3
    assert struct.unpack_from("<Q", packed_request, 24)[0] == 4
    assert struct.unpack_from("<4Q", packed_request, 88) == (12, 13, 14, 15)
    assert struct.unpack_from("<Q", packed_request, 272)[0] == 0
    region_setter = _word(source, "RUCP-REQUEST-REGION!")
    for field in ("CLIP-X", "CLIP-Y", "CLIP-W", "CLIP-H"):
        assert f"_RUCP-Q.{field} !" in region_setter

    for public in (
        "RUCP-REQUEST-BYTES",
        "RUCP-REQUEST-CLEAR",
        "RUCP-REQUEST-IDENTITY!",
        "RUCP-REQUEST-REGION!",
        "RUCP-REQUEST-SOURCE!",
        "RUCP-REQUEST-WORK!",
        "RUCP-REQUEST-OUTPUT!",
        "RUCP-LOOKUP-ENTRY-BYTES",
        "RUCP-CORRELATION-BYTES",
        "RUCP-CORRELATION-LIFECYCLE-GENERATION@",
        "RUCP-CORRELATION-SCOPE@",
        "RUCP-BUILD",
    ):
        assert re.search(rf"(?m)^: {re.escape(public)}(?=\s)", source)

    assert "ALLOCATE" not in source
    assert re.search(r"(?m)^\s*FREE\b", source) is None
    for forbidden in (
        "RTE-CONTROL-PREFLIGHT",
        "RTE-CONTROL-PLAN-VALID?",
        "RTE-CONTROL-DEFINE",
        "RTE-LIMITS@",
        "RTERM-UCTX",
        "DESK-",
    ):
        assert forbidden not in code

    shaped = _word(source, "_RUCP-SPANS-SHAPED?")
    assert shaped.count("_RUCP-OPTIONAL-SPAN?") == 6
    assert "_RUCP-RECORDS-A @ _RUCP-RECORDS-U @ _RUCP-SPAN?" in shaped
    for modulus in (
        "RUCP-LOOKUP-ENTRY-SIZE MOD",
        "_RUCP-ORDER-U @ 7 AND",
        "_RUCP-ORDER2-U @ 7 AND",
        "RTE-CONTROL-SIZE MOD",
        "RUCP-CORRELATION-SIZE MOD",
    ):
        assert modulus in shaped


def test_source_validation_is_versioned_packed_and_generation_separated() -> None:
    source = _source()
    record = _word(source, "_RUCP-RECORD-BASE?")
    text = _word(source, "_RUCP-TEXT-SHAPE?")
    text_field = _word(source, "_RUCP-TEXT-FIELD?")
    validate = _word(source, "_RUCP-VALIDATE-SOURCE?")

    for exact in (
        "_UMSN-RECORD-MAGIC",
        "_UMSN-RECORD-ABI",
        "UMSN-RECORD-SIZE",
        "_RUCP-SOURCE-GEN @ <>",
        "UMSN-SOURCE-UIDL <>",
        "_RUCP-R.SUBKEY @ IF",
        "UTUI-RESOLVED-VALID?",
    ):
        assert exact in record
    assert "_RUCP-OWNER-GEN" not in record
    assert "_RUCP-EXPECTED-TEXT" in text_field
    assert text.count("_RUCP-TEXT-FIELD?") == 2
    assert "_RUCP-EXPECTED-TEXT @ _RUCP-TEXT-U @ <>" in validate
    assert "_RUCP-MENUBAR-COUNT @ 1 <>" in validate
    assert "_RUCP-LAST-ID" in validate


def test_control_state_and_geometry_keep_semantics_at_the_right_layer() -> None:
    source = _source()
    state = _word(source, "_RUCP-STATE>RTE")
    geometry = _word(source, "_RUCP-BAR-GEOMETRY?")
    write = _word(source, "_RUCP-WRITE-CONTROL")
    write_geometry = _word(source, "_RUCP-WRITE-BAR-GEOMETRY")
    scalars = _word(source, "_RUCP-SCALARS?")
    text = _word(source, "_RUCP-CONTROL-TEXT-A")

    assert "UMSN-F-VISIBLE" in state
    assert "UMSN-F-ENABLED" in state
    assert "UMSN-F-OPEN" in state
    assert "UMSN-F-SELECTED" in state
    assert "UMSN-F-FOCUSED" not in state
    assert "UMSN-F-PAINTABLE" not in state
    assert "PAINTABLE remains only in the UMSN source" in source
    assert "claim" not in " ".join(
        line for line in source.splitlines() if "_RUCP-X." in line
    ).lower()

    assert "_RUCP-IEND?" in geometry
    assert " MAX " not in geometry
    assert " MIN" not in geometry
    assert "_RUCP-BAR-ROW @ _RUCP-REGION-Y @ <" in geometry
    assert "_RUCP-BAR-COL @ _RUCP-REGION-X @ <" in geometry
    assert "_RUCP-BAR-ROW-END @ _RUCP-REGION-ROW-END @ >" in geometry
    assert "_RUCP-BAR-COL-END @ _RUCP-REGION-COL-END @ >" in geometry
    assert "_RUCP-BAR-ROW @ _RUCP-REGION-Y @ -" in geometry
    assert "_RUCP-BAR-COL @ _RUCP-REGION-X @ -" in geometry
    assert "_RUCP-BAR-LOCAL-ROW @" in write_geometry
    assert "_RUCP-BAR-LOCAL-COL @" in write_geometry
    assert "_RUCP-BAR-H @" in write_geometry
    assert "_RUCP-BAR-W @" in write_geometry
    assert "_RUCP-REGION-X @ _RUCP-I32?" in scalars
    assert "_RUCP-REGION-Y @ _RUCP-I32?" in scalars
    assert "RTE-REGION-CLIPPED AND 0= IF" in scalars
    assert "_RUCP-CLIP-ZERO? IF -1 EXIT THEN" in scalars
    assert "_RUCP-CLIP-COL-END @ _RUCP-REGION-COL-END @ >" in scalars
    assert "_RUCP-CLIP-ROW-END @ _RUCP-REGION-ROW-END @ >" in scalars
    assert write.count("_RUCP-WRITE-BAR-GEOMETRY") == 1
    assert write.index("UMSN-K-MENUBAR = IF") < write.index(
        "_RUCP-WRITE-BAR-GEOMETRY"
    )
    assert "DUP 0= IF 2DROP 0 EXIT THEN" in text

    # A partially covered logical root retains its complete menubar geometry.
    root_row, root_col = -1, -2
    bar_row, bar_col, bar_rows, bar_cols = 0, 0, 1, 7
    assert (bar_row - root_row, bar_col - root_col, bar_rows, bar_cols) == (
        1,
        2,
        1,
        7,
    )

    def canonical_clip(
        root: tuple[int, int, int, int],
        clip: tuple[int, int, int, int],
        surface: tuple[int, int],
        clipped: bool,
    ) -> bool:
        root_x, root_y, root_w, root_h = root
        clip_x, clip_y, clip_w, clip_h = clip
        surface_w, surface_h = surface
        if not clipped:
            return clip == (0, 0, 0, 0)
        if clip == (0, 0, 0, 0):
            return True
        return (
            clip_w > 0
            and clip_h > 0
            and clip_x + clip_w <= surface_w
            and clip_y + clip_h <= surface_h
            and root_x <= clip_x
            and root_y <= clip_y
            and clip_x + clip_w <= root_x + root_w
            and clip_y + clip_h <= root_y + root_h
        )

    assert canonical_clip((-2, -1, 9, 4), (0, 0, 7, 2), (7, 2), True)
    assert canonical_clip((-2, -1, 9, 4), (0, 0, 0, 0), (7, 2), True)
    assert not canonical_clip((-2, -1, 9, 4), (0, 0, 7, 0), (7, 2), True)
    assert not canonical_clip((-2, -1, 9, 4), (0, 0, 8, 2), (7, 2), True)
    assert canonical_clip((-2, -1, 9, 4), (0, 0, 0, 0), (7, 2), False)


def test_parent_first_order_is_bounded_and_not_a_nested_bank_search() -> None:
    source = _source()
    graph = _word(source, "_RUCP-GRAPH?")
    build = _word(source, "_RUCP-BUILD-GRAPH?")
    ordinal = _word(source, "_RUCP-SORT-ROWS-BY-ORDINAL")
    parent = _word(source, "_RUCP-SORT-ROWS-BY-PARENT")

    assert graph.count("_RUCP-GRAPH-ONE?") == 1
    assert "_RUCP-LOOKUP-AT" in _word(source, "_RUCP-PARENT-RECORD?")
    assert "_RUCP-RECORD-COUNT @ 0 ?DO" not in _word(
        source, "_RUCP-GRAPH-ONE?"
    )
    assert "_RUCP-ORDER2-AT" in ordinal
    assert "_RUCP-ORDER-AT" in parent
    assert build.index("_RUCP-EMIT-MENUS?") < build.index("_RUCP-EMIT-ROWS")
    assert build.count("_RUCP-EMIT-MENUS?") == 1
    assert build.count("_RUCP-EMIT-ROWS") == 1
    menus = _word(source, "_RUCP-BUCKET-MENUS?")
    rows = _word(source, "_RUCP-COUNT-ROW-ORDINALS?")
    for placement in (menus, rows):
        assert placement.index("_RUCP-ORDER-CAP @") < placement.index(
            "_RUCP-SET-CAPACITY"
        )
        assert placement.index("_RUCP-HIGH-WATER @ U< 0=") > placement.index(
            "_RUCP-SET-CAPACITY"
        )


def test_correlation_is_canonical_while_controls_are_parent_first() -> None:
    source = _source()
    correlation = _word(source, "_RUCP-WRITE-CORRELATIONS?")

    assert "I _RUCP-RECORD-AT" in correlation
    assert "_RUCP-R.INDEX @ _RUCP-LOOKUP-AT" in correlation
    assert "_RUCP-ATTACHMENT @ OVER _RUCP-X.ATTACHMENT !" in correlation
    assert "_RUCP-R.SOURCE @ OVER _RUCP-X.SOURCE !" in correlation
    assert "_RUCP-R.SUBKEY @ OVER _RUCP-X.SUBKEY !" in correlation
    assert "0 SWAP _RUCP-X.LIFECYCLE-GENERATION !" in correlation
    assert "0 OVER _RUCP-X.SCOPE !" in correlation

    # Canonical source order deliberately disagrees with hierarchy order.
    records = [
        {"source": 1, "kind": "item", "parent": 10, "order": 1},
        {"source": 4, "kind": "bar", "parent": None, "order": 7},
        {"source": 7, "kind": "menu", "parent": 4, "order": 1},
        {"source": 8, "kind": "sep", "parent": 7, "order": 0},
        {"source": 10, "kind": "menu", "parent": 4, "order": 0},
        {"source": 12, "kind": "item", "parent": 7, "order": 2},
    ]
    bar = next(record for record in records if record["kind"] == "bar")
    menus = sorted(
        (record for record in records if record["kind"] == "menu"),
        key=lambda record: record["order"],
    )
    menu_rank = {record["source"]: rank for rank, record in enumerate(menus)}
    rows = sorted(
        (record for record in records if record["kind"] in {"item", "sep"}),
        key=lambda record: (menu_rank[record["parent"]], record["order"]),
    )
    wire = [bar, *menus, *rows]
    control_id = {record["source"]: 50 + i for i, record in enumerate(wire)}

    assert [record["source"] for record in wire] == [4, 10, 7, 1, 8, 12]
    canonical = [(record["source"], control_id[record["source"]]) for record in records]
    assert canonical == [(1, 53), (4, 50), (7, 52), (8, 54), (10, 51), (12, 55)]

    packed = b"".join(
        struct.pack("<7Q", 0xA77A, 1, source_index, 0, object_id, 0, 0)
        for source_index, object_id in canonical
    )
    assert len(packed) == 6 * 56
    assert struct.unpack_from("<Q", packed, 0)[0] == 0xA77A
    assert struct.unpack_from("<Q", packed, 4 * 56 + 32)[0] == 51
    assert struct.unpack_from("<Q", packed, 4 * 56 + 40)[0] == 0
    assert struct.unpack_from("<Q", packed, 4 * 56 + 48)[0] == 0

    bar = struct.pack(
        "<24Q",
        9, 4, 50, 1, 3, 7, 22, 0, 0,
        1, 2, 1, 40, 24, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    )
    descendant = struct.pack(
        "<24Q",
        9, 4, 51, 2, 3, 0, 22, 50, 0,
        0, 0, 0, 0, 24, 80, 0x1000, 4, 0, 0, 0, 0, 0, 0, 0,
    )
    assert len(bar) == len(descendant) == 192
    assert struct.unpack_from("<5Q", bar, 5 * 8) == (7, 22, 0, 0, 1)
    assert struct.unpack_from("<5Q", descendant, 5 * 8) == (0, 22, 50, 0, 0)
    assert struct.unpack_from("<4Q", descendant, 9 * 8) == (0, 0, 0, 0)


def test_plan_uses_exact_bank_extent_and_leaves_validation_to_preflight() -> None:
    source = _source()
    plan = _word(source, "_RUCP-WRITE-PLAN?")
    body = _word(source, "_RUCP-BUILD-BODY")
    shaped = _word(source, "_RUCP-SPANS-SHAPED?")
    authority = _word(source, "_RUCP-RANGE-AUTHORITY?")
    capacities = _word(source, "_RUCP-CAPACITIES?")
    clear_partial = _word(source, "_RUCP-CLEAR-PARTIAL")

    assert "RTE-CONTROL-PLAN-SIZE U<" not in shaped
    assert "_RUCP-PLAN-U @ RTE-CONTROL-PLAN-SIZE U<" in capacities
    assert capacities.index("RTE-CONTROL-PLAN-SIZE U<") < capacities.index(
        "_RUCP-SET-CAPACITY"
    )
    assert "-1 _RUCP-RANGES-VALID !" in authority
    assert "_RUCP-RECORD-COUNT @ RTE-CONTROL-SIZE _RUCP-UMUL?" in plan
    assert "_RTE-CP.ITEMS-U !" in plan
    assert "_RUCP-CONTROLS-U @" in plan
    for clip_field in ("X", "Y", "COLS", "ROWS"):
        assert f"_RTE-CP.CLIP-{clip_field} !" in plan
    assert body.index("_RUCP-VALIDATE-SOURCE?") < body.index(
        "_RUCP-BUILD-OUTPUT?"
    )
    assert body.index("_RUCP-RANGE-AUTHORITY?") < body.index(
        "_RUCP-SCALARS?"
    )
    assert body.index("_RUCP-SCALARS?") < body.index(
        "_RUCP-CAPACITIES?"
    )
    assert "_RUCP-RANGES-VALID @ 0= IF EXIT THEN" in clear_partial
    assert "_RUCP-DIRTY" not in source
    assert "_RUCP-CLEAR-PARTIAL" in _word(source, "_RUCP-FAIL-RESULT")
    assert "RTE-CONTROL-PLAN-VALID?" not in source

    packed_plan = struct.pack(
        "<5Q2q6Qq4Q",
        9,
        4,
        7,
        2,
        22,
        -2,
        -1,
        9,
        4,
        0,
        0,
        7,
        2,
        3,
        3,
        0x2000,
        6 * 192,
        0,
    )
    assert len(packed_plan) == 144
    assert struct.unpack_from("<4Q", packed_plan, 72) == (0, 0, 7, 2)
    assert struct.unpack_from("<Q", packed_plan, 128)[0] == 6 * 192


def test_scrub_words_cover_every_mutable_span_and_are_routed() -> None:
    source = _source()
    clear_mutable = _word(source, "_RUCP-CLEAR-MUTABLE")
    clear_work = _word(source, "_RUCP-CLEAR-WORK")
    clear_partial = _word(source, "_RUCP-CLEAR-PARTIAL")
    build_output = _word(source, "_RUCP-BUILD-OUTPUT?")
    failure = _word(source, "_RUCP-FAIL-RESULT")
    success = _word(source, "_RUCP-SUCCESS-RESULT")

    mutable_spans = (
        ("_RUCP-LOOKUP-A", "_RUCP-LOOKUP-U"),
        ("_RUCP-ORDER-A", "_RUCP-ORDER-U"),
        ("_RUCP-ORDER2-A", "_RUCP-ORDER2-U"),
        ("_RUCP-PLAN-A", "_RUCP-PLAN-U"),
        ("_RUCP-CONTROLS-A", "_RUCP-CONTROLS-U"),
        ("_RUCP-CORR-A", "_RUCP-CORR-U"),
    )
    for address, length in mutable_spans:
        assert f"{address} @ {length} @ 0 FILL" in clear_mutable
    for address, length in mutable_spans[:3]:
        assert f"{address} @ {length} @ 0 FILL" in clear_work
    for address, length in mutable_spans[3:]:
        assert f"{address} @ {length} @ 0 FILL" not in clear_work

    assert "_RUCP-RANGES-VALID @ 0= IF EXIT THEN" in clear_partial
    assert "_RUCP-CLEAR-MUTABLE" in clear_partial
    assert build_output.index("_RUCP-CLEAR-MUTABLE") < build_output.index(
        "_RUCP-BUILD-GRAPH?"
    )
    assert "_RUCP-CLEAR-PARTIAL" in failure
    assert "_RUCP-CLEAR-WORK" in success
