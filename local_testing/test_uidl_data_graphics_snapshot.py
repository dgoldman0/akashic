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
    shapes = _definition(source, "_UDGSN-SHAPES?")
    spans = _definition(source, "_UDGSN-PROOF-SPANS?")
    proof = _definition(source, "_UDGSN-AUTHORITY?")
    authority = _definition(source, "_UDGSN-AUTHORITY-DISJOINT?")
    observed = _definition(source, "_UDGSN-CAPTURE-OBSERVED")
    body = _definition(source, "_UDGSN-CAPTURE-BODY")

    assert "UDG-BUILDER-SIZE MSPAN-NONWRAPPING?" in shapes
    assert "_UDGSN-DESCRIPTORS-U @ UDGSN-DESCRIPTOR-SIZE MOD" in shapes
    assert "_UDGSN-AUTHORITY-DISJOINT?" not in shapes
    assert shapes.count("_UDGSN-DISJOINT?") == 3
    # One enclosed authority proof covers all three banks.  Each authority
    # query walks the document's storage, so clustered banks need one.
    assert "3 _UDGSN-PROOF-SPANS MSPAN-SET-INIT" in spans
    for address, length in (
        ("_UDGSN-BUILDER @", "UDG-BUILDER-SIZE"),
        ("_UDGSN-DESCRIPTORS-A @", "_UDGSN-DESCRIPTORS-U @"),
        ("_UDGSN-NATIVE-A @", "_UDGSN-NATIVE-U @"),
    ):
        assert f"{address} {length}" in spans
    assert spans.count("MSPAN-SET-PUSH") == 3
    assert "EXECUTE" not in spans + proof
    assert proof.index("_UDGSN-PROOF-SPANS?") < proof.index(
        "_UDGSN-PROOF-SPANS ['] _UDGSN-AUTHORITY-DISJOINT?"
    ) < proof.index("MSPAN-SET-PROVE-DISJOINT?")
    for authority_name in (
        "_UDGSN-OWNED-DISJOINT?",
        "UDG-STORAGE-DISJOINT?",
        "DGRAPH-STORAGE-DISJOINT?",
        "DGF-STORAGE-DISJOINT?",
        "_UTUI-STORAGE-DISJOINT-BODY?",
        "_UTUI-DATA-GRAPHICS-STORAGE-DISJOINT-OBSERVED?",
    ):
        assert authority_name in authority

    # Shapes, then the early exit for a document with no mounted
    # DATA_GRAPHICS relation (nothing is read or written), then authority,
    # all before any bank write or the mounted iterator.
    _ordered(
        observed,
        "_UDGSN-SHAPES? 0=",
        "_UTUI-MOUNTED-DATA-GRAPHICS? 0= IF 0 0 UDGSN-S-OK EXIT THEN",
        "_UDGSN-AUTHORITY? 0=",
        "_UDGSN-DESCRIPTORS-U @ UDGSN-DESCRIPTOR-SIZE /",
        "-1 _UDGSN-RANGES-VALID !",
        "_UDGSN-CAPTURE-BODY",
    )
    early = observed[: observed.index("_UDGSN-AUTHORITY? 0=")]
    for write in ("_UDGSN-CLEAR-SCRATCH", "FILL", "MOVE", "_UDGSN-CAPTURE-BODY"):
        assert write not in early
    assert "_UTUI-MOUNTED-DATA-GRAPHICS-EACH-PREFLIGHTED" in body
    assert "UTUI-RESOLVED-OBSERVE" in _definition(
        source, "_UDGSN-CAPTURE-CALL"
    )


def test_mounted_data_graphics_query_is_a_validated_read_only_walk() -> None:
    source = (SNAPSHOT.parent / "uidl-tui.f").read_text(encoding="utf-8")
    query = _definition(source, "_UTUI-MOUNTED-DATA-GRAPHICS?")
    # An unready or malformed chain answers true so the complete path runs
    # and reports it.  A validated chain is walked read-only for the kind.
    assert "_UTUI-MC-RELATIONS-READY? 0= IF -1 EXIT THEN" in query
    assert "_UTUI-MCR-KIND@ _UTUI-MC-K-DATA-GRAPHICS =" in query
    assert "_UTUI-MCR-NEXT@" in query
    for write in (" ! ", "+!", "FILL", "MOVE", "EXECUTE"):
        assert write not in query


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


