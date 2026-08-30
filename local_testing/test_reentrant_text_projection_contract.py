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
    continuation = _definition(source, "_UTF8-DECODE-WITH-CONT")
    validation = _definition(source, "_UTF8-DECODE-WITH-VALID?")
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
        "32 CONSTANT UTF8-DECODE-STATE-SIZE",
    ):
        assert declaration in source

    assert "CREATE _UTF8-DECODE-STATE UTF8-DECODE-STATE-SIZE ALLOT" in source
    assert "_UTF8-DECODE-STATE UTF8-DECODE-WITH" in wrapper
    assert "VARIABLE _UD-" not in source

    # Every continuation is unrolled: the return stack always contains the
    # caller state, never a DO-loop index, and each source byte is read once.
    for offset in (1, 2, 3):
        assert f"{offset} R@ _UTF8-DECODE-WITH-CONT" in decode
    assert not _has_token(decode, "DO")
    assert not _has_token(decode, "LOOP")
    assert continuation.count("C@") == 1
    assert "_UTF8-CONT?" in continuation
    assert "_UTF8-DS-CP + !" in continuation

    closure = (
        decode
        + failure
        + continuation
        + validation
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


def test_utf8_caller_state_path_preserves_failure_and_scalar_rules() -> None:
    source = UTF8.read_text(encoding="utf-8")
    decode = _definition(source, "UTF8-DECODE-WITH")
    failure = _definition(source, "_UTF8-DECODE-WITH-FAIL")
    valid = _definition(source, "_UTF8-DECODE-WITH-VALID?")

    assert "UTF8-REPLACEMENT -ROT" in failure
    assert "_UTF8-DS-A + @ 1+" in failure
    assert "_UTF8-DS-L + @ 1-" in failure
    assert decode.count("_UTF8-DECODE-WITH-FAIL EXIT") == 5
    for boundary in ("0x10FFFF", "0xD800", "0xDFFF", "0x80", "0x800", "0x10000"):
        assert boundary in valid
    assert "_UTF8-DECODE-WITH-VALID? 0= IF" in decode
    assert "UTF8-REPLACEMENT R@ _UTF8-DS-CP + !" in decode


def test_cell_width_has_reentrant_search_and_projection_paths() -> None:
    source = CELL_WIDTH.read_text(encoding="utf-8")
    utf8_source = UTF8.read_text(encoding="utf-8")
    search = _definition(source, "_CW-BSEARCH-WITH")
    compare = _definition(source, "_CW-ENTRY-CMP")
    width = _definition(source, "CW-WIDTH-WITH")
    projection = _definition(source, "CW-CELL-CP-WITH")
    width_wrapper = _definition(source, "CW-WIDTH")
    projection_wrapper = _definition(source, "CW-CELL-CP")

    for declaration in (
        "0 CONSTANT _CW-BS-LO",
        "8 CONSTANT _CW-BS-HI",
        "16 CONSTANT _CW-BS-MID",
        "24 CONSTANT CW-STATE-SIZE",
    ):
        assert declaration in source

    assert "CREATE _CW-STATE CW-STATE-SIZE ALLOT" in source
    assert "_CW-STATE CW-WIDTH-WITH" in width_wrapper
    assert "_CW-STATE CW-CELL-CP-WITH" in projection_wrapper
    assert "VARIABLE _CB-" not in source

    assert "BEGIN" in search and "AGAIN" in search
    assert not _has_token(search, "DO")
    assert not _has_token(search, "LOOP")
    assert "_CW-ENTRY-CMP" in search
    assert "_CW-ZERO-TBL _CW-ZERO-N R@ _CW-BSEARCH-WITH" in width
    assert "_CW-WIDE-TBL _CW-WIDE-N R@ _CW-BSEARCH-WITH" in width
    assert "UTF8-DISPLAY-CP" in projection
    assert "R@ CW-WIDTH-WITH" in projection

    closure = (
        search
        + compare
        + width
        + projection
        + _definition(utf8_source, "UTF8-DISPLAY-CP")
        + _definition(utf8_source, "UTF8-DISPLAY-UNSAFE?")
    )
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
    assert "_CW-STATE" not in width + projection

    assert "' CW-WIDTH-WITH" not in source
    assert "' CW-CELL-CP-WITH" not in source
    assert ": CW-WIDTH   _cw-width-xt  _cw-guard WITH-GUARD ;" in source
    assert ": CW-CELL-CP _cw-cell-cp-xt _cw-guard WITH-GUARD ;" in source


def test_reentrant_helper_ownership_is_documented() -> None:
    utf8 = UTF8_DOC.read_text(encoding="utf-8")
    width = CELL_WIDTH_DOC.read_text(encoding="utf-8")

    for phrase in (
        "UTF8-DECODE-WITH",
        "UTF8-DECODE-STATE-SIZE",
        "caller-owned state",
        "overlap it with the\nsource buffer",
    ):
        assert phrase in utf8
    assert re.search(r"must\s+not share", utf8)

    for phrase in (
        "CW-WIDTH-WITH",
        "CW-CELL-CP-WITH",
        "CW-STATE-SIZE",
        "caller-owned scratch",
        "must not overlap the read-only\nrange tables",
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
    replacement = 0xFFFD
    if pos == len(data):
        return replacement, pos
    b0 = data[pos]
    if b0 < 0x80:
        need = 1
    elif b0 < 0xC0:
        need = 0
    elif b0 < 0xE0:
        need = 2
    elif b0 < 0xF0:
        need = 3
    elif b0 < 0xF8:
        need = 4
    else:
        need = 0
    if need == 0 or len(data) - pos < need:
        return replacement, pos + 1
    continuation = data[pos + 1 : pos + need]
    if any(byte & 0xC0 != 0x80 for byte in continuation):
        return replacement, pos + 1
    masks = {1: 0x7F, 2: 0x1F, 3: 0x0F, 4: 0x07}
    cp = b0 & masks[need]
    for byte in continuation:
        cp = (cp << 6) | (byte & 0x3F)
    minimum = {1: 0, 2: 0x80, 3: 0x800, 4: 0x10000}[need]
    if cp < minimum or 0xD800 <= cp <= 0xDFFF or cp > 0x10FFFF:
        cp = replacement
    return cp, pos + need


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

    # The malformed three-byte candidate advances one byte. After one
    # clipped codepoint, its continuation byte and ASCII tail remain visible.
    actual, prefix_work, body_work, borrowed = _borrowed_text(
        b"\xe2\x82A", 0, -1, 8, 1, None, False
    )
    assert actual == {(0, 0): 0xFFFD, (0, 1): ord("A")}
    assert (prefix_work, body_work, borrowed) == (1, 2, True)

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
