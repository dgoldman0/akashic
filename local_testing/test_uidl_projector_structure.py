"""Seconds-only structural and byte-layout locks for UIDL candidates."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECTOR = ROOT / "akashic" / "tui" / "rich-terminal" / "uidl-projector.f"
SEMANTIC = ROOT / "akashic" / "liraq" / "uidl-semantic.f"


def _definition(source: str, name: str) -> str:
    matches = re.findall(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert matches, name
    return matches[-1]


def _first_definition(source: str, name: str) -> str:
    matches = re.findall(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert matches, name
    return matches[0]


def _code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _layout(capacities: list[int]) -> tuple[list[tuple[int, int]], int, int]:
    """Oracle for physical offset/exact length, high-water, and UTF-8 quota."""
    items: list[tuple[int, int]] = []
    used = 0
    utf8 = 0
    for capacity in capacities:
        exact = 64 + capacity
        stride = (exact + 7) & ~7
        items.append((used, exact))
        used += stride
        utf8 += capacity
    return items, used, utf8


def test_projector_is_neutral_allocation_free_and_caller_bounded() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    code = _code(source)

    assert "PROVIDED akashic-tui-rterm-uidl-projector1" in code
    assert re.findall(r"(?m)^REQUIRE\s+(\S+)\s*$", code) == [
        "../../liraq/uidl-semantic.f",
        "../../utils/memory-span.f",
        "../../concurrency/guard.f",
    ]
    assert not re.search(
        r"(?m)(?:^|[ \t])(?:CREATE|ALLOT|ALLOCATE|FREE|RESIZE|XBUF|BUFFER:)"
        r"(?=[ \t]|$)",
        code,
    )
    for forbidden in (
        "PT-",
        "RTE-",
        "RTAPT-",
        "RTERM-",
        "APTSCB-",
        "APTAS-",
        "SCR-",
        "DRW-",
        "RGN-",
        "AHOST-",
        "DESK-",
        "EXECUTE",
    ):
        assert forbidden not in code

    ranges = _definition(source, "_RUPJ-RANGES?")
    assert ranges.count("_RUPJ-SPAN?") == 2
    assert "RUPJ-ITEM-SIZE MOD" in ranges
    assert "RUPJ-ITEM-SIZE / DUP 0=" in ranges
    assert ranges.count("UIDL-STORAGE-DISJOINT?") == 2
    assert ranges.count("ST-STORAGE-DISJOINT?") == 2
    assert "MSPAN-OVERLAP? 0=" in ranges


def test_item_contract_keeps_stable_key_and_exact_snapshot_extent() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")

    assert "48 CONSTANT RUPJ-ITEM-SIZE" in source
    fields = {
        "_RUPJ-I.ELEMENT-INDEX": 0,
        "_RUPJ-I.SUBKEY": 8,
        "_RUPJ-I.KIND": 16,
        "_RUPJ-I.SNAPSHOT-OFF": 24,
        "_RUPJ-I.SNAPSHOT-BYTES": 32,
        "_RUPJ-I.RESERVED": 40,
    }
    for name, offset in fields.items():
        definition = _definition(source, name)
        if offset:
            assert f"{offset} +" in definition
        else:
            assert "+" not in definition

    capture = _definition(source, "_RUPJ-LABEL-CAPTURE")
    item_clear = capture.index("RUPJ-ITEM-SIZE 0 FILL")
    stores = (
        "_RUPJ-I.ELEMENT-INDEX !",
        "_RUPJ-I.KIND !",
        "_RUPJ-I.SNAPSHOT-OFF !",
        "_RUPJ-I.SNAPSHOT-BYTES !",
    )
    assert all(item_clear < capture.index(store) for store in stores)
    assert "UIDL-SNAPSHOT-K-LABEL" in capture
    assert "_RUPJ-I.SUBKEY !" not in capture
    assert "_RUPJ-I.RESERVED !" not in capture


def test_arena_alignment_is_physical_but_utf8_quota_is_raw() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    align = _definition(source, "_RUPJ-ALIGN8?")
    preflight = _definition(source, "_RUPJ-LABEL-PREFLIGHT")
    capture = _definition(source, "_RUPJ-LABEL-CAPTURE")

    assert "7 _RUPJ-UADD?" in align
    assert "-8 AND" in align
    assert "_RUPJ-LENGTH-MAX U>" in align
    assert "_RUPJ-C-EXACT @ _RUPJ-ALIGN8?" in preflight
    assert "_RUPJ-C-STRIDE @" in preflight
    assert "_RUPJ-C-NEXT-SNAPSHOT !" in preflight

    # The record stores exact bytes, while the next physical high-water uses
    # the aligned stride and owner quota uses the raw declared text ceiling.
    assert "_RUPJ-C-EXACT @ _RUPJ-C-ITEM @ _RUPJ-I.SNAPSHOT-BYTES !" in capture
    assert "_RUPJ-C-NEXT-SNAPSHOT @ _RUPJ-SNAPSHOT-USED !" in capture
    assert "UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@" in capture
    assert "_RUPJ-UTF8-QUOTA @ _RUPJ-C-TEXT-CAP @ _RUPJ-UADD?" in capture

    items, used, utf8 = _layout([4, 9])
    assert items == [(0, 68), (72, 73)]
    assert used == 152
    assert utf8 == 13


def test_capture_measures_preflights_then_copies_before_item_publication() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    capture = _definition(source, "_RUPJ-LABEL-CAPTURE")

    measure = capture.index("UIDL-SNAPSHOT-SIZE")
    unsupported = capture.index("UIDL-SNAP-S-UNSUPPORTED", measure)
    preflight = capture.index("_RUPJ-LABEL-PREFLIGHT", unsupported)
    copied = capture.index("UIDL-SNAPSHOT-CAPTURE", preflight)
    validated = capture.index("UIDL-LABEL-SNAPSHOT-VALID?", copied)
    cap = capture.index("UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@", validated)
    item = capture.index("RUPJ-ITEM-SIZE 0 FILL", cap)
    snapshot_commit = capture.index("_RUPJ-SNAPSHOT-USED !", item)
    utf8_commit = capture.index("_RUPJ-UTF8-QUOTA !", snapshot_commit)
    count_commit = capture.index("_RUPJ-ITEM-COUNT +!", utf8_commit)
    assert measure < unsupported < preflight < copied < validated < cap
    assert cap < item < snapshot_commit < utf8_commit < count_commit

    assert "UIDL-SNAP-S-CAPACITY" in capture
    assert capture.count("_RUPJ-SET-CAPACITY") >= 3
    assert capture.count("_RUPJ-SET-INVALID") >= 4


def test_tree_walk_uses_pool_indices_not_ids_and_is_cycle_bounded() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    process = _definition(source, "_RUPJ-PROCESS-ELEMENT")
    walk = _definition(source, "_RUPJ-WALK")
    body = _definition(source, "_RUPJ-BUILD-BODY")

    assert "UIDL-ELEM-INDEX?" in process
    assert "UIDL-TYPE UIDL-T-LABEL =" in process
    assert "_RUPJ-VISITED @ 1 _RUPJ-UADD?" in process
    assert "_RUPJ-ELEMENT-TOTAL @ U>" in process
    assert "UIDL-ID" not in source

    assert "UIDL-FIRST-CHILD" in walk
    assert walk.index("UIDL-ELEM-INDEX? 0= IF") < walk.index(
        "UIDL-PARENT 2 PICK <>"
    )
    assert "UIDL-PARENT 2 PICK <>" in walk
    assert "UIDL-NEXT-SIB SWAP RECURSE" in walk
    assert "UIDL-ELEM-COUNT" in body
    assert "UIDL-ROOT" in body
    assert body.index("UIDL-ELEM-INDEX? 0= IF") < body.index(
        "DUP UIDL-PARENT 0<>"
    )
    assert "DUP UIDL-PARENT 0<>" in body


def test_complete_source_observation_and_failure_atomicity_are_explicit() -> None:
    projector = PROJECTOR.read_text(encoding="utf-8")
    semantic = SEMANTIC.read_text(encoding="utf-8")

    observe = _definition(semantic, "UIDL-SEMANTIC-OBSERVE")
    semantic_guard = _definition(semantic, "_UIDLS-OBSERVE-WITH-SEMANTIC")
    lel = _definition(semantic, "_UIDLS-OBSERVE-IN-LEL")
    state = _definition(semantic, "_UIDLS-OBSERVE-IN-STATE")
    assert "UIDL-OBSERVE" in observe
    assert "_uidls-guard WITH-GUARD" in semantic_guard
    assert "LEL-OBSERVE" in lel
    assert "ST-OBSERVE" in state

    call = _definition(projector, "_RUPJ-BUILD-CALL")
    assert "['] _RUPJ-BUILD-BODY UIDL-SEMANTIC-OBSERVE" in call

    body = _definition(projector, "_RUPJ-BUILD-BODY")
    ranges = body.index("_RUPJ-RANGES? 0= IF")
    publish_ranges = body.index("-1 _RUPJ-RANGES-VALID !", ranges)
    initial_clear = body.index("_RUPJ-CLEAR-BANKS", publish_ranges)
    walk = body.index("_RUPJ-WALK", initial_clear)
    result = body.rindex("RUPJ-S-OK")
    assert ranges < publish_ranges < initial_clear < walk < result
    assert body.count("_RUPJ-FAIL-RESULT") == 6

    failure = _definition(projector, "_RUPJ-FAIL-RESULT")
    assert failure.index("_RUPJ-CLEAR-BANKS") < failure.index(
        "0 0 0 0 0 _RUPJ-STATUS @"
    )
    public = _first_definition(projector, "RUPJ-BUILD")
    assert public.index("['] _RUPJ-BUILD-CALL CATCH") < public.index(
        "_RUPJ-SCRUB"
    )

    guarded = _definition(projector, "RUPJ-BUILD")
    serialized = _definition(projector, "_RUPJ-BUILD-GUARDED")
    assert "['] _RUPJ-BUILD-GUARDED UIDL-OBSERVE" in guarded
    assert "_rupj-build-xt _rupj-guard WITH-GUARD" in serialized

    variables = set(re.findall(r"(?m)^VARIABLE\s+(_RUPJ-[^\s]+)", projector))
    scrub = _definition(projector, "_RUPJ-SCRUB")
    scrubbed = set(re.findall(r"(?<!\S)0\s+(_RUPJ-[A-Z0-9-]+)\s+!", scrub))
    assert scrubbed == variables


def test_published_candidate_validation_rechecks_canonical_dense_layout() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    ranges = _definition(source, "_RUPJ-V-RANGES?")
    one = _definition(source, "_RUPJ-V-ONE?")
    body = _definition(source, "_RUPJ-V-BODY?")

    assert ranges.count("_RUPJ-SPAN?") == 2
    assert "RUPJ-ITEM-SIZE MOD" in ranges
    assert "MSPAN-OVERLAP? IF" in ranges
    assert "_RUPJ-V-ITEM-COUNT @ 0<> IF 1 ELSE 0 THEN" in ranges
    assert "_RUPJ-V-OBJECTS @ _RUPJ-V-ITEM-COUNT @ <>" in ranges

    assert "_RUPJ-V-KEY-FIRST?" in one
    assert "_RUPJ-I.SUBKEY @ IF" in one
    assert "UIDL-SNAPSHOT-K-LABEL <>" in one
    assert "_RUPJ-I.RESERVED @ IF" in one
    assert "_RUPJ-V-EXPECTED-OFF @ <>" in one
    assert "_RUPJ-ALIGN8?" in one
    assert "UIDL-LABEL-SNAPSHOT-VALID?" in one
    assert "UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@" in one
    assert "_RUPJ-ZERO?" in one

    assert "_RUPJ-V-EXPECTED-OFF @ _RUPJ-V-SNAPSHOT-USED @ <>" in body
    assert "_RUPJ-V-UTF8-SUM @ _RUPJ-V-UTF8 @ <>" in body
    assert body.count("_RUPJ-ZERO?") == 2

    public = _definition(source, "RUPJ-CANDIDATE-VALID?")
    assert "_rupj-candidate-valid-q-xt _rupj-guard WITH-GUARD" in public
