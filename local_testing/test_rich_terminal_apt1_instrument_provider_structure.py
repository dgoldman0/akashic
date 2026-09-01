"""Seconds-only structural locks for the generic APT-1 INSTRUMENT provider."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / "akashic/tui/rich-terminal/apt1-engine.f"


def _source() -> str:
    return PROVIDER.read_text(encoding="utf-8")


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


def test_public_descriptor_and_vocabulary_are_exact_and_generic() -> None:
    source = _source()

    assert _constant(source, "RTAPT-INSTRUMENT-SIZE") == 208
    assert "( instrument engine -- status )" in _word(
        source, "RTAPT-INSTRUMENT-DEFINE"
    )
    fields = (
        "OWNER", "GENERATION", "ID", "KIND", "VISIBLE", "Z", "REGION",
        "PARENT", "ROW", "COL", "HEIGHT", "WIDTH", "ROOT-HEIGHT",
        "ROOT-WIDTH", "COLOR-A", "COLOR-B", "MODE", "OPTIONS", "MINIMUM",
        "MAXIMUM", "VALUE", "SCALE", "UNIT-A", "UNIT-U", "FORMATTED-U",
        "RESERVED",
    )
    assert {
        field: _offset(source, f"_RTAPT-INSTRUMENT.{field}") for field in fields
    } == {field: index * 8 for index, field in enumerate(fields)}

    expected_constants = {
        "RTAPT-INSTRUMENT-READOUT": 1,
        "RTAPT-INSTRUMENT-METER": 2,
        "RTAPT-INSTRUMENT-STATUS": 3,
        "RTAPT-READOUT-INTEGER": 0,
        "RTAPT-READOUT-FIXED": 1,
        "RTAPT-READOUT-PERCENT": 2,
        "RTAPT-METER-HORIZONTAL": 0,
        "RTAPT-METER-VERTICAL": 1,
        "RTAPT-METER-SHOW-VALUE": 1,
        "RTAPT-STATUS-CIRCLE": 0,
        "RTAPT-STATUS-SQUARE": 1,
        "RTAPT-STATUS-DIAMOND": 2,
    }
    assert {
        name: _constant(source, name) for name in expected_constants
    } == expected_constants


def test_hybrid_admission_extends_only_the_caller_supplied_summary() -> None:
    source = _source()
    assert _constant(source, "RTAPT-HYBRID-ADMISSION-SIZE") == 320
    fields = {
        "CLIP-X": 72,
        "CLIP-Y": 80,
        "CLIP-COLS": 88,
        "CLIP-ROWS": 96,
        "INSTRUMENT-REGION-COUNT": 224,
        "INSTRUMENT-COUNT": 232,
        "READOUT-COUNT": 240,
        "METER-COUNT": 248,
        "STATUS-COUNT": 256,
        "INSTRUMENT-UNIT-BYTES": 264,
        "INSTRUMENT-UNIT-ALIGNED": 272,
        "INSTRUMENT-UNIT-MAX": 280,
        "INSTRUMENT-FORMATTED-BYTES": 288,
        "INSTRUMENT-FORMATTED-MAX": 296,
        "INSTRUMENT-LAST": 304,
        "RESERVED": 312,
    }
    assert {
        field: _offset(source, f"_RTAPT-HA.{field}") for field in fields
    } == fields

    arithmetic = _word(source, "_RTAPT-HAF-ARITHMETIC?")
    arithmetic_tokens = " ".join(arithmetic.split())
    assert re.search(
        r"_RTAPT-HAF-INSTRUMENT-COUNT\s+@\s+"
        r"_RTAPT-INSTRUMENT-COPY-FIXED\s+_RTAPT-UMUL\?",
        arithmetic,
    )
    assert (
        "_RTAPT-HAF-INSTRUMENT-UNIT-ALIGNED @ _RTAPT-UADD?"
        in arithmetic_tokens
    )
    assert "_RTAPT-HAF-INSTRUMENT-FORMATTED-BYTES @" in arithmetic_tokens
    utf8_arithmetic = arithmetic.split("_RTAPT-HAF-UTF8 !", 1)[0]
    assert "_RTAPT-HAF-INSTRUMENT-FORMATTED-BYTES @" in utf8_arithmetic
    assert "_RTAPT-HAF-INSTRUMENT-UNIT-BYTES @" not in utf8_arithmetic
    assert "_RTAPT-HAF-INSTRUMENT-UNIT-BYTES @" in arithmetic


def test_authority_precedes_mutation_and_caller_text_dereference() -> None:
    source = _source()
    public = _word(source, "RTAPT-INSTRUMENT-DEFINE")
    body = _word(source, "_RTAPT-INSTRUMENT-DEFINE-BODY")
    authority = _word(source, "_RTAPT-INSTRUMENT-AUTHORITY?")
    unit_authority = _word(source, "_RTAPT-INSTRUMENT-UNIT-AUTHORITY?")

    _ordered(
        public,
        "2DUP _RTAPT-INSTRUMENT-AUTHORITY?",
        "_RTAPT-ID-E ! _RTAPT-ID-I !",
        "_RTAPT-INSTRUMENT-LOAD",
    )
    assert "_RTAPT-HAF-OWNED-DISJOINT?" in authority
    assert "RTAPT-STORAGE-DISJOINT?" in authority
    assert "_RTAPT-BYTE-SPAN-DISJOINT?" in unit_authority
    assert "MSPAN-OVERLAP?" in unit_authority
    _ordered(
        body,
        "_RTAPT-INSTRUMENT-FIELDS?",
        "_RTAPT-INSTRUMENT-UNIT-AUTHORITY?",
        "_RTAPT-READY-STATUS",
        "_RTAPT-INSTRUMENT-CAPACITY?",
        "_RTAPT-INSTRUMENT-LIMITS",
        "_RTAPT-INSTRUMENT-UNIT-TEXT?",
    )


def test_retry_capture_preserves_raw_cell_geometry_without_clipping() -> None:
    source = _source()
    geometry = _word(source, "_RTAPT-INSTRUMENT-GEOMETRY?")
    capture = _word(source, "_RTAPT-INSTRUMENT-CAPTURE")
    captured_shape = _word(source, "_RTAPT-INSTRUMENT-COPY-SHAPE?")
    sender = _word(source, "_RTAPT-PUSH-INSTRUMENT-COMMON")

    assert "_RTAPT-I32?" in geometry
    assert geometry.count("_RTAPT-U32?") >= 4
    assert geometry.count("_RTAPT-LPF-SADD?") == 2
    for forbidden in ("UNORM", " MAX", " MIN", "INTERSECT", "CLAMP"):
        assert forbidden not in geometry.upper()
    for field, scratch in (
        ("ROW", "ROW"),
        ("COL", "COL"),
        ("HEIGHT", "HEIGHT"),
        ("WIDTH", "WIDTH"),
    ):
        assert (
            f"_RTAPT-ID-{scratch} @ _RTAPT-ID-COPY @ "
            f"_RTAPT-INSTRUMENT.{field} !"
        ) in capture
        assert f"_RTAPT-INSTRUMENT.{field} @" in captured_shape
        assert f"_RTAPT-INSTRUMENT.{field} @" in sender
    assert "_RTAPT-INSTRUMENT.ROOT-HEIGHT !" not in capture
    assert "_RTAPT-INSTRUMENT.ROOT-WIDTH !" not in capture
    assert "_RTAPT-INSTRUMENT.UNIT-A !" not in capture
    assert "_RTAPT-LPF-SADD?" in captured_shape


def test_retry_storage_and_wire_accounting_are_exact_not_product_capped() -> None:
    source = _source()
    capacity = _word(source, "_RTAPT-INSTRUMENT-CAPACITY?")
    capture = _word(source, "_RTAPT-INSTRUMENT-CAPTURE")
    banks = _word(source, "_RTAPT-CAPTURED-BANKS?")

    assert _constant(source, "_RTAPT-READOUT-FRAME-FIXED") == 144
    assert _constant(source, "_RTAPT-METER-FRAME-BYTES") == 152
    assert _constant(source, "_RTAPT-STATUS-FRAME-BYTES") == 136

    _ordered(
        capacity,
        "_RTAPT-ID-UNIT-U @ _RTAPT-INSTRUMENT-COPY-FIXED",
        "_RTAPT-ALIGN8?",
        "_RTAPT-E.COPY-U",
        "_RTAPT-E.COPY-USED",
    )
    assert "_RTAPT-ID-COPY-U @ 0 FILL" in capture
    assert capture.count(" MOVE") == 1
    assert "_RTAPT-ID-UNIT-U @ MOVE" in capture
    assert "_RTAPT-INSTRUMENT-COPY-FIXED _RTAPT-UADD?" in banks
    assert "_RTAPT-ALIGN8?" in banks
    assert "_RTAPT-ZERO-SPAN?" in banks
    assert not re.search(r"INSTRUMENT-(?:MAX|CAPACITY)\s+CONSTANT", source)


def test_define_replace_lifecycle_preserves_backlinks_and_quotas() -> None:
    source = _source()
    operation = _word(source, "_RTAPT-INSTRUMENT-OPERATION?")
    body = _word(source, "_RTAPT-INSTRUMENT-DEFINE-BODY")
    quotas = _word(source, "_RTAPT-INSTRUMENT-QUOTAS?")
    capture = _word(source, "_RTAPT-INSTRUMENT-CAPTURE")
    publication = _word(source, "_RTAPT-PUBLICATION-INSTRUMENT?")
    ledgers = _word(source, "_RTAPT-OWNER-LEDGERS?")

    assert "PT-RET-REPLACE-START =" in operation
    assert "_RTAPT-OP-INSTRUMENT-DEFINE" in operation
    assert "_RTAPT-O.OBJECT-HIGH @ U>" in operation
    assert "_RTAPT-GLYPH-RUN-TARGET?" in operation
    assert "_RTAPT-OP-INSTRUMENT-REPLACE" in operation
    assert "_RTAPT-INSTRUMENT-REGION-OP" in body
    assert body.count("_RTAPT-INSTRUMENT-QUOTAS?") == 1
    assert "FORMATTED-U is the complete READOUT representation" in quotas
    assert "_RTAPT-ID-FORMATTED-U @ _RTAPT-ID-QUOTA-UTF8 !" in quotas
    assert "_RTAPT-ID-UNIT-U @ _RTAPT-ID-QUOTA-UTF8" not in quotas
    assert "_RTAPT-O.PENDING-OBJECTS !" in capture
    assert "_RTAPT-O.PENDING-OBJECT-HIGH !" in capture
    assert "_RTAPT-O.PENDING-UTF8 !" in capture
    assert "_RTAPT-INSTRUMENT-REGION-BACKLINK?" in publication
    assert "_RTAPT-PUBLICATION-NONDEFINITION+?" in publication
    assert "_RTAPT-OP-INSTRUMENT-REPLACE = OR" in ledgers


def test_wire_dispatch_maps_semantics_and_define_vs_replace_explicitly() -> None:
    source = _source()
    dispatch = _word(source, "_RTAPT-SEND-CAPTURED")
    readout = _word(source, "_RTAPT-SEND-READOUT")
    meter = _word(source, "_RTAPT-SEND-METER")
    status = _word(source, "_RTAPT-SEND-STATUS")

    assert "_RTAPT-OP-INSTRUMENT-DEFINE" in dispatch
    assert "_RTAPT-OP-INSTRUMENT-REPLACE" in dispatch
    assert "0 _RTAPT-SEND-INSTRUMENT" in dispatch
    assert "-1 _RTAPT-SEND-INSTRUMENT" in dispatch
    for sender, define, replace in (
        (readout, "PT-READOUT-DEFINE", "PT-READOUT-REPLACE"),
        (meter, "PT-METER-DEFINE", "PT-METER-REPLACE"),
        (status, "PT-STATUS-DEFINE", "PT-STATUS-REPLACE"),
    ):
        assert define in sender
        assert replace in sender
    assert "_RTAPT-READOUT-MODE>PT" in readout
    assert "_RTAPT-METER-MODE>PT" in meter
    assert "_RTAPT-METER-OPTIONS>PT" in meter
    assert "_RTAPT-STATUS-MODE>PT" in status
    assert "_RTAPT-PUSH-RGBA" in readout + meter + status
