"""Seconds-only layout lock for the neutral/provider hybrid admission ABI."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "akashic/tui/rich-terminal/engine.f"
PROVIDER = ROOT / "akashic/tui/rich-terminal/apt1-engine.f"


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


def test_hybrid_wrapper_and_checked_summary_have_exact_fixed_layouts() -> None:
    engine = ENGINE.read_text(encoding="utf-8")
    provider = PROVIDER.read_text(encoding="utf-8")
    assert _constant(engine, "RTE-HYBRID-PLAN-SIZE") == 96
    assert _constant(engine, "RTE-HYBRID-TEXT-REF-SIZE") == 16
    assert _constant(engine, "RTE-HYBRID-ADMISSION-SIZE") == 176
    assert _constant(provider, "RTAPT-HYBRID-ADMISSION-SIZE") == 176

    wrapper = {
        "ATTEMPT": 0,
        "SOURCE-GENERATION": 8,
        "SURFACE-GENERATION": 16,
        "CONTROL-PLAN": 24,
        "GLYPH-PLAN": 32,
        "GLYPH-REFS-A": 40,
        "GLYPH-REFS-U": 48,
        "GLYPH-TEXT-A": 56,
        "GLYPH-TEXT-U": 64,
        "CONTROL-TEXT-A": 72,
        "CONTROL-TEXT-U": 80,
        "RESERVED": 88,
    }
    assert {
        field: _offset(engine, f"_RTE-HP.{field}") for field in wrapper
    } == wrapper
    fixed_wrapper = _word(engine, "_RTE-HPV-FIXED-WRAPPER?")
    for field in ("ATTEMPT", "SOURCE-GENERATION", "SURFACE-GENERATION"):
        assert f"OVER _RTE-HP.{field} @ 0=" in fixed_wrapper

    fields = (
        "OWNER", "GENERATION", "SURFACE-COLS", "SURFACE-ROWS",
        "REGION-ID", "REGION-X", "REGION-Y", "REGION-COLS",
        "REGION-ROWS", "REGION-Z", "REGION-FLAGS", "CONTROL-COUNT",
        "CONTROL-TEXT", "CONTROL-ALIGNED", "CONTROL-MAX", "CONTROL-LAST",
        "GLYPH-COUNT", "GLYPH-TEXT", "GLYPH-ALIGNED", "GLYPH-MAX",
        "GLYPH-LAST", "RESERVED",
    )
    expected = {field: index * 8 for index, field in enumerate(fields)}
    assert {
        field: _offset(engine, f"_RTE-HA.{field}") for field in fields
    } == expected
    assert {
        field: _offset(provider, f"_RTAPT-HA.{field}") for field in fields
    } == expected
