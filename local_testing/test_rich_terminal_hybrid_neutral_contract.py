"""Seconds-only structural locks for neutral one-pass hybrid admission."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "akashic/tui/rich-terminal/engine.f"


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions)


def test_neutral_fixed_authority_is_scratch_free_and_precedes_item_walks() -> None:
    source = _text(ENGINE)
    fixed_names = (
        "_RTE-HPV-OWNED-DISJOINT?", "_RTE-HPV-FIXED-RECORD?",
        "_RTE-HPV-FIXED-BYTE?", "_RTE-HPV-FIXED-DISJOINT?",
        "_RTE-HPV-CONTROL-PLAN-SPAN", "_RTE-HPV-CONTROL-ITEMS-SPAN",
        "_RTE-HPV-CONTROL-TEXT-SPAN", "_RTE-HPV-GLYPH-PLAN-SPAN",
        "_RTE-HPV-GLYPH-ITEMS-SPAN", "_RTE-HPV-GLYPH-REFS-SPAN",
        "_RTE-HPV-GLYPH-TEXT-SPAN", "_RTE-HPV-FIXED-PLAN?",
        "_RTE-HPV-FIXED-WRAPPER?", "_RTE-HPV-FIXED-CONTROL?",
        "_RTE-HPV-FIXED-GLYPH?", "_RTE-HPV-FIXED-HEADERS-SAME?",
        "_RTE-HPV-FIXED-CROSS?", "_RTE-HPV-FIXED-AUTHORITY?",
        "_RTE-HPV-ADMISSION-GRAPH-DISJOINT?",
        "_RTE-HPV-ADMISSION-AUTHORITY?",
    )
    fixed = "\n".join(_word(source, name) for name in fixed_names)
    authority = _word(source, "_RTE-HPV-FIXED-AUTHORITY?")
    public = _word(source, "RTE-HYBRID-PREFLIGHT")
    body = _word(source, "_RTE-HYBRID-PREFLIGHT-BODY")
    control_body = _word(source, "_RTE-CONTROL-PLAN-VALID-BODY")
    glyph = _word(source, "_RTE-HPV-GLYPH?")
    assert "VARIABLE _RTE-HPV-OWNED-LIMIT" not in source
    assert "_RTE-HPV-OWNED-END _RTE-HPV-OWNED-START -" in source
    for forbidden in (
        " FILL", " MOVE", "?DO", " DO", "LOOP",
        "_RTE-CPV-ITEM?", "_RTE-HPV-GLYPH-ITEM?",
    ):
        assert forbidden not in fixed
    assert not re.search(r"(?m)(?:^|\s)!(?:\s|$)", fixed)
    assert "RTE-STORAGE-DISJOINT?" in authority
    assert "_RTE-HPV-OWNED-START _RTE-HPV-OWNED-END" in authority
    _ordered(
        public,
        "_RTE-HPV-FIXED-AUTHORITY?",
        "_RTE-HPV-ADMISSION-AUTHORITY?",
        "_RTE-F.HYBRID-PREFLIGHT-XT @ 0=",
        "_RTE-HPV-FACADE !",
        "_RTE-HPV-ADMISSION !",
        "_RTE-HPV-HYBRID !",
    )
    _ordered(
        body,
        "_RTE-HPV-INIT",
        " FILL",
        "_RTE-HPV-CONTROL?",
        "_RTE-HPV-GLYPH?",
    )
    assert control_body.count("?DO") == 1
    assert glyph.count("?DO") == 1
    assert body.count("_RTE-F.HYBRID-PREFLIGHT-XT @ EXECUTE") == 1
    _ordered(
        body,
        "_RTE-F.HYBRID-PREFLIGHT-XT @ EXECUTE",
        "DUP RTE-S-OK = IF",
        "RTE-HYBRID-ADMISSION-SIZE MOVE",
    )
    assert body.count(" MOVE") == 1
    for old in (
        "_RTE-HPV-ENTRY-AUTHORITY?", "_RTE-HPV-WRAPPER?",
        "_RTE-HPV-ITEM-SPANS?", "RTE-CONTROL-PREFLIGHT",
        "RTE-GLYPH-RUN-PREFLIGHT",
    ):
        assert old not in body + public


def test_control_text_envelope_is_authority_not_quota() -> None:
    source = _text(ENGINE)
    wrapper = _word(source, "_RTE-HPV-FIXED-WRAPPER?")
    fixed_control = _word(source, "_RTE-HPV-FIXED-CONTROL?")
    authority = _word(source, "_RTE-CPV-TEXT-AUTHORITY?")
    item = _word(source, "_RTE-CPV-ITEM?")
    control = _word(source, "_RTE-HPV-CONTROL?")
    assert "_RTE-HP.CONTROL-PLAN @ 0= IF" in wrapper
    assert "_RTE-HP.CONTROL-TEXT-A @" in wrapper
    assert "_RTE-HP.CONTROL-TEXT-U @ OR" in wrapper
    assert "_RTE-HPV-CONTROL-TEXT-SPAN" in fixed_control
    assert "_RTE-HPV-FIXED-BYTE?" in fixed_control
    _ordered(
        authority,
        "_RTE-CPV-FIXED-AUTHORITY @ IF",
        "_RTE-CPV-CONTROL-TEXT-U @ 0=",
        "_RTE-CPV-TEXT-A @ _RTE-CPV-CONTROL-TEXT-A @ U<",
        "_RTE-CPV-TEXT-A @ _RTE-CPV-TEXT-U @ +",
    )
    _ordered(
        item,
        "_RTE-CPV-ITEM-STRUCTURAL?",
        "_RTE-CPV-ITEM-TEXT-AUTHORITY?",
        "_RTE-CPV-ITEM-TEXT?",
    )
    assert "_RTE-HPV-CONTROL-TEXT-U @ 0=" in control
    assert "_RTE-CPV-TEXT-BYTES @ 0<> AND" in control
    summary_writes = "\n".join(
        line for line in control.splitlines() if "_RTE-HPV-SUMMARY" in line
    )
    assert "CONTROL-TEXT-A" not in summary_writes
    assert "CONTROL-TEXT-U" not in summary_writes
