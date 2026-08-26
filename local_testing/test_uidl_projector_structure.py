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


def _layout(text_lengths: list[int]) -> tuple[list[tuple[int, int]], int, int]:
    """Oracle for physical offset/exact length, high-water, and UTF-8 quota."""
    items: list[tuple[int, int]] = []
    used = 0
    utf8 = 0
    for text_length in text_lengths:
        exact = 64 + text_length
        stride = (exact + 7) & ~7
        items.append((used, exact))
        used += stride
        utf8 += text_length
    return items, used, utf8


def test_projector_is_neutral_allocation_free_and_caller_bounded() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    code = _code(source)

    assert re.findall(r"(?m)^PROVIDED\s+(\S+)\s*$", code) == [
        "akashic-tui-rterm-uidl-projector"
    ]
    assert "UIDL-LABEL-SNAPSHOT-TEXT-CAPACITY@" not in code
    assert re.findall(r"(?m)^REQUIRE\s+(\S+)\s*$", code) == [
        "../uidl-tui.f",
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
        "_UTUI",
        "TSC-",
        "UTUI-ELEM-RGN",
        "sidecar",
        "EXECUTE",
    ):
        assert forbidden not in code
    assert "SIDECAR" not in code.upper()

    assert set(re.findall(r"(?<![_A-Z0-9-])(UTUI-[A-Z0-9?@-]+)", code)) == {
        "UTUI-ELEM-RESOLVED-CAPTURE",
        "UTUI-RESOLVED-BYTES",
        "UTUI-RESOLVED-OBSERVE",
        "UTUI-RESOLVED-S-OK",
        "UTUI-RESOLVED-S-UNAVAILABLE",
        "UTUI-RESOLVED-VALID?",
        "UTUI-STORAGE-DISJOINT?",
    }

    ranges = _definition(source, "_RUPJ-RANGES?")
    assert ranges.count("_RUPJ-SPAN?") == 2
    assert "RUPJ-ITEM-SIZE MOD" in ranges
    assert "RUPJ-ITEM-SIZE / DUP 0=" in ranges
    assert ranges.count("UTUI-STORAGE-DISJOINT?") == 2
    assert ranges.count("UIDL-STORAGE-DISJOINT?") == 2
    assert ranges.count("ST-STORAGE-DISJOINT?") == 2
    assert "MSPAN-OVERLAP? 0=" in ranges


