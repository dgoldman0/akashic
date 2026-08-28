"""Seconds-scale contract guards for neutral UIDL menu snapshots."""

from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/uidl-menu-snapshot.f"


def _source() -> str:
    return SOURCE.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def _semantic_tag_count(relative: str) -> int:
    uidl = (ROOT / relative).read_text(encoding="utf-8")
    return len(re.findall(r"<(?:menubar|menu|item|separator)\b", uidl))


def test_snapshot_and_work_records_have_exact_pointer_free_shapes() -> None:
    source = _source()

    assert "192 CONSTANT UMSN-RECORD-SIZE" in source
    assert "136 CONSTANT UMSN-WORK-ENTRY-SIZE" in source
    assert "3 CONSTANT UMSN-S-INVALID" in source
    assert ": UMSN-STATUS-VALID?  ( status -- flag )  4 U< ;" in source
    assert "UMSN-S-STALE" not in source
    assert "32 CONSTANT UMSN-F-PAINTABLE" in source
    assert "0x314E53554E454D55 CONSTANT _UMSN-RECORD-MAGIC" in source
    assert ": _UMSN-R.RESOLVED    ( r -- a ) 120 + ;" in source
    assert ": _UMSN-W.RESOLVED    ( w -- a )  64 + ;" in source

    record_cells = (
        0x314E53554E454D55,
        1,
        192,
        9,
        1,
        12,
        0,
        8,
        3,
        0x33,
        4,
        0,
        5,
        5,
        6,
        1,
        2,
        1,
        20,
        80,
        253,
        236,
        0,
        7,
    )
    packed_record = struct.pack("<24Q", *record_cells)
    assert len(packed_record) == 192
    assert packed_record[:8] == b"UMENUSN1"
    assert struct.unpack_from("<Q", packed_record, 120)[0] == 1
    assert struct.unpack_from("<Q", packed_record, 184)[0] == 7

    work_cells = (3, 8, 4, 0x33, 0, 5, 5, 6, *range(1, 10))
    packed_work = struct.pack("<17Q", *work_cells)
    assert len(packed_work) == 136
    assert struct.unpack_from("<Q", packed_work, 64)[0] == 1
    assert struct.unpack_from("<Q", packed_work, 128)[0] == 9

    write = _word(source, "_UMSN-WRITE-RECORD")
    for borrowed_pointer in (
        "_UMSN-V-ELEM",
        "_UMSN-V-LABEL-A",
        "_UMSN-V-SHORTCUT-A",
        "_UMSN-V-RESOLVED-A",
    ):
        assert borrowed_pointer not in write
    assert write.index("_UMSN-E-COPY-TEXT") < write.index(
        "_UMSN-RECORD-MAGIC"
    )
    assert write.index("_UMSN-DIRTY-RECORD-U") < write.index("0 FILL")


def test_capture_uses_four_caller_bounded_disjoint_spans() -> None:
    source = _source()
    ranges = _word(source, "_UMSN-RANGES?")
    capture = _word(source, "UMSN-CAPTURE")
    clear = _word(source, "_UMSN-CLEAR-PARTIAL")

    assert "ALLOCATE" not in source
    assert " FREE" not in source
    assert ranges.count("_UMSN-OPTIONAL-SPAN?") == 4
    assert ranges.count("_UMSN-AUTHORITY-DISJOINT?") == 4
    assert ranges.count("MSPAN-OVERLAP?") == 6
    assert "UMSN-WORK-ENTRY-SIZE MOD" in ranges
    assert "UMSN-RECORD-SIZE MOD" in ranges
    assert "_UMSN-WORK-TEXT-U ! _UMSN-WORK-TEXT-A !" in capture
    assert capture.index("_UMSN-RANGES?") < capture.index(
        "_UMSN-CAPTURE-BODY"
    )
    assert "_UMSN-DIRTY-WORK-TEXT-U" in clear
    assert "_UMSN-DIRTY-RECORD-U" in clear
    assert "_UMSN-DIRTY-TEXT-U" in clear
    assert "_UMSN-WORK-U @ ?DUP" in clear
    assert "_UMSN-SCRUB" in capture


