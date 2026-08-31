"""Seconds-only structural and byte oracle for UIDL semantic claims."""

from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/rich-terminal/uidl-claim-ledger.f"


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_claim_ledger_is_single_pass_caller_bounded_and_byte_exact() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    code = "\n".join(line.split("\\", 1)[0] for line in source.splitlines())

    assert "112 CONSTANT RUCL-REQUEST-SIZE" in source
    assert "80 CONSTANT RUCL-CLAIM-SIZE" in source
    assert "-1 1 RSHIFT CONSTANT _RUCL-SIGNED-MAX" in source
    assert "0xFFFFFFFF CONSTANT _RUCL-U32-MAX" in source
    request_offsets = {
        "ATTACHMENT": 0,
        "SOURCE-GEN": 8,
        "ADMITTED": 16,
        "SURFACE-W": 24,
        "SURFACE-H": 32,
        "CLIP-ROW": 40,
        "CLIP-COL": 48,
        "CLIP-H": 56,
        "CLIP-W": 64,
        "RECORDS-A": 72,
        "RECORDS-U": 80,
        "CLAIMS-A": 88,
        "CLAIMS-U": 96,
        "RESERVED": 104,
    }
    for field, offset in request_offsets.items():
        word = _word(source, f"_RUCL-Q.{field}")
        if offset:
            assert f"{offset} +" in word
        else:
            assert "+" not in word

    claim_offsets = {
        "ATTACHMENT": 0,
        "GENERATION": 8,
        "SOURCE": 16,
        "INDEX": 24,
        "SUBKEY": 32,
        "Z": 40,
        "ROW0": 48,
        "COL0": 56,
        "ROW1": 64,
        "COL1": 72,
    }
    for field, offset in claim_offsets.items():
        word = _word(source, f"_RUCL-C.{field}")
        if offset:
            assert f"{offset} +" in word
        else:
            assert "+" not in word

    request = struct.pack(
        "<5Q2q7Q",
        0xA77A,
        9,
        4,
        8,
        4,
        -1,
        2,
        5,
        7,
        0x1000,
        4 * 192,
        0x2000,
        2 * 80,
        0,
    )
    assert len(request) == 112
    assert struct.unpack_from("<q", request, 40)[0] == -1
    assert struct.unpack_from("<q", request, 48)[0] == 2
    assert struct.unpack_from("<Q", request, 104)[0] == 0

    # This mirrors the ledger's one-pass PAINTABLE selection and half-open
    # intersection.  Canonical source order is preserved; nonpaintable and
    # fully clipped records consume no output capacity.
    records = [
        (3, True, -2, -3, 5, 10, 5),
        (7, False, 0, 2, 2, 2, 6),
        (11, True, 8, 2, 1, 1, 7),
        (19, True, 3, 7, 4, 5, 8),
    ]
    attachment, generation, source_kind = 0xA77A, 9, 1
    surface_rows, surface_cols = 4, 8
    clip_row0, clip_col0, clip_row1, clip_col1 = -1, 2, 4, 9
    claims = []
    for index, paintable, row, col, height, width, z in records:
        if not paintable:
            continue
        row0 = max(row, clip_row0, 0)
        col0 = max(col, clip_col0, 0)
        row1 = min(row + height, clip_row1, surface_rows)
        col1 = min(col + width, clip_col1, surface_cols)
        if row0 < row1 and col0 < col1:
            claims.append(
                (
                    attachment,
                    generation,
                    source_kind,
                    index,
                    0,
                    z,
                    row0,
                    col0,
                    row1,
                    col1,
                )
            )
    assert claims == [
        (0xA77A, 9, 1, 3, 0, 5, 0, 2, 3, 7),
        (0xA77A, 9, 1, 19, 0, 8, 3, 7, 4, 8),
    ]
    packed_claims = b"".join(struct.pack("<10Q", *claim) for claim in claims)
    assert len(packed_claims) == 2 * 80
    assert struct.unpack_from("<Q", packed_claims, 16)[0] == source_kind
    assert struct.unpack_from("<4Q", packed_claims, 48) == (0, 2, 3, 7)
    assert struct.unpack_from("<Q", packed_claims, 80 + 24)[0] == 19

    for public in (
        "RUCL-REQUEST-BYTES",
        "RUCL-REQUEST-CLEAR",
        "RUCL-REQUEST-ADMISSION!",
        "RUCL-REQUEST-GEOMETRY!",
        "RUCL-REQUEST-STORAGE!",
        "RUCL-CLAIM-BYTES",
        "RUCL-ADMITTED-RECTANGLE!",
        "RUCL-BUILD",
    ):
        assert re.search(rf"(?m)^: {re.escape(public)}(?=\s)", source)
    assert "ALLOCATE" not in code
    assert re.search(r"(?m)^\s*FREE\b", code) is None
    for forbidden in ("SCR-GET", "RTE-", "RTERM-", "RTAPT-", "DESK-"):
        assert forbidden not in code

    body = _word(source, "_RUCL-BUILD-BODY")
    refusal = _word(source, "_RUCL-REFUSED-RESULT")
    traversal = _word(source, "_RUCL-BUILD-CLAIMS?")
    traversal_code = "\n".join(
        line.split("\\", 1)[0] for line in traversal.splitlines()
    )
    emit = _word(source, "_RUCL-EMIT?")
    shape = _word(source, "_RUCL-SOURCE-SHAPE?")
    validate = _word(source, "_RUCL-VALIDATE-ONE?")

    assert body.index("_RUCL-RANGE-AUTHORITY?") < body.index("_RUCL-SCALARS?")
    assert body.index("_RUCL-SOURCE-SHAPE?") < body.index("_RUCL-ADMITTED @ 0=")
    assert body.index("_RUCL-ADMITTED @ 0=") < body.index("_RUCL-BUILD-CLAIMS?")
    assert "_RUCL-CLEAR-CLAIMS" in refusal
    assert "_RUCL-RECORD" not in refusal
    assert "_RUCL-RECORD-AT" not in body
    assert "_RUCL-ADMITTED @ _RUCL-RECORD-COUNT @ =" in shape
    assert "_RUCL-RECORDS-U @ 0= IF 0 EXIT THEN" in shape
    assert "DUP _RUCL-INDEX !" not in validate
    assert "_RUCL-R.INDEX @ DUP 0< IF DROP 0 EXIT THEN\n    _RUCL-INDEX !" in validate

    assert traversal_code.count("0 ?DO") == 1
    assert traversal_code.count("_RUCL-VALIDATE-ONE?") == 1
    assert traversal_code.count("_RUCL-EMIT?") == 1
    assert traversal_code.count("UNLOOP EXIT") == 3
    assert re.search(r"(?<![A-Z0-9_-])(?:>R|R@|R>)(?![A-Z0-9_-])", traversal_code) is None
    assert "_RUCL-CLAIM-CAP @ U< 0=" in emit
    assert "_RUCL-SET-CAPACITY" in emit
    assert "_RUCL-SET-CAPACITY" not in shape
    assert code.count("_RUCL-SET-CAPACITY") == 2  # definition plus actual emit
    assert "_RUCL-RECORD @ _RUCL-R.SOURCE @ OVER _RUCL-C.SOURCE !" in emit
    assert "MAX 0 MAX" in _word(source, "_RUCL-CLIP-ONE?")
    assert "_RUCL-SURFACE-H @ MIN" in _word(source, "_RUCL-CLIP-ONE?")
    assert "_RUCL-SURFACE-W @ MIN" in _word(source, "_RUCL-CLIP-ONE?")


