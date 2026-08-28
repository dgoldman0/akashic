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
    assert "88 CONSTANT _SCR-DESC-SIZE" in source
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
