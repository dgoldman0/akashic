"""Seconds-only provider and bridge locks for hybrid rich admission."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "akashic/tui/rich-terminal/engine.f"
PROVIDER = ROOT / "akashic/tui/rich-terminal/apt1-engine.f"
BRIDGE = ROOT / "akashic/tui/rich-terminal/engine-apt1.f"


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


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


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions)


def test_provider_authority_is_stack_only_and_immutable_before_scratch() -> None:
    source = _text(PROVIDER)
    storage = _word(source, "RTAPT-STORAGE-DISJOINT?")
    authority = _word(source, "_RTAPT-HAF-AUTHORITY?")
    assert "VARIABLE _RTAPT-SD-" not in source
    assert "VARIABLE _RTAPT-HAF-OWNED-LIMIT" not in source
    assert "_RTAPT-HAF-OWNED-END _RTAPT-HAF-OWNED-START -" in source
    assert ">R" in storage
    for forbidden in ("!", "?DO", "_RTAPT-ENGINE-STORAGE?", "_RTAPT-ENGINE-RANGES?"):
        assert forbidden not in storage
    for required in (
        "_RTAPT-E.SESSION", "_RTAPT-E.OWNERS-A", "_RTAPT-E.OPS-A",
        "_RTAPT-E.COPY-A", "_RTAPT-E.OWNER-CAP", "_RTAPT-E.OP-CAP",
        "_RTAPT-E.OWNER-USED", "_RTAPT-E.OP-COUNT", "_RTAPT-E.COPY-USED",
        "_RTAPT-E.SEND-INDEX", "PT-STORAGE-DISJOINT?", "MSPAN-OVERLAP?",
    ):
        assert required in storage
    assert storage.count("2DROP R> DROP 0 EXIT") >= 20
    assert "!" not in authority
    assert "_RTAPT-ENGINE-STORAGE?" not in authority
    assert "_RTAPT-ENGINE-RANGES?" not in authority
    assert authority.count("RTAPT-STORAGE-DISJOINT?") == 2
    _ordered(
        authority,
        "_RTAPT-HAF-OWNED-END _RTAPT-HAF-OWNED-START -",
        "OVER RTAPT-HYBRID-ADMISSION-SIZE 2 PICK",
    )


def test_provider_uses_one_full_validation_and_capability_precedence() -> None:
    source = _text(PROVIDER)
    family = _word(source, "_RTAPT-HAF-FAMILY?")
    arithmetic = _word(source, "_RTAPT-HAF-ARITHMETIC?")
    existing = _word(source, "_RTAPT-HAF-EXISTING-ADMISSION")
    owner_admission = _word(source, "_RTAPT-HAF-OWNER-ADMISSION")
    body = _word(source, "_RTAPT-HYBRID-PREFLIGHT-BODY")
    limits = _word(source, "RTAPT-LIMITS@")
    after_valid = _word(source, "_RTAPT-LIMITS-AFTER-VALID@")
    assert limits.count("_RTAPT-ENGINE-VALID?") == 1
    assert limits.count("_RTAPT-LIMITS-AFTER-VALID@") == 1
    assert "_RTAPT-ENGINE-VALID?" not in after_valid
    assert body.count("_RTAPT-ENGINE-VALID?") == 1
    assert body.count("_RTAPT-LIMITS-AFTER-VALID@") == 1
    assert "RTAPT-LIMITS@" not in body
    _ordered(
        body, "_RTAPT-ENGINE-VALID?", "_RTAPT-HAF-FIELDS?",
        "_RTAPT-LIMITS-AFTER-VALID@", "RTAPT-F-CONTROLS AND 0=",
        "_RTAPT-L.GLYPH-RUN-BYTES @ 0=", "_RTAPT-HAF-ARITHMETIC?",
    )
    assert "_RTAPT-HAF-FAMILY-TEXT @ _RTAPT-UADD?" not in family
    assert "_RTAPT-HAF-FAMILY-ALIGNED @ _RTAPT-HAF-FAMILY-TEXT @ -" in family
    assert "SWAP U> IF 0 EXIT THEN" in family
    _ordered(
        body, "RTAPT-F-CONTROLS AND 0=", "_RTAPT-L.GLYPH-RUN-BYTES @ 0=",
        "_RTAPT-HAF-CONTROL-MAX @", "_RTAPT-HAF-GLYPH-MAX @",
    )
    for required in (
        "_RTAPT-CONTROL-COPY-FIXED", "_RTAPT-GLYPH-RUN-DEFINE-COPY-FIXED",
        "_RTAPT-CONTROL-FRAME-FIXED", "_RTAPT-GLYPH-RUN-DEFINE-FRAME-FIXED",
        "_RTAPT-REGION-DEFINE-COPY-SIZE", "_RTAPT-UPDATE-ENVELOPE-FRAME-BYTES",
        "_RTAPT-REGION-DEFINE-FRAME-BYTES",
    ):
        assert required in arithmetic
    assert body.count("_RTAPT-HAF-OWNER-ADMISSION") == 1
    assert "_RTAPT-LPF-OWNER-ADMISSION" not in body
    assert "_RTAPT-OWNER-FIND ?DUP IF" in owner_admission
    assert owner_admission.index("_RTAPT-OWNER-FIND ?DUP IF") < owner_admission.index(
        "_RTAPT-LPF-OWNER-ADMISSION"
    )
    for comparison in (
        "_RTAPT-O.REGIONS @ 1 U<",
        "_RTAPT-O.OBJECTS @ _RTAPT-HAF-OBJECTS @ U<",
        "_RTAPT-O.UTF8-BYTES @ _RTAPT-HAF-UTF8 @ U<",
    ):
        assert comparison in existing
    assert "RTAPT-OWNER-ST-OPEN <>" in existing
    assert "RTAPT-S-BUSY" in existing
    assert existing.count("RTAPT-S-CAPACITY") == 3
    assert "RTAPT-S-OK" in existing
    for forbidden in (
        "_RTAPT-LPF-OWNER-ADMISSION",
        "_RTAPT-LPF-ADD-OWNER-QUOTAS",
        "_RTAPT-LPF-AGG-",
    ):
        assert forbidden not in existing
    assert "+!" not in existing + owner_admission
    assert re.search(r"_RTAPT-(?:O|E)\.[A-Z0-9-]+\s+!", existing) is None
    assert "_RTAPT-HAF-CONTROL-LAST" not in arithmetic + body
    assert "_RTAPT-HAF-GLYPH-LAST" not in arithmetic + body


def test_provider_consumes_only_fixed_summary_and_bridge_installs_callback() -> None:
    provider = _text(PROVIDER)
    engine = _text(ENGINE)
    bridge = _text(BRIDGE)
    provider_path = "\n".join(
        _word(provider, name) for name in (
            "_RTAPT-HAF-AUTHORITY?", "_RTAPT-HAF-COPY-SUMMARY",
            "_RTAPT-HAF-HEADER?", "_RTAPT-HAF-FAMILY?",
            "_RTAPT-HAF-FIELDS?", "_RTAPT-HAF-ARITHMETIC?",
            "_RTAPT-HYBRID-PREFLIGHT-BODY", "RTAPT-HYBRID-PREFLIGHT",
        )
    )
    exact = _word(bridge, "_RTAPTE-FACADE?")
    init = _word(bridge, "_RTAPTE-INIT-BODY")
    callback = _word(bridge, "_RTAPTE-HYBRID-PREFLIGHT")
    layout = _word(bridge, "_RTAPTE-HYBRID-LAYOUT?")
    assert _constant(engine, "RTE-FACADE-SIZE") == 192
    assert _offset(engine, "_RTE-F.HYBRID-PREFLIGHT-XT") == 184
    assert _constant(provider, "RTAPT-HYBRID-ADMISSION-SIZE") == 200
    for forbidden in ("ITEMS-A", "ITEMS-U", "REFS-A", "REFS-U", "TEXT-A", "?DO"):
        assert forbidden not in provider_path
    assert "RTAPT-HYBRID-PREFLIGHT _RTAPTE-STATUS>RTE" in callback
    assert "['] _RTAPTE-HYBRID-PREFLIGHT = AND" in exact
    assert "RTE-HYBRID-ADMISSION-SIZE RTAPT-HYBRID-ADMISSION-SIZE <>" in init
    assert "_RTAPTE-HYBRID-LAYOUT? 0= OR" in init
    assert init.index("_RTAPTE-HYBRID-LAYOUT? 0= OR") < init.index(
        "RTE-FACADE-SIZE 0 FILL"
    )
    for field in (
        "OWNER", "GENERATION", "SURFACE-COLS", "SURFACE-ROWS",
        "REGION-ID", "REGION-X", "REGION-Y", "REGION-COLS",
        "REGION-ROWS", "REGION-Z", "REGION-FLAGS", "CONTROL-COUNT",
        "CONTROL-BYTES", "CONTROL-ALIGNED", "CONTROL-MAX", "CONTROL-LAST",
        "CONTROL-COLLECTIONS", "CONTROL-ITEMS", "CONTROL-UTF8",
        "GLYPH-COUNT", "GLYPH-TEXT", "GLYPH-ALIGNED", "GLYPH-MAX",
        "GLYPH-LAST", "RESERVED",
    ):
        assert re.search(
            rf"0 _RTE-HA\.{field}\s+0 _RTAPT-HA\.{field} =",
            layout,
        )
    assert layout.count(" AND") == 24
    assert "['] _RTAPTE-HYBRID-PREFLIGHT" in init
    assert "_RTE-F.HYBRID-PREFLIGHT-XT !" in init
    for old in (
        "RTE-CONTROL-PREFLIGHT", "RTE-GLYPH-RUN-PREFLIGHT",
        "RTAPT-CONTROL-PREFLIGHT", "RTAPT-GLYPH-RUN-PREFLIGHT",
        "_RTAPTE-CONTROL-PREFLIGHT", "_RTAPTE-GLYPH-RUN-PREFLIGHT",
    ):
        assert re.search(rf"(?m)^: {re.escape(old)}(?=\s)", engine + provider + bridge)
