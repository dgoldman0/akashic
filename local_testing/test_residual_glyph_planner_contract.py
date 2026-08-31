"""Seconds-only structural and byte oracle for residual GLYPH_RUN planning."""

from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/rich-terminal/residual-glyph-planner.f"
SCREEN = ROOT / "akashic/tui/screen.f"


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_residual_plan_is_byte_exact_linear_and_claim_exclusive() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())

    assert "248 CONSTANT RGRP-REQUEST-SIZE" in source
    request_fields = (
        "OWNER",
        "OWNER-GEN",
        "SURFACE-W",
        "SURFACE-H",
        "REGION-ID",
        "REGION-X",
        "REGION-Y",
        "REGION-W",
        "REGION-H",
        "REGION-Z",
        "REGION-F",
        "OBJECT-Z",
        "FIRST-ID",
        "MAX-RUN-U",
        "CLAIMS-A",
        "CLAIMS-U",
        "HEADS-A",
        "HEADS-U",
        "EVENTS-A",
        "EVENTS-U",
        "DIFF-A",
        "DIFF-U",
        "PLAN-A",
        "PLAN-U",
        "ITEMS-A",
        "ITEMS-U",
        "REFS-A",
        "REFS-U",
        "TEXT-A",
        "TEXT-U",
        "RESERVED",
    )
    for offset, field in enumerate(request_fields):
        word = _word(source, f"_RGRP-Q.{field}")
        if offset:
            assert f"{offset * 8} +" in word
        else:
            assert "+" not in word

    packed_request = struct.pack("<31Q", *range(1, 31), 0)
    assert len(packed_request) == 248
    assert struct.unpack_from("<Q", packed_request, 88)[0] == 12
    assert struct.unpack_from("<Q", packed_request, 104)[0] == 14
    assert struct.unpack_from("<Q", packed_request, 240)[0] == 0

    assert "24 CONSTANT RGRP-EVENT-SIZE" in source
    assert "16 CONSTANT RGRP-TEXT-REF-SIZE" in source
    event = struct.pack("<QQq", 7, 3, -1)
    text_ref = struct.pack("<2Q", 8, 1)
    assert len(event) == 24
    assert struct.unpack("<QQq", event) == (7, 3, -1)
    assert len(text_ref) == 16
    assert struct.unpack("<2Q", text_ref) == (8, 1)

    # Two claims from distinct attachment/generation families overlap.  The
    # tiny model uses the same start/removal events and persistent column
    # difference bank as the Forth implementation.
    cells = [
        [(ord("A"), 1, 0, 0), (ord("B"), 1, 0, 0),
         (ord("C"), 1, 0, 0), (ord("D"), 1, 0, 0),
         (0, 1, 0, 0), (ord("E"), 1, 0, 0), (ord("F"), 2, 0, 0)],
        [(ord(char), 1, 0, 0) for char in "abcdefg"],
    ]
    claims = [
        (0xA1, 4, 0, 1, 1, 3),
        (0xB2, 9, 0, 2, 2, 4),
    ]
    rows, cols, max_run_bytes = 2, 7, 2
    heads = [[] for _ in range(rows + 1)]
    for claim_index, (_attachment, _generation, row0, col0, row1, col1) in enumerate(claims):
        heads[row0].append((claim_index, 1))
        heads[row1].append((claim_index, -1))
    assert sum(map(len, heads)) == 2 * len(claims)

    difference = [0] * (cols + 1)
    refs = []
    runs = []
    text = bytearray()
    reads = 0
    for row in range(rows):
        for claim_index, delta in heads[row]:
            col0, col1 = claims[claim_index][3], claims[claim_index][5]
            difference[col0] += delta
            difference[col1] -= delta
        active = 0
        run = None
        for col in range(cols):
            active += difference[col]
            if active:
                if run is not None:
                    runs.append(run)
                    run = None
                continue
            reads += 1
            cp, fg, bg, attrs = cells[row][col]
            cp = cp or 32
            scalar = chr(cp).encode("utf-8")
            style = (fg, bg, attrs & 0x006F)
            if run is not None and (
                run[2] != style or len(run[3]) + len(scalar) > max_run_bytes
            ):
                runs.append(run)
                run = None
            if run is None:
                run = [row, col, style, bytearray()]
            run[3].extend(scalar)
        if run is not None:
            runs.append(run)
        active += difference[cols]
        assert active == 0

    first_object = 100
    items = bytearray()
    aligned_text = 0
    for run_index, (row, col, style, run_text) in enumerate(runs):
        offset = len(text)
        text.extend(run_text)
        refs.append((offset, len(run_text)))
        aligned_text += (len(run_text) + 7) & ~7
        fg, bg, attrs = style
        items.extend(
            struct.pack(
                "<15Q",
                first_object + run_index,
                0,
                row,
                col,
                1,
                len(run_text),
                rows,
                cols,
                3,
                (1 << 64) - 1,
                fg,
                bg,
                attrs,
                len(run_text),
                0,
            )
        )

    assert reads == rows * cols - 5
    assert [(run[0], run[1], bytes(run[3])) for run in runs] == [
        (0, 0, b"A"),
        (0, 4, b" E"),
        (0, 6, b"F"),
        (1, 0, b"ab"),
        (1, 4, b"ef"),
        (1, 6, b"g"),
    ]
    assert bytes(text) == b"A EFabefg"
    assert refs == [(0, 1), (1, 2), (3, 1), (4, 2), (6, 2), (8, 1)]
    assert aligned_text == 6 * 8
    assert len(items) == 6 * 120
    assert struct.unpack_from("<Q", items, 5 * 120)[0] == 105

    packed_refs = b"".join(struct.pack("<2Q", *ref) for ref in refs)
    plan = struct.pack(
        "<14Q",
        1,
        2,
        cols,
        rows,
        9,
        0,
        0,
        cols,
        rows,
        0,
        3,
        0x2000,
        len(items),
        0,
    )
    assert len(packed_refs) == 6 * 16
    assert len(plan) == 112
    assert struct.unpack_from("<Q", plan, 96)[0] == 6 * 120

    for public in (
        "RGRP-REQUEST-BYTES",
        "RGRP-REQUEST-CLEAR",
        "RGRP-REQUEST-IDENTITY!",
        "RGRP-REQUEST-REGION!",
        "RGRP-REQUEST-LIMIT!",
        "RGRP-REQUEST-CLAIMS!",
        "RGRP-REQUEST-WORK!",
        "RGRP-REQUEST-OUTPUT!",
        "RGRP-TEXT-REF-BYTES",
        "RGRP-BUILD",
        "RGRP-BUILD-FROM-PLANE",
    ):
        assert re.search(rf"(?m)^: {re.escape(public)}(?=\s)", source)

    for forbidden in (
        "ALLOCATE",
        "RTE-GLYPH-RUN-PLAN-VALID?",
        "RTE-GLYPH-RUN-PREFLIGHT",
        "RTE-CONTROL",
        "RTERM-",
        "RTAPT-",
        "DESK-",
    ):
        assert forbidden not in code
    assert re.search(r"(?m)^\s*FREE\b", code) is None
    assert "SCR-GET" not in code
    load_cell = _word(source, "_RGRP-LOAD-CELL?")
    assert "_RGRP-PLANE-A" in load_cell
    assert "_RGRP-PLANE-W" in load_cell
    assert "_RGRP-ENCODE-CELL?" in load_cell
    encode_cell = _word(source, "_RGRP-ENCODE-CELL?")
    assert "0x20 >=" in encode_cell
    assert "0x7E <=" in encode_cell
    assert encode_cell.index("_RGRP-UTF8 C!") < encode_cell.index("ELSE")
    assert "CW-CELL-CP" in encode_cell
    assert "UTF8-ENCODE" in encode_cell
    scoped = _word(source, "_RGRP-BUILD-SCOPED")
    assert "SCR-WITH-BACK-PLANE" in scoped
    supplied = _word(source, "RGRP-BUILD-FROM-PLANE")
    assert "_RGRP-PLANE-H ! _RGRP-PLANE-W ! _RGRP-PLANE-A !" in supplied
    assert "_RGRP-BUILD-FROM-SET-PLANE" in supplied
    assert "SCR-WITH-BACK-PLANE" not in supplied
    bound_plane = _word(source, "_RGRP-BUILD-FROM-SET-PLANE")
    assert "_RGRP-PLANE-SPAN?" in bound_plane
    assert "_RGRP-BUILD-BODY" in bound_plane
    assert "_RGRP-SCRUB" in bound_plane
    authorized = _word(source, "_RGRP-BUILD-FROM-AUTHORIZED-PLANE")
    assert "-1 _RGRP-SCREEN-AUTHORIZED !" in authorized
    assert "SCR-" not in authorized

    authority = _word(source, "_RGRP-RANGE-AUTHORITY?")
    body = _word(source, "_RGRP-BUILD-BODY")
    failure = _word(source, "_RGRP-FAIL-RESULT")
    clear = _word(source, "_RGRP-CLEAR-MUTABLE")
    scrub = _word(source, "_RGRP-SCRUB")
    claims_word = _word(source, "_RGRP-BUILD-EVENTS?")
    activate = _word(source, "_RGRP-ACTIVATE-WORK?")
    event_claim = _word(source, "_RGRP-EVENT-CLAIM?")
    publish = _word(source, "_RGRP-PUBLISH-PLAN?")

    assert body.index("_RGRP-RANGE-AUTHORITY?") < body.index("_RGRP-SCALARS?")
    assert body.index("_RGRP-SCAN?") < body.index("_RGRP-PUBLISH-PLAN?")
    assert authority.count("_RGRP-SCREEN-DISJOINT?") == 1
    assert "_RGRP-SCREEN-AUTHORIZED @ 0= IF" in authority
    assert _word(source, "_RGRP-SCREEN-DISJOINT?").count(
        "SCR-STORAGE-DISJOINT?"
    ) == 9
    assert "_RGRP-CLEAR-MUTABLE" in failure
    for bank in ("HEADS", "EVENTS", "DIFF", "PLAN", "ITEMS", "REFS", "TEXT"):
        assert f"_RGRP-{bank}-A @ _RGRP-{bank}-U @" in clear
    variables = set(re.findall(r"(?m)^VARIABLE (_RGRP-[A-Z0-9_-]+)", source))
    scrubbed = set(re.findall(r"0 (_RGRP-[A-Z0-9_-]+) !", scrub))
    assert variables - scrubbed == {"_RGRP-OWNED-LIMIT"}

    assert claims_word.count("0 ?DO") == 1
    assert claims_word.count("_RGRP-CLAIM-VALID?") == 1
    assert claims_word.count("_RGRP-EVENT-CLAIM?") == 1
    claim_valid = _word(source, "_RGRP-CLAIM-VALID?")
    assert "_RGRP-C.SOURCE @ DUP 0= SWAP 0< OR IF 0 EXIT THEN" in claim_valid
    assert "UMSN-SOURCE-UIDL" not in claim_valid
    assert "_RGRP-C.SUBKEY" not in claim_valid
    assert "_RGRP-PRIOR" not in source
    assert "_RGRP-REGION-H @ 1 _RGRP-UADD?" in activate
    assert "_RGRP-REGION-W @ 1 _RGRP-UADD?" in activate
    assert "_RGRP-EVENT-COUNT @ 2 _RGRP-UADD?" in event_claim
    assert "_RGRP-RUN-COUNT @ 0= IF -1 EXIT THEN" in publish
    assert "_RGRP-PUBLISH-PLAN?" not in _word(source, "_RGRP-SCAN?")
    assert "CELL-A-BLINK" in _word(source, "_RGRP-LOAD-CELL?")
    assert "CW-CELL-CP" in encode_cell
    assert "UTF8-ENCODE" in encode_cell
    assert "TUI-PALETTE>RGBA" not in _word(source, "_RGRP-STYLE-SAME?")
    assert _word(source, "_RGRP-WRITE-ITEM").count("TUI-PALETTE>RGBA") == 2

    screen = SCREEN.read_text(encoding="utf-8")
    borrow = _word(screen, "SCR-WITH-BACK-PLANE")
    assert "_SCR-O-BACK" in borrow
    assert "_SCR-O-W" in borrow
    assert "_SCR-O-H" in borrow
    assert "_SCR-BACK-PLANE-XT @ EXECUTE" in borrow
    assert "' SCR-WITH-BACK-PLANE CONSTANT _scr-with-back-plane-xt" in screen
    assert re.search(
        r"(?ms)^: SCR-WITH-BACK-PLANE\s*\n"
        r"\s+_scr-with-back-plane-xt _scr-guard WITH-GUARD ;$",
        screen,
    )

    loop_section = source[source.index(": _RGRP-BUILD-EVENTS?") :]
    loop_code = "\n".join(line.split("\\", 1)[0] for line in loop_section.splitlines())
    assert re.search(r"(?<![A-Z0-9_-])(?:>R|R@|R>)(?![A-Z0-9_-])", loop_code) is None