def test_udgsn_frozen_validator_deeply_authenticates_exact_native_ownership() -> None:
    source = SNAPSHOT.read_text(encoding="utf-8")

    optional_span = _definition(source, "_UDGSN-OPTIONAL-SPAN?")
    assert "OVER 0< IF 2DROP 0 EXIT THEN" in optional_span
    assert "8 CONSTANT UDGSN-FROZEN-WORK-ENTRY-SIZE" in source
    sizing = _definition(source, "UDGSN-FROZEN-WORK-BYTES")
    assert "DUP 0< IF DROP 0 EXIT THEN" in sizing
    assert "UDGSN-FROZEN-WORK-ENTRY-SIZE _UDGSN-SIZED-BYTES" in sizing

    public = re.sub(r"\s+", " ", _definition(source, "UDGSN-FROZEN-VALIDATE"))
    assert (
        "( offset-work-a offset-work-u descriptors-a descriptors-u "
        "native-a native-u -- status )" in public
    )
    assert "['] _UDGSN-F-VALIDATE-CALL CATCH" in public

    ranges = _definition(source, "_UDGSN-F-RANGES")
    assert "_UDGSN-F-DESCRIPTORS-U @ UDGSN-DESCRIPTOR-SIZE MOD" in ranges
    assert "_UDGSN-F-DESCRIPTORS-U @ 0=" in ranges
    assert "_UDGSN-F-NATIVE-U @ 0= <>" in ranges
    assert "_UDGSN-F-WORK-U @ _UDGSN-F-WORK-NEED @ U<" in ranges
    assert ranges.count("_UDGSN-F-AUTHORITY-DISJOINT?") == 3
    assert ranges.count("_UDGSN-DISJOINT?") == 3
    _ordered(
        ranges,
        "_UDGSN-F-WORK-U @ _UDGSN-F-WORK-NEED @ U<",
        "-1 _UDGSN-F-RANGES-VALID !",
        "_UDGSN-F-CLEAR-SCRATCH",
    )

    entry = _definition(source, "_UDGSN-F-ENTRY?")
    _ordered(
        entry,
        "UDGSN-DESCRIPTOR-NATIVE-OFFSET@",
        "_UDGSN-F-NATIVE-U @ _UDGSN-F-OFFSET @ -",
        "UDG-ENTRY-BYTES@",
        "UDG-ENTRY-VALIDATE",
        "UDGSN-DESCRIPTOR-SUMMARY UDG-SUMMARY-SIZE",
        "COMPARE 0=",
        "_UDGSN-F-GEOMETRY?",
        "_UDGSN-F-WORK-AT !",
    )
    # The mounted relation key names the descriptor ordering relation.  The
    # graph's application-owned root key is authenticated only through the
    # recomputed UDG summary and must never be equated with that relation key.
    assert "UDGSN-DESCRIPTOR-ROOT-KEY@" not in entry
    assert "_UDGSN-F-RELATION" not in entry

    order = _definition(source, "_UDGSN-F-ORDER?")
    assert "UDGSN-DESCRIPTOR-ROOT-KEY@" in order
    assert "_UDGSN-F-PRIOR-RELATION @ _UDGSN-F-RELATION @" in order
    assert "_UDGSN-F-GENERATION @ _UDGSN-F-PRIOR-GENERATION @" in order

    geometry = _definition(source, "_UDGSN-F-GEOMETRY?")
    for accessor in (
        "UDGSN-DESCRIPTOR-ROW@",
        "UDGSN-DESCRIPTOR-COLUMN@",
        "UDGSN-DESCRIPTOR-CLIP-ROW@",
        "UDGSN-DESCRIPTOR-CLIP-COLUMN@",
    ):
        assert f"{accessor} DUP 0< IF" in geometry
    assert "UDGSN-DESCRIPTOR-HEIGHT@\n        _UDGSN-F-GRAPH @ UDG-ROOT-HEIGHT@ <>" in geometry
    assert "UDGSN-DESCRIPTOR-WIDTH@\n        _UDGSN-F-GRAPH @ UDG-ROOT-WIDTH@ <>" in geometry
    assert "UDGSN-DESCRIPTOR-Z@ 255 U>" in geometry

    # Native offsets are not trusted to follow descriptor identity order.
    # The bounded heap sort is O(n log n), after which one cursor proves an
    # exact gap-free, overlap-free partition of the whole native bank.
    heap = _definition(source, "_UDGSN-F-SIFT-DOWN")
    sort = _definition(source, "_UDGSN-F-SORT-OFFSETS")
    coverage = _definition(source, "_UDGSN-F-COVERAGE?")
    assert "2 * 1+" in heap
    assert "_UDGSN-F-SWAP-OFFSETS" in heap
    assert sort.count("_UDGSN-F-SIFT-DOWN") == 2
    assert "_UDGSN-F-CURSOR @ <> IF 0 EXIT THEN" in coverage
    assert "UDG-ENTRY-BYTES@" in coverage
    assert "_UDGSN-F-CURSOR @ _UDGSN-F-NATIVE-U @ =" in coverage

    body = _definition(source, "_UDGSN-F-VALIDATE-BODY")
    _ordered(
        body,
        "_UDGSN-F-RANGES",
        "_UDGSN-F-ORDER?",
        "_UDGSN-F-ENTRY?",
        "_UDGSN-F-SORT-OFFSETS",
        "_UDGSN-F-COVERAGE?",
    )
    guarded = _definition(source, "_UDGSN-F-VALIDATE-CALL")
    _ordered(
        guarded,
        "['] _UDGSN-F-VALIDATE-BODY CATCH",
        "_UDGSN-F-CLEAR-SCRATCH",
        "_UDGSN-F-SCRUB",
    )
