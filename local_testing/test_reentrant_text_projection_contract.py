"""Lightweight contracts for non-yielding caller-state text helpers."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
UTF8 = ROOT / "akashic" / "text" / "utf8.f"
CELL_WIDTH = ROOT / "akashic" / "text" / "cell-width.f"
DRAW = ROOT / "akashic" / "tui" / "draw.f"
STREAMS_SOURCE_STORE = (
    ROOT / "akashic" / "tui" / "applets" / "streams" / "source-store.f"
)
STREAMS_OBSERVATION_STORE = (
    ROOT / "akashic" / "tui" / "applets" / "streams" / "observation-store.f"
)
UTF8_DOC = ROOT / "docs" / "text" / "utf8.md"
CELL_WIDTH_DOC = ROOT / "docs" / "text" / "cell-width.md"


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(word)}(?:\s|$).*?\s;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert match is not None, f"missing Forth definition {word}"
    return match.group(0)


def _has_token(source: str, token: str) -> bool:
    source = re.sub(r"(?m)\\.*$", "", source)
    return re.search(rf"(?<!\S){re.escape(token)}(?!\S)", source) is not None


def test_utf8_decode_has_a_distinct_caller_state_path() -> None:
    source = UTF8.read_text(encoding="utf-8")
    decode = _definition(source, "UTF8-DECODE-WITH")
    failure = _definition(source, "_UTF8-DECODE-WITH-FAIL")
    lead = _definition(source, "_UTF8-LEAD")
    sequence_length = _definition(source, "_UTF8-SEQLEN")
    continuation_test = _definition(source, "_UTF8-CONT?")
    display_unsafe = _definition(source, "UTF8-DISPLAY-UNSAFE?")
    display_cp = _definition(source, "UTF8-DISPLAY-CP")
    wrapper = _definition(source, "UTF8-DECODE")

    for declaration in (
        "0 CONSTANT _UTF8-DS-A",
        "8 CONSTANT _UTF8-DS-L",
        "16 CONSTANT _UTF8-DS-CP",
        "24 CONSTANT _UTF8-DS-NEED",
        "32 CONSTANT _UTF8-DS-LOW",
        "40 CONSTANT _UTF8-DS-HIGH",
        "48 CONSTANT UTF8-DECODE-STATE-SIZE",
    ):
        assert declaration in source

    assert "CREATE _UTF8-DECODE-STATE UTF8-DECODE-STATE-SIZE ALLOT" in source
    assert "_UTF8-DECODE-STATE UTF8-DECODE-WITH" in wrapper
    assert "VARIABLE _UD-" not in source

    # Continuations are consumed by a BEGIN loop over caller state: the
    # return stack only ever holds that state, never a DO-loop index.
    assert "BEGIN" in decode and "REPEAT" in decode
    assert not _has_token(decode, "DO")
    assert not _has_token(decode, "LOOP")
    assert "R@ _UTF8-LEAD" in decode

    closure = (
        decode
        + failure
        + lead
        + sequence_length
        + continuation_test
        + display_unsafe
        + display_cp
    )
    forbidden = (
        "WITH-GUARD",
        "GUARD-ACQUIRE",
        "YIELD",
        "YIELD?",
        "PAUSE",
        "ALLOCATE",
        "RESIZE",
        "FREE",
        "CATCH",
        "THROW",
        "EXECUTE",
    )
    for word in forbidden:
        assert not _has_token(closure, word)
    for prefix in ("SCR-", "TASK-", "SEM-", "EVT-"):
        assert prefix not in closure
    assert "_UTF8-DECODE-STATE" not in decode

    # Only the shared-state compatibility API is wrapped by the module guard.
    assert "' UTF8-DECODE     CONSTANT _utf8-decode-xt" in source
    assert "' UTF8-DECODE-WITH" not in source
    assert ": UTF8-DECODE     _utf8-decode-xt _utf8-guard WITH-GUARD ;" in source


def test_utf8_caller_state_path_replaces_maximal_subparts() -> None:
    """APT-1-TEXT Section 5: one U+FFFD per maximal ill-formed subpart."""

    source = UTF8.read_text(encoding="utf-8")
    decode = _definition(source, "UTF8-DECODE-WITH")
    failure = _definition(source, "_UTF8-DECODE-WITH-FAIL")
    lead = _definition(source, "_UTF8-LEAD")

    # The failure path consumes exactly the bytes the caller proved valid.
    assert "( consumed state -- cp addr' len' )" in failure
    assert "UTF8-REPLACEMENT -ROT" in failure
    # A bad lead consumes one byte; a truncated or diverging sequence
    # consumes its valid prefix.
    assert "1 R> _UTF8-DECODE-WITH-FAIL EXIT" in decode
    assert decode.count("R> _UTF8-DECODE-WITH-FAIL EXIT") == 3
    # Overlong, surrogate, and out-of-range forms are excluded by the
    # second byte's range, as in Unicode's well-formed byte sequence table.
    for lead_range in (
        "0xC2 0xE0 WITHIN",
        "0xE0 = IF\n        0x0F AND 2 0xA0 0xBF",
        "0xED = IF\n        0x0F AND 2 0x80 0x9F",
        "0xF0 = IF\n        0x07 AND 3 0x90 0xBF",
        "0xF4 = IF\n        0x07 AND 3 0x80 0x8F",
    ):
        assert lead_range in lead


def test_cell_width_is_pure_over_generated_tables() -> None:
    source = CELL_WIDTH.read_text(encoding="utf-8")
    width = _definition(source, "CW-WIDTH")
    projection = _definition(source, "CW-CELL-CP-WITH")
    projection_wrapper = _definition(source, "CW-CELL-CP")

    assert "REQUIRE unicode-props.f" in source
    assert "REQUIRE grapheme.f" in source
    assert "UP-PROPS" in width and "UP-WIDTH" in width
    assert "UTF8-DISPLAY-CP" in projection
    assert "UP-WIDTH 1 <>" in projection
    assert "CW-CELL-CP-WITH" in projection_wrapper
    assert _definition(source, "CW-SWIDTH").count("GR-SWIDTH") == 1
    # The hand-written range tables are gone: widths come only from the
    # generated Unicode 15.1.0 tables.
    assert "_CW-PAIR," not in source
    assert "_CW-BSEARCH-WITH" not in source

    closure = width + projection
    for word in (
        "WITH-GUARD",
        "YIELD",
        "YIELD?",
        "PAUSE",
        "ALLOCATE",
        "RESIZE",
        "FREE",
        "CATCH",
        "THROW",
        "EXECUTE",
    ):
        assert not _has_token(closure, word)
    for prefix in ("SCR-", "TASK-", "SEM-", "EVT-"):
        assert prefix not in closure


def test_reentrant_helper_ownership_is_documented() -> None:
    utf8 = UTF8_DOC.read_text(encoding="utf-8")
    width = CELL_WIDTH_DOC.read_text(encoding="utf-8")

    for phrase in (
        "UTF8-DECODE-WITH",
        "UTF8-DECODE-STATE-SIZE",
        "caller-owned state",
        "overlap it with the\nsource buffer",
        "maximal subpart",
    ):
        assert phrase in utf8
    assert re.search(r"must\s+not share", utf8)

    for phrase in (
        "CW-WIDTH",
        "CW-SWIDTH",
        "CW-CELL-CP",
        "APT-1-TEXT.md",
        "unicode-tables.f",
    ):
        assert phrase in width


def test_utf8_private_span_consumers_start_at_live_decode_state() -> None:
    for path in (STREAMS_SOURCE_STORE, STREAMS_OBSERVATION_STORE):
        source = path.read_text(encoding="utf-8")
        assert "_UD-CP" not in source
        assert (
            "_UTF8-DECODE-STATE\n"
            "[DEFINED] _utf8-guard [IF]\n"
            "    _utf8-guard _GRD-SIZE-SPIN +"
            in source
        )


def test_text_draw_uses_one_bounded_non_yielding_plane_borrow() -> None:
    source = DRAW.read_text(encoding="utf-8")
    run = _definition(source, "_DRW-TEXT-RUN")
    prefix = _definition(source, "_DRW-TEXT-SKIP-LEFT")
    row_visible = _definition(source, "_DRW-TEXT-ROW-VISIBLE?")
    body = _definition(source, "_DRW-TEXT-BODY")
    next_cp = _definition(source, "_DRW-TEXT-NEXT")
    make_cell = _definition(source, "_DRW-MAKE-CELL")
    plane_set = _definition(source, "_DRW-PLANE-SET")
    transaction = _definition(source, "_DRW-TEXT-TRANSACTION")
    clear = _definition(source, "_DRW-TEXT-CLEAR")

    assert "CREATE _DRW-TEXT-UTF8-STATE UTF8-DECODE-STATE-SIZE ALLOT" in source
    assert "CREATE _DRW-TEXT-CW-STATE CW-STATE-SIZE ALLOT" in source
    assert "UTF8-DECODE-WITH" in next_cp
    assert not _has_token(next_cp, "UTF8-DECODE")
    assert "_DRW-TEXT-SKIP-LEFT IF" in run
    assert run.count("_DRW-WITH-BACK-MUTATION") == 1
    assert run.index("_DRW-TEXT-SKIP-LEFT IF") < run.index(
        "['] _DRW-TEXT-BODY _DRW-WITH-BACK-MUTATION"
    )
    assert "_DRW-WITH-BACK-MUTATION" not in prefix
    assert "DUP _DRW-TEXT-U @ U< 0= IF DROP 0 EXIT THEN" in prefix
    assert "0 _DRW-ORIGIN-COL @ - MAX" in prefix

    assert "_DRW-TEXT-ROW-VISIBLE? 0= IF EXIT THEN" in body
    assert "_DRW-LOCAL-ROW-LOW >=" in row_visible
    assert "_DRW-LOCAL-ROW-HIGH < AND" in row_visible
    assert "WITHIN" not in row_visible
    for required in (
        "_DRW-LOCAL-COL-LOW",
        "_DRW-LOCAL-COL-HIGH",
        "_DRW-PLANE-COLS @ _DRW-TEXT-BUDGET !",
        "_DRW-TEXT-BUDGET @ 0> AND",
        "CW-CELL-CP-WITH",
        "_DRW-MAKE-CELL",
        "_DRW-PLANE-SET",
    ):
        assert required in body
    first_decode = body.index("_DRW-TEXT-NEXT")
    assert body.index("_DRW-TEXT-ROW-VISIBLE? 0= IF EXIT THEN") < first_decode
    assert body.index("_DRW-TEXT-COL @ _DRW-TEXT-HIGH @ >= IF EXIT THEN") < first_decode
    assert body.index("_DRW-PLANE-COLS @ _DRW-TEXT-BUDGET !") < first_decode
    assert body.count("-1 _DRW-TEXT-BUDGET +!") == 1
    for forbidden in (
        "SCR-",
        "DRW-CHAR",
        "WITH-GUARD",
        "YIELD",
        "YIELD?",
        "PAUSE",
        "ALLOCATE",
        "FREE",
        "RESIZE",
        "EXECUTE",
    ):
        assert forbidden not in body
    assert not _has_token(body, "UTF8-DECODE")
    assert not _has_token(body, "CW-CELL-CP")

    helper_closure = body + row_visible + next_cp + make_cell + plane_set
    for axis in ("ROW", "COL"):
        helper_closure += _definition(source, f"_DRW-LOCAL-{axis}-LOW")
        helper_closure += _definition(source, f"_DRW-LOCAL-{axis}-HIGH")
    for forbidden in (
        "WITH-GUARD",
        "YIELD",
        "YIELD?",
        "PAUSE",
        "ALLOCATE",
        "FREE",
        "RESIZE",
        "CATCH",
        "THROW",
        "EXECUTE",
        "DRW-CHAR",
    ):
        assert not _has_token(helper_closure, forbidden)
    # In the body dynamic extent these dimension helpers take their cached
    # active-plane branch; the SCR fallback remains for ordinary scalar use.
    for dimension, cached, fallback in (
        ("_DRW-SCREEN-ROWS", "_DRW-PLANE-ROWS @", "SCR-H"),
        ("_DRW-SCREEN-COLS", "_DRW-PLANE-COLS @", "SCR-W"),
    ):
        definition = _definition(source, dimension)
        assert "_DRW-PLANE-ACTIVE @ IF" in definition
        assert definition.index(cached) < definition.index("ELSE")
        assert definition.index("ELSE") < definition.index(fallback)

    assert "['] _DRW-TEXT-RUN CATCH" in transaction
    assert transaction.index("_DRW-TEXT-CLEAR") < transaction.index("THROW")
    for state, size in (
        ("_DRW-TEXT-UTF8-STATE", "UTF8-DECODE-STATE-SIZE"),
        ("_DRW-TEXT-CW-STATE", "CW-STATE-SIZE"),
    ):
        assert f"{state} {size} 0 FILL" in clear
    assert "0 _DRW-TEXT-A !" in clear
    assert "0 _DRW-TEXT-U !" in clear
    assert "0 _DRW-TEXT-BUDGET !" in clear

    assert "0 _DRW-TEXT-START" in _definition(source, "DRW-TEXT")
    assert "-1 _DRW-TEXT-START" in _definition(
        source, "DRW-TEXT-UNTRUSTED"
    )


def _decode_one(data: bytes, pos: int) -> tuple[int, int]:
    """Decode one scalar, replacing one maximal ill-formed subpart."""

    replacement = 0xFFFD
    if pos == len(data):
        return replacement, pos
    b0 = data[pos]
    if b0 < 0x80:
        return b0, pos + 1
    ranges = {
        **{lead: (1, 0x80, 0xBF) for lead in range(0xC2, 0xE0)},
        0xE0: (2, 0xA0, 0xBF),
        **{lead: (2, 0x80, 0xBF) for lead in range(0xE1, 0xF0) if lead != 0xED},
        0xED: (2, 0x80, 0x9F),
        0xF0: (3, 0x90, 0xBF),
        **{lead: (3, 0x80, 0xBF) for lead in range(0xF1, 0xF4)},
        0xF4: (3, 0x80, 0x8F),
    }
    if b0 not in ranges:
        return replacement, pos + 1
    need, low, high = ranges[b0]
    cp = b0 & {1: 0x1F, 2: 0x0F, 3: 0x07}[need]
    for index in range(1, need + 1):
        if pos + index >= len(data):
            return replacement, pos + index
        byte = data[pos + index]
        lower, upper = (low, high) if index == 1 else (0x80, 0xBF)
        if not lower <= byte <= upper:
            return replacement, pos + index
        cp = (cp << 6) | (byte & 0x3F)
    return cp, pos + need + 1


def _cell_cp(cp: int) -> int:
    replacement = 0xFFFD
    unsafe = (
        cp < 0
        or cp > 0x10FFFF
        or 0xD800 <= cp <= 0xDFFF
        or 0 <= cp < 0x20
        or 0x7F <= cp < 0xA0
        or cp in {0x061C, 0xFEFF}
        or 0x200B <= cp < 0x2010
        or 0x2028 <= cp < 0x202F
        or 0x2060 <= cp < 0x2070
        or 0x0300 <= cp <= 0x036F
        or 0xFE00 <= cp <= 0xFE0F
        or 0x4E00 <= cp <= 0x9FFF
        or 0x1F300 <= cp <= 0x1FAFF
    )
    return replacement if unsafe else cp


def _bounds(
    cols: int,
    rows: int,
    clip: tuple[int, int, int, int, int, int] | None,
) -> tuple[int, int, int, int]:
    if clip is None:
        return 0, rows, 0, cols
    origin_row, origin_col, clip_row, clip_col, clip_h, clip_w = clip
    row_low = max(clip_row - origin_row, -origin_row)
    row_high = min(clip_row + clip_h - origin_row, rows - origin_row)
    col_low = max(clip_col - origin_col, -origin_col)
    col_high = min(clip_col + clip_w - origin_col, cols - origin_col)
    return row_low, row_high, col_low, col_high


def _physical(
    row: int,
    col: int,
    clip: tuple[int, int, int, int, int, int] | None,
) -> tuple[int, int]:
    if clip is None:
        return row, col
    return row + clip[0], col + clip[1]


def _scalar_text(
    data: bytes,
    row: int,
    col: int,
    cols: int,
    rows: int,
    clip: tuple[int, int, int, int, int, int] | None,
    untrusted: bool,
) -> dict[tuple[int, int], int]:
    out: dict[tuple[int, int], int] = {}
    pos = 0
    current = col
    while pos < len(data):
        cp, pos = _decode_one(data, pos)
        if untrusted:
            cp = _cell_cp(cp)
        physical_row, physical_col = _physical(row, current, clip)
        if clip is None:
            admitted = 0 <= physical_row < rows and 0 <= physical_col < cols
        else:
            _, _, clip_row, clip_col, clip_h, clip_w = clip
            admitted = (
                clip_row <= physical_row < clip_row + clip_h
                and clip_col <= physical_col < clip_col + clip_w
                and 0 <= physical_row < rows
                and 0 <= physical_col < cols
            )
        if admitted:
            out[(physical_row, physical_col)] = cp
        current += 1
    return out


def _borrowed_text(
    data: bytes,
    row: int,
    col: int,
    cols: int,
    rows: int,
    clip: tuple[int, int, int, int, int, int] | None,
    untrusted: bool,
) -> tuple[dict[tuple[int, int], int], int, int, bool]:
    row_low, row_high, col_low, col_high = _bounds(cols, rows, clip)
    pos = 0
    prefix_work = 0
    if not data:
        return {}, 0, 0, False
    if col < col_low:
        distance = col_low - col
        if distance >= len(data):
            return {}, 0, 0, False
        while distance > 0 and pos < len(data):
            _, pos = _decode_one(data, pos)
            prefix_work += 1
            distance -= 1
        if distance:
            return {}, prefix_work, 0, False
        col = col_low
    if not (row_low <= row < row_high) or not (col_low <= col < col_high):
        return {}, prefix_work, 0, True
    out: dict[tuple[int, int], int] = {}
    body_work = 0
    budget = cols
    while pos < len(data) and col < col_high and budget > 0:
        cp, pos = _decode_one(data, pos)
        if untrusted:
            cp = _cell_cp(cp)
        out[_physical(row, col, clip)] = cp
        col += 1
        budget -= 1
        body_work += 1
    return out, prefix_work, body_work, True


def test_one_borrow_text_is_visible_equivalent_to_scalar_drawing() -> None:
    mixed = b"A\xc3\xa9\xe2\x98\xba\xf0\x9f\x98\x80\x80Z"
    untrusted = b"A\x01\xcc\x81\xe4\xb8\x96\xf0\x9f\x98\x80Z"
    cases = (
        (mixed, 1, 2, 12, 4, None, False),
        (mixed, 1, -3, 7, 4, None, False),
        (mixed, -1, 0, 7, 4, None, False),
        (mixed, 1, 6, 7, 4, None, False),
        (mixed, 0, -2, 8, 4, (-1, -2, 0, 0, 3, 6), False),
        (mixed, 0, 0, 8, 4, (1, 2, 1, 4, 2, 3), False),
        (mixed, 4, 0, 8, 4, (1, 2, 1, 2, 2, 4), False),
        (mixed, 0, 0, 8, 4, (10, 2, 10, 2, 2, 4), False),
        (mixed, 0, 0, 8, 4, (1, 20, 1, 20, 2, 4), False),
        (untrusted, 0, -1, 8, 2, None, True),
        (b"\xc3\xa9A", 0, -1, 4, 1, None, False),
        (mixed, 0, 0, 0, 0, None, False),
    )
    for data, row, col, cols, rows, clip, project in cases:
        expected = _scalar_text(data, row, col, cols, rows, clip, project)
        actual, _, body_work, _ = _borrowed_text(
            data, row, col, cols, rows, clip, project
        )
        assert actual == expected
        assert body_work <= max(cols, 0)


def test_clipped_prefix_and_visible_body_have_independent_work_bounds() -> None:
    data = b"x" * 1000
    actual, prefix_work, body_work, borrowed = _borrowed_text(
        data, 0, -900, 20, 1, None, False
    )
    assert prefix_work == 900
    assert body_work == 20
    assert len(actual) == 20
    assert borrowed

    # The source-byte upper bound rejects an extreme signed coordinate
    # without attempting a coordinate-sized loop or taking the plane borrow.
    actual, prefix_work, body_work, borrowed = _borrowed_text(
        b"short", 0, -(1 << 63), 280, 84, None, False
    )
    assert actual == {}
    assert prefix_work == 0
    assert body_work == 0
    assert not borrowed


def test_text_prefix_skips_codepoints_and_preserves_malformed_boundaries() -> None:
    actual, prefix_work, body_work, borrowed = _borrowed_text(
        b"\xe2\x82\xacA\xffB", 0, -1, 8, 1, None, False
    )
    assert actual == {(0, 0): ord("A"), (0, 1): 0xFFFD, (0, 2): ord("B")}
    assert (prefix_work, body_work, borrowed) == (1, 3, True)

    # The truncated three-byte candidate is one maximal subpart and one
    # U+FFFD. After that one clipped codepoint, only the ASCII tail remains.
    actual, prefix_work, body_work, borrowed = _borrowed_text(
        b"\xe2\x82A", 0, -1, 8, 1, None, False
    )
    assert actual == {(0, 0): ord("A")}
    assert (prefix_work, body_work, borrowed) == (1, 1, True)

    actual, prefix_work, body_work, borrowed = _borrowed_text(
        b"AB" + b"x" * 10000, 0, 278, 280, 1, None, False
    )
    assert actual == {(0, 278): ord("A"), (0, 279): ord("B")}
    assert (prefix_work, body_work, borrowed) == (0, 2, True)


def test_bounded_untrusted_projection_keeps_one_cell_per_visible_codepoint() -> None:
    data = b"\n\xcc\x81\xe2\x80\x8d\xef\xb8\x8f\xe4\xb8\x96\xe2\x98\x83"
    actual, prefix_work, body_work, borrowed = _borrowed_text(
        data, 0, 0, 10, 1, None, True
    )
    assert actual == {
        (0, 0): 0xFFFD,  # control
        (0, 1): 0xFFFD,  # combining mark
        (0, 2): 0xFFFD,  # zero-width joiner
        (0, 3): 0xFFFD,  # variation selector
        (0, 4): 0xFFFD,  # wide CJK codepoint
        (0, 5): 0x2603,  # isolated width-one snowman
    }
    assert (prefix_work, body_work, borrowed) == (0, 6, True)

    actual, prefix_work, body_work, borrowed = _borrowed_text(
        b"visible", -1, 0, 8, 3, None, True
    )
    assert actual == {}
    assert (prefix_work, body_work, borrowed) == (0, 0, True)