def test_item_contract_keeps_key_snapshot_and_neutral_resolved_state() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")

    assert "128 CONSTANT RUPJ-ITEM-SIZE" in source
    assert "1 CONSTANT RUPJ-ITEM-F-HAS-RESOLVED" in source
    assert "2 CONSTANT RUPJ-ITEM-F-EFFECTIVE-VISIBLE" in source
    assert "3 CONSTANT _RUPJ-ITEM-F-MASK" in source
    fields = {
        "_RUPJ-I.ELEMENT-INDEX": 0,
        "_RUPJ-I.SUBKEY": 8,
        "_RUPJ-I.KIND": 16,
        "_RUPJ-I.SNAPSHOT-OFF": 24,
        "_RUPJ-I.SNAPSHOT-BYTES": 32,
        "_RUPJ-I.FLAGS": 40,
        "_RUPJ-I.RESOLVED": 48,
        "_RUPJ-I.RESERVED": 120,
    }
    for name, offset in fields.items():
        definition = _definition(source, name)
        if offset:
            assert f"{offset} +" in definition
        else:
            assert "+" not in definition

    accessors = {
        "RUPJ-ITEM-BYTES": "RUPJ-ITEM-SIZE",
        "RUPJ-ITEM-ELEMENT-INDEX@": "_RUPJ-I.ELEMENT-INDEX @",
        "RUPJ-ITEM-SUBKEY@": "_RUPJ-I.SUBKEY @",
        "RUPJ-ITEM-KIND@": "_RUPJ-I.KIND @",
        "RUPJ-ITEM-SNAPSHOT-OFFSET@": "_RUPJ-I.SNAPSHOT-OFF @",
        "RUPJ-ITEM-SNAPSHOT-BYTES@": "_RUPJ-I.SNAPSHOT-BYTES @",
        "RUPJ-ITEM-FLAGS@": "_RUPJ-I.FLAGS @",
        "RUPJ-ITEM-HAS-RESOLVED?": "RUPJ-ITEM-F-HAS-RESOLVED AND 0<>",
        "RUPJ-ITEM-EFFECTIVE-VISIBLE?": (
            "RUPJ-ITEM-F-EFFECTIVE-VISIBLE AND 0<>"
        ),
        "RUPJ-ITEM-RESOLVED": "_RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES",
        "RUPJ-ITEM-RESOLVED-ROW@": "_RUPJ-R.ROW @",
        "RUPJ-ITEM-RESOLVED-COL@": "_RUPJ-R.COL @",
        "RUPJ-ITEM-RESOLVED-HEIGHT@": "_RUPJ-R.H @",
        "RUPJ-ITEM-RESOLVED-WIDTH@": "_RUPJ-R.W @",
        "RUPJ-ITEM-RESOLVED-FG@": "_RUPJ-R.FG @",
        "RUPJ-ITEM-RESOLVED-BG@": "_RUPJ-R.BG @",
        "RUPJ-ITEM-RESOLVED-ATTRS@": "_RUPJ-R.ATTRS @",
        "RUPJ-ITEM-RESOLVED-ALIGN@": "_RUPJ-R.ALIGN @",
        "RUPJ-ITEM-RESOLVED-Z@": "_RUPJ-R.Z @",
    }
    for name, fragment in accessors.items():
        assert fragment in _definition(source, name)
    assert set(re.findall(r"(?m)^:\s+(RUPJ-[^\s]+)(?=\s)", source)) == {
        "RUPJ-STATUS-VALID?",
        *accessors,
        "RUPJ-BUILD",
        "RUPJ-CANDIDATE-VALID?",
    }

    capture = _definition(source, "_RUPJ-LABEL-CAPTURE")
    item_clear = capture.index("RUPJ-ITEM-SIZE 0 FILL")
    resolved = capture.index("_RUPJ-CAPTURE-RESOLVED?", item_clear)
    stores = (
        "_RUPJ-I.ELEMENT-INDEX !",
        "_RUPJ-I.KIND !",
        "_RUPJ-I.SNAPSHOT-OFF !",
        "_RUPJ-I.SNAPSHOT-BYTES !",
    )
    assert all(resolved < capture.index(store) for store in stores)
    assert "UIDL-SNAPSHOT-K-LABEL" in capture
    assert "_RUPJ-I.SUBKEY !" not in capture
    assert "_RUPJ-I.RESERVED !" not in capture


def test_arena_alignment_is_physical_but_utf8_quota_is_current_text() -> None:
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
    # the aligned stride and owner quota use the current copied text length.
    assert "_RUPJ-C-EXACT @ _RUPJ-C-ITEM @ _RUPJ-I.SNAPSHOT-BYTES !" in capture
    assert "_RUPJ-C-NEXT-SNAPSHOT @ _RUPJ-SNAPSHOT-USED !" in capture
    assert "UIDL-LABEL-SNAPSHOT-TEXT@ NIP" in capture
    assert "_RUPJ-UTF8-QUOTA @ _RUPJ-C-TEXT-U @ _RUPJ-UADD?" in capture

    items, used, utf8 = _layout([0, 4, 9])
    assert items == [(0, 64), (64, 68), (136, 73)]
    assert used == 216
    assert utf8 == 13