def test_exact_admitted_rectangle_constructor_is_generic_and_fail_before_write() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    public = _word(source, "RUCL-ADMITTED-RECTANGLE!")
    authority = _word(source, "_RUCL-AR-AUTHORITY?")
    scalars = _word(source, "_RUCL-AR-SCALARS?")
    writer = _word(source, "_RUCL-AR-WRITE")

    assert (
        "attachment source-generation source-kind source-index semantic-subkey"
        in public
    )
    assert "z row0 col0 row1 col1 claim -- status" in public
    assert public.index("_RUCL-AR-AUTHORITY?") < public.index(
        "_RUCL-AR-ARGS!"
    ) < public.index("_RUCL-AR-SCALARS?") < public.index("_RUCL-AR-WRITE")
    assert "RUCL-CLAIM-SIZE _RUCL-SPAN?" in authority
    assert "RUCL-CLAIM-SIZE _RUCL-OWNED-DISJOINT?" in authority
    assert "_RUCL-AR-WRITE" not in public[: public.index("_RUCL-AR-SCALARS?")]
    assert "_RUCL-AR-SUBKEY @" not in scalars
    assert "_RUCL-AR-ROW0 @ _RUCL-AR-ROW1 @ U<" in scalars
    assert "_RUCL-AR-COL0 @ _RUCL-AR-COL1 @ U<" in scalars

    fields = {
        "ATTACHMENT": "ATTACHMENT",
        "GENERATION": "GENERATION",
        "SOURCE": "SOURCE",
        "INDEX": "INDEX",
        "SUBKEY": "SUBKEY",
        "Z": "Z",
        "ROW0": "ROW0",
        "COL0": "COL0",
        "ROW1": "ROW1",
        "COL1": "COL1",
    }
    for source_field, claim_field in fields.items():
        assert (
            f"_RUCL-AR-{source_field} @ OVER _RUCL-C.{claim_field} !" in writer
            or source_field == "COL1"
            and f"_RUCL-AR-COL1 @ SWAP _RUCL-C.COL1 !" in writer
        )

    constructor_path = "\n".join((public, authority, scalars, writer))
    for applet_or_family in ("TEXT_AREA", "TEXT-AREA", "UMSN-K-", "DESK-"):
        assert applet_or_family not in constructor_path

    exact = (0xA77A, 19, 1, 37, 0xBEEF, 8, 3, 7, 9, 21)
    packed = struct.pack("<10Q", *exact)
    assert len(packed) == 80
    assert struct.unpack("<10Q", packed) == exact
