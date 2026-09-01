"""Seconds-only structural contract for the mounted UDG snapshot boundary."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "akashic" / "tui" / "uidl-data-graphics-snapshot.f"
MODEL = ROOT / "akashic" / "tui" / "data-graphics-model.f"


def _definitions(source: str) -> list[tuple[str, str]]:
    return [
        (match.group(1), match.group(0))
        for match in re.finditer(
            r"(?ms)^:\s+(\S+)(?=\s).*?;\s*(?:\\[^\n]*)?$",
            source,
        )
    ]


def _definition(source: str, name: str) -> str:
    matches = [body for word, body in _definitions(source) if word == name]
    assert matches, f"missing Forth definition {name}"
    return matches[0]


def _ordered(source: str, *needles: str) -> None:
    positions = [source.index(needle) for needle in needles]
    assert positions == sorted(positions), needles


def test_udgsn_public_descriptor_abi_is_pointer_free_and_exact() -> None:
    source = SNAPSHOT.read_text(encoding="utf-8")
    model = MODEL.read_text(encoding="utf-8")

    for value, name in enumerate(
        ("UDGSN-S-OK", "UDGSN-S-CAPACITY", "UDGSN-S-UNAVAILABLE", "UDGSN-S-INVALID")
    ):
        assert re.search(rf"(?m)^{value}\s+CONSTANT\s+{name}\b", source)
    assert "4 U<" in _definition(source, "UDGSN-STATUS-VALID?")
    assert "160 CONSTANT UDGSN-DESCRIPTOR-SIZE" in source
    assert "UDGSN-DESCRIPTOR-SIZE _UDGSN-SIZED-BYTES" in _definition(
        source, "UDGSN-DESCRIPTOR-BANK-BYTES"
    )
    public = re.sub(r"\s+", " ", _definition(source, "UDGSN-CAPTURE"))
    assert (
        "( builder descriptors-a descriptors-u native-a native-u "
        "-- descriptor-count native-used status )" in public
    )

    offsets = {
        "SOURCE": 0,
        "INDEX": 8,
        "GENERATION": 16,
        "ROOT-KEY": 24,
        "NATIVE-O": 32,
        "ROW": 40,
        "COLUMN": 48,
        "HEIGHT": 56,
        "WIDTH": 64,
        "CLIP-ROW": 72,
        "CLIP-COLUMN": 80,
        "CLIP-HEIGHT": 88,
        "CLIP-WIDTH": 96,
        "Z": 104,
        "SUMMARY": 112,
    }
    for field, offset in offsets.items():
        body = _definition(source, f"_UDGSN-D.{field}")
        if offset:
            assert f"{offset} +" in body
        else:
            assert "+" not in body.split("--", 1)[-1]
    assert "48 CONSTANT UDG-SUMMARY-SIZE" in model
    assert 112 + 48 == 160
    assert "_UDGSN-D.ROOT-KEY @" in _definition(
        source, "UDGSN-DESCRIPTOR-ROOT-KEY@"
    )
    native = _definition(source, "UDGSN-DESCRIPTOR-NATIVE")
    assert "UDGSN-DESCRIPTOR-NATIVE-OFFSET@ +" in native
    assert "UDGSN-DESCRIPTOR-ENTRY-BYTES@" in native

    # No borrowed relation, widget, graph, or terminal pointer enters the ABI.
    assert not re.search(
        r"(?m)^:\s+_UDGSN-D\.(?:WIDGET|RELATION|GRAPH|TERMINAL|POINTER)\b",
        source,
    )


def test_udgsn_preflights_all_banks_before_the_mounted_iterator() -> None:
    source = SNAPSHOT.read_text(encoding="utf-8")
    ranges = _definition(source, "_UDGSN-RANGES?")
    authority = _definition(source, "_UDGSN-AUTHORITY-DISJOINT?")
    observed = _definition(source, "_UDGSN-CAPTURE-OBSERVED")
    body = _definition(source, "_UDGSN-CAPTURE-BODY")

    assert "UDG-BUILDER-SIZE MSPAN-NONWRAPPING?" in ranges
    assert "_UDGSN-DESCRIPTORS-U @ UDGSN-DESCRIPTOR-SIZE MOD" in ranges
    assert ranges.count("_UDGSN-AUTHORITY-DISJOINT?") == 3
    assert ranges.count("_UDGSN-DISJOINT?") == 3
    for authority_name in (
        "_UDGSN-OWNED-DISJOINT?",
        "UDG-STORAGE-DISJOINT?",
        "DGRAPH-STORAGE-DISJOINT?",
        "DGF-STORAGE-DISJOINT?",
        "_UTUI-STORAGE-DISJOINT-BODY?",
        "_UTUI-DATA-GRAPHICS-STORAGE-DISJOINT-OBSERVED?",
    ):
        assert authority_name in authority

    _ordered(
        observed,
        "_UDGSN-RANGES? 0=",
        "_UDGSN-DESCRIPTORS-U @ UDGSN-DESCRIPTOR-SIZE /",
        "-1 _UDGSN-RANGES-VALID !",
        "_UDGSN-CAPTURE-BODY",
    )
    assert "_UTUI-MOUNTED-DATA-GRAPHICS-EACH-PREFLIGHTED" in body
    assert "UTUI-RESOLVED-OBSERVE" in _definition(
        source, "_UDGSN-CAPTURE-CALL"
    )


def test_udgsn_keeps_canonical_order_and_measures_before_copying() -> None:
    source = SNAPSHOT.read_text(encoding="utf-8")
    visitor = _definition(source, "_UDGSN-MOUNTED-VISITOR")
    order = _definition(source, "_UDGSN-V-ORDER?")
    geometry = _definition(source, "_UDGSN-V-GEOMETRY?")
    produce = _definition(source, "_UDGSN-V-PRODUCE")
    capture = _definition(source, "_UDGSN-V-CAPTURE")
    validate = _definition(source, "_UDGSN-V-VALIDATE?")
    metadata = _definition(source, "_UDGSN-V-WRITE-METADATA")

    _ordered(
        visitor,
        "_UDGSN-V-ARGS?",
        "_UDGSN-V-ORDER?",
        "_UDGSN-V-GEOMETRY?",
        "_UDGSN-V-CAPTURE",
    )
    assert "_UDGSN-V-INDEX @ _UDGSN-PRIOR-INDEX @ U<" in order
    assert "_UDGSN-PRIOR-ROOT @ _UDGSN-V-ROOT-KEY @ U< 0=" in order
    assert "_UDGSN-V-GENERATION @ _UDGSN-PRIOR-GENERATION @ <>" in order
    assert "_UTUI-MOUNTED-DATA-GRAPHICS-GEOMETRY" in geometry
    assert "_UTUI-MOUNTED-DATA-GRAPHICS-CAPTURE-PREFLIGHTED" in produce

    measure_at = capture.index("0 0 _UDGSN-V-PRODUCE")
    remaining_at = capture.index("_UDGSN-V-REMAINING @ U>", measure_at)
    dirty_at = capture.index("_UDGSN-DIRTY-NATIVE-U !", remaining_at)
    copy_at = capture.index("_UDGSN-V-PRODUCE", dirty_at)
    exact_at = capture.index("_UDGSN-V-ENTRY-U @ <>", copy_at)
    validate_at = capture.index("_UDGSN-V-VALIDATE?", exact_at)
    metadata_at = capture.index("_UDGSN-V-WRITE-METADATA", validate_at)
    commit_at = capture.index(
        "_UDGSN-V-NEXT-NATIVE @ _UDGSN-NATIVE-USED !", metadata_at
    )
    assert measure_at < remaining_at < dirty_at < copy_at < exact_at
    assert exact_at < validate_at < metadata_at < commit_at

    assert "UDG-ENTRY-VALIDATE" in validate
    assert "_UDGSN-D.SUMMARY UDG-SUMMARY-ROOT-KEY@" in validate
    assert "_UDGSN-V-ENTRY @ UDG-ROOT-KEY@ <>" in validate
    assert "UDGSN-DESCRIPTOR-ROOT-KEY@" not in validate
    assert "_UDGSN-V-ROOT-KEY @" not in validate
    assert "UDGSN-DESCRIPTOR-ENTRY-BYTES@" in validate
    assert "_UDGSN-V-ROOT-FIT?" in validate
    assert "_UDGSN-V-ROOT-KEY @" in metadata
    assert "_UDGSN-D.ROOT-KEY !" in metadata


def test_udgsn_failure_is_atomic_over_every_dirtied_prefix() -> None:
    source = SNAPSHOT.read_text(encoding="utf-8")
    capacity = _definition(source, "_UDGSN-V-CAPACITY?")
    clear_output = _definition(source, "_UDGSN-CLEAR-OUTPUT")
    clear_scratch = _definition(source, "_UDGSN-CLEAR-SCRATCH")
    fail = _definition(source, "_UDGSN-FAIL-RESULT")
    body = _definition(source, "_UDGSN-CAPTURE-BODY")
    inner_catch = _definition(source, "_UDGSN-CAPTURE-OBSERVED-CATCH")
    public = _definition(source, "UDGSN-CAPTURE")

    _ordered(
        capacity,
        "_UDGSN-DIRTY-DESCRIPTOR-U !",
        "_UDGSN-V-DESCRIPTOR @ UDGSN-DESCRIPTOR-SIZE 0 FILL",
    )
    assert "_UDGSN-DIRTY-DESCRIPTOR-U @ ?DUP IF" in clear_output
    assert "_UDGSN-DIRTY-NATIVE-U @ ?DUP IF" in clear_output
    assert "_UDGSN-BUILDER @ UDG-BUILDER-SIZE 0 FILL" in clear_scratch
    _ordered(
        fail,
        "_UDGSN-CLEAR-OUTPUT",
        "_UDGSN-CLEAR-SCRATCH",
        "0 0 _UDGSN-STATUS @",
    )
    assert "_UDGSN-FAIL-RESULT" in body
    assert body.count("_UDGSN-CLEAR-SCRATCH") == 2
    assert "['] _UDGSN-CAPTURE-OBSERVED CATCH" in inner_catch
    assert "_UDGSN-FAIL-RESULT" in inner_catch
    assert "['] _UDGSN-CAPTURE-CALL CATCH" in public
    assert "_UDGSN-FAIL-RESULT" in public
    assert public.index("['] _UDGSN-CAPTURE-CALL CATCH") < public.index(
        "_UDGSN-SCRUB"
    )