def test_capture_measures_preflights_then_copies_before_item_publication() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    capture = _definition(source, "_RUPJ-LABEL-CAPTURE")

    measure = capture.index("UIDL-SNAPSHOT-SIZE")
    unsupported = capture.index("UIDL-SNAP-S-UNSUPPORTED", measure)
    preflight = capture.index("_RUPJ-LABEL-PREFLIGHT", unsupported)
    copied = capture.index("UIDL-SNAPSHOT-CAPTURE", preflight)
    validated = capture.index("UIDL-LABEL-SNAPSHOT-VALID?", copied)
    text = capture.index("UIDL-LABEL-SNAPSHOT-TEXT@ NIP", validated)
    item = capture.index("RUPJ-ITEM-SIZE 0 FILL", text)
    resolved = capture.index("_RUPJ-CAPTURE-RESOLVED?", item)
    key = capture.index("_RUPJ-I.ELEMENT-INDEX !", resolved)
    snapshot_commit = capture.index("_RUPJ-SNAPSHOT-USED !", key)
    utf8_commit = capture.index("_RUPJ-UTF8-QUOTA !", snapshot_commit)
    count_commit = capture.index("_RUPJ-ITEM-COUNT +!", utf8_commit)
    assert measure < unsupported < preflight < copied < validated < text
    assert text < item < resolved < key < snapshot_commit
    assert snapshot_commit < utf8_commit < count_commit

    assert "UIDL-SNAP-S-CAPACITY" in capture
    assert capture.count("_RUPJ-SET-CAPACITY") >= 3
    assert capture.count("_RUPJ-SET-INVALID") >= 4


