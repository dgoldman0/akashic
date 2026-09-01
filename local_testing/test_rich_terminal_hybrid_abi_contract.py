"""Seconds-only layout lock for the neutral/bridge hybrid admission ABI."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "akashic/tui/rich-terminal/engine.f"
BRIDGE = ROOT / "akashic/tui/rich-terminal/engine-apt1.f"
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
    bridge = BRIDGE.read_text(encoding="utf-8")
    provider = PROVIDER.read_text(encoding="utf-8")
    assert _constant(engine, "RTE-HYBRID-PLAN-SIZE") == 120
    assert _constant(engine, "RTE-HYBRID-TEXT-REF-SIZE") == 16
    assert _constant(engine, "RTE-HYBRID-ADMISSION-SIZE") == 320
    assert _constant(provider, "RTAPT-HYBRID-ADMISSION-SIZE") == 320

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
        "CONTROL-BYTES-A": 72,
        "CONTROL-BYTES-U": 80,
        "INSTRUMENT-PLAN": 88,
        "INSTRUMENT-BYTES-A": 96,
        "INSTRUMENT-BYTES-U": 104,
        "RESERVED": 112,
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
        "REGION-ROWS", "CLIP-X", "CLIP-Y", "CLIP-COLS", "CLIP-ROWS",
        "REGION-Z", "REGION-FLAGS", "CONTROL-COUNT", "CONTROL-BYTES",
        "CONTROL-ALIGNED", "CONTROL-MAX", "CONTROL-LAST",
        "CONTROL-COLLECTIONS", "CONTROL-ITEMS", "CONTROL-UTF8",
        "GLYPH-COUNT", "GLYPH-TEXT", "GLYPH-ALIGNED", "GLYPH-MAX",
        "GLYPH-LAST", "INSTRUMENT-REGION-COUNT", "INSTRUMENT-COUNT",
        "READOUT-COUNT", "METER-COUNT", "STATUS-COUNT",
        "INSTRUMENT-UNIT-BYTES",
        "INSTRUMENT-UNIT-ALIGNED", "INSTRUMENT-UNIT-MAX",
        "INSTRUMENT-FORMATTED-BYTES", "INSTRUMENT-FORMATTED-MAX",
        "INSTRUMENT-LAST", "RESERVED",
    )
    expected = {field: index * 8 for index, field in enumerate(fields)}
    assert {
        field: _offset(engine, f"_RTE-HA.{field}") for field in fields
    } == expected
    assert {
        field: _offset(provider, f"_RTAPT-HA.{field}") for field in fields
    } == expected

    # The bridge must fail closed while a concrete provider still advertises
    # an older private record.  Once the provider is adapted, the same complete
    # field-by-field proof becomes the construction gate without a copy shim.
    layout = _word(bridge, "_RTAPTE-HYBRID-LAYOUT?")
    for field in fields:
        assert f"0 _RTE-HA.{field}" in layout
        assert f"0 _RTAPT-HA.{field}" in layout
    assert "[DEFINED] _RTAPT-HA.INSTRUMENT-REGION-COUNT [IF]" in bridge
    init = _word(bridge, "_RTAPTE-INIT-BODY")
    size = init.index(
        "RTE-HYBRID-ADMISSION-SIZE RTAPT-HYBRID-ADMISSION-SIZE <>"
    )
    layout_check = init.index("_RTAPTE-HYBRID-LAYOUT? 0= OR", size)
    facade_fill = init.index("RTE-FACADE-SIZE 0 FILL", layout_check)
    assert size < layout_check < facade_fill


def test_success_returns_the_exact_provider_admitted_summary() -> None:
    engine = ENGINE.read_text(encoding="utf-8")
    public = _word(engine, "RTE-HYBRID-PREFLIGHT")
    body = _word(engine, "_RTE-HYBRID-PREFLIGHT-BODY")
    graph = _word(engine, "_RTE-HPV-ADMISSION-GRAPH-DISJOINT?")
    authority = _word(engine, "_RTE-HPV-ADMISSION-AUTHORITY?")

    assert "( hybrid admission facade -- status )" in public.splitlines()[0]
    assert public.index("_RTE-HPV-FIXED-AUTHORITY?") < public.index(
        "_RTE-HPV-ADMISSION-AUTHORITY?"
    ) < public.index("_RTE-HPV-ADMISSION !")
    assert "_RTE-HPV-OWNED-DISJOINT?" in authority
    assert "RTE-STORAGE-DISJOINT?" in authority
    for source_span in (
        "RTE-HYBRID-PLAN-SIZE", "_RTE-HPV-CONTROL-PLAN-SPAN",
        "_RTE-HPV-CONTROL-ITEMS-SPAN", "_RTE-HPV-CONTROL-BYTES-SPAN",
        "_RTE-HPV-GLYPH-PLAN-SPAN", "_RTE-HPV-GLYPH-ITEMS-SPAN",
        "_RTE-HPV-GLYPH-REFS-SPAN", "_RTE-HPV-GLYPH-TEXT-SPAN",
        "_RTE-HPV-INSTRUMENT-PLAN-SPAN",
        "_RTE-HPV-INSTRUMENT-REGIONS-SPAN",
        "_RTE-HPV-INSTRUMENT-ITEMS-SPAN",
        "_RTE-HPV-INSTRUMENT-BYTES-SPAN",
    ):
        assert source_span in graph
    assert "?DO" not in graph + authority
    assert " MOVE" not in graph + authority
    assert not re.search(r"(?m)(?:^|\s)!(?:\s|$)", graph + authority)
    assert body.count("_RTE-F.HYBRID-PREFLIGHT-XT @ EXECUTE") == 1
    assert body.index("_RTE-F.HYBRID-PREFLIGHT-XT @ EXECUTE") < body.index(
        "DUP RTE-S-OK = IF"
    ) < body.index("RTE-HYBRID-ADMISSION-SIZE MOVE")
    assert body.count(" MOVE") == 1
