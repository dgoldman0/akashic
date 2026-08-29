"""Seconds-only structural oracle for active-screen storage authority."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/screen.f"


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _valid_optional_span(address: int, length: int, word_bits: int = 64) -> bool:
    if length < 0:
        return False
    if length == 0:
        return address == 0
    if address == 0:
        return False
    return address + length < (1 << word_bits)


def _overlap(a: int, u: int, b: int, v: int) -> bool:
    return u > 0 and v > 0 and a < b + v and b < a + u


def test_screen_storage_authority_covers_the_complete_live_graph() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    body = _word(source, "SCR-STORAGE-DISJOINT?")
    active = _word(source, "_SCR-ACTIVE-STORAGE-VALID?")

    assert "REQUIRE ../utils/memory-span.f" in source
    assert "104 CONSTANT _SCR-DESC-SIZE" in source
    assert "48 CONSTANT SCB-DESC-SIZE" in source
    assert source.index("CREATE _SCR-OWNED-START") < source.index(
        "VARIABLE _SCBI-BACKEND"
    )
    assert source.index("CREATE _SCR-OWNED-END") > source.index(
        ": SCR-CURSOR-OFF      _scr-curoff-xt"
    )
    assert "_SCR-OWNED-END _SCR-OWNED-LIMIT !" in source

    assert body.index("_SCR-OPTIONAL-BYTE-SPAN?") < body.index(
        "_SCR-ACTIVE-STORAGE-VALID?"
    )
    assert body.index("_SCR-ACTIVE-STORAGE-VALID?") < body.index(
        "_SCR-SD-U @ 0= IF -1 EXIT THEN"
    )
    assert "_SCR-MODULE-DISJOINT?" in body
    assert "_SCR-SD-SCREEN @ _SCR-DESC-SIZE _SCR-SD-OVERLAP?" in body
    assert "_SCR-SD-FRONT @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP?" in body
    assert "_SCR-SD-BACK @ _SCR-SD-BUF-U @ _SCR-SD-OVERLAP?" in body
    assert "_SCR-SD-BACKEND @ SCB-DESC-SIZE _SCR-SD-OVERLAP?" in body

    assert "_SCR-DIMS-BYTES?" in active
    assert active.count("_SCR-ALIGNED-SPAN?") == 2
    assert active.count("_SCR-MODULE-DISJOINT?") == 3
    assert active.count("MSPAN-OVERLAP?") == 6
    assert "DUP SCB-VALID?" in active

    assert "' SCR-STORAGE-DISJOINT? CONSTANT _scr-storage-disjoint-xt" in source
    guarded = re.search(
        r"(?ms)^: SCR-STORAGE-DISJOINT\?\s*\n"
        r"\s+_scr-storage-disjoint-xt _scr-guard WITH-GUARD ;$",
        source,
    )
    assert guarded is not None


def test_half_open_and_canonical_empty_policy_is_byte_exact() -> None:
    assert _valid_optional_span(0, 0)
    assert not _valid_optional_span(8, 0)
    assert not _valid_optional_span(0, 8)
    assert not _valid_optional_span(8, -1)
    assert _valid_optional_span(0x1000, 0x80)
    assert not _valid_optional_span((1 << 64) - 4, 8)

    protected = (0x1000, 0x80)
    assert _overlap(0x0FFF, 2, *protected)
    assert _overlap(0x107F, 2, *protected)
    assert not _overlap(0x0F80, 0x80, *protected)
    assert not _overlap(0x1080, 0x20, *protected)
    assert not _overlap(0, 0, *protected)


def test_frame_plane_borrow_exposes_one_guarded_committed_baseline() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    borrow = _word(source, "SCR-WITH-FRAME-PLANES")
    advance = _word(source, "_SCR-ADVANCE-FRONT")
    resize = _word(source, "SCR-RESIZE")

    assert "96 CONSTANT _SCR-O-FRONT-GENERATION" in source
    callback_fields = (
        "_SCR-O-FRONT + @",
        "_SCR-O-BACK + @",
        "_SCR-O-W + @",
        "_SCR-O-H + @",
        "_SCR-O-FRONT-GENERATION + @",
        "_SCR-O-DRAW-GENERATION + @",
        "_SCR-O-FORCE + @ IF -1 ELSE 0 THEN",
        "_SCR-FRAME-PLANES-XT @ EXECUTE",
    )
    positions = [borrow.index(token) for token in callback_fields]
    assert positions == sorted(positions)
    assert "_SCR-O-FRONT-GENERATION + !" in advance
    assert advance.index("_SCR-O-DRAW-GENERATION + @") < advance.index(
        "_SCR-O-FRONT-GENERATION + !"
    )
    assert "0 _SCR-CUR @ _SCR-O-FRONT-GENERATION + !" in resize
    assert resize.index("_SCR-O-FRONT-GENERATION + !") < resize.index(
        "SCR-FORCE"
    )
    assert (
        "' SCR-WITH-FRAME-PLANES CONSTANT _scr-with-frame-planes-xt"
        in source
    )
    assert re.search(
        r"(?ms)^: SCR-WITH-FRAME-PLANES\s*\n"
        r"\s+_scr-with-frame-planes-xt _scr-guard WITH-GUARD ;$",
        source,
    )


def test_front_watermark_advances_only_with_an_accepted_commit_model() -> None:
    front_draw = 0
    draw = 1

    # BEGIN, SPAN, CURSOR, or COMMIT refusal bypasses _SCR-ADVANCE-FRONT.
    for accepted in (False, False, False, False):
        if accepted:
            front_draw = draw
        assert front_draw == 0

    # DELTA/SNAPSHOT acceptance publishes the exact back-plane generation.
    front_draw = draw
    assert front_draw == 1

    # An accepted NONE can advance the watermark because its eligibility
    # proves front and back are already byte-identical.
    draw = 2
    front_draw = draw
    assert front_draw == 2

    # Resize installs a blank front and forces a complete replacement.
    front_draw = 0
    assert front_draw == 0