def test_resolved_capture_is_root_relative_and_status_closed() -> None:
    source = PROJECTOR.read_text(encoding="utf-8")
    subtract = _definition(source, "_RUPJ-SSUB?")
    normalize = _definition(source, "_RUPJ-C-NORMALIZE-RESOLVED?")
    capture = _definition(source, "_RUPJ-CAPTURE-RESOLVED?")
    root = _definition(source, "_RUPJ-CAPTURE-ROOT?")

    assert "_RUPJ-SIGNED-MIN _RUPJ-SUB-B @ + < IF" in subtract
    assert "_RUPJ-SIGNED-MAX _RUPJ-SUB-B @ + > IF" in subtract
    assert "_RUPJ-SUB-A @ _RUPJ-SUB-B @ - -1" in subtract

    assert normalize.count("UTUI-RESOLVED-VALID?") == 2
    assert normalize.count("_RUPJ-SSUB?") == 2
    assert "_RUPJ-ROOT-ROW @ _RUPJ-SSUB?" in normalize
    assert "_RUPJ-ROOT-COL @ _RUPJ-SSUB?" in normalize
    assert "_RUPJ-C-NORM-ROW @" in normalize
    assert "_RUPJ-C-NORM-COL @" in normalize

    assert capture.count("UTUI-ELEM-RESOLVED-CAPTURE") == 1
    ok = capture.index("UTUI-RESOLVED-S-OK = IF")
    normalized = capture.index("_RUPJ-C-NORMALIZE-RESOLVED?", ok)
    has = capture.index("RUPJ-ITEM-F-HAS-RESOLVED", normalized)
    visible = capture.index("RUPJ-ITEM-F-EFFECTIVE-VISIBLE", has)
    unavailable = capture.index("UTUI-RESOLVED-S-UNAVAILABLE = IF", visible)
    zero = capture.index("_RUPJ-ZERO? 0= IF", unavailable)
    invalid = capture.rindex("_RUPJ-SET-INVALID 0")
    assert ok < normalized < has < visible < unavailable < zero < invalid
    assert "_RUPJ-C-RESOLVED-FLAGS @ _RUPJ-C-ITEM @ _RUPJ-I.FLAGS !" in capture
    assert "-1 EXIT" in capture[unavailable:invalid]

    assert root.count("UTUI-ELEM-RESOLVED-CAPTURE") == 1
    assert "UTUI-RESOLVED-S-OK <> IF" in root
    assert "UTUI-RESOLVED-S-UNAVAILABLE" not in root
    assert "UTUI-RESOLVED-VALID? 0= IF" in root
    assert root.count("DUP 0< IF DROP 0 EXIT THEN") == 2
    assert root.count("DUP 0> 0= IF DROP 0 EXIT THEN") == 2
    assert "_RUPJ-ROOT-ROW !" in root
    assert "_RUPJ-ROOT-COL !" in root
    assert "_RUPJ-ROOT-H !" in root
    assert "_RUPJ-ROOT-W !" in root
    assert root.rindex("RUPJ-ITEM-SIZE 0 FILL") < root.rindex("-1")


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
    root_capture = body.index("_RUPJ-CAPTURE-ROOT? 0= IF")
    walk = body.index("_RUPJ-WALK", root_capture)
    assert root_capture < walk
    assert "_RUPJ-ROOT-H @" in body[walk:]
    assert "_RUPJ-ROOT-W @" in body[walk:]


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
    assert body.count("_RUPJ-FAIL-RESULT") == 7

    failure = _definition(projector, "_RUPJ-FAIL-RESULT")
    assert failure.index("_RUPJ-CLEAR-BANKS") < failure.index(
        "0 0 0 0 0 0 0 _RUPJ-STATUS @"
    )
    public = _first_definition(projector, "RUPJ-BUILD")
    assert public.index("['] _RUPJ-BUILD-CALL CATCH") < public.index(
        "_RUPJ-SCRUB"
    )

    guarded = _definition(projector, "RUPJ-BUILD")
    serialized = _definition(projector, "_RUPJ-BUILD-GUARDED")
    assert "['] _RUPJ-BUILD-GUARDED UTUI-RESOLVED-OBSERVE" in guarded
    assert "_rupj-build-xt _rupj-guard WITH-GUARD" in serialized

    assert (
        "root-height root-width status" in _first_definition(projector, "RUPJ-BUILD")
    )

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
    assert "_RUPJ-V-ROOT-H @ DUP 0> 0= IF" in ranges
    assert "_RUPJ-V-ROOT-W @ DUP 0> 0= IF" in ranges

    assert "_RUPJ-V-KEY-FIRST?" in one
    assert "_RUPJ-I.SUBKEY @ IF" in one
    assert "UIDL-SNAPSHOT-K-LABEL <>" in one
    assert "_RUPJ-ITEM-F-MASK INVERT AND IF" in one
    visible = one.index("RUPJ-ITEM-F-EFFECTIVE-VISIBLE AND IF")
    has = one.index("RUPJ-ITEM-F-HAS-RESOLVED AND 0= IF", visible)
    assert visible < has
    assert "UTUI-RESOLVED-VALID? 0= IF" in one
    assert "_RUPJ-V-INTERSECTS-ROOT? 0= IF" in one
    assert "_RUPJ-I.RESOLVED UTUI-RESOLVED-BYTES" in one
    assert "_RUPJ-I.RESERVED @ IF" in one
    assert "_RUPJ-V-EXPECTED-OFF @ <>" in one
    assert "_RUPJ-ALIGN8?" in one
    assert "UIDL-LABEL-SNAPSHOT-VALID?" in one
    assert "UIDL-LABEL-SNAPSHOT-TEXT@ NIP" in one
    assert "_RUPJ-ZERO?" in one

    assert "_RUPJ-V-EXPECTED-OFF @ _RUPJ-V-SNAPSHOT-USED @ <>" in body
    assert "_RUPJ-V-UTF8-SUM @ _RUPJ-V-UTF8 @ <>" in body
    assert body.count("_RUPJ-ZERO?") == 2

    public = _definition(source, "RUPJ-CANDIDATE-VALID?")
    assert "root-height root-width -- flag" in public
    assert "_rupj-candidate-valid-q-xt _rupj-guard WITH-GUARD" in public

    intersects = _definition(source, "_RUPJ-V-INTERSECTS-ROOT?")
    for fragment in (
        "_RUPJ-V-R-ROW @ _RUPJ-V-ROOT-H @ <",
        "_RUPJ-V-R-ROW @ _RUPJ-V-R-H @ + 0> AND",
        "_RUPJ-V-R-COL @ _RUPJ-V-ROOT-W @ < AND",
        "_RUPJ-V-R-COL @ _RUPJ-V-R-W @ + 0> AND",
    ):
        assert fragment in intersects