def test_capture_is_one_tree_visit_plus_one_canonical_index_pass() -> None:
    source = _source()
    body = _word(source, "_UMSN-CAPTURE-BODY")
    visitor = _word(source, "_UMSN-TREE-VISITOR")
    classify = _word(source, "_UMSN-V-CLASSIFY?")
    resolved = _word(source, "_UMSN-V-RESOLVED?")
    emit = _word(source, "_UMSN-EMIT-CANONICAL")
    emit_one = _word(source, "_UMSN-EMIT-ONE")

    assert body.count("UTUI-RESOLVED-TREE-EACH") == 1
    for forbidden in (
        "_UMSN-WALK-DOCUMENT",
        "_UMSN-MARK-MENU",
        "_UMSN-MARK-MENUBAR",
        "_UMSN-CAPTURE-RESOLVED",
        "UTUI-ELEM-RESOLVED",
        "UTUI-RESOLVED-OBSERVE",
        "_UTUI-RS-CLEAR",
    ):
        assert forbidden not in source

    assert "_UMSN-V-LOCAL !" in visitor
    assert "_UMSN-V-EFFECTIVE !" in visitor
    assert "_UMSN-V-RESOLVED-U !" in visitor
    assert "UIDL-FIRST-CHILD IF" in classify
    assert "_UTUI-MENU-ROW?" in classify
    assert "UIDL-T-SEPARATOR" in classify
    assert "_UMSN-SET-UNAVAILABLE" in resolved
    assert "UTUI-RESOLVED-SIZE <>" in resolved
    assert "_UMSN-W.RESOLVED UTUI-RESOLVED-SIZE CMOVE" in resolved

    assert "_UMSN-SCAN-I @ _UMSN-HIGH-WATER @ <" in emit
    assert "_UMSN-WORK-AT" in emit
    assert "_UMSN-EMIT-ONE" in emit
    assert "UIDL-" not in emit_one
    assert "_UTUI-" not in emit_one

    current_siblings = (4, 2, 3)
    ordinal_by_index = {
        index: order for order, index in enumerate(current_siblings)
    }
    emitted = [
        (index, ordinal_by_index[index]) for index in sorted(current_siblings)
    ]
    assert emitted == [(2, 1), (3, 2), (4, 0)]


def test_current_text_is_copied_and_repacked_under_checked_bounds() -> None:
    source = _source()
    text = _word(source, "_UMSN-TEXT?")
    read = _word(source, "_UMSN-V-READ-TEXTS?")
    preflight = _word(source, "_UMSN-V-PREFLIGHT-WORK-TEXT?")
    disjoint = _word(source, "_UMSN-V-TEXT-SOURCES-DISJOINT?")
    copy = _word(source, "_UMSN-V-COPY-TEXT")
    visitor = _word(source, "_UMSN-TREE-VISITOR")
    emit_copy = _word(source, "_UMSN-E-COPY-TEXT")
    write = _word(source, "_UMSN-WRITE-RECORD")

    assert "UTF8-VALID?" in text
    assert "DUP 32 < SWAP 127 = OR" in text
    assert "S\" label\" UIDL-ATTR" in read
    assert "UIDL-TEXT@" in read
    assert "S\" key\" UIDL-ATTR" in read
    assert "_UMSN-V-LABEL-U @ 0> 0=" in read
    assert "_UMSN-UADD?" in preflight
    assert "_UMSN-WORK-TEXT-U @ U>" in preflight
    assert disjoint.count("MSPAN-OVERLAP?") == 2
    assert "_UMSN-V-NEXT-WORK-TEXT @ _UMSN-WORK-TEXT-USED @ -" in disjoint
    assert visitor.index("_UMSN-V-RESOLVED?") < visitor.index(
        "_UMSN-V-READ-TEXTS?"
    )
    assert visitor.index("_UMSN-V-PREFLIGHT-WORK-TEXT?") < visitor.index(
        "_UMSN-V-TEXT-SOURCES-DISJOINT?"
    )
    assert visitor.index("_UMSN-V-TEXT-SOURCES-DISJOINT?") < visitor.index(
        "_UMSN-V-COPY-TEXT"
    )
    assert copy.index("_UMSN-DIRTY-WORK-TEXT-U") < copy.index("CMOVE")
    assert "_UMSN-WORK-TEXT-A" in emit_copy
    assert write.index("_UMSN-E-COPY-TEXT") < write.index(
        "_UMSN-RECORD-MAGIC"
    )

    assert _semantic_tag_count("akashic/tui/applets/pad/pad.uidl") == 49
    assert _semantic_tag_count("akashic/tui/applets/daybook/daybook.uidl") == 22
    pad = (ROOT / "akashic/tui/applets/pad/pad.uidl").read_text(
        encoding="utf-8"
    )
    assert pad.count("key=Ctrl+A") == 3


def test_local_visibility_and_effective_paintability_remain_distinct() -> None:
    source = _source()
    args = _word(source, "_UMSN-V-ARGS?")
    state = _word(source, "_UMSN-V-BUILD-STATE")
    parent_selected = _word(source, "_UMSN-V-MARK-PARENT-SELECTED")
    validate = _word(source, "_UMSN-E-STATE?")

    assert args.count("_UMSN-V-RESOLVED-U @ 0=") == 1
    assert "_UMSN-V-EFFECTIVE @ _UMSN-V-LOCAL @ 0= AND" in args
    assert "_UMSN-V-LOCAL @ IF UMSN-F-VISIBLE" in state
    assert "_UMSN-V-EFFECTIVE @ IF UMSN-F-PAINTABLE" in state
    assert "_UTUI-HAS-FOCUS?" not in source
    assert "UMSN-F-SELECTED OR SWAP _UMSN-W.STATE !" in parent_selected
    assert "UMSN-F-PAINTABLE AND" in validate
    assert "UMSN-F-VISIBLE AND 0= AND" in validate
